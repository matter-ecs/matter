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

local archetypes = {}
for i = 1, 30_000 do
	local id = i
	world:spawnAt(id)
	pinnedWorld:spawnAt(id)

	local str = ""
	if flip() then
		world:insert(id, A({ a = true, id = i }))
		pinnedWorld:insert(id, pinnedA({ a = true, id = i }))
		str ..= "A_"
	end
	if flip() then
		world:insert(id, B({ b = true, id = i }))
		pinnedWorld:insert(id, pinnedB({ b = true, id = i }))
		str ..= "B_"
	end
	if flip() then
		world:insert(id, C({ c = true, id = i }))
		pinnedWorld:insert(id, pinnedC({ c = true, id = i }))
		str ..= "C_"
	end
	if flip() then
		world:insert(id, D({ d = true, id = i }))
		pinnedWorld:insert(id, pinnedD({ d = true, id = i }))
		str ..= "D_"
	end
	if flip() then
		world:insert(id, E({ e = true, id = i }))
		pinnedWorld:insert(id, pinnedE({ e = true, id = i }))
		str ..= "E_"
	end
	if flip() then
		world:insert(id, F({ f = true, id = i }))
		pinnedWorld:insert(id, pinnedF({ f = true, id = i }))
		str ..= "F_"
	end
	if flip() then
		world:insert(id, G({ g = true, id = i }))
		pinnedWorld:insert(id, pinnedG({ g = true, id = i }))
		str ..= "G"
	end

	archetypes[str] = (archetypes[str] or 0) + 1
end

local total = 0
for _ in archetypes do
	total += 1
end

print(total, "different archetypes")

return {
	ParameterGenerator = function()
		return
	end,

	Functions = {
		["Matter 0.8.4"] = function()
			local count = 0
			for _ in pinnedWorld:query(pinnedB, pinnedA) do
				count += 1
			end
		end,
		["Matter 0.9"] = function()
			local count = 0
			for _ in world:query(B, A) do
				count += 1
			end
		end,
	},
}
