-- Lights -- cost of PointLight / SpotLight / SurfaceLight.
--
-- The old score was Brightness x Range, which misses the single biggest cost
-- driver: `Shadows`. A shadow-casting light makes the renderer re-draw
-- everything in its range into a shadow map, which is why ShadowsDrawcallCount
-- exists as its own Stats metric. It is worth far more than a couple of studs of
-- extra range, so it gets a multiplier and is called out by name in the row.
--
-- Disabled lights cost nothing and are skipped rather than reported as green.

local SHADOW_MULTIPLIER = 3

local OK_BELOW     = 40
local MEDIUM_BELOW = 150

return {
	id    = "Lights",
	label = "Lights",

	scan = function(index, budget)
		local findings = {}
		local shadowCasters = 0

		budget:setPhase("Scoring lights", #index.lights)

		for _, light in ipairs(index.lights) do
			if light.Enabled and light.Range > 0 and light.Brightness > 0 then
				local score   = light.Brightness * light.Range
				local reasons = {}

				if light.Shadows then
					score *= SHADOW_MULTIPLIER
					shadowCasters += 1
					table.insert(reasons, "Shadows")
				end

				local why = (#reasons > 0) and (" · " .. table.concat(reasons, ", ")) or ""

				table.insert(findings, {
					Instance = light,
					Amount   = string.format("(score %.0f%s)", score, why),
					Sort     = score,
					Bucket   = (score < OK_BELOW and "Ok")
						or (score < MEDIUM_BELOW and "Medium")
						or "Big",
				})
			end

			if not budget:step() then
				return nil
			end
		end

		local summary
		if shadowCasters > 0 then
			summary = string.format(
				"Lights: %d of %d enabled light(s) cast shadows. Turning Shadows off on " ..
				"decorative lights is usually the cheapest win here.",
				shadowCasters, #findings
			)
		end

		return findings, summary
	end,
}
