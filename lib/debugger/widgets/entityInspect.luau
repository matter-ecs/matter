local formatTableModule = require(script.Parent.Parent.formatTable)
local getAllComponentData = require(script.Parent.Parent.getAllComponentData)
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
				for component, componentData in getAllComponentData(world, debugger.debugEntity) do
					table.insert(items, {
						tostring(component),
						formatTable(componentData, FormatMode.Long),
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
