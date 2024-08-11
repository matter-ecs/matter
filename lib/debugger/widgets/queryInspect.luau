local format = require(script.Parent.Parent.formatTable)

return function(plasma)
	return plasma.widget(function(debugger)
		return plasma
			.window({
				title = "Queries",
				closable = true,
			}, function()
				if #debugger._queries == 0 then
					return plasma.label("No queries.")
				end

				for i, query in debugger._queries do
					if query.changedComponent then
						plasma.heading(string.format("Query Changed %d", i))

						plasma.label(tostring(query.changedComponent))

						continue
					end

					local budgetUsed = math.floor((query.duration / debugger.debugSystemRuntime) * 100)

					plasma.heading(`Query {i} - {budgetUsed}%`)
					plasma.label(table.concat(query.componentNames, ", "))
				end
				return nil
			end)
			:closed()
	end)
end
