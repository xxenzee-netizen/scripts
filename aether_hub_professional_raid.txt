local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Player = Players.LocalPlayer
local scriptRunning = true
local speed = 200
local flyHeight = 10
local active = false
local activeTween = nil
local targetMobs = {} 
local attackMultiplier = 1 

local NotifierEnabled = false
local CurrentFruit = nil
local WorkspaceConnection = nil

-----------------------------------
-- PERFORMANCE OPTIMIZATION (LAG FIX)
-----------------------------------
-- Drastically reduces lag by only checking relevant models instead of every descendant in the game
local function getPotentialNPCs()
    local npcs = {}
    local enemiesFolder = Workspace:FindFirstChild("Enemies")
    if enemiesFolder then
        for _, obj in ipairs(enemiesFolder:GetChildren()) do 
            table.insert(npcs, obj) 
        end
    end
    for _, obj in ipairs(Workspace:GetChildren()) do 
        if obj:IsA("Model") and obj ~= Player.Character then 
            table.insert(npcs, obj) 
        end 
    end
    return npcs
end

-----------------------------------
-- STRICT DAMAGEABLE NPC CHECK
-----------------------------------
local function IsDamageableNPC(model)
    if not model or not model:IsA("Model") then return false end
    if model == Player.Character then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    
    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("PrimaryPart") or model:FindFirstChild("Head")
    
    if not hum or not root then return false end
    if hum.Health <= 0 then return false end
    if hum.MaxHealth >= 999999 or hum.MaxHealth <= 0 then return false end
    
    local nameLower = model.Name:lower()
    local ignored = {"quest", "shop", "dealer", "manager", "captain", "citizen", "merchant", "setter", "bloxfruit", "gacha", "home", "spawn"}
    for _, keyword in ipairs(ignored) do
        if nameLower:find(keyword) then return false end
    end
    
    return true
end

-----------------------------------
-- UI SETUP (BLACK UP / PURPLE DOWN)
-----------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZenithHubGUI"
ScreenGui.ResetOnSpawn = false

local coreGuiExists, coreGui = pcall(function() return game:GetService("CoreGui") end)
if coreGuiExists and coreGui then
    ScreenGui.Parent = coreGui
else
    ScreenGui.Parent = Player:WaitForChild("PlayerGui")
end

-- Confirmation Menu Overlay
local ConfirmOverlay = Instance.new("Frame")
ConfirmOverlay.Size = UDim2.new(1, 0, 1, 0)
ConfirmOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ConfirmOverlay.BackgroundTransparency = 0.6
ConfirmOverlay.Visible = false
ConfirmOverlay.ZIndex = 50
ConfirmOverlay.Parent = ScreenGui

local ConfirmBox = Instance.new("Frame")
ConfirmBox.Size = UDim2.new(0, 260, 0, 120)
ConfirmBox.Position = UDim2.new(0.5, -130, 0.5, -60)
ConfirmBox.BackgroundColor3 = Color3.fromRGB(20, 10, 30)
ConfirmBox.ZIndex = 51
ConfirmBox.Parent = ConfirmOverlay
Instance.new("UICorner", ConfirmBox).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", ConfirmBox).Color = Color3.fromRGB(150, 50, 255)

local ConfirmText = Instance.new("TextLabel")
ConfirmText.Size = UDim2.new(1, -20, 0, 60)
ConfirmText.Position = UDim2.new(0, 10, 0, 10)
ConfirmText.BackgroundTransparency = 1
ConfirmText.Text = "Are you sure you want to close the script?"
ConfirmText.TextColor3 = Color3.fromRGB(255, 255, 255)
ConfirmText.TextWrapped = true
ConfirmText.Font = Enum.Font.GothamBold
ConfirmText.TextSize = 14
ConfirmText.ZIndex = 52
ConfirmText.Parent = ConfirmBox

local YesBtn = Instance.new("TextButton")
YesBtn.Size = UDim2.new(0, 100, 0, 30)
YesBtn.Position = UDim2.new(0, 20, 1, -40)
YesBtn.BackgroundColor3 = Color3.fromRGB(120, 30, 160)
YesBtn.Text = "Yes"
YesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
YesBtn.Font = Enum.Font.GothamBold
YesBtn.ZIndex = 52
YesBtn.Parent = ConfirmBox
Instance.new("UICorner", YesBtn).CornerRadius = UDim.new(0, 4)

local NoBtn = Instance.new("TextButton")
NoBtn.Size = UDim2.new(0, 100, 0, 30)
NoBtn.Position = UDim2.new(1, -120, 1, -40)
NoBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
NoBtn.Text = "No"
NoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
NoBtn.Font = Enum.Font.GothamBold
NoBtn.ZIndex = 52
NoBtn.Parent = ConfirmBox
Instance.new("UICorner", NoBtn).CornerRadius = UDim.new(0, 4)

-- Main Window / Tabbed UI
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0.86, 0, 0.76, 0)
MainFrame.Position = UDim2.new(0.07, 0, 0.12, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 14)

local BgGradient = Instance.new("UIGradient", MainFrame)
BgGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 9, 14)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(31, 13, 48))
})
BgGradient.Rotation = 135

-- Header
local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -110, 0, 28)
TitleLabel.Position = UDim2.new(0, 18, 0, 7)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "✦ AETHER"
TitleLabel.TextColor3 = Color3.fromRGB(242, 235, 255)
TitleLabel.TextSize = 15
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = MainFrame

