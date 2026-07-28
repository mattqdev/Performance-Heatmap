-- Density -- how tightly packed a Model is, in parts per 1,000 studs³.
--
-- The previous formula was `partCount / sum(part volumes)`, which is really the
-- inverse of the average part size: a hundred small parts scattered over a
-- kilometre scored as "very dense", a hundred huge parts stacked in one spot
-- scored as "sparse". That is backwards for the thing this mode exists to find.
--
-- Density is now measured against the model's own oriented bounding box, which
-- is what "packed into a small space" actually means -- the concern the forum
-- raised about placement mattering more than raw counts.

local MIN_PARTS  = 8      -- below this the ratio is noise
local MIN_VOLUME = 1      -- studs³; guards against degenerate/flat boxes
local UNIT       = 1000   -- report per 1,000 studs³

local OK_BELOW     = 10
local MEDIUM_BELOW = 40

return {
	id    = "Density",
	label = "Density",

	scan = function(index, budget)
		local findings = {}

		budget:setPhase("Measuring density", #index.models)

		for _, record in ipairs(index.models) do
			if record.direct >= MIN_PARTS then
				local ok, _, size = pcall(function()
					return record.Model:GetBoundingBox()
				end)

				if ok and size then
					local volume = size.X * size.Y * size.Z

					if volume >= MIN_VOLUME then
						local density = record.direct / (volume / UNIT)

						table.insert(findings, {
							Instance = record.Model,
							Amount   = string.format("(%.1f /1k studs³ · %d parts)", density, record.direct),
							Sort     = density,
							Bucket   = (density < OK_BELOW and "Ok")
								or (density < MEDIUM_BELOW and "Medium")
								or "Big",
						})
					end
				end
			end

			if not budget:step() then
				return nil
			end
		end

		return findings
	end,
}
