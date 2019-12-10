#!/bin/env ruby

$stdout.sync = 1

require 'typhoeus'
require 'mime-types'
require 'fileutils'
require 'json'

require './project/config.rb'

require './database.rb'
require './task.rb'
require './resource.rb'
require './statistics.rb'


step = JSON.load(open(ARGV[3]).read)
Dir.chdir(ARGV[1])
Database.connect

transition_started_at = Time.new

Resource::RESOURCE_TYPES[step["resource"]["description"]["type"]].transition(step["resource"],step["required"],step["steps"],{"stepfile": ARGV[3]})

Statistics.record([step["required"]["type"],step["required"]["role"],step["resource"]["id"]], Time.new - transition_started_at)

exit 0