local CreatorLabel = Instance.new("TextLabel")
CreatorLabel.Size = UDim2.new(1, -110, 0, 18)
CreatorLabel.Position = UDim2.new(0, 19, 0, 28)
CreatorLabel.BackgroundTransparency = 1
CreatorLabel.Text = "by NotThatAnik"
CreatorLabel.TextColor3 = Color3.fromRGB(135, 125, 155)
CreatorLabel.TextSize = 9
CreatorLabel.Font = Enum.Font.Gotham
CreatorLabel.TextXAlignment = Enum.TextXAlignment.Left
CreatorLabel.Parent = MainFrame

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.new(0, 30, 0, 28)
MinimizeBtn.Position = UDim2.new(1, -68, 0, 8)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(30, 28, 38)
MinimizeBtn.Text = "—"
MinimizeBtn.TextColor3 = Color3.fromRGB(230, 225, 240)
MinimizeBtn.TextSize = 16
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.Parent = MainFrame
Instance.new("UICorner", MinimizeBtn).CornerRadius = UDim.new(0, 6)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0, 8)
CloseBtn.BackgroundColor3 = Color3.fromRGB(115, 35, 48)
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Color3.fromRGB(255, 240, 245)
CloseBtn.TextSize = 18
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = MainFrame
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

-- Left sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 145, 1, -60)
Sidebar.Position = UDim2.new(0, 12, 0, 50)
Sidebar.BackgroundColor3 = Color3.fromRGB(14, 15, 22)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 10)

local SidebarStroke = Instance.new("UIStroke", Sidebar)
SidebarStroke.Color = Color3.fromRGB(37, 31, 50)
SidebarStroke.Thickness = 1

local SidebarTitle = Instance.new("TextLabel")
SidebarTitle.Size = UDim2.new(1, -20, 0, 24)
SidebarTitle.Position = UDim2.new(0, 12, 0, 9)
SidebarTitle.BackgroundTransparency = 1
SidebarTitle.Text = "NAVIGATION"
SidebarTitle.TextColor3 = Color3.fromRGB(105, 98, 120)
SidebarTitle.TextSize = 8
SidebarTitle.Font = Enum.Font.GothamBold
SidebarTitle.TextXAlignment = Enum.TextXAlignment.Left
SidebarTitle.Parent = Sidebar

local TabHolder = Instance.new("Frame")
TabHolder.Size = UDim2.new(1, -10, 1, -46)
TabHolder.Position = UDim2.new(0, 5, 0, 36)
TabHolder.BackgroundTransparency = 1
TabHolder.Parent = Sidebar

local TabLayout = Instance.new("UIListLayout", TabHolder)
TabLayout.Padding = UDim.new(0, 7)
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function createTab(text, icon, order)
    local btn = Instance.new("TextButton")
    btn.Name = text .. "Tab"
    btn.LayoutOrder = order
    btn.Size = UDim2.new(1, 0, 0, 42)
    btn.BackgroundColor3 = Color3.fromRGB(20, 20, 29)
    btn.Text = "   " .. icon .. "   " .. text
    btn.TextColor3 = Color3.fromRGB(168, 162, 180)
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamSemibold
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.AutoButtonColor = false
    btn.Parent = TabHolder
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local accent = Instance.new("Frame")
    accent.Name = "Accent"
    accent.Size = UDim2.new(0, 3, 0.6, 0)
    accent.Position = UDim2.new(0, 0, 0.2, 0)
    accent.BackgroundColor3 = Color3.fromRGB(130, 70, 255)
    accent.Visible = false
    accent.BorderSizePixel = 0
    accent.Parent = btn
    Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 2)

    return btn
end

local StatusTab = createTab("Status", "▣", 1)
local FarmingTab = createTab("Farming", "⚒", 2)
local RaidsTab = createTab("Raids", "◇", 3)
local FruitsTab = createTab("Fruits", "✦", 4)

-- Right content area
local PageHolder = Instance.new("Frame")
PageHolder.Name = "PageHolder"
PageHolder.Size = UDim2.new(1, -177, 1, -60)
PageHolder.Position = UDim2.new(0, 165, 0, 50)
PageHolder.BackgroundColor3 = Color3.fromRGB(9, 10, 15)
PageHolder.BorderSizePixel = 0
PageHolder.Parent = MainFrame
Instance.new("UICorner", PageHolder).CornerRadius = UDim.new(0, 10)

local PageStroke = Instance.new("UIStroke", PageHolder)
PageStroke.Color = Color3.fromRGB(34, 29, 45)
PageStroke.Thickness = 1

local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.Size = UDim2.new(1, -10, 1, -10)
    page.Position = UDim2.new(0, 5, 0, 5)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(105, 65, 180)
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.Visible = false
    page.Parent = PageHolder

    local padding = Instance.new("UIPadding", page)
    padding.PaddingLeft = UDim.new(0, 11)
    padding.PaddingRight = UDim.new(0, 11)
    padding.PaddingTop = UDim.new(0, 12)
    padding.PaddingBottom = UDim.new(0, 18)

    return page
end

local StatusPage = createPage("StatusPage")
local FarmingPage = createPage("FarmingPage")
local RaidsPage = createPage("RaidsPage")
local FruitsPage = createPage("FruitsPage")

-- Existing code uses this name for the farming controls.
local Container = FarmingPage

local Pages = {
    Status = StatusPage,
    Farming = FarmingPage,
    Raids = RaidsPage,
    Fruits = FruitsPage
}

local Tabs = {
    Status = StatusTab,
    Farming = FarmingTab,
    Raids = RaidsTab,
    Fruits = FruitsTab
}

local function showTab(name)
    for pageName, page in pairs(Pages) do
        page.Visible = (pageName == name)
    end

    for tabName, tab in pairs(Tabs) do
        local accent = tab:FindFirstChild("Accent")

        if tabName == name then
            tab.BackgroundColor3 = Color3.fromRGB(34, 25, 48)
            tab.TextColor3 = Color3.fromRGB(245, 240, 255)
            if accent then accent.Visible = true end
        else
            tab.BackgroundColor3 = Color3.fromRGB(20, 20, 29)
            tab.TextColor3 = Color3.fromRGB(168, 162, 180)
            if accent then accent.Visible = false end
        end
    end
end

StatusTab.MouseButton1Click:Connect(function() showTab("Status") end)
FarmingTab.MouseButton1Click:Connect(function() showTab("Farming") end)
RaidsTab.MouseButton1Click:Connect(function() showTab("Raids") end)
FruitsTab.MouseButton1Click:Connect(function() showTab("Fruits") end)

