local TS = game:GetService("TweenService")

local module = {}

function module.hover(frame, clickButton)
	local defaultSize = frame.Size + UDim2.new(0.1, 0, 0.1, 0)
	local finalSize = frame.Size 

	frame.MouseEnter:Connect(function()
		TS:Create(frame, TweenInfo.new(0.3), {Size = defaultSize}):Play()
		TS:Create(clickButton, TweenInfo.new(0.3), {ImageTransparency = 0}):Play()
	end)

	frame.MouseLeave:Connect(function()
		TS:Create(frame, TweenInfo.new(0.3), {Size = finalSize}):Play()
		TS:Create(clickButton, TweenInfo.new(0.3), {ImageTransparency = 0.5}):Play()
	end)
end

function module.Click(frame, clickButton)
	local defaultSize = frame.Size
	local finalSize = frame.Size + UDim2.new(0.1, 0, 0.1, 0)

	clickButton.MouseButton1Down:Connect(function()
		TS:Create(frame, TweenInfo.new(0.2), {Size = defaultSize}):Play()
	end)

	clickButton.MouseButton1Up:Connect(function()
		TS:Create(frame, TweenInfo.new(0.2), {Size = finalSize}):Play()
	end)
end


function module.button(frame, mouse)
	local clickButton = frame:FindFirstChild("Click")
	local textLabel = frame:FindFirstChild("TextLabel")

	module.hover(frame, clickButton)

	frame.MouseEnter:Connect(function()
		TS:Create(textLabel, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
		mouse.Icon = "rbxasset://SystemCursors/PointingHand"
	end)

	frame.MouseLeave:Connect(function()
		TS:Create(textLabel, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
		mouse.Icon = "rbxasset://SystemCursors/Arrow"
	end)

	module.Click(frame, clickButton)
end

return module