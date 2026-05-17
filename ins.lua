local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local plr = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "MoneyGui"
gui.ResetOnSpawn = false
gui.Parent = plr.PlayerGui

-- toast
local function showToast(text)
    local toast = Instance.new("Frame")
    toast.Size = UDim2.new(0, 240, 0, 32)
    toast.Position = UDim2.new(0.5, -120, 1, -60)
    toast.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    toast.BorderSizePixel = 1
    toast.BorderColor3 = Color3.fromRGB(255, 255, 255)
    toast.ZIndex = 20
    toast.Parent = gui
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.ZIndex = 21
    lbl.Parent = toast
    TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -120, 1, -80)
    }):Play()
    task.delay(1.5, function()
        TweenService:Create(toast, TweenInfo.new(0.3), {
            Position = UDim2.new(0.5, -120, 1, -40),
            BackgroundTransparency = 1
        }):Play()
        TweenService:Create(lbl, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
        task.wait(0.3)
        toast:Destroy()
    end)
end

-- main frame
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 240, 0, 184)
frame.Position = UDim2.new(0.5, -120, 0.5, -92)
frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
frame.BorderSizePixel = 1
frame.BorderColor3 = Color3.fromRGB(255, 255, 255)
frame.Active = true
frame.Parent = gui

local input = Instance.new("TextBox")
input.Size = UDim2.new(1, -16, 0, 28)
input.Position = UDim2.new(0, 8, 0, 8)
input.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
input.BorderSizePixel = 1
input.BorderColor3 = Color3.fromRGB(255, 255, 255)
input.Text = "10000"
input.TextColor3 = Color3.fromRGB(255, 255, 255)
input.Font = Enum.Font.Code
input.TextSize = 16
input.ClearTextOnFocus = false
input.Parent = frame

local addBtn = Instance.new("TextButton")
addBtn.Size = UDim2.new(0.5, -12, 0, 32)
addBtn.Position = UDim2.new(0, 8, 0, 44)
addBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
addBtn.BorderSizePixel = 0
addBtn.Text = "ADD"
addBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
addBtn.Font = Enum.Font.GothamBold
addBtn.TextSize = 14
addBtn.Parent = frame

local subBtn = Instance.new("TextButton")
subBtn.Size = UDim2.new(0.5, -12, 0, 32)
subBtn.Position = UDim2.new(0.5, 4, 0, 44)
subBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
subBtn.BorderSizePixel = 1
subBtn.BorderColor3 = Color3.fromRGB(255, 255, 255)
subBtn.Text = "SUBTRACT"
subBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
subBtn.Font = Enum.Font.GothamBold
subBtn.TextSize = 14
subBtn.Parent = frame

local allBtn = Instance.new("TextButton")
allBtn.Size = UDim2.new(0.5, -12, 0, 32)
allBtn.Position = UDim2.new(0, 8, 0, 84)
allBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
allBtn.BorderSizePixel = 1
allBtn.BorderColor3 = Color3.fromRGB(255, 255, 255)
allBtn.Text = "GET ALL"
allBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
allBtn.Font = Enum.Font.GothamBold
allBtn.TextSize = 14
allBtn.Parent = frame

local sellAllBtn = Instance.new("TextButton")
sellAllBtn.Size = UDim2.new(0.5, -12, 0, 32)
sellAllBtn.Position = UDim2.new(0.5, 4, 0, 84)
sellAllBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
sellAllBtn.BorderSizePixel = 1
sellAllBtn.BorderColor3 = Color3.fromRGB(255, 255, 255)
sellAllBtn.Text = "SELL ALL"
sellAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sellAllBtn.Font = Enum.Font.GothamBold
sellAllBtn.TextSize = 14
sellAllBtn.Parent = frame

local spawnerBtn = Instance.new("TextButton")
spawnerBtn.Size = UDim2.new(1, -16, 0, 32)
spawnerBtn.Position = UDim2.new(0, 8, 0, 124)
spawnerBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
spawnerBtn.BorderSizePixel = 1
spawnerBtn.BorderColor3 = Color3.fromRGB(255, 255, 255)
spawnerBtn.Text = "TOGGLE SPAWNER"
spawnerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
spawnerBtn.Font = Enum.Font.GothamBold
spawnerBtn.TextSize = 14
spawnerBtn.Parent = frame

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, 0, 0, 16)
hint.Position = UDim2.new(0, 0, 0, 164)
hint.BackgroundTransparency = 1
hint.Text = "INSERT to close"
hint.TextColor3 = Color3.fromRGB(100, 100, 100)
hint.Font = Enum.Font.Code
hint.TextSize = 11
hint.Parent = frame

-- spawner menu
local spawnerOpen = false
local spawnerFrame = Instance.new("Frame")
spawnerFrame.Size = UDim2.new(0, 400, 0, 500)
spawnerFrame.Position = UDim2.new(0.5, 10, 0.5, -250)
spawnerFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
spawnerFrame.BorderSizePixel = 1
spawnerFrame.BorderColor3 = Color3.fromRGB(255, 255, 255)
spawnerFrame.Visible = false
spawnerFrame.ZIndex = 5
spawnerFrame.Active = true
spawnerFrame.ClipsDescendants = true
spawnerFrame.Parent = gui

