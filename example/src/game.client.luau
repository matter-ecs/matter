local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local start = require(ReplicatedStorage.Shared.start)
local receiveReplication = require(ReplicatedStorage.Client.receiveReplication)

local world, state = start({
	ReplicatedStorage.Shared.systems,
	ReplicatedStorage.Client.systems,
})

receiveReplication(world, state)

local components = require(ReplicatedStorage.Shared.components)

for i = 1, 1000 do
	world:spawn(components.Test())
end
