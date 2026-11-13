local players = game:GetService("Players")
local coreGui = game:GetService("CoreGui")
local tweenService = game:GetService("TweenService")
local textService = game:GetService("TextService")
local uis = game:GetService("UserInputService")

local localPlayer = players.LocalPlayer
while not localPlayer do
    task.wait()
    localPlayer = players.LocalPlayer
end

if not getgenv().fixlag_core then
    warn("[fixlag gui] fixlag core is not loaded")
    return
end

if getgenv().fixlag_core.destroy_gui then
    pcall(getgenv().fixlag_core.destroy_gui)
end

local author = "Techinified"
local theme = {
       panelTop = Color3.fromRGB(30, 33, 45),
    panelBottom = Color3.fromRGB(16, 17, 23),
            row = Color3.fromRGB(33, 36, 49),
       rowHover = Color3.fromRGB(42, 46, 62),
         button = Color3.fromRGB(40, 44, 58),
    buttonHover = Color3.fromRGB(54, 59, 76),
           text = Color3.fromRGB(235, 237, 242),
      textMuted = Color3.fromRGB(140, 147, 163),
         danger = Color3.fromRGB(240, 110, 110),
    dangerHover = Color3.fromRGB(88, 40, 48),
         accent = Color3.fromRGB(64, 196, 120),
      accentAlt = Color3.fromRGB(56, 189, 248),
      switchOff = Color3.fromRGB(70, 76, 92),
       switchOn = Color3.fromRGB(64, 196, 120),
           knob = Color3.fromRGB(255, 255, 255),
     idleStroke = Color3.fromRGB(255, 255, 255),
         dotOff = Color3.fromRGB(88, 95, 112),
       logoText = Color3.fromRGB(14, 16, 22),
}

local panelWidth = 284
local headerHeight = 52
local bodyHeight = 240
local rowHeight = 40
local expandedSize = UDim2.fromOffset(panelWidth, headerHeight + bodyHeight)
local collapsedSize = UDim2.fromOffset(panelWidth, headerHeight)
local panelCorner = UDim.new(0, 12)
local corner = UDim.new(0, 9)
local pill = UDim.new(1, 0)

local confirmText = "Are you sure you wanna delete the script?"
local confirmHint = "click x again to confirm"
local confirmTimeout = 3
local toastShown = UDim2.new(0.5, 0, 1, -24)
local toastHidden = UDim2.new(0.5, 0, 1, 80)

local switchTween = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local hoverTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local collapseTween = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local introTween = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function create(className, properties, children)
    local instance = Instance.new(className)
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

local function accentGradient(rotation)
    return create("UIGradient", {
        Color = ColorSequence.new(theme.accent, theme.accentAlt),
        Rotation = rotation,
    })
end

local function toHex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function rowAppearance(enabled)
    if enabled then
        return {
            track = theme.switchOn,
            knob = UDim2.fromOffset(21, 3),
            strokeColor = theme.accent,
            strokeTransparency = 0.55,
            label = theme.text,
            dot = theme.accent,
        }
    end
    return {
        track = theme.switchOff,
        knob = UDim2.fromOffset(3, 3),
        strokeColor = theme.idleStroke,
        strokeTransparency = 0.82,
        label = theme.textMuted,
        dot = theme.dotOff,
    }
end

local function createToggleRow(feature, order)
    local look = rowAppearance(feature.enabled)

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
        Color = look.strokeColor,
        Transparency = look.strokeTransparency,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })

    local row = create("TextButton", {
        Size = UDim2.new(1, 0, 0, rowHeight),
        BackgroundColor3 = theme.row,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = order,
    }, { rounded(corner), stroke, dot, label, track })

    row.MouseEnter:Connect(function()
        tween(row, hoverTween, { BackgroundColor3 = theme.rowHover })
    end)
    row.MouseLeave:Connect(function()
        tween(row, hoverTween, { BackgroundColor3 = theme.row })
    end)

    row.Activated:Connect(function()
        local enabled = not feature.enabled
        local nextLook = rowAppearance(enabled)
        tween(track, switchTween, { BackgroundColor3 = nextLook.track })
        tween(knob, switchTween, { Position = nextLook.knob })
        tween(stroke, switchTween, {
            Color = nextLook.strokeColor,
            Transparency = nextLook.strokeTransparency,
        })
        tween(label, switchTween, { TextColor3 = nextLook.label })
        tween(dot, switchTween, { BackgroundColor3 = nextLook.dot })
        feature:set_enabled(enabled)
    end)

    return row
end

local function createHeaderButton(text, offsetFromRight, textColor, hoverColor, onActivated)
    local button = create("TextButton", {
        Size = UDim2.fromOffset(28, 28),
        Position = UDim2.new(1, offsetFromRight, 0.5, -14),
        BackgroundColor3 = theme.button,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = text,
        TextColor3 = textColor,
        TextSize = 15,
        Font = Enum.Font.GothamBold,
    }, { rounded(UDim.new(0, 8)) })

    button.MouseEnter:Connect(function()
        if button:GetAttribute("locked") then
            return
        end
        tween(button, hoverTween, { BackgroundColor3 = hoverColor })
    end)
    button.MouseLeave:Connect(function()
        if button:GetAttribute("locked") then
            return
        end
        tween(button, hoverTween, { BackgroundColor3 = theme.button })
    end)
    button.Activated:Connect(function()
        onActivated(button)
    end)
    return button
end

local function isPointerPress(input)
    return input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function isPointerMove(input)
    return input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement
end

local function makeDraggable(session, handle, frame)
    local pressPoint
    local startPosition

    handle.InputBegan:Connect(function(input)
        if isPointerPress(input) then
            pressPoint = input.Position
            startPosition = frame.Position
        end
    end)

    session:connect(uis.InputChanged, function(input)
        if pressPoint and isPointerMove(input) then
            local shift = input.Position - pressPoint
            frame.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + shift.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + shift.Y
            )
        end
    end)

    session:connect(uis.InputEnded, function(input)
        if isPointerPress(input) then
            pressPoint = nil
        end
    end)
end

local function createGui(features, session, onClose)
    local body = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, bodyHeight),
        Position = UDim2.fromOffset(0, headerHeight),
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
        createToggleRow(feature, order).Parent = body
    end

    local panel
    local collapsed = false

    local separator = create("Frame", {
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.new(0, 12, 0, headerHeight - 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, {
        create("UIGradient", {
            Color = ColorSequence.new(theme.accent, theme.accentAlt),
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
        accentGradient(45),
        create("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "F",
            TextColor3 = theme.logoText,
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
        Text = string.format('by <font color="%s">%s</font>', toHex(theme.accent), author),
        TextColor3 = theme.textMuted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
    })

    local collapseButton = createHeaderButton("-", -68, theme.text, theme.buttonHover, function(button)
        collapsed = not collapsed
        button.Text = collapsed and "+" or "-"
        if collapsed then
            separator.Visible = false
            tween(panel, collapseTween, { Size = collapsedSize })
            task.delay(collapseTween.Time, function()
                if collapsed and body.Parent then
                    body.Visible = false
                end
            end)
        else
            separator.Visible = true
            body.Visible = true
            tween(panel, collapseTween, { Size = expandedSize })
        end
    end)

    local toastWidth = textService:GetTextSize(
        confirmText,
        13,
        Enum.Font.GothamMedium,
        Vector2.new(1000, 16)
    ).X + 28

    local toast = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = toastHidden,
        Size = UDim2.fromOffset(toastWidth, 46),
        BackgroundColor3 = theme.panelBottom,
        BorderSizePixel = 0,
        ZIndex = 10,
    }, {
        rounded(UDim.new(0, 10)),
        create("UIStroke", {
            Color = theme.danger,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }),
        create("TextLabel", {
            Size = UDim2.new(1, -28, 0, 16),
            Position = UDim2.fromOffset(14, 7),
            BackgroundTransparency = 1,
            Text = confirmText,
            TextColor3 = theme.text,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamMedium,
        }),
        create("TextLabel", {
            Size = UDim2.new(1, -28, 0, 14),
            Position = UDim2.fromOffset(14, 25),
            BackgroundTransparency = 1,
            Text = confirmHint,
            TextColor3 = theme.textMuted,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamMedium,
        }),
    })

    local confirming = false
    local confirmToken = 0

    local function setConfirming(button, state)
        confirming = state
        button:SetAttribute("locked", state)
        tween(button, switchTween, {
            BackgroundColor3 = state and theme.danger or theme.button,
            TextColor3 = state and theme.knob or theme.danger,
        })
        tween(toast, collapseTween, {
            Position = state and toastShown or toastHidden,
        })
    end

    local closeButton = createHeaderButton("x", -36, theme.danger, theme.dangerHover, function(button)
        confirmToken = confirmToken + 1

        if confirming then
            pcall(onClose)
            return
        end

        setConfirming(button, true)

        local token = confirmToken
        task.delay(confirmTimeout, function()
            if token == confirmToken and confirming and button.Parent then
                setConfirming(button, false)
            end
        end)
    end)

    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, headerHeight),
        BackgroundTransparency = 1,
        Active = true,
    }, { logo, title, subtitle, collapseButton, closeButton })

    local introScale = create("UIScale", { Scale = 0.9 })

    panel = create("Frame", {
        Size = expandedSize,
        Position = UDim2.fromOffset(16, 12),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Active = true,
        ClipsDescendants = true,
    }, {
        rounded(panelCorner),
        create("UIGradient", {
            Color = ColorSequence.new(theme.panelTop, theme.panelBottom),
            Rotation = 90,
        }),
        create("UIStroke", {
            Thickness = 1.2,
            Transparency = 0.5,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Color = Color3.new(1, 1, 1),
        }, { accentGradient(45) }),
        introScale,
        header,
        separator,
        body,
    })

    makeDraggable(session, header, panel)

    task.defer(function()
        tween(introScale, introTween, { Scale = 1 })
    end)

    return create("ScreenGui", {
        Name = "fixlag_panel",
        ResetOnSpawn = false,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, { panel, toast })
end

local function attachGui(gui)
    local parents = {}
    if gethui then
        parents[#parents + 1] = gethui()
    end
    parents[#parents + 1] = coreGui
    parents[#parents + 1] = localPlayer:WaitForChild("PlayerGui")

    for _, parent in ipairs(parents) do
        local attached = pcall(function()
            gui.Parent = parent
        end)
        if attached and gui.Parent == parent then
            return
        end
    end
end

local interfaceSession = getgenv().fixlag_core.session_class.new()
local gui

gui = createGui(getgenv().fixlag_core.features, interfaceSession, function()
    task.spawn(getgenv().fixlag_core.shutdown)
end)
attachGui(gui)

getgenv().fixlag_core.destroy_gui = function()
    interfaceSession:close()
    gui:Destroy()
    getgenv().fixlag_core.destroy_gui = nil
end