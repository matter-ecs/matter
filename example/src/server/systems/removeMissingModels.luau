local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.Shared.components)
local Matter = require(ReplicatedStorage.Lib.Matter)

local function removeMissingModels(world)
	for id, model in world:query(Components.Model) do
		for _ in Matter.useEvent(model, "AncestryChanged") do
			if model:IsDescendantOf(game) == false then
				world:remove(id, Components.Model)
				break
			end
		end
		if not model.PrimaryPart then
			world:remove(id, Components.Model)
		end
	end

	for _id, modelRecord in world:queryChanged(Components.Model) do
		if modelRecord.new == nil then
			if modelRecord.old then
				modelRecord.old:Destroy()
			end
		end
	end
end

return removeMissingModels
