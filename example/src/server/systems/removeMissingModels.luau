local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.Shared.components)
local Matter = require(ReplicatedStorage.Lib.Matter)

local function removeMissingModels(cx)
	for id, model in cx.world:query(Components.Model) do
		for _ in Matter.useEvent(model.model, "AncestryChanged") do
			if model.model:IsDescendantOf(game) == false then
				cx.world:remove(id, Components.Model)
				break
			end
		end
		if not model.model.PrimaryPart then
			cx.world:remove(id, Components.Model)
		end
	end

	for _id, modelRecord in cx.world:queryChanged(Components.Model) do
		if modelRecord.new == nil then
			if modelRecord.old and modelRecord.old.model then
				modelRecord.old.model:Destroy()
			end
		end
	end
end

return removeMissingModels
