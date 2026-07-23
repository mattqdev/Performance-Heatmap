-- Main.local.luau (sotto il tuo Plugin object)
local plugin = plugin

-- 1) carico i moduli (prima di tutto: la versione arriva da Version.luau)
local Modules       = script:WaitForChild("Modules", 30)
local Anim          = require(Modules:WaitForChild("Anim",          10))
local UIService     = require(Modules:WaitForChild("UIService",     10))
local HeatmapSvc    = require(Modules:WaitForChild("HeatmapService", 10))
local Version       = require(Modules:WaitForChild("Version",       10))
local UpdateChecker = require(Modules:WaitForChild("UpdateChecker",  10))

-- la versione è ora incorporata nel codice (Version.current), non più in uno StringValue
local name = script.Parent.Name .. " v" .. Version.current

-- 2) TOOLBAR + BUTTON (gestiti qui)
local toolbar       = plugin:CreateToolbar(name)
local toggleButton = toolbar:CreateButton(
	"Toggle Heatmap",
	"Toggle Performance Heatmap",
	"rbxassetid://128855426371963"
)
toggleButton.ClickableWhenViewportHidden = true

-- 3) DOCK WIDGET (gestito qui)
local dockInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Left,
	false, false,    -- inizialmente disabilitato, non override
	153, 300,        -- width/height default
	153, 300         -- min width/height
)
local widget = plugin:CreateDockWidgetPluginGui(name, dockInfo)
widget.Title   = name
widget.Enabled = false

-- 4) sposto dentro al widget le GUI-frame che hai creato in Explorer
local mainUI   = script:WaitForChild("MainUI", 30)
local bg       = script:WaitForChild("BG",     30)
local template = script:WaitForChild("Template",30)
local statsTemplate = script:WaitForChild("Stat",30)
local statslist = mainUI:WaitForChild("Body"):WaitForChild("Stats")
mainUI.Parent   = widget
bg.Parent       = widget

-- 5) instanzio i servizi, passando mouse, animazioni e riferimenti UI
local ui      = UIService.new(plugin:GetMouse(), Anim, mainUI, template, statsTemplate)
local heatmap = HeatmapSvc.new("PerformanceHeatmapContainer")

-- 6) controllo aggiornamenti (non bloccante, non fatale)
task.spawn(function()
	local res = UpdateChecker.check()
	if res.ok and res.updateAvailable then
		warn(string.format(
			"[%s] Nuova versione disponibile: v%s (installata: v%s). Aggiorna su %s",
			name, res.latest, res.current, res.url or "Creator Store"
		))
		widget.Title = name .. "  •  Update available (v" .. tostring(res.latest) .. ")"
	elseif not res.ok then
		warn(string.format("[%s] Controllo aggiornamenti non riuscito: %s", name, tostring(res.error)))
	end
end)

-- 7) quando seleziono un’opzione nel menu…
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

-- 8) togglo la visibilità del widget
toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if not widget.Enabled then
		heatmap:clear()
	end
end)
