local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- Luau/executor compatibility helpers.
-- Roblox Luau does not guarantee executor-only globals such as getgenv/getrenv/cloneref.
local function getSharedEnvironment()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then return env end
    end
    if type(getrenv) == "function" then
        local ok, env = pcall(getrenv)
        if ok and type(env) == "table" then return env end
    end
    if type(getfenv) == "function" then
        local ok, env = pcall(getfenv, 0)
        if ok and type(env) == "table" then return env end
    end
    return _G
end

local function cloneReference(instance)
    if type(cloneref) == "function" then
        local ok, result = pcall(cloneref, instance)
        if ok and result then return result end
    end
    return instance
end

local function safeFindRemote(parent, name)
    if not parent then return nil end
    local ok, result = pcall(function()
        return parent:FindFirstChild(name)
    end)
    return ok and result or nil
end

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
local AutoV4Enabled = false
local AutoV3Enabled = false
local WalkWaterEnabled = false
local setWaterWalk
local getFruitName
local ChestFarmEnabled = false
local ChestFarmMode = "Tween"
local ChestFarmSpeed = 180
local ChestFarmMoving = false
local ChestFarmTween = nil
local ChestFarmToken = 0

-----------------------------------
-- PERFORMANCE OPTIMIZATION (LAG FIX)
-----------------------------------
-- Drastically reduces lag by only checking relevant models instead of every descendant in the game
local function getPotentialNPCs()
    local npcs = {}
    local seen = {}
    local enemiesFolder = Workspace:FindFirstChild("Enemies")

    if enemiesFolder then
        for _, obj in ipairs(enemiesFolder:GetChildren()) do
            if obj:IsA("Model") and not seen[obj] then
                seen[obj] = true
                npcs[#npcs + 1] = obj
            end
        end
    end

    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= Player.Character and not seen[obj] then
            seen[obj] = true
            npcs[#npcs + 1] = obj
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
    if hum.MaxHealth <= 0 then return false end
    
    local nameLower = model.Name:lower()
    local ignored = {"quest", "shop", "dealer", "manager", "captain", "citizen", "merchant", "setter", "bloxfruit", "gacha", "home", "spawn"}
    for _, keyword in ipairs(ignored) do
        if nameLower:find(keyword) then return false end
    end
    
    return true
end

-----------------------------------
-- UI SETUP
-- Custom Redz-inspired layout: same visual language (compact dark rows,
-- left navigation, section headers, descriptions + right toggles), but
-- implemented entirely with native Roblox GUI objects.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local oldGui = nil
pcall(function()
    local pg = Player:FindFirstChild("PlayerGui")
    oldGui = pg and (pg:FindFirstChild("BantaiHubGUI") or pg:FindFirstChild("AetherHubGUI"))
    if oldGui then oldGui:Destroy() end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BantaiHubGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- PlayerGui is the reliable LocalScript parent. gethui is used when the
-- runtime provides it, without requiring an external UI library.
local parentGui = Player:WaitForChild("PlayerGui")
pcall(function()
    if typeof(gethui) == "function" then
        parentGui = gethui()
    end
end)
ScreenGui.Parent = parentGui

-- Theme
local COLORS = {
    Window = Color3.fromRGB(0, 0, 0),
    Sidebar = Color3.fromRGB(0, 0, 0),
    Row = Color3.fromRGB(8, 8, 8),
    RowHover = Color3.fromRGB(14, 14, 14),
    Content = Color3.fromRGB(0, 0, 0),
    Border = Color3.fromRGB(0, 0, 0),
    Text = Color3.fromRGB(248, 244, 255),
    Muted = Color3.fromRGB(177, 158, 192),
    Accent = Color3.fromRGB(170, 80, 255),
    AccentDark = Color3.fromRGB(91, 39, 145),
    Off = Color3.fromRGB(45, 45, 45),
    Knob = Color3.fromRGB(220, 220, 220),
}

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 7)
    c.Parent = obj
    return c
end

local function stroke(obj, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or COLORS.Border
    s.Thickness = thickness or 1
    s.Transparency = 1
    s.Parent = obj
    return s
end

local function label(parent, text, size, position, textSize, color, font)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.Size = size
    l.Position = position
    l.TextColor3 = color or COLORS.Text
    l.TextSize = textSize or 12
    l.Font = font or Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = parent
    return l
end

ScreenGui.Parent = parentGui

-----------------------------------
-- BANTAI KEY SYSTEM
-- Source: https://pastebin.com/raw/C9GyQeDK
-- Saved keys are rechecked against the current source, so a changed key
-- requires a new entry while the same valid key is remembered between runs.
-----------------------------------
do
local KEY_SOURCE = "https://pastebin.com/raw/C9GyQeDK"
local KEY_FILE = "BantaiHub/key.txt"
local keyAccepted = false
local keySourceCache = nil

local function trimKey(v)
    return tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function readSavedBantaiKey()
    if type(isfile) == "function" and isfile(KEY_FILE) and type(readfile) == "function" then
        local ok, value = pcall(readfile, KEY_FILE)
        if ok then return trimKey(value) end
    end
    return ""
end

local function saveBantaiKey(value)
    if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("BantaiHub") then
        pcall(makefolder, "BantaiHub")
    end
    if type(writefile) == "function" then pcall(writefile, KEY_FILE, value) end
end

local function fetchKeySource()
    local ok, body = pcall(function()
        if type(game.HttpGet) == "function" then
            return game:HttpGet(KEY_SOURCE)
        end
        return HttpService:GetAsync(KEY_SOURCE)
    end)
    if ok and type(body) == "string" and #body > 0 then
        keySourceCache = body
        return body
    end
    return nil
end

local function keyExistsInSource(key, body)
    key = trimKey(key)
    if key == "" or type(body) ~= "string" then return false end
    if trimKey(body) == key then return true end
    for line in body:gmatch("[^\r\n]+") do
        local clean = trimKey(line):gsub("^[`\\\"']+", ""):gsub("[`\\\"']+$", "")
        if clean == key then return true end
    end
    -- Also support a raw source that contains the key inside a small list/code block.
    local escaped = key:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return body:match("%f[%w]" .. escaped .. "%f[%W]") ~= nil
end

local function createKeyGate()
    local existing = parentGui:FindFirstChild("BantaiHubKeySystem")
    if existing then existing:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "BantaiHubKeySystem"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = parentGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(390, 235)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = Color3.fromRGB(0,0,0)
    frame.BorderSizePixel = 0
    frame.Parent = sg
    corner(frame, 14)
    local st = Instance.new("UIStroke")
    st.Color = COLORS.Accent
    st.Thickness = 1.5
    st.Parent = frame

    local title = label(frame, "BANTAI HUB", UDim2.new(1,-40,0,30), UDim2.new(0,20,0,18), 19, COLORS.Text, Enum.Font.GothamBold)
    local sub = label(frame, "Secure access", UDim2.new(1,-40,0,22), UDim2.new(0,20,0,48), 10, COLORS.Muted, Enum.Font.GothamMedium)
    sub.Text = "Enter the current key to continue"

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1,-40,0,42)
    box.Position = UDim2.new(0,20,0,82)
    box.BackgroundColor3 = Color3.fromRGB(8,8,8)
    box.BorderSizePixel = 0
    box.TextColor3 = COLORS.Text
    box.PlaceholderColor3 = COLORS.Muted
    box.PlaceholderText = "Paste key here..."
    box.Text = ""
    box.TextSize = 12
    box.Font = Enum.Font.GothamMedium
    box.ClearTextOnFocus = false
    box.Parent = frame
    corner(box, 8)

    local verify = Instance.new("TextButton")
    verify.Size = UDim2.new(0.47,-10,0,38)
    verify.Position = UDim2.new(0,20,0,142)
    verify.BackgroundColor3 = COLORS.Accent
    verify.BorderSizePixel = 0
    verify.Text = "VERIFY KEY"
    verify.TextColor3 = COLORS.Text
    verify.TextSize = 11
    verify.Font = Enum.Font.GothamBold
    verify.AutoButtonColor = false
    verify.Parent = frame
    corner(verify, 8)

    local get = Instance.new("TextButton")
    get.Size = UDim2.new(0.47,-10,0,38)
    get.Position = UDim2.new(0.53,0,0,142)
    get.BackgroundColor3 = Color3.fromRGB(12,12,12)
    get.BorderSizePixel = 0
    get.Text = "GET KEY"
    get.TextColor3 = COLORS.Text
    get.TextSize = 11
    get.Font = Enum.Font.GothamBold
    get.AutoButtonColor = false
    get.Parent = frame
    corner(get, 8)

    local status = label(frame, "Checking key source...", UDim2.new(1,-40,0,24), UDim2.new(0,20,0,190), 9, COLORS.Muted, Enum.Font.GothamMedium)

    local function copyLink()
        local copier = setclipboard or toclipboard
        if type(copier) == "function" then pcall(copier, KEY_SOURCE); status.Text = "Key link copied" else status.Text = KEY_SOURCE end
    end
    get.Activated:Connect(copyLink)
    verify.Activated:Connect(function()
        local entered = trimKey(box.Text)
        if entered == "" then status.Text = "Enter a key"; status.TextColor3 = Color3.fromRGB(255,80,80); return end
        verify.Text = "CHECKING..."
        local body = fetchKeySource() or keySourceCache
        if body and keyExistsInSource(entered, body) then
            saveBantaiKey(entered)
            keyAccepted = true
            status.Text = "Access granted"
            status.TextColor3 = Color3.fromRGB(100,255,150)
            task.wait(0.25)
            sg:Destroy()
        else
            verify.Text = "VERIFY KEY"
            status.Text = body and "Invalid / expired key" or "Could not reach key source"
            status.TextColor3 = Color3.fromRGB(255,80,80)
        end
    end)

    local saved = readSavedBantaiKey()
    if saved ~= "" then
        local body = fetchKeySource()
        if body and keyExistsInSource(saved, body) then
            keyAccepted = true
            sg:Destroy()
            return
        end
        if body then saveBantaiKey("") end
        status.Text = "Saved key changed — enter new key"
    else
        fetchKeySource()
        status.Text = "Enter the current key"
    end
end

local savedBantaiKey = readSavedBantaiKey()
local sourceForSavedKey = fetchKeySource()
if savedBantaiKey ~= "" then
    if sourceForSavedKey and keyExistsInSource(savedBantaiKey, sourceForSavedKey) then
        keyAccepted = true
    elseif not sourceForSavedKey then
        -- Keep a previously accepted key when the key host is temporarily offline.
        -- It will be checked again against the live source on the next successful fetch.
        keyAccepted = true
    end
end
if not keyAccepted then
    createKeyGate()
    repeat task.wait(0.1) until keyAccepted
end
end

-- Main window
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainWindow"
MainFrame.Size = UDim2.new(0, 760, 0, 470)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.BackgroundColor3 = COLORS.Window
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui
corner(MainFrame, 10)
stroke(MainFrame, COLORS.Border, 1)

-- Center background image using BOTH supplied IDs. The texture layer is wider,
-- while the asset layer is centered over it. Both stay behind the controls.
local GuiImage = Instance.new("ImageLabel")
GuiImage.Name = "BackgroundTexture"
GuiImage.Size = UDim2.new(0.78, 0, 0.78, 0)
GuiImage.AnchorPoint = Vector2.new(0.5, 0.5)
GuiImage.Position = UDim2.new(0.62, 0, 0.57, 0)
GuiImage.BackgroundTransparency = 1
GuiImage.Image = "rbxassetid://119502002905930"
GuiImage.ScaleType = Enum.ScaleType.Fit
GuiImage.ImageTransparency = 0.10
GuiImage.ZIndex = 1
GuiImage.Parent = MainFrame
corner(GuiImage, 10)

local CenterImage = Instance.new("ImageLabel")
CenterImage.Name = "CenterAssetImage"
CenterImage.Size = UDim2.new(0.46, 0, 0.46, 0)
CenterImage.AnchorPoint = Vector2.new(0.5, 0.5)
CenterImage.Position = UDim2.new(0.62, 0, 0.57, 0)
CenterImage.BackgroundTransparency = 1
CenterImage.Image = "rbxassetid://126946818712793"
CenterImage.ScaleType = Enum.ScaleType.Fit
CenterImage.ImageTransparency = 0.05
CenterImage.ZIndex = 2
CenterImage.Parent = MainFrame

local MainScale = Instance.new("UIScale")
MainScale.Scale = 1
MainScale.Parent = MainFrame

-- Responsive scale for phones / smaller displays.
local function updateScale()
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local scaleX = viewport.X / 900
    local scaleY = viewport.Y / 620
    MainScale.Scale = math.clamp(math.min(scaleX, scaleY), 0.72, 1)
end
updateScale()
if Workspace.CurrentCamera then
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 55)
Header.BackgroundColor3 = Color3.fromRGB(14, 7, 22)
Header.BorderSizePixel = 0
Header.Parent = MainFrame
corner(Header, 10)

local HeaderMask = Instance.new("Frame")
HeaderMask.Size = UDim2.new(1, 0, 0, 12)
HeaderMask.Position = UDim2.new(0, 0, 1, -12)
HeaderMask.BackgroundColor3 = Color3.fromRGB(14, 7, 22)
HeaderMask.BorderSizePixel = 0
HeaderMask.Parent = Header

local TitleLabel = label(Header, "bantai hub", UDim2.new(0, 105, 0, 30),
    UDim2.new(0, 18, 0, 8), 16, COLORS.Text, Enum.Font.GothamBold)

local AuthorLabel = label(Header, "by NotThatAnik", UDim2.new(0, 120, 0, 22),
    UDim2.new(0, 106, 0, 13), 9, COLORS.Muted, Enum.Font.GothamMedium)

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.new(0, 30, 0, 26)
MinimizeBtn.Position = UDim2.new(1, -70, 0, 13)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
MinimizeBtn.Text = "-"
MinimizeBtn.TextColor3 = COLORS.Text
MinimizeBtn.TextSize = 15
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.AutoButtonColor = false
MinimizeBtn.Parent = Header
corner(MinimizeBtn, 6)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 26)
CloseBtn.Position = UDim2.new(1, -35, 0, 13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = COLORS.Text
CloseBtn.TextSize = 18
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = Header
corner(CloseBtn, 6)

-- Modern drag handling; avoids deprecated GuiObject.Draggable.
do
    local dragging = false
    local dragStart
    local startPos

    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end)
