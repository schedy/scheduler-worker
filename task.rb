require 'fiddle'

require_relative './resource.rb'


module Ethon
	class Easy
		module Queryable
			def mime_type(filename)
				if defined?(MIME) && t = MIME::Types.type_for(filename).first
					t.to_s
				else
					'text/plain'
				end
			end
		end
	end
end


class Task < ActiveRecord::Base


	def run(task_description, code_directory)
		child_pid = Process.pid
		# INFO: Update task pid.
		self.update(pid: child_pid)

		transition_started_at = Time.new

		transition_result = Resource.transition(task_description["plan"]["steps"],false)

		if transition_result != 0
			clean(false)
			self.update_status(status: (transition_result == 2 ? "failed" : "crashed"))
			puts 'Transition crashed !'
			exit 1
		end

		# INFO: Update local status to started, set release time and inform server
		self.update_status(status: "started")
		# INFO: Now I try some magic.. https://cr.yp.to/docs/selfpipe.html
		# Create a pipe to self and trap CHLD from finished or ALRM from timeout signals, write to pipe if those traps are triggered.
		# That will break beauty sleep of wakeup_reader and trigger a cleanup, either with status finished or timeout.

		reason = nil
		wakeup_reader, wakeup_writer = IO.pipe
		trap("CHLD") { wakeup_writer.write(1) }
		trap("ALRM") { wakeup_writer.write(1) }

		# INFO: If executor is available, grab it from SCHEDULER_WORKER_ROOT/project/executors/<executor> and execute.
		#task_description["executor"] = [task_description["executor"]] if not task_description["executor"].kind_of? Array #FIXME: remove after interpreter update
		execute_order = [code_directory+"/project/executors/#{task_description["executor"][0]}"].join(' ')
		executor_started_at = Time.new
		executor_pid = Bundler.with_clean_env {
			spawn(execute_order,*task_description['executor'][1..-1], pgroup: true, chdir: ARGV[1])
		}
		if executor_pid then
			puts [execute_order,'started.'].join(' ')
		else
			puts "Spawn went wrong !"
		end
		executor_pgid = Process.getpgid(executor_pid)
		self.update(executor_pid: executor_pid, executor_pgid: executor_pgid)

		timeout_duration = (task_description["timeout"] or 24*60*60).to_i
		Fiddle::Function.new(Fiddle.dlopen("libc.so.6")['alarm'],[-Fiddle::TYPE_INT],-Fiddle::TYPE_INT).call(timeout_duration)
		wakeup_reader.read(1)
		clean(true)
		executor_pid,executor_status = Process.wait2
		if executor_status.exitstatus.to_s == "0"
			Statistics.record([task_description["test_name"],task_description["test_environment"]], Time.new - executor_started_at)
			result='finished'
		elsif executor_status.exitstatus.nil?
			result='timeout'
		else
			result='failed'
		end
		update_status(status: result)
	end


	def clean(kill)
		kill_executor if (executor_pgid != nil) && (executor_pgid != 0) && kill
		Resource.release(id.to_s) if self.status != 'crashed' and self.status != 'transitioning'
		self.update(cleaned_at: Time.now())
		post_artifacts
	end


	def kill_executor
		raise 'you cannot kill nil process !'if executor_pgid == nil
		Process.kill('SIGKILL',-executor_pgid) rescue Errno::ESRCH
		puts ["Task ID :",id,"is with pgid",executor_pgid,'is killed !'].join(' ')
	end


	def post_artifacts
		target_uri = [SCHEDULER_URI,'tasks',id,'artifacts'].join('/')
		artifacts = Dir.glob(directory+"/*").select { |f| File.file?(f) && File.stat(f).readable? }.map{ |e| e.prepend('/') }
		artifacts.each { |artifact|
			request = Typhoeus::Request.new(target_uri,method: :post,body: {task: id.to_s, data: File.open(artifact,"r")})
			request.on_complete do |response|
				p ['Filename:',File.basename(artifact),"- Response Code:",response.options[:response_code],"- Response Time:",response.options[:total_time]].join(' ')
			end
			request.run
		}
	end


	def update_status(options)
		self.update(status: options[:status])
		Task.update_status(options.merge(task_id: id))
	end


	def self.update_status(options = {})
		print "Uploading task status: "+options.inspect+".. "

		body = { status: options[:status], worker: WORKER_NAME }
		raise "Invalid options: "+options.inspect if (not options[:task_id]) and not (options[:having_status])
		request = if options[:having_status]
			Typhoeus::Request.new(SCHEDULER_URI+"/workers/"+WORKER_NAME+"/tasks/"+options[:having_status]+"/status", method: :post, body: body)
		else
			Typhoeus::Request.new(SCHEDULER_URI+"/tasks/"+options[:task_id].to_s+"/status", method: :post, body: body)
		end

		request.on_complete do |response|
			if response.success?
				puts "OK"
				return JSON.parse(response.body)["tasks"]
			elsif response.timed_out?
				puts "Request timed out !"
				return false
			elsif response.code == 423
				puts "Task already locked or invalid status transition!"
				return false
			else
				puts "HTTP request failed: " + response.code.to_s
				p SCHEDULER_URI+"/task_statuses"
				p response.return_message
				p response.body
				return false
			end
		end

		request.run
	end

end
