--!optimize 2
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Matter)
local PinnedMatter = require(ReplicatedStorage.PinnedMatter)

local world = Matter.World.new()
local pinnedWorld = PinnedMatter.World.new()

local A, B = Matter.component(), Matter.component()
local pinnedA, pinnedB = PinnedMatter.component(), PinnedMatter.component()

for i = 1, 10_000 do
	world:spawnAt(i, A({}), B({}))
	pinnedWorld:spawnAt(i, pinnedA({}), pinnedB({}))
end

return {
	ParameterGenerator = function()
		return
	end,

	Functions = {
		["New Matter"] = function()
			local query = world:query(A, B)
			for _ = 1, 1_000 do
				query:next()
			end
		end,
		["Old Matter"] = function()
			local query = pinnedWorld:query(pinnedA, pinnedB)
			for _ = 1, 1_000 do
				query:next()
			end
		end,
	},
}
