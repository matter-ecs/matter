--!optimize 2
--!native
--!strict
local topoRuntime = require(script.Parent.topoRuntime)
local Component = require(script.Parent.component)

local assertValidComponentInstance = Component.assertValidComponentInstance
local assertValidComponent = Component.assertValidComponent

local ERROR_NO_ENTITY = "Entity doesn't exist, use world:contains to check if needed"
local ERROR_DUPLICATE_ENTITY =
	"The world already contains an entity with ID %d. Use World:replace instead if this is intentional."
local ERROR_NO_COMPONENTS = "Missing components"

type Component = { [any]: any }
type ComponentInstance = { [any]: any }

type i53 = number
type i24 = number

type Ty = { i53 }
type ArchetypeId = number

type Column = { any }

type Archetype = {
	id: number,
	edges: {
		[i53]: {
			add: Archetype,
			remove: Archetype,
		},
	},
	types: Ty,
	type: string | number,
	entities: { number },
	columns: { Column },
	records: {},
}

type Record = {
	archetype: Archetype,
	row: number,
	dense: i24,
	componentRecord: ArchetypeMap,
}

type EntityIndex = { dense: { [i24]: i53 }, sparse: { [i53]: Record } }

type ArchetypeRecord = number
--[[
TODO:
{
	index: number,
	count: number,
	column: number
} 

]]

type ArchetypeMap = {
	cache: { [number]: ArchetypeRecord },
	first: ArchetypeMap,
	second: ArchetypeMap,
	parent: ArchetypeMap,
	size: number,
}

type ComponentIndex = { [i24]: ArchetypeMap }

type Archetypes = { [ArchetypeId]: Archetype }

local function transitionArchetype(
	entityIndex: EntityIndex,
	to: Archetype,
	destinationRow: i24,
	from: Archetype,
	sourceRow: i24
)
	local columns = from.columns
	local sourceEntities = from.entities
	local destinationEntities = to.entities
	local destinationColumns = to.columns
	local tr = to.records
	local types = from.types

	for i, column in columns do
		-- Retrieves the new column index from the source archetype's record from each component
		-- We have to do this because the columns are tightly packed and indexes may not correspond to each other.
		local targetColumn = destinationColumns[tr[types[i]]]

		-- Sometimes target column may not exist, e.g. when you remove a component.
		if targetColumn then
			targetColumn[destinationRow] = column[sourceRow]
		end
		-- If the entity is the last row in the archetype then swapping it would be meaningless.
		local last = #column
		if sourceRow ~= last then
			-- Swap rempves columns to ensure there are no holes in the archetype.
			column[sourceRow] = column[last]
		end
		column[last] = nil
	end

	local sparse = entityIndex.sparse
	local movedAway = #sourceEntities

	-- Move the entity from the source to the destination archetype.
	-- Because we have swapped columns we now have to update the records
	-- corresponding to the entities' rows that were swapped.
	local e1 = sourceEntities[sourceRow]
	local e2 = sourceEntities[movedAway]

	if sourceRow ~= movedAway then
		sourceEntities[sourceRow] = e2
	end

	sourceEntities[movedAway] = nil
	destinationEntities[destinationRow] = e1

	local record1 = sparse[e1]
	local record2 = sparse[e2]

	record1.row = destinationRow
	record2.row = sourceRow
end

local function archetypeAppend(entity: number, archetype: Archetype): number
	local entities = archetype.entities
	local length = #entities + 1
	entities[length] = entity
	return length
end

local function newEntity(entityId: i53, record: Record, archetype: Archetype)
	local row = archetypeAppend(entityId, archetype)
	record.archetype = archetype
	record.row = row
	return record
end

local function moveEntity(entityIndex: EntityIndex, entityId: i53, record: Record, to: Archetype)
	local sourceRow = record.row
	local from = record.archetype
	local destinationRow = archetypeAppend(entityId, to)
	transitionArchetype(entityIndex, to, destinationRow, from, sourceRow)
	record.archetype = to
	record.row = destinationRow
end

local function hash(arr): string | number
	return table.concat(arr, "_")
end