local spawnerTitle = Instance.new("TextLabel")
spawnerTitle.Size = UDim2.new(1, 0, 0, 32)
spawnerTitle.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
spawnerTitle.BorderSizePixel = 0
spawnerTitle.Text = "BIKE SPAWNER"
spawnerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
spawnerTitle.Font = Enum.Font.GothamBold
spawnerTitle.TextSize = 13
spawnerTitle.ZIndex = 6
spawnerTitle.Parent = spawnerFrame

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -32)
scroll.Position = UDim2.new(0, 0, 0, 32)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
scroll.ZIndex = 6
scroll.Parent = spawnerFrame

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, 120, 0, 140)
grid.CellPadding = UDim2.new(0, 8, 0, 8)
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.Parent = scroll

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.Parent = scroll

-- populate bike cards
local bikes = RS.Bikes:GetChildren()
scroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#bikes / 3) * 148 + 16)

for _, bike in ipairs(bikes) do
    local card = Instance.new("TextButton")
    card.Size = UDim2.new(0, 120, 0, 140)
    card.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
    card.BorderSizePixel = 1
    card.BorderColor3 = Color3.fromRGB(60, 60, 60)
    card.Text = ""
    card.ZIndex = 7
    card.Parent = scroll

    -- viewport
    local vpf = Instance.new("ViewportFrame")
    vpf.Size = UDim2.new(1, 0, 0, 100)
    vpf.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
    vpf.BorderSizePixel = 0
    vpf.ZIndex = 8
    vpf.Parent = card

    local worldModel = Instance.new("WorldModel")
    worldModel.Parent = vpf

    local cam = Instance.new("Camera")
    vpf.CurrentCamera = cam
    cam.Parent = vpf

    -- clone bike into viewport
    local ok, clone = pcall(function() return bike:Clone() end)
    if ok and clone then
        clone.Parent = worldModel
        task.defer(function()
            local cf, size = clone:GetBoundingBox()
            local dist = math.max(size.X, size.Y, size.Z) * 1.4
            cam.CFrame = CFrame.lookAt(
                cf.Position + Vector3.new(dist, dist * 0.4, dist),
                cf.Position
            )
        end)
    end

    -- name label
    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, 0, 0, 36)
    nameLbl.Position = UDim2.new(0, 0, 0, 100)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = bike.Name
    nameLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    nameLbl.Font = Enum.Font.Gotham
    nameLbl.TextSize = 11
    nameLbl.TextWrapped = true
    nameLbl.ZIndex = 8
    nameLbl.Parent = card

    -- hover
    card.MouseEnter:Connect(function()
        card.BorderColor3 = Color3.fromRGB(255, 255, 255)
    end)
    card.MouseLeave:Connect(function()
        card.BorderColor3 = Color3.fromRGB(60, 60, 60)
    end)

    card.MouseButton1Click:Connect(function()
        RS.Remotes.SpawnBike:FireServer(bike.Name)
        showToast("Spawned " .. bike.Name)
    end)
end

-- spawner drag
local sDragging, sDragStart, sStartPos
spawnerTitle.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        sDragging = true
        sDragStart = inp.Position
        sStartPos = spawnerFrame.Position
    end
end)
spawnerTitle.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        sDragging = false
    end
end)

-- money remote
local function fireBike(name, price)
    RS.Remotes.PurchaseBike:FireServer(name, {
        ["Name"] = name,
        ["Robux"] = false,
        ["Speed"] = 40,
        ["Kind"] = "E-BIKE",
        ["ProductID"] = 3585359520,
        ["Price"] = price
    })
end

addBtn.MouseButton1Click:Connect(function()
    fireBike("EBOX V2", -math.abs(tonumber(input.Text) or 0))
end)
subBtn.MouseButton1Click:Connect(function()
    fireBike("EBOX V2", math.abs(tonumber(input.Text) or 0))
end)

allBtn.MouseButton1Click:Connect(function()
    allBtn.Text = "WORKING..."
    allBtn.Active = false
    for _, bike in ipairs(RS.Bikes:GetChildren()) do
        fireBike(bike.Name, 0)
        task.wait(0.1)
    end
    allBtn.Text = "DONE (" .. #bikes .. ")"
    task.wait(2)
    allBtn.Text = "GET ALL"
    allBtn.Active = true
end)

sellAllBtn.MouseButton1Click:Connect(function()
    sellAllBtn.Text = "WORKING..."
    sellAllBtn.Active = false
    for _, bike in ipairs(RS.Bikes:GetChildren()) do
        RS.Remotes.SellBike:FireServer(bike.Name)
        task.wait(0.1)
    end
    sellAllBtn.Text = "DONE (" .. #bikes .. ")"
    task.wait(2)
    sellAllBtn.Text = "SELL ALL"
    sellAllBtn.Active = true
end)

spawnerBtn.MouseButton1Click:Connect(function()
    spawnerOpen = not spawnerOpen
    spawnerFrame.Visible = spawnerOpen
end)

-- drag both frames
local dragging, dragStart, startPos
frame.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = inp.Position
        startPos = frame.Position
    end
end)
frame.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

UIS.InputChanged:Connect(function(inp)
    if inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    if dragging then
        local delta = inp.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
    if sDragging then
        local delta = inp.Position - sDragStart
        spawnerFrame.Position = UDim2.new(sStartPos.X.Scale, sStartPos.X.Offset + delta.X, sStartPos.Y.Scale, sStartPos.Y.Offset + delta.Y)
    end
end)

UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.Insert then
        gui:Destroy()
    end
end)
