--#selene:allow(empty_loop)
local useCurrentSystem = require(script.Parent.Parent.topoRuntime).useCurrentSystem
local World = require(script.Parent.Parent.World)

local originalQuery = World.query

local function hookWorld(debugger)
	World.query = function(world, ...)
		if useCurrentSystem() == debugger.debugSystem then
			local start = os.clock()

			for _ in originalQuery(world, ...) do
			end

			local duration = os.clock() - start

			local componentNames = {}
			for i = 1, select("#", ...) do
				table.insert(componentNames, tostring((select(i, ...))))
			end

			table.insert(debugger._queries, {
				duration = duration,
				componentNames = componentNames,
			})
		end

		return originalQuery(world, ...)
	end
end

local function unhookWorld()
	World.query = originalQuery
end

return {
	hookWorld = hookWorld,
	unhookWorld = unhookWorld,
}