local function ensureComponentRecord(
	componentIndex: ComponentIndex,
	archetypeId: number,
	componentId: number,
	i: number
): ArchetypeMap
	local archetypesMap = componentIndex[componentId]

	if not archetypesMap then
		archetypesMap = { size = 0, cache = {}, first = {}, second = {} } :: ArchetypeMap
		componentIndex[componentId] = archetypesMap
	end

	archetypesMap.cache[archetypeId] = i
	archetypesMap.size += 1

	return archetypesMap
end

local function archetypeOf(world: any, types: { i24 }, prev: Archetype?): Archetype
	local ty = hash(types)

	local id = world.nextArchetypeId + 1
	world.nextArchetypeId = id

	local length = #types
	local columns = table.create(length)
	local componentIndex = world.componentIndex

	local records = {}
	for i, componentId in types do
		ensureComponentRecord(componentIndex, id, componentId, i)
		records[componentId] = i
		columns[i] = {}
	end

	local archetype = {
		columns = columns,
		edges = {},
		entities = {},
		id = id,
		records = records,
		type = ty,
		types = types,
	}
	world.archetypeIndex[ty] = archetype
	world.archetypes[id] = archetype

	return archetype
end

--[=[
	@class World

	A World contains entities which have components.
	The World is queryable and can be used to get entities with a specific set of components.
	Entities are simply ever-increasing integers.
]=]
local World = {}
World.__index = World

--[=[
	Creates a new World.
]=]
function World.new()
	local world = setmetatable({
		entityIndex = {
			-- Used for checking if an entity is alive
			-- Maps an ID without generation and flags to an ID with
			-- A densely populated map of existing ids
			dense = {},

			-- TBA
			sparse = {},
		},
		componentIndex = {},
		_componentIdToComponent = {},
		archetypes = {},
		archetypeIndex = {},
		_nextId = 0,
		nextArchetypeId = 0,
		_size = 0,
		_changedStorage = {},
		ROOT_ARCHETYPE = (nil :: any) :: Archetype,
	}, World)

	world.ROOT_ARCHETYPE = archetypeOf(world, {})
	return world
end

type World = typeof(World.new())

local function destructColumns(columns, count, row)
	if row == count then
		for _, column in columns do
			column[count] = nil
		end
	else
		for _, column in columns do
			column[row] = column[count]
			column[count] = nil
		end
	end
end

local function archetypeDelete(world: World, id: i53)
	local componentIndex = world.componentIndex
	local archetypesMap = componentIndex[id]
	local archetypes = world.archetypes
	if archetypesMap then
		for archetypeId in archetypesMap.cache do
			for _, entity in archetypes[archetypeId].entities do
				world:remove(entity, id)
			end
		end

		componentIndex[id] = nil
	end
end

local function ensureArchetype(world: World, types, prev)
	if #types < 1 then
		return world.ROOT_ARCHETYPE
	end

	local ty = hash(types)
	local archetype = world.archetypeIndex[ty]
	if archetype then
		return archetype
	end

	return archetypeOf(world, types, prev)
end

local function findInsert(types: { i53 }, toAdd: i53)
	for i, id in types do
		if id == toAdd then
			return -1
		end
		if id > toAdd then
			return i
		end
	end

	return #types + 1
end

local function findArchetypeWith(world: World, node: Archetype, componentId: i53)
	local types = node.types
	-- Component IDs are added incrementally, so inserting and sorting
	-- them each time would be expensive. Instead this insertion sort can find the insertion
	-- point in the types array.

	local destinationType = table.clone(node.types)
	local at = findInsert(types, componentId)
	if at == -1 then
		-- If it finds a duplicate, it just means it is the same archetype so it can return it
		-- directly instead of needing to hash types for a lookup to the archetype.
		return node
	end

	table.insert(destinationType, at, componentId)
	return ensureArchetype(world, destinationType, node)
end

local function ensureEdge(archetype: Archetype, componentId: i53)
	local edges = archetype.edges
	local edge = edges[componentId]
	if not edge then
		edge = {} :: any
		edges[componentId] = edge
	end
	return edge
end

local function archetypeTraverseAdd(world: World, componentId: i53, from: Archetype): Archetype
	from = from or world.ROOT_ARCHETYPE

	local edge = ensureEdge(from, componentId)
	local add = edge.add
	if not add then
		-- Save an edge using the component ID to the archetype to allow
		-- faster traversals to adjacent archetypes.
		add = findArchetypeWith(world, from, componentId)
		edge.add = add :: never
	end

	return add
