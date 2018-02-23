class AddDirectoryToTasks < ActiveRecord::Migration
	def change
		add_column :tasks, :directory, :text
	end
end
