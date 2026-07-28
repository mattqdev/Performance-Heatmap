-- Particles -- cost of ParticleEmitters, weighted by overdraw.
--
-- The old score was Rate x Lifetime x Brightness. The first two are right (their
-- product is how many particles are alive at once) but Brightness is not what
-- hurts: particles are transparent quads, so the cost is how much *screen* they
-- cover and how many times the GPU shades the same pixel. Ten 20-stud puffs cost
-- far more than a thousand 0.1-stud sparks, and the old formula said the
-- opposite.
--
-- So: simultaneous particles x area (size²) x opacity. Fully transparent and
-- disabled emitters draw nothing and are skipped.

local AREA_SCALE = 10 -- keeps the score in a readable range

local OK_BELOW     = 20
local MEDIUM_BELOW = 80

-- NumberSequences are keypoint curves; the mean of the keypoints is a good
-- enough stand-in for the average value over a particle's life.
local function averageOfSequence(sequence)
	local keypoints = sequence.Keypoints
	local total = 0
	for _, keypoint in ipairs(keypoints) do
		total += keypoint.Value
	end
	return (#keypoints > 0) and (total / #keypoints) or 0
end

return {
	id    = "Particles",
	label = "Particles",

	scan = function(index, budget)
		local findings = {}

		budget:setPhase("Scoring particles", #index.emitters)

		for _, emitter in ipairs(index.emitters) do
			if emitter.Enabled and emitter.Rate > 0 then
				local lifetime     = emitter.Lifetime
				local averageLife  = (lifetime.Min + lifetime.Max) / 2
				local simultaneous = emitter.Rate * averageLife
				local averageSize  = averageOfSequence(emitter.Size)
				local opacity      = 1 - averageOfSequence(emitter.Transparency)

				if simultaneous > 0 and averageSize > 0 and opacity > 0.01 then
					local score = simultaneous * averageSize * averageSize * opacity / AREA_SCALE

					table.insert(findings, {
						Instance = emitter,
						Amount   = string.format(
							"(~%d alive · %.1f studs · score %.0f)",
							simultaneous, averageSize, score
						),
						Sort   = score,
						Bucket = (score < OK_BELOW and "Ok")
							or (score < MEDIUM_BELOW and "Medium")
							or "Big",
					})
				end
			end

			if not budget:step() then
				return nil
			end
		end

		return findings
	end,
}
