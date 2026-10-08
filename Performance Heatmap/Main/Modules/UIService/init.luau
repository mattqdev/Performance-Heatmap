-- UIService.luau -- everything that draws into the panel.

local UIService   = {}
UIService.__index = UIService

local StudioService = game:GetService("StudioService")
local Selection     = game:GetService("Selection")
local RunService    = game:GetService("RunService")
local Stats         = game:GetService("Stats")

local Properties = require(script.Properties)

-- Same palette as HeatmapService.colors; used when no colors are passed in.
local DEFAULT_COLORS = {
	Big    = Color3.fromRGB(255,   0,   0),
	Medium = Color3.fromRGB(255, 255,   0),
	Ok     = Color3.fromRGB(0,   255,   0),
}

-- Section titles are set from here rather than read from the place file. The
-- old labels ("BIG ELEMENTS" / "MEDIUM ELEMENTS") described the objects' size,
-- which is not what the buckets mean -- an item is in the top bucket because it
-- looks expensive, not because it is large.
local HEADER_TITLES = {
	HeaderBig    = "HIGH COST",
	HeaderMedium = "MODERATE",
}

function UIService.new(mouse, animModule, main, template, statsTemplate)
	local self = setmetatable({
		mouse         = mouse,
		anim          = animModule,
		mainUI        = main,
		template      = template,
		statsTemplate = statsTemplate,

		-- Stats rows are built once and then only have their text updated; see
		-- ensureStats. Maps Properties index -> the row's value label.
		_statRows  = nil,
		_statsBuilt = false,
	}, UIService)

	-- bind the menu Frame-buttons to their callbacks
	for _, button in ipairs(main.Body.Head:GetChildren()) do
		if button:IsA("Frame") then
			animModule.button(button, mouse)
			button.Click.MouseButton1Down:Connect(function()
				self:fire(button.Name)
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

-- Results list -------------------------------------------------------------

function UIService:refreshList(bigList, medList, colors)
	local list = self.mainUI.Body.List
	colors = colors or DEFAULT_COLORS

	for _, child in ipairs(list:GetChildren()) do
		if child.Name == "Template" then
			child:Destroy()
		end
	end

	-- Every child gets its own LayoutOrder, in the order it's created: the lists
	-- arrive already sorted by severity, and equal LayoutOrders would leave the
	-- final order up to the sibling order inside the ScrollingFrame.
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	-- The icon comes from the row's own instance, so a mode that reports mixed
	-- classes (Overlap and Texture both do) shows the right one per row instead
	-- of one class hard-coded for the whole mode.
	local function classIcon(instance)
		local ok, icon = pcall(function()
			return StudioService:GetClassIcon(instance.ClassName).Image
		end)
		return ok and icon or ""
	end

	local function makeRow(entry, color)
		local row = self.template:Clone()
		row.Parent            = list
		row.Title.Text        = entry.Instance.Name
		row.Amount.Text       = entry.Amount
		row.Amount.TextColor3 = color
		row.Icon.Image        = classIcon(entry.Instance)
		row.LayoutOrder       = nextOrder()

		self.anim.hover(row.View, row.View)
		self.anim.Click(row.View, row.View)
		row.View.MouseButton1Down:Connect(function()
			Selection:Set({ entry.Instance })
		end)
	end

	local function makeHeader(headerName, count)
		local header = list:FindFirstChild(headerName)
		if not header then
			return
		end
		header.LayoutOrder = nextOrder()

		local label = header:FindFirstChild("Title")
		if label then
			label.Text = string.format("%s (%d)", HEADER_TITLES[headerName] or headerName, count)
		end
	end

	makeHeader("HeaderBig", #bigList)
	for _, entry in ipairs(bigList) do
		makeRow(entry, colors.Big)
	end

	makeHeader("HeaderMedium", #medList)
	for _, entry in ipairs(medList) do
		makeRow(entry, colors.Medium)
	end
end

-- Stats panel --------------------------------------------------------------

-- In edit mode the Stats service reports *Studio*, not your game: frame and
-- render timings include the editor viewport, the selection gizmos and every
-- dock widget, and bandwidth is whatever Studio is talking to. Those rows are
-- built greyed out with a note, rather than being coloured against a budget they
-- have no relationship to.
local function isPlaying()
	return RunService:IsRunning()
end

local function meaningfulHere(row)
	return not row.PlayOnly or isPlaying()
end

-- Green up to `Good`, yellow up to `Warn`, red past it (reversed when
-- HigherIsBetter). Rows without thresholds keep the template's neutral colour.
-- These budgets are rules of thumb, not engine limits: red means "worth a look",
-- not "broken".
local function valueColor(row, value, colors)
	if type(row.Good) ~= "number" or type(row.Warn) ~= "number" then
		return nil
	end
	if row.HigherIsBetter then
		if value >= row.Good then return colors.Ok end
		if value >= row.Warn then return colors.Medium end
		return colors.Big
	end
	if value <= row.Good then return colors.Ok end
	if value <= row.Warn then return colors.Medium end
	return colors.Big
end

local function readStat(name)
	local ok, value = pcall(function()
		return Stats[name]
	end)
	return (ok and type(value) == "number") and value or nil
end

-- Builds the rows once. The old code destroyed and recreated all ~22 rows and
-- rebound all ~22 property signals every 0.1s -- several hundred instances per
-- second of pure churn for a panel whose layout never changes.
function UIService:ensureStats(mainUI, template)
	if self._statsBuilt then
		return
	end

	local statsFrame = mainUI.Body.Stats

	for _, child in ipairs(statsFrame:GetChildren()) do
		if child.Name == "Stat" or child.Name == "Divider" then
			child:Destroy()
		end
	end

	self._statRows = {}

	for index, row in ipairs(Properties) do
		if row.Divider then
			local header = script.Divider:Clone()
			header.Title.Text  = row.Title
			header.LayoutOrder = index
			header.Parent      = statsFrame
		else
			local widget = template:Clone()
			widget.Name        = "Stat"
			widget.LayoutOrder = index
			widget.Parent      = statsFrame

			widget.Container.Title.Text = row.Name

			table.insert(self._statRows, {
				data        = row,
				label       = widget.Amount,
				description = widget.Container.Desc,
			})
		end
	end

	self._statsBuilt = true
	self:_applyDescriptions()
end

-- The PlayOnly note has to follow the Studio play state, because a plugin keeps
-- running across Play Solo -- a panel still saying "edit mode" once the game is
-- running would be its own small lie. Only rewritten when the state flips.
function UIService:_applyDescriptions()
	local playing = isPlaying()
	if self._descriptionsFor == playing then
		return
	end
	self._descriptionsFor = playing

	for _, entry in ipairs(self._statRows) do
		entry.description.Text = meaningfulHere(entry.data)
			and entry.data.Description
			or (entry.data.Description .. " (edit mode: this is Studio, not your game)")
	end
end

-- Cheap per-tick refresh: sets two properties per row, creates nothing.
function UIService:updateStats(colors)
	if not self._statRows then
		return
	end
	colors = colors or DEFAULT_COLORS
	self:_applyDescriptions()

	for _, entry in ipairs(self._statRows) do
		local value = readStat(entry.data.Name)

		if value == nil then
			entry.label.Text = "n/a"
		else
			entry.label.Text = tostring(math.floor(value * 10000 + 0.5) / 10000)

			if meaningfulHere(entry.data) then
				local color = valueColor(entry.data, value, colors)
				if color then
					entry.label.TextColor3 = color
				end
			end
		end
	end
end

return UIService
