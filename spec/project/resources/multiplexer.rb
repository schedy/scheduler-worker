class Multiplexer < Resource

	def self.estimate(candidate, required)
		required_children = required["children"]
		candidate_children = (candidate["children"] or [])
		Resource.estimate(candidate_children, required_children)
	end


	def self.transition(owned, required)

	end

end