end

local function componentAdd(world: World, entityId: i53, componentInstance)
	local component = getmetatable(componentInstance)
	local componentId = #component

	-- TODO:
	-- This never gets cleaned up
	world._componentIdToComponent[componentId] = component

	local entityIndex = world.entityIndex
	local record = entityIndex.sparse[entityId]
	local from = record.archetype
	local to = archetypeTraverseAdd(world, componentId, from)

	if from == to then
		-- If the archetypes are the same it can avoid moving the entity
		-- and just set the data directly.
		local archetypeRecord = to.records[componentId]
		from.columns[archetypeRecord][record.row] = componentInstance
		return
	end

	if from then
		-- If there was a previous archetype, then the entity needs to move the archetype
		moveEntity(entityIndex, entityId, record, to)
	else
		if #to.types > 0 then
			-- When there is no previous archetype it should create the archetype
			newEntity(entityId, record, to)
		end
	end

	local archetypeRecord = to.records[componentId]
	to.columns[archetypeRecord][record.row] = componentInstance
end

local function archetypeTraverseRemove(world: World, componentId: i53, archetype: Archetype?): Archetype
	local from = (archetype or world.ROOT_ARCHETYPE) :: Archetype
	local edge = ensureEdge(from, componentId)

	local remove = edge.remove
	if not remove then
		local to = table.clone(from.types)
		table.remove(to, table.find(to, componentId))
		remove = ensureArchetype(world, to, from)
		edge.remove = remove :: never
	end

	return remove
end

local function get(record: Record, componentId: i24): ComponentInstance?
	local archetype = record.archetype
	if archetype == nil then
		return nil
	end

	local archetypeRecord = archetype.records[componentId]
	if not archetypeRecord then
		return nil
	end

	return archetype.columns[archetypeRecord][record.row]
end

local function componentRemove(world: World, entityId: i53, component: Component): ComponentInstance?
	local componentId = #component
	local entityIndex = world.entityIndex
	local record = entityIndex.sparse[entityId]
	local sourceArchetype = record.archetype
	local destinationArchetype = archetypeTraverseRemove(world, componentId, sourceArchetype)

	-- TODO:
	-- There is a better way to get the component for returning
	local componentInstance = get(record, componentId)
	if componentInstance == nil then
		return nil
	end

	if sourceArchetype and not (sourceArchetype == destinationArchetype) then
		moveEntity(entityIndex, entityId, record, destinationArchetype)
	end

	return componentInstance
end

function World.entity(world: World)
	world._nextId += 1
	return world._nextId
end

function World.__iter(world: World)
	local dense = world.entityIndex.dense
	local sparse = world.entityIndex.sparse
	local last

	local componentIdToComponent = world._componentIdToComponent
	print(componentIdToComponent)
	return function()
		local lastEntity, entityId = next(dense, last)
		if not lastEntity then
			return
		end
		last = lastEntity

		local record = sparse[entityId]
		local archetype = record.archetype
		if not archetype then
			-- Returns only the entity id as an entity without data should not return
			-- data and allow the user to get an error if they don't handle the case.
			return entityId
		end

		local row = record.row
		local types = archetype.types
		local columns = archetype.columns
		local entityData = {}
		for i, column in columns do
			-- We use types because the key should be the component ID not the column index
			entityData[componentIdToComponent[types[i]]] = column[row]
		end

		return entityId, entityData
	end
end

function World._trackChanged(world: World, componentId: number, id, old, new)
	if not world._changedStorage[componentId] then
		return
	end

	if old == new then
		return
	end

	local record = table.freeze({
		old = old,
		new = new,
	})

	for _, storage in ipairs(world._changedStorage[componentId]) do
		-- If this entity has changed since the last time this system read it,
		-- we ensure that the "old" value is whatever the system saw it as last, instead of the
		-- "old" value we have here.
		if storage[id] then
			storage[id] = table.freeze({ old = storage[id].old, new = new })
		else
			storage[id] = record
		end
	end
end