showTab("Status")

-- Status is intentionally empty for future additions.
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -28, 0, 1)
StatusLabel.Position = UDim2.new(0, 14, 0, 1)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = ""
StatusLabel.Visible = true
StatusLabel.Parent = StatusPage

-- Farming page
local TargetLabel = Instance.new("TextLabel")
TargetLabel.Size = UDim2.new(1, -28, 0, 24)
TargetLabel.Position = UDim2.new(0.05, 0, 0, 8)
TargetLabel.BackgroundTransparency = 1
TargetLabel.Text = "Target: All Damageable"
TargetLabel.TextColor3 = Color3.fromRGB(200, 170, 230)
TargetLabel.TextSize = 12
TargetLabel.Font = Enum.Font.Gotham
TargetLabel.TextTruncate = Enum.TextTruncate.AtEnd
TargetLabel.Parent = FarmingPage

local DropdownBtn = Instance.new("TextButton")
DropdownBtn.Size = UDim2.new(0.72, -4, 0, 36)
DropdownBtn.Position = UDim2.new(0, 14, 0, 42)
DropdownBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 90)
DropdownBtn.Text = "Select Mobs (Multi)"
DropdownBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
DropdownBtn.TextSize = 12
DropdownBtn.Font = Enum.Font.GothamSemibold
DropdownBtn.Parent = FarmingPage
Instance.new("UICorner", DropdownBtn).CornerRadius = UDim.new(0, 6)

local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Size = UDim2.new(0.23, -4, 0, 36)
RefreshBtn.Position = UDim2.new(0.75, 0, 0, 42)
RefreshBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 180)
RefreshBtn.Text = "Refresh"
RefreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RefreshBtn.TextSize = 11
RefreshBtn.Font = Enum.Font.GothamBold
RefreshBtn.Parent = FarmingPage
Instance.new("UICorner", RefreshBtn).CornerRadius = UDim.new(0, 6)

local SpeedBox = Instance.new("TextBox")
SpeedBox.Size = UDim2.new(1, -28, 0, 36)
SpeedBox.Position = UDim2.new(0, 14, 0, 86)
SpeedBox.BackgroundColor3 = Color3.fromRGB(20, 10, 35)
SpeedBox.Text = "Speed: " .. tostring(speed)
SpeedBox.TextColor3 = Color3.fromRGB(220, 200, 255)
SpeedBox.TextSize = 12
SpeedBox.Font = Enum.Font.Gotham
SpeedBox.Parent = FarmingPage
Instance.new("UICorner", SpeedBox).CornerRadius = UDim.new(0, 6)

local HeightBox = Instance.new("TextBox")
HeightBox.Size = UDim2.new(1, -28, 0, 36)
HeightBox.Position = UDim2.new(0, 14, 0, 130)
HeightBox.BackgroundColor3 = Color3.fromRGB(20, 10, 35)
HeightBox.Text = "Fly Height: " .. tostring(flyHeight)
HeightBox.TextColor3 = Color3.fromRGB(220, 200, 255)
HeightBox.TextSize = 12
HeightBox.Font = Enum.Font.Gotham
HeightBox.Parent = FarmingPage
Instance.new("UICorner", HeightBox).CornerRadius = UDim.new(0, 6)

local AtkMultBox = Instance.new("TextBox")
AtkMultBox.Size = UDim2.new(1, -28, 0, 36)
AtkMultBox.Position = UDim2.new(0, 14, 0, 174)
AtkMultBox.BackgroundColor3 = Color3.fromRGB(35, 10, 50)
AtkMultBox.Text = "Atk Multiplier: " .. tostring(attackMultiplier) .. "x"
AtkMultBox.TextColor3 = Color3.fromRGB(255, 150, 255)
AtkMultBox.TextSize = 12
AtkMultBox.Font = Enum.Font.GothamBold
AtkMultBox.Parent = FarmingPage
Instance.new("UICorner", AtkMultBox).CornerRadius = UDim.new(0, 6)

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -28, 0, 42)
ToggleButton.Position = UDim2.new(0, 14, 0, 224)
ToggleButton.BackgroundColor3 = Color3.fromRGB(120, 30, 160)
ToggleButton.Text = "Start Auto Farm"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.TextSize = 12
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Parent = FarmingPage
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0, 8)

-- Raids page
local RaidTitle = Instance.new("TextLabel")
RaidTitle.Size = UDim2.new(1, -28, 0, 32)
RaidTitle.Position = UDim2.new(0, 14, 0, 12)
RaidTitle.BackgroundTransparency = 1
RaidTitle.Text = "Raid Automation"
RaidTitle.TextColor3 = Color3.fromRGB(225, 205, 245)
RaidTitle.TextSize = 18
RaidTitle.Font = Enum.Font.GothamBold
RaidTitle.TextXAlignment = Enum.TextXAlignment.Left
RaidTitle.Parent = RaidsPage

local RaidInfo = Instance.new("TextLabel")
RaidInfo.Size = UDim2.new(1, -28, 0, 46)
RaidInfo.Position = UDim2.new(0, 14, 0, 52)
RaidInfo.BackgroundTransparency = 1
RaidInfo.Text = "Automatically attacks raid NPCs and moves between raid islands."
RaidInfo.TextColor3 = Color3.fromRGB(170, 160, 185)
RaidInfo.TextSize = 12
RaidInfo.TextWrapped = true
RaidInfo.Font = Enum.Font.Gotham
RaidInfo.TextXAlignment = Enum.TextXAlignment.Left
RaidInfo.Parent = RaidsPage

local AutoRaidButton = Instance.new("TextButton")
AutoRaidButton.Size = UDim2.new(1, -28, 0, 40)
AutoRaidButton.Position = UDim2.new(0, 14, 0, 120)
AutoRaidButton.BackgroundColor3 = Color3.fromRGB(45, 25, 70)
AutoRaidButton.Text = "Auto Raid: OFF"
AutoRaidButton.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoRaidButton.TextSize = 12
AutoRaidButton.Font = Enum.Font.GothamBold
AutoRaidButton.Parent = RaidsPage
Instance.new("UICorner", AutoRaidButton).CornerRadius = UDim.new(0, 8)

