local lighting = game:GetService("Lighting")
local workspace = game:GetService("Workspace")
local terrain = workspace.Terrain
local base_part_by_class = {}
local original_values = setmetatable({}, { __mode = "k" })
local claims_by_owner = {}

local vm = {}
local vm_labels = {
    "Destroy VFX",
    "Destroy Terrain & Water",
    "Destroy Debris",
    "Destroy Decorations",
    "Gray Sky",
    "Custom Atmosphere",
    "FPS UnCap",
    "FPS & Ping Display",
}

local function get_property(instance, property)
    return instance[property]
end

local function set_property(instance, property, value)
    instance[property] = value
end

local function values_match(current, target)
    local kind = typeof(current)
    if kind ~= typeof(target) then
        return false
    end

    if kind == "number" then
        return math.abs(current - target) <= math.max(1e-4, math.abs(target) * 1e-6)
    end

    if kind == "NumberRange" then
        return values_match(current.Min, target.Min) and values_match(current.Max, target.Max)
    end

    if kind == "NumberSequence" or kind == "ColorSequence" then
        local current_points = current.Keypoints
        local target_points = target.Keypoints
        if #current_points ~= #target_points then
            return false
        end
        for index = 1, #current_points do
            local a = current_points[index]
            local b = target_points[index]
            if not values_match(a.Time, b.Time) or not values_match(a.Value, b.Value) then
                return false
            end
            if kind == "NumberSequence" and not values_match(a.Envelope, b.Envelope) then
                return false
            end
        end
        return true
    end

    return current == target
end

local function create_throttle()
    local budget = 0.002
    local deadline = os.clock() + budget
    return function()
        if os.clock() >= deadline then
            task.wait()
            deadline = os.clock() + budget
        end
    end
end

local function is_part(instance)
    if instance == terrain then
        return false
    end

    local class_name = instance.ClassName
    local result = base_part_by_class[class_name]
    if result == nil then
        result = instance:IsA("BasePart")
        base_part_by_class[class_name] = result
    end
    return result
end

local function merge_properties(existing, added)
    if existing == nil or existing == added then
        return added
    end

    local merged = {}
    for property, value in pairs(existing) do
        merged[property] = value
    end
    for property, value in pairs(added) do
        merged[property] = value
    end
    return merged
end

local function find_remaining_claim(instance, property)
    for _, claims in pairs(claims_by_owner) do
        local properties = claims[instance]
        if properties and properties[property] ~= nil then
            return properties[property]
        end
    end
    return nil
end