--[=[
	Spawns a new entity in the world with the given components.

	@param ... ComponentInstance -- The component values to spawn the entity with.
	@return number -- The new entity ID.
]=]
function World.spawn(world: World, ...: ComponentInstance)
	return world:spawnAt(world._nextId, ...)
end

--[=[
	Spawns a new entity in the world with a specific entity ID and given components.

	The next ID generated from [World:spawn] will be increased as needed to never collide with a manually specified ID.

	@param entityId number -- The entity ID to spawn with
	@param ... ComponentInstance -- The component values to spawn the entity with.
	@return number -- The same entity ID that was passed in
]=]
function World.spawnAt(world: World, entityId: i53, ...: ComponentInstance)
	if world:contains(entityId) then
		error(string.format(ERROR_DUPLICATE_ENTITY, entityId), 2)
	end

	world._size += 1
	if entityId >= world._nextId then
		world._nextId = entityId + 1
	end

	local entityIndex = world.entityIndex
	entityIndex.sparse[entityId] = {
		dense = entityId,
	} :: Record
	entityIndex.dense[entityId] = entityId

	local components = {}
	for i = 1, select("#", ...) do
		local newComponent = select(i, ...)
		assertValidComponentInstance(newComponent, i)

		local metatable = getmetatable(newComponent)
		local componentId = #metatable
		if components[componentId] then
			error(("Duplicate component type at index %d (%s)"):format(i, tostring(metatable)), 2)
		end

		world:_trackChanged(componentId, entityId, nil, newComponent)

		components[componentId] = newComponent
		componentAdd(world, entityId, newComponent)
	end

	return entityId
end

--[=[
	Replaces a given entity by ID with an entirely new set of components.
	Equivalent to removing all components from an entity, and then adding these ones.

	@param id number -- The entity ID
	@param ... ComponentInstance -- The component values to spawn the entity with.
]=]
function World.replace(world: World, entityId: i53, ...: ComponentInstance)
	error("Replace is unimplemented")

	if not world:contains(entityId) then
		error(ERROR_NO_ENTITY, 2)
	end

	--moveEntity(entityId, record, world.ROOT_ARCHETYPE)
	for i = 1, select("#", ...) do
		local newComponent = select(i, ...)
		assertValidComponentInstance(newComponent, i)
	end
end

--[=[
	Despawns a given entity by ID, removing it and all its components from the world entirely.

	@param id number -- The entity ID
]=]
function World.despawn(world: World, entityId: i53)
	local entityIndex = world.entityIndex
	local record = entityIndex[entityId]

	archetypeDelete(world, entityId)
	-- -- TODO:
	-- -- Track despawn changes
	-- if record.archetype then
	-- 	moveEntity(entityIndex, entityId, record, world.ROOT_ARCHETYPE)
	-- 	world.ROOT_ARCHETYPE.entities[record.row] = nil
	-- end

	-- entityIndex[entityId] = nil
	world._size -= 1
end

--[=[
	Removes all entities from the world.

	:::caution
	Removing entities in this way is not reported by `queryChanged`.
	:::
]=]
function World.clear(world: World)
	world.entityIndex = {}
	world.componentIndex = {}
	world.archetypes = {}
	world.archetypeIndex = {}
	world._size = 0
	world.ROOT_ARCHETYPE = archetypeOf(world, {}, nil)
end

--[=[
	Checks if the given entity ID is currently spawned in this world.

	@param id number -- The entity ID
	@return bool -- `true` if the entity exists
]=]
function World.contains(world: World, entityId: i53)
	return world.entityIndex.sparse[entityId] ~= nil
end

