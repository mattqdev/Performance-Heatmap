-- Main.local.luau (under your Plugin object)
-- Entry point: owns every Studio plugin API call and wires the modules together.
local plugin = plugin

-- 1) load the modules (first of all: the version comes from Version.luau)
local Modules       = script:WaitForChild("Modules", 30)
local Anim          = require(Modules:WaitForChild("Anim",           10))
local UIService     = require(Modules:WaitForChild("UIService",      10))
local HeatmapSvc    = require(Modules:WaitForChild("HeatmapService", 10))
local Version       = require(Modules:WaitForChild("Version",        10))
local UpdateChecker = require(Modules:WaitForChild("UpdateChecker",  10))

-- the version is baked into the code (Version.current), not read from a
-- StringValue in the place file
local name = script.Parent.Name .. " v" .. Version.current

-- 2) TOOLBAR + BUTTON
local toolbar      = plugin:CreateToolbar(name)
local toggleButton = toolbar:CreateButton(
	"Toggle Heatmap",
	"Toggle Performance Heatmap",
	"rbxassetid://128855426371963"
)
toggleButton.ClickableWhenViewportHidden = true

-- 3) DOCK WIDGET
local dockInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Left,
	false, false,    -- initially disabled, no override
	153, 300,        -- default width/height
	153, 300         -- min width/height
)
local widget = plugin:CreateDockWidgetPluginGui(name, dockInfo)
widget.Title   = name
widget.Enabled = false

-- The widget title is the only piece of panel chrome that lives in code rather
-- than in the place file, so it doubles as the status line: update notice while
-- idle, scan progress while a scan runs.
local idleTitle = name

local function setStatus(text)
	widget.Title = text and (idleTitle .. "  •  " .. text) or idleTitle
end

-- 4) move the GUI frames you created in Explorer into the widget
local mainUI        = script:WaitForChild("MainUI",   30)
local bg            = script:WaitForChild("BG",       30)
local template      = script:WaitForChild("Template", 30)
local statsTemplate = script:WaitForChild("Stat",     30)
local statsList     = mainUI:WaitForChild("Body"):WaitForChild("Stats")
mainUI.Parent = widget
bg.Parent     = widget

-- 5) instantiate the services
local ui      = UIService.new(plugin:GetMouse(), Anim, mainUI, template, statsTemplate)
local heatmap = HeatmapSvc.new({ folderName = "PerformanceHeatmapAdornments" })

-- 6) update check (non-blocking, non-fatal)
task.spawn(function()
	local result = UpdateChecker.check()
	if result.ok and result.updateAvailable then
		warn(string.format(
			"[%s] New version available: v%s (installed: v%s). Update at %s",
			name, result.latest, result.current, result.url or "Creator Store"
		))
		idleTitle = name .. "  •  Update available (v" .. tostring(result.latest) .. ")"
		if not heatmap.scanning then
			widget.Title = idleTitle
		end
	elseif not result.ok then
		warn(string.format("[%s] Update check failed: %s", name, tostring(result.error)))
	end
end)

-- 7) when an option is selected in the menu...
ui:onOptionSelected(function(option)
	local showingStats = (option == "Stats")
	mainUI.Body.List.Visible = not showingStats
	statsList.Visible        = showingStats

	if showingStats then
		return
	end

	-- Progress goes to the widget title. A scan on a large place takes seconds,
	-- and the alternative -- a frozen Studio with no feedback and no way out --
	-- is what made the old scans feel broken.
	local completed = heatmap:run(option, function(label, done, total)
		if total > 0 then
			setStatus(string.format("%s %d%%", label, math.floor(done / total * 100)))
		else
			setStatus(label .. "…")
		end
	end)

	setStatus(nil)

	-- a superseded scan already has a newer one repainting the list behind it
	if not completed then
		return
	end

	ui:refreshList(heatmap.BigModels, heatmap.MediumModels, heatmap.colors)

	if heatmap.lastSummary then
		warn("[Performance Heatmap] " .. heatmap.lastSummary)
	end

	local skipped = heatmap:skippedHighlights()
	if skipped > 0 then
		warn(string.format(
			"[Performance Heatmap] %d further result(s) are listed but not highlighted: " ..
			"painting a whole scene red makes nothing stand out. The list is complete.",
			skipped
		))
	end
end)

-- Stats panel: built once, then only its values are refreshed.
local statsRunning = true
task.spawn(function()
	while statsRunning do
		if widget.Enabled and statsList.Visible then
			ui:ensureStats(mainUI, statsTemplate)
			ui:updateStats(heatmap.colors)
		end
		task.wait(0.1)
	end
end)

-- 8) toggle the widget's visibility
toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

-- Closing the panel hides the highlights, and the widget can also be closed from
-- its own X button (which never fires the toolbar Click), so both cases hang off
-- Enabled itself. Re-opening within the same session restores the highlights and
-- the list as they were -- handy when the panel gets closed by accident. This
-- lives purely in memory: nothing is saved to plugin settings.
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	heatmap:setVisible(widget.Enabled)

	if widget.Enabled and heatmap:hasResults() then
		ui:refreshList(heatmap.BigModels, heatmap.MediumModels, heatmap.colors)
	end
end)

-- The adornments only live as long as this script: drop them (and cancel any
-- scan still in flight) when the plugin unloads or reloads.
plugin.Unloading:Connect(function()
	statsRunning = false
	heatmap:clear()
end)
