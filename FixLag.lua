local lighting = game:GetService("Lighting")
local workspace = game:GetService("Workspace")
local terrain = workspace.Terrain
local basePartByClass = {}
local originalValues = setmetatable({}, { __mode = "k" })
local claimsByOwner = {}

local vm = {}
local vmLabels = {
    "Destroy VFX",
    "Destroy Terrain & Water",
    "Destroy Debris",
    "Destroy Decorations",
    "Gray Sky",
    "Custom Atmosphere",
    "FPS UnCap",
    "FPS & Ping Display",
}

local function getProperty(instance, property)
    return instance[property]
end

local function setProperty(instance, property, value)
    instance[property] = value
end

local function valuesMatch(current, target)
    local kind = typeof(current)
    if kind ~= typeof(target) then
        return false
    end

    if kind == "number" then
        return math.abs(current - target) <= math.max(1e-4, math.abs(target) * 1e-6)
    end

    if kind == "NumberRange" then
        return valuesMatch(current.Min, target.Min) and valuesMatch(current.Max, target.Max)
    end

    if kind == "NumberSequence" or kind == "ColorSequence" then
        local currentPoints = current.Keypoints
        local targetPoints = target.Keypoints
        if #currentPoints ~= #targetPoints then
            return false
        end
        for index = 1, #currentPoints do
            local a = currentPoints[index]
            local b = targetPoints[index]
            if not valuesMatch(a.Time, b.Time) or not valuesMatch(a.Value, b.Value) then
                return false
            end
            if kind == "NumberSequence" and not valuesMatch(a.Envelope, b.Envelope) then
                return false
            end
        end
        return true
    end

    return current == target
end

local function createThrottle()
    local budget = 0.002
    local deadline = os.clock() + budget
    return function()
        if os.clock() >= deadline then
            task.wait()
            deadline = os.clock() + budget
        end
    end
end

local function isPart(instance)
    if instance == terrain then
        return false
    end

    local className = instance.ClassName
    local result = basePartByClass[className]
    if result == nil then
        result = instance:IsA("BasePart")
        basePartByClass[className] = result
    end
    return result
end

local function mergeProperties(existing, added)
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

local function findRemainingClaim(instance, property)
    for _, claims in pairs(claimsByOwner) do
        local properties = claims[instance]
        if properties and properties[property] ~= nil then
            return properties[property]
        end
    end
    return nil
end