-- Fruits page
local FruitTitle = Instance.new("TextLabel")
FruitTitle.Size = UDim2.new(1, -28, 0, 32)
FruitTitle.Position = UDim2.new(0, 14, 0, 12)
FruitTitle.BackgroundTransparency = 1
FruitTitle.Text = "Fruit Tools"
FruitTitle.TextColor3 = Color3.fromRGB(225, 205, 245)
FruitTitle.TextSize = 18
FruitTitle.Font = Enum.Font.GothamBold
FruitTitle.TextXAlignment = Enum.TextXAlignment.Left
FruitTitle.Parent = FruitsPage

local NotifierBtn = Instance.new("TextButton")
NotifierBtn.Size = UDim2.new(1, -28, 0, 44)
NotifierBtn.Position = UDim2.new(0, 14, 0, 58)
NotifierBtn.BackgroundColor3 = Color3.fromRGB(45, 25, 70)
NotifierBtn.Text = "Fruit Notifier: OFF"
NotifierBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
NotifierBtn.TextSize = 12
NotifierBtn.Font = Enum.Font.GothamBold
NotifierBtn.Parent = FruitsPage
Instance.new("UICorner", NotifierBtn).CornerRadius = UDim.new(0, 8)

local TPBtn = Instance.new("TextButton")
TPBtn.Size = UDim2.new(1, -28, 0, 44)
TPBtn.Position = UDim2.new(0, 14, 0, 112)
TPBtn.BackgroundColor3 = Color3.fromRGB(90, 20, 150)
TPBtn.Text = "TP to Spawned Fruit"
TPBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TPBtn.TextSize = 13
TPBtn.Font = Enum.Font.GothamBold
TPBtn.Parent = FruitsPage
Instance.new("UICorner", TPBtn).CornerRadius = UDim.new(0, 8)

local FruitHint = Instance.new("TextLabel")
FruitHint.Size = UDim2.new(1, -28, 0, 55)
FruitHint.Position = UDim2.new(0, 14, 0, 168)
FruitHint.BackgroundTransparency = 1
FruitHint.Text = "Fruit detection and teleport controls are kept here."
FruitHint.TextColor3 = Color3.fromRGB(160, 150, 175)
FruitHint.TextSize = 12
FruitHint.TextWrapped = true
FruitHint.Font = Enum.Font.Gotham
FruitHint.TextXAlignment = Enum.TextXAlignment.Left
FruitHint.Parent = FruitsPage

local isMinimized = false
MinimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        MinimizeBtn.Text = "+"
        MainFrame.Size = UDim2.new(0.86, 0, 0, 44)
        Sidebar.Visible = false
        PageHolder.Visible = false
    else
        MinimizeBtn.Text = "-"
        MainFrame.Size = UDim2.new(0.86, 0, 0.76, 0)
        Sidebar.Visible = true
        PageHolder.Visible = true
    end
end)

CloseBtn.MouseButton1Click:Connect(function() ConfirmOverlay.Visible = true end)
NoBtn.MouseButton1Click:Connect(function() ConfirmOverlay.Visible = false end)

local MobScrollFrame = Instance.new("ScrollingFrame")
MobScrollFrame.Size = UDim2.new(0.9, 0, 0, 140)
MobScrollFrame.Position = UDim2.new(0.05, 0, 0, 58)
MobScrollFrame.BackgroundColor3 = Color3.fromRGB(20, 10, 30)
MobScrollFrame.BorderSizePixel = 0
MobScrollFrame.ScrollBarThickness = 4
MobScrollFrame.Visible = false
MobScrollFrame.ZIndex = 10
MobScrollFrame.Parent = Container
Instance.new("UICorner", MobScrollFrame).CornerRadius = UDim.new(0, 6)

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = MobScrollFrame
UIListLayout.Padding = UDim.new(0, 3)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function GetAvailableMobs()
    local mobs = {}
    local hash = {}
    for _, obj in ipairs(getPotentialNPCs()) do
        if IsDamageableNPC(obj) then
            if not hash[obj.Name] then
                hash[obj.Name] = true
                table.insert(mobs, obj.Name)
            end
        end
    end
    table.sort(mobs)
    return mobs
end

local function updateTargetLabel()
    local names = {}
    for k, v in pairs(targetMobs) do 
        if v then table.insert(names, k) end 
    end
    if #names > 0 then
        TargetLabel.Text = "Target: " .. table.concat(names, ", ")
    else
        TargetLabel.Text = "Target: All Damageable"
    end
end

