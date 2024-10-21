export type EntityId = number
export type ComponentId = number
export type ComponentIds = { ComponentId }

export type Component = { [any]: any }
export type ComponentInstance = { [any]: any }

export type ArchetypeId = string
export type Archetype = {
	entities: { EntityId },
	componentIds: { ComponentId },
	idToIndex: { [ComponentId]: number },
	indexToId: { [number]: ComponentId },
	fields: { { ComponentInstance } },
}

function hash(componentIds: { number })
	table.sort(componentIds)
	return table.concat(componentIds, "_")
end

function new(componentIds: { ComponentId }): (Archetype, ArchetypeId)
	local length = #componentIds
	local archetypeId = hash(componentIds)

	local idToIndex, indexToId = {}, {}
	local fields = table.create(length)

	local archetype: Archetype = {
		entities = {},
		componentIds = componentIds,
		idToIndex = idToIndex,
		indexToId = indexToId,
		fields = fields,
	}

	for index, componentId in componentIds do
		idToIndex[componentId] = index
		indexToId[index] = componentId

		fields[index] = {}
	end

	return archetype, archetypeId
end

return {
	new = new,
	hash = hash,
}
