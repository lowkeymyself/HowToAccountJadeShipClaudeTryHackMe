local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
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
pcall(function()
    Library.ScreenGui.DisplayOrder = 999
    Library.ScreenGui.Parent = CoreGui
end)

local Tabs = {
    Main     = Window:AddTab('Main'),
    Troll    = Window:AddTab('Troll'),
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

BikeLeft:AddToggle('AutoFixBike', {
    Text = 'Auto-fix Bike',
    Default = false,
    Callback = function(val)
        local function isWheelPart(p)
            local n = p.Name:lower()
            return n:find('wheel') or n:find('tire') or n:find('tyre') or n:find('rim') or n:find('hub')
        end

        local function findBackWheel(model, seat)
            local backWheel, bestZ = nil, math.huge
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA('BasePart') and isWheelPart(p) then
                    local lz = seat.CFrame:ToObjectSpace(CFrame.new(p.Position)).Z
                    if lz < bestZ then bestZ = lz; backWheel = p end
                end
            end
            return backWheel
        end

        local function findProximityPrompt(model)
            for _, v in ipairs(model:GetDescendants()) do
                if v:IsA('ProximityPrompt') then return v end
            end
            return nil
        end

        local function gearText()
            for _, v in ipairs(plr.PlayerGui:GetDescendants()) do
                if v:IsA('TextLabel') and v.Visible
                and (v.Text == '-' or v.Text == 'N') then
                    return v.Text
                end
            end
            return nil
        end

        local function eject(seat, hum)
            pcall(function() seat.Disabled = true end)
            task.wait(0.05)
            pcall(function() seat.Disabled = false end)
            if hum.SeatPart ~= nil then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
        end

        local function ejectAndRemount(seat, hum, pp)
            eject(seat, hum)
            task.wait(0.1)
            if pp then pcall(function() fireproximityprompt(pp) end)
            else pcall(function() seat:Sit(hum) end) end
        end

        local fixInProgress = {}

        local function setupFixWatcher(char)
            if _G.AutoFixSeatConn then _G.AutoFixSeatConn:Disconnect(); _G.AutoFixSeatConn = nil end
            local hum = char and char:FindFirstChildWhichIsA('Humanoid')
            if not hum then return end
            _G.AutoFixSeatConn = hum:GetPropertyChangedSignal('SeatPart'):Connect(function()
                local seat = hum.SeatPart
                if not seat or not seat:IsA('VehicleSeat') then return end
                if fixInProgress[seat] then return end
                fixInProgress[seat] = true

                local backWheel = findBackWheel(seat.Parent, seat)
                local snapCF    = backWheel and backWheel.CFrame
                local pp        = findProximityPrompt(seat.Parent)

                task.spawn(function()
                    if backWheel and snapCF then
                        local elapsed = 0
                        local lockConn; lockConn = RunService.Heartbeat:Connect(function(dt)
                            elapsed += dt
                            if elapsed > 0.8 or hum.SeatPart ~= seat then
                                lockConn:Disconnect(); return
                            end
                            pcall(function() backWheel.CFrame = snapCF end)
                        end)
                    end

                    local deadline = tick() + 2
                    while tick() < deadline do
                        if hum.SeatPart ~= seat then fixInProgress[seat] = nil; return end
                        if gearText() then break end
                        RunService.Heartbeat:Wait()
                    end
                    if hum.SeatPart ~= seat then fixInProgress[seat] = nil; return end

                    for attempt = 1, 5 do
                        if hum.SeatPart ~= seat then break end
                        local g = gearText()
                        if g == 'N' then
                            if attempt > 1 then showToast('Bike fixed (attempt ' .. attempt .. ')') end
                            break
                        end
                        if g ~= '-' then break end
                        ejectAndRemount(seat, hum, pp)
                        task.wait(0.5)
                    end

                    fixInProgress[seat] = nil
                end)
            end)
        end

        if val then
            setupFixWatcher(plr.Character)
            _G.AutoFixCharConn = plr.CharacterAdded:Connect(function(char)
                task.wait(1)
                setupFixWatcher(char)
            end)
            showToast('Auto-fix Bike ON')
        else
            if _G.AutoFixSeatConn then _G.AutoFixSeatConn:Disconnect(); _G.AutoFixSeatConn = nil end
            if _G.AutoFixCharConn then _G.AutoFixCharConn:Disconnect(); _G.AutoFixCharConn = nil end
            showToast('Auto-fix Bike OFF')
        end
    end
})

BikeLeft:AddDivider()

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

local clonedBikes = {}

BikeLeft:AddButton({
    Text = 'Clone Bike',
    Func = function()
        local char = plr.Character
        local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
        if not hum or not hum.SeatPart then showToast('Not on a bike'); return end
        local model = hum.SeatPart.Parent
        local clone = model:Clone()
        clone:PivotTo(model:GetPivot() * CFrame.new((#clonedBikes + 1) * 10, 0, 0))
        clone.Parent = workspace
        table.insert(clonedBikes, clone)
        showToast('Bike cloned (' .. #clonedBikes .. ' clones)')
    end
})

BikeLeft:AddButton({
    Text = 'Clear Cloned Bikes',
    Func = function()
        for _, b in ipairs(clonedBikes) do pcall(function() b:Destroy() end) end
        clonedBikes = {}
        showToast('Cloned bikes cleared')
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

BikeLeft:AddInput('WheelieStrength', {
    Default = '8',
    Numeric = true,
    Finished = false,
    Text = 'Wheelie Strength (rad/s)',
})

BikeLeft:AddToggle('WheelieBoost', {
    Text = 'Wheelie Boost (hold C)',
    Default = false,
    Callback = function(val)
        if val then
            _G.WheelieConn = RunService.Heartbeat:Connect(function()
                if not UIS:IsKeyDown(Enum.KeyCode.C) then return end
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not seat or not seat:IsA('VehicleSeat') then return end
                local strength = tonumber(Options.WheelieStrength.Value) or 8
                local rv  = seat.CFrame.RightVector
                local cur = seat.AssemblyAngularVelocity
                seat.AssemblyAngularVelocity = cur + rv * (strength - cur:Dot(rv))
            end)
            showToast('Wheelie Boost ON — hold C')
        else
            if _G.WheelieConn then _G.WheelieConn:Disconnect(); _G.WheelieConn = nil end
            showToast('Wheelie Boost OFF')
        end
    end
})

BikeLeft:AddToggle('WheelieLock', {
    Text = 'Wheelie Lock (V to lock/unlock)',
    Default = false,
    Callback = function(val)
        if val then
            local locked = false
            local lockedPitchY = 0

            _G.WheelieVConn = UIS.InputBegan:Connect(function(input, gp)
                if gp or input.KeyCode ~= Enum.KeyCode.V then return end
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not seat or not seat:IsA('VehicleSeat') then return end
                if locked then
                    locked = false
                    showToast('Wheelie angle unlocked')
                else
                    lockedPitchY = seat.CFrame.LookVector.Y
                    locked = true
                    showToast('Wheelie angle locked')
                end
            end)

            _G.WheelieLocConn = RunService.Heartbeat:Connect(function()
                if not locked then return end
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not seat or not seat:IsA('VehicleSeat') then return end
                local err = lockedPitchY - seat.CFrame.LookVector.Y
                local rv  = seat.CFrame.RightVector
                local cur = seat.AssemblyAngularVelocity
                local correction = math.clamp(err * 15, -12, 12)
                seat.AssemblyAngularVelocity = cur + rv * (correction - cur:Dot(rv))
            end)

            showToast('Wheelie Lock ON — press V to lock angle')
        else
            if _G.WheelieVConn   then _G.WheelieVConn:Disconnect();   _G.WheelieVConn   = nil end
            if _G.WheelieLocConn then _G.WheelieLocConn:Disconnect(); _G.WheelieLocConn = nil end
            showToast('Wheelie Lock OFF')
        end
    end
})

BikeLeft:AddInput('StoppieStrength', {
    Default = '8',
    Numeric = true,
    Finished = false,
    Text = 'Stoppie Strength (rad/s)',
})

BikeLeft:AddToggle('StoppieBoost', {
    Text = 'Stoppie (hold ,)',
    Default = false,
    Callback = function(val)
        if val then
            _G.StoppieConn = RunService.Heartbeat:Connect(function()
                if not UIS:IsKeyDown(Enum.KeyCode.Comma) then return end
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not seat or not seat:IsA('VehicleSeat') then return end
                local strength = tonumber(Options.StoppieStrength.Value) or 8
                local rv  = seat.CFrame.RightVector
                local cur = seat.AssemblyAngularVelocity
                seat.AssemblyAngularVelocity = cur + rv * (-strength - cur:Dot(rv))
            end)
            showToast('Stoppie ON — hold ,')
        else
            if _G.StoppieConn then _G.StoppieConn:Disconnect(); _G.StoppieConn = nil end
            showToast('Stoppie OFF')
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
                if not seat or not seat:IsA('VehicleSeat') then return end
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
                if not seat or not seat:IsA('VehicleSeat') then return end
                local rv  = seat.CFrame.RightVector
                local av  = seat.AssemblyAngularVelocity
                seat.AssemblyAngularVelocity = rv * av:Dot(rv)
            end)

            showToast('No Wobble ON — press N to lock/release')
        else
            if _G.NoWobbleKeyConn then _G.NoWobbleKeyConn:Disconnect(); _G.NoWobbleKeyConn = nil end
            if _G.NoWobbleConn    then _G.NoWobbleConn:Disconnect();    _G.NoWobbleConn    = nil end
            showToast('No Wobble OFF')
        end
    end
})

BikeLeft:AddDivider()

BikeLeft:AddInput('AnimSpeedInput', {
    Default = '1.0',
    Numeric = true,
    Finished = false,
    Text = 'Anim Speed (multiplier)',
})

BikeLeft:AddToggle('AnimTweaks', {
    Text = 'Anim Tweaks (bike only)',
    Default = false,
    Callback = function(val)
        if val then
            _G.AnimConn = RunService.Heartbeat:Connect(function()
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not seat or not seat:IsA('VehicleSeat') then return end
                local animator = hum:FindFirstChildWhichIsA('Animator')
                if not animator then return end
                local speed = tonumber(Options.AnimSpeedInput.Value) or 1.0
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
local bikeCustGui   = nil  -- assigned when bike customization panel is built below
local partPickerGui = nil  -- assigned when part picker panel is built below

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
            _G.FlyConn = RunService.Heartbeat:Connect(function()
                local char = plr.Character
                local hum  = char and char:FindFirstChildWhichIsA('Humanoid')
                if not hum then return end
                local seat = hum.SeatPart
                if not seat then return end
                local cam   = workspace.CurrentCamera
                local speed = (tonumber(Options.FlySpeedInput.Value) or 60) * 1.6
                local fwd   = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
                if fwd.Magnitude > 0.001 then fwd = fwd.Unit end
                local right = cam.CFrame.RightVector
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
                if math.abs(roll) < 0.06 then return end  -- dead zone (~3 deg), don't touch physics
                -- rebuild CFrame preserving LookVector (carries yaw + pitch), zero roll only
                local lv    = cf.LookVector
                local right = lv:Cross(Vector3.new(0, 1, 0))
                if right.Magnitude < 0.05 then return end  -- near-vertical edge case
                right = right.Unit
                local newUp = right:Cross(lv).Unit
                -- proportional lerp: gentle when barely tilted, stronger as bike tips
                local alpha = math.clamp(math.abs(roll) * 0.4, 0.03, 0.22)
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

Right:AddDivider()

Right:AddInput('FovInput', {
    Default = '70',
    Numeric = true,
    Finished = false,
    Text = 'FOV',
})

Right:AddButton({
    Text = 'Apply FOV',
    Func = function()
        local fov = math.clamp(tonumber(Options.FovInput.Value) or 70, 1, 120)
        workspace.CurrentCamera.FieldOfView = fov
        showToast('FOV set to ' .. fov)
    end
})

Right:AddButton({
    Text = 'Reset FOV',
    Func = function()
        workspace.CurrentCamera.FieldOfView = 70
        showToast('FOV reset to 70')
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
        psg.Parent         = CoreGui

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
if game.PlaceId ~= TARGET_GAME_ID then return end
local isTargetGame = true

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
gui.Parent = CoreGui

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
    tg.Parent        = CoreGui
    trailGui         = tg

    local panel = Instance.new('Frame')
    panel.Size             = UDim2.new(0, 360, 0, 500)
    panel.Position         = UDim2.new(0.5, -460, 0.5, -250)
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
        rowY += 32
        return box
    end

    local function makeDivLine()
        local line = Instance.new('Frame')
        line.Size = UDim2.new(1, -20, 0, 1)
        line.Position = UDim2.new(0, 10, 0, rowY + 6)
        line.BackgroundColor3 = BORDER
        line.BorderSizePixel = 0
        line.ZIndex = 11
        line.Parent = panel
        rowY += 18
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
    rowY += 36

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

    local function isWheelPart(p)
        local n = p.Name:lower()
        return n:find('wheel') or n:find('tire') or n:find('tyre')
            or n:find('rim') or n:find('hub')
    end

    local function applySA(p, saFn)
        if not saFn then return end
        local sa = p:FindFirstChildOfClass('SurfaceAppearance')
        if sa then pcall(saFn, sa) end
    end

    local function applyToAll(fn, saFn)
        local model = getTargetModel()
        if not model then showToast('Not on a bike'); return end
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA('BasePart') then
                pcall(fn, p)
                applySA(p, saFn)
            end
        end
    end

    local function applyToWheels(fn, saFn)
        local model = getTargetModel()
        if not model then showToast('Not on a bike'); return end
        local parts = {}
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA('BasePart') and isWheelPart(p) then
                table.insert(parts, p)
            end
        end
        if #parts == 0 then
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA('Part') and p.Shape == Enum.PartType.Cylinder then
                    table.insert(parts, p)
                end
            end
        end
        for _, p in ipairs(parts) do
            pcall(fn, p)
            applySA(p, saFn)
        end
    end

    local function applyToBody(fn, saFn)
        local model = getTargetModel()
        if not model then showToast('Not on a bike'); return end
        local wheelSet = {}
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA('BasePart') and isWheelPart(p) then wheelSet[p] = true end
        end
        local hasNamed = next(wheelSet) ~= nil
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA('BasePart') then
                local skip = hasNamed and wheelSet[p]
                    or (not hasNamed and p:IsA('Part') and p.Shape == Enum.PartType.Cylinder)
                if not skip then
                    pcall(fn, p)
                    applySA(p, saFn)
                end
            end
        end
    end

    local function getBikeRoot()
        local model = getTargetModel()
        if not model then return nil end
        local seat = model:FindFirstChildWhichIsA('VehicleSeat', true)
        return seat or model.PrimaryPart or model:FindFirstChildWhichIsA('BasePart', true)
    end

    local bc = Instance.new('ScreenGui')
    bc.Name           = 'BikeCustGui'
    bc.ResetOnSpawn   = false
    bc.DisplayOrder   = 997
    bc.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    bc.Enabled        = false
    bc.Parent         = CoreGui
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
        local tl = Instance.new('TextLabel')
        tl.Size = UDim2.new(1, -140, 1, 0); tl.Position = UDim2.new(0, 8, 0, 0)
        tl.BackgroundTransparency = 1; tl.Text = 'Bike Customization'
        tl.TextColor3 = TEXT; tl.Font = Enum.Font.GothamBold
        tl.TextSize = 14; tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.ZIndex = 12; tl.Parent = titleBar

        local sl = Instance.new('TextLabel')
        sl.Size = UDim2.new(0, 50, 0, 20); sl.Position = UDim2.new(1, -132, 0.5, -10)
        sl.BackgroundTransparency = 1; sl.Text = 'Scooter'
        sl.TextColor3 = SUBTEXT; sl.Font = Enum.Font.Gotham
        sl.TextSize = 11; sl.TextXAlignment = Enum.TextXAlignment.Right
        sl.ZIndex = 12; sl.Parent = titleBar

        local stb = Instance.new('TextButton')
        stb.Size = UDim2.new(0, 44, 0, 20); stb.Position = UDim2.new(1, -78, 0.5, -10)
        stb.BackgroundColor3 = BGSUB; stb.BorderSizePixel = 1; stb.BorderColor3 = BORDER
        stb.Text = 'OFF'; stb.TextColor3 = SUBTEXT
        stb.Font = Enum.Font.GothamBold; stb.TextSize = 11; stb.ZIndex = 12; stb.Parent = titleBar
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
        cb.Text = 'X'; cb.TextColor3 = TEXT; cb.Font = Enum.Font.GothamBold
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
    local function bcSecHdr(label)
        if _bcOrder > 0 then
            local gap = Instance.new('Frame')
            gap.Size = UDim2.new(1,0,0,6); gap.BackgroundTransparency = 1
            gap.BorderSizePixel = 0; gap.LayoutOrder = bcNext(); gap.ZIndex = 11; gap.Parent = scroll
        end
        local f = Instance.new('Frame')
        f.Size = UDim2.new(1,0,0,28); f.BackgroundColor3 = BGSUB
        f.BorderSizePixel = 0; f.LayoutOrder = bcNext(); f.ZIndex = 11; f.Parent = scroll
        local l = Instance.new('TextLabel')
        l.Size = UDim2.new(1,-10,1,0); l.Position = UDim2.new(0,10,0,0)
        l.BackgroundTransparency = 1; l.Text = label; l.TextColor3 = ACCENT
        l.Font = Enum.Font.GothamBold; l.TextSize = 12
        l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 12; l.Parent = f
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
        l.Font = Enum.Font.Gotham; l.TextSize = 12
        l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 12; l.Parent = par
        return l
    end
    local function bcInp(par, def, x, y, w, h)
        local b = Instance.new('TextBox')
        b.Size = UDim2.new(0,w or 54,0,h or 22); b.Position = UDim2.new(0,x,0,y)
        b.BackgroundColor3 = BGSUB; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = tostring(def or ''); b.TextColor3 = TEXT; b.Font = Enum.Font.Gotham
        b.TextSize = 12; b.ClearTextOnFocus = false; b.ZIndex = 12; b.Parent = par
        return b
    end
    local function bcBtn(par, text, x, y, w, h)
        local b = Instance.new('TextButton')
        b.Size = UDim2.new(0,w or 80,0,h or 22); b.Position = UDim2.new(0,x,0,y)
        b.BackgroundColor3 = BGSUB; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = text; b.TextColor3 = TEXT; b.Font = Enum.Font.Gotham
        b.TextSize = 12; b.ZIndex = 12; b.Parent = par
        return b
    end
    local function bcTog(par, x, y, w, h)
        local b = Instance.new('TextButton')
        b.Size = UDim2.new(0,w or 48,0,h or 22); b.Position = UDim2.new(0,x,0,y)
        b.BackgroundColor3 = BGSUB; b.BorderSizePixel = 1; b.BorderColor3 = BORDER
        b.Text = 'OFF'; b.TextColor3 = SUBTEXT; b.Font = Enum.Font.GothamBold
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
                applyToAll(function(p) p.Material = e[2] end)
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
                applyToAll(function(p) p.Color = c end, function(sa) sa.Color = c end)
                showToast(e[1] .. ' applied')
            end)
        end
    end

    -- ================================================================
    -- CUSTOM COLOR
    -- ================================================================
    do
        bcSecHdr('CUSTOM COLOR')
        do
            local r = bcRow(34)
            bcLbl(r,'All Parts  R:',8,5,86,20)
            local R = bcInp(r,'255',96,4,44,22); bcLbl(r,'G:',144,5,14,20)
            local G = bcInp(r,'255',160,4,44,22); bcLbl(r,'B:',208,5,14,20)
            local B = bcInp(r,'255',224,4,44,22)
            bcBtn(r,'Apply All',274,4,80,22).MouseButton1Click:Connect(function()
                local c = Color3.fromRGB(math.clamp(tonumber(R.Text)or 255,0,255),math.clamp(tonumber(G.Text)or 255,0,255),math.clamp(tonumber(B.Text)or 255,0,255))
                applyToAll(function(p) p.Color=c end, function(sa) sa.Color=c end)
                showToast('Color applied to all parts')
            end)
        end
        do
            local r = bcRow(34)
            bcLbl(r,'Body  R:',8,5,58,20)
            local R = bcInp(r,'255',68,4,44,22); bcLbl(r,'G:',116,5,14,20)
            local G = bcInp(r,'255',132,4,44,22); bcLbl(r,'B:',180,5,14,20)
            local B = bcInp(r,'255',196,4,44,22)
            bcBtn(r,'Apply Body',246,4,90,22).MouseButton1Click:Connect(function()
                local c = Color3.fromRGB(math.clamp(tonumber(R.Text)or 255,0,255),math.clamp(tonumber(G.Text)or 255,0,255),math.clamp(tonumber(B.Text)or 255,0,255))
                applyToBody(function(p) p.Color=c end, function(sa) sa.Color=c end)
                showToast('Body color applied')
            end)
        end
        do
            local r = bcRow(34)
            bcLbl(r,'Wheels R:',8,5,62,20)
            local R = bcInp(r,'255',72,4,44,22); bcLbl(r,'G:',120,5,14,20)
            local G = bcInp(r,'255',136,4,44,22); bcLbl(r,'B:',184,5,14,20)
            local B = bcInp(r,'255',200,4,44,22)
            bcBtn(r,'Apply Wheels',250,4,96,22).MouseButton1Click:Connect(function()
                local c = Color3.fromRGB(math.clamp(tonumber(R.Text)or 255,0,255),math.clamp(tonumber(G.Text)or 255,0,255),math.clamp(tonumber(B.Text)or 255,0,255))
                applyToWheels(function(p) p.Color=c end, function(sa) sa.Color=c end)
                showToast('Wheel color applied')
            end)
        end
        do
            local r = bcRow(34)
            bcLbl(r, 'Select individual parts:', 8, 5, 156, 20)
            bcBtn(r, 'Part Picker', 168, 4, 90, 22).MouseButton1Click:Connect(function()
                if partPickerGui then partPickerGui.Enabled = not partPickerGui.Enabled end
            end)
        end
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
                applyToAll(function(p) p.Transparency=v end); showToast('Transparency: '..v)
            end)
        end
        do
            local r = bcRow(34); bcLbl(r,'Reflectance:',8,5,84,20)
            local inp = bcInp(r,'0',94,4,54,22)
            bcBtn(r,'Apply',154,4,70,22).MouseButton1Click:Connect(function()
                local v = math.clamp(tonumber(inp.Text)or 0,0,1)
                applyToAll(function(p) p.Reflectance=v end); showToast('Reflectance: '..v)
            end)
        end
        do
            local r = bcRow(34); bcLbl(r,'Cast Shadow:',8,5,82,20)
            togBtns.shad = bcTog(r,92,4); bcTogOn(togBtns.shad)
            togBtns.shad.MouseButton1Click:Connect(function()
                togState.shad = not togState.shad
                if togState.shad then bcTogOn(togBtns.shad) else bcTogOff(togBtns.shad) end
                applyToAll(function(p) p.CastShadow=togState.shad end)
            end)
        end
    end

    -- ================================================================
    -- SIZE SCALE
    -- ================================================================
    do
        bcSecHdr('SIZE SCALE')
        local r = bcRow(34); bcLbl(r,'Multiplier:',8,5,74,20)
        local inp = bcInp(r,'1.0',84,4,58,22)
        bcBtn(r,'Apply Scale',148,4,96,22).MouseButton1Click:Connect(function()
            local mult = tonumber(inp.Text) or 1.0
            if mult <= 0 then showToast('Invalid scale'); return end
            local model = getTargetModel()
            if not model then showToast('Not on a bike'); return end
            local parts = {}
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA('BasePart') then table.insert(parts, p) end
            end
            if #parts == 0 then return end
            local cx,cy,cz = 0,0,0
            for _, p in ipairs(parts) do cx=cx+p.Position.X; cy=cy+p.Position.Y; cz=cz+p.Position.Z end
            local n = #parts
            local cen = Vector3.new(cx/n,cy/n,cz/n)
            for _, p in ipairs(parts) do
                pcall(function() local off=p.Position-cen; p.Size=p.Size*mult; p.Position=cen+off*mult end)
            end
            showToast('Scale x'..mult..' applied')
        end)
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
    do -- spotlights
        local r0 = bcRow(34); bcLbl(r0,'Spotlight Br:',8,5,84,20)
        local spBr = bcInp(r0,'3',94,4,40,22); bcLbl(r0,'Rng:',138,5,32,20)
        local spRg = bcInp(r0,'20',172,4,40,22); bcLbl(r0,'Ang:',216,5,32,20)
        local spAng = bcInp(r0,'90',250,4,40,22)
        local r1 = bcRow(34); bcLbl(r1,'Spotlights:',8,5,74,20)
        togBtns.sp = bcTog(r1,84,4)
        togBtns.sp.MouseButton1Click:Connect(function()
            togState.sp = not togState.sp
            if togState.sp then
                bcTogOn(togBtns.sp)
                for _, s in ipairs(effInst.spotlights) do pcall(function() s:Destroy() end) end
                effInst.spotlights = {}
                local model = getTargetModel()
                if model then
                    local wh = {}
                    for _, p in ipairs(model:GetDescendants()) do
                        if p:IsA('BasePart') and isWheelPart(p) then table.insert(wh,p) end
                    end
                    if #wh == 0 then
                        for _, p in ipairs(model:GetDescendants()) do
                            if p:IsA('Part') and p.Shape==Enum.PartType.Cylinder then table.insert(wh,p) end
                        end
                    end
                    for _, p in ipairs(wh) do
                        local sl = Instance.new('SpotLight')
                        sl.Brightness=math.clamp(tonumber(spBr.Text)or 3,0,10)
                        sl.Range=math.clamp(tonumber(spRg.Text)or 20,0,60)
                        sl.Angle=math.clamp(tonumber(spAng.Text)or 90,0,180)
                        sl.Face=Enum.NormalId.Bottom; sl.Parent=p
                        table.insert(effInst.spotlights, sl)
                    end
                end
            else
                bcTogOff(togBtns.sp)
                for _, s in ipairs(effInst.spotlights) do pcall(function() s:Destroy() end) end
                effInst.spotlights = {}
            end
        end)
    end
    do -- neon glow
        local r = bcRow(34); bcLbl(r,'Neon Glow (all):',8,5,110,20)
        togBtns.ng = bcTog(r,120,4)
        togBtns.ng.MouseButton1Click:Connect(function()
            togState.ng = not togState.ng
            if togState.ng then
                bcTogOn(togBtns.ng); applyToAll(function(p) p.Material=Enum.Material.Neon end)
            else
                bcTogOff(togBtns.ng); applyToAll(function(p) p.Material=Enum.Material.SmoothPlastic end)
            end
        end)
    end

    -- ================================================================
    -- RESET
    -- ================================================================
    do
        bcSecHdr('RESET')
        local r = bcRow(40)
        local rstBtn = bcBtn(r,'Reset All Appearance',8,8,200,24)
        rstBtn.BackgroundColor3 = Color3.fromRGB(160,40,40)
        rstBtn.Font = Enum.Font.GothamBold
        rstBtn.MouseButton1Click:Connect(function()
            applyToAll(function(p)
                p.Material=Enum.Material.SmoothPlastic; p.Transparency=0
                p.Reflectance=0; p.CastShadow=true
            end)
            local model = getTargetModel()
            if model then
                for _, d in ipairs(model:GetDescendants()) do
                    if d:IsA('PointLight') or d:IsA('SpotLight') or d:IsA('SurfaceLight') then
                        pcall(function() d:Destroy() end)
                    end
                end
            end
            effInst.headlight=nil; effInst.spotlights={}
            for k in pairs(togState) do togState[k]=false end
            togState.shad=true
            for _, btn in pairs(togBtns) do pcall(bcTogOff,btn) end
            bcTogOn(togBtns.shad)
            for _, mb in ipairs(matBtns) do mb.BackgroundColor3=BGSUB end
            showToast('All appearance reset')
        end)
    end

    -- ================================================================
    -- CONFIGS
    -- ================================================================
    do
        bcSecHdr('CONFIGS')

        local CFG_FILE = 'Konstant/bike_appearance_configs.json'

        local function cfgSerialize(tbl)
            -- Color3 -> array, Enum -> string
            local out = {}
            for name, partData in pairs(tbl) do
                local pd = {}
                for k, v in pairs(partData) do
                    if typeof(v) == 'Color3' then
                        pd[k] = { _c3 = true, r = v.R, g = v.G, b = v.B }
                    elseif typeof(v) == 'EnumItem' then
                        pd[k] = { _enum = true, v = tostring(v) }
                    else
                        pd[k] = v
                    end
                end
                out[name] = pd
            end
            return game:GetService('HttpService'):JSONEncode(out)
        end

        local function cfgDeserialize(json)
            local raw = game:GetService('HttpService'):JSONDecode(json)
            local out = {}
            for name, partData in pairs(raw) do
                local pd = {}
                for k, v in pairs(partData) do
                    if type(v) == 'table' and v._c3 then
                        pd[k] = Color3.new(v.r, v.g, v.b)
                    elseif type(v) == 'table' and v._enum then
                        local ok, enumVal = pcall(function()
                            local parts = v.v:split('.')
                            return Enum[parts[2]][parts[3]]
                        end)
                        pd[k] = ok and enumVal or v.v
                    else
                        pd[k] = v
                    end
                end
                out[name] = pd
            end
            return out
        end

        local function cfgFlushToDisk(tbl)
            if type(writefile) ~= 'function' then return end
            pcall(function()
                if type(makefolder) == 'function' then pcall(makefolder, 'Konstant') end
                writefile(CFG_FILE, cfgSerialize(tbl))
            end)
        end

        local cfgTable   = {}   -- { [name] = { [partName] = {...} } }
        do
            -- load persisted configs from disk on startup
            if type(readfile) == 'function' then
                pcall(function()
                    local content = readfile(CFG_FILE)
                    if content and content ~= '' then
                        cfgTable = cfgDeserialize(content)
                    end
                end)
            end
        end
        local cfgSelName = ''

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
        cfgDdLbl.TextColor3 = SUBTEXT; cfgDdLbl.Font = Enum.Font.Gotham; cfgDdLbl.TextSize = 11
        cfgDdLbl.TextXAlignment = Enum.TextXAlignment.Left
        cfgDdLbl.TextTruncate = Enum.TextTruncate.AtEnd
        cfgDdLbl.ZIndex = 13; cfgDdLbl.Parent = cfgDdBtn

        local cfgDdArrow = Instance.new('TextLabel')
        cfgDdArrow.Size = UDim2.new(0, 20, 1, 0); cfgDdArrow.Position = UDim2.new(1, -20, 0, 0)
        cfgDdArrow.BackgroundTransparency = 1; cfgDdArrow.Text = '▼'
        cfgDdArrow.TextColor3 = SUBTEXT; cfgDdArrow.Font = Enum.Font.Gotham; cfgDdArrow.TextSize = 10
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
                item.Text = '  ' .. name; item.TextColor3 = TEXT
                item.Font = Enum.Font.Gotham; item.TextSize = 11
                item.TextXAlignment = Enum.TextXAlignment.Left
                item.ZIndex = 31; item.Parent = cfgPopup
                item.MouseEnter:Connect(function()
                    if name ~= cfgSelName then item.BackgroundColor3 = BG2 end
                end)
                item.MouseLeave:Connect(function()
                    item.BackgroundColor3 = (name == cfgSelName) and ACCENT or BGSUB
                end)
                item.MouseButton1Click:Connect(function()
                    cfgSelName = name
                    cfgDdLbl.Text = name; cfgDdLbl.TextColor3 = TEXT
                    cfgPopup.Visible = false; cfgPopupOpen = false; cfgDdArrow.Text = '▼'
                    -- refresh highlight
                    for _, c2 in ipairs(cfgPopup:GetChildren()) do
                        if c2:IsA('TextButton') then
                            c2.BackgroundColor3 = (c2.Text:sub(3) == cfgSelName) and ACCENT or BGSUB
                        end
                    end
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
                cfgDdLbl.Text = names[1]; cfgDdLbl.TextColor3 = TEXT
            end
        end

        -- save
        cfgSaveBtn.MouseButton1Click:Connect(function()
            local name = cfgNameInp.Text
            if name == '' then showToast('Enter a config name'); return end
            local model = getTargetModel()
            if not model then showToast('Not on a bike'); return end
            local data = {}
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA('BasePart') then
                    data[p.Name] = {
                        Color        = p.Color,
                        Material     = p.Material,
                        Transparency = p.Transparency,
                        Reflectance  = p.Reflectance,
                        CastShadow   = p.CastShadow,
                    }
                end
            end
            cfgTable[name] = data
            cfgFlushToDisk(cfgTable)
            cfgSelName = name
            cfgDdLbl.Text = name; cfgDdLbl.TextColor3 = TEXT
            showToast('Saved "' .. name .. '"')
        end)

        -- delete
        cfgDelBtn.MouseButton1Click:Connect(function()
            if cfgSelName == '' then showToast('No config selected'); return end
            local deleted = cfgSelName
            cfgTable[cfgSelName] = nil
            cfgFlushToDisk(cfgTable)
            cfgSelName = ''
            cfgDdLbl.Text = 'No configs saved'; cfgDdLbl.TextColor3 = SUBTEXT
            cfgPopup.Visible = false; cfgPopupOpen = false; cfgDdArrow.Text = '▼'
            showToast('Deleted "' .. deleted .. '"')
        end)

        -- load
        cfgLoadBtn.MouseButton1Click:Connect(function()
            if cfgSelName == '' then showToast('No config selected'); return end
            local data = cfgTable[cfgSelName]
            if not data then showToast('Config not found'); return end
            local model = getTargetModel()
            if not model then showToast('Not on a bike'); return end
            local applied = 0
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA('BasePart') and data[p.Name] then
                    local d = data[p.Name]
                    pcall(function()
                        p.Color        = d.Color
                        p.Material     = d.Material
                        p.Transparency = d.Transparency
                        p.Reflectance  = d.Reflectance
                        p.CastShadow   = d.CastShadow
                    end)
                    applied += 1
                end
            end
            showToast('Loaded "' .. cfgSelName .. '" (' .. applied .. ' parts)')
        end)
    end
end

-- ============================================================
-- PART PICKER WINDOW  (Dex-style tree explorer)
-- ============================================================
do
    -- in-game SelectionBoxes; stored in-place so _G ref stays valid
    local ppSelBoxes = {}
    _G.PPSelBoxes    = ppSelBoxes

    local pp = Instance.new('ScreenGui')
    pp.Name           = 'PartPickerGui'
    pp.ResetOnSpawn   = false
    pp.DisplayOrder   = 996
    pp.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pp.Enabled        = false
    pp.Parent         = CoreGui
    partPickerGui     = pp

    local ppanel = Instance.new('Frame')
    ppanel.Size             = UDim2.new(0, 360, 0, 520)
    ppanel.Position         = UDim2.new(0.5, 60, 0.5, -260)
    ppanel.BackgroundColor3 = BG2
    ppanel.BorderSizePixel  = 1
    ppanel.BorderColor3     = BORDER
    ppanel.Active           = true
    ppanel.ZIndex           = 10
    ppanel.Parent           = pp

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
    ppCountLbl.TextColor3 = SUBTEXT; ppCountLbl.Font = Enum.Font.Gotham; ppCountLbl.TextSize = 11
    ppCountLbl.TextXAlignment = Enum.TextXAlignment.Right
    ppCountLbl.ZIndex = 12; ppCountLbl.Parent = ppTBar

    do
        local tl = Instance.new('TextLabel')
        tl.Size = UDim2.new(1, -130, 1, 0); tl.Position = UDim2.new(0, 10, 0, 0)
        tl.BackgroundTransparency = 1; tl.Text = 'Part Picker'
        tl.TextColor3 = TEXT; tl.Font = Enum.Font.GothamBold
        tl.TextSize = 14; tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.ZIndex = 12; tl.Parent = ppTBar

        local xb = Instance.new('TextButton')
        xb.Size = UDim2.new(0, 32, 0, 32); xb.Position = UDim2.new(1, -32, 0, 0)
        xb.BackgroundColor3 = Color3.fromRGB(180, 50, 50); xb.BorderSizePixel = 0
        xb.Text = 'X'; xb.TextColor3 = TEXT; xb.Font = Enum.Font.GothamBold
        xb.TextSize = 13; xb.ZIndex = 12; xb.Parent = ppTBar
        xb.MouseButton1Click:Connect(function()
            -- clear outlines when window is closed
            for k, sb in pairs(ppSelBoxes) do
                pcall(function() sb:Destroy() end); ppSelBoxes[k] = nil
            end
            pp.Enabled = false
        end)
    end

    -- ---- toolbar (30 px) ----
    local ppCtrl = Instance.new('Frame')
    ppCtrl.Size             = UDim2.new(1, 0, 0, 30)
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
        b.Text = text; b.TextColor3 = TEXT; b.Font = Enum.Font.Gotham; b.TextSize = 11
        b.ZIndex = 12; b.Parent = ppCtrl
        return b
    end
    local ppRefreshBtn    = ppToolBtn('↻ Refresh',    4,  82)
    local ppExpandBtn     = ppToolBtn('Expand All',   90,  78)
    local ppCollapseBtn   = ppToolBtn('Collapse All', 172,  88)
    local ppDeselectBtn   = ppToolBtn('Deselect All', 264,  88)

    -- ---- color picker state ----
    local ppPickedColor = Color3.fromRGB(255, 80, 80)
    local ppCPOpen      = false

    -- ---- bottom bar: color swatch + hex + Apply (46 px, anchored to bottom) ----
    local ppBot = Instance.new('Frame')
    ppBot.Size             = UDim2.new(1, 0, 0, 46)
    ppBot.Position         = UDim2.new(0, 0, 1, -46)
    ppBot.BackgroundColor3 = BGSUB
    ppBot.BorderSizePixel  = 0
    ppBot.ZIndex           = 11
    ppBot.Parent           = ppanel

    do -- top border
        local ln = Instance.new('Frame')
        ln.Size = UDim2.new(1, 0, 0, 1); ln.BackgroundColor3 = BORDER
        ln.BorderSizePixel = 0; ln.ZIndex = 12; ln.Parent = ppBot
    end

    -- color swatch (click to open/close color picker)
    local ppSwatch = Instance.new('TextButton')
    ppSwatch.Size = UDim2.new(0, 28, 0, 28); ppSwatch.Position = UDim2.new(0, 8, 0, 9)
    ppSwatch.BackgroundColor3 = ppPickedColor; ppSwatch.BorderSizePixel = 1
    ppSwatch.BorderColor3 = BORDER; ppSwatch.Text = ''
    ppSwatch.ZIndex = 12; ppSwatch.Parent = ppBot

    -- hex readout / quick input
    local ppHexBox = Instance.new('TextBox')
    ppHexBox.Size = UDim2.new(0, 68, 0, 22); ppHexBox.Position = UDim2.new(0, 42, 0, 12)
    ppHexBox.BackgroundColor3 = BG2; ppHexBox.BorderSizePixel = 1; ppHexBox.BorderColor3 = BORDER
    ppHexBox.Text = 'FF5050'; ppHexBox.TextColor3 = TEXT; ppHexBox.Font = Enum.Font.Code
    ppHexBox.TextSize = 11; ppHexBox.ClearTextOnFocus = false
    ppHexBox.ZIndex = 12; ppHexBox.Parent = ppBot

    -- hide / unhide selection
    local ppHideBtn = Instance.new('TextButton')
    ppHideBtn.Size = UDim2.new(0, 40, 0, 28); ppHideBtn.Position = UDim2.new(0, 114, 0, 9)
    ppHideBtn.BackgroundColor3 = BGSUB; ppHideBtn.BorderSizePixel = 1; ppHideBtn.BorderColor3 = BORDER
    ppHideBtn.Text = 'Hide'; ppHideBtn.TextColor3 = TEXT
    ppHideBtn.Font = Enum.Font.Gotham; ppHideBtn.TextSize = 11
    ppHideBtn.ZIndex = 12; ppHideBtn.Parent = ppBot

    local ppUnhideBtn = Instance.new('TextButton')
    ppUnhideBtn.Size = UDim2.new(0, 44, 0, 28); ppUnhideBtn.Position = UDim2.new(0, 158, 0, 9)
    ppUnhideBtn.BackgroundColor3 = BGSUB; ppUnhideBtn.BorderSizePixel = 1; ppUnhideBtn.BorderColor3 = BORDER
    ppUnhideBtn.Text = 'Unhide'; ppUnhideBtn.TextColor3 = TEXT
    ppUnhideBtn.Font = Enum.Font.Gotham; ppUnhideBtn.TextSize = 11
    ppUnhideBtn.ZIndex = 12; ppUnhideBtn.Parent = ppBot

    local ppApplyBtn = Instance.new('TextButton')
    ppApplyBtn.Size = UDim2.new(0, 148, 0, 30); ppApplyBtn.Position = UDim2.new(1, -156, 0, 8)
    ppApplyBtn.BackgroundColor3 = ACCENT; ppApplyBtn.BorderSizePixel = 0
    ppApplyBtn.Text = 'Apply to Selected'; ppApplyBtn.TextColor3 = TEXT
    ppApplyBtn.Font = Enum.Font.GothamBold; ppApplyBtn.TextSize = 12
    ppApplyBtn.ZIndex = 12; ppApplyBtn.Parent = ppBot

    -- ---- tree scroll area ----
    -- layout: 32 (title) + 30 (toolbar) + 1 (line) = 63 top offset; 46 bottom
    local ppScroll = Instance.new('ScrollingFrame')
    ppScroll.Size                  = UDim2.new(1, 0, 1, -(32 + 31 + 46))
    ppScroll.Position              = UDim2.new(0, 0, 0, 32 + 31)
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

    -- ---- tree state ----
    local ppNodeList = {}
    local ppSelCount = 0

    local function ppUpdateCount()
        ppCountLbl.Text = ppSelCount .. ' selected'
    end

    -- recompute row visibility in a single forward pass (parent-before-children order)
    local function ppRecomputeVis()
        for _, n in ipairs(ppNodeList) do
            if n.parentNode == nil then
                n.row.Visible = true
            else
                n.row.Visible = n.parentNode.row.Visible and n.parentNode.expanded
            end
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
            if child:IsA('BasePart') or child:IsA('Model') or child:IsA('Folder') then
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
            arr.TextColor3 = SUBTEXT; arr.Font = Enum.Font.Gotham; arr.TextSize = 10
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
        classLbl.TextColor3 = SUBTEXT; classLbl.Font = Enum.Font.Gotham; classLbl.TextSize = 9
        classLbl.TextXAlignment = Enum.TextXAlignment.Right
        classLbl.TextTruncate = Enum.TextTruncate.AtEnd
        classLbl.ZIndex = 13; classLbl.Parent = row

        -- part name
        local nameLbl = Instance.new('TextLabel')
        nameLbl.Size = UDim2.new(1, -(indent + 30 + 72), 1, 0)
        nameLbl.Position = UDim2.new(0, indent + 30, 0, 0)
        nameLbl.BackgroundTransparency = 1; nameLbl.Text = inst.Name
        nameLbl.TextColor3 = TEXT
        nameLbl.Font = Enum.Font.Gotham; nameLbl.TextSize = 12
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
            else
                -- No Ctrl: select only this node
                ppDeselectAll()
                ppSetSel(n, true)
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

    local function ppBuildTree()
        ppClearTree()
        local model = ppGetRootModel()
        if not model then showToast('Not on a bike'); return end
        ppAddNode(model, 0, nil)
        ppRecomputeVis()
        showToast('Tree: ' .. #ppNodeList .. ' nodes')
    end

    ppRefreshBtn.MouseButton1Click:Connect(ppBuildTree)

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

    -- ================================================================
    -- COLOR PICKER POPUP
    -- ================================================================
    do
        local cpGui = Instance.new('ScreenGui')
        cpGui.Name           = 'PPColorPickerGui'
        cpGui.ResetOnSpawn   = false
        cpGui.DisplayOrder   = 999
        cpGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        cpGui.Enabled        = false
        cpGui.Parent         = CoreGui

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
        cpTitle.TextColor3 = TEXT; cpTitle.Font = Enum.Font.GothamBold; cpTitle.TextSize = 12
        cpTitle.TextXAlignment = Enum.TextXAlignment.Left; cpTitle.ZIndex = 22; cpTitle.Parent = cpTBar

        local cpXBtn = Instance.new('TextButton')
        cpXBtn.Size = UDim2.new(0, 26, 0, 26); cpXBtn.Position = UDim2.new(1, -26, 0, 0)
        cpXBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50); cpXBtn.BorderSizePixel = 0
        cpXBtn.Text = 'X'; cpXBtn.TextColor3 = TEXT; cpXBtn.Font = Enum.Font.GothamBold
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
            ppSwatch.BackgroundColor3 = c
            ppHexBox.Text = hex
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
        ppHexBox.FocusLost:Connect(function()
            local hex = ppHexBox.Text:match('^#?(%x%x%x%x%x%x)$')
            if hex then
                local r = tonumber(hex:sub(1,2), 16) / 255
                local g = tonumber(hex:sub(3,4), 16) / 255
                local b = tonumber(hex:sub(5,6), 16) / 255
                local h, s, v = Color3.new(r, g, b):ToHSV()
                cpSetHSV(h, s, v)
            end
        end)

        -- swatch toggle
        ppSwatch.MouseButton1Click:Connect(function()
            ppCPOpen = not ppCPOpen
            cpGui.Enabled = ppCPOpen
        end)
    end

    ppApplyBtn.MouseButton1Click:Connect(function()
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

    -- hide / unhide selected parts; ppOrigTrans caches pre-hide values per BasePart
    local ppOrigTrans = {}
    ppHideBtn.MouseButton1Click:Connect(function()
        local n = 0
        for _, node in ipairs(ppNodeList) do
            if node.selected then
                local parts = {}
                if node.instance:IsA('BasePart') then
                    parts[#parts+1] = node.instance
                else
                    for _, desc in ipairs(node.instance:GetDescendants()) do
                        if desc:IsA('BasePart') then parts[#parts+1] = desc end
                    end
                end
                for _, p in ipairs(parts) do
                    if not ppOrigTrans[p] then ppOrigTrans[p] = p.Transparency end
                    pcall(function() p.Transparency = 1 end)
                end
                n += 1
            end
        end
        if n == 0 then showToast('No parts selected') else showToast('Hidden (' .. n .. ' node(s))') end
    end)
    ppUnhideBtn.MouseButton1Click:Connect(function()
        local n = 0
        for _, node in ipairs(ppNodeList) do
            if node.selected then
                local parts = {}
                if node.instance:IsA('BasePart') then
                    parts[#parts+1] = node.instance
                else
                    for _, desc in ipairs(node.instance:GetDescendants()) do
                        if desc:IsA('BasePart') then parts[#parts+1] = desc end
                    end
                end
                for _, p in ipairs(parts) do
                    local orig = ppOrigTrans[p]
                    pcall(function() p.Transparency = orig or 0 end)
                    ppOrigTrans[p] = nil
                end
                n += 1
            end
        end
        if n == 0 then showToast('No parts selected') else showToast('Unhidden (' .. n .. ' node(s))') end
    end)

    -- expose cleanup so SMCleanup can clear in-game outlines on reload
    _G.PPCleanup = ppClearSelBoxes
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
minimapGui.Parent         = CoreGui

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
    if _G.OptimizerCleanup then pcall(_G.OptimizerCleanup); _G.OptimizerCleanup = nil end

    -- disconnect all RunService connections
    for _, key in ipairs({'SpeedConn', 'BrakeConn', 'TurnConn', 'AnimConn', 'HitboxConn',
                          'WheelieConn', 'WheelieVConn', 'WheelieLocConn',
                          'StoppieConn', 'CruiseConn',
                          'NoWobbleConn', 'NoWobbleKeyConn',
                          'AntiAdminConn', 'OptimizerConn',
                          'FlyConn', 'AntiFallConn',
                          'RainbowConn', 'TrailColorConn',
                          'AdminESPConn', 'BikeESPConn', 'SpeedTagConn', 'SpeedTagLeaveConn',
                          'PlayerESPConn', 'PlayerESPCharConn',
                          'JumpKeyConn',
                          'AutoFixSeatConn', 'AutoFixCharConn'}) do
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
    pcall(function() if trailGui      then trailGui:Destroy()      end end)
    pcall(function() if bikeCustGui   then bikeCustGui:Destroy()   end end)
    pcall(function() if partPickerGui then partPickerGui:Destroy() end end)

    -- destroy LinoriaLib window
    pcall(function() Library.ScreenGui:Destroy() end)
end

-- ============================================================
-- SETTINGS TAB (SaveManager + ThemeManager)
-- Must come AFTER all Toggles/Options are registered
-- ============================================================
local SettingsRight = Tabs.Settings:AddRightGroupbox('Theme')

SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetFolder('Konstant')
SaveManager:BuildConfigSection(Tabs.Settings)

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder('Konstant')
ThemeManager:ApplyToGroupbox(SettingsRight)

-- Load autoload config after a short delay so all game systems finish initializing
-- before toggle callbacks fire (loading immediately breaks the game on join)
task.delay(3, function()
    SaveManager:LoadAutoloadConfig()
end)
