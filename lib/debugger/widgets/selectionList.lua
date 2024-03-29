return function(Plasma)
	local create = Plasma.create

	local Item = Plasma.widget(function(text, selected, icon, sideText, _, barWidth, index)
		local clicked, setClicked = Plasma.useState(false)
		local style = Plasma.useStyle()

		local refs = Plasma.useInstance(function(ref)
			local button = create("TextButton", {
				[ref] = "button",
				Size = UDim2.new(1, 0, 0, 25),
				Text = "",

				create("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),

				create("UIPadding", {
					PaddingBottom = UDim.new(0, 0),
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
					PaddingTop = UDim.new(0, 0),
				}),

				create("Frame", {
					[ref] = "container",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),

					create("UIListLayout", {
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 10),
					}),

					create("TextLabel", {
						Name = "index",
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.new(0, 0, 1, 0),
						BackgroundTransparency = 1,
						Text = index,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextSize = 11,
						TextColor3 = style.mutedTextColor,
						Font = Enum.Font.Gotham,
						Visible = index ~= nil,
					}),

					create("TextLabel", {
						Name = "Icon",
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 22, 1, 0),
						Text = icon,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextSize = 16,
						TextColor3 = style.textColor,
						Font = Enum.Font.GothamBold,
					}),

					create("TextLabel", {
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 0, 1, 0),
						Text = text,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextSize = 13,
						TextColor3 = style.textColor,
						Font = Enum.Font.Gotham,
						TextTruncate = Enum.TextTruncate.AtEnd,

						create("UISizeConstraint", {
							MaxSize = Vector2.new(165, math.huge),
						}),
					}),

					create("TextLabel", {
						[ref] = "sideText",
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.new(0, 0, 1, 0),
						Text = "",
						TextXAlignment = Enum.TextXAlignment.Left,
						TextSize = 11,
						TextColor3 = style.mutedTextColor,
						Font = Enum.Font.Gotham,
					}),
				}),

				create("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),

				create("Frame", {
					[ref] = "bar",
					BackgroundColor3 = style.mutedTextColor,
					BorderSizePixel = 0,
					LayoutOrder = 1,
					ZIndex = 2,
				}),

				Activated = function()
					setClicked(true)
				end,
			})

			return button
		end)

		Plasma.useEffect(function()
			refs.button.container.TextLabel.Text = text
			refs.button.container.Icon.Text = icon or ""
			refs.button.container.Icon.Visible = icon ~= nil
		end, text, icon)

		refs.button.container.sideText.Visible = sideText ~= nil
		refs.button.container.sideText.Text = if sideText ~= nil then sideText else ""
		refs.button.container.sideText.TextColor3 = if selected then style.textColor else style.mutedTextColor
		refs.button.container.TextLabel.TextTruncate = sideText and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None

		refs.button.bar.Size = UDim2.new(barWidth or 0, 0, 0, 1)

		Plasma.useEffect(function()
			refs.button.BackgroundColor3 = if selected then style.primaryColor else style.bg2
		end, selected)

		return {
			clicked = function()
				if clicked then
					setClicked(false)
					return true
				end

				return false
			end,
		}
	end)

	return Plasma.widget(function(items, options)
		options = options or {}

		Plasma.useInstance(function()
			local frame = create("Frame", {
				BackgroundTransparency = 1,
				Size = options.width and UDim2.new(0, options.width, 0, 0) or UDim2.new(1, 0, 0, 0),

				create("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})

			Plasma.automaticSize(frame, {
				axis = Enum.AutomaticSize.Y,
			})

			return frame
		end)

		local selected

		for _, item in items do
			if
				Item(item.text, item.selected, item.icon, item.sideText, options.width, item.barWidth, item.index):clicked()
			then
				selected = item
			end
		end

		return {
			selected = function()
				return selected
			end,
		}
	end)
end
