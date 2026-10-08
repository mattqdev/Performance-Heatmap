-- Draws -- how the whole place batches into draw calls, without measuring it.
--
-- The renderer draws together objects that share geometry and surface, so the
-- number of distinct (geometry, surface, pass) combinations is approximately the
-- number of draw calls it takes to draw the place. That is derivable statically,
-- for everything at once -- where Measure gives an exact figure for a handful of
-- objects from one camera. The two answer the same question at opposite scales.
--
-- The useful output isn't the total, it's the tail: an asset used once pays a
-- whole draw call for one object, while a mesh reused 8,000 times pays one draw
-- call for all of them. Those one-offs are what the list shows.
--
-- This is an estimate and is labelled as one everywhere it appears. The summary
-- prints it next to the engine's own SceneDrawcallCount so the error is visible
-- rather than hidden -- with the caveat that the two count different things:
-- this covers the whole place, SceneDrawcallCount only what the camera can
-- currently see, so they line up only when the camera frames everything.

local Stats = game:GetService("Stats")

local Format = require(script.Parent.Parent.Format)

-- A batch used by this many objects or fewer is paying a full draw call for
-- almost nothing. One use is the pure case and is what the top bucket is for.
local ONE_OFF_USES = 1
local FEW_USES     = 3

-- How many of the best-reused batches the summary calls out.
local TOP_REUSED = 12

local SURFACE_MAPS = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" }

local function readProperty(instance, property)
	local ok, value = pcall(function()
		return instance[property]
	end)
	return ok and value or nil
end

-- Image properties are `Content` on current engine versions and plain strings on
-- older ones; normalise both to a comparable asset URI.
local function uri(value)
	if value == nil then
		return nil
	end
	if type(value) == "string" then
		return (value ~= "") and value or nil
	end
	local ok, text = pcall(function()
		return value.Uri
	end)
	return (ok and type(text) == "string" and text ~= "") and text or nil
end

local function geometryKey(part)
	if part:IsA("MeshPart") then
		local mesh = uri(readProperty(part, "MeshId")) or uri(readProperty(part, "MeshContent"))
		return "mesh:" .. (mesh or "unresolved")
	end

	if part:IsA("PartOperation") then
		-- Solid modelling bakes a unique mesh per operation and exposes no shared
		-- asset id (UnionOperation.AssetId is not a readable member), so two
		-- copies of one union are indistinguishable from two different unions.
		-- Each is counted as its own batch, which is the conservative reading.
		return "solid:" .. part:GetDebugId()
	end

	local shape = readProperty(part, "Shape")
	return "shape:" .. (shape and shape.Name or part.ClassName)
end

local function surfaceKey(part)
	local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
	if appearance then
		-- A SurfaceAppearance is a per-object material: two objects share a batch
		-- only when they point at the same set of maps.
		local maps = {}
		for _, map in ipairs(SURFACE_MAPS) do
			table.insert(maps, uri(readProperty(appearance, map)) or "-")
		end
		return "surface:" .. table.concat(maps, "|")
	end

	local texture = uri(readProperty(part, "TextureID")) or uri(readProperty(part, "TextureContent"))
	if texture then
		return "texture:" .. texture
	end

	local variant = readProperty(part, "MaterialVariant")
	if variant and variant ~= "" then
		return "variant:" .. tostring(variant)
	end

	local material = readProperty(part, "Material")
	return "material:" .. (material and material.Name or "Plastic")
end

-- Transparency is drawn in its own sorted pass, and shadow casters are gathered
-- again for the shadow map; neither batches with its opposite.
local function passKey(part)
	return (part.Transparency > 0 and "T" or "O") .. (part.CastShadow and "S" or "-")
end

return {
	id    = "Draws",
	label = "Draw calls",

	scan = function(index, budget)
		local batches, order = {}, {}

		local function record(key, instance)
			local batch = batches[key]
			if not batch then
				batch = { Key = key, First = instance, Uses = 0 }
				batches[key] = batch
				table.insert(order, batch)
			end
			batch.Uses += 1
		end

		budget:setPhase("Grouping geometry", #index.parts)

		local renderables = 0
		for _, part in ipairs(index.parts) do
			-- Terrain is a BasePart but is drawn by its own system, and a fully
			-- transparent part isn't drawn at all.
			if not part:IsA("Terrain") and part.Transparency < 1 then
				renderables += 1
				record(geometryKey(part) .. "|" .. surfaceKey(part) .. "|" .. passKey(part), part)
			end

			if not budget:step() then
				return nil
			end
		end

		-- Decals and Textures are surface quads drawn on top of their part, so
		-- each distinct image is its own batch on top of the geometry above.
		budget:setPhase("Grouping decals", #index.decals)

		for _, decal in ipairs(index.decals) do
			local image = uri(readProperty(decal, "Texture"))
			if image then
				renderables += 1
				record("decal:" .. image .. "|" .. (decal.Transparency > 0 and "T" or "O"), decal)
			end

			if not budget:step() then
				return nil
			end
		end

		-- Findings: one row per batch, worst reuse first. A batch is one draw
		-- call whatever its size, so the waste is in how few objects share it.
		budget:setPhase("Scoring batches", #order)

		local findings = {}
		local oneOffs  = 0

		for _, batch in ipairs(order) do
			if batch.Uses <= ONE_OFF_USES then
				oneOffs += 1
			end

			local bucket = (batch.Uses <= ONE_OFF_USES and "Big")
				or (batch.Uses <= FEW_USES and "Medium")
				or "Ok"

			if bucket ~= "Ok" then
				table.insert(findings, {
					Instance = batch.First,
					Amount   = string.format(
						"(est. 1 draw call · %s)",
						batch.Uses == 1 and "used once" or Format.plural(batch.Uses, "object")
					),
					-- One draw call spread over N objects: the fewer objects, the
					-- more of it each one is paying for.
					Sort   = 1 / batch.Uses,
					Bucket = bucket,
				})
			end

			if not budget:step() then
				return nil
			end
		end

		-- Headline numbers, including how far off the estimate is from the real
		-- counter. Showing the error is the point: an estimate that reports its
		-- own accuracy is worth more than one that quietly doesn't.
		table.sort(order, function(a, b)
			return a.Uses > b.Uses
		end)

		local topReused, topObjects = math.min(TOP_REUSED, #order), 0
		for position = 1, topReused do
			topObjects += order[position].Uses
		end

		local notes = {
			string.format(
				"Draws: %d renderable object(s) group into %d batch(es), so drawing all of this " ..
				"place costs roughly %d draw call(s).",
				renderables, #order, #order
			),
			string.format(
				"%d batch(es) are used once and pay a full draw call for a single object; the %d " ..
				"best-reused batches cover %d object(s) between them. Reusing an asset is what " ..
				"turns many objects into one draw call.",
				oneOffs, topReused, topObjects
			),
		}

		local ok, sceneDraws = pcall(function()
			return Stats.SceneDrawcallCount
		end)
		if ok and type(sceneDraws) == "number" then
			table.insert(notes, string.format(
				"The engine reports %d draw call(s) right now -- but that counts only what the " ..
				"camera can see, while the estimate above covers the whole place, so the two " ..
				"only line up when the camera frames everything.",
				sceneDraws
			))
		end

		table.insert(notes,
			"This is an estimate: batching depends on renderer decisions no property exposes, " ..
			"and copies of the same union can't be told apart from different unions, so each is " ..
			"counted separately. Use Measure for an exact figure on specific objects.")

		return findings, table.concat(notes, " ")
	end,
}
