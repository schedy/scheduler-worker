class Device < Resource

	def self.estimate(candidate, required)
		return 	{ transition_duration: 0, actors: {}, steps: [] } if not required["image"] or candidate["image"] == required["image"]

		step = {
			resource: candidate,
			required: required,
			steps: []
		}
		{ transition_duration: 60.0, actors: {}, steps: step }
	end


	def self.transition(owned, required)

	end

end
