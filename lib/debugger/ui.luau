local RunService = game:GetService("RunService")
local World = require(script.Parent.Parent.World)
local rollingAverage = require(script.Parent.Parent.rollingAverage)

local function systemName(system)
	local systemFn = if type(system) == "table" then system.system else system
	local name = debug.info(systemFn, "n")

	if name ~= "" and name ~= "system" then
		return name
	end

	local source = debug.info(systemFn, "s")
	local segments = string.split(source, ".")

	return segments[#segments]
end

local timeUnits = { "s", "ms", "μs", "ns" }
local function formatDuration(duration)
	local unit = 1
	while duration < 1 and unit < #timeUnits do
		duration *= 1000
		unit += 1
	end

	return duration, timeUnits[unit]
end

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()
local LONG_SYSTEM_NAME = 24

local function ui(debugger, loop)
	local plasma = debugger.plasma
	local custom = debugger._customWidgets
	local skipSystems = loop._skipSystems

	plasma.setStyle({
		primaryColor = Color3.fromHex("bd515c"),
	})

	local objectStack = plasma.useState({})
	local worldViewOpen, setWorldViewOpen = plasma.useState(false)
	local worldExists = debugger.debugWorld ~= nil

	if debugger.hoverEntity and worldExists then
		if debugger.debugWorld:contains(debugger.hoverEntity) then
			custom.hoverInspect(debugger.debugWorld, debugger.hoverEntity, custom)
		end
	end

	local hoveredSystem

	custom.container(function()
		if debugger:_isServerView() then
			return
		end

		custom.panel(function()
			if
				custom
					.realmSwitch({
						left = "client",
						right = "server",
						isRight = IS_SERVER,
						tag = if IS_SERVER then "MatterDebuggerSwitchToClientView" else nil,
					})
					:clicked()
			then
				if IS_CLIENT then
					debugger:switchToServerView()
				end
			end

			plasma.space(15)
			plasma.heading("STATE")
			plasma.space(10)

			local items = {}

			for index, object in loop._state do
				if type(object) ~= "table" then
					continue
				end

				local isWorld = getmetatable(object) == World

				local selected = (#objectStack > 0 and object == objectStack[#objectStack].value)
					or (debugger.debugWorld == object and worldViewOpen)

				local name = debugger.loopParameterNames[index]
				local defaultName = (if isWorld then "World" else "table") .. " " .. index

				table.insert(items, {
					text = if name then name else defaultName,
					icon = if isWorld then "🌐" else "{}",
					object = object,
					selected = selected,
					isWorld = isWorld,
				})
			end

			local selectedState = custom.selectionList(items):selected()

			if selectedState then
				if selectedState.isWorld then
					if worldViewOpen and debugger.debugWorld == selectedState.object then
						debugger.debugWorld = nil
						setWorldViewOpen(false)
					else
						debugger.debugWorld = selectedState.object
						setWorldViewOpen(true)
					end
				else
					local previousFirstValue = if objectStack[1] then objectStack[1].value else nil
					table.clear(objectStack)

					if selectedState.object ~= previousFirstValue then
						objectStack[1] = {
							key = selectedState.text,
							icon = selectedState.icon,
							value = selectedState.object,
						}
					end
				end
			end

			plasma.space(15)
			plasma.heading("SYSTEMS")
			plasma.space(10)

			local durations = {}
			local longestDuration = 0

			for _, eventName in debugger._eventOrder do
				local systems = loop._orderedSystemsByEvent[eventName]

				if not systems then
					continue
				end

				plasma.heading(eventName, {
					font = Enum.Font.Gotham,
				})
				plasma.space(5)

				local listOfSystems = {}

				for _, system in systems do
					local samples = loop.profiling[system]
					if samples then
						local duration = rollingAverage.getAverage(samples)
						durations[system] = duration
						longestDuration = math.max(longestDuration, duration)
					end
				end

				for index, system in systems do
					local averageFrameTime = ""
					local icon

					local duration = durations[system] or 0
					local humanDuration, unit = formatDuration(duration)
					averageFrameTime = string.format("%.0f%s", humanDuration, unit)

					if duration > 0.004 then -- 4ms
						icon = "\xe2\x9a\xa0\xef\xb8\x8f"
					end

					if loop._systemErrors[system] then
						icon = "\xf0\x9f\x92\xa5"
					end

					local barWidth
					if longestDuration == 0 then
						barWidth = 0
					else
						barWidth = duration / longestDuration
					end

					local systemIsDisabled = skipSystems[system]
					local systemName = systemName(system)
					local length = string.len(systemName)

					if systemIsDisabled then
						length += 4
					end

					table.insert(listOfSystems, {
						text = if systemIsDisabled then `<i><s>{systemName}</s></i>` else systemName,
						sideText = if systemIsDisabled then `<b>{"(disabled)"}</b>` else averageFrameTime,
						selected = debugger.debugSystem == system,
						system = system,
						icon = icon,
						barWidth = barWidth,
						index = index,
					})
				end

				local systemList = custom.selectionList(listOfSystems, custom)
				local selected = systemList:selected()
				local rightClicked = systemList:rightClicked()
				hoveredSystem = systemList:hovered()

				if selected then
					local selectedSystem = selected.system
					if selectedSystem == debugger.debugSystem then
						debugger.debugSystem = nil
					else
						debugger.debugSystem = selectedSystem
					end
				elseif rightClicked then
					local rightClickedSystem = rightClicked.system
					if rightClickedSystem then
						skipSystems[rightClickedSystem] = not skipSystems[rightClickedSystem]
					end
				end

				if debugger.debugSystem then
					debugger.debugSystemRuntime = durations[debugger.debugSystem]
				else
					debugger.debugSystemRuntime = nil
				end

				plasma.space(10)
			end
		end)

		debugger.parent = custom.container(function()
			if debugger.debugWorld and worldViewOpen then
				local closed = custom.worldInspect(debugger, objectStack)

				if closed then
					setWorldViewOpen(false)
				end
			end

			if debugger.debugWorld and debugger.debugEntity then
				custom.entityInspect(debugger)
			end

			if #objectStack > 0 then
				custom.valueInspect(objectStack, custom)
			end

			if debugger.debugSystem then
				local queriesOpen, setQueriesOpen = plasma.useState(false)
				local logsOpen, setLogsOpen = plasma.useState(true)

				if loop._systemLogs[debugger.debugSystem] == nil then
					loop._systemLogs[debugger.debugSystem] = {}
				end

				local numLogs = #loop._systemLogs[debugger.debugSystem]

				local name = systemName(debugger.debugSystem)

				local closed = plasma
					.window({
						title = "System",
						closable = true,
					}, function()
						plasma.useKey(name)

						if plasma.button(string.format("View queries (%d)", #debugger._queries)):clicked() then
							setQueriesOpen(true)
						end

						if numLogs > 0 then
							if plasma.button(string.format("View logs (%d)", numLogs)):clicked() then
								setLogsOpen(true)
							end
						end

						local currentlyDisabled = skipSystems[debugger.debugSystem]

						if
							plasma
								.checkbox("<font size='13'>Disable System</font>", {
									checked = currentlyDisabled,
								})
								:clicked()
						then
							skipSystems[debugger.debugSystem] = not currentlyDisabled
						end
					end)
					:closed()

				if queriesOpen then
					local closed = custom.queryInspect(debugger)

					if closed then
						setQueriesOpen(false)
					end
				end

				if loop._systemErrors[debugger.debugSystem] then
					custom.errorInspect(debugger, custom)
				end

				plasma.useKey(name)

				if numLogs > 0 and logsOpen then
					local closed = plasma
						.window({
							closable = true,
							title = "Logs",
						}, function()
							local items = {}
							for i = numLogs, 1, -1 do
								table.insert(items, { loop._systemLogs[debugger.debugSystem][i] })
							end
							plasma.table(items, {
								font = Enum.Font.Code,
							})
						end)
						:closed()

					if closed then
						setLogsOpen(false)
					end
				end

				if closed then
					debugger.debugSystem = nil
				end
			end

			plasma.useKey(nil)
			debugger.frame = custom.frame()
		end, {
			marginTop = 46,
			marginLeft = 10,
			direction = Enum.FillDirection.Horizontal,
		})
	end, {
		direction = Enum.FillDirection.Horizontal,
		padding = 0,
	})

	if hoveredSystem and hoveredSystem.system then
		local hoveredSystemName = systemName(hoveredSystem.system)
		local length = string.len(hoveredSystemName)
		local systemDisabled = skipSystems[hoveredSystem.system]

		if systemDisabled then
			length += 2
		end

		if length >= LONG_SYSTEM_NAME then
			custom.tooltip(`<b>{hoveredSystemName}{if systemDisabled then " (disabled)" else ""}</b>`, {
				tag = "MatterDebuggerTooltip_System",
				backgroundTransparency = 0,
			})
		end
	end
end

return ui
