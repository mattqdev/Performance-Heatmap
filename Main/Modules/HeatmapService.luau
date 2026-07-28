local HeatmapService = {}
HeatmapService.__index = HeatmapService

local workspace       = game:GetService("Workspace")
local StudioService   = game:GetService("StudioService")
local AssetService    = game:GetService("AssetService")

local UIService = require(script.Parent.UIService)

function HeatmapService.new(containerName)
	local self = setmetatable({
		folderName   = containerName or "PerformanceHeatmapContainer",
		BigModels    = {},
		MediumModels = {},
		-- last option passed to run(), so the panel can be restored on re-open
		lastOption   = nil,
		-- the highlight folder. Kept as a reference because while the panel is
		-- closed the folder lives outside Workspace (see detach/attach).
		_folder      = nil,
		-- cache MeshId -> triangles (or false if it can't be loaded). Persists across runs:
		-- reloading permission-less meshes on every click is just wasted time.
		_triCache    = {},
		colors = {
			Big    = Color3.fromRGB(255,   0,   0),
			Medium = Color3.fromRGB(255, 255,   0),
			Ok     = Color3.fromRGB(0,   255,   0),
		}
	}, HeatmapService)
	return self
end

-- creates (if needed) and returns the folder that holds the highlights.
-- Also re-attaches a folder that detach() moved out of Workspace.
function HeatmapService:ensureFolder()
	local f = self._folder or workspace:FindFirstChild(self.folderName)

	-- a folder the user deleted from the Explorer is locked: re-parenting it
	-- throws, so give up on it and build a fresh one
	if f and f.Parent ~= workspace and not pcall(function() f.Parent = workspace end) then
		f = nil
	end

	if not f then
		f = Instance.new("Folder")
		f.Name       = self.folderName
		f.Archivable = false
		f.Parent     = workspace
	end

	self._folder = f
	return f
end

-- Wipes results and the highlight folder itself (not just its children, so no
-- empty container is left behind in Workspace).
function HeatmapService:clear()
	local f = self._folder or workspace:FindFirstChild(self.folderName)
	if f then pcall(function() f:Destroy() end) end
	self._folder = nil
	self.BigModels, self.MediumModels = {}, {}
end

-- Called when the panel is closed: takes the highlight folder out of Workspace
-- so it stops cluttering the scene and the Explorer, but keeps it alive in
-- memory along with the result tables. Re-opening the panel in the same session
-- can then restore exactly what was there (see attach) with no re-analysis.
-- Nothing is written to disk or to plugin settings: this is session-only state.
function HeatmapService:detach()
	local f = self._folder or workspace:FindFirstChild(self.folderName)
	if not f then return end
	self._folder = f
	pcall(function() f.Parent = nil end)
end

-- Puts a detached highlight folder back into Workspace.
-- Returns true when there was something to restore.
function HeatmapService:attach()
	local f = self._folder
	if not f then return false end
	if f.Parent == workspace then return true end
	if not pcall(function() f.Parent = workspace end) then
		self._folder = nil
		return false
	end
	return true
end

-- Sorts both tables from the most severe to the least.
-- Entries carry an explicit numeric `Sort`, plus an optional `Group` for modes
-- that mix metrics which can't be compared with each other (Triangles: real
-- triangle counts vs. estimates). Higher Group comes first; ties fall back to
-- the name so the order never depends on Workspace traversal order.
-- Parsing `Amount` is only a fallback for entries that don't set `Sort`.
function HeatmapService:sortModels()
	local function weight(entry)
		if type(entry.Sort) == "number" then return entry.Sort end
		-- strip thousands separators ("12,345 tris" -> 12345) before reading the number
		local s = tostring(entry.Amount):gsub(",", "")
		return tonumber(string.match(s, "%d+%.?%d*")) or 0
	end

	local function comparator(a, b)
		local ga, gb = a.Group or 0, b.Group or 0
		if ga ~= gb then return ga > gb end
		local wa, wb = weight(a), weight(b)
		if wa ~= wb then return wa > wb end
		return a.Model.Name < b.Model.Name
	end

	table.sort(self.BigModels, comparator)
	table.sort(self.MediumModels, comparator)
end

-- builds a scaled UDim2, in case it's ever needed elsewhere
function HeatmapService.scaleUDim2(size, factor)
	return UDim2.new(
		size.X.Scale  * factor, size.X.Offset  * factor,
		size.Y.Scale  * factor, size.Y.Offset  * factor
	)
