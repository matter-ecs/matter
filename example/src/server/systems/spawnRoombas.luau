local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.Shared.components)

local function spawnRoombas(cx)
	for id, _ in cx.world:query(Components.Transform, Components.Roomba):without(Components.Model) do
		local model = ReplicatedStorage.Assets.KillerRoomba:Clone()
		model.Parent = workspace
		model.PrimaryPart:SetNetworkOwner(nil)

		cx.world:insert(
			id,
			Components.Model({
				model = model,
			})
		)
	end
end

return spawnRoombas
