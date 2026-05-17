local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local plr = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "MoneyGui"
gui.ResetOnSpawn = false
gui.Parent = plr.PlayerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 240, 0, 148)
frame.Position = UDim2.new(0.5, -120, 0.5, -74)
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
allBtn.Size = UDim2.new(1, -16, 0, 32)
allBtn.Position = UDim2.new(0, 8, 0, 84)
allBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
allBtn.BorderSizePixel = 1
allBtn.BorderColor3 = Color3.fromRGB(255, 255, 255)
allBtn.Text = "GET ALL BIKES"
allBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
allBtn.Font = Enum.Font.GothamBold
allBtn.TextSize = 14
allBtn.Parent = frame

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, 0, 0, 16)
hint.Position = UDim2.new(0, 0, 0, 128)
hint.BackgroundTransparency = 1
hint.Text = "INSERT to close"
hint.TextColor3 = Color3.fromRGB(100, 100, 100)
hint.Font = Enum.Font.Code
hint.TextSize = 11
hint.Parent = frame

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
    local bikes = RS.Bikes:GetChildren()
    for i, bike in ipairs(bikes) do
        fireBike(bike.Name, 0)
        task.wait(0.1)
    end
    allBtn.Text = "DONE (" .. #bikes .. ")"
    task.wait(2)
    allBtn.Text = "GET ALL BIKES"
    allBtn.Active = true
end)

-- drag
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
    if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = inp.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.Insert then
        gui:Destroy()
    end
end)
