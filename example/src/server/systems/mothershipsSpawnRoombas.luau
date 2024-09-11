local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.Shared.components)
local Matter = require(ReplicatedStorage.Lib.Matter)

local function mothershipsSpawnRoombas(cx)
	for id, model, lasering, transform in
		cx.world:query(Components.Model, Components.Lasering, Components.Transform, Components.Mothership)
	do
		model.model.Beam.Transparency = 1 - lasering.remainingTime

		lasering = lasering:patch({
			remainingTime = lasering.remainingTime - Matter.useDeltaTime(),
		})

		if not lasering.spawned then
			local spawnPosition = Vector3.new(transform.cframe.p.X, 11, transform.cframe.p.Z)

			cx.world:spawn(
				Components.Roomba(),
				Components.Charge({
					charge = 100,
				}),
				Components.Transform({
					cframe = CFrame.new(spawnPosition),
				})
			)

			lasering = lasering:patch({ spawned = true })
		end

		if lasering.remainingTime <= 0 then
			cx.world:remove(id, Components.Lasering)
		else
			cx.world:insert(id, lasering)
		end
	end
end

return mothershipsSpawnRoombas
