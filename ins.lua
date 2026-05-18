local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local plr = Players.LocalPlayer

-- deduplication guard: if a previous instance is running, clean it up first
if _G.SMCleanup then
    pcall(_G.SMCleanup)
    _G.SMCleanup = nil
end

local playSuccess -- defined after gui is created below
local showToast   -- defined after gui is created below
local minimapGui  -- defined after gui is created below

local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

local Window = Library:CreateWindow({
    Title = 'Konstant',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Main     = Window:AddTab('Main'),
    Troll    = Window:AddTab('Troll'),
    Rideout  = Window:AddTab('Rideout'),
    Maps     = Window:AddTab('Maps'),
    ESP      = Window:AddTab('ESP'),
    Settings = Window:AddTab('Settings')
}

local Left     = Tabs.Main:AddLeftGroupbox('Money')
local BikeLeft = Tabs.Main:AddLeftGroupbox('Bikes')
local Right    = Tabs.Main:AddRightGroupbox('Mods')

Left:AddInput('Amount', {
    Default = '10000',
    Numeric = true,
    Finished = false,
    Text = 'Amount',
})

Left:AddDivider()

Left:AddButton({
    Text = 'Add Money',
    Func = function()
        local amount = math.abs(tonumber(Options.Amount.Value) or 0)
        RS.Remotes.PurchaseBike:FireServer('EBOX V2', {
            ['Name'] = 'EBOX V2', ['Robux'] = false,
            ['Speed'] = 40, ['Kind'] = 'E-BIKE',
            ['ProductID'] = 3585359520, ['Price'] = -amount
        })
        playSuccess()
    end
})

Left:AddButton({
    Text = 'Subtract Money',
    Func = function()
        local amount = math.abs(tonumber(Options.Amount.Value) or 0)
        RS.Remotes.PurchaseBike:FireServer('EBOX V2', {
            ['Name'] = 'EBOX V2', ['Robux'] = false,
            ['Speed'] = 40, ['Kind'] = 'E-BIKE',
            ['ProductID'] = 3585359520, ['Price'] = amount
        })
        playSuccess()
    end
})

Left:AddDivider()

Left:AddToggle('AntiAdmin', {
    Text = 'Anti-Admin',
    Default = false,
    Callback = function(val)
        if val then
            local TS       = game:GetService("TeleportService")
            local Players  = game:GetService("Players")
            local adminIDs = {781611480, 3455747658, 609001673, 2682265042}

            local warnSfx = Instance.new("Sound")
            warnSfx.SoundId = "rbxassetid://138956818415312"
            warnSfx.Volume = 2
            warnSfx.Parent = gui

            _G.AntiAdminConn = Players.PlayerAdded:Connect(function(p)
                if not Toggles.AntiAdmin.Value then return end
                for _, id in ipairs(adminIDs) do
                    if p.UserId == id then
                        showToast("Admin detected: " .. p.Name .. " — hopping")
                        warnSfx:Play()
                        task.wait(2)
                        TS:Teleport(game.PlaceId)
                        return
                    end
                end
            end)
        else
            if _G.AntiAdminConn then
                _G.AntiAdminConn:Disconnect()
                _G.AntiAdminConn = nil
            end
        end
    end
})

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

Left:AddDivider()

Left:AddToggle('StreamOptimizer', {
    Text = 'Stream Optimizer',
    Default = false,
    Callback = function(val)
        if val then
            local RS2 = game:GetService('RunService')

            -- carpet-bomb the entire map with a dense grid.
            -- 200-stud step across ±4000 on X and Z = 41*41 = 1681 points.
            -- fired in batches of 10 per Heartbeat to avoid a single-frame spike.
            -- forces the streaming engine to load every chunk immediately
            -- instead of waiting for the player to physically approach each area.
            local GRID_MIN  = -4000
            local GRID_MAX  =  4000
            local GRID_STEP =  200
            local BATCH     =  10   -- requests per frame

            local points = {}
            local Y = 50  -- mid-height so request covers both terrain and buildings
            for x = GRID_MIN, GRID_MAX, GRID_STEP do
                for z = GRID_MIN, GRID_MAX, GRID_STEP do
                    table.insert(points, Vector3.new(x, Y, z))
                end
            end

            -- shuffle so loading fans out across the map evenly
            for i = #points, 2, -1 do
                local j = math.random(i)
                points[i], points[j] = points[j], points[i]
            end

            local idx          = 0
            local lastPct      = -1

            showToast('Stream Optimizer ON — loading ' .. #points .. ' chunks...')

            _G.OptimizerConn = RS2.Heartbeat:Connect(function()
                if idx >= #points then
                    -- all chunks done; light pulse to keep the player's current
                    -- area resident in case they move to the edge of the map
                    local c    = plr.Character
                    local hrp2 = c and c:FindFirstChild('HumanoidRootPart')
                    if hrp2 then
                        pcall(function()
                            workspace:RequestStreamAroundAsync(hrp2.Position, 3)
                        end)
                    end
                    return
                end

                -- fire BATCH points this frame
                local batchEnd = math.min(idx + BATCH, #points)
                for i = idx + 1, batchEnd do
                    local pos = points[i]
                    task.spawn(function()
                        pcall(function()
                            workspace:RequestStreamAroundAsync(pos, 3)
                        end)
                    end)
                end
                idx = batchEnd

                -- toast progress every 10% so you can see it working
                local pct = math.floor(idx / #points * 10) * 10
                if pct ~= lastPct then
                    lastPct = pct
                    if pct < 100 then
                        showToast('Loading... ' .. pct .. '%')
                    else
                        showToast('Map fully loaded!')
                    end
                end
            end)
        else
            if _G.OptimizerConn then
                _G.OptimizerConn:Disconnect()
                _G.OptimizerConn = nil
            end
            showToast('Stream Optimizer OFF')
        end
    end
})

BikeLeft:AddButton({
    Text = 'Get All Bikes',
    Func = function()
        local bikes = RS.Bikes:GetChildren()
        local count = 0
        for _, bike in ipairs(bikes) do
            if bike:IsA('Model') then
                RS.Remotes.PurchaseBike:FireServer(bike.Name, {
                    ['Name'] = bike.Name, ['Robux'] = false,
                    ['Speed'] = 40, ['Kind'] = 'E-BIKE',
                    ['ProductID'] = 3585359520, ['Price'] = 0
                })
                count += 1
                task.wait(0.1)
            end
        end
        playSuccess()
        showToast('Got all ' .. count .. ' bikes.')
    end
})

BikeLeft:AddButton({
    Text = 'Sell All Bikes',
    Func = function()
        local bikes = RS.Bikes:GetChildren()
        local count = 0
        for _, bike in ipairs(bikes) do
            if bike:IsA('Model') then
                RS.Remotes.SellBike:FireServer(bike.Name)
                count += 1
                task.wait(0.1)
            end
        end
        playSuccess()
        showToast('Sold all ' .. count .. ' bikes.')
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

BikeLeft:AddButton({
    Text = 'Unpatch Bike',
    Func = function()
        if _G.SpeedConn then
            _G.SpeedConn:Disconnect()
            _G.SpeedConn = nil
            showToast('Unpatched')
        else
            showToast('Nothing to unpatch')
        end
    end
})

BikeLeft:AddButton({
    Text = 'Patch Bike',
    Func = function()
        local RS2  = game:GetService('RunService')
        local char = plr.Character

        local seat
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA('VehicleSeat') and v.Occupant
            and v.Occupant.Parent == char then
                seat = v
                break
            end
        end

        if not seat then
            showToast('Get in a bike first')
            return
        end

        if _G.SpeedConn then
            _G.SpeedConn:Disconnect()
            _G.SpeedConn = nil
        end

        local root     = seat.Parent:FindFirstChildWhichIsA('BasePart')
        local mph      = tonumber(Options.SpeedInput.Value) or 60
        local accelMph = tonumber(Options.AccelInput.Value) or 37
        local maxSpeed = mph * 1.6       -- studs/s
        local accel    = accelMph * 1.6  -- studs/s²

        _G.SpeedConn = RS2.Heartbeat:Connect(function(dt)
            if not UIS:IsKeyDown(Enum.KeyCode.W) then return end
            if not root or not root.Parent then
                _G.SpeedConn:Disconnect()
                _G.SpeedConn = nil
                return
            end
            local vel     = root.AssemblyLinearVelocity
            local flatVel = Vector3.new(vel.X, 0, vel.Z)
            if flatVel.Magnitude < maxSpeed then
                local fwd     = root.CFrame.LookVector
                local flatFwd = Vector3.new(fwd.X, 0, fwd.Z).Unit
                root.AssemblyLinearVelocity = Vector3.new(
                    vel.X + flatFwd.X * dt * accel,
                    vel.Y,
                    vel.Z + flatFwd.Z * dt * accel
                )
            end
        end)

        playSuccess()
        showToast('Patched — ' .. mph .. ' mph @ ' .. accelMph .. ' mph/s')
    end
})

BikeLeft:AddDivider()

BikeLeft:AddToggle('SpawnerToggle', {
    Text = 'Toggle Spawner',
    Default = false,
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

BikeLeft:AddInput('GravityInput', {
    Default = '196.2',
    Numeric = true,
    Finished = false,
    Text = 'Gravity (default 196.2)',
})

BikeLeft:AddToggle('CustomGravity', {
    Text = 'Custom Gravity',
    Default = false,
    Callback = function(val)
        if val then
            _G.OriginalGravity = workspace.Gravity  -- save game's actual default
            local g = tonumber(Options.GravityInput.Value) or _G.OriginalGravity
            workspace.Gravity = g
            showToast('Gravity: ' .. g .. '  (was ' .. _G.OriginalGravity .. ')')
        else
            workspace.Gravity = _G.OriginalGravity or 196.2
            showToast('Gravity restored to ' .. workspace.Gravity)
        end
    end
})

BikeLeft:AddDivider()

BikeLeft:AddInput('BrakeInput', {
    Default = '120',
    Numeric = true,
    Finished = false,
    Text = 'Brake Force (mph/s)',
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
            if v:IsA('VehicleSeat') and v.Occupant
            and v.Occupant.Parent == char then
                seat = v
                break
            end
        end

        if not seat then
            showToast('Get in a bike first')
            return
        end

        if _G.BrakeConn then
            _G.BrakeConn:Disconnect()
            _G.BrakeConn = nil
        end

        local root       = seat.Parent:FindFirstChildWhichIsA('BasePart')
        local brakeMph   = tonumber(Options.BrakeInput.Value) or 120
        local brakeDecel = brakeMph * 1.6  -- studs/s²

        _G.BrakeConn = RS2.Heartbeat:Connect(function(dt)
            if not UIS:IsKeyDown(Enum.KeyCode.S) then return end
            if not root or not root.Parent then
                _G.BrakeConn:Disconnect()
                _G.BrakeConn = nil
                return
            end
            local vel     = root.AssemblyLinearVelocity
            local flatVel = Vector3.new(vel.X, 0, vel.Z)
            local mag     = flatVel.Magnitude
            if mag > 0.1 then
                local reduction = math.min(mag, brakeDecel * dt)
                local newFlat   = flatVel - flatVel.Unit * reduction
                root.AssemblyLinearVelocity = Vector3.new(newFlat.X, vel.Y, newFlat.Z)
            else
                root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
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
            if v:IsA('VehicleSeat') and v.Occupant
            and v.Occupant.Parent == char then
                seat = v
                break
            end
        end

        if not seat then
            showToast('Get in a bike first')
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

BikeLeft:AddInput('AnimSpeedInput', {
    Default = '1.0',
    Numeric = true,
    Finished = false,
    Text = 'Anim Speed (multiplier)',
})

BikeLeft:AddInput('AnimFadeInput', {
    Default = '0.3',
    Numeric = true,
    Finished = false,
    Text = 'Anim Transition (seconds)',
})

BikeLeft:AddToggle('AnimTweaks', {
    Text = 'Anim Tweaks (bike only)',
    Default = false,
    Callback = function(val)
        if val then
            local RS2 = game:GetService('RunService')

            -- O(1) bike check: Humanoid.SeatPart returns the seat or nil
            local function onBike()
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return false, nil end
                local seat = hum.SeatPart
                return seat and seat:IsA('VehicleSeat'), hum
            end

            -- hook __namecall to intercept AnimationTrack:Play and
            -- inject our custom fadeTime + speed so every animation
            -- that the game plays while on a bike gets smooth transitions.
            local mt    = getrawmetatable(game)
            local oldNC = mt.__namecall
            setreadonly(mt, false)
            mt.__namecall = newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if method == 'Play' then
                    local ok2, isAnim = pcall(function()
                        return typeof(self) == 'Instance' and self:IsA('AnimationTrack')
                    end)
                    if ok2 and isAnim then
                        local riding = onBike()
                        if riding then
                            local fade  = tonumber(Options.AnimFadeInput.Value)  or 0.3
                            local speed = tonumber(Options.AnimSpeedInput.Value) or 1.0
                            -- Play(fadeTime, weight, speed)
                            return oldNC(self, fade, 1, speed)
                        end
                    end
                end
                return oldNC(self, ...)
            end)
            setreadonly(mt, true)
            _G.AnimNCHook = oldNC
            _G.AnimMT     = mt

            -- heartbeat: AdjustSpeed on already-playing tracks so
            -- the multiplier applies even to animations that started
            -- before the toggle was enabled. runs every 30 frames (~0.5s).
            local tick = 0
            _G.AnimConn = RS2.Heartbeat:Connect(function()
                tick += 1
                if tick < 30 then return end
                tick = 0

                local riding, hum = onBike()
                if not riding or not hum then return end

                local animator = hum:FindFirstChildWhichIsA('Animator')
                if not animator then return end

                local speed = tonumber(Options.AnimSpeedInput.Value) or 1.0
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    pcall(function() track:AdjustSpeed(speed) end)
                end
            end)

            showToast('Anim tweaks ON')
        else
            -- disconnect speed scanner
            if _G.AnimConn then
                _G.AnimConn:Disconnect()
                _G.AnimConn = nil
            end

            -- restore original __namecall
            if _G.AnimMT and _G.AnimNCHook then
                pcall(function()
                    setreadonly(_G.AnimMT, false)
                    _G.AnimMT.__namecall = _G.AnimNCHook
                    setreadonly(_G.AnimMT, true)
                end)
                _G.AnimNCHook = nil
                _G.AnimMT     = nil
            end

            -- reset all currently playing tracks back to 1x speed
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

BikeLeft:AddToggle('HitboxViewer', {
    Text = 'Hitbox Viewer',
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

-- trail settings shared between the toggle and the settings panel
local trailSettings = {
    startR = 255, startG = 215, startB = 0,
    endR   = 200, endG   = 100, endB   = 0,
    lifetime      = 0.6,
    halfWidth     = 0.5,
    textureId     = '',
    lightEmission = 0.5,
    rainbow       = false,
}
local trailGui    = nil  -- assigned when trail panel is built below
local bikeCustGui = nil  -- assigned when bike customization panel is built below

Right:AddDivider()

-- ---- Freeze Bike -------------------------------------------------------
Right:AddToggle('FreezeBike', {
    Text = 'Freeze Bike',
    Default = false,
    Callback = function(val)
        if val then
            local bikeModel = getBikeRoot()
            if not bikeModel then
                showToast('Get on a bike first')
                Toggles.FreezeBike:SetValue(false)
                return
            end
            _G.FrozenBikeParts = {}
            for _, p in ipairs(bikeModel:GetDescendants()) do
                if p:IsA('BasePart') then
                    _G.FrozenBikeParts[p] = p.AssemblyLinearVelocity
                    p.Anchored = true
                end
            end
            showToast('Bike frozen')
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
            showToast('Bike unfrozen')
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
            local RS2 = game:GetService('RunService')
            local flyRoot = nil
            _G.FlyConn = RS2.Heartbeat:Connect(function()
                local _, r = getBikeRoot()
                if r then flyRoot = r end
                if not flyRoot or not flyRoot.Parent then return end
                local cam   = workspace.CurrentCamera
                local speed = (tonumber(Options.FlySpeedInput.Value) or 60) * 1.6
                local fwd   = cam.CFrame.LookVector
                local right = cam.CFrame.RightVector
                local dir   = Vector3.new(0, 0, 0)
                if UIS:IsKeyDown(Enum.KeyCode.W)         then dir = dir + fwd                end
                if UIS:IsKeyDown(Enum.KeyCode.S)         then dir = dir - fwd                end
                if UIS:IsKeyDown(Enum.KeyCode.A)         then dir = dir - right              end
                if UIS:IsKeyDown(Enum.KeyCode.D)         then dir = dir + right              end
                if UIS:IsKeyDown(Enum.KeyCode.E)         then dir = dir + Vector3.new(0,1,0) end
                if UIS:IsKeyDown(Enum.KeyCode.Q)         then dir = dir - Vector3.new(0,1,0) end
                if dir.Magnitude > 0.01 then
                    flyRoot.AssemblyLinearVelocity = dir.Unit * speed
                else
                    local vel = flyRoot.AssemblyLinearVelocity
                    flyRoot.AssemblyLinearVelocity = Vector3.new(vel.X * 0.8, 0, vel.Z * 0.8)
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
    Text = 'Anti-Fall  (WHEELIE IS BROKEN)',
    Default = false,
    Callback = function(val)
        if val then
            local RS2 = game:GetService('RunService')
            local afRoot = nil
            _G.AntiFallConn = RS2.Heartbeat:Connect(function()
                afRoot = cachedRoot(afRoot)
                if not afRoot then return end
                local cf  = afRoot.CFrame
                local lv  = cf.LookVector
                local yaw = math.atan2(-lv.X, -lv.Z)
                afRoot.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, yaw, 0)
            end)
            showToast('Anti-Fall ON  (wheelies disabled)')
        else
            if _G.AntiFallConn then _G.AntiFallConn:Disconnect(); _G.AntiFallConn = nil end
            showToast('Anti-Fall OFF')
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

local _lastJump = 0
_G.JumpKeyConn = UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local keyStr = (Options.JumpKeyInput and Options.JumpKeyInput.Value or 'G'):upper():gsub('%s+', '')
    local ok, kc = pcall(function() return Enum.KeyCode[keyStr] end)
    if not ok or kc == nil then return end
    if inp.KeyCode ~= kc then return end
    local now = tick()
    if now - _lastJump < 0.3 then return end
    _lastJump = now
    local _, bikeRoot = getBikeRoot()
    if not bikeRoot then return end
    local force = tonumber(Options.JumpForceInput.Value) or 80
    local vel   = bikeRoot.AssemblyLinearVelocity
    bikeRoot.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y + force, vel.Z)
end)

Right:AddDivider()

-- ---- Air Control -------------------------------------------------------
Right:AddInput('AirControlInput', {
    Default = '40',
    Numeric = true,
    Finished = false,
    Text = 'Air Control Force',
})

Right:AddToggle('AirControl', {
    Text = 'Air Control (A/D mid-air)',
    Default = false,
    Callback = function(val)
        if val then
            local RS2 = game:GetService('RunService')
            local airRoot = nil
            _G.AirConn = RS2.Heartbeat:Connect(function(dt)
                airRoot = cachedRoot(airRoot)
                if not airRoot then return end
                local aDown = UIS:IsKeyDown(Enum.KeyCode.A)
                local dDown = UIS:IsKeyDown(Enum.KeyCode.D)
                if not aDown and not dDown then return end
                local hit = workspace:Raycast(airRoot.Position, Vector3.new(0, -4, 0))
                if hit then return end
                local force    = tonumber(Options.AirControlInput.Value) or 40
                local rightVec = airRoot.CFrame.RightVector
                rightVec = Vector3.new(rightVec.X, 0, rightVec.Z)
                if rightVec.Magnitude < 0.01 then return end
                rightVec = rightVec.Unit
                local dir = aDown and -1 or 1
                airRoot.AssemblyLinearVelocity = airRoot.AssemblyLinearVelocity + rightVec * dir * force * dt
            end)
            showToast('Air Control ON')
        else
            if _G.AirConn then _G.AirConn:Disconnect(); _G.AirConn = nil end
            showToast('Air Control OFF')
        end
    end
})

Right:AddDivider()

-- ---- Rainbow Bike / Custom Color ---------------------------------------
Right:AddInput('RainbowSpeedInput', {
    Default = '0.4',
    Numeric = true,
    Finished = false,
    Text = 'Rainbow Speed',
})

Right:AddToggle('RainbowBike', {
    Text = 'Rainbow Bike',
    Default = false,
    Callback = function(val)
        if val then
            local RS2 = game:GetService('RunService')
            local hue = 0
            local rainbowRoot = nil
            _G.RainbowConn = RS2.Heartbeat:Connect(function(dt)
                rainbowRoot = cachedRoot(rainbowRoot)
                if not rainbowRoot then return end
                local bikeModel = rainbowRoot.Parent
                if not bikeModel then return end
                local speed = tonumber(Options.RainbowSpeedInput.Value) or 0.4
                hue = (hue + dt * speed) % 1
                local col = Color3.fromHSV(hue, 1, 1)
                for _, p in ipairs(bikeModel:GetDescendants()) do
                    if p:IsA('BasePart') then pcall(function() p.Color = col end) end
                end
            end)
            showToast('Rainbow ON')
        else
            if _G.RainbowConn then _G.RainbowConn:Disconnect(); _G.RainbowConn = nil end
            showToast('Rainbow OFF')
        end
    end
})

Right:AddDivider()

Right:AddButton({
    Text = 'Bike Customization',
    Func = function()
        if bikeCustGui then bikeCustGui.Enabled = not bikeCustGui.Enabled end
    end
})

Right:AddDivider()

-- ---- Bike Trail --------------------------------------------------------
Right:AddToggle('BikeTrail', {
    Text = 'Bike Trail',
    Default = false,
    Callback = function(val)
        if val then
            local _, bikeRoot = getBikeRoot()
            if not bikeRoot then showToast('Get on a bike first') return end
            pcall(function() if _G.TrailAttach0 then _G.TrailAttach0:Destroy() end end)
            pcall(function() if _G.TrailAttach1 then _G.TrailAttach1:Destroy() end end)
            pcall(function() if _G.ActiveTrail   then _G.ActiveTrail:Destroy()  end end)
            local hw = math.max(0.05, trailSettings.halfWidth)
            local a0 = Instance.new('Attachment')
            a0.Position = Vector3.new(0,  hw, 0)
            a0.Parent   = bikeRoot
            local a1 = Instance.new('Attachment')
            a1.Position = Vector3.new(0, -hw, 0)
            a1.Parent   = bikeRoot
            local trail = Instance.new('Trail')
            trail.Attachment0   = a0
            trail.Attachment1   = a1
            trail.Lifetime      = trailSettings.lifetime
            trail.MinLength     = 0
            trail.FaceCamera    = true
            trail.LightEmission = trailSettings.lightEmission
            trail.Texture       = trailSettings.textureId
            trail.Transparency  = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            })
            trail.Parent     = bikeRoot.Parent
            _G.TrailAttach0  = a0
            _G.TrailAttach1  = a1
            _G.ActiveTrail   = trail
            _G.TrailBikeRoot = bikeRoot
            local frameTick = 0
            local RS2 = game:GetService('RunService')
            _G.TrailColorConn = RS2.Heartbeat:Connect(function()
                frameTick += 1
                if frameTick < 3 then return end
                frameTick = 0
                if not _G.ActiveTrail or not _G.ActiveTrail.Parent then return end
                if trailSettings.rainbow or Toggles.RainbowBike.Value then
                    if _G.TrailBikeRoot and _G.TrailBikeRoot.Parent then
                        _G.ActiveTrail.Color = ColorSequence.new(_G.TrailBikeRoot.Color)
                    end
                else
                    local sc = Color3.fromRGB(trailSettings.startR, trailSettings.startG, trailSettings.startB)
                    local ec = Color3.fromRGB(trailSettings.endR,   trailSettings.endG,   trailSettings.endB)
                    _G.ActiveTrail.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, sc),
                        ColorSequenceKeypoint.new(1, ec),
                    })
                end
            end)
            showToast('Trail ON')
        else
            if _G.TrailColorConn then _G.TrailColorConn:Disconnect(); _G.TrailColorConn = nil end
            pcall(function() if _G.TrailAttach0 then _G.TrailAttach0:Destroy(); _G.TrailAttach0 = nil end end)
            pcall(function() if _G.TrailAttach1 then _G.TrailAttach1:Destroy(); _G.TrailAttach1 = nil end end)
            pcall(function() if _G.ActiveTrail   then _G.ActiveTrail:Destroy();  _G.ActiveTrail  = nil end end)
            _G.TrailBikeRoot = nil
            showToast('Trail OFF')
        end
    end
})

Right:AddButton({
    Text = 'Trail Settings',
    Func = function()
        if trailGui then trailGui.Enabled = not trailGui.Enabled end
    end
})


ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:SetFolder('BikeTool')
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

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
        psg.Parent         = plr:WaitForChild('PlayerGui')

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

-- in the target game the full UI is shown (Load by asset ID, Import, teleport buttons).
-- in any other game only Clone + Export are available: grab that game's map, save it to
-- your PC via the executor file system, then import it next time you're in the supermoto game.
local TARGET_GAME_ID = 74559235274954
local isTargetGame   = game.PlaceId == TARGET_GAME_ID

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

-- everything below this line is only built in the target game
if isTargetGame then

    MapLeft:AddDivider()

    MapLeft:AddInput('MapAssetId', {
        Default  = '',
        Numeric  = false,
        Finished = false,
        Text     = 'Asset ID  (or paste the full URL)',
    })

    MapLeft:AddButton({
        Text = 'Load Map',
        Func = function()
            local raw = Options.MapAssetId.Value
            if raw == '' then showToast('Enter an asset ID first') return end

            local assetId = raw:match('%d+')
            if not assetId then showToast('Could not read an ID from that') return end

            local slot = #loadedMaps + 1
            if slot > #MAP_SLOTS then
                showToast('Max 3 maps loaded - clear one first')
                return
            end

            showToast('Downloading map ' .. slot .. '  (' .. assetId .. ')...')
            task.spawn(function()
                local ok, objects = pcall(function()
                    return game:GetObjects('rbxassetid://' .. assetId)
                end)
                if not ok or not objects or #objects == 0 then
                    showToast('Load failed - check the ID')
                    return
                end

                local spawnX = MAP_SLOTS[slot].x
                local spawnZ = MAP_SLOTS[slot].z

                local loaded = 0
                for _, obj in ipairs(objects) do
                    if obj:IsA('Model') or obj:IsA('BasePart') then
                        pcall(function()
                            if obj:IsA('Model') then
                                local bbCF, bbSize = obj:GetBoundingBox()
                                local bottomY   = bbCF.Position.Y - bbSize.Y / 2
                                local pivotCF   = obj:GetPivot()
                                local newPivotY = pivotCF.Position.Y + (2 - bottomY)
                                obj:PivotTo(CFrame.new(spawnX, newPivotY, spawnZ))
                            else
                                obj.Position = Vector3.new(spawnX, obj.Size.Y / 2 + 2, spawnZ)
                            end
                        end)
                        obj.Parent = workspace

                        -- force every part to be anchored and collideable so the
                        -- client-side bike physics actually land on the map
                        for _, part in ipairs(obj:GetDescendants()) do
                            if part:IsA('BasePart') then
                                part.Anchored   = true
                                part.CanCollide = true
                            end
                        end
                        if obj:IsA('BasePart') then
                            obj.Anchored   = true
                            obj.CanCollide = true
                        end

                        local mapName = (obj.Name ~= '' and obj.Name) or ('Asset ' .. assetId)
                        table.insert(loadedMaps, {obj = obj, name = mapName, x = spawnX, z = spawnZ})
                        lastMapPos = Vector3.new(spawnX, 20, spawnZ)
                        loaded += 1
                    end
                end

                if loaded > 0 then
                    showToast('Loaded: ' .. loadedMaps[#loadedMaps].name .. ' (#' .. #loadedMaps .. ')')
                else
                    showToast('Model had no geometry to load')
                end
            end)
        end
    })

    MapLeft:AddDivider()

    MapLeft:AddButton({
        Text = 'Teleport to Last Map',
        Func = function()
            if #loadedMaps == 0 then showToast('No map loaded yet') return end
            teleportOntoMap(loadedMaps[#loadedMaps])
        end
    })

    MapLeft:AddDivider()

    -- import a file that was exported from another game session.
    -- the file lives in your executor's workspace folder under SuperMotoMaps/.
    MapLeft:AddInput('ImportFilename', {
        Default  = '',
        Numeric  = false,
        Finished = false,
        Text     = 'Import filename (without .json)',
    })

    MapLeft:AddButton({
        Text = 'Import from File',
        Func = function()
            if not PasswordGate.ask() then return end
            if type(readfile) ~= 'function' then
                showToast('Executor has no file-read support')
                return
            end
            local name = Options.ImportFilename.Value
            if name == '' then showToast('Enter a filename first') return end

            local slot = #loadedMaps + 1
            if slot > #MAP_SLOTS then
                showToast('Max 3 maps loaded - clear one first')
                return
            end

            local path = MAP_SAVE_FOLDER .. '/' .. name .. '.json'
            local ok, content = pcall(readfile, path)
            if not ok or not content or content == '' then
                showToast('File not found: ' .. name .. '.json')
                return
            end
            showToast('Importing...')
            task.spawn(function() importMap(content, slot) end)
        end
    })

    MapRight:AddButton({
        Text = 'Teleport to Map 1',
        Func = function()
            local entry = loadedMaps[1]
            if not entry then showToast('No maps loaded') return end
            teleportOntoMap(entry)
        end
    })

    MapRight:AddButton({
        Text = 'Teleport to Map 2',
        Func = function()
            local entry = loadedMaps[2]
            if not entry then showToast('Only ' .. #loadedMaps .. ' map(s) loaded') return end
            teleportOntoMap(entry)
        end
    })

    MapRight:AddButton({
        Text = 'Teleport to Map 3',
        Func = function()
            local entry = loadedMaps[3]
            if not entry then showToast('Only ' .. #loadedMaps .. ' map(s) loaded') return end
            teleportOntoMap(entry)
        end
    })

    MapRight:AddDivider()

end  -- isTargetGame

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
        if v:IsA('VehicleSeat') and v.Occupant and v.Occupant.Parent == char then
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

local RunService   = game:GetService('RunService')
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
        if v:IsA('VehicleSeat') and v.Occupant
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
        if v:IsA('VehicleSeat') and v.Occupant then
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

local TrollLeft  = Tabs.Troll:AddLeftGroupbox('Fling')
local TrollRight = Tabs.Troll:AddRightGroupbox('Target')

TrollRight:AddInput('FlingTarget', {
    Default = '',
    Numeric = false,
    Finished = false,
    Text = 'Username or display name',
})

TrollRight:AddButton({
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
-- ESP TAB
-- ============================================================

local ESPLeft = Tabs.ESP:AddLeftGroupbox('ESP')

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
        if not obj:IsA('VehicleSeat') then continue end
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
        lbl.Text                   = '[Bike] ' .. ownerName
        lbl.TextColor3             = Color3.fromRGB(255, 200, 0)
        lbl.Font                   = Enum.Font.Gotham
        lbl.TextSize               = 13
        lbl.TextStrokeTransparency = 0.5
        lbl.Parent                 = bill
        table.insert(bikeBoxMap, { box=box, bill=bill })
    end
end

ESPLeft:AddToggle('BikeESP', {
    Text = 'Bike ESP',
    Default = false,
    Callback = function(val)
        if val then
            refreshBikeESP()
            local timer = 0
            _G.BikeESPConn = game:GetService('RunService').Heartbeat:Connect(function()
                timer += 1
                if timer >= 60 then timer = 0; refreshBikeESP() end
            end)
            showToast('Bike ESP ON')
        else
            clearBikeESP()
            if _G.BikeESPConn then _G.BikeESPConn:Disconnect(); _G.BikeESPConn = nil end
            showToast('Bike ESP OFF')
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
                    local mph = math.floor(data.hrp.AssemblyLinearVelocity.Magnitude * 0.625 + 0.5)
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

-- ============================================================
-- RIDEOUT TAB
-- ============================================================

local RideoutLeft  = Tabs.Rideout:AddLeftGroupbox('Rideout')
local RideoutRight = Tabs.Rideout:AddRightGroupbox('Leader')

-- rideout state
local _rideoutActive    = false
local _rideoutLeader    = nil
local _leaderBox        = nil
local _leaderBill       = nil
local _rideoutHudGui    = nil
local _selfLeaderBox    = nil  -- yellow SelectionBox on own character (Claim Ownership)
local _ownershipActive  = false
local _ownershipHudGui  = nil  -- top-of-screen rider count banner

-- rideout waypoint state
local rideoutWPs      = {}
local nextRoWpId      = 1
local rideoutWpGui    = nil  -- list panel, assigned after tab buttons
local _addRoWpRow     = nil  -- forward declaration
local _reflowRoWpRows = nil  -- forward declaration

local function _parseXYZ(str)
    -- accepts:  "100, 50, 200"  or  "CFrame.new(100, 50, 200, ...)"
    local nums = {}
    for n in str:gmatch('%-?%d+%.?%d*') do
        table.insert(nums, tonumber(n))
        if #nums == 3 then break end
    end
    if #nums == 3 then return nums[1], nums[2], nums[3] end
    return nil
end

local function _makeRideoutWP(name, wx, wy, wz)
    local id = nextRoWpId
    nextRoWpId += 1

    local beamPart = Instance.new('Part')
    beamPart.Size         = Vector3.new(0.6, 500, 0.6)
    beamPart.CFrame       = CFrame.new(wx, wy + 250, wz)
    beamPart.Anchored     = true
    beamPart.CanCollide   = false
    beamPart.Material     = Enum.Material.Neon
    beamPart.Color        = Color3.fromRGB(50, 255, 80)
    beamPart.Transparency = 0.35
    beamPart.CastShadow   = false
    beamPart.Parent       = workspace

    local topPart = Instance.new('Part')
    topPart.Size        = Vector3.new(1, 1, 1)
    topPart.CFrame      = CFrame.new(wx, wy + 515, wz)
    topPart.Anchored    = true
    topPart.CanCollide  = false
    topPart.Transparency = 1
    topPart.Parent      = workspace

    local billboard = Instance.new('BillboardGui')
    billboard.Size        = UDim2.new(0, 280, 0, 80)
    billboard.AlwaysOnTop = false
    billboard.MaxDistance = 6000
    billboard.Parent      = topPart

    local bbName = Instance.new('TextLabel')
    bbName.Size                   = UDim2.new(1, 0, 0.6, 0)
    bbName.BackgroundTransparency = 1
    bbName.Text                   = name
    bbName.TextColor3             = Color3.fromRGB(50, 255, 80)
    bbName.Font                   = Enum.Font.GothamBold
    bbName.TextSize               = 30
    bbName.TextScaled             = false
    bbName.TextStrokeTransparency = 0.25
    bbName.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    bbName.Parent                 = billboard

    local bbDist = Instance.new('TextLabel')
    bbDist.Size                   = UDim2.new(1, 0, 0.4, 0)
    bbDist.Position               = UDim2.new(0, 0, 0.6, 0)
    bbDist.BackgroundTransparency = 1
    bbDist.TextColor3             = Color3.fromRGB(160, 255, 160)
    bbDist.Font                   = Enum.Font.Gotham
    bbDist.TextSize               = 20
    bbDist.TextStrokeTransparency = 0.3
    bbDist.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    bbDist.Parent                 = billboard

    local wp = {id=id, name=name, x=wx, y=wy, z=wz,
                beamPart=beamPart, topPart=topPart,
                bbName=bbName, bbDist=bbDist, row=nil}
    rideoutWPs[id] = wp

    -- distance label updater (shared heartbeat)
    if not _G.RideoutWPUpdateConn then
        local RS2 = game:GetService('RunService')
        _G.RideoutWPUpdateConn = RS2.Heartbeat:Connect(function()
            local myChar = plr.Character
            local myHRP  = myChar and myChar:FindFirstChild('HumanoidRootPart')
            for _, w in pairs(rideoutWPs) do
                if w.bbDist and w.bbDist.Parent then
                    if myHRP then
                        local d = math.floor((myHRP.Position - Vector3.new(w.x, w.y, w.z)).Magnitude + 0.5)
                        w.bbDist.Text = d .. ' m'
                    else
                        w.bbDist.Text = ''
                    end
                end
            end
        end)
    end

    -- add row to panel if it's already open
    if rideoutWpGui and _addRoWpRow then
        local panel = rideoutWpGui:FindFirstChildWhichIsA('Frame')
        local scroll = panel and panel:FindFirstChild('Scroll')
        if scroll then _addRoWpRow(wp, scroll) end
    end

    showToast(name .. ' placed')
    return wp
end

local function _clearRideoutWPs()
    for _, wp in pairs(rideoutWPs) do
        pcall(function() if wp.beamPart and wp.beamPart.Parent then wp.beamPart:Destroy() end end)
        pcall(function() if wp.topPart  and wp.topPart.Parent  then wp.topPart:Destroy()  end end)
        pcall(function() if wp.row      and wp.row.Parent      then wp.row:Destroy()      end end)
    end
    rideoutWPs  = {}
    nextRoWpId  = 1
    if _G.RideoutWPUpdateConn then _G.RideoutWPUpdateConn:Disconnect(); _G.RideoutWPUpdateConn = nil end
end

local function _cleanOwnership()
    _ownershipActive = false
    if _selfLeaderBox then
        pcall(function() _selfLeaderBox:Destroy() end)
        _selfLeaderBox = nil
    end
    if _ownershipHudGui then
        _ownershipHudGui.Enabled = false
    end
    if _G.OwnershipConn then _G.OwnershipConn:Disconnect(); _G.OwnershipConn = nil end
end

local function _cleanLeaderESP()
    if _leaderBox  then pcall(function() _leaderBox:Destroy()  end); _leaderBox  = nil end
    if _leaderBill then pcall(function() _leaderBill:Destroy() end); _leaderBill = nil end
end

local function _cleanLeaderTrail()
    if _G.RideoutTrailA0 then pcall(function() _G.RideoutTrailA0:Destroy() end); _G.RideoutTrailA0 = nil end
    if _G.RideoutTrailA1 then pcall(function() _G.RideoutTrailA1:Destroy() end); _G.RideoutTrailA1 = nil end
    if _G.RideoutTrail   then pcall(function() _G.RideoutTrail:Destroy()   end); _G.RideoutTrail   = nil end
end

local function _applyLeaderESP(p)
    _cleanLeaderESP()
    local char = p.Character
    if not char then return end
    local hrp = char:FindFirstChild('HumanoidRootPart')
    if not hrp then return end
    local box = Instance.new('SelectionBox')
    box.Color3        = Color3.fromRGB(50, 255, 80)
    box.LineThickness = 0.08
    box.SurfaceTransparency = 0.85
    box.SurfaceColor3 = Color3.fromRGB(50, 255, 80)
    box.Adornee       = char
    box.Parent        = workspace
    _leaderBox = box
    local bill = Instance.new('BillboardGui')
    bill.AlwaysOnTop = true
    bill.Size        = UDim2.new(0, 180, 0, 26)
    bill.StudsOffset = Vector3.new(0, 4.5, 0)
    bill.Adornee     = hrp
    bill.Parent      = workspace
    local lbl = Instance.new('TextLabel')
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = '[LEADER] ' .. p.Name
    lbl.TextColor3             = Color3.fromRGB(50, 255, 80)
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextSize               = 14
    lbl.TextStrokeTransparency = 0.4
    lbl.Parent                 = bill
    _leaderBill = bill
end

local function _applyLeaderTrail(p)
    _cleanLeaderTrail()
    local char = p.Character
    if not char then return end
    local hrp = char:FindFirstChild('HumanoidRootPart')
    if not hrp then return end
    local a0 = Instance.new('Attachment')
    a0.Position = Vector3.new(0, 0.6, 0)
    a0.Parent   = hrp
    local a1 = Instance.new('Attachment')
    a1.Position = Vector3.new(0, -0.6, 0)
    a1.Parent   = hrp
    local trail = Instance.new('Trail')
    trail.Attachment0   = a0
    trail.Attachment1   = a1
    trail.Lifetime      = 600
    trail.MinLength     = 0
    trail.FaceCamera    = true
    trail.LightEmission = 0.9
    trail.Color         = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 255, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0,  160, 50)),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 0.3),
    })
    trail.Parent     = workspace
    _G.RideoutTrailA0 = a0
    _G.RideoutTrailA1 = a1
    _G.RideoutTrail   = trail
end

-- Start / Stop Rideout
RideoutLeft:AddButton({
    Text = 'Start Rideout',
    Func = function()
        _rideoutActive = true
        showToast('Rideout started')
    end
})

RideoutLeft:AddButton({
    Text = 'Stop Rideout',
    Func = function()
        _rideoutActive = false
        _rideoutLeader = nil
        _cleanLeaderESP()
        _cleanLeaderTrail()
        _cleanOwnership()
        if _G.RideoutLeaderConn  then _G.RideoutLeaderConn:Disconnect();  _G.RideoutLeaderConn  = nil end
        if _G.RideoutFollowConn  then _G.RideoutFollowConn:Disconnect();  _G.RideoutFollowConn  = nil end
        if _G.RideoutHUDConn     then _G.RideoutHUDConn:Disconnect();     _G.RideoutHUDConn     = nil end
        if _rideoutHudGui        then _rideoutHudGui.Enabled = false end
        showToast('Rideout stopped')
    end
})

RideoutLeft:AddButton({
    Text = 'Claim Ownership (set yourself as leader)',
    Func = function()
        if _ownershipActive then
            _cleanOwnership()
            showToast('Ownership released')
            return
        end

        local myChar = plr.Character
        if not myChar then showToast('Get in-game first'); return end

        _ownershipActive = true

        -- yellow SelectionBox on own character
        local box = Instance.new('SelectionBox')
        box.Color3               = Color3.fromRGB(255, 210, 0)
        box.LineThickness        = 0.09
        box.SurfaceTransparency  = 0.8
        box.SurfaceColor3        = Color3.fromRGB(255, 210, 0)
        box.Adornee              = myChar
        box.Parent               = workspace
        _selfLeaderBox           = box

        -- build the top-center rider count HUD if it doesn't exist yet
        if not _ownershipHudGui then
            local hg = Instance.new('ScreenGui')
            hg.Name           = 'OwnershipHudGui'
            hg.ResetOnSpawn   = false
            hg.DisplayOrder   = 215
            hg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            hg.Parent         = plr.PlayerGui
            _ownershipHudGui  = hg

            local bar = Instance.new('Frame')
            bar.Name             = 'Bar'
            bar.AnchorPoint      = Vector2.new(0.5, 0)
            bar.Size             = UDim2.new(0, 340, 0, 42)
            bar.Position         = UDim2.new(0.5, 0, 0, 6)
            bar.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
            bar.BorderSizePixel  = 1
            bar.BorderColor3     = Color3.fromRGB(255, 210, 0)
            bar.ZIndex           = 20
            bar.Parent           = hg

            -- left accent bar
            local accent = Instance.new('Frame')
            accent.Size             = UDim2.new(0, 3, 1, 0)
            accent.BackgroundColor3 = Color3.fromRGB(255, 210, 0)
            accent.BorderSizePixel  = 0
            accent.ZIndex           = 21
            accent.Parent           = bar

            -- top line
            local topLine = Instance.new('Frame')
            topLine.Size             = UDim2.new(1, 0, 0, 2)
            topLine.BackgroundColor3 = Color3.fromRGB(255, 210, 0)
            topLine.BorderSizePixel  = 0
            topLine.ZIndex           = 21
            topLine.Parent           = bar

            local badge = Instance.new('TextLabel')
            badge.Size                   = UDim2.new(0, 80, 1, 0)
            badge.Position               = UDim2.new(0, 8, 0, 0)
            badge.BackgroundTransparency = 1
            badge.Text                   = 'LEADING'
            badge.TextColor3             = Color3.fromRGB(255, 210, 0)
            badge.Font                   = Enum.Font.GothamBold
            badge.TextSize               = 11
            badge.TextXAlignment         = Enum.TextXAlignment.Left
            badge.ZIndex                 = 21
            badge.Parent                 = bar

            local riderLbl = Instance.new('TextLabel')
            riderLbl.Name                   = 'RiderLabel'
            riderLbl.Size                   = UDim2.new(1, -100, 1, 0)
            riderLbl.Position               = UDim2.new(0, 90, 0, 0)
            riderLbl.BackgroundTransparency = 1
            riderLbl.Text                   = '0 riders nearby'
            riderLbl.TextColor3             = Color3.fromRGB(240, 240, 240)
            riderLbl.Font                   = Enum.Font.Gotham
            riderLbl.TextSize               = 15
            riderLbl.TextXAlignment         = Enum.TextXAlignment.Left
            riderLbl.ZIndex                 = 21
            riderLbl.Parent                 = bar
        end
        _ownershipHudGui.Enabled = true

        -- re-adorn box if character respawns
        local RS2 = game:GetService('RunService')
        local _lastOwnChar = myChar
        local _frameCount  = 0
        _G.OwnershipConn = RS2.Heartbeat:Connect(function()
            if not _ownershipActive then return end

            -- re-adorn on respawn
            local curChar = plr.Character
            if curChar ~= _lastOwnChar then
                _lastOwnChar = curChar
                if curChar and _selfLeaderBox then
                    _selfLeaderBox.Adornee = curChar
                end
            end

            -- update rider count every 30 frames (~0.5s)
            _frameCount += 1
            if _frameCount < 30 then return end
            _frameCount = 0

            local myHRP = curChar and curChar:FindFirstChild('HumanoidRootPart')
            local bar2  = _ownershipHudGui and _ownershipHudGui:FindFirstChild('Bar')
            local lbl   = bar2 and bar2:FindFirstChild('RiderLabel')
            if not lbl then return end

            local count = 0
            if myHRP then
                local myPos = myHRP.Position
                for _, p in ipairs(Players:GetPlayers()) do
                    if p == plr then continue end
                    local c = p.Character
                    local h = c and c:FindFirstChild('HumanoidRootPart')
                    if h and (h.Position - myPos).Magnitude <= 200 then
                        count += 1
                    end
                end
            end

            local word = count == 1 and 'rider' or 'riders'
            lbl.Text = count .. ' ' .. word .. ' within 200 studs'
        end)

        showToast('You are the leader')
    end
})

RideoutLeft:AddDivider()

-- Set Leader
RideoutLeft:AddInput('RideoutLeaderName', {
    Default  = '',
    Numeric  = false,
    Finished = false,
    Text     = 'Leader username',
})

RideoutLeft:AddButton({
    Text = 'Set Leader',
    Func = function()
        local raw = (Options.RideoutLeaderName and Options.RideoutLeaderName.Value or ''):lower():gsub('%s+', '')
        if raw == '' then showToast('Enter a username'); return end
        local found = nil
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= plr then
                if p.Name:lower():find(raw, 1, true) or p.DisplayName:lower():find(raw, 1, true) then
                    found = p; break
                end
            end
        end
        if not found then showToast('Player not found'); return end
        _rideoutLeader = found
        _applyLeaderESP(found)
        showToast('Leader: ' .. found.Name)
        -- re-apply trail if toggle is on
        if Toggles.LeaderTrail and Toggles.LeaderTrail.Value then
            _applyLeaderTrail(found)
        end
    end
})

RideoutLeft:AddDivider()

-- Leader Trail toggle
RideoutLeft:AddToggle('LeaderTrail', {
    Text    = 'Leader Trail (permanent)',
    Default = false,
    Callback = function(val)
        if val then
            if not _rideoutLeader then showToast('Set a leader first'); Toggles.LeaderTrail:SetValue(false); return end
            _applyLeaderTrail(_rideoutLeader)
            showToast('Leader trail ON')
        else
            _cleanLeaderTrail()
            showToast('Leader trail OFF')
        end
    end
})

-- Teleport to Leader
RideoutLeft:AddButton({
    Text = 'Teleport to Leader',
    Func = function()
        if not _rideoutLeader then showToast('Set a leader first'); return end
        local char = _rideoutLeader.Character
        if not char then showToast('Leader has no character'); return end
        local hrp = char:FindFirstChild('HumanoidRootPart')
        if not hrp then showToast('Leader HRP not found'); return end
        local myChar = plr.Character
        local myHRP  = myChar and myChar:FindFirstChild('HumanoidRootPart')
        if not myHRP then showToast('Get in-game first'); return end
        local offset = Vector3.new(3, 0, 3)
        myHRP.CFrame = CFrame.new(hrp.Position + offset)
        showToast('Teleported to ' .. _rideoutLeader.Name)
    end
})

RideoutLeft:AddDivider()

-- Leader HUD toggle (right side of screen overlay)
RideoutLeft:AddToggle('RideoutHUD', {
    Text    = 'Rideout HUD',
    Default = false,
    Callback = function(val)
        if val then
            if not _rideoutHudGui then
                local hg = Instance.new('ScreenGui')
                hg.Name           = 'RideoutHUDGui'
                hg.ResetOnSpawn   = false
                hg.DisplayOrder   = 210
                hg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                hg.Parent         = plr.PlayerGui
                _rideoutHudGui = hg

                local card = Instance.new('Frame')
                card.Size             = UDim2.new(0, 220, 0, 72)
                card.Position         = UDim2.new(1, -228, 0, 8)
                card.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
                card.BorderSizePixel  = 1
                card.BorderColor3     = Color3.fromRGB(50, 255, 80)
                card.ZIndex           = 20
                card.Parent           = hg

                local accent = Instance.new('Frame')
                accent.Size             = UDim2.new(0, 3, 1, 0)
                accent.BackgroundColor3 = Color3.fromRGB(50, 255, 80)
                accent.BorderSizePixel  = 0
                accent.ZIndex           = 21
                accent.Parent           = card

                local titleL = Instance.new('TextLabel')
                titleL.Size                   = UDim2.new(1, -10, 0, 20)
                titleL.Position               = UDim2.new(0, 8, 0, 2)
                titleL.BackgroundTransparency = 1
                titleL.Text                   = 'RIDEOUT'
                titleL.TextColor3             = Color3.fromRGB(50, 255, 80)
                titleL.Font                   = Enum.Font.GothamBold
                titleL.TextSize               = 12
                titleL.TextXAlignment         = Enum.TextXAlignment.Left
                titleL.ZIndex                 = 21
                titleL.Parent                 = card

                local infoL = Instance.new('TextLabel')
                infoL.Name                   = 'InfoLabel'
                infoL.Size                   = UDim2.new(1, -10, 0, 44)
                infoL.Position               = UDim2.new(0, 8, 0, 24)
                infoL.BackgroundTransparency = 1
                infoL.Text                   = 'No leader set'
                infoL.TextColor3             = Color3.fromRGB(200, 255, 200)
                infoL.Font                   = Enum.Font.Gotham
                infoL.TextSize               = 13
                infoL.TextXAlignment         = Enum.TextXAlignment.Left
                infoL.TextYAlignment         = Enum.TextYAlignment.Top
                infoL.TextWrapped            = true
                infoL.ZIndex                 = 21
                infoL.Parent                 = card
            end
            _rideoutHudGui.Enabled = true
            local infoLbl = _rideoutHudGui:FindFirstChild('Frame') and
                            _rideoutHudGui.Frame:FindFirstChild('InfoLabel')
            local RS2 = game:GetService('RunService')
            _G.RideoutHUDConn = RS2.Heartbeat:Connect(function()
                if not _rideoutHudGui or not _rideoutHudGui.Enabled then return end
                local card2 = _rideoutHudGui:FindFirstChildWhichIsA('Frame')
                if not card2 then return end
                local lbl = card2:FindFirstChild('InfoLabel')
                if not lbl then return end
                if not _rideoutLeader then
                    lbl.Text = 'No leader set'
                    return
                end
                local lChar = _rideoutLeader.Character
                local lHRP  = lChar and lChar:FindFirstChild('HumanoidRootPart')
                local myChar2 = plr.Character
                local myHRP2  = myChar2 and myChar2:FindFirstChild('HumanoidRootPart')
                if not lHRP then lbl.Text = _rideoutLeader.Name .. '\nOffline'; return end
                local spd  = math.floor((lHRP.AssemblyLinearVelocity.Magnitude * 0.625) + 0.5)
                local dist = myHRP2 and math.floor((myHRP2.Position - lHRP.Position).Magnitude + 0.5) or 0
                lbl.Text = _rideoutLeader.Name .. '\n' .. spd .. ' mph  |  ' .. dist .. ' studs away'
            end)
            showToast('Rideout HUD ON')
        else
            if _G.RideoutHUDConn then _G.RideoutHUDConn:Disconnect(); _G.RideoutHUDConn = nil end
            if _rideoutHudGui then _rideoutHudGui.Enabled = false end
            showToast('Rideout HUD OFF')
        end
    end
})

RideoutLeft:AddDivider()

-- Follow Leader toggle (steers player's bike toward leader each Heartbeat)
RideoutLeft:AddToggle('FollowLeader', {
    Text    = 'Follow Leader (bike fly)',
    Default = false,
    Callback = function(val)
        if val then
            if not _rideoutLeader then showToast('Set a leader first'); Toggles.FollowLeader:SetValue(false); return end
            local RS2 = game:GetService('RunService')
            _G.RideoutFollowConn = RS2.Heartbeat:Connect(function(dt)
                if not _rideoutLeader then return end
                local lChar = _rideoutLeader.Character
                local lHRP  = lChar and lChar:FindFirstChild('HumanoidRootPart')
                if not lHRP then return end
                local _, bikeRoot = getBikeRoot()
                if not bikeRoot then return end
                local toLeader = lHRP.Position - bikeRoot.Position
                local dist2 = toLeader.Magnitude
                if dist2 < 6 then
                    bikeRoot.AssemblyLinearVelocity = bikeRoot.AssemblyLinearVelocity * 0.85
                    return
                end
                local dir = toLeader.Unit
                local speed = math.min(dist2 * 0.5, 80)
                bikeRoot.AssemblyLinearVelocity = Vector3.new(
                    dir.X * speed,
                    bikeRoot.AssemblyLinearVelocity.Y,
                    dir.Z * speed
                )
            end)
            showToast('Follow Leader ON')
        else
            if _G.RideoutFollowConn then _G.RideoutFollowConn:Disconnect(); _G.RideoutFollowConn = nil end
            showToast('Follow Leader OFF')
        end
    end
})

RideoutLeft:AddDivider()

-- ---- Rideout Waypoints -------------------------------------------------
RideoutLeft:AddInput('RoWpName', {
    Default  = 'Waypoint',
    Numeric  = false,
    Finished = false,
    Text     = 'Waypoint name',
})

RideoutLeft:AddButton({
    Text = 'Set Waypoint (at your position)',
    Func = function()
        local myChar = plr.Character
        local myHRP  = myChar and myChar:FindFirstChild('HumanoidRootPart')
        if not myHRP then showToast('Get in-game first'); return end
        local name = (Options.RoWpName and Options.RoWpName.Value or 'Waypoint')
        if name:gsub('%s+', '') == '' then name = 'Waypoint' end
        local pos = myHRP.Position
        _makeRideoutWP(name, pos.X, pos.Y, pos.Z)
    end
})

RideoutLeft:AddDivider()

RideoutLeft:AddInput('RoImportCF', {
    Default  = '',
    Numeric  = false,
    Finished = false,
    Text     = 'Import: X, Y, Z  (or CFrame.new(...))',
})

RideoutLeft:AddButton({
    Text = 'Import Waypoint',
    Func = function()
        local str = Options.RoImportCF and Options.RoImportCF.Value or ''
        local x, y, z = _parseXYZ(str)
        if not x then showToast('Invalid CFrame -- use X, Y, Z'); return end
        local name = (Options.RoWpName and Options.RoWpName.Value or 'Waypoint')
        if name:gsub('%s+', '') == '' then name = 'Imported WP' end
        _makeRideoutWP(name, x, y, z)
    end
})

RideoutLeft:AddButton({
    Text = 'Copy Current CFrame',
    Func = function()
        local myChar = plr.Character
        local myHRP  = myChar and myChar:FindFirstChild('HumanoidRootPart')
        if not myHRP then showToast('Get in-game first'); return end
        local p = myHRP.Position
        local cfStr = string.format('%.2f, %.2f, %.2f', p.X, p.Y, p.Z)
        pcall(function() setclipboard(cfStr) end)
        showToast('Pos: ' .. cfStr)
    end
})

RideoutLeft:AddDivider()

RideoutLeft:AddButton({
    Text = 'Waypoint List',
    Func = function()
        if rideoutWpGui then rideoutWpGui.Enabled = not rideoutWpGui.Enabled end
    end
})

RideoutLeft:AddButton({
    Text = 'Clear All Waypoints',
    Func = function()
        _clearRideoutWPs()
        showToast('All waypoints cleared')
    end
})

-- Right groupbox: leader info + refresh
RideoutRight:AddButton({
    Text = 'Refresh Leader ESP',
    Func = function()
        if not _rideoutLeader then showToast('No leader set'); return end
        _applyLeaderESP(_rideoutLeader)
        if Toggles.LeaderTrail and Toggles.LeaderTrail.Value then
            _applyLeaderTrail(_rideoutLeader)
        end
        showToast('Leader ESP refreshed')
    end
})

RideoutRight:AddButton({
    Text = 'Clear Leader',
    Func = function()
        _rideoutLeader = nil
        _cleanLeaderESP()
        _cleanLeaderTrail()
        if Toggles.LeaderTrail then Toggles.LeaderTrail:SetValue(false) end
        if Toggles.FollowLeader then Toggles.FollowLeader:SetValue(false) end
        showToast('Leader cleared')
    end
})

RideoutRight:AddDivider()

-- auto-refresh leader ESP when leader respawns (character changed)
do
    local RS2 = game:GetService('RunService')
    local _lastLeaderChar = nil
    _G.RideoutLeaderConn = RS2.Heartbeat:Connect(function()
        if not _rideoutLeader then _lastLeaderChar = nil; return end
        local char = _rideoutLeader.Character
        if char ~= _lastLeaderChar then
            _lastLeaderChar = char
            if char then
                task.delay(0.2, function()
                    _applyLeaderESP(_rideoutLeader)
                    if Toggles.LeaderTrail and Toggles.LeaderTrail.Value then
                        _applyLeaderTrail(_rideoutLeader)
                    end
                end)
            end
        end
    end)
end

-- ============================================================
-- RIDEOUT WAYPOINT LIST PANEL
-- ============================================================
do
    local wpg = Instance.new('ScreenGui')
    wpg.Name           = 'RideoutWPGui'
    wpg.ResetOnSpawn   = false
    wpg.DisplayOrder   = 996
    wpg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    wpg.Enabled        = false
    wpg.Parent         = plr.PlayerGui
    rideoutWpGui       = wpg

    local panel = Instance.new('Frame')
    panel.Name             = 'Panel'
    panel.Size             = UDim2.new(0, 440, 0, 420)
    panel.Position         = UDim2.new(0.5, -220, 0.5, -210)
    panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    panel.BorderSizePixel  = 1
    panel.BorderColor3     = Color3.fromRGB(50, 80, 50)
    panel.Active           = true
    panel.ZIndex           = 10
    panel.Parent           = wpg

    -- drag
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
        game:GetService('UserInputService').InputChanged:Connect(function(inp)
            if drag and inp.UserInputType == Enum.UserInputType.MouseMovement then
                local d = inp.Position - dragStart
                panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                           startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    -- title bar
    local titleBar = Instance.new('Frame')
    titleBar.Size             = UDim2.new(1, 0, 0, 30)
    titleBar.BackgroundColor3 = Color3.fromRGB(25, 45, 25)
    titleBar.BorderSizePixel  = 0
    titleBar.ZIndex           = 11
    titleBar.Parent           = panel

    local accentLine = Instance.new('Frame')
    accentLine.Size             = UDim2.new(1, 0, 0, 2)
    accentLine.Position         = UDim2.new(0, 0, 1, -2)
    accentLine.BackgroundColor3 = Color3.fromRGB(50, 255, 80)
    accentLine.BorderSizePixel  = 0
    accentLine.ZIndex           = 12
    accentLine.Parent           = titleBar

    local titleLblWp = Instance.new('TextLabel')
    titleLblWp.Size                   = UDim2.new(1, -40, 1, 0)
    titleLblWp.Position               = UDim2.new(0, 10, 0, 0)
    titleLblWp.BackgroundTransparency = 1
    titleLblWp.Text                   = 'Rideout Waypoints'
    titleLblWp.TextColor3             = Color3.fromRGB(50, 255, 80)
    titleLblWp.Font                   = Enum.Font.GothamBold
    titleLblWp.TextSize               = 14
    titleLblWp.TextXAlignment         = Enum.TextXAlignment.Left
    titleLblWp.ZIndex                 = 12
    titleLblWp.Parent                 = titleBar

    local closeBtnWp = Instance.new('TextButton')
    closeBtnWp.Size             = UDim2.new(0, 30, 1, 0)
    closeBtnWp.Position         = UDim2.new(1, -30, 0, 0)
    closeBtnWp.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
    closeBtnWp.BorderSizePixel  = 0
    closeBtnWp.Text             = 'X'
    closeBtnWp.TextColor3       = Color3.fromRGB(240, 240, 240)
    closeBtnWp.Font             = Enum.Font.GothamBold
    closeBtnWp.TextSize         = 13
    closeBtnWp.ZIndex           = 12
    closeBtnWp.Parent           = titleBar
    closeBtnWp.MouseButton1Click:Connect(function() wpg.Enabled = false end)

    -- column header
    local hdr = Instance.new('Frame')
    hdr.Size             = UDim2.new(1, 0, 0, 22)
    hdr.Position         = UDim2.new(0, 0, 0, 30)
    hdr.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    hdr.BorderSizePixel  = 0
    hdr.ZIndex           = 11
    hdr.Parent           = panel

    local function hdrLabel(txt, x, w)
        local l = Instance.new('TextLabel')
        l.Size                   = UDim2.new(0, w, 1, 0)
        l.Position               = UDim2.new(0, x, 0, 0)
        l.BackgroundTransparency = 1
        l.Text                   = txt
        l.TextColor3             = Color3.fromRGB(140, 140, 140)
        l.Font                   = Enum.Font.GothamBold
        l.TextSize               = 11
        l.TextXAlignment         = Enum.TextXAlignment.Left
        l.ZIndex                 = 12
        l.Parent                 = hdr
    end
    hdrLabel('Name',     8,   240)
    hdrLabel('',         248,  0)
    hdrLabel('Position', 256, 120)

    -- scrolling list
    local scroll = Instance.new('ScrollingFrame')
    scroll.Name                            = 'Scroll'
    scroll.Size                            = UDim2.new(1, 0, 1, -106)
    scroll.Position                        = UDim2.new(0, 0, 0, 52)
    scroll.BackgroundColor3                = Color3.fromRGB(16, 16, 16)
    scroll.BorderSizePixel                 = 0
    scroll.ScrollBarThickness              = 6
    scroll.ScrollBarImageColor3            = Color3.fromRGB(50, 200, 70)
    scroll.CanvasSize                      = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize             = Enum.AutomaticSize.Y
    scroll.ZIndex                          = 11
    scroll.Parent                          = panel

    local listLayout = Instance.new('UIListLayout')
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding   = UDim.new(0, 2)
    listLayout.Parent    = scroll

    local listPad = Instance.new('UIPadding')
    listPad.PaddingTop  = UDim.new(0, 3)
    listPad.PaddingLeft = UDim.new(0, 3)
    listPad.Parent      = scroll

    -- empty state label
    local emptyLbl = Instance.new('TextLabel')
    emptyLbl.Name                   = 'EmptyLabel'
    emptyLbl.Size                   = UDim2.new(1, 0, 0, 36)
    emptyLbl.BackgroundTransparency = 1
    emptyLbl.Text                   = 'No waypoints placed yet.\nUse "Set Waypoint" in the Rideout tab.'
    emptyLbl.TextColor3             = Color3.fromRGB(100, 100, 100)
    emptyLbl.Font                   = Enum.Font.Gotham
    emptyLbl.TextSize               = 12
    emptyLbl.TextWrapped            = true
    emptyLbl.ZIndex                 = 12
    emptyLbl.Parent                 = scroll

    local function updateEmptyLabel()
        local count = 0
        for _ in pairs(rideoutWPs) do count += 1 end
        emptyLbl.Visible = (count == 0)
    end

    -- footer: total count label + clear-all button
    local footer = Instance.new('Frame')
    footer.Size             = UDim2.new(1, 0, 0, 54)
    footer.Position         = UDim2.new(0, 0, 1, -54)
    footer.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    footer.BorderSizePixel  = 0
    footer.ZIndex           = 11
    footer.Parent           = panel

    local footerLine = Instance.new('Frame')
    footerLine.Size             = UDim2.new(1, 0, 0, 1)
    footerLine.BackgroundColor3 = Color3.fromRGB(50, 80, 50)
    footerLine.BorderSizePixel  = 0
    footerLine.ZIndex           = 12
    footerLine.Parent           = footer

    local countLbl = Instance.new('TextLabel')
    countLbl.Name                   = 'CountLabel'
    countLbl.Size                   = UDim2.new(0.5, 0, 0, 26)
    countLbl.Position               = UDim2.new(0, 8, 0, 6)
    countLbl.BackgroundTransparency = 1
    countLbl.Text                   = '0 waypoints'
    countLbl.TextColor3             = Color3.fromRGB(130, 130, 130)
    countLbl.Font                   = Enum.Font.Gotham
    countLbl.TextSize               = 12
    countLbl.TextXAlignment         = Enum.TextXAlignment.Left
    countLbl.ZIndex                 = 12
    countLbl.Parent                 = footer

    local clearAllBtn = Instance.new('TextButton')
    clearAllBtn.Size             = UDim2.new(0, 130, 0, 26)
    clearAllBtn.Position         = UDim2.new(1, -138, 0, 6)
    clearAllBtn.BackgroundColor3 = Color3.fromRGB(130, 35, 35)
    clearAllBtn.BorderSizePixel  = 0
    clearAllBtn.Text             = 'Clear All'
    clearAllBtn.TextColor3       = Color3.fromRGB(240, 240, 240)
    clearAllBtn.Font             = Enum.Font.GothamBold
    clearAllBtn.TextSize         = 12
    clearAllBtn.ZIndex           = 12
    clearAllBtn.Parent           = footer
    clearAllBtn.MouseButton1Click:Connect(function()
        _clearRideoutWPs()
        updateEmptyLabel()
        countLbl.Text = '0 waypoints'
        showToast('All waypoints cleared')
    end)

    local function updateCountLabel()
        local count = 0
        for _ in pairs(rideoutWPs) do count += 1 end
        countLbl.Text = count .. (count == 1 and ' waypoint' or ' waypoints')
    end

    -- assign the forward-declared helpers
    _reflowRoWpRows = function()
        -- UIListLayout handles positioning automatically; just update footer
        updateCountLabel()
        updateEmptyLabel()
    end

    _addRoWpRow = function(wp, sc)
        local rowCount = 0
        for _ in pairs(rideoutWPs) do rowCount += 1 end

        local row = Instance.new('Frame')
        row.Name             = 'WpRow_' .. wp.id
        row.LayoutOrder      = wp.id
        row.Size             = UDim2.new(1, -6, 0, 30)
        row.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
        row.BorderColor3     = Color3.fromRGB(40, 60, 40)
        row.BorderSizePixel  = 1
        row.ZIndex           = 12
        row.Parent           = sc
        wp.row = row

        -- editable name box
        local nameBox = Instance.new('TextBox')
        nameBox.Size             = UDim2.new(1, -204, 1, -6)
        nameBox.Position         = UDim2.new(0, 4, 0, 3)
        nameBox.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
        nameBox.BorderColor3     = Color3.fromRGB(45, 70, 45)
        nameBox.BorderSizePixel  = 1
        nameBox.Text             = wp.name
        nameBox.TextColor3       = Color3.fromRGB(220, 220, 220)
        nameBox.Font             = Enum.Font.Gotham
        nameBox.TextSize         = 13
        nameBox.PlaceholderText  = 'Waypoint name'
        nameBox.ClearTextOnFocus = false
        nameBox.TextXAlignment   = Enum.TextXAlignment.Left
        nameBox.ZIndex           = 13
        nameBox.Parent           = row
        nameBox.FocusLost:Connect(function()
            local newName = nameBox.Text:match('^%s*(.-)%s*$')
            if not newName or newName == '' then
                newName = 'WP ' .. wp.id
                nameBox.Text = newName
            end
            wp.name = newName
            if wp.bbName and wp.bbName.Parent then wp.bbName.Text = newName end
        end)

        -- position display label
        local posLbl = Instance.new('TextLabel')
        posLbl.Size                   = UDim2.new(0, 100, 1, -6)
        posLbl.Position               = UDim2.new(1, -200, 0, 3)
        posLbl.BackgroundTransparency = 1
        posLbl.Text                   = string.format('%.0f, %.0f, %.0f', wp.x, wp.y, wp.z)
        posLbl.TextColor3             = Color3.fromRGB(100, 160, 100)
        posLbl.Font                   = Enum.Font.Gotham
        posLbl.TextSize               = 10
        posLbl.TextXAlignment         = Enum.TextXAlignment.Left
        posLbl.ZIndex                 = 13
        posLbl.Parent                 = row

        -- Go (teleport) button
        local goBtn = Instance.new('TextButton')
        goBtn.Size             = UDim2.new(0, 44, 1, -6)
        goBtn.Position         = UDim2.new(1, -96, 0, 3)
        goBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 180)
        goBtn.BorderSizePixel  = 0
        goBtn.Text             = 'Go'
        goBtn.TextColor3       = Color3.fromRGB(240, 240, 240)
        goBtn.Font             = Enum.Font.GothamBold
        goBtn.TextSize         = 12
        goBtn.ZIndex           = 13
        goBtn.Parent           = row
        goBtn.MouseButton1Click:Connect(function()
            local myChar = plr.Character
            local myHRP  = myChar and myChar:FindFirstChild('HumanoidRootPart')
            if not myHRP then return end
            myHRP.CFrame = CFrame.new(wp.x, wp.y + 3, wp.z)
            showToast('Teleported to ' .. wp.name)
        end)

        -- Copy CFrame button
        local cpBtn = Instance.new('TextButton')
        cpBtn.Size             = UDim2.new(0, 44, 1, -6)
        cpBtn.Position         = UDim2.new(1, -48, 0, 3)
        cpBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        cpBtn.BorderSizePixel  = 0
        cpBtn.Text             = 'Copy'
        cpBtn.TextColor3       = Color3.fromRGB(180, 255, 180)
        cpBtn.Font             = Enum.Font.GothamBold
        cpBtn.TextSize         = 11
        cpBtn.ZIndex           = 13
        cpBtn.Parent           = row
        cpBtn.MouseButton1Click:Connect(function()
            local cfStr = string.format('%.2f, %.2f, %.2f', wp.x, wp.y, wp.z)
            pcall(function() setclipboard(cfStr) end)
            showToast('Copied: ' .. cfStr)
        end)

        -- small red X delete button at far right of row
        local xBtn = Instance.new('TextButton')
        xBtn.Size             = UDim2.new(0, 18, 1, -6)
        xBtn.Position         = UDim2.new(1, -2, 0, 3)
        xBtn.AnchorPoint      = Vector2.new(1, 0)
        xBtn.BackgroundColor3 = Color3.fromRGB(160, 35, 35)
        xBtn.BorderSizePixel  = 0
        xBtn.Text             = 'X'
        xBtn.TextColor3       = Color3.fromRGB(240, 240, 240)
        xBtn.Font             = Enum.Font.GothamBold
        xBtn.TextSize         = 10
        xBtn.ZIndex           = 13
        xBtn.Parent           = row
        xBtn.MouseButton1Click:Connect(function()
            pcall(function() if wp.beamPart and wp.beamPart.Parent then wp.beamPart:Destroy() end end)
            pcall(function() if wp.topPart  and wp.topPart.Parent  then wp.topPart:Destroy()  end end)
            row:Destroy()
            rideoutWPs[wp.id] = nil
            _reflowRoWpRows()
        end)

        _reflowRoWpRows()
    end

    -- populate rows for any waypoints already placed before panel was built
    for _, wp in pairs(rideoutWPs) do
        _addRoWpRow(wp, scroll)
    end
    updateEmptyLabel()
    updateCountLabel()
end

-- ============================================================
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
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = plr.PlayerGui

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

-- spawner window
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
titleLbl.Text = 'Bike Spawner'
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

local bikeList = {}
for _, v in ipairs(RS.Bikes:GetChildren()) do
    if v:IsA('Model') then
        table.insert(bikeList, v)
    end
end
scroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#bikeList / 3) * 154 + 8)

for _, bike in ipairs(bikeList) do
    local card = Instance.new('TextButton')
    card.Size = UDim2.new(0, 130, 0, 150)
    card.BackgroundColor3 = BGSUB
    card.BorderSizePixel = 1
    card.BorderColor3 = BORDER
    card.Text = ''
    card.ZIndex = 12
    card.Parent = scroll

    local vpf = Instance.new('ViewportFrame')
    vpf.Size = UDim2.new(1, 0, 0, 108)
    vpf.BackgroundColor3 = BG2
    vpf.BorderSizePixel = 0
    vpf.ZIndex = 13
    vpf.Parent = card

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
        RS.Remotes.SpawnBike:FireServer(bike.Name)
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

Toggles.SpawnerToggle:OnChanged(function()
    spawnerFrame.Visible = Toggles.SpawnerToggle.Value
end)

-- keybind (change hideKey to whatever you want)
local hideKey = Enum.KeyCode.Delete

UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == hideKey then
        Library:Toggle()
        spawnerFrame.Visible = false
        Toggles.SpawnerToggle:SetValue(false)
    end
end)

-- ============================================================
-- TRAIL SETTINGS PANEL
-- ============================================================

do
    local TRAIL_PRESETS = {
        { name = 'Solid',   textureId = '',                        lightEmission = 0.5  },
        { name = 'Neon',    textureId = '',                        lightEmission = 1.0  },
        { name = 'Sparkle', textureId = 'rbxassetid://1308397735', lightEmission = 0.8  },
        { name = 'Ribbon',  textureId = 'rbxassetid://16254848910', lightEmission = 0.4 },
    }

    local tg = Instance.new('ScreenGui')
    tg.Name          = 'TrailSettingsGui'
    tg.ResetOnSpawn  = false
    tg.DisplayOrder  = 998
    tg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    tg.Enabled       = false
    tg.Parent        = plr.PlayerGui
    trailGui         = tg

    local panel = Instance.new('Frame')
    panel.Size             = UDim2.new(0, 360, 0, 430)
    panel.Position         = UDim2.new(0.5, -460, 0.5, -215)
    panel.BackgroundColor3 = BG2
    panel.BorderSizePixel  = 1
    panel.BorderColor3     = BORDER
    panel.Active           = true
    panel.ZIndex           = 10
    panel.Parent           = tg

    -- drag
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
        game:GetService('UserInputService').InputChanged:Connect(function(inp)
            if drag and inp.UserInputType == Enum.UserInputType.MouseMovement then
                local d = inp.Position - dragStart
                panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                           startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    -- title bar
    local title = Instance.new('Frame')
    title.Size            = UDim2.new(1, 0, 0, 28)
    title.BackgroundColor3 = BGSUB
    title.BorderSizePixel = 0
    title.ZIndex          = 11
    title.Parent          = panel
    local titleLbl = Instance.new('TextLabel')
    titleLbl.Size  = UDim2.new(1, -36, 1, 0)
    titleLbl.Position = UDim2.new(0, 8, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text  = 'Trail Settings'
    titleLbl.TextColor3 = TEXT
    titleLbl.Font  = Enum.Font.GothamBold
    titleLbl.TextSize = 14
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.ZIndex = 12
    titleLbl.Parent = title
    local closeBtn = Instance.new('TextButton')
    closeBtn.Size  = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -28, 0, 0)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text  = 'X'
    closeBtn.TextColor3 = TEXT
    closeBtn.Font  = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.ZIndex = 12
    closeBtn.Parent = title
    closeBtn.MouseButton1Click:Connect(function() tg.Enabled = false end)

    -- helper: row label + value box
    local rowY = 36
    local function makeRow(labelText, default, onChanged)
        local lbl = Instance.new('TextLabel')
        lbl.Size  = UDim2.new(0, 130, 0, 22)
        lbl.Position = UDim2.new(0, 10, 0, rowY)
        lbl.BackgroundTransparency = 1
        lbl.Text  = labelText
        lbl.TextColor3 = TEXT
        lbl.Font  = Enum.Font.Gotham
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 11
        lbl.Parent = panel

        local box = Instance.new('TextBox')
        box.Size  = UDim2.new(0, 160, 0, 22)
        box.Position = UDim2.new(0, 145, 0, rowY)
        box.BackgroundColor3 = BGSUB
        box.BorderColor3     = BORDER
        box.BorderSizePixel  = 1
        box.Text  = tostring(default)
        box.TextColor3 = TEXT
        box.Font  = Enum.Font.Gotham
        box.TextSize = 13
        box.ZIndex = 11
        box.Parent = panel
        box.FocusLost:Connect(function() onChanged(box.Text) end)
        rowY += 28
        return box
    end

    local function makeDivLine()
        local line = Instance.new('Frame')
        line.Size = UDim2.new(1, -20, 0, 1)
        line.Position = UDim2.new(0, 10, 0, rowY + 4)
        line.BackgroundColor3 = BORDER
        line.BorderSizePixel = 0
        line.ZIndex = 11
        line.Parent = panel
        rowY += 14
    end

    -- Type preset buttons
    local typeLbl = Instance.new('TextLabel')
    typeLbl.Size  = UDim2.new(0, 80, 0, 22)
    typeLbl.Position = UDim2.new(0, 10, 0, rowY)
    typeLbl.BackgroundTransparency = 1
    typeLbl.Text  = 'Type:'
    typeLbl.TextColor3 = TEXT
    typeLbl.Font  = Enum.Font.GothamBold
    typeLbl.TextSize = 13
    typeLbl.TextXAlignment = Enum.TextXAlignment.Left
    typeLbl.ZIndex = 11
    typeLbl.Parent = panel
    local presetBtns = {}
    for i, preset in ipairs(TRAIL_PRESETS) do
        local btn = Instance.new('TextButton')
        btn.Size  = UDim2.new(0, 74, 0, 22)
        btn.Position = UDim2.new(0, 70 + (i-1)*80, 0, rowY)
        btn.BackgroundColor3 = BGSUB
        btn.BorderColor3     = BORDER
        btn.BorderSizePixel  = 1
        btn.Text  = preset.name
        btn.TextColor3 = TEXT
        btn.Font  = Enum.Font.Gotham
        btn.TextSize = 12
        btn.ZIndex = 11
        btn.Parent = panel
        presetBtns[i] = btn
        btn.MouseButton1Click:Connect(function()
            trailSettings.textureId     = preset.textureId
            trailSettings.lightEmission = preset.lightEmission
            for _, b in ipairs(presetBtns) do b.BackgroundColor3 = BGSUB end
            btn.BackgroundColor3 = ACCENT
            -- live-apply if trail active
            if _G.ActiveTrail and _G.ActiveTrail.Parent then
                _G.ActiveTrail.Texture       = preset.textureId
                _G.ActiveTrail.LightEmission = preset.lightEmission
            end
        end)
    end
    rowY += 32

    -- Custom Texture ID
    local texBox = makeRow('Texture ID', '', function(v)
        trailSettings.textureId = v
        if _G.ActiveTrail and _G.ActiveTrail.Parent then
            _G.ActiveTrail.Texture = v
        end
    end)

    makeDivLine()

    -- Start Color
    makeRow('Start R', trailSettings.startR, function(v)
        trailSettings.startR = math.clamp(tonumber(v) or 255, 0, 255)
    end)
    makeRow('Start G', trailSettings.startG, function(v)
        trailSettings.startG = math.clamp(tonumber(v) or 215, 0, 255)
    end)
    makeRow('Start B', trailSettings.startB, function(v)
        trailSettings.startB = math.clamp(tonumber(v) or 0, 0, 255)
    end)

    makeDivLine()

    -- End Color
    makeRow('End R', trailSettings.endR, function(v)
        trailSettings.endR = math.clamp(tonumber(v) or 200, 0, 255)
    end)
    makeRow('End G', trailSettings.endG, function(v)
        trailSettings.endG = math.clamp(tonumber(v) or 100, 0, 255)
    end)
    makeRow('End B', trailSettings.endB, function(v)
        trailSettings.endB = math.clamp(tonumber(v) or 0, 0, 255)
    end)

    makeDivLine()

    -- Lifetime & Width
    makeRow('Lifetime (s)', trailSettings.lifetime, function(v)
        local n = math.clamp(tonumber(v) or 0.6, 0.05, 10)
        trailSettings.lifetime = n
        if _G.ActiveTrail and _G.ActiveTrail.Parent then _G.ActiveTrail.Lifetime = n end
    end)
    makeRow('Width (studs)', trailSettings.halfWidth * 2, function(v)
        local n = math.clamp(tonumber(v) or 1, 0.1, 8)
        trailSettings.halfWidth = n / 2
        if _G.TrailAttach0 and _G.TrailAttach0.Parent then
            _G.TrailAttach0.Position = Vector3.new(0,  trailSettings.halfWidth, 0)
            _G.TrailAttach1.Position = Vector3.new(0, -trailSettings.halfWidth, 0)
        end
    end)
    makeRow('Light Emission', trailSettings.lightEmission, function(v)
        local n = math.clamp(tonumber(v) or 0.5, 0, 1)
        trailSettings.lightEmission = n
        if _G.ActiveTrail and _G.ActiveTrail.Parent then _G.ActiveTrail.LightEmission = n end
    end)

    makeDivLine()

    -- Rainbow toggle
    local rbLabel = Instance.new('TextLabel')
    rbLabel.Size  = UDim2.new(0, 130, 0, 22)
    rbLabel.Position = UDim2.new(0, 10, 0, rowY)
    rbLabel.BackgroundTransparency = 1
    rbLabel.Text  = 'Rainbow Trail'
    rbLabel.TextColor3 = TEXT
    rbLabel.Font  = Enum.Font.Gotham
    rbLabel.TextSize = 13
    rbLabel.TextXAlignment = Enum.TextXAlignment.Left
    rbLabel.ZIndex = 11
    rbLabel.Parent = panel
    local rbBtn = Instance.new('TextButton')
    rbBtn.Size  = UDim2.new(0, 80, 0, 22)
    rbBtn.Position = UDim2.new(0, 145, 0, rowY)
    rbBtn.BackgroundColor3 = BGSUB
    rbBtn.BorderColor3     = BORDER
    rbBtn.BorderSizePixel  = 1
    rbBtn.Text  = 'OFF'
    rbBtn.TextColor3 = TEXT
    rbBtn.Font  = Enum.Font.Gotham
    rbBtn.TextSize = 13
    rbBtn.ZIndex = 11
    rbBtn.Parent = panel
    rbBtn.MouseButton1Click:Connect(function()
        trailSettings.rainbow = not trailSettings.rainbow
        if trailSettings.rainbow then
            rbBtn.BackgroundColor3 = ACCENT
            rbBtn.Text = 'ON'
        else
            rbBtn.BackgroundColor3 = BGSUB
            rbBtn.Text = 'OFF'
        end
    end)
end

-- ============================================================
-- BIKE CUSTOMIZATION PANEL
-- ============================================================
do
    local BIKE_MATERIALS = {
        { name = 'Plastic',      mat = Enum.Material.SmoothPlastic },
        { name = 'Metal',        mat = Enum.Material.Metal         },
        { name = 'Neon',         mat = Enum.Material.Neon          },
        { name = 'ForceField',   mat = Enum.Material.ForceField    },
        { name = 'Glass',        mat = Enum.Material.Glass         },
        { name = 'DiamondPlate', mat = Enum.Material.DiamondPlate  },
    }

    local bc = Instance.new('ScreenGui')
    bc.Name           = 'BikeCustGui'
    bc.ResetOnSpawn   = false
    bc.DisplayOrder   = 997
    bc.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    bc.Enabled        = false
    bc.Parent         = plr.PlayerGui
    bikeCustGui       = bc

    local panel = Instance.new('Frame')
    panel.Size             = UDim2.new(0, 380, 0, 520)
    panel.Position         = UDim2.new(0.5, 80, 0.5, -260)
    panel.BackgroundColor3 = BG2
    panel.BorderSizePixel  = 1
    panel.BorderColor3     = BORDER
    panel.Active           = true
    panel.ZIndex           = 10
    panel.Parent           = bc

    -- drag
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
        game:GetService('UserInputService').InputChanged:Connect(function(inp)
            if drag and inp.UserInputType == Enum.UserInputType.MouseMovement then
                local d = inp.Position - dragStart
                panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                           startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    -- title bar
    local titleBar = Instance.new('Frame')
    titleBar.Size             = UDim2.new(1, 0, 0, 28)
    titleBar.BackgroundColor3 = BGSUB
    titleBar.BorderSizePixel  = 0
    titleBar.ZIndex           = 11
    titleBar.Parent           = panel
    local titleLbl2 = Instance.new('TextLabel')
    titleLbl2.Size                   = UDim2.new(1, -36, 1, 0)
    titleLbl2.Position               = UDim2.new(0, 8, 0, 0)
    titleLbl2.BackgroundTransparency = 1
    titleLbl2.Text                   = 'Bike Customization'
    titleLbl2.TextColor3             = TEXT
    titleLbl2.Font                   = Enum.Font.GothamBold
    titleLbl2.TextSize               = 14
    titleLbl2.TextXAlignment         = Enum.TextXAlignment.Left
    titleLbl2.ZIndex                 = 12
    titleLbl2.Parent                 = titleBar
    local closeBtn2 = Instance.new('TextButton')
    closeBtn2.Size             = UDim2.new(0, 28, 0, 28)
    closeBtn2.Position         = UDim2.new(1, -28, 0, 0)
    closeBtn2.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeBtn2.BorderSizePixel  = 0
    closeBtn2.Text             = 'X'
    closeBtn2.TextColor3       = TEXT
    closeBtn2.Font             = Enum.Font.GothamBold
    closeBtn2.TextSize         = 13
    closeBtn2.ZIndex           = 12
    closeBtn2.Parent           = titleBar
    closeBtn2.MouseButton1Click:Connect(function() bc.Enabled = false end)

    local rowY2 = 36
    local function makeRow2(labelText, default, onChanged)
        local lbl = Instance.new('TextLabel')
        lbl.Size  = UDim2.new(0, 140, 0, 22)
        lbl.Position = UDim2.new(0, 10, 0, rowY2)
        lbl.BackgroundTransparency = 1
        lbl.Text  = labelText
        lbl.TextColor3 = TEXT
        lbl.Font  = Enum.Font.Gotham
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 11
        lbl.Parent = panel
        local box = Instance.new('TextBox')
        box.Size  = UDim2.new(0, 180, 0, 22)
        box.Position = UDim2.new(0, 155, 0, rowY2)
        box.BackgroundColor3 = BGSUB
        box.BorderColor3     = BORDER
        box.BorderSizePixel  = 1
        box.Text  = tostring(default)
        box.TextColor3 = TEXT
        box.Font  = Enum.Font.Gotham
        box.TextSize = 13
        box.ZIndex = 11
        box.Parent = panel
        box.FocusLost:Connect(function() onChanged(box.Text) end)
        rowY2 += 28
        return box
    end

    local function makeDivLine2()
        local line = Instance.new('Frame')
        line.Size             = UDim2.new(1, -20, 0, 1)
        line.Position         = UDim2.new(0, 10, 0, rowY2 + 4)
        line.BackgroundColor3 = BORDER
        line.BorderSizePixel  = 0
        line.ZIndex           = 11
        line.Parent           = panel
        rowY2 += 14
    end

    local function makeSectionLbl(text)
        local lbl = Instance.new('TextLabel')
        lbl.Size                   = UDim2.new(1, -20, 0, 20)
        lbl.Position               = UDim2.new(0, 10, 0, rowY2)
        lbl.BackgroundTransparency = 1
        lbl.Text                   = text
        lbl.TextColor3             = ACCENT
        lbl.Font                   = Enum.Font.GothamBold
        lbl.TextSize               = 12
        lbl.TextXAlignment         = Enum.TextXAlignment.Left
        lbl.ZIndex                 = 11
        lbl.Parent                 = panel
        rowY2 += 24
    end

    -- helper: apply to all bike parts
    local function applyToBike(fn)
        local bikeModel = getBikeRoot()
        if not bikeModel then showToast('Get on a bike first'); return end
        for _, p in ipairs(bikeModel:GetDescendants()) do
            if p:IsA('BasePart') then pcall(fn, p) end
        end
    end

    -- --- Material presets ---
    makeSectionLbl('Material')
    local matBtns = {}
    local matPerRow = 3
    for i, entry in ipairs(BIKE_MATERIALS) do
        local col = (i - 1) % matPerRow
        local row = math.floor((i - 1) / matPerRow)
        local btn = Instance.new('TextButton')
        btn.Size             = UDim2.new(0, 110, 0, 22)
        btn.Position         = UDim2.new(0, 10 + col * 118, 0, rowY2 + row * 26)
        btn.BackgroundColor3 = BGSUB
        btn.BorderColor3     = BORDER
        btn.BorderSizePixel  = 1
        btn.Text             = entry.name
        btn.TextColor3       = TEXT
        btn.Font             = Enum.Font.Gotham
        btn.TextSize         = 12
        btn.ZIndex           = 11
        btn.Parent           = panel
        matBtns[i]           = btn
        btn.MouseButton1Click:Connect(function()
            for _, b in ipairs(matBtns) do b.BackgroundColor3 = BGSUB end
            btn.BackgroundColor3 = ACCENT
            applyToBike(function(p) p.Material = entry.mat end)
            showToast('Material: ' .. entry.name)
        end)
    end
    rowY2 += math.ceil(#BIKE_MATERIALS / matPerRow) * 26 + 4

    makeDivLine2()

    -- --- Color ---
    makeSectionLbl('Color')
    local colorBoxes = {}
    colorBoxes.r = makeRow2('Red (0-255)', 255, function() end)
    colorBoxes.g = makeRow2('Green (0-255)', 0,   function() end)
    colorBoxes.b = makeRow2('Blue (0-255)', 200,  function() end)

    local applyColorBtn = Instance.new('TextButton')
    applyColorBtn.Size             = UDim2.new(0, 160, 0, 24)
    applyColorBtn.Position         = UDim2.new(0, 10, 0, rowY2)
    applyColorBtn.BackgroundColor3 = BGSUB
    applyColorBtn.BorderColor3     = BORDER
    applyColorBtn.BorderSizePixel  = 1
    applyColorBtn.Text             = 'Apply Color'
    applyColorBtn.TextColor3       = TEXT
    applyColorBtn.Font             = Enum.Font.GothamBold
    applyColorBtn.TextSize         = 13
    applyColorBtn.ZIndex           = 11
    applyColorBtn.Parent           = panel
    applyColorBtn.MouseButton1Click:Connect(function()
        local r = math.clamp(tonumber(colorBoxes.r.Text) or 255, 0, 255)
        local g = math.clamp(tonumber(colorBoxes.g.Text) or 0,   0, 255)
        local b = math.clamp(tonumber(colorBoxes.b.Text) or 200, 0, 255)
        local col = Color3.fromRGB(r, g, b)
        applyToBike(function(p) p.Color = col end)
        showToast(string.format('Color: %d %d %d', r, g, b))
    end)
    rowY2 += 32

    makeDivLine2()

    -- --- Transparency & Reflectance ---
    makeSectionLbl('Surface')
    makeRow2('Transparency (0-1)', 0, function(v)
        local n = math.clamp(tonumber(v) or 0, 0, 0.99)
        applyToBike(function(p) p.Transparency = n end)
    end)
    makeRow2('Reflectance (0-1)', 0, function(v)
        local n = math.clamp(tonumber(v) or 0, 0, 1)
        applyToBike(function(p) p.Reflectance = n end)
    end)

    makeDivLine2()

    -- --- Headlight ---
    makeSectionLbl('Headlight')
    local _bikeLight = nil
    local hlBrightnessBox = makeRow2('Brightness', 5, function() end)
    local hlRangeBox      = makeRow2('Range (studs)', 40, function() end)

    local hlToggleBtn = Instance.new('TextButton')
    hlToggleBtn.Size             = UDim2.new(0, 160, 0, 24)
    hlToggleBtn.Position         = UDim2.new(0, 10, 0, rowY2)
    hlToggleBtn.BackgroundColor3 = BGSUB
    hlToggleBtn.BorderColor3     = BORDER
    hlToggleBtn.BorderSizePixel  = 1
    hlToggleBtn.Text             = 'Headlight: OFF'
    hlToggleBtn.TextColor3       = TEXT
    hlToggleBtn.Font             = Enum.Font.GothamBold
    hlToggleBtn.TextSize         = 13
    hlToggleBtn.ZIndex           = 11
    hlToggleBtn.Parent           = panel
    hlToggleBtn.MouseButton1Click:Connect(function()
        if _bikeLight and _bikeLight.Parent then
            _bikeLight:Destroy(); _bikeLight = nil
            hlToggleBtn.BackgroundColor3 = BGSUB
            hlToggleBtn.Text = 'Headlight: OFF'
            showToast('Headlight OFF')
        else
            local _, bikeRoot = getBikeRoot()
            if not bikeRoot then showToast('Get on a bike first'); return end
            local pl = Instance.new('PointLight')
            pl.Brightness = math.max(0.1, tonumber(hlBrightnessBox.Text) or 5)
            pl.Range      = math.max(1,   tonumber(hlRangeBox.Text)      or 40)
            pl.Color      = Color3.fromRGB(255, 240, 200)
            pl.Parent     = bikeRoot
            _bikeLight    = pl
            hlToggleBtn.BackgroundColor3 = ACCENT
            hlToggleBtn.Text = 'Headlight: ON'
            showToast('Headlight ON')
        end
    end)
    rowY2 += 32

    makeDivLine2()

    -- --- Exhaust Smoke ---
    makeSectionLbl('Exhaust Smoke')
    local _bikeSmoke = nil

    local smokeToggleBtn = Instance.new('TextButton')
    smokeToggleBtn.Size             = UDim2.new(0, 160, 0, 24)
    smokeToggleBtn.Position         = UDim2.new(0, 10, 0, rowY2)
    smokeToggleBtn.BackgroundColor3 = BGSUB
    smokeToggleBtn.BorderColor3     = BORDER
    smokeToggleBtn.BorderSizePixel  = 1
    smokeToggleBtn.Text             = 'Smoke: OFF'
    smokeToggleBtn.TextColor3       = TEXT
    smokeToggleBtn.Font             = Enum.Font.GothamBold
    smokeToggleBtn.TextSize         = 13
    smokeToggleBtn.ZIndex           = 11
    smokeToggleBtn.Parent           = panel
    smokeToggleBtn.MouseButton1Click:Connect(function()
        if _bikeSmoke and _bikeSmoke.Parent then
            _bikeSmoke:Destroy(); _bikeSmoke = nil
            smokeToggleBtn.BackgroundColor3 = BGSUB
            smokeToggleBtn.Text = 'Smoke: OFF'
            showToast('Smoke OFF')
        else
            local _, bikeRoot = getBikeRoot()
            if not bikeRoot then showToast('Get on a bike first'); return end
            local sm = Instance.new('Smoke')
            sm.Color      = Color3.fromRGB(180, 180, 180)
            sm.Opacity    = 0.3
            sm.RiseVelocity = 4
            sm.Size       = 2
            sm.Parent     = bikeRoot
            _bikeSmoke    = sm
            smokeToggleBtn.BackgroundColor3 = ACCENT
            smokeToggleBtn.Text = 'Smoke: ON'
            showToast('Smoke ON')
        end
    end)
    rowY2 += 32

    -- Reset button
    makeDivLine2()
    local resetBtn = Instance.new('TextButton')
    resetBtn.Size             = UDim2.new(1, -20, 0, 24)
    resetBtn.Position         = UDim2.new(0, 10, 0, rowY2)
    resetBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
    resetBtn.BorderColor3     = BORDER
    resetBtn.BorderSizePixel  = 1
    resetBtn.Text             = 'Reset Appearance'
    resetBtn.TextColor3       = TEXT
    resetBtn.Font             = Enum.Font.GothamBold
    resetBtn.TextSize         = 13
    resetBtn.ZIndex           = 11
    resetBtn.Parent           = panel
    resetBtn.MouseButton1Click:Connect(function()
        applyToBike(function(p)
            p.Material     = Enum.Material.SmoothPlastic
            p.Transparency = 0
            p.Reflectance  = 0
        end)
        for _, b in ipairs(matBtns) do b.BackgroundColor3 = BGSUB end
        showToast('Appearance reset')
    end)

    -- resize panel to fit content
    panel.Size = UDim2.new(0, 380, 0, rowY2 + 40)
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
minimapGui.DisplayOrder   = 200
minimapGui.Enabled        = false
minimapGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
minimapGui.Parent         = plr.PlayerGui

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

    -- disconnect all RunService connections
    for _, key in ipairs({'SpeedConn', 'BrakeConn', 'TurnConn', 'AnimConn', 'HitboxConn',
                          'AntiAdminConn', 'OptimizerConn',
                          'FlyConn', 'AntiFallConn', 'AirConn',
                          'RainbowConn', 'TrailColorConn',
                          'AdminESPConn', 'BikeESPConn', 'SpeedTagConn', 'SpeedTagLeaveConn',
                          'JumpKeyConn',
                          'RideoutLeaderConn', 'RideoutFollowConn', 'RideoutHUDConn',
                          'RideoutWPUpdateConn', 'OwnershipConn'}) do
        if _G[key] then
            pcall(function() _G[key]:Disconnect() end)
            _G[key] = nil
        end
    end

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

    -- cleanup bike trail
    pcall(function() if _G.TrailAttach0 then _G.TrailAttach0:Destroy() end end)
    pcall(function() if _G.TrailAttach1 then _G.TrailAttach1:Destroy() end end)
    pcall(function() if _G.ActiveTrail   then _G.ActiveTrail:Destroy()  end end)

    -- cleanup ESP overlays
    pcall(clearAdminESP)
    pcall(clearBikeESP)
    pcall(clearSpeedTags)

    -- cleanup rideout
    pcall(_cleanLeaderESP)
    pcall(_cleanLeaderTrail)
    pcall(_cleanOwnership)
    pcall(_clearRideoutWPs)
    pcall(function() if _rideoutHudGui    then _rideoutHudGui:Destroy()    end end)
    pcall(function() if _ownershipHudGui  then _ownershipHudGui:Destroy()  end end)
    pcall(function() if rideoutWpGui      then rideoutWpGui:Destroy()      end end)
    pcall(function() if _G.RideoutTrailA0 then _G.RideoutTrailA0:Destroy() end end)
    pcall(function() if _G.RideoutTrailA1 then _G.RideoutTrailA1:Destroy() end end)
    pcall(function() if _G.RideoutTrail   then _G.RideoutTrail:Destroy()   end end)

    -- unfreeze bike if still frozen
    if _G.FrozenBikeParts then
        for p in pairs(_G.FrozenBikeParts) do
            pcall(function() p.Anchored = false end)
        end
        _G.FrozenBikeParts = nil
    end

    -- destroy ScreenGuis this script owns
    pcall(function() gui:Destroy() end)
    pcall(function() minimapGui:Destroy() end)

    -- destroy LinoriaLib window
    pcall(function() Library.ScreenGui:Destroy() end)
end
