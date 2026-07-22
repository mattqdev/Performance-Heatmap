local HeatmapService = {}
HeatmapService.__index = HeatmapService

local workspace       = game:GetService("Workspace")
local StudioService   = game:GetService("StudioService")

local UIService = require(script.Parent.UIService)

function HeatmapService.new(containerName)
	local self = setmetatable({
		folderName   = containerName or "PerformanceHeatmapContainer",
		BigModels    = {},
		MediumModels = {},
		colors = {
			Big    = Color3.fromRGB(255,   0,   0),
			Medium = Color3.fromRGB(255, 255,   0),
			Ok     = Color3.fromRGB(0,   255,   0),
		}
	}, HeatmapService)
	return self
end

-- crea (se serve) e restituisce la cartella dove mettere gli highlight
function HeatmapService:ensureFolder()
	local f = workspace:FindFirstChild(self.folderName)
	if not f then
		f = Instance.new("Folder")
		f.Name       = self.folderName
		f.Archivable = false
		f.Parent     = workspace
	end
	return f
end

function HeatmapService:clear()
	local f = workspace:FindFirstChild(self.folderName)
	if f then for _,c in ipairs(f:GetChildren()) do c:Destroy() end end
	self.BigModels, self.MediumModels = {}, {}
end

-- ordina le due tabelle in base al valore numerico estratto da Amount
function HeatmapService:sortModels()
	local function extract(str)
		return tonumber(string.match(str, "([%d%.]+)")) or 0
	end
	table.sort(self.BigModels, function(a,b) return extract(a.Amount) > extract(b.Amount) end)
	table.sort(self.MediumModels, function(a,b) return extract(a.Amount) > extract(b.Amount) end)
end

-- costruisce un UDim2 scalato, se mai ti servisse altrove
function HeatmapService.scaleUDim2(size, factor)
	return UDim2.new(
		size.X.Scale  * factor, size.X.Offset  * factor,
		size.Y.Scale  * factor, size.Y.Offset  * factor
	)
end

-- Crea i pezzi evidenziati per un Model intero
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

-- Crea l’highlight per oggetti tipo luci o emitter
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

-- Metodi di analisi
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
			local entry      = { Model = model, Amount = amtStr }
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
			local entry  = { Model = model, Amount = amtStr }
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
				local entry  = { Model = obj, Amount = amtStr }
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
			local entry      = { Model = obj, Amount = amtStr }
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

-- In base all’opzione chiama la routine giusta
function HeatmapService:run(option, mainUI)
	self:clear()
	if option == "Density"  then self:density()
	elseif option == "Count"    then self:count()
	elseif option == "Lights"   then self:lights()
	elseif option == "Particles"then self:particles()
	end
	self:sortModels()
end

return HeatmapService
