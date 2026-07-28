-- Modules/UIService.lua
local UIService    = {}
UIService.__index  = UIService

local StudioService = game:GetService("StudioService")
local Selection     = game:GetService("Selection")
local STATS = game:GetService("Stats")

local FetchProp = require(script.Properties)

local connections = {}

-- Same palette as HeatmapService.colors; used when no colors are passed in.
local DEFAULT_COLORS = {
	Big    = Color3.fromRGB(255,   0,   0),
	Medium = Color3.fromRGB(255, 255,   0),
	Ok     = Color3.fromRGB(0,   255,   0),
}

-- The section headers live in the plugin's GUI, so their Text may already carry
-- a count from a previous session that got saved into the place file: strip it
-- before using it as the base label.
local function baseTitle(label)
	return (label.Text:gsub("%s*%(%d+%)%s*$", ""))
end

function UIService.new(mouse, animModule, main, template, Statstemp)
	local self = setmetatable({
		mouse     = mouse,
		anim      = animModule,
		mainUI    = main,
		template  = template,
		statsTemplate  = Statstemp,
		-- header name -> label text without the count suffix
		headerTitles   = {},
	}, UIService)

	for _,headerName in ipairs({ "HeaderBig", "HeaderMedium" }) do
		local header = main.Body.List:FindFirstChild(headerName)
		if header and header:FindFirstChild("Title") then
			self.headerTitles[headerName] = baseTitle(header.Title)
		end
	end

	-- bind the menu Frame-buttons to their callbacks
	for _,btn in ipairs(main.Body.Head:GetChildren()) do
		if btn:IsA("Frame") then
			animModule.button(btn, mouse)
			btn.Click.MouseButton1Down:Connect(function()
				self:fire(btn.Name)
			end)
		end
	end

	return self
end

function UIService:onOptionSelected(fn)
	self._onSelect = fn
end

function UIService:fire(option)
	if self._onSelect then
		self._onSelect(option)
	end
end

-- Modules/UIService.lua
function UIService:refreshList(bigList, medList, instanceClass, colors)
	local list = self.mainUI.Body.List
	colors = colors or DEFAULT_COLORS

	-- clear the list
	for _,child in ipairs(list:GetChildren()) do
		if child.Name == "Template" then child:Destroy() end
	end

	-- Every child gets its own LayoutOrder, in the order it's created: the lists
	-- arrive already sorted by severity, and equal LayoutOrders would leave the
	-- final order up to the sibling order inside the ScrollingFrame.
	local order = 0
	local function nextOrder()
		order = order + 1
		return order
	end

	local function mkRow(data, color)
		local row = self.template:Clone()
		row.Parent            = list
		row.Title.Text        = data.Model.Name
		row.Amount.Text       = data.Amount
		row.Amount.TextColor3 = color
		row.Icon.Image        = StudioService:GetClassIcon(instanceClass).Image
		row.LayoutOrder       = nextOrder()

		self.anim.hover(row.View, row.View)
		self.anim.Click(row.View, row.View)
		row.View.MouseButton1Down:Connect(function()
			Selection:Set({ data.Model })
		end)
	end

	-- places the section header and shows how many items it holds
	local function mkHeader(headerName, count)
		local header = list:FindFirstChild(headerName)
		if not header then return end
		header.LayoutOrder = nextOrder()

		local label = header:FindFirstChild("Title")
		if label then
			local base = self.headerTitles[headerName] or baseTitle(label)
			self.headerTitles[headerName] = base
			label.Text = string.format("%s (%d)", base, count)
		end
	end

	-- use the colors passed in from HeatmapService
	mkHeader("HeaderBig", #bigList)
	for _,r in ipairs(bigList) do mkRow(r, colors.Big) end

	mkHeader("HeaderMedium", #medList)
	for _,r in ipairs(medList) do mkRow(r, colors.Medium) end
end

function UIService:createStats(mainUI, template, colors)
	local statsFrame = mainUI.Body.Stats
	colors = colors or DEFAULT_COLORS

	-- 1) Clear the container (stat and divider rows)
	for _, child in ipairs(statsFrame:GetChildren()) do
		if child.Name == "Stat" or child.Name == "Divider" then
			child:Destroy()
		end
	end

	-- 2) Visual index for the value: green up to `Good`, yellow up to `Warn`,
	-- red beyond it (reversed when HigherIsBetter). Rows in Properties.luau
	-- without thresholds keep the template's neutral color -- these budgets are
	-- rules of thumb, not engine limits, so a red row means "worth a look",
	-- not "broken".
	local function valueColor(data, val)
		if type(data.Good) ~= "number" or type(data.Warn) ~= "number" then
			return nil
		end
		if data.HigherIsBetter then
			if val >= data.Good then return colors.Ok end
			if val >= data.Warn then return colors.Medium end
			return colors.Big
		end
		if val <= data.Good then return colors.Ok end
		if val <= data.Warn then return colors.Medium end
		return colors.Big
	end

	-- 3) Helper to round to 4 decimals
	local function setValueLabel(row, data, val)
		local mult = 10 ^ 4
		row.Amount.Text = tostring(math.floor(val * mult + 0.5) / mult)

		local color = valueColor(data, val)
		if color then
			row.Amount.TextColor3 = color
		end
	end

	-- 4) Iterate over FetchProp
	for i, data in ipairs(FetchProp) do
		if data.Divider then
			-- create a simple TextLabel as a divider
			local hdr = script.Divider:Clone()
			hdr.Title.Text               = data.Title
			hdr.LayoutOrder        = i
			hdr.Parent             = statsFrame
		else
			-- create the Stat row
			local row = template:Clone()
			row.Name               = "Stat"
			row.Parent             = statsFrame
			row.LayoutOrder        = i

			-- set titles and description
			row.Container.Title.Text = data.Name
			row.Container.Desc.Text  = data.Description

			-- initial value
			setValueLabel(row, data, STATS[data.Name])

			-- bind the signal, disconnecting any previous connection
			if connections[data.Name] then
				connections[data.Name]:Disconnect()
			end
			connections[data.Name] = STATS:GetPropertyChangedSignal(data.Name)
				:Connect(function()
					setValueLabel(row, data, STATS[data.Name])
				end)
		end
	end
end


return UIService
