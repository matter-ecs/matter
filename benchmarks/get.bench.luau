--!optimize 2
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Matter)
local Matter_0_8 = require(ReplicatedStorage.Matter_0_8)
local Matter_0_9 = require(ReplicatedStorage.Matter_0_9)

local A, B = Matter.component(), Matter.component()
local A_0_8, B_0_8 = Matter_0_8.component(), Matter_0_8.component()
local A_0_9, B_0_9 = Matter_0_9.component(), Matter_0_9.component()

local N = 1000

return {
	ParameterGenerator = function()
		local world, world_0_8, world_0_9 = Matter.World.new(), Matter_0_8.World.new(), Matter_0_9.World.new()
		for i = 1, N do
			world_0_8:spawnAt(i, A_0_8({}), B_0_8({}))
			world_0_9:spawnAt(i, A_0_9({}), B_0_9({}))
			world:spawnAt(i, A({ a = true }), B({ b = true }))
		end

		return world_0_8, world_0_9, world
	end,

	Functions = {
		["Matter 0.8"] = function(_, world)
			for i = 1, N do
				world:get(i, B_0_8, A_0_8)
			end
		end,
		["Matter 0.9"] = function(_, _, world)
			for i = 1, N do
				world:get(i, B_0_9, A_0_9)
			end
		end,
		["Matter Unreleased"] = function(_, _, _, world)
			for i = 1, N do
				world:get(i, B, A)
			end
		end,
	},
}
