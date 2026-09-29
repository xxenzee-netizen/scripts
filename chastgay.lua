--// Simple Auto Chest Farm
--// Tween + Teleport
--// Movable + Minimizable + Tween Speed

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer

local Enabled = false
local Mode = "Tween"
local TweenSpeed = 180
local CurrentTween = nil

--==================================================
-- GUI
--==================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SimpleChestFarm"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = Player:WaitForChild("PlayerGui")

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 270, 0, 210)
Main.Position = UDim2.new(0.5, -135, 0.5, -105)
Main.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(65, 65, 75)
Stroke.Thickness = 1
Stroke.Parent = Main

--==================================================
-- TOP BAR
--==================================================

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 40)
TopBar.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
TopBar.BorderSizePixel = 0
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 12)
TopCorner.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.Position = UDim2.new(0, 12, 0, 0)
Title.Size = UDim2.new(1, -90, 1, 0)
Title.BackgroundTransparency = 1
Title.Text = "  Auto Chest Farm"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local Minimize = Instance.new("TextButton")
Minimize.Position = UDim2.new(1, -70, 0, 7)
Minimize.Size = UDim2.new(0, 28, 0, 26)
Minimize.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
Minimize.Text = "—"
Minimize.TextColor3 = Color3.new(1, 1, 1)
Minimize.TextSize = 18
Minimize.Font = Enum.Font.GothamBold
Minimize.Parent = TopBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = Minimize

local Close = Instance.new("TextButton")
Close.Position = UDim2.new(1, -36, 0, 7)
Close.Size = UDim2.new(0, 28, 0, 26)
Close.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
Close.Text = "×"
Close.TextColor3 = Color3.fromRGB(255, 100, 100)
Close.TextSize = 18
Close.Font = Enum.Font.GothamBold
Close.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = Close

--==================================================
-- CONTENT
--==================================================

local Content = Instance.new("Frame")
Content.Position = UDim2.new(0, 10, 0, 48)
Content.Size = UDim2.new(1, -20, 1, -58)
Content.BackgroundTransparency = 1
Content.Parent = Main

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, 0, 0, 25)
Status.BackgroundTransparency = 1
Status.Text = "●  Status: OFF"
Status.TextColor3 = Color3.fromRGB(255, 80, 80)
Status.TextSize = 14
Status.Font = Enum.Font.GothamMedium
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Content

local Toggle = Instance.new("TextButton")
Toggle.Position = UDim2.new(0, 0, 0, 32)
Toggle.Size = UDim2.new(0.48, -5, 0, 35)
Toggle.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
Toggle.Text = "START"
Toggle.TextColor3 = Color3.new(1, 1, 1)
Toggle.TextSize = 13
Toggle.Font = Enum.Font.GothamBold
Toggle.Parent = Content

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 8)
ToggleCorner.Parent = Toggle

local ModeButton = Instance.new("TextButton")
ModeButton.Position = UDim2.new(0.52, 0, 0, 32)
ModeButton.Size = UDim2.new(0.48, 0, 0, 35)
ModeButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
ModeButton.Text = "TWEEN"
ModeButton.TextColor3 = Color3.new(1, 1, 1)
ModeButton.TextSize = 13
ModeButton.Font = Enum.Font.GothamBold
ModeButton.Parent = Content

local ModeCorner = Instance.new("UICorner")
ModeCorner.CornerRadius = UDim.new(0, 8)
ModeCorner.Parent = ModeButton

--==================================================
-- SPEED
--==================================================

local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Position = UDim2.new(0, 0, 0, 78)
SpeedLabel.Size = UDim2.new(0.45, 0, 0, 25)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "Tween Speed"
SpeedLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
SpeedLabel.TextSize = 13
SpeedLabel.Font = Enum.Font.GothamMedium
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedLabel.Parent = Content

