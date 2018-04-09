require 'active_record'
require_relative './database.rb'

class Statistics < ActiveRecord::Base

	@@cache = nil

	def self.reload_cache
		@@cache = {}

		Statistics.all.to_a.map(&:serializable_hash).each { |action_statistic|
			@@cache[action_statistic["action"]] = action_statistic["average_duration"]
		}
	end


	def self.measure(action=[])
		#puts 'Measuring: '+action.to_s+query.to_s
		start_time = Time.now
		yield
		end_time = Time.now
		duration = (end_time-start_time)
		self.record(action, duration)
	end


	def self.record(action, duration)
		action = action.map { |a| a.to_s } 
		quoted_action = action.map { |element| ActiveRecord::Base.connection.quote(element) }.join(',')
		query = "WITH upsert AS (
		                UPDATE statistics SET occurence=occurence+1, average_duration = (occurence*average_duration + #{duration}) / (occurence+1)
		                WHERE action @> ARRAY[#{quoted_action}] RETURNING *)
		         INSERT INTO statistics (action, average_duration, occurence,created_at,updated_at )
		         SELECT ARRAY[#{quoted_action}], #{duration},1,now(),now() WHERE NOT EXISTS (SELECT * FROM upsert)"

		ActiveRecord::Base.connection.execute(query)
		connection.instance_variable_get(:@connection).exec("NOTIFY statistics_changed")
	end


	def self.query_average(action=[],default_average)
		Statistics.reload_cache unless @@cache
		@@cache[action] or default_average
	end

end
