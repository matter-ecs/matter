return function(plasma)
	return plasma.widget(function(debugger)
		local queryWindow = plasma.window({
			title = "Query Resource Usage (%)",
			closable = true,
		}, function()
			if #debugger._queries == 0 then
				return plasma.label("No queries.")
			end

			--
			plasma.heading("---------------------------------------------------")

			for i, query in debugger._queries do
				if query.changedComponent then
					plasma.heading(string.format("Query Changed %d", i))
					plasma.label(tostring(query.changedComponent))

					continue
				end

				local budgetUsed =
					math.clamp(math.floor((query.averageDuration / debugger.debugSystemRuntime) * 100), 0, 100)

				plasma.heading(`<b>Query {i} - {budgetUsed}%</b>`)
				plasma.label(table.concat(query.componentNames, ", "))
			end
			return nil
		end)

		return queryWindow:closed()
	end)
end
