require 'pg'
require 'active_record'
require 'yaml'

namespace :build do

	desc "Build scheduler worker tarball"
	task :tarball do
		sh 'unset RUBYOPT; bundle package --all'
		FileUtils.mkdir_p 'docker/build'
		FileUtils.rm 'docker/scheduler-worker.tar.bz2' if File.exists?('docker/scheduler-worker.tar.bz2')
		Dir.chdir 'docker/build'
		['statistics.rb','reporter.rb', 'Rakefile', 'Gemfile', 'Gemfile.lock', 'LICENSE', 'cleaner.rb', 'database.rb', 'executor.rb','manager.rb', 'vendor', 'db', 'config'].each { |dir|
			FileUtils.cp_r '../../'+dir, '.'
		}
		puts `tar -jcvf ../scheduler-worker.tar.bz2 *`
		Dir.chdir '..'
		FileUtils.rm_r 'build'
		Dir.chdir '..'
	end


	desc "Build scheduler worker docker image"
	task docker: "tarball" do
		Dir.chdir 'docker'
		sh 'sudo docker build .'
		puts
		puts '***** Read docker/Dockerfile to find out how to start your newly created image *****'
		puts
	end


	
end


namespace :db do

	task :db_connect do
		require './config/database.rb'
		ActiveRecord::Base.establish_connection(DATABASE)
	end
	
	desc "Migrate the db"
	task :migrate => [:db_connect] do
		#ActiveRecord::Base.select_by_sql("select count(*) from information_schema.tables where table_schema = 'public'")
		ActiveRecord::Migrator.migrate("db/migrate")
	end
	
	namespace :schema do
		desc 'Creates a db/schema.rb file that is portable against any DB supported by Active Record'
		task :dump => [:db_connect] do
			require 'active_record/schema_dumper'
			File.open('db/schema.rb', "w:utf-8") { |file|
				ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, file)
			}
		end

		desc 'Loads a schema.rb file into the database'
		task :load => [:db_connect] do
			load('db/schema.rb')
		end
		
	end

	
end


