-- WorkspaceIndex.luau
-- One traversal of Workspace, shared by every analyzer.
--
-- The old analyzers each called workspace:GetDescendants(), and the Model modes
-- then called GetDescendants() again per Model -- quadratic on nested rigs, and
-- a part inside a Model inside a Model was counted once for every ancestor, so
-- the map Model always came out as the single worst offender (true, and
-- useless). Here each part is attributed to its *nearest* Model ancestor
-- (`direct`), with the inclusive figure kept alongside it (`total`) purely for
-- display.
--
-- Everything is budgeted: pass a Budget and the build yields cooperatively and
-- aborts on cancellation (returning nil).

local Workspace = game:GetService("Workspace")

local WorkspaceIndex = {}
WorkspaceIndex.__index = WorkspaceIndex

-- Image properties are `Content` on current engine versions and plain strings on
-- older ones; normalise both to a comparable asset URI.
local function toUri(value)
	if value == nil then
		return nil
	end
	if type(value) == "string" then
		return (value ~= "" and value) or nil
	end
	local ok, uri = pcall(function()
		return value.Uri
	end)
	if ok and type(uri) == "string" and uri ~= "" then
		return uri
	end
	return nil
end

local SURFACE_MAPS = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" }

-- MeshPart carries its texture on TextureID (legacy) or TextureContent (current),
-- and which of the two exists depends on the engine version, so read both
-- defensively rather than assuming either.
local MESH_TEXTURE_PROPERTIES = { "TextureID", "TextureContent" }

local function readProperty(instance, property)
	local ok, value = pcall(function()
		return instance[property]
	end)
	return ok and value or nil
end

function WorkspaceIndex.new()
	return setmetatable({
		parts     = {},   -- every BasePart
		meshParts = {},   -- MeshParts only
		lights    = {},   -- PointLight / SpotLight / SurfaceLight
		emitters  = {},   -- ParticleEmitter
		models    = {},   -- array of model records, see _modelRecord
		modelOf   = {},   -- Model -> record

		-- texture bookkeeping: `textured` is the per-object view the Texture mode
		-- iterates (stable order), `textureUsage` is assetUri -> how many objects
		-- reference it, which is what tells a one-off texture from a reused one.
		textured     = {},
		texturedOf   = {},
		textureUsage = {},
		uniqueTextures = 0,

		instanceCount = 0,
	}, WorkspaceIndex)
end

function WorkspaceIndex:_modelRecord(model)
	local record = self.modelOf[model]
	if not record then
		record = { Model = model, direct = 0, total = 0, volume = 0 }
		self.modelOf[model] = record
		table.insert(self.models, record)
	end
	return record
end

-- Walks up from a part, adding it to every Model ancestor's inclusive count and
-- to the nearest one's direct count.
function WorkspaceIndex:_attributePart(part)
	local volume  = part.Size.X * part.Size.Y * part.Size.Z
	local nearest = true
	local node    = part.Parent

	while node and node ~= Workspace and node ~= game do
		if node:IsA("Model") then
			local record = self:_modelRecord(node)
			record.total += 1
			if nearest then
				record.direct += 1
				record.volume += volume
				nearest = false
			end
		end
		node = node.Parent
	end
end

function WorkspaceIndex:_addTexture(owner, uri)
	if not owner or not uri then
		return
	end

	local uris = self.texturedOf[owner]
	if not uris then
		uris = {}
		self.texturedOf[owner] = uris
		table.insert(self.textured, { Object = owner, Uris = uris })
	end

	-- the same image on the same object (front and back Decal) is one asset
	for _, existing in ipairs(uris) do
		if existing == uri then
			return
		end
	end
	table.insert(uris, uri)

	local seen = self.textureUsage[uri]
	if seen then
		self.textureUsage[uri] = seen + 1
	else
		self.textureUsage[uri] = 1
		self.uniqueTextures += 1
	end
end

-- Nearest BasePart at or above `instance` -- a Decal's owner, a SurfaceAppearance's
-- MeshPart, and so on.
local function ownerPart(instance)
	local node = instance
	while node and node ~= game do
		if node:IsA("BasePart") then
			return node
		end
		node = node.Parent
	end
	return nil
end

function WorkspaceIndex:_classify(instance)
	if instance:IsA("BasePart") then
		table.insert(self.parts, instance)
		self:_attributePart(instance)

		if instance:IsA("MeshPart") then
			table.insert(self.meshParts, instance)
			for _, property in ipairs(MESH_TEXTURE_PROPERTIES) do
				self:_addTexture(instance, toUri(readProperty(instance, property)))
			end
		end

	elseif instance:IsA("Light") then
		table.insert(self.lights, instance)

	elseif instance:IsA("ParticleEmitter") then
		table.insert(self.emitters, instance)
		self:_addTexture(ownerPart(instance), toUri(instance.Texture))

	elseif instance:IsA("Decal") then
		-- Texture is a subclass of Decal, so this covers both
		self:_addTexture(ownerPart(instance), toUri(instance.Texture))

	elseif instance:IsA("SurfaceAppearance") then
		local owner = ownerPart(instance)
		for _, property in ipairs(SURFACE_MAPS) do
			local ok, value = pcall(function()
				return instance[property]
			end)
			if ok then
				self:_addTexture(owner, toUri(value))
			end
		end
	end
end

-- Builds the index. Returns nil if the budget was cancelled mid-scan.
function WorkspaceIndex.build(budget)
	local self = WorkspaceIndex.new()

	local descendants = Workspace:GetDescendants()
	self.instanceCount = #descendants

	budget:setPhase("Indexing", self.instanceCount)

	for _, instance in ipairs(descendants) do
		self:_classify(instance)
		if not budget:step() then
			return nil
		end
	end

	return self
end

return WorkspaceIndex