local function split_path(path)
    local segments = {}
    for segment in string.gmatch(tostring(path), "[^%.]+") do
        segments[#segments + 1] = segment
    end
    return segments
end

local function warn_tagged(message)
    warn("[fixlag] " .. message)
end

local override_store = {}

function override_store.claim(owner, instance, properties)
    local claims = claims_by_owner[owner]
    if not claims then
        claims = setmetatable({}, { __mode = "k" })
        claims_by_owner[owner] = claims
    end
    claims[instance] = merge_properties(claims[instance], properties)

    for property, value in pairs(properties) do
        local readable, current = pcall(get_property, instance, property)
        if readable then
            local saved = original_values[instance]
            if not saved then
                saved = {}
                original_values[instance] = saved
            end
            if saved[property] == nil then
                saved[property] = current
            end
            pcall(set_property, instance, property, value)
        end
    end
end

function override_store.release(owner)
    local claims = claims_by_owner[owner]
    claims_by_owner[owner] = nil
    if not claims then
        return
    end

    local throttle = create_throttle()
    for instance, properties in pairs(claims) do
        local saved = original_values[instance]
        for property in pairs(properties) do
            local remaining_value = find_remaining_claim(instance, property)
            if remaining_value ~= nil then
                pcall(set_property, instance, property, remaining_value)
            elseif saved and saved[property] ~= nil then
                pcall(set_property, instance, property, saved[property])
                saved[property] = nil
            end
        end
        throttle()
    end
end

local session_class = {}
session_class.__index = session_class

function session_class.new()
    return setmetatable({
        active = true,
        connections = {},
        close_callbacks = {},
        locked_targets = setmetatable({}, { __mode = "k" }),
    }, session_class)
end

function session_class:connect(signal, handler)
    if self.active then
        self.connections[#self.connections + 1] = signal:Connect(handler)
    end
end

function session_class:on_close(callback)
    if self.active then
        self.close_callbacks[#self.close_callbacks + 1] = callback
    else
        callback()
    end
end

function session_class:override(instance, properties)
    if self.active then
        override_store.claim(self, instance, properties)
    end
end

local function watch_property(session, instance, property, targets)
    local ok, signal = pcall(instance.GetPropertyChangedSignal, instance, property)
    if not ok then
        return
    end

    local reapply_pending = false
    session:connect(signal, function()
        if reapply_pending or values_match(instance[property], targets[property]) then
            return
        end

        reapply_pending = true
        task.defer(function()
            reapply_pending = false
            if session.active then
                pcall(set_property, instance, property, targets[property])
            end
        end)
    end)
end

function session_class:lock(instance, properties)
    if not self.active then
        return
    end

    override_store.claim(self, instance, properties)

    local targets = self.locked_targets[instance]
    if not targets then
        targets = {}
        self.locked_targets[instance] = targets
    end

    for property, value in pairs(properties) do
        local already_watched = targets[property] ~= nil
        targets[property] = value
        if not already_watched then
            watch_property(self, instance, property, targets)
        end
    end
end

function session_class:close()
    if not self.active then
        return
    end
    self.active = false

    for _, connection in ipairs(self.connections) do
        connection:Disconnect()
    end
    for _, callback in ipairs(self.close_callbacks) do
        pcall(callback)
    end

    override_store.release(self)
end

local feature_class = {}
feature_class.__index = feature_class

function feature_class.new(definition)
    return setmetatable({
        label = definition.label,
        start = definition.start,
        enabled = false,
    }, feature_class)
end

function feature_class:enable(delay)
    if self.enabled then
        return
    end
    self.enabled = true

    local session = session_class.new()
    self.session = session

    task.spawn(function()
        if delay and delay > 0 then
            task.wait(delay)
        end
        if not session.active then
            return
        end

        local ok, err = pcall(self.start, session)
        if not ok then
            warn_tagged(string.format("%s failed: %s", self.label, tostring(err)))
        end
    end)
end

function feature_class:disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    self.session:close()
end

function feature_class:set_enabled(enabled, delay)
    if enabled then
        self:enable(delay)
    else
        self:disable()
    end
end

local function for_each_descendant(session, root, handler)
    local throttle = create_throttle()
    local stack = { root }

    while #stack > 0 do
        local node = table.remove(stack)
        for _, child in ipairs(node:GetChildren()) do
            if not session.active then
                return
            end
            handler(child)
            stack[#stack + 1] = child
            throttle()
        end
    end
end

local vfx_overrides = {
    ParticleEmitter = {
        Enabled = false,
        Rate = 0,
        Lifetime = NumberRange.new(0, 0),
        Size = NumberSequence.new(0),
        Transparency = NumberSequence.new(1),
    },
    Smoke = { Enabled = false, Opacity = 0 },
    Trail = { Enabled = false, Transparency = NumberSequence.new(1) },
    Beam = { Enabled = false, Transparency = NumberSequence.new(1), Width0 = 0, Width1 = 0 },
    Explosion = { Visible = false },
    ForceField = { Visible = false },
    Fire = { Enabled = false },
    Sparkles = { Enabled = false },
    PointLight = { Enabled = false },
    SpotLight = { Enabled = false },
    SurfaceLight = { Enabled = false },
    BloomEffect = { Enabled = false },
    BlurEffect = { Enabled = false },
    ColorCorrectionEffect = { Enabled = false },
    DepthOfFieldEffect = { Enabled = false },
    SunRaysEffect = { Enabled = false },
}

local function suppress_effect(session, instance, should_lock, overrides)
    local class_overrides = (overrides or vfx_overrides)[instance.ClassName]
    if not class_overrides then
        return false
    end

    if should_lock then
        session:lock(instance, class_overrides)
    else
        session:override(instance, class_overrides)
    end

    if instance.ClassName == "ParticleEmitter" then
        pcall(instance.Clear, instance)
    end
    return true
end

local function suppress_under(session, root, overrides, should_lock)
    local function suppress(instance)
        suppress_effect(session, instance, should_lock, overrides)
    end

    session:connect(root.DescendantAdded, suppress)
    for _, descendant in ipairs(root:GetDescendants()) do
        suppress(descendant)
    end
end

local decoration_classes = {
    Decal = { Transparency = 1 },
    Texture = { Transparency = 1 },
    SpecialMesh = { Scale = Vector3.new(0, 0, 0) },
    SurfaceGui = { Enabled = false },
    BillboardGui = { Enabled = false },
}

local function create_hider(part_properties)
    return function(session, instance)
        if suppress_effect(session, instance, false) then
            return
        end

        if is_part(instance) then
            session:override(instance, part_properties)
            return
        end

        local decoration = decoration_classes[instance.ClassName]
        if decoration then
            session:override(instance, decoration)
        end
    end
end

local matte_part = { Reflectance = 0, CastShadow = false }

local actions = {
    hide = create_hider({
        CastShadow = false,
        CanCollide = false,
        CanTouch = false,
        CanQuery = false,
        Transparency = 1,
        LocalTransparencyModifier = 1,
    }),
    visual = create_hider({
        CastShadow = false,
        Transparency = 1,
        LocalTransparencyModifier = 1,
    }),
    ghost = create_hider({
        CastShadow = false,
        CanCollide = false,
        Transparency = 1,
        LocalTransparencyModifier = 1,
    }),
    effects = function(session, instance)
        suppress_effect(session, instance, false)
    end,
    matte = function(session, instance)
        if is_part(instance) then
            session:override(instance, matte_part)
        end
    end,
    destroy = function(_, instance)
        instance:Destroy()
    end,
}

local function watch_path(session, segments, on_found)
    local function descend(parent, index)
        local name = segments[index]
        local is_last = index == #segments

        local function consider(child)
            if name ~= "*" and child.Name ~= name then
                return
            end

            if is_last then
                task.defer(on_found, child)
            else
                descend(child, index + 1)
            end
        end

        session:connect(parent.ChildAdded, consider)
        for _, child in ipairs(parent:GetChildren()) do
            consider(child)
        end
    end

    descend(workspace, 1)
end

local function run_rule(session, rule)
    local mode = rule.mode or "hide"
    local action = actions[mode]
    if not action then
        warn_tagged("unknown mode '" .. tostring(mode) .. "' for path " .. tostring(rule.path))
        return
    end

    local segments = split_path(rule.path)
    if #segments == 0 then
        warn_tagged("empty path in rules")
        return
    end

    local handled_targets = setmetatable({}, { __mode = "k" })

    local function apply_to(instance)
        if session.active then
            pcall(action, session, instance)
        end
    end

    local function apply_to_subtree(root)
        apply_to(root)
        for_each_descendant(session, root, apply_to)
    end

    local function apply_to_children(target)
        session:connect(target.ChildAdded, function(child)
            task.defer(apply_to, child)
        end)
        for _, child in ipairs(target:GetChildren()) do
            apply_to(child)
        end
    end

    local function apply_to_subtrees(target)
        session:connect(target.DescendantAdded, apply_to)
        if rule.children then
            for _, child in ipairs(target:GetChildren()) do
                apply_to_subtree(child)
            end
        else
            apply_to_subtree(target)
        end
    end

    local function on_target(target)
        if handled_targets[target] then
            return
        end
        handled_targets[target] = true

        if mode ~= "destroy" then
            apply_to_subtrees(target)
        elseif rule.children then
            apply_to_children(target)
        else
            apply_to(target)
        end
    end

    watch_path(session, segments, on_target)
end

local function create_rule_starter(rules)
    return function(session)
        for _, rule in ipairs(rules) do
            local ok, err = pcall(run_rule, session, rule)
            if not ok then
                warn_tagged("rule failed (" .. tostring(rule.path) .. "): " .. tostring(err))
            end
        end
    end
end

local function get_quality_level()
    return settings().Rendering.QualityLevel
end

local function set_quality_level(level)
    settings().Rendering.QualityLevel = level
end

vm[1] = function(session)
    local function suppress(instance)
        suppress_effect(session, instance, false)
    end

    session:connect(workspace.DescendantAdded, suppress)
    for_each_descendant(session, workspace, suppress)
    suppress_under(session, lighting, vfx_overrides, true)
end

vm[2] = function(session)
    session:override(terrain, {
        Decoration = false,
        WaterWaveSize = 0,
        WaterWaveSpeed = 0,
        WaterReflectance = 0,
        WaterTransparency = 0,
    })

    if type(sethiddenproperty) ~= "function" then
        return
    end

    local previous_decoration
    if type(gethiddenproperty) == "function" then
        local read_ok, value = pcall(gethiddenproperty, terrain, "Decoration")
        if read_ok and type(value) == "boolean" then
            previous_decoration = value
        end
    end

    local applied = pcall(sethiddenproperty, terrain, "Decoration", false)
    if applied and previous_decoration ~= nil then
        session:on_close(function()
            pcall(sethiddenproperty, terrain, "Decoration", previous_decoration)
        end)
    end
end

vm[3] = create_rule_starter({
    { path = "Thrown", mode = "visual", children = true },
})

vm[4] = create_rule_starter({
    { path = "Map.Trees", mode = "ghost" },
})

local sky_overrides = {
    Clouds = { Enabled = false },
    Sky = {
        SkyboxBk = "rbxassetid://92959017845968",
        SkyboxFt = "rbxassetid://129304841254693",
        SkyboxLf = "rbxassetid://129249062260004",
        SkyboxRt = "rbxassetid://117319232583147",
        SkyboxUp = "rbxassetid://121193772599100",
        SkyboxDn = "rbxassetid://115022734343595",
        SunAngularSize = 0,
        SunTextureId = "",
        MoonAngularSize = 0,
        MoonTextureId = "",
    },
}

vm[5] = function(session)
    suppress_under(session, lighting, sky_overrides, true)
    suppress_under(session, terrain, sky_overrides, false)

    if not lighting:FindFirstChildOfClass("Sky") then
        local sky = Instance.new("Sky")
        sky.Name = "custom_sky"
        sky.Parent = lighting
        session:on_close(function()
            sky:Destroy()
        end)
    end
end

vm[6] = function(session)
    session:lock(lighting, {
        ClockTime = 12,
        GlobalShadows = false,
        Brightness = 0.8,
        OutdoorAmbient = Color3.fromRGB(120, 120, 120),
        Ambient = Color3.fromRGB(120, 120, 120),
        ExposureCompensation = -0.2,
        FogStart = 9e9,
        FogEnd = 9e9,
        ColorShift_Top = Color3.new(0, 0, 0),
        ColorShift_Bottom = Color3.new(0, 0, 0),
    })
    suppress_under(session, lighting, { Atmosphere = { Density = 0, Haze = 0, Glare = 0 } }, true)
end

vm[7] = function(session)
    local fps_cap_setter = setfpscap or set_fps_cap
    local fps_cap_getter = getfpscap or get_fps_cap

    if type(fps_cap_setter) == "function" then
        local previous_cap = 60
        if type(fps_cap_getter) == "function" then
            local read_ok, value = pcall(fps_cap_getter)
            if read_ok and type(value) == "number" then
                previous_cap = value
            end
        end

        pcall(fps_cap_setter, 9999)
        session:on_close(function()
            pcall(fps_cap_setter, previous_cap)
        end)
    end

    local has_quality_level, previous_level = pcall(get_quality_level)
    if has_quality_level then
        pcall(set_quality_level, Enum.QualityLevel.Level01)
        session:on_close(function()
            pcall(set_quality_level, previous_level)
        end)
    end
end

local players = game:GetService("Players")
local run_service = game:GetService("RunService")
local user_input_service = game:GetService("UserInputService")
local tween_service = game:GetService("TweenService")

vm[8] = function(session)
    local player = players.LocalPlayer
    local player_gui = player:WaitForChild("PlayerGui")
    if not session.active then
        return
    end

    local color_good = Color3.fromRGB(80, 255, 140)
    local color_mid = Color3.fromRGB(255, 205, 70)
    local color_bad = Color3.fromRGB(255, 85, 100)
    local color_muted = Color3.fromRGB(140, 145, 165)

    local screen_gui = Instance.new("ScreenGui")
    screen_gui.Name = "fps_ping_counter"
    screen_gui.ResetOnSpawn = false
    screen_gui.Parent = player_gui
    session:on_close(function()
        screen_gui:Destroy()
    end)

    local main_frame = Instance.new("Frame")
    main_frame.Name = "main_frame"
    main_frame.Size = UDim2.new(0, 108, 0, 32)
    main_frame.Position = UDim2.new(0.8, 0, 0, 50)
    main_frame.BackgroundColor3 = Color3.fromRGB(20, 21, 30)
    main_frame.BackgroundTransparency = 0.12
    main_frame.BorderSizePixel = 0
    main_frame.Active = true
    main_frame.ClipsDescendants = true
    main_frame.Parent = screen_gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = main_frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(70, 74, 100)
    stroke.Thickness = 1
    stroke.Transparency = 0.35
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = main_frame

    local background = Instance.new("UIGradient")
    background.Rotation = 90
    background.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 32, 46)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 15, 22)),
    })
    background.Parent = main_frame

    local scale = Instance.new("UIScale")
    scale.Scale = 0.8
    scale.Parent = main_frame

    local accent = Instance.new("Frame")
    accent.Name = "accent"
    accent.Size = UDim2.new(1, 0, 0, 2)
    accent.BackgroundColor3 = Color3.new(1, 1, 1)
    accent.BorderSizePixel = 0
    accent.Parent = main_frame

    local accent_gradient = Instance.new("UIGradient")
    accent_gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 200, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 90, 255)),
    })
    accent_gradient.Parent = accent

    local function create_label(name, text, font, text_size, position, size)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = size
        label.Position = position
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = color_muted
        label.Font = font
        label.TextSize = text_size
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = main_frame
        return label
    end

    local function create_dot(name, position)
        local dot = Instance.new("Frame")
        dot.Name = name
        dot.Size = UDim2.new(0, 5, 0, 5)
        dot.Position = position
        dot.BackgroundColor3 = color_good
        dot.BorderSizePixel = 0
        dot.Parent = main_frame

        local dot_corner = Instance.new("UICorner")
        dot_corner.CornerRadius = UDim.new(1, 0)
        dot_corner.Parent = dot
        return dot
    end

    local fps_dot = create_dot("fps_dot", UDim2.new(0, 9, 0, 8))
    create_label("fps_title", "FPS", Enum.Font.GothamBold, 10, UDim2.new(0, 18, 0, 4), UDim2.new(0, 28, 0, 12))
    local fps_label = create_label("fps_value", "0", Enum.Font.Code, 13, UDim2.new(0, 9, 0, 14), UDim2.new(0, 36, 0, 16))

    local divider = Instance.new("Frame")
    divider.Name = "divider"
    divider.Size = UDim2.new(0, 1, 0, 18)
    divider.Position = UDim2.new(0, 47, 0, 8)
    divider.BackgroundColor3 = Color3.fromRGB(70, 74, 100)
    divider.BackgroundTransparency = 0.4
    divider.BorderSizePixel = 0
    divider.Parent = main_frame

    local ping_dot = create_dot("ping_dot", UDim2.new(0, 54, 0, 8))
    create_label("ping_title", "PING", Enum.Font.GothamBold, 10, UDim2.new(0, 63, 0, 4), UDim2.new(0, 38, 0, 12))
    local ping_label = create_label("ping_value", "0 ms", Enum.Font.Code, 13, UDim2.new(0, 54, 0, 14), UDim2.new(0, 50, 0, 16))

    tween_service:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

    local dragging = false
    local drag_input
    local drag_start
    local start_position

    session:connect(main_frame.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            drag_start = input.Position
            start_position = main_frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    session:connect(main_frame.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            drag_input = input
        end
    end)

    session:connect(user_input_service.InputChanged, function(input)
        if input == drag_input and dragging then
            local delta = input.Position - drag_start
            main_frame.Position = UDim2.new(
                start_position.X.Scale,
                start_position.X.Offset + delta.X,
                start_position.Y.Scale,
                start_position.Y.Offset + delta.Y
            )
        end
    end)

    local color_tween = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local current_fps_color
    local current_ping_color

    local function apply_color(label, dot, color)
        tween_service:Create(label, color_tween, { TextColor3 = color }):Play()
        tween_service:Create(dot, color_tween, { BackgroundColor3 = color }):Play()
    end

    local displayed_fps
    local displayed_ping
    local shown_fps
    local shown_ping

    session:connect(run_service.RenderStepped, function(dt)
        if dt <= 0 then
            return
        end

        local fps = 1 / dt
        local ping = player:GetNetworkPing() * 1000
        displayed_fps = displayed_fps or fps
        displayed_ping = displayed_ping or ping

        local alpha = 1 - math.exp(-6 * dt)
        displayed_fps = displayed_fps + (fps - displayed_fps) * alpha
        displayed_ping = displayed_ping + (ping - displayed_ping) * alpha

        local fps_value = math.floor(displayed_fps)
        if fps_value ~= shown_fps then
            shown_fps = fps_value
            fps_label.Text = string.format("%d", fps_value)
        end

        local ping_value = math.floor(displayed_ping)
        if ping_value ~= shown_ping then
            shown_ping = ping_value
            ping_label.Text = string.format("%d ms", ping_value)
        end

        local fps_color
        if displayed_fps <= 25 then
            fps_color = color_bad
        elseif displayed_fps <= 40 then
            fps_color = color_mid
        else
            fps_color = color_good
        end

        local ping_color
        if displayed_ping <= 150 then
            ping_color = color_good
        elseif displayed_ping <= 250 then
            ping_color = color_mid
        else
            ping_color = color_bad
        end

        if fps_color ~= current_fps_color then
            current_fps_color = fps_color
            apply_color(fps_label, fps_dot, fps_color)
        end

        if ping_color ~= current_ping_color then
            current_ping_color = ping_color
            apply_color(ping_label, ping_dot, ping_color)
        end
    end)
end

local function load_gui()
    local url = "https://raw.githubusercontent.com/Muza-Cloud/tsb/main/FixLagGui.lua"

    local ok, err = pcall(function()
        loadstring(game:HttpGet(url))()
    end)
    if not ok then
        warn_tagged("gui failed: " .. tostring(err))
    end
end

local function build_order(count)
    local order = {}
    for index = 1, count do
        order[index] = index
    end

    for index = count, 2, -1 do
        local swap = math.random(index)
        order[index], order[swap] = order[swap], order[index]
    end
    return order
end

local function run_vm(features)
    local order = build_order(#features)
    for position, index in ipairs(order) do
        local feature = features[index]
        local delay = (position - 1) * 0.3
        local ok, err = pcall(feature.enable, feature, delay)
        if not ok then
            warn_tagged(string.format("%s start failed: %s", feature.label, tostring(err)))
        end
    end
end

if getgenv().fixlag_shutdown then
    pcall(getgenv().fixlag_shutdown)
end

local features = {}
for index = 1, #vm do
    features[index] = feature_class.new({ label = vm_labels[index], start = vm[index] })
end

local api = {
    features = features,
    session_class = session_class,
    vm = vm,
}

local function shutdown()
    if api.destroy_gui then
        pcall(api.destroy_gui)
    end
    for _, feature in ipairs(features) do
        feature:disable()
    end
    getgenv().fixlag_core = nil
    getgenv().fixlag_shutdown = nil
end

api.shutdown = shutdown
getgenv().fixlag_core = api
getgenv().fixlag_shutdown = shutdown

run_vm(features)
load_gui()