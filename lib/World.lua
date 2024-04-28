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

type i53 = number
type i24 = number

type Component = { [any]: any }

type Ty = { i53 }
type ArchetypeId = number

type Column = { any }

type Archetype = {
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
	destinationArchetype: Archetype,
	destinationRow: i24,
	sourceArchetype: Archetype,
	sourceRow: i24
)
	local columns = sourceArchetype.columns
	local sourceEntities = sourceArchetype.entities
	local destinationEntities = destinationArchetype.entities
	local destinationColumns = destinationArchetype.columns

	for componentId, column in columns do
		local targetColumn = destinationColumns[componentId]
		if targetColumn then
			targetColumn[destinationRow] = column[sourceRow]
		end
		column[sourceRow] = column[#column]
		column[#column] = nil
	end

	destinationEntities[destinationRow] = sourceEntities[sourceRow]
	local moveAway = #sourceEntities
	sourceEntities[sourceRow] = sourceEntities[moveAway]
	sourceEntities[moveAway] = nil
	entityIndex[destinationEntities[destinationRow]].row = sourceRow
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
	if true then
		return table.concat(arr, "_")
	end
	local hashed = 5381
	for i = 1, #arr do
		hashed = ((bit32.lshift(hashed, 5)) + hashed) + arr[i]
	end
	return hashed
end

local function createArchetypeRecords(componentIndex: ComponentIndex, to: Archetype, from: Archetype?)
	local destinationCount = #to.types
	local destinationIds = to.types

	for i = 1, destinationCount do
		local destinationId = destinationIds[i]

		if not componentIndex[destinationId] then
			componentIndex[destinationId] = { sparse = {}, size = 0 }
		end
		componentIndex[destinationId].sparse[to.id] = i
		to.records[destinationId] = i
	end
end

local function archetypeOf(world: World, types: { i24 }, prev: Archetype?): Archetype
	local ty = hash(types)

	world.nextArchetypeId = (world.nextArchetypeId :: number) + 1
	local id = world.nextArchetypeId

	local columns = {} :: { any }

	for _ in types do
		table.insert(columns, {})
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
	createArchetypeRecords(world.componentIndex, archetype, prev)

	return archetype
end

local World = {}
World.__index = World

local function reset(world: World) end

function World.new()
	local self = setmetatable({
		entityIndex = {},
		componentIndex = {},
		archetypes = {},
		archetypeIndex = {},
		nextId = 0,
		nextArchetypeId = 0,
		_size = 0,
	}, World)

	self.ROOT_ARCHETYPE = archetypeOf(self, {}, nil)
	return self
end

type World = typeof(World.new())

local function ensureArchetype(world: World, types, prev)
	if #types < 1 then
		if not world.ROOT_ARCHETYPE then
			local ROOT_ARCHETYPE = archetypeOf(world, {}, nil)
			world.ROOT_ARCHETYPE = ROOT_ARCHETYPE
			return ROOT_ARCHETYPE
		end
	end
	local ty = hash(types)
	local archetype = world.archetypeIndex[ty]
	if archetype then
		return archetype
	end

	return archetypeOf(world, types, prev)
end

local function findInsert(types: { i53 }, toAdd: i53)
	local count = #types
	for i = 1, count do
		local id = types[i]
		if id == toAdd then
			return -1
		end
		if id > toAdd then
			return i
		end
	end
	return count + 1
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
	if not archetype.edges[componentId] then
		archetype.edges[componentId] = {} :: any
	end
	return archetype.edges[componentId]
end

local function archetypeTraverseAdd(world: World, componentId: i53, archetype: Archetype?): Archetype
	local from = (archetype or world.ROOT_ARCHETYPE) :: Archetype
	local edge = ensureEdge(from, componentId)

	if not edge.add then
		edge.add = findArchetypeWith(world, from, componentId)
	end

	return edge.add
end

local function componentAdd(world: World, entityId: i53, component)
	local componentId = #getmetatable(component)

	local record = world:ensureRecord(entityId)
	local sourceArchetype = record.archetype
	local destinationArchetype = archetypeTraverseAdd(world, componentId, sourceArchetype)

	if sourceArchetype and not (sourceArchetype == destinationArchetype) then
		moveEntity(world.entityIndex, entityId, record, destinationArchetype)
	else
		-- if it has any components, then it wont be the root archetype
		if #destinationArchetype.types > 0 then
			newEntity(entityId, record, destinationArchetype)
		end
	end

	--print(component)
	local archetypeRecord = destinationArchetype.records[componentId]
	destinationArchetype.columns[archetypeRecord][record.row] = component
	--print(destinationArchetype.columns[archetypeRecord])
end

function World.ensureRecord(world: World, entityId: i53)
	local entityIndex = world.entityIndex
	local id = entityId
	if not entityIndex[id] then
		entityIndex[id] = {} :: Record
	end
	return entityIndex[id]
end

function World.insert(world: World, entityId: i53, ...)
	debug.profilebegin("insert")

	if not world:contains(entityId) then
		error(ERROR_NO_ENTITY, 2)
	end

	for i = 1, select("#", ...) do
		componentAdd(world, entityId, select(i, ...))
	end

	debug.profileend()
end

local function archetypeTraverseRemove(world: World, componentId: i53, archetype: Archetype?): Archetype
	local from = (archetype or world.ROOT_ARCHETYPE) :: Archetype
	local edge = ensureEdge(from, componentId)

	if not edge.remove then
		local to = table.clone(from.types)
		table.remove(to, table.find(to, componentId))
		edge.remove = ensureArchetype(world, to, from)
	end

	return edge.remove
end

function World.remove(world: World, entityId: i53, component: Component)
	local componentId = #component
	local record = world:ensureRecord(entityId)
	local sourceArchetype = record.archetype
	local destinationArchetype = archetypeTraverseRemove(world, componentId, sourceArchetype)

	if sourceArchetype and not (sourceArchetype == destinationArchetype) then
		moveEntity(world.entityIndex, entityId, record, destinationArchetype)
	end
end

local function get(componentIndex: { [i24]: ArchetypeMap }, record: Record, componentId: i24)
	local archetype = record.archetype
	local archetypeRecord = componentIndex[componentId].sparse[archetype.id]

	if not archetypeRecord then
		return nil
	end

	return archetype.columns[archetypeRecord][record.row]
end

function World.get(world: World, entityId: i53, a: Component, b: Component, c: Component, d: Component, e: Component)
	local componentIndex = world.componentIndex
	local record = world.entityIndex[entityId]
	if not record then
		return nil
	end

	local va = get(componentIndex, record, #a)

	if b == nil then
		return va
	elseif c == nil then
		return va, get(componentIndex, record, #b)
	elseif d == nil then
		return va, get(componentIndex, record, #b), get(componentIndex, record, #c)
	elseif e == nil then
		return va, get(componentIndex, record, #b), get(componentIndex, record, #c), get(componentIndex, record, #d)
	else
		error("args exceeded")
	end
end

function World.entity(world: World)
	world.nextId += 1
	return world.nextId
end

function World:__iter()
	return error("NOT IMPLEMENTED YET")
end

function World.spawn(world: World, ...: () -> <T>() -> (number, T))
	return world:spawnAt(world.nextId, ...)
end

function World.despawn(world: World, entityId: i53)
	-- TODO: handle archetypes
	world.entityIndex[entityId] = nil
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

function World.spawnAt(world: World, entityId: i53, ...)
	if world:contains(entityId) then
		error(string.format(ERROR_DUPLICATE_ENTITY, entityId), 2)
	end

	if entityId >= world.nextId then
		world.nextId = entityId + 1
	end

	world._size += 1
	world:ensureRecord(entityId)

	local components = {}
	for i = 1, select("#", ...) do
		local component = select(i, ...)
		assertValidComponentInstance(component, i)

		local metatable = getmetatable(component)
		if components[metatable] then
			error(("Duplicate component type at index %d"):format(i), 2)
		end

		components[metatable] = component
		componentAdd(world, entityId, component)
	end

	return entityId
end

--[[function World.insert(world: World, entity: i53, ...: () -> <T>(data: T) -> (number, T))
	for i = 1, select("#", ...) do
		local component = select(i, ...)
		local componentId, data = component()
		world:add(entity, componentId, data)
	end
end]]

local function noop(): any
	return function() end
end

local function getSmallestMap(componentIndex, components)
	local s: any

	for i, componentId in components do
		local map = componentIndex[componentId]
		if s == nil or map.size < s.size then
			s = map
		end
	end

	return s.sparse
end

function World.query(world: World, ...: Component): any
	local compatibleArchetypes = {}
	local components = { ... } :: { any }
	local archetypes = world.archetypes
	local queryLength = select("#", ...)
	local a: any, b: any, c: any, d: any, e: any = ...

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
	else
		for i, comp in components do
			components[i] = #comp
		end
	end

	local firstArchetypeMap = getSmallestMap(world.componentIndex, components)

	for id in firstArchetypeMap do
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

	local lastArchetype, archetype = next(compatibleArchetypes)
	if not lastArchetype then
		return noop()
	end

	local lastRow

	local preparedQuery = {}
	preparedQuery.__index = preparedQuery

	function preparedQuery:without(...)
		local components = { ... }
		for i, component in components do
			components[i] = #component
		end

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

		return self
	end

	function preparedQuery:__iter()
		return function()
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
			end

			local queryOutput = {}
			for i, componentId in (components :: any) :: { number } do
				queryOutput[i] = columns[archetypeRecords[componentId]][row]
			end

			return entityId, unpack(queryOutput, 1, queryLength)
		end
	end

	return setmetatable({}, preparedQuery)
end

return World
