local Component = require(script.Parent.component)
local archetypeModule = require(script.Parent.archetype)
local topoRuntime = require(script.Parent.topoRuntime)

local assertValidComponentInstances = Component.assertValidComponentInstances
local assertValidComponent = Component.assertValidComponent
local assertComponentArgsProvided = Component.assertComponentArgsProvided
local archetypeOf = archetypeModule.archetypeOf
local negateArchetypeOf = archetypeModule.negateArchetypeOf
local areArchetypesCompatible = archetypeModule.areArchetypesCompatible

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

--[=[
	Creates a new World.
]=]
function World.new()
	return setmetatable({
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

	local id = insertCommand.entityId
	local entity = world:_getEntity(id)
	local wasNew = false
	for _, componentInstance in insertCommand.componentInstances do
		local metatable = getmetatable(componentInstance)
		local oldComponent = entity[metatable]

		if not oldComponent then
			wasNew = true
			table.insert(world._entityMetatablesCache[id], metatable)
		end

		world:_trackChanged(metatable, id, oldComponent, componentInstance)
		entity[metatable] = componentInstance
	end

	if wasNew then
		world:_transitionArchetype(id, entity)
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
	local id = removeCommand.entityId
	local entity = world:_getEntity(id)

	local removed = {}
	for index, metatable in removeCommand.components do
		local oldComponent = entity[metatable]
		removed[index] = oldComponent

		world:_trackChanged(metatable, id, oldComponent, nil)
		entity[metatable] = nil
	end

	-- Rebuild entity metatable cache
	local metatables = {}
	for metatable in pairs(entity) do
		table.insert(metatables, metatable)
	end

	world._entityMetatablesCache[id] = metatables
	world:_transitionArchetype(id, entity)
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
function World:spawnAt(id, ...)
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
	self:_transitionArchetype(id, {})

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

function World:_transitionArchetype(id, components)
	debug.profilebegin("World:transitionArchetype")
	local storage = self.storage
	local newArchetype = nil
	local oldArchetype = self._entityArchetypes[id]

	if oldArchetype then
		if not components then
			storage[oldArchetype][id] = nil
		end
	end

	if components then
		newArchetype = archetypeOf(unpack(self._entityMetatablesCache[id]))

		if oldArchetype ~= newArchetype then
			if oldArchetype then
				storage[oldArchetype][id] = nil
			end

			if storage[newArchetype] == nil then
				storage[newArchetype] = {}
			end

			if self._entityArchetypeCache[newArchetype] == nil then
				debug.profilebegin("update query cache")
				self._entityArchetypeCache[newArchetype] = true
				self:_updateQueryCache(newArchetype)
				debug.profileend()
			end

			storage[newArchetype][id] = components
		else
			storage[newArchetype][id] = components
		end
	end

	self._entityArchetypes[id] = newArchetype

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
function World:contains(id)
	return self._entityArchetypes[id] ~= nil
end

--[=[
	Gets a specific component (or set of components) from a specific entity in this world.

	@param id number -- The entity ID
	@param ... Component -- The components to fetch
	@return ... -- Returns the component values in the same order they were passed in
]=]
function World:get(id, ...)
	assertWorldOperationIsValid(self, id, ...)

	local entity = self:_getEntity(id)

	local length = select("#", ...)

	if length == 1 then
		assertValidComponent((...), 1)
		return entity[...]
	end

	local components = {}
	for i = 1, length do
		local metatable = select(i, ...)
		assertValidComponent(metatable, i)
		components[i] = entity[metatable]
	end

	return unpack(components, 1, length)
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

function World:query(...)
	debug.profilebegin("World:query")
	assertValidComponent((...), 1)

	local metatables = { ... }
	local queryLength = select("#", ...)

	local archetype = archetypeOf(...)

	if self._queryCache[archetype] == nil then
		self:_newQueryArchetype(archetype)
	end

	local compatibleArchetypes = self._queryCache[archetype]

	debug.profileend()

	if next(compatibleArchetypes) == nil then
		-- If there are no compatible storages avoid creating our complicated iterator
		return noopQuery
	end

	local queryOutput = table.create(queryLength)

	local function expand(entityId, entityData)
		if not entityId then
			return
		end

		if queryLength == 1 then
			return entityId, entityData[metatables[1]]
		elseif queryLength == 2 then
			return entityId, entityData[metatables[1]], entityData[metatables[2]]
		elseif queryLength == 3 then
			return entityId, entityData[metatables[1]], entityData[metatables[2]], entityData[metatables[3]]
		elseif queryLength == 4 then
			return entityId,
				entityData[metatables[1]],
				entityData[metatables[2]],
				entityData[metatables[3]],
				entityData[metatables[4]]
		elseif queryLength == 5 then
			return entityId,
				entityData[metatables[1]],
				entityData[metatables[2]],
				entityData[metatables[3]],
				entityData[metatables[4]],
				entityData[metatables[5]]
		end

		for i, metatable in ipairs(metatables) do
			queryOutput[i] = entityData[metatable]
		end

		return entityId, unpack(queryOutput, 1, queryLength)
	end

	return QueryResult.new(self, expand, archetype, compatibleArchetypes, metatables)
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
	debug.profilebegin("insert")

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
function World:remove(id, ...)
	assertWorldOperationIsValid(self, id, ...)

	local components = { ... }
	local length = #components

	local entity = self:_getEntity(id)
	local removed = table.create(length, nil)
	for index, component in components do
		assertValidComponent(component, index)

		local oldComponent = entity[component]
		removed[index] = oldComponent
	end

	bufferCommand(self, { type = "remove", entityId = id, components = components })
	return unpack(removed, 1, length)
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
