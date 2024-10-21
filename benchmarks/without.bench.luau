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

for i = 1, 50_000 do
	local id = i
	world:spawnAt(id)
	pinnedWorld:spawnAt(id)

	if flip() then
		world:insert(id, A({ a = true, id = i }))
		pinnedWorld:insert(id, pinnedA({ a = true, id = i }))
	end
	if flip() then
		world:insert(id, B({ b = true, id = i }))
		pinnedWorld:insert(id, pinnedB({ b = true, id = i }))
	end
	if flip() then
		world:insert(id, C({ c = true, id = i }))
		pinnedWorld:insert(id, pinnedC({ c = true, id = i }))
	end
	if flip() then
		world:insert(id, D({ d = true, id = i }))
		pinnedWorld:insert(id, pinnedD({ d = true, id = i }))
	end
	if flip() then
		world:insert(id, E({ e = true, id = i }))
		pinnedWorld:insert(id, pinnedE({ e = true, id = i }))
	end
	if flip() then
		world:insert(id, F({ f = true, id = i }))
		pinnedWorld:insert(id, pinnedF({ f = true, id = i }))
	end
	if flip() then
		world:insert(id, G({ g = true, id = i }))
		pinnedWorld:insert(id, pinnedG({ g = true, id = i }))
	end
end

return {
	ParameterGenerator = function()
		return
	end,

	Functions = {
		["Matter 0.8.4"] = function()
			local count = 0
			for _ in pinnedWorld:query(pinnedB):without(pinnedC) do
				count += 1
			end
		end,
		["Matter 0.9"] = function()
			local count = 0
			for _ in world:query(B):without(C) do
				count += 1
			end
		end,
	},
}
