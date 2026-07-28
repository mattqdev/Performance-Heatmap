-- Analyzers -- registry of heatmap modes.
--
-- Adding a mode used to mean touching three places: the if-chain in
-- HeatmapService:run, the rowClass helper in init.local.luau, and a Frame in the
-- plugin's GUI (which isn't in this repo). Two of those are gone: the header
-- menu already wires every Frame under Body.Head by name, so a mode now needs a
-- module here whose `id` matches that Frame's Name, and nothing else.
--
-- Each module is:
--   id    -- must equal the GUI Frame's Name; this is what run() dispatches on
--   label -- human-readable, for messages
--   scan(index, budget) -> findings, summary?
--
-- `scan` reads the shared WorkspaceIndex, calls budget:step() in every loop, and
-- returns nil the moment step() reports a cancellation. A finding is:
--   { Instance, Amount, Sort, Bucket, Group? }
-- where Bucket is "Ok" | "Medium" | "Big", Sort is the numeric severity, and
-- Group (optional, higher first) separates metrics that can't be ranked against
-- each other -- see Triangles, which mixes measured counts with estimates.

local modules = {
	require(script.Count),
	require(script.Density),
	require(script.Triangles),
	require(script.Texture),
	require(script.Overlap),
	require(script.Lights),
	require(script.Particles),
}

local Analyzers = {
	list = modules,
	byId = {},
}

for _, analyzer in ipairs(modules) do
	Analyzers.byId[analyzer.id] = analyzer
end

return Analyzers
