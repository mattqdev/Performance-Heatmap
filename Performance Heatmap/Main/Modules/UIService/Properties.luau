-- Declarative list of the Stats metrics shown in the panel.
--
-- `Good` / `Warn` drive the color of the value in the UI: green up to Good,
-- yellow up to Warn, red past it (add `HigherIsBetter = true` to flip it -- no
-- metric here needs it, every one of these is "lower is better").
-- Omit both to leave a row uncolored.
--
-- These budgets are rules of thumb for a mid-range device, not engine limits:
-- red means "worth investigating", not "broken". Timing metrics are in SECONDS
-- (that's why the engine's *Ms variants exist and are deprecated), bandwidth in
-- Kbps, everything else is a raw count.
--
-- `PlayOnly = true` marks a row whose value is about the *process*, not the
-- place: in edit mode the Stats service is reporting Studio itself -- the editor
-- viewport, the selection gizmos, every open dock widget, and whatever Studio is
-- talking to over the network. Colouring those against a game budget would be
-- inventing a number, so the panel greys them out and says so until you hit
-- Play. Scene and instance counts are properties of what's loaded and stay
-- meaningful either way.
return {
	-- Instance & Physics Counts
	{ Divider     = true,  Title = "Instance & Physics Counts" },
	{ Name        = "InstanceCount",          Description = "Number of Instances in memory.",
	  Good        = 15000,   Warn = 40000 },
	{ Name        = "PrimitivesCount",        Description = "Number of physics-simulated objects.",
	  Good        = 2000,    Warn = 8000 },
	{ Name        = "MovingPrimitivesCount",  Description = "Count of moving physics objects.",
	  Good        = 100,     Warn = 500 },
	{ Name        = "ContactsCount",          Description = "Number of parts currently in contact.",
	  Good        = 200,     Warn = 1000 },

	-- Timing metrics (seconds; 1/60 = 0.0167s, 1/30 = 0.0333s)
	{ Divider     = true,  Title = "Timing Metrics" },
	{ Name        = "FrameTime",              Description = "Time taken to render a frame.",
	  Good        = 1/60,    Warn = 1/30,   PlayOnly = true },
	{ Name        = "PhysicsStepTime",        Description = "Time taken for physics update.",
	  Good        = 0.004,   Warn = 0.008,  PlayOnly = true },
	{ Name        = "HeartbeatTime",          Description = "Time to update server scheduler jobs.",
	  Good        = 1/60,    Warn = 1/30,   PlayOnly = true },
	{ Name        = "RenderCPUFrameTime",     Description = "CPU time for rendering a frame.",
	  Good        = 1/60,    Warn = 1/30,   PlayOnly = true },
	{ Name        = "RenderGPUFrameTime",     Description = "GPU time for rendering a frame.",
	  Good        = 1/60,    Warn = 1/30,   PlayOnly = true },

	-- Bandwidth (network & physics)
	{ Divider     = true,  Title = "Bandwidth (Network & Physics)" },
	{ Name        = "DataReceiveKbps",        Description = "KB/s of data received by this instance.",
	  Good        = 50,      Warn = 200,    PlayOnly = true },
	{ Name        = "DataSendKbps",           Description = "KB/s of data sent by this instance.",
	  Good        = 50,      Warn = 200,    PlayOnly = true },
	{ Name        = "PhysicsReceiveKbps",     Description = "KB/s of physics data received.",
	  Good        = 50,      Warn = 200,    PlayOnly = true },
	{ Name        = "PhysicsSendKbps",        Description = "KB/s of physics data sent.",
	  Good        = 50,      Warn = 200,    PlayOnly = true },

	-- Scene & Shadows
	{ Divider     = true,  Title = "Scene & Shadows" },
	{ Name        = "SceneDrawcallCount",     Description = "Number of draw calls in the scene.",
	  Good        = 1000,    Warn = 3000 },
	{ Name        = "SceneTriangleCount",     Description = "Number of triangles rendered in the scene.",
	  Good        = 500000,  Warn = 1500000 },
	{ Name        = "ShadowsDrawcallCount",   Description = "Number of shadow draw calls.",
	  Good        = 500,     Warn = 1500 },
	{ Name        = "ShadowsTriangleCount",   Description = "Number of triangles rendered for shadows.",
	  Good        = 250000,  Warn = 750000 },

	-- UI
	{ Divider     = true,  Title = "UI Drawcalls & Triangles" },
	{ Name        = "UI2DDrawcallCount",      Description = "Number of 2D UI draw calls.",
	  Good        = 100,     Warn = 300 },
	{ Name        = "UI2DTriangleCount",      Description = "Number of triangles rendered for 2D UI.",
	  Good        = 5000,    Warn = 20000 },
	{ Name        = "UI3DDrawcallCount",      Description = "Number of 3D UI draw calls.",
	  Good        = 50,      Warn = 150 },
	{ Name        = "UI3DTriangleCount",      Description = "Number of triangles rendered for 3D UI.",
	  Good        = 5000,    Warn = 20000 },
}
