--!optimize 2
--!native
--!strict
local component = require(script.Parent.component)
local topoRuntime = require(script.Parent.topoRuntime)
local Component = require(script.Parent.component)

local assertValidComponentInstance = Component.assertValidComponentInstance
local assertValidComponent = Component.assertValidComponent

local ERROR_NO_ENTITY = "Entity doesn't exist, use world:contains to check if needed"
local ERROR_DUPLICATE_ENTITY =
	"The world already contains an entity with ID %d. Use World:replace instead if this is intentional."
local ERROR_NO_COMPONENTS = "Missing components"

type i53 = number
type i24 = number

type Component = { [any]: any }
type ComponentInstance = Component

type Ty = { i53 }
type ArchetypeId = number

type Column = { any }

type Archetype = {
	-- Unique identifier of this archetype
	id: number,
	edges: {
		[i24]: {
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
}

type EntityIndex = { [i24]: Record }
type ComponentIndex = { [i24]: ArchetypeMap }

type ArchetypeRecord = number
type ArchetypeMap = { sparse: { [ArchetypeId]: ArchetypeRecord }, size: number }
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

	for componentId, column in columns do
		local targetColumn = destinationColumns[tr[types[componentId]]]
		if targetColumn then
			targetColumn[destinationRow] = column[sourceRow]
		end

		local last = #column
		if sourceRow ~= last then
			column[sourceRow] = column[last]
		end

		column[last] = nil
	end

	local atSourceRow = sourceEntities[sourceRow]
	destinationEntities[destinationRow] = atSourceRow
	entityIndex[atSourceRow].row = destinationRow

	local movedAway = #sourceEntities
	if sourceRow ~= movedAway then
		local atMovedAway = sourceEntities[movedAway]
		sourceEntities[sourceRow] = atMovedAway
		entityIndex[atMovedAway].row = sourceRow
	end

	sourceEntities[movedAway] = nil
end

local function archetypeAppend(entity: i53, archetype: Archetype): i24
	local entities = archetype.entities
	table.insert(entities, entity)
	return #entities
end

local function newEntity(entityId: i53, record: Record, archetype: Archetype)
	local row = archetypeAppend(entityId, archetype)
	record.archetype = archetype
	record.row = row
	return record
end

local function moveEntity(entityIndex, entityId: i53, record: Record, to: Archetype)
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

local function createArchetypeRecords(componentIndex: ComponentIndex, to: Archetype)
	local destinationIds = to.types
	local records = to.records
	local id = to.id

	for i, destinationId in destinationIds do
		local archetypesMap = componentIndex[destinationId]

		if not archetypesMap then
			archetypesMap = { size = 0, sparse = {} }
			componentIndex[destinationId] = archetypesMap
		end

		archetypesMap.sparse[id] = i
		records[destinationId] = i
	end
end

local function archetypeOf(world: World, types: { i24 }, prev: Archetype?): Archetype
	local ty = hash(types)

	world.nextArchetypeId = (world.nextArchetypeId :: number) + 1
	local id = world.nextArchetypeId

	local length = #types
	local columns = table.create(length) :: { any }

	for index in types do
		columns[index] = {}
	end

	local archetype = {
		id = id,
		types = types,
		type = ty,
		columns = columns,
		entities = {},
		edges = {},
		records = {},
	}

	world.archetypeIndex[ty] = archetype
	world.archetypes[id] = archetype

	if length > 0 then
		createArchetypeRecords(world.componentIndex, archetype)
	end

	return archetype
end

local World = {}
World.__index = World

function World.new()
	local self = setmetatable({
		entityIndex = {},
		componentIndex = {},
		componentIdToComponent = {},
		archetypes = {},
		archetypeIndex = {},
		nextId = 0,
		nextArchetypeId = 0,
		_size = 0,
		_changedStorage = {},
		ROOT_ARCHETYPE = (nil :: any) :: Archetype,
	}, World)

	return self
end

type World = typeof(World.new())

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
	local at = findInsert(types, componentId)
	if at == -1 then
		return node
	end

	local destinationType = table.clone(node.types)
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

local function archetypeTraverseAdd(world: World, componentId: i53, from: Archetype?): Archetype
	if not from then
		-- If there was no source archetype then it should return the ROOT_ARCHETYPE
		local ROOT_ARCHETYPE = world.ROOT_ARCHETYPE
		if not ROOT_ARCHETYPE then
			ROOT_ARCHETYPE = archetypeOf(world, {}, nil)
			world.ROOT_ARCHETYPE = ROOT_ARCHETYPE :: never
		end

		from = ROOT_ARCHETYPE
	end

	local edge = ensureEdge(from :: Archetype, componentId)
	local add = edge.add
	if not add then
		-- Save an edge using the component ID to the archetype to allow
		-- faster traversals to adjacent archetypes.
		add = findArchetypeWith(world, from :: Archetype, componentId)
		edge.add = add :: never
	end

	return add
end

local function ensureRecord(entityIndex, entityId): Record
	local record = entityIndex[entityId]

	if not record then
		record = {}
		entityIndex[entityId] = record
	end

	return record :: Record
end

local function componentAdd(world: World, entityId: i53, componentInstance)
	local component = getmetatable(componentInstance)
	local componentId = #component

	-- TODO:
	-- This never gets cleaned up
	world.componentIdToComponent[componentId] = component

	local record = ensureRecord(world.entityIndex, entityId)
	local sourceArchetype = record.archetype
	local destinationArchetype = archetypeTraverseAdd(world, componentId, sourceArchetype)

	if sourceArchetype == destinationArchetype then
		local archetypeRecord = destinationArchetype.records[componentId]
		destinationArchetype.columns[archetypeRecord][record.row] = componentInstance
		return
	end

	if sourceArchetype then
		moveEntity(world.entityIndex, entityId, record, destinationArchetype)
	else
		-- if it has any components, then it wont be the root archetype
		if #destinationArchetype.types > 0 then
			newEntity(entityId, record, destinationArchetype)
		end
	end

	local archetypeRecord = destinationArchetype.records[componentId]
	destinationArchetype.columns[archetypeRecord][record.row] = componentInstance
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
	local record = ensureRecord(world.entityIndex, entityId)
	local sourceArchetype = record.archetype
	local destinationArchetype = archetypeTraverseRemove(world, componentId, sourceArchetype)

	-- TODO:
	-- There is a better way to get the component for returning
	local componentInstance = get(record, componentId)
	if componentInstance == nil then
		return nil
	end

	if sourceArchetype and not (sourceArchetype == destinationArchetype) then
		moveEntity(world.entityIndex, entityId, record, destinationArchetype)
	end

	return componentInstance
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
		local oldComponent = componentRemove(world, entityId, select(i, ...))
		if not oldComponent then
			continue
		end

		table.insert(removed, oldComponent)

		world:_trackChanged(select(i, ...), entityId, oldComponent, nil)
	end

	return unpack(removed, 1, length)
end

function World.get(world: World, entityId: i53, ...: Component): any
	local componentIndex = world.componentIndex
	local record = world.entityIndex[entityId]
	if not record then
		return nil
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

function World.insert(world: World, entityId: i53, ...)
	if not world:contains(entityId) then
		error(ERROR_NO_ENTITY, 2)
	end

	for i = 1, select("#", ...) do
		local newComponent = select(i, ...)
		assertValidComponentInstance(newComponent, i)

		local metatable = getmetatable(newComponent)
		local oldComponent = world:get(entityId, metatable)
		componentAdd(world, entityId, newComponent)

		world:_trackChanged(metatable, entityId, oldComponent, newComponent)
	end
end

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

function World.entity(world: World)
	world.nextId += 1
	return world.nextId
end

function World:__iter()
	local previous = nil
	return function()
		local entityId, data = next(self.entityIndex, previous)
		previous = entityId

		if entityId == nil then
			return nil
		end

		local archetype = data.archetype
		if not archetype then
			return entityId, {}
		end

		local columns = archetype.columns
		local components = {}
		for i, map in columns do
			local componentId = archetype.types[i]
			components[self.componentIdToComponent[componentId]] = map[data.row]
		end

		return entityId, components
	end
end

function World._trackChanged(world: World, metatable, id, old, new)
	if not world._changedStorage[metatable] then
		return
	end

	if old == new then
		return
	end

	local record = table.freeze({
		old = old,
		new = new,
	})

	for _, storage in ipairs(world._changedStorage[metatable]) do
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

	if entityId >= world.nextId then
		world.nextId = entityId + 1
	end

	world._size += 1
	ensureRecord(world.entityIndex, entityId)

	local components = {}
	for i = 1, select("#", ...) do
		local component = select(i, ...)
		assertValidComponentInstance(component, i)

		local metatable = getmetatable(component)
		if components[metatable] then
			error(("Duplicate component type at index %d"):format(i), 2)
		end

		world:_trackChanged(metatable, entityId, nil, component)

		components[metatable] = component
		componentAdd(world, entityId, component)
	end

	return entityId
end

--[=[
	Spawns a new entity in the world with the given components.

	@param ... ComponentInstance -- The component values to spawn the entity with.
	@return number -- The new entity ID.
]=]
function World.spawn(world: World, ...: ComponentInstance)
	return world:spawnAt(world.nextId, ...)
end

function World.despawn(world: World, entityId: i53)
	local entityIndex = world.entityIndex
	local record = entityIndex[entityId]

	-- TODO:
	-- Track despawn changes
	if record.archetype then
		moveEntity(entityIndex, entityId, record, world.ROOT_ARCHETYPE)
		world.ROOT_ARCHETYPE.entities[record.row] = nil
	end

	entityIndex[entityId] = nil
	world._size -= 1
end

function World.clear(world: World)
	world.entityIndex = {}
	world.componentIndex = {}
	world.archetypes = {}
	world.archetypeIndex = {}
	world._size = 0
	world.ROOT_ARCHETYPE = archetypeOf(world, {}, nil)
end

function World.size(world: World)
	return world._size
end

function World.contains(world: World, entityId: i53)
	return world.entityIndex[entityId] ~= nil
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

	local firstArchetypeMap
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

	for id in firstArchetypeMap.sparse do
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

return World
