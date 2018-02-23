#!/bin/env ruby
require 'optparse'
require 'typhoeus'

require_relative './project/config.rb'
require_relative './database.rb'
require_relative './task.rb'

options = {}

OptionParser.new do |opts|
	opts.banner = "Usage: bundle exec ruby cleaner-oneshot.rb [options]"
	opts.on("-s n","--status=n","List of statuses to clean, example: assigned") { |e|
		options["status"] = e
	}
	opts.on("-t n","--taskid=n","List of task ids, example: 2030,2031") { |e|
		options["task_ids"] = e
	}
	opts.on("-r n","--result=n","Desired result on tasks, example: cleaned") { |e|
		options["result"] = e
	}
	opts.on("-w n","--sweep=n","Clean all what is not cleaned, example: true") { |e|
		options["sweep"] = e
	}
	opts.on("-k n","--kill=n","Attempt to kill task_pid, example: true") { |e|
		options["kill"] = e
	}
end.parse!


raise "Insufficent arguments. Worker name is mandatory." if not WORKER_NAME

Database.connect()

tasks_to_clean = if !options["task_ids"].blank?
	options["task_ids"].split(',').map { |task_id|
		Task.find(Integer(task_id))
	}
elsif options["sweep"] == "true"
	Task.where(cleaned_at: nil)
elsif !options["statuses"].blank?
	Task.where(status: options["status"])
else
	raise "Insufficent arguments. One of following is needed: task_ids, sweep, statuses"
end


tasks_to_clean.each { |task|
	task.clean(options["kill"] == "true")
	task.update_status(status: (options["result"] or "crashed"))
}
