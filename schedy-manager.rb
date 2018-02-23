#!/bin/env ruby

require 'typhoeus'
require 'mime-types'
require 'fileutils'
require 'json'
require 'daemons'
require 'seapig-client'
require 'awesome_print'
require './project/config.rb'

require './database.rb'
require './task.rb'
require './resource.rb'
require './statistics.rb'

$stdout.sync = 1

if Database.connect() then puts 'Successfully connected to database' end


# cleaning tasks that got accepted by previous session but didn't manage to fork
Task.update_status(having_status: "accepted", status: "waiting").each { |task_id|
	next if not task = Task.where(id: task_id).first
	task.destroy!
}


EM.run {

	seapig_client = SeapigClient.new(SEAPIG_URI, name: "manager-"+WORKER_NAME, debug: true)
	assignments = seapig_client.slave('assignments:'+WORKER_NAME)
	tasks_to_estimate = seapig_client.slave('tasks-to-estimate')

	estimates = seapig_client.master('estimates:'+WORKER_NAME, object: { "generated_for" => {"Postgres::Task:waiting" => 0 }, "estimates" => {} })

	reestimate_queued_for = []
	reestimate_queued_mutex = Mutex.new
	assignment_queued = false
	assignments_last_processed_version = 0
	reestimate_delayed = false

	reestimate = Proc.new {
		t0 = Time.new

		reestimate_queued_mutex.synchronize {
			puts "Re-estimating because: "+reestimate_queued_for.join(",")
			reestimate_queued_for = []
		}
		reestimate_delayed = false

		next if (not tasks_to_estimate.valid)
		if (not assignments.valid) or (not assignments_last_processed_version) or (assignments_last_processed_version != assignments.version["Postgres::Task:assigned:"+WORKER_NAME])
			puts "Delaying reestimation, need to process assignments first"
			reestimate_delayed = true
			next
		end

		current_time = Time.new.to_i

		next_release_time = Resource.find_by_sql("SELECT MIN(estimated_release_time) AS ert FROM resources WHERE estimated_release_time IS NOT NULL").first.try(:ert)

		estimates["estimates"] = {}

		[current_time,next_release_time].compact.each { |observation_time|
			available_resources = (observation_time != current_time) ? Resource.free(estimated_release_time: observation_time.to_i) : Resource.free(estimated_release_time: "NULL")

			tasks_to_estimate.each { |req_id,req_obj|

				estimated_plan = Resource.estimate(available_resources, req_obj["requirements"])

				req_obj["tasks"].each { |task_id,task|

					if estimated_plan
						execution_duration = Statistics.query_average(task["duration-key"],60)

						plan_key = if observation_time != current_time then observation_time else "now" end
						estimates["estimates"][task_id.to_s] ||= {}
						estimates["estimates"][task_id.to_s][plan_key] = [
							estimated_plan[:transition_duration],
							estimated_plan[:alternatives],
							execution_duration
						]
					end
				}
			}
		}

		estimates["generated_for"]["Postgres::Task:assigned:"+WORKER_NAME] = assignments_last_processed_version
		puts "Estimation duration: %.6f    %i"%[Time.new - t0, tasks_to_estimate.size]
		estimates.bump()
	}


	assignment = Proc.new {
		assignment_queued = false
		assignments_last_processed_version = assignments.version["Postgres::Task:assigned:"+WORKER_NAME]
		reestimate_queued_mutex.synchronize { EM.next_tick(&reestimate) if (reestimate_queued_for << "resuming-delayed-reestimation").size == 1 } if reestimate_delayed

		puts "Got new assignments "+assignments["tasks"].map { |task| task["id"] }.inspect #+" "+assignments.version.inspect

		assignments["tasks"].each { |task_description|

			task_id = task_description["id"].to_s
			#puts assignments

			# INFO: Start an assignment procedure, if it is not assigned by anyone else yet.
			puts "\tprocessing task#"+ task_id
			next if !Task.where(id: task_id).blank?
			puts "\t\taccepting"

			next if not Task.update_status(task_id: task_id, status: "accepted")

			puts "\t\taccepted"

			#INFO: Create Task in local db, with status 'pre-fork' or something
			new_task = Task.create!(id: task_id, status: "accepted")

			#INFO: Perform estimate
			plan = Resource.estimate(Resource.free(estimated_release_time: 'NULL',ids: task_description["resources"]), task_description['requirements'])

			if plan == nil
				new_task.destroy!
				Task.update_status(task_id: task_id, status: "waiting")
				puts "Task ID: %8s - Received an empty plan. @ %s"%[task_id,Time.now]
			else

				transition_duration = plan[:transition_duration]

				execution_duration = Statistics.query_average([task_description["test_name"],task_description["test_environment"]],60)

				estimated_release_time = transition_duration + execution_duration + Time.now.to_i

				if not lock_response=Resource.lock(task_id,plan[:actors])
					new_task.destroy!
					Task.update_status(task_id: task_id, status: "waiting")
					puts "Task ID: %8s - Resource lock failed. @ %s - %s"%[task_id,Time.now,lock_response]
					next
				end

				Resource.where(task_id: task_id).update_all(estimated_release_time: estimated_release_time )
				new_task.directory = [Dir.pwd,"storage","tasks",task_id].join('/')+"/"

				FileUtils::mkdir_p(new_task.directory)

				new_task.update_status(status: "transition")


				File.open(new_task.directory + "/task.json","w") { |file|
					file.write(task_description.merge(actors: plan[:actors], plan: plan).to_json)
				}

				child_pid = spawn("./schedy-task.rb", task_id, new_task.directory, pgroup: true)
				Process.detach(child_pid)
			end

		}
	}

	Thread.new {
		ActiveRecord::Base.connection_pool.with_connection { |connection|
			connection = connection.instance_variable_get(:@connection)
			connection.exec("LISTEN resources_change")
			connection.exec("LISTEN statistics_changed")
			loop {
				connection.wait_for_notify { |channel, pid, payload|
					case channel
					when 'resources_change', 'resources_changed'
						reestimate_queued_mutex.synchronize { EM.next_tick(&reestimate) if (reestimate_queued_for << "resource-state-changed").size == 1 }
					when 'statistics_changed'
						EM.next_tick { Statistics.reload_cache }
					end
				}
			}
		}
	}

	EM.add_periodic_timer(3600) { Statistics.reload_cache }

	tasks_to_estimate.onstatuschange {
		next if not tasks_to_estimate.valid
		puts "Got new tasks-to-estimate: "+tasks_to_estimate.version.inspect
		reestimate_queued_mutex.synchronize { EM.next_tick(&reestimate) if (reestimate_queued_for << "new-tasks-to-estimate-received").size == 1 }
	}


	assignments.onstatuschange  {
		next if not assignments.valid
		assignment_queued = !EM.next_tick(&assignment) if not assignment_queued
	}

}
