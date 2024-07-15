--!optimize 2
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--local Jecs = require(ReplicatedStorage.Jecs)
local Matter = require(ReplicatedStorage.Matter)
local OldMatter = require(ReplicatedStorage.PinnedMatter)

--local jecsWorld = Jecs.World.new()
local matterWorld = Matter.World.new()
local oldWorld = OldMatter.World.new()

local mA, mB = Matter.component(), Matter.component()
local oldA, oldB = OldMatter.component(), OldMatter.component()
--local jA, jB = jecsWorld:component(), jecsWorld:component()

for i = 1, 100 do
	matterWorld:spawnAt(i, mA({}), mB({}))
	oldWorld:spawnAt(i, oldA({}), oldB({}))

	--local jecsEntity = jecsWorld:entity()
	--jecsWorld:set(jecsEntity, jA, {})
	--jecsWorld:set(jecsEntity, jB, {})
end

return {
	ParameterGenerator = function()
		return
	end,

	Functions = {
		["New"] = function(Profiler)
			local count = 0
			for entityId in matterWorld:query(mA, mB) do
				count += 1
			end
		end,
		["Old"] = function(Profiler)
			local count = 0
			for entityId in oldWorld:query(oldA, oldB) do
				count += 1
			end
		end,
		-- ["Jecs"] = function(Profiler)
		-- 	local count = 0
		-- 	for entityID in jecsWorld:query(jA, jB) do
		-- 		count += 1
		-- 	end
		-- end,
	},
}
