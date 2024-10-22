local function getAllComponentData(world, entity: number): { [{ [any]: any }]: { [any]: any } }
	local componentToData = {}

	local location = world.allEntities[entity]
	local archetype = location.archetype
	local indexInArchetype = location.indexInArchetype

	for index, field in archetype.fields do
		local componentId = archetype.componentIds[index]
		local component = world.componentIdToComponent[componentId]
		local data = field[indexInArchetype]

		componentToData[component] = data
	end

	return componentToData
end

return getAllComponentData
