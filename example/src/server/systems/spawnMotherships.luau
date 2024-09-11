local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.Shared.components)
local Matter = require(ReplicatedStorage.Lib.Matter)

local function spawnMotherships(cx)
	if Matter.useThrottle(10) then
		local spawnPosition = Vector3.new(500, 500, 500)
			* Vector3.new(math.random(1, 2) == 1 and 1 or -1, 1, math.random(1, 2) == 1 and 1 or -1)

		local despawnPosition = Vector3.new(500, 500, 500)
			* Vector3.new(math.random(1, 2) == 1 and 1 or -1, 1, math.random(1, 2) == 1 and 1 or -1)

		local goalPosition = Vector3.new(math.random(-100, 100), 100, math.random(-100, 100))

		cx.world:spawn(
			Components.Mothership({
				goal = goalPosition,
				nextGoal = despawnPosition,
			}),
			Components.Transform({
				cframe = CFrame.new(spawnPosition),
			})
		)
	end

	for id in cx.world:query(Components.Transform, Components.Mothership):without(Components.Model) do
		local model = ReplicatedStorage.Assets.Mothership:Clone()
		model.Parent = workspace
		model.PrimaryPart:SetNetworkOwner(nil)

		cx.world:insert(
			id,
			Components.Model({
				model = model,
			})
		)
	end

	for id, mothership, transform in
		cx.world:query(Components.Mothership, Components.Transform):without(Components.Lasering)
	do
		if (transform.cframe.p - mothership.goal).magnitude < 10 then
			if mothership.lasered then
				cx.world:despawn(id)
			else
				cx.world:insert(
					id,
					mothership:patch({
						goal = mothership.nextGoal,
						lasered = true,
					}),
					Components.Lasering({
						remainingTime = 1,
					})
				)
			end
		end
	end

	for _, mothership, model in cx.world:query(Components.Mothership, Components.Model):without(Components.Lasering) do
		model.model.Roomba.AlignPosition.Position = mothership.goal
	end
end

return spawnMotherships
