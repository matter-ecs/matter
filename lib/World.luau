--!native
--!optimize 2

local Archetype = require(script.Parent.Archetype)
local Component = require(script.Parent.component)
local topoRuntime = require(script.Parent.topoRuntime)

local assertValidComponentInstances = Component.assertValidComponentInstances
local assertValidComponent = Component.assertValidComponent
local assertComponentArgsProvided = Component.assertComponentArgsProvided

type EntityId = Archetype.EntityId
type ComponentId = Archetype.ComponentId

type Component = Archetype.Component
type ComponentInstance = Archetype.ComponentInstance

type Archetype = Archetype.Archetype

type EntityRecord = {
	indexInArchetype: number,
	archetype: Archetype,
}

-- Find archetype for entity
type Entities = { [EntityId]: EntityRecord? }

-- Find archetype from all components
type Archetypes = { Archetype }

local ERROR_NO_ENTITY = "Entity doesn't exist, use world:contains to check if needed"
local ERROR_EXISTING_ENTITY =
	"The world already contains an entity with ID %s. Use world:replace instead if this is intentional."

-- The old solver is not great at resolving intersections, so we redefine entityId each time.
type DespawnCommand = { type: "despawn", entityId: number }

type InsertCommand = {
	type: "insert",
	entityId: number,
	componentInstances: { [any]: any },
}

type RemoveCommand = {
	type: "remove",
	entityId: number,
	components: { [any]: any },
}

type ReplaceCommand = {
	type: "replace",
	entityId: number,
	componentInstances: { [any]: any },
}

type Command = DespawnCommand | InsertCommand | RemoveCommand | ReplaceCommand

local function assertEntityExists(world, id: number)
	assert(world:contains(id), "Entity doesn't exist, use world:contains to check if needed")
end

local function assertWorldOperationIsValid(world, id: number, ...)
	assertEntityExists(world, id)
	assertComponentArgsProvided(...)
end

--[=[
	@class World

	A World contains entities which have components.
	The World is queryable and can be used to get entities with a specific set of components.
	Entities are simply ever-increasing integers.
]=]
local World = {}
World.__index = World

local function ensureArchetype(world: World, componentIds: { ComponentId })
	local archetypeId = Archetype.hash(componentIds)
	local existingArchetype = world.hashToArchetype[archetypeId]
	if existingArchetype then
		return existingArchetype
	end

	-- Create new archetype
	local archetype, archetypeId = Archetype.new(componentIds)
	world.hashToArchetype[archetypeId] = archetype
	table.insert(world.archetypes, archetype)

	for _, componentId in componentIds do
		local associatedArchetypes = world.componentToArchetypes[componentId]
		if associatedArchetypes == nil then
			associatedArchetypes = {}
			world.componentToArchetypes[componentId] = associatedArchetypes
		end

		table.insert(associatedArchetypes, archetype)
	end

	return archetype
end

--[=[
	Creates a new World.
]=]
function World.new()
	local self = setmetatable({
		archetypes = {} :: { Archetype },
		allEntities = {} :: { [EntityId]: EntityRecord? },

		componentIdToComponent = {} :: { [ComponentId]: Component },
		componentToArchetypes = {} :: { [ComponentId]: { Archetype } },
		hashToArchetype = {} :: { [string]: Archetype? },

		-- Is the world buffering commands?
		deferring = false,

		-- The commands that are queued
		commands = {} :: { Command },

		-- Entities marked for deletion by commands, but not deleted yet
		markedForDeletion = {},

		-- The next ID that will be assigned with World:spawn
		_nextId = 1,

		-- The total number of active entities in the world
		_size = 0,

		-- Storage for `queryChanged`
		_changedStorage = {},
	}, World)

	self.rootArchetype = ensureArchetype(self, {})
	return self
end

export type World = typeof(World.new())

