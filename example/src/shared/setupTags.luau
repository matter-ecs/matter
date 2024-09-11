local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.Shared.components)

local boundTags = {
	Spinner = Components.Spinner,
}

local function setupTags(cx)
	local function spawnBound(instance, component)
		local id = cx.world:spawn(
			component(),
			Components.Model({
				model = instance,
			}),
			Components.Transform({
				cframe = instance.PrimaryPart.CFrame,
			})
		)

		instance:SetAttribute("serverEntityId", id)
	end

	for tagName, component in pairs(boundTags) do
		for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
			spawnBound(instance, component)
		end

		CollectionService:GetInstanceAddedSignal(tagName):Connect(function(instance)
			spawnBound(instance, component)
		end)

		CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(instance)
			local id = instance:GetAttribute("serverEntityId")
			if id then
				cx.world:despawn(id)
			end
		end)
	end
end

return setupTags
