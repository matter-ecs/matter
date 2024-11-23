--!optimize 2
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Matter)
local PinnedMatter = require(ReplicatedStorage.Matter_0_8)

local A, B = Matter.component(), Matter.component()
local pinnedA, pinnedB = PinnedMatter.component(), PinnedMatter.component()

local N = 500

return {
	ParameterGenerator = function()
		local world, pinnedWorld = Matter.World.new(), PinnedMatter.World.new()
		for i = 1, N do
			world:spawnAt(i)
			pinnedWorld:spawnAt(i)
		end

		return world, pinnedWorld
	end,

	Functions = {
		["Matter 0.9"] = function(_, world)
			for i = 1, N do
				world:insert(i, A({ i }))
			end
		end,
		["Matter 0.8.4"] = function(_, _, world)
			for i = 1, N do
				world:insert(i, A({ i }))
			end
		end,
	},
}
