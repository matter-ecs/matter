--#selene:allow(empty_loop)
local useCurrentSystem = require(script.Parent.Parent.topoRuntime).useCurrentSystem
local World = require(script.Parent.Parent.World)
local rollingAverage = require(script.Parent.Parent.rollingAverage)

local originalQuery = World.query

local function hookWorld(debugger)
	World.query = function(world, ...)
		if useCurrentSystem() == debugger.debugSystem then
			local start = os.clock()

			-- while this seems like a mistake, it is necessary!
			-- we duplicate the query to avoid draining the original one.
			-- we iterate through so we can calculate the query's budget
			-- see https://github.com/matter-ecs/matter/issues/106
			-- and https://github.com/matter-ecs/matter/pull/107
			for _ in originalQuery(world, ...) do
			end

			local file, line = debug.info(2, "sl")

			local key = file .. line
			local samples = debugger._queryDurationSamples
			local sample = samples[key]
			if not sample then
				sample = {}
				samples[key] = sample
			end

			local componentNames = {}
			for i = 1, select("#", ...) do
				table.insert(componentNames, tostring((select(i, ...))))
			end

			local duration = os.clock() - start
			rollingAverage.addSample(sample, duration)

			local averageDuration = rollingAverage.getAverage(debugger._queryDurationSamples[file .. line])

			table.insert(debugger._queries, {
				averageDuration = averageDuration,
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
