local formatTableModule = require(script.Parent.Parent.formatTable)
local formatTable = formatTableModule.formatTable
local FormatMode = formatTableModule.FormatMode

return function(plasma)
	return plasma.widget(function(debugger, world)
		local style = plasma.useStyle()

		local closed = plasma
			.window({
				title = string.format("Entity %d", debugger.debugEntity),
				closable = true,
			}, function()
				if not world:contains(debugger.debugEntity) then
					debugger.debugEntity = nil
					return
				end

				if debugger.findInstanceFromEntity then
					local model = debugger.findInstanceFromEntity(debugger.debugEntity)

					if model then
						plasma.highlight(model, {
							fillColor = style.primaryColor,
						})
					end
				end

				plasma.row(function()
					if plasma.button("despawn"):clicked() then
						world:despawn(debugger.debugEntity)
						debugger.debugEntity = nil
					end
				end)

				if not debugger.debugEntity then
					return
				end

				local items = { { "Component", "Data" } }

				local location = world.allEntities[debugger.debugEntity]
				local archetype = location.archetype
				local indexInArchetype = location.indexInArchetype

				for index, field in archetype.fields do
					local componentId = archetype.componentIds[index]
					local component = world.componentIdToComponent[componentId]
					local data = field[indexInArchetype]

					table.insert(items, {
						tostring(component),
						formatTable(data, FormatMode.Long),
					})
				end

				plasma.useKey(debugger.debugEntity)
				plasma.table(items, {
					headings = true,
					font = Enum.Font.Code,
				})
			end)
			:closed()

		if closed then
			debugger.debugEntity = nil
		end
	end)
end
