export type Data = number | string | { [any]: any }

local entityToRelations: { [number]: { unknown } } = {}
local function newRelation(component, entityId, data: Data?)
	local relations = entityToRelations[entityId] or {}
	local relation = relations[component]
	if relation then
		return { relation, data }
	end

	local relation = { cascade = false }
	relations[component] = relation
	entityToRelations[entityId] = relations
	return { relation, data }
end

return {
	newRelation = newRelation,
}