--[=[
	Iterates over all entities in this World. Iteration returns entity ID followed by a dictionary mapping
	Component to Component Instance.

	**Usage:**

	```lua
	for entityId, entityData in world do
		print(entityId, entityData[Components.Example])
	end
	```

	@return number
	@return {[Component]: ComponentInstance}
]=]
function World.__iter(world: World)
	local lastEntityId = nil
	return function(): (number?, ...any)
		local entityId, entityRecord = next(world.allEntities, lastEntityId)
		if entityId == nil or entityRecord == nil then
			return nil
		end

		lastEntityId = entityId

		local componentIdToComponent = world.componentIdToComponent
		local archetype = entityRecord.archetype
		local componentInstances = {}
		for index, componentStorage in archetype.fields do
			componentInstances[componentIdToComponent[archetype.indexToId[index]]] =
				componentStorage[entityRecord.indexInArchetype]
		end

		return entityId, componentInstances
	end
end

local function ensureRecord(world: World, entityId: number): EntityRecord
	local entityRecord = world.allEntities[entityId]
	if entityRecord == nil then
		local rootArchetype = world.rootArchetype
		entityRecord = {
			archetype = rootArchetype,
			indexInArchetype = #rootArchetype.entities + 1,
		}

		table.insert(rootArchetype.entities, entityId)
		world.allEntities[entityId] = entityRecord
	end

	return entityRecord :: EntityRecord
end

local function transitionArchetype(
	world: World,
	entityId: number,
	entityRecord: EntityRecord,
	archetype: Archetype
): number
	local oldArchetype = entityRecord.archetype
	local oldEntityIndex = entityRecord.indexInArchetype

	-- Add entity to archetype's entities
	local entities = archetype.entities
	local entityIndex = #entities + 1
	entities[entityIndex] = entityId

	-- Move old storage to new storage if needed
	local oldNumEntities = #oldArchetype.entities
	local wasLastEntity = oldNumEntities == oldEntityIndex
	for index, oldComponentStorage in oldArchetype.fields do
		local componentStorage = archetype.fields[archetype.idToIndex[oldArchetype.componentIds[index]]]

		-- Does the new storage contain this component?
		if componentStorage then
			componentStorage[entityIndex] = oldComponentStorage[oldEntityIndex]
		end

		-- Swap entity component storage
		if not wasLastEntity then
			oldComponentStorage[oldEntityIndex] = oldComponentStorage[oldNumEntities]
		end

		oldComponentStorage[oldNumEntities] = nil
	end

	-- Swap entity location marker
	if not wasLastEntity then
		oldArchetype.entities[oldEntityIndex] = oldArchetype.entities[oldNumEntities];
		(world.allEntities[oldArchetype.entities[oldEntityIndex]] :: EntityRecord).indexInArchetype = oldEntityIndex
	end

	-- Remove from old archetype
	oldArchetype.entities[oldNumEntities] = nil

	-- Mark entity as being in new archetype
	entityRecord.indexInArchetype = entityIndex
	entityRecord.archetype = archetype

	return entityIndex
end

local function executeDespawn(world: World, despawnCommand: DespawnCommand)
	local entityId = despawnCommand.entityId
	local entityRecord = ensureRecord(world, entityId)
	local archetype = entityRecord.archetype

	-- Track changes
	for _, componentStorage in archetype.fields do
		local componentInstance = componentStorage[entityRecord.indexInArchetype]
		local component = getmetatable(componentInstance :: any)
		world:_trackChanged(component, entityId, componentInstance, nil)
	end

	-- TODO:
	-- Optimize remove so no cascades
	transitionArchetype(world, entityId, entityRecord, world.rootArchetype)
	table.remove(world.rootArchetype.entities, entityRecord.indexInArchetype)
	world.allEntities[entityId] = nil

	world._size -= 1
end

local function executeInsert(world: World, insertCommand: InsertCommand)
	debug.profilebegin("World:insert")

	local entityId = insertCommand.entityId
	local entityRecord = ensureRecord(world, entityId)
	local componentInstances = insertCommand.componentInstances

	local oldArchetype = entityRecord.archetype
	for _, componentInstance in componentInstances do
		local component = getmetatable(componentInstance)
		local componentId = #component
		local componentIds = table.clone(oldArchetype.componentIds)

		local archetype: Archetype
		local entityIndex: number
		local oldComponentInstance: ComponentInstance?
		if oldArchetype.idToIndex[componentId] == nil then
			table.insert(componentIds, componentId)
			archetype = ensureArchetype(world, componentIds)
			entityIndex = transitionArchetype(world, entityId, entityRecord, archetype)
			oldComponentInstance = archetype.fields[archetype.idToIndex[componentId]][entityIndex]

			-- FIXME:
			-- This shouldn't be in a hotpath, probably better in createArchetype
			world.componentIdToComponent[componentId] = component
		else
			archetype = oldArchetype
			entityIndex = entityRecord.indexInArchetype
			oldComponentInstance = oldArchetype.fields[oldArchetype.idToIndex[componentId]][entityIndex]
		end

		archetype.fields[archetype.idToIndex[componentId]][entityIndex] = componentInstance
		world:_trackChanged(component, entityId, oldComponentInstance, componentInstance)

		oldArchetype = archetype
	end

	debug.profileend()
