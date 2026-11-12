local lighting = game:GetService("Lighting")
local workspace = game:GetService("Workspace")

local terrain = workspace.Terrain
local environment = getgenv and getgenv() or _G

local thrown_rules = {
    { path = "Thrown", mode = "visual", children = true },
}

local map_decor_rules = {
    { path = "Map.Halloween", mode = "visual" },
    { path = "Map.Circus2", mode = "visual" },
    { path = "Map.Trash", mode = "visual" },
    { path = "Map.Trees", mode = "visual" },
    { path = "Map.FX", mode = "visual" },
    { path = "HalloweenDoorTrees", mode = "visual" },
    { path = "CandyVisuals", mode = "visual" },
}

local disabled = { Enabled = false }

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
    Fire = disabled,
    Sparkles = disabled,
    PointLight = disabled,
    SpotLight = disabled,
    SurfaceLight = disabled,
    BloomEffect = disabled,
    BlurEffect = disabled,
    ColorCorrectionEffect = disabled,
    DepthOfFieldEffect = disabled,
    SunRaysEffect = disabled,
}

local sky_overrides = {
    Clouds = disabled,
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

local atmosphere_properties = {
    Density = 0,
    Haze = 0,
    Glare = 0,
}

local atmosphere_overrides = {
    Atmosphere = atmosphere_properties,
}

local decoration_overrides = {
    Decal = { Transparency = 1 },
    Texture = { Transparency = 1 },
    SpecialMesh = { Scale = Vector3.new(0, 0, 0) },
    SurfaceGui = disabled,
    BillboardGui = disabled,
}

local hidden_part_properties = {
    CastShadow = false,
    CanCollide = false,
    CanTouch = false,
    CanQuery = false,
    Transparency = 1,
    LocalTransparencyModifier = 1,
}

local visual_part_properties = {
    CastShadow = false,
    Transparency = 1,
    LocalTransparencyModifier = 1,
}

local matte_part_properties = {
    Reflectance = 0,
    CastShadow = false,
}

local lighting_properties = {
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
}

local terrain_properties = {
    Decoration = false,
    WaterWaveSize = 0,
    WaterWaveSpeed = 0,
    WaterReflectance = 0,
    WaterTransparency = 0,
}

local startup_stagger = 0.3
local gui_url = "https://raw.githubusercontent.com/Muza-Cloud/tsb/main/FixLagGui.lua"

local function get_property(instance, property)
    return instance[property]
end

local function set_property(instance, property, value)
    instance[property] = value
end

local function values_match(current, target)
    if type(current) == "number" and type(target) == "number" then
        return math.abs(current - target) <= math.max(1e-4, math.abs(target) * 1e-6)
    end
    return current == target
end

local function create_throttle(budget)
    local deadline = os.clock() + budget
    return function()
        if os.clock() >= deadline then
            task.wait()
            deadline = os.clock() + budget
        end
    end
end

local base_part_by_class = {}

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

local override_store = {}

local original_values = setmetatable({}, { __mode = "k" })
local claims_by_owner = {}

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

    local throttle = create_throttle(0.002)
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
        locked_instances = setmetatable({}, { __mode = "k" }),
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

local function reapply_when_changed(session, instance, property, value)
    local ok, signal = pcall(instance.GetPropertyChangedSignal, instance, property)
    if not ok then
        return
    end

    local reapply_pending = false
    session:connect(signal, function()
        if reapply_pending or values_match(instance[property], value) then
            return
        end

        reapply_pending = true
        task.defer(function()
            reapply_pending = false
            if session.active then
                pcall(set_property, instance, property, value)
            end
        end)
    end)
end

function session_class:lock(instance, properties)
    if not self.active then
        return
    end

    override_store.claim(self, instance, properties)

    if self.locked_instances[instance] then
        return
    end
    self.locked_instances[instance] = true

    for property, value in pairs(properties) do
        reapply_when_changed(self, instance, property, value)
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
            warn(string.format("[fixlag] %s failed: %s", self.label, tostring(err)))
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
    local throttle = create_throttle(0.002)
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

local function create_hider(part_properties)
    return function(session, instance)
        if suppress_effect(session, instance, false) then
            return
        end

        if is_part(instance) then
            session:override(instance, part_properties)
            return
        end

        local decoration = decoration_overrides[instance.ClassName]
        if decoration then
            session:override(instance, decoration)
        end
    end
end

local actions = {
    hide = create_hider(hidden_part_properties),
    visual = create_hider(visual_part_properties),
    effects = function(session, instance)
        suppress_effect(session, instance, false)
    end,
    matte = function(session, instance)
        if is_part(instance) then
            session:override(instance, matte_part_properties)
        end
    end,
    destroy = function(_, instance)
        instance:Destroy()
    end,
}

local function split_path(path)
    local segments = {}
    for segment in string.gmatch(tostring(path), "[^%.]+") do
        segments[#segments + 1] = segment
    end
    return segments
end

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
        warn("[fixlag] unknown mode '" .. tostring(mode) .. "' for path " .. tostring(rule.path))
        return
    end

    local segments = split_path(rule.path)
    if #segments == 0 then
        warn("[fixlag] empty path in rules")
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
                warn("[fixlag] rule failed (" .. tostring(rule.path) .. "): " .. tostring(err))
            end
        end
    end
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

local function destroy_vfx(session)
    local function suppress(instance)
        suppress_effect(session, instance, false)
    end

    session:connect(workspace.DescendantAdded, suppress)
    for_each_descendant(session, workspace, suppress)
    suppress_under(session, lighting, vfx_overrides, true)
end

local function destroy_terrain_and_water(session)
    local has_hidden_access = type(sethiddenproperty) == "function" and type(gethiddenproperty) == "function"
    local hidden_read, previous_decoration

    if has_hidden_access then
        hidden_read, previous_decoration = pcall(gethiddenproperty, terrain, "Decoration")
    end

    session:override(terrain, terrain_properties)

    if hidden_read then
        pcall(sethiddenproperty, terrain, "Decoration", false)
        session:on_close(function()
            pcall(sethiddenproperty, terrain, "Decoration", previous_decoration)
        end)
    end
end

local function gray_sky(session)
    session:lock(lighting, lighting_properties)
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

local function custom_atmosphere(session)
    suppress_under(session, lighting, atmosphere_overrides, true)
end

local function get_quality_level()
    return settings().Rendering.QualityLevel
end

local function set_quality_level(level)
    settings().Rendering.QualityLevel = level
end

local function boost_performance(session)
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

local feature_definitions = {
    { label = "destroy VFX", start = destroy_vfx },
    { label = "destroy terrain & water", start = destroy_terrain_and_water },
    { label = "destroy debris", start = create_rule_starter(thrown_rules) },
    { label = "destroy decorations", start = create_rule_starter(map_decor_rules) },
    { label = "gray sky", start = gray_sky },
    { label = "custom Atmosphere", start = custom_atmosphere },
    { label = "FPS Cap", start = boost_performance },
}

if environment.fixlag_shutdown then
    pcall(environment.fixlag_shutdown)
end

local features = {}
for index, definition in ipairs(feature_definitions) do
    local feature = feature_class.new(definition)
    feature:set_enabled(true, (index - 1) * startup_stagger)
    features[#features + 1] = feature
end

local api = {
    features = features,
    session_class = session_class,
}

local function shutdown()
    if api.destroy_gui then
        pcall(api.destroy_gui)
    end
    for _, feature in ipairs(features) do
        feature:disable()
    end
    environment.fixlag_core = nil
    environment.fixlag_shutdown = nil
end

api.shutdown = shutdown
environment.fixlag_core = api
environment.fixlag_shutdown = shutdown

if gui_url ~= "" then
    local ok, err = pcall(function()
        loadstring(game:HttpGet(gui_url))()
    end)
    if not ok then
        warn("[fixlag] gui failed: " .. tostring(err))
    end
else
    warn("[fixlag] gui_url is empty, core runs without gui")
end