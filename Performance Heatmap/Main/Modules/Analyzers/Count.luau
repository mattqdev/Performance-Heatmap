-- Count -- raw part count per Model.
--
-- The bluntest mode the plugin has, and the one the DevForum thread is rightly
-- sceptical of: part count alone does not predict frame time. It stays because
-- it is still the fastest way to find a model somebody built out of 400 wedges,
-- but Triangles / Draw-call-shaped modes are the ones to trust.
--
-- Counts are *direct*: parts whose nearest Model ancestor is this model. The
-- inclusive figure is shown next to it when the two differ, so a map container
-- no longer reports the whole place and drowns out everything else.

local OK_BELOW     = 25
local MEDIUM_BELOW = 100

return {
	id    = "Count",
	label = "Part Count",

	scan = function(index, budget)
		local findings = {}

		budget:setPhase("Counting parts", #index.models)

		for _, record in ipairs(index.models) do
			local count = record.direct

			if count > 0 then
				local amount
				if record.total > count then
					amount = string.format("(%d parts · %d with children)", count, record.total)
				else
					amount = string.format("(%d parts)", count)
				end

				table.insert(findings, {
					Instance = record.Model,
					Amount   = amount,
					Sort     = count,
					Bucket   = (count < OK_BELOW and "Ok")
						or (count < MEDIUM_BELOW and "Medium")
						or "Big",
				})
			end

			if not budget:step() then
				return nil
			end
		end

		return findings
	end,
}
