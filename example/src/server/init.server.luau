local ReplicatedStorage = game:GetService("ReplicatedStorage")
local start = require(ReplicatedStorage.Shared.start)
local setupTags = require(ReplicatedStorage.Shared.setupTags)

local cx = start({
	script.systems,
	ReplicatedStorage.Shared.systems,
})

setupTags(cx)