end

-- formats an integer with thousands separators (12345 -> "12,345")
function HeatmapService.commaNumber(n)
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Creates the highlight parts for a whole Model
function HeatmapService:createHighlight(model, color)
	local folder = self:ensureFolder()
	for _,desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			local h = Instance.new("Part")
			h.Size         = desc.Size + Vector3.new(1,1,1)
			h.CFrame       = desc.CFrame
			h.Anchored     = true
			h.CanCollide   = false
			h.Transparency = .5
			h.BrickColor   = BrickColor.new(color)
			h.Archivable   = false
			h.Parent       = folder
		end
	end
end

-- Highlights a BasePart directly (e.g. the MeshPart itself)
function HeatmapService:createHighlightPart(part, color)
	local h = Instance.new("Part")
	h.Size         = part.Size + Vector3.new(1,1,1)
	h.CFrame       = part.CFrame
	h.Anchored     = true
	h.CanCollide   = false
	h.Transparency = .5
	h.BrickColor   = BrickColor.new(color)
	h.Archivable   = false
	h.Parent       = self:ensureFolder()
end

-- Creates the highlight for objects such as lights or emitters
function HeatmapService:createHighlightInstance(obj, color)
	local p = obj.Parent
	if p and p:IsA("BasePart") then
		local h = Instance.new("Part")
		h.Size         = p.Size + Vector3.new(1,1,1)
		h.CFrame       = p.CFrame
		h.Anchored     = true
		h.CanCollide   = false
		h.Transparency = .5
		h.BrickColor   = BrickColor.new(color)
		h.Archivable   = false
		h.Parent       = self:ensureFolder()
	end
end

-- Analysis methods
function HeatmapService:density()
	for _,model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") then
			local count, vol = 0, 0
			for _,d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					vol  = vol + (d.Size.X * d.Size.Y * d.Size.Z)
					count = count + 1
				end
			end
			local dens       = (vol>0) and (count/vol) or 0
			local amtStr     = string.format("(Density: %.2f)", dens)
			local entry      = { Model = model, Amount = amtStr, Sort = dens }
			local col        = self.colors.Ok

			if dens < .5 then
				col = self.colors.Ok
			elseif dens < .8 then
				col = self.colors.Medium
				table.insert(self.MediumModels, entry)
			else
				col = self.colors.Big
				table.insert(self.BigModels, entry)
			end
			self:createHighlight(model, col)
		end
	end
end

function HeatmapService:count()
	for _,model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") then
			local c = 0
			for _,d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then c = c + 1 end
			end
			local amtStr = string.format("(%d Parts)", c)
			local entry  = { Model = model, Amount = amtStr, Sort = c }
			local col    = self.colors.Ok

			if c < 10 then
				col = self.colors.Ok
			elseif c < 50 then
				col = self.colors.Medium
				table.insert(self.MediumModels, entry)
			else
				col = self.colors.Big
				table.insert(self.BigModels, entry)
			end
			self:createHighlight(model, col)
		end
	end
end

function HeatmapService:lights()
	for _,obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
			if obj.Range and obj.Range > 0 then
				local score  = obj.Brightness * obj.Range
				local amtStr = string.format("(Score: %.2f)", score)
				local entry  = { Model = obj, Amount = amtStr, Sort = score }
				local col    = self.colors.Ok

				if score < 30 then
					col = self.colors.Ok
				elseif score < 100 then
					col = self.colors.Medium
					table.insert(self.MediumModels, entry)
				else
					col = self.colors.Big
					table.insert(self.BigModels, entry)
				end
				self:createHighlightInstance(obj, col)
			end
		end
	end
end

function HeatmapService:particles()
	for _,obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			local lt         = obj.Lifetime
			local avgLife    = (lt.Min + lt.Max) / 2
			local score      = obj.Rate * avgLife * obj.Brightness
			local amtStr     = string.format("(Score: %.2f)", score)
			local entry      = { Model = obj, Amount = amtStr, Sort = score }
			local col        = self.colors.Ok

			if score < 30 then
				col = self.colors.Ok
			elseif score < 100 then
				col = self.colors.Medium
				table.insert(self.MediumModels, entry)
			else
				col = self.colors.Big
				table.insert(self.BigModels, entry)
			end
			self:createHighlightInstance(obj, col)
		end
	end
