require 'active_record'
require 'rest_client'
require 'awesome_print'
require_relative './project/config.rb'

# create database scheduler_worker;
# create table resources (id serial primary key, task_id bigint, created_at timestamp, updated_at timestamp, description jsonb);
# create table tasks (id bigint primary key, created_at timestamp, updated_at timestamp, status text, pid text, cleaned_at timestamp);
# create table artifacts (id bigint primary key, task_id bigint, actor_id bigint, created_at timestamp, updated_at timestamp, results text, logs text);

module Database

  def self.connect
    ActiveRecord::Base.establish_connection(DATABASE)
  end

  def self.disconnect
    ActiveRecord::Base.connection.disconnect!()
  end

  class Resource < ActiveRecord::Base

    def self.free
      self.transaction {
        Resource.where('task_id IS NULL').map { |resource|
          resource.description. merge(id: resource.id)
        }
      }
    end

    # def self.free_children(parent_name)
    #   self.transaction {
    #     Resource.where('task_id IS NULL AND parent_type IS '+parent_name.to_s+' GROUP BY parent_id').map { |resource|
    #       resource.description.merge(id: resource.id)
    #     }

    #   }
    # end

    def self.release(task_id)
      resources = Resource.where(task_id: task_id)
      resources_json = resources.as_json
      resources.update_all(task_id: nil)
      outgoing = {$WORKER_NAME => Hash[*resources_json.map {|p| [p["id"],p["description"].merge(task_id: nil)]}.flatten ]}
      RestClient.post(SCHEDULER_URI+'/resource_statuses',{statuses: outgoing, assign: false})
      connection.instance_variable_get(:@connection).exec("NOTIFY resources_change")
      true
    rescue
      false
    end

    def self.lock(task_id,actors)
      self.transaction {
        actors.values.map { |actor|
          target_resource = Resource.find(actor[:id])
          if target_resource.task_id == nil
            target_resource.update(task_id: task_id)
          else
            p 'Resource is already locked !'
            raise
          end
        }
        outgoing = {$WORKER_NAME => Hash[*actors.map { |k,v| [v[:id],v.merge(task_id: task_id).slice!(:id)] }.flatten]}
        RestClient.post(SCHEDULER_URI+'/resource_statuses',{statuses: outgoing, assign: true})
      }
      connection.instance_variable_get(:@connection).exec("NOTIFY resources_change")
      true
    rescue
      false
    end

    def self.duration(task_name,package)
      self.transaction {
        Resource.find_by_sql("
        SELECT t.description::json ->>'test_name' AS test_name, AVG(EXTRACT(EPOCH FROM (ts2.created_at - ts1.created_at))) AS duration
          FROM task_statuses ts1, task_statuses ts2, tasks t
            WHERE ts2.task_id = t.id AND ts1.task_id = t.id AND ts1.task_id = ts2.task_id AND ts1.status = 'started' AND ts2.status = 'finished'
            AND ts2.current = true AND t.description::json->>'test_name' = '?' AND t.description::json->>'package' = '?' GROUP BY test_name;",task_name)
      }
    end

  end


  class Task < ActiveRecord::Base

  end


end
