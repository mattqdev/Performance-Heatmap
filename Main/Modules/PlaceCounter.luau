-- PlaceCounter.luau
-- Counts the Instances that belong to the *place*, as opposed to
-- Stats.InstanceCount, which counts every Instance in the process.
--
-- Stats.InstanceCount is honest but rarely what people think it is: in Studio
-- it includes the editor's own UI, CoreGui, every installed plugin's widgets and
-- the engine's internal services, so an empty baseplate already reads tens of
-- thousands. None of that ships with the game, and none of it can be reduced
-- from the place. This counter covers only the services a place's content lives
-- in, so it answers the question people are actually asking.
--
-- Counted once with GetDescendants, then kept current from DescendantAdded /
-- DescendantRemoving, so a read is O(1) and the stats loop can poll it every
-- tick. The plugin's own highlights live in CoreGui, which is not counted:
-- nothing the plugin measures may include itself.

local PlaceCounter = {}
PlaceCounter.__index = PlaceCounter

-- Where a place's own content lives. Players is included for play mode
-- (characters, PlayerGui); in edit mode it's empty.
local SERVICES = {
	"Workspace",
	"Players",
	"Lighting",
	"MaterialService",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"SoundService",
	"Teams",
	"TextChatService",
	"Chat",
}

function PlaceCounter.new()
	return setmetatable({
		count        = 0,
		_started     = false,
		_connections = {},
	}, PlaceCounter)
end

-- Lazy: only pays for the initial walk once the Stats panel is actually shown.
function PlaceCounter:start()
	if self._started then
		return
	end
	self._started = true

	for _, serviceName in ipairs(SERVICES) do
		-- a service may not exist, or not be readable, in every DataModel
		local ok, service = pcall(game.FindService, game, serviceName)
		if ok and service then
			local counted, descendants = pcall(service.GetDescendants, service)
			if counted then
				self.count += #descendants
			end

			table.insert(self._connections, service.DescendantAdded:Connect(function()
				self.count += 1
			end))
			table.insert(self._connections, service.DescendantRemoving:Connect(function()
				self.count -= 1
			end))
		end
	end
end

function PlaceCounter:get(): number?
	return self._started and self.count or nil
end

function PlaceCounter:stop()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._started = false
	self.count    = 0
end

return PlaceCounter
