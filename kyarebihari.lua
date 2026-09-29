--// Auto Chest Farm + Auto Raid
--// Part 1/3

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer

local Enabled = false
local AutoRaid = false
local Mode = "Tween"

local TweenSpeed = 180
local CurrentTween = nil

local RaidBusy = false
local RaidToken = 0

--==================================================
-- GUI
--==================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ChestRaidFarm"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = Player:WaitForChild("PlayerGui")

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 280, 0, 245)
Main.Position = UDim2.new(0.5, -140, 0.5, -122)
Main.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 12)

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(65, 65, 75)
Stroke.Thickness = 1
Stroke.Parent = Main

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 40)
TopBar.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
TopBar.BorderSizePixel = 0
TopBar.Parent = Main

Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 12)

local Title = Instance.new("TextLabel")
Title.Position = UDim2.new(0, 12, 0, 0)
Title.Size = UDim2.new(1, -90, 1, 0)
Title.BackgroundTransparency = 1
Title.Text = "Auto Chest + Raid"
Title.TextColor3 = Color3.new(1, 1, 1)
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

Instance.new("UICorner", Minimize).CornerRadius = UDim.new(0, 6)

local Close = Instance.new("TextButton")
Close.Position = UDim2.new(1, -36, 0, 7)
Close.Size = UDim2.new(0, 28, 0, 26)
Close.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
Close.Text = "×"
Close.TextColor3 = Color3.fromRGB(255, 100, 100)
Close.TextSize = 18
Close.Font = Enum.Font.GothamBold
Close.Parent = TopBar

Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 6)

local Content = Instance.new("Frame")
Content.Position = UDim2.new(0, 10, 0, 48)
Content.Size = UDim2.new(1, -20, 1, -58)
Content.BackgroundTransparency = 1
Content.Parent = Main

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, 0, 0, 25)
Status.BackgroundTransparency = 1
Status.Text = "● Status: OFF"
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

Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0, 8)

local ModeButton = Instance.new("TextButton")
ModeButton.Position = UDim2.new(0.52, 0, 0, 32)
ModeButton.Size = UDim2.new(0.48, 0, 0, 35)
ModeButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
ModeButton.Text = "TWEEN"
ModeButton.TextColor3 = Color3.new(1, 1, 1)
ModeButton.TextSize = 13
ModeButton.Font = Enum.Font.GothamBold
ModeButton.Parent = Content

Instance.new("UICorner", ModeButton).CornerRadius = UDim.new(0, 8)

local RaidButton = Instance.new("TextButton")
RaidButton.Position = UDim2.new(0, 0, 0, 76)
RaidButton.Size = UDim2.new(1, 0, 0, 35)
RaidButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
RaidButton.Text = "AUTO RAID: OFF"
RaidButton.TextColor3 = Color3.new(1, 1, 1)
RaidButton.TextSize = 13
RaidButton.Font = Enum.Font.GothamBold
RaidButton.Parent = Content

Instance.new("UICorner", RaidButton).CornerRadius = UDim.new(0, 8)

local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Position = UDim2.new(0, 0, 0, 120)
SpeedLabel.Size = UDim2.new(0.45, 0, 0, 25)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "Tween Speed"
SpeedLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
SpeedLabel.TextSize = 13
SpeedLabel.Font = Enum.Font.GothamMedium
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedLabel.Parent = Content

local SpeedBox = Instance.new("TextBox")
SpeedBox.Position = UDim2.new(0.48, 0, 0, 117)
SpeedBox.Size = UDim2.new(0.52, 0, 0, 32)
SpeedBox.BackgroundColor3 = Color3.fromRGB(35, 35, 43)
SpeedBox.Text = tostring(TweenSpeed)
SpeedBox.TextColor3 = Color3.new(1, 1, 1)
SpeedBox.TextSize = 13
SpeedBox.Font = Enum.Font.Gotham
SpeedBox.ClearTextOnFocus = false
SpeedBox.Parent = Content

Instance.new("UICorner", SpeedBox).CornerRadius = UDim.new(0, 7)

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

local function GetCharacter()

    return Player.Character or Player.CharacterAdded:Wait()

end

local function GetRoot()

    local Character = Player.Character

    if not Character then
        return nil
    end

    return Character:FindFirstChild("HumanoidRootPart")

end

local function StopMovement()

    RaidToken += 1
    RaidBusy = false

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
--// Part 2/3

local function GetChest()

    local Root = GetRoot()

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

local function IsRaidActive()

    local PlayerGui =
        Player:FindFirstChild("PlayerGui")

    if not PlayerGui then
        return false
    end

    local MainGui =
        PlayerGui:FindFirstChild("Main")

    if not MainGui then
        return false
    end

    local TopHUDList =
        MainGui:FindFirstChild("TopHUDList")

    if not TopHUDList then
        return false
    end

    local RaidTimer =
        TopHUDList:FindFirstChild("RaidTimer")

    return RaidTimer ~= nil
        and RaidTimer.Visible == true

end

