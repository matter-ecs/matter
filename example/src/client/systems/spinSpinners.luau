local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Components = require(ReplicatedStorage.Shared.components)

local function spinSpinners(cx)
	if cx.widgets.checkbox("Disable Spinning"):checked() then
		return
	end

	local transparency = cx.widgets.slider(1)

	local randomize = cx.widgets.button("Randomize colors!"):clicked()

	for _, model in cx.world:query(Components.Model, Components.Spinner) do
		model.model.PrimaryPart.CFrame = model.model.PrimaryPart.CFrame * CFrame.Angles(0, math.rad(5), 0)
		model.model.PrimaryPart.Transparency = transparency

		if randomize then
			model.model.PrimaryPart.BrickColor = BrickColor.random()
		end
	end
end

return {
	system = spinSpinners,
	event = "Stepped",
}
