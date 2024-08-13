--!optimize 2
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Matter)
local PinnedMatter = require(ReplicatedStorage.PinnedMatter)

local world = Matter.World.new()
local pinnedWorld = PinnedMatter.World.new()

local A, B, C, D = Matter.component(), Matter.component(), Matter.component(), Matter.component()
local pinnedA, pinnedB, pinnedC, pinnedD =
	PinnedMatter.component(), PinnedMatter.component(), PinnedMatter.component(), PinnedMatter.component()

local function flip()
	return math.random() > 0.5
end

for i = 1, 200_000 do
	local id = i
	world:spawnAt(id)
	pinnedWorld:spawnAt(id)

	if flip() then
		world:insert(id, A())
		pinnedWorld:insert(id, pinnedA())
	end
	if flip() then
		world:insert(id, B())
		pinnedWorld:insert(id, pinnedB())
	end
	if flip() then
		world:insert(id, C())
		pinnedWorld:insert(id, pinnedC())
	end
	if flip() then
		world:insert(id, D())
		pinnedWorld:insert(id, pinnedD())
	end
end

return {
	ParameterGenerator = function()
		return
	end,

	Functions = {
		["Old Matter"] = function()
			for _ in pinnedWorld:query(pinnedA, pinnedB) do
			end
		end,
		["New Matter"] = function()
			--local count = 0
			for _ in world:query(A, B) do
				--count += 1
			end

			--print(count)
		end,
	},
}
