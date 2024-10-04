function archetypeOf(componentIds: { number })
	table.sort(componentIds)
	return table.concat(componentIds, "_")
end

return {
	archetypeOf = archetypeOf,
}
