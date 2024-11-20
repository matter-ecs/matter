local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.Shared.components)

local function spinSpinners(world, _, ui)
	if ui.checkbox("Disable Spinning"):checked() then
		return
	end

	local transparency = ui.slider(1)

	local randomize = ui.button("Randomize colors!"):clicked()

	for _, model in world:query(Components.Model, Components.Spinner) do
		model.PrimaryPart.CFrame = model.PrimaryPart.CFrame * CFrame.Angles(0, math.rad(5), 0)
		model.PrimaryPart.Transparency = transparency

		if randomize then
			model.PrimaryPart.BrickColor = BrickColor.random()
		end
	end
end

return {
	system = spinSpinners,
	event = "Stepped",
}
