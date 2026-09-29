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
-- SMOOTH MOVEMENT SYSTEM
--==================================================

local MovementToken = 0
local Moving = false

local function GetRoot()

    local Character = Player.Character

    if not Character then
        return nil
    end

    return Character:FindFirstChild("HumanoidRootPart")

end

local function StopMovement()

    MovementToken += 1
    Moving = false

    if CurrentTween then

        pcall(function()
            CurrentTween:Cancel()
        end)

        CurrentTween = nil

    end

    local Character = Player.Character

    if Character then

        local Proxy = Character:FindFirstChild("ChestFarmProxy")

        if Proxy then
            Proxy:Destroy()
        end

    end

end

--==================================================
-- SMOOTH TWEEN TO CHEST
--==================================================

local function SmoothTweenTo(TargetCFrame)

    local Character = GetCharacter()
    local Root = GetRoot()

    if not Character or not Root or not Enabled then
        return false
    end

    StopMovement()

    local MyToken = MovementToken

    Moving = true

    -- Proxy part.
    -- This follows the movement pattern used by the
    -- supplied redz script's PartTele system.
    local Proxy = Instance.new("Part")

    Proxy.Name = "ChestFarmProxy"
    Proxy.Size = Vector3.new(2, 1, 2)
    Proxy.Transparency = 1
    Proxy.Anchored = true
    Proxy.CanCollide = false
    Proxy.CanTouch = false
    Proxy.CanQuery = false
    Proxy.CFrame = Root.CFrame
    Proxy.Parent = Character

    local Distance =
        (TargetCFrame.Position - Root.Position).Magnitude

    if Distance <= 10 then

        Character:PivotTo(TargetCFrame)

        Proxy:Destroy()
        Moving = false

        return true

    end

    -- Higher speed = faster movement.
    local Speed = math.max(TweenSpeed, 1)

    local Duration = math.clamp(
        Distance / Speed,
        0.15,
        8
    )

    CurrentTween = TweenService:Create(
        Proxy,
        TweenInfo.new(
            Duration,
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.InOut
        ),
        {
            CFrame = TargetCFrame
        }
    )

    CurrentTween:Play()

    local Completed = false

    local Connection

    Connection = CurrentTween.Completed:Connect(function(State)

        Completed = true

        if Connection then
            Connection:Disconnect()
            Connection = nil
        end

    end)

    -- Smoothly follow the proxy.
    while Enabled
        and Moving
        and MyToken == MovementToken
        and not Completed do

        Character = Player.Character

        if not Character then
            break
        end

        Root = Character:FindFirstChild("HumanoidRootPart")

        if not Root then
            break
        end

        if Proxy.Parent then

            -- Move the complete character instead of
            -- directly tweening HumanoidRootPart.
            Character:PivotTo(Proxy.CFrame)

        else

            break

        end

        task.wait()

    end

    if Connection then
        Connection:Disconnect()
    end

    if CurrentTween then

        pcall(function()
            CurrentTween:Cancel()
        end)

        CurrentTween = nil

    end

    if Proxy and Proxy.Parent then
        Proxy:Destroy()
    end

    Moving = false

    return Enabled
        and MyToken == MovementToken
        and Completed

end

--==================================================
-- TELEPORT
--==================================================

local function TeleportToChest(TargetCFrame)

    local Character = GetCharacter()

    if not Character or not Enabled then
        return false
    end

    StopMovement()

    Character:PivotTo(TargetCFrame)

    task.wait(0.08)

    return true

end

--==================================================
-- CHEST COLLECTION
--==================================================

local function TriggerChest(Chest)

    if not Chest or not Chest.Parent then
        return false
    end

    local Character = GetCharacter()
    local Root = Character:FindFirstChild("HumanoidRootPart")

    if not Root then
        return false
    end

    local Success, ChestCFrame =
        pcall(function()
            return Chest:GetPivot()
        end)

    if not Success or not ChestCFrame then
        return false
    end

    local Distance =
        (ChestCFrame.Position - Root.Position).Magnitude

    -- We only trigger the chest when actually close.
    if Distance > 12 then
        return false
    end

    if typeof(firetouchinterest) == "function" then

        pcall(function()

            firetouchinterest(
                Chest,
                Root,
                0
            )

            task.wait(0.03)

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

    return true

end

--==================================================
-- COLLECT CHEST RELIABLY
--==================================================

local function CollectChest(Chest)

    if not Enabled
        or not Chest
        or not Chest.Parent then

        return false

    end

    local Character = GetCharacter()
    local Root = Character:FindFirstChild("HumanoidRootPart")

    if not Root then
        return false
    end

    local Success, ChestCFrame =
        pcall(function()
            return Chest:GetPivot()
        end)

    if not Success or not ChestCFrame then
        return false
    end

    --==============================================
    -- TWEEN
    --==============================================

    if Mode == "Tween" then

        local Reached =
            SmoothTweenTo(ChestCFrame)

        if not Reached then
            return false
        end

    --==============================================
    -- TELEPORT
    --==============================================

    else

        if not TeleportToChest(ChestCFrame) then
            return false
        end

    end

    if not Enabled then
        return false
    end

    -- Give Roblox a moment to update character position.
    task.wait(0.08)

    --==============================================
    -- FIRST COLLECTION ATTEMPT
    --==============================================

    TriggerChest(Chest)

    --==============================================
    -- RETRY COLLECTION
    --==============================================

    -- Some chests don't register the first touch
    -- immediately, so retry briefly instead of
    -- instantly moving to another chest.

    for _ = 1, 6 do

        if not Enabled then
            return false
        end

        if not Chest.Parent then
            return true
        end

        if Chest:GetAttribute("IsDisabled") then
            return true
        end

        local CurrentRoot = GetRoot()

        if not CurrentRoot then
            return false
        end

        local CurrentChestCFrame

        pcall(function()
            CurrentChestCFrame = Chest:GetPivot()
        end)

        if not CurrentChestCFrame then
            return true
        end

        local Distance =
            (CurrentChestCFrame.Position -
            CurrentRoot.Position).Magnitude

        if Distance <= 12 then

            TriggerChest(Chest)

        else

            -- If the character was corrected slightly,
            -- gently return to the chest instead of
            -- immediately selecting another chest.

            if Mode == "Tween" then

                SmoothTweenTo(CurrentChestCFrame)

            else

                Character:PivotTo(CurrentChestCFrame)

            end

        end

        task.wait(0.12)

    end

    return true

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

    local Closest = nil
    local ClosestDistance = math.huge

    for _, Chest in ipairs(
        CollectionService:GetTagged("_ChestTagged")
    ) do

        if Chest
            and Chest.Parent
            and not Chest:GetAttribute("IsDisabled") then

            local Success, Pivot =
                pcall(function()
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
-- MAIN FARM LOOP
--==================================================

task.spawn(function()

    while ScreenGui.Parent do

        if Enabled and not Moving then

            local Chest = GetChest()

            if Chest then

                pcall(function()

                    CollectChest(Chest)

                end)

                -- Small delay before choosing the next chest.
                task.wait(0.15)

            else

                task.wait(0.5)

            end

        else

            task.wait(0.1)

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

        StopMovement()

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

        StopMovement()

    else

        Mode = "Tween"

        ModeButton.Text = "TWEEN"

    end

end)

--==================================================
-- SPEED
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

    StopMovement()

    ScreenGui:Destroy()

end)
