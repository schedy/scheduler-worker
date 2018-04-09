#!/bin/env ruby

$stdout.sync = 1

code_directory = Dir.pwd
require 'daemons'
Daemons.daemonize(app_name: 'schedy-task', log_output: true, dir: ARGV[1], dir_mode: :normal, log_dir: ARGV[1])
$0 = 'schedy-task '+ARGV.join(" ")
Dir.chdir(code_directory)

require 'typhoeus'
require 'mime-types'
require 'fileutils'
require 'json'

require './project/config.rb'

require './database.rb'
require './task.rb'
require './resource.rb'
require './statistics.rb'

task_description = JSON.load(open(ARGV[1]+"/task.json").read)

Database.connect
task = Task.find(ARGV[0])
task.run(task_description, code_directory)
