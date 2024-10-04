type ComponentId = number
type EntityId = number

export type Archetype = {
	ownedEntities: { EntityId },

	--- The component IDs that are part of this archetype, in no particular order
	componentIds: { ComponentId },

	--- Maps a component ID to its index in the storage
	componentIdToStorageIndex: { [ComponentId]: number },

	--- Maps a storage index to its component ID, useful for iterating the world
	storageIndexToComponentId: { [number]: ComponentId },

	fields: { { any } },
}

type Node = {
	children: { [ComponentId]: Node? },
	archetype: Archetype?,
}

type Terms = { ComponentId }

local function newArchetypeTree()
	local function createNode(): Node
		local node: Node = {
			children = {},
		}

		return node
	end

	local root = createNode()
	local function findNode(_, terms: Terms): Node
		table.sort(terms)

		local node = root
		for _, term in terms do
			local child = node.children[term]
			if child == nil then
				child = createNode()
				node.children[term] = child
			end

			node = child
		end

		return node
	end

	local function findArchetypes(self, terms: Terms)
		table.sort(terms)

		local archetypes = {}
		local function collapse(node: Node)
			table.insert(archetypes, node.archetype)

			for _, child in node.children do
				collapse(child)
			end
		end

		collapse(findNode(self, terms))
		return archetypes
	end

	local function ensureArchetype(self, terms: Terms): Archetype
		local node = findNode(self, terms)
		if node.archetype == nil then
			node.archetype = {
				ownedEntities = {},
				componentIds = terms,
				componentIdToStorageIndex = {},
				storageIndexToComponentId = {},
				fields = {},
			}

			for index, componentId in terms do
				node.archetype.componentIdToStorageIndex[componentId] = index
				node.archetype.storageIndexToComponentId[index] = componentId
				node.archetype.fields[index] = {}
			end
		end

		return node.archetype
	end

	return table.freeze({
		findNode = findNode,
		findArchetypes = findArchetypes,
		ensureArchetype = ensureArchetype,
		root = root,
	})
end

return {
	new = newArchetypeTree,
}
