local merge = require(script.Parent.immutable).merge

--[=[
	@class Component

	A component is a named piece of data that exists on an entity.
	Components are created and removed in the [World](/api/World).

	In the docs, the terms "Component" and "ComponentInstance" are used:
	- **"Component"** refers to the base class of a specific type of component you've created.
		This is what [`Matter.component`](/api/Matter#component) returns.
	- **"Component Instance"** refers to what encapsulates data you pass into a Component.
		You only really interact with a [TableComponentInstance](/api/TableComponentInstance).

	Since component instances are immutable, one helper function exists on all component instances, `patch`,
	which allows reusing data from an existing component instance to make up for the ergonomic loss of mutations.
]=]

--[=[
	@within Component
	@type ComponentInstance TableComponentInstance | ValueComponentInstance
]=]

--[=[
	@within Component
	@type ValueComponentInstance {}

	If you pass anything other than a table into a Component, then you will get a ValueComponentInstance back.
	Unlike a [TableComponentInstance](/api/TableComponentInstance), you shouldn't need to interact with this
	and it will not be passed back to you in queries.

	This is strictly used for insertions.
]=]

--[=[
	@class TableComponentInstance
]=]

-- This is a special value we set inside the component's metatable that will allow us to detect when
-- a Component is accidentally inserted as a Component Instance.
-- It should not be accessible through indexing into a component instance directly.
local DIAGNOSTIC_COMPONENT_MARKER = table.freeze({})

-- This tells the World whether the component should be unwrapped on insertion.
local PRIMITIVE_MARKER = table.freeze({})

local lastId = 0
local function new(name: string, defaultData)
	name = name or debug.info(2, "s") .. "@" .. debug.info(2, "l")

	local Component = {}
	Component.__index = Component

	function Component.new(data)
		-- If we aren't passed data, then we use the default data.
		-- If no default data is provided, we want to default a table.
		data = if data == nil then defaultData or {} else data

		if typeof(data) == "table" then
			if defaultData then
				data = merge(defaultData, data)
			end

			return table.freeze(setmetatable(data, Component))
		else
			return table.freeze(setmetatable({ data = data, [PRIMITIVE_MARKER] = true }, Component))
		end
	end

	--[=[
		@within TableComponentInstance

		```lua
		for id, target in world:query(Target) do
			if shouldChangeTarget(target) then
				world:insert(id, target:patch({ -- modify the existing component
					currentTarget = getNewTarget()
				}))
			end
		end
		```

		A utility function used to immutably modify an existing component instance. Key/value pairs from the passed table
		will override those of the existing component instance.

		As all components are immutable and frozen, it is not possible to modify the existing component directly.

		You can use the `Matter.None` constant to remove a value from the component instance:

		```lua
		target:patch({
			currentTarget = Matter.None -- sets currentTarget to nil
		})
		```

		@param partialNewData {} -- The table to be merged with the existing component data.
		@return TableComponentInstance -- A copy of the component instance with values from `partialNewData` overriding existing values.
	]=]
	function Component:patch(partialNewData)
		return getmetatable(self).new(merge(self, partialNewData))
	end

	lastId += 1
	local id = lastId
	setmetatable(Component, {
		__call = function(_, ...)
			return Component.new(...)
		end,

		__tostring = function()
			return name
		end,

		__len = function()
			return id
		end,

		[DIAGNOSTIC_COMPONENT_MARKER] = true,
	})

	return Component
end

local function assertValidType(value, position)
	if typeof(value) ~= "table" then
		error(string.format("Component #%d is invalid: not a table", position), 3)
	end

	local metatable = getmetatable(value)

	if metatable == nil then
		error(string.format("Component #%d is invalid: has no metatable", position), 3)
	end
end

local function assertValidComponent(value, position)
	assertValidType(value, position)

	local metatable = getmetatable(value)
	if getmetatable(metatable) ~= nil and getmetatable(metatable)[DIAGNOSTIC_COMPONENT_MARKER] then
		error(
			string.format(
				"Component #%d is invalid: Component Instance %s was passed instead of the Component itself!",
				position,
				tostring(metatable)
			),
			3
		)
	end
end

local function assertValidComponentInstance(value, position)
	assertValidType(value, position)

	if getmetatable(value)[DIAGNOSTIC_COMPONENT_MARKER] ~= nil then
		error(
			string.format(
				"Component #%d is invalid: passed a Component instead of a Component instance; "
					.. "did you forget to call it as a function?",
				position
			),
			3
		)
	end
end

local function assertValidComponentInstances(componentInstances)
	for position, componentInstance in componentInstances do
		assertValidComponentInstance(componentInstance, position)
	end
end

local function assertComponentArgsProvided(...)
	if not (...) then
		error(`No components passed to world:{debug.info(3, "n")}, at least one component is required`, 2)
	end
end

local function isPrimitive(componentInstance)
	return componentInstance[PRIMITIVE_MARKER] ~= nil
end

return {
	new = new,
	assertValidComponentInstance = assertValidComponentInstance,
	assertValidComponentInstances = assertValidComponentInstances,
	assertComponentArgsProvided = assertComponentArgsProvided,
	assertValidComponent = assertValidComponent,

	isPrimitive = isPrimitive,
}
