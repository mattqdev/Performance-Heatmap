-- Measure -- the real render cost of the objects you select.
--
-- Every other mode ranks a proxy and says so. This one measures: it reads the
-- engine's own scene counters, makes the object stop rendering, reads them
-- again, and reports the difference. Modules/RenderProbe holds the mechanics and
-- the record of what was verified in Studio before this shipped.
--
-- Why it earns its place: it is a genuine triangle count on meshes the user does
-- not own -- exactly the meshes Triangles can only estimate, which on most real
-- places is nearly all of them -- and it is the first per-object draw call
-- figure the plugin has been able to give.
--
-- Two limits, both put in front of the user rather than buried here:
--   * it measures what THIS CAMERA sees. An object outside the frustum costs
--     nothing right now. That is a fact about the shot, not about the object.
--   * it measures the MARGIN. An object batched with fifty others adds no draw
--     call of its own, so removing it alone saves none -- which is precisely the
--     number you want when deciding what to delete, and precisely why these
--     figures do not add up to the whole scene.
--
-- Costs a few frames per object, so it works on a selection (or on the worst
-- offenders of the previous scan), never on a whole place.

local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local Format      = require(script.Parent.Parent.Format)
local RenderProbe = require(script.Parent.Parent.RenderProbe)

-- Each target costs ~9 frames. Past this the action stops feeling interactive,
-- and the roadmap's use for it is "confirm the top of the last scan" anyway.
local MAX_TARGETS = 50

-- Unlike every other mode, these bands rank *the selection you asked about*
-- rather than judging objects against a place-wide budget. Anything that
-- measured above zero is listed: you pointed at it, so you get its number.
-- Dropping a measured object into the unshown "Ok" bucket would be the one
-- outcome that makes the mode feel broken.
local BIG_DRAWS,    BIG_TRIANGLES    = 8, 20000
local MEDIUM_DRAWS, MEDIUM_TRIANGLES = 1, 1

-- Draw calls and triangles are different units, and the results list is a single
-- ordering, so the two have to be traded off somewhere. This is that exchange
-- rate and nothing more: it decides row order only, is never displayed, and is
-- not offered as a cost model. A draw call is CPU submit overhead, worth roughly
-- a few thousand triangles of GPU raster on a mid-range device.
local DRAWCALL_IN_TRIANGLES = 5000

-- True when something above `instance` is selected too, in which case the
-- ancestor already covers it: selecting a model and one of its parts should
-- measure the model once, not the model and then the part again inside it.
local function coveredByAncestor(instance, selected)
	local node = instance.Parent
	while node and node ~= game do
		if selected[node] then
			return true
		end
		node = node.Parent
	end
	return false
end

local function measurable(instance)
	return instance:IsDescendantOf(Workspace)
end

local function fromSelection()
	local picked = Selection:Get()
	if #picked == 0 then
		return nil
	end

	local selected = {}
	for _, instance in ipairs(picked) do
		selected[instance] = true
	end

	local targets = {}
	for _, instance in ipairs(picked) do
		if measurable(instance) and not coveredByAncestor(instance, selected) then
			table.insert(targets, instance)
		end
	end

	return (#targets > 0) and targets or nil
end

-- Nothing selected: fall back to confirming the worst offenders the previous
-- scan turned up. Heuristic heatmap to narrow the field, measurement to check
-- the field was narrowed to the right things.
local function fromPrevious(context)
	local previous = context and context.previous
	if not previous then
		return nil
	end

	local targets, seen = {}, {}
	for _, list in ipairs({ previous.Big, previous.Medium }) do
		for _, finding in ipairs(list or {}) do
			local instance = finding.Instance
			if instance and not seen[instance] and measurable(instance) then
				seen[instance] = true
				table.insert(targets, instance)
				if #targets >= MAX_TARGETS then
					return targets
				end
			end
		end
	end

	return (#targets > 0) and targets or nil
end

return {
	id    = "Measure",
	label = "Measure Selection",

	-- Works on a selection, not on the place: the shared Workspace traversal
	-- would be seconds of work whose result this mode never reads.
	usesIndex = false,

	scan = function(_, budget, context)
		if not RenderProbe.available() then
			return {}, "Measure: SceneDrawcallCount / SceneTriangleCount aren't readable here, " ..
				"so there is nothing to measure against."
		end

		local source  = "selection"
		local targets = fromSelection()
		if not targets then
			targets = fromPrevious(context)
			source  = "previous scan"
		end

		if not targets then
			return {}, "Measure: select the objects you want measured (Explorer or viewport) and " ..
				"pick Measure again. With nothing selected it falls back to the worst offenders " ..
				"of the last scan, and there hasn't been one yet."
		end

		local truncated = #targets > MAX_TARGETS
		for index = #targets, MAX_TARGETS + 1, -1 do
			table.remove(targets, index)
		end

		budget:setPhase("Measuring", #targets)

		local findings = {}
		local totalDraws, totalTriangles, invisible = 0, 0, 0

		for _, target in ipairs(targets) do
			local parts = RenderProbe.renderables(target)
			local draws, triangles = RenderProbe.cost(parts)
			if draws == nil then
				return nil -- the counters went away mid-run; report nothing
			end

			totalDraws     += draws
			totalTriangles += triangles

			local bucket, amount
			if #parts == 0 then
				-- A Folder, a Script, a fully transparent part: there was never
				-- anything here to draw, which is a different statement from
				-- "the camera can't see it".
				bucket = "Ok"
				amount = "(nothing to draw)"
			elseif draws == 0 and triangles == 0 then
				-- Never "0 draw calls", which reads as "this is free". It isn't
				-- drawn from where the camera is standing, and that's all we know.
				bucket = "Ok"
				amount = "(not drawn from this camera)"
				invisible += 1
			else
				bucket = (draws >= BIG_DRAWS or triangles >= BIG_TRIANGLES) and "Big"
					or ((draws >= MEDIUM_DRAWS or triangles >= MEDIUM_TRIANGLES) and "Medium")
					or "Ok"
				amount = string.format(
					"(%s · %s tris)",
					Format.plural(draws, "draw call"),
					Format.thousands(triangles)
				)
			end

			table.insert(findings, {
				Instance = target,
				Amount   = amount,
				Sort     = draws * DRAWCALL_IN_TRIANGLES + triangles,
				Bucket   = bucket,
			})

			if not budget:step() then
				return nil
			end
		end

		local notes = {
			string.format(
				"Measure: %d object(s) from the %s cost %s and %s triangle(s) from where the " ..
				"camera is now.",
				#targets, source, Format.plural(totalDraws, "draw call"),
				Format.thousands(totalTriangles)
			),
			"These come from the engine's own counters, not from an estimate -- including on " ..
			"meshes you don't own, which the Triangles mode can only guess at.",
			"They are marginal costs from this one shot: an object outside the view, or one " ..
			"that shares a batch with others, measures zero. That's a fact about the camera " ..
			"and the batching, not a free object -- and it's why measuring objects separately " ..
			"adds up to less than measuring them together.",
			"HIGH COST / MODERATE here rank what you selected against each other, not against " ..
			"a budget for the whole place.",
		}

		if invisible > 0 then
			table.insert(notes, string.format(
				"%d of them weren't drawn at all from here; point the camera at them and measure again.",
				invisible
			))
		end

		if truncated then
			table.insert(notes, string.format(
				"Only the first %d were measured -- each one costs a few frames.",
				MAX_TARGETS
			))
		end

		return findings, table.concat(notes, " ")
	end,
}
