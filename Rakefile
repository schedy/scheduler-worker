require 'pg'
require 'active_record'
require 'yaml'

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
