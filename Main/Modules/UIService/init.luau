-- Modules/UIService.lua
local UIService    = {}
UIService.__index  = UIService

local StudioService = game:GetService("StudioService")
local Selection     = game:GetService("Selection")
local STATS = game:GetService("Stats")

local FetchProp = require(script.Properties)

local connections = {}

function UIService.new(mouse, animModule, main, template, Statstemp)
	local self = setmetatable({
		mouse     = mouse,
		anim      = animModule,
		mainUI    = main,
		template  = template,
		statsTemplate  = Statstemp,
	}, UIService)


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
	-- clear the list
	for _,child in ipairs(self.mainUI.Body.List:GetChildren()) do
		if child.Name == "Template" then child:Destroy() end
	end

	local function mkRow(data, color, order)
		local row = self.template:Clone()
		row.Parent            = self.mainUI.Body.List
		row.Title.Text        = data.Model.Name
		row.Amount.Text       = data.Amount
		row.Amount.TextColor3 = color
		row.Icon.Image        = StudioService:GetClassIcon(instanceClass).Image
		row.LayoutOrder       = order

		self.anim.hover(row.View, row.View)
		self.anim.Click(row.View, row.View)
		row.View.MouseButton1Down:Connect(function()
			Selection:Set({ data.Model })
		end)
	end

	-- use the colors passed in from HeatmapService
	for _,r in ipairs(bigList) do mkRow(r, colors.Big,    1) end
	for _,r in ipairs(medList) do mkRow(r, colors.Medium, 2) end
end

function UIService:createStats(mainUI, template)
	local statsFrame = mainUI.Body.Stats

	-- 1) Clear the container (stat and divider rows)
	for _, child in ipairs(statsFrame:GetChildren()) do
		if child.Name == "Stat" or child.Name == "Divider" then
			child:Destroy()
		end
	end

	-- 3) Helper to round to 4 decimals
	local function setValueLabel(row, val)
		local mult = 10 ^ 4
		row.Amount.Text = tostring(math.floor(val * mult + 0.5) / mult)
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
			setValueLabel(row, STATS[data.Name])

			-- bind the signal, disconnecting any previous connection
			if connections[data.Name] then
				connections[data.Name]:Disconnect()
			end
			connections[data.Name] = STATS:GetPropertyChangedSignal(data.Name)
				:Connect(function()
					setValueLabel(row, STATS[data.Name])
				end)
		end
	end
end


return UIService