local function populateDropdown()
    for _, child in ipairs(MobScrollFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    local mobs = GetAvailableMobs()
    local function createBtn(text, tName, order)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, 26)
        btn.BackgroundColor3 = (targetMobs[tName] or (tName == "" and next(targetMobs) == nil)) and Color3.fromRGB(130, 40, 220) or Color3.fromRGB(40, 20, 60)
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(230, 230, 230)
        btn.TextSize = 11
        btn.Font = Enum.Font.Gotham
        btn.LayoutOrder = order
        btn.ZIndex = 11
        btn.Parent = MobScrollFrame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        
        btn.MouseButton1Click:Connect(function()
            if tName == "" then
                targetMobs = {}
                for _, b in ipairs(MobScrollFrame:GetChildren()) do
                    if b:IsA("TextButton") then b.BackgroundColor3 = Color3.fromRGB(40, 20, 60) end
                end
                btn.BackgroundColor3 = Color3.fromRGB(130, 40, 220)
            else
                targetMobs[tName] = not targetMobs[tName]
                btn.BackgroundColor3 = targetMobs[tName] and Color3.fromRGB(130, 40, 220) or Color3.fromRGB(40, 20, 60)
                
                for _, b in ipairs(MobScrollFrame:GetChildren()) do
                    if b:IsA("TextButton") and b.Text == "All Damageable" then
                        b.BackgroundColor3 = Color3.fromRGB(40, 20, 60)
                    end
                end
            end
            updateTargetLabel()
        end)
    end

    createBtn("All Damageable", "", 0)
    for i, mobName in ipairs(mobs) do
        createBtn(mobName, mobName, i)
    end
    MobScrollFrame.CanvasSize = UDim2.new(0, 0, 0, (#mobs + 1) * 29)
end

DropdownBtn.MouseButton1Click:Connect(function()
    populateDropdown()
    MobScrollFrame.Visible = not MobScrollFrame.Visible
end)
RefreshBtn.MouseButton1Click:Connect(populateDropdown)

SpeedBox.FocusLost:Connect(function()
    local num = tonumber(SpeedBox.Text:match("%d+"))
    if num and num > 0 then speed = num end
    SpeedBox.Text = "Speed: " .. tostring(speed)
end)

HeightBox.FocusLost:Connect(function()
    local num = tonumber(HeightBox.Text:match("%d+"))
    if num and num >= 0 then flyHeight = num end
    HeightBox.Text = "Fly Height: " .. tostring(flyHeight)
end)

AtkMultBox.FocusLost:Connect(function()
    local num = tonumber(AtkMultBox.Text:match("%d+"))
    if num and num > 0 then attackMultiplier = math.clamp(num, 1, 100) end
    AtkMultBox.Text = "Atk Multiplier: " .. tostring(attackMultiplier) .. "x"
end)

populateDropdown()
-----------------------------------
-- FRUIT NOTIFIER & TP LOGIC
-----------------------------------
local function getFruitName(fruit)
    local fruitName = "Unknown Fruit"
    for _, descendant in ipairs(fruit:GetChildren()) do
        if descendant:IsA("MeshPart") and string.sub(descendant.Name, 1, 7) == "Meshes/" then
            local i = string.find(descendant.Name, '_')
            fruitName = i and string.sub(descendant.Name, 8, i - 1) or string.sub(descendant.Name, 8)
            local lowerName = string.lower(fruitName)
            if lowerName == "magu" then fruitName = "Magma"
            elseif lowerName == "smouke" then fruitName = "Smoke"
            elseif lowerName == "quaketest" then fruitName = "Quake"
            end
            fruitName = fruitName:gsub("^%l", string.upper) .. " Fruit"
            fruitName = fruitName:gsub("%d+", '')
            break
        end
    end
    if fruitName == "Unknown Fruit" then fruitName = fruit.Name end
    return fruitName
end

local function scanForFruits()
    CurrentFruit = nil
    for _, child in ipairs(Workspace:GetChildren()) do
        if string.find(child.Name, "Fruit") or child.Name == "Fruit " then
            local handle = child:FindFirstChild("Handle") or child:FindFirstChildOfClass("Part") or child:FindFirstChildOfClass("MeshPart")
            if handle then
                CurrentFruit = child
                break
            end
        end
    end
end

local function trackFruit(fruit)
    CurrentFruit = fruit
    local handle = fruit:WaitForChild("Handle", 5) or fruit:FindFirstChildOfClass("Part") or fruit:FindFirstChildOfClass("MeshPart")
    if not handle then return end
    
    local name = getFruitName(fruit)
    task.spawn(function()
        while scriptRunning and NotifierEnabled and fruit and fruit.Parent == Workspace do
            if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                local pos = handle.Position
                local dist = math.floor((Player.Character.HumanoidRootPart.Position - pos).Magnitude * 0.15)
                StatusLabel.Text = string.format("%s Detected!\nDist: %dm away", name, dist)
            end
            task.wait(0.3)
        end
        if scriptRunning and NotifierEnabled then
            scanForFruits()
            if not CurrentFruit then
                StatusLabel.Text = "Status: No fruit currently spawned"
            end
        end
    end)
end

NotifierBtn.MouseButton1Click:Connect(function()
    NotifierEnabled = not NotifierEnabled
    if NotifierEnabled then
        NotifierBtn.Text = "Fruit Notifier: ON"
        NotifierBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 255)
        StatusLabel.Text = "Status: Searching for fruits..."
        
        WorkspaceConnection = Workspace.ChildAdded:Connect(function(child)
            if string.find(child.Name, "Fruit") or child.Name == "Fruit " then
                trackFruit(child)
            end
        end)
        
        scanForFruits()
        if CurrentFruit then trackFruit(CurrentFruit) else StatusLabel.Text = "Status: No fruit currently spawned" end
    else
        NotifierBtn.Text = "Fruit Notifier: OFF"
        NotifierBtn.BackgroundColor3 = Color3.fromRGB(45, 25, 70)
        StatusLabel.Text = "Status: Disabled"
        if WorkspaceConnection then WorkspaceConnection:Disconnect() WorkspaceConnection = nil end
        CurrentFruit = nil
    end
end)

-----------------------------------
-- OPTIMIZED FAST ATTACK (BUG & LAG FREE)
-----------------------------------
_G.FastAttack = true
if _G.FastAttack then
    local _ENV = (getgenv or getrenv or getfenv)()
    local function SafeWaitForChild(parent, childName)
        local success, result = pcall(function() return parent:WaitForChild(childName) end)
        return result
    end
    local Remotes = SafeWaitForChild(ReplicatedStorage, "Remotes")
    local Modules = SafeWaitForChild(ReplicatedStorage, "Modules")
    local Net = SafeWaitForChild(Modules, "Net")

    local Settings = { AutoClick = true, ClickDelay = 0.0000000000001 }
    local Module = {}

    Module.FastAttack = (function()
        if _ENV.rz_FastAttack then return _ENV.rz_FastAttack end
        local FastAttack = { Distance = 60, attackMobs = true, attackPlayers = true, Equipped = nil }
        local RegisterAttack = SafeWaitForChild(Net, "RE/RegisterAttack")
        local RegisterHit = SafeWaitForChild(Net, "RE/RegisterHit")

        local function IsAlive(character)
            return character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0
        end

        function FastAttack:Attack(BasePart, OthersEnemies)
            if not BasePart or #OthersEnemies == 0 then return end
            for i = 1, attackMultiplier do
                task.spawn(function()
                    if RegisterAttack then RegisterAttack:FireServer(Settings.ClickDelay or 0) end
                    if RegisterHit then RegisterHit:FireServer(BasePart, OthersEnemies) end
                end)
            end
        end

        function FastAttack:AttackNearest()
            local OthersEnemies = {}
            local BasePart = nil
            local char = Player.Character
            if not char or not char:FindFirstChild("HumanoidRootPart") then return end
            
            -- Only iterate optimized list, never full Descendants to prevent lag
            for _, model in ipairs(getPotentialNPCs()) do
                if IsDamageableNPC(model) then
                    if next(targetMobs) == nil or targetMobs[model.Name] then
                        local Head = model:FindFirstChild("Head")
                        if Head and Player:DistanceFromCharacter(Head.Position) < FastAttack.Distance then
                            table.insert(OthersEnemies, { model, Head })
                            if not BasePart then BasePart = Head end
                        end
                    end
                end
            end

            local equippedWeapon = char:FindFirstChildOfClass("Tool")
            if equippedWeapon and equippedWeapon:FindFirstChild("LeftClickRemote") then
                for _, enemyData in ipairs(OthersEnemies) do
                    local enemy = enemyData[1]
                    local hrp = enemy:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local direction = (hrp.Position - char:GetPivot().Position).Unit
                        for i = 1, attackMultiplier do
                            task.spawn(function()
                                pcall(function() equippedWeapon.LeftClickRemote:FireServer(direction, 1) end)
                            end)
                        end
                    end
                end
            elseif #OthersEnemies > 0 then
                self:Attack(BasePart, OthersEnemies)
            end
        end

        function FastAttack:BladeHits()
            local Equipped = IsAlive(Player.Character) and Player.Character:FindFirstChildOfClass("Tool")
            if Equipped and Equipped.ToolTip ~= "Gun" then
                self:AttackNearest()
            end
        end

        task.spawn(function()
            while scriptRunning and task.wait(Settings.ClickDelay) do
                if active and Settings.AutoClick then
                    FastAttack:BladeHits()
                end
            end
        end)

        _ENV.rz_FastAttack = FastAttack
        return FastAttack
    end)()
end

local remote, idremote
pcall(function()
    for _, v in next, ({ReplicatedStorage:FindFirstChild("Util"), ReplicatedStorage:FindFirstChild("Common"), ReplicatedStorage:FindFirstChild("Remotes"), ReplicatedStorage:FindFirstChild("Assets"), ReplicatedStorage:FindFirstChild("FX")}) do
        if v then
            for _, n in next, v:GetChildren() do
                if n:IsA("RemoteEvent") and n:GetAttribute("Id") then
                    remote, idremote = n, n:GetAttribute("Id")
                end
            end
            v.ChildAdded:Connect(function(n)
                if n:IsA("RemoteEvent") and n:GetAttribute("Id") then
                    remote, idremote = n, n:GetAttribute("Id")
                end
            end)
        end
    end
end)

-- Optimized Melee Loop to prevent freezing
task.spawn(function()
    while scriptRunning and task.wait(0.1) do
        if not active then continue end 
        local char = Player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        
        local parts = {}
        for _, model in ipairs(getPotentialNPCs()) do
            if IsDamageableNPC(model) then
                if next(targetMobs) == nil or targetMobs[model.Name] then
                    local hrp = model:FindFirstChild("HumanoidRootPart")
                    if hrp and (hrp.Position - root.Position).Magnitude <= 65 then
                        for _, _v in ipairs(model:GetChildren()) do
                            if _v:IsA("BasePart") then
                                parts[#parts+1] = {model, _v}
                            end
                        end
                    end
                end
            end
        end

        local tool = char:FindFirstChildOfClass("Tool")
        if #parts > 0 and tool and (tool:GetAttribute("WeaponType") == "Melee" or tool:GetAttribute("WeaponType") == "Sword") then
            for i = 1, attackMultiplier do
                task.spawn(function()
                    pcall(function()
                        require(ReplicatedStorage.Modules.Net):RemoteEvent("RegisterHit", true)
                        ReplicatedStorage.Modules.Net["RE/RegisterAttack"]:FireServer()
                        local head = parts[1][1]:FindFirstChild("Head")
                        if not head then return end
                        ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(head, parts, {}, tostring(Player.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15))
                        if remote and idremote then
                            cloneref(remote):FireServer(string.gsub("RE/RegisterHit", ".", function(c)
                                return string.char(bit32.bxor(string.byte(c), math.floor(Workspace:GetServerTimeNow() / 10 % 10) + 1))
                            end),
                            bit32.bxor(idremote + 909090, ReplicatedStorage.Modules.Net.seed:InvokeServer() * 2), head, parts)
                        end
                    end)
                end)
            end
        end
    end
end)

-----------------------------------
-- NEAREST NPC MOVEMENT & SUSPENSION
-----------------------------------
local function applySuspension(hrp)
    local bv = hrp:FindFirstChild("AutoFarmVelocity")
    if not bv then
        bv = Instance.new("BodyVelocity")
        bv.Name = "AutoFarmVelocity"
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.Velocity = Vector3.new(0, 0, 0)
        bv.Parent = hrp
    end
end

local function removeSuspension()
    local char = Player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local bv = char.HumanoidRootPart:FindFirstChild("AutoFarmVelocity")
        if bv then bv:Destroy() end
    end
end

local function getNearestNPC()
    local char = Player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil, nil end

    local hrp = char.HumanoidRootPart
    local nearestHrp = nil
    local nearestHumanoid = nil
    local shortestDist = math.huge

    for _, model in ipairs(getPotentialNPCs()) do
        if IsDamageableNPC(model) then
            if next(targetMobs) == nil or targetMobs[model.Name] then
                local targetHrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("PrimaryPart")
                local hum = model:FindFirstChildOfClass("Humanoid")
                if targetHrp and hum then
                    local dist = (hrp.Position - targetHrp.Position).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        nearestHrp = targetHrp
                        nearestHumanoid = hum
                    end
                end
            end
        end
    end
    return nearestHrp, nearestHumanoid
end

local function tweenToPosition(targetCFrame)
    local char = Player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
    local hrp = char.HumanoidRootPart

    local distance = (hrp.Position - targetCFrame.Position).Magnitude
    local duration = math.max(distance / math.max(speed, 1), 0.01)

    applySuspension(hrp)

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    activeTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    activeTween:Play()

    local isDone = false
    local connection
    connection = activeTween.Completed:Connect(function()
        isDone = true
        if connection then connection:Disconnect() end
    end)

    while not isDone and active and scriptRunning do
        task.wait()
        if not char or not char:FindFirstChild("HumanoidRootPart") then
            if activeTween then activeTween:Cancel() end
            return false
        end
    end
    return active
end

local function startLoop()
    task.spawn(function()
        while active and scriptRunning do
            local targetHrp, targetHumanoid = getNearestNPC()
            if targetHrp and targetHumanoid then
                local overheadCFrame = targetHrp.CFrame * CFrame.new(0, flyHeight, 0)
                local arrived = tweenToPosition(overheadCFrame)
                
                if arrived and active and scriptRunning then
                    local char = Player.Character
                    if char and char:FindFirstChild("HumanoidRootPart") then
                        local hrp = char.HumanoidRootPart
                        applySuspension(hrp)
                        while active and scriptRunning and targetHumanoid and targetHumanoid.Health > 0 and targetHrp and targetHrp.Parent do
                            hrp.CFrame = targetHrp.CFrame * CFrame.new(0, flyHeight, 0)
                            task.wait()
                        end
                    end
                end
            else
                removeSuspension()
                task.wait(0.2)
            end
        end
        removeSuspension()
    end)
end


-----------------------------------
-- AUTO RAID (AUTO-FARM TWEEN + RAID ISLAND ROUTING)
-- Uses the same movement routine as Auto Farm and keeps the character directly
-- above the active raid NPC while the existing FastAttack module does damage.
local AutoRaidActive = false
local AutoRaidTween = nil
local AutoRaidMoveToken = 0
local RaidLastIsland = nil
local RaidLastNPC = nil

local function StopRaidTween()
    AutoRaidMoveToken += 1
    if AutoRaidTween then
        pcall(function() AutoRaidTween:Cancel() end)
        AutoRaidTween = nil
    end
    removeSuspension()
end

local function IsRaidActive()
    local playerGui = Player:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    local main = playerGui:FindFirstChild("Main")
    local topHUD = main and main:FindFirstChild("TopHUDList")
    local raidTimer = topHUD and topHUD:FindFirstChild("RaidTimer")
    return raidTimer ~= nil and raidTimer.Visible == true
end

-- This is the raid-island finder used by the original working raid logic:
-- search Island 5 -> Island 1 and choose the active island within 3000 studs.
local function GetRaidIsland()
    local worldOrigin = Workspace:FindFirstChild("_WorldOrigin")
    local locations = worldOrigin and worldOrigin:FindFirstChild("Locations")
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not locations or not root then return nil end

    for i = 5, 1, -1 do
        local island = locations:FindFirstChild("Island " .. tostring(i))
        if island then
            local position = island:IsA("BasePart") and island.Position
                or (island:IsA("Model") and island:GetPivot().Position)

            if position and (position - root.Position).Magnitude <= 3000 then
                return island
            end
        end
    end

    return nil
end

local function GetIslandCFrame(island)
    if not island then return nil end
    if island:IsA("BasePart") then
        return island.CFrame
    elseif island:IsA("Model") then
        return island:GetPivot()
    end
    return nil
end

-- Same tween pattern as Auto Farm: apply suspension, linear TweenService,
-- then keep the suspension active while travelling.
local function raidTweenToPosition(targetCFrame)
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return false end

    AutoRaidMoveToken += 1
    local token = AutoRaidMoveToken

    if AutoRaidTween then
        pcall(function() AutoRaidTween:Cancel() end)
        AutoRaidTween = nil
    end

    local distance = (root.Position - targetCFrame.Position).Magnitude
    if distance <= 5 then
        root.CFrame = targetCFrame
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    applySuspension(root)

    local duration = math.max(distance / math.max(speed, 1), 0.01)
    AutoRaidTween = TweenService:Create(
        root,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        {CFrame = targetCFrame}
    )

    local done = false
    local connection
    connection = AutoRaidTween.Completed:Connect(function()
        done = true
        if connection then
            connection:Disconnect()
            connection = nil
        end
    end)

    AutoRaidTween:Play()

    while AutoRaidActive and scriptRunning and not done do
        task.wait()

        if token ~= AutoRaidMoveToken then
            pcall(function() AutoRaidTween:Cancel() end)
            if connection then connection:Disconnect() end
            return false
        end

        char = Player.Character
        root = char and char:FindFirstChild("HumanoidRootPart")
        hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then
            pcall(function() AutoRaidTween:Cancel() end)
            return false
        end

        applySuspension(root)
    end

    AutoRaidTween = nil
    return AutoRaidActive and scriptRunning and token == AutoRaidMoveToken
end

local function GetNearestRaidNPC()
    local enemies = Workspace:FindFirstChild("Enemies")
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local island = GetRaidIsland()
    if not enemies or not root then return nil, nil, nil end

    local bestModel, bestRoot, bestHumanoid
    local bestDistance = math.huge

    for _, mob in ipairs(enemies:GetChildren()) do
        local humanoid = mob:FindFirstChildOfClass("Humanoid")
        local mobRoot = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart

        if humanoid and mobRoot and humanoid.Health > 0 then
            local fromPlayer = (root.Position - mobRoot.Position).Magnitude
            local islandCFrame = GetIslandCFrame(island)
            local fromIsland = islandCFrame and (islandCFrame.Position - mobRoot.Position).Magnitude or fromPlayer

            -- Prefer NPCs belonging to the active raid island. This prevents
            -- the raid loop from killing an unrelated mob and never advancing.
            if fromPlayer <= 1800 and fromIsland <= 1200 and fromPlayer < bestDistance then
                bestModel = mob
                bestRoot = mobRoot
                bestHumanoid = humanoid
                bestDistance = fromPlayer
            end
        end
    end

    return bestModel, bestRoot, bestHumanoid
end

local function RaidDamage(model)
    if not model or not model.Parent then return end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local head = model:FindFirstChild("Head")
    if not humanoid or humanoid.Health <= 0 or not head then return end

    local env = (getgenv and getgenv()) or (getrenv and getrenv()) or getfenv()
    local fastAttack = env.rz_FastAttack
    if fastAttack and fastAttack.Attack then
        pcall(function()
            fastAttack:Attack(head, {{model, head}})
        end)
    end
end

local function StartAutoRaid()
    task.spawn(function()
        local lastAttack = 0
        local noNpcTicks = 0

        while AutoRaidActive and scriptRunning do
            if not IsRaidActive() then
                StopRaidTween()
                task.wait(0.25)
                continue
            end

            local model, npcRoot, humanoid = GetNearestRaidNPC()

            if model and npcRoot and humanoid then
                RaidLastNPC = model
                noNpcTicks = 0

                local char = Player.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if not root then
                    task.wait(0.15)
                    continue
                end

                local aboveCFrame = npcRoot.CFrame * CFrame.new(0, flyHeight, 0)
                local distance = (root.Position - aboveCFrame.Position).Magnitude

                if distance > 7 then
                    raidTweenToPosition(aboveCFrame)
                end

                -- Exactly like Auto Farm: remain suspended and directly above
                -- the same NPC while it is alive, instead of free-falling.
                while AutoRaidActive
                    and scriptRunning
                    and model.Parent
                    and npcRoot.Parent
                    and humanoid.Parent
                    and humanoid.Health > 0 do

                    char = Player.Character
                    root = char and char:FindFirstChild("HumanoidRootPart")
                    if not root then break end

                    applySuspension(root)
                    root.CFrame = npcRoot.CFrame * CFrame.new(0, flyHeight, 0)

                    if os.clock() - lastAttack >= 0.08 then
                        RaidDamage(model)
                        lastAttack = os.clock()
                    end

                    task.wait()
                end

                removeSuspension()
                task.wait(0.05)
            else
                noNpcTicks += 1

                -- Don't immediately retarget a random mob. Wait briefly so the
                -- dead NPC is removed from Enemies, then use the ORIGINAL working
                -- raid-island finder and the Auto Farm tween.
                if noNpcTicks >= 3 then
                    local island = GetRaidIsland()
                    if island then
                        RaidLastIsland = island
                        local islandCFrame = GetIslandCFrame(island)
                        if islandCFrame then
                            local target = islandCFrame * CFrame.new(0, flyHeight + 55, 0)
                            raidTweenToPosition(target)
                        end
                        task.wait(0.12)
                    else
                        task.wait(0.2)
                    end
                    noNpcTicks = 0
                else
                    task.wait(0.05)
                end
            end
        end

        StopRaidTween()
    end)
end

AutoRaidButton.MouseButton1Click:Connect(function()
    AutoRaidActive = not AutoRaidActive

    if AutoRaidActive then
        AutoRaidButton.Text = "Auto Raid: ON"
        AutoRaidButton.BackgroundColor3 = Color3.fromRGB(115, 55, 190)
        StartAutoRaid()
    else
        AutoRaidButton.Text = "Auto Raid: OFF"
        AutoRaidButton.BackgroundColor3 = Color3.fromRGB(30, 24, 42)
        StopRaidTween()
    end
end)

-----------------------------------
-- TOGGLES, BINDINGS & CLOSE EVENT
-----------------------------------
local function pressJ()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.J, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.J, false, game)
    end)
