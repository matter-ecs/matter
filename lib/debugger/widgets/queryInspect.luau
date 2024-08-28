local function getColorForBudget(color: Color3): string
	local r = math.floor(color.R * 255)
	local g = math.floor(color.G * 255)
	local b = math.floor(color.B * 255)

	return `{r},{g},{b}`
end

return function(Plasma)
	return Plasma.widget(function(debugger)
		local queryWindow = Plasma.window({
			title = "Query Resource Usage (%)",
			closable = true,
		}, function()
			if #debugger._queries == 0 then
				return Plasma.label("No queries.")
			end

			-- Plasma windows do not respect the title, so we need to
			-- fill the content frame to extend the width of the widget
			Plasma.heading("---------------------------------------------          ")

			for i, query in debugger._queries do
				if query.changedComponent then
					Plasma.label(string.format("Query Changed %d", i))
					Plasma.heading(tostring(query.changedComponent))

					continue
				end

				local budgetUsed =
					math.clamp(math.floor((query.averageDuration / debugger.debugSystemRuntime) * 100), 0, 100)

				local color = Color3.fromRGB(135, 255, 111)
				if budgetUsed >= 75 then
					color = Color3.fromRGB(244, 73, 73)
				elseif budgetUsed >= 50 then
					color = Color3.fromRGB(255, 157, 0)
				elseif budgetUsed >= 25 then
					color = Color3.fromRGB(230, 195, 24)
				end

				Plasma.label(`<font color="rgb({getColorForBudget(color)})"><b>Query {i} - {budgetUsed}%</b></font>`)
				Plasma.heading(table.concat(query.componentNames, ", "))
			end
			return nil
		end)

		return queryWindow:closed()
	end)
end
