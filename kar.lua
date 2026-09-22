local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local plr = Players.LocalPlayer

-- Safe GUI parenting: CoreGui is blocked on many executors/games.
-- Falls back to gethui()/get_hidden_gui() so custom panels still build.
local function getGuiParent()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    ok, h = pcall(function() return get_hidden_gui and get_hidden_gui() end)
    if ok and h then return h end
    return CoreGui
end
local function safeParentGui(gui)
    local parent = getGuiParent()
    local ok, err = pcall(function() gui.Parent = parent end)
    if not ok then
        pcall(function() gui.Parent = plr and plr:FindFirstChildOfClass('PlayerGui') end)
    end
    return gui
end

-- 1 mph = 0.44704 m/s, 1 stud ~= 0.28 m; precise ratio matches the in-game HUD
local MPH_TO_STUDS = 1.5966
local STUDS_TO_MPH = 0.6264

-- cloud endpoint (empty = disabled)
local CLOUD_ENDPOINT = 'https://konstant-aero-cloud.kar-cloud.workers.dev'

local function cloudCall(method, urlPath, body)
    if CLOUD_ENDPOINT == '' then return nil, 'Cloud endpoint not configured' end
    local httpReq = request or (syn and syn.request)
                 or (http and http.request) or http_request
    if not httpReq then return nil, 'executor has no request()' end
    local HttpService = game:GetService('HttpService')
    local opts = {
        Url     = CLOUD_ENDPOINT .. urlPath,
        Method  = method,
        Headers = { ['Content-Type'] = 'application/json' },
    }
    if body ~= nil then opts.Body = HttpService:JSONEncode(body) end
    local ok, resp = pcall(httpReq, opts)
    if not ok then return nil, tostring(resp) end
    if not resp then return nil, 'no response' end
    local decoded
    if resp.Body and resp.Body ~= '' then
        local dOk, dVal = pcall(function() return HttpService:JSONDecode(resp.Body) end)
        if dOk then decoded = dVal end
    end
    local status = resp.StatusCode or resp.Status or 0
    if status >= 400 then
        return nil, (decoded and decoded.error) or ('HTTP ' .. tostring(status))
    end
    return decoded, nil
end

-- undo/redo stack (Ctrl+Z / Ctrl+Y + top-right buttons)
local History = { undo = {}, redo = {}, MAX = 60 }
local COMMON_PROPS = { 'Color', 'Material', 'Transparency', 'Reflectance',
                       'CastShadow', 'Anchored', 'CanCollide' }

function History.push(label, apply, undo)
    table.insert(History.undo, { label = label, apply = apply, undo = undo })
    if #History.undo > History.MAX then table.remove(History.undo, 1) end
    History.redo = {}
end

function History.snap(parts, props)
    props = props or COMMON_PROPS
    local out = {}
    for _, p in ipairs(parts) do
        local s = {}
        for _, k in ipairs(props) do
            local ok, v = pcall(function() return p[k] end)
            if ok then s[k] = v end
        end
        out[p] = s
    end
    return out
end

function History.applySnap(snap)
    for p, s in pairs(snap) do
        if p and p.Parent then
            for k, v in pairs(s) do pcall(function() p[k] = v end) end
        end
    end
end

function History.pushDiff(label, parts, props, mutate)
    if not parts or #parts == 0 then if mutate then mutate() end; return end
    local before = History.snap(parts, props)
    if mutate then mutate() end
    local after = History.snap(parts, props)
    History.push(label,
        function() History.applySnap(after) end,
        function() History.applySnap(before) end)
end

function History.doUndo()
    local e = table.remove(History.undo); if not e then return nil end
    pcall(e.undo); table.insert(History.redo, e); return e.label
end

function History.doRedo()
    local e = table.remove(History.redo); if not e then return nil end
    pcall(e.apply); table.insert(History.undo, e); return e.label
end

-- deduplication guard: if a previous instance is running, clean it up first
if _G.SMCleanup then
    pcall(_G.SMCleanup)
    _G.SMCleanup = nil
end

local playSuccess = function() end -- assigned for real after gui is created below
local showToast = function() end   -- assigned for real after gui is created below
local minimapGui  -- defined after gui is created below

-- universal bike/vehicle discovery
local UNIVERSAL_SPAWN_NAMES  = { 'SpawnBike', 'BikeSpawn', 'SpawnVehicle', 'GiveBike', 'CreateBike' }
local UNIVERSAL_BIKE_FOLDERS = { 'Bikes', 'BikeList', 'Vehicles' }

local function _findFirstByNames(root, names)
    for _, n in ipairs(names) do
        local f = root:FindFirstChild(n, true)
        if f then return f end
    end
    return nil
end

local function _discoverBikes()
    local bikesFolder = _findFirstByNames(RS, UNIVERSAL_BIKE_FOLDERS)
    local list = {}
    if bikesFolder then
        for _, v in ipairs(bikesFolder:GetChildren()) do
            if v:IsA('Model') then table.insert(list, v) end
        end
        if #list == 0 then
            for _, v in ipairs(bikesFolder:GetDescendants()) do
                if v:IsA('Model') then table.insert(list, v) end
            end
        end
    end

    local spawnRemote = _findFirstByNames(RS, UNIVERSAL_SPAWN_NAMES)
    return {
        mode = 'universal',
        bikes = list,
        canSpawn = (#list > 0 and spawnRemote ~= nil),
        spawn = function(name)
            if not spawnRemote then return end
            pcall(function()
                if spawnRemote:IsA('RemoteEvent') then
                    spawnRemote:FireServer(name)
                elseif spawnRemote:IsA('RemoteFunction') then
                    spawnRemote:InvokeServer(name)
                end
            end)
        end,
    }
end

local BIKE_INFO = _discoverBikes()

-- legacy flags kept as false for any lingering reference
local IS_SUPERMOTO = false
local IS_KONSTANT  = false
local BRAND_TITLE  = 'Konstant Aero'

-- VehicleSeat + Seat = every rig type we care about
local function isVehicleSeat(s)
    return s and (s:IsA('VehicleSeat') or s:IsA('Seat'))
end

-- user-facing terminology (Aero: generic vehicle language)
local VEHICLE_TERM     = 'vehicle'
local VEHICLE_TERM_CAP = 'Vehicle'

-- trick terminology + key: planes / cars do flips instead of wheelies
local WHEELIE_TERM     = 'Backflip'
local STOPPIE_TERM     = 'Frontflip'
local STOPPIE_KEY      = Enum.KeyCode.Comma
local STOPPIE_KEY_LBL  = ','

local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local function safeLoadUrl(url)
    local ok, src = pcall(function() return game:HttpGet(url) end)
    if not ok or not src or src == '' then return nil, 'HttpGet failed: ' .. tostring(src) end
    local ok2, fn = pcall(loadstring, src)
    if not ok2 then return nil, 'loadstring failed' end
    local ok3, mod = pcall(fn)
    if not ok3 then return nil, 'module init failed: ' .. tostring(mod) end
    return mod, nil
end
local Library, libErr = safeLoadUrl(repo .. 'Library.lua')
assert(Library, 'Konstant: Linoria Library failed to load - ' .. tostring(libErr))
local ThemeManager = (function() local m = safeLoadUrl(repo .. 'addons/ThemeManager.lua'); return m end)()
if not ThemeManager then warn('Konstant: ThemeManager failed to load - Settings theme section disabled') end
local SaveManager = (function() local m = safeLoadUrl(repo .. 'addons/SaveManager.lua'); return m end)()
if not SaveManager then warn('Konstant: SaveManager failed to load - configs disabled') end

local Window = Library:CreateWindow({
    Title = BRAND_TITLE,
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})
pcall(function()
    Library.ScreenGui.DisplayOrder = 999
    safeParentGui(Library.ScreenGui)
end)
-- menu toggle key: Delete (override Linoria's default RightControl)
-- Linoria forks use different property names; set every known variant.
pcall(function() Library.ToggleKeybind = Enum.KeyCode.Delete end)
pcall(function() Library.ToggleKey     = Enum.KeyCode.Delete end)
pcall(function() Library.MenuKeybind   = Enum.KeyCode.Delete end)
-- Also bind a direct UIS listener that flips the menu state both ways.
_G.MenuToggleConn = UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode ~= Enum.KeyCode.Delete then return end
    -- Try every documented toggle path; first one that exists wins.
    if not pcall(function() Library:Toggle() end) then
        if not pcall(function() Library.Toggled = not Library.Toggled end) then
            pcall(function()
                if Library.ScreenGui then
                    Library.ScreenGui.Enabled = not Library.ScreenGui.Enabled
                end
            end)
        end
    end
end)

local Tabs = {
    Main     = Window:AddTab('Main'),
    General  = Window:AddTab('General'),
    Maps     = Window:AddTab('Maps'),
    Settings = Window:AddTab('Settings')
}

local Left     = Tabs.Main:AddLeftGroupbox('Visual')
local BikeLeft = Tabs.Main:AddLeftGroupbox(VEHICLE_TERM_CAP .. 's')
local Right    = Tabs.Main:AddRightGroupbox('Mods')

Left:AddToggle('Fullbright', {
    Text = 'Fullbright',
    Default = false,
    Callback = function(val)
        local L = game:GetService('Lighting')
        if val then
            _G.FBCache = {
                Ambient        = L.Ambient,
                OutdoorAmbient = L.OutdoorAmbient,
                Brightness     = L.Brightness,
                ClockTime      = L.ClockTime,
            }
            L.Ambient        = Color3.fromRGB(255, 255, 255)
            L.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
            L.Brightness     = 2
            L.ClockTime      = 12
        else
            if _G.FBCache then
                L.Ambient        = _G.FBCache.Ambient
                L.OutdoorAmbient = _G.FBCache.OutdoorAmbient
                L.Brightness     = _G.FBCache.Brightness
                L.ClockTime      = _G.FBCache.ClockTime
            end
        end
    end
})

Left:AddDivider()

Left:AddToggle('MinimapToggle', {
    Text = 'Minimap',
    Default = false,
    Callback = function(val)
        if minimapGui then minimapGui.Enabled = val end
    end
})

Left:AddToggle('CustomOverlay', {
    Text = 'Custom Overlay',
    Default = false,
    Callback = function(val)
        -- speedOverlay is built at the bottom of the file (after all
        -- Roblox services + helpers are defined). We forward-toggle its
        -- .Enabled property and start/stop the render loop.
        if _G.AeroOverlaySetEnabled then _G.AeroOverlaySetEnabled(val) end
    end
})

BikeLeft:AddDivider()

BikeLeft:AddInput('SpeedInput', {
    Default = '60',
    Numeric = true,
    Finished = false,
    Text = 'Max Speed (mph)',
})

BikeLeft:AddInput('AccelInput', {
    Default = '37',
    Numeric = true,
    Finished = false,
    Text = 'Acceleration (mph/s)',
})

-- Ground-only gate: when ON, speed + brake + reverse only apply while bike is grounded.
-- A 6-stud downward raycast from the seat (with the player filtered out) is the check.
BikeLeft:AddToggle('GroundOnly', {
    Text = 'Ground-Only Physics',
    Default = false,
    Tooltip = 'Speed, brake, and reverse only fire while the ' .. VEHICLE_TERM .. ' is touching ground.',
})

-- Airplane Mode: switches Speed + Brake from flat 2D math to full 3D nose-direction.
-- OFF (default): old behavior — accelerate flat regardless of pitch (right for bikes/cars)
-- ON:            accelerate along LookVector — pitch up to climb, pitch down to dive
BikeLeft:AddToggle('AirplaneMode', {
    Text = 'Airplane Mode',
    Default = false,
    Tooltip = 'Use full 3D nose direction so planes can climb. Leave OFF for bikes and cars.',
})

-- Sticky Vehicle: tires planted, still drivable. Downward velocity clamp when grounded.
BikeLeft:AddToggle('StickyVehicle', {
    Text = 'Sticky ' .. VEHICLE_TERM_CAP,
    Default = false,
    Tooltip = 'Glues the ' .. VEHICLE_TERM .. ' to the floor while you keep driving. Kills bounce / launches.',
    Callback = function(val)
        if val then
            _G.StickyConn = RunService.Heartbeat:Connect(function()
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                local seat = hum and hum.SeatPart
                if not isVehicleSeat(seat) then return end
                -- only act on meaningful upward velocity; horizontal untouched.
                -- weak reversal (0.4x) so the physics solver isn't overwhelmed at speed,
                -- which is what was making wheels phase through the chassis on the old version.
                local vel = seat.AssemblyLinearVelocity
                if vel.Y > 3 then
                    seat.AssemblyLinearVelocity = Vector3.new(vel.X, -vel.Y * 0.4, vel.Z)
                end
            end)
            showToast('Sticky ' .. VEHICLE_TERM_CAP .. ' ON')
        else
            if _G.StickyConn then _G.StickyConn:Disconnect(); _G.StickyConn = nil end
            showToast('Sticky ' .. VEHICLE_TERM_CAP .. ' OFF')
        end
    end
})

BikeLeft:AddButton({
    Text = 'Unpatch ' .. VEHICLE_TERM_CAP,
    Func = function()
        _G.SpeedPatched = false
        local was = _G.SpeedConn or _G.SpeedConnStep
        if _G.SpeedConn     then _G.SpeedConn:Disconnect();     _G.SpeedConn     = nil end
        if _G.SpeedConnStep then _G.SpeedConnStep:Disconnect(); _G.SpeedConnStep = nil end
        if was then showToast('Unpatched') else showToast('Nothing to unpatch') end
    end
})

BikeLeft:AddButton({
    Text = 'Patch ' .. VEHICLE_TERM_CAP,
    Func = function()
        local RS2  = game:GetService('RunService')

        -- Sanity: verify we're seated NOW so the toast makes sense; the
        -- heartbeat below re-resolves seat + root every frame, so the boost
        -- survives respawns, dismounts, and being kicked off the seat.
        local char0 = plr.Character
        local hum0  = char0 and char0:FindFirstChildWhichIsA('Humanoid')
        if not (hum0 and isVehicleSeat(hum0.SeatPart)) then
            showToast('Get in a ' .. VEHICLE_TERM .. ' first')
            return
        end

        if _G.SpeedConn then
            _G.SpeedConn:Disconnect()
            _G.SpeedConn = nil
        end
        if _G.SpeedConnStep then
            _G.SpeedConnStep:Disconnect()
            _G.SpeedConnStep = nil
        end
        _G.SpeedPatched = true

        -- The per-frame worker. Reads mph/accel LIVE from the input boxes so
        -- editing the values without re-Patching takes effect immediately;
        -- the old code baked them into the closure at Patch time which was
        -- part of the "I set accel to 15000 and nothing happens" bug when
        -- the user tweaked values after patching.
        local function tick(dt)
            if not _G.SpeedPatched then return end
            if not UIS:IsKeyDown(Enum.KeyCode.W) then return end

            local mph      = tonumber(Options.SpeedInput.Value) or 60
            local accelMph = tonumber(Options.AccelInput.Value) or 37
            local maxSpeed = mph * MPH_TO_STUDS
            local accel    = accelMph * MPH_TO_STUDS

            -- Re-resolve seat + root EVERY frame. Caching them across
            -- respawns / re-mounts was the "sometimes it works, sometimes
            -- it doesn't" bug: root went nil after a respawn and the old
            -- code disconnected. Now the boost auto-recovers.
            local char2 = plr.Character
            local hum2  = char2 and char2:FindFirstChildWhichIsA('Humanoid')
            local seat2 = hum2 and hum2.SeatPart
            if not isVehicleSeat(seat2) then return end

            -- AssemblyRootPart = Roblox's canonical "which part represents
            -- this assembly's rigid body". Writing AssemblyLinearVelocity
            -- on it moves the whole welded assembly, not a stray sub-part.
            -- Fallback to seat itself which is always in the chassis
            -- assembly; also write to the character root as a backup so a
            -- multi-assembly bike still gets pushed forward.
            local root = seat2.AssemblyRootPart or seat2
            if not root or not root.Parent then return end

            -- Ground-only gate (silently bypassed when Airplane Mode is on)
            if Toggles.GroundOnly and Toggles.GroundOnly.Value
               and not (Toggles.AirplaneMode and Toggles.AirplaneMode.Value) then
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                local model = seat2.Parent
                rp.FilterDescendantsInstances = { model, char2 }
                local hit = workspace:Raycast(root.Position, Vector3.new(0, -10, 0), rp)
                if not hit then return end
            end

            local function push(part)
                if not part or not part.Parent then return end
                local vel = part.AssemblyLinearVelocity
                if Toggles.AirplaneMode and Toggles.AirplaneMode.Value then
                    if vel.Magnitude < maxSpeed then
                        local fwd = part.CFrame.LookVector
                        part.AssemblyLinearVelocity = vel + fwd * dt * accel
                    end
                else
                    local flatVel = Vector3.new(vel.X, 0, vel.Z)
                    if flatVel.Magnitude < maxSpeed then
                        local fwd     = root.CFrame.LookVector
                        local flatFwd = Vector3.new(fwd.X, 0, fwd.Z)
                        if flatFwd.Magnitude < 0.01 then return end
                        flatFwd = flatFwd.Unit
                        part.AssemblyLinearVelocity = Vector3.new(
                            vel.X + flatFwd.X * dt * accel,
                            vel.Y,
                            vel.Z + flatFwd.Z * dt * accel
                        )
                    end
                end
            end

            push(root)
            -- Character root shares the seat's assembly on VehicleSeat;
            -- writing it too covers games where the seat sits on a separate
            -- Motor6D-driven assembly.
            local hrp = char2 and char2:FindFirstChild('HumanoidRootPart')
            if hrp and hrp.AssemblyRootPart and hrp.AssemblyRootPart ~= root then
                push(hrp.AssemblyRootPart)
            end
        end

        -- Dual-connect: Stepped fires BEFORE the physics step (writes get
        -- used by physics that same frame), Heartbeat fires AFTER (catches
        -- any anti-cheat that runs post-physics). Only one push per
        -- physics step actually lands because the vel.Magnitude gate blocks
        -- the second call.
        _G.SpeedConnStep = RS2.Stepped:Connect(function(_, dt) tick(dt) end)
        _G.SpeedConn     = RS2.Heartbeat:Connect(tick)

        playSuccess()
        showToast('Patched -- live reads from the input boxes')
    end
})

BikeLeft:AddDivider()

if BIKE_INFO.canSpawn then
    BikeLeft:AddToggle('SpawnerToggle', {
        Text = 'Toggle Spawner',
        Default = false,
    })
    BikeLeft:AddDivider()
end

local clonedBikes = {}

BikeLeft:AddButton({
    Text = 'Clone ' .. VEHICLE_TERM_CAP,
    Func = function()
        local char = plr.Character
        local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
        if not hum or not hum.SeatPart then showToast('Not on a ' .. VEHICLE_TERM); return end
        local model = hum.SeatPart.Parent
        local clone = model:Clone()
        clone:PivotTo(model:GetPivot() * CFrame.new((#clonedBikes + 1) * 10, 0, 0))
        clone.Parent = workspace
        table.insert(clonedBikes, clone)
        showToast(VEHICLE_TERM_CAP .. ' cloned (' .. #clonedBikes .. ' clones)')
    end
})

BikeLeft:AddButton({
    Text = 'Clear Cloned ' .. VEHICLE_TERM_CAP .. 's',
    Func = function()
        for _, b in ipairs(clonedBikes) do pcall(function() b:Destroy() end) end
        clonedBikes = {}
        showToast('Cloned ' .. VEHICLE_TERM .. 's cleared')
    end
})

BikeLeft:AddDivider()

-- forward-declared so HitboxViewer toggle (defined in this groupbox) and
-- the Troll section (which does the full definitions) share the same upvalues
local hitboxMap      = {}
local clearHitboxes  = nil
local refreshHitboxes = nil

local function getBikeRoot()
    -- O(1): Humanoid.SeatPart is always the current VehicleSeat (no workspace scan)
    local char = plr.Character
    local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
    if not hum then return nil, nil end
    local seat = hum.SeatPart
    if not seat or not seat:IsA('VehicleSeat') then return nil, nil end
    return seat.Parent, seat.Parent:FindFirstChildWhichIsA('BasePart')
end

-- scans once and returns root; on heartbeat only rescans if root went nil
local function cachedRoot(stored)
    if stored and stored.Parent then return stored end
    local _, r = getBikeRoot()
    return r
end

BikeLeft:AddInput('BrakeInput', {
    Default = '120',
    Numeric = true,
    Finished = false,
    Text = 'Brake Force (mph/s)',
})

BikeLeft:AddInput('ReverseInput', {
    Default = '50',
    Numeric = true,
    Finished = false,
    Text = 'Reverse Force (mph/s)',
})

BikeLeft:AddButton({
    Text = 'Unpatch Brake',
    Func = function()
        if _G.BrakeConn then
            _G.BrakeConn:Disconnect()
            _G.BrakeConn = nil
            showToast('Brake unpatched')
        else
            showToast('Nothing to unpatch')
        end
    end
})

BikeLeft:AddButton({
    Text = 'Patch Brake',
    Func = function()
        local RS2  = game:GetService('RunService')
        local char = plr.Character

        local seat
        for _, v in pairs(workspace:GetDescendants()) do
            if isVehicleSeat(v) and v.Occupant
            and v.Occupant.Parent == char then
                seat = v
                break
            end
        end

        if not seat then
            showToast('Get in a ' .. VEHICLE_TERM .. ' first')
            return
        end

        if _G.BrakeConn then
            _G.BrakeConn:Disconnect()
            _G.BrakeConn = nil
        end

        local root       = seat.Parent:FindFirstChildWhichIsA('BasePart')
        local brakeMph   = tonumber(Options.BrakeInput.Value) or 120
        local brakeDecel = brakeMph * MPH_TO_STUDS  -- studs/s²

        _G.BrakeConn = RS2.Heartbeat:Connect(function(dt)
            if not UIS:IsKeyDown(Enum.KeyCode.S) then return end
            if not root or not root.Parent then
                _G.BrakeConn:Disconnect()
                _G.BrakeConn = nil
                return
            end
            -- Seated-only gate: bail if player is not on a VehicleSeat
            local char2 = plr.Character
            local hum2  = char2 and char2:FindFirstChildWhichIsA('Humanoid')
            local seat2 = hum2 and hum2.SeatPart
            if not isVehicleSeat(seat2) then return end
            -- Ground-only gate (silently bypassed when Airplane Mode is on)
            if Toggles.GroundOnly and Toggles.GroundOnly.Value
               and not (Toggles.AirplaneMode and Toggles.AirplaneMode.Value) then
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = { root.Parent, char2 }
                local hit = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), rp)
                if not hit then return end
            end
            local vel = root.AssemblyLinearVelocity
            local fwd = root.CFrame.LookVector

            -- reverse is its own independent force, not derived from brake.
            local revMph      = tonumber(Options.ReverseInput.Value) or 50
            local revAccel    = revMph * MPH_TO_STUDS
            local revMaxStuds = (revMph * 0.4) * MPH_TO_STUDS

            if Toggles.AirplaneMode and Toggles.AirplaneMode.Value then
                -- 3D nose-direction brake / reverse (planes + tilted vehicles)
                if fwd.Magnitude < 0.01 then return end
                local forwardSpeed = vel:Dot(fwd)
                if forwardSpeed > 2 then
                    local reduction = math.min(forwardSpeed, brakeDecel * dt)
                    root.AssemblyLinearVelocity = vel - fwd * reduction
                else
                    local currentRev = -forwardSpeed
                    if currentRev < revMaxStuds then
                        root.AssemblyLinearVelocity = vel - fwd * (revAccel * dt)
                    end
                end
            else
                -- Flat 2D brake / reverse (ground vehicles; preserves Y velocity)
                local flatVel = Vector3.new(vel.X, 0, vel.Z)
                local flatFwd = Vector3.new(fwd.X, 0, fwd.Z)
                if flatFwd.Magnitude < 0.01 then return end
                flatFwd = flatFwd.Unit
                local forwardSpeed = flatVel:Dot(flatFwd)
                if forwardSpeed > 2 then
                    local reduction = math.min(forwardSpeed, brakeDecel * dt)
                    local newFlat   = flatVel - flatFwd * reduction
                    root.AssemblyLinearVelocity = Vector3.new(newFlat.X, vel.Y, newFlat.Z)
                else
                    local currentRev = -forwardSpeed
                    if currentRev < revMaxStuds then
                        local addition = revAccel * dt
                        root.AssemblyLinearVelocity = Vector3.new(
                            vel.X - flatFwd.X * addition,
                            vel.Y,
                            vel.Z - flatFwd.Z * addition
                        )
                    end
                end
            end
        end)

        playSuccess()
        showToast('Brake patched — ' .. brakeMph .. ' mph/s')
    end
})

BikeLeft:AddDivider()

BikeLeft:AddInput('TurnInput', {
    Default = '90',
    Numeric = true,
    Finished = false,
    Text = 'Turn Speed (deg/s)',
})

BikeLeft:AddButton({
    Text = 'Unpatch Turn',
    Func = function()
        if _G.TurnConn then
            _G.TurnConn:Disconnect()
            _G.TurnConn = nil
            showToast('Turn unpatched')
        else
            showToast('Nothing to unpatch')
        end
    end
})

BikeLeft:AddButton({
    Text = 'Patch Turn',
    Func = function()
        local RS2  = game:GetService('RunService')
        local char = plr.Character

        local seat
        for _, v in pairs(workspace:GetDescendants()) do
            if isVehicleSeat(v) and v.Occupant
            and v.Occupant.Parent == char then
                seat = v
                break
            end
        end

        if not seat then
            showToast('Get in a ' .. VEHICLE_TERM .. ' first')
            return
        end

        if _G.TurnConn then
            _G.TurnConn:Disconnect()
            _G.TurnConn = nil
        end

        local root    = seat.Parent:FindFirstChildWhichIsA('BasePart')
        local degPerS = tonumber(Options.TurnInput.Value) or 90
        local radPerS = math.rad(degPerS)  -- convert to radians/s for angular velocity

        _G.TurnConn = RS2.Heartbeat:Connect(function(dt)
            local aDown = UIS:IsKeyDown(Enum.KeyCode.A)
            local dDown = UIS:IsKeyDown(Enum.KeyCode.D)
            if not aDown and not dDown then return end
            if not root or not root.Parent then
                _G.TurnConn:Disconnect()
                _G.TurnConn = nil
                return
            end
            -- positive Y = left (A), negative Y = right (D)
            local dir = aDown and 1 or -1
            local cur = root.AssemblyAngularVelocity
            root.AssemblyAngularVelocity = Vector3.new(cur.X, dir * radPerS, cur.Z)
        end)

        playSuccess()
        showToast('Turn patched — ' .. degPerS .. ' deg/s')
    end
})

BikeLeft:AddDivider()

BikeLeft:AddInput('WheelieStrength', {
    Default = '8',
    Numeric = true,
    Finished = false,
    Text = WHEELIE_TERM .. ' Strength (rad/s)',
})

BikeLeft:AddToggle('WheelieBoost', {
    Text = WHEELIE_TERM .. ' Boost (hold C)',
    Default = false,
    Callback = function(val)
        if val then
            _G.WheelieConn = RunService.Heartbeat:Connect(function()
                if not UIS:IsKeyDown(Enum.KeyCode.C) then return end
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not isVehicleSeat(seat) then return end
                local strength = tonumber(Options.WheelieStrength.Value) or 8
                local rv  = seat.CFrame.RightVector
                local cur = seat.AssemblyAngularVelocity
                seat.AssemblyAngularVelocity = cur + rv * (strength - cur:Dot(rv))
            end)
            showToast(WHEELIE_TERM .. ' Boost ON — hold C')
        else
            if _G.WheelieConn then _G.WheelieConn:Disconnect(); _G.WheelieConn = nil end
            showToast(WHEELIE_TERM .. ' Boost OFF')
        end
    end
})

local wheelieLockToggle = BikeLeft:AddToggle('WheelieLock', {
    Text = WHEELIE_TERM .. ' Lock',
    Default = false,
    Callback = function(val)
        if val then
            local locked = false
            local lockedPitchY = 0

            _G.WheelieVConn = UIS.InputBegan:Connect(function(input, gp)
                if gp then return end
                -- key comes from the KeyPicker below; resolve its string
                -- name ('V', 'H', 'Space', ...) into the actual KeyCode
                local wantName = (Options.WheelieLockKey and Options.WheelieLockKey.Value) or 'V'
                local wantKC   = Enum.KeyCode[wantName]
                if not wantKC or input.KeyCode ~= wantKC then return end
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not isVehicleSeat(seat) then return end
                if locked then
                    locked = false
                    showToast(WHEELIE_TERM .. ' angle unlocked')
                else
                    lockedPitchY = seat.CFrame.LookVector.Y
                    locked = true
                    showToast(WHEELIE_TERM .. ' angle locked')
                end
            end)

            _G.WheelieLocConn = RunService.Heartbeat:Connect(function()
                if not locked then return end
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not isVehicleSeat(seat) then return end
                local err = lockedPitchY - seat.CFrame.LookVector.Y
                local rv  = seat.CFrame.RightVector
                local cur = seat.AssemblyAngularVelocity
                local correction = math.clamp(err * 15, -12, 12)
                seat.AssemblyAngularVelocity = cur + rv * (correction - cur:Dot(rv))
            end)

            showToast(WHEELIE_TERM .. ' Lock ON — press V to lock angle')
        else
            if _G.WheelieVConn   then _G.WheelieVConn:Disconnect();   _G.WheelieVConn   = nil end
            if _G.WheelieLocConn then _G.WheelieLocConn:Disconnect(); _G.WheelieLocConn = nil end
            showToast(WHEELIE_TERM .. ' Lock OFF')
        end
    end
})

-- rebindable key for Backflip Lock (default V). String is stored in
-- Options.WheelieLockKey.Value as the KeyCode name, resolved live in
-- the InputBegan handler above so rebinding takes effect immediately.
wheelieLockToggle:AddKeyPicker('WheelieLockKey', {
    Default   = 'V',
    NoUI      = false,
    Text      = WHEELIE_TERM .. ' Lock Key',
    Mode      = 'Always',
    SyncToggleState = false,
})

BikeLeft:AddInput('StoppieStrength', {
    Default = '8',
    Numeric = true,
    Finished = false,
    Text = STOPPIE_TERM .. ' Strength (rad/s)',
})

BikeLeft:AddToggle('StoppieBoost', {
    Text = STOPPIE_TERM .. ' (hold ,)',
    Default = false,
    Callback = function(val)
        if val then
            _G.StoppieConn = RunService.Heartbeat:Connect(function()
                if not UIS:IsKeyDown(Enum.KeyCode.Comma) then return end
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not isVehicleSeat(seat) then return end
                local strength = tonumber(Options.StoppieStrength.Value) or 8
                local rv  = seat.CFrame.RightVector
                local cur = seat.AssemblyAngularVelocity
                seat.AssemblyAngularVelocity = cur + rv * (-strength - cur:Dot(rv))
            end)
            showToast(STOPPIE_TERM .. ' ON — hold ,')
        else
            if _G.StoppieConn then _G.StoppieConn:Disconnect(); _G.StoppieConn = nil end
            showToast(STOPPIE_TERM .. ' OFF')
        end
    end
})

BikeLeft:AddDivider()

BikeLeft:AddInput('CruiseSpeedInput', {
    Default = '40',
    Numeric = true,
    Finished = false,
    Text = 'Cruise Speed (studs/s)',
})

BikeLeft:AddToggle('CruiseControl', {
    Text = 'Cruise Control',
    Default = false,
    Callback = function(val)
        if val then
            _G.CruiseConn = RunService.Heartbeat:Connect(function()
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not isVehicleSeat(seat) then return end
                local vel = seat.AssemblyLinearVelocity
                if vel.Magnitude < 0.5 then return end
                local target = tonumber(Options.CruiseSpeedInput.Value) or 40
                seat.AssemblyLinearVelocity = vel.Unit * target
            end)
            showToast('Cruise Control ON')
        else
            if _G.CruiseConn then _G.CruiseConn:Disconnect(); _G.CruiseConn = nil end
            showToast('Cruise Control OFF')
        end
    end
})

BikeLeft:AddDivider()

BikeLeft:AddToggle('NoWobble', {
    Text = 'No Wobble (N to toggle)',
    Default = false,
    Callback = function(val)
        if val then
            local enabled = false

            _G.NoWobbleKeyConn = UIS.InputBegan:Connect(function(input, gp)
                if gp or input.KeyCode ~= Enum.KeyCode.N then return end
                enabled = not enabled
                showToast('No Wobble: ' .. (enabled and 'LOCKED' or 'released'))
            end)

            _G.NoWobbleConn = RunService.Heartbeat:Connect(function()
                if not enabled then return end
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not isVehicleSeat(seat) then return end
                -- preserve world-Y angular velocity (yaw, so you can still turn)
                -- kill X and Z components (roll + pitch wobble)
                local av = seat.AssemblyAngularVelocity
                seat.AssemblyAngularVelocity = Vector3.new(0, av.Y, 0)
            end)

            showToast('No Wobble ON — press N to lock/release')
        else
            if _G.NoWobbleKeyConn then _G.NoWobbleKeyConn:Disconnect(); _G.NoWobbleKeyConn = nil end
            if _G.NoWobbleConn    then _G.NoWobbleConn:Disconnect();    _G.NoWobbleConn    = nil end
            showToast('No Wobble OFF')
        end
    end
})

-- Lock Steering: same idea as No Wobble but zeros yaw too.
-- Vehicle can only go straight; no turning, no roll, no pitch.
BikeLeft:AddToggle('LockSteering', {
    Text = 'Lock Steering',
    Default = false,
    Tooltip = 'Zeros ALL angular velocity. Vehicle only moves forward — no turning at all.',
    Callback = function(val)
        if val then
            -- auto-kill Patch Turn so the two don't fight each frame
            if _G.TurnConn then
                _G.TurnConn:Disconnect()
                _G.TurnConn = nil
                showToast('Patch Turn disabled (Lock Steering owns the angular velocity now)')
            end
            _G.LockSteeringConn = RunService.Heartbeat:Connect(function()
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not isVehicleSeat(seat) then return end
                -- kill every axis: no roll, no pitch, no yaw
                seat.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)
            showToast('Lock Steering ON')
        else
            if _G.LockSteeringConn then _G.LockSteeringConn:Disconnect(); _G.LockSteeringConn = nil end
            showToast('Lock Steering OFF')
        end
    end
})

BikeLeft:AddDivider()

-- AnimTweaks + HitboxViewer moved to the General tab (universal player features)

BikeLeft:AddButton({
    Text = 'Kill Velocity',
    Func = function()
        local char = plr.Character
        local hrp  = char and char:FindFirstChild('HumanoidRootPart')
        if hrp then
            hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end
        local bikeModel = getBikeRoot()
        if bikeModel then
            for _, p in ipairs(bikeModel:GetDescendants()) do
                if p:IsA('BasePart') then
                    p.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
                    p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                end
            end
        end
        showToast('Velocity killed')
    end
})

local bikeCustGui       = nil  -- assigned when bike customization panel is built below
local partPickerGui     = nil  -- assigned when part picker panel is built below
local ppBuildTreePublic = nil  -- upvalue: ppBuildTree wired in from the part picker do-block

Right:AddDivider()

-- ---- Freeze Vehicle ----------------------------------------------------
Right:AddToggle('FreezeBike', {
    Text = 'Freeze Vehicle',
    Default = false,
    Callback = function(val)
        if val then
            -- explicit seated check (matches the Sticky / Lock Steering / Cruise pattern)
            local char = plr.Character
            local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
            local seat = hum and hum.SeatPart
            if not isVehicleSeat(seat) then
                showToast('Get on a ' .. VEHICLE_TERM .. ' first')
                Toggles.FreezeBike:SetValue(false)
                return
            end
            local bikeModel = seat.Parent
            _G.FrozenBikeParts = {}
            for _, p in ipairs(bikeModel:GetDescendants()) do
                if p:IsA('BasePart') then
                    _G.FrozenBikeParts[p] = p.AssemblyLinearVelocity
                    p.Anchored = true
                end
            end
            showToast('Vehicle frozen')
        else
            if _G.FrozenBikeParts then
                for p, vel in pairs(_G.FrozenBikeParts) do
                    pcall(function()
                        p.Anchored = false
                        p.AssemblyLinearVelocity = vel
                    end)
                end
                _G.FrozenBikeParts = nil
            end
            showToast('Vehicle unfrozen')
        end
    end
})

-- ---- Fly Mode ----------------------------------------------------------
Right:AddInput('FlySpeedInput', {
    Default = '60',
    Numeric = true,
    Finished = false,
    Text = 'Fly Speed (studs/s)',
})

Right:AddToggle('FlyMode', {
    Text = 'Fly Mode (WASD + E up / Q down)',
    Default = false,
    Callback = function(val)
        if val then
            _G.FlyConn = RunService.Heartbeat:Connect(function()
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not seat then return end
                local cam   = workspace.CurrentCamera
                local speed = (tonumber(Options.FlySpeedInput.Value) or 60) * MPH_TO_STUDS
                local fwd   = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
                if fwd.Magnitude > 0.001 then fwd = fwd.Unit end
                -- flatten right too so A/D stay horizontal regardless of camera pitch
                local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
                if right.Magnitude > 0.001 then right = right.Unit end
                local dir   = Vector3.new(0, 0, 0)
                if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + fwd                end
                if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - fwd                end
                if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - right              end
                if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + right              end
                if UIS:IsKeyDown(Enum.KeyCode.E) then dir = dir + Vector3.new(0,1,0) end
                if UIS:IsKeyDown(Enum.KeyCode.Q) then dir = dir - Vector3.new(0,1,0) end
                if dir.Magnitude > 0.01 then
                    seat.AssemblyLinearVelocity = dir.Unit * speed
                else
                    local vel = seat.AssemblyLinearVelocity
                    seat.AssemblyLinearVelocity = vel * 0.82
                end
            end)
            showToast('Fly ON  (WASD move, E up, Q down)')
        else
            if _G.FlyConn then _G.FlyConn:Disconnect(); _G.FlyConn = nil end
            showToast('Fly OFF')
        end
    end
})

-- ---- Anti-Fall ---------------------------------------------------------
Right:AddToggle('AntiFall', {
    Text = 'Anti-Fall',
    Default = false,
    Callback = function(val)
        if val then
            _G.AntiFallConn = RunService.Heartbeat:Connect(function()
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not seat then return end
                local cf = seat.CFrame
                -- rv.Y = sine of roll angle: 0 when upright, ±1 when fully tipped sideways
                local roll = cf.RightVector.Y
                if math.abs(roll) < 0.10 then return end  -- dead zone (~5.7 deg), preserves natural lean
                -- rebuild CFrame preserving LookVector (carries yaw + pitch), zero roll only
                local lv    = cf.LookVector
                local right = lv:Cross(Vector3.new(0, 1, 0))
                if right.Magnitude < 0.05 then return end  -- near-vertical edge case
                right = right.Unit
                local newUp = right:Cross(lv).Unit
                -- proportional lerp: gentle when barely tilted, capped lower for smoothness
                local alpha = math.clamp(math.abs(roll) * 0.3, 0.02, 0.16)
                seat.CFrame = cf:Lerp(CFrame.fromMatrix(cf.Position, right, newUp), alpha)
            end)
            showToast('Anti-Fall ON')
        else
            if _G.AntiFallConn then _G.AntiFallConn:Disconnect(); _G.AntiFallConn = nil end
            showToast('Anti-Fall OFF')
        end
    end
})

Right:AddDivider()

-- ---- Optimizer ---------------------------------------------------------
Right:AddToggle('Optimizer', {
    Text = 'Optimizer',
    Default = false,
    Callback = function(val)
        if val then
            local Lighting = game:GetService('Lighting')

            -- save originals
            local origShadows = Lighting.GlobalShadows
            local origFogEnd  = Lighting.FogEnd
            local origTerrain = nil

            -- 1. shadows off
            Lighting.GlobalShadows = false

            -- 2. push fog to horizon
            Lighting.FogEnd = 1e6

            -- 3. terrain decorations
            pcall(function()
                origTerrain = workspace.Terrain.Decoration
                workspace.Terrain.Decoration = false
            end)

            -- 4. reduce streaming radius so fewer chunks load when moving fast
            local origMinRadius    = nil
            local origTargetRadius = nil
            pcall(function()
                origMinRadius    = workspace.StreamingMinRadius
                origTargetRadius = workspace.StreamingTargetRadius
                workspace.StreamingMinRadius    = 32
                workspace.StreamingTargetRadius = 256
            end)

            -- 5. RenderFidelity=Performance on all parts (real GPU gain via lowest-LOD mesh)
            --    + CastShadow=false + disable particles
            local origFidelity      = {}
            local disabledParticles = {}

            local function onDescendantAdded(v)
                if v:IsA('BasePart') then
                    pcall(function()
                        origFidelity[v] = v.RenderFidelity
                        v.RenderFidelity = Enum.RenderFidelity.Performance
                        v.CastShadow    = false
                    end)
                elseif v:IsA('ParticleEmitter') or v:IsA('Smoke') or v:IsA('Fire')
                    or v:IsA('Sparkles') or v:IsA('Beam') then
                    if v.Enabled then
                        pcall(function() v.Enabled = false end)
                        table.insert(disabledParticles, v)
                    end
                end
            end

            for _, v in ipairs(workspace:GetDescendants()) do onDescendantAdded(v) end
            local particleConn = workspace.DescendantAdded:Connect(onDescendantAdded)

            -- 6. pause ALL other players' animations (bone transforms are CPU-heavy)
            --    runs every 30 frames to avoid per-frame overhead
            local frame = 0
            _G.OptimizerConn = RunService.Heartbeat:Connect(function()
                frame += 1
                if frame < 30 then return end
                frame = 0
                for _, p in ipairs(Players:GetPlayers()) do
                    if p == plr then continue end
                    local char = p.Character
                    if not char then continue end
                    local hum      = char:FindFirstChildWhichIsA('Humanoid')
                    local animator = hum and hum:FindFirstChildWhichIsA('Animator')
                    if animator then
                        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                            pcall(function() track:AdjustSpeed(0) end)
                        end
                    end
                end
            end)

            -- cleanup closure stored for disable path and SMCleanup
            _G.OptimizerCleanup = function()
                Lighting.GlobalShadows = origShadows
                Lighting.FogEnd        = origFogEnd
                pcall(function() workspace.Terrain.Decoration = origTerrain end)
                pcall(function()
                    if origMinRadius    then workspace.StreamingMinRadius    = origMinRadius    end
                    if origTargetRadius then workspace.StreamingTargetRadius = origTargetRadius end
                end)
                -- restore RenderFidelity + CastShadow on every part we touched
                for part, fidelity in pairs(origFidelity) do
                    pcall(function()
                        part.RenderFidelity = fidelity
                        part.CastShadow     = true
                    end)
                end
                -- re-enable particles
                for _, v in ipairs(disabledParticles) do
                    pcall(function() v.Enabled = true end)
                end
                pcall(function() particleConn:Disconnect() end)
                -- restore all other players' animation speeds to normal
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= plr then
                        local char = p.Character
                        if not char then continue end
                        local hum  = char:FindFirstChildWhichIsA('Humanoid')
                        local anim = hum and hum:FindFirstChildWhichIsA('Animator')
                        if anim then
                            for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                                pcall(function() track:AdjustSpeed(1) end)
                            end
                        end
                    end
                end
            end

            showToast('Optimizer ON')
        else
            if _G.OptimizerConn then _G.OptimizerConn:Disconnect(); _G.OptimizerConn = nil end
            if _G.OptimizerCleanup then _G.OptimizerCleanup(); _G.OptimizerCleanup = nil end
            showToast('Optimizer OFF')
        end
    end
})

Right:AddDivider()

-- ---- Jump Key ----------------------------------------------------------
Right:AddInput('JumpForceInput', {
    Default = '80',
    Numeric = true,
    Finished = false,
    Text = 'Jump Force (studs/s)',
})

Right:AddInput('JumpKeyInput', {
    Default  = 'G',
    Numeric  = false,
    Finished = false,
    Text     = 'Jump Key (e.g. G, H, F)',
})

_G.JumpKeyConn = UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local keyStr = (Options.JumpKeyInput and Options.JumpKeyInput.Value or 'G'):upper():gsub('%s+', '')
    local ok, kc = pcall(function() return Enum.KeyCode[keyStr] end)
    if not ok or kc == nil then return end
    if inp.KeyCode ~= kc then return end
    local _, bikeRoot = getBikeRoot()
    if not bikeRoot then return end
    local force = tonumber(Options.JumpForceInput.Value) or 80
    local vel   = bikeRoot.AssemblyLinearVelocity
    bikeRoot.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y + force, vel.Z)
end)

Right:AddDivider()

-- ---- Freecam ------------------------------------------------------------
-- Roblox-style detached camera. WASD + Q (down) + E (up) + Shift (sprint x3)
-- Mouse look while locked. Shift+P toggles, or use the toggle directly.
Right:AddInput('FreecamSpeedInput', {
    Default = '60',
    Numeric = true,
    Finished = false,
    Text = 'Freecam Speed (studs/s)',
})

local _freecamPrevType  = nil
local _freecamPrevMouse = nil
local _freecamYaw, _freecamPitch = 0, 0

Right:AddToggle('Freecam', {
    Text = 'Freecam (Shift+P to toggle)',
    Default = false,
    Callback = function(val)
        local cam = workspace.CurrentCamera
        if val then
            _freecamPrevType  = cam.CameraType
            _freecamPrevMouse = UIS.MouseBehavior
            cam.CameraType = Enum.CameraType.Scriptable
            -- seed yaw/pitch from the current camera so there's no snap on enable
            local lv = cam.CFrame.LookVector
            _freecamYaw   = math.atan2(-lv.X, -lv.Z)
            _freecamPitch = math.asin(math.clamp(lv.Y, -1, 1))
            local pos = cam.CFrame.Position
            UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
            _G.FreecamConn = RunService.RenderStepped:Connect(function(dt)
                local md = UIS:GetMouseDelta()
                local sens = 0.005
                _freecamYaw   = _freecamYaw   - md.X * sens
                _freecamPitch = math.clamp(_freecamPitch - md.Y * sens,
                                           -math.rad(89), math.rad(89))
                local lookCF = CFrame.fromEulerAnglesYXZ(_freecamPitch, _freecamYaw, 0)
                local speed  = (tonumber(Options.FreecamSpeedInput.Value) or 60)
                if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then speed = speed * 3 end
                local fwd   = lookCF.LookVector
                local right = lookCF.RightVector
                local move  = Vector3.new(0, 0, 0)
                if UIS:IsKeyDown(Enum.KeyCode.W) then move = move + fwd                end
                if UIS:IsKeyDown(Enum.KeyCode.S) then move = move - fwd                end
                if UIS:IsKeyDown(Enum.KeyCode.A) then move = move - right              end
                if UIS:IsKeyDown(Enum.KeyCode.D) then move = move + right              end
                if UIS:IsKeyDown(Enum.KeyCode.E) then move = move + Vector3.new(0,1,0) end
                if UIS:IsKeyDown(Enum.KeyCode.Q) then move = move - Vector3.new(0,1,0) end
                pos = pos + move * dt * speed
                cam.CFrame = CFrame.new(pos) * lookCF
            end)
            showToast('Freecam ON')
        else
            if _G.FreecamConn then _G.FreecamConn:Disconnect(); _G.FreecamConn = nil end
            UIS.MouseBehavior = _freecamPrevMouse or Enum.MouseBehavior.Default
            cam.CameraType = _freecamPrevType or Enum.CameraType.Custom
            showToast('Freecam OFF')
        end
    end
})

-- Shift+P keybind that flips the toggle (mirrors the in-menu toggle state)
_G.FreecamKeyConn = UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode ~= Enum.KeyCode.P then return end
    if not (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)) then return end
    if Toggles.Freecam then
        Toggles.Freecam:SetValue(not Toggles.Freecam.Value)
    end
end)

-- ---- Lock Character ---------------------------------------------------
-- Pairs nicely with Freecam: while flying around, your character stays put.
-- WASD / jump are sunk via ContextActionService at high priority,
-- and AutoRotate is killed so the camera can't spin the body.
Right:AddToggle('LockCharacter', {
    Text = 'Lock Character',
    Default = false,
    Tooltip = 'WASD, jump, and camera-look-rotation are blocked from affecting your character.',
    Callback = function(val)
        local CAS = game:GetService('ContextActionService')
        if val then
            local function sink() return Enum.ContextActionResult.Sink end
            pcall(function()
                CAS:BindActionAtPriority(
                    'KonstantLockChar',
                    sink, false,
                    Enum.ContextActionPriority.High.Value,
                    Enum.PlayerActions.CharacterForward,
                    Enum.PlayerActions.CharacterBackward,
                    Enum.PlayerActions.CharacterLeft,
                    Enum.PlayerActions.CharacterRight,
                    Enum.PlayerActions.CharacterJump
                )
            end)
            -- Fallback for forks that don't recognise PlayerActions: bind the raw keys too.
            pcall(function()
                CAS:BindActionAtPriority(
                    'KonstantLockCharKeys',
                    sink, false,
                    Enum.ContextActionPriority.High.Value,
                    Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
                    Enum.KeyCode.Space
                )
            end)

            -- Kill AutoRotate so the camera can't spin the character body.
            local function applyLock(char)
                local hum = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                _G.LockCharAutoRotate = hum.AutoRotate  -- remember original on first apply
                hum.AutoRotate = false
            end
            applyLock(plr.Character)
            _G.LockCharConn = plr.CharacterAdded:Connect(function(char)
                task.wait(0.2)  -- let Humanoid finish loading
                applyLock(char)
            end)
            showToast('Character locked')
        else
            pcall(function() CAS:UnbindAction('KonstantLockChar') end)
            pcall(function() CAS:UnbindAction('KonstantLockCharKeys') end)
            if _G.LockCharConn then _G.LockCharConn:Disconnect(); _G.LockCharConn = nil end
            -- restore AutoRotate (default true if we never captured one)
            local char = plr.Character
            local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
            if hum then
                if _G.LockCharAutoRotate ~= nil then
                    hum.AutoRotate = _G.LockCharAutoRotate
                else
                    hum.AutoRotate = true
                end
            end
            _G.LockCharAutoRotate = nil
            showToast('Character unlocked')
        end
    end
})

Right:AddDivider()

-- Rainbow Bike moved into the Bike Customization panel.

Right:AddButton({
    Text = VEHICLE_TERM_CAP .. ' Customization',
    Func = function()
        if bikeCustGui then
            bikeCustGui.Enabled = not bikeCustGui.Enabled
        else
            showToast('Customization panel did not build - check console (F9) for error')
            warn('Konstant: bikeCustGui is nil - init aborted before customization panel was built')
        end
    end
})


-- ============================================================
-- MAPS TAB
-- ============================================================

local HttpService = game:GetService('HttpService')
local MPS        = game:GetService('MarketplaceService')

-- ============================================================
-- PASSWORD GATE MODULE
-- Spawns a modal overlay, yields the calling coroutine until
-- the player confirms or cancels. Returns true only when the
-- hardcoded password is entered correctly.
-- ============================================================
local PasswordGate = (function()
    local CORRECT = 'LSEAutomated'

    local function ask()
        local signal = Instance.new('BindableEvent')
        local result = false

        local psg = Instance.new('ScreenGui')
        psg.Name           = 'PasswordGateGui'
        psg.ResetOnSpawn   = false
        psg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        psg.DisplayOrder   = 100
        safeParentGui(psg)

        -- card pinned to top-center
        local card = Instance.new('Frame')
        card.Size             = UDim2.new(0, 320, 0, 130)
        card.Position         = UDim2.new(0.5, -160, 0, 12)
        card.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
        card.BorderSizePixel  = 1
        card.BorderColor3     = Color3.fromRGB(60, 60, 60)
        card.ZIndex           = 2
        card.Parent           = psg

        local title = Instance.new('TextLabel')
        title.Size                 = UDim2.new(1, 0, 0, 28)
        title.Position             = UDim2.new(0, 0, 0, 0)
        title.BackgroundColor3     = Color3.fromRGB(35, 35, 35)
        title.BorderSizePixel      = 0
        title.Text                 = 'Password Required'
        title.TextColor3           = Color3.fromRGB(210, 210, 210)
        title.Font                 = Enum.Font.SourceSans
        title.TextSize             = 14
        title.TextXAlignment       = Enum.TextXAlignment.Left
        title.ZIndex               = 3
        title.Parent               = card
        -- left padding via inner label offset
        title.Position             = UDim2.new(0, 8, 0, 0)
        title.Size                 = UDim2.new(1, -8, 0, 28)

        local box = Instance.new('TextBox')
        box.Size             = UDim2.new(1, -16, 0, 28)
        box.Position         = UDim2.new(0, 8, 0, 36)
        box.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
        box.BorderSizePixel  = 1
        box.BorderColor3     = Color3.fromRGB(55, 55, 55)
        box.TextColor3       = Color3.fromRGB(200, 200, 200)
        box.PlaceholderText  = 'enter password'
        box.PlaceholderColor3 = Color3.fromRGB(75, 75, 75)
        box.Text             = ''
        box.Font             = Enum.Font.SourceSans
        box.TextSize         = 14
        box.ClearTextOnFocus = false
        box.ZIndex           = 3
        box.Parent           = card

        local status = Instance.new('TextLabel')
        status.Size              = UDim2.new(1, -16, 0, 14)
        status.Position          = UDim2.new(0, 8, 0, 70)
        status.BackgroundTransparency = 1
        status.Text              = ''
        status.TextColor3        = Color3.fromRGB(200, 70, 70)
        status.Font              = Enum.Font.SourceSans
        status.TextSize          = 13
        status.TextXAlignment    = Enum.TextXAlignment.Left
        status.ZIndex            = 3
        status.Parent            = card

        local confirmBtn = Instance.new('TextButton')
        confirmBtn.Size             = UDim2.new(0, 100, 0, 26)
        confirmBtn.Position         = UDim2.new(0, 8, 0, 96)
        confirmBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        confirmBtn.BorderSizePixel  = 1
        confirmBtn.BorderColor3     = Color3.fromRGB(80, 80, 80)
        confirmBtn.Text             = 'Confirm'
        confirmBtn.TextColor3       = Color3.fromRGB(210, 210, 210)
        confirmBtn.Font             = Enum.Font.SourceSans
        confirmBtn.TextSize         = 14
        confirmBtn.ZIndex           = 3
        confirmBtn.Parent           = card

        local cancelBtn = Instance.new('TextButton')
        cancelBtn.Size             = UDim2.new(0, 100, 0, 26)
        cancelBtn.Position         = UDim2.new(1, -108, 0, 96)
        cancelBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        cancelBtn.BorderSizePixel  = 1
        cancelBtn.BorderColor3     = Color3.fromRGB(65, 65, 65)
        cancelBtn.Text             = 'Cancel'
        cancelBtn.TextColor3       = Color3.fromRGB(150, 150, 150)
        cancelBtn.Font             = Enum.Font.SourceSans
        cancelBtn.TextSize         = 14
        cancelBtn.ZIndex           = 3
        cancelBtn.Parent           = card

        local function cleanup(ok)
            result = ok
            psg:Destroy()
            signal:Fire()
        end

        confirmBtn.MouseButton1Click:Connect(function()
            if box.Text == CORRECT then
                cleanup(true)
            else
                status.Text = 'wrong password'
                box.Text    = ''
            end
        end)

        box.FocusLost:Connect(function(enterPressed)
            if not enterPressed then return end
            if box.Text == CORRECT then
                cleanup(true)
            else
                status.Text = 'wrong password'
                box.Text    = ''
            end
        end)

        cancelBtn.MouseButton1Click:Connect(function()
            cleanup(false)
        end)

        signal.Event:Wait()
        signal:Destroy()
        return result
    end

    return { ask = ask }
end)()

local loadedMaps = {}
local lastMapPos = nil

-- fixed slots: same coords for everyone so friends loading the same map end up together
-- spaced 12000 studs apart so even large maps never overlap; within safe Roblox float range
local MAP_SLOTS = {
    {x =  8000, z =  8000},  -- slot 1
    {x = 20000, z =  8000},  -- slot 2
    {x = 32000, z =  8000},  -- slot 3
}

-- Aero build: only Clone + Export map tools are available. Full asset-load
-- and teleport-to-slot UI are supermoto-specific and live in tes.lua.
-- Grab the current game's map, save it to your PC via the executor file
-- system, then import it next time you're in a game that supports it.
local MAP_SAVE_FOLDER = 'SuperMotoMaps'

-- ---- helpers -----------------------------------------------------------
local function c3(col) -- Color3 -> {r,g,b} 0-255
    return math.floor(col.R*255+0.5), math.floor(col.G*255+0.5), math.floor(col.B*255+0.5)
end
local function fc(r,g,b) return Color3.fromRGB(r,g,b) end

-- ---- serialise ---------------------------------------------------------
-- Walks every BasePart and serialises: geometry, appearance, surface types,
-- physical properties, and supported children (Decal, Texture,
-- SurfaceAppearance, lights, Sound).
-- Positions stored as-is; importer auto-recentres at the target slot.
local function exportMap(mapEntry)
    if type(writefile) ~= 'function' then
        showToast('Executor has no file-write support')
        return
    end

    local parts = {}
    for _, part in ipairs(mapEntry.obj:GetDescendants()) do
        if not part:IsA('BasePart') then continue end
        pcall(function()
            local cf = part.CFrame
            local rv, uv, lv = cf.RightVector, cf.UpVector, cf.LookVector
            local pr, pg, pb = c3(part.Color)
            local e = {
                cls = part.ClassName,
                cx  = math.floor(cf.X*1000+0.5)/1000,
                cy  = math.floor(cf.Y*1000+0.5)/1000,
                cz  = math.floor(cf.Z*1000+0.5)/1000,
                r00=math.floor(rv.X*1e6+0.5)/1e6, r01=math.floor(rv.Y*1e6+0.5)/1e6, r02=math.floor(rv.Z*1e6+0.5)/1e6,
                r10=math.floor(uv.X*1e6+0.5)/1e6, r11=math.floor(uv.Y*1e6+0.5)/1e6, r12=math.floor(uv.Z*1e6+0.5)/1e6,
                r20=math.floor(lv.X*1e6+0.5)/1e6, r21=math.floor(lv.Y*1e6+0.5)/1e6, r22=math.floor(lv.Z*1e6+0.5)/1e6,
                sx=part.Size.X, sy=part.Size.Y, sz=part.Size.Z,
                r=pr, g=pg, b=pb,
                mat = part.Material.Name,
                tr  = part.Transparency,
                ref = part.Reflectance,
                cs  = part.CastShadow and 1 or 0,
                ts  = part.TopSurface.Name,
                bos = part.BottomSurface.Name,
                fs  = part.FrontSurface.Name,
                bks = part.BackSurface.Name,
                ls  = part.LeftSurface.Name,
                rs  = part.RightSurface.Name,
            }
            -- optional properties that may not exist on all instances
            pcall(function() e.ds    = part.DoubleSided and 1 or 0 end)
            pcall(function() e.shape = part.Shape.Name end)
            pcall(function()
                local cpp = part.CustomPhysicalProperties
                if cpp then
                    e.cpp = { d=cpp.Density, f=cpp.Friction, el=cpp.Elasticity,
                              fw=cpp.FrictionWeight, ew=cpp.ElasticityWeight }
                end
            end)
            -- children: each wrapped individually so one bad child doesn't skip the rest
            local ch = {}
            for _, kid in ipairs(part:GetChildren()) do
                pcall(function()
                    if kid:IsA('SpecialMesh') and kid.MeshId ~= '' then
                        table.insert(ch, { t='SM', mid=kid.MeshId, tex=kid.TextureId,
                            sx=kid.Scale.X, sy=kid.Scale.Y, sz=kid.Scale.Z })
                    elseif kid:IsA('SurfaceAppearance') then
                        local sr,sg,sb = c3(kid.Color)
                        local entry = { t='SA', r=sr,g=sg,b=sb }
                        pcall(function() entry.alb   = kid.AlbedoMap    end)
                        pcall(function() entry.norm  = kid.NormalMap    end)
                        pcall(function() entry.met   = kid.MetalnessMap end)
                        pcall(function() entry.rough = kid.RoughnessMap end)
                        table.insert(ch, entry)
                    elseif kid:IsA('Decal') then
                        local dr,dg,db = c3(kid.Color3)
                        table.insert(ch, { t='D', face=kid.Face.Name, tex=kid.Texture,
                            tr=kid.Transparency, r=dr,g=dg,b=db })
                    elseif kid:IsA('Texture') then
                        local txr,txg,txb = c3(kid.Color3)
                        table.insert(ch, { t='TX', face=kid.Face.Name, tex=kid.Texture,
                            tr=kid.Transparency, r=txr,g=txg,b=txb,
                            su=kid.StudsPerTileU, sv=kid.StudsPerTileV,
                            ou=kid.OffsetStudsU,  ov=kid.OffsetStudsV })
                    elseif kid:IsA('PointLight') then
                        local lr,lg,lb = c3(kid.Color)
                        table.insert(ch, { t='PL', br=kid.Brightness, range=kid.Range,
                            r=lr,g=lg,b=lb, shad=kid.Shadows and 1 or 0, en=kid.Enabled and 1 or 0 })
                    elseif kid:IsA('SpotLight') then
                        local lr,lg,lb = c3(kid.Color)
                        table.insert(ch, { t='SL', br=kid.Brightness, range=kid.Range,
                            angle=kid.Angle, face=kid.Face.Name,
                            r=lr,g=lg,b=lb, shad=kid.Shadows and 1 or 0, en=kid.Enabled and 1 or 0 })
                    elseif kid:IsA('SurfaceLight') then
                        local lr,lg,lb = c3(kid.Color)
                        table.insert(ch, { t='SFL', br=kid.Brightness, range=kid.Range,
                            angle=kid.Angle, face=kid.Face.Name,
                            r=lr,g=lg,b=lb, shad=kid.Shadows and 1 or 0, en=kid.Enabled and 1 or 0 })
                    elseif kid:IsA('Sound') then
                        table.insert(ch, { t='SND', sid=kid.SoundId, vol=kid.Volume,
                            pitch=kid.PlaybackSpeed, loop=kid.Looped and 1 or 0 })
                    end
                end)
            end
            if #ch > 0 then e.ch = ch end
            table.insert(parts, e)
        end)
    end

    if #parts == 0 then showToast('Nothing to export') return end

    local json = HttpService:JSONEncode({ v=2, game=mapEntry.name, parts=parts })

    pcall(function()
        if type(isfolder)=='function' and not isfolder(MAP_SAVE_FOLDER) then
            if type(makefolder)=='function' then makefolder(MAP_SAVE_FOLDER) end
        end
    end)

    local filename = mapEntry.name:gsub('[^%w%-]','_'):sub(1,40) .. '.json'
    local ok, err  = pcall(writefile, MAP_SAVE_FOLDER..'/'..filename, json)
    if ok then
        showToast('Saved '..#parts..' parts  ->  '..filename)
    else
        showToast('Export failed: '..tostring(err))
    end
end

-- ---- deserialise -------------------------------------------------------
local function importMap(jsonStr, slot)
    local ok, data = pcall(function() return HttpService:JSONDecode(jsonStr) end)
    if not ok or not data or not data.parts or #data.parts == 0 then
        showToast('Could not parse file')
        return
    end

    local spawnX = MAP_SLOTS[slot].x
    local spawnZ = MAP_SLOTS[slot].z

    local minX, minZ =  math.huge,  math.huge
    local maxX, maxZ = -math.huge, -math.huge
    for _, e in ipairs(data.parts) do
        if e.cx < minX then minX = e.cx end
        if e.cx > maxX then maxX = e.cx end
        if e.cz < minZ then minZ = e.cz end
        if e.cz > maxZ then maxZ = e.cz end
    end
    local offX = spawnX - (minX+maxX)/2
    local offZ = spawnZ - (minZ+maxZ)/2

    local folder = Instance.new('Folder')
    folder.Name  = 'ImportedMap_'..slot

    local count = 0
    for _, e in ipairs(data.parts) do
        pcall(function()
            -- part class
            local part
            if e.cls == 'WedgePart' then
                part = Instance.new('WedgePart')
            elseif e.cls == 'CornerWedgePart' then
                part = Instance.new('CornerWedgePart')
            else
                part = Instance.new('Part')  -- MeshPart falls back to Part
            end

            -- geometry
            part.CFrame = CFrame.new(
                e.cx+offX, e.cy, e.cz+offZ,
                e.r00, e.r01, e.r02,
                e.r10, e.r11, e.r12,
                e.r20, e.r21, e.r22
            )
            part.Size = Vector3.new(e.sx, e.sy, e.sz)

            -- appearance
            part.Color        = fc(e.r, e.g, e.b)
            part.Transparency = e.tr  or 0
            part.Reflectance  = e.ref or 0
            part.CastShadow   = e.cs ~= 0
            if e.ds ~= nil then pcall(function() part.DoubleSided = e.ds ~= 0 end) end
            pcall(function() part.Material = Enum.Material[e.mat] end)
            if e.shape and e.shape ~= 'Block' then
                pcall(function() part.Shape = Enum.PartType[e.shape] end)
            end

            -- surface types
            pcall(function() part.TopSurface    = Enum.SurfaceType[e.ts]  end)
            pcall(function() part.BottomSurface = Enum.SurfaceType[e.bos] end)
            pcall(function() part.FrontSurface  = Enum.SurfaceType[e.fs]  end)
            pcall(function() part.BackSurface   = Enum.SurfaceType[e.bks] end)
            pcall(function() part.LeftSurface   = Enum.SurfaceType[e.ls]  end)
            pcall(function() part.RightSurface  = Enum.SurfaceType[e.rs]  end)

            -- custom physical properties
            if e.cpp then
                pcall(function()
                    part.CustomPhysicalProperties = PhysicalProperties.new(
                        e.cpp.d, e.cpp.f, e.cpp.el, e.cpp.fw, e.cpp.ew)
                end)
            end

            part.Anchored   = true
            part.CanCollide = true

            -- children
            if e.ch then
                for _, c in ipairs(e.ch) do
                    pcall(function()
                        if c.t == 'SM' then
                            local sm = Instance.new('SpecialMesh')
                            sm.MeshType  = Enum.MeshType.FileMesh
                            sm.MeshId    = c.mid
                            sm.TextureId = c.tex or ''
                            sm.Scale     = Vector3.new(c.sx or 1, c.sy or 1, c.sz or 1)
                            sm.Parent    = part
                        elseif c.t == 'SA' then
                            local sa = Instance.new('SurfaceAppearance')
                            sa.AlbedoMap    = c.alb   or ''
                            sa.NormalMap    = c.norm  or ''
                            sa.MetalnessMap = c.met   or ''
                            sa.RoughnessMap = c.rough or ''
                            sa.Color        = fc(c.r, c.g, c.b)
                            sa.Parent       = part
                        elseif c.t == 'D' then
                            local d = Instance.new('Decal')
                            pcall(function() d.Face = Enum.NormalId[c.face] end)
                            d.Texture      = c.tex or ''
                            d.Transparency = c.tr  or 0
                            d.Color3       = fc(c.r, c.g, c.b)
                            d.Parent       = part
                        elseif c.t == 'TX' then
                            local tx = Instance.new('Texture')
                            pcall(function() tx.Face = Enum.NormalId[c.face] end)
                            tx.Texture       = c.tex or ''
                            tx.Transparency  = c.tr  or 0
                            tx.Color3        = fc(c.r, c.g, c.b)
                            tx.StudsPerTileU = c.su or 1
                            tx.StudsPerTileV = c.sv or 1
                            tx.OffsetStudsU  = c.ou or 0
                            tx.OffsetStudsV  = c.ov or 0
                            tx.Parent        = part
                        elseif c.t == 'PL' then
                            local l = Instance.new('PointLight')
                            l.Brightness = c.br or 1
                            l.Range      = c.range or 20
                            l.Color      = fc(c.r, c.g, c.b)
                            l.Shadows    = c.shad ~= 0
                            l.Enabled    = c.en   ~= 0
                            l.Parent     = part
                        elseif c.t == 'SL' then
                            local l = Instance.new('SpotLight')
                            l.Brightness = c.br or 1
                            l.Range      = c.range or 20
                            l.Angle      = c.angle or 45
                            pcall(function() l.Face = Enum.NormalId[c.face] end)
                            l.Color      = fc(c.r, c.g, c.b)
                            l.Shadows    = c.shad ~= 0
                            l.Enabled    = c.en   ~= 0
                            l.Parent     = part
                        elseif c.t == 'SFL' then
                            local l = Instance.new('SurfaceLight')
                            l.Brightness = c.br or 1
                            l.Range      = c.range or 20
                            l.Angle      = c.angle or 45
                            pcall(function() l.Face = Enum.NormalId[c.face] end)
                            l.Color      = fc(c.r, c.g, c.b)
                            l.Shadows    = c.shad ~= 0
                            l.Enabled    = c.en   ~= 0
                            l.Parent     = part
                        elseif c.t == 'SND' then
                            local s = Instance.new('Sound')
                            s.SoundId        = c.sid   or ''
                            s.Volume         = c.vol   or 1
                            s.PlaybackSpeed  = c.pitch or 1
                            s.Looped         = c.loop  ~= 0
                            s.Parent         = part
                        end
                    end)
                end
            end

            part.Parent = folder
            count += 1
        end)
    end

    folder.Parent = workspace
    local name = data.game or ('Imported Map '..slot)
    table.insert(loadedMaps, {obj=folder, name=name, x=spawnX, z=spawnZ})
    lastMapPos = Vector3.new(spawnX, 20, spawnZ)
    showToast('Imported '..count..' parts  ->  slot '..slot..'  ('..name..')')
end

-- ---- teleport helper --------------------------------------------------
-- Picks a random BasePart from the map folder and lands the player 5 studs
-- above its top face. Guaranteed to hit something that exists.
local function teleportOntoMap(entry)
    local char = plr.Character
    local hrp  = char and char:FindFirstChild('HumanoidRootPart')
    if not hrp then return end

    local parts = {}
    for _, p in ipairs(entry.obj:GetDescendants()) do
        if p:IsA('BasePart') then
            table.insert(parts, p)
        end
    end

    if #parts == 0 then showToast('Map has no parts') return end

    local picked = parts[math.random(1, #parts)]
    local topY   = picked.Position.Y + picked.Size.Y / 2
    hrp.CFrame   = CFrame.new(picked.Position.X, topY + 5, picked.Position.Z)
    showToast('Teleported to ' .. entry.name)
end

-- ---- clone -------------------------------------------------------------
local MapLeft  = Tabs.Maps:AddLeftGroupbox('Load')
local MapRight = Tabs.Maps:AddRightGroupbox('Manage')

local function cloneCurrentMap()
    local slot = #loadedMaps + 1
    if slot > #MAP_SLOTS then
        showToast('Max 3 maps loaded - clear one first')
        return
    end

    local spawnX = MAP_SLOTS[slot].x
    local spawnZ = MAP_SLOTS[slot].z

    local charSet = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then charSet[p.Character] = true end
    end

    showToast('Cloning map... may take a moment')
    task.spawn(function()
        local folder = Instance.new('Folder')
        folder.Name  = 'ClonedMap_' .. slot

        local partCount = 0
        local objCount  = 0
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA('Terrain') or obj:IsA('Camera') or charSet[obj] then continue end

            local ok, clone = pcall(function() return obj:Clone() end)
            if not ok or not clone then continue end

            -- shift every BasePart inside the clone to the slot offset
            for _, part in ipairs(clone:GetDescendants()) do
                if part:IsA('BasePart') then
                    part.CFrame     = part.CFrame + Vector3.new(spawnX, 0, spawnZ)
                    part.Anchored   = true
                    part.CanCollide = true
                    partCount += 1
                end
            end
            -- handle the case where the top-level clone is itself a BasePart
            if clone:IsA('BasePart') then
                clone.CFrame     = clone.CFrame + Vector3.new(spawnX, 0, spawnZ)
                clone.Anchored   = true
                clone.CanCollide = true
                partCount += 1
            end

            clone.Parent = folder
            objCount += 1
        end

        if objCount == 0 then
            folder:Destroy()
            showToast('Nothing to clone')
            return
        end

        folder.Parent = workspace

        -- copy terrain voxels from around the player to the slot offset.
        -- ReadVoxels captures the actual terrain data; WriteVoxels stamps it
        -- at the new location. done at resolution 4 (fine enough for riding on).
        local terrainRegion = nil
        pcall(function()
            local hrpT = plr.Character and plr.Character:FindFirstChild('HumanoidRootPart')
            if not hrpT then return end
            local pos = hrpT.Position
            local RANGE = 500
            local RES   = 4
            local function snap(v) return math.floor(v / RES) * RES end
            local srcMin = Vector3.new(snap(pos.X - RANGE), snap(-150), snap(pos.Z - RANGE))
            local srcMax = Vector3.new(snap(pos.X + RANGE), snap(600),  snap(pos.Z + RANGE))
            local srcRgn = Region3.new(srcMin, srcMax)
            local mats, occs = workspace.Terrain:ReadVoxels(srcRgn, RES)
            local dstMin = Vector3.new(srcMin.X + spawnX, srcMin.Y, srcMin.Z + spawnZ)
            local dstMax = Vector3.new(srcMax.X + spawnX, srcMax.Y, srcMax.Z + spawnZ)
            local dstRgn = Region3.new(dstMin, dstMax)
            workspace.Terrain:WriteVoxels(dstRgn, RES, mats, occs)
            terrainRegion = dstRgn
        end)

        local gameName = 'Cloned Map ' .. slot
        pcall(function()
            local info = MPS:GetProductInfo(game.PlaceId)
            if info and info.Name then gameName = info.Name end
        end)

        table.insert(loadedMaps, {obj = folder, name = gameName, x = spawnX, z = spawnZ, terrainRegion = terrainRegion})
        lastMapPos = Vector3.new(spawnX, 20, spawnZ)
        local terrainNote = terrainRegion and '  + terrain' or ''
        showToast('Cloned ' .. partCount .. ' parts across ' .. objCount .. ' models' .. terrainNote .. '  ->  slot ' .. slot)
    end)
end

MapLeft:AddButton({
    Text = 'Clone Current Map',
    Func = function()
        if not PasswordGate.ask() then return end
        cloneCurrentMap()
    end,
})

-- Universal teleport: works on cloned maps (Aero) and asset-loaded maps (Supermoto).
MapLeft:AddButton({
    Text = 'Teleport to Last Map',
    Func = function()
        if #loadedMaps == 0 then showToast('No map loaded yet') return end
        teleportOntoMap(loadedMaps[#loadedMaps])
    end
})

-- Export + cleanup available in every game
MapRight:AddButton({
    Text = 'Export Last Map',
    Func = function()
        if not PasswordGate.ask() then return end
        if #loadedMaps == 0 then showToast('No maps loaded') return end
        task.spawn(function() exportMap(loadedMaps[#loadedMaps]) end)
    end
})

MapRight:AddDivider()

local function clearMapEntry(entry)
    pcall(function() entry.obj:Destroy() end)
    if entry.terrainRegion then
        pcall(function()
            workspace.Terrain:FillBlock(
                CFrame.new(entry.terrainRegion.CFrame.Position),
                entry.terrainRegion.Size,
                Enum.Material.Air
            )
        end)
    end
end

MapRight:AddButton({
    Text = 'Remove Last Map',
    Func = function()
        if #loadedMaps == 0 then showToast('No maps to remove') return end
        local entry = table.remove(loadedMaps)
        clearMapEntry(entry)
        lastMapPos = loadedMaps[#loadedMaps] and Vector3.new(loadedMaps[#loadedMaps].x, 20, loadedMaps[#loadedMaps].z) or nil
        showToast('Removed: ' .. entry.name)
    end
})

MapRight:AddButton({
    Text = 'Clear All Maps',
    Func = function()
        for _, entry in ipairs(loadedMaps) do
            clearMapEntry(entry)
        end
        loadedMaps = {}
        lastMapPos = nil
        showToast('All maps cleared')
    end
})


-- ============================================================
-- TROLL TAB
-- ============================================================

local exitBike = function()
    local char = plr.Character
    if not char then return end
    for _, v in pairs(workspace:GetDescendants()) do
        if isVehicleSeat(v) and v.Occupant and v.Occupant.Parent == char then
            local bikeNameVal = v.Parent:FindFirstChild('BikeName', true)
            if bikeNameVal and bikeNameVal.Value ~= '' then
                pcall(function() RS.DeleteBikeNew:FireServer(bikeNameVal.Value) end)
                pcall(function() RS.Remotes.DeleteBikeNew:FireServer(bikeNameVal.Value) end)
            end
            task.wait(0.5)
            return
        end
    end
end

local savedFlingPos = nil

local function savePos()
    local char = plr.Character
    local hrp = char and char:FindFirstChild('HumanoidRootPart')
    if hrp then savedFlingPos = hrp.CFrame end
end

local function returnToSaved()
    local char = plr.Character
    local hrp = char and char:FindFirstChild('HumanoidRootPart')
    if hrp and savedFlingPos then
        hrp.CFrame = savedFlingPos
        hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
    savedFlingPos = nil
end

local flingOne -- forward declare
flingOne = function(target)
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild('HumanoidRootPart')
    if not hrp then return end

    local targetChar = target.Character
    if not targetChar then return end

    -- prefer bike root over character HRP
    local targetRoot = targetChar:FindFirstChild('HumanoidRootPart')
    if not targetRoot then return end
    for _, v in pairs(workspace:GetDescendants()) do
        if isVehicleSeat(v) and v.Occupant
        and v.Occupant.Parent == targetChar then
            local r = v.Parent:FindFirstChildWhichIsA('BasePart')
            if r then targetRoot = r end
            break
        end
    end

    showToast('Flinging: ' .. target.Name)

    local deadline = tick() + 3
    local movel    = 0.1

    while tick() < deadline and not _G.FlingStop do
        if not targetRoot.Parent then break end

        -- teleport directly onto the target every frame
        hrp.CFrame = CFrame.new(targetRoot.Position + Vector3.new(0, 1, 0))

        -- touch fling: spike for exactly one render frame then restore
        RunService.Heartbeat:Wait()
        local vel = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = vel * 1e35 + Vector3.new(0, 1e35, 0)
        RunService.RenderStepped:Wait()
        hrp.AssemblyLinearVelocity = vel
        RunService.Stepped:Wait()
        hrp.AssemblyLinearVelocity = vel + Vector3.new(0, movel, 0)
        movel = -movel
    end

    hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
    hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
end

local function findPlayers(query)
    query = query:lower()
    local results = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr then
            if p.Name:lower():find(query, 1, true)
            or p.DisplayName:lower():find(query, 1, true) then
                table.insert(results, p)
            end
        end
    end
    return results
end

local function getBikeRiders()
    local riders = {}
    local seen = {}
    for _, v in pairs(workspace:GetDescendants()) do
        if isVehicleSeat(v) and v.Occupant then
            local p = Players:GetPlayerFromCharacter(v.Occupant.Parent)
            if p and p ~= plr and not seen[p] then
                seen[p] = true
                table.insert(riders, p)
            end
        end
    end
    return riders
end

-- assign to the forward-declared upvalues so the Bikes tab toggle shares them
clearHitboxes = function()
    for _, list in pairs(hitboxMap) do
        for _, sb in ipairs(list) do pcall(function() sb:Destroy() end) end
    end
    hitboxMap = {}
end

refreshHitboxes = function()
    clearHitboxes()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Character then
            hitboxMap[p] = {}
            for _, part in ipairs(p.Character:GetDescendants()) do
                if part:IsA('BasePart') then
                    local sb = Instance.new('SelectionBox')
                    sb.Adornee             = part
                    sb.Color3              = Color3.fromRGB(255, 50, 50)
                    sb.LineThickness       = 0.05
                    sb.SurfaceTransparency = 0.85
                    sb.SurfaceColor3       = Color3.fromRGB(255, 50, 50)
                    sb.Parent              = workspace
                    table.insert(hitboxMap[p], sb)
                end
            end
        end
    end
end

local TrollLeft  = Tabs.General:AddLeftGroupbox('Fling')
local TrollRight = Tabs.General:AddRightGroupbox('ESP & Players')

-- Fling target input + Fling User button live next to the rest of the fling actions
TrollLeft:AddInput('FlingTarget', {
    Default = '',
    Numeric = false,
    Finished = false,
    Text = 'Username or display name',
})

TrollLeft:AddButton({
    Text = 'Fling User',
    Func = function()
        local query = Options.FlingTarget.Value
        if query == '' then showToast('Enter a name first') return end

        local results = findPlayers(query)

        if #results == 0 then
            showToast('No player found: ' .. query)
        elseif #results > 1 then
            local names = {}
            for _, p in ipairs(results) do table.insert(names, p.Name) end
            showToast('Multiple results: ' .. table.concat(names, ', '))
        else
            _G.FlingStop = false
            savePos()
            exitBike()
            task.spawn(function()
                task.wait(0.6)
                flingOne(results[1])
                returnToSaved()
            end)
        end
    end
})

TrollLeft:AddButton({
    Text = 'Fling All',
    Func = function()
        local targets = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= plr then table.insert(targets, p) end
        end
        if #targets == 0 then showToast('No other players') return end

        _G.FlingStop = false
        savePos()
        exitBike()
        task.spawn(function()
            task.wait(0.6)
            for _, target in ipairs(targets) do
                if _G.FlingStop then break end
                flingOne(target)
            end
            returnToSaved()
            if not _G.FlingStop then
                showToast('Fling All done')
            end
        end)
    end
})

TrollLeft:AddToggle('AutoFling', {
    Text = 'Auto-Fling',
    Default = false,
    Callback = function(val)
        if val then
            _G.FlingStop = false
            savePos()
            exitBike()
            task.spawn(function()
                task.wait(0.6)
                local noTargetTime = 0
                while Toggles.AutoFling.Value do
                    local riders = getBikeRiders()
                    if #riders > 0 then
                        noTargetTime = 0
                        for _, target in ipairs(riders) do
                            if not Toggles.AutoFling.Value or _G.FlingStop then break end
                            flingOne(target)
                        end
                    else
                        noTargetTime += 0.5
                        if noTargetTime >= 3 then
                            returnToSaved()
                            noTargetTime = 0
                        end
                    end
                    task.wait(0.5)
                end
                returnToSaved()
            end)
        else
            _G.FlingStop = true
        end
    end
})

TrollLeft:AddButton({
    Text = 'Stop',
    Func = function()
        _G.FlingStop = true
        Toggles.AutoFling:SetValue(false)
        Toggles.TouchFling:SetValue(false)
        returnToSaved()
        showToast('Stopped')
    end
})

TrollLeft:AddDivider()

TrollLeft:AddToggle('TouchFling', {
    Text = 'Touch Fling',
    Default = false,
    Callback = function(val)
        if val then
            task.spawn(function()
                local movel = 0.1
                while Toggles.TouchFling.Value do
                    local char = plr.Character
                    local hrp  = char and char:FindFirstChild('HumanoidRootPart')
                    if hrp then
                        RunService.Heartbeat:Wait()
                        local vel = hrp.AssemblyLinearVelocity
                        hrp.AssemblyLinearVelocity = vel * 1e35 + Vector3.new(0, 1e35, 0)
                        RunService.RenderStepped:Wait()
                        hrp.AssemblyLinearVelocity = vel
                        RunService.Stepped:Wait()
                        hrp.AssemblyLinearVelocity = vel + Vector3.new(0, movel, 0)
                        movel = -movel
                    else
                        task.wait(0.1)
                    end
                end
            end)
        end
    end
})

-- ============================================================
-- ESP / Player visuals (lives in the General tab's right groupbox)
-- ============================================================

local ESPLeft = TrollRight  -- alias: ESP toggles land in the General right groupbox

ESPLeft:AddInput('AdminNames', {
    Default  = '',
    Numeric  = false,
    Finished = false,
    Text     = 'Admin Names (comma-sep)',
})

local function isAdmin(player)
    if player.UserId == game.CreatorId then return true end
    local input = Options.AdminNames and Options.AdminNames.Value or ''
    for name in (input .. ','):gmatch('([^,]+),') do
        name = name:match('^%s*(.-)%s*$')
        if name ~= '' and player.Name:lower():find(name:lower(), 1, true) then
            return true
        end
    end
    return false
end

local adminBoxMap = {}
local function clearAdminESP()
    for _, data in pairs(adminBoxMap) do
        pcall(function() if data.box  then data.box:Destroy()  end end)
        pcall(function() if data.bill then data.bill:Destroy() end end)
    end
    adminBoxMap = {}
end

local function refreshAdminESP()
    clearAdminESP()
    if not Toggles.AdminESP or not Toggles.AdminESP.Value then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == plr then continue end
        if not isAdmin(p) then continue end
        local char = p.Character
        if not char then continue end
        local hrp = char:FindFirstChild('HumanoidRootPart')
        if not hrp then continue end
        local box = Instance.new('SelectionBox')
        box.Color3        = Color3.fromRGB(255, 50, 50)
        box.LineThickness = 0.07
        box.Adornee       = char
        box.Parent        = workspace
        local bill = Instance.new('BillboardGui')
        bill.AlwaysOnTop = true
        bill.Size        = UDim2.new(0, 180, 0, 26)
        bill.StudsOffset = Vector3.new(0, 3.5, 0)
        bill.Adornee     = hrp
        bill.Parent      = workspace
        local lbl = Instance.new('TextLabel')
        lbl.Size                   = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text                   = '[ADMIN] ' .. p.Name
        lbl.TextColor3             = Color3.fromRGB(255, 80, 80)
        lbl.Font                   = Enum.Font.GothamBold
        lbl.TextSize               = 14
        lbl.TextStrokeTransparency = 0.5
        lbl.Parent                 = bill
        adminBoxMap[p.UserId] = { box=box, bill=bill }
    end
end

ESPLeft:AddToggle('AdminESP', {
    Text = 'Admin ESP',
    Default = false,
    Callback = function(val)
        if val then
            refreshAdminESP()
            local timer = 0
            _G.AdminESPConn = game:GetService('RunService').Heartbeat:Connect(function()
                timer += 1
                if timer >= 120 then timer = 0; refreshAdminESP() end
            end)
            showToast('Admin ESP ON')
        else
            clearAdminESP()
            if _G.AdminESPConn then _G.AdminESPConn:Disconnect(); _G.AdminESPConn = nil end
            showToast('Admin ESP OFF')
        end
    end
})

ESPLeft:AddButton({
    Text = 'Refresh Admin ESP',
    Func = function()
        refreshAdminESP()
        showToast('Admin ESP refreshed')
    end
})

ESPLeft:AddDivider()

local bikeBoxMap = {}
local function clearBikeESP()
    for _, data in pairs(bikeBoxMap) do
        pcall(function() if data.box  then data.box:Destroy()  end end)
        pcall(function() if data.bill then data.bill:Destroy() end end)
    end
    bikeBoxMap = {}
end

local function refreshBikeESP()
    clearBikeESP()
    if not Toggles.BikeESP or not Toggles.BikeESP.Value then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if not isVehicleSeat(obj) then continue end
        local model = obj.Parent
        if not model then continue end
        local ownerName = 'Unoccupied'
        if obj.Occupant then
            local char = obj.Occupant.Parent
            if char then
                local p = Players:GetPlayerFromCharacter(char)
                if p then ownerName = p.Name end
            end
        end
        local box = Instance.new('SelectionBox')
        box.Color3        = Color3.fromRGB(255, 200, 0)
        box.LineThickness = 0.05
        box.Adornee       = model
        box.Parent        = workspace
        local bill = Instance.new('BillboardGui')
        bill.AlwaysOnTop = true
        bill.Size        = UDim2.new(0, 160, 0, 22)
        bill.StudsOffset = Vector3.new(0, 4, 0)
        bill.Adornee     = obj
        bill.Parent      = workspace
        local lbl = Instance.new('TextLabel')
        lbl.Size                   = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text                   = '[' .. VEHICLE_TERM_CAP .. '] ' .. ownerName
        lbl.TextColor3             = Color3.fromRGB(255, 200, 0)
        lbl.Font                   = Enum.Font.Gotham
        lbl.TextSize               = 13
        lbl.TextStrokeTransparency = 0.5
        lbl.Parent                 = bill
        table.insert(bikeBoxMap, { box=box, bill=bill })
    end
end

ESPLeft:AddToggle('BikeESP', {
    Text = VEHICLE_TERM_CAP .. ' ESP',
    Default = false,
    Callback = function(val)
        if val then
            refreshBikeESP()
            local timer = 0
            _G.BikeESPConn = game:GetService('RunService').Heartbeat:Connect(function()
                timer += 1
                if timer >= 60 then timer = 0; refreshBikeESP() end
            end)
            showToast(VEHICLE_TERM_CAP .. ' ESP ON')
        else
            clearBikeESP()
            if _G.BikeESPConn then _G.BikeESPConn:Disconnect(); _G.BikeESPConn = nil end
            showToast(VEHICLE_TERM_CAP .. ' ESP OFF')
        end
    end
})

ESPLeft:AddDivider()

local speedTagMap = {}
local function clearSpeedTags()
    for _, data in pairs(speedTagMap) do
        pcall(function() if data.bill then data.bill:Destroy() end end)
    end
    speedTagMap = {}
end

local function getOrCreateTag(player)
    if speedTagMap[player.UserId] then return speedTagMap[player.UserId] end
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild('HumanoidRootPart')
    if not hrp then return nil end
    local bill = Instance.new('BillboardGui')
    bill.AlwaysOnTop = false
    bill.MaxDistance = 150
    bill.Size        = UDim2.new(0, 160, 0, 22)
    bill.StudsOffset = Vector3.new(0, 3, 0)
    bill.Adornee     = hrp
    bill.Parent      = workspace
    local lbl = Instance.new('TextLabel')
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = player.Name .. ' -- 0 mph'
    lbl.TextColor3             = Color3.fromRGB(200, 255, 200)
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 13
    lbl.TextStrokeTransparency = 0.5
    lbl.Parent                 = bill
    local data = { bill=bill, label=lbl, hrp=hrp }
    speedTagMap[player.UserId] = data
    return data
end

ESPLeft:AddToggle('SpeedNametags', {
    Text = 'Speed Nametags',
    Default = false,
    Callback = function(val)
        if val then
            local RS2 = game:GetService('RunService')
            _G.SpeedTagConn = RS2.Heartbeat:Connect(function()
                for _, p in ipairs(Players:GetPlayers()) do
                    if p == plr then continue end
                    local data = getOrCreateTag(p)
                    if not data then continue end
                    if not data.hrp or not data.hrp.Parent then
                        pcall(function() if data.bill then data.bill:Destroy() end end)
                        speedTagMap[p.UserId] = nil
                        continue
                    end
                    local mph = math.floor(data.hrp.AssemblyLinearVelocity.Magnitude * STUDS_TO_MPH + 0.5)
                    data.label.Text = p.Name .. ' -- ' .. mph .. ' mph'
                end
            end)
            _G.SpeedTagLeaveConn = Players.PlayerRemoving:Connect(function(p)
                local data = speedTagMap[p.UserId]
                if data then
                    pcall(function() data.bill:Destroy() end)
                    speedTagMap[p.UserId] = nil
                end
            end)
            showToast('Speed Nametags ON')
        else
            clearSpeedTags()
            if _G.SpeedTagConn      then _G.SpeedTagConn:Disconnect();      _G.SpeedTagConn      = nil end
            if _G.SpeedTagLeaveConn then _G.SpeedTagLeaveConn:Disconnect(); _G.SpeedTagLeaveConn = nil end
            showToast('Speed Nametags OFF')
        end
    end
})

ESPLeft:AddDivider()

-- ---- Player ESP ---------------------------------------------------------
local playerESPMap = {}

local function clearPlayerESP()
    for _, data in pairs(playerESPMap) do
        pcall(function() if data.box  then data.box:Destroy()  end end)
        pcall(function() if data.bill then data.bill:Destroy() end end)
    end
    playerESPMap = {}
end

local function refreshPlayerESP()
    clearPlayerESP()
    if not Toggles.PlayerESP or not Toggles.PlayerESP.Value then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == plr then continue end
        local char = p.Character
        if not char then continue end
        local hrp = char:FindFirstChild('HumanoidRootPart')
        if not hrp then continue end

        local box = Instance.new('SelectionBox')
        box.Color3               = Color3.fromRGB(255, 255, 255)
        box.LineThickness        = 0.05
        box.SurfaceTransparency  = 0.9
        box.SurfaceColor3        = Color3.fromRGB(255, 255, 255)
        box.Adornee              = char
        box.Parent               = workspace

        local bill = Instance.new('BillboardGui')
        bill.AlwaysOnTop = true
        bill.Size        = UDim2.new(0, 160, 0, 22)
        bill.StudsOffset = Vector3.new(0, 3.2, 0)
        bill.Adornee     = hrp
        bill.Parent      = workspace

        local lbl = Instance.new('TextLabel')
        lbl.Size                   = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text                   = p.Name
        lbl.TextColor3             = Color3.fromRGB(230, 230, 230)
        lbl.Font                   = Enum.Font.GothamBold
        lbl.TextSize               = 13
        lbl.TextStrokeTransparency = 0.4
        lbl.Parent                 = bill

        playerESPMap[p.UserId] = { box = box, bill = bill }
    end
end

ESPLeft:AddToggle('PlayerESP', {
    Text    = 'Player ESP',
    Default = false,
    Callback = function(val)
        if val then
            refreshPlayerESP()
            local timer = 0
            _G.PlayerESPConn = game:GetService('RunService').Heartbeat:Connect(function()
                timer += 1
                if timer >= 90 then timer = 0; refreshPlayerESP() end
            end)
            -- re-adorn when a player's character respawns mid-refresh
            _G.PlayerESPCharConn = Players.PlayerAdded:Connect(function() refreshPlayerESP() end)
            showToast('Player ESP ON')
        else
            clearPlayerESP()
            if _G.PlayerESPConn     then _G.PlayerESPConn:Disconnect();     _G.PlayerESPConn     = nil end
            if _G.PlayerESPCharConn then _G.PlayerESPCharConn:Disconnect(); _G.PlayerESPCharConn = nil end
            showToast('Player ESP OFF')
        end
    end
})

ESPLeft:AddButton({
    Text = 'Refresh Player ESP',
    Func = function()
        refreshPlayerESP()
        showToast('Player ESP refreshed')
    end
})

ESPLeft:AddDivider()

-- ---- Anim Tweaks (moved from Main; universal player feature) -------------
ESPLeft:AddInput('AnimSpeedInput', {
    Default = '1.0',
    Numeric = true,
    Finished = false,
    Text = 'Anim Speed (multiplier)',
})

ESPLeft:AddToggle('AnimTweaks', {
    Text = 'Anim Tweaks',
    Default = false,
    Callback = function(val)
        if val then
            _G.AnimConn = RunService.Heartbeat:Connect(function()
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local animator = hum:FindFirstChildWhichIsA('Animator')
                if not animator then return end
                -- bail on invalid input rather than pinning to 1.0 every frame
                -- (the old fallback was what made anims "feel frozen at default")
                local speed = tonumber(Options.AnimSpeedInput.Value)
                if not speed or speed <= 0 then return end
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    pcall(function() track:AdjustSpeed(speed) end)
                end
            end)
            showToast('Anim tweaks ON')
        else
            if _G.AnimConn then _G.AnimConn:Disconnect(); _G.AnimConn = nil end
            local char = plr.Character
            local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
            local anim = hum  and hum:FindFirstChildWhichIsA('Animator')
            if anim then
                for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                    pcall(function() track:AdjustSpeed(1) end)
                end
            end
            showToast('Anim tweaks OFF')
        end
    end
})

ESPLeft:AddToggle('HitboxViewer', {
    Text = 'Hitbox Viewer (players)',
    Default = false,
    Callback = function(val)
        if val then
            refreshHitboxes()
            local timer = 0
            _G.HitboxConn = game:GetService('RunService').Heartbeat:Connect(function()
                timer += 1
                if timer >= 60 then timer = 0; refreshHitboxes() end
            end)
        else
            clearHitboxes()
            if _G.HitboxConn then _G.HitboxConn:Disconnect(); _G.HitboxConn = nil end
        end
    end
})

ESPLeft:AddDivider()

-- ============================================================
-- HIDE PLAYERS
-- Basic: LocalTransparencyModifier=1 on every BasePart of every other
--        player's character (client-side only, no server replication).
-- Full : also noclips + hides workspace-wide parts whose name contains
--        the username, and disables effect instances (Particle/Beam/etc)
--        on the character and any name-matched parts.
-- Never touches the local player. Ignore Friends optional.
-- ============================================================
do
    local EFFECT_CLASSES = {
        ParticleEmitter = true, Beam = true, Trail = true,
        Fire = true, Smoke = true, Sparkles = true, Explosion = true,
    }

    -- cache[userId] = { parts={[BasePart]={ltm,coll}}, effects={[Instance]=wasEnabled}, extras={[BasePart]={ltm,coll}} }
    local cache = {}
    -- friend cache -- IsFriendsWith yields, don't hammer it every frame
    local friendCache = {}
    local function isFriend(other)
        if friendCache[other.UserId] ~= nil then return friendCache[other.UserId] end
        local ok, res = pcall(function() return plr:IsFriendsWith(other.UserId) end)
        local val = (ok and res) and true or false
        friendCache[other.UserId] = val
        return val
    end

    local function shouldHide(other)
        if other == plr then return false end
        if not (Toggles.HidePlayers and Toggles.HidePlayers.Value) then return false end
        if Toggles.HidePlayersIgnoreFriends and Toggles.HidePlayersIgnoreFriends.Value
           and isFriend(other) then return false end
        return true
    end

    local function ensureCache(uid)
        cache[uid] = cache[uid] or { parts = {}, effects = {}, extras = {} }
        return cache[uid]
    end

    local function hidePart(part, c, alsoNoclip)
        if not part or not part:IsA('BasePart') then return end
        local bucket = alsoNoclip and c.extras or c.parts
        if bucket[part] then return end
        bucket[part] = { ltm = part.LocalTransparencyModifier, coll = part.CanCollide }
        pcall(function()
            part.LocalTransparencyModifier = 1
            if alsoNoclip then part.CanCollide = false end
        end)
    end

    local function hideEffect(inst, c)
        if c.effects[inst] then return end
        if EFFECT_CLASSES[inst.ClassName] then
            c.effects[inst] = inst.Enabled
            pcall(function() inst.Enabled = false end)
        end
    end

    local function restore(uid)
        local c = cache[uid]
        if not c then return end
        for part, e in pairs(c.parts) do
            if part and part.Parent then
                pcall(function() part.LocalTransparencyModifier = e.ltm end)
            end
        end
        for part, e in pairs(c.extras) do
            if part and part.Parent then
                pcall(function()
                    part.LocalTransparencyModifier = e.ltm
                    part.CanCollide                = e.coll
                end)
            end
        end
        for inst, wasEnabled in pairs(c.effects) do
            if inst and inst.Parent then
                pcall(function() inst.Enabled = wasEnabled end)
            end
        end
        cache[uid] = nil
    end

    local function restoreAll()
        for uid in pairs(cache) do restore(uid) end
    end

    local function processPlayer(other)
        if not shouldHide(other) then restore(other.UserId); return end
        local fullMode = Toggles.HidePlayersFull and Toggles.HidePlayersFull.Value
        local c = ensureCache(other.UserId)
        local char = other.Character
        if char then
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA('BasePart') then
                    hidePart(d, c, fullMode)
                end
                if fullMode and EFFECT_CLASSES[d.ClassName] then
                    hideEffect(d, c)
                end
            end
        end
        if fullMode then
            -- Full mode: instead of walking every workspace descendant (was
            -- O(workspace) per player and killed FPS), scan the workspace's
            -- top-level children for Instances whose Name contains the user
            -- name (case-insensitive substring). That catches character
            -- Models (Name = username) + player-owned rigs like `<Name>sCar`.
            -- For each match, hide + noclip all BaseParts under it and
            -- disable any effect instances.
            local q = other.Name:lower()
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj ~= char and obj.Name:lower():find(q, 1, true) then
                    for _, d in ipairs(obj:GetDescendants()) do
                        if d:IsA('BasePart') then hidePart(d, c, true) end
                        if EFFECT_CLASSES[d.ClassName] then hideEffect(d, c) end
                    end
                    -- also handle the top-level obj itself if it's a BasePart
                    if obj:IsA('BasePart') then hidePart(obj, c, true) end
                end
            end
        end
    end

    local function sweep()
        for _, other in ipairs(Players:GetPlayers()) do processPlayer(other) end
    end

    _G.HidePlayersSweep = sweep

    ESPLeft:AddToggle('HidePlayers', {
        Text = 'Hide Players',
        Default = false,
        Callback = function(val)
            if val then
                sweep()
                local timer = 0
                _G.HidePlayersConn = RunService.Heartbeat:Connect(function()
                    timer += 1
                    -- 180 frames ~= 3s; low enough to catch respawns quickly
                    -- but not so frequent that Full mode's workspace-children
                    -- sweep tanks FPS on huge maps.
                    if timer >= 180 then timer = 0; sweep() end
                end)
                _G.HidePlayersJoinConn = Players.PlayerAdded:Connect(function(p)
                    p.CharacterAdded:Connect(function() task.wait(0.5); processPlayer(p) end)
                end)
                _G.HidePlayersLeaveConn = Players.PlayerRemoving:Connect(function(p)
                    restore(p.UserId); friendCache[p.UserId] = nil
                end)
                -- wire CharacterAdded on already-present players
                _G.HidePlayersCharConns = _G.HidePlayersCharConns or {}
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= plr then
                        _G.HidePlayersCharConns[p.UserId] = p.CharacterAdded:Connect(function()
                            task.wait(0.5); processPlayer(p)
                        end)
                    end
                end
                showToast('Hide Players ON')
            else
                restoreAll()
                if _G.HidePlayersConn      then _G.HidePlayersConn:Disconnect();      _G.HidePlayersConn      = nil end
                if _G.HidePlayersJoinConn  then _G.HidePlayersJoinConn:Disconnect();  _G.HidePlayersJoinConn  = nil end
                if _G.HidePlayersLeaveConn then _G.HidePlayersLeaveConn:Disconnect(); _G.HidePlayersLeaveConn = nil end
                if _G.HidePlayersCharConns then
                    for _, c in pairs(_G.HidePlayersCharConns) do pcall(function() c:Disconnect() end) end
                    _G.HidePlayersCharConns = nil
                end
                showToast('Hide Players OFF')
            end
        end
    })

    ESPLeft:AddToggle('HidePlayersFull', {
        Text = 'Full',
        Default = false,
        Tooltip = 'Also noclips + hides workspace parts named after the player, and disables their effects (particles / beams / trails).',
        Callback = function(_)
            -- restore first (so extras from previous mode drop out of cache)
            -- then re-sweep with the new fullMode value
            restoreAll()
            if Toggles.HidePlayers and Toggles.HidePlayers.Value then sweep() end
        end
    })

    ESPLeft:AddToggle('HidePlayersIgnoreFriends', {
        Text = 'Ignore Friends',
        Default = false,
        Tooltip = 'Skip Roblox friends (they stay visible + solid).',
        Callback = function(_)
            -- reset friend cache in case a mistaken previous check is stale
            friendCache = {}
            restoreAll()
            if Toggles.HidePlayers and Toggles.HidePlayers.Value then sweep() end
        end
    })
end

-- custom spawner panel (linoria-matched, no rounding)
-- ============================================================

local BG     = Color3.fromRGB(25, 25, 25)
local BG2    = Color3.fromRGB(20, 20, 20)
local BGSUB  = Color3.fromRGB(30, 30, 30)
local BORDER = Color3.fromRGB(50, 50, 50)
local ACCENT = Color3.fromRGB(0, 120, 215)
local TEXT   = Color3.fromRGB(240, 240, 240)
local SUBTEXT= Color3.fromRGB(160, 160, 160)

local gui = Instance.new('ScreenGui')
gui.Name = 'SpawnerGui'
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000  -- above Linoria (999), below customizer (1001)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
safeParentGui(gui)

local sfx = Instance.new('Sound')
sfx.SoundId = 'rbxassetid://131039887376992'
sfx.Volume = 2
sfx.Parent = gui
playSuccess = function() sfx:Play() end

-- linoria-style toast: slides in from bottom-right, accent left bar
local toastY = 0
showToast = function(text)
    toastY = toastY + 44
    local offY = toastY

    local t = Instance.new('Frame')
    t.Size = UDim2.new(0, 280, 0, 48)
    t.AnchorPoint = Vector2.new(1, 1)
    t.Position = UDim2.new(1, 0, 1, -(offY - 44))
    t.BackgroundColor3 = BG2
    t.BorderSizePixel = 1
    t.BorderColor3 = BORDER
    t.ZIndex = 50
    t.Parent = gui

    -- accent left bar
    local bar = Instance.new('Frame')
    bar.Size = UDim2.new(0, 3, 1, 0)
    bar.BackgroundColor3 = ACCENT
    bar.BorderSizePixel = 0
    bar.ZIndex = 51
    bar.Parent = t

    local l = Instance.new('TextLabel')
    l.Size = UDim2.new(1, -10, 1, 0)
    l.Position = UDim2.new(0, 8, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = TEXT
    l.Font = Enum.Font.Gotham
    l.TextSize = 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.ZIndex = 51
    l.Parent = t

    -- slide in from right
    TweenService:Create(t, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(1, -8, 1, -(offY - 44))
    }):Play()

    task.delay(2, function()
        TweenService:Create(t, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(1, 300, 1, -(offY - 44))
        }):Play()
        TweenService:Create(l, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
        task.wait(0.2)
        t:Destroy()
        toastY = toastY - 44
    end)
end

-- top-right undo/redo widget + Ctrl+Z / Ctrl+Y hotkeys
do
    local udGui = Instance.new('ScreenGui')
    udGui.Name           = 'AeroUndoRedoGui'
    udGui.ResetOnSpawn   = false
    udGui.DisplayOrder   = 1005  -- above every panel (Linoria 999, panels 1001)
    udGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    safeParentGui(udGui)

    local udFrame = Instance.new('Frame')
    udFrame.Size             = UDim2.new(0, 120, 0, 30)
    udFrame.Position         = UDim2.new(1, -132, 0, 12)
    udFrame.AnchorPoint      = Vector2.new(0, 0)
    udFrame.BackgroundColor3 = BG2
    udFrame.BorderSizePixel  = 1
    udFrame.BorderColor3     = BORDER
    udFrame.ZIndex           = 40
    udFrame.Parent           = udGui

    local function udBtn(text, x)
        local b = Instance.new('TextButton')
        b.Size = UDim2.new(0, 54, 0, 24); b.Position = UDim2.new(0, x, 0, 3)
        b.BackgroundColor3 = BGSUB; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = text; b.TextColor3 = TEXT
        b.Font = Enum.Font.Code; b.TextSize = 11
        b.AutoButtonColor = false; b.ZIndex = 41; b.Parent = udFrame
        b.MouseEnter:Connect(function()
            if b.BackgroundColor3 == BGSUB then b.BackgroundColor3 = BORDER end
        end)
        b.MouseLeave:Connect(function()
            if b.BackgroundColor3 == BORDER then b.BackgroundColor3 = BGSUB end
        end)
        return b
    end
    local undoBtn = udBtn('Undo', 4)
    local redoBtn = udBtn('Redo', 62)

    local function runUndo()
        local label = History.doUndo()
        if not label then showToast('Nothing to undo'); return end
        showToast('Undo: ' .. label)
    end
    local function runRedo()
        local label = History.doRedo()
        if not label then showToast('Nothing to redo'); return end
        showToast('Redo: ' .. label)
    end

    undoBtn.MouseButton1Click:Connect(runUndo)
    redoBtn.MouseButton1Click:Connect(runRedo)

    -- ignore when a TextBox has focus so typing-undo doesn't pop our stack
    UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl)
                  or UIS:IsKeyDown(Enum.KeyCode.RightControl)
        if not ctrl then return end
        if input.KeyCode == Enum.KeyCode.Z then runUndo()
        elseif input.KeyCode == Enum.KeyCode.Y then runRedo() end
    end)
end

-- spawner window (only built when current place exposes spawnable bikes)
if BIKE_INFO.canSpawn then

local spawnerFrame = Instance.new('Frame')
spawnerFrame.Size = UDim2.new(0, 440, 0, 520)
spawnerFrame.Position = UDim2.new(0.5, 20, 0.5, -260)
spawnerFrame.BackgroundColor3 = BG2
spawnerFrame.BorderSizePixel = 1
spawnerFrame.BorderColor3 = BORDER
spawnerFrame.Visible = false
spawnerFrame.ZIndex = 10
spawnerFrame.Active = true
spawnerFrame.ClipsDescendants = true
spawnerFrame.Parent = gui

-- title bar
local titleBar = Instance.new('Frame')
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = BG2
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 11
titleBar.Parent = spawnerFrame

local accentLine = Instance.new('Frame')
accentLine.Size = UDim2.new(1, 0, 0, 1)
accentLine.Position = UDim2.new(0, 0, 0, 32)
accentLine.BackgroundColor3 = ACCENT
accentLine.BorderSizePixel = 0
accentLine.ZIndex = 12
accentLine.Parent = spawnerFrame

local titleLbl = Instance.new('TextLabel')
titleLbl.Size = UDim2.new(1, -16, 1, 0)
titleLbl.Position = UDim2.new(0, 10, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = VEHICLE_TERM_CAP .. ' Spawner'
titleLbl.TextColor3 = TEXT
titleLbl.Font = Enum.Font.GothamSemibold
titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.ZIndex = 12
titleLbl.Parent = titleBar

local scroll = Instance.new('ScrollingFrame')
scroll.Size = UDim2.new(1, -4, 1, -38)
scroll.Position = UDim2.new(0, 2, 0, 36)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 2
scroll.ScrollBarImageColor3 = ACCENT
scroll.ZIndex = 11
scroll.Parent = spawnerFrame

local grid = Instance.new('UIGridLayout')
grid.CellSize = UDim2.new(0, 130, 0, 150)
grid.CellPadding = UDim2.new(0, 4, 0, 4)
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.Parent = scroll

local gridPad = Instance.new('UIPadding')
gridPad.PaddingTop = UDim.new(0, 4)
gridPad.PaddingBottom = UDim.new(0, 4)
gridPad.Parent = scroll

local bikeList = BIKE_INFO.bikes
scroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#bikeList / 3) * 154 + 8)

-- lazy population: ViewportFrame contents (bike clone + camera) are heavy.
-- defer them to first toggle-open so script load + opening the panel stay snappy.
local spawnerPopulated = false
local spawnerPopulateFns = {}

for _, bike in ipairs(bikeList) do
    local card = Instance.new('TextButton')
    card.Size = UDim2.new(0, 130, 0, 150)
    card.BackgroundColor3 = BGSUB
    card.BorderSizePixel = 1
    card.BorderColor3 = BORDER
    card.Text = ''
    card.AutoButtonColor = false
    card.ZIndex = 12
    card.Parent = scroll
    -- Linoria-style hover: brighten border to accent
    card.MouseEnter:Connect(function() card.BorderColor3 = ACCENT end)
    card.MouseLeave:Connect(function() card.BorderColor3 = BORDER end)

    local vpf = Instance.new('ViewportFrame')
    vpf.Size = UDim2.new(1, 0, 0, 108)
    vpf.BackgroundTransparency = 1
    vpf.BorderSizePixel = 0
    vpf.ZIndex = 13
    vpf.Parent = card

    -- defer the clone-into-vpf work; the empty card is cheap, the clone is not
    table.insert(spawnerPopulateFns, function()
        local wm = Instance.new('WorldModel')
        wm.Parent = vpf
        local cam = Instance.new('Camera')
        vpf.CurrentCamera = cam
        cam.Parent = vpf

        local ok, clone = pcall(function() return bike:Clone() end)
        if ok and clone then
            clone.Parent = wm
            local cok, cf, size = pcall(function()
                return clone:GetBoundingBox()
            end)
            if cok and cf then
                local dist = math.max(size.X, size.Y, size.Z) * 1.4
                cam.CFrame = CFrame.lookAt(
                    cf.Position + Vector3.new(dist, dist * 0.4, dist),
                    cf.Position
                )
            end
        end
    end)

    local sep = Instance.new('Frame')
    sep.Size = UDim2.new(1, 0, 0, 1)
    sep.Position = UDim2.new(0, 0, 0, 108)
    sep.BackgroundColor3 = BORDER
    sep.BorderSizePixel = 0
    sep.ZIndex = 13
    sep.Parent = card

    local nameLbl = Instance.new('TextLabel')
    nameLbl.Size = UDim2.new(1, -8, 0, 38)
    nameLbl.Position = UDim2.new(0, 4, 0, 110)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = bike.Name
    nameLbl.TextColor3 = SUBTEXT
    nameLbl.Font = Enum.Font.Gotham
    nameLbl.TextSize = 11
    nameLbl.TextWrapped = true
    nameLbl.ZIndex = 13
    nameLbl.Parent = card

    card.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.1), { BorderColor3 = ACCENT }):Play()
        TweenService:Create(nameLbl, TweenInfo.new(0.1), { TextColor3 = TEXT }):Play()
    end)
    card.MouseLeave:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.1), { BorderColor3 = BORDER }):Play()
        TweenService:Create(nameLbl, TweenInfo.new(0.1), { TextColor3 = SUBTEXT }):Play()
    end)
    card.MouseButton1Down:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.08), { BackgroundColor3 = BG }):Play()
    end)
    card.MouseButton1Up:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.08), { BackgroundColor3 = BGSUB }):Play()
    end)
    card.MouseButton1Click:Connect(function()
        BIKE_INFO.spawn(bike.Name)
        showToast('Spawned ' .. bike.Name)
    end)
end

local sDrag, sDragStart, sStart
titleBar.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        sDrag = true
        sDragStart = inp.Position
        sStart = spawnerFrame.Position
    end
end)
titleBar.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then sDrag = false end
end)
UIS.InputChanged:Connect(function(inp)
    if sDrag and inp.UserInputType == Enum.UserInputType.MouseMovement then
        local d = inp.Position - sDragStart
        spawnerFrame.Position = UDim2.new(sStart.X.Scale, sStart.X.Offset + d.X, sStart.Y.Scale, sStart.Y.Offset + d.Y)
    end
end)

local function populateSpawner()
    if spawnerPopulated then return end
    spawnerPopulated = true
    task.spawn(function()
        for i, fn in ipairs(spawnerPopulateFns) do
            pcall(fn)
            if i % 3 == 0 then task.wait() end
        end
    end)
end

Toggles.SpawnerToggle:OnChanged(function()
    spawnerFrame.Visible = Toggles.SpawnerToggle.Value
    if Toggles.SpawnerToggle.Value then populateSpawner() end
end)

-- keybind (change hideKey to whatever you want)
local hideKey = Enum.KeyCode.Delete

UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == hideKey then
        pcall(function() Library:Toggle() end)
        pcall(function() spawnerFrame.Visible = false end)
        pcall(function()
            if Toggles and Toggles.SpawnerToggle then
                Toggles.SpawnerToggle:SetValue(false)
            end
        end)
    end
end)

end -- if BIKE_INFO.canSpawn


-- ============================================================
-- BIKE CUSTOMIZATION PANEL
-- ============================================================
do
    local _scooterMode = false
    _G._scooterMode = false

    local function getTargetModel()
        local char = plr.Character
        local hum2  = char and char:FindFirstChildWhichIsA('Humanoid')
        if not hum2 or not hum2.SeatPart then return nil end
        local base = hum2.SeatPart.Parent
        if not base then return nil end
        if _scooterMode then
            local root = base
            while root and root.Parent and root.Parent ~= workspace
                  and root.Parent:IsA('Model') do
                root = root.Parent
            end
            return root
        else
            return base
        end
    end

    local function applySA(p, saFn)
        if not saFn then return end
        local sa = p:FindFirstChildOfClass('SurfaceAppearance')
        if sa then pcall(saFn, sa) end
    end

    -- optional (undoLabel, undoProps): when set, snapshot into History
    local function applyToAll(fn, saFn, undoLabel, undoProps)
        local model = getTargetModel()
        if not model then showToast('Not on a ' .. VEHICLE_TERM); return end
        local parts = {}
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA('BasePart') then parts[#parts+1] = p end
        end
        local function doit()
            for _, p in ipairs(parts) do
                pcall(fn, p)
                applySA(p, saFn)
            end
        end
        if undoLabel then
            History.pushDiff(undoLabel, parts, undoProps or COMMON_PROPS, doit)
        else
            doit()
        end
    end

    local function getBikeRoot()
        local model = getTargetModel()
        if not model then return nil end
        local seat = model:FindFirstChildWhichIsA('VehicleSeat', true)
                  or model:FindFirstChildWhichIsA('Seat', true)
        return seat or model.PrimaryPart or model:FindFirstChildWhichIsA('BasePart', true)
    end

    local bc = Instance.new('ScreenGui')
    bc.Name           = 'BikeCustGui'
    bc.ResetOnSpawn   = false
    bc.DisplayOrder   = 1001   -- above Linoria's main window (999)
    bc.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    bc.Enabled        = false
    safeParentGui(bc)
    bikeCustGui       = bc

    local panel = Instance.new('Frame')
    panel.Size             = UDim2.new(0, 430, 0, 580)
    panel.Position         = UDim2.new(0.5, -155, 0.5, -290)
    panel.BackgroundColor3 = BG2
    panel.BorderSizePixel  = 1
    panel.BorderColor3     = BORDER
    panel.Active           = true
    panel.ZIndex           = 10
    panel.Parent           = bc

    do
        local drag, dragStart, startPos = false, nil, nil
        panel.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                drag = true; dragStart = inp.Position; startPos = panel.Position
            end
        end)
        panel.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
        end)
        UIS.InputChanged:Connect(function(inp)
            if drag and inp.UserInputType == Enum.UserInputType.MouseMovement then
                local d = inp.Position - dragStart
                panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                           startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    local titleBar = Instance.new('Frame')
    titleBar.Size             = UDim2.new(1, 0, 0, 32)
    titleBar.BackgroundColor3 = BGSUB
    titleBar.BorderSizePixel  = 0
    titleBar.ZIndex           = 11
    titleBar.Parent           = panel
    do
        -- accent underline (Linoria signature divider between title and content)
        local accentLine = Instance.new('Frame')
        accentLine.Size = UDim2.new(1, 0, 0, 1); accentLine.Position = UDim2.new(0, 0, 1, 0)
        accentLine.BackgroundColor3 = ACCENT; accentLine.BorderSizePixel = 0
        accentLine.ZIndex = 12; accentLine.Parent = titleBar

        local tl = Instance.new('TextLabel')
        tl.Size = UDim2.new(1, -140, 1, 0); tl.Position = UDim2.new(0, 10, 0, 0)
        tl.BackgroundTransparency = 1; tl.Text = VEHICLE_TERM_CAP .. ' Customization'
        tl.TextColor3 = TEXT; tl.Font = Enum.Font.Code
        tl.TextSize = 13; tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.ZIndex = 12; tl.Parent = titleBar

        local sl = Instance.new('TextLabel')
        sl.Size = UDim2.new(0, 50, 0, 20); sl.Position = UDim2.new(1, -132, 0.5, -10)
        sl.BackgroundTransparency = 1; sl.Text = 'Scooter'
        sl.TextColor3 = SUBTEXT; sl.Font = Enum.Font.Code
        sl.TextSize = 11; sl.TextXAlignment = Enum.TextXAlignment.Right
        sl.ZIndex = 12; sl.Parent = titleBar

        local stb = Instance.new('TextButton')
        stb.Size = UDim2.new(0, 44, 0, 20); stb.Position = UDim2.new(1, -78, 0.5, -10)
        stb.BackgroundColor3 = BGSUB; stb.BorderSizePixel = 1; stb.BorderColor3 = BORDER
        stb.Text = 'OFF'; stb.TextColor3 = SUBTEXT
        stb.Font = Enum.Font.Code; stb.TextSize = 11; stb.ZIndex = 12; stb.Parent = titleBar
        stb.MouseButton1Click:Connect(function()
            _scooterMode = not _scooterMode
            _G._scooterMode = _scooterMode
            if _scooterMode then stb.BackgroundColor3 = ACCENT; stb.TextColor3 = TEXT; stb.Text = 'ON'
            else stb.BackgroundColor3 = BGSUB; stb.TextColor3 = SUBTEXT; stb.Text = 'OFF' end
            showToast('Scooter mode: ' .. (_scooterMode and 'ON' or 'OFF'))
        end)

        local cb = Instance.new('TextButton')
        cb.Size = UDim2.new(0, 32, 0, 32); cb.Position = UDim2.new(1, -32, 0, 0)
        cb.BackgroundColor3 = Color3.fromRGB(180, 50, 50); cb.BorderSizePixel = 0
        cb.Text = 'X'; cb.TextColor3 = TEXT; cb.Font = Enum.Font.Code
        cb.TextSize = 13; cb.ZIndex = 12; cb.Parent = titleBar
        cb.MouseButton1Click:Connect(function() bc.Enabled = false end)
    end

    local scroll = Instance.new('ScrollingFrame')
    scroll.Size                   = UDim2.new(1, 0, 1, -32)
    scroll.Position               = UDim2.new(0, 0, 0, 32)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel        = 0
    scroll.ScrollBarThickness     = 5
    scroll.ScrollBarImageColor3   = BORDER
    scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
    scroll.ZIndex                 = 11
    scroll.Parent                 = panel
    do
        local lay = Instance.new('UIListLayout')
        lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Padding = UDim.new(0, 0); lay.Parent = scroll
        local pad = Instance.new('UIPadding')
        pad.PaddingBottom = UDim.new(0, 14); pad.Parent = scroll
    end

    local _bcOrder = 0
    local function bcNext() _bcOrder = _bcOrder + 1; return _bcOrder end
    -- Linoria-style: flat transparent header row, small caps accent label,
    -- thin accent underline that stops short on the right
    local function bcSecHdr(label)
        if _bcOrder > 0 then
            local gap = Instance.new('Frame')
            gap.Size = UDim2.new(1,0,0,10); gap.BackgroundTransparency = 1
            gap.BorderSizePixel = 0; gap.LayoutOrder = bcNext(); gap.ZIndex = 11; gap.Parent = scroll
        end
        local f = Instance.new('Frame')
        f.Size = UDim2.new(1,0,0,22); f.BackgroundTransparency = 1
        f.BorderSizePixel = 0; f.LayoutOrder = bcNext(); f.ZIndex = 11; f.Parent = scroll
        local l = Instance.new('TextLabel')
        l.Size = UDim2.new(1,-10,1,-3); l.Position = UDim2.new(0,10,0,0)
        l.BackgroundTransparency = 1; l.Text = label; l.TextColor3 = ACCENT
        l.Font = Enum.Font.Code; l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 12; l.Parent = f
        local rule = Instance.new('Frame')
        rule.Size = UDim2.new(1,-20,0,1); rule.Position = UDim2.new(0,10,1,-2)
        rule.BackgroundColor3 = ACCENT; rule.BorderSizePixel = 0
        rule.BackgroundTransparency = 0.55; rule.ZIndex = 12; rule.Parent = f
    end
    local function bcRow(h)
        local f = Instance.new('Frame')
        f.Size = UDim2.new(1,0,0,h or 32); f.BackgroundTransparency = 1
        f.LayoutOrder = bcNext(); f.ZIndex = 11; f.Parent = scroll
        return f
    end
    local function bcLbl(par, text, x, y, w, h)
        local l = Instance.new('TextLabel')
        l.Size = UDim2.new(0,w or 110,0,h or 20); l.Position = UDim2.new(0,x,0,y)
        l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = TEXT
        l.Font = Enum.Font.Code; l.TextSize = 12
        l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 12; l.Parent = par
        return l
    end
    local function bcInp(par, def, x, y, w, h)
        local b = Instance.new('TextBox')
        b.Size = UDim2.new(0,w or 54,0,h or 22); b.Position = UDim2.new(0,x,0,y)
        b.BackgroundColor3 = BGSUB; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = tostring(def or ''); b.TextColor3 = TEXT; b.Font = Enum.Font.Code
        b.TextSize = 12; b.ClearTextOnFocus = false; b.ZIndex = 12; b.Parent = par
        -- accent border on focus (Linoria-style)
        b.Focused:Connect(function() b.BorderColor3 = ACCENT end)
        b.FocusLost:Connect(function() b.BorderColor3 = BORDER end)
        return b
    end
    local function bcBtn(par, text, x, y, w, h)
        local b = Instance.new('TextButton')
        b.Size = UDim2.new(0,w or 80,0,h or 22); b.Position = UDim2.new(0,x,0,y)
        b.BackgroundColor3 = BGSUB; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = text; b.TextColor3 = TEXT; b.Font = Enum.Font.Code
        b.TextSize = 12; b.ZIndex = 12; b.AutoButtonColor = false; b.Parent = par
        -- hover state: brighten background slightly
        b.MouseEnter:Connect(function()
            if b.BackgroundColor3 == BGSUB then b.BackgroundColor3 = BORDER end
        end)
        b.MouseLeave:Connect(function()
            if b.BackgroundColor3 == BORDER then b.BackgroundColor3 = BGSUB end
        end)
        return b
    end
    local function bcTog(par, x, y, w, h)
        local b = Instance.new('TextButton')
        b.Size = UDim2.new(0,w or 48,0,h or 22); b.Position = UDim2.new(0,x,0,y)
        b.BackgroundColor3 = BGSUB; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = 'OFF'; b.TextColor3 = SUBTEXT; b.Font = Enum.Font.Code
        b.TextSize = 11; b.ZIndex = 12; b.Parent = par
        return b
    end
    local function bcTogOn(b) b.BackgroundColor3=ACCENT; b.TextColor3=TEXT; b.Text='ON' end
    local function bcTogOff(b) b.BackgroundColor3=BGSUB; b.TextColor3=SUBTEXT; b.Text='OFF' end

    -- shared state: tables keep cross-section refs to ~4 locals instead of ~22
    local matBtns  = {}
    local togBtns  = {}
    local togState = { hl=false, sp=false, smk=false, fire=false, spk=false, ff=false, ng=false, shad=true, sndLoop=false }
    local effInst  = { spotlights = {} }

    -- ================================================================
    -- MATERIAL
    -- ================================================================
    do
        bcSecHdr('MATERIAL')
        local MAT = {
            {'Plastic',Enum.Material.SmoothPlastic}, {'Metal',Enum.Material.Metal},
            {'Neon',Enum.Material.Neon},             {'ForceField',Enum.Material.ForceField},
            {'Glass',Enum.Material.Glass},           {'DiamondPlate',Enum.Material.DiamondPlate},
            {'Ice',Enum.Material.Ice},               {'Brick',Enum.Material.Brick},
            {'Wood',Enum.Material.Wood},             {'Sand',Enum.Material.Sand},
            {'Granite',Enum.Material.Granite},       {'Marble',Enum.Material.Marble},
        }
        local mf = bcRow(math.ceil(#MAT/4) * 26 + 8)
        for i, e in ipairs(MAT) do
            local col = (i-1)%4; local row = math.floor((i-1)/4)
            local b = bcBtn(mf, e[1], 8+col*100, 4+row*26, 96, 22)
            table.insert(matBtns, b)
            b.MouseButton1Click:Connect(function()
                applyToAll(function(p) p.Material = e[2] end, nil,
                    e[1] .. ' material', {'Material'})
                for _, mb in ipairs(matBtns) do mb.BackgroundColor3 = BGSUB end
                b.BackgroundColor3 = ACCENT
                showToast(e[1] .. ' applied')
            end)
        end
    end

    -- ================================================================
    -- QUICK COLOR
    -- ================================================================
    do
        bcSecHdr('QUICK COLOR')
        local QC = {
            {'Red',220,50,50},   {'Orange',255,140,0},  {'Yellow',255,220,0}, {'Lime',80,200,80},
            {'Cyan',0,200,220},  {'Blue',50,100,220},   {'Purple',150,50,220},{'Pink',255,100,180},
            {'White',255,255,255},{'Black',20,20,20},   {'Gold',212,175,55},  {'Chrome',190,195,200},
        }
        local qf = bcRow(math.ceil(#QC/4) * 26 + 8)
        for i, e in ipairs(QC) do
            local col = (i-1)%4; local row = math.floor((i-1)/4)
            local c = Color3.fromRGB(e[2], e[3], e[4])
            local b = bcBtn(qf, e[1], 8+col*100, 4+row*26, 96, 22)
            b.BackgroundColor3 = c
            b.TextColor3 = (e[2] > 200 and e[3] > 200) and Color3.fromRGB(20,20,20) or Color3.fromRGB(255,255,255)
            b.MouseButton1Click:Connect(function()
                applyToAll(function(p) p.Color = c end, function(sa) sa.Color = c end,
                    e[1] .. ' color', {'Color'})
                showToast(e[1] .. ' applied')
            end)
        end
    end

    -- ================================================================
    -- ADVANCED
    -- ================================================================
    do
        bcSecHdr('ADVANCED')
        local r = bcRow(34)
        bcLbl(r, 'Advanced customization:', 8, 5, 156, 20)
        bcBtn(r, 'Advanced Selection', 168, 4, 130, 22).MouseButton1Click:Connect(function()
            if partPickerGui then
                partPickerGui.Enabled = not partPickerGui.Enabled
                if partPickerGui.Enabled and ppBuildTreePublic then
                    -- auto-build on first open so buttons don't say "No parts selected"
                    pcall(ppBuildTreePublic)
                end
            else
                showToast('Advanced Selection did not build - check console (F9) for error')
                warn('Konstant: partPickerGui is nil - init aborted before part picker was built')
            end
        end)
    end

    -- ================================================================
    -- SURFACE
    -- ================================================================
    do
        bcSecHdr('SURFACE')
        do
            local r = bcRow(34); bcLbl(r,'Transparency:',8,5,90,20)
            local inp = bcInp(r,'0',100,4,54,22)
            bcBtn(r,'Apply',160,4,70,22).MouseButton1Click:Connect(function()
                local v = math.clamp(tonumber(inp.Text)or 0,0,0.99)
                applyToAll(function(p) p.Transparency=v end, nil,
                    'Transparency ' .. v, {'Transparency'})
                showToast('Transparency: '..v)
            end)
        end
        do
            local r = bcRow(34); bcLbl(r,'Reflectance:',8,5,84,20)
            local inp = bcInp(r,'0',94,4,54,22)
            bcBtn(r,'Apply',154,4,70,22).MouseButton1Click:Connect(function()
                local v = math.clamp(tonumber(inp.Text)or 0,0,1)
                applyToAll(function(p) p.Reflectance=v end, nil,
                    'Reflectance ' .. v, {'Reflectance'})
                showToast('Reflectance: '..v)
            end)
        end
        do
            local r = bcRow(34); bcLbl(r,'Cast Shadow:',8,5,82,20)
            togBtns.shad = bcTog(r,92,4); bcTogOn(togBtns.shad)
            togBtns.shad.MouseButton1Click:Connect(function()
                togState.shad = not togState.shad
                if togState.shad then bcTogOn(togBtns.shad) else bcTogOff(togBtns.shad) end
                applyToAll(function(p) p.CastShadow=togState.shad end, nil,
                    'CastShadow ' .. (togState.shad and 'ON' or 'OFF'), {'CastShadow'})
            end)
        end
    end

    -- ================================================================
    -- LIGHTING
    -- ================================================================
    bcSecHdr('LIGHTING')
    do -- headlight
        local r0 = bcRow(30); bcLbl(r0,'Headlight Color  R:',8,3,128,20)
        local hlR = bcInp(r0,'255',138,2,44,22); bcLbl(r0,'G:',186,3,14,20)
        local hlG = bcInp(r0,'255',202,2,44,22); bcLbl(r0,'B:',250,3,14,20)
        local hlB = bcInp(r0,'255',266,2,44,22)
        local r1 = bcRow(34); bcLbl(r1,'Brightness:',8,5,74,20)
        local hlBr = bcInp(r1,'5',84,4,44,22); bcLbl(r1,'Range:',132,5,44,20)
        local hlRg = bcInp(r1,'40',178,4,44,22)
        local r2 = bcRow(34); bcLbl(r2,'Headlight:',8,5,68,20)
        togBtns.hl = bcTog(r2,78,4)
        togBtns.hl.MouseButton1Click:Connect(function()
            togState.hl = not togState.hl
            if togState.hl then
                bcTogOn(togBtns.hl)
                local root = getBikeRoot()
                if root then
                    if effInst.headlight then effInst.headlight:Destroy() end
                    local sl = Instance.new('SpotLight')
                    sl.Color      = Color3.fromRGB(math.clamp(tonumber(hlR.Text)or 255,0,255),math.clamp(tonumber(hlG.Text)or 255,0,255),math.clamp(tonumber(hlB.Text)or 255,0,255))
                    sl.Brightness = math.clamp(tonumber(hlBr.Text)or 5,0,20)
                    sl.Range      = math.clamp(tonumber(hlRg.Text)or 40,0,60)
                    sl.Angle      = 75
                    sl.Face       = Enum.NormalId.Front
                    sl.Parent     = root; effInst.headlight = sl
                end
            else
                bcTogOff(togBtns.hl)
                if effInst.headlight then effInst.headlight:Destroy(); effInst.headlight = nil end
            end
        end)
    end

    -- ================================================================
    -- RAINBOW
    -- ================================================================
    do
        bcSecHdr('RAINBOW')
        local r0 = bcRow(34); bcLbl(r0,'Speed:',8,5,60,20)
        local spInp = bcInp(r0,'0.4',74,4,58,22)
        local r1 = bcRow(34); bcLbl(r1,'Rainbow Cycle:',8,5,110,20)
        togBtns.rb = bcTog(r1,120,4)
        togBtns.rb.MouseButton1Click:Connect(function()
            togState.rb = not togState.rb
            if togState.rb then
                bcTogOn(togBtns.rb)
                local hue = 0
                if _G.RainbowConn then _G.RainbowConn:Disconnect() end
                _G.RainbowConn = RunService.Heartbeat:Connect(function(dt)
                    local model = getTargetModel()
                    if not model then return end
                    local speed = tonumber(spInp.Text) or 0.4
                    hue = (hue + dt * speed) % 1
                    local col = Color3.fromHSV(hue, 1, 1)
                    for _, p in ipairs(model:GetDescendants()) do
                        if p:IsA('BasePart') then pcall(function() p.Color = col end) end
                    end
                end)
            else
                bcTogOff(togBtns.rb)
                if _G.RainbowConn then _G.RainbowConn:Disconnect(); _G.RainbowConn = nil end
            end
        end)
    end

    -- ================================================================
    -- CONFIGS
    -- ================================================================
    do
        bcSecHdr('CONFIGS')

        local CFG_FILE = 'Konstant/bike_appearance_configs.json'

        -- recursive value encoder: handles Color3/EnumItem/Vector3/CFrame at any depth
        local function encVal(v)
            local t = typeof(v)
            if t == 'Color3' then
                return { _c3 = true, r = v.R, g = v.G, b = v.B }
            elseif t == 'EnumItem' then
                return { _enum = true, v = tostring(v) }
            elseif t == 'Vector3' then
                return { _v3 = true, x = v.X, y = v.Y, z = v.Z }
            elseif t == 'CFrame' then
                return { _cf = true, c = { v:GetComponents() } }
            elseif t == 'table' then
                local out = {}
                for k, val in pairs(v) do out[k] = encVal(val) end
                return out
            else
                return v
            end
        end
        local function decVal(v)
            if type(v) ~= 'table' then return v end
            if v._c3 then
                return Color3.new(v.r or 0, v.g or 0, v.b or 0)
            elseif v._enum then
                local ok, enumVal = pcall(function()
                    local parts = tostring(v.v):split('.')
                    if #parts ~= 3 or parts[1] ~= 'Enum' then error('bad enum') end
                    return Enum[parts[2]][parts[3]]
                end)
                return ok and enumVal or nil
            elseif v._v3 then
                return Vector3.new(v.x or 0, v.y or 0, v.z or 0)
            elseif v._cf then
                local c = v.c or {}
                if #c == 12 then return CFrame.new(unpack(c)) end
                return nil
            else
                local out = {}
                for k, val in pairs(v) do out[k] = decVal(val) end
                return out
            end
        end
        -- serialize the WHOLE cfgTable ({configName -> {partKey -> {props}}}) to json
        local function cfgSerialize(tbl)
            return game:GetService('HttpService'):JSONEncode(encVal(tbl))
        end
        local function cfgDeserialize(json)
            return decVal(game:GetService('HttpService'):JSONDecode(json)) or {}
        end

        -- cfgCloudMeta[name] = { id, owner, ownerName, cloudName } (nil if local-only)
        local cfgCloudMeta = {}

        local HttpService_local = game:GetService('HttpService')

        -- v2 on-disk: { _version=2, configs, cloud }; v1 (flat table) auto-detected
        local function cfgFlushToDisk(tbl)
            if type(writefile) ~= 'function' then return end
            pcall(function()
                if type(makefolder) == 'function' then pcall(makefolder, 'Konstant') end
                local serialized = cfgSerialize(tbl)
                local decoded = HttpService_local:JSONDecode(serialized)
                local wrapped = {
                    _version = 2,
                    configs  = decoded,
                    cloud    = cfgCloudMeta,
                }
                local json = HttpService_local:JSONEncode(wrapped)
                -- sanity round-trip: what we'd write must parse back cleanly
                local ok = pcall(function() HttpService_local:JSONDecode(json) end)
                if ok then
                    writefile(CFG_FILE, json)
                else
                    showToast('Config save failed: bad JSON')
                end
            end)
        end

        local cfgTable = {}
        do
            if type(readfile) == 'function' then
                local ok, result = pcall(function()
                    local content = readfile(CFG_FILE)
                    if not content or content == '' then return nil end
                    local raw = HttpService_local:JSONDecode(content)
                    if type(raw) == 'table' and raw._version == 2 then
                        -- v2: pull configs through cfgDeserialize (needs JSON string)
                        local configs = cfgDeserialize(HttpService_local:JSONEncode(raw.configs or {}))
                        local cloud   = type(raw.cloud) == 'table' and raw.cloud or {}
                        return { _configs = configs, _cloud = cloud }
                    end
                    -- v1: whole file is the appearance table
                    return { _configs = cfgDeserialize(content), _cloud = {} }
                end)
                if ok and type(result) == 'table' then
                    cfgTable      = result._configs or {}
                    cfgCloudMeta  = result._cloud   or {}
                elseif not ok then
                    showToast('Config file corrupted -- cleared')
                    pcall(function() writefile(CFG_FILE, '{}') end)
                end
            end
        end
        local cfgSelName = ''

        -- helper: is the current user the owner of the cloud entry for `name`?
        local function cfgIsOwner(name)
            local meta = cfgCloudMeta[name]
            return meta ~= nil and plr and meta.owner == plr.UserId
        end

        -- row 1: name input + save + delete
        local r0 = bcRow(34)
        bcLbl(r0, 'Name:', 8, 6, 40, 22)
        local cfgNameInp = bcInp(r0, 'My Config', 52, 6, 124, 22)
        local cfgSaveBtn = bcBtn(r0, 'Save', 182, 6, 50, 22)
        cfgSaveBtn.BackgroundColor3 = ACCENT
        local cfgDelBtn  = bcBtn(r0, 'Delete', 236, 6, 54, 22)
        cfgDelBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)

        -- row 2: dropdown + load button
        local r1 = bcRow(34)

        -- dropdown button (TextButton so the whole area is clickable)
        local cfgDdBtn = Instance.new('TextButton')
        cfgDdBtn.Size = UDim2.new(0, 174, 0, 22); cfgDdBtn.Position = UDim2.new(0, 8, 0, 6)
        cfgDdBtn.BackgroundColor3 = BGSUB; cfgDdBtn.BorderSizePixel = 1; cfgDdBtn.BorderColor3 = BORDER
        cfgDdBtn.Text = ''; cfgDdBtn.ZIndex = 12; cfgDdBtn.Parent = r1

        local cfgDdLbl = Instance.new('TextLabel')
        cfgDdLbl.Size = UDim2.new(1, -22, 1, 0); cfgDdLbl.Position = UDim2.new(0, 6, 0, 0)
        cfgDdLbl.BackgroundTransparency = 1; cfgDdLbl.Text = 'No configs saved'
        cfgDdLbl.TextColor3 = SUBTEXT; cfgDdLbl.Font = Enum.Font.Code; cfgDdLbl.TextSize = 11
        cfgDdLbl.TextXAlignment = Enum.TextXAlignment.Left
        cfgDdLbl.TextTruncate = Enum.TextTruncate.AtEnd
        cfgDdLbl.ZIndex = 13; cfgDdLbl.Parent = cfgDdBtn

        local cfgDdArrow = Instance.new('TextLabel')
        cfgDdArrow.Size = UDim2.new(0, 20, 1, 0); cfgDdArrow.Position = UDim2.new(1, -20, 0, 0)
        cfgDdArrow.BackgroundTransparency = 1; cfgDdArrow.Text = '▼'
        cfgDdArrow.TextColor3 = SUBTEXT; cfgDdArrow.Font = Enum.Font.Code; cfgDdArrow.TextSize = 10
        cfgDdArrow.ZIndex = 13; cfgDdArrow.Parent = cfgDdBtn

        local cfgLoadBtn = bcBtn(r1, 'Load', 188, 6, 52, 22)
        cfgLoadBtn.BackgroundColor3 = ACCENT

        -- dropdown popup (child of panel so it renders above the scroll frame)
        local cfgPopup = Instance.new('Frame')
        cfgPopup.BackgroundColor3 = BGSUB; cfgPopup.BorderSizePixel = 1; cfgPopup.BorderColor3 = BORDER
        cfgPopup.Size = UDim2.new(0, 182, 0, 0); cfgPopup.ZIndex = 30
        cfgPopup.Visible = false; cfgPopup.ClipsDescendants = true; cfgPopup.Parent = panel

        local cfgPopupLayout = Instance.new('UIListLayout')
        cfgPopupLayout.SortOrder = Enum.SortOrder.LayoutOrder
        cfgPopupLayout.Padding = UDim.new(0, 0); cfgPopupLayout.Parent = cfgPopup

        local cfgPopupOpen = false
        local ITEM_H = 22

        -- [C] = cloud-linked, [K] = you own it
        local function cfgTagSuffix(name)
            local meta = cfgCloudMeta[name]
            if not meta then return '' end
            local s = '  [C]'
            if plr and meta.owner == plr.UserId then s = s .. ' [K]' end
            return s
        end

        local refreshCloudUI

        local function cfgUpdateHeaderLabel()
            if cfgSelName == '' then
                cfgDdLbl.Text = 'No configs saved'; cfgDdLbl.TextColor3 = SUBTEXT
            else
                cfgDdLbl.Text = cfgSelName .. cfgTagSuffix(cfgSelName)
                cfgDdLbl.TextColor3 = TEXT
            end
        end

        local function cfgRebuildItems()
            for _, c in ipairs(cfgPopup:GetChildren()) do
                if c:IsA('TextButton') then c:Destroy() end
            end
            local names = {}
            for n in pairs(cfgTable) do table.insert(names, n) end
            table.sort(names)
            for i, name in ipairs(names) do
                local item = Instance.new('TextButton')
                item.Size = UDim2.new(1, 0, 0, ITEM_H)
                item.BackgroundColor3 = (name == cfgSelName) and ACCENT or BGSUB
                item.BorderSizePixel = 0; item.LayoutOrder = i
                item.Text = '  ' .. name .. cfgTagSuffix(name); item.TextColor3 = TEXT
                item.Font = Enum.Font.Code; item.TextSize = 11
                item.TextXAlignment = Enum.TextXAlignment.Left
                item.TextTruncate = Enum.TextTruncate.AtEnd
                item.ZIndex = 31; item.Parent = cfgPopup
                item:SetAttribute('cfgName', name)  -- reliable lookup key
                item.MouseEnter:Connect(function()
                    if name ~= cfgSelName then item.BackgroundColor3 = BG2 end
                end)
                item.MouseLeave:Connect(function()
                    item.BackgroundColor3 = (name == cfgSelName) and ACCENT or BGSUB
                end)
                item.MouseButton1Click:Connect(function()
                    cfgSelName = name
                    cfgUpdateHeaderLabel()
                    cfgPopup.Visible = false; cfgPopupOpen = false; cfgDdArrow.Text = '▼'
                    for _, c2 in ipairs(cfgPopup:GetChildren()) do
                        if c2:IsA('TextButton') then
                            c2.BackgroundColor3 = (c2:GetAttribute('cfgName') == cfgSelName)
                                and ACCENT or BGSUB
                        end
                    end
                    if refreshCloudUI then refreshCloudUI() end
                end)
            end
            return #names
        end

        local function cfgTogglePopup()
            local names = {}; for n in pairs(cfgTable) do table.insert(names, n) end
            if #names == 0 then return end
            cfgPopupOpen = not cfgPopupOpen
            cfgDdArrow.Text = cfgPopupOpen and '▲' or '▼'
            if cfgPopupOpen then
                cfgRebuildItems()
                local popH = math.min(#names, 6) * ITEM_H
                cfgPopup.Size = UDim2.new(0, 182, 0, popH)
                -- position relative to panel using AbsolutePosition
                local relY = cfgDdBtn.AbsolutePosition.Y - panel.AbsolutePosition.Y
                local posY = relY - popH
                if posY < 32 then posY = relY + 22 end
                cfgPopup.Position = UDim2.new(0, 8, 0, posY)
                cfgPopup.Visible = true
            else
                cfgPopup.Visible = false
            end
        end

        cfgDdBtn.MouseButton1Click:Connect(cfgTogglePopup)

        -- show first loaded config name in label if configs came from disk
        do
            local names = {}; for n in pairs(cfgTable) do table.insert(names, n) end
            table.sort(names)
            if #names > 0 then
                cfgSelName = names[1]
                cfgUpdateHeaderLabel()
            end
        end

        -- save (local); cloud meta stays intact for same-name overwrites
        -- v2 payload: { _v=2, parts={[key]=props}, effects={headlight,rainbow} }
        cfgSaveBtn.MouseButton1Click:Connect(function()
            local name = cfgNameInp.Text
            if name == '' then showToast('Enter a config name'); return end
            local model = getTargetModel()
            if not model then showToast('Not on a ' .. VEHICLE_TERM); return end
            local deltas = _G.ppDeltas or {}
            local parts = {}
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA('BasePart') then
                    local key = (p.Parent and p.Parent.Name or '') .. '/' .. p.Name
                    pcall(function()
                        -- per-decal snapshot (children Decals/Textures)
                        local decals = {}
                        for _, ch in ipairs(p:GetChildren()) do
                            if ch:IsA('Decal') or ch:IsA('Texture') then
                                decals[#decals + 1] = {
                                    Class        = ch.ClassName,
                                    Face         = tostring(ch.Face),
                                    Texture      = ch.Texture,
                                    Transparency = ch.Transparency,
                                    Color3       = ch.Color3,
                                }
                            end
                        end
                        local sa = p:FindFirstChildOfClass('SurfaceAppearance')
                        -- Relative transform deltas (only nonzero for parts
                        -- the user actually edited via Advanced Selection).
                        -- Unchanged parts save no transform data at all, so
                        -- loading onto a different bike geometry won't clobber
                        -- welded positions the user never touched.
                        local d = deltas[p]
                        local dP = d and d.pos  or nil
                        local dR = d and d.rot  or nil
                        local dS = d and d.size or nil
                        local zeroVec = Vector3.new()
                        local hasDelta = (dP and dP.Magnitude > 1e-6)
                                      or (dR and dR.Magnitude > 1e-6)
                                      or (dS and dS.Magnitude > 1e-6)
                        parts[key] = {
                            Color        = p.Color,
                            Material     = p.Material,
                            Transparency = p.Transparency,
                            Reflectance  = p.Reflectance,
                            CastShadow   = p.CastShadow,
                            Anchored     = p.Anchored,
                            CanCollide   = p.CanCollide,
                            SAColor      = sa and sa.Color or nil,
                            Decals       = #decals > 0 and decals or nil,
                            dPos         = hasDelta and (dP or zeroVec) or nil,
                            dRot         = hasDelta and (dR or zeroVec) or nil,
                            dSize        = hasDelta and (dS or zeroVec) or nil,
                        }
                    end)
                end
            end
            -- whole-bike effects snapshot
            local effects = { headlight = nil, rainbow = false }
            if effInst.headlight then
                local hl = effInst.headlight
                effects.headlight = {
                    Color      = hl.Color,
                    Brightness = hl.Brightness,
                    Range      = hl.Range,
                    Angle      = hl.Angle,
                }
            end
            effects.rainbow = _G.RainbowConn ~= nil
            -- v3 = relative transform deltas (dPos/dRot/dSize instead of
            -- absolute CFrameRel/Size). v2 files still load, they just skip
            -- the pos/rot/size restore because the old absolute form would
            -- break a bike with different geometry.
            cfgTable[name] = { _v = 3, parts = parts, effects = effects }
            cfgFlushToDisk(cfgTable)
            cfgSelName = name
            cfgUpdateHeaderLabel()
            if refreshCloudUI then refreshCloudUI() end
            showToast('Saved "' .. name .. '"')
        end)

        -- delete (local only); cloud entry survives -- use "Delete from Cloud" for that
        cfgDelBtn.MouseButton1Click:Connect(function()
            if cfgSelName == '' then showToast('No config selected'); return end
            local deleted = cfgSelName
            cfgTable[cfgSelName]     = nil
            cfgCloudMeta[cfgSelName] = nil
            cfgFlushToDisk(cfgTable)
            cfgSelName = ''
            cfgUpdateHeaderLabel()
            cfgPopup.Visible = false; cfgPopupOpen = false; cfgDdArrow.Text = '▼'
            if refreshCloudUI then refreshCloudUI() end
            showToast('Deleted "' .. deleted .. '"')
        end)

        -- load: reapplies every prop the save handler captured; v1 files still
        -- work because parts falls back to the raw table for old configs.
        cfgLoadBtn.MouseButton1Click:Connect(function()
            if cfgSelName == '' then showToast('No config selected'); return end
            local data = cfgTable[cfgSelName]
            if not data then showToast('Config not found'); return end
            local model = getTargetModel()
            if not model then showToast('Not on a ' .. VEHICLE_TERM); return end

            local ver       = data._v or 1
            local isNested  = ver >= 2
            local partsData = isNested and (data.parts or {}) or data
            local effects   = isNested and (data.effects or {}) or nil
            -- v2 stored ABSOLUTE CFrameRel + Size for every part -- restoring
            -- that on a different-shaped bike would destroy welds. Only v3+
            -- (relative dPos/dRot/dSize) applies transforms on load.
            local applyTransforms = ver >= 3

            local applied = 0
            _G.ppDeltas = _G.ppDeltas or {}
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA('BasePart') then
                    local key = (p.Parent and p.Parent.Name or '') .. '/' .. p.Name
                    local d = partsData[key] or partsData[p.Name]
                    if d then
                        pcall(function()
                            if d.Color        then p.Color        = d.Color        end
                            if d.Material     then p.Material     = d.Material     end
                            if d.Transparency then p.Transparency = d.Transparency end
                            if d.Reflectance  then p.Reflectance  = d.Reflectance  end
                            if d.CastShadow ~= nil then p.CastShadow = d.CastShadow end
                            if d.Anchored   ~= nil then p.Anchored   = d.Anchored   end
                            if d.CanCollide ~= nil then p.CanCollide = d.CanCollide end
                            if applyTransforms then
                                -- v3+: add the stored deltas to the current state
                                if d.dPos and d.dPos.Magnitude > 1e-6 then
                                    p.CFrame = p.CFrame + d.dPos
                                end
                                if d.dRot and d.dRot.Magnitude > 1e-6 then
                                    p.CFrame = p.CFrame * CFrame.fromOrientation(
                                        math.rad(d.dRot.X),
                                        math.rad(d.dRot.Y),
                                        math.rad(d.dRot.Z))
                                end
                                if d.dSize and d.dSize.Magnitude > 1e-6 then
                                    p.Size = Vector3.new(
                                        math.max(0.05, p.Size.X + d.dSize.X),
                                        math.max(0.05, p.Size.Y + d.dSize.Y),
                                        math.max(0.05, p.Size.Z + d.dSize.Z))
                                end
                                -- populate ppDeltas so a subsequent re-Save
                                -- carries the loaded deltas forward unchanged
                                if (d.dPos and d.dPos.Magnitude > 1e-6)
                                or (d.dRot and d.dRot.Magnitude > 1e-6)
                                or (d.dSize and d.dSize.Magnitude > 1e-6) then
                                    _G.ppDeltas[p] = {
                                        pos  = d.dPos  or Vector3.new(),
                                        rot  = d.dRot  or Vector3.new(),
                                        size = d.dSize or Vector3.new(),
                                    }
                                end
                            end
                            if d.SAColor then
                                local sa = p:FindFirstChildOfClass('SurfaceAppearance')
                                if sa then sa.Color = d.SAColor end
                            end
                            if d.Decals then
                                -- wipe existing then rebuild from snapshot
                                for _, ch in ipairs(p:GetChildren()) do
                                    if ch:IsA('Decal') or ch:IsA('Texture') then ch:Destroy() end
                                end
                                for _, dd in ipairs(d.Decals) do
                                    local cls  = dd.Class or 'Decal'
                                    local inst = Instance.new(cls)
                                    inst.Texture = dd.Texture or ''
                                    -- Face was serialized as tostring(Enum.NormalId.X)
                                    local faceParts = tostring(dd.Face or ''):split('.')
                                    local faceEnum  = Enum.NormalId.Front
                                    if #faceParts == 3 then
                                        local ok, e = pcall(function()
                                            return Enum[faceParts[2]][faceParts[3]]
                                        end)
                                        if ok and e then faceEnum = e end
                                    end
                                    inst.Face         = faceEnum
                                    inst.Transparency = dd.Transparency or 0
                                    if dd.Color3 then inst.Color3 = dd.Color3 end
                                    inst.Parent = p
                                end
                            end
                        end)
                        applied += 1
                    end
                end
            end
            -- restore whole-bike effects (headlight, rainbow)
            if effects then
                if effects.headlight then
                    local root = getBikeRoot()
                    if root then
                        if effInst.headlight then effInst.headlight:Destroy() end
                        local sl = Instance.new('SpotLight')
                        sl.Color      = effects.headlight.Color      or Color3.new(1,1,1)
                        sl.Brightness = effects.headlight.Brightness or 5
                        sl.Range      = effects.headlight.Range      or 40
                        sl.Angle      = effects.headlight.Angle      or 75
                        sl.Face       = Enum.NormalId.Front
                        sl.Parent     = root
                        effInst.headlight = sl
                        togState.hl = true; bcTogOn(togBtns.hl)
                    end
                elseif effInst.headlight then
                    effInst.headlight:Destroy(); effInst.headlight = nil
                    togState.hl = false; bcTogOff(togBtns.hl)
                end
                -- rainbow is a heartbeat toggle; leave as-is if already matching
            end
            showToast('Loaded "' .. cfgSelName .. '" to ' .. applied .. ' parts')
        end)

        -- cloud UI: row 2 = id/download/copy, row 3 = upload/delete/rename
        -- row 2
        local r2 = bcRow(34)
        bcLbl(r2, 'Cloud ID:', 8, 6, 60, 22)
        local cldIdInp = bcInp(r2, '', 72, 6, 92, 22)
        cldIdInp.PlaceholderText  = 'XXXXXXXX'
        cldIdInp.PlaceholderColor3 = SUBTEXT
        local cldDlBtn = bcBtn(r2, 'Download from Cloud', 170, 6, 160, 22)
        cldDlBtn.BackgroundColor3 = ACCENT
        -- Copy ID -- any cloud-linked config, setclipboard-or-toast
        local cldCopyBtn = bcBtn(r2, 'Copy ID', 336, 6, 66, 22)

        -- row 3: upload / overwrite / delete / rename (contextual visibility)
        local r3 = bcRow(34)
        local cldUpBtn = bcBtn(r3, 'Upload to Cloud', 8, 6, 130, 22)
        cldUpBtn.BackgroundColor3 = ACCENT
        local cldDelBtn = bcBtn(r3, 'Delete from Cloud', 142, 6, 130, 22)
        cldDelBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
        local cldRnBtn = bcBtn(r3, 'Rename Cloud', 276, 6, 100, 22)

        -- upload always visible, copy shows for cloud-linked, delete/rename owner-only
        refreshCloudUI = function()
            local has   = cfgSelName ~= '' and cfgTable[cfgSelName] ~= nil
            local meta  = has and cfgCloudMeta[cfgSelName] or nil
            local owner = has and cfgIsOwner(cfgSelName)

            cldUpBtn.Visible   = true
            cldCopyBtn.Visible = meta ~= nil
            cldDelBtn.Visible  = has and owner and meta ~= nil
            cldRnBtn.Visible   = has and owner and meta ~= nil
            cldUpBtn.Text      = (has and owner and meta) and 'Overwrite to Cloud' or 'Upload to Cloud'
        end
        refreshCloudUI()

        cldCopyBtn.MouseButton1Click:Connect(function()
            local meta = cfgCloudMeta[cfgSelName]
            if not meta or not meta.id then
                showToast('Selected config is not cloud-linked'); return
            end
            if setclipboard then
                local ok = pcall(setclipboard, meta.id)
                if ok then showToast('Copied ID ' .. meta.id); return end
            end
            showToast('ID: ' .. meta.id .. ' (no clipboard access)')
        end)

        -- ---- download from cloud ----
        cldDlBtn.MouseButton1Click:Connect(function()
            local id = (cldIdInp.Text or ''):upper():gsub('%s+', '')
            if id == '' or #id ~= 8 then
                showToast('Enter an 8-char cloud ID'); return
            end
            showToast('Downloading ' .. id .. '...')
            task.spawn(function()
                local doc, err = cloudCall('GET', '/config/' .. id)
                if not doc then showToast('Download failed: ' .. err); return end

                -- doc.data is the appearance table serialized just like the
                -- local format: {[partKey] = {Color3-wrapped, EnumItem-wrapped, ...}}
                -- Round-trip it through cfgDeserialize so Color3/Material are rehydrated.
                local rehydrated
                local rok, rerr = pcall(function()
                    rehydrated = cfgDeserialize(HttpService_local:JSONEncode({ tmp = doc.data })).tmp
                end)
                if not rok or not rehydrated then
                    showToast('Bad cloud data: ' .. tostring(rerr)); return
                end

                -- name-collision handling: append the ID if a local config
                -- already lives at doc.name.
                local localName = doc.name or ('cloud-' .. id)
                if cfgTable[localName] and cfgCloudMeta[localName]
                   and cfgCloudMeta[localName].id ~= id then
                    localName = localName .. ' (' .. id .. ')'
                end

                cfgTable[localName] = rehydrated
                cfgCloudMeta[localName] = {
                    id        = id,
                    owner     = doc.owner,
                    ownerName = doc.ownerName or '',
                    cloudName = doc.name or localName,
                }
                cfgFlushToDisk(cfgTable)
                cfgSelName = localName
                cfgUpdateHeaderLabel()
                refreshCloudUI()
                showToast('Downloaded "' .. localName .. '"')
            end)
        end)

        cldUpBtn.MouseButton1Click:Connect(function()
            if cfgSelName == '' then showToast('No config selected'); return end
            local data = cfgTable[cfgSelName]
            if not data then showToast('Config not found'); return end

            -- serialize to the JSON-friendly wrapped form and hand the parsed
            -- table to the worker so it stores an object (not a string blob).
            local serialized = HttpService_local:JSONDecode(cfgSerialize({ tmp = data })).tmp

            local meta   = cfgCloudMeta[cfgSelName]
            local isOwn  = meta and cfgIsOwner(cfgSelName)
            local userId = plr and plr.UserId or 0
            local userNm = plr and plr.Name   or 'unknown'

            if isOwn then
                -- overwrite existing cloud entry (actor via ?query, not body)
                showToast('Overwriting ' .. meta.id .. '...')
                task.spawn(function()
                    local doc, err = cloudCall('PUT',
                        '/config/' .. meta.id .. '?actor=' .. userId,
                        { name = meta.cloudName, data = serialized })
                    if not doc then showToast('Overwrite failed: ' .. err); return end
                    cfgCloudMeta[cfgSelName].cloudName = doc.name
                    cfgFlushToDisk(cfgTable)
                    showToast('Overwrote ' .. meta.id)
                end)
            else
                -- create new cloud entry (owner = you, even if we started from
                -- a downloaded config from someone else)
                showToast('Uploading "' .. cfgSelName .. '"...')
                task.spawn(function()
                    local doc, err = cloudCall('POST', '/config', {
                        name = cfgSelName, owner = userId, ownerName = userNm,
                        data = serialized,
                    })
                    if not doc then showToast('Upload failed: ' .. err); return end
                    cfgCloudMeta[cfgSelName] = {
                        id        = doc.id,
                        owner     = doc.owner,
                        ownerName = doc.ownerName or userNm,
                        cloudName = doc.name,
                    }
                    cfgFlushToDisk(cfgTable)
                    cfgUpdateHeaderLabel()
                    cfgPopup.Visible = false; cfgPopupOpen = false; cfgDdArrow.Text = '▼'
                    refreshCloudUI()
                    if setclipboard then pcall(setclipboard, doc.id) end
                    showToast('Uploaded! ID: ' .. doc.id
                        .. (setclipboard and ' (copied)' or ''))
                end)
            end
        end)

        cldDelBtn.MouseButton1Click:Connect(function()
            local meta = cfgCloudMeta[cfgSelName]
            if not meta or not cfgIsOwner(cfgSelName) then
                showToast('Not the owner'); return
            end
            local id = meta.id
            showToast('Deleting ' .. id .. ' from cloud...')
            task.spawn(function()
                -- actor in URL (executors sometimes strip DELETE bodies)
                local ok, err = cloudCall('DELETE',
                    '/config/' .. id .. '?actor=' .. plr.UserId)
                if not ok then showToast('Delete failed: ' .. err); return end
                -- local copy stays; only the cloud entry + metadata go away
                cfgCloudMeta[cfgSelName] = nil
                cfgFlushToDisk(cfgTable)
                cfgUpdateHeaderLabel()
                refreshCloudUI()
                showToast('Deleted ' .. id .. ' from cloud')
            end)
        end)

        cldRnBtn.MouseButton1Click:Connect(function()
            local meta = cfgCloudMeta[cfgSelName]
            if not meta or not cfgIsOwner(cfgSelName) then
                showToast('Not the owner'); return
            end
            local newName = cfgSelName  -- the local name IS the new cloud name
            showToast('Renaming cloud entry...')
            task.spawn(function()
                local doc, err = cloudCall('PATCH',
                    '/config/' .. meta.id .. '?actor=' .. plr.UserId,
                    { name = newName })
                if not doc then showToast('Rename failed: ' .. err); return end
                cfgCloudMeta[cfgSelName].cloudName = doc.name
                cfgFlushToDisk(cfgTable)
                showToast('Renamed cloud to "' .. doc.name .. '"')
            end)
        end)
    end
end

-- ============================================================


-- ============================================================
-- PART PICKER WINDOW  (Dex-style tree explorer)
-- ============================================================
do
    -- in-game SelectionBoxes; stored in-place so _G ref stays valid
    local ppSelBoxes = {}
    _G.PPSelBoxes    = ppSelBoxes

    -- widget registry (packed into one local so the color picker stays under
    -- Luau's 200-live-locals cap); must sit before the X handler references it
    local ppI            = {}
    local ppInvisOnly    = false
    local ppMouseSelOn   = false
    local ppPropsOn      = true   -- Properties (right pane) visible by default
    local ppPickedColor  = Color3.fromRGB(255, 80, 80)
    local ppCPOpen       = false
    local ppRefreshInspector  -- assigned in the wiring block
    local ppUndoable          -- assigned in the wiring block; Hide/Unhide
                              -- fire before its lexical declaration, so
                              -- forward-declare or the closures resolve nil
    local ppVisualCache = {}  -- [realPart] = {ghost, posDelta, rotOffset,
                              -- sizeOverride, origLTM}; wireMove/wireRot/
                              -- wireSize check this to update the ghost
                              -- offset instead of the real part when
                              -- Visual Only is on. Hoisted so the gizmo
                              -- wire fns (lexically higher) can see it.
    local ppShowContextMenu   -- right-click popup: {Delete}. Assigned below.

    local pp = Instance.new('ScreenGui')
    pp.Name           = 'PartPickerGui'
    pp.ResetOnSpawn   = false
    pp.DisplayOrder   = 1002 -- above customizer (1001), below undo (1005); was 996 (hidden behind Linoria)
    pp.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pp.Enabled        = false
    safeParentGui(pp)
    partPickerGui     = pp

    -- 640 = 360 tree | 1 divider | 279 inspector
    local ppanel = Instance.new('Frame')
    ppanel.Size             = UDim2.new(0, 640, 0, 580)
    ppanel.Position         = UDim2.new(0.5, -60, 0.5, -290)
    ppanel.BackgroundColor3 = BG2
    ppanel.BorderSizePixel  = 1
    ppanel.BorderColor3     = BORDER
    ppanel.Active           = true
    ppanel.ZIndex           = 10
    ppanel.Parent           = pp
    ppI.panel = ppanel  -- expose for Properties toggle width flip

    do -- drag
        local drag, dragStart, startPos = false, nil, nil
        ppanel.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                drag = true; dragStart = inp.Position; startPos = ppanel.Position
            end
        end)
        ppanel.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
        end)
        UIS.InputChanged:Connect(function(inp)
            if drag and inp.UserInputType == Enum.UserInputType.MouseMovement then
                local d = inp.Position - dragStart
                ppanel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                            startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    -- ---- title bar (32 px) ----
    local ppTBar = Instance.new('Frame')
    ppTBar.Size             = UDim2.new(1, 0, 0, 32)
    ppTBar.BackgroundColor3 = BGSUB
    ppTBar.BorderSizePixel  = 0
    ppTBar.ZIndex           = 11
    ppTBar.Parent           = ppanel

    local ppCountLbl = Instance.new('TextLabel')
    ppCountLbl.Size = UDim2.new(0, 90, 1, 0); ppCountLbl.Position = UDim2.new(1, -122, 0, 0)
    ppCountLbl.BackgroundTransparency = 1; ppCountLbl.Text = '0 selected'
    ppCountLbl.TextColor3 = SUBTEXT; ppCountLbl.Font = Enum.Font.Code; ppCountLbl.TextSize = 11
    ppCountLbl.TextXAlignment = Enum.TextXAlignment.Right
    ppCountLbl.ZIndex = 12; ppCountLbl.Parent = ppTBar

    do
        local tl = Instance.new('TextLabel')
        tl.Size = UDim2.new(1, -130, 1, 0); tl.Position = UDim2.new(0, 10, 0, 0)
        tl.BackgroundTransparency = 1; tl.Text = 'Advanced Selection'
        tl.TextColor3 = TEXT; tl.Font = Enum.Font.Code
        tl.TextSize = 14; tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.ZIndex = 12; tl.Parent = ppTBar

        local xb = Instance.new('TextButton')
        xb.Size = UDim2.new(0, 32, 0, 32); xb.Position = UDim2.new(1, -32, 0, 0)
        xb.BackgroundColor3 = Color3.fromRGB(180, 50, 50); xb.BorderSizePixel = 0
        xb.Text = 'X'; xb.TextColor3 = TEXT; xb.Font = Enum.Font.Code
        xb.TextSize = 13; xb.ZIndex = 12; xb.Parent = ppTBar
        xb.MouseButton1Click:Connect(function()
            -- clear outlines + gizmos when window is closed
            for k, sb in pairs(ppSelBoxes) do
                pcall(function() sb:Destroy() end); ppSelBoxes[k] = nil
            end
            if ppI.destroyGizmos then ppI.destroyGizmos() end
            pp.Enabled = false
        end)
    end

    -- ---- toolbar (30 px, left column only) ----
    local ppCtrl = Instance.new('Frame')
    ppCtrl.Size             = UDim2.new(0, 360, 0, 30)
    ppCtrl.Position         = UDim2.new(0, 0, 0, 32)
    ppCtrl.BackgroundColor3 = BGSUB
    ppCtrl.BorderSizePixel  = 0
    ppCtrl.ZIndex           = 11
    ppCtrl.Parent           = ppanel

    do -- separator line under toolbar
        local ln = Instance.new('Frame')
        ln.Size = UDim2.new(1, 0, 0, 1); ln.Position = UDim2.new(0, 0, 1, -1)
        ln.BackgroundColor3 = BORDER; ln.BorderSizePixel = 0; ln.ZIndex = 12; ln.Parent = ppCtrl
    end

    local function ppToolBtn(text, x, w)
        local b = Instance.new('TextButton')
        b.Size = UDim2.new(0, w, 0, 22); b.Position = UDim2.new(0, x, 0, 4)
        b.BackgroundColor3 = BGSUB; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = text; b.TextColor3 = TEXT; b.Font = Enum.Font.Code; b.TextSize = 11
        b.ZIndex = 12; b.Parent = ppCtrl
        return b
    end
    local ppRefreshBtn    = ppToolBtn('Refresh',      4,  82)
    local ppExpandBtn     = ppToolBtn('Expand All',   90,  78)
    local ppCollapseBtn   = ppToolBtn('Collapse All', 172,  88)
    local ppDeselectBtn   = ppToolBtn('Deselect All', 264,  88)

    -- filter/mode bar: Show Invisible Only | Mouse Selection
    local ppFilterBar = Instance.new('Frame')
    ppFilterBar.Size             = UDim2.new(0, 360, 0, 26)
    ppFilterBar.Position         = UDim2.new(0, 0, 0, 32 + 31)
    ppFilterBar.BackgroundColor3 = BGSUB
    ppFilterBar.BorderSizePixel  = 0
    ppFilterBar.ZIndex           = 11
    ppFilterBar.Parent           = ppanel

    do -- separator line under filter bar
        local ln = Instance.new('Frame')
        ln.Size = UDim2.new(1, 0, 0, 1); ln.Position = UDim2.new(0, 0, 1, -1)
        ln.BackgroundColor3 = BORDER; ln.BorderSizePixel = 0
        ln.ZIndex = 12; ln.Parent = ppFilterBar
    end

    -- shared factory for checkbox + label pair -- returns (box, check, lblBtn)
    local function ppMakeCheck(chkX, lblX, lblW, labelText)
        local box = Instance.new('TextButton')
        box.Size = UDim2.new(0, 14, 0, 14)
        box.Position = UDim2.new(0, chkX, 0.5, -7)
        box.BackgroundColor3 = BG2; box.BorderSizePixel = 1; box.BorderColor3 = BORDER
        box.Text = ''; box.AutoButtonColor = false
        box.ZIndex = 12; box.Parent = ppFilterBar
        local check = Instance.new('Frame')
        check.Size = UDim2.new(0, 8, 0, 8)
        check.Position = UDim2.new(0.5, -4, 0.5, -4)
        check.BackgroundColor3 = ACCENT; check.BorderSizePixel = 0
        check.Visible = false; check.ZIndex = 13; check.Parent = box
        local lbl = Instance.new('TextLabel')
        lbl.Size = UDim2.new(0, lblW, 1, 0)
        lbl.Position = UDim2.new(0, lblX, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText; lbl.TextColor3 = TEXT
        lbl.Font = Enum.Font.Code; lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 12; lbl.Parent = ppFilterBar
        local lblBtn = Instance.new('TextButton')
        lblBtn.Size = lbl.Size; lblBtn.Position = lbl.Position
        lblBtn.BackgroundTransparency = 1; lblBtn.Text = ''
        lblBtn.AutoButtonColor = false; lblBtn.ZIndex = 13; lblBtn.Parent = ppFilterBar
        return box, check, lblBtn
    end

    -- three checks fit across 360w by trimming labels and tightening pitch
    ppI.invisBtn, ppI.invisCheck, ppI.invisLblBtn =
        ppMakeCheck(  8,  28, 100, 'Show Invisible')
    ppI.mouseBtn, ppI.mouseCheck, ppI.mouseLblBtn =
        ppMakeCheck(132, 152,  90, 'Mouse Select')
    ppI.propsBtn, ppI.propsCheck, ppI.propsLblBtn =
        ppMakeCheck(246, 266,  90, 'Properties')

    -- search bar: substring filter, ancestors of matches stay visible
    local ppSearchBar = Instance.new('Frame')
    ppSearchBar.Size             = UDim2.new(0, 360, 0, 26)
    ppSearchBar.Position         = UDim2.new(0, 0, 0, 32 + 31 + 27)
    ppSearchBar.BackgroundColor3 = BGSUB
    ppSearchBar.BorderSizePixel  = 0
    ppSearchBar.ZIndex           = 11
    ppSearchBar.Parent           = ppanel

    do -- separator line under the search bar
        local ln = Instance.new('Frame')
        ln.Size = UDim2.new(1, 0, 0, 1); ln.Position = UDim2.new(0, 0, 1, -1)
        ln.BackgroundColor3 = BORDER; ln.BorderSizePixel = 0
        ln.ZIndex = 12; ln.Parent = ppSearchBar
    end

    local ppSearchBox = Instance.new('TextBox')
    ppSearchBox.Size                = UDim2.new(1, -12, 0, 20)
    ppSearchBox.Position            = UDim2.new(0, 6, 0, 3)
    ppSearchBox.BackgroundColor3    = BG2
    ppSearchBox.BorderSizePixel     = 1
    ppSearchBox.BorderColor3        = BORDER
    ppSearchBox.Text                = ''
    ppSearchBox.PlaceholderText     = 'Search parts...'
    ppSearchBox.PlaceholderColor3   = SUBTEXT
    ppSearchBox.TextColor3          = TEXT
    ppSearchBox.Font                = Enum.Font.Code
    ppSearchBox.TextSize            = 11
    ppSearchBox.TextXAlignment      = Enum.TextXAlignment.Left
    ppSearchBox.ClearTextOnFocus    = false
    ppSearchBox.ZIndex              = 12
    ppSearchBox.Parent              = ppSearchBar
    do
        local pad = Instance.new('UIPadding')
        pad.PaddingLeft  = UDim.new(0, 6)
        pad.PaddingRight = UDim.new(0, 6)
        pad.Parent       = ppSearchBox
    end
    ppSearchBox.Focused:Connect(function() ppSearchBox.BorderColor3 = ACCENT end)
    ppSearchBox.FocusLost:Connect(function() ppSearchBox.BorderColor3 = BORDER end)

    -- tree scroll: 32 title + 31 toolbar + 27 filter + 27 search = 117 top
    local ppScroll = Instance.new('ScrollingFrame')
    ppScroll.Size                  = UDim2.new(0, 360, 1, -(32 + 31 + 27 + 27))
    ppScroll.Position              = UDim2.new(0, 0, 0, 32 + 31 + 27 + 27)
    ppScroll.BackgroundColor3      = BG2
    ppScroll.BackgroundTransparency = 0
    ppScroll.BorderSizePixel       = 0
    ppScroll.ScrollBarThickness    = 5
    ppScroll.ScrollBarImageColor3  = BORDER
    ppScroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
    ppScroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    ppScroll.ZIndex                = 11
    ppScroll.Parent                = ppanel

    local ppLayout = Instance.new('UIListLayout')
    ppLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ppLayout.Padding   = UDim.new(0, 0)
    ppLayout.Parent    = ppScroll

    -- right pane (property inspector); do-block frees the widget-build locals
    do
    local ppVDivider = Instance.new('Frame')
    ppVDivider.Size             = UDim2.new(0, 1, 1, -32)
    ppVDivider.Position         = UDim2.new(0, 360, 0, 32)
    ppVDivider.BackgroundColor3 = BORDER
    ppVDivider.BorderSizePixel  = 0
    ppVDivider.ZIndex           = 12
    ppVDivider.Parent           = ppanel
    ppI.vDivider = ppVDivider  -- expose so the Properties toggle can hide it

    local ppRScroll = Instance.new('ScrollingFrame')
    ppRScroll.Size                  = UDim2.new(0, 279, 1, -32)
    ppRScroll.Position              = UDim2.new(0, 361, 0, 32)
    ppRScroll.BackgroundColor3      = BG2
    ppRScroll.BorderSizePixel       = 0
    ppRScroll.ScrollBarThickness    = 5
    ppRScroll.ScrollBarImageColor3  = BORDER
    ppRScroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
    ppRScroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    ppRScroll.ZIndex                = 11
    ppRScroll.Parent                = ppanel
    ppI.rScroll = ppRScroll  -- expose so the Properties toggle can hide it

    -- inspector layout helpers; ppRY is the running Y offset
    local ppRY = 6
    local function ppSect(label)
        if ppRY > 6 then ppRY = ppRY + 8 end
        local l = Instance.new('TextLabel')
        l.Size = UDim2.new(1, -24, 0, 16); l.Position = UDim2.new(0, 12, 0, ppRY)
        l.BackgroundTransparency = 1; l.Text = label; l.TextColor3 = ACCENT
        l.Font = Enum.Font.Code; l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 12; l.Parent = ppRScroll
        local rule = Instance.new('Frame')
        rule.Size = UDim2.new(1, -24, 0, 1); rule.Position = UDim2.new(0, 12, 0, ppRY + 17)
        rule.BackgroundColor3 = ACCENT; rule.BackgroundTransparency = 0.55
        rule.BorderSizePixel = 0; rule.ZIndex = 12; rule.Parent = ppRScroll
        ppRY = ppRY + 24
    end
    local function ppRow(h) local y = ppRY; ppRY = ppRY + (h or 26); return y end
    local function ppRLbl(text, x, y, w, color)
        local l = Instance.new('TextLabel')
        l.Size = UDim2.new(0, w or 100, 0, 18); l.Position = UDim2.new(0, x or 12, 0, y)
        l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = color or SUBTEXT
        l.Font = Enum.Font.Code; l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 12; l.Parent = ppRScroll
        return l
    end
    local function ppRInp(text, x, y, w)
        local b = Instance.new('TextBox')
        b.Size = UDim2.new(0, w or 60, 0, 22); b.Position = UDim2.new(0, x, 0, y)
        b.BackgroundColor3 = BG2; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = text or ''; b.TextColor3 = TEXT; b.Font = Enum.Font.Code
        b.TextSize = 11; b.ClearTextOnFocus = false; b.ZIndex = 12; b.Parent = ppRScroll
        b.Focused:Connect(function() b.BorderColor3 = ACCENT end)
        b.FocusLost:Connect(function() b.BorderColor3 = BORDER end)
        return b
    end
    local function ppRBtn(text, x, y, w, accent)
        local b = Instance.new('TextButton')
        b.Size = UDim2.new(0, w or 80, 0, 22); b.Position = UDim2.new(0, x, 0, y)
        b.BackgroundColor3 = accent and ACCENT or BGSUB
        b.BorderSizePixel = accent and 0 or 1; b.BorderColor3 = BORDER
        b.Text = text; b.TextColor3 = TEXT; b.Font = Enum.Font.Code
        b.TextSize = 11; b.AutoButtonColor = false; b.ZIndex = 12; b.Parent = ppRScroll
        if not accent then
            b.MouseEnter:Connect(function()
                if b.BackgroundColor3 == BGSUB then b.BackgroundColor3 = BORDER end
            end)
            b.MouseLeave:Connect(function()
                if b.BackgroundColor3 == BORDER then b.BackgroundColor3 = BGSUB end
            end)
        end
        return b
    end
    local function ppRTog(x, y, w, initialOn)
        local b = Instance.new('TextButton')
        b.Size = UDim2.new(0, w or 60, 0, 22); b.Position = UDim2.new(0, x, 0, y)
        b.BackgroundColor3 = initialOn and ACCENT or BGSUB
        b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = initialOn and 'ON' or 'OFF'
        b.TextColor3 = initialOn and TEXT or SUBTEXT
        b.Font = Enum.Font.Code; b.TextSize = 11; b.AutoButtonColor = false
        b.ZIndex = 12; b.Parent = ppRScroll
        return b
    end
    ppI.setTog = function(b, on)
        b.BackgroundColor3 = on and ACCENT or BGSUB
        b.TextColor3 = on and TEXT or SUBTEXT
        b.Text = on and 'ON' or 'OFF'
    end

    -- dropdown popup parents to ScreenGui so it renders clip-free over ppanel
    local ppDDs = {}
    local function ppMakeDropdown(x, y, w, options, initial, onSelect)
        local btn = Instance.new('TextButton')
        btn.Size = UDim2.new(0, w or 120, 0, 22); btn.Position = UDim2.new(0, x, 0, y)
        btn.BackgroundColor3 = BG2; btn.BorderSizePixel = 1; btn.BorderColor3 = BORDER
        btn.Text = ' ' .. tostring(initial) .. '   v'
        btn.TextColor3 = TEXT; btn.Font = Enum.Font.Code; btn.TextSize = 11
        btn.TextXAlignment = Enum.TextXAlignment.Left; btn.AutoButtonColor = false
        btn.ZIndex = 12; btn.Parent = ppRScroll

        local popup = Instance.new('Frame')
        popup.BackgroundColor3 = BGSUB; popup.BorderSizePixel = 1; popup.BorderColor3 = BORDER
        popup.Visible = false; popup.ZIndex = 40; popup.Parent = pp

        local popupScroll = Instance.new('ScrollingFrame')
        popupScroll.Size = UDim2.new(1, 0, 1, 0)
        popupScroll.BackgroundTransparency = 1; popupScroll.BorderSizePixel = 0
        popupScroll.ScrollBarThickness = 4; popupScroll.ScrollBarImageColor3 = BORDER
        popupScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        popupScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        popupScroll.ZIndex = 41; popupScroll.Parent = popup

        local lay = Instance.new('UIListLayout')
        lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = popupScroll

        local dd = { btn = btn, popup = popup, value = initial }

        for i, opt in ipairs(options) do
            local item = Instance.new('TextButton')
            item.Size = UDim2.new(1, 0, 0, 20); item.LayoutOrder = i
            item.BackgroundColor3 = BGSUB; item.BorderSizePixel = 0
            item.Text = '  ' .. tostring(opt); item.TextColor3 = TEXT
            item.Font = Enum.Font.Code; item.TextSize = 11
            item.TextXAlignment = Enum.TextXAlignment.Left
            item.AutoButtonColor = false; item.ZIndex = 42; item.Parent = popupScroll
            item.MouseEnter:Connect(function() item.BackgroundColor3 = BORDER end)
            item.MouseLeave:Connect(function() item.BackgroundColor3 = BGSUB end)
            item.MouseButton1Click:Connect(function()
                dd.value = opt
                btn.Text = ' ' .. tostring(opt) .. '   v'
                popup.Visible = false
                if onSelect then onSelect(opt) end
            end)
        end
        ppDDs[#ppDDs + 1] = dd

        btn.MouseButton1Click:Connect(function()
            if popup.Visible then popup.Visible = false; return end
            for _, other in ipairs(ppDDs) do
                if other ~= dd then other.popup.Visible = false end
            end
            local ap = btn.AbsolutePosition
            local sz = btn.AbsoluteSize
            popup.Position = UDim2.new(0, ap.X, 0, ap.Y + sz.Y + 1)
            popup.Size     = UDim2.new(0, sz.X, 0, math.min(#options * 20, 200))
            popup.Visible = true
        end)
        return dd
    end
    -- click-away closes any open dropdown
    UIS.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local mp = UIS:GetMouseLocation()
        for _, dd in ipairs(ppDDs) do
            if dd.popup.Visible then
                local pAP, pSZ = dd.popup.AbsolutePosition, dd.popup.AbsoluteSize
                local bAP, bSZ = dd.btn.AbsolutePosition,   dd.btn.AbsoluteSize
                local inPopup = mp.X >= pAP.X and mp.X <= pAP.X + pSZ.X
                            and mp.Y >= pAP.Y and mp.Y <= pAP.Y + pSZ.Y
                local inBtn   = mp.X >= bAP.X and mp.X <= bAP.X + bSZ.X
                            and mp.Y >= bAP.Y and mp.Y <= bAP.Y + bSZ.Y
                if not inPopup and not inBtn then dd.popup.Visible = false end
            end
        end
    end)

    -- (ppPickedColor / ppCPOpen / ppRefreshInspector are all hoisted
    -- above the filter bar so they survive the wrapping do-block below.)

    -- horizontal slider [0..1]; returns { setValue(v) } for external pushes
    local function ppMakeSlider(x, y, w, initial, onChange)
        initial = math.clamp(initial or 0, 0, 1)
        local track = Instance.new('Frame')
        track.Size = UDim2.new(0, w, 0, 6); track.Position = UDim2.new(0, x, 0, y + 8)
        track.BackgroundColor3 = BG2; track.BorderSizePixel = 1; track.BorderColor3 = BORDER
        track.ZIndex = 12; track.Parent = ppRScroll

        local fill = Instance.new('Frame')
        fill.Size = UDim2.new(initial, 0, 1, 0); fill.Position = UDim2.new(0, 0, 0, 0)
        fill.BackgroundColor3 = ACCENT; fill.BorderSizePixel = 0
        fill.ZIndex = 13; fill.Parent = track

        local knob = Instance.new('Frame')
        knob.Size = UDim2.new(0, 10, 0, 14); knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.new(initial, 0, 0.5, 0)
        knob.BackgroundColor3 = ACCENT; knob.BorderSizePixel = 1; knob.BorderColor3 = BORDER
        knob.ZIndex = 14; knob.Parent = track

        -- oversized invisible hit area (14px tall) so the track is easier to grab
        local hit = Instance.new('TextButton')
        hit.Size = UDim2.new(1, 0, 0, 20); hit.Position = UDim2.new(0, 0, 0, -7)
        hit.BackgroundTransparency = 1; hit.Text = ''; hit.AutoButtonColor = false
        hit.ZIndex = 15; hit.Parent = track

        local dragging = false
        local function pushValue(mouseX)
            local abs = track.AbsolutePosition
            local sz  = track.AbsoluteSize
            local v   = math.clamp((mouseX - abs.X) / sz.X, 0, 1)
            fill.Size     = UDim2.new(v, 0, 1, 0)
            knob.Position = UDim2.new(v, 0, 0.5, 0)
            if onChange then onChange(v) end
        end
        hit.MouseButton1Down:Connect(function()
            dragging = true; pushValue(UIS:GetMouseLocation().X)
        end)
        UIS.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
               or input.UserInputType == Enum.UserInputType.Touch then
                pushValue(input.Position.X)
            end
        end)
        UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)

        return { setValue = function(v)
            v = math.clamp(v or 0, 0, 1)
            fill.Size     = UDim2.new(v, 0, 1, 0)
            knob.Position = UDim2.new(v, 0, 0.5, 0)
        end }
    end

    -- ============ SECTION: SELECTION ============
    ppSect('SELECTION')
    local _y = ppRow(20)
    ppI.selLbl   = ppRLbl('0 parts',     12, _y, 240, TEXT)
    _y = ppRow(22)
    ppI.decalLbl = ppRLbl('Decal: false', 12, _y, 240, SUBTEXT)

    -- ============ SECTION: APPEARANCE ============
    ppSect('APPEARANCE')

    -- Material dropdown -- live-applies on select
    _y = ppRow(28)
    ppRLbl('Material', 12, _y + 3, 60)
    local MATERIALS = {
        'Plastic', 'SmoothPlastic', 'Metal', 'DiamondPlate', 'Neon', 'ForceField',
        'Glass', 'Ice', 'Brick', 'Slate', 'Concrete', 'Cobblestone',
        'Fabric', 'Wood', 'WoodPlanks', 'Sand', 'Grass', 'Foil',
        'Marble', 'Granite', 'Sandstone', 'Pebble', 'CorrodedMetal', 'Basalt',
    }
    -- dropdown only stores the picked material; Apply next to it commits it
    ppI.matDD  = ppMakeDropdown(78, _y, 114, MATERIALS, 'SmoothPlastic', nil)
    ppI.matBtn = ppRBtn('Apply', 196, _y, 60)

    -- Color: swatch + hex + Paint (Swatch/HexBox keep original names for
    -- the color picker + hex-sync code lower in the do block)
    _y = ppRow(28)
    ppRLbl('Color', 12, _y + 3, 60)
    ppI.swatch = Instance.new('TextButton')
    ppI.swatch.Size = UDim2.new(0, 22, 0, 22); ppI.swatch.Position = UDim2.new(0, 78, 0, _y)
    ppI.swatch.BackgroundColor3 = ppPickedColor; ppI.swatch.BorderSizePixel = 1
    ppI.swatch.BorderColor3 = BORDER; ppI.swatch.Text = ''; ppI.swatch.AutoButtonColor = false
    ppI.swatch.ZIndex = 12; ppI.swatch.Parent = ppRScroll
    ppI.hexBox = Instance.new('TextBox')
    ppI.hexBox.Size = UDim2.new(0, 76, 0, 22); ppI.hexBox.Position = UDim2.new(0, 104, 0, _y)
    ppI.hexBox.BackgroundColor3 = BG2; ppI.hexBox.BorderSizePixel = 1; ppI.hexBox.BorderColor3 = BORDER
    ppI.hexBox.Text = 'FF5050'; ppI.hexBox.TextColor3 = TEXT; ppI.hexBox.Font = Enum.Font.Code
    ppI.hexBox.TextSize = 11; ppI.hexBox.ClearTextOnFocus = false
    ppI.hexBox.ZIndex = 12; ppI.hexBox.Parent = ppRScroll
    ppI.hexBox.Focused:Connect(function()  ppI.hexBox.BorderColor3 = ACCENT end)
    ppI.hexBox.FocusLost:Connect(function() ppI.hexBox.BorderColor3 = BORDER end)
    ppI.applyBtn = ppRBtn('Paint', 186, _y, 70, true)

    -- Transparency (0..1) -- number box + Apply
    _y = ppRow(28)
    ppRLbl('Transparency', 12, _y + 3, 90)
    ppI.transIn  = ppRInp('0',     108, _y, 58)
    ppI.transBtn = ppRBtn('Apply', 172, _y, 84)

    -- slider: live-apply, syncs the number box, skips fully-invisible parts
    _y = ppRow(20)
    ppI.transSlider = ppMakeSlider(12, _y, 244, 0, function(v)
        ppI.transIn.Text = string.format('%.2f', v)
        local function touch(p)
            if p.Transparency < 1 then pcall(function() p.Transparency = v end) end
        end
        for inst in pairs(ppSelBoxes) do
            if inst and inst.Parent then
                if inst:IsA('BasePart') then touch(inst)
                else
                    for _, d in ipairs(inst:GetDescendants()) do
                        if d:IsA('BasePart') then touch(d) end
                    end
                end
            end
        end
    end)

    -- Reflectance (0..1)
    _y = ppRow(28)
    ppRLbl('Reflectance',  12, _y + 3, 90)
    ppI.reflIn  = ppRInp('0',     108, _y, 58)
    ppI.reflBtn = ppRBtn('Apply', 172, _y, 84)

    -- TRANSFORM: Pos / Rot (deg) / Size XYZ, primary populates on refresh
    ppSect('TRANSFORM')

    -- Visual Only: makes selected parts physically inert (Massless + no
    -- collide) so transforms don't fight the driving physics or push the
    -- rider. Weld still holds the part to the bike; just no mass or collide.
    _y = ppRow(28); ppRLbl('Visual Only', 12, _y + 3, 90)
    ppI.visOnlyTog = ppRTog(196, _y, 60, false)

    _y = ppRow(28); ppRLbl('Pos',  12, _y + 3, 30)
    ppI.posX = ppRInp('0',  46, _y, 40)
    ppI.posY = ppRInp('0',  90, _y, 40)
    ppI.posZ = ppRInp('0', 134, _y, 40)
    ppI.posBtn = ppRBtn('Apply', 178, _y, 78)

    _y = ppRow(28); ppRLbl('Rot',  12, _y + 3, 30)
    ppI.rotX = ppRInp('0',  46, _y, 40)
    ppI.rotY = ppRInp('0',  90, _y, 40)
    ppI.rotZ = ppRInp('0', 134, _y, 40)
    ppI.rotBtn = ppRBtn('Apply', 178, _y, 78)

    _y = ppRow(28); ppRLbl('Size', 12, _y + 3, 30)
    ppI.sizeX = ppRInp('1',  46, _y, 40)
    ppI.sizeY = ppRInp('1',  90, _y, 40)
    ppI.sizeZ = ppRInp('1', 134, _y, 40)
    ppI.sizeBtn = ppRBtn('Apply', 178, _y, 78)

    -- Visual gizmo mode picker: three radio-style buttons -- pick one of
    -- Move (arrows), Rot (arcs), or Size (ball-handles). Clicking the
    -- active mode again turns gizmos off (Studio-style behaviour).
    _y = ppRow(28); ppRLbl('Gizmo', 12, _y + 3, 40)
    ppI.gizmoMoveBtn = ppRBtn('Move', 56,  _y, 62)
    ppI.gizmoRotBtn  = ppRBtn('Rot',  122, _y, 62)
    ppI.gizmoSizeBtn = ppRBtn('Size', 188, _y, 62)

    -- ============ SECTION: PHYSICS ============
    ppSect('PHYSICS')

    _y = ppRow(28); ppRLbl('Anchored',   12, _y + 3, 90)
    ppI.anchTog = ppRTog(196, _y, 60, false)
    _y = ppRow(28); ppRLbl('CanCollide', 12, _y + 3, 90)
    ppI.collTog = ppRTog(196, _y, 60, true)
    _y = ppRow(28); ppRLbl('CastShadow', 12, _y + 3, 90)
    ppI.shadTog = ppRTog(196, _y, 60, true)

    -- ============ SECTION: VISIBILITY ============
    ppSect('VISIBILITY')
    _y = ppRow(28)
    ppI.hideBtn   = ppRBtn('Hide',   12, _y, 118)
    ppI.unhideBtn = ppRBtn('Unhide', 138, _y, 118)

    -- ============ SECTION: DECAL / TEXTURE ============
    ppSect('DECAL / TEXTURE')

    _y = ppRow(28); ppRLbl('Visible', 12, _y + 3, 60)
    ppI.decVisTog = ppRTog(196, _y, 60, true)

    _y = ppRow(28); ppRLbl('Face', 12, _y + 3, 40)
    local FACES = { 'Front', 'Back', 'Left', 'Right', 'Top', 'Bottom' }
    ppI.faceDD = ppMakeDropdown(58, _y, 100, FACES, 'Front', nil)

    _y = ppRow(28); ppRLbl('Texture ID', 12, _y + 3, 78)
    ppI.texIn = ppRInp('rbxassetid://', 90, _y, 166)

    _y = ppRow(30)
    ppI.texApplyBtn = ppRBtn('Apply Texture',  12, _y, 118)
    ppI.texRmBtn    = ppRBtn('Remove Decals', 138, _y, 118)

    -- copy/paste: parts serialize relative to the vehicle seat so data
    -- pasted onto a different vehicle lands in the same seat-relative spot
    ppSect('COPY / PASTE')
    do
        local function dataBox(y, placeholder)
            local b = Instance.new('TextBox')
            b.Size = UDim2.new(0, 244, 0, 48); b.Position = UDim2.new(0, 12, 0, y)
            b.BackgroundColor3 = BG2; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
            b.Text = ''; b.PlaceholderText = placeholder; b.PlaceholderColor3 = SUBTEXT
            b.TextColor3 = TEXT; b.Font = Enum.Font.Code; b.TextSize = 10
            b.MultiLine = true; b.TextWrapped = true; b.ClearTextOnFocus = false
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextYAlignment = Enum.TextYAlignment.Top
            b.ClipsDescendants = true; b.ZIndex = 12; b.Parent = ppRScroll
            b.Focused:Connect(function() b.BorderColor3 = ACCENT end)
            b.FocusLost:Connect(function() b.BorderColor3 = BORDER end)
            return b
        end
        _y = ppRow(28)
        ppI.copyBtn  = ppRBtn('Copy Selected', 12, _y, 118)
        ppI.clearCpBtn = ppRBtn('Clear Boxes', 138, _y, 118)
        _y = ppRow(54)
        ppI.copyOut  = dataBox(_y, 'Copied data shows here (also sent to clipboard)')
        _y = ppRow(54)
        ppI.pasteIn  = dataBox(_y, 'Paste part data here...')
        _y = ppRow(28)
        ppI.pasteBtn = ppRBtn('Paste', 12, _y, 118, true)
        ppI.pasteDelBtn = ppRBtn('Delete Pasted', 138, _y, 118)
        _y = ppRow(28); ppRLbl('Collide', 12, _y + 3, 90)
        ppI.pasteCollTog = ppRTog(196, _y, 60, false)
        _y = ppRow(28); ppRLbl('Weight', 12, _y + 3, 90)
        ppI.pasteWeightIn  = ppRInp('0', 108, _y, 58)
        ppI.pasteWeightBtn = ppRBtn('Set', 172, _y, 84)
        _y = ppRow(44)
        local hint = ppRLbl('Collide/Weight apply to selected pasted parts and to new pastes. Weight 0 = massless. Unmatched parts spawn mid-vehicle.',
            12, _y, 244, SUBTEXT)
        hint.Size = UDim2.new(0, 244, 0, 42); hint.TextWrapped = true; hint.TextSize = 10
    end

    -- mouse-select ignore list: name patterns + explicit parts + invisible
    ppSect('MOUSE SELECT IGNORE')
    _y = ppRow(28); ppRLbl('Names', 12, _y + 3, 44)
    ppI.ignNamesIn = ppRInp('Weight', 58, _y, 198)
    ppI.ignNamesIn.TextXAlignment = Enum.TextXAlignment.Left
    ppI.ignNamesIn.PlaceholderText = 'comma separated, e.g. Weight, Hitbox'
    _y = ppRow(28)
    ppI.ignSelBtn   = ppRBtn('Ignore Selected', 12, _y, 118)
    ppI.ignClearBtn = ppRBtn('Clear Ignored', 138, _y, 118)
    _y = ppRow(28); ppRLbl('Skip Invisible', 12, _y + 3, 110)
    ppI.ignInvisTog = ppRTog(196, _y, 60, false)
    _y = ppRow(22)
    ppI.ignCountLbl = ppRLbl('0 parts ignored by hand', 12, _y, 244, SUBTEXT)

    -- bottom padding
    ppRY = ppRY + 12

    -- radio-mode gizmos: 'move' | 'rot' | 'size' | nil
    local gizmoMode    = nil
    local activeGizmo  = nil
    local dragCF, dragSize

    local function destroyGizmos()
        if activeGizmo then
            pcall(function() activeGizmo:Destroy() end)
            activeGizmo = nil
        end
    end

    -- "primary" = first BasePart under the selection (descending Models/Folders)
    local function firstSelBP()
        for inst in pairs(ppSelBoxes) do
            if inst and inst.Parent then
                if inst:IsA('BasePart') then return inst end
                for _, d in ipairs(inst:GetDescendants()) do
                    if d:IsA('BasePart') then return d end
                end
            end
        end
    end

    -- one history entry per drag (Up), not per MouseDrag frame
    local function pushGizmoUndo(label, part, before, after)
        History.push(label,
            function() if part.Parent then
                for k, v in pairs(after) do pcall(function() part[k] = v end) end
            end end,
            function() if part.Parent then
                for k, v in pairs(before) do pcall(function() part[k] = v end) end
            end end)
    end

    -- Drag-start snapshots for visual-only mode so we don't accumulate
    -- deltas across drags (a fresh Down resets the baseline).
    local dragStartPosDelta, dragStartRotOffset, dragStartSizeOver

    local function wireMove(part, h)
        h.MouseButton1Down:Connect(function()
            dragCF = part.CFrame
            local e = ppVisualCache[part]
            if e then dragStartPosDelta = e.posDelta end
        end)
        h.MouseButton1Up:Connect(function()
            if dragCF and dragCF ~= part.CFrame then
                pushGizmoUndo('Gizmo move', part, { CFrame = dragCF }, { CFrame = part.CFrame })
            end
            dragCF = nil; dragStartPosDelta = nil
        end)
        h.MouseDrag:Connect(function(face, distance)
            if not dragCF then return end
            local axis  = Vector3.FromNormalId(face)
            local wDlta = dragCF:VectorToWorldSpace(axis * distance)
            local e = ppVisualCache[part]
            if e then
                -- ghost-mode: update posDelta, real part untouched
                e.posDelta = (dragStartPosDelta or Vector3.new()) + wDlta
            else
                part.CFrame = dragCF + wDlta
            end
            if ppRefreshInspector then ppRefreshInspector() end
        end)
    end
    local function wireRot(part, h)
        h.MouseButton1Down:Connect(function()
            dragCF = part.CFrame
            local e = ppVisualCache[part]
            if e then dragStartRotOffset = e.rotOffset end
        end)
        h.MouseButton1Up:Connect(function()
            if dragCF and dragCF ~= part.CFrame then
                pushGizmoUndo('Gizmo rotate', part, { CFrame = dragCF }, { CFrame = part.CFrame })
            end
            dragCF = nil; dragStartRotOffset = nil
        end)
        h.MouseDrag:Connect(function(axis, angle)
            if not dragCF then return end
            local rotCF
            if     axis == Enum.Axis.X then rotCF = CFrame.Angles(angle, 0, 0)
            elseif axis == Enum.Axis.Y then rotCF = CFrame.Angles(0, angle, 0)
            else                            rotCF = CFrame.Angles(0, 0, angle) end
            local e = ppVisualCache[part]
            if e then
                e.rotOffset = (dragStartRotOffset or CFrame.new()) * rotCF
            else
                -- right-multiply: rotates around the part's own local axis
                part.CFrame = dragCF * rotCF
            end
            if ppRefreshInspector then ppRefreshInspector() end
        end)
    end
    -- grows Size along face axis; shifts CFrame by half-delta to pin opposite face
    local function wireSize(part, h)
        h.MouseButton1Down:Connect(function()
            dragCF   = part.CFrame
            dragSize = part.Size
            local e = ppVisualCache[part]
            if e then dragStartSizeOver = e.sizeOverride or part.Size end
        end)
        h.MouseButton1Up:Connect(function()
            if dragCF and (dragCF ~= part.CFrame or dragSize ~= part.Size) then
                pushGizmoUndo('Gizmo resize', part,
                    { CFrame = dragCF, Size = dragSize },
                    { CFrame = part.CFrame, Size = part.Size })
            end
            dragCF = nil; dragSize = nil; dragStartSizeOver = nil
        end)
        h.MouseDrag:Connect(function(face, distance)
            if not dragSize then return end
            local axisVec = Vector3.FromNormalId(face)
            local absAxis = Vector3.new(math.abs(axisVec.X),
                                        math.abs(axisVec.Y),
                                        math.abs(axisVec.Z))
            local newSize = (dragStartSizeOver or dragSize) + absAxis * distance
            newSize = Vector3.new(math.max(0.05, newSize.X),
                                  math.max(0.05, newSize.Y),
                                  math.max(0.05, newSize.Z))
            local e = ppVisualCache[part]
            if e then
                e.sizeOverride = newSize
                -- ghost carries the visual size + centered pivot shift via
                -- posDelta so the "grow along axis" behaviour still holds
                e.posDelta = (dragStartPosDelta or e.posDelta or Vector3.new())
                             + dragCF:VectorToWorldSpace(axisVec * (distance * 0.5))
            else
                part.Size   = newSize
                part.CFrame = dragCF + dragCF:VectorToWorldSpace(axisVec * (distance * 0.5))
            end
            if ppRefreshInspector then ppRefreshInspector() end
        end)
    end

    local function attachGizmos()
        destroyGizmos()
        if not gizmoMode then return end
        local part = firstSelBP()
        if not part then return end

        -- Visual-only: adorn the gizmo to the GHOST so it visually
        -- follows the offset location. wireXxx still gets the real part
        -- for the ghost-cache lookup.
        local ghostEntry = ppVisualCache[part]
        local adornee    = (ghostEntry and ghostEntry.ghost) or part

        if gizmoMode == 'move' then
            local h = Instance.new('Handles')
            h.Style   = Enum.HandlesStyle.Movement
            h.Color3  = Color3.fromRGB(255, 200, 60)
            h.Adornee = adornee
            safeParentGui(h)
            activeGizmo = h
            wireMove(part, h)
        elseif gizmoMode == 'rot' then
            local h = Instance.new('ArcHandles')
            h.Color3  = Color3.fromRGB(255,  80,  80)
            h.Adornee = adornee
            safeParentGui(h)
            activeGizmo = h
            wireRot(part, h)
        else -- 'size'
            local h = Instance.new('Handles')
            h.Style   = Enum.HandlesStyle.Resize
            h.Color3  = Color3.fromRGB(100, 220, 100)
            h.Adornee = adornee
            safeParentGui(h)
            activeGizmo = h
            wireSize(part, h)
        end
    end

    -- keep the radio-button visuals in sync with gizmoMode
    local function refreshGizmoBtns()
        local pairs_ = {
            { ppI.gizmoMoveBtn, 'move' },
            { ppI.gizmoRotBtn,  'rot'  },
            { ppI.gizmoSizeBtn, 'size' },
        }
        for _, e in ipairs(pairs_) do
            e[1].BackgroundColor3 = (e[2] == gizmoMode) and ACCENT or BGSUB
        end
    end

    ppI.attachGizmos  = attachGizmos
    ppI.destroyGizmos = destroyGizmos
    -- Toggle behaviour: clicking the active mode turns gizmos OFF; clicking
    -- a different mode switches. Nil clears explicitly.
    ppI.setGizmoMode  = function(mode)
        gizmoMode = (gizmoMode == mode) and nil or mode
        attachGizmos()
        refreshGizmoBtns()
    end

    end  -- close RIGHT PANE do-block (frees helpers/temps)

    -- ---- tree state ----
    local ppNodeList = {}
    local ppSelCount = 0

    local function ppUpdateCount()
        ppCountLbl.Text = ppSelCount .. ' selected'
        if ppRefreshInspector then ppRefreshInspector() end
    end

    -- inst OR any BasePart descendant with Transparency >= 1
    local function ppHasInvisibleBP(inst)
        if inst:IsA('BasePart') and inst.Transparency >= 1 then return true end
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA('BasePart') and d.Transparency >= 1 then return true end
        end
        return false
    end

    -- row visibility: fast path when both filters off; else bubble matches up
    local function ppRecomputeVis()
        local query     = (ppSearchBox.Text or ''):lower()
        local invisOnly = ppInvisOnly

        if query == '' and not invisOnly then
            for _, n in ipairs(ppNodeList) do
                if n.parentNode == nil then
                    n.row.Visible = true
                else
                    n.row.Visible = n.parentNode.row.Visible and n.parentNode.expanded
                end
            end
            return
        end

        -- pass 1: per-node self-match against every active filter
        for _, n in ipairs(ppNodeList) do
            local nameOK  = (query == '')
                          or (n.instance.Name:lower():find(query, 1, true) ~= nil)
            local invisOK = (not invisOnly) or ppHasInvisibleBP(n.instance)
            n._match        = nameOK and invisOK
            n._hasMatchDesc = false
        end
        -- pass 2: bubble matches upward (reverse walk = children before parents)
        for i = #ppNodeList, 1, -1 do
            local n = ppNodeList[i]
            if n.parentNode and (n._match or n._hasMatchDesc) then
                n.parentNode._hasMatchDesc = true
            end
        end
        -- pass 3: any node that matches or has a matching descendant is shown
        for _, n in ipairs(ppNodeList) do
            n.row.Visible = n._match or n._hasMatchDesc
        end
    end

    local function ppCtrlDown()
        return UIS:IsKeyDown(Enum.KeyCode.LeftControl)
            or UIS:IsKeyDown(Enum.KeyCode.RightControl)
    end

    -- deselect every node and clear all in-game outlines
    local function ppDeselectAll()
        for _, nd in ipairs(ppNodeList) do
            if nd.selected then
                nd.selected = false
                nd.row.BackgroundTransparency = 1
            end
        end
        for k, sb in pairs(ppSelBoxes) do
            pcall(function() sb:Destroy() end); ppSelBoxes[k] = nil
        end
        ppSelCount = 0
        ppUpdateCount()
    end

    -- select/deselect a node and manage its in-game SelectionBox
    local function ppSetSel(n, on)
        if n.selected == on then return end
        n.selected = on
        if on then
            n.row.BackgroundColor3    = Color3.fromRGB(0, 100, 200)
            n.row.BackgroundTransparency = 0.55
            ppSelCount += 1
            local sb = Instance.new('SelectionBox')
            sb.Adornee             = n.instance
            sb.Color3              = Color3.fromRGB(0, 160, 255)
            sb.LineThickness       = 0.06
            sb.SurfaceColor3       = Color3.fromRGB(0, 160, 255)
            sb.SurfaceTransparency = 0.82
            sb.Parent              = workspace
            ppSelBoxes[n.instance] = sb
        else
            n.row.BackgroundTransparency = 1
            ppSelCount -= 1
            if ppSelBoxes[n.instance] then
                pcall(function() ppSelBoxes[n.instance]:Destroy() end)
                ppSelBoxes[n.instance] = nil
            end
        end
        ppUpdateCount()
    end

    -- forward declaration for recursion
    local ppAddNode

    ppAddNode = function(inst, depth, parentNode)
        -- collect child instances worth showing in the tree
        local childInsts = {}
        for _, child in ipairs(inst:GetChildren()) do
            if (child:IsA('BasePart') or child:IsA('Model') or child:IsA('Folder'))
                and not child:GetAttribute('KPastePhys') then
                table.insert(childInsts, child)
            end
        end

        local n = {
            instance    = inst,
            depth       = depth,
            expanded    = (depth == 0),   -- root starts expanded
            selected    = false,
            isSelectable = inst:IsA('BasePart'),
            hasChildren  = #childInsts > 0,
            parentNode   = parentNode,
            childNodes   = {},
            row          = nil,
            arrow        = nil,
        }
        table.insert(ppNodeList, n)

        -- build the row Frame
        local row = Instance.new('Frame')
        row.Size                 = UDim2.new(1, 0, 0, 24)
        row.BackgroundColor3     = BG2
        row.BackgroundTransparency = 1
        row.BorderSizePixel      = 0
        row.LayoutOrder          = #ppNodeList
        row.Visible              = false   -- ppRecomputeVis sets this after tree build
        row.ZIndex               = 12
        row.Parent               = ppScroll
        n.row = row

        local indent = depth * 14

        -- expand/collapse arrow
        if n.hasChildren then
            local arr = Instance.new('TextButton')
            arr.Size = UDim2.new(0, 16, 0, 16); arr.Position = UDim2.new(0, indent + 2, 0.5, -8)
            arr.BackgroundTransparency = 1
            arr.Text = n.expanded and '▼' or '▶'
            arr.TextColor3 = SUBTEXT; arr.Font = Enum.Font.Code; arr.TextSize = 10
            arr.ZIndex = 14; arr.Parent = row
            n.arrow = arr
            arr.MouseButton1Click:Connect(function()
                n.expanded = not n.expanded
                arr.Text = n.expanded and '▼' or '▶'
                ppRecomputeVis()
            end)
        end

        -- colored type dot (green = BasePart, blue = container)
        local dot = Instance.new('Frame')
        dot.Size = UDim2.new(0, 7, 0, 7); dot.Position = UDim2.new(0, indent + 20, 0.5, -3)
        dot.BackgroundColor3 = n.isSelectable
            and Color3.fromRGB(80, 210, 110)
            or  Color3.fromRGB(90, 140, 220)
        dot.BorderSizePixel = 0; dot.ZIndex = 14; dot.Parent = row
        local dotCorner = Instance.new('UICorner')
        dotCorner.CornerRadius = UDim.new(1, 0); dotCorner.Parent = dot

        -- class label (right side, small, greyed)
        local classLbl = Instance.new('TextLabel')
        classLbl.Size = UDim2.new(0, 70, 1, 0); classLbl.Position = UDim2.new(1, -72, 0, 0)
        classLbl.BackgroundTransparency = 1; classLbl.Text = inst.ClassName
        classLbl.TextColor3 = SUBTEXT; classLbl.Font = Enum.Font.Code; classLbl.TextSize = 9
        classLbl.TextXAlignment = Enum.TextXAlignment.Right
        classLbl.TextTruncate = Enum.TextTruncate.AtEnd
        classLbl.ZIndex = 13; classLbl.Parent = row

        -- part name
        local nameLbl = Instance.new('TextLabel')
        nameLbl.Size = UDim2.new(1, -(indent + 30 + 72), 1, 0)
        nameLbl.Position = UDim2.new(0, indent + 30, 0, 0)
        nameLbl.BackgroundTransparency = 1; nameLbl.Text = inst.Name
        nameLbl.TextColor3 = TEXT
        nameLbl.Font = Enum.Font.Code; nameLbl.TextSize = 12
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.ZIndex = 13; nameLbl.Parent = row

        -- click/hover overlay. ZIndex 13 < arrow ZIndex 14, so arrow area is
        -- intercepted by the arrow button first; this fires for all other areas.
        local hit = Instance.new('TextButton')
        hit.Size = UDim2.new(1, 0, 1, 0); hit.BackgroundTransparency = 1
        hit.Text = ''; hit.ZIndex = 13; hit.Parent = row

        hit.MouseButton1Click:Connect(function()
            if ppCtrlDown() then
                -- Ctrl held: toggle this node in/out of selection
                ppSetSel(n, not n.selected)
            elseif n.selected then
                -- Plain click on the already-selected node -> deselect it,
                -- letting you back out without needing the "Deselect All" btn.
                ppSetSel(n, false)
            else
                -- Plain click on a new node: select only this one
                ppDeselectAll()
                ppSetSel(n, true)
            end
        end)
        -- right-click: open the "Delete" context menu for this node's instance
        hit.MouseButton2Click:Connect(function()
            if ppShowContextMenu then
                local mouse = plr and plr:GetMouse()
                ppShowContextMenu(n.instance, mouse and mouse.X or 100, mouse and mouse.Y or 100)
            end
        end)
        hit.MouseEnter:Connect(function()
            if not n.selected then
                row.BackgroundColor3 = BGSUB; row.BackgroundTransparency = 0.4
            end
        end)
        hit.MouseLeave:Connect(function()
            if not n.selected then row.BackgroundTransparency = 1 end
        end)

        -- recurse into children (depth-first, so parent always before children in ppNodeList)
        for _, child in ipairs(childInsts) do
            table.insert(n.childNodes, ppAddNode(child, depth + 1, n))
        end

        return n
    end

    local function ppClearSelBoxes()
        for k, sb in pairs(ppSelBoxes) do
            pcall(function() sb:Destroy() end); ppSelBoxes[k] = nil
        end
        ppSelCount = 0
        ppUpdateCount()
    end

    local function ppClearTree()
        ppClearSelBoxes()
        for _, n in ipairs(ppNodeList) do
            if n.row then n.row:Destroy() end
        end
        ppNodeList = {}
    end

    local function ppGetRootModel()
        local char = plr.Character
        local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
        if not hum or not hum.SeatPart then return nil end
        if _G._scooterMode then
            local cur = hum.SeatPart
            while cur.Parent and cur.Parent ~= workspace do
                cur = cur.Parent
            end
            return cur:IsA('Model') and cur or nil
        else
            local base = hum.SeatPart.Parent
            return base and base:IsA('Model') and base or nil
        end
    end

    -- Auto-rebuild plumbing:
    -- * DescendantAdded/Removing on the current bike model, debounced 0.4s
    -- * Toast suppression when the rebuild is automatic (silent)
    -- * Selection restored by instance after each rebuild so the auto-
    --   refresh doesn't nuke what the user had picked.
    local ppAutoConn1, ppAutoConn2
    local ppRebuildScheduled = false
    local ppSchedule  -- forward decl

    local function ppBuildTree(silent)
        local savedY  = ppScroll.CanvasPosition.Y
        local prevSel = {}   -- instance -> true; restored after rebuild
        for inst in pairs(ppSelBoxes) do prevSel[inst] = true end

        ppClearTree()
        local model = ppGetRootModel()
        if not model then
            if not silent then showToast('Not on a bike') end
            return
        end
        ppAddNode(model, 0, nil)
        ppRecomputeVis()

        -- restore previous selection (by instance) so auto-refresh preserves it
        for _, n in ipairs(ppNodeList) do
            if prevSel[n.instance] then ppSetSel(n, true) end
        end

        -- restore scroll after AutomaticCanvasSize resizes on the next tick
        task.defer(function() ppScroll.CanvasPosition = Vector2.new(0, savedY) end)

        -- (re)attach DescendantAdded/Removing on the fresh model so future
        -- additions/removals trigger a debounced rebuild
        if ppAutoConn1 then ppAutoConn1:Disconnect() end
        if ppAutoConn2 then ppAutoConn2:Disconnect() end
        ppAutoConn1 = model.DescendantAdded:Connect(function(desc)
            if desc:IsA('BasePart') or desc:IsA('Model') or desc:IsA('Folder') then
                ppSchedule()
            end
        end)
        ppAutoConn2 = model.DescendantRemoving:Connect(function(desc)
            if desc:IsA('BasePart') or desc:IsA('Model') or desc:IsA('Folder') then
                ppSchedule()
            end
        end)

        if not silent then showToast('Tree: ' .. #ppNodeList .. ' nodes') end
    end

    ppSchedule = function()
        if ppRebuildScheduled then return end
        ppRebuildScheduled = true
        task.delay(0.4, function()
            ppRebuildScheduled = false
            if partPickerGui and partPickerGui.Enabled then pcall(ppBuildTree, true) end
        end)
    end

    ppRefreshBtn.MouseButton1Click:Connect(function() ppBuildTree(false) end)
    -- expose so the Bike Customization "Advanced Selection" button can auto-build
    -- the tree on first open (prevents "No parts selected" toasts before Refresh)
    ppBuildTreePublic = function() ppBuildTree(false) end
    -- rebuild after respawn so ppSelBoxes doesn't hold stale destroyed instances
    if plr and plr.CharacterAdded then
        plr.CharacterAdded:Connect(function()
            -- small delay: wait until the new character is seated
            task.delay(1.2, function()
                if partPickerGui and partPickerGui.Enabled then
                    pcall(ppBuildTree, true)
                end
            end)
        end)
    end

    ppExpandBtn.MouseButton1Click:Connect(function()
        for _, n in ipairs(ppNodeList) do
            if n.hasChildren then
                n.expanded = true
                if n.arrow then n.arrow.Text = '▼' end
            end
        end
        ppRecomputeVis()
    end)

    ppCollapseBtn.MouseButton1Click:Connect(function()
        for _, n in ipairs(ppNodeList) do
            -- collapse all except root (keep root open so tree stays visible)
            if n.hasChildren and n.parentNode then
                n.expanded = false
                if n.arrow then n.arrow.Text = '▶' end
            end
        end
        ppRecomputeVis()
    end)

    ppDeselectBtn.MouseButton1Click:Connect(ppDeselectAll)

    -- live search: recompute visibility on every keystroke
    ppSearchBox:GetPropertyChangedSignal('Text'):Connect(ppRecomputeVis)

    -- ================================================================
    -- COLOR PICKER POPUP
    -- ================================================================
    do
        local cpGui = Instance.new('ScreenGui')
        cpGui.Name           = 'PPColorPickerGui'
        cpGui.ResetOnSpawn   = false
        cpGui.DisplayOrder   = 1004 -- above picker (1002), below undo (1005); was 999 (z-fight with Linoria)
        cpGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        cpGui.Enabled        = false
        safeParentGui(cpGui)

        local CP_W      = 220
        local SV_MARGIN = 15
        local SV_SIZE   = CP_W - SV_MARGIN * 2
        local SV_Y      = 36
        local HUE_Y     = SV_Y + SV_SIZE + 10
        local PREV_Y    = HUE_Y + 14 + 10
        local CP_H      = PREV_Y + 22 + 12

        local cpPanel = Instance.new('Frame')
        cpPanel.Size             = UDim2.new(0, CP_W, 0, CP_H)
        cpPanel.Position         = UDim2.new(0.5, -CP_W - 40, 0.5, -CP_H / 2)
        cpPanel.BackgroundColor3 = BG2
        cpPanel.BorderSizePixel  = 1
        cpPanel.BorderColor3     = BORDER
        cpPanel.Active           = true
        cpPanel.ZIndex           = 20
        cpPanel.Parent           = cpGui

        -- drag (title bar only)
        local cpDrag, cpDragStart, cpDragOrigin = false, nil, nil

        -- title bar
        local cpTBar = Instance.new('Frame')
        cpTBar.Size = UDim2.new(1, 0, 0, 26); cpTBar.BackgroundColor3 = BGSUB
        cpTBar.BorderSizePixel = 0; cpTBar.ZIndex = 21; cpTBar.Parent = cpPanel

        cpTBar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                cpDrag = true; cpDragStart = inp.Position; cpDragOrigin = cpPanel.Position
            end
        end)
        cpTBar.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then cpDrag = false end
        end)

        local cpTitle = Instance.new('TextLabel')
        cpTitle.Size = UDim2.new(1, -28, 1, 0); cpTitle.Position = UDim2.new(0, 8, 0, 0)
        cpTitle.BackgroundTransparency = 1; cpTitle.Text = 'Color Picker'
        cpTitle.TextColor3 = TEXT; cpTitle.Font = Enum.Font.Code; cpTitle.TextSize = 12
        cpTitle.TextXAlignment = Enum.TextXAlignment.Left; cpTitle.ZIndex = 22; cpTitle.Parent = cpTBar

        local cpXBtn = Instance.new('TextButton')
        cpXBtn.Size = UDim2.new(0, 26, 0, 26); cpXBtn.Position = UDim2.new(1, -26, 0, 0)
        cpXBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50); cpXBtn.BorderSizePixel = 0
        cpXBtn.Text = 'X'; cpXBtn.TextColor3 = TEXT; cpXBtn.Font = Enum.Font.Code
        cpXBtn.TextSize = 11; cpXBtn.ZIndex = 22; cpXBtn.Parent = cpTBar
        cpXBtn.MouseButton1Click:Connect(function()
            cpGui.Enabled = false; ppCPOpen = false
        end)

        -- SV square (hue-colored background)
        local svSq = Instance.new('Frame')
        svSq.Size = UDim2.new(0, SV_SIZE, 0, SV_SIZE)
        svSq.Position = UDim2.new(0, SV_MARGIN, 0, SV_Y)
        svSq.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        svSq.BorderSizePixel = 0; svSq.ZIndex = 21; svSq.Parent = cpPanel

        -- saturation overlay: white left -> transparent right
        local satOv = Instance.new('Frame')
        satOv.Size = UDim2.new(1, 0, 1, 0); satOv.BackgroundColor3 = Color3.new(1, 1, 1)
        satOv.BorderSizePixel = 0; satOv.ZIndex = 22; satOv.Parent = svSq
        local satGrad = Instance.new('UIGradient')
        satGrad.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1)
        }
        satGrad.Rotation = 0; satGrad.Parent = satOv

        -- value overlay: transparent top -> black bottom
        local valOv = Instance.new('Frame')
        valOv.Size = UDim2.new(1, 0, 1, 0); valOv.BackgroundColor3 = Color3.new(0, 0, 0)
        valOv.BorderSizePixel = 0; valOv.ZIndex = 23; valOv.Parent = svSq
        local valGrad = Instance.new('UIGradient')
        valGrad.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0)
        }
        valGrad.Rotation = 90; valGrad.Parent = valOv

        -- hit area on SV square
        local svHit = Instance.new('TextButton')
        svHit.Size = UDim2.new(1, 0, 1, 0); svHit.BackgroundTransparency = 1
        svHit.Text = ''; svHit.ZIndex = 24; svHit.Parent = svSq

        -- SV crosshair (child of cpPanel to avoid ClipsDescendants clipping)
        local svCur = Instance.new('Frame')
        svCur.Size = UDim2.new(0, 10, 0, 10)
        svCur.AnchorPoint = Vector2.new(0.5, 0.5)
        svCur.BackgroundTransparency = 1; svCur.BorderSizePixel = 0
        svCur.ZIndex = 25; svCur.Parent = cpPanel
        do
            local ch = Instance.new('Frame')
            ch.Size = UDim2.new(1, 0, 0, 1); ch.Position = UDim2.new(0, 0, 0.5, 0)
            ch.BackgroundColor3 = Color3.new(1, 1, 1); ch.BorderSizePixel = 0
            ch.ZIndex = 26; ch.Parent = svCur
            local cv = Instance.new('Frame')
            cv.Size = UDim2.new(0, 1, 1, 0); cv.Position = UDim2.new(0.5, 0, 0, 0)
            cv.BackgroundColor3 = Color3.new(1, 1, 1); cv.BorderSizePixel = 0
            cv.ZIndex = 26; cv.Parent = svCur
        end

        -- hue strip
        local hueStrip = Instance.new('Frame')
        hueStrip.Size = UDim2.new(0, SV_SIZE, 0, 14)
        hueStrip.Position = UDim2.new(0, SV_MARGIN, 0, HUE_Y)
        hueStrip.BackgroundColor3 = Color3.new(1, 1, 1); hueStrip.BorderSizePixel = 0
        hueStrip.ZIndex = 21; hueStrip.Parent = cpPanel
        local hueGrad = Instance.new('UIGradient')
        hueGrad.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0,     Color3.fromHSV(0,     1, 1)),
            ColorSequenceKeypoint.new(1/6,   Color3.fromHSV(1/6,   1, 1)),
            ColorSequenceKeypoint.new(2/6,   Color3.fromHSV(2/6,   1, 1)),
            ColorSequenceKeypoint.new(3/6,   Color3.fromHSV(3/6,   1, 1)),
            ColorSequenceKeypoint.new(4/6,   Color3.fromHSV(4/6,   1, 1)),
            ColorSequenceKeypoint.new(5/6,   Color3.fromHSV(5/6,   1, 1)),
            ColorSequenceKeypoint.new(1,     Color3.fromHSV(1,     1, 1)),
        }
        hueGrad.Parent = hueStrip

        local hueHit = Instance.new('TextButton')
        hueHit.Size = UDim2.new(1, 0, 1, 0); hueHit.BackgroundTransparency = 1
        hueHit.Text = ''; hueHit.ZIndex = 22; hueHit.Parent = hueStrip

        -- hue cursor bar (child of cpPanel)
        local hueCur = Instance.new('Frame')
        hueCur.Size = UDim2.new(0, 4, 0, 18)
        hueCur.AnchorPoint = Vector2.new(0.5, 0.5)
        hueCur.BackgroundColor3 = Color3.new(1, 1, 1)
        hueCur.BorderSizePixel = 1; hueCur.BorderColor3 = Color3.new(0, 0, 0)
        hueCur.ZIndex = 22; hueCur.Parent = cpPanel

        -- preview swatch
        local cpPreview = Instance.new('Frame')
        cpPreview.Size = UDim2.new(0, 26, 0, 22)
        cpPreview.Position = UDim2.new(0, SV_MARGIN, 0, PREV_Y)
        cpPreview.BackgroundColor3 = ppPickedColor; cpPreview.BorderSizePixel = 1
        cpPreview.BorderColor3 = BORDER; cpPreview.ZIndex = 21; cpPreview.Parent = cpPanel

        -- hex input inside picker
        local cpHexIn = Instance.new('TextBox')
        cpHexIn.Size = UDim2.new(0, 74, 0, 22)
        cpHexIn.Position = UDim2.new(0, SV_MARGIN + 32, 0, PREV_Y)
        cpHexIn.BackgroundColor3 = BGSUB; cpHexIn.BorderSizePixel = 1; cpHexIn.BorderColor3 = BORDER
        cpHexIn.Text = 'FF5050'; cpHexIn.TextColor3 = TEXT; cpHexIn.Font = Enum.Font.Code
        cpHexIn.TextSize = 11; cpHexIn.ClearTextOnFocus = false
        cpHexIn.ZIndex = 22; cpHexIn.Parent = cpPanel

        -- ---- HSV state ----
        local cpH, cpS, cpV = 0, 1, 1   -- all 0-1

        local function cpColorToHex(c)
            return string.format('%02X%02X%02X',
                math.floor(c.R * 255 + 0.5),
                math.floor(c.G * 255 + 0.5),
                math.floor(c.B * 255 + 0.5))
        end

        local function cpSyncUI()
            local c = Color3.fromHSV(cpH, cpS, cpV)
            svSq.BackgroundColor3 = Color3.fromHSV(cpH, 1, 1)
            svCur.Position   = UDim2.new(0, SV_MARGIN + cpS * SV_SIZE,
                                          0, SV_Y    + (1 - cpV) * SV_SIZE)
            hueCur.Position  = UDim2.new(0, SV_MARGIN + cpH * SV_SIZE,
                                          0, HUE_Y + 7)
            cpPreview.BackgroundColor3 = c
            local hex = cpColorToHex(c)
            cpHexIn.Text  = hex
            ppPickedColor = c
            ppI.swatch.BackgroundColor3 = c
            ppI.hexBox.Text = hex
        end

        local function cpSetHSV(h, s, v)
            cpH = math.clamp(h, 0, 1)
            cpS = math.clamp(s, 0, 1)
            cpV = math.clamp(v, 0, 1)
            cpSyncUI()
        end

        -- initialise cursors to default red
        cpSyncUI()

        -- SV square interaction
        local svDrag = false
        local function svUpdate(pos)
            local abs = svSq.AbsolutePosition
            local sz  = svSq.AbsoluteSize
            cpSetHSV(cpH,
                math.clamp((pos.X - abs.X) / sz.X, 0, 1),
                1 - math.clamp((pos.Y - abs.Y) / sz.Y, 0, 1))
        end
        svHit.MouseButton1Down:Connect(function()
            svDrag = true; svUpdate(UIS:GetMouseLocation())
        end)

        -- hue strip interaction
        local hueDrag = false
        local function hueUpdate(pos)
            local abs = hueStrip.AbsolutePosition
            local sz  = hueStrip.AbsoluteSize
            cpSetHSV(math.clamp((pos.X - abs.X) / sz.X, 0, 1), cpS, cpV)
        end
        hueHit.MouseButton1Down:Connect(function()
            hueDrag = true; hueUpdate(UIS:GetMouseLocation())
        end)

        -- global mouse tracking (dragging outside frames)
        UIS.InputChanged:Connect(function(inp)
            if inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            if cpDrag then
                local d = inp.Position - cpDragStart
                cpPanel.Position = UDim2.new(cpDragOrigin.X.Scale, cpDragOrigin.X.Offset + d.X,
                                             cpDragOrigin.Y.Scale, cpDragOrigin.Y.Offset + d.Y)
            end
            if svDrag  then svUpdate(inp.Position) end
            if hueDrag then hueUpdate(inp.Position) end
        end)
        UIS.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                svDrag = false; hueDrag = false
            end
        end)

        -- hex input in picker -> update HSV
        cpHexIn.FocusLost:Connect(function()
            local hex = cpHexIn.Text:match('^#?(%x%x%x%x%x%x)$')
            if hex then
                local r = tonumber(hex:sub(1,2), 16) / 255
                local g = tonumber(hex:sub(3,4), 16) / 255
                local b = tonumber(hex:sub(5,6), 16) / 255
                local h, s, v = Color3.new(r, g, b):ToHSV()
                cpSetHSV(h, s, v)
            end
        end)

        -- hex input in bottom bar -> update HSV
        ppI.hexBox.FocusLost:Connect(function()
            local hex = ppI.hexBox.Text:match('^#?(%x%x%x%x%x%x)$')
            if hex then
                local r = tonumber(hex:sub(1,2), 16) / 255
                local g = tonumber(hex:sub(3,4), 16) / 255
                local b = tonumber(hex:sub(5,6), 16) / 255
                local h, s, v = Color3.new(r, g, b):ToHSV()
                cpSetHSV(h, s, v)
            end
        end)

        -- swatch toggle
        ppI.swatch.MouseButton1Click:Connect(function()
            ppCPOpen = not ppCPOpen
            cpGui.Enabled = ppCPOpen
        end)
    end

    ppI.applyBtn.MouseButton1Click:Connect(function()
        local c = ppPickedColor
        local painted = {}
        local function paintPart(p)
            if painted[p] then return end
            pcall(function() p.Color = c end)
            local sa = p:FindFirstChildOfClass('SurfaceAppearance')
            if sa then pcall(function() sa.Color = c end) end
            painted[p] = true
        end
        local function paintInst(inst)
            if inst:IsA('BasePart') then
                paintPart(inst)
            else
                for _, desc in ipairs(inst:GetDescendants()) do
                    if desc:IsA('BasePart') then paintPart(desc) end
                end
            end
        end
        local n = 0
        for _, node in ipairs(ppNodeList) do
            if node.selected then
                paintInst(node.instance)
                n += 1
            end
        end
        if n == 0 then
            showToast('No parts selected')
        else
            showToast('Color applied (' .. n .. ' node(s))')
        end
    end)

    -- Hide/Unhide go through History; no per-part cache to desync
    ppI.hideBtn.MouseButton1Click:Connect(function()
        local n = ppUndoable('Hide', {'Transparency'},
            function(p) p.Transparency = 1 end)
        if n > 0 then showToast('Hidden (' .. n .. ' part(s))') end
    end)
    -- the actual unhide work, factored out so the confirm popup can call it
    local function ppDoUnhide()
        local n = ppUndoable('Unhide', {'Transparency'},
            function(p) p.Transparency = 0 end)
        if n > 0 then showToast('Unhidden (' .. n .. ' part(s))') end
    end

    -- confirmation modal: prevents accidentally turning every hidden part visible
    local function ppShowUnhideConfirm()
        -- count selection up front so we can short-circuit the dialog
        local sel = 0
        for _, node in ipairs(ppNodeList) do
            if node.selected then sel += 1 end
        end
        if sel == 0 then showToast('No parts selected'); return end

        local backdrop = Instance.new('Frame')
        backdrop.Size = UDim2.new(1, 0, 1, 0)
        backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
        backdrop.BackgroundTransparency = 0.55
        backdrop.BorderSizePixel = 0
        backdrop.ZIndex = 100
        backdrop.Parent = pp

        local box = Instance.new('Frame')
        box.Size = UDim2.new(0, 300, 0, 132)
        box.AnchorPoint = Vector2.new(0.5, 0.5)
        box.Position = UDim2.new(0.5, 0, 0.5, 0)
        box.BackgroundColor3 = BG2
        box.BorderSizePixel = 1
        box.BorderColor3 = BORDER
        box.ZIndex = 101
        box.Parent = backdrop

        local accent = Instance.new('Frame')
        accent.Size = UDim2.new(1, 0, 0, 2)
        accent.BackgroundColor3 = ACCENT
        accent.BorderSizePixel = 0
        accent.ZIndex = 102
        accent.Parent = box

        local msg = Instance.new('TextLabel')
        msg.Size = UDim2.new(1, -20, 0, 68)
        msg.Position = UDim2.new(0, 10, 0, 12)
        msg.BackgroundTransparency = 1
        msg.Text = 'Are you sure you would like to make every part visible?'
        msg.TextColor3 = TEXT
        msg.Font = Enum.Font.Code
        msg.TextSize = 13
        msg.TextWrapped = true
        msg.TextXAlignment = Enum.TextXAlignment.Center
        msg.TextYAlignment = Enum.TextYAlignment.Center
        msg.ZIndex = 102
        msg.Parent = box

        local function mkBtn(text, xOff, onClick)
            local b = Instance.new('TextButton')
            b.Size = UDim2.new(0, 124, 0, 30)
            b.Position = UDim2.new(0, xOff, 1, -40)
            b.BackgroundColor3 = BGSUB
            b.BorderSizePixel = 1
            b.BorderColor3 = BORDER
            b.Text = text
            b.TextColor3 = TEXT
            b.Font = Enum.Font.Code
            b.TextSize = 12
            b.ZIndex = 102
            b.AutoButtonColor = false
            b.Parent = box
            b.MouseEnter:Connect(function() b.BorderColor3 = ACCENT end)
            b.MouseLeave:Connect(function() b.BorderColor3 = BORDER end)
            b.MouseButton1Click:Connect(onClick)
            return b
        end

        mkBtn('Yes',  16,  function() backdrop:Destroy(); ppDoUnhide() end)
        mkBtn('No',   160, function() backdrop:Destroy() end)
    end

    ppI.unhideBtn.MouseButton1Click:Connect(ppShowUnhideConfirm)

    -- ================================================================
    -- PROPERTY INSPECTOR WIRING
    -- Helpers below iterate the selection (keys of ppSelBoxes are the
    -- selected BasePart instances). Every property control applies live.
    -- ================================================================
    -- Selecting a Model or Folder in the tree implies "all BaseParts under
    -- it" for property operations. seen{} dedupes so a BasePart selected
    -- directly plus its ancestor Model doesn't get hit twice.
    local function ppSelectedBaseParts()
        local list, seen = {}, {}
        for inst in pairs(ppSelBoxes) do
            if inst and inst.Parent then
                if inst:IsA('BasePart') then
                    if not seen[inst] then seen[inst] = true; list[#list + 1] = inst end
                else
                    for _, d in ipairs(inst:GetDescendants()) do
                        if d:IsA('BasePart') and not seen[d] then
                            seen[d] = true; list[#list + 1] = d
                        end
                    end
                end
            end
        end
        return list
    end
    local function ppApplyToParts(fn)
        local list = ppSelectedBaseParts()
        if #list == 0 then showToast('No parts selected'); return 0 end
        for _, p in ipairs(list) do pcall(fn, p) end
        return #list
    end

    -- snapshot + mutate + push to History (exposed as ppI.undoable).
    -- Forward-declared at the top of the pp block; assigned here.
    ppUndoable = function(label, props, mutateFn)
        local list = ppSelectedBaseParts()
        if #list == 0 then showToast('No parts selected'); return 0 end
        History.pushDiff(label, list, props, function()
            for _, p in ipairs(list) do pcall(mutateFn, p) end
        end)
        return #list
    end
    ppI.undoable = ppUndoable
    -- collect every Decal / Texture under the selection (descend Models/Folders)
    local function ppSelectedDecals()
        local list, seen = {}, {}
        for inst in pairs(ppSelBoxes) do
            if inst and inst.Parent then
                for _, d in ipairs(inst:GetDescendants()) do
                    if (d:IsA('Decal') or d:IsA('Texture')) and not seen[d] then
                        seen[d] = true; list[#list + 1] = d
                    end
                end
                -- inst itself could be a Decal? no -- tree only shows BasePart/Model/Folder.
            end
        end
        return list
    end
    local function ppApplyToDecals(fn)
        local list = ppSelectedDecals()
        for _, d in ipairs(list) do pcall(fn, d) end
        return #list
    end

    -- refresh inspector -- sel count, decal indicator, transform + slider sync
    ppRefreshInspector = function()
        ppI.selLbl.Text = ppSelCount .. (ppSelCount == 1 and ' part' or ' parts')
        local dCount = #ppSelectedDecals()
        if dCount > 0 then
            ppI.decalLbl.Text = 'Decal: true (' .. dCount .. ')'
            ppI.decalLbl.TextColor3 = ACCENT
        else
            ppI.decalLbl.Text = 'Decal: false'
            ppI.decalLbl.TextColor3 = SUBTEXT
        end

        -- find the first BasePart under the selection (descending Models/Folders)
        local first
        for inst in pairs(ppSelBoxes) do
            if inst and inst.Parent then
                if inst:IsA('BasePart') then first = inst; break end
                for _, d in ipairs(inst:GetDescendants()) do
                    if d:IsA('BasePart') then first = d; break end
                end
                if first then break end
            end
        end
        if not first then
            -- nothing selected -- kill any leftover gizmo adornee so it
            -- doesn't hang on the last-selected part
            if ppI.destroyGizmos then ppI.destroyGizmos() end
            return
        end

        -- Pos/Rot/Size inputs are RELATIVE (delta from current), so on
        -- refresh we don't overwrite them with the world state anymore --
        -- they're an input buffer, not a readout. Transparency + physics
        -- toggles still mirror the primary since those ARE absolute.
        local fmt = function(n) return string.format('%.2f', n) end
        ppI.transIn.Text = fmt(first.Transparency)
        if ppI.transSlider then ppI.transSlider.setValue(first.Transparency) end

        -- physics toggles mirror the primary's actual state
        ppI.setTog(ppI.anchTog, first.Anchored == true)
        ppI.setTog(ppI.collTog, first.CanCollide == true)
        ppI.setTog(ppI.shadTog, first.CastShadow == true)

        -- re-adornee the gizmos to the new primary (no-op if gizmos are off)
        if ppI.attachGizmos then ppI.attachGizmos() end
        if ppI.syncPasteUI then ppI.syncPasteUI(first) end
    end

    -- Show Invisible Only toggle
    local function ppSetInvisOnly(on)
        ppInvisOnly = on
        ppI.invisCheck.Visible = on
        ppI.invisBtn.BorderColor3 = on and ACCENT or BORDER
        ppRecomputeVis()
    end
    ppI.invisBtn.MouseButton1Click:Connect(function() ppSetInvisOnly(not ppInvisOnly) end)
    ppI.invisLblBtn.MouseButton1Click:Connect(function() ppSetInvisOnly(not ppInvisOnly) end)

    -- Helper: expand every ancestor of `node` in the tree AND collapse
    -- any other top-level branch that isn't the one containing `node`.
    -- Called after Mouse Selection picks something so the row is visible
    -- and unrelated branches close automatically.
    local function ppExpandToAndFocus(node)
        if not node then return end
        -- 1. collect ancestors of this node (excluding node itself)
        local ancestorSet = {}
        local cur = node.parentNode
        while cur do ancestorSet[cur] = true; cur = cur.parentNode end
        -- 2. any hasChildren node NOT in that set (and not root) collapses;
        --    ancestors of the target expand
        for _, n in ipairs(ppNodeList) do
            if n.hasChildren and n.parentNode then
                local wantOpen = ancestorSet[n] == true
                if n.expanded ~= wantOpen then
                    n.expanded = wantOpen
                    if n.arrow then n.arrow.Text = wantOpen and '\u{25BC}' or '\u{25B6}' end
                end
            end
        end
        ppRecomputeVis()
        -- 3. scroll the row into view (best-effort based on LayoutOrder)
        local layout = node.row and node.row.Parent and node.row.Parent:FindFirstChildOfClass('UIListLayout')
        local rowH   = node.row and node.row.AbsoluteSize.Y or 24
        local approxY = (node.row and node.row.LayoutOrder or 1) * rowH
        if ppScroll and ppScroll.Parent then
            task.defer(function()
                pcall(function()
                    ppScroll.CanvasPosition = Vector2.new(0, math.max(0, approxY - 80))
                end)
            end)
        end
    end

    -- ignore list: explicit instances (ancestors count too), name substrings
    -- from the Names box, and optionally anything fully transparent
    ppI.ignored = {}
    ppI.ignoreSkipInvis = false
    ppI.refreshIgnCount = function()
        local n = 0
        for inst in pairs(ppI.ignored) do
            if inst.Parent then n += 1 else ppI.ignored[inst] = nil end
        end
        ppI.ignCountLbl.Text = n .. (n == 1 and ' part' or ' parts') .. ' ignored by hand'
    end
    ppI.isIgnored = function(inst)
        if ppI.ignoreSkipInvis and inst:IsA('BasePart') and inst.Transparency >= 1 then
            return true
        end
        local pats = {}
        for w in string.gmatch(ppI.ignNamesIn.Text or '', '[^,]+') do
            w = w:match('^%s*(.-)%s*$'):lower()
            if w ~= '' then pats[#pats + 1] = w end
        end
        local cur = inst
        while cur and cur ~= workspace and cur ~= game do
            if ppI.ignored[cur] then return true end
            local nm = cur.Name:lower()
            for _, w in ipairs(pats) do
                if nm:find(w, 1, true) then return true end
            end
            cur = cur.Parent
        end
        return false
    end
    -- raycast from the cursor, stepping past ignored parts and the character
    ppI.pickUnderMouse = function(mouse)
        local ray = mouse.UnitRay
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        local excl = { plr.Character }
        params.FilterDescendantsInstances = excl
        for _ = 1, 64 do
            local res = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
            if not res then return nil end
            local hit = res.Instance
            if not ppI.isIgnored(hit) then return hit end
            excl[#excl + 1] = hit
            params.FilterDescendantsInstances = excl
        end
        return nil
    end

    ppI.ignSelBtn.MouseButton1Click:Connect(function()
        local n = 0
        for inst in pairs(ppSelBoxes) do
            if inst and inst.Parent and not ppI.ignored[inst] then
                ppI.ignored[inst] = true; n += 1
            end
        end
        ppI.refreshIgnCount()
        showToast(n > 0 and ('Mouse select now ignores ' .. n .. ' more') or 'No parts selected')
    end)
    ppI.ignClearBtn.MouseButton1Click:Connect(function()
        table.clear(ppI.ignored)
        ppI.refreshIgnCount()
        showToast('Ignore list cleared (name filter still applies)')
    end)
    ppI.ignInvisTog.MouseButton1Click:Connect(function()
        ppI.ignoreSkipInvis = ppI.ignInvisTog.Text == 'OFF'
        ppI.setTog(ppI.ignInvisTog, ppI.ignoreSkipInvis)
    end)

    -- Mouse Selection: click 3D parts to select; Ctrl+click behaves like tree
    local ppMouseConn
    local function ppSetMouseSel(on)
        ppMouseSelOn = on
        ppI.mouseCheck.Visible    = on
        ppI.mouseBtn.BorderColor3 = on and ACCENT or BORDER
        if ppMouseConn then ppMouseConn:Disconnect(); ppMouseConn = nil end
        if not on then return end
        local mouse = plr and plr:GetMouse()
        ppMouseConn = UIS.InputBegan:Connect(function(input, gameProcessed)
            if not ppMouseSelOn then return end
            if gameProcessed then return end   -- click hit a UI element
            local isL = input.UserInputType == Enum.UserInputType.MouseButton1
            local isR = input.UserInputType == Enum.UserInputType.MouseButton2
            if not (isL or isR) then return end
            if not mouse then return end
            local target = ppI.pickUnderMouse(mouse)
            if not target or not target:IsA('BasePart') or target:IsA('Terrain') then return end
            -- right-click: skip the tree flow, just pop the context menu
            if isR then
                if ppShowContextMenu then
                    ppShowContextMenu(target, mouse.X, mouse.Y)
                end
                return
            end
            -- find the matching node in the tree
            local hitNode
            for _, node in ipairs(ppNodeList) do
                if node.instance == target then hitNode = node; break end
            end
            if not hitNode then
                showToast('Part not in tree -- click Refresh'); return
            end
            if ppCtrlDown() then
                ppSetSel(hitNode, not hitNode.selected)
            elseif hitNode.selected then
                ppSetSel(hitNode, false)
            else
                ppDeselectAll()
                ppSetSel(hitNode, true)
                -- expand ancestors + collapse sibling branches + scroll
                ppExpandToAndFocus(hitNode)
            end
        end)
    end
    ppI.mouseBtn.MouseButton1Click:Connect(function() ppSetMouseSel(not ppMouseSelOn) end)
    ppI.mouseLblBtn.MouseButton1Click:Connect(function() ppSetMouseSel(not ppMouseSelOn) end)

    -- Properties: shows/hides the right inspector pane. When hidden the
    -- panel shrinks to 360w so the tree gets the whole space.
    local function ppSetProps(on)
        ppPropsOn = on
        ppI.propsCheck.Visible    = on
        ppI.propsBtn.BorderColor3 = on and ACCENT or BORDER
        if ppI.vDivider then ppI.vDivider.Visible = on end
        if ppI.rScroll  then ppI.rScroll.Visible  = on end
        if ppI.panel    then
            local h = ppI.panel.Size.Y.Offset
            ppI.panel.Size = UDim2.new(0, on and 640 or 360, 0, h)
        end
    end
    ppI.propsBtn.MouseButton1Click:Connect(function() ppSetProps(not ppPropsOn) end)
    ppI.propsLblBtn.MouseButton1Click:Connect(function() ppSetProps(not ppPropsOn) end)
    -- default: Properties is on
    ppSetProps(true)

    -- ============ CONTEXT MENU ============
    -- right-click anywhere on a tree row (or on a world part in Mouse
    -- Selection mode) to open a small floating menu. Currently one action:
    -- Delete (destroys the instance; client-side if no auth, replicates
    -- when the client owns it).
    local ppCtxFrame
    local ppCtxJustCreated = false
    local function ppKillContextMenu()
        if ppCtxFrame then pcall(function() ppCtxFrame:Destroy() end) end
        ppCtxFrame = nil
    end
    ppShowContextMenu = function(inst, x, y)
        ppKillContextMenu()
        if not inst or not inst.Parent then return end
        -- swallow the InputBegan that opened us (same event fires the
        -- global outside-click dismisser); reset on the next tick
        ppCtxJustCreated = true
        task.defer(function() ppCtxJustCreated = false end)
        local menu = Instance.new('Frame')
        menu.Size = UDim2.new(0, 160, 0, 120)
        menu.Position = UDim2.new(0, x, 0, y)
        menu.BackgroundColor3 = BG2
        menu.BorderSizePixel = 1
        menu.BorderColor3 = ACCENT
        menu.ZIndex = 200
        menu.Parent = pp
        ppCtxFrame = menu
        -- header (target name)
        local hdr = Instance.new('TextLabel')
        hdr.Size = UDim2.new(1, -6, 0, 20)
        hdr.Position = UDim2.new(0, 6, 0, 4)
        hdr.BackgroundTransparency = 1
        hdr.Text = inst.Name
        hdr.TextColor3 = SUBTEXT
        hdr.TextTruncate = Enum.TextTruncate.AtEnd
        hdr.Font = Enum.Font.Code
        hdr.TextSize = 11
        hdr.TextXAlignment = Enum.TextXAlignment.Left
        hdr.ZIndex = 201
        hdr.Parent = menu
        -- delete button
        local del = Instance.new('TextButton')
        del.Size = UDim2.new(1, -8, 0, 26)
        del.Position = UDim2.new(0, 4, 0, 28)
        del.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
        del.BorderSizePixel = 0
        del.Text = 'Delete'
        del.TextColor3 = TEXT
        del.Font = Enum.Font.Code
        del.TextSize = 12
        del.AutoButtonColor = true
        del.ZIndex = 201
        del.Parent = menu
        del.MouseButton1Click:Connect(function()
            local name = inst.Name
            pcall(function() inst:Destroy() end)
            showToast('Deleted "' .. name .. '"')
            ppKillContextMenu()
            if ppBuildTreePublic then task.defer(function() pcall(ppBuildTreePublic) end) end
        end)
        local function ctxBtn(text, y, onClick)
            local b = Instance.new('TextButton')
            b.Size = UDim2.new(1, -8, 0, 26); b.Position = UDim2.new(0, 4, 0, y)
            b.BackgroundColor3 = BGSUB; b.BorderSizePixel = 0
            b.Text = text; b.TextColor3 = TEXT; b.Font = Enum.Font.Code; b.TextSize = 12
            b.AutoButtonColor = true; b.ZIndex = 201; b.Parent = menu
            b.MouseButton1Click:Connect(function() ppKillContextMenu(); onClick() end)
        end
        ctxBtn('Copy Data', 58, function()
            local list = {}
            if inst:IsA('BasePart') then list[1] = inst
            else
                for _, d in ipairs(inst:GetDescendants()) do
                    if d:IsA('BasePart') then list[#list + 1] = d end
                end
            end
            if ppI.copyParts then ppI.copyParts(list) end
        end)
        ctxBtn(ppI.ignored[inst] and 'Un-ignore (mouse)' or 'Ignore (mouse)', 88, function()
            ppI.ignored[inst] = (not ppI.ignored[inst]) or nil
            ppI.refreshIgnCount()
            showToast((ppI.ignored[inst] and 'Ignoring "' or 'Un-ignored "') .. inst.Name .. '"')
        end)
    end
    -- dismiss on any click outside the menu
    UIS.InputBegan:Connect(function(input, gp)
        if not ppCtxFrame then return end
        if ppCtxJustCreated then return end  -- ignore the event that opened us
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
           and input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
        local mp = UIS:GetMouseLocation()
        local abs = ppCtxFrame.AbsolutePosition
        local sz  = ppCtxFrame.AbsoluteSize
        if mp.X < abs.X or mp.X > abs.X + sz.X or mp.Y < abs.Y or mp.Y > abs.Y + sz.Y then
            ppKillContextMenu()
        end
    end)

    -- Material Apply -- reads the current dropdown value, commits to selection
    ppI.matBtn.MouseButton1Click:Connect(function()
        local v = ppI.matDD.value or 'SmoothPlastic'
        local matEnum = Enum.Material[v] or Enum.Material.SmoothPlastic
        local n = ppUndoable('Material ' .. v, {'Material'},
            function(p) p.Material = matEnum end)
        if n > 0 then showToast(v .. ' -> ' .. n .. ' part(s)') end
    end)

    -- Transparency Apply -- undoable
    ppI.transBtn.MouseButton1Click:Connect(function()
        local v = math.clamp(tonumber(ppI.transIn.Text) or 0, 0, 1)
        local n = ppUndoable('Transparency ' .. v, {'Transparency'},
            function(p) p.Transparency = v end)
        if n > 0 then showToast('Transparency ' .. v .. ' (' .. n .. ')') end
    end)

    -- Reflectance Apply -- undoable
    ppI.reflBtn.MouseButton1Click:Connect(function()
        local v = math.clamp(tonumber(ppI.reflIn.Text) or 0, 0, 1)
        local n = ppUndoable('Reflectance ' .. v, {'Reflectance'},
            function(p) p.Reflectance = v end)
        if n > 0 then showToast('Reflectance ' .. v .. ' (' .. n .. ')') end
    end)

    -- ppVisualCache was hoisted to the very top of the pp do-block so
    -- the gizmo wire fns (lexically higher up) can see it. The Pos/Rot/
    -- Size Apply handlers below check it to decide whether to mutate the
    -- real part (normal mode) or update the ghost's offset (visual-only).

    -- Pos/Rot/Size Apply buttons are now RELATIVE: input XYZ is a delta
    -- ADDED to each selected part's current state, not an absolute value.
    -- Accumulated deltas are tracked in _G.ppDeltas keyed by BasePart and
    -- serialized by the config save so unchanged parts stay at 0 (loading
    -- doesn't clobber bike geometry the user never touched).
    _G.ppDeltas = _G.ppDeltas or {}
    local function ppDeltaFor(part)
        local d = _G.ppDeltas[part]
        if not d then
            d = { pos = Vector3.new(), rot = Vector3.new(), size = Vector3.new() }
            _G.ppDeltas[part] = d
        end
        return d
    end

    -- Position Apply: ADD (x,y,z) to each selected part's world position.
    -- Visual-only mode: stack the delta onto ghost.posDelta so the ghost
    -- appears offset while the real part stays put.
    ppI.posBtn.MouseButton1Click:Connect(function()
        local x = tonumber(ppI.posX.Text) or 0
        local y = tonumber(ppI.posY.Text) or 0
        local z = tonumber(ppI.posZ.Text) or 0
        local delta = Vector3.new(x, y, z)
        if delta.Magnitude == 0 then showToast('Enter a Pos delta first'); return end
        if ppI.visOnlyTog and ppI.visOnlyTog.Text == 'ON' and ppVisualCache then
            local n = 0
            for p, entry in pairs(ppVisualCache) do
                if p and p.Parent then
                    entry.posDelta = (entry.posDelta or Vector3.new()) + delta
                    n = n + 1
                end
            end
            if n > 0 then showToast('Visual Pos +' .. tostring(delta) .. ' (' .. n .. ')')
            else showToast('No visual-only parts') end
            return
        end
        local n = ppUndoable('Position +' .. tostring(delta), {'CFrame'}, function(p)
            p.CFrame = p.CFrame + delta
            ppDeltaFor(p).pos = ppDeltaFor(p).pos + delta
        end)
        if n > 0 then showToast('Pos +' .. tostring(delta) .. ' (' .. n .. ')') end
    end)

    -- Rotation Apply: ADD Euler (x,y,z) degrees in the part's LOCAL frame.
    -- Visual-only mode: compound onto ghost.rotOffset.
    ppI.rotBtn.MouseButton1Click:Connect(function()
        local dx = tonumber(ppI.rotX.Text) or 0
        local dy = tonumber(ppI.rotY.Text) or 0
        local dz = tonumber(ppI.rotZ.Text) or 0
        if dx == 0 and dy == 0 and dz == 0 then showToast('Enter a Rot delta first'); return end
        local rotCF = CFrame.fromOrientation(math.rad(dx), math.rad(dy), math.rad(dz))
        if ppI.visOnlyTog and ppI.visOnlyTog.Text == 'ON' and ppVisualCache then
            local n = 0
            for p, entry in pairs(ppVisualCache) do
                if p and p.Parent then
                    entry.rotOffset = (entry.rotOffset or CFrame.new()) * rotCF
                    n = n + 1
                end
            end
            if n > 0 then showToast('Visual Rot (' .. n .. ')')
            else showToast('No visual-only parts') end
            return
        end
        local n = ppUndoable('Rotation +(' .. dx .. ',' .. dy .. ',' .. dz .. ')',
            {'CFrame'}, function(p)
                p.CFrame = p.CFrame * rotCF
                local d = ppDeltaFor(p).rot
                ppDeltaFor(p).rot = Vector3.new(d.X + dx, d.Y + dy, d.Z + dz)
            end)
        if n > 0 then showToast('Rot +(' .. dx .. ',' .. dy .. ',' .. dz .. ') (' .. n .. ')') end
    end)

    -- Size Apply: ADD (x,y,z) to each selected part's Size. Visual-only
    -- mode: stack onto ghost.sizeOverride from the current real size.
    ppI.sizeBtn.MouseButton1Click:Connect(function()
        local dx = tonumber(ppI.sizeX.Text) or 0
        local dy = tonumber(ppI.sizeY.Text) or 0
        local dz = tonumber(ppI.sizeZ.Text) or 0
        if dx == 0 and dy == 0 and dz == 0 then showToast('Enter a Size delta first'); return end
        local delta = Vector3.new(dx, dy, dz)
        if ppI.visOnlyTog and ppI.visOnlyTog.Text == 'ON' and ppVisualCache then
            local n = 0
            for p, entry in pairs(ppVisualCache) do
                if p and p.Parent then
                    local base = entry.sizeOverride or p.Size
                    entry.sizeOverride = Vector3.new(
                        math.max(0.05, base.X + dx),
                        math.max(0.05, base.Y + dy),
                        math.max(0.05, base.Z + dz))
                    n = n + 1
                end
            end
            if n > 0 then showToast('Visual Size (' .. n .. ')')
            else showToast('No visual-only parts') end
            return
        end
        local n = ppUndoable('Size +' .. tostring(delta), {'Size'}, function(p)
            p.Size = Vector3.new(
                math.max(0.05, p.Size.X + dx),
                math.max(0.05, p.Size.Y + dy),
                math.max(0.05, p.Size.Z + dz))
            ppDeltaFor(p).size = ppDeltaFor(p).size + delta
        end)
        if n > 0 then showToast('Size +' .. tostring(delta) .. ' (' .. n .. ')') end
    end)

    -- physics toggles: ON/OFF mirrors the primary via ppRefreshInspector
    ppI.anchTog.MouseButton1Click:Connect(function()
        local on = ppI.anchTog.Text == 'OFF'
        ppI.setTog(ppI.anchTog, on)
        local n = ppUndoable('Anchored ' .. (on and 'ON' or 'OFF'),
            {'Anchored'}, function(p) p.Anchored = on end)
        if n > 0 then showToast('Anchored ' .. (on and 'ON' or 'OFF') .. ' (' .. n .. ')') end
    end)
    ppI.collTog.MouseButton1Click:Connect(function()
        local on = ppI.collTog.Text == 'OFF'
        ppI.setTog(ppI.collTog, on)
        local n = ppUndoable('CanCollide ' .. (on and 'ON' or 'OFF'),
            {'CanCollide'}, function(p) p.CanCollide = on end)
        if n > 0 then showToast('CanCollide ' .. (on and 'ON' or 'OFF') .. ' (' .. n .. ')') end
    end)
    ppI.shadTog.MouseButton1Click:Connect(function()
        local on = ppI.shadTog.Text == 'OFF'
        ppI.setTog(ppI.shadTog, on)
        local n = ppUndoable('CastShadow ' .. (on and 'ON' or 'OFF'),
            {'CastShadow'}, function(p) p.CastShadow = on end)
        if n > 0 then showToast('CastShadow ' .. (on and 'ON' or 'OFF') .. ' (' .. n .. ')') end
    end)

    -- Gizmo mode buttons: click one to pick a mode, click the active one
    -- again to turn gizmos off. Only one adornment class is on at a time.
    ppI.gizmoMoveBtn.MouseButton1Click:Connect(function() ppI.setGizmoMode('move') end)
    ppI.gizmoRotBtn .MouseButton1Click:Connect(function() ppI.setGizmoMode('rot')  end)
    ppI.gizmoSizeBtn.MouseButton1Click:Connect(function() ppI.setGizmoMode('size') end)

    -- Visual Only: real part stays 100% normal (still welded, still spinning,
    -- still colliding, still contributing mass). We just spawn a ghost clone
    -- that heartbeats to follow the real part's CFrame with a user offset
    -- applied. Wheel keeps spinning under the ghost; ghost spins with it.
    -- ppVisualCache was hoisted to the top of the pp do-block; do not
    -- overwrite it, just make sure the connection state is fresh here.
    local ppVisualConn

    local function ppMakeGhost(real)
        local ok, clone = pcall(function() return real:Clone() end)
        if not ok or not clone then return nil end
        -- strip everything that isn't purely visual (joints, constraints,
        -- movers, scripts, sounds all get destroyed; decals/meshes stay)
        for _, ch in ipairs(clone:GetChildren()) do
            local keep = ch:IsA('Decal') or ch:IsA('Texture')
                or ch:IsA('DataModelMesh') or ch:IsA('SurfaceAppearance')
            if not keep then pcall(function() ch:Destroy() end) end
        end
        pcall(function()
            clone.Anchored     = true
            clone.CanCollide   = false
            clone.CanTouch     = false
            clone.CanQuery     = false
            clone.Massless     = true
            clone.Name         = real.Name .. '__VisGhost'
            clone.CFrame       = real.CFrame
            clone.Parent       = workspace
        end)
        return clone
    end

    local function ppTearDownVisual()
        if ppVisualConn then ppVisualConn:Disconnect(); ppVisualConn = nil end
        for p, entry in pairs(ppVisualCache) do
            if entry.ghost then pcall(function() entry.ghost:Destroy() end) end
            -- restore the real part's client-side transparency modifier
            if p and p.Parent then
                pcall(function() p.LocalTransparencyModifier = entry.origLTM or 0 end)
            end
            ppVisualCache[p] = nil
        end
    end

    ppI.visOnlyTog.MouseButton1Click:Connect(function()
        local on = ppI.visOnlyTog.Text == 'OFF'
        ppI.setTog(ppI.visOnlyTog, on)
        if on then
            local n = 0
            for _, p in ipairs(ppSelectedBaseParts()) do
                if ppVisualCache[p] == nil then
                    local g = ppMakeGhost(p)
                    if g then
                        ppVisualCache[p] = {
                            ghost        = g,
                            posDelta     = Vector3.new(0, 0, 0),
                            rotOffset    = CFrame.new(),
                            sizeOverride = nil,
                            origLTM      = p.LocalTransparencyModifier or 0,
                        }
                        -- hide the real part on THIS client only (server + other
                        -- players still see it normally, physics untouched)
                        pcall(function() p.LocalTransparencyModifier = 1 end)
                        n = n + 1
                    end
                end
            end
            if n == 0 then
                ppI.setTog(ppI.visOnlyTog, false)
                showToast('Visual Only: select parts first')
                return
            end
            if not ppVisualConn then
                ppVisualConn = RunService.RenderStepped:Connect(function()
                    for p, entry in pairs(ppVisualCache) do
                        if p and p.Parent and entry.ghost and entry.ghost.Parent then
                            entry.ghost.CFrame = (p.CFrame + entry.posDelta) * entry.rotOffset
                            if entry.sizeOverride then
                                entry.ghost.Size = entry.sizeOverride
                            end
                        elseif entry.ghost then
                            pcall(function() entry.ghost:Destroy() end)
                            ppVisualCache[p] = nil
                        end
                    end
                end)
            end
            showToast('Visual Only ON (' .. n .. ' ghost(s))')
        else
            ppTearDownVisual()
            showToast('Visual Only OFF')
        end
    end)

    -- Decal Visible toggle: flip every existing Decal/Texture Transparency
    ppI.decVisTog.MouseButton1Click:Connect(function()
        local on = ppI.decVisTog.Text == 'OFF'
        ppI.setTog(ppI.decVisTog, on)
        local n = ppApplyToDecals(function(d) d.Transparency = on and 0 or 1 end)
        if n == 0 then showToast('No decals on selection')
        else showToast('Decals ' .. (on and 'shown' or 'hidden') .. ' (' .. n .. ')') end
    end)

    -- Apply Texture: replace existing decals or create one on the chosen face
    ppI.texApplyBtn.MouseButton1Click:Connect(function()
        local num = (ppI.texIn.Text or ''):match('%d+')
        if not num then showToast('Enter an asset ID'); return end
        local uri  = 'rbxassetid://' .. num
        local face = Enum.NormalId[ppI.faceDD.value] or Enum.NormalId.Front
        local parts = ppSelectedBaseParts()
        if #parts == 0 then showToast('No parts selected'); return end
        local updated, created = 0, 0
        for _, inst in ipairs(parts) do
            local decals = {}
            for _, ch in ipairs(inst:GetChildren()) do
                if ch:IsA('Decal') then decals[#decals + 1] = ch end
            end
            if #decals == 0 then
                local d = Instance.new('Decal')
                d.Texture = uri; d.Face = face; d.Parent = inst
                created += 1
            else
                for _, d in ipairs(decals) do
                    pcall(function() d.Texture = uri; d.Face = face end)
                    updated += 1
                end
            end
        end
        showToast('Texture: ' .. updated .. ' updated, ' .. created .. ' created')
        ppRefreshInspector()
    end)

    -- Remove all decals + textures from the selection
    ppI.texRmBtn.MouseButton1Click:Connect(function()
        local n = ppApplyToDecals(function(d) d:Destroy() end)
        if n == 0 then showToast('No decals on selection')
        else showToast('Removed ' .. n .. ' decal(s)') end
        ppRefreshInspector()
    end)

    do
        local HS = game:GetService('HttpService')
        local PREFIX = 'KPART1:'
        local setClip = setclipboard or toclipboard or (syn and syn.write_clipboard)
        local clipCache = nil   -- { key, clones } from the last copy this session
        local pasted = {}       -- [part] = { anchor, offset, last, lastAnchor, collide, weight, twin, weld }
        local pasteState = { collide = false, weight = 0 }
        local followConn
        local GENERIC = { Part = true, MeshPart = true, Union = true, WedgePart = true,
                          Handle = true, UnionOperation = true }

        -- %.9g round-trips float32 exactly, which is what Roblox stores
        local function enc(...)
            local t = { ... }
            for i, v in ipairs(t) do t[i] = string.format('%.9g', v) end
            return table.concat(t, ',')
        end
        local function dec(s)
            local t = {}
            for x in string.gmatch(s or '', '[^,]+') do t[#t + 1] = tonumber(x) end
            return t
        end
        local function decV3(s)
            local t = dec(s)
            if #t < 3 then return nil end
            return Vector3.new(t[1], t[2], t[3])
        end
        local function decC3(s)
            local t = dec(s)
            if #t < 3 then return nil end
            return Color3.new(t[1], t[2], t[3])
        end
        local function decCF(s)
            local t = dec(s)
            if #t ~= 12 then return nil end
            return CFrame.new(table.unpack(t))
        end
        local function get(o, k)
            local ok, v = pcall(function() return o[k] end)
            if ok then return v end
        end
        local function set(o, k, v)
            if v ~= nil then pcall(function() o[k] = v end) end
        end

        local function ownSeat()
            local char = plr.Character
            local hum = char and char:FindFirstChildWhichIsA('Humanoid')
            return hum and hum.SeatPart
        end
        -- vehicle a part belongs to: your own root if inside it, else its top model
        local function rootOf(part)
            local own = ppGetRootModel()
            if own and part:IsDescendantOf(own) then return own end
            local top = part
            while top.Parent and top.Parent ~= workspace do top = top.Parent end
            return top:IsA('Model') and top or nil
        end
        -- reference frame for layout: seat, else pivot
        local function refFor(root)
            local own = ppGetRootModel()
            local seat = ownSeat()
            if root and own == root and seat then return seat.CFrame end
            if root then
                local vs = root:FindFirstChildWhichIsA('VehicleSeat', true)
                    or root:FindFirstChildWhichIsA('Seat', true)
                if vs then return vs.CFrame end
                return root:GetPivot()
            end
            return seat and seat.CFrame or CFrame.new()
        end
        -- the part this one is rigidly attached to (pasted parts report their anchor)
        local function partnerOf(p)
            if pasted[p] then return pasted[p].anchor end
            for _, j in ipairs(p:GetJoints()) do
                local a, b
                if j:IsA('JointInstance') or j:IsA('WeldConstraint') then
                    a, b = j.Part0, j.Part1
                elseif j:IsA('RigidConstraint') then
                    a = j.Attachment0 and j.Attachment0.Parent
                    b = j.Attachment1 and j.Attachment1.Parent
                end
                local other = (a == p) and b or a
                if other and other ~= p and other:IsA('BasePart') then return other end
            end
        end
        local function pathIn(root, inst)
            local names, cur = {}, inst
            while cur and cur ~= root do
                table.insert(names, 1, cur.Name); cur = cur.Parent
            end
            return cur == root and names or nil
        end

        local function meshSizeOf(p)
            local ms = get(p, 'MeshSize')
            if typeof(ms) ~= 'Vector3' and gethiddenproperty then
                local ok, v = pcall(gethiddenproperty, p, 'MeshSize')
                if ok then ms = v end
            end
            return typeof(ms) == 'Vector3' and ms or nil
        end

        local function childRec(ch)
            local r = { k = ch.ClassName }
            if ch:IsA('Decal') then
                r.tx = ch.Texture; r.f = ch.Face.Name; r.t = ch.Transparency
                r.col = enc(ch.Color3.R, ch.Color3.G, ch.Color3.B); r.z = ch.ZIndex
                if ch:IsA('Texture') then
                    r.su = enc(ch.StudsPerTileU, ch.StudsPerTileV, ch.OffsetStudsU, ch.OffsetStudsV)
                end
            elseif ch:IsA('SpecialMesh') then
                r.mt = ch.MeshType.Name; r.id = ch.MeshId; r.tx = ch.TextureId
                r.sc = enc(ch.Scale.X, ch.Scale.Y, ch.Scale.Z)
                r.of = enc(ch.Offset.X, ch.Offset.Y, ch.Offset.Z)
                r.vc = enc(ch.VertexColor.X, ch.VertexColor.Y, ch.VertexColor.Z)
            elseif ch:IsA('DataModelMesh') then
                r.sc = enc(ch.Scale.X, ch.Scale.Y, ch.Scale.Z)
                r.of = enc(ch.Offset.X, ch.Offset.Y, ch.Offset.Z)
            elseif ch:IsA('Light') then
                r.b = ch.Brightness; r.col = enc(ch.Color.R, ch.Color.G, ch.Color.B)
                r.sh = ch.Shadows; r.e = ch.Enabled; r.rg = get(ch, 'Range')
                r.a = get(ch, 'Angle'); local f = get(ch, 'Face'); r.f = f and f.Name
            else
                return nil
            end
            return r
        end

        local function partRec(p, root, ref)
            local c = p.Color
            local r = {
                c = p.ClassName, n = p.Name,
                cf = enc(ref:ToObjectSpace(p.CFrame):GetComponents()),
                s = enc(p.Size.X, p.Size.Y, p.Size.Z),
                col = enc(c.R, c.G, c.B),
                m = p.Material.Name, mv = get(p, 'MaterialVariant'),
                t = p.Transparency, r = p.Reflectance, cs = p.CastShadow,
            }
            local partner = partnerOf(p)
            local path = partner and root and pathIn(root, partner)
            if path then
                r.rn = partner.Name; r.rp = path
                r.rcf = enc(partner.CFrame:ToObjectSpace(p.CFrame):GetComponents())
            end
            if p:IsA('Part') then r.sh = p.Shape.Name end
            if p:IsA('MeshPart') then
                r.mid = get(p, 'MeshId'); r.tid = get(p, 'TextureID')
                r.ds = get(p, 'DoubleSided')
                local ms = meshSizeOf(p)
                if ms then r.ms = enc(ms.X, ms.Y, ms.Z) end
            end
            if p:FindFirstChildOfClass('SurfaceAppearance') then r.sa = true end
            local kids = {}
            for _, ch in ipairs(p:GetChildren()) do
                local cr = childRec(ch)
                if cr then kids[#kids + 1] = cr end
            end
            if #kids > 0 then r.ch = kids end
            return r
        end

        -- session clone: keeps unions/SurfaceAppearance that data alone can't rebuild
        local function cleanClone(p, bare)
            local wasArch = p.Archivable
            pcall(function() p.Archivable = true end)
            local ok, cl = pcall(function() return p:Clone() end)
            pcall(function() p.Archivable = wasArch end)
            if not ok or not cl then return nil end
            for _, d in ipairs(cl:GetDescendants()) do
                if bare or d:IsA('JointInstance') or d:IsA('WeldConstraint') or d:IsA('Constraint')
                    or d:IsA('NoCollisionConstraint') or d:IsA('BodyMover')
                    or d:IsA('LuaSourceContainer') or d:IsA('Sound') or d:IsA('BasePart')
                    or d:IsA('Model') or d:IsA('ProximityPrompt') or d:IsA('ClickDetector') then
                    pcall(function() d:Destroy() end)
                end
            end
            return cl
        end

        ppI.copyParts = function(list)
            if #list == 0 then showToast('No parts selected'); return end
            local root = rootOf(list[1])
            local ref = refFor(root)
            local key = HS:GenerateGUID(false)
            local recs, clones = {}, {}
            for i, p in ipairs(list) do
                recs[i] = partRec(p, root, ref)
                clones[i] = cleanClone(p)
            end
            clipCache = { key = key, clones = clones }
            local data = PREFIX .. HS:JSONEncode({ v = 1, k = key, parts = recs })
            ppI.copyOut.Text = data
            local copied = setClip and pcall(setClip, data)
            showToast('Copied ' .. #list .. ' part(s)' .. (copied and ' to clipboard' or ' (clipboard unavailable, use the box)'))
        end

        local function newMeshPart(id)
            local AS = game:GetService('AssetService')
            local ok, mp = false, nil
            if Content and Content.fromUri then
                ok, mp = pcall(function() return AS:CreateMeshPartAsync(Content.fromUri(id)) end)
            end
            if not ok or typeof(mp) ~= 'Instance' then
                ok, mp = pcall(function() return AS:CreateMeshPartAsync(id) end)
            end
            if ok and typeof(mp) == 'Instance' then return mp end
        end

        local function buildChild(r, parent)
            local ok, ch = pcall(Instance.new, r.k)
            if not ok then return end
            if r.k == 'Decal' or r.k == 'Texture' then
                set(ch, 'Texture', r.tx); set(ch, 'Face', r.f and Enum.NormalId[r.f])
                set(ch, 'Transparency', r.t); set(ch, 'Color3', decC3(r.col)); set(ch, 'ZIndex', r.z)
                local su = dec(r.su)
                if #su == 4 then
                    set(ch, 'StudsPerTileU', su[1]); set(ch, 'StudsPerTileV', su[2])
                    set(ch, 'OffsetStudsU', su[3]); set(ch, 'OffsetStudsV', su[4])
                end
            elseif r.k == 'SpecialMesh' then
                set(ch, 'MeshType', r.mt and Enum.MeshType[r.mt]); set(ch, 'MeshId', r.id)
                set(ch, 'TextureId', r.tx); set(ch, 'Scale', decV3(r.sc))
                set(ch, 'Offset', decV3(r.of)); set(ch, 'VertexColor', decV3(r.vc))
            elseif ch:IsA('DataModelMesh') then
                set(ch, 'Scale', decV3(r.sc)); set(ch, 'Offset', decV3(r.of))
            elseif ch:IsA('Light') then
                set(ch, 'Brightness', r.b); set(ch, 'Color', decC3(r.col)); set(ch, 'Shadows', r.sh)
                set(ch, 'Enabled', r.e); set(ch, 'Range', r.rg); set(ch, 'Angle', r.a)
                set(ch, 'Face', r.f and Enum.NormalId[r.f])
            end
            ch.Parent = parent
        end

        -- returns the part plus a note when something could not be rebuilt exactly
        local function buildPart(r)
            local size = decV3(r.s) or Vector3.one
            local p, note
            if r.c == 'MeshPart' and r.mid and r.mid ~= '' then
                p = newMeshPart(r.mid)
                if p then
                    set(p, 'TextureID', r.tid); set(p, 'DoubleSided', r.ds)
                else
                    p = Instance.new('Part')
                    local sm = Instance.new('SpecialMesh')
                    sm.MeshType = Enum.MeshType.FileMesh
                    set(sm, 'MeshId', r.mid); set(sm, 'TextureId', r.tid)
                    local ms = decV3(r.ms)
                    if ms and ms.X > 0 and ms.Y > 0 and ms.Z > 0 then
                        sm.Scale = size / ms
                        -- keep the Size gizmo scaling the mesh like a real MeshPart
                        p:GetPropertyChangedSignal('Size'):Connect(function()
                            sm.Scale = p.Size / ms
                        end)
                    else
                        note = 'mesh scale guessed'
                    end
                    sm.Parent = p
                end
            elseif r.c == 'WedgePart' or r.c == 'CornerWedgePart' or r.c == 'Part' then
                p = Instance.new(r.c)
            else
                p = Instance.new('Part'); note = r.c .. ' rebuilt as block'
            end
            if r.sa then note = 'SurfaceAppearance needs same-session paste' end
            set(p, 'Shape', r.sh and Enum.PartType[r.sh])
            p.Size = size
            set(p, 'Color', decC3(r.col))
            set(p, 'Material', r.m and Enum.Material[r.m])
            if r.mv and r.mv ~= '' then set(p, 'MaterialVariant', r.mv) end
            set(p, 'Transparency', r.t); set(p, 'Reflectance', r.r); set(p, 'CastShadow', r.cs)
            p.Name = r.n or 'Pasted'
            for _, cr in ipairs(r.ch or {}) do pcall(buildChild, cr, p) end
            return p, note
        end

        -- weight goes through density (Roblox clamps it to 0.0001..100)
        local function applyWeight(tw, w)
            if w <= 0 then tw.Massless = true; return 0 end
            tw.Massless = false
            local base = PhysicalProperties.new(tw.Material)
            tw.CustomPhysicalProperties = PhysicalProperties.new(1, base.Friction, base.Elasticity,
                base.FrictionWeight, base.ElasticityWeight)
            local vol = tw:GetMass()
            local d = math.clamp(w / math.max(vol, 1e-6), 0.0001, 100)
            tw.CustomPhysicalProperties = PhysicalProperties.new(d, base.Friction, base.Elasticity,
                base.FrictionWeight, base.ElasticityWeight)
            return tw:GetMass()
        end

        -- the visible part stays an anchored follower (gizmo-safe); collision and
        -- mass live on an invisible twin welded to the anchor, synced from edits
        local function applyPhys(part)
            local e = pasted[part]
            if not e then return 0 end
            if not e.collide and e.weight <= 0 then
                if e.twin then pcall(function() e.twin:Destroy() end) end
                e.twin, e.weld = nil, nil
                return 0
            end
            if not e.twin or not e.twin.Parent then
                local tw = cleanClone(part, true)
                if not tw then return 0 end
                tw.Name = part.Name .. '__Phys'
                tw:SetAttribute('KPastePhys', true)
                tw.Anchored = false; tw.Transparency = 1; tw.CastShadow = false
                set(tw, 'CanQuery', false); set(tw, 'CanTouch', false)
                tw.CFrame = e.anchor.CFrame * e.offset
                local w = Instance.new('Weld')
                w.Part0 = e.anchor; w.Part1 = tw; w.C0 = e.offset; w.Parent = tw
                tw.Parent = part
                e.twin, e.weld, e.twinOff, e.twinSize = tw, w, e.offset, part.Size
            end
            e.twin.CanCollide = e.collide
            return applyWeight(e.twin, e.weight)
        end

        -- an outside CFrame write (gizmo, Apply, undo) is folded into the offset
        local function ensureFollow()
            if followConn then return end
            followConn = RunService.RenderStepped:Connect(function()
                for part, e in pairs(pasted) do
                    local a = e.anchor
                    if part.Parent and a and a.Parent then
                        if e.last and not part.CFrame:FuzzyEq(e.last, 1e-4) then
                            e.offset = e.lastAnchor:ToObjectSpace(part.CFrame)
                        end
                        part.CFrame = a.CFrame * e.offset
                        e.last = part.CFrame; e.lastAnchor = a.CFrame
                        if e.twin and e.twin.Parent then
                            if e.twinOff ~= e.offset then e.weld.C0 = e.offset; e.twinOff = e.offset end
                            if e.twinSize ~= part.Size then
                                e.twin.Size = part.Size; e.twinSize = part.Size
                                applyWeight(e.twin, e.weight)
                            end
                        end
                        -- drive the Visual Only ghost here too so it never lags a frame
                        local ve = ppVisualCache[part]
                        if ve and ve.ghost and ve.ghost.Parent then
                            ve.ghost.CFrame = (part.CFrame + ve.posDelta) * ve.rotOffset
                        end
                    end
                end
            end)
        end

        local function resolveAnchor(a)
            while a and pasted[a] and pasted[a].anchor do a = pasted[a].anchor end
            return a
        end

        local function finalize(p, anchor, worldCF)
            p.Anchored = true; p.CanCollide = false; p.CanTouch = false
            set(p, 'CanQuery', true); set(p, 'Massless', true)
            p.CFrame = worldCF
            pasted[p] = { anchor = anchor, offset = anchor.CFrame:ToObjectSpace(worldCF),
                          last = p.CFrame, lastAnchor = anchor.CFrame,
                          collide = pasteState.collide, weight = pasteState.weight }
        end

        -- same path first, then a unique non-generic name anywhere in the vehicle
        local function findPartner(root, folder, r)
            if type(r.rp) == 'table' then
                local cur = root
                for _, nm in ipairs(r.rp) do
                    cur = cur and cur:FindFirstChild(nm)
                end
                if cur and cur:IsA('BasePart') then return cur end
            end
            if type(r.rn) ~= 'string' or GENERIC[r.rn] then return nil end
            local hit
            for _, d in ipairs(root:GetDescendants()) do
                if d.Name == r.rn and d:IsA('BasePart') and not d:IsDescendantOf(folder) then
                    if hit then return nil end
                    hit = d
                end
            end
            return hit
        end

        ppI.pasteBtn.MouseButton1Click:Connect(function()
            local raw = ppI.pasteIn.Text or ''
            local json = raw:match('{.*}')
            local ok, data = pcall(function() return HS:JSONDecode(json or '') end)
            if not ok or type(data) ~= 'table' or type(data.parts) ~= 'table' then
                showToast('Paste box has no valid part data'); return
            end
            local root, seat = ppGetRootModel(), ownSeat()
            if not root or not seat then showToast('Sit on a vehicle first'); return end

            local folder = root:FindFirstChild('KonstantPasted')
            if not folder then
                folder = Instance.new('Folder'); folder.Name = 'KonstantPasted'; folder.Parent = root
            end

            -- unmatched parts follow the first selected part (or the seat)
            local fallback = seat
            for _, p in ipairs(ppSelectedBaseParts()) do fallback = p; break end
            fallback = resolveAnchor(fallback)

            -- pass 1: partner matches place exactly; the rest keep their layout
            -- around the vehicle's bounding-box center
            local plan, loose, sum = {}, {}, Vector3.zero
            for i, r in ipairs(data.parts) do
                local partner = findPartner(root, folder, r)
                local rcf = decCF(r.rcf)
                if partner and rcf then
                    plan[i] = { anchor = resolveAnchor(partner), cf = partner.CFrame * rcf }
                else
                    local rel = decCF(r.cf) or CFrame.new()
                    loose[#loose + 1] = { i = i, rel = rel }
                    sum += rel.Position
                end
            end
            if #loose > 0 then
                local centroid = sum / #loose
                local bb = root:GetBoundingBox()
                local center = CFrame.new(bb.Position) * seat.CFrame.Rotation
                for _, l in ipairs(loose) do
                    plan[l.i] = { anchor = fallback,
                                  cf = center * CFrame.new(-centroid) * l.rel, loose = true }
                end
            end

            local useCache = clipCache and clipCache.key == data.k
            local made, notes, nLoose = {}, {}, 0
            for i, r in ipairs(data.parts) do
                local pl = plan[i]
                local src = useCache and clipCache.clones[i]
                local p, note
                if src then p = src:Clone() else p, note = buildPart(r) end
                if p and pl then
                    if note then notes[note] = true end
                    if pl.loose then nLoose += 1 end
                    finalize(p, pl.anchor, pl.cf)
                    p.Parent = folder
                    applyPhys(p)
                    made[#made + 1] = p
                end
            end
            if #made == 0 then showToast('Nothing pasted'); return end
            ensureFollow()

            History.push('Paste ' .. #made .. ' part(s)',
                function() for _, p in ipairs(made) do pcall(function() p.Parent = folder end) end end,
                function() for _, p in ipairs(made) do pcall(function() p.Parent = nil end) end end)

            -- rebuild now and select what was pasted so the gizmos grab it
            pcall(ppBuildTree, true)
            local want = {}
            for _, p in ipairs(made) do want[p] = true end
            ppDeselectAll()
            local firstNode
            for _, n in ipairs(ppNodeList) do
                if want[n.instance] then
                    ppSetSel(n, true); firstNode = firstNode or n
                end
            end
            if firstNode then ppExpandToAndFocus(firstNode) end

            local msg = 'Pasted ' .. #made .. (useCache and ' (exact clone)' or '')
            if nLoose > 0 then msg = msg .. ', ' .. nLoose .. ' unmatched -> vehicle center' end
            local extra = {}
            for k in pairs(notes) do extra[#extra + 1] = k end
            if #extra > 0 then msg = msg .. ' - ' .. table.concat(extra, ', ') end
            showToast(msg)
        end)

        local function selectedPasted()
            local out = {}
            for _, p in ipairs(ppSelectedBaseParts()) do
                if pasted[p] then out[#out + 1] = p end
            end
            return out
        end

        ppI.syncPasteUI = function(first)
            local e = first and pasted[first]
            ppI.setTog(ppI.pasteCollTog, e and e.collide or (not e and pasteState.collide))
            ppI.pasteWeightIn.Text = tostring(e and e.weight or pasteState.weight)
        end

        ppI.pasteCollTog.MouseButton1Click:Connect(function()
            local on = ppI.pasteCollTog.Text == 'OFF'
            ppI.setTog(ppI.pasteCollTog, on)
            pasteState.collide = on
            local list = selectedPasted()
            for _, p in ipairs(list) do pasted[p].collide = on; applyPhys(p) end
            showToast('Collide ' .. (on and 'ON' or 'OFF')
                .. (#list > 0 and (' (' .. #list .. ' pasted)') or ' for new pastes'))
        end)

        ppI.pasteWeightBtn.MouseButton1Click:Connect(function()
            local w = math.max(0, tonumber(ppI.pasteWeightIn.Text) or 0)
            ppI.pasteWeightIn.Text = tostring(w)
            pasteState.weight = w
            local list = selectedPasted()
            local total = 0
            for _, p in ipairs(list) do pasted[p].weight = w; total += applyPhys(p) end
            if #list == 0 then
                showToast('Weight ' .. w .. ' for new pastes')
            elseif w <= 0 then
                showToast('Massless (' .. #list .. ' pasted)')
            else
                showToast(string.format('Weight set: %.3f total mass (%d pasted)', total, #list))
            end
        end)

        ppI.copyBtn.MouseButton1Click:Connect(function()
            ppI.copyParts(ppSelectedBaseParts())
        end)
        ppI.clearCpBtn.MouseButton1Click:Connect(function()
            ppI.copyOut.Text = ''; ppI.pasteIn.Text = ''
        end)
        ppI.pasteDelBtn.MouseButton1Click:Connect(function()
            local n = 0
            for part in pairs(pasted) do
                pcall(function() part:Destroy() end)
                pasted[part] = nil; n += 1
            end
            local root = ppGetRootModel()
            local folder = root and root:FindFirstChild('KonstantPasted')
            if folder then pcall(function() folder:Destroy() end) end
            showToast('Deleted ' .. n .. ' pasted part(s)')
        end)
    end

    -- initial render (empty selection)
    ppRefreshInspector()

    -- expose cleanup so SMCleanup can clear in-game outlines on reload
    _G.PPCleanup = function()
        ppClearSelBoxes()
        if ppI.destroyGizmos then ppI.destroyGizmos() end
    end
end

-- ============================================================

-- MINIMAP
-- ============================================================

local MAP_SMALL   = 240
local MAP_LARGE   = 680
local MAP_SCALE   = 0.15     -- pixels per stud
local mapExpanded = false
local GRID        = 32       -- terrain grid cells (32x32)
local CANVAS_PX   = 1200     -- canvas pixel size (covers 8000 studs total)

-- panning in pixels (positive = view shifts right/down = world shifts left/up)
local panPxX = 0
local panPxY = 0

local scanOriginX = 0
local scanOriginZ = 0
local scanDone    = false

minimapGui = Instance.new('ScreenGui')
minimapGui.Name           = 'MinimapGui'
minimapGui.ResetOnSpawn   = false
minimapGui.DisplayOrder   = 998
minimapGui.Enabled        = false
minimapGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
safeParentGui(minimapGui)

local mapFrame = Instance.new('Frame')
mapFrame.Size               = UDim2.new(0, MAP_SMALL, 0, MAP_SMALL + 22)
mapFrame.Position           = UDim2.new(0, 12, 0, 12)
mapFrame.BackgroundColor3   = BG2
mapFrame.BorderSizePixel    = 1
mapFrame.BorderColor3       = BORDER
mapFrame.ClipsDescendants   = false
mapFrame.ZIndex             = 30
mapFrame.Parent             = minimapGui

local mapBar = Instance.new('Frame')
mapBar.Size             = UDim2.new(1, 0, 0, 20)
mapBar.BackgroundColor3 = BG2
mapBar.BorderSizePixel  = 0
mapBar.ZIndex           = 31
mapBar.Parent           = mapFrame

local mapBarAccent = Instance.new('Frame')
mapBarAccent.Size             = UDim2.new(1, 0, 0, 1)
mapBarAccent.Position         = UDim2.new(0, 0, 0, 20)
mapBarAccent.BackgroundColor3 = ACCENT
mapBarAccent.BorderSizePixel  = 0
mapBarAccent.ZIndex           = 31
mapBarAccent.Parent           = mapFrame

local mapTitleLbl = Instance.new('TextLabel')
mapTitleLbl.Size               = UDim2.new(1, -6, 1, 0)
mapTitleLbl.Position           = UDim2.new(0, 6, 0, 0)
mapTitleLbl.BackgroundTransparency = 1
mapTitleLbl.Text               = 'Minimap    X: resize    RMB: pan    LMB: waypoint'
mapTitleLbl.TextColor3         = SUBTEXT
mapTitleLbl.Font               = Enum.Font.Gotham
mapTitleLbl.TextSize           = 9
mapTitleLbl.TextXAlignment     = Enum.TextXAlignment.Left
mapTitleLbl.ZIndex             = 32
mapTitleLbl.Parent             = mapBar

local mapView = Instance.new('Frame')
mapView.Size             = UDim2.new(1, 0, 1, -21)
mapView.Position         = UDim2.new(0, 0, 0, 21)
mapView.BackgroundColor3 = Color3.fromRGB(10, 14, 10)
mapView.BorderSizePixel  = 0
mapView.ClipsDescendants = true
mapView.ZIndex           = 30
mapView.Parent           = mapFrame

-- canvas: the big scrollable world frame.
-- All terrain cells, dots and waypoints live inside it.
-- It is repositioned every frame so the player appears at mapView center + pan.
local canvas = Instance.new('Frame')
canvas.Size                 = UDim2.new(0, CANVAS_PX, 0, CANVAS_PX)
canvas.Position             = UDim2.new(0, 0, 0, 0)
canvas.BackgroundTransparency = 1
canvas.ZIndex               = 29
canvas.Parent               = mapView

-- terrain grid layer (inside canvas)
local terrainLayer = Instance.new('Frame')
terrainLayer.Size                 = UDim2.new(1, 0, 1, 0)
terrainLayer.BackgroundColor3     = Color3.fromRGB(10, 14, 10)
terrainLayer.BorderSizePixel      = 0
terrainLayer.ZIndex               = 29
terrainLayer.Parent               = canvas

local cells = {}
for row = 1, GRID do
    cells[row] = {}
    for col = 1, GRID do
        local c = Instance.new('Frame')
        c.Size             = UDim2.new(1/GRID, 1, 1/GRID, 1)
        c.Position         = UDim2.new((col-1)/GRID, 0, (row-1)/GRID, 0)
        c.BackgroundColor3 = Color3.fromRGB(10, 14, 10)
        c.BorderSizePixel  = 0
        c.ZIndex           = 29
        c.Parent           = terrainLayer
        cells[row][col]    = c
    end
end

-- material -> color lookup
local MAT_COLOR = {
    [Enum.Material.Grass]         = Color3.fromRGB(45, 80, 30),
    [Enum.Material.LeafyGrass]    = Color3.fromRGB(50, 90, 35),
    [Enum.Material.Ground]        = Color3.fromRGB(80, 65, 40),
    [Enum.Material.Mud]           = Color3.fromRGB(70, 55, 30),
    [Enum.Material.Sand]          = Color3.fromRGB(180, 160, 100),
    [Enum.Material.Sandstone]     = Color3.fromRGB(160, 130, 80),
    [Enum.Material.Rock]          = Color3.fromRGB(110, 95, 75),
    [Enum.Material.Slate]         = Color3.fromRGB(90, 85, 80),
    [Enum.Material.Concrete]      = Color3.fromRGB(110, 110, 110),
    [Enum.Material.SmoothPlastic] = Color3.fromRGB(95, 95, 95),
    [Enum.Material.Plastic]       = Color3.fromRGB(85, 85, 85),
    [Enum.Material.Metal]         = Color3.fromRGB(130, 130, 140),
    [Enum.Material.DiamondPlate]  = Color3.fromRGB(140, 140, 150),
    [Enum.Material.Wood]          = Color3.fromRGB(130, 95, 55),
    [Enum.Material.WoodPlanks]    = Color3.fromRGB(140, 105, 60),
    [Enum.Material.Water]         = Color3.fromRGB(25, 75, 175),
    [Enum.Material.Ice]           = Color3.fromRGB(180, 220, 240),
    [Enum.Material.Snow]          = Color3.fromRGB(220, 230, 245),
    [Enum.Material.Cobblestone]   = Color3.fromRGB(100, 95, 85),
    [Enum.Material.Asphalt]       = Color3.fromRGB(55, 55, 60),
    [Enum.Material.Foil]          = Color3.fromRGB(180, 180, 200),
}

local scanGen = 0

local function runTerrainScan()
    scanGen += 1
    local myGen = scanGen
    local char = plr.Character
    local hrp  = char and char:FindFirstChild('HumanoidRootPart')
    if not hrp then return end

    -- fix the scan origin at the player's current position (never updates again)
    scanOriginX = hrp.Position.X
    scanOriginZ = hrp.Position.Z

    local halfStuds   = (CANVAS_PX / 2) / MAP_SCALE
    local studPerCell = (CANVAS_PX / GRID) / MAP_SCALE
    local VOID        = Color3.fromRGB(10, 14, 10)

    for row = 1, GRID do
        if scanGen ~= myGen then return end
        for col = 1, GRID do
            local wx = scanOriginX - halfStuds + (col - 0.5) * studPerCell
            local wz = scanOriginZ - halfStuds + (row - 0.5) * studPerCell
            local result = workspace:Raycast(
                Vector3.new(wx, 600, wz),
                Vector3.new(0, -1200, 0)
            )
            local color = VOID
            if result then
                local mc = MAT_COLOR[result.Material]
                if mc then
                    color = mc
                else
                    local pc = result.Instance and result.Instance.Color
                    color = pc and Color3.new(pc.R*0.65, pc.G*0.65, pc.B*0.65) or Color3.fromRGB(70, 70, 70)
                end
            end
            if cells[row] and cells[row][col] then
                cells[row][col].BackgroundColor3 = color
            end
        end
        task.wait()
    end
    scanDone = true
end

-- N indicator (fixed in mapView corner, not on canvas)
local northLbl = Instance.new('TextLabel')
northLbl.Size               = UDim2.new(0, 14, 0, 14)
northLbl.Position           = UDim2.new(1, -16, 0, 3)
northLbl.BackgroundTransparency = 1
northLbl.Text               = 'N'
northLbl.TextColor3         = ACCENT
northLbl.Font               = Enum.Font.GothamBold
northLbl.TextSize           = 10
northLbl.ZIndex             = 40
northLbl.Parent             = mapView

-- dots and waypoint layers inside canvas
local dotsLayer = Instance.new('Frame')
dotsLayer.Size                 = UDim2.new(0, CANVAS_PX, 0, CANVAS_PX)
dotsLayer.BackgroundTransparency = 1
dotsLayer.ZIndex               = 31
dotsLayer.Parent               = canvas

local wpLayer = Instance.new('Frame')
wpLayer.Size                 = UDim2.new(0, CANVAS_PX, 0, CANVAS_PX)
wpLayer.BackgroundTransparency = 1
wpLayer.ZIndex               = 33
wpLayer.Parent               = canvas

-- self dot (inside canvas/dotsLayer)
local selfDotMap = Instance.new('Frame')
selfDotMap.Size             = UDim2.new(0, 12, 0, 12)
selfDotMap.AnchorPoint      = Vector2.new(0.5, 0.5)
selfDotMap.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
selfDotMap.BorderSizePixel  = 1
selfDotMap.BorderColor3     = Color3.fromRGB(20, 150, 40)
selfDotMap.ZIndex           = 35
selfDotMap.Parent           = dotsLayer

-- direction indicator (Fortnite-style: short pointer at edge of dot, rotates with camera)
local dirLine = Instance.new('Frame')
dirLine.Size             = UDim2.new(0, 5, 0, 7)
dirLine.AnchorPoint      = Vector2.new(0.5, 1)
dirLine.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
dirLine.BorderSizePixel  = 0
dirLine.ZIndex           = 36
dirLine.Parent           = dotsLayer

-- world coords -> canvas pixel position
local function worldToCanvas(wx, wz)
    return CANVAS_PX/2 + (wx - scanOriginX) * MAP_SCALE,
           CANVAS_PX/2 + (wz - scanOriginZ) * MAP_SCALE
end

-- canvas pixel position -> world coords (for placing waypoints on click)
local function canvasToWorld(cpx, cpy, groundY)
    return scanOriginX + (cpx - CANVAS_PX/2) / MAP_SCALE,
           groundY or 0,
           scanOriginZ + (cpy - CANVAS_PX/2) / MAP_SCALE
end

-- waypoints
local mapWPs   = {}
local nextWpId = 1

local function makeWaypoint(wx, wy, wz)
    local id = nextWpId
    nextWpId += 1

    -- minimap dot
    local dot = Instance.new('Frame')
    dot.Size             = UDim2.new(0, 10, 0, 10)
    dot.AnchorPoint      = Vector2.new(0.5, 0.5)
    dot.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
    dot.BorderSizePixel  = 1
    dot.BorderColor3     = Color3.fromRGB(180, 130, 0)
    dot.ZIndex           = 34
    dot.Parent           = wpLayer

    local distLbl = Instance.new('TextLabel')
    distLbl.Size               = UDim2.new(0, 60, 0, 11)
    distLbl.AnchorPoint        = Vector2.new(0.5, 0)
    distLbl.BackgroundTransparency = 1
    distLbl.TextColor3         = Color3.fromRGB(255, 200, 0)
    distLbl.Font               = Enum.Font.Gotham
    distLbl.TextSize           = 9
    distLbl.ZIndex             = 35
    distLbl.Parent             = wpLayer

    local removeBtn = Instance.new('TextButton')
    removeBtn.Size             = UDim2.new(0, 12, 0, 12)
    removeBtn.AnchorPoint      = Vector2.new(1, 1)
    removeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
    removeBtn.BorderSizePixel  = 0
    removeBtn.Text             = 'X'
    removeBtn.TextColor3       = TEXT
    removeBtn.Font             = Enum.Font.GothamBold
    removeBtn.TextSize         = 8
    removeBtn.ZIndex           = 36
    removeBtn.Parent           = wpLayer

    local travelBtn = Instance.new('TextButton')
    travelBtn.Size             = UDim2.new(0, 28, 0, 12)
    travelBtn.AnchorPoint      = Vector2.new(0, 1)
    travelBtn.BackgroundColor3 = ACCENT
    travelBtn.BorderSizePixel  = 0
    travelBtn.Text             = 'Go'
    travelBtn.TextColor3       = TEXT
    travelBtn.Font             = Enum.Font.GothamSemibold
    travelBtn.TextSize         = 8
    travelBtn.ZIndex           = 36
    travelBtn.Parent           = wpLayer

    -- sky beam in the world: tall neon gold pillar visible from far away
    local beamPart = Instance.new('Part')
    beamPart.Size        = Vector3.new(0.5, 400, 0.5)
    beamPart.CFrame      = CFrame.new(wx, wy + 200, wz)
    beamPart.Anchored    = true
    beamPart.CanCollide  = false
    beamPart.Material    = Enum.Material.Neon
    beamPart.Color       = Color3.fromRGB(255, 200, 0)
    beamPart.Transparency = 0.4
    beamPart.CastShadow  = false
    beamPart.Parent      = workspace

    -- invisible anchor at the top of the beam for the name label
    local topPart = Instance.new('Part')
    topPart.Size        = Vector3.new(1, 1, 1)
    topPart.CFrame      = CFrame.new(wx, wy + 415, wz)
    topPart.Anchored    = true
    topPart.CanCollide  = false
    topPart.Transparency = 1
    topPart.Parent      = workspace

    local billboard = Instance.new('BillboardGui')
    billboard.Size        = UDim2.new(0, 240, 0, 70)
    billboard.StudsOffset = Vector3.new(0, 0, 0)
    billboard.AlwaysOnTop = false   -- renders in the actual world, not as an overlay
    billboard.MaxDistance = 5000
    billboard.Parent      = topPart

    local bbName = Instance.new('TextLabel')
    bbName.Size                   = UDim2.new(1, 0, 0.58, 0)
    bbName.Position               = UDim2.new(0, 0, 0, 0)
    bbName.BackgroundTransparency = 1
    bbName.Text                   = 'WP ' .. id
    bbName.TextColor3             = Color3.fromRGB(255, 220, 0)
    bbName.Font                   = Enum.Font.GothamBold
    bbName.TextSize               = 30
    bbName.TextStrokeTransparency = 0.3
    bbName.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    bbName.Parent                 = billboard

    local bbDist = Instance.new('TextLabel')
    bbDist.Size                   = UDim2.new(1, 0, 0.42, 0)
    bbDist.Position               = UDim2.new(0, 0, 0.58, 0)
    bbDist.BackgroundTransparency = 1
    bbDist.TextColor3             = Color3.fromRGB(220, 200, 120)
    bbDist.Font                   = Enum.Font.Gotham
    bbDist.TextSize               = 20
    bbDist.TextStrokeTransparency = 0.3
    bbDist.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    bbDist.Parent                 = billboard

    local wp = {id=id, x=wx, y=wy, z=wz, active=true,
                dot=dot, distLbl=distLbl, removeBtn=removeBtn, travelBtn=travelBtn,
                beamPart=beamPart, topPart=topPart, bbDist=bbDist}
    mapWPs[id] = wp

    removeBtn.MouseButton1Click:Connect(function()
        wp.active = false
        for _, el in ipairs({dot, distLbl, removeBtn, travelBtn}) do el:Destroy() end
        if beamPart and beamPart.Parent then beamPart:Destroy() end
        if topPart  and topPart.Parent  then topPart:Destroy()  end
        mapWPs[id] = nil
        showToast('Waypoint ' .. id .. ' removed')
    end)

    travelBtn.MouseButton1Click:Connect(function()
        local char = plr.Character
        local hrp  = char and char:FindFirstChild('HumanoidRootPart')
        if not hrp then return end
        showToast('Preloading area...')
        task.spawn(function()
            local cam     = workspace.CurrentCamera
            local prevCF  = cam.CFrame
            local prevTyp = cam.CameraType
            cam.CameraType = Enum.CameraType.Scriptable
            cam.CFrame     = CFrame.new(wp.x, wp.y + 120, wp.z)
                             * CFrame.Angles(math.rad(-90), 0, 0)
            task.wait(0.7)
            cam.CFrame     = prevCF
            cam.CameraType = prevTyp
            hrp.CFrame = CFrame.new(wp.x, wp.y + 3, wp.z)
            showToast('Teleported to WP ' .. id)
        end)
    end)

    showToast('Waypoint ' .. id .. ' placed')
end

-- left-click on map = place waypoint (convert screen click -> canvas -> world)
mapView.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        local relX = inp.Position.X - mapView.AbsolutePosition.X
        local relY = inp.Position.Y - mapView.AbsolutePosition.Y
        -- click position inside the canvas
        local cpx = relX - canvas.Position.X.Offset
        local cpy = relY - canvas.Position.Y.Offset
        local char = plr.Character
        local hrp  = char and char:FindFirstChild('HumanoidRootPart')
        local gy   = hrp and hrp.Position.Y or 0
        local wx, wy, wz = canvasToWorld(cpx, cpy, gy)
        makeWaypoint(wx, wy, wz)
    end
end)

-- right-click drag = pan (pixel-based: drags the canvas directly)
local isPanning        = false
local panDragOrigin    = Vector2.new(0, 0)
local panPxAtDragStart = Vector2.new(0, 0)

mapView.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton2 then
        isPanning        = true
        panDragOrigin    = Vector2.new(inp.Position.X, inp.Position.Y)
        panPxAtDragStart = Vector2.new(panPxX, panPxY)
    end
end)
mapView.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton2 then isPanning = false end
end)
UIS.InputChanged:Connect(function(inp)
    if isPanning and inp.UserInputType == Enum.UserInputType.MouseMovement then
        panPxX = panPxAtDragStart.X + (inp.Position.X - panDragOrigin.X)
        panPxY = panPxAtDragStart.Y + (inp.Position.Y - panDragOrigin.Y)
    end
end)

-- X key = resize
UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.X and minimapGui.Enabled then
        mapExpanded   = not mapExpanded
        local newSize = mapExpanded and MAP_LARGE or MAP_SMALL
        TweenService:Create(mapFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, newSize, 0, newSize + 22)
        }):Play()
    end
end)

-- player dot pool
local mapPlrDots = {}

-- update every frame
game:GetService('RunService').Heartbeat:Connect(function()
    if not minimapGui.Enabled then return end

    local char = plr.Character
    local hrp  = char and char:FindFirstChild('HumanoidRootPart')
    if not hrp then return end

    local mw = mapView.AbsoluteSize.X
    local mh = mapView.AbsoluteSize.Y

    -- reposition canvas so the player appears at mapView center + pan offset.
    -- everything inside the canvas (terrain, dots, waypoints) moves with it.
    local cpx, cpy = worldToCanvas(hrp.Position.X, hrp.Position.Z)
    canvas.Position = UDim2.new(0, math.floor(mw/2 - cpx + panPxX),
                                0, math.floor(mh/2 - cpy + panPxY))

    -- self dot at player's canvas position
    selfDotMap.Position = UDim2.new(0, cpx, 0, cpy)

    -- direction indicator: short pointer at edge of dot, rotated by camera look
    local lv    = workspace.CurrentCamera.CFrame.LookVector
    local angle = math.deg(math.atan2(lv.X, -lv.Z))
    dirLine.Position = UDim2.new(0, cpx, 0, cpy)
    dirLine.Rotation = angle

    -- other players
    local alive = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr then
            alive[p] = true
            local pHRP = p.Character and p.Character:FindFirstChild('HumanoidRootPart')
            if pHRP then
                local entry = mapPlrDots[p]
                if not entry then
                    local d = Instance.new('Frame')
                    d.Size             = UDim2.new(0, 6, 0, 6)
                    d.AnchorPoint      = Vector2.new(0.5, 0.5)
                    d.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
                    d.BorderSizePixel  = 0
                    d.ZIndex           = 32
                    d.Parent           = dotsLayer

                    local nl = Instance.new('TextLabel')
                    nl.Size               = UDim2.new(0, 60, 0, 11)
                    nl.AnchorPoint        = Vector2.new(0.5, 1)
                    nl.BackgroundTransparency = 1
                    nl.Text               = p.Name
                    nl.TextColor3         = Color3.fromRGB(220, 60, 60)
                    nl.Font               = Enum.Font.Gotham
                    nl.TextSize           = 8
                    nl.ZIndex             = 33
                    nl.Parent             = dotsLayer

                    entry         = {dot = d, lbl = nl}
                    mapPlrDots[p] = entry
                end

                local px2, py2 = worldToCanvas(pHRP.Position.X, pHRP.Position.Z)
                entry.dot.Position = UDim2.new(0, px2, 0, py2)
                entry.lbl.Position = UDim2.new(0, px2, 0, py2 - 4)
            end
        end
    end
    for p, entry in pairs(mapPlrDots) do
        if not alive[p] then
            entry.dot:Destroy()
            entry.lbl:Destroy()
            mapPlrDots[p] = nil
        end
    end

    -- waypoints
    for _, wp in pairs(mapWPs) do
        if not wp.active then continue end
        local wx2, wy2 = worldToCanvas(wp.x, wp.z)
        local dist     = math.floor((Vector3.new(wp.x, hrp.Position.Y, wp.z) - hrp.Position).Magnitude)
        wp.dot.Position       = UDim2.new(0, wx2, 0, wy2)
        wp.distLbl.Position   = UDim2.new(0, wx2, 0, wy2 + 7)
        wp.distLbl.Text       = dist .. 'm'
        wp.removeBtn.Position = UDim2.new(0, wx2 - 1, 0, wy2 - 1)
        wp.travelBtn.Position = UDim2.new(0, wx2 + 2, 0, wy2 - 1)
        if wp.bbDist then
            wp.bbDist.Text = dist .. 'm'
        end
    end
end)

-- scan once the first time the minimap is turned on (never auto-rescans after)
Toggles.MinimapToggle:OnChanged(function()
    if Toggles.MinimapToggle.Value and not scanDone then
        task.spawn(runTerrainScan)
    end
end)

-- ============================================================
-- CLEANUP (deduplication guard)
-- called by the NEXT script load to cleanly tear down this instance
-- ============================================================
_G.SMCleanup = function()
    -- stop any active fling loops
    _G.FlingStop = true

    -- restore optimizer state (lighting, particles, players) before disconnecting conn
    if _G.OptimizerCleanup    then pcall(_G.OptimizerCleanup);    _G.OptimizerCleanup    = nil end
    if _G.AeroOverlayCleanup  then pcall(_G.AeroOverlayCleanup);  _G.AeroOverlayCleanup  = nil end

    -- disconnect all RunService connections
    for _, key in ipairs({'SpeedConn', 'SpeedConnStep', 'BrakeConn', 'TurnConn', 'AnimConn', 'HitboxConn',
                          'HidePlayersConn', 'HidePlayersJoinConn', 'HidePlayersLeaveConn',
                          'WheelieConn', 'WheelieVConn', 'WheelieLocConn',
                          'StoppieConn', 'CruiseConn',
                          'NoWobbleConn', 'NoWobbleKeyConn',
                          'AntiAdminConn', 'OptimizerConn',
                          'FlyConn', 'AntiFallConn',
                          'RainbowConn',
                          'AdminESPConn', 'BikeESPConn', 'SpeedTagConn', 'SpeedTagLeaveConn',
                          'PlayerESPConn', 'PlayerESPCharConn',
                          'JumpKeyConn',
                          'FreecamConn', 'FreecamKeyConn', 'LockCharConn',
                          'StickyConn', 'LockSteeringConn',
                          'MenuToggleConn',
                          'AutoFixScanConn', 'AutoFixSeatConn', 'AutoFixCharConn'}) do
        if _G[key] then
            pcall(function() _G[key]:Disconnect() end)
            _G[key] = nil
        end
    end

    -- restore camera + mouse from freecam if it was active on reload
    pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
    pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.Default end)
    -- restore character movement if Lock Character was active on reload
    pcall(function()
        local CAS = game:GetService('ContextActionService')
        CAS:UnbindAction('KonstantLockChar')
        CAS:UnbindAction('KonstantLockCharKeys')
    end)
    pcall(function()
        local char = plr.Character
        local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
        if hum then hum.AutoRotate = true end
    end)

    -- restore world gravity
    pcall(function() workspace.Gravity = 196.2 end)

    -- destroy all in-world waypoint beams
    for _, wp in pairs(mapWPs) do
        pcall(function() if wp.beamPart then wp.beamPart:Destroy() end end)
        pcall(function() if wp.topPart  then wp.topPart:Destroy()  end end)
    end

    -- destroy all custom-loaded map models and wipe their terrain
    for _, entry in ipairs(loadedMaps) do
        pcall(function() clearMapEntry(entry) end)
    end

    -- clear hitbox selection boxes
    pcall(clearHitboxes)

    -- cleanup ESP overlays
    pcall(clearAdminESP)
    pcall(clearBikeESP)
    pcall(clearSpeedTags)
    pcall(clearPlayerESP)

    -- destroy cloned bikes
    for _, b in ipairs(clonedBikes) do pcall(function() b:Destroy() end) end
    clonedBikes = {}

    -- unfreeze bike if still frozen
    if _G.FrozenBikeParts then
        for p in pairs(_G.FrozenBikeParts) do
            pcall(function() p.Anchored = false end)
        end
        _G.FrozenBikeParts = nil
    end

    -- clear part picker in-game SelectionBoxes before destroying the GUI
    pcall(function() if _G.PPCleanup then _G.PPCleanup(); _G.PPCleanup = nil end end)

    -- destroy ScreenGuis this script owns
    pcall(function() gui:Destroy() end)
    pcall(function() minimapGui:Destroy() end)
    pcall(function() if bikeCustGui   then bikeCustGui:Destroy()   end end)
    pcall(function() if partPickerGui then partPickerGui:Destroy() end end)

    -- destroy LinoriaLib window
    pcall(function() Library.ScreenGui:Destroy() end)
end

-- ============================================================
-- CUSTOM OVERLAY (bottom-right speedometer)
-- 20-segment bar + big lerped digit + peak marker; color scales
-- with the speed ratio (cyan -> mint -> yellow -> orange -> red).
-- Wired to the Main / Visual "Custom Overlay" toggle via
-- _G.AeroOverlaySetEnabled(bool).
-- ============================================================
do
    local overlayGui = Instance.new('ScreenGui')
    overlayGui.Name           = 'AeroSpeedOverlay'
    overlayGui.ResetOnSpawn   = false
    overlayGui.IgnoreGuiInset = true
    overlayGui.DisplayOrder   = 900
    overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    overlayGui.Enabled        = false
    safeParentGui(overlayGui)

    -- outer container, bottom-right with 24px margin
    local root = Instance.new('Frame')
    root.Name              = 'Root'
    root.Size              = UDim2.new(0, 260, 0, 128)
    root.AnchorPoint       = Vector2.new(1, 1)
    root.Position          = UDim2.new(1, -24, 1, -24)
    root.BackgroundColor3  = Color3.fromRGB(12, 12, 16)
    root.BackgroundTransparency = 0.12
    root.BorderSizePixel   = 0
    root.Parent            = overlayGui
    local rootStroke = Instance.new('UIStroke')
    rootStroke.Color        = Color3.fromRGB(60, 60, 70)
    rootStroke.Thickness    = 1
    rootStroke.Transparency = 0.2
    rootStroke.Parent       = root

    -- top accent bar (2px, color shifts with speed)
    local accentBar = Instance.new('Frame')
    accentBar.Name             = 'AccentBar'
    accentBar.Size             = UDim2.new(1, 0, 0, 2)
    accentBar.Position         = UDim2.new(0, 0, 0, 0)
    accentBar.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
    accentBar.BorderSizePixel  = 0
    accentBar.Parent           = root

    -- top row: SPEED label (left), PEAK indicator (right)
    local topRow = Instance.new('Frame')
    topRow.Size                 = UDim2.new(1, -20, 0, 18)
    topRow.Position             = UDim2.new(0, 10, 0, 8)
    topRow.BackgroundTransparency = 1
    topRow.Parent               = root

    local speedLbl = Instance.new('TextLabel')
    speedLbl.Size                   = UDim2.new(0, 120, 1, 0)
    speedLbl.BackgroundTransparency = 1
    speedLbl.Text                   = 'SPEED'
    speedLbl.TextColor3             = Color3.fromRGB(140, 140, 150)
    speedLbl.Font                   = Enum.Font.Code
    speedLbl.TextSize               = 11
    speedLbl.TextXAlignment         = Enum.TextXAlignment.Left
    speedLbl.Parent                 = topRow

    local peakLbl = Instance.new('TextLabel')
    peakLbl.Size                   = UDim2.new(1, -120, 1, 0)
    peakLbl.Position               = UDim2.new(0, 120, 0, 0)
    peakLbl.BackgroundTransparency = 1
    peakLbl.Text                   = 'PEAK 0'
    peakLbl.TextColor3             = Color3.fromRGB(120, 120, 130)
    peakLbl.Font                   = Enum.Font.Code
    peakLbl.TextSize               = 11
    peakLbl.TextXAlignment         = Enum.TextXAlignment.Right
    peakLbl.Parent                 = topRow

    -- big lerped MPH number, centered
    local numLbl = Instance.new('TextLabel')
    numLbl.Size                    = UDim2.new(1, -20, 0, 54)
    numLbl.Position                = UDim2.new(0, 10, 0, 28)
    numLbl.BackgroundTransparency  = 1
    numLbl.Text                    = '0'
    numLbl.TextColor3              = Color3.fromRGB(230, 230, 240)
    numLbl.Font                    = Enum.Font.GothamBold
    numLbl.TextSize                = 46
    numLbl.TextScaled              = false
    numLbl.TextStrokeTransparency  = 0.5
    numLbl.TextStrokeColor3        = Color3.fromRGB(0, 200, 255)
    numLbl.Parent                  = root

    -- segment bar (20 pieces, ~11px wide with 1px gaps)
    local segBar = Instance.new('Frame')
    segBar.Size                 = UDim2.new(1, -20, 0, 8)
    segBar.Position             = UDim2.new(0, 10, 0, 88)
    segBar.BackgroundTransparency = 1
    segBar.Parent               = root

    local NUM_SEGS = 20
    local segs = {}
    for i = 1, NUM_SEGS do
        local s = Instance.new('Frame')
        s.Size = UDim2.new(1 / NUM_SEGS, -2, 1, 0)
        s.Position = UDim2.new((i - 1) / NUM_SEGS, 1, 0, 0)
        s.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
        s.BorderSizePixel  = 0
        s.Parent = segBar
        segs[i] = s
    end

    -- peak marker (thin vertical line over segment bar)
    local peakTick = Instance.new('Frame')
    peakTick.Size                = UDim2.new(0, 2, 1, 6)
    peakTick.Position            = UDim2.new(0, 0, 0, -3)
    peakTick.AnchorPoint         = Vector2.new(0.5, 0)
    peakTick.BackgroundColor3    = Color3.fromRGB(255, 255, 255)
    peakTick.BackgroundTransparency = 0.35
    peakTick.BorderSizePixel     = 0
    peakTick.Visible             = false
    peakTick.Parent              = segBar

    -- unit label under the bar
    local unitLbl = Instance.new('TextLabel')
    unitLbl.Size                   = UDim2.new(1, 0, 0, 16)
    unitLbl.Position               = UDim2.new(0, 0, 0, 104)
    unitLbl.BackgroundTransparency = 1
    unitLbl.Text                   = 'MPH'
    unitLbl.TextColor3             = Color3.fromRGB(160, 160, 170)
    unitLbl.Font                   = Enum.Font.Code
    unitLbl.TextSize               = 11
    unitLbl.Parent                 = root

    -- color scale: takes speed ratio (0..1+) and returns a Color3
    local function speedColor(r)
        r = math.clamp(r, 0, 1.2)
        -- 5-stop gradient: cyan -> mint -> yellow -> orange -> red
        local stops = {
            { 0.00, Color3.fromRGB(  0, 200, 255) },
            { 0.30, Color3.fromRGB(100, 220, 100) },
            { 0.55, Color3.fromRGB(255, 210,  60) },
            { 0.80, Color3.fromRGB(255, 130,  50) },
            { 1.00, Color3.fromRGB(255,  60,  60) },
        }
        for i = 1, #stops - 1 do
            local a, b = stops[i], stops[i + 1]
            if r >= a[1] and r <= b[1] then
                local t = (r - a[1]) / (b[1] - a[1])
                return a[2]:Lerp(b[2], t)
            end
        end
        return stops[#stops][2]
    end

    -- lerped display state
    local displayed = 0
    local peakMph   = 0
    local overlayConn

    local function overlayTick(dt)
        if not overlayGui.Enabled then return end
        -- speed source: prefer seat's assembly (vehicle), fall back to HRP
        local char = plr.Character
        local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
        local seat = hum and hum.SeatPart
        local ref
        if seat and isVehicleSeat(seat) then
            ref = seat.AssemblyRootPart or seat
        else
            ref = char and char:FindFirstChild('HumanoidRootPart')
        end
        if not ref or not ref.Parent then return end

        local actual = ref.AssemblyLinearVelocity.Magnitude * STUDS_TO_MPH
        -- smooth follow, snap when big jump (>60 mph delta) to avoid drag
        if math.abs(actual - displayed) > 60 then
            displayed = actual
        else
            displayed = displayed + (actual - displayed) * math.min(1, dt * 8)
        end
        if actual > peakMph then peakMph = actual end

        -- speed ratio: capped scale of 180 mph as "full bar"; over 180 tips
        -- the color into deep red and the bar caps out visually.
        local MAX_SCALE = 180
        local ratio = displayed / MAX_SCALE
        local col   = speedColor(ratio)

        numLbl.Text             = tostring(math.floor(displayed + 0.5))
        numLbl.TextColor3       = col
        numLbl.TextStrokeColor3 = col
        peakLbl.Text            = 'PEAK ' .. tostring(math.floor(peakMph + 0.5))
        accentBar.BackgroundColor3 = col
        rootStroke.Color        = col:Lerp(Color3.fromRGB(60, 60, 70), 0.55)

        -- light up segments proportional to ratio
        local filled = math.clamp(math.floor(ratio * NUM_SEGS + 0.5), 0, NUM_SEGS)
        for i = 1, NUM_SEGS do
            if i <= filled then
                -- gradient across the lit region (dimmer at low, brighter at cap)
                local segRatio = (i - 1) / (NUM_SEGS - 1)
                segs[i].BackgroundColor3 = speedColor(segRatio)
            else
                segs[i].BackgroundColor3 = Color3.fromRGB(35, 35, 40)
            end
        end

        -- peak tick position (relative to bar, clamped)
        if peakMph > 0 then
            local pRatio = math.clamp(peakMph / MAX_SCALE, 0, 1)
            peakTick.Visible  = true
            peakTick.Position = UDim2.new(pRatio, 0, 0, -3)
        else
            peakTick.Visible = false
        end
    end

    _G.AeroOverlaySetEnabled = function(on)
        overlayGui.Enabled = on and true or false
        if on then
            if not overlayConn then
                overlayConn = RunService.RenderStepped:Connect(overlayTick)
            end
            peakMph   = 0  -- reset peak each time you enable it
            displayed = 0
        else
            if overlayConn then overlayConn:Disconnect(); overlayConn = nil end
        end
    end

    -- register for SMCleanup
    _G.AeroOverlayCleanup = function()
        if overlayConn then overlayConn:Disconnect(); overlayConn = nil end
        pcall(function() overlayGui:Destroy() end)
    end
end

-- ============================================================
-- SETTINGS TAB (SaveManager + ThemeManager)
-- Must come AFTER all Toggles/Options are registered
-- ============================================================
local SettingsRight = Tabs.Settings:AddRightGroupbox('Theme')

if SaveManager then
    pcall(function()
        SaveManager:SetLibrary(Library)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetFolder('Konstant')
        SaveManager:BuildConfigSection(Tabs.Settings)
    end)
else
    warn('Konstant: skipping SaveManager section (failed to load)')
end

if ThemeManager then
    pcall(function()
        ThemeManager:SetLibrary(Library)
        ThemeManager:SetFolder('Konstant')
        ThemeManager:ApplyToGroupbox(SettingsRight)
    end)
else
    warn('Konstant: skipping ThemeManager section (failed to load)')
end

-- Load autoload config after a short delay so all game systems finish initializing
-- before toggle callbacks fire (loading immediately breaks the game on join)
task.delay(3, function()
    if SaveManager then pcall(function() SaveManager:LoadAutoloadConfig() end) end
end)
