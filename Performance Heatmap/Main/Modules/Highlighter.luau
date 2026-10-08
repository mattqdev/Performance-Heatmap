-- Highlighter.luau
-- Draws the heatmap boxes as adornments under CoreGui instead of as real Parts
-- in Workspace.
--
-- Why this matters: the old approach cloned an oversized transparent Part for
-- every highlighted BasePart. On a large place that doubled the instance count,
-- inflated the very Stats the plugin displays (SceneDrawcallCount,
-- InstanceCount, SceneTriangleCount), sat on top of the real objects so they
-- couldn't be clicked in the viewport, and went stale as soon as anything moved.
--
-- Adornments have none of those problems: they live outside Workspace (nothing
-- to clean up in the Explorer, nothing saved into the place, no effect on the
-- measurements), they follow their Adornee automatically, and they are not
-- pickable. Hiding the panel just unparents the folder, which is why detach /
-- attach on the service is now a one-line `setVisible`.

local CoreGui = game:GetService("CoreGui")

local Highlighter = {}
Highlighter.__index = Highlighter

-- Rendering thousands of adornments is itself slow, and a viewport painted
-- entirely red tells you nothing. We draw the worst offenders and leave the rest
-- to the list.
local DEFAULT_MAX = 150

-- Adornments render exactly on the surface, so a small inflate avoids z-fighting
-- with the object underneath (the old Parts used +1 stud, which was chunky).
local INFLATE     = Vector3.new(0.06, 0.06, 0.06)
local TRANSPARENCY = 0.6

function Highlighter.new(folderName, maxAdornments)
	return setmetatable({
		folderName = folderName or "PerformanceHeatmapAdornments",
		max        = maxAdornments or DEFAULT_MAX,
		_folder    = nil,
		_visible   = true,
		_count     = 0,
		_skipped   = 0,
	}, Highlighter)
end

function Highlighter:_ensureFolder()
	local f = self._folder
	local wanted = self._visible and CoreGui or nil

	-- the folder can be destroyed from under us (plugin reload, user poking
	-- around in CoreGui); a destroyed instance can't be re-parented, so rebuild
	if f and f.Parent ~= wanted and not pcall(function()
		f.Parent = wanted
	end) then
		f = nil
	end

	if not f then
		f = Instance.new("Folder")
		f.Name       = self.folderName
		f.Archivable = false
		f.Parent     = wanted
	end

	self._folder = f
	return f
end

function Highlighter:_newBox(adornee, cframe, size, color)
	local box = Instance.new("BoxHandleAdornment")
	box.Adornee      = adornee
	box.CFrame       = cframe
	box.Size         = size
	box.Color3       = color
	box.Transparency = TRANSPARENCY
	box.AlwaysOnTop  = false
	box.ZIndex       = 0
	box.Archivable   = false
	box.Parent       = self:_ensureFolder()

	self._count += 1
	return box
end

-- Nearest BasePart we can hang an adornment on (lights and emitters are
-- parented to a BasePart, or to an Attachment inside one).
local function hostPart(instance)
	local node = instance
	while node and node ~= game do
		if node:IsA("BasePart") then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Adds a highlight for any instance a mode can report. Returns false when the
-- highlight budget is used up, so the caller can stop asking.
function Highlighter:add(instance, color)
	if self._count >= self.max then
		self._skipped += 1
		return false
	end

	if instance:IsA("Model") then
		-- One box around the whole model rather than one per part: far cheaper,
		-- and it reads better as "this model is the problem".
		local ok, cf, size = pcall(function()
			return instance:GetBoundingBox()
		end)
		if not ok or size.Magnitude == 0 then
			return true
		end
		-- Adornee is the Model itself (Model is a PVInstance), so the adornment
		-- CFrame is relative to the model's pivot, not to the world.
		local offset = instance:GetPivot():ToObjectSpace(cf)
		self:_newBox(instance, offset, size + INFLATE, color)
		return true
	end

	-- a BasePart boxes itself; a light or emitter boxes the part it hangs off
	local part = hostPart(instance)
	if part then
		self:_newBox(part, CFrame.identity, part.Size + INFLATE, color)
	end
	return true
end

-- How many highlights were dropped because of the cap (0 when everything fit).
function Highlighter:skipped()
	return self._skipped
end

function Highlighter:count()
	return self._count
end

-- Panel closed / opened. The adornments are kept alive so re-opening restores
-- the previous scan verbatim with no re-analysis; this is session-only,
-- in-memory state and is never persisted.
function Highlighter:setVisible(visible)
	self._visible = visible and true or false
	if self._folder then
		pcall(function()
			self._folder.Parent = self._visible and CoreGui or nil
		end)
	end
end

function Highlighter:clear()
	if self._folder then
		pcall(function()
			self._folder:Destroy()
		end)
	end
	self._folder  = nil
	self._count   = 0
	self._skipped = 0
end

return Highlighter
