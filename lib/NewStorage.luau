--!strict
type EntityId = number
type ComponentInstance = { [any]: any }
type ComponentMetatable = { [any]: any }

type ComponentId = ComponentMetatable
type ArchetypeId = number
--type Archetype = { id: number, componentMetatables: { ComponentId } }

type ContiguousEntityId = number
type Archetype = {
	id: number,
	componentMetatables: { ComponentId },

	-- component ids are contiguous by nature
	components: { [ComponentId]: { [ContiguousEntityId]: ComponentInstance } },
}

-- find archetypes containing component
type ComponentIndex = { [ComponentId]: { ArchetypeId } }

-- find archetype for entity
type EntityIndex = { [EntityId]: Archetype }
