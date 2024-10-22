export type EntityId = number
export type ComponentId = number
export type ComponentIds = { ComponentId }

export type Component = { [any]: any }
export type ComponentInstance = { [any]: any }

export type ArchetypeEdge = {
	add: Archetype?,
	remove: Archetype?,
}

export type ArchetypeId = string
export type Archetype = {
	entities: { EntityId },
	componentIds: { ComponentId },
	idToIndex: { [ComponentId]: number },
	indexToId: { [number]: ComponentId },
	fields: { { ComponentInstance } },
	edges: { [ComponentId]: ArchetypeEdge? },
}

function hash(componentIds: { number })
	table.sort(componentIds)
	return table.concat(componentIds, "_")
end

function ensureEdge(archetype: Archetype, componentId: ComponentId): ArchetypeEdge
	local edge = archetype.edges[componentId]
	if edge then
		return edge
	end

	edge = { add = nil, remove = nil }
	archetype.edges[componentId] = edge
	return edge
end

function link(archetype: Archetype, nextArchetype: Archetype, componentId: ComponentId)
	ensureEdge(archetype, componentId).add = nextArchetype
	ensureEdge(nextArchetype, componentId).remove = archetype
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
		edges = {},
	}

	for index, componentId in componentIds do
		idToIndex[componentId] = index
		indexToId[index] = componentId

		fields[index] = {}
	end

	return archetype, archetypeId
end

return {
	hash = hash,
	ensureEdge = ensureEdge,
	link = link,

	new = new,
}
