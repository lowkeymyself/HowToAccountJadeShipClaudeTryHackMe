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
    Title = 'SuperMoto Menu',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Main     = Window:AddTab('Main'),
    Troll    = Window:AddTab('Troll'),
    Maps     = Window:AddTab('Maps'),
    Settings = Window:AddTab('Settings')
}

local Left = Tabs.Main:AddLeftGroupbox('Money')
local Right = Tabs.Main:AddRightGroupbox('Bikes')

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

Right:AddButton({
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

Right:AddButton({
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

Right:AddDivider()

Right:AddInput('SpeedInput', {
    Default = '60',
    Numeric = true,
    Finished = false,
    Text = 'Max Speed (mph)',
})

Right:AddInput('AccelInput', {
    Default = '37',
    Numeric = true,
    Finished = false,
    Text = 'Acceleration (mph/s)',
})

Right:AddButton({
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

Right:AddButton({
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

Right:AddDivider()

Right:AddToggle('SpawnerToggle', {
    Text = 'Toggle Spawner',
    Default = false,
})

Right:AddDivider()

-- forward-declared so HitboxViewer toggle (defined in this groupbox) and
-- the Troll section (which does the full definitions) share the same upvalues
local hitboxMap      = {}
local clearHitboxes  = nil
local refreshHitboxes = nil

local function getBikeRoot()
    local char = plr.Character
    if not char then return nil, nil end
    for _, v in pairs(workspace:GetDescendants()) do
        if v:IsA('VehicleSeat') and v.Occupant and v.Occupant.Parent == char then
            return v.Parent, v.Parent:FindFirstChildWhichIsA('BasePart')
        end
    end
    return nil, nil
end

-- scans once and returns root; on heartbeat only rescans if root went nil
local function cachedRoot(stored)
    if stored and stored.Parent then return stored end
    local _, r = getBikeRoot()
    return r
end

Right:AddInput('GravityInput', {
    Default = '196.2',
    Numeric = true,
    Finished = false,
    Text = 'Gravity (default 196.2)',
})

Right:AddToggle('CustomGravity', {
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

Right:AddDivider()

Right:AddInput('BrakeInput', {
    Default = '120',
    Numeric = true,
    Finished = false,
    Text = 'Brake Force (mph/s)',
})

Right:AddButton({
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

Right:AddButton({
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

Right:AddDivider()

Right:AddInput('TurnInput', {
    Default = '90',
    Numeric = true,
    Finished = false,
    Text = 'Turn Speed (deg/s)',
})

Right:AddButton({
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

Right:AddButton({
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

Right:AddToggle('HitboxViewer', {
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

Right:AddButton({
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
    for _, key in ipairs({'SpeedConn', 'BrakeConn', 'TurnConn', 'HitboxConn',
                          'AntiAdminConn', 'OptimizerConn'}) do
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

    -- destroy ScreenGuis this script owns
    pcall(function() gui:Destroy() end)
    pcall(function() minimapGui:Destroy() end)

    -- destroy LinoriaLib window
    pcall(function() Library.ScreenGui:Destroy() end)
end
