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
			numChildren = 0,
		}

		return node
	end

	local root = createNode()
	root.archetype = {
		ownedEntities = {},
		componentIds = {},
		componentIdToStorageIndex = {},
		storageIndexToComponentId = {},
		fields = {},
	} :: Archetype

	local function findNode(_, terms: Terms): Node
		local node = root
		for _, term in terms do
			local child = node.children[term]
			if child == nil then
				child = createNode()
				node.children[term] = child
				node.numChildren += 1
			end

			node = child
		end

		return node
	end

	local function findArchetypes(_, with: Terms)
		local terms = table.clone(with)
		table.sort(terms)

		--print("finding:", terms)
		--print("	", root)
		local archetypes = {}
		local count = 0
		local function check(node: Node, ...: ComponentId)
			-- print("check:", node, ...)
			count += 1
			if select("#", ...) == 0 then
				if node.archetype and #node.archetype.ownedEntities > 0 then
					table.insert(archetypes, node.archetype)
				end
			end

			for componentId, child in node.children do
				local head = select(1, ...)
				-- print("	child", componentId, child, head)
				if head then
					if componentId < head then
						check(child, ...)
					elseif componentId == head then
						check(child, select(2, ...))
					end
				else
					check(child, ...)
				end
			end
		end

		-- Make sure that a node exists for each term
		-- If it doesn't then we know that the archetypes will be empty
		local smallestHeight, smallestNode, smallestNodeIndex = math.huge, nil, -1
		for index, componentId in terms do
			local node = root.children[componentId]
			if node == nil then
				return {}
			end

			if node.numChildren < smallestHeight then
				smallestNode = node
				smallestNodeIndex = index
				smallestHeight = node.numChildren
			end
		end

		if smallestNode == nil then
			return {}
		end

		-- TODO:
		-- Only traverse path with smallest num children
		local newTerms = table.clone(terms)
		table.remove(newTerms, smallestNodeIndex)

		-- print("terms", terms, smallestNode, "newTerms", newTerms)
		check(smallestNode, unpack(newTerms, 1, #newTerms))
		-- if terms[1] == 152 then -- terms[1] == 5 and terms[2] == 150 then
		-- 	print("jumps:", count, newTerms, smallestNode)
		-- end

		return archetypes
	end

	local function ensureArchetype(self, terms: Terms): Archetype
		table.sort(terms)

		--print("ensure:", terms)
		local archetype
		for skipIndex = 1, #terms do
			local newTerms = table.clone(terms)
			table.remove(newTerms, skipIndex)
			table.insert(newTerms, 1, terms[skipIndex])

			--print("	newTerms", skipIndex, newTerms)
			local node = findNode(self, newTerms)
			if node.archetype then
				archetype = node.archetype
			else
				if archetype == nil then
					archetype = {
						ownedEntities = {},
						componentIds = terms,
						componentIdToStorageIndex = {},
						storageIndexToComponentId = {},
						fields = {},
					}

					for index, componentId in terms do
						archetype.componentIdToStorageIndex[componentId] = index
						archetype.storageIndexToComponentId[index] = componentId
						archetype.fields[index] = {}
					end
				end

				node.archetype = archetype
			end
		end

		--print("	ret:", archetype)
		return archetype
	end

	local function count()
		local archetypes = {}
		local function check(node, str)
			if node.archetype then
				archetypes[str] = (archetypes[str] or 0) + #node.archetype.ownedEntities
			end

			for componentId, child in node.children do
				check(child, str .. "_" .. componentId)
			end
		end

		check(root, "")
		return archetypes
	end

	local function cleanup()
		-- TODO:
		-- dont potentially delete root node

		local function check(node)
			for componentId, child in node.children do
				local archetype, children = child.archetype, child.children
				if archetype == nil or #archetype.ownedEntities == 0 then
					if next(children) == nil then
						node.children[componentId] = nil
						node.numChildren -= 1
					else
						child.archetype = nil
					end
				end

				check(child)
			end
		end

		check(root)
	end

	return table.freeze({
		findNode = findNode,
		findArchetypes = findArchetypes,
		ensureArchetype = ensureArchetype,
		root = root,
		count = count,
		cleanup = cleanup,
	})
end

return {
	new = newArchetypeTree,
}
