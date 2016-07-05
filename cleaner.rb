#!/bin/env ruby
# coding: utf-8

require 'fileutils'
require 'json'
require 'daemons'
require 'seapig-client'
require 'optparse'
require './manager.rb'
require './database.rb'
require 'active_support/core_ext/hash'

$SCHEDULER_URI = ''
$TASKDIR = Dir.pwd.to_s+"/tasks/"
statuses = ['waiting','preparing','transitioning','starting','finished','crashed','cancelled','timeout']
threads = []
OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby cleaner.rb [options]"
  opts.on("-s n","--scheduler_uri=n","Scheduler URI, example: http://scheduler-server") { |e|
    $SCHEDULER_URI = e
  }
  opts.on("-w n","--worker_name=n","Worker Name, example: ts001") { |e|
    $WORKER_NAME = e
  }
end.parse!

def uploadFiles(task_id)
  dir_files = Dir.glob($TASKDIR+task_id.to_s+"/*").select { |f| File.file?(f) }.map { |e| e.prepend('/') }
  dir_files.each { |f_name|
    RestClient.post($SCHEDULER_URI+'/artifacts', task: task_id, data: File.new(f_name))
  }
end

def dispatchRequest(endpoint,task_id,options)
  if endpoint.include?('values')
    options.each { |k,v|
      RestClient.post($SCHEDULER_URI+endpoint,task_id: task_id, property: k, value: v)
    }
  elsif endpoint.include?('status')
    RestClient.post($SCHEDULER_URI+endpoint,task_id: task_id, status: options["status"])
  end
end

EM.run {
  Database.connect()
  EM.add_periodic_timer(60) {
    puts 'Timeout cleaner triggered.'
    Database::Task.where('pid IS NOT NULL AND cleaned_at IS NULL').map { |task|
      task_id = task.id
      if File.file?($TASKDIR+task_id.to_s+"/task.json")
        task_json = File.open($TASKDIR+task_id.to_s+"/task.json") { |f| JSON.parse(f.read) }
        timeout = if task_json["timeout"].to_i > 0 then task_json["timeout"] else 30*60 end
      end
      if (Time.now - task.updated_at > timeout )
        #Task timed out.
        puts "This task timed out: "+task.id.to_s
        Process.kill('QUIT', task.pid.to_i)
      end
    }
  }

  EM.add_periodic_timer(60) { threads.each { |thr| thr.join } }

  EM.add_periodic_timer(3){
    puts 'Cleaner triggered.'
    #### Periodicly check if process is alive.
    Database::Task.where('pid IS NOT NULL AND cleaned_at IS NULL').map { |task|
      task_id = task.id.to_s
      task_pid = task.pid.to_s
      begin
        puts "Checking "+task_id
        ###Process is alive.
        pid = Process.getpgid(task_pid.to_i)
      rescue Errno::ESRCH
        ###Process is dead.
        puts "This task's process looks dead: "+task_id
        ##Check if process left finished file in its dir.
        ##This file is subject to change, and MUST change.
        task_report_html = $TASKDIR+task_id+"/report.html"
        task_report = $TASKDIR+task_id+"/output.xml"
        if File.file?(task_report_html)
          task_output_xml = File.read(task_report)
          puts "Freeing resources bind to: "+task_id
          #Free its resources.
          Database::Resource.release(task_id)
          puts "Uploading results: "+task_id
          # TODO: SOMETHING WRONG IN PARSED NAME. IF TEST IS NOT SUCCESSFUL , THAT OBJECT DOES NOT EXIST.
          parsed_result = Hash.from_xml(task_output_xml)["robot"]["suite"]["status"]["status"]
          parsed_name = Hash.from_xml(task_output_xml)["robot"]["suite"]["suite"]["test"]["name"]
          parsed_status = Hash.from_xml(task_output_xml)["robot"]["suite"]["suite"]["test"]["status"]
          robot_test_result = File.open($TASKDIR+task_id.to_s+"/test_result", "w+") { |file| file.write(parsed_result == "PASS" ? "100" : "0" )}
          #Upload files in task folder
          threads << Thread.new { uploadFiles(task_id) }
          puts "Result is: "+parsed_result.to_s
          dispatchRequest('/task_values',task_id,{"result"=>parsed_result,"name"=>parsed_name})
          if parsed_result == "FAIL"
            dispatchRequest('/task_values',task_id,{"reason"=>parsed_status})
          end
          #Inform server that task has finished.
          puts "Setting it to finished: "+task_id
          dispatchRequest('/task_statuses',task_id,{"status"=>"finished"})
        #If process did not leave a finished file.
        else
          #Inform server that task has FAILED after transition is done.
          if statuses.index(task.status.to_s).to_i > 2
            puts "This task has failed: "+task_id
            Database::Resource.release(task_id)
            dispatchRequest('/task_statuses',task_id,{"status"=>"failed"})
            #Upload files in task folder
            Thread.new { uploadFiles(task_id) }
            if (File.file?($TASKDIR+task_id.to_s+"/test_result"))
              parsed_result = if File.read($TASKDIR+task_id+"/test_result").to_i > 50 then "PASS" else "FAIL" end
              dispatchRequest('/task_values',task_id,{"result"=>parsed_result})
              dispatchRequest('/task_statuses',task_id,{"status"=>"finished"})
            end
          else
            #Inform server that task has CRASHED before or during tranisiton.
            if (File.file?($TASKDIR+task_id.to_s+"/failed") or File.file?($TASKDIR+task_id.to_s+"/task.json"))
              #Inform server that transition has failed to fetch packages or something like that.
              puts "This task has failed: "+task_id
              Database::Resource.release(task_id)
              RestClient.post($SCHEDULER_URI+'/task_statuses', task_id: task_id, status: "failed")
              #Upload files in task folder
              threads << Thread.new { uploadFiles(task_id) }
                if (File.file?($TASKDIR+task_id.to_s+"/test_result"))
                  parsed_result = if File.read($TASKDIR+task_id+"/test_result").to_i > 50 then "PASS" else "FAIL" end
                  dispatchRequest('/task_values',task_id,{"result"=>parsed_result})
                  dispatchRequest('/task_statuses',task_id,{"status"=>"finished"})
                end
            else
              puts "This task has crashed: "+task_id
              RestClient.post($SCHEDULER_URI+'/task_statuses', task_id: task_id, status: "crashed")
            end
          end
        end
        begin
          puts "Marking task as cleaned: "+task_id
          Process.kill('QUIT', task_pid.to_i)
          puts 'Child of executor is killed.'
        rescue Errno::ESRCH
          puts 'Fool, you cannot kill what does not bleed !'
        end
        task.update(cleaned_at: Time.now())
      else
        puts "Task ID :"+task_id+" is alive with pid "+task_pid.to_s
      end
    }

  }

}
