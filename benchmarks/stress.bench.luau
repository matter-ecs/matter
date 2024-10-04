--!optimize 2
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Matter)
local PinnedMatter = require(ReplicatedStorage.PinnedMatter)

local world = Matter.World.new()
local pinnedWorld = PinnedMatter.World.new()

local A, B, C, D, E, F, G =
	Matter.component(),
	Matter.component(),
	Matter.component(),
	Matter.component(),
	Matter.component(),
	Matter.component(),
	Matter.component()
local pinnedA, pinnedB, pinnedC, pinnedD, pinnedE, pinnedF, pinnedG =
	PinnedMatter.component(),
	PinnedMatter.component(),
	PinnedMatter.component(),
	PinnedMatter.component(),
	PinnedMatter.component(),
	PinnedMatter.component(),
	PinnedMatter.component()

local function flip()
	return math.random() > 0.5
end

for i = 1, 10_000 do
	local id = i
	world:spawnAt(id)
	pinnedWorld:spawnAt(id)

	if flip() then
		world:insert(id, A({ a = true }))
		pinnedWorld:insert(id, pinnedA({ a = true }))
	end
	if flip() then
		world:insert(id, B({ b = true }))
		pinnedWorld:insert(id, pinnedB({ b = true }))
	end
	if flip() then
		world:insert(id, C({ c = true }))
		pinnedWorld:insert(id, pinnedC({ c = true }))
	end
	if flip() then
		world:insert(id, D({ d = true }))
		pinnedWorld:insert(id, pinnedD({ d = true }))
	end
	if flip() then
		world:insert(id, E({ e = true }))
		pinnedWorld:insert(id, pinnedE({ e = true }))
	end
	if flip() then
		world:insert(id, F({ f = true }))
		pinnedWorld:insert(id, pinnedF({ f = true }))
	end
	if flip() then
		world:insert(id, G({ g = true }))
		pinnedWorld:insert(id, pinnedG({ g = true }))
	end
end

return {
	ParameterGenerator = function()
		return
	end,

	Functions = {
		["Old Matter"] = function()
			--local count = 0
			for _ in pinnedWorld:query(pinnedB, pinnedA) do
				--count += 1
			end

			--print("old:", count)
		end,
		["New Matter"] = function()
			--local count = 0
			for _ in world:query(B, A) do
				--count += 1
				--print("entt", a, b)
			end

			--print("new:", count)
		end,
	},
}
