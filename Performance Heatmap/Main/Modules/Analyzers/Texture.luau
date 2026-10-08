-- Texture -- texture memory pressure per object.
--
-- Texture memory is the usual reason a place is fine on a desktop and crashes on
-- a phone, and no property on any instance reports it, so nobody looks at it.
-- What we *can* count exactly is how many distinct image assets the place
-- references and how often each one is reused, which is the part that actually
-- decides the bill: an atlas used on 500 objects is paid for once, whereas 500
-- one-off images are paid for 500 times.
--
-- So an object is scored by the images it references, weighted heavily towards
-- the ones used nowhere else in the place. Note this counts *assets*, not
-- megabytes -- the engine does not expose resolution, so this is a ranking, not
-- a memory figure, and it is labelled as such.

local ONE_OFF_WEIGHT = 2.0   -- an image only this object uses
local SHARED_WEIGHT  = 0.5   -- an image reused elsewhere; amortised

local OK_BELOW     = 4
local MEDIUM_BELOW = 8

return {
	id    = "Texture",
	label = "Textures",

	scan = function(index, budget)
		local findings = {}
		local usage    = index.textureUsage
		local oneOffTotal = 0

		budget:setPhase("Scoring textures", #index.textured)

		for _, entry in ipairs(index.textured) do
			local score   = 0
			local oneOffs = 0

			for _, uri in ipairs(entry.Uris) do
				if (usage[uri] or 0) <= 1 then
					score += ONE_OFF_WEIGHT
					oneOffs += 1
				else
					score += SHARED_WEIGHT
				end
			end

			if score > 0 then
				oneOffTotal += oneOffs

				local detail = (oneOffs > 0)
					and string.format(" · %d used only here", oneOffs)
					or " · all reused"

				table.insert(findings, {
					Instance = entry.Object,
					Amount   = string.format("(%d textures%s)", #entry.Uris, detail),
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
		if index.uniqueTextures > 0 then
			summary = string.format(
				"Textures: %d unique image asset(s) across %d object(s), %d of them used " ..
				"exactly once. This ranks texture *memory pressure* -- the engine doesn't " ..
				"expose resolution, so these are asset counts, not megabytes.",
				index.uniqueTextures, #index.textured, oneOffTotal
			)
		end

		return findings, summary
	end,
}