end

local function executeReplace(world: World, replaceCommand: ReplaceCommand)
	local entityId = replaceCommand.entityId
	if not world:contains(entityId) then
		error(ERROR_NO_ENTITY, 2)
	end

	local entityRecord = ensureRecord(world, entityId)
	local oldArchetype = entityRecord.archetype

	local componentIds = {}
	local componentIdMap = {}

	-- Track new
	for _, componentInstance in replaceCommand.componentInstances do
		local component = getmetatable(componentInstance)
		local componentId = #component
		table.insert(componentIds, componentId)

		local storageIndex = oldArchetype.idToIndex[componentId]
		world:_trackChanged(
			component,
			entityId,
			if storageIndex then oldArchetype.fields[storageIndex][entityRecord.indexInArchetype] else nil,
			componentInstance
		)

		componentIdMap[componentId] = true
	end

	-- Track removed
	for index, componentStorage in oldArchetype.fields do
		local componentId = oldArchetype.indexToId[index]
		if componentIdMap[componentId] == nil then
			local component = world.componentIdToComponent[componentId]
			world:_trackChanged(component, entityId, componentStorage[entityRecord.indexInArchetype], nil)
		end
	end

	transitionArchetype(world, entityId, entityRecord, world.rootArchetype)
	transitionArchetype(world, entityId, entityRecord, ensureArchetype(world, componentIds))
	executeInsert(
		world,
		{ type = "insert", componentInstances = replaceCommand.componentInstances, entityId = entityId }
	)
end

local function executeRemove(world: World, removeCommand: RemoveCommand)
	local entityId = removeCommand.entityId
	local entityRecord = ensureRecord(world, entityId)
	local archetype = entityRecord.archetype
	local componentIds = table.clone(entityRecord.archetype.componentIds)

	local didRemove = false
	for _, component in removeCommand.components do
		local componentId = #component
		local index = table.find(componentIds, componentId)
		if index then
			local componentInstance = archetype.fields[archetype.idToIndex[componentId]][entityRecord.indexInArchetype]
			world:_trackChanged(component, entityId, componentInstance, nil)

			table.remove(componentIds, index)
			didRemove = true
		end
	end

	if didRemove then
		transitionArchetype(world, entityId, entityRecord, ensureArchetype(world, componentIds))
	end
end

local function processCommand(world: World, command: Command)
	if command.type == "insert" then
		executeInsert(world, command)
	elseif command.type == "despawn" then
		executeDespawn(world, command)
	elseif command.type == "remove" then
		executeRemove(world, command)
	elseif command.type == "replace" then
		executeReplace(world, command)
	else
		error(`Unknown command type: {command.type}`)
	end
end

local function bufferCommand(world: World, command: Command)
	if world.deferring then
		-- We want to ignore commands that succeed a deletion.
		-- Spawn isn't considered a command, and so it never reaches here.
		local markedForDeletion = world.markedForDeletion
		if markedForDeletion[command.entityId] then
			return
		end

		if command.type == "despawn" then
			markedForDeletion[command.entityId] = true
		end

		table.insert(world.commands, command)
	else
		processCommand(world, command)
	end
end

--[=[
	Starts deferring entity commands.

	If you are using a [`Loop`](/api/Loop), this is done for you.
]=]
function World:startDeferring()
	self.deferring = true
end

--[=[
	Sequentially processes all of the commands in the buffer.

	If you are using a [`Loop`](/api/Loop), this is called after every system.
	However, you can call it more often if you want.
]=]
function World:commitCommands()
	for _, command in self.commands do
		processCommand(self, command)
	end

	table.clear(self.commands)
