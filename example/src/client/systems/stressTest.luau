local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.Shared.components)

local function stressTest(world, _, ui)
	for id in world:query(Components.Test) do
	end
end

return stressTest
