-- temporary TextField component unique to Matter's repository
-- for the client system search feature
-- this should be a native Plasma component eventually
return function(Plasma)
	local create = Plasma.create

	return Plasma.widget(function(placeholder, options)
		options = options or { editable = true }
		local text, setText = Plasma.useState("")
		local lastUpdate, setLastUpdate = Plasma.useState(os.clock())

		local refs = Plasma.useInstance(function(ref)
			local style = Plasma.useStyle()

			return create("Frame", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,

				create("UIPadding", {
					PaddingLeft = UDim.new(0, 1),
					PaddingRight = UDim.new(0, 1),
					PaddingTop = UDim.new(0, 0),
					PaddingBottom = UDim.new(0, 0),
				}),

				create("TextBox", {
					[ref] = "textField",
					AnchorPoint = Vector2.new(0, 0),
					TextEditable = options.editable,
					BackgroundTransparency = 0,
					BackgroundColor3 = style.bg1,
					Font = Enum.Font.Gotham,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = style.textColor,
					TextSize = 12,
					Size = UDim2.fromScale(1, 1),
					PlaceholderText = placeholder,
					Text = text,
					RichText = true,

					create("UICorner", {
						CornerRadius = UDim.new(0, 4),
					}),

					create("UIStroke", {
						Thickness = 1,
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					}),

					create("UIPadding", {
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
					}),

					Changed = function(property: string)
						if property == "Text" then
							setLastUpdate(os.clock())
						end
					end,
				}),
			})
		end)

		local instance = refs.textField
		local shouldUpdate = (os.clock() - lastUpdate) > 0.15

		-- let's cap text updates to every 0.15 seconds
		if shouldUpdate then
			setText(instance.Text)
			setLastUpdate(os.clock())
		end

		return {
			text = function()
				return text
			end,
		}
	end)
end
