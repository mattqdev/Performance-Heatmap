-- RenderProbe.luau
-- Attributes real render cost to specific objects, by difference.
--
-- Every other mode in this plugin ranks a proxy. This one asks the engine: the
-- renderer publishes SceneDrawcallCount and SceneTriangleCount every frame, so
-- making an object stop rendering and reading the counters again gives its
-- actual contribution. That is how the plugin gets a true triangle count for
-- meshes AssetService:CreateEditableMeshAsync refuses to open -- most of the
-- Toolbox -- and the first per-object draw call figure it has ever had.
--
-- What was verified in Studio before this shipped (edit mode, 1082-part scene):
--   * LocalTransparencyModifier = 1 really does drop a part from the render
--     batch: 58 -> 13 draw calls, 33,080 -> 26 triangles with everything hidden.
--   * The property is not serialised, so nothing dirties the place, and the
--     counters return to exactly their previous values once it is restored.
--   * With nothing moving, the counters are stable to the unit frame after
--     frame. A delta of one draw call is signal, not noise.
--   * CastShadow is deliberately NOT touched. It IS serialised, so toggling it
--     would mark the place as modified, and the shadow counters were still
--     drifting (0 -> 15 -> 2 -> 39) several frames after a change. Shadow cost
--     is therefore left unmeasured rather than reported as a noisy guess.
--
-- What a delta means, exactly: the cost of this object *from the current
-- camera*, *at the margin*. Zero is a real and frequent answer -- the object is
-- outside the frustum, or it shares a batch with others so removing it alone
-- saves no draw call. Zero must never be presented as "this object is free", and
-- marginal costs do not sum: measuring the parts of a scene one at a time adds
-- up to less than measuring them together.

local RunService = game:GetService("RunService")
local Stats      = game:GetService("Stats")

local RenderProbe = {}

-- Frames to wait for the renderer to rebuild its batches around a visibility
-- change. Two is enough for a single part; a thousand-part model needed a third
-- before the counters came back to rest.
local SETTLE_FRAMES = 3

local function nextFrame()
	-- RenderStepped fires once per rendered frame, which is the clock the scene
	-- counters actually move on; task.wait is the fallback for any context where
	-- it isn't available.
	local ok = pcall(function()
		RunService.RenderStepped:Wait()
	end)
	if not ok then
		task.wait()
	end
end

local function settle()
	for _ = 1, SETTLE_FRAMES do
		nextFrame()
	end
end

-- Returns draws, triangles -- or nil when either counter can't be read.
local function counters()
	local ok, draws = pcall(function()
		return Stats.SceneDrawcallCount
	end)
	if not ok or type(draws) ~= "number" then
		return nil
	end

	local okTriangles, triangles = pcall(function()
		return Stats.SceneTriangleCount
	end)
	if not okTriangles or type(triangles) ~= "number" then
		return nil
	end

	return draws, triangles
end

-- Whether measuring is possible at all here.
function RenderProbe.available()
	return counters() ~= nil
end

-- Every BasePart at or under `root` that is actually drawn. A part already at
-- full transparency contributes nothing to the counters, so hiding it would be
-- pure work for a guaranteed zero.
function RenderProbe.renderables(root, out)
	out = out or {}

	local function consider(instance)
		if instance:IsA("BasePart") and instance.Transparency < 1 then
			table.insert(out, instance)
		end
	end

	consider(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		consider(descendant)
	end

	return out
end

-- Measures `parts` as a single unit. Yields for roughly 3 * SETTLE_FRAMES
-- frames. Returns draws, triangles, or nil if the counters became unreadable.
--
-- The parts are restored on every path out of this function. Leaving a user's
-- geometry invisible because a scan was cancelled or a property write failed is
-- the one outcome this module is not allowed to produce, so both loops are
-- guarded per part and the restore always runs.
function RenderProbe.cost(parts)
	if #parts == 0 then
		return 0, 0
	end

	settle()
	local baseDraws, baseTriangles = counters()
	if not baseDraws then
		return nil
	end

	local saved = table.create(#parts)
	for index, part in ipairs(parts) do
		local ok = pcall(function()
			saved[index] = part.LocalTransparencyModifier
			part.LocalTransparencyModifier = 1
		end)
		if not ok then
			saved[index] = nil
		end
	end

	settle()
	local hiddenDraws, hiddenTriangles = counters()

	for index, part in ipairs(parts) do
		if saved[index] ~= nil then
			pcall(function()
				part.LocalTransparencyModifier = saved[index]
			end)
		end
	end
	settle()

	if not hiddenDraws then
		return nil
	end

	-- Clamped: while a batch is being rebuilt the renderer can transiently
	-- report a higher count than the baseline, and a negative cost is not a
	-- thing we should ever put in front of anyone.
	return math.max(baseDraws - hiddenDraws, 0), math.max(baseTriangles - hiddenTriangles, 0)
end

return RenderProbe
