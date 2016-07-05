#!/bin/env ruby

require 'jsonclient'
require 'fileutils'
require 'json'
require 'daemons'
require 'seapig-client'

require './manager.rb'
require './database.rb'
require './statistics.rb'

$stdout.sync = 1

puts 'Executor online.'
OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby executor.rb [options]"
  opts.on("-p n","--seapig-server=n","Seapig Server, example: http://scheduler-server/seapig") { |e|
    $SEAPIG_SERVER = e
  }
  opts.on("-s n","--scheduler_uri=n","Scheduler URI, example: http://scheduler-server") { |e|
    $SCHEDULER_URI = e
  }
  opts.on("-w n","--worker_name=n","Worker Name, example: ts001") { |e|
    $WORKER_NAME = e
  }
end.parse!

EM.run {
	if Database.connect() then puts 'Successfully connected to database' end
	seapig_server = SeapigServer.new($SEAPIG_SERVER)
	scheduler_server = JSONClient.new

	assignments = seapig_server.slave('assignments:'+$WORKER_NAME)
	estimates = seapig_server.master('estimates:'+$WORKER_NAME)
	tasks_waiting = seapig_server.slave('tasks-waiting')
  $AVG_DURATIONS = if Statistics.all.to_a.map(&:serializable_hash).blank? then {} else  Statistics.all.to_a.map(&:serializable_hash) end
  reestimate = Proc.new {
    p 'Re-estimating..'
    resources = Database::Resource.free
    tasks_waiting['tasks'].each { |task|
      plan = Manager.estimate(resources, task['requirements'])

      # XXX: this one is using test name for determining average duration, but what happens for different packages ?
      execution_duration = if $AVG_DURATIONS.detect {|e| e["action"][0].to_s.include? task['test_name'] }.blank? then 60 else $AVG_DURATIONS.detect {|e| e["action"][0].include? task['test_name']}["average_duration"] end
      if plan
        actor_size = plan[:actors].size
        plan[:actors] = actor_size
        plan[:steps] = []
      plan[:execution_duration] = execution_duration
      estimates[task['id'].to_s] = plan
      puts '-'*80
      puts "Estimation for Task ID: %8i - Score: %6.2f - Ex.. Duration: %8i - Actor Count: %8i @ %s"%[task['id'],plan[:transition_duration],execution_duration,plan[:actors],Time.now]
    else
      estimates.delete(task['id'].to_s)
    end
  }
  estimates.changed
}

assignment = Proc.new {

  puts "Assignments object changed."
  assignments.each_pair { |task_id, task|
    next if not Database::Task.where(id: task_id).blank?
    scheduler_server.post($SCHEDULER_URI+'/task_statuses', task_id: task_id, status: "assigned")
    #create Task in local db, with status 'pre-fork' or something
    new_task = Database::Task.create!(id: task_id, status: "preparing")
    #perform estimate
    plan = Manager.estimate(Database::Resource.free, task['requirements'])
    #upload task status 'waiting' if plan can't be done , and "next"
    if plan == nil
      scheduler_server.post($SCHEDULER_URI+'/task_statuses', task_id: task_id, status: "waiting")
      new_task.destroy!
      puts "Task ID: %8s - Received an empty plan. @ %s"%[task_id,Time.now]

    else

      if not Database::Resource.lock(task_id,plan[:actors])
        scheduler_server.post($SCHEDULER_URI+'/task_statuses', task_id: task_id, status: "waiting")
        new_task.destroy!
        puts "Task ID: %8s - Received a lock conflict. @ %s"%[task_id,Time.now]
        next
      end

      task_directory = Dir.pwd.to_s+"/tasks/"+task_id.to_s
      dister_directory = Dir.pwd.to_s
      FileUtils::mkdir_p task_directory
      Database.disconnect()
      child_pid = fork do
        seapig_server.detach_fd
        EM.stop_event_loop
        EM.release_machine
        Daemons.daemonize(app_name: 'executor', log_output: true, log_dir: task_directory)
        child_pid = Process.pid
        Database.connect()
        Database::Task.find(task_id).update(pid: child_pid)
        Dir.chdir(task_directory)
        Database::Task.find(task_id).update(status: "transitioning")
        scheduler_server.post($SCHEDULER_URI+'/task_statuses', task_id: task_id, status: "transition")
        transition = Manager.transition(plan[:steps])
        Database::Task.find(task_id).update(status: "started")
        scheduler_server.post($SCHEDULER_URI+'/task_statuses', task_id: task_id, status: "started")
        File.open("task.json","w") do |f|
          f.write(task.merge(actors: plan[:actors]).to_json)
        end
        if not task["executor"].nil?
          execute_order = [dister_directory+"/project/executors/"+task['executor'].to_s].join(' ')
          p 'Execution order received.'+execute_order
          exec execute_order
          p "Well done."
        else
          p "Could not find an executor."
        end
      end
      Process.detach(child_pid)
      Database.connect()
    end

  }
}

Thread.new {
  ActiveRecord::Base.connection_pool.with_connection { |connection|
    connection = connection.instance_variable_get(:@connection)
    connection.exec("LISTEN resources_change")
    loop {
      connection.wait_for_notify { |channel, pid, payload|
        EM.schedule reestimate
      }
    }
  }
}

tasks_waiting.onchange(&reestimate)
assignments.onchange(&assignment)


}