local SpeedBox = Instance.new("TextBox")
SpeedBox.Position = UDim2.new(0.48, 0, 0, 75)
SpeedBox.Size = UDim2.new(0.52, 0, 0, 32)
SpeedBox.BackgroundColor3 = Color3.fromRGB(35, 35, 43)
SpeedBox.Text = tostring(TweenSpeed)
SpeedBox.PlaceholderText = "Speed"
SpeedBox.TextColor3 = Color3.new(1, 1, 1)
SpeedBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
SpeedBox.TextSize = 13
SpeedBox.Font = Enum.Font.Gotham
SpeedBox.ClearTextOnFocus = false
SpeedBox.Parent = Content

local SpeedCorner = Instance.new("UICorner")
SpeedCorner.CornerRadius = UDim.new(0, 7)
SpeedCorner.Parent = SpeedBox

--==================================================
-- INFO
--==================================================

local Info = Instance.new("TextLabel")
Info.Position = UDim2.new(0, 0, 0, 118)
Info.Size = UDim2.new(1, 0, 0, 35)
Info.BackgroundTransparency = 1
Info.Text = "Automatically finds and collects available chests."
Info.TextColor3 = Color3.fromRGB(125, 125, 135)
Info.TextSize = 11
Info.Font = Enum.Font.Gotham
Info.TextWrapped = true
Info.TextXAlignment = Enum.TextXAlignment.Left
Info.Parent = Content

--==================================================
-- DRAGGING
--==================================================

local Dragging = false
local DragStart
local StartPosition

TopBar.InputBegan:Connect(function(Input)

    if Input.UserInputType == Enum.UserInputType.MouseButton1
        or Input.UserInputType == Enum.UserInputType.Touch then

        Dragging = true
        DragStart = Input.Position
        StartPosition = Main.Position

        Input.Changed:Connect(function()

            if Input.UserInputState == Enum.UserInputState.End then
                Dragging = false
            end

        end)

    end

end)

UserInputService.InputChanged:Connect(function(Input)

    if not Dragging then
        return
    end

    if Input.UserInputType == Enum.UserInputType.MouseMovement
        or Input.UserInputType == Enum.UserInputType.Touch then

        local Delta = Input.Position - DragStart

        Main.Position = UDim2.new(
            StartPosition.X.Scale,
            StartPosition.X.Offset + Delta.X,
            StartPosition.Y.Scale,
            StartPosition.Y.Offset + Delta.Y
        )

    end

end)

--==================================================
-- CHARACTER
--==================================================

local function GetCharacter()

    return Player.Character or Player.CharacterAdded:Wait()

end

--==================================================
-- FIND CHEST
--==================================================

local function GetChest()

    local Character = GetCharacter()
    local Root = Character:FindFirstChild("HumanoidRootPart")

    if not Root then
        return nil
    end

    local Closest
    local ClosestDistance = math.huge

    for _, Chest in ipairs(CollectionService:GetTagged("_ChestTagged")) do

        if Chest
            and Chest.Parent
            and not Chest:GetAttribute("IsDisabled") then

            local Success, Pivot = pcall(function()
                return Chest:GetPivot()
            end)

            if Success and Pivot then

                local Distance =
                    (Pivot.Position - Root.Position).Magnitude

                if Distance < ClosestDistance then

                    ClosestDistance = Distance
                    Closest = Chest

                end

            end

        end

    end

    return Closest

end

--==================================================
-- CANCEL TWEEN
--==================================================

local function CancelTween()

    if CurrentTween then

        pcall(function()
            CurrentTween:Cancel()
        end)

        CurrentTween = nil

    end

end
--==================================================
-- COLLECT CHEST
--==================================================