end

--[=[
	Stops deferring entity commands and processes all commands left in the buffer.
]=]
function World:stopDeferring()
	self:commitCommands()
	self.deferring = false
end

--[=[
	Spawns a new entity in the world with the given components.

	@param ... ComponentInstance -- The component values to spawn the entity with.
	@return number -- The new entity ID.
]=]

function World:spawn(...)
	return self:spawnAt(self._nextId, ...)
end

--[=[
	Spawns a new entity in the world with a specific entity ID and given components.

	The next ID generated from [World:spawn] will be increased as needed to never collide with a manually specified ID.

	@param id number -- The entity ID to spawn with
	@param ... ComponentInstance -- The component values to spawn the entity with.
	@return number -- The same entity ID that was passed in
]=]
function World:spawnAt(id: number, ...)
	if id >= self._nextId then
		self._nextId = id + 1
	end

	local componentInstances = { ... }
	assertValidComponentInstances(componentInstances)

	local willBeDeleted = self.markedForDeletion[id] ~= nil
	if self:contains(id) and not willBeDeleted then
		error(string.format(ERROR_EXISTING_ENTITY, id), 2)
	end

	if not willBeDeleted then
		self._size += 1
	end

	self.markedForDeletion[id] = nil

	ensureRecord(self, id)
	bufferCommand(self, { type = "insert", entityId = id, componentInstances = componentInstances })
	return id
end

--[=[
	Replaces a given entity by ID with an entirely new set of components.
	Equivalent to removing all components from an entity, and then adding these ones.

	@param id number -- The entity ID
	@param ... ComponentInstance -- The component values to spawn the entity with.
]=]
function World:replace(id, ...)
	local componentInstances = { ... }
	assertValidComponentInstances(componentInstances)

	bufferCommand(self, { type = "replace", entityId = id, componentInstances = componentInstances })
end

--[=[
	Despawns a given entity by ID, removing it and all its components from the world entirely.

	@param id number -- The entity ID
]=]
function World:despawn(id)
	if not self:contains(id) then
		error(ERROR_NO_ENTITY, 2)
	end

	bufferCommand(self, { type = "despawn", entityId = id })
end

--[=[
	Removes all entities from the world.

	:::caution
	Removing entities in this way is not reported by `queryChanged`.
	:::
]=]
function World:clear()
	self.storage = {}
	self.commands = {}
	self.markedForDeletion = {}

	self._entityArchetypes = {}
	self._entityMetatablesCache = {}
	self._size = 0
	self._changedStorage = {}
end

--[=[
	Checks if the given entity ID is currently spawned in this world.

	@param id number -- The entity ID
	@return bool -- `true` if the entity exists
]=]
function World:contains(id)
	return self.allEntities[id] ~= nil
end