local function GetRaidIsland()

    local Root = GetRoot()

    if not Root then
        return nil
    end

    local WorldOrigin =
        Workspace:FindFirstChild("_WorldOrigin")

    if not WorldOrigin then
        return nil
    end

    local Locations =
        WorldOrigin:FindFirstChild("Locations")

    if not Locations then
        return nil
    end

    for Index = 5, 1, -1 do

        local Island =
            Locations:FindFirstChild(
                "Island " .. Index
            )

        if Island then

            local Success, Position =
                pcall(function()

                    return Island:GetPivot().Position

                end)

            if Success and Position then

                if (
                    Position - Root.Position
                ).Magnitude <= 3000 then

                    return Island

                end

            end

        end

    end

    return nil

end

local function GetRaidTarget()

    local Root = GetRoot()

    if not Root then
        return nil
    end

    local Enemies =
        Workspace:FindFirstChild("Enemies")

    if not Enemies then
        return nil
    end

    local Closest = nil
    local ClosestDistance = math.huge

    for _, Enemy in ipairs(
        Enemies:GetChildren()
    ) do

        if Enemy and Enemy.Parent then

            local Humanoid =
                Enemy:FindFirstChildOfClass(
                    "Humanoid"
                )

            local EnemyRoot =
                Enemy:FindFirstChild(
                    "HumanoidRootPart"
                )
                or Enemy.PrimaryPart

            if Humanoid
                and EnemyRoot
                and Humanoid.Health > 0 then

                local Distance =
                    (
                        EnemyRoot.Position -
                        Root.Position
                    ).Magnitude

                if Distance <= 1000
                    and Distance < ClosestDistance then

                    ClosestDistance = Distance
                    Closest = Enemy

                end

            end

        end

    end

    return Closest

end

local function SmoothMove(TargetCFrame)

    if not Enabled then
        return false
    end

    local Character = GetCharacter()
    local Root = GetRoot()

    if not Character or not Root then
        return false
    end

    if not TargetCFrame then
        return false
    end

    StopMovement()

    local MyToken = RaidToken

    local Distance =
        (
            TargetCFrame.Position -
            Root.Position
        ).Magnitude

    if Distance <= 8 then

        Character:PivotTo(TargetCFrame)

        return true

    end

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

    local Duration =
        math.clamp(
            Distance / math.max(TweenSpeed, 1),
            0.15,
            8
        )

    CurrentTween =
        TweenService:Create(
            Proxy,
            TweenInfo.new(
                Duration,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.Out
            ),
            {
                CFrame = TargetCFrame
            }
        )

    CurrentTween:Play()

    local Finished = false

    local Connection =
        CurrentTween.Completed:Connect(
            function()
                Finished = true
            end
        )

    while Enabled
        and MyToken == RaidToken
        and not Finished do

        Character = Player.Character

        if not Character then
            break
        end

        Root =
            Character:FindFirstChild(
                "HumanoidRootPart"
            )

        if not Root then
            break
        end

        if Proxy.Parent then

            Character:PivotTo(
                Proxy.CFrame
            )

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

    if Proxy.Parent then
        Proxy:Destroy()
    end

    return Finished
        and Enabled
        and MyToken == RaidToken

end

local function TeleportMove(TargetCFrame)

    if not Enabled then
        return false
    end

    local Character =
        Player.Character

    if not Character then
        return false
    end

    StopMovement()

    Character:PivotTo(TargetCFrame)

    task.wait(0.1)

    return true

end

local function AttackRaidTarget(Enemy)

    if not Enemy
        or not Enemy.Parent then

        return false

    end

    local Humanoid =
        Enemy:FindFirstChildOfClass(
            "Humanoid"
        )

    local EnemyRoot =
        Enemy:FindFirstChild(
            "HumanoidRootPart"
        )
        or Enemy.PrimaryPart

    if not Humanoid
        or not EnemyRoot
        or Humanoid.Health <= 0 then

        return false

    end

    local TargetCFrame =
        EnemyRoot.CFrame *
        CFrame.new(0, 6, 0)

    if Mode == "Tween" then

        SmoothMove(TargetCFrame)

    else

        TeleportMove(TargetCFrame)

    end

    local StartTime = os.clock()

    while Enabled
        and AutoRaid
        and IsRaidActive()
        and Enemy.Parent
        and Humanoid.Health > 0 do

        local CurrentRoot =
            GetRoot()

        if not CurrentRoot then
            break
        end

        local Distance =
            (
                EnemyRoot.Position -
                CurrentRoot.Position
            ).Magnitude

        if Distance > 18 then

            local NewCFrame =
                EnemyRoot.CFrame *
                CFrame.new(0, 6, 0)

            if Mode == "Tween" then

                SmoothMove(NewCFrame)

            else

                TeleportMove(NewCFrame)

            end

        end

        if os.clock() - StartTime > 25 then
            break
        end

        task.wait(0.12)

    end

    return true

end
--// Part 3/3

