return {
	-- Instance & Physics Counts
	{ Divider     = true,  Title = "Instance & Physics Counts" },
	{ Name        = "InstanceCount",          Description = "Number of Instances in memory." },
	{ Name        = "PrimitivesCount",        Description = "Number of physics-simulated objects." },
	{ Name        = "MovingPrimitivesCount",  Description = "Count of moving physics objects." },
	{ Name        = "ContactsCount",          Description = "Number of parts currently in contact." },

	-- Timing metrics
	{ Divider     = true,  Title = "Timing Metrics" },
	{ Name        = "FrameTime",              Description = "Time taken to render a frame." },
	{ Name        = "PhysicsStepTime",        Description = "Time taken for physics update." },
	{ Name        = "HeartbeatTime",          Description = "Time to update server scheduler jobs." },
	{ Name        = "RenderCPUFrameTime",     Description = "CPU time for rendering a frame." },
	{ Name        = "RenderGPUFrameTime",     Description = "GPU time for rendering a frame." },

	-- Bandwidth (network & physics)
	{ Divider     = true,  Title = "Bandwidth (Network & Physics)" },
	{ Name        = "DataReceiveKbps",        Description = "KB/s of data received by this instance." },
	{ Name        = "DataSendKbps",           Description = "KB/s of data sent by this instance." },
	{ Name        = "PhysicsReceiveKbps",     Description = "KB/s of physics data received." },
	{ Name        = "PhysicsSendKbps",        Description = "KB/s of physics data sent." },

	-- Scene & Shadows
	{ Divider     = true,  Title = "Scene & Shadows" },
	{ Name        = "SceneDrawcallCount",     Description = "Number of draw calls in the scene." },
	{ Name        = "SceneTriangleCount",     Description = "Number of triangles rendered in the scene." },
	{ Name        = "ShadowsDrawcallCount",   Description = "Number of shadow draw calls." },
	{ Name        = "ShadowsTriangleCount",   Description = "Number of triangles rendered for shadows." },

	-- UI
	{ Divider     = true,  Title = "UI Drawcalls & Triangles" },
	{ Name        = "UI2DDrawcallCount",      Description = "Number of 2D UI draw calls." },
	{ Name        = "UI2DTriangleCount",      Description = "Number of triangles rendered for 2D UI." },
	{ Name        = "UI3DDrawcallCount",      Description = "Number of 3D UI draw calls." },
	{ Name        = "UI3DTriangleCount",      Description = "Number of triangles rendered for 3D UI." },
}
