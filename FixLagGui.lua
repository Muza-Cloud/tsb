local players = game:GetService("Players")
local coreGui = game:GetService("CoreGui")
local tweenService = game:GetService("TweenService")
local uis = game:GetService("UserInputService")

local local_player = players.LocalPlayer
while not local_player do
    task.wait()
    local_player = players.LocalPlayer
end

local environment = getgenv and getgenv() or _G

local api = environment.fixlag_core
if not api then
    warn("[fixlag gui] fixlag core is not loaded")
    return
end

if api.destroy_gui then
    pcall(api.destroy_gui)
end

local author = "techinified"

local theme = {
       panel_top = Color3.fromRGB(30, 33, 45),
    panel_bottom = Color3.fromRGB(16, 17, 23),
             row = Color3.fromRGB(33, 36, 49),
       row_hover = Color3.fromRGB(42, 46, 62),
          button = Color3.fromRGB(40, 44, 58),
    button_hover = Color3.fromRGB(54, 59, 76),
            text = Color3.fromRGB(235, 237, 242),
      text_muted = Color3.fromRGB(140, 147, 163),
          danger = Color3.fromRGB(240, 110, 110),
    danger_hover = Color3.fromRGB(88, 40, 48),
          accent = Color3.fromRGB(64, 196, 120),
      accent_alt = Color3.fromRGB(56, 189, 248),
      switch_off = Color3.fromRGB(70, 76, 92),
       switch_on = Color3.fromRGB(64, 196, 120),
            knob = Color3.fromRGB(255, 255, 255),
     idle_stroke = Color3.fromRGB(255, 255, 255),
         dot_off = Color3.fromRGB(88, 95, 112),
       logo_text = Color3.fromRGB(14, 16, 22),
}

local panel_width = 284
local header_height = 52
local body_height = 240
local row_height = 40
local expanded_size = UDim2.fromOffset(panel_width, header_height + body_height)
local collapsed_size = UDim2.fromOffset(panel_width, header_height)
local panel_corner = UDim.new(0, 12)
local corner = UDim.new(0, 9)
local pill = UDim.new(1, 0)

local switch_tween = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local hover_tween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local collapse_tween = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local intro_tween = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function create(class_name, properties, children)
    local instance = Instance.new(class_name)
    for property, value in pairs(properties) do
        instance[property] = value
    end
    for _, child in ipairs(children or {}) do
        child.Parent = instance
    end
    return instance
end

local function rounded(radius)
    return create("UICorner", { CornerRadius = radius })
end

local function tween(instance, info, goal)
    tweenService:Create(instance, info, goal):Play()
end

local function accent_gradient(rotation)
    return create("UIGradient", {
        Color = ColorSequence.new(theme.accent, theme.accent_alt),
        Rotation = rotation,
    })
end

local function to_hex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function row_appearance(enabled)
    if enabled then
        return {
            track = theme.switch_on,
            knob = UDim2.fromOffset(21, 3),
            stroke_color = theme.accent,
            stroke_transparency = 0.55,
            label = theme.text,
            dot = theme.accent,
        }
    end
    return {
        track = theme.switch_off,
        knob = UDim2.fromOffset(3, 3),
        stroke_color = theme.idle_stroke,
        stroke_transparency = 0.82,
        label = theme.text_muted,
        dot = theme.dot_off,
    }
end

local function create_toggle_row(feature, order)
    local look = row_appearance(feature.enabled)

    local dot = create("Frame", {
        Size = UDim2.fromOffset(6, 6),
        Position = UDim2.new(0, 12, 0.5, -3),
        BackgroundColor3 = look.dot,
        BorderSizePixel = 0,
    }, { rounded(pill) })

    local knob = create("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = look.knob,
        BackgroundColor3 = theme.knob,
        BorderSizePixel = 0,
    }, { rounded(pill) })

    local track = create("Frame", {
        Size = UDim2.fromOffset(40, 22),
        Position = UDim2.new(1, -52, 0.5, -11),
        BackgroundColor3 = look.track,
        BorderSizePixel = 0,
    }, {
        rounded(pill),
        create("UIGradient", {
            Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)),
            Rotation = 90,
        }),
        knob,
    })

    local label = create("TextLabel", {
        Size = UDim2.new(1, -84, 1, 0),
        Position = UDim2.fromOffset(28, 0),
        BackgroundTransparency = 1,
        Text = feature.label,
        TextColor3 = look.label,
        TextSize = 14,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
    })

    local stroke = create("UIStroke", {
        Color = look.stroke_color,
        Transparency = look.stroke_transparency,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })

    local row = create("TextButton", {
        Size = UDim2.new(1, 0, 0, row_height),
        BackgroundColor3 = theme.row,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = order,
    }, { rounded(corner), stroke, dot, label, track })

    row.MouseEnter:Connect(function()
        tween(row, hover_tween, { BackgroundColor3 = theme.row_hover })
    end)
    row.MouseLeave:Connect(function()
        tween(row, hover_tween, { BackgroundColor3 = theme.row })
    end)

    row.Activated:Connect(function()
        local enabled = not feature.enabled
        local next_look = row_appearance(enabled)
        tween(track, switch_tween, { BackgroundColor3 = next_look.track })
        tween(knob, switch_tween, { Position = next_look.knob })
        tween(stroke, switch_tween, {
            Color = next_look.stroke_color,
            Transparency = next_look.stroke_transparency,
        })
        tween(label, switch_tween, { TextColor3 = next_look.label })
        tween(dot, switch_tween, { BackgroundColor3 = next_look.dot })
        feature:set_enabled(enabled)
    end)

    return row
end