--[=[
	Gets a specific component (or set of components) from a specific entity in this world.

	@param entityId number -- The entity ID
	@param ... Component -- The components to fetch
	@return ... -- Returns the component values in the same order they were passed in
]=]
function World:get(entityId, ...: Component)
	assertWorldOperationIsValid(self, entityId, ...)

	local length = select("#", ...)
	local componentInstances = table.create(length, nil)

	local entityRecord = self.allEntities[entityId]
	local archetype = entityRecord.archetype
	local idToIndex = archetype.idToIndex
	for i = 1, length do
		local component = select(i, ...)
		assertValidComponent(component, i)

		-- Does this component belong to the archetype that this entity is in?
		local storageIndex = idToIndex[#component]
		if storageIndex == nil then
			continue
		end

		-- Yes
		componentInstances[i] = archetype.fields[storageIndex][entityRecord.indexInArchetype]
	end

	return unpack(componentInstances, 1, length)
end

local function noop() end
local noopQuery = setmetatable({
	next = noop,
	snapshot = function()
		return {}
	end,
	without = function(self)
		return self
	end,
	view = function()
		return setmetatable({
			get = noop,
			contains = function()
				return false
			end,
		}, {
			__iter = function()
				return noop
			end,
			__call = noop,
		})
	end,
}, {
	__iter = function()
		return noop
	end,
	__call = noop,
})

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

function QueryResult.new(compatibleArchetypes: { Archetype }, queryLength: number, componentIds: { number })
	local A, B, C, D, E, F, G, H = unpack(componentIds)
	local a, b, c, d, e, f, g, h = nil, nil, nil, nil, nil, nil, nil, nil

	local currentEntityIndex = 1
	local currentArchetypeIndex = 1
	local currentArchetype = compatibleArchetypes[1]
	local currentEntities = currentArchetype.entities

	local function cacheFields()
		if currentArchetype == nil then
			return
		end

		local storage, idToIndex = currentArchetype.fields, currentArchetype.idToIndex
		if queryLength == 1 then
			a = storage[idToIndex[A]]
		elseif queryLength == 2 then
			a = storage[idToIndex[A]]
			b = storage[idToIndex[B]]
		elseif queryLength == 3 then
			a = storage[idToIndex[A]]
			b = storage[idToIndex[B]]
			c = storage[idToIndex[C]]
		elseif queryLength == 4 then
			a = storage[idToIndex[A]]
			b = storage[idToIndex[B]]
			c = storage[idToIndex[C]]
			d = storage[idToIndex[D]]
		elseif queryLength == 5 then
			a = storage[idToIndex[A]]
			b = storage[idToIndex[B]]
			c = storage[idToIndex[C]]
			d = storage[idToIndex[D]]
			e = storage[idToIndex[E]]
		elseif queryLength == 6 then
			a = storage[idToIndex[A]]
			b = storage[idToIndex[B]]
			c = storage[idToIndex[C]]
			d = storage[idToIndex[D]]
			e = storage[idToIndex[E]]
			f = storage[idToIndex[F]]
		elseif queryLength == 7 then
			a = storage[idToIndex[A]]
			b = storage[idToIndex[B]]
			c = storage[idToIndex[C]]
			d = storage[idToIndex[D]]
			e = storage[idToIndex[E]]
			f = storage[idToIndex[F]]
			g = storage[idToIndex[G]]
		elseif queryLength == 8 then
			a = storage[idToIndex[A]]
			b = storage[idToIndex[B]]
			c = storage[idToIndex[C]]
			d = storage[idToIndex[D]]
			e = storage[idToIndex[E]]
			f = storage[idToIndex[F]]
			g = storage[idToIndex[G]]
			h = storage[idToIndex[H]]
		end

		-- For anything longer, we do not cache.
	end

	local entityId: number
	--[=[
		@within QueryResult
		@method next
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
	local function nextEntity(): any
		entityId = currentEntities[currentEntityIndex]
		while entityId == nil do
			currentEntityIndex = 1
			currentArchetypeIndex += 1
			currentArchetype = compatibleArchetypes[currentArchetypeIndex]
			if currentArchetype == nil then
				return nil
			end

			cacheFields()
			currentEntities = currentArchetype.entities
			entityId = currentEntities[currentEntityIndex]
		end

		local entityIndex = currentEntityIndex
		currentEntityIndex += 1

		local entityId = currentEntities[entityIndex]
		if queryLength == 1 then
			return entityId, a[entityIndex]
		elseif queryLength == 2 then
			return entityId, a[entityIndex], b[entityIndex]
		elseif queryLength == 3 then
			return entityId, a[entityIndex], b[entityIndex], c[entityIndex]
		elseif queryLength == 4 then
			return entityId, a[entityIndex], b[entityIndex], c[entityIndex], d[entityIndex]
		elseif queryLength == 5 then
			return entityId, a[entityIndex], b[entityIndex], c[entityIndex], d[entityIndex], e[entityIndex]
		elseif queryLength == 6 then
			return entityId,
				a[entityIndex],
				b[entityIndex],
				c[entityIndex],
				d[entityIndex],
				e[entityIndex],
				f[entityIndex]
		elseif queryLength == 7 then
			return entityId,
				a[entityIndex],
				b[entityIndex],
				c[entityIndex],
				d[entityIndex],
				e[entityIndex],
				f[entityIndex],
				g[entityIndex]
		elseif queryLength == 8 then
			return entityId,
				a[entityIndex],
				b[entityIndex],
				c[entityIndex],
				d[entityIndex],
				e[entityIndex],
				f[entityIndex],
				g[entityIndex],
				h[entityIndex]
		else
			local output: { ComponentInstance } = table.create(queryLength + 1)
			for index, componentId in componentIds do
				output[index] = currentArchetype.fields[currentArchetype.idToIndex[componentId]][entityIndex]
			end

			return entityId, unpack(output, 1, queryLength)
		end
	end

	local function iter()
		return nextEntity
	end

	--[=[
		@within QueryResult
		@method without

		Returns an iterator that will skip any entities that also have the given components.
		The filtering is done at the archetype level, and so it is faster than manually skipping entities.

		@param ... Component -- The component types to filter against.
		@return () -> (id, ...ComponentInstance) -- Iterator of entity ID followed by the requested component values

		```lua
		for id in world:query(Target):without(Model) do
			-- Do something
		end
		```
	]=]
	local function without(self, ...: Component)
		local numComponents = select("#", ...)
		local numCompatibleArchetypes = #compatibleArchetypes
		for archetypeIndex = numCompatibleArchetypes, 1, -1 do
			local archetype = compatibleArchetypes[archetypeIndex]
			local shouldRemove = false
			for componentIndex = 1, numComponents do
				local component = select(componentIndex, ...)
				if archetype.idToIndex[#component] then
					shouldRemove = true
					break
				end
			end

			if shouldRemove then
				if archetypeIndex ~= numCompatibleArchetypes then
					compatibleArchetypes[archetypeIndex] = compatibleArchetypes[numCompatibleArchetypes]
				end

				compatibleArchetypes[numCompatibleArchetypes] = nil
				numCompatibleArchetypes -= 1
			end
		end

		if numCompatibleArchetypes == 0 then
			return noopQuery
		end

		currentArchetype = compatibleArchetypes[1]
		currentEntities = currentArchetype.entities

		cacheFields()
		return self
	end

	local Snapshot = {
		__iter = function(self)
			local i = 0
			return function()
				i += 1

				local entry = self[i] :: any
				if entry then
					return unpack(entry, 1, entry.n)
				end

				return
			end
		end,
	}

	--[=[
		@within QueryResult
		@method snapshot

		Creates a "snapshot" of this query, draining this QueryResult and returning a list containing all of its results.

		By default, iterating over a QueryResult happens in "real time": it iterates over the actual data in the ECS, so
		changes that occur during the iteration will affect future results.

		By contrast, `QueryResult:snapshot()` creates a list of all of the results of this query at the moment it is called,
		so changes made while iterating over the result of `QueryResult:snapshot` do not affect future results of the
		iteration.

		Of course, this comes with a cost: we must allocate a new list and iterate over everything returned from the
		QueryResult in advance, so using this method is slower than iterating over a QueryResult directly.

		The table returned from this method has a custom `__iter` method, which lets you use it as you would use QueryResult
		directly:

		```lua
			for entityId, health, player in world:query(Health, Player):snapshot() do

			end
		```

		However, the table itself is just a list of sub-tables structured like `{entityId, component1, component2, ...etc}`.

		@return {{entityId: number, component: ComponentInstance, component: ComponentInstance, component: ComponentInstance, ...}}
	]=]
	local function snapshot()
		local entities: { any } = setmetatable({}, Snapshot) :: any
		while true do
			local entry = table.pack(nextEntity())
			if entry.n == 1 then
				break
			end

			table.insert(entities, entry)
		end

		return entities
	end

	--[=[
		@class View

		Provides random access to the results of a query.

		Calling the View is equivalent to iterating a query.

		```lua
		for id, player, health, poison in world:query(Player, Health, Poison):view() do
			-- Do something
		end
		```
	]=]

	--[=[
		@within QueryResult
		@method view

		Creates a View of the query and does all of the iterator tasks at once at an amortized cost.
		This is used for many repeated random access to an entity. If you only need to iterate, just use a query.

		```lua
		local inflicting = world:query(Damage, Hitting, Player):view()
		for _, source in world:query(DamagedBy) do
			local damage = inflicting:get(source.from)
		end

		for _ in world:query(Damage):view() do end -- You can still iterate views if you want!
		```

		@return View
	]=]
	local function view()
		local entities = {}
		while true do
			local entry = table.pack(nextEntity())
			if entry.n == 1 then
				break
			end

			entities[entry[1]] = table.move(entry, 2, #entry, 1, {})
		end

		--[=[
			@within View
			@method get

			Retrieve the query results to corresponding `entity`
			@param entityId number -- the entity ID
			@return ...ComponentInstance
		]=]
		local function get(_, entityId: EntityId)
			local components = entities[entityId]
			if components == nil then
				return nil
			end

			return unpack(components, 1, #components)
		end

		--[=[
			@within View
			@method contains

			Equivalent to `world:contains()`
			@param entityId number -- the entity ID
			@return boolean
		]=]
		local function contains(_, entityId: EntityId)
			return entities[entityId] ~= nil
		end

		return setmetatable({
			get = get,
			contains = contains,
		}, {
			__iter = function()
				local index = 0
				return function()
					index += 1
					local entity = entities[index]
					if not entity then
						return
					end

					return index, unpack(entity, 1, #entity)
				end
			end,
		})
	end

	cacheFields()
	return setmetatable({
		next = nextEntity,
		without = without,
		snapshot = snapshot,
		view = view,
	}, {
		__iter = iter,
		__call = nextEntity,
	})
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

function World:query(...)
	local A, B, C, D, E, F, G, H = ...
	local componentIds: { number }

	local queryLength = select("#", ...)
	if queryLength == 1 then
		componentIds = { #A }
	elseif queryLength == 2 then
		componentIds = { #A, #B }
	elseif queryLength == 3 then
		componentIds = { #A, #B, #C }
	elseif queryLength == 4 then
		componentIds = { #A, #B, #C, #D }
	elseif queryLength == 5 then
		componentIds = { #A, #B, #C, #D, #E }
	elseif queryLength == 6 then
		componentIds = { #A, #B, #C, #D, #E, #F }
	elseif queryLength == 7 then
		componentIds = { #A, #B, #C, #D, #E, #F, #G }
	elseif queryLength == 8 then
		componentIds = { #A, #B, #C, #D, #E, #F, #G, #H }
	else
		componentIds = table.create(queryLength)
		for i = 1, queryLength do
			componentIds[i] = #select(i, ...)
		end
	end

	local possibleArchetypes: { Archetype }
	local compatibleArchetypes: { Archetype } = {}
	for _, componentId in componentIds do
		local associatedArchetypes = self.componentToArchetypes[componentId]
		if associatedArchetypes == nil then
			return noopQuery
		end

		if possibleArchetypes == nil or #possibleArchetypes > #associatedArchetypes then
			possibleArchetypes = associatedArchetypes
		end
	end

	-- Narrow the archetypes so only ones that contain all components are searched
	for _, archetype in possibleArchetypes do
		local incompatible = false
		for _, componentId in componentIds do
			-- Does this archetype have this component?
			if archetype.idToIndex[componentId] == nil then
				-- Nope, so we can't use this one.
				incompatible = true
				break
			end
		end

		if incompatible then
			continue
		end

		table.insert(compatibleArchetypes, archetype)
	end

	if #compatibleArchetypes == 0 then
		return noopQuery
	end

	return QueryResult.new(compatibleArchetypes, queryLength, componentIds) :: any
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

--[=[
	@interface ChangeRecord
	@within World
	.new? ComponentInstance -- The new value of the component. Nil if just removed.
	.old? ComponentInstance -- The former value of the component. Nil if just added.
]=]

--[=[
	:::info Topologically-aware function
	This function is only usable if called within the context of [`Loop:begin`](/api/Loop#begin).
	:::

	Queries for components that have changed **since the last time your system ran `queryChanged`**.

	Only one changed record is returned per entity, even if the same entity changed multiple times. The order
	in which changed records are returned is not guaranteed to be the order that the changes occurred in.

	It should be noted that `queryChanged` does not have the same iterator invalidation concerns as `World:query`.

	:::tip
	The first time your system runs (i.e., on the first frame), all existing entities in the world that match your query
	are returned as "new" change records.
	:::

	:::info
	Calling this function from your system creates storage internally for your system. Then, changes meeting your
	criteria are pushed into your storage. Calling `queryChanged` again each frame drains this storage.

	If your system isn't called every frame, the storage will continually fill up and does not empty unless you drain
	it.

	If you stop calling `queryChanged` in your system, changes will stop being tracked.
	:::

	### Returns
	`queryChanged` returns an iterator function, so you call it in a for loop just like `World:query`.

	The iterator returns the entity ID, followed by a [`ChangeRecord`](#ChangeRecord).

	The `ChangeRecord` type is a table that contains two fields, `new` and `old`, respectively containing the new
	component instance, and the old component instance. `new` and `old` will never be the same value.

	`new` will be nil if the component was removed (or the entity was despawned), and `old` will be nil if the
	component was just added.

	The `old` field will be the value of the component the last time this system observed it, not
	necessarily the value it changed from most recently.

	The `ChangeRecord` table is potentially shared with multiple systems tracking changes for this component, so it
	cannot be modified.

	```lua
	for id, record in world:queryChanged(Model) do
		if record.new == nil then
			-- Model was removed

			if enemy.type == "this is a made up example" then
				world:remove(id, Enemy)
			end
		end
	end
	```

	@param componentToTrack Component -- The component you want to listen to changes for.
	@return () -> (id, ChangeRecord) -- Iterator of entity ID and change record
]=]
function World:queryChanged(componentToTrack, ...: nil)
	if ... then
		error("World:queryChanged does not take any additional parameters", 2)
	end

	local hookState = topoRuntime.useHookState(componentToTrack, cleanupQueryChanged)

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

	if not self._changedStorage[componentToTrack] then
		self._changedStorage[componentToTrack] = {}
	end

	local storage = {}
	hookState.storage = storage
	hookState.world = self
	hookState.componentToTrack = componentToTrack

	table.insert(self._changedStorage[componentToTrack], storage)

	local queryResult = self:query(componentToTrack)

	return function(): any
		local entityId, component = queryResult:next()

		if entityId then
			return entityId, table.freeze({ new = component })
		end
		return
	end
end

function World._trackChanged(self: World, metatable, id, old, new)
	if not self._changedStorage[metatable] then
		return
	end

	if old == new then
		return
	end

	local record = table.freeze({
		old = old,
		new = new,
	})

	for _, storage in ipairs(self._changedStorage[metatable]) do
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
function World:insert(id, ...)
	assertWorldOperationIsValid(self, id, ...)

	local componentInstances = { ... }
	assertValidComponentInstances(componentInstances)

	bufferCommand(self, { type = "insert", entityId = id, componentInstances = componentInstances })
end

--[=[
	Removes a component (or set of components) from an existing entity.

	```lua
	local removedA, removedB = world:remove(entityId, ComponentA, ComponentB)
	```

	@param id number -- The entity ID
	@param ... Component -- The components to remove
]=]
function World:remove(id, ...: Component)
	local entityRecord = self.allEntities[id]
	if entityRecord == nil then
		error(ERROR_NO_ENTITY, 2)
	end

	local components = { ... }
	local componentInstances = {}
	local archetype = entityRecord.archetype
	for _, component in components do
		local componentId = #component
		local storage = archetype.fields[archetype.idToIndex[componentId]]
		table.insert(componentInstances, if storage then storage[entityRecord.indexInArchetype] else nil)
	end

	bufferCommand(self :: any, { type = "remove", entityId = id, components = components })
	return unpack(componentInstances)
end

--[=[
	Returns the number of entities currently spawned in the world.
]=]
function World:size()
	return self._size
end

--[=[
	:::tip
	[Loop] automatically calls this function on your World(s), so there is no need to call it yourself if you're using
	a Loop.
	:::

	If you are not using a Loop, you should call this function at a regular interval (i.e., once per frame) to optimize
	the internal storage for queries.

	This is part of a strategy to eliminate iterator invalidation when modifying the World while inside a query from
	[World:query]. While inside a query, any changes to the World are stored in a separate location from the rest of
	the World. Calling this function combines the separate storage back into the main storage, which speeds things up
	again.

	@deprecated v0.9.0 -- With the introduction of command buffering only one storage will ever exist at a time.
]=]
function World:optimizeQueries() end

return World
