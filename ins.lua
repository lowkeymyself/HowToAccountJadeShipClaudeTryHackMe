local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local plr = Players.LocalPlayer

local playSuccess -- defined after gui is created below
local showToast   -- defined after gui is created below

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

        local root    = seat.Parent:FindFirstChildWhichIsA('BasePart')
        local mph     = tonumber(Options.SpeedInput.Value) or 60
        local maxSpeed = mph * 1.6 -- convert to studs/s

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
                    vel.X + flatFwd.X * dt * 60,
                    vel.Y,
                    vel.Z + flatFwd.Z * dt * 60
                )
            end
        end)

        playSuccess()
        showToast('Patched — max ' .. mph .. ' mph')
    end
})

Right:AddDivider()

Right:AddToggle('SpawnerToggle', {
    Text = 'Toggle Spawner',
    Default = false,
})

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:SetFolder('BikeTool')
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

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
