return function(Plasma)
	local create = Plasma.create

	local Item = Plasma.widget(function(text, selected, icon, sideText, barWidth, index)
		local clicked, setClicked = Plasma.useState(false)
		local rightClicked, setRightClicked = Plasma.useState(false)
		local hovered, setHovered = Plasma.useState(false)
		local style = Plasma.useStyle()

		local refs = Plasma.useInstance(function(ref)
			local button = create("TextButton", {
				[ref] = "button",
				AutoButtonColor = false,
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
						[ref] = "index",
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
						[ref] = "mainText",
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 0, 1, 0),
						Text = text,
						RichText = true,
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
						RichText = true,
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

				InputBegan = function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						setClicked(true)
					elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
						setRightClicked(true)
					end
				end,

				MouseEnter = function()
					setHovered(true)
				end,

				MouseLeave = function()
					setHovered(false)
				end,
			})

			return button
		end)

		Plasma.useEffect(function()
			refs.mainText.Text = text
			refs.button.container.Icon.Text = icon or ""
			refs.button.container.Icon.Visible = icon ~= nil
		end, text, icon)

		refs.button.container.sideText.Visible = sideText ~= nil
		refs.button.container.sideText.Text = if sideText ~= nil then sideText else ""
		refs.button.container.sideText.TextColor3 = if selected then style.textColor else style.mutedTextColor
		refs.mainText.TextTruncate = sideText and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None

		refs.button.bar.Size = UDim2.new(barWidth or 0, 0, 0, 1)

		Plasma.useEffect(function()
			refs.button.BackgroundColor3 = if selected
				then style.primaryColor
				elseif hovered then style.bg1
				else style.bg2

			refs.index.TextColor3 = if selected or hovered then style.textColor else style.mutedTextColor
		end, selected, hovered)

		return {
			clicked = function()
				if clicked then
					setClicked(false)
					return true
				end

				return false
			end,
			rightClicked = function()
				if rightClicked then
					setRightClicked(false)
					return true
				end

				return false
			end,
			hovered = function()
				return hovered
			end,
		}
	end)

	return Plasma.widget(function(items)
		Plasma.useInstance(function()
			local frame = create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),

				create("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 2),
				}),
			})

			Plasma.automaticSize(frame, {
				axis = Enum.AutomaticSize.Y,
			})

			return frame
		end)

		local selected
		local rightClicked
		local hovered

		for _, item in items do
			local buttonInList = Item(item.text, item.selected, item.icon, item.sideText, item.barWidth, item.index)

			if buttonInList:clicked() then
				selected = item
			end

			if buttonInList:rightClicked() then
				rightClicked = item
			end

			if buttonInList:hovered() then
				hovered = item
			end
		end

		return {
			selected = function()
				return selected
			end,
			rightClicked = function()
				return rightClicked
			end,
			hovered = function()
				return hovered
			end,
		}
	end)
end
