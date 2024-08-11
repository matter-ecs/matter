--!strict
local Component = require(script.Parent.component)
local archetypeModule = require(script.Parent.archetype)
local component = require(script.Parent.component)
local topoRuntime = require(script.Parent.topoRuntime)

local assertValidComponentInstances = Component.assertValidComponentInstances
local assertValidComponent = Component.assertValidComponent
local archetypeOf = archetypeModule.archetypeOf
local negateArchetypeOf = archetypeModule.negateArchetypeOf
local areArchetypesCompatible = archetypeModule.areArchetypesCompatible

type EntityId = number
type DenseEntityId = number
type ComponentId = number

type Component = { [any]: any }
type ComponentInstance = { [any]: any }
type ComponentMetatable = { [any]: any }
type ComponentMetatables = { ComponentMetatable }
type ComponentToId = { [Component]: number }

type ArchetypeId = string
type Archetype = {
	id: string,

	ownedEntities: { EntityId },

	--- Maps a component ID to its index in the storage
	componentIds: { ComponentId },

	componentToStorageIndex: { [ComponentId]: number },
	storage: { { ComponentInstance } },
}

type EntityRecord = {
	indexInArchetype: number,
	archetype: Archetype,
}

-- Find archetype for entity
type Entities = { [EntityId]: EntityRecord? }

-- Find archetypes containing component
type ComponentToArchetypes = { [ComponentId]: { number } }

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

--[=[
	@class World

	A World contains entities which have components.
	The World is queryable and can be used to get entities with a specific set of components.
	Entities are simply ever-increasing integers.
]=]
local World = {}
World.__index = World

local function createArchetype(world: World, componentIds: { ComponentId }): Archetype
	local archetypeId = archetypeOf(componentIds)
	local componentToStorageIndex = {}
	local length = #componentIds
	local storage = table.create(length)

	local indexInArchetypes = #world.archetypes + 1
	local archetype: Archetype = {
		id = archetypeId,
		indexInArchetypes = indexInArchetypes,

		componentIds = componentIds,
		componentToStorageIndex = componentToStorageIndex,
		storage = storage,

		-- Keep track of all entity ids for fast iteration in queries
		ownedEntities = {},
	}

	for index, componentId in componentIds do
		local associatedArchetypes = world.componentToArchetypes[componentId] or ({} :: any)
		associatedArchetypes[indexInArchetypes] = index
		world.componentToArchetypes[componentId] = associatedArchetypes

		componentToStorageIndex[componentId] = index
		storage[index] = {}
	end

	table.insert(world.archetypes, archetype)
	return archetype
end

--[=[
	Creates a new World.
]=]
function World.new()
	local self = setmetatable({
		entities = {} :: Entities,
		componentToArchetypes = {} :: ComponentToArchetypes,
		archetypes = {} :: Archetypes,
		archetypeHashToIndex = {} :: { [string]: number },

		-- Map from archetype string --> entity ID --> entity data
		storage = {},

		deferring = false,
		commands = {} :: { Command },

		markedForDeletion = {},

		-- Map from entity ID -> archetype string
		_entityArchetypes = {},

		-- Cache of the component metatables on each entity. Used for generating archetype.
		-- Map of entity ID -> array
		_entityMetatablesCache = {},

		-- Cache of what query archetypes are compatible with what component archetypes
		_queryCache = {},

		-- Cache of what entity archetypes have ever existed in the game. This is used for knowing
		-- when to update the queryCache.
		_entityArchetypeCache = {},

		-- The next ID that will be assigned with World:spawn
		_nextId = 1,

		-- The total number of active entities in the world
		_size = 0,

		-- Storage for `queryChanged`
		_changedStorage = {},
	}, World)

	self.rootArchetype = createArchetype(self, {})
	return self
end

export type World = typeof(World.new())

function World:_getEntity(id)
	local archetype = self._entityArchetypes[id]
	return self.storage[archetype][id]
end

function World:_next(last)
	local entityId, archetype = next(self._entityArchetypes, last)

	if entityId == nil then
		return nil
	end

	return entityId, self.storage[archetype][entityId]
end

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
function World:__iter()
	return World._next, self
end

local function ensureArchetype(world: World, componentIds: { number })
	local archetypeId = archetypeOf(componentIds)
	local archetypes = world.archetypes
	for _, archetype in archetypes do
		if archetype.id == archetypeId then
			return archetype
		end
	end

	return createArchetype(world, componentIds)
end

