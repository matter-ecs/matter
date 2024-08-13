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
			local count = 0
			for _ in world:query(A, B) do
				count += 1
			end
		end,
		["Old Matter"] = function()
			local count = 0
			for _ in pinnedWorld:query(pinnedA, pinnedB) do
				count += 1
			end
		end,
	},
}
