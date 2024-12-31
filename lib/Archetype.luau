export type EntityId = number
export type ComponentId = number
export type ComponentIds = { ComponentId }

export type Component = { [any]: any }
export type ComponentInstance = { [any]: any }

type EdgeId = number
type EdgeDiff = {
	added: {},
	removed: {},
}

type GraphEdge = {
	id: EdgeId,

	-- Source archetype
	from: Archetype?,

	-- Destination archetype
	to: Archetype?,

	-- What changes on the edge
	diff: EdgeDiff,

	prev: GraphEdge,
	next: GraphEdge,
}

type GraphEdges = { [EdgeId]: GraphEdge }
type GraphNode = {
	outgoing: { additive: GraphEdges, subtractive: GraphEdges },

	incoming: { additive: GraphEdge?, subtractive: GraphEdge? },
}

export type ArchetypeId = string
export type Archetype = {
	entities: { EntityId },
	componentIds: { ComponentId },
	idToIndex: { [ComponentId]: number },
	indexToId: { [number]: ComponentId },
	fields: { { ComponentInstance } },
	node: GraphNode,
}

export type Archetypes = { [ArchetypeId]: Archetype? }

local function hash(componentIds: { number })
	table.sort(componentIds)
	return table.concat(componentIds, "_")
end

local function new(componentIds: { ComponentId }): (Archetype, ArchetypeId)
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
		node = {
			outgoing = {
				additive = {},
				subtractive = {},
			},
			incoming = {},
		},
	}

	for index, componentId in componentIds do
		idToIndex[componentId] = index
		indexToId[index] = componentId

		fields[index] = {}
	end

	return archetype, archetypeId
end

local function ensureArchetype(archetypes: Archetypes, componentArchetypeMap, componentIds: { ComponentId })
	local archetypeId = hash(componentIds)
	local existingArchetype = archetypes[archetypeId]
	if existingArchetype then
		return existingArchetype
	end

	-- Create new archetype
	local archetype, archetypeId = new(componentIds)
	archetypes[archetypeId] = archetype

	for _, componentId in componentIds do
		local associatedArchetypes = componentArchetypeMap[componentId]
		if associatedArchetypes == nil then
			associatedArchetypes = {}
			componentArchetypeMap[componentId] = associatedArchetypes
		end

		table.insert(associatedArchetypes, archetype)
	end

	return archetype
end

--- Create or return the edge for a given id
local function ensureEdge(edges: GraphEdges, componentId: ComponentId): GraphEdge
	local edge = edges[componentId]
	if edge == nil then
		edge = {}
		edges[componentId] = edge
	end

	return edge
end

local function initializeEdge(archetype: Archetype, nextArchetype: Archetype, componentId: ComponentId, edge: GraphEdge)
	edge.from = archetype
	edge.to = nextArchetype
	edge.id = componentId
end

--- Traverse the graph to find the next archetype with the new component. This will create the archetype if it
--- doesn't exist and create the edge if it doesn't exist.
local function traverseAdd(
	archetypes: Archetypes,
	archetype: Archetype,
	componentArchetypeMap,
	componentId: ComponentId
): Archetype
	local node = archetype.node
	local edge = ensureEdge(node.outgoing, componentId)
	local to = edge.to
	if to then
		return to
	end

	-- Get the archetype
	local nextComponentIds = table.clone(archetype.componentIds)
	table.insert(nextComponentIds, componentId)
	table.sort(nextComponentIds)

	local nextArchetype = ensureArchetype(archetypes, componentArchetypeMap, nextComponentIds)
	initializeEdge(archetype, nextArchetype, componentId, edge)

	-- Add new incoming to the list
	local nextIncoming = nextArchetype.node.incoming
	local link = nextIncoming.additive

	nextIncoming.additive = edge
	edge.prev = nextIncoming

	edge.next = link
	if link then
		link.prev = edge
	end

	return edge.to
end

local function traverseRemove() end

return table.freeze({
	new = new,
	hash = hash,
	ensureArchetype = ensureArchetype,
	traverseAdd = traverseAdd,
})
