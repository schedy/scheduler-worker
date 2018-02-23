class AddChildrenIdsToResources < ActiveRecord::Migration
	def change
		add_column :resources, :children_ids, :integer, array: true, default: '{}'
	end
end
