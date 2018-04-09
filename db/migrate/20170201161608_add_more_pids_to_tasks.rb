class AddMorePidsToTasks < ActiveRecord::Migration
	def change
		add_column :tasks, :executor_pid, :integer
		add_column :tasks, :executor_pgid, :integer
	end
end
