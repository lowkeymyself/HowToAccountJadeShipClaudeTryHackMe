local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local plr = Players.LocalPlayer

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
    Main = Window:AddTab('Main'),
    Troll = Window:AddTab('Troll'),
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

        -- disconnect old patch if any
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

local noclipCache = {}

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

Right:AddToggle('BikeNoclip', {
    Text = 'Bike Noclip',
    Default = false,
    Callback = function(val)
        local bikeModel = getBikeRoot()
        if not bikeModel then showToast('Get in a bike first') return end
        if val then
            -- find the largest non-seat part (main chassis) to keep collideable
            local chassis = nil
            local bestSz  = 0
            for _, p in ipairs(bikeModel:GetDescendants()) do
                if p:IsA('BasePart') and not p:IsA('VehicleSeat') then
                    local sz = p.Size.Magnitude
                    if sz > bestSz then bestSz = sz; chassis = p end
                end
            end
            noclipCache = {}
            for _, p in ipairs(bikeModel:GetDescendants()) do
                if p:IsA('BasePart') then
                    noclipCache[p] = p.CanCollide
                    -- keep seat + chassis collideable so bike stays on the ground
                    if not p:IsA('VehicleSeat') and p ~= chassis then
                        p.CanCollide = false
                    end
                end
            end
            showToast('Noclip ON')
        else
            for p, original in pairs(noclipCache) do
                if p and p.Parent then p.CanCollide = original end
            end
            noclipCache = {}
            showToast('Noclip OFF')
        end
    end
})

Right:AddInput('HoverForce', {
    Default = '1',
    Numeric = true,
    Finished = false,
    Text = 'Hover Force  (1=float  2=rise  0.5=half-grav)',
})

Right:AddToggle('Levitate', {
    Text = 'Levitate',
    Default = false,
    Callback = function(val)
        if val then
            local RS2  = game:GetService('RunService')
            local root = nil
            _G.LevitateConn = RS2.Heartbeat:Connect(function(dt)
                root = cachedRoot(root)
                if not root then return end
                local force = tonumber(Options.HoverForce.Value) or 1
                local vel   = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(
                    vel.X,
                    vel.Y + workspace.Gravity * dt * force,
                    vel.Z
                )
            end)
        else
            if _G.LevitateConn then
                _G.LevitateConn:Disconnect()
                _G.LevitateConn = nil
            end
        end
    end
})

Right:AddToggle('AnchorSelf', {
    Text = 'Anchor Self',
    Default = false,
    Callback = function(val)
        if val then
            local RS2          = game:GetService('RunService')
            local bikeModel, _ = getBikeRoot()
            if not bikeModel then showToast('Get in a bike first') return end
            -- snapshot every part's CFrame
            local anchorData = {}
            for _, p in ipairs(bikeModel:GetDescendants()) do
                if p:IsA('BasePart') then anchorData[p] = p.CFrame end
            end
            _G.AnchorConn = RS2.Heartbeat:Connect(function()
                for part, cf in pairs(anchorData) do
                    if not part.Parent then
                        anchorData[part] = nil
                    else
                        part.CFrame                 = cf
                        part.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
                        part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    end
                end
            end)
            showToast('Anchored')
        else
            if _G.AnchorConn then
                _G.AnchorConn:Disconnect()
                _G.AnchorConn = nil
            end
            -- zero all velocities on release so nothing flings
            local bikeModel2, _ = getBikeRoot()
            if bikeModel2 then
                for _, p in ipairs(bikeModel2:GetDescendants()) do
                    if p:IsA('BasePart') then
                        p.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
                        p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    end
                end
            end
            showToast('Anchor OFF')
        end
    end
})

Right:AddDivider()

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