end

-- Body
local Body = Instance.new("Frame")
Body.Size = UDim2.new(1, -20, 1, -65)
Body.Position = UDim2.new(0, 10, 0, 58)
Body.BackgroundTransparency = 1
Body.Parent = MainFrame

-- Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 190, 1, 0)
Sidebar.BackgroundColor3 = COLORS.Sidebar
Sidebar.BackgroundTransparency = 0.10
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Body
corner(Sidebar, 8)
stroke(Sidebar, COLORS.Border, 1)

label(Sidebar, "MENU", UDim2.new(1, -24, 0, 20),
    UDim2.new(0, 12, 0, 9), 9, COLORS.Muted, Enum.Font.GothamBold)

local TabHolder = Instance.new("ScrollingFrame")
TabHolder.Size = UDim2.new(1, -10, 1, -42)
TabHolder.Position = UDim2.new(0, 5, 0, 35)
TabHolder.BackgroundTransparency = 1
TabHolder.BorderSizePixel = 0
TabHolder.ScrollBarThickness = 2
TabHolder.ScrollBarImageColor3 = COLORS.Accent
TabHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
TabHolder.CanvasSize = UDim2.new()
TabHolder.Parent = Sidebar

local TabLayout = Instance.new("UIListLayout")
TabLayout.Padding = UDim.new(0, 5)
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Parent = TabHolder

local Pages = {}
local Tabs = {}

local function createTab(name, icon, order)
    local button = Instance.new("TextButton")
    button.Name = name .. "Tab"
    button.LayoutOrder = order
    button.Size = UDim2.new(1, 0, 0, 42)
    button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    button.Text = ""
    button.AutoButtonColor = false
    button.Parent = TabHolder
    corner(button, 6)

    local accent = Instance.new("Frame")
    accent.Name = "ActiveBar"
    accent.Size = UDim2.new(0, 3, 0.58, 0)
    accent.Position = UDim2.new(0, 0, 0.21, 0)
    accent.BackgroundColor3 = COLORS.Accent
    accent.BorderSizePixel = 0
    accent.Visible = false
    accent.Parent = button
    corner(accent, 2)

    label(button, icon, UDim2.new(0, 25, 1, 0),
        UDim2.new(0, 12, 0, 0), 14, COLORS.Muted, Enum.Font.GothamMedium)

    label(button, name, UDim2.new(1, -48, 1, 0),
        UDim2.new(0, 40, 0, 0), 11, COLORS.Muted, Enum.Font.GothamMedium)

    Tabs[name] = button
    return button
end

local StatusTab = createTab("Status", "◈", 1)
local FarmingTab = createTab("Farm", "⌂", 2)
local FarmSettingsTab = createTab("Farm Settings", "⚙", 3)
local RaidsTab = createTab("Raids", "⚔", 4)
local FruitsTab = createTab("Fruits", "◇", 5)
local LocalPlayerTab = createTab("Local Player", "♙", 6)
local ChestFarmTab = createTab("Chest Farm", "▣", 7)
local HopTab = createTab("Hop", "↻", 8)

-- Right side
local PageHolder = Instance.new("Frame")
PageHolder.Size = UDim2.new(1, -200, 1, 0)
PageHolder.Position = UDim2.new(0, 200, 0, 0)
PageHolder.BackgroundColor3 = COLORS.Content
PageHolder.BackgroundTransparency = 0.14
PageHolder.BorderSizePixel = 0
PageHolder.Parent = Body
corner(PageHolder, 8)
stroke(PageHolder, COLORS.Border, 1)

-- Background images live inside the content holder so they remain visible behind pages.
GuiImage.Parent = PageHolder
GuiImage.Size = UDim2.new(0.62, 0, 0.62, 0)
GuiImage.Position = UDim2.new(0.62, 0, 0.54, 0)
GuiImage.ZIndex = 1
CenterImage.Parent = PageHolder
CenterImage.Size = UDim2.new(0.38, 0, 0.38, 0)
CenterImage.Position = UDim2.new(0.62, 0, 0.54, 0)
CenterImage.ZIndex = 2
PageHolder.BackgroundTransparency = 0.28

local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.Size = UDim2.new(1, -8, 1, -8)
    page.Position = UDim2.new(0, 4, 0, 4)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = COLORS.Accent
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new()
    page.Visible = false
    page.Parent = PageHolder

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 14)
    padding.Parent = page

    -- Every page is a ScrollingFrame. Without a list layout, all controls
    -- share the same position and only the last control is visible.
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page

    return page
end

local StatusPage = createPage("StatusPage")
local FarmingPage = createPage("FarmingPage")
local FarmSettingsPage = createPage("FarmSettingsPage")
local RaidsPage = createPage("RaidsPage")
local FruitsPage = createPage("FruitsPage")
local LocalPlayerPage = createPage("LocalPlayerPage")
local ChestFarmPage = createPage("ChestFarmPage")
local HopPage = createPage("HopPage")

Pages.Status = StatusPage
Pages.Farm = FarmingPage
Pages["Farm Settings"] = FarmSettingsPage
Pages.Raids = RaidsPage
Pages.Fruits = FruitsPage
Pages["Local Player"] = LocalPlayerPage
Pages["Chest Farm"] = ChestFarmPage
Pages.Hop = HopPage

local Container = FarmingPage

local function showTab(name)
    for pageName, page in pairs(Pages) do
        page.Visible = (pageName == name)
    end

    for tabName, tab in pairs(Tabs) do
        local activeTab = (tabName == name)
        tab.BackgroundColor3 = activeTab and COLORS.RowHover or Color3.fromRGB(0, 0, 0)
        local bar = tab:FindFirstChild("ActiveBar")
        if bar then bar.Visible = activeTab end

        for _, child in ipairs(tab:GetChildren()) do
            if child:IsA("TextLabel") then
                child.TextColor3 = activeTab and COLORS.Text or COLORS.Muted
            end
        end
    end
end

StatusTab.MouseButton1Click:Connect(function() showTab("Status") end)
FarmingTab.MouseButton1Click:Connect(function() showTab("Farm") end)
FarmSettingsTab.MouseButton1Click:Connect(function() showTab("Farm Settings") end)
RaidsTab.MouseButton1Click:Connect(function() showTab("Raids") end)
FruitsTab.MouseButton1Click:Connect(function() showTab("Fruits") end)
LocalPlayerTab.MouseButton1Click:Connect(function() showTab("Local Player") end)
ChestFarmTab.MouseButton1Click:Connect(function() showTab("Chest Farm") end)
HopTab.MouseButton1Click:Connect(function() showTab("Hop") end)

-- Content helpers
local function addSection(page, title, order)
    local frame = Instance.new("Frame")
    frame.Name = title .. "Section"
    frame.LayoutOrder = order or 1
    frame.Size = UDim2.new(1, 0, 0, 30)
    frame.BackgroundTransparency = 1
    frame.Parent = page

    label(frame, title, UDim2.new(1, 0, 1, 0),
        UDim2.new(0, 2, 0, 0), 16, COLORS.Text, Enum.Font.GothamBold)
    return frame
end

local function makeDescriptionRow(page, title, description, order, callback)
    local row = Instance.new("TextButton")
    row.Name = title:gsub("%s+", "") .. "Row"
    row.LayoutOrder = order or 1
    row.Size = UDim2.new(1, 0, 0, 62)
    row.BackgroundColor3 = COLORS.Row
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = page
    corner(row, 6)

    row.MouseEnter:Connect(function()
        row.BackgroundColor3 = COLORS.RowHover
    end)
    row.MouseLeave:Connect(function()
        row.BackgroundColor3 = COLORS.Row
    end)

    local titleLabel = label(row, title, UDim2.new(1, -92, 0, 24),
        UDim2.new(0, 13, 0, 5), 12, COLORS.Text, Enum.Font.GothamMedium)

    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local desc = label(row, description, UDim2.new(1, -92, 0, 22),
        UDim2.new(0, 13, 0, 29), 9, COLORS.Muted, Enum.Font.Gotham)

    desc.TextWrapped = false
    desc.TextTruncate = Enum.TextTruncate.AtEnd

    callback(row, desc)
    return row
end

local function makeToggle(page, title, description, order, initial, callback)
    local row = makeDescriptionRow(page, title, description, order, function(row)
        local track = Instance.new("TextButton")
        track.Name = "Toggle"
        track.Size = UDim2.new(0, 50, 0, 26)
        track.Position = UDim2.new(1, -64, 0.5, -13)
        track.BackgroundColor3 = COLORS.Off
        track.Text = ""
        track.AutoButtonColor = false
        track.Parent = row
        corner(track, 13)

        local knob = Instance.new("Frame")
        knob.Name = "Knob"
        knob.Size = UDim2.new(0, 20, 0, 20)
        knob.Position = UDim2.new(0, 3, 0.5, -10)
        knob.BackgroundColor3 = COLORS.Knob
        knob.BorderSizePixel = 0
        knob.Parent = track
        corner(knob, 10)

        local state = initial == true

        local function render(value)
            state = value
            track.BackgroundColor3 = value and COLORS.Accent or COLORS.Off
            knob.BackgroundColor3 = value and COLORS.Window or COLORS.Knob
            knob:TweenPosition(
                value and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
                Enum.EasingDirection.Out,
                Enum.EasingStyle.Quad,
                0.12,
                true
            )
        end

        local function toggle()
            render(not state)
            callback(state)
        end

        local clickLock = false
        local function guardedToggle()
            if clickLock then return end
            clickLock = true
            toggle()
            task.delay(0.12, function() clickLock = false end)
        end

        track.Activated:Connect(guardedToggle)
        row.Activated:Connect(guardedToggle)
        render(state)

        row:SetAttribute("Value", state)
        row:SetAttribute("SetValueReady", true)

        row:SetAttribute("ToggleTitle", title)
        row:SetAttribute("ToggleDescription", description)

    end)
    return row
end

local function makeAction(page, title, description, order, callback)
    return makeDescriptionRow(page, title, description, order, function(row)
        local arrow = label(row, "›", UDim2.new(0, 30, 1, 0),
            UDim2.new(1, -45, 0, 0), 24, COLORS.Muted, Enum.Font.Gotham)
        arrow.TextXAlignment = Enum.TextXAlignment.Center
        row.MouseButton1Click:Connect(callback)
    end)
end

local function makeInput(page, title, description, order, value, onCommit)
    local row = Instance.new("Frame")
    row.LayoutOrder = order or 1
    row.Size = UDim2.new(1, 0, 0, 62)
    row.BackgroundColor3 = COLORS.Row
    row.BorderSizePixel = 0
    row.Parent = page
    corner(row, 6)

    label(row, title, UDim2.new(0.52, 0, 0, 24),
        UDim2.new(0, 13, 0, 5), 12, COLORS.Text, Enum.Font.GothamMedium)
    label(row, description, UDim2.new(0.52, 0, 0, 20),
        UDim2.new(0, 13, 0, 30), 9, COLORS.Muted, Enum.Font.Gotham)

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0, 125, 0, 34)
    box.Position = UDim2.new(1, -139, 0.5, -17)
    box.BackgroundColor3 = COLORS.Row
    box.Text = tostring(value)
    box.TextColor3 = COLORS.Text
    box.TextSize = 11
    box.Font = Enum.Font.Gotham
    box.ClearTextOnFocus = false
    box.Parent = row
    corner(box, 5)

    box.FocusLost:Connect(function()
        onCommit(box, box.Text)
    end)

    return row, box
end

-- Status intentionally empty. Fruit notifications are shown in the Fruits tab.
showTab("Farm")

-----------------------------------
-- SERVER HOP
-- One-click target hop. The Night Hub server API is used to select an
-- actual Fullmoon/NearMoon server before joining it. No background hop loop.
-----------------------------------
do
local HopBusy = false

local function moonTargetFound(mode)
    local lighting = game:GetService("Lighting")
    local sky = lighting:FindFirstChildOfClass("Sky")
    local texture = sky and tostring(sky.MoonTextureId or "") or ""
    local id = texture:match("%d+") or ""
    local night = lighting.ClockTime >= 18 or lighting.ClockTime < 5

    if mode == "FullMoon" then
        return night and (id == "9709149431" or id == "79932823311771")
    elseif mode == "NearMoon" then
        return night and id == "9709149052"
    end
    return false
end