local function CollectChest(Chest)

    if not Enabled or not Chest or not Chest.Parent then
        return
    end

    local Character = GetCharacter()
    local Root = Character:FindFirstChild("HumanoidRootPart")

    if not Root then
        return
    end

    local Success, ChestPivot = pcall(function()
        return Chest:GetPivot()
    end)

    if not Success or not ChestPivot then
        return
    end

    --==============================================
    -- TELEPORT MODE
    --==============================================

    if Mode == "Teleport" then

        Character:PivotTo(ChestPivot)

    --==============================================
    -- TWEEN MODE
    --==============================================

    else

        CancelTween()

        local Distance =
            (ChestPivot.Position - Root.Position).Magnitude

        if Distance > 12 then

            local Duration =
                math.clamp(
                    Distance / math.max(TweenSpeed, 1),
                    0.08,
                    4
                )

            CurrentTween = TweenService:Create(
                Root,
                TweenInfo.new(
                    Duration,
                    Enum.EasingStyle.Linear,
                    Enum.EasingDirection.Out
                ),
                {
                    CFrame = ChestPivot
                }
            )

            CurrentTween:Play()

            local Finished = false
            local Connection

            Connection = CurrentTween.Completed:Connect(function()

                Finished = true

                if Connection then
                    Connection:Disconnect()
                end

            end)

            while not Finished and Enabled do
                task.wait()
            end

            if not Enabled then
                CancelTween()
                return
            end

        end

    end

    --==============================================
    -- COLLECT CHEST
    --==============================================

    task.wait(0.05)

    Root = Character:FindFirstChild("HumanoidRootPart")

    if not Root or not Chest.Parent then
        return
    end

    local CurrentPivot

    pcall(function()
        CurrentPivot = Chest:GetPivot()
    end)

    if not CurrentPivot then
        return
    end

    if (CurrentPivot.Position - Root.Position).Magnitude <= 15 then

        if typeof(firetouchinterest) == "function" then

            pcall(function()

                firetouchinterest(
                    Chest,
                    Root,
                    0
                )

                firetouchinterest(
                    Chest,
                    Root,
                    1
                )

            end)

        end

        if typeof(firesignal) == "function" then

            pcall(function()

                firesignal(
                    Chest.Touched,
                    Root
                )

            end)

        end

    end

end

--==================================================
-- FARM LOOP
--==================================================

task.spawn(function()

    while ScreenGui.Parent do

        if Enabled then

            local Chest = GetChest()

            if Chest then

                pcall(function()
                    CollectChest(Chest)
                end)

                task.wait(0.1)

            else

                task.wait(0.5)

            end

        else

            task.wait(0.15)

        end

    end

end)

--==================================================
-- ON / OFF
--==================================================

Toggle.MouseButton1Click:Connect(function()

    Enabled = not Enabled

    if Enabled then

        Toggle.Text = "STOP"
        Toggle.BackgroundColor3 =
            Color3.fromRGB(45, 110, 65)

        Status.Text = "●  Status: ON"
        Status.TextColor3 =
            Color3.fromRGB(80, 255, 120)

    else

        CancelTween()

        Toggle.Text = "START"
        Toggle.BackgroundColor3 =
            Color3.fromRGB(45, 45, 55)

        Status.Text = "●  Status: OFF"
        Status.TextColor3 =
            Color3.fromRGB(255, 80, 80)

    end

end)

--==================================================
-- TWEEN / TELEPORT
--==================================================

ModeButton.MouseButton1Click:Connect(function()

    if Mode == "Tween" then

        Mode = "Teleport"
        ModeButton.Text = "TELEPORT"

        CancelTween()

    else

        Mode = "Tween"
        ModeButton.Text = "TWEEN"

    end

end)

--==================================================
-- SPEED SETTER
--==================================================

SpeedBox.FocusLost:Connect(function()

    local Number = tonumber(SpeedBox.Text)

    if Number then

        TweenSpeed = math.clamp(
            Number,
            1,
            10000
        )

        SpeedBox.Text =
            tostring(TweenSpeed)

    else

        SpeedBox.Text =
            tostring(TweenSpeed)

    end

end)

--==================================================
-- MINIMIZE
--==================================================

local Minimized = false
local OriginalSize = Main.Size

Minimize.MouseButton1Click:Connect(function()

    Minimized = not Minimized

    if Minimized then

        Content.Visible = false

        Main.Size =
            UDim2.new(0, 270, 0, 40)

        Minimize.Text = "+"

    else

        Content.Visible = true

        Main.Size = OriginalSize

        Minimize.Text = "—"

    end

end)

--==================================================
-- CLOSE
--==================================================

Close.MouseButton1Click:Connect(function()

    Enabled = false

    CancelTween()

    ScreenGui:Destroy()

end)
