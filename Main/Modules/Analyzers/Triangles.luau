-- Triangles -- per-MeshPart geometry cost.
--
-- Where permissions allow, this is the REAL triangle count, read from the mesh
-- via AssetService:CreateEditableMeshAsync. That API only works on assets the
-- user owns, so most Toolbox and Marketplace meshes cannot be measured -- in a
-- public plugin that is the majority of scenes. Those fall back to a crude cost
-- proxy built from always-readable properties, and are labelled "est." so an
-- estimate is never passed off as a measurement.
--
-- Measured and estimated rows are ranked in separate groups because a triangle
-- count and a heuristic score are not the same unit.

local AssetService = game:GetService("AssetService")

-- MeshId -> triangle count, or false when the mesh cannot be loaded. Module
-- level so it survives across runs: re-requesting meshes we already know we have
-- no permission for is pure wasted time, and every load is a network round trip.
local triangleCache = {}

local MEASURED_OK_BELOW     = 2000
local MEASURED_MEDIUM_BELOW = 10000

local ESTIMATE_OK_BELOW     = 5
local ESTIMATE_MEDIUM_BELOW = 12

-- 12,345 -> "12,345"
local function withThousands(n)
	local digits = tostring(math.floor(n + 0.5))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

-- Real triangle count, or nil when the mesh can't be read.
local function measure(meshPart)
	local id       = meshPart.MeshId
	local cacheKey = (id ~= nil and id ~= "") and id or nil

	if cacheKey and triangleCache[cacheKey] ~= nil then
		local cached = triangleCache[cacheKey]
		return (cached ~= false) and cached or nil
	end

	local count
	local ok, editableMesh = pcall(function()
		local content
		if id ~= nil and id ~= "" then
			content = Content.fromUri(id)
		else
			content = meshPart.MeshContent -- newer MeshParts carry no MeshId
		end
		return AssetService:CreateEditableMeshAsync(content)
	end)

	if ok and editableMesh then
		count = #editableMesh:GetFaces()
		editableMesh:Destroy() -- EditableMeshes are memory-heavy; free immediately
	else
		count = false -- no permission, or an unreadable format
	end

	if cacheKey then
		triangleCache[cacheKey] = count
	end
	return (count ~= false) and count or nil
end

-- Cost proxy for meshes we CAN'T measure. Uses only properties that are always
-- readable. This is not a triangle count and is never presented as one.
local function estimate(meshPart)
	local score   = meshPart.Size.Magnitude / 10
	local reasons = {}

	if meshPart.RenderFidelity == Enum.RenderFidelity.Precise then
		score += 6
		table.insert(reasons, "Render=Precise")
	elseif meshPart.RenderFidelity == Enum.RenderFidelity.Automatic then
		score += 2
	end

	if meshPart.CanCollide then
		if meshPart.CollisionFidelity == Enum.CollisionFidelity.PreciseConvexDecomposition then
			score += 6
			table.insert(reasons, "Collision=Precise")
		elseif meshPart.CollisionFidelity == Enum.CollisionFidelity.Default then
			score += 3
			table.insert(reasons, "Collision=Default")
		end
	end

	return score, reasons
end

return {
	id    = "Triangles",
	label = "Triangles",

	scan = function(index, budget)
		local findings = {}
		local measured, estimated = 0, 0

		budget:setPhase("Reading meshes", #index.meshParts)

		for _, meshPart in ipairs(index.meshParts) do
			local triangles = measure(meshPart)
			local amount, bucket, sort, group

			if triangles ~= nil then
				measured += 1
				amount = string.format("(%s tris)", withThousands(triangles))
				bucket = (triangles < MEASURED_OK_BELOW and "Ok")
					or (triangles < MEASURED_MEDIUM_BELOW and "Medium")
					or "Big"
				-- measured rows outrank estimated ones: different units
				sort, group = triangles, 1
			else
				estimated += 1
				local score, reasons = estimate(meshPart)
				local why = (#reasons > 0) and (" · " .. table.concat(reasons, ", ")) or ""
				amount = string.format("(est. %.1f%s)", score, why)
				bucket = (score < ESTIMATE_OK_BELOW and "Ok")
					or (score < ESTIMATE_MEDIUM_BELOW and "Medium")
					or "Big"
				sort, group = score, 0
			end

			table.insert(findings, {
				Instance = meshPart,
				Amount   = amount,
				Sort     = sort,
				Group    = group,
				Bucket   = bucket,
			})

			if not budget:step() then
				return nil
			end
		end

		local summary
		if estimated > 0 then
			summary = string.format(
				"Triangles: %d MeshPart(s) measured, %d estimated. Meshes you don't own " ..
				"don't expose their real triangle count; those rows are a proxy from " ..
				"RenderFidelity / CollisionFidelity / size, marked \"est.\".",
				measured, estimated
			)
		end

		return findings, summary
	end,
}
