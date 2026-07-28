-- HeatmapService.luau
-- Orchestrates a scan: build the shared index once, hand it to the selected
-- analyzer, bucket and sort what comes back, then paint the worst offenders.
--
-- The analysis itself lives in Modules/Analyzers/*, the drawing in
-- Modules/Highlighter, the traversal in Modules/WorkspaceIndex. This file only
-- sequences them and owns the run lifecycle (progress, cancellation, results).

local HeatmapService = {}
HeatmapService.__index = HeatmapService

local Analyzers      = require(script.Parent.Analyzers)
local Budget         = require(script.Parent.Budget)
local Highlighter    = require(script.Parent.Highlighter)
local WorkspaceIndex = require(script.Parent.WorkspaceIndex)

function HeatmapService.new(options)
	options = options or {}

	local self = setmetatable({
		BigModels    = {},
		MediumModels = {},

		-- last mode passed to run(), so re-opening the panel can re-render
		lastOption = nil,
		-- last analyzer summary, re-warned on demand rather than on every render
		lastSummary = nil,

		scanning = false,

		-- bumped on every run; a scan whose token is stale must not write results
		_token   = 0,
		_budget  = nil,

		_highlighter = Highlighter.new(
			options.folderName or "PerformanceHeatmapAdornments",
			options.maxHighlights
		),

		colors = {
			Big    = Color3.fromRGB(255,   0,   0),
			Medium = Color3.fromRGB(255, 255,   0),
			Ok     = Color3.fromRGB(0,   255,   0),
		},
	}, HeatmapService)

	return self
end

-- Sorts both tables from most severe to least.
-- `Group` (higher first) comes before `Sort` so modes that mix incomparable
-- metrics keep them apart; ties fall back to the name, so the order never
-- depends on Workspace traversal order.
function HeatmapService:sortModels()
	local function comparator(a, b)
		local groupA, groupB = a.Group or 0, b.Group or 0
		if groupA ~= groupB then
			return groupA > groupB
		end
		if a.Sort ~= b.Sort then
			return a.Sort > b.Sort
		end
		return a.Instance.Name < b.Instance.Name
	end

	table.sort(self.BigModels, comparator)
	table.sort(self.MediumModels, comparator)
end

-- Paints the worst offenders. "Ok" items are deliberately not drawn: the old
-- behaviour created a highlight for every single object that was fine, which on
-- a large place meant tens of thousands of instances spent saying "nothing to
-- see here" -- and turned the viewport into a wall of colour where nothing
-- stands out.
function HeatmapService:_paint()
	self._highlighter:clear()

	for _, entry in ipairs(self.BigModels) do
		if not self._highlighter:add(entry.Instance, self.colors.Big) then
			return
		end
	end

	for _, entry in ipairs(self.MediumModels) do
		if not self._highlighter:add(entry.Instance, self.colors.Medium) then
			return
		end
	end
end

-- Cancels any scan in flight. The running coroutine notices at its next
-- budget:step() and unwinds without touching the result tables.
function HeatmapService:cancel()
	if self._budget then
		self._budget:cancel()
		self._budget = nil
	end
	self.scanning = false
end

function HeatmapService:clear()
	self:cancel()
	self._highlighter:clear()
	self.BigModels, self.MediumModels = {}, {}
	self.lastSummary = nil
end

-- Panel closed / opened. Results stay in memory so re-opening restores the
-- previous scan verbatim; nothing is written to disk or to plugin settings.
function HeatmapService:setVisible(visible)
	self._highlighter:setVisible(visible)
end

function HeatmapService:hasResults()
	return #self.BigModels > 0 or #self.MediumModels > 0
end

-- How many highlights the cap dropped (0 when everything fit on screen).
function HeatmapService:skippedHighlights()
	return self._highlighter:skipped()
end

-- Runs `option`. Yields. Returns true when the scan completed, false when it was
-- cancelled or the mode is unknown.
--
-- onProgress(label, done, total) is called throughout, so the caller can show
-- progress somewhere -- currently the widget title, which is the only piece of
-- panel chrome that lives in code rather than in the place file.
function HeatmapService:run(option, onProgress)
	local analyzer = Analyzers.byId[option]
	if not analyzer then
		return false
	end

	-- a click while a scan is running supersedes it
	self:cancel()

	self._token += 1
	local token = self._token

	self.BigModels, self.MediumModels = {}, {}
	self.lastOption  = option
	self.lastSummary = nil

	local budget = Budget.new(onProgress)
	self._budget  = budget
	self.scanning = true

	local index = WorkspaceIndex.build(budget)
	if not index or budget:cancelled() or token ~= self._token then
		return false
	end

	local findings, summary = analyzer.scan(index, budget)
	if not findings or budget:cancelled() or token ~= self._token then
		return false
	end

	budget:setPhase("Sorting", #findings)

	for _, finding in ipairs(findings) do
		if finding.Bucket == "Big" then
			table.insert(self.BigModels, finding)
		elseif finding.Bucket == "Medium" then
			table.insert(self.MediumModels, finding)
		end
		if not budget:step() then
			return false
		end
	end

	self:sortModels()

	budget:setPhase("Highlighting", 0)
	self:_paint()

	self.lastSummary = summary
	self.scanning    = false
	self._budget     = nil

	return true
end

return HeatmapService