local function create_header_button(text, offset_from_right, text_color, hover_color, on_activated)
    local button = create("TextButton", {
        Size = UDim2.fromOffset(28, 28),
        Position = UDim2.new(1, offset_from_right, 0.5, -14),
        BackgroundColor3 = theme.button,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = text,
        TextColor3 = text_color,
        TextSize = 15,
        Font = Enum.Font.GothamBold,
    }, { rounded(UDim.new(0, 8)) })

    button.MouseEnter:Connect(function()
        tween(button, hover_tween, { BackgroundColor3 = hover_color })
    end)
    button.MouseLeave:Connect(function()
        tween(button, hover_tween, { BackgroundColor3 = theme.button })
    end)
    button.Activated:Connect(function()
        on_activated(button)
    end)
    return button
end

local function is_pointer_press(input)
    return input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function is_pointer_move(input)
    return input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement
end

local function make_draggable(session, handle, frame)
    local press_point
    local start_position

    handle.InputBegan:Connect(function(input)
        if is_pointer_press(input) then
            press_point = input.Position
            start_position = frame.Position
        end
    end)

    session:connect(uis.InputChanged, function(input)
        if press_point and is_pointer_move(input) then
            local shift = input.Position - press_point
            frame.Position = UDim2.new(
                start_position.X.Scale,
                start_position.X.Offset + shift.X,
                start_position.Y.Scale,
                start_position.Y.Offset + shift.Y
            )
        end
    end)

    session:connect(uis.InputEnded, function(input)
        if is_pointer_press(input) then
            press_point = nil
        end
    end)
end

local function create_gui(features, session, on_close)
    local body = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, body_height),
        Position = UDim2.fromOffset(0, header_height),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.accent,
        ScrollBarImageTransparency = 0.35,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, {
        create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
        create("UIPadding", {
            PaddingTop = UDim.new(0, 8),
            PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 12),
        }),
    })

    for order, feature in ipairs(features) do
        create_toggle_row(feature, order).Parent = body
    end

    local panel
    local collapsed = false

    local separator = create("Frame", {
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.new(0, 12, 0, header_height - 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, {
        create("UIGradient", {
            Color = ColorSequence.new(theme.accent, theme.accent_alt),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.15, 0.6),
                NumberSequenceKeypoint.new(0.85, 0.6),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })

    local logo = create("Frame", {
        Size = UDim2.fromOffset(32, 32),
        Position = UDim2.fromOffset(12, 10),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, {
        rounded(UDim.new(0, 9)),
        accent_gradient(45),
        create("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "F",
            TextColor3 = theme.logo_text,
            TextSize = 18,
            Font = Enum.Font.GothamBold,
        }),
    })

    local title = create("TextLabel", {
        Size = UDim2.new(1, -126, 0, 20),
        Position = UDim2.fromOffset(54, 8),
        BackgroundTransparency = 1,
        Text = "FixLag",
        TextColor3 = theme.text,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
    })

    local subtitle = create("TextLabel", {
        Size = UDim2.new(1, -126, 0, 14),
        Position = UDim2.fromOffset(54, 28),
        BackgroundTransparency = 1,
        RichText = true,
        Text = string.format('by <font color="%s">%s</font>', to_hex(theme.accent), author),
        TextColor3 = theme.text_muted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
    })

    local collapse_button = create_header_button("-", -68, theme.text, theme.button_hover, function(button)
        collapsed = not collapsed
        button.Text = collapsed and "+" or "-"
        if collapsed then
            separator.Visible = false
            tween(panel, collapse_tween, { Size = collapsed_size })
            task.delay(collapse_tween.Time, function()
                if collapsed and body.Parent then
                    body.Visible = false
                end
            end)
        else
            separator.Visible = true
            body.Visible = true
            tween(panel, collapse_tween, { Size = expanded_size })
        end
    end)

    local close_button = create_header_button("x", -36, theme.danger, theme.danger_hover, on_close)

    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, header_height),
        BackgroundTransparency = 1,
        Active = true,
    }, { logo, title, subtitle, collapse_button, close_button })

    local intro_scale = create("UIScale", { Scale = 0.9 })

    panel = create("Frame", {
        Size = expanded_size,
        Position = UDim2.fromOffset(16, 12),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Active = true,
        ClipsDescendants = true,
    }, {
        rounded(panel_corner),
        create("UIGradient", {
            Color = ColorSequence.new(theme.panel_top, theme.panel_bottom),
            Rotation = 90,
        }),
        create("UIStroke", {
            Thickness = 1.2,
            Transparency = 0.5,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Color = Color3.new(1, 1, 1),
        }, { accent_gradient(45) }),
        intro_scale,
        header,
        separator,
        body,
    })

    make_draggable(session, header, panel)

    task.defer(function()
        tween(intro_scale, intro_tween, { Scale = 1 })
    end)

    return create("ScreenGui", {
        Name = "fixlag_panel",
        ResetOnSpawn = false,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, { panel })
end

local function attach_gui(gui)
    local parents = {}
    if gethui then
        parents[#parents + 1] = gethui()
    end
    parents[#parents + 1] = coreGui
    parents[#parents + 1] = local_player:WaitForChild("PlayerGui")

    for _, parent in ipairs(parents) do
        local attached = pcall(function()
            gui.Parent = parent
        end)
        if attached and gui.Parent == parent then
            return
        end
    end
end

local interface_session = api.session_class.new()
local gui

gui = create_gui(api.features, interface_session, function()
    task.spawn(api.shutdown)
end)
attach_gui(gui)

api.destroy_gui = function()
    interface_session:close()
    gui:Destroy()
    api.destroy_gui = nil
end