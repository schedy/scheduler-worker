require 'active_record'
require 'rest_client'
require 'awesome_print'
require_relative './database.rb'

class StatisticsArchive < ActiveRecord::Base
  self.table_name = "statistics_archive"
end

class Statistics < ActiveRecord::Base

  def self.connect
    ActiveRecord::Base.establish_connection(DATABASE)
  end

  def self.disconnect
    ActiveRecord::Base.connection.disconnect!()
  end

  def self.measure(action=[])
    self.transaction {
      puts 'Measuring: '+action.to_s
      start_time = Time.now
      yield
      end_time = Time.now
      duration = (end_time-start_time)
      StatisticsArchive.create!(action: action, duration: duration)
      query =
        "WITH upsert AS (UPDATE statistics SET occurence=occurence+1, average_duration = (occurence*average_duration + #{duration}) / (occurence+1) WHERE action @> ARRAY['#{action}'] RETURNING *)
       INSERT INTO statistics (action, average_duration, occurence,created_at,updated_at )
         SELECT ARRAY['#{action}'], #{duration},1,now(),now() WHERE NOT EXISTS (SELECT * FROM upsert)"
      ActiveRecord::Base.connection.execute(query)
    }
  end

  def self.aggregate
    self.transaction {
      query = "WITH upsert AS (UPDATE statistics SET average_duration = sub.average_duration, occurence = sub.occurence FROM (SELECT action,AVG(duration) as average_duration,COUNT(*) as occurence FROM statistics_archive GROUP BY action) AS sub WHERE statistics.action @> sub.action RETURNING *) INSERT INTO statistics (action,average_duration,occurence,created_at,updated_at) SELECT sa.action,sa.duration,1,now(),now() FROM statistics_archive sa WHERE NOT EXISTS (SELECT * FROM upsert)"
      ActiveRecord::Base.connection.execute(query)
    }
  end

end


# def self.average(action)
#   query = "SELECT average_duration FROM statistics WHERE action @> ARRAY['#{action}']"
#   ActiveRecord::Base.connection.execute(query).first["average_duration"].to_i
# end
