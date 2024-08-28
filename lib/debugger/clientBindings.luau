local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local tags = {
	system = "MatterDebuggerTooltip_System",
	altHover = "MatterDebuggerTooltip_AltHover",
}

local function getOffset(mousePos: Vector2, tag: string): UDim2
	if tag == tags.altHover then
		return UDim2.fromOffset(mousePos.X + 20, mousePos.Y)
	elseif tag == tags.system then
		return UDim2.fromOffset(mousePos.X + 20, mousePos.Y + 10)
	end

	return UDim2.fromOffset(mousePos.X, mousePos.Y + 10)
end

local function clientBindings(debugger)
	local connections = {}

	table.insert(
		connections,
		CollectionService:GetInstanceAddedSignal("MatterDebuggerSwitchToClientView"):Connect(function(instance)
			instance.Activated:Connect(function()
				debugger:switchToClientView()
			end)
		end)
	)

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end

			local mousePosition = UserInputService:GetMouseLocation()

			for _, tag in tags do
				for _, gui in CollectionService:GetTagged(tag) do
					gui.Position = getOffset(mousePosition, tag)
				end
			end
		end)
	)

	for _, tag in tags do
		table.insert(
			connections,
			CollectionService:GetInstanceAddedSignal(tag):Connect(function(gui)
				local mousePosition = UserInputService:GetMouseLocation()
				gui.Position = getOffset(mousePosition, tag)
			end)
		)
	end

	return connections
end

return clientBindings