local function splitPath(path)
    local segments = {}
    for segment in string.gmatch(tostring(path), "[^%.]+") do
        segments[#segments + 1] = segment
    end
    return segments
end

local function warnTagged(message)
    warn("[fixlag] " .. message)
end

local overrideStore = {}

function overrideStore.claim(owner, instance, properties)
    local claims = claimsByOwner[owner]
    if not claims then
        claims = setmetatable({}, { __mode = "k" })
        claimsByOwner[owner] = claims
    end
    claims[instance] = mergeProperties(claims[instance], properties)

    for property, value in pairs(properties) do
        local readable, current = pcall(getProperty, instance, property)
        if readable then
            local saved = originalValues[instance]
            if not saved then
                saved = {}
                originalValues[instance] = saved
            end
            if saved[property] == nil then
                saved[property] = current
            end
            pcall(setProperty, instance, property, value)
        end
    end
end

function overrideStore.release(owner)
    local claims = claimsByOwner[owner]
    claimsByOwner[owner] = nil
    if not claims then
        return
    end

    local throttle = createThrottle()
    for instance, properties in pairs(claims) do
        local saved = originalValues[instance]
        for property in pairs(properties) do
            local remainingValue = findRemainingClaim(instance, property)
            if remainingValue ~= nil then
                pcall(setProperty, instance, property, remainingValue)
            elseif saved and saved[property] ~= nil then
                pcall(setProperty, instance, property, saved[property])
                saved[property] = nil
            end
        end
        throttle()
    end
end

local sessionClass = {}
sessionClass.__index = sessionClass

function sessionClass.new()
    return setmetatable({
        active = true,
        connections = {},
        closeCallbacks = {},
        lockedTargets = setmetatable({}, { __mode = "k" }),
    }, sessionClass)
end

function sessionClass:connect(signal, handler)
    if self.active then
        self.connections[#self.connections + 1] = signal:Connect(handler)
    end
end

function sessionClass:onClose(callback)
    if self.active then
        self.closeCallbacks[#self.closeCallbacks + 1] = callback
    else
        callback()
    end
end

function sessionClass:override(instance, properties)
    if self.active then
        overrideStore.claim(self, instance, properties)
    end
end

local function watchProperty(session, instance, property, targets)
    local ok, signal = pcall(instance.GetPropertyChangedSignal, instance, property)
    if not ok then
        return
    end

    local reapplyPending = false
    session:connect(signal, function()
        if reapplyPending or valuesMatch(instance[property], targets[property]) then
            return
        end

        reapplyPending = true
        task.defer(function()
            reapplyPending = false
            if session.active then
                pcall(setProperty, instance, property, targets[property])
            end
        end)
    end)
end

function sessionClass:lock(instance, properties)
    if not self.active then
        return
    end

    overrideStore.claim(self, instance, properties)

    local targets = self.lockedTargets[instance]
    if not targets then
        targets = {}
        self.lockedTargets[instance] = targets
    end

    for property, value in pairs(properties) do
        local alreadyWatched = targets[property] ~= nil
        targets[property] = value
        if not alreadyWatched then
            watchProperty(self, instance, property, targets)
        end
    end
end

function sessionClass:close()
    if not self.active then
        return
    end
    self.active = false

    for _, connection in ipairs(self.connections) do
        connection:Disconnect()
    end
    for _, callback in ipairs(self.closeCallbacks) do
        pcall(callback)
    end

    overrideStore.release(self)
end

local featureClass = {}
featureClass.__index = featureClass

function featureClass.new(definition)
    return setmetatable({
        label = definition.label,
        start = definition.start,
        enabled = false,
    }, featureClass)
end

function featureClass:enable(delay)
    if self.enabled then
        return
    end
    self.enabled = true

    local session = sessionClass.new()
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
            warnTagged(string.format("%s failed: %s", self.label, tostring(err)))
        end
    end)
end

function featureClass:disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    self.session:close()
end

function featureClass:setEnabled(enabled, delay)
    if enabled then
        self:enable(delay)
    else
        self:disable()
    end
end

local function forEachDescendant(session, root, handler)
    local throttle = createThrottle()
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

local vfxOverrides = {
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

local function suppressEffect(session, instance, shouldLock, overrides)
    local classOverrides = (overrides or vfxOverrides)[instance.ClassName]
    if not classOverrides then
        return false
    end

    if shouldLock then
        session:lock(instance, classOverrides)
    else
        session:override(instance, classOverrides)
    end

    if instance.ClassName == "ParticleEmitter" then
        pcall(instance.Clear, instance)
    end
    return true
end

local function suppressUnder(session, root, overrides, shouldLock)
    local function suppress(instance)
        suppressEffect(session, instance, shouldLock, overrides)
    end

    session:connect(root.DescendantAdded, suppress)
    for _, descendant in ipairs(root:GetDescendants()) do
        suppress(descendant)
    end
end

local decorationClasses = {
    Decal = { Transparency = 1 },
    Texture = { Transparency = 1 },
    SpecialMesh = { Scale = Vector3.new(0, 0, 0) },
    SurfaceGui = { Enabled = false },
    BillboardGui = { Enabled = false },
}

local function createHider(partProperties)
    return function(session, instance)
        if suppressEffect(session, instance, false) then
            return
        end

        if isPart(instance) then
            session:override(instance, partProperties)
            return
        end

        local decoration = decorationClasses[instance.ClassName]
        if decoration then
            session:override(instance, decoration)
        end
    end
end

local mattePart = { Reflectance = 0, CastShadow = false }

local actions = {
    hide = createHider({
        CastShadow = false,
        CanCollide = false,
        CanTouch = false,
        CanQuery = false,
        Transparency = 1,
        LocalTransparencyModifier = 1,
    }),
    visual = createHider({
        CastShadow = false,
        Transparency = 1,
        LocalTransparencyModifier = 1,
    }),
    ghost = createHider({
        CastShadow = false,
        CanCollide = false,
        Transparency = 1,
        LocalTransparencyModifier = 1,
    }),
    effects = function(session, instance)
        suppressEffect(session, instance, false)
    end,
    matte = function(session, instance)
        if isPart(instance) then
            session:override(instance, mattePart)
        end
    end,
    destroy = function(_, instance)
        instance:Destroy()
    end,
}

local function watchPath(session, segments, onFound)
    local function descend(parent, index)
        local name = segments[index]
        local isLast = index == #segments

        local function consider(child)
            if name ~= "*" and child.Name ~= name then
                return
            end

            if isLast then
                task.defer(onFound, child)
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

local function runRule(session, rule)
    local mode = rule.mode or "hide"
    local action = actions[mode]
    if not action then
        warnTagged("unknown mode '" .. tostring(mode) .. "' for path " .. tostring(rule.path))
        return
    end

    local segments = splitPath(rule.path)
    if #segments == 0 then
        warnTagged("empty path in rules")
        return
    end

    local handledTargets = setmetatable({}, { __mode = "k" })

    local function applyTo(instance)
        if session.active then
            pcall(action, session, instance)
        end
    end

    local function applyToSubtree(root)
        applyTo(root)
        forEachDescendant(session, root, applyTo)
    end

    local function applyToChildren(target)
        session:connect(target.ChildAdded, function(child)
            task.defer(applyTo, child)
        end)
        for _, child in ipairs(target:GetChildren()) do
            applyTo(child)
        end
    end

    local function applyToSubtrees(target)
        session:connect(target.DescendantAdded, applyTo)
        if rule.children then
            for _, child in ipairs(target:GetChildren()) do
                applyToSubtree(child)
            end
        else
            applyToSubtree(target)
        end
    end

    local function onTarget(target)
        if handledTargets[target] then
            return
        end
        handledTargets[target] = true

        if mode ~= "destroy" then
            applyToSubtrees(target)
        elseif rule.children then
            applyToChildren(target)
        else
            applyTo(target)
        end
    end

    watchPath(session, segments, onTarget)
end

local function createRuleStarter(rules)
    return function(session)
        for _, rule in ipairs(rules) do
            local ok, err = pcall(runRule, session, rule)
            if not ok then
                warnTagged("rule failed (" .. tostring(rule.path) .. "): " .. tostring(err))
            end
        end
    end
end

local function getQualityLevel()
    return settings().Rendering.QualityLevel
end

local function setQualityLevel(level)
    settings().Rendering.QualityLevel = level
end

vm[1] = function(session)
    local function suppress(instance)
        suppressEffect(session, instance, false)
    end

    session:connect(workspace.DescendantAdded, suppress)
    forEachDescendant(session, workspace, suppress)
    suppressUnder(session, lighting, vfxOverrides, true)
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

    local previousDecoration
    if type(gethiddenproperty) == "function" then
        local readOk, value = pcall(gethiddenproperty, terrain, "Decoration")
        if readOk and type(value) == "boolean" then
            previousDecoration = value
        end
    end

    local applied = pcall(sethiddenproperty, terrain, "Decoration", false)
    if applied and previousDecoration ~= nil then
        session:onClose(function()
            pcall(sethiddenproperty, terrain, "Decoration", previousDecoration)
        end)
    end
end

vm[3] = createRuleStarter({
    { path = "Thrown", mode = "ghost", children = true },
})

vm[4] = createRuleStarter({
    { path = "Map.Trees", mode = "ghost" },
})

local skyOverrides = {
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
    suppressUnder(session, lighting, skyOverrides, true)
    suppressUnder(session, terrain, skyOverrides, false)

    if not lighting:FindFirstChildOfClass("Sky") then
        local sky = Instance.new("Sky")
        sky.Name = "custom_sky"
        sky.Parent = lighting
        session:onClose(function()
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
    suppressUnder(session, lighting, { Atmosphere = { Density = 0, Haze = 0, Glare = 0 } }, true)
end

vm[7] = function(session)
    local fpsCapSetter = setfpscap or set_fps_cap
    local fpsCapGetter = getfpscap or get_fps_cap

    if type(fpsCapSetter) == "function" then
        local previousCap = 60
        if type(fpsCapGetter) == "function" then
            local readOk, value = pcall(fpsCapGetter)
            if readOk and type(value) == "number" then
                previousCap = value
            end
        end

        pcall(fpsCapSetter, 9999)
        session:onClose(function()
            pcall(fpsCapSetter, previousCap)
        end)
    end

    local hasQualityLevel, previousLevel = pcall(getQualityLevel)
    if hasQualityLevel then
        pcall(setQualityLevel, Enum.QualityLevel.Level01)
        session:onClose(function()
            pcall(setQualityLevel, previousLevel)
        end)
    end
end

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")

vm[8] = function(session)
    local player = players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    if not session.active then
        return
    end

    local colorGood = Color3.fromRGB(80, 255, 140)
    local colorMid = Color3.fromRGB(255, 205, 70)
    local colorBad = Color3.fromRGB(255, 85, 100)
    local colorMuted = Color3.fromRGB(140, 145, 165)

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "fps_ping_counter"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    session:onClose(function()
        screenGui:Destroy()
    end)

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "main_frame"
    mainFrame.Size = UDim2.new(0, 108, 0, 32)
    mainFrame.Position = UDim2.new(0.8, 0, 0, 50)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 21, 30)
    mainFrame.BackgroundTransparency = 0.12
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = mainFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(70, 74, 100)
    stroke.Thickness = 1
    stroke.Transparency = 0.35
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = mainFrame

    local background = Instance.new("UIGradient")
    background.Rotation = 90
    background.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 32, 46)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 15, 22)),
    })
    background.Parent = mainFrame

    local scale = Instance.new("UIScale")
    scale.Scale = 0.8
    scale.Parent = mainFrame

    local accent = Instance.new("Frame")
    accent.Name = "accent"
    accent.Size = UDim2.new(1, 0, 0, 2)
    accent.BackgroundColor3 = Color3.new(1, 1, 1)
    accent.BorderSizePixel = 0
    accent.Parent = mainFrame

    local accentGradient = Instance.new("UIGradient")
    accentGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 200, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 90, 255)),
    })
    accentGradient.Parent = accent

    local function createLabel(name, text, font, textSize, position, size)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = size
        label.Position = position
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = colorMuted
        label.Font = font
        label.TextSize = textSize
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = mainFrame
        return label
    end

    local function createDot(name, position)
        local dot = Instance.new("Frame")
        dot.Name = name
        dot.Size = UDim2.new(0, 5, 0, 5)
        dot.Position = position
        dot.BackgroundColor3 = colorGood
        dot.BorderSizePixel = 0
        dot.Parent = mainFrame

        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = dot
        return dot
    end

    local fpsDot = createDot("fps_dot", UDim2.new(0, 9, 0, 8))
    createLabel("fps_title", "FPS", Enum.Font.GothamBold, 10, UDim2.new(0, 18, 0, 4), UDim2.new(0, 28, 0, 12))
    local fpsLabel = createLabel("fps_value", "0", Enum.Font.Code, 13, UDim2.new(0, 9, 0, 14), UDim2.new(0, 36, 0, 16))

    local divider = Instance.new("Frame")
    divider.Name = "divider"
    divider.Size = UDim2.new(0, 1, 0, 18)
    divider.Position = UDim2.new(0, 47, 0, 8)
    divider.BackgroundColor3 = Color3.fromRGB(70, 74, 100)
    divider.BackgroundTransparency = 0.4
    divider.BorderSizePixel = 0
    divider.Parent = mainFrame

    local pingDot = createDot("ping_dot", UDim2.new(0, 54, 0, 8))
    createLabel("ping_title", "PING", Enum.Font.GothamBold, 10, UDim2.new(0, 63, 0, 4), UDim2.new(0, 38, 0, 12))
    local pingLabel = createLabel("ping_value", "0 ms", Enum.Font.Code, 13, UDim2.new(0, 54, 0, 14), UDim2.new(0, 50, 0, 16))

    tweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

    local dragging = false
    local dragInput
    local dragStart
    local startPosition

    session:connect(mainFrame.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    session:connect(mainFrame.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    session:connect(userInputService.InputChanged, function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)

    local colorTween = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local currentFpsColor
    local currentPingColor

    local function applyColor(label, dot, color)
        tweenService:Create(label, colorTween, { TextColor3 = color }):Play()
        tweenService:Create(dot, colorTween, { BackgroundColor3 = color }):Play()
    end

    local displayedFps
    local displayedPing
    local shownFps
    local shownPing

    session:connect(runService.RenderStepped, function(dt)
        if dt <= 0 then
            return
        end

        local fps = 1 / dt
        local ping = player:GetNetworkPing() * 1000
        displayedFps = displayedFps or fps
        displayedPing = displayedPing or ping

        local alpha = 1 - math.exp(-6 * dt)
        displayedFps = displayedFps + (fps - displayedFps) * alpha
        displayedPing = displayedPing + (ping - displayedPing) * alpha

        local fpsValue = math.floor(displayedFps)
        if fpsValue ~= shownFps then
            shownFps = fpsValue
            fpsLabel.Text = string.format("%d", fpsValue)
        end

        local pingValue = math.floor(displayedPing)
        if pingValue ~= shownPing then
            shownPing = pingValue
            pingLabel.Text = string.format("%d ms", pingValue)
        end

        local fpsColor
        if displayedFps <= 25 then
            fpsColor = colorBad
        elseif displayedFps <= 40 then
            fpsColor = colorMid
        else
            fpsColor = colorGood
        end

        local pingColor
        if displayedPing <= 150 then
            pingColor = colorGood
        elseif displayedPing <= 250 then
            pingColor = colorMid
        else
            pingColor = colorBad
        end

        if fpsColor ~= currentFpsColor then
            currentFpsColor = fpsColor
            applyColor(fpsLabel, fpsDot, fpsColor)
        end

        if pingColor ~= currentPingColor then
            currentPingColor = pingColor
            applyColor(pingLabel, pingDot, pingColor)
        end
    end)
end

local function loadGui()
    local url = "https://raw.githubusercontent.com/Muza-Cloud/tsb/main/FixLagGui.lua"

    local ok, err = pcall(function()
        loadstring(game:HttpGet(url))()
    end)
    if not ok then
        warnTagged("gui failed: " .. tostring(err))
    end
end

local function buildOrder(count)
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

local function runVm(features)
    local order = buildOrder(#features)
    for position, index in ipairs(order) do
        local feature = features[index]
        local delay = (position - 1) * 0.3
        local ok, err = pcall(feature.enable, feature, delay)
        if not ok then
            warnTagged(string.format("%s start failed: %s", feature.label, tostring(err)))
        end
    end
end

if getgenv().fixLagShutdown then
    pcall(getgenv().fixLagShutdown)
end

local features = {}
for index = 1, #vm do
    features[index] = featureClass.new({ label = vmLabels[index], start = vm[index] })
end

local api = {
    features = features,
    sessionClass = sessionClass,
    vm = vm,
}

local function shutdown()
    if api.destroyGui then
        pcall(api.destroyGui)
    end
    for _, feature in ipairs(features) do
        feature:disable()
    end
    getgenv().fixLagCore = nil
    getgenv().fixLagShutdown = nil
end

api.shutdown = shutdown
getgenv().fixLagCore = api
getgenv().fixLagShutdown = shutdown

runVm(features)
loadGui()