local formatValueModule = require(script.Parent.Parent.formatValue)
local getAllComponentData = require(script.Parent.Parent.getAllComponentData)
local formatValue = formatValueModule.formatValue
local FormatMode = formatValueModule.FormatMode

return function(plasma)
	return plasma.widget(function(world, id, custom)
		local entityData = getAllComponentData(world, id)

		local str = "<b>Entity " .. id .. "</b>\n\n"

		for component, componentData in pairs(entityData) do
			str ..= tostring(component) .. " "

			if next(componentData) == nil then
				str ..= "{ }\n"
			else
				str ..= (formatValue(componentData, FormatMode.Long, 0, 2) .. "\n")
			end
		end

		custom.tooltip(str, {
			tag = "MatterDebuggerTooltip_AltHover",
			backgroundTransparency = 0.15,
		})
	end)
end
