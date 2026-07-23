-- Main.local.luau (under your Plugin object)
local plugin = plugin

-- 1) load the modules (first of all: the version comes from Version.luau)
local Modules       = script:WaitForChild("Modules", 30)
local Anim          = require(Modules:WaitForChild("Anim",          10))
local UIService     = require(Modules:WaitForChild("UIService",     10))
local HeatmapSvc    = require(Modules:WaitForChild("HeatmapService", 10))
local Version       = require(Modules:WaitForChild("Version",       10))
local UpdateChecker = require(Modules:WaitForChild("UpdateChecker",  10))

-- the version is now baked into the code (Version.current), no longer a StringValue
local name = script.Parent.Name .. " v" .. Version.current

-- 2) TOOLBAR + BUTTON (handled here)
local toolbar       = plugin:CreateToolbar(name)
local toggleButton = toolbar:CreateButton(
	"Toggle Heatmap",
	"Toggle Performance Heatmap",
	"rbxassetid://128855426371963"
)
toggleButton.ClickableWhenViewportHidden = true

-- 3) DOCK WIDGET (handled here)
local dockInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Left,
	false, false,    -- initially disabled, no override
	153, 300,        -- default width/height
	153, 300         -- min width/height
)
local widget = plugin:CreateDockWidgetPluginGui(name, dockInfo)
widget.Title   = name
widget.Enabled = false

-- 4) move the GUI frames you created in Explorer into the widget
local mainUI   = script:WaitForChild("MainUI", 30)
local bg       = script:WaitForChild("BG",     30)
local template = script:WaitForChild("Template",30)
local statsTemplate = script:WaitForChild("Stat",30)
local statslist = mainUI:WaitForChild("Body"):WaitForChild("Stats")
mainUI.Parent   = widget
bg.Parent       = widget

-- 5) instantiate the services, passing mouse, animations and UI references
local ui      = UIService.new(plugin:GetMouse(), Anim, mainUI, template, statsTemplate)
local heatmap = HeatmapSvc.new("PerformanceHeatmapContainer")

-- 6) update check (non-blocking, non-fatal)
task.spawn(function()
	local res = UpdateChecker.check()
	if res.ok and res.updateAvailable then
		warn(string.format(
			"[%s] New version available: v%s (installed: v%s). Update at %s",
			name, res.latest, res.current, res.url or "Creator Store"
		))
		widget.Title = name .. "  •  Update available (v" .. tostring(res.latest) .. ")"
	elseif not res.ok then
		warn(string.format("[%s] Update check failed: %s", name, tostring(res.error)))
	end
end)

-- 7) when an option is selected in the menu...
ui:onOptionSelected(function(option)
	mainUI.Body.List.Visible = not (option == "Stats")
	statslist.Visible = (option == "Stats")

	heatmap:run(option)

	local cls = (option == "Lights"    and "PointLight")
		or (option == "Particles" and "ParticleEmitter")
		or (option == "Triangles" and "MeshPart")
		or "Model"

	ui:refreshList(
		heatmap.BigModels,
		heatmap.MediumModels,
		cls,
		heatmap.colors
	)
end)

task.spawn(function()
	while true do
		UIService:createStats(mainUI, statsTemplate)
		task.wait(0.1)
	end
end)

-- 8) toggle the widget's visibility
toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if not widget.Enabled then
		heatmap:clear()
	end
end)
