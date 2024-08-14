local CollectionService = game:GetService("CollectionService")

type Options = {
	tag: string,
	backgroundTransparency: number?,
}

return function(plasma)
	local create = plasma.create

	return plasma.widget(function(text, options: Options)
		local refs = plasma.useInstance(function(ref)
			local style = plasma.useStyle()

			create("TextLabel", {
				[ref] = "label",
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextSize = 13,
				RichText = true,
				BorderSizePixel = 0,
				Font = Enum.Font.Code,
				TextStrokeTransparency = 0.5,
				TextColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = options.backgroundTransparency or 0.2,
				BackgroundColor3 = style.bg1,
				AutomaticSize = Enum.AutomaticSize.XY,
				ZIndex = 100,

				create("UIPadding", {
					PaddingBottom = UDim.new(0, 4),
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
					PaddingTop = UDim.new(0, 4),
				}),

				create("UICorner"),

				create("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			})

			CollectionService:AddTag(ref.label, options.tag)

			return ref.label
		end)

		refs.label.Text = text
	end)
end