local function RunAutoRaid()

    if not AutoRaid
        or not Enabled
        or not IsRaidActive() then

        return

    end

    RaidBusy = true
    RaidToken += 1

    while Enabled
        and AutoRaid
        and IsRaidActive() do

        local Enemy =
            GetRaidTarget()

        if Enemy then

            AttackRaidTarget(Enemy)

        else

            local Island =
                GetRaidIsland()

            if Island then

                local Success,
                    IslandCFrame =
                    pcall(function()

                        return Island:GetPivot()

                    end)

                if Success and IslandCFrame then

                    local Target =
                        IslandCFrame *
                        CFrame.new(0, 67, 0)

                    if Mode == "Tween" then

                        SmoothMove(Target)

                    else

                        TeleportMove(Target)

                    end

                end

            end

            task.wait(0.2)

        end

    end

    StopMovement()
    RaidBusy = false

end

--==================================================
-- MAIN CONTROLLER
--==================================================

task.spawn(function()

    while ScreenGui.Parent do

        if Enabled then

            if AutoRaid
                and IsRaidActive() then

                if not RaidBusy then

                    task.spawn(
                        RunAutoRaid
                    )

                end

                task.wait(0.15)

            elseif not RaidBusy then

                local Chest =
                    GetChest()

                if Chest then

                    local Success,
                        ChestCFrame =
                        pcall(function()

                            return Chest:GetPivot()

                        end)

                    if Success and ChestCFrame then

                        if Mode == "Tween" then

                            SmoothMove(
                                ChestCFrame
                            )

                        else

                            TeleportMove(
                                ChestCFrame
                            )

                        end

                        task.wait(0.08)

                        local Root =
                            GetRoot()

                        if Root
                            and Chest.Parent then

                            if typeof(
                                firetouchinterest
                            ) == "function" then

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

                            if typeof(
                                firesignal
                            ) == "function" then

                                pcall(function()

                                    firesignal(
                                        Chest.Touched,
                                        Root
                                    )

                                end)

                            end

                        end

                    end

                else

                    task.wait(0.4)

                end

            end

        else

            task.wait(0.15)

        end

    end

end)

--==================================================
-- START / STOP
--==================================================

Toggle.MouseButton1Click:Connect(
    function()

        Enabled = not Enabled

        if Enabled then

            Toggle.Text = "STOP"

            Toggle.BackgroundColor3 =
                Color3.fromRGB(
                    45,
                    110,
                    65
                )

            Status.Text =
                "● Status: ON"

            Status.TextColor3 =
                Color3.fromRGB(
                    80,
                    255,
                    120
                )

        else

            StopMovement()

            Toggle.Text =
                "START"

            Toggle.BackgroundColor3 =
                Color3.fromRGB(
                    45,
                    45,
                    55
                )

            Status.Text =
                "● Status: OFF"

            Status.TextColor3 =
                Color3.fromRGB(
                    255,
                    80,
                    80
                )

        end

    end
)

--==================================================
-- AUTO RAID TOGGLE
--==================================================

RaidButton.MouseButton1Click:Connect(
    function()

        AutoRaid = not AutoRaid

        if AutoRaid then

            RaidButton.Text =
                "AUTO RAID: ON"

            RaidButton.BackgroundColor3 =
                Color3.fromRGB(
                    120,
                    55,
                    180
                )

        else

            RaidButton.Text =
                "AUTO RAID: OFF"

            RaidButton.BackgroundColor3 =
                Color3.fromRGB(
                    45,
                    45,
                    55
                )

            if RaidBusy then
                StopMovement()
            end

        end

    end
)

--==================================================
-- MODE
--==================================================

ModeButton.MouseButton1Click:Connect(
    function()

        StopMovement()

        if Mode == "Tween" then

            Mode = "Teleport"
            ModeButton.Text = "TELEPORT"

        else

            Mode = "Tween"
            ModeButton.Text = "TWEEN"

        end

    end
)

--==================================================
-- SPEED
--==================================================

SpeedBox.FocusLost:Connect(
    function()

        local Number =
            tonumber(
                SpeedBox.Text
            )

        if Number then

            TweenSpeed =
                math.clamp(
                    Number,
                    1,
                    10000
                )

            SpeedBox.Text =
                tostring(
                    TweenSpeed
                )

        else

            SpeedBox.Text =
                tostring(
                    TweenSpeed
                )

        end

    end
)

--==================================================
-- MINIMIZE
--==================================================

local Minimized = false
local OriginalSize = Main.Size

Minimize.MouseButton1Click:Connect(
    function()

        Minimized = not Minimized

        if Minimized then

            Content.Visible = false

            Main.Size =
                UDim2.new(
                    0,
                    280,
                    0,
                    40
                )

            Minimize.Text = "+"

        else

            Content.Visible = true

            Main.Size =
                OriginalSize

            Minimize.Text = "—"

        end

    end
)

--==================================================
-- CLOSE
--==================================================

Close.MouseButton1Click:Connect(
    function()

        Enabled = false
        AutoRaid = false

        StopMovement()

        ScreenGui:Destroy()

    end
)
