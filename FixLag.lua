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
    { path = "Map.Trees", mode = "destroy" },
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