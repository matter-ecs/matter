local formatTableModule = require(script.Parent.Parent.formatTable)
local formatTable = formatTableModule.formatTable
local FormatMode = formatTableModule.FormatMode

return function(plasma)
	return plasma.widget(function(world, id, custom)
		local entityData = world:_getEntity(id)

		local str = "<b>Entity " .. id .. "</b>\n\n"

		for component, componentData in pairs(entityData) do
			str ..= tostring(component) .. " "

			if next(componentData) == nil then
				str ..= "{ }\n"
			else
				str ..= (formatTable(componentData, FormatMode.Long, 0, 2) .. "\n")
			end
		end

		custom.tooltip(str, {
			tag = "MatterDebuggerTooltip_AltHover",
			backgroundTransparency = 0.15,
		})
	end)
end
