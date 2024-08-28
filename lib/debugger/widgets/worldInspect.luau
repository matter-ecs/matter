local formatTableModule = require(script.Parent.Parent.formatTable)
local formatTable = formatTableModule.formatTable

local BY_COMPONENT_NAME = "ComponentName"
local BY_ENTITY_COUNT = "EntityCount"

return function(plasma)
	return plasma.widget(function(debugger, objectStack)
		local style = plasma.useStyle()

		local world = debugger.debugWorld

		local cache, setCache = plasma.useState()

		local sortType, setSortType = plasma.useState(BY_COMPONENT_NAME)
		local isAscendingOrder, setIsAscendingOrder = plasma.useState(true)

		local skipIntersections, setSkipIntersections = plasma.useState(true)
		local debugComponent, setDebugComponent = plasma.useState()

		local closed = plasma
			.window({
				title = "World inspect",
				closable = true,
			}, function()
				if not cache or os.clock() - cache.createdTime > debugger.componentRefreshFrequency then
					cache = {
						createdTime = os.clock(),
						uniqueComponents = {},
						emptyEntities = 0,
					}

					setCache(cache)

					for _, entityData in world do
						if next(entityData) == nil then
							cache.emptyEntities += 1
						else
							for component in entityData do
								cache.uniqueComponents[component] = (cache.uniqueComponents[component] or 0) + 1
							end
						end
					end
				end

				plasma.row({
					verticalAlignment = Enum.VerticalAlignment.Center,
				}, function()
					plasma.heading("SIZE:")
					plasma.label(
						`{world:size()} {if cache.emptyEntities > 0 then `({cache.emptyEntities} empty)` else ""}`
					)

					if plasma.button("View Raw"):clicked() then
						table.clear(objectStack)
						objectStack[1] = {
							value = world,
							key = "Raw World",
						}
					end
				end)

				plasma.row({ padding = 15 }, function()
					if plasma.checkbox("Show intersections", { checked = not skipIntersections }):clicked() then
						setSkipIntersections(not skipIntersections)
					end
				end)

				local items = {}
				for component, count in cache.uniqueComponents do
					table.insert(items, {
						count,
						tostring(component),
						selected = debugComponent == component,
						component = component,
					})
				end

				local indexForSort = if sortType == BY_ENTITY_COUNT then 1 else 2

				table.sort(items, function(a, b)
					if isAscendingOrder then
						return a[indexForSort] < b[indexForSort]
					end

					return a[indexForSort] > b[indexForSort]
				end)

				local arrow = if isAscendingOrder then "▲" else "▼"
				local countHeading = `{if sortType == BY_ENTITY_COUNT then arrow else ""} Count `
				local componentHeading = `{if sortType == BY_COMPONENT_NAME then arrow else ""} Component`
				local headings = { countHeading, componentHeading }
				table.insert(items, 1, headings)

				plasma.row({ padding = 30 }, function()
					local worldInspectTable = plasma.table(items, {
						width = 200,
						headings = true,
						selectable = true,
						font = Enum.Font.Code,
					})

					local selectedHeading = worldInspectTable:selectedHeading()

					if headings[selectedHeading] == headings[1] then
						if sortType == BY_ENTITY_COUNT then
							setIsAscendingOrder(not isAscendingOrder)
						else
							setSortType(BY_ENTITY_COUNT)
						end
					elseif headings[selectedHeading] == headings[2] then
						if sortType == BY_COMPONENT_NAME then
							setIsAscendingOrder(not isAscendingOrder)
						else
							setSortType(BY_COMPONENT_NAME)
						end
					end

					local selectedRow = worldInspectTable:selected()

					if selectedRow then
						setDebugComponent(selectedRow.component)
					end

					if debugComponent then
						local items = { { "Entity ID", tostring(debugComponent) } }
						local intersectingComponents = {}

						local intersectingData = {}

						for entityId, data in world:query(debugComponent) do
							table.insert(items, {
								entityId,
								formatTable(data),

								selected = debugger.debugEntity == entityId,
							})

							intersectingData[entityId] = {}

							if skipIntersections then
								continue
							end

							for component, value in world:_getEntity(entityId) do
								if component == debugComponent then
									continue
								end

								local index = table.find(intersectingComponents, component)

								if not index then
									table.insert(intersectingComponents, component)

									index = #intersectingComponents
								end

								intersectingData[entityId][index] = value
							end
						end

						for i, item in items do
							if i == 1 then
								for _, component in intersectingComponents do
									table.insert(item, tostring(component))
								end

								continue
							end

							for i = 1, #intersectingComponents do
								local data = intersectingData[item[1]][i]

								table.insert(item, if data then formatTable(data) else "")
							end
						end

						plasma.useKey(tostring(debugComponent))

						local tableWidget = plasma.table(items, {
							font = Enum.Font.Code,
							selectable = true,
							headings = true,
						})

						local selectedRow = tableWidget:selected()
						local hovered = tableWidget:hovered()

						if selectedRow then
							debugger.debugEntity = selectedRow[1]
						end

						if hovered then
							local entityId = hovered[1]

							if debugger.debugEntity == entityId or not world:contains(entityId) then
								return
							end

							if debugger.findInstanceFromEntity then
								local model = debugger.findInstanceFromEntity(entityId)

								if model then
									plasma.highlight(model, {
										fillColor = style.primaryColor,
									})
								end
							end
						end
					end
				end)
			end)
			:closed()

		if closed then
			return closed
		end
		return nil
	end)
end
