#!/bin/env ruby

require 'seapig-client'
require 'socket'

require './database.rb'


last_report = 0
report = false

EM.run {

	Database.connect()
	seapig_server = SeapigServer.new(ARGV[0], name: 'reporter-'+ARGV[1])
	status = seapig_server.master('worker-status-'+ARGV[1])
  status['ip'] = Socket.ip_address_list.reject {|i| i.ipv4_loopback? or i.ipv6? }.map(&:ip_address).join('&')

	EM.add_periodic_timer(1) {
		next if (not report) and (Time.new.to_f - last_report < 60)
		last_report = Time.new.to_f

		puts "%s - uploading status"%[Time.new.strftime('%Y-%m-%d %H:%M:%S')]

		resources = Database::Resource.all.to_a
		status['timestamp'] = last_report
		status['resources'] = resources.map { |resource|
			{
				id: resource.id,
				type: resource.description['type'],
				task_id: resource.task_id
			}
		}
		p status
		status.changed
		report = false
	}


	Thread.new {
		ActiveRecord::Base.connection_pool.with_connection { |connection|
			connection = connection.instance_variable_get(:@connection)
			connection.exec("LISTEN resources_change")
			loop {
				connection.wait_for_notify { |channel, pid, payload|
					report = true
				}
			}
		}
	}

}