end

local function toggleScript()
    active = not active
    pressJ()

    if active then
        ToggleButton.Text = "Stop Auto Farm"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(150, 50, 255)
        startLoop()
    else
        ToggleButton.Text = "Start Auto Farm"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(120, 30, 160)
        
        if activeTween then
            activeTween:Cancel()
            activeTween = nil
        end
        removeSuspension()
    end
end
ToggleButton.MouseButton1Click:Connect(toggleScript)

TPBtn.MouseButton1Click:Connect(function()
    if CurrentFruit then
        local handle = CurrentFruit:FindFirstChild("Handle") or CurrentFruit:FindFirstChildOfClass("Part") or CurrentFruit:FindFirstChildOfClass("MeshPart")
        if handle then
            if active then toggleScript() end
            if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                Player.Character.HumanoidRootPart.CFrame = CFrame.new(handle.Position + Vector3.new(0, 4, 0))
                StatusLabel.Text = "Teleported to " .. getFruitName(CurrentFruit)
            end
        end
    else
        StatusLabel.Text = "No active fruit to teleport to!"
    end
end)

YesBtn.MouseButton1Click:Connect(function()
    scriptRunning = false
    active = false
    AutoRaidActive = false
    StopRaidTween()
    if activeTween then activeTween:Cancel() end
    if WorkspaceConnection then WorkspaceConnection:Disconnect() end
    removeSuspension()
    ScreenGui:Destroy()
end)

local function setupDeathListener(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then
        hum.Died:Connect(function()
            AutoRaidActive = false
            StopRaidTween()
            removeSuspension()
        end)
    end
end

Player.CharacterAdded:Connect(function(newChar)
    if not scriptRunning then return end
    setupDeathListener(newChar)
    if active then
        task.wait(1.5)
        pressJ()
    end
end)

if Player.Character then
    setupDeathListener(Player.Character)
end
