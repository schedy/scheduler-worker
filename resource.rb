require_relative 'database.rb'
require 'graphmatcher'

module Enumerable
	def independent
		temp = self.clone
		all_resources = self.map { |el| el.transpose[0] }.flatten.uniq
		self.each { |val|
			(all_resources & val.transpose[0]).length == val.transpose[0].length ? (all_resources -= val.transpose[0]) : (temp.delete(val))
		}
		temp
	end
end

class Resource < ActiveRecord::Base


	def self.exclusive?
		true
	end

	def self.nodes(description)
		[description]+(description["children"] or []).map { |child| nodes(child) }.flatten
	end

	def self.estimate_costs(available_resources,task_requirements)
		costs = {}
		available_resources.each_with_index { |resource,resource_index|
			costs[resource_index] = {}
			task_requirements.each_with_index { |requirement,requirement_index|
				if (resource[:description]["type"] != requirement["type"] ) or (not RESOURCE_TYPES[resource[:description]["type"]]) or not res = RESOURCE_TYPES[resource[:description]["type"]].estimate(resource, requirement)
					costs[resource_index][requirement_index] = 360000
				else
					costs[resource_index][requirement_index] = res[:transition_duration]
				end
			}
		}

		costs
	end

	#unsuitable method name.
	def self.free(estimated_release_time:, exclusive_ids: nil)

		shared_resource_types = RESOURCE_TYPES.to_a.select { |klass_name, klass| not klass.exclusive? }.map { |klass_name, klass| klass_name }
		resources = Resource.where("task_id IS NULL OR estimated_release_time <= #{estimated_release_time} OR description ->> 'type' IN (?)", shared_resource_types)

		if not ids.nil?
			resources = resources.where("id IN (?)",ids)
		end

		resources.map { |resource|
			{
				id: resource.id,
				description: resource.description,
				children_ids: resource.children_ids,
				estimated_release_time: resource.estimated_release_time
			}
		}
	end



	def self.lock(task_id, actors)
		ids = actors.values.map { |actor| self.nodes(actor) }.flatten.map { |description| description[:id] }
		self.transaction {
			if already_locked = (resources = Resource.where(id: ids).lock("FOR UPDATE")).find { |resource| resource.task_id }
				puts "Locking failed."
				return false
			end
			resources.update_all(task_id: task_id)
		}
		connection.exec_query("NOTIFY resources_change")
		outgoing = {
			WORKER_NAME => actors.map { |role, actor| actor.merge(task_id: task_id, role: role, created_at: Time.now.iso8601(3)) }
		}
		RestClient.post(SCHEDULER_URI+'/resources/statuses',{statuses: outgoing, assign: true})
		true
	end


	def self.release(task_id)
		resources = Resource.where(task_id: task_id)
		resources_json = resources.as_json
		resources.update_all(task_id: nil, estimated_release_time: nil)
		if resources.size > 0
			outgoing = {
				WORKER_NAME => resources_json.map { |resource| resource.merge("task_id"=>nil, "role"=>nil, "created_at"=>Time.now.iso8601(3)) }
			}
			RestClient.post(SCHEDULER_URI+'/resources/statuses', { statuses: outgoing, assign: false })
			connection.exec_query("NOTIFY resources_change")
		end
	end


	def self.estimate(data_graph, query_graph)

		available_resources = data_graph
		task_requirements = query_graph
		costs = Resource.estimate_costs(available_resources, task_requirements)

		graph = if not available_resources.empty?
					available_resources.map { |res|
						[
							res[:children_ids].map {|ci| available_resources.index{ |t| t[:id] == ci.to_i } }.compact,
							[res[:description]["type"]]
						]
					}.transpose
				else
					[ [],[] ]
				end


		query = task_requirements.map { |req| [req["children"],[req["type"]],[req["role"]]]}.transpose

		@graphmatcher = Graphmatcher.new(
			{
				:data_graph => graph,
				:query_graph => query,
				:limit => 100,
				:max_allowed_time => 4.0,
				:cost_matrix => costs
			}
		)

		plans = @graphmatcher.find_matches.select { |plan| plan.inject(0) { |max, (node,cost)| [max, cost].max } < 360000 }

		return nil if plans.empty?

		sorted_plans = plans.sort_by { |plan| plan.inject(0) { |max, (node,cost)| [max, cost].max }}.independent[0..9].shuffle

		plan = sorted_plans[0]

		roles = task_requirements.map { |req| req["role"] }
		planned_resources = plan.transpose.first.map { |index| available_resources[index] }
		total_cost = plan.inject(0) { |max, (node,cost)| [max, cost].max }
		actors = [roles,planned_resources].transpose.reduce({}) { |hash,(k,v)| hash[k] = v;hash}
		steps = actors.map { |k,v| {resource: v  , required: task_requirements.find { |e| e["role"]==k } , steps: [] } }


		plan = {
			:transition_duration => total_cost,
			:actors => actors,
			:steps => steps,
			:alternatives => sorted_plans.map { |plan| plan.transpose[0].select { |index| RESOURCE_TYPES[available_resources[index][:description]["type"]].exclusive? }.map { |index| available_resources[index][:id] }
			}
		}




	end


	def self.transition(steps, spawned=true)
		puts "Transition begins."

		steps.flatten.each_with_index { |step, i|
			step_file = [(spawned ? ARGV[3] : ARGV[1]+"schedy-transition"), i.to_s].compact.join('-')

			open(step_file,"w") { |f| f.write(JSON.dump(step)) }
			child_pid = spawn("./schedy-transition.rb", ARGV[0], ARGV[1], step["resource"]["id"].to_s, step_file, [:out, :err]=>[step_file+".output","w"])
		}

		ret = if steps.size > 0
				  child_responses = Process.waitall
				  child_responses.map { |e| e[1].exitstatus }.max
			  else
				  0
			  end

		exit ret if spawned
		return ret
	end

	Dir['./project/resources/*.rb'].each { |file| require file }
	RESOURCE_TYPES = Hash[*ObjectSpace.each_object(Class).select { |klass| klass < Resource }.map { |klass| [klass.name.to_s, klass] }.flatten]

end