end

-- Counts the real triangles of a MeshPart via EditableMesh.
-- Returns a number, or nil if the mesh can't be measured (permissions/format).
-- Results are cached per MeshId so each unique mesh loads only once.
function HeatmapService:meshTriangleCount(meshPart)
	self._triCache = self._triCache or {}

	local id = meshPart.MeshId
	local cacheKey = (id ~= nil and id ~= "") and id or nil
	if cacheKey and self._triCache[cacheKey] ~= nil then
		local c = self._triCache[cacheKey]
		return (c ~= false) and c or nil
	end

	local count
	local ok, em = pcall(function()
		local content
		if id ~= nil and id ~= "" then
			content = Content.fromUri(id)
		else
			content = meshPart.MeshContent -- newer MeshParts without a MeshId
		end
		return AssetService:CreateEditableMeshAsync(content)
	end)

	if ok and em then
		count = #em:GetFaces()
		em:Destroy() -- free immediately: EditableMeshes are memory-heavy
	else
		count = false -- not loadable (permissions/format)
	end

	if cacheKey then
		self._triCache[cacheKey] = count
	end
	return (count ~= false) and count or nil
end

-- Cost proxy for MeshParts that CAN'T be measured: uses only always-readable
-- properties (fidelity + size). It is NOT a triangle count, and is labelled
-- "est." accordingly -- we never pass a heuristic off as real data.
function HeatmapService:meshCostEstimate(part)
	local score   = part.Size.Magnitude / 10
	local reasons = {}

	if part.RenderFidelity == Enum.RenderFidelity.Precise then
		score = score + 6
		table.insert(reasons, "Render=Precise")
	elseif part.RenderFidelity == Enum.RenderFidelity.Automatic then
		score = score + 2
	end

	if part.CanCollide then
		if part.CollisionFidelity == Enum.CollisionFidelity.PreciseConvexDecomposition then
			score = score + 6
			table.insert(reasons, "Collision=Precise")
		elseif part.CollisionFidelity == Enum.CollisionFidelity.Default then
			score = score + 3
			table.insert(reasons, "Collision=Default")
		end
	end

	return score, reasons
end

-- MeshPart cost heatmap.
-- Where permissions allow it uses the REAL triangle count (EditableMesh);
-- otherwise it falls back to the estimate, so the list isn't empty on scenes
-- built from third-party assets (which is the common case).
function HeatmapService:triangles()
	local measured, estimated = 0, 0

	for _,obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("MeshPart") then
			local tris = self:meshTriangleCount(obj)
			local amtStr, bucket, sort, group

			if tris ~= nil then
				measured = measured + 1
				amtStr = string.format("(%s tris)", HeatmapService.commaNumber(tris))
				bucket = (tris < 2000 and "Ok") or (tris < 10000 and "Medium") or "Big"
				-- measured meshes rank above estimated ones: a triangle count and an
				-- estimate score are different units and can't be ordered together
				sort, group = tris, 1
			else
				estimated = estimated + 1
				local score, reasons = self:meshCostEstimate(obj)
				local why = (#reasons > 0) and (" · " .. table.concat(reasons, ", ")) or ""
				amtStr = string.format("(est. %.1f%s)", score, why)
				bucket = (score < 5 and "Ok") or (score < 12 and "Medium") or "Big"
				sort, group = score, 0
			end

			local entry = { Model = obj, Amount = amtStr, Sort = sort, Group = group }
			if bucket == "Big" then
				table.insert(self.BigModels, entry)
			elseif bucket == "Medium" then
				table.insert(self.MediumModels, entry)
			end
			self:createHighlightPart(obj, self.colors[bucket])
		end
	end

	if estimated > 0 then
		warn(string.format(
			"[Performance Heatmap] Triangles: %d MeshPart(s) measured, %d estimated. " ..
			"Meshes without read permission don't expose real triangles: " ..
			"the estimate uses RenderFidelity/CollisionFidelity/size.",
			measured, estimated
		))
	end
end

-- Dispatches to the right routine based on the option
function HeatmapService:run(option, mainUI)
	self:clear()
	self.lastOption = option
	if option == "Density"  then self:density()
	elseif option == "Count"    then self:count()
	elseif option == "Lights"   then self:lights()
	elseif option == "Particles"then self:particles()
	elseif option == "Triangles"then self:triangles()
	end
	self:sortModels()
end

return HeatmapService