-- Night Hub encodes the JobIds returned by its moon server API.
local function BH_bytesFromHex(value)
    local out = {}
    for i = 1, #value, 2 do
        out[#out + 1] = tonumber(value:sub(i, i + 1), 16)
    end
    return out
end

local function BH_u32LE(bytes, index)
    return bytes[index] + bytes[index + 1] * 256 + bytes[index + 2] * 65536 + bytes[index + 3] * 16777216
end

local function BH_qr(a, ai, bi, ci, di)
    a[ai] = (a[ai] + a[bi]) % 4294967296
    a[di] = bit32.lrotate(bit32.bxor(a[di], a[ai]), 16)
    a[ci] = (a[ci] + a[di]) % 4294967296
    a[bi] = bit32.lrotate(bit32.bxor(a[bi], a[ci]), 12)
    a[ai] = (a[ai] + a[bi]) % 4294967296
    a[di] = bit32.lrotate(bit32.bxor(a[di], a[ai]), 8)
    a[ci] = (a[ci] + a[di]) % 4294967296
    a[bi] = bit32.lrotate(bit32.bxor(a[bi], a[ci]), 7)
end

local function BH_rounds(a)
    for _ = 1, 10 do
        BH_qr(a, 1, 5, 9, 13)
        BH_qr(a, 2, 6, 10, 14)
        BH_qr(a, 3, 7, 11, 15)
        BH_qr(a, 4, 8, 12, 16)
        BH_qr(a, 1, 6, 11, 16)
        BH_qr(a, 2, 7, 12, 13)
        BH_qr(a, 3, 8, 9, 14)
        BH_qr(a, 4, 5, 10, 15)
    end
end

local BH_CONST = {1634760805, 857760878, 2036477234, 1797285236}
local BH_KEY = BH_bytesFromHex("8992d555ed7846a562b058523100fbd0e59b5f6f28e98003230ffb4d9db60411")

local function BH_streamBlock(key, counter, nonce)
    local state = {BH_CONST[1], BH_CONST[2], BH_CONST[3], BH_CONST[4]}
    for i = 0, 7 do state[5 + i] = BH_u32LE(key, 1 + 4 * i) end
    state[13] = counter % 4294967296
    for i = 0, 2 do state[14 + i] = BH_u32LE(nonce, 1 + 4 * i) end
    local working = {}
    for i = 1, 16 do working[i] = state[i] end
    BH_rounds(working)
    local out = {}
    for i = 1, 16 do
        local v = (working[i] + state[i]) % 4294967296
        local j = (i - 1) * 4
        out[j + 1] = bit32.band(v, 255)
        out[j + 2] = bit32.band(bit32.rshift(v, 8), 255)
        out[j + 3] = bit32.band(bit32.rshift(v, 16), 255)
        out[j + 4] = bit32.band(bit32.rshift(v, 24), 255)
    end
    return out
end

local function BH_stream(key, nonce, counter, length)
    local out, produced = {}, 0
    while produced < length do
        local block = BH_streamBlock(key, counter, nonce)
        for i = 1, 64 do
            if produced >= length then break end
            produced += 1
            out[produced] = block[i]
        end
        counter += 1
    end
    return out
end

local function BH_mac(key, nonce, data)
    local state = {BH_CONST[1], BH_CONST[2], BH_CONST[3], BH_CONST[4]}
    for i = 0, 7 do state[5 + i] = BH_u32LE(key, 1 + 4 * i) end
    state[13] = 4294967295
    for i = 0, 2 do state[14 + i] = BH_u32LE(nonce, 1 + 4 * i) end
    BH_rounds(state)
    local len = #data
    for i = 0, len + (16 - len % 16) % 16 - 1, 16 do
        for word = 0, 3 do
            local j = i + word * 4
            local value = (data[j + 1] or 0) + (data[j + 2] or 0) * 256 + (data[j + 3] or 0) * 65536 + (data[j + 4] or 0) * 16777216
            state[word + 1] = bit32.bxor(state[word + 1], value)
        end
        BH_rounds(state)
    end
    state[1] = bit32.bxor(state[1], len)
    BH_rounds(state)
    local v = state[1]
    return {
        bit32.band(v, 255),
        bit32.band(bit32.rshift(v, 8), 255),
        bit32.band(bit32.rshift(v, 16), 255),
        bit32.band(bit32.rshift(v, 24), 255),
    }
end

local BH_alphabetCache = {}
local function BH_alphabet(key)
    local cacheKey = table.concat(key, ",")
    if BH_alphabetCache[cacheKey] then return BH_alphabetCache[cacheKey] end
    local seed = BH_stream(key, {0,0,0,0,0,0,0,0,0,0,0,0}, 11259375, 128)
    local chars = {}
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    for i = 1, 64 do chars[i] = alphabet:sub(i, i) end
    for i = 64, 2, -1 do
        local j = ((seed[2 * (i - 1) + 1] * 256 + seed[2 * (i - 1) + 2]) % i) + 1
        chars[i], chars[j] = chars[j], chars[i]
    end
    local result = table.concat(chars)
    BH_alphabetCache[cacheKey] = result
    return result
end

local function BH_decode64(value, alphabet)
    local lookup = {}
    for i = 1, 64 do lookup[alphabet:sub(i, i)] = i - 1 end
    local values = {}
    for i = 1, #value do
        local n = lookup[value:sub(i, i)]
        if n == nil then return nil end
        values[#values + 1] = n
    end
    local out = {}
    for i = 1, #values, 4 do
        local a, b, c, d = values[i], values[i + 1], values[i + 2], values[i + 3]
        if b == nil then return nil end
        out[#out + 1] = bit32.band(bit32.lshift(a, 2) + bit32.rshift(b, 4), 255)
        if c ~= nil then out[#out + 1] = bit32.band(bit32.lshift(bit32.band(b, 15), 4) + bit32.rshift(c, 2), 255) end
        if d ~= nil then out[#out + 1] = bit32.band(bit32.lshift(bit32.band(c, 3), 6) + d, 255) end
    end
    return out
end

local function BH_decodeJobId(encoded)
    if type(encoded) ~= "string" or encoded:sub(1, 9) ~= "NIGHTHUB|" then return encoded end
    local payload = encoded:sub(10)
    local alphabet = BH_alphabet(BH_KEY)
    local decoded = BH_decode64(payload, alphabet)
    if not decoded or #decoded < 12 then return nil end

    local nonce = {}
    for i = 1, 8 do nonce[i] = decoded[i] end
    local encrypted = {}
    for i = 13, #decoded do encrypted[#encrypted + 1] = decoded[i] end
    local tag = BH_mac(BH_KEY, nonce, encrypted)
    for i = 1, 4 do
        if tag[i] ~= decoded[8 + i] then return nil end
    end
    local stream = BH_stream(BH_KEY, nonce, 1, #encrypted)
    local plain = {}
    for i = 1, #encrypted do plain[i] = bit32.bxor(encrypted[i], stream[i]) end
    local chars = {}
    for i = 1, #plain do chars[i] = string.char(plain[i]) end
    return table.concat(chars)
end

local function BH_request(url)
    local requester = rawget(getfenv and getfenv() or _G, "request") or rawget(getfenv and getfenv() or _G, "http_request")
    if not requester and type(syn) == "table" then requester = syn.request end
    if type(requester) == "function" then
        local ok, result = pcall(requester, {Url = url, Method = "GET"})
        if ok and result and type(result.Body) == "string" then return true, result.Body end
    end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then return true, body end
    return false, nil
end

local function publicHopTarget(mode)
    local ok, body = BH_request("http://163.223.9.144/boss/" .. mode)
    if not ok then return nil, "Moon server API unavailable" end
    local decoded
    ok = pcall(function() decoded = HttpService:JSONDecode(body) end)
    if not ok or type(decoded) ~= "table" or type(decoded.data) ~= "table" then return nil, "Invalid moon server API response" end

    local candidates = {}
    for _, server in pairs(decoded.data) do
        if type(server) == "table" and server.JobId and server.PlaceId == game.PlaceId and server.Age then
            local jobId = BH_decodeJobId(tostring(server.JobId))
            if jobId and jobId ~= game.JobId and tonumber(server.Players or 0) < 12 then
                candidates[#candidates + 1] = {JobId = jobId, Age = tonumber(server.Age) or math.huge}
            end
        end
    end
    table.sort(candidates, function(a, b) return a.Age < b.Age end)
    if #candidates == 0 then return nil, "No target moon server found" end
    return candidates[1].JobId
end

local function hopToMoonOnce(mode)
    if HopBusy then return end
    HopBusy = true
    HopStatus.Text = "Finding " .. (mode == "FullMoon" and "Full Moon" or "Near Moon") .. " server..."
    task.spawn(function()
        local target, err = publicHopTarget(mode)
        if target then
            HopStatus.Text = "Joining target server..."
            local serverBrowser = ReplicatedStorage:FindFirstChild("__ServerBrowser")
            local success = false
            if serverBrowser then
                success = pcall(function()
                    serverBrowser:InvokeServer("teleport", tostring(target))
                end)
            end
            if not success then
                HopStatus.Text = "Hop failed"
                HopBusy = false
            end
        else
            HopStatus.Text = err or "No target server found"
            HopBusy = false
        end
    end)
end

addSection(HopPage, "Server Hop", 1)
local HopStatus = label(HopPage, "Moon target: idle", UDim2.new(1,0,0,34), UDim2.new(0,2,0,0), 10, COLORS.Muted, Enum.Font.GothamMedium)
HopStatus.LayoutOrder = 2
local FullMoonHopRow = makeAction(HopPage, "Hop Full Moon", "Join one server selected as Full Moon.", 3, function()
    if moonTargetFound("FullMoon") then HopStatus.Text = "Full Moon is already here"; return end
    hopToMoonOnce("Fullmoon")
end)
local NearMoonHopRow = makeAction(HopPage, "Hop Near Moon", "Join one server selected as Near Moon.", 4, function()
    if moonTargetFound("NearMoon") then HopStatus.Text = "Near Moon is already here"; return end
    hopToMoonOnce("NearMoon")
end)
local StopHopRow = makeAction(HopPage, "Stop Hop Search", "Cancel the current hop request.", 5, function()
    HopBusy = false
    HopStatus.Text = "Moon target: stopped"
end)
end


-- Farming page
addSection(FarmingPage, "Farm", 1)

local TargetLabel = label(FarmingPage, "Target: All Damageable",
    UDim2.new(1, 0, 0, 18), UDim2.new(), 2, COLORS.Muted, Enum.Font.Gotham)

local DropdownBtn = Instance.new("TextButton")
DropdownBtn.LayoutOrder = 3
DropdownBtn.Size = UDim2.new(1, 0, 0, 42)
DropdownBtn.BackgroundColor3 = COLORS.Row
DropdownBtn.Text = "Select NPCs..."
DropdownBtn.TextColor3 = COLORS.Text
DropdownBtn.TextSize = 11
DropdownBtn.Font = Enum.Font.GothamMedium
DropdownBtn.TextXAlignment = Enum.TextXAlignment.Left
DropdownBtn.Parent = FarmingPage
corner(DropdownBtn, 6)

-- Dropdown contents. This object was referenced later by populateDropdown()
-- but was missing, which stopped the script before any feature loops started.
local MobScrollFrame = Instance.new("ScrollingFrame")
MobScrollFrame.Name = "MobDropdown"
MobScrollFrame.LayoutOrder = 4
MobScrollFrame.Size = UDim2.new(1, 0, 0, 150)
MobScrollFrame.BackgroundColor3 = COLORS.Content
MobScrollFrame.ClipsDescendants = true
MobScrollFrame.BorderSizePixel = 0
MobScrollFrame.ScrollBarThickness = 3
MobScrollFrame.ScrollBarImageColor3 = COLORS.Accent
MobScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
MobScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
MobScrollFrame.Visible = false
MobScrollFrame.Size = UDim2.new(1, 0, 0, 0)
MobScrollFrame.ZIndex = 20
MobScrollFrame.Parent = FarmingPage
corner(MobScrollFrame, 6)

local MobDropdownPadding = Instance.new("UIPadding")
MobDropdownPadding.PaddingTop = UDim.new(0, 4)
MobDropdownPadding.PaddingBottom = UDim.new(0, 4)
MobDropdownPadding.PaddingLeft = UDim.new(0, 3)
MobDropdownPadding.PaddingRight = UDim.new(0, 3)
MobDropdownPadding.Parent = MobScrollFrame

local MobDropdownLayout = Instance.new("UIListLayout")
MobDropdownLayout.Padding = UDim.new(0, 3)
MobDropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
MobDropdownLayout.Parent = MobScrollFrame

local RefreshBtn = Instance.new("TextButton")
RefreshBtn.LayoutOrder = 5
RefreshBtn.Size = UDim2.new(1, 0, 0, 38)
RefreshBtn.BackgroundColor3 = COLORS.Row
RefreshBtn.Text = "Refresh Mob List"
RefreshBtn.TextColor3 = COLORS.Text
RefreshBtn.TextSize = 10
RefreshBtn.Font = Enum.Font.GothamMedium
RefreshBtn.TextXAlignment = Enum.TextXAlignment.Left
RefreshBtn.Parent = FarmingPage
corner(RefreshBtn, 6)

local ToggleButton
local FarmToggle
local FarmKnob

local FarmRow = makeDescriptionRow(
    FarmingPage,
    "Auto Farm Level",
    "Automatically move above and farm the selected NPCs.",
    6,
    function(row)
        FarmToggle = Instance.new("TextButton")
        FarmToggle.Size = UDim2.new(0, 50, 0, 26)
        FarmToggle.Position = UDim2.new(1, -64, 0.5, -13)
        FarmToggle.BackgroundColor3 = COLORS.Off
        FarmToggle.Text = ""
        FarmToggle.AutoButtonColor = false
        FarmToggle.Parent = row
        corner(FarmToggle, 13)

        FarmKnob = Instance.new("Frame")
        FarmKnob.Size = UDim2.new(0, 20, 0, 20)
        FarmKnob.Position = UDim2.new(0, 3, 0.5, -10)
        FarmKnob.BackgroundColor3 = COLORS.Knob
        FarmKnob.BorderSizePixel = 0
        FarmKnob.Parent = FarmToggle
        corner(FarmKnob, 10)
    end
)

ToggleButton = FarmRow
-- FarmToggle is wired after toggleScript is declared below.

-- Farm settings
addSection(FarmSettingsPage, "Farm Settings", 1)

local SpeedRow, SpeedBox = makeInput(
    FarmSettingsPage, "Tween Speed",
    "Movement speed used by Auto Farm and Auto Raid.",
    2, speed,
    function(box, value)
        local num = tonumber(tostring(value):match("%d+"))
        if num and num > 0 then
            speed = num
            local labels = ChestSpeedRow and ChestSpeedRow:GetChildren() or {}
            for _, child in ipairs(labels) do
                if child:IsA("TextLabel") and child ~= labels[1] then
                    child.Text = "Uses the same Tween Speed value from Farm Settings: " .. tostring(speed)
                end
            end
        end
        box.Text = tostring(speed)
    end
)

local HeightRow, HeightBox = makeInput(
    FarmSettingsPage, "Fly Height",
    "Distance to stay above the target NPC.",
    3, flyHeight,
    function(box, value)
        local num = tonumber(tostring(value):match("%d+"))
        if num and num >= 0 then flyHeight = num end
        box.Text = tostring(flyHeight)
    end
)

local AtkMultBox = Instance.new("TextBox")
AtkMultBox.LayoutOrder = 4
AtkMultBox.Size = UDim2.new(1, 0, 0, 38)
AtkMultBox.BackgroundColor3 = COLORS.Row
AtkMultBox.BorderSizePixel = 0
AtkMultBox.Text = "Attack Multiplier: " .. tostring(attackMultiplier) .. "x"
AtkMultBox.TextColor3 = COLORS.Text
AtkMultBox.TextSize = 10
AtkMultBox.Font = Enum.Font.GothamMedium
AtkMultBox.ClearTextOnFocus = false
AtkMultBox.TextXAlignment = Enum.TextXAlignment.Left
AtkMultBox.Parent = FarmSettingsPage
corner(AtkMultBox, 7)
stroke(AtkMultBox, COLORS.Border, 1)

-- Raids
addSection(RaidsPage, "Raids", 1)

local AutoRaidButton
local RaidToggle
local RaidKnob

local RaidRow = makeDescriptionRow(
    RaidsPage,
    "Auto Raid",
    "Defeat raid NPCs, stay above them, then travel to the next island.",
    2,
    function(row)
        AutoRaidButton = row

        RaidToggle = Instance.new("TextButton")
        RaidToggle.Size = UDim2.new(0, 50, 0, 26)
        RaidToggle.Position = UDim2.new(1, -64, 0.5, -13)
        RaidToggle.BackgroundColor3 = COLORS.Off
        RaidToggle.Text = ""
        RaidToggle.AutoButtonColor = false
        RaidToggle.Parent = row
        corner(RaidToggle, 13)

        RaidKnob = Instance.new("Frame")
        RaidKnob.Size = UDim2.new(0, 20, 0, 20)
        RaidKnob.Position = UDim2.new(0, 3, 0.5, -10)
        RaidKnob.BackgroundColor3 = COLORS.Knob
        RaidKnob.BorderSizePixel = 0
        RaidKnob.Parent = RaidToggle
        corner(RaidKnob, 10)
    end
)

-- Fruits
addSection(FruitsPage, "Fruit / Stock", 1)

local FruitStatusLabel = label(FruitsPage, "No fruit spawned", UDim2.new(1, 0, 0, 38),
    UDim2.new(0, 2, 0, 0), 11, COLORS.Muted, Enum.Font.GothamMedium)
FruitStatusLabel.LayoutOrder = 2
FruitStatusLabel.TextWrapped = true
FruitStatusLabel.TextYAlignment = Enum.TextYAlignment.Center

local NotifierBtn
local NotifierToggle
local NotifierKnob

local FruitRow = makeDescriptionRow(
    FruitsPage,
    "Fruit Notifier",
    "Notify when a spawned fruit is detected.",
    3,
    function(row)
        NotifierBtn = row

        NotifierToggle = Instance.new("TextButton")
        NotifierToggle.Size = UDim2.new(0, 50, 0, 26)
        NotifierToggle.Position = UDim2.new(1, -64, 0.5, -13)
        NotifierToggle.BackgroundColor3 = COLORS.Off
        NotifierToggle.Text = ""
        NotifierToggle.AutoButtonColor = false
        NotifierToggle.Parent = row
        corner(NotifierToggle, 13)

        NotifierKnob = Instance.new("Frame")
        NotifierKnob.Size = UDim2.new(0, 20, 0, 20)
        NotifierKnob.Position = UDim2.new(0, 3, 0.5, -10)
        NotifierKnob.BackgroundColor3 = COLORS.Knob
        NotifierKnob.BorderSizePixel = 0
        NotifierKnob.Parent = NotifierToggle
        corner(NotifierKnob, 10)
    end
)

local TPBtn = makeAction(
    FruitsPage,
    "Teleport to Spawned Fruit",
    "Teleport to the currently detected fruit.",
    4,
    function()
        -- Always rescan here so teleport works even when Fruit Notifier is OFF.
        local fruit = CurrentFruit
        if not fruit or fruit.Parent ~= Workspace then
            fruit = nil
            for _, child in ipairs(Workspace:GetChildren()) do
                if string.find(string.lower(child.Name), "fruit", 1, true) then
                    local h = child:FindFirstChild("Handle")
                        or child:FindFirstChildOfClass("Part")
                        or child:FindFirstChildOfClass("MeshPart")
                    if h then
                        fruit = child
                        break
                    end
                end
            end
            CurrentFruit = fruit
        end

        if fruit then
            local handle = fruit:FindFirstChild("Handle")
                or fruit:FindFirstChildOfClass("Part")
                or fruit:FindFirstChildOfClass("MeshPart")

            local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
            if handle and root then
                if active then
                    active = false
                    if activeTween then
                        pcall(function() activeTween:Cancel() end)
                        activeTween = nil
                    end
                    local c = Player.Character
                    local r = c and c:FindFirstChild("HumanoidRootPart")
                    local bv = r and r:FindFirstChild("AutoFarmVelocity")
                    if bv then bv:Destroy() end
                    if FarmToggle and FarmKnob then
                        FarmToggle.BackgroundColor3 = COLORS.Off
                        FarmKnob.BackgroundColor3 = COLORS.Knob
                        FarmKnob.Position = UDim2.new(0, 3, 0.5, -10)
                    end
                end
                root.CFrame = CFrame.new(handle.Position + Vector3.new(0, 4, 0))
                FruitStatusLabel.Text = "Fruit: " .. getFruitName(fruit) .. "\nTeleported to spawned fruit"
            end
        else
            FruitStatusLabel.Text = "No fruit spawned"
        end
    end
)

-----------------------------------
-- TWEEN TO FRUITS
-----------------------------------
do
local TweenFruitEnabled = false
local TweenFruitMoveToken = 0
local TweenFruitMove = nil

local function findSpawnedFruit()
    if CurrentFruit and CurrentFruit.Parent == Workspace then
        local h = CurrentFruit:FindFirstChild("Handle") or CurrentFruit:FindFirstChildOfClass("BasePart")
        if h then return CurrentFruit, h end
    end
    for _, child in ipairs(Workspace:GetChildren()) do
        if string.find(string.lower(child.Name), "fruit", 1, true) then
            local h = child:FindFirstChild("Handle") or child:FindFirstChildOfClass("BasePart")
            if h then CurrentFruit = child; return child, h end
        end
    end
    CurrentFruit = nil
    return nil, nil
end

local function stopFruitTween()
    TweenFruitMoveToken += 1
    if TweenFruitMove then pcall(function() TweenFruitMove:Cancel() end); TweenFruitMove = nil end
end

local function tweenToFruit(fruit, handle)
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not handle then return false end
    TweenFruitMoveToken += 1
    local token = TweenFruitMoveToken
    if TweenFruitMove then pcall(function() TweenFruitMove:Cancel() end) end
    local target = CFrame.new(handle.Position + Vector3.new(0,4,0))
    local distance = (root.Position - target.Position).Magnitude
    if distance <= 5 then return true end
    local duration = math.max(distance / math.max(speed,1), 0.01)
    TweenFruitMove = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame=target})
    TweenFruitMove:Play()
    local done = false
    local conn
    conn = TweenFruitMove.Completed:Connect(function() done=true; if conn then conn:Disconnect() end end)
    while TweenFruitEnabled and scriptRunning and token == TweenFruitMoveToken and not done do task.wait() end
    return TweenFruitEnabled and scriptRunning and token == TweenFruitMoveToken
end

local FruitTweenRow = makeToggle(FruitsPage, "Tween to Fruits", "Tween to spawned fruits using the Tween Speed from Farm Settings.", 5, false, function(enabled)
    TweenFruitEnabled = enabled
    if not enabled then stopFruitTween() end
end)

task.spawn(function()
    while scriptRunning do
        if TweenFruitEnabled then
            local fruit, handle = findSpawnedFruit()
            if fruit and handle then
                FruitStatusLabel.Text = "Fruit: " .. getFruitName(fruit) .. "\nTweening to spawned fruit"
                tweenToFruit(fruit, handle)
                task.wait(0.15)
            else
                FruitStatusLabel.Text = "Tween to Fruits: waiting for fruit"
                task.wait(0.4)
            end
        else
            task.wait(0.25)
        end
    end
end)
end

-- Chest Farm
addSection(ChestFarmPage, "Chest Farm", 1)

local ChestStatusLabel = label(ChestFarmPage, "Chest Farm: OFF\nNearest chest: idle",
    UDim2.new(1, 0, 0, 42), UDim2.new(0, 2, 0, 0), 10, COLORS.Muted, Enum.Font.GothamMedium)
ChestStatusLabel.LayoutOrder = 2
ChestStatusLabel.TextWrapped = true
ChestStatusLabel.TextTruncate = Enum.TextTruncate.None

local ChestFarmToggle
local ChestFarmKnob
local ChestFarmRow = makeDescriptionRow(
    ChestFarmPage,
    "Auto Farm Chest",
    "Find the nearest available chest and collect it repeatedly.",
    3,
    function(row)
        ChestFarmToggle = Instance.new("TextButton")
        ChestFarmToggle.Size = UDim2.new(0, 50, 0, 26)
        ChestFarmToggle.Position = UDim2.new(1, -64, 0.5, -13)
        ChestFarmToggle.BackgroundColor3 = COLORS.Off
        ChestFarmToggle.Text = ""
        ChestFarmToggle.AutoButtonColor = false
        ChestFarmToggle.Parent = row
        corner(ChestFarmToggle, 13)

        ChestFarmKnob = Instance.new("Frame")
        ChestFarmKnob.Size = UDim2.new(0, 20, 0, 20)
        ChestFarmKnob.Position = UDim2.new(0, 3, 0.5, -10)
        ChestFarmKnob.BackgroundColor3 = COLORS.Knob
        ChestFarmKnob.BorderSizePixel = 0
        ChestFarmKnob.Parent = ChestFarmToggle
        corner(ChestFarmKnob, 10)
    end
)

local ChestModeRow
ChestModeRow = makeAction(
    ChestFarmPage,
    "Movement: Tween",
    "Tap to switch between smooth tween and direct teleport.",
    4,
    function()
        ChestFarmMode = ChestFarmMode == "Tween" and "Teleport" or "Tween"
        local title = ChestModeRow and ChestModeRow:FindFirstChildWhichIsA("TextLabel")
        if title then title.Text = "Movement: " .. ChestFarmMode end
        if ChestFarmMode == "Teleport" and ChestFarmTween then
            pcall(function() ChestFarmTween:Cancel() end)
            ChestFarmTween = nil
        end
    end
)

local ChestSpeedRow = makeDescriptionRow(
    ChestFarmPage, "Tween Speed",
    "Uses the same Tween Speed value from Farm Settings: " .. tostring(speed),
    5, function() end
)

local ChestInfoRow = makeDescriptionRow(
    ChestFarmPage,
    "Chest System",
    "Uses the game's _ChestTagged collection and skips disabled chests.",
    6,
    function() end
)

-- Local Player
addSection(LocalPlayerPage, "Local Player", 1)

local V4Button = nil
local V3Button = nil
local WaterButton = nil

local V4Row = makeDescriptionRow(
    LocalPlayerPage,
    "Auto Turn On V4",
    "Automatically activate V4 when the character has enough race energy.",
    2,
    function(row)
        V4Button = row
        local t = Instance.new("TextButton")
        t.Name = "Toggle"
        t.Size = UDim2.new(0, 50, 0, 26)
        t.Position = UDim2.new(1, -64, 0.5, -13)
        t.BackgroundColor3 = COLORS.Off
        t.Text = ""
        t.AutoButtonColor = false
        t.Parent = row
        corner(t, 13)
        local k = Instance.new("Frame")
        k.Name = "Knob"
        k.Size = UDim2.new(0, 20, 0, 20)
        k.Position = UDim2.new(0, 3, 0.5, -10)
        k.BackgroundColor3 = COLORS.Knob
        k.BorderSizePixel = 0
        k.Parent = t
        corner(k, 10)

        local toggleLock = false
        local function toggle()
            if toggleLock then return end
            toggleLock = true
            AutoV4Enabled = not AutoV4Enabled
            t.BackgroundColor3 = AutoV4Enabled and COLORS.Accent or COLORS.Off
            k.BackgroundColor3 = AutoV4Enabled and COLORS.Window or COLORS.Knob
            k:TweenPosition(
                AutoV4Enabled and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
                Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.12, true
            )
            task.delay(0.12, function() toggleLock = false end)
        end
        row.Activated:Connect(toggle)
        t.Activated:Connect(toggle)
    end
)

local V3Row = makeDescriptionRow(
    LocalPlayerPage,
    "Auto Turn On V3",
    "Automatically request the V3 ability while enabled.",
    3,
    function(row)
        V3Button = row
        local t = Instance.new("TextButton")
        t.Name = "Toggle"
        t.Size = UDim2.new(0, 50, 0, 26)
        t.Position = UDim2.new(1, -64, 0.5, -13)
        t.BackgroundColor3 = COLORS.Off
        t.Text = ""
        t.AutoButtonColor = false
        t.Parent = row
        corner(t, 13)
        local k = Instance.new("Frame")
        k.Name = "Knob"
        k.Size = UDim2.new(0, 20, 0, 20)
        k.Position = UDim2.new(0, 3, 0.5, -10)
        k.BackgroundColor3 = COLORS.Knob
        k.BorderSizePixel = 0
        k.Parent = t
        corner(k, 10)

        local toggleLock = false
        local function toggle()
            if toggleLock then return end
            toggleLock = true
            AutoV3Enabled = not AutoV3Enabled
            t.BackgroundColor3 = AutoV3Enabled and COLORS.Accent or COLORS.Off
            k.BackgroundColor3 = AutoV3Enabled and COLORS.Window or COLORS.Knob
            k:TweenPosition(
                AutoV3Enabled and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
                Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.12, true
            )
            task.delay(0.12, function() toggleLock = false end)
        end
        row.Activated:Connect(toggle)
        t.Activated:Connect(toggle)
    end
)

local WaterRow = makeDescriptionRow(
    LocalPlayerPage,
    "Walk On Water",
    "Use the game's water plane as the walking surface while enabled.",
    4,
    function(row)
        WaterButton = row
        local t = Instance.new("TextButton")
        t.Name = "Toggle"
        t.Size = UDim2.new(0, 50, 0, 26)
        t.Position = UDim2.new(1, -64, 0.5, -13)
        t.BackgroundColor3 = COLORS.Off
        t.Text = ""
        t.AutoButtonColor = false
        t.Parent = row
        corner(t, 13)
        local k = Instance.new("Frame")
        k.Name = "Knob"
        k.Size = UDim2.new(0, 20, 0, 20)
        k.Position = UDim2.new(0, 3, 0.5, -10)
        k.BackgroundColor3 = COLORS.Knob
        k.BorderSizePixel = 0
        k.Parent = t
        corner(k, 10)

        local toggleLock = false
        local function toggle()
            if toggleLock then return end
            toggleLock = true
            WalkWaterEnabled = not WalkWaterEnabled
            t.BackgroundColor3 = WalkWaterEnabled and COLORS.Accent or COLORS.Off
            k.BackgroundColor3 = WalkWaterEnabled and COLORS.Window or COLORS.Knob
            k:TweenPosition(
                WalkWaterEnabled and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
                Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.12, true
            )
            if setWaterWalk then
                setWaterWalk(WalkWaterEnabled)
            end
            task.delay(0.12, function() toggleLock = false end)
        end
        row.Activated:Connect(toggle)
        t.Activated:Connect(toggle)
    end
)

-- Confirmation dialog
local ConfirmOverlay = Instance.new("Frame")
ConfirmOverlay.Size = UDim2.new(1, 0, 1, 0)
ConfirmOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ConfirmOverlay.BackgroundTransparency = 0.45
ConfirmOverlay.Visible = false
ConfirmOverlay.ZIndex = 100
ConfirmOverlay.Parent = ScreenGui

local ConfirmBox = Instance.new("Frame")
ConfirmBox.Size = UDim2.new(0, 300, 0, 140)
ConfirmBox.Position = UDim2.new(0.5, -150, 0.5, -70)
ConfirmBox.BackgroundColor3 = COLORS.Row
ConfirmBox.ZIndex = 101
ConfirmBox.Parent = ConfirmOverlay
corner(ConfirmBox, 8)
stroke(ConfirmBox, COLORS.Border, 1)

label(ConfirmBox, "Close bantai hub?",
    UDim2.new(1, -30, 0, 45), UDim2.new(0, 15, 0, 15),
    13, COLORS.Text, Enum.Font.GothamBold)

local YesBtn = Instance.new("TextButton")
YesBtn.Size = UDim2.new(0.42, 0, 0, 34)
YesBtn.Position = UDim2.new(0.05, 0, 1, -48)
YesBtn.BackgroundColor3 = COLORS.AccentDark
YesBtn.Text = "Yes"
YesBtn.TextColor3 = COLORS.Text
YesBtn.Font = Enum.Font.GothamBold
YesBtn.Parent = ConfirmBox
YesBtn.ZIndex = 102
corner(YesBtn, 6)

local NoBtn = Instance.new("TextButton")
NoBtn.Size = UDim2.new(0.42, 0, 0, 34)
NoBtn.Position = UDim2.new(0.53, 0, 1, -48)
NoBtn.BackgroundColor3 = COLORS.Off
NoBtn.Text = "No"
NoBtn.TextColor3 = COLORS.Text
NoBtn.Font = Enum.Font.GothamBold
NoBtn.Parent = ConfirmBox
NoBtn.ZIndex = 102
corner(NoBtn, 6)

local isMinimized = false

local RestoreCircle = Instance.new("TextButton")
RestoreCircle.Name = "RestoreCircle"
RestoreCircle.Size = UDim2.new(0, 46, 0, 46)
RestoreCircle.AnchorPoint = Vector2.new(0.5, 0.5)
RestoreCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
RestoreCircle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
RestoreCircle.Text = "B"
RestoreCircle.TextColor3 = Color3.fromRGB(255, 255, 255)
RestoreCircle.TextSize = 18
RestoreCircle.Font = Enum.Font.GothamBold
RestoreCircle.AutoButtonColor = false
RestoreCircle.Visible = false
RestoreCircle.ZIndex = 200
RestoreCircle.Parent = ScreenGui
corner(RestoreCircle, 23)
stroke(RestoreCircle, Color3.fromRGB(255, 255, 255), 1)

MinimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = true
    MainFrame.Visible = false
    RestoreCircle.Visible = true
end)

-- The minimized B button can be moved with mouse or touch. A simple tap
-- restores the main window; dragging only moves the circle.
do
    local dragging = false
    local dragStart = nil
    local startPos = nil
    local didDrag = false

    RestoreCircle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            didDrag = false
            dragStart = input.Position
            startPos = RestoreCircle.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragStart
        if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then didDrag = true end
        RestoreCircle.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end)

    RestoreCircle.MouseButton1Click:Connect(function()
        if didDrag then
            didDrag = false
            return
        end
        isMinimized = false
        RestoreCircle.Visible = false
        MainFrame.Visible = true
    end)
end

CloseBtn.MouseButton1Click:Connect(function()
    ConfirmOverlay.Visible = true
end)

NoBtn.MouseButton1Click:Connect(function()
    ConfirmOverlay.Visible = false
end)

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
        btn.BackgroundColor3 = (targetMobs[tName] or (tName == "" and next(targetMobs) == nil)) and COLORS.Accent or COLORS.Off
        btn.Text = text
        btn.TextColor3 = ((targetMobs[tName] or (tName == "" and next(targetMobs) == nil)) and COLORS.Window or COLORS.Text)
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
                    if b:IsA("TextButton") then b.BackgroundColor3 = COLORS.Off end
                end
                btn.BackgroundColor3 = COLORS.Accent
            else
                targetMobs[tName] = not targetMobs[tName]
                btn.BackgroundColor3 = targetMobs[tName] and COLORS.Accent or COLORS.Off
                
                for _, b in ipairs(MobScrollFrame:GetChildren()) do
                    if b:IsA("TextButton") and b.Text == "All Damageable" then
                        b.BackgroundColor3 = COLORS.Off
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
    MobScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
end

DropdownBtn.Activated:Connect(function()
    populateDropdown()
    local open = not MobScrollFrame.Visible
    MobScrollFrame.Visible = open
    MobScrollFrame.Size = open and UDim2.new(1, 0, 0, 150) or UDim2.new(1, 0, 0, 0)
end)
RefreshBtn.MouseButton1Click:Connect(populateDropdown)

SpeedBox.FocusLost:Connect(function()
    local num = tonumber(SpeedBox.Text:match("%d+"))
    if num and num > 0 then
        speed = num
        if ChestSpeedRow then
            local labels = {}
            for _, child in ipairs(ChestSpeedRow:GetChildren()) do if child:IsA("TextLabel") then labels[#labels+1] = child end end
            if labels[2] then labels[2].Text = "Uses the same Tween Speed value from Farm Settings: " .. tostring(speed) end
        end
    end
    SpeedBox.Text = "Tween Speed: " .. tostring(speed)
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
function getFruitName(fruit)
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
        if string.find(string.lower(child.Name), "fruit", 1, true) then
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
                local dist = math.floor((Player.Character.HumanoidRootPart.Position - pos).Magnitude + 0.5)
                FruitStatusLabel.Text = string.format("Fruit: %s\nDistance: %d studs away", name, dist)
            end
            task.wait(0.3)
        end
        if scriptRunning and NotifierEnabled then
            scanForFruits()
            if not CurrentFruit then
                FruitStatusLabel.Text = "No fruit spawned"
            end
        end
    end)
end

local function renderNotifierToggle(enabled)
    NotifierToggle.BackgroundColor3 = enabled and COLORS.Accent or COLORS.Off
    NotifierKnob.BackgroundColor3 = enabled and COLORS.Window or COLORS.Knob
    NotifierKnob:TweenPosition(
        enabled and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
        Enum.EasingDirection.Out,
        Enum.EasingStyle.Quad,
        0.12,
        true
    )
end

local function toggleNotifier()
    NotifierEnabled = not NotifierEnabled
    renderNotifierToggle(NotifierEnabled)

    if NotifierEnabled then
        FruitStatusLabel.Text = "Searching for spawned fruit..."

        if WorkspaceConnection then
            WorkspaceConnection:Disconnect()
            WorkspaceConnection = nil
        end

        WorkspaceConnection = Workspace.ChildAdded:Connect(function(child)
            if string.find(string.lower(child.Name), "fruit", 1, true) then
                trackFruit(child)
            end
        end)

        scanForFruits()
        if CurrentFruit then
            trackFruit(CurrentFruit)
        else
            FruitStatusLabel.Text = "No fruit spawned"
        end
    else
        FruitStatusLabel.Text = "Fruit Notifier: Off"
        if WorkspaceConnection then
            WorkspaceConnection:Disconnect()
            WorkspaceConnection = nil
        end
        CurrentFruit = nil
    end
end

local NotifierToggleLock = false
local function guardedNotifierToggle()
    if NotifierToggleLock then return end
    NotifierToggleLock = true
    toggleNotifier()
    task.delay(0.12, function() NotifierToggleLock = false end)
end
NotifierBtn.Activated:Connect(guardedNotifierToggle)
NotifierToggle.Activated:Connect(guardedNotifierToggle)

-----------------------------------
-- OPTIMIZED FAST ATTACK (BUG & LAG FREE)
-----------------------------------
_G.FastAttack = true
if _G.FastAttack then
    local _ENV = getSharedEnvironment()
    local function SafeWaitForChild(parent, childName, timeout)
        if not parent then return nil end
        local success, result = pcall(function()
            return parent:WaitForChild(childName, timeout or 10)
        end)
        return success and result or nil
    end
    local Remotes = SafeWaitForChild(ReplicatedStorage, "Remotes")
    local Modules = SafeWaitForChild(ReplicatedStorage, "Modules")
    local Net = SafeWaitForChild(Modules, "Net")

    local Settings = { AutoClick = true, ClickDelay = 0.03 }
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
                        local netModule = ReplicatedStorage:FindFirstChild("Modules")
                        netModule = netModule and netModule:FindFirstChild("Net")
                        if not netModule then return end

                        pcall(function()
                            local netRequire = require(netModule)
                            if type(netRequire) == "table" and type(netRequire.RemoteEvent) == "function" then
                                netRequire:RemoteEvent("RegisterHit", true)
                            end
                        end)

                        local registerAttack = netModule:FindFirstChild("RE/RegisterAttack")
                        local registerHit = netModule:FindFirstChild("RE/RegisterHit")
                        if not registerAttack or not registerHit then return end

                        registerAttack:FireServer()
                        local head = parts[1][1]:FindFirstChild("Head")
                        if not head then return end
                        registerHit:FireServer(head, parts, {}, tostring(Player.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15))

                        if remote and idremote and type(bit32) == "table" and type(bit32.bxor) == "function" then
                            local seedRemote = netModule:FindFirstChild("seed")
                            local seed
                            if seedRemote and seedRemote:IsA("RemoteFunction") then
                                local ok, value = pcall(function() return seedRemote:InvokeServer() end)
                                if ok then seed = value end
                            end
                            if type(seed) == "number" then
                                cloneReference(remote):FireServer(string.gsub("RE/RegisterHit", ".", function(c)
                                    return string.char(bit32.bxor(string.byte(c), math.floor(Workspace:GetServerTimeNow() / 10 % 10) + 1))
                                end),
                                bit32.bxor(idremote + 909090, seed * 2), head, parts)
                            end
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

local function equipFarmWeapon()
    local char = Player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local backpack = Player:FindFirstChildOfClass("Backpack")
    if not char or not hum or not backpack then return false end

    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped then return true end

    local preferred = nil
    local fallback = nil
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            fallback = fallback or tool
            local tip = string.lower(tostring(tool.ToolTip or ""))
            if tip == "melee" or tip == "sword" then
                preferred = tool
                break
            end
        end
    end

    local tool = preferred or fallback
    if not tool then return false end

    local ok = pcall(function()
        hum:EquipTool(tool)
    end)
    return ok
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
        activeTween = nil
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
            pcall(equipFarmWeapon)
            local ok, targetHrp, targetHumanoid = pcall(getNearestNPC)
            if not ok then
                targetHrp, targetHumanoid = nil, nil
            end
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
-- LOCAL PLAYER
-----------------------------------
local function setLocalToggle(button, knob, enabled)
    button.BackgroundColor3 = enabled and COLORS.Accent or COLORS.Off
    knob.BackgroundColor3 = enabled and COLORS.Window or COLORS.Knob
    knob:TweenPosition(
        enabled and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
        Enum.EasingDirection.Out,
        Enum.EasingStyle.Quad,
        0.12,
        true
    )
end

local function getWaterPlane()
    local map = Workspace:FindFirstChild("Map")
    local water = map and map:FindFirstChild("WaterBase-Plane")
    if water and water:IsA("BasePart") then
        return water
    end
    return nil
end

setWaterWalk = function(enabled)
    WalkWaterEnabled = enabled
    local water = getWaterPlane()
    if not water then return false end

    local ok = pcall(function()
        if enabled then
            -- Working water-walk height from the supplied farming source.
            water.Size = Vector3.new(1000, 112, 1000)
        else
            water.Size = Vector3.new(1000, 80, 1000)
        end
    end)
    return ok
end

task.spawn(function()
    while scriptRunning do
        if WalkWaterEnabled then
            pcall(setWaterWalk, true)
        end
        task.wait(0.35)
    end
end)

local AutoV4LoopRunning = false
local AutoV3LoopRunning = false

local function startAutoV4()
    if AutoV4LoopRunning then return end
    AutoV4LoopRunning = true

    task.spawn(function()
        while scriptRunning and AutoV4Enabled do
            pcall(function()
                local char = Player.Character
                local energy = char and char:FindFirstChild("RaceEnergy")
                local transformed = char and char:FindFirstChild("RaceTransformed")
                local awakening = (Player.Backpack and Player.Backpack:FindFirstChild("Awakening"))
                    or (char and char:FindFirstChild("Awakening"))

                if energy and transformed and energy.Value >= 1 and not transformed.Value and awakening then
                    local remoteFunction = awakening:FindFirstChild("RemoteFunction")
                    if remoteFunction then
                        remoteFunction:InvokeServer(true)
                    end
                end
            end)
            task.wait(1)
        end

        AutoV4LoopRunning = false
    end)
end

local function startAutoV3()
    if AutoV3LoopRunning then return end
    AutoV3LoopRunning = true

    task.spawn(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commE = remotes and remotes:FindFirstChild("CommE")

        while scriptRunning and AutoV3Enabled do
            pcall(function()
                if commE then
                    commE:FireServer("ActivateAbility")
                end
            end)
            task.wait(1)
        end

        AutoV3LoopRunning = false
    end)
end

-- The source uses Awakening.RemoteFunction(true) for V4 and
-- Remotes.CommE:FireServer("ActivateAbility") for V3. 

task.spawn(function()
    while scriptRunning do
        if AutoV4Enabled then startAutoV4() end
        if AutoV3Enabled then startAutoV3() end

        if WalkWaterEnabled then
            pcall(setWaterWalk, true)
        end

        task.wait(0.35)
    end
end)

-----------------------------------
-- AUTO CHEST FARM
-----------------------------------
local function getNearestChest()
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil, math.huge end

    local nearest, nearestDistance = nil, math.huge
    local tagged = {}
    local ok, result = pcall(function() return CollectionService:GetTagged("_ChestTagged") end)
    if ok and type(result) == "table" then tagged = result end

    for _, chest in ipairs(tagged) do
        if chest and chest.Parent and not chest:GetAttribute("IsDisabled") then
            local okPivot, pivot = pcall(function() return chest:GetPivot() end)
            if okPivot and pivot then
                local distance = (pivot.Position - root.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearest = chest
                end
            end
        end
    end
    return nearest, nearestDistance
end

local function stopChestMovement()
    ChestFarmToken += 1
    ChestFarmMoving = false
    if ChestFarmTween then
        pcall(function() ChestFarmTween:Cancel() end)
        ChestFarmTween = nil
    end
end

local function moveToChest(cframe)
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not ChestFarmEnabled then return false end

    stopChestMovement()
    local token = ChestFarmToken
    ChestFarmMoving = true

    if ChestFarmMode == "Teleport" then
        char:PivotTo(cframe)
        ChestFarmMoving = false
        return true
    end

    local distance = (root.Position - cframe.Position).Magnitude
    if distance <= 8 then
        char:PivotTo(cframe)
        ChestFarmMoving = false
        return true
    end

    local duration = math.clamp(distance / math.max(speed, 1), 0.12, 8)
    applySuspension(root)
    ChestFarmTween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = cframe})
    local tween = ChestFarmTween
    local completed = false
    local conn = tween.Completed:Connect(function() completed = true end)
    tween:Play()

    while ChestFarmEnabled and scriptRunning and token == ChestFarmToken and not completed do
        task.wait()
        if not root.Parent then break end
    end

    if conn then conn:Disconnect() end
    if tween == ChestFarmTween then
        ChestFarmTween = nil
    end
    ChestFarmMoving = false
    return ChestFarmEnabled and scriptRunning and token == ChestFarmToken and completed
end

local function triggerChestTouch(chest)
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not chest or not chest.Parent then return end

    local touchPart = nil
    if chest:IsA("BasePart") then
        touchPart = chest
    else
        touchPart = chest:FindFirstChildWhichIsA("BasePart", true)
    end
    if not touchPart then return end

    pcall(function()
        if typeof(firetouchinterest) == "function" then
            firetouchinterest(touchPart, root, 0)
            task.wait(0.03)
            firetouchinterest(touchPart, root, 1)
        end
    end)

    pcall(function()
        if typeof(firesignal) == "function" then
            firesignal(touchPart.Touched, root)
        end
    end)
end

local function collectNearestChest()
    local chest, distance = getNearestChest()
    if not chest then
        ChestStatusLabel.Text = "Chest Farm: ON\nNo available chest found"
        return
    end

    local okPivot, pivot = pcall(function() return chest:GetPivot() end)
    if not okPivot or not pivot then return end
    ChestStatusLabel.Text = string.format("Chest Farm: ON\nNearest chest: %d studs away", math.floor(distance + 0.5))

    if moveToChest(pivot) and ChestFarmEnabled then
        task.wait(0.08)
        triggerChestTouch(chest)
        for _ = 1, 5 do
            if not ChestFarmEnabled or not chest.Parent or chest:GetAttribute("IsDisabled") then break end
            task.wait(0.12)
            triggerChestTouch(chest)
        end
    end
end

local function renderChestToggle(enabled)
    if not ChestFarmToggle or not ChestFarmKnob then return end
    ChestFarmToggle.BackgroundColor3 = enabled and Color3.fromRGB(255,255,255) or COLORS.Off
    ChestFarmKnob.BackgroundColor3 = enabled and Color3.fromRGB(0,0,0) or COLORS.Knob
    ChestFarmKnob:TweenPosition(enabled and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.12, true)
end

local ChestToggleLock = false
local function toggleChestFarm()
    if ChestToggleLock then return end
    ChestToggleLock = true
    ChestFarmEnabled = not ChestFarmEnabled
    renderChestToggle(ChestFarmEnabled)
    if ChestFarmEnabled then
        ChestStatusLabel.Text = "Chest Farm: ON\nScanning for nearest chest..."
    else
        stopChestMovement()
        removeSuspension()
        ChestStatusLabel.Text = "Chest Farm: OFF\nNearest chest: idle"
    end
    task.delay(0.12, function() ChestToggleLock = false end)
end
ChestFarmToggle.Activated:Connect(toggleChestFarm)
ChestFarmRow.Activated:Connect(toggleChestFarm)
renderChestToggle(false)

task.spawn(function()
    while scriptRunning do
        if ChestFarmEnabled and not ChestFarmMoving then
            pcall(collectNearestChest)
            task.wait(0.15)
        else
            task.wait(0.15)
        end
    end
end)

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

    local env = getSharedEnvironment()
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

local function renderRaidToggle(enabled)
    RaidToggle.BackgroundColor3 = enabled and COLORS.Accent or COLORS.Off
    RaidKnob.BackgroundColor3 = enabled and COLORS.Window or COLORS.Knob
    RaidKnob:TweenPosition(
        enabled and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
        Enum.EasingDirection.Out,
        Enum.EasingStyle.Quad,
        0.12,
        true
    )
end

local function toggleAutoRaid()
    AutoRaidActive = not AutoRaidActive
    renderRaidToggle(AutoRaidActive)

    if AutoRaidActive then
        StartAutoRaid()
    else
        StopRaidTween()
    end
end

local RaidToggleLock = false
local function guardedRaidToggle()
    if RaidToggleLock then return end
    RaidToggleLock = true
    toggleAutoRaid()
    task.delay(0.12, function() RaidToggleLock = false end)
end
RaidToggle.Activated:Connect(guardedRaidToggle)
RaidRow.Activated:Connect(guardedRaidToggle)

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

local function renderFarmToggle(enabled)
    if not FarmToggle or not FarmKnob then return end
    FarmToggle.BackgroundColor3 = enabled and COLORS.Accent or COLORS.Off
    FarmKnob.BackgroundColor3 = enabled and COLORS.Window or COLORS.Knob
    FarmKnob:TweenPosition(
        enabled and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
        Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.12, true
    )
end

local function toggleScript()
    active = not active
    pressJ()
    renderFarmToggle(active)

    if active then
        startLoop()
    else
        if activeTween then
            activeTween:Cancel()
            activeTween = nil
        end
        removeSuspension()
    end
end

local FarmToggleLock = false
local function guardedFarmToggle()
    if FarmToggleLock then return end
    FarmToggleLock = true
    toggleScript()
    task.delay(0.12, function() FarmToggleLock = false end)
end
FarmToggle.Activated:Connect(guardedFarmToggle)
FarmRow.Activated:Connect(guardedFarmToggle)

YesBtn.MouseButton1Click:Connect(function()
    scriptRunning = false
    saveHopMode("")
    active = false
    AutoRaidActive = false
    ChestFarmEnabled = false
    stopChestMovement()
    StopRaidTween()
    if activeTween then
        pcall(function() activeTween:Cancel() end)
        activeTween = nil
    end
    if WorkspaceConnection then
        WorkspaceConnection:Disconnect()
        WorkspaceConnection = nil
    end
    removeSuspension()
    if WalkWaterEnabled then setWaterWalk(false) end
    WalkWaterEnabled = false
    if AutoV4Enabled then AutoV4Enabled = false end
    if AutoV3Enabled then AutoV3Enabled = false end
    ScreenGui:Destroy()
end)

local function setupDeathListener(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then
        hum.Died:Connect(function()
            AutoRaidActive = false
            ChestFarmEnabled = false
            stopChestMovement()
            StopRaidTween()
            removeSuspension()
            if WalkWaterEnabled then
                setWaterWalk(false)
                task.defer(function()
                    if scriptRunning and WalkWaterEnabled then
                        setWaterWalk(true)
                    end
                end)
            end
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
    if WalkWaterEnabled then
        task.wait(0.2)
        setWaterWalk(true)
    end
end)

if Player.Character then
    setupDeathListener(Player.Character)
end

-----------------------------------
-- BANTAI HUB ADD-ON FEATURES
-- Added after the complete original script so the original GUI/startup order
-- is left untouched. Every feature is isolated behind pcall where game APIs
-- can vary between versions.
-----------------------------------

B = {} -- shared Bantai state
B.BantaiBringMobsEnabled = false
B.BantaiBringRange = 500
B.BantaiSelectedRaid = "Flame"
B.BantaiAutoBuyChip = false
B.BantaiAutoStartRaid = false

-----------------------------------
-- BRING MOBS UI
-----------------------------------
B.BantaiBringRow = makeToggle(
    FarmingPage,
    "Bring Mobs",
    "Pull matching damageable NPCs together while farming.",
    7,
    false,
    function(enabled)
        B.BantaiBringMobsEnabled = enabled
    end
)

B.BantaiBringRangeRow, B.BantaiBringRangeBox = makeInput(
    FarmSettingsPage,
    "Bring Mob Range",
    "Maximum distance used when collecting matching mobs.",
    5,
    B.BantaiBringRange,
    function(box, value)
        local num = tonumber(tostring(value):match("%d+"))
        if num then
            B.BantaiBringRange = math.clamp(num, 50, 1500)
        end
        box.Text = tostring(B.BantaiBringRange)
    end
)

function B.BantaiIsSelectedMob(model)
    if not model then return false end
    if next(targetMobs) == nil then return true end
    return targetMobs[model.Name] == true
end

function B.BantaiBringMobs()
    if not B.BantaiBringMobsEnabled then return end

    local character = Player.Character
    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
    local enemies = Workspace:FindFirstChild("Enemies")
    if not playerRoot or not enemies then return end

    local candidates = {}
    for _, mob in ipairs(enemies:GetChildren()) do
        if IsDamageableNPC(mob) and B.BantaiIsSelectedMob(mob) then
            local root = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart
            if root then
                local distance = (root.Position - playerRoot.Position).Magnitude
                if distance <= B.BantaiBringRange then
                    candidates[mob.Name] = candidates[mob.Name] or mob
                end
            end
        end
    end

    for _, mob in ipairs(enemies:GetChildren()) do
        if IsDamageableNPC(mob) and B.BantaiIsSelectedMob(mob) then
            local root = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart
            local anchor = candidates[mob.Name]
            local anchorRoot = anchor and (anchor:FindFirstChild("HumanoidRootPart") or anchor.PrimaryPart)

            if root and anchorRoot and anchor ~= mob then
                local playerDistance = (root.Position - playerRoot.Position).Magnitude
                local anchorDistance = (root.Position - anchorRoot.Position).Magnitude

                if playerDistance <= B.BantaiBringRange and anchorDistance <= B.BantaiBringRange then
                    pcall(function()
                        root.CanCollide = false
                        root.AssemblyLinearVelocity = Vector3.zero
                        root.AssemblyAngularVelocity = Vector3.zero
                        local humanoid = mob:FindFirstChildOfClass("Humanoid")
                        if humanoid then
                            humanoid.WalkSpeed = 0
                            humanoid.AutoRotate = false
                        end
                        mob:PivotTo(anchorRoot.CFrame)
                    end)
                end
            end
        end
    end
end

-----------------------------------
-- RAID CONTROLS UI
-----------------------------------
B.BantaiRaidOptions = {}
pcall(function()
    local raidsModule = ReplicatedStorage:FindFirstChild("Raids")
    if raidsModule then
        local raidsData = require(raidsModule)
        for _, raidList in pairs(raidsData) do
            if type(raidList) == "table" then
                for _, raidName in pairs(raidList) do
                    if type(raidName) == "string" and not table.find(B.BantaiRaidOptions, raidName) then
                        table.insert(B.BantaiRaidOptions, raidName)
                    end
                end
            end
        end
    end
end)
if #B.BantaiRaidOptions == 0 then
    B.BantaiRaidOptions = {
        "Flame", "Ice", "Sand", "Dark", "Light", "Magma",
        "Quake", "Buddha", "Spider", "Phoenix", "Rumble", "Dough"
    }
end
B.BantaiRaidIndex = 1

-- Real raid selector: opens a list of every chip instead of cycling one-by-one.
B.BantaiRaidSelectRow = nil
B.BantaiRaidSelectList = nil
B.BantaiRaidSelectRow = makeDescriptionRow(
    RaidsPage,
    "Select Raid: " .. B.BantaiSelectedRaid,
    "Tap to open the full raid list.",
    3,
    function(row, desc)
        local arrow = label(row, "⌄", UDim2.new(0, 30, 1, 0), UDim2.new(1, -45, 0, 0), 18, COLORS.Accent, Enum.Font.GothamBold)
        arrow.TextXAlignment = Enum.TextXAlignment.Center

        local list = Instance.new("ScrollingFrame")
        list.Name = "RaidOptions"
        list.LayoutOrder = 4
        list.Size = UDim2.new(1, 0, 0, 0)
        list.BackgroundColor3 = COLORS.Row
        list.BorderSizePixel = 0
        list.ScrollBarThickness = 3
        list.ScrollBarImageColor3 = COLORS.Accent
        list.AutomaticCanvasSize = Enum.AutomaticSize.Y
        list.CanvasSize = UDim2.new()
        list.Visible = false
        list.Parent = RaidsPage
        corner(list, 6)

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 3)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = list

        local padding = Instance.new("UIPadding")
        padding.PaddingTop = UDim.new(0, 4)
        padding.PaddingBottom = UDim.new(0, 4)
        padding.PaddingLeft = UDim.new(0, 4)
        padding.PaddingRight = UDim.new(0, 4)
        padding.Parent = list

        for index, raidName in ipairs(B.BantaiRaidOptions) do
            local option = Instance.new("TextButton")
            option.Name = raidName .. "RaidOption"
            option.LayoutOrder = index
            option.Size = UDim2.new(1, 0, 0, 34)
            option.BackgroundColor3 = COLORS.Content
            option.Text = raidName
            option.TextColor3 = COLORS.Text
            option.TextSize = 10
            option.Font = Enum.Font.GothamMedium
            option.TextXAlignment = Enum.TextXAlignment.Left
            option.AutoButtonColor = false
            option.Parent = list
            corner(option, 5)

            option.Activated:Connect(function()
                B.BantaiRaidIndex = index
                B.BantaiSelectedRaid = raidName
                local titleLabel = B.BantaiRaidSelectRow:FindFirstChildWhichIsA("TextLabel")
                if titleLabel then titleLabel.Text = "Select Raid: " .. raidName end
                desc.Text = "Selected: " .. raidName .. " • Tap to change"
                list.Visible = false
                list.Size = UDim2.new(1, 0, 0, 0)
                arrow.Text = "⌄"
            end)
        end

        local open = false
        local function toggleList()
            open = not open
            list.Visible = open
            list.Size = open and UDim2.new(1, 0, 0, math.min(12 * 37 + 8, 240)) or UDim2.new(1, 0, 0, 0)
            arrow.Text = open and "⌃" or "⌄"
        end
        row.Activated:Connect(toggleList)
        arrow.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                toggleList()
            end
        end)
        B.BantaiRaidSelectList = list
    end
)

B.BantaiBuyChipRow = makeToggle(
    RaidsPage,
    "Auto Buy Chip",
    "Automatically request the selected raid chip when none is owned.",
    5,
    false,
    function(enabled)
        B.BantaiAutoBuyChip = enabled
    end
)

B.BantaiStartRaidRow = makeToggle(
    RaidsPage,
    "Auto Start Raid",
    "Automatically start a raid when a Special Microchip is available.",
    6,
    false,
    function(enabled)
        B.BantaiAutoStartRaid = enabled
    end
)

-----------------------------------
-- STATUS UI
-----------------------------------
addSection(StatusPage, "Status", 1)

B.BantaiMoonRow = makeDescriptionRow(
    StatusPage,
    "Moon Phase",
    "Checking...",
    2,
    function() end
)
B.BantaiLeviathanRow = makeDescriptionRow(
    StatusPage,
    "Leviathan",
    "Checking...",
    3,
    function() end
)
B.BantaiFruitStockRow = makeDescriptionRow(
    StatusPage,
    "Fruit Stock",
    "Checking...",
    4,
    function() end
)

-- Fruit stock is intentionally tall because Night Hub displays each fruit on
-- its own line together with its price.
B.BantaiFruitStockRow.Size = UDim2.new(1, 0, 0, 260)
do
    local stockLabels = {}
    for _, child in ipairs(B.BantaiFruitStockRow:GetChildren()) do
        if child:IsA("TextLabel") then stockLabels[#stockLabels + 1] = child end
    end
    if stockLabels[2] then
        stockLabels[2].TextWrapped = true
        stockLabels[2].TextTruncate = Enum.TextTruncate.None
        stockLabels[2].TextYAlignment = Enum.TextYAlignment.Top
        stockLabels[2].Size = UDim2.new(1, -26, 0, 210)
        stockLabels[2].Position = UDim2.new(0, 13, 0, 34)
    end
end

function B.BantaiSetRowDescription(row, value)
    local labels = {}
    for _, child in ipairs(row:GetChildren()) do
        if child:IsA("TextLabel") then
            labels[#labels + 1] = child
        end
    end
    if labels[2] then
        labels[2].Text = tostring(value)
    end
end

function B.BantaiGetCommF()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CommF_")
end

function B.BantaiHasRaidChip()
    local backpack = Player:FindFirstChild("Backpack")
    local character = Player.Character
    return (backpack and backpack:FindFirstChild("Special Microchip") ~= nil)
        or (character and character:FindFirstChild("Special Microchip") ~= nil)
end

function B.BantaiRaidIsActive()
    local playerGui = Player:FindFirstChild("PlayerGui")
    local main = playerGui and playerGui:FindFirstChild("Main")
    local timer = main and main:FindFirstChild("Timer")
    if timer and timer:IsA("GuiObject") then
        return timer.Visible
    end

    local topHud = main and main:FindFirstChild("TopHUDList")
    local raidTimer = topHud and topHud:FindFirstChild("RaidTimer")
    return raidTimer and raidTimer:IsA("GuiObject") and raidTimer.Visible or false
end

function B.BantaiStartRaid()
    if B.BantaiRaidIsActive() or not B.BantaiHasRaidChip() then return false end

    local map = Workspace:FindFirstChild("Map")
    if not map then return false end

    -- Use the exact RaidSummon2 locations used by the supplied reference,
    -- then fall back to a guarded descendant search for map variants.
    local detectors = {}
    pcall(function()
        local boatCastle = map:FindFirstChild("Boat Castle")
        local raidSummon = boatCastle and boatCastle:FindFirstChild("RaidSummon2")
        local button = raidSummon and raidSummon:FindFirstChild("Button")
        local main = button and button:FindFirstChild("Main")
        local detector = main and main:FindFirstChildOfClass("ClickDetector")
        if detector then detectors[#detectors + 1] = detector end
    end)

    pcall(function()
        local circleIsland = map:FindFirstChild("CircleIsland")
        local raidSummon = circleIsland and circleIsland:FindFirstChild("RaidSummon2")
        local button = raidSummon and raidSummon:FindFirstChild("Button")
        local main = button and button:FindFirstChild("Main")
        local detector = main and main:FindFirstChildOfClass("ClickDetector")
        if detector then detectors[#detectors + 1] = detector end
    end)

    if #detectors == 0 then
        pcall(function()
            for _, obj in ipairs(map:GetDescendants()) do
                if obj:IsA("ClickDetector") then
                    local parentName = obj.Parent and obj.Parent.Name:lower() or ""
                    local fullName = obj:GetFullName():lower()
                    if parentName == "main" and fullName:find("raidsummon2", 1, true) then
                        detectors[#detectors + 1] = obj
                        break
                    end
                end
            end
        end)
    end

    if #detectors == 0 then return false end

    local fired = false
    pcall(function()
        if type(fireclickdetector) == "function" then
            fireclickdetector(detectors[1])
            fired = true
        end
    end)
    return fired
end

function B.BantaiMoonPhase()
    local lighting = game:GetService("Lighting")
    local sky = lighting:FindFirstChildOfClass("Sky")
    local texture = sky and tostring(sky.MoonTextureId or "") or ""
    texture = texture:match("%d+") or ""

    local phases = {
        ["9709149431"] = "🌕 Full Moon (100%)",
        ["9709149052"] = "🌔 Waxing Gibbous (75%)",
        ["9709143733"] = "🌓 First Quarter (50%)",
        ["9709150401"] = "🌒 Waxing Crescent (25%)",
        ["9709149680"] = "🌘 Waning Crescent (15%)",
    }

    local clock = lighting.ClockTime
    local night = clock >= 18 or clock < 5
    if not night then
        return "☀️ Day / Moon not visible"
    end

    if texture == "9709149431" or texture == "79932823311771" then
        return "🌕 Full Moon (100%)"
    elseif phases[texture] then
        return phases[texture]
    end
    return "🌙 Night / Unknown phase"
end

function B.BantaiLeviathanStatus()
    local map = Workspace:FindFirstChild("Map")
    local commF = B.BantaiGetCommF()
    if not commF then return "Remote unavailable" end

    -- Same server query used by the supplied Night Hub reference.
    local ok, response = pcall(function()
        return commF:InvokeServer("InfoLeviathan", "1")
    end)
    if not ok then
        return "Unavailable"
    end

    if map and map:FindFirstChild("LeviathanGate") then
        return "🧊 Frozen Dimension Spawn"
    end

    local seaBeasts = Workspace:FindFirstChild("SeaBeasts")
    local leviathan = seaBeasts and seaBeasts:FindFirstChild("Leviathan")
    if leviathan then
        return "🐋 Spawned"
    end

    if response == 5 then
        return "🐋 The Leviathan is out there!"
    end
    if response ~= -1 and response ~= nil then
        return "💬 Spy information available"
    end
    return "❌ I don't know anything yet."
end

function B.BantaiFruitStockStatus()
    local commF = B.BantaiGetCommF()
    if not commF then return "Remote unavailable" end

    local ok, response = pcall(function()
        return commF:InvokeServer("GetFruits")
    end)
    if not ok or type(response) ~= "table" then
        return "Unavailable"
    end

    local onSale = {}
    local rarityNames = {
        [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Legendary", [5] = "Mythical"
    }

    local function formatPrice(value)
        local text = tostring(math.floor(tonumber(value) or 0))
        repeat
            local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
            text = replaced
            if count == 0 then break end
        until false
        return text
    end

    for _, fruit in pairs(response) do
        if type(fruit) == "table" and fruit.OnSale then
            local name = tostring(fruit.Name or "Unknown Fruit")
            local rarity = rarityNames[tonumber(fruit.Rarity)] or tostring(fruit.Rarity or "Unknown")
            local price = formatPrice(fruit.Price)
            onSale[#onSale + 1] = string.format("__R%d__🍎 %s [%s] — %s$", tonumber(fruit.Rarity) or 0, name, rarity, price)
        end
    end
    table.sort(onSale, function(a, b)
        local ra = tonumber(a:match("__R(%d+)__")) or 0
        local rb = tonumber(b:match("__R(%d+)__")) or 0
        if ra ~= rb then return ra > rb end
        return a:lower() < b:lower()
    end)
    for i = 1, #onSale do
        onSale[i] = onSale[i]:gsub("__R%d+__", "")
    end

    if #onSale == 0 then
        return "No fruits on sale"
    end
    return table.concat(onSale, "\n")
end

-----------------------------------
-- FEATURE WORKERS
-- These are deliberately started last, after every original function and
-- GUI object in Bantai v3 has already been created.
-----------------------------------

task.spawn(function()
    while scriptRunning do
        if B.BantaiBringMobsEnabled then
            pcall(B.BantaiBringMobs)
        end
        task.wait(0.08)
    end
end)

task.spawn(function()
    while scriptRunning do
        if B.BantaiAutoBuyChip and not B.BantaiRaidIsActive() and not B.BantaiHasRaidChip() then
            local commF = B.BantaiGetCommF()
            if commF then
                pcall(function()
                    commF:InvokeServer("RaidsNpc", "Select", B.BantaiSelectedRaid)
                end)
            end
        end
        task.wait(1.5)
    end
end)

task.spawn(function()
    while scriptRunning do
        if B.BantaiAutoStartRaid and not B.BantaiRaidIsActive() and B.BantaiHasRaidChip() then
            pcall(B.BantaiStartRaid)
        end
        task.wait(0.75)
    end
end)

task.spawn(function()
    task.wait(0.5)
    while scriptRunning do
        pcall(function()
            B.BantaiSetRowDescription(B.BantaiMoonRow, B.BantaiMoonPhase())
        end)
        pcall(function()
            B.BantaiSetRowDescription(B.BantaiLeviathanRow, B.BantaiLeviathanStatus())
        end)
        pcall(function()
            B.BantaiSetRowDescription(B.BantaiFruitStockRow, B.BantaiFruitStockStatus())
        end)
        task.wait(4)
    end
end)



-----------------------------------
-- BOSS FARM + SHOP EXTENSION
-----------------------------------
B.BossFarmEnabled = false
B.BossTween = nil
B.SelectedBoss = nil
B.BossSelectRow = nil
B.BossSelectList = nil

B.WorldBosses = {
    [1] = {"The Gorilla King", "The Saw", "Bobby", "Yeti", "Mob Leader", "Vice Admiral", "Warden", "Chief Warden", "Swan", "Magma Admiral", "Fishman Lord", "Wysper", "Thunder God", "Cyborg", "Saber Expert"},
    [2] = {"Diamond", "Jeremy", "Fajita", "Don Swan", "Smoke Admiral", "Cursed Captain", "Darkbeard", "Order", "Awakened Ice Admiral", "Tide Keeper"},
    [3] = {"Stone", "Island Empress", "Rocket Admiral", "Captain Elephant", "Beautiful Pirate", "rip_indra True Form", "Longma", "Soul Reaper", "Cake Queen", "Cake Prince", "Dough King"},
}

function B.getSeaIndex()
    local place = game.PlaceId
    if place == 2753915549 then return 1 end
    if place == 4442272183 then return 2 end
    return 3
end

function B.setBossTitle(name)
    if B.BossSelectRow then
        local labels = {}
        for _, child in ipairs(B.BossSelectRow:GetChildren()) do
            if child:IsA("TextLabel") then labels[#labels+1] = child end
        end
        if labels[1] then labels[1].Text = "Select Boss: " .. tostring(name or "None") end
        if labels[2] then labels[2].Text = "Choose any boss from this sea." end
    end
end

function B.makeBossSelector()
    local bosses = B.WorldBosses[B.getSeaIndex()] or B.WorldBosses[3]
    B.SelectedBoss = bosses[1]
    B.BossSelectRow = makeDescriptionRow(FarmingPage, "Select Boss: " .. B.SelectedBoss,
        "Choose any boss from this sea.", 12, function(row, desc)
            local arrow = label(row, "⌄", UDim2.new(0,30,1,0), UDim2.new(1,-45,0,0), 18, COLORS.Text, Enum.Font.GothamBold)
            arrow.TextXAlignment = Enum.TextXAlignment.Center
            local list = Instance.new("ScrollingFrame")
            list.Name = "BossOptions"
            list.LayoutOrder = 13
            list.Size = UDim2.new(1,0,0,0)
            list.BackgroundColor3 = COLORS.Row
            list.BackgroundTransparency = 0.05
            list.BorderSizePixel = 0
            list.ScrollBarThickness = 3
            list.ScrollBarImageColor3 = COLORS.Accent
            list.AutomaticCanvasSize = Enum.AutomaticSize.Y
            list.CanvasSize = UDim2.new()
            list.Visible = false
            list.Parent = FarmingPage
            corner(list,6)
            local layout = Instance.new("UIListLayout")
            layout.Padding = UDim.new(0,3)
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Parent = list
            for i,boss in ipairs(bosses) do
                local option = Instance.new("TextButton")
                option.Size = UDim2.new(1,0,0,36)
                option.LayoutOrder = i
                option.BackgroundColor3 = COLORS.Content
                option.BackgroundTransparency = 0.08
                option.Text = boss
                option.TextColor3 = COLORS.Text
                option.TextSize = 10
                option.Font = Enum.Font.GothamMedium
                option.TextXAlignment = Enum.TextXAlignment.Left
                option.AutoButtonColor = false
                option.Parent = list
                corner(option,5)
                option.Activated:Connect(function()
                    B.SelectedBoss = boss
                    B.setBossTitle(boss)
                    list.Visible = false
                    list.Size = UDim2.new(1,0,0,0)
                    arrow.Text = "⌄"
                end)
            end
            local open = false
            local function toggle()
                open = not open
                list.Visible = open
                list.Size = open and UDim2.new(1,0,0,math.min(#bosses*39+8,250)) or UDim2.new(1,0,0,0)
                arrow.Text = open and "⌃" or "⌄"
            end
            row.Activated:Connect(toggle)
        end)
    return B.BossSelectRow
end
B.makeBossSelector()

B.BossStatusRow = makeDescriptionRow(FarmingPage, "Boss Status", "Checking...", 14, function() end)
B.BossFarmRow = makeToggle(FarmingPage, "Boss Farm", "Fly above the selected boss and use Bantai's existing fast-attack module.", 15, false, function(v)
    B.BossFarmEnabled = v
end)

function B.findBossModel()
    if not B.SelectedBoss then return nil end
    local enemies = Workspace:FindFirstChild("Enemies")
    local m = enemies and enemies:FindFirstChild(B.SelectedBoss)
    if m and m:FindFirstChildOfClass("Humanoid") then return m end
    local replicated = ReplicatedStorage:FindFirstChild(B.SelectedBoss)
    if replicated and replicated:IsA("Model") then return replicated end
    return nil
end

function B.bossFarmStep()
    local boss = B.findBossModel()
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = boss and boss:FindFirstChildOfClass("Humanoid")
    local hrp = boss and boss:FindFirstChild("HumanoidRootPart")
    if not boss or not root or not hum or not hrp or hum.Health <= 0 then
        B.BantaiSetRowDescription(B.BossStatusRow, "❌ " .. tostring(B.SelectedBoss) .. " not spawned")
        return
    end
    B.BantaiSetRowDescription(B.BossStatusRow, "✅ " .. tostring(B.SelectedBoss) .. " spawned • HP " .. math.floor(hum.Health))
    pcall(equipFarmWeapon)
    hrp.CanCollide = false
    hum.WalkSpeed = 0
    local targetCFrame = hrp.CFrame * CFrame.new(0, flyHeight, 0)
    local distance = (root.Position - targetCFrame.Position).Magnitude
    if distance > 6 then
        if B.BossTween then pcall(function() B.BossTween:Cancel() end) end
        local duration = math.max(distance / math.max(speed,1), 0.01)
        B.BossTween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame=targetCFrame})
        B.BossTween:Play()
        local done = false
        local conn
        conn = B.BossTween.Completed:Connect(function() done=true; if conn then conn:Disconnect() end end)
        while B.BossFarmEnabled and scriptRunning and not done and hum.Health > 0 do
            task.wait()
        end
    end
    if not B.BossFarmEnabled or not scriptRunning or hum.Health <= 0 then return end
    root.CFrame = hrp.CFrame * CFrame.new(0, flyHeight, 0)
    local env = getSharedEnvironment()
    local fastAttack = env and env.rz_FastAttack
    local head = boss:FindFirstChild("Head") or hrp
    if fastAttack and type(fastAttack.Attack) == "function" then
        pcall(function() fastAttack:Attack(head, {{boss, head}}) end)
    elseif fastAttack and type(fastAttack.BladeHits) == "function" then
        pcall(function() fastAttack:BladeHits() end)
    end
end

task.spawn(function()
    while scriptRunning do
        pcall(function()
            local boss = B.findBossModel()
            if boss then
                local hum = boss:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    B.BantaiSetRowDescription(B.BossStatusRow, "✅ " .. tostring(B.SelectedBoss) .. " spawned • HP " .. math.floor(hum.Health))
                else
                    B.BantaiSetRowDescription(B.BossStatusRow, "❌ " .. tostring(B.SelectedBoss) .. " not spawned")
                end
            else
                B.BantaiSetRowDescription(B.BossStatusRow, "❌ " .. tostring(B.SelectedBoss) .. " not spawned")
            end
        end)
        task.wait(1)
    end
end)

task.spawn(function()
    while scriptRunning do
        if B.BossFarmEnabled then pcall(B.bossFarmStep) end
        task.wait(0.08)
    end
end)

-- Shop tab uses the buy calls documented in the supplied redz/nightub sources.
B.ShopTab = createTab("Shop", "◇", 8)
B.ShopPage = createPage("B.ShopPage")
Pages.Shop = B.ShopPage
B.ShopTab.MouseButton1Click:Connect(function() showTab("Shop") end)

function B.shopCall(name, ...)
    local commF = B.BantaiGetCommF()
    if not commF then return false end
    local args = {...}
    local ok = pcall(function()
        return commF:InvokeServer(name, table.unpack(args))
    end)
    return ok
end

function B.shopButton(title, desc, order, callback)
    return makeAction(B.ShopPage, title, desc, order, callback)
end

addSection(B.ShopPage, "Game", 1)
B.shopButton("Redeem All Codes", "Redeem available codes from the current script context.", 2, function()
    -- No code list is assumed here; only documented shop purchases are enabled.
end)
B.shopButton("Travel to Sea 1", "TravelMain", 3, function() B.shopCall("TravelMain") end)
B.shopButton("Travel to Sea 2", "TravelDressrosa", 4, function() B.shopCall("TravelDressrosa") end)
B.shopButton("Travel to Sea 3", "TravelZou", 5, function() B.shopCall("TravelZou") end)

addSection(B.ShopPage, "Fighting Style", 10)
B.melee = {
    {"Black Leg", function() B.shopCall("BuyBlackLeg") end},
    {"Electro", function() B.shopCall("BuyElectro") end},
    {"Fishman Karate", function() B.shopCall("BuyFishmanKarate") end},
    {"Dragon Claw", function() B.shopCall("BlackbeardReward","DragonClaw","1"); B.shopCall("BlackbeardReward","DragonClaw","2") end},
    {"Superhuman", function() B.shopCall("BuySuperhuman") end},
    {"Death Step", function() B.shopCall("BuyDeathStep") end},
    {"Sharkman Karate", function() B.shopCall("BuySharkmanKarate") end},
    {"Electric Claw", function() B.shopCall("BuyElectricClaw") end},
    {"Dragon Talon", function() B.shopCall("BuyDragonTalon") end},
    {"GodHuman", function() B.shopCall("BuyGodhuman") end},
    {"Sanguine Art", function() B.shopCall("BuySanguineArt") end},
}
B.order = 11
for _,item in ipairs(B.melee) do B.shopButton("Buy "..item[1], "Purchase fighting style.", B.order, item[2]); B.order+=1 end

addSection(B.ShopPage, "Haki / Ability", B.order+1); B.order+=2
B.haki = {
    {"Buy Geppo", function() B.shopCall("BuyHaki","Geppo") end},
    {"Buy Buso", function() B.shopCall("BuyHaki","Buso") end},
    {"Buy Soru", function() B.shopCall("BuyHaki","Soru") end},
    {"Buy Ken (Observation)", function() B.shopCall("KenTalk","Buy") end},
}
for _,item in ipairs(B.haki) do B.shopButton(item[1], "Purchase ability.", B.order, item[2]); B.order+=1 end

addSection(B.ShopPage, "Sword", B.order+1); B.order+=2
B.swords = {"Katana","Cutlass","Dual Katana","Iron Mace","Triple Katana","Pipe","Dual-Headed Blade","Soul Cane","Bisento"}
for _,name in ipairs(B.swords) do B.shopButton("Buy "..name, "BuyItem: "..name, B.order, function() B.shopCall("BuyItem", name == "Dual Katana" and "Duel Katana" or name) end); B.order+=1 end
B.shopButton("Buy Pole V2", "ThunderGodTalk.", B.order, function() B.shopCall("ThunderGodTalk") end); B.order+=1

addSection(B.ShopPage, "Gun", B.order+1); B.order+=2
B.guns = {"Musket","Slingshot","Flintlock","Refined Flintlock","Cannon"}
for _,name in ipairs(B.guns) do B.shopButton("Buy "..name, "BuyItem: "..name, B.order, function() B.shopCall("BuyItem",name) end); B.order+=1 end
B.shopButton("Buy Kabucha", "BlackbeardReward Slingshot.", B.order, function() B.shopCall("BlackbeardReward","Slingshot","1"); B.shopCall("BlackbeardReward","Slingshot","2") end); B.order+=1
B.shopButton("Buy Bizarre Rifle", "Ectoplasm Buy.", B.order, function() B.shopCall("Ectoplasm","Buy",1) end); B.order+=1

addSection(B.ShopPage, "Accessories", B.order+1); B.order+=2
for _,name in ipairs({"Black Cape","Swordsman Hat","Tomoe Ring"}) do B.shopButton("Buy "..name, "BuyItem: "..name, B.order, function() B.shopCall("BuyItem",name) end); B.order+=1 end

addSection(B.ShopPage, "Race / Other", B.order+1); B.order+=2
B.shopButton("Buy Ghoul Race", "Ectoplasm Change.", B.order, function() B.shopCall("Ectoplasm","Change",4) end); B.order+=1
B.shopButton("Buy Cyborg Race", "CyborgTrainer Buy.", B.order, function() B.shopCall("CyborgTrainer","Buy") end); B.order+=1
B.shopButton("Buy Refund Stats", "BlackbeardReward Refund.", B.order, function() B.shopCall("BlackbeardReward","Refund","1"); B.shopCall("BlackbeardReward","Refund","2") end); B.order+=1
B.shopButton("Buy Reroll Race", "BlackbeardReward Reroll.", B.order, function() B.shopCall("BlackbeardReward","Reroll","1"); B.shopCall("BlackbeardReward","Reroll","2") end)

-- Keep the centered image visible behind the translucent panels and put every
-- normal control above both image layers.
for _,obj in ipairs(MainFrame:GetDescendants()) do
    if obj:IsA("GuiObject") and obj ~= GuiImage and obj ~= CenterImage then
        obj.ZIndex = math.max(obj.ZIndex, 4)
    end
end
GuiImage.ZIndex = 1
CenterImage.ZIndex = 2

-- Keep the original default tab exactly as Bantai v3 intended.
showTab("Farm")