local function ensureRecord(world: World, entityId: number): EntityRecord
	local entityRecord = world.entities[entityId]
	if entityRecord == nil then
		local rootArchetype = world.rootArchetype
		entityRecord = {
			archetype = rootArchetype,

			-- O(N) for length
			indexInArchetype = #rootArchetype.ownedEntities + 1,
		}

		table.insert(rootArchetype.ownedEntities, entityId)
		world.entities[entityId] = entityRecord
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

	-- Add entity to archetype's ownedEntities
	local ownedEntities = archetype.ownedEntities
	local entityIndex = #ownedEntities + 1
	ownedEntities[entityIndex] = entityId

	-- Move old storage to new storage if needed
	local oldNumEntities = #oldArchetype.ownedEntities
	local wasLastEntity = oldNumEntities == oldEntityIndex
	for index, oldComponentStorage in oldArchetype.storage do
		local componentStorage = archetype.storage[archetype.componentToStorageIndex[oldArchetype.componentIds[index]]]

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
		oldArchetype.ownedEntities[oldEntityIndex] = oldArchetype.ownedEntities[oldNumEntities];
		(world.entities[oldArchetype.ownedEntities[oldEntityIndex]] :: EntityRecord).indexInArchetype = oldEntityIndex
	end

	-- Remove from old archetype
	oldArchetype.ownedEntities[oldNumEntities] = nil

	-- Mark entity as being in new archetype
	entityRecord.indexInArchetype = entityIndex
	entityRecord.archetype = archetype

	return entityIndex
end

local function executeDespawn(world: World, despawnCommand: DespawnCommand)
	local id = despawnCommand.entityId
	local entity = world:_getEntity(id)

	for metatable, component in pairs(entity) do
		world:_trackChanged(metatable, id, component, nil)
	end

	local shouldOnlyClear = world.deferring and world.markedForDeletion[id] ~= true
	world._entityMetatablesCache[id] = if shouldOnlyClear then {} else nil
	world:_transitionArchetype(id, if shouldOnlyClear then {} else nil)

	world._size -= 1
end

local function executeInsert(world: World, insertCommand: InsertCommand)
	debug.profilebegin("World:insert")

	local entityId = insertCommand.entityId
	local entityRecord = ensureRecord(world, entityId)
	local componentInstances = insertCommand.componentInstances

	local oldArchetype = entityRecord.archetype
	for _, componentInstance in componentInstances do
		local componentId = #getmetatable(componentInstance)
		local componentIds = table.clone(oldArchetype.componentIds)
		table.insert(componentIds, componentId)

		local archetype = ensureArchetype(world, componentIds)
		local entityIndex = transitionArchetype(world, entityId, entityRecord, archetype)
		archetype.storage[archetype.componentToStorageIndex[componentId]][entityIndex] = componentInstance

		oldArchetype = archetype
	end

	debug.profileend()
end

local function executeReplace(world: World, replaceCommand: ReplaceCommand)
	local id = replaceCommand.entityId
	if not world:contains(id) then
		error(ERROR_NO_ENTITY, 2)
	end

	local components = {}
	local metatables = {}
	local entity = world:_getEntity(id)

	for _, componentInstance in replaceCommand.componentInstances do
		local metatable = getmetatable(componentInstance)
		world:_trackChanged(metatable, id, entity[metatable], componentInstance)

		components[metatable] = componentInstance
		table.insert(metatables, metatable)
	end

	for metatable, component in pairs(entity) do
		if not components[metatable] then
			world:_trackChanged(metatable, id, component, nil)
		end
	end

	world._entityMetatablesCache[id] = metatables
	world:_transitionArchetype(id, components)
end