--[=[
	Gets a specific component (or set of components) from a specific entity in this world.

	@param id number -- The entity ID
	@param ... Component -- The components to fetch
	@return ... -- Returns the component values in the same order they were passed in
]=]
function World.get(world: World, entityId: i53, ...: Component): any
	local record = world.entityIndex.sparse[entityId]
	if not record then
		error(ERROR_NO_ENTITY, 2)
	end

	local length = select("#", ...)
	local components = {}
	for i = 1, length do
		local metatable = select(i, ...)
		assertValidComponent(metatable, i)
		components[i] = get(record, #metatable)
	end

	return unpack(components, 1, length)
end

local function noop(): any
	return function() end
end

local emptyQueryResult = setmetatable({
	next = function() end,
	snapshot = function()
		return {}
	end,
	without = function(self)
		return self
	end,
	view = function()
		return {
			get = function() end,
			contains = function() end,
		}
	end,
}, {
	__iter = noop,
	__call = noop,
})

local function queryResult(compatibleArchetypes, components: { number }, queryLength, ...): any
	local a: any, b: any, c: any, d: any, e: any, f: any, g: any, h: any = ...
	local lastArchetype, archetype = next(compatibleArchetypes)
	if not lastArchetype then
		return emptyQueryResult
	end

	local lastRow
	local queryOutput = {}
	local function iterate()
		local row = next(archetype.entities, lastRow)
		while row == nil do
			lastArchetype, archetype = next(compatibleArchetypes, lastArchetype)
			if lastArchetype == nil then
				return
			end
			row = next(archetype.entities, row)
		end

		lastRow = row

		local columns = archetype.columns
		local entityId = archetype.entities[row :: number]
		local archetypeRecords = archetype.records

		if queryLength == 1 then
			return entityId, columns[archetypeRecords[a]][row]
		elseif queryLength == 2 then
			return entityId, columns[archetypeRecords[a]][row], columns[archetypeRecords[b]][row]
		elseif queryLength == 3 then
			return entityId,
				columns[archetypeRecords[a]][row],
				columns[archetypeRecords[b]][row],
				columns[archetypeRecords[c]][row]
		elseif queryLength == 4 then
			return entityId,
				columns[archetypeRecords[a]][row],
				columns[archetypeRecords[b]][row],
				columns[archetypeRecords[c]][row],
				columns[archetypeRecords[d]][row]
		elseif queryLength == 5 then
			return entityId,
				columns[archetypeRecords[a]][row],
				columns[archetypeRecords[b]][row],
				columns[archetypeRecords[c]][row],
				columns[archetypeRecords[d]][row],
				columns[archetypeRecords[e]][row]
		elseif queryLength == 6 then
			return entityId,
				columns[archetypeRecords[a]][row],
				columns[archetypeRecords[b]][row],
				columns[archetypeRecords[c]][row],
				columns[archetypeRecords[d]][row],
				columns[archetypeRecords[e]][row],
				columns[archetypeRecords[f]][row]
		elseif queryLength == 7 then
			return columns[archetypeRecords[a]][row],
				columns[archetypeRecords[b]][row],
				columns[archetypeRecords[c]][row],
				columns[archetypeRecords[d]][row],
				columns[archetypeRecords[e]][row],
				columns[archetypeRecords[f]][row],
				columns[archetypeRecords[g]][row]
		elseif queryLength == 8 then
			return columns[archetypeRecords[a]][row],
				columns[archetypeRecords[b]][row],
				columns[archetypeRecords[c]][row],
				columns[archetypeRecords[d]][row],
				columns[archetypeRecords[e]][row],
				columns[archetypeRecords[f]][row],
				columns[archetypeRecords[g]][row],
				columns[archetypeRecords[h]][row]
		end

		for i, componentId in components do
			queryOutput[i] = columns[archetypeRecords[componentId]][row]
		end

		return entityId, unpack(queryOutput, 1, queryLength)
	end
	--[=[
		@class QueryResult

		A result from the [`World:query`](/api/World#query) function.

		Calling the table or the `next` method allows iteration over the results. Once all results have been returned, the
		QueryResult is exhausted and is no longer useful.

		```lua
		for id, enemy, charge, model in world:query(Enemy, Charge, Model) do
			-- Do something
		end
		```
	]=]
	local QueryResult = {}
	QueryResult.__index = QueryResult

	-- TODO:
	-- remove in matter 1.0
	function QueryResult:__call()
		return iterate()
	end

	function QueryResult:__iter()
		return function()
			return iterate()
		end
	end

	--[=[
		Returns an iterator that will skip any entities that also have the given components.

		@param ... Component -- The component types to filter against.
		@return () -> (id, ...ComponentInstance) -- Iterator of entity ID followed by the requested component values

		```lua
		for id in world:query(Target):without(Model) do
			-- Do something
		end
		```
	]=]
	function QueryResult:without(...)
		local components = { ... }
		for i, component in components do
			components[i] = #component
		end

		local compatibleArchetypes = compatibleArchetypes
		for i = #compatibleArchetypes, 1, -1 do
			local archetype = compatibleArchetypes[i]
			local shouldRemove = false
			for _, componentId in components do
				if archetype.records[componentId] then
					shouldRemove = true
					break
				end
			end

			if shouldRemove then
				table.remove(compatibleArchetypes, i)
			end
		end

		lastArchetype, archetype = next(compatibleArchetypes)
		if not lastArchetype then
			return emptyQueryResult
		end

		return self
	end

	--[=[
		Returns the next set of values from the query result. Once all results have been returned, the
		QueryResult is exhausted and is no longer useful.

		:::info
		This function is equivalent to calling the QueryResult as a function. When used in a for loop, this is implicitly
		done by the language itself.
		:::

		```lua
		-- Using world:query in this position will make Lua invoke the table as a function. This is conventional.
		for id, enemy, charge, model in world:query(Enemy, Charge, Model) do
			-- Do something
		end
		```

		If you wanted to iterate over the QueryResult without a for loop, it's recommended that you call `next` directly
		instead of calling the QueryResult as a function.
		```lua
		local id, enemy, charge, model = world:query(Enemy, Charge, Model):next()
		local id, enemy, charge, model = world:query(Enemy, Charge, Model)() -- Possible, but unconventional
		```

		@return id -- Entity ID
		@return ...ComponentInstance -- The requested component values
	]=]
	function QueryResult:next()
		return iterate()
	end

	local function drain()
		local entry = table.pack(iterate())
		return if entry.n > 0 then entry else nil
	end

	local Snapshot = {
		__iter = function(self): any
			local i = 0
			return function()
				i += 1

				local data = self[i] :: any

				if data then
					return unpack(data, 1, data.n)
				end

				return
			end
		end,
	}

	function QueryResult:snapshot()
		local list = setmetatable({}, Snapshot) :: any
		for entry in drain do
			table.insert(list, entry)
		end

		return list
	end

	--[=[
		Creates a View of the query and does all of the iterator tasks at once at an amortized cost.
		This is used for many repeated random access to an entity. If you only need to iterate, just use a query.

		```lua
		local inflicting = world:query(Damage, Hitting, Player):view()
		for _, source in world:query(DamagedBy) do
			local damage = inflicting:get(source.from)
		end

		for _ in world:query(Damage):view() do end -- You can still iterate views if you want!
		```
		
		@return View See [View](/api/View) docs.
	]=]
	function QueryResult:view()
		local fetches = {}
		local list = {} :: any

		local View = {}
		View.__index = View

		function View:__iter()
			local current = list.head
			return function()
				if not current then
					return
				end
				local entity = current.entity
				local fetch = fetches[entity]
				current = current.next

				return entity, unpack(fetch, 1, fetch.n)
			end
		end

		--[=[
			@within View
				Retrieve the query results to corresponding `entity`
			@param entity number - the entity ID
			@return ...ComponentInstance
		]=]
		function View:get(entity)
			if not self:contains(entity) then
				return
			end

			local fetch = fetches[entity]
			local queryLength = fetch.n

			if queryLength == 1 then
				return fetch[1]
			elseif queryLength == 2 then
				return fetch[1], fetch[2]
			elseif queryLength == 3 then
				return fetch[1], fetch[2], fetch[3]
			elseif queryLength == 4 then
				return fetch[1], fetch[2], fetch[3], fetch[4]
			elseif queryLength == 5 then
				return fetch[1], fetch[2], fetch[3], fetch[4], fetch[5]
			end

			return unpack(fetch, 1, fetch.n)
		end

		--[=[
			@within View
			Equivalent to `world:contains()`	
			@param entity number - the entity ID
			@return boolean 
		]=]
		function View:contains(entity)
			return fetches[entity] ~= nil
		end

		for entry in drain do
			local entityId = entry[1]
			local fetch = table.pack(select(2, unpack(entry)))
			local node = { entity = entityId, next = nil }
			fetches[entityId] = fetch

			if not list.head then
				list.head = node
			else
				local current = list.head
				while current.next do
					current = current.next
				end
				current.next = node
			end
		end

		return setmetatable({}, View)
	end

	return setmetatable({}, QueryResult)
end

--[=[
	Performs a query against the entities in this World. Returns a [QueryResult](/api/QueryResult), which iterates over
	the results of the query.

	Order of iteration is not guaranteed.

	```lua
	for id, enemy, charge, model in world:query(Enemy, Charge, Model) do
		-- Do something
	end

	for id in world:query(Target):without(Model) do
		-- Again, with feeling
	end
	```

	@param ... Component -- The component types to query. Only entities with *all* of these components will be returned.
	@return QueryResult -- See [QueryResult](/api/QueryResult) docs.
]=]
function World.query(world: World, ...: Component): any
	local compatibleArchetypes = {}
	local components = { ... }
	local archetypes = world.archetypes
	local queryLength = select("#", ...)
	local a: any, b: any, c: any, d: any, e: any, f: any, g: any, h: any = ...

	if queryLength == 0 then
		return emptyQueryResult
	end

	if queryLength == 1 then
		a = #a
		components = { a }
		-- local archetypesMap = world.componentIndex[a]
		-- components = { a }
		-- local function single()
		-- 	local id = next(archetypesMap)
		-- 	local archetype = archetypes[id :: number]
		-- 	local lastRow

		-- 	return function(): any
		-- 		local row, entity = next(archetype.entities, lastRow)
		-- 		while row == nil do
		-- 			id = next(archetypesMap, id)
		-- 			if id == nil then
		-- 				return
		-- 			end
		-- 			archetype = archetypes[id]
		-- 			row = next(archetype.entities, row)
		-- 		end
		-- 		lastRow = row

		-- 		return entity, archetype.columns[archetype.records[a]]
		-- 	end
		-- end
		-- return single()
	elseif queryLength == 2 then
		--print("iter double")
		a = #a
		b = #b
		components = { a, b }

		-- --print(a, b, world.componentIndex)
		-- --[[local archetypesMap = world.componentIndex[a]
		-- for id in archetypesMap do
		-- 	local archetype = archetypes[id]
		-- 	if archetype.records[b] then
		-- 		table.insert(compatibleArchetypes, archetype)
		-- 	end
		-- end

		-- local function double(): () -> (number, any, any)
		-- 	local lastArchetype, archetype = next(compatibleArchetypes)
		-- 	local lastRow

		-- 	return function()
		-- 		local row = next(archetype.entities, lastRow)
		-- 		while row == nil do
		-- 			lastArchetype, archetype = next(compatibleArchetypes, lastArchetype)
		-- 			if lastArchetype == nil then
		-- 				return
		-- 			end

		-- 			row = next(archetype.entities, row)
		-- 		end
		-- 		lastRow = row

		-- 		local entity = archetype.entities[row :: number]
		-- 		local columns = archetype.columns
		-- 		local archetypeRecords = archetype.records
		-- 		return entity, columns[archetypeRecords[a]], columns[archetypeRecords[b]]
		-- 	end
		-- end
		-- return double()
	elseif queryLength == 3 then
		a = #a
		b = #b
		c = #c
		components = { a, b, c }
	elseif queryLength == 4 then
		a = #a
		b = #b
		c = #c
		d = #d

		components = { a, b, c, d }
	elseif queryLength == 5 then
		a = #a
		b = #b
		c = #c
		d = #d
		e = #e

		components = { a, b, c, d, e }
	elseif queryLength == 6 then
		a = #a
		b = #b
		c = #c
		d = #d
		e = #e
		f = #f

		components = { a, b, c, d, e, f }
	elseif queryLength == 7 then
		a = #a
		b = #b
		c = #c
		d = #d
		e = #e
		f = #f
		g = #g

		components = { a, b, c, d, e, f, g }
	elseif queryLength == 8 then
		a = #a
		b = #b
		c = #c
		d = #d
		e = #e
		f = #f
		g = #g
		h = #h

		components = { a, b, c, d, e, f, g, h }
	else
		for i, component in components do
			components[i] = (#component) :: any
		end
	end

	local firstArchetypeMap: ArchetypeMap
	local componentIndex = world.componentIndex
	for _, componentId in (components :: any) :: { number } do
		local map = componentIndex[componentId]
		if not map then
			return emptyQueryResult
		end

		if firstArchetypeMap == nil or map.size < firstArchetypeMap.size then
			firstArchetypeMap = map
		end
	end

	for id in firstArchetypeMap.cache do
		local archetype = archetypes[id]
		local archetypeRecords = archetype.records
		local matched = true
		for _, componentId in components do
			if not archetypeRecords[componentId] then
				matched = false
				break
			end
		end

		if matched then
			table.insert(compatibleArchetypes, archetype)
		end
	end

	return queryResult(compatibleArchetypes, components :: any, queryLength, a, b, c, d, e, f, g, h)
end

local function cleanupQueryChanged(hookState)
	local world = hookState.world
	local componentToTrack = hookState.componentToTrack

	for index, object in world._changedStorage[componentToTrack] do
		if object == hookState.storage then
			table.remove(world._changedStorage[componentToTrack], index)
			break
		end
	end

	if next(world._changedStorage[componentToTrack]) == nil then
		world._changedStorage[componentToTrack] = nil
	end
end

function World.queryChanged(world: World, componentToTrack, ...: nil)
	if ... then
		error("World:queryChanged does not take any additional parameters", 2)
	end

	local hookState = topoRuntime.useHookState(componentToTrack, cleanupQueryChanged) :: any
	if hookState.storage then
		return function(): any
			local entityId, record = next(hookState.storage)

			if entityId then
				hookState.storage[entityId] = nil

				return entityId, record
			end
			return
		end
	end

	if not world._changedStorage[componentToTrack] then
		world._changedStorage[componentToTrack] = {}
	end

	local storage = {}
	hookState.storage = storage
	hookState.world = world
	hookState.componentToTrack = componentToTrack

	table.insert(world._changedStorage[componentToTrack], storage)

	-- TODO:
	-- Go back to lazy evaluation of the query
	-- Switched because next is not working
	local snapshot = world:query(componentToTrack):snapshot()
	local last
	return function(): any
		local index, entry = next(snapshot, last)
		last = index

		if not index then
			return
		end

		local entityId, component = entry[1], entry[2]
		if entityId then
			return entityId, table.freeze({ new = component })
		end

		return
	end
end

--[=[
	Inserts a component (or set of components) into an existing entity.

	If another instance of a given component already exists on this entity, it is replaced.

	```lua
	world:insert(
		entityId,
		ComponentA({
			foo = "bar"
		}),
		ComponentB({
			baz = "qux"
		})
	)
	```

	@param id number -- The entity ID
	@param ... ComponentInstance -- The component values to insert
]=]
function World.insert(world: World, entityId: i53, ...)
	if not world:contains(entityId) then
		error(ERROR_NO_ENTITY, 2)
	end

	for i = 1, select("#", ...) do
		local newComponent = select(i, ...)
		assertValidComponentInstance(newComponent, i)

		local metatable = getmetatable(newComponent)
		local componentId = #metatable
		local oldComponent = world:get(entityId, metatable)
		componentAdd(world, entityId, newComponent)

		world:_trackChanged(componentId, entityId, oldComponent, newComponent)
	end
end

--[=[
	Removes a component (or set of components) from an existing entity.

	```lua
	local removedA, removedB = world:remove(entityId, ComponentA, ComponentB)
	```

	@param entityId number -- The entity ID
	@param ... Component -- The components to remove
	@return ...ComponentInstance -- Returns the component instance values that were removed in the order they were passed.
]=]
function World.remove(world: World, entityId: i53, ...)
	if not world:contains(entityId) then
		error(ERROR_NO_ENTITY, 2)
	end

	local length = select("#", ...)
	local removed = {}
	for i = 1, length do
		local component = select(i, ...)
		local componentId = #getmetatable(component)
		local oldComponent = componentRemove(world, entityId, component)
		if not oldComponent then
			continue
		end

		table.insert(removed, oldComponent)
		world:_trackChanged(componentId, entityId, oldComponent, nil)
	end

	return unpack(removed, 1, length)
end

--[=[
	Returns the number of entities currently spawned in the world.
]=]
function World.size(world: World)
	return world._size
end

return World
