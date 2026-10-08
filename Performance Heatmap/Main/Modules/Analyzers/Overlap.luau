-- Overlap -- parts that interpenetrate each other.
--
-- Two things this finds, both of which cost real frames and neither of which any
-- other tool surfaces:
--   * buried geometry -- a part almost entirely inside another is still fully
--     transmitted, stored and (unless occluded) drawn. It is pure waste.
--   * z-fighting candidates -- coincident surfaces flicker on some devices and
--     force the GPU to shade the same pixels twice (overdraw).
--
-- Method: bucket world-space AABBs into a uniform grid and compare only the
-- parts that share a cell. Boxes are conservative for rotated parts, so a
-- reported overlap is an upper bound on the real intersection -- treat the
-- percentage as "how buried this looks", not as a measured volume.

local CELL_SIZE   = 16     -- studs
local MAX_SPAN    = 24     -- cells a part may cover before we skip it
local MIN_VOLUME  = 0.001  -- ignore degenerate parts
local MAX_PAIRS   = 2000000

local OK_BELOW     = 0.20
local MEDIUM_BELOW = 0.50

-- World-space AABB of an oriented part.
local function worldBounds(part)
	local cf, size = part.CFrame, part.Size
	local right = cf.RightVector * (size.X * 0.5)
	local up    = cf.UpVector    * (size.Y * 0.5)
	local look  = cf.LookVector  * (size.Z * 0.5)

	local extents = Vector3.new(
		math.abs(right.X) + math.abs(up.X) + math.abs(look.X),
		math.abs(right.Y) + math.abs(up.Y) + math.abs(look.Y),
		math.abs(right.Z) + math.abs(up.Z) + math.abs(look.Z)
	)

	return cf.Position - extents, cf.Position + extents
end

local function intersectionVolume(minA, maxA, minB, maxB)
	local x = math.min(maxA.X, maxB.X) - math.max(minA.X, minB.X)
	if x <= 0 then return 0 end
	local y = math.min(maxA.Y, maxB.Y) - math.max(minA.Y, minB.Y)
	if y <= 0 then return 0 end
	local z = math.min(maxA.Z, maxB.Z) - math.max(minA.Z, minB.Z)
	if z <= 0 then return 0 end
	return x * y * z
end

return {
	id    = "Overlap",
	label = "Overlap",

	scan = function(index, budget)
		-- 1) candidates: parts that are actually drawn and are not so large that
		-- they overlap everything by construction (baseplates, terrain-sized slabs)
		local candidates = {}

		budget:setPhase("Collecting geometry", #index.parts)

		for _, part in ipairs(index.parts) do
			if part.Transparency < 1 then
				local low, high = worldBounds(part)
				local span = high - low
				local volume = span.X * span.Y * span.Z

				if volume >= MIN_VOLUME
					and span.X <= CELL_SIZE * MAX_SPAN
					and span.Y <= CELL_SIZE * MAX_SPAN
					and span.Z <= CELL_SIZE * MAX_SPAN
				then
					table.insert(candidates, {
						Part   = part,
						Min    = low,
						Max    = high,
						Volume = volume,
						Buried = 0,
						Peers  = 0,
					})
				end
			end

			if not budget:step() then
				return nil
			end
		end

		-- 2) spatial hash
		budget:setPhase("Bucketing", #candidates)

		local grid = {}
		for i, candidate in ipairs(candidates) do
			local x0 = math.floor(candidate.Min.X / CELL_SIZE)
			local y0 = math.floor(candidate.Min.Y / CELL_SIZE)
			local z0 = math.floor(candidate.Min.Z / CELL_SIZE)
			local x1 = math.floor(candidate.Max.X / CELL_SIZE)
			local y1 = math.floor(candidate.Max.Y / CELL_SIZE)
			local z1 = math.floor(candidate.Max.Z / CELL_SIZE)

			for x = x0, x1 do
				for y = y0, y1 do
					for z = z0, z1 do
						local key = x .. "," .. y .. "," .. z
						local cell = grid[key]
						if not cell then
							cell = {}
							grid[key] = cell
						end
						table.insert(cell, i)
					end
				end
			end

			if not budget:step() then
				return nil
			end
		end

		-- 3) pairwise tests inside each cell. A pair can share several cells, so
		-- results are accumulated against a seen-set rather than re-added.
		budget:setPhase("Comparing", 0)

		local seen        = {}
		local comparisons = 0
		local truncated   = false

		for _, cell in pairs(grid) do
			local n = #cell
			for a = 1, n - 1 do
				-- yield per row of the pair matrix, not per cell: one dense cell
				-- can hold thousands of parts, and n²/2 comparisons without a
				-- yield is exactly the freeze this rewrite exists to remove
				if not budget:step() then
					return nil
				end

				for b = a + 1, n do
					local i, j = cell[a], cell[b]
					if i > j then i, j = j, i end

					local key = i * 1000000 + j
					if not seen[key] then
						seen[key] = true
						comparisons += 1

						local ca, cb = candidates[i], candidates[j]
						local shared = intersectionVolume(ca.Min, ca.Max, cb.Min, cb.Max)

						if shared > 0 then
							ca.Buried += shared
							cb.Buried += shared
							ca.Peers += 1
							cb.Peers += 1
						end
					end

					if comparisons >= MAX_PAIRS then
						truncated = true
						break
					end
				end
				if truncated then break end
			end

			if truncated then break end
		end

		-- 4) score: fraction of a part's own volume that sits inside something else
		budget:setPhase("Scoring overlap", #candidates)

		local findings = {}
		for _, candidate in ipairs(candidates) do
			if candidate.Peers > 0 then
				local buried = math.min(candidate.Buried / candidate.Volume, 1)

				if buried >= OK_BELOW then
					table.insert(findings, {
						Instance = candidate.Part,
						Amount   = string.format(
							"(%.0f%% overlapped · %d part%s)",
							buried * 100, candidate.Peers,
							candidate.Peers == 1 and "" or "s"
						),
						Sort   = buried,
						Bucket = (buried < MEDIUM_BELOW and "Medium") or "Big",
					})
				end
			end

			if not budget:step() then
				return nil
			end
		end

		local summary
		if truncated then
			summary = string.format(
				"Overlap: stopped after %d pair comparisons -- the scene is dense enough " ..
				"that the results below are partial.",
				MAX_PAIRS
			)
		elseif #findings > 0 then
			summary = string.format(
				"Overlap: %d part(s) sit at least %d%% inside another part. Deeply buried " ..
				"geometry is never seen but is still stored, replicated and (unless " ..
				"occluded) drawn. Percentages come from axis-aligned boxes, so they are " ..
				"an upper bound for rotated parts.",
				#findings, OK_BELOW * 100
			)
		end

		return findings, summary
	end,
}
