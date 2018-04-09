require 'active_record'
require 'rest_client'
require_relative './project/config.rb'

# create database scheduler_worker;
# create table resources (id serial primary key, task_id bigint, created_at timestamp, updated_at timestamp, description jsonb);
# create table tasks (id bigint primary key, created_at timestamp, updated_at timestamp, status text, pid text, cleaned_at timestamp);
# create table artifacts (id bigint primary key, task_id bigint, actor_id bigint, created_at timestamp, updated_at timestamp, results text, logs text);

module Database

	def self.connect
		raise "Can't connect to database." if not ActiveRecord::Base.establish_connection(DATABASE)
	end

end
