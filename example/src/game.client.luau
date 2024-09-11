local ReplicatedStorage = game:GetService("ReplicatedStorage")
local start = require(ReplicatedStorage.Shared.start)
local receiveReplication = require(ReplicatedStorage.Client.receiveReplication)

local cx = start({
	ReplicatedStorage.Shared.systems,
	ReplicatedStorage.Client.systems,
})

receiveReplication(cx)
