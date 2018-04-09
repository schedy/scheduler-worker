class AddEstimatedReleaseTimeToResources < ActiveRecord::Migration
	def change
		add_column :resources, :estimated_release_time, :bigint
	end
end