local function executeRemove(world: World, removeCommand: RemoveCommand)
	local entityId = removeCommand.entityId
	local entityRecord = ensureRecord(world, entityId)
	local componentIds = table.clone(entityRecord.archetype.componentIds)
	for _, component in removeCommand.components do
		local index = table.find(componentIds, #component)
		if index then
			table.remove(componentIds, index)
		end
	end

	transitionArchetype(world, entityId, entityRecord, ensureArchetype(world, componentIds))
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
	self._entityMetatablesCache[id] = {}

	ensureRecord(self, id)
	bufferCommand(self, { type = "insert", entityId = id, componentInstances = componentInstances })
	return id
end

function World:_newQueryArchetype(queryArchetype)
	if self._queryCache[queryArchetype] == nil then
		self._queryCache[queryArchetype] = {}
	else
		return -- Archetype isn't actually new
	end

	for entityArchetype in self.storage do
		if areArchetypesCompatible(queryArchetype, entityArchetype) then
			self._queryCache[queryArchetype][entityArchetype] = true
		end
	end
end

function World:_updateQueryCache(entityArchetype)
	for queryArchetype, compatibleArchetypes in pairs(self._queryCache) do
		if areArchetypesCompatible(queryArchetype, entityArchetype) then
			compatibleArchetypes[entityArchetype] = true
		end
	end
end

function World._transitionArchetype(
	self: typeof(World.new()),
	entityId: EntityId,
	toAdd: { [ComponentId]: ComponentInstance }?,
	toRemove: { Component }?
)
	debug.profilebegin("transitionArchetype")
	if toAdd then
		local entityRecord = ensureRecord(self, entityId)
		local oldArchetype = entityRecord.archetype
		local oldComponentIds = oldArchetype.componentToStorageIndex
		local newComponentIds = table.clone(oldComponentIds)
		local hasNew = false

		for componentId, componentInstance in toAdd do
			-- table.insert(newComponentIds, componentId)
			if not table.find(newComponentIds, componentId) then
				table.insert(newComponentIds, componentId)
				hasNew = true
			end
		end

		if hasNew then
			-- Move from old to new
			-- todo: remove from old ownedEntities
			local oldIndexInArchetype = entityRecord.indexInArchetype
			local newArchetype = ensureArchetype(self, newComponentIds)
			local indexInArchetype = #newArchetype.ownedEntities + 1
			newArchetype.ownedEntities[indexInArchetype] = entityId

			for _, componentId in newComponentIds do
				local oldStorageIndex = oldArchetype.componentToStorageIndex[componentId]
				if oldStorageIndex then
					--warn("TODO: exist")
				else
					-- It doesn't exist in the old archetype, so just add.
					newArchetype.storage[newArchetype.componentToStorageIndex[componentId]][indexInArchetype] =
						toAdd[componentId]
				end
			end

			-- todo: swap to avoid cascading moves
			table.remove(oldArchetype.ownedEntities, oldIndexInArchetype)

			entityRecord.indexInArchetype = indexInArchetype
			entityRecord.archetype = newArchetype
			--print("oldArchetype", oldArchetype, "newArchetype", newArchetype)
		else
			--warn("TODO: none new")
		end
	elseif toRemove then
	end

	-- local entityRecord = ensureRecord(self, entityId)
	-- local oldArchetype = entityRecord.archetype
	-- local oldComponentIds = oldArchetype.componentToStorageIndex
	-- local newComponentIds = table.clone(oldComponentIds)
	-- local storage

	-- if toAdd then
	-- 	for _, componentInstance in toAdd do
	-- 		table.insert(newComponentIds, #getmetatable(componentInstance))
	-- 	end
	-- end

	-- if toRemove then

	-- end

	-- local newArchetype = entityRecord.
	-- if myComponents == nil then
	-- 	-- Remove all components
	-- 	local entityRecord = self.entities[id]
	-- 	if entityRecord == nil then
	-- 		warn("Tried to transitionArchetype a dead entity")
	-- 		return
	-- 	end

	-- 	local archetype = entityRecord.archetype
	-- 	if archetype == nil then
	-- 		warn("Already have no archetype")
	-- 		return
	-- 	end

	-- 	for _, storageIndex in archetype.componentToStorageIndex do
	-- 		-- TODO:
	-- 		-- swap remove
	-- 		table.remove(archetype.storage[storageIndex], entityRecord.indexInArchetype)
	-- 	end

	-- 	-- entityRecord.archetype = nil
	-- 	-- entityRecord.indexInArchetype = nil
	-- 	self.entities[id] = nil

	-- 	-- TODO:
	-- 	-- This is slow (and unsafe)
	-- 	table.remove(archetype.ownedEntities, table.find(archetype.ownedEntities, id))
	-- else
	-- 	local componentIds: { ComponentId } = {}
	-- 	for component in myComponents do
	-- 		table.insert(componentIds, #component)
	-- 	end

	-- 	local entityRecord = self.entities[id]
	-- 	if entityRecord == nil then
	-- 		entityRecord = {}
	-- 		self.entities[id] = entityRecord
	-- 	end
	-- 	assert(entityRecord, "Make typechecker happy")

	-- 	-- Find the archetype that matches these components
	-- 	local newArchetypeId = archetypeOf(componentIds)
	-- 	local newArchetype = self.archetypes[newArchetypeId] or createArchetype(self, componentIds)

	-- 	print("archetype", newArchetype)
	-- 	-- Add entity to archetype
	-- 	local indexInArchetype = #newArchetype.ownedEntities + 1
	-- 	for component, componentInstance in myComponents do
	-- 		newArchetype.storage[newArchetype.componentToStorageIndex[#component]][indexInArchetype] = componentInstance
	-- 	end

	-- 	entityRecord.indexInArchetype = indexInArchetype
	-- 	entityRecord.archetype = newArchetype
	-- 	table.insert(newArchetype.ownedEntities, id)
	-- end

	debug.profileend()
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
function World.contains(self: typeof(World.new()), id)
	return self.entities[id] ~= nil
end

--[=[
	Gets a specific component (or set of components) from a specific entity in this world.

	@param id number -- The entity ID
	@param ... Component -- The components to fetch
	@return ... -- Returns the component values in the same order they were passed in
]=]
function World.get(self: World, entityId, ...: Component)
	local entityRecord = self.entities[entityId]
	if entityRecord == nil then
		error(ERROR_NO_ENTITY, 2)
	end

	local length = select("#", ...)
	local componentInstances = table.create(length, nil)

	local archetype = entityRecord.archetype
	local componentToStorageIndex = archetype.componentToStorageIndex
	for i = 1, length do
		local component = select(i, ...)
		assertValidComponent(component, i)

		-- Does this component belong to the archetype that this entity is in?
		local storageIndex = componentToStorageIndex[component]
		if storageIndex == nil then
			continue
		end

		-- Yes
		componentInstances[i] = archetype.storage[storageIndex][entityRecord.indexInArchetype]
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

function QueryResult.new(world, expand, queryArchetype, compatibleArchetypes, metatables)
	return setmetatable({
		world = world,
		currentCompatibleArchetype = next(compatibleArchetypes),
		compatibleArchetypes = compatibleArchetypes,
		storageIndex = 1,
		metatables = metatables,
		_expand = expand,
		_queryArchetype = queryArchetype,
	}, QueryResult)
end

local function nextItem(query)
	local world = query.world
	local currentCompatibleArchetype = query.currentCompatibleArchetype
	local compatibleArchetypes = query.compatibleArchetypes

	local entityId, entityData

	local storage = world.storage
	local currently = storage[currentCompatibleArchetype]
	if currently then
		entityId, entityData = next(currently, query.lastEntityId)
	end

	while entityId == nil do
		currentCompatibleArchetype = next(compatibleArchetypes, currentCompatibleArchetype)

		if currentCompatibleArchetype == nil then
			return nil
		elseif storage[currentCompatibleArchetype] == nil then
			continue
		end

		entityId, entityData = next(storage[currentCompatibleArchetype])
	end

	query.lastEntityId = entityId

	query.currentCompatibleArchetype = currentCompatibleArchetype

	return entityId, entityData
end

function QueryResult:__iter()
	return function()
		return self._expand(nextItem(self))
	end
end

function QueryResult:__call()
	return self._expand(nextItem(self))
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
	return self._expand(nextItem(self))
end

local snapshot = {
	__iter = function(self): any
		local i = 0
		return function()
			i += 1

			local data = self[i]

			if data then
				return unpack(data, 1, data.n)
			end
			return
		end
	end,
}

--[=[
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
function QueryResult:snapshot()
	local list = setmetatable({}, snapshot)

	local function iter()
		return nextItem(self)
	end

	for entityId, entityData in iter do
		if entityId then
			table.insert(list, table.pack(self._expand(entityId, entityData)))
		end
	end

	return list
end

--[=[
	Returns an iterator that will skip any entities that also have the given components.

	:::tip
	This is essentially equivalent to querying normally, using `World:get` to check if a component is present,
	and using Lua's `continue` keyword to skip this iteration (though, using `:without` is faster).

	This means that you should avoid queries that return a very large amount of results only to filter them down
	to a few with `:without`. If you can, always prefer adding components and making your query more specific.
	:::

	@param ... Component -- The component types to filter against.
	@return () -> (id, ...ComponentInstance) -- Iterator of entity ID followed by the requested component values

	```lua
	for id in world:query(Target):without(Model) do
		-- Do something
	end
	```
]=]

function QueryResult:without(...)
	local world = self.world
	local filter = negateArchetypeOf(...)

	local negativeArchetype = `{self._queryArchetype}x{filter}`

	if world._queryCache[negativeArchetype] == nil then
		world:_newQueryArchetype(negativeArchetype)
	end

	local compatibleArchetypes = world._queryCache[negativeArchetype]

	self.compatibleArchetypes = compatibleArchetypes
	self.currentCompatibleArchetype = next(compatibleArchetypes)
	return self
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
	local components = {}
	local metatables = self.metatables
	local queryLength = #metatables
	local componentRecords = {}
	for index, metatable in metatables do
		components[index] = {}
		componentRecords[metatable] = index
	end

	local function iter()
		return nextItem(self)
	end

	local entities = {}
	local entityIndex = 0
	local entityRecords = {}

	for entityId, entityData in iter do
		entityIndex += 1

		for metatable, componentIndex in componentRecords do
			components[componentIndex][entityId] = entityData[metatable]
		end

		entities[entityIndex] = entityId
		entityRecords[entityId] = entityIndex
	end

	local View = {}
	View.__index = View

	local tuple = {}
	local function expand(entity)
		if queryLength == 1 then
			return components[1][entity]
		elseif queryLength == 2 then
			return components[1][entity], components[2][entity]
		elseif queryLength == 3 then
			return components[1][entity], components[2][entity], components[3][entity]
		elseif queryLength == 4 then
			return components[1][entity], components[2][entity], components[3][entity], components[4][entity]
		elseif queryLength == 5 then
			return components[1][entity],
				components[2][entity],
				components[3][entity],
				components[4][entity],
				components[5][entity]
		end

		for index, componentField in components do
			tuple[index] = componentField[entity]
		end

		return unpack(tuple)
	end

	function View:__iter()
		local index = 0
		return function()
			index += 1
			local entity = entities[index]
			if not entity then
				return
			end

			return entity, expand(entity)
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

		return expand(entity)
	end

	--[=[
		@within View
		Equivalent to `world:contains()`
		@param entity number - the entity ID
		@return boolean
	]=]

	function View:contains(entity)
		return entityRecords[entity] ~= nil
	end

	return setmetatable({}, View)
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

function World.query(self: World, ...)
	-- TODO:
	-- cache queries
	local components = { ... }
	local a, b = ...

	local queryLength = select("#", ...)
	if queryLength == 1 then
		components = { #a }
	elseif queryLength == 2 then
		components = { #a, #b }
	else
		error("Unimplemented query length")
	end

	local possibleArchetypes
	local compatibleArchetypes = {}
	for _, componentId in components do
		local associatedArchetypes = self.componentToArchetypes[componentId]
		if associatedArchetypes == nil then
			error("No-op query unimplemented")
		end

		if possibleArchetypes == nil or #possibleArchetypes > #associatedArchetypes then
			possibleArchetypes = associatedArchetypes
		end
	end

	-- Narrow the archetypes so only ones that contain all components are searched
	for archetypeIndex in possibleArchetypes do
		local archetype = self.archetypes[archetypeIndex]
		local incompatible = false
		for _, componentId in components do
			-- Does this archetype have this component?
			if archetype.componentToStorageIndex[componentId] == nil then
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

	local currentArchetypeIndex = 1
	local currentArchetype = compatibleArchetypes[currentArchetypeIndex]
	local currentArchetypeNumEntities = #currentArchetype.ownedEntities
	local currentEntityIndex = 0
	local function nextEntity(): any
		currentEntityIndex += 1
		if currentEntityIndex > currentArchetypeNumEntities then
			currentEntityIndex = 0
			currentArchetypeIndex += 1
			currentArchetype = compatibleArchetypes[currentArchetypeIndex]
			if currentArchetype == nil then
				-- Out of entities.
				return nil
			end

			currentArchetypeNumEntities = #currentArchetype.ownedEntities
			return nextEntity()
		end

		local entityId = currentArchetype.ownedEntities[currentEntityIndex]
		local storage, componentToStorageIndex = currentArchetype.storage, currentArchetype.componentToStorageIndex
		if queryLength == 1 then
			return entityId, storage[componentToStorageIndex[components[1]]][currentEntityIndex]
		elseif queryLength == 2 then
			return entityId,
				storage[componentToStorageIndex[components[1]]][currentEntityIndex],
				storage[componentToStorageIndex[components[2]]][currentEntityIndex]
		elseif queryLength == 3 then
			return entityId,
				storage[componentToStorageIndex[components[1]]][currentEntityIndex],
				storage[componentToStorageIndex[components[2]]][currentEntityIndex],
				storage[componentToStorageIndex[components[3]]][currentEntityIndex]
		else
			error("Unimplemented Query Length")
		end
	end

	local function iter()
		return nextEntity
	end

	return setmetatable({}, {
		__iter = iter,
		next = nextEntity,
	})
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

function World:_trackChanged(metatable, id, old, new)
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
	if not self:contains(id) then
		error(ERROR_NO_ENTITY, 2)
	end

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
function World.remove(self: World, id, ...: ComponentMetatable)
	local entityRecord = self.entities[id]
	if entityRecord == nil then
		error(ERROR_NO_ENTITY, 2)
	end

	local components = { ... }
	bufferCommand(self :: any, { type = "remove", entityId = id, components = components })
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
