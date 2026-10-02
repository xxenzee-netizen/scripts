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

-- Shared movement cancellation + tween noclip.
local FeatureTweens = {}
local FeatureTweenTokens = {}
local TweenNoclip = false
local TweenNoclipStates = {}

local function beginFeatureTween(name)
    FeatureTweenTokens[name] = (FeatureTweenTokens[name] or 0) + 1
    local token = FeatureTweenTokens[name]
    local old = FeatureTweens[name]
    if old then pcall(function() old:Cancel() end) end
    FeatureTweens[name] = nil
    return token
end

local function cancelFeatureTween(name)
    FeatureTweenTokens[name] = (FeatureTweenTokens[name] or 0) + 1
    local tw = FeatureTweens[name]
    if tw then pcall(function() tw:Cancel() end) end
    FeatureTweens[name] = nil
end

local function isFeatureTweenCurrent(name, token)
    return scriptRunning and FeatureTweenTokens[name] == token
end

local function setTweenNoclip(enabled)
    if enabled == TweenNoclip then return end
    TweenNoclip = enabled
    if enabled then
        TweenNoclipStates = {}
        local char = Player.Character
        if char then
            for _, obj in ipairs(char:GetDescendants()) do
                if obj:IsA("BasePart") then
                    TweenNoclipStates[obj] = obj.CanCollide
                    obj.CanCollide = false
                end
            end
        end
    else
        for part, state in pairs(TweenNoclipStates) do
            if part and part.Parent then pcall(function() part.CanCollide = state end) end
        end
        TweenNoclipStates = {}
    end
end


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
RunService.Heartbeat:Connect(function()
    if not TweenNoclip then return end
    local char = Player.Character
    if not char then return end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then obj.CanCollide = false end
    end
end)
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
ScreenGui.Enabled = false -- shown once the whole UI is built (no half-built black flash)

-- PlayerGui is the reliable LocalScript parent. gethui is used when the
-- runtime provides it, without requiring an external UI library.
task.delay(15, function() if ScreenGui and ScreenGui.Parent then ScreenGui.Enabled = true end end)
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
    Sidebar = Color3.fromRGB(3, 3, 3),
    Row = Color3.fromRGB(10, 10, 10),
    RowHover = Color3.fromRGB(18, 18, 18),
    Content = Color3.fromRGB(5, 5, 5),
    Border = Color3.fromRGB(35, 35, 35),
    Text = Color3.fromRGB(245, 245, 245),
    Muted = Color3.fromRGB(145, 145, 145),
    Accent = Color3.fromRGB(235, 235, 235),
    AccentDark = Color3.fromRGB(90, 90, 90),
    Off = Color3.fromRGB(35, 35, 35),
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
    s.Transparency = transparency or 0.4
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
    frame.BackgroundColor3 = Color3.fromRGB(8,8,8)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = sg
    corner(frame, 14)

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
    verify.Name = "VerifyKeyButton"
    verify.Size = UDim2.new(1,-40,0,38)
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

    local status = label(frame, "Checking key source...", UDim2.new(1,-40,0,24), UDim2.new(0,20,0,190), 9, COLORS.Muted, Enum.Font.GothamMedium)

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
MainFrame.BackgroundTransparency = 0
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui
corner(MainFrame, 10)
stroke(MainFrame, COLORS.Border, 1)

-- Centered 3840x2160 artwork. In executor environments that support local
-- assets, download the supplied image once and use it as the hub backdrop.
local BANTAI_BG_URL = "https://cdn.myimgs.org/images/50864/1000045832.jpg"
local BANTAI_BG_FILE = "BantaiHub/background_v2.jpg"
local BackgroundImage = Instance.new("ImageLabel")
BackgroundImage.Name = "HubBackground"
BackgroundImage.Size = UDim2.fromScale(1,1)
BackgroundImage.Position = UDim2.fromScale(0.5,0.5)
BackgroundImage.AnchorPoint = Vector2.new(0.5,0.5)
BackgroundImage.BackgroundTransparency = 1
BackgroundImage.ImageTransparency = 0
BackgroundImage.ScaleType = Enum.ScaleType.Crop -- 3840x2160 (16:9) art fills the 760x470 window without distortion
BackgroundImage.ZIndex = 0
BackgroundImage.Parent = MainFrame
corner(BackgroundImage, 10)

do
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
end

-- Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 55)
Header.BackgroundColor3 = Color3.fromRGB(14, 7, 22)
Header.BackgroundTransparency = 0.45
Header.BorderSizePixel = 0
Header.Parent = MainFrame
corner(Header, 10)

do
local HeaderMask = Instance.new("Frame")
HeaderMask.Size = UDim2.new(1, 0, 0, 12)
HeaderMask.Position = UDim2.new(0, 0, 1, -12)
HeaderMask.BackgroundColor3 = Color3.fromRGB(14, 7, 22)
HeaderMask.BackgroundTransparency = 1
HeaderMask.BorderSizePixel = 0
HeaderMask.Parent = Header
end

label(Header, "bantai hub", UDim2.new(0, 105, 0, 30),
    UDim2.new(0, 18, 0, 8), 16, COLORS.Text, Enum.Font.GothamBold)

label(Header, "by NotThatAnik", UDim2.new(0, 120, 0, 22),
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

-- Robust drag handling (mouse + touch), kept on screen.
do
    Header.Active = true
    local dragging, dragStart, startPos = false, nil, nil

    local function isPointer(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
    end

    Header.InputBegan:Connect(function(input)
        if isPointer(input) then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = input.Position - dragStart
        local view = ScreenGui.AbsoluteSize
        local nx = math.clamp(startPos.X.Offset + delta.X, -startPos.X.Scale * view.X, (1 - startPos.X.Scale) * view.X)
        local ny = math.clamp(startPos.Y.Offset + delta.Y, -startPos.Y.Scale * view.Y, (1 - startPos.Y.Scale) * view.Y)
        MainFrame.Position = UDim2.new(startPos.X.Scale, nx, startPos.Y.Scale, ny)
    end)

    UserInputService.InputEnded:Connect(function(input)
        if isPointer(input) then dragging = false end
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
Sidebar.BackgroundTransparency = 0.55
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
    button.BackgroundColor3 = COLORS.Sidebar
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

    label(button, icon, UDim2.new(0, 31, 1, 0),
        UDim2.new(0, 8, 0, 0), 18, COLORS.Muted, Enum.Font.GothamBold)

    label(button, name, UDim2.new(1, -45, 1, 0),
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
local TravelTab = createTab("Travel", "✈", 9)
local SeaEventsTab = createTab("Sea Events", "🌊", 10)

-- Right side
local PageHolder = Instance.new("Frame")
PageHolder.Size = UDim2.new(1, -200, 1, 0)
PageHolder.Position = UDim2.new(0, 200, 0, 0)
PageHolder.BackgroundColor3 = COLORS.Content
PageHolder.BackgroundTransparency = 0.55
PageHolder.BorderSizePixel = 0
PageHolder.Parent = Body
corner(PageHolder, 8)
stroke(PageHolder, COLORS.Border, 1)

PageHolder.BackgroundTransparency = 0.55

PageHolder.ZIndex = 1
PageHolder.ZIndex = 1

local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.Size = UDim2.new(1, -8, 1, -8)
    page.Position = UDim2.new(0, 4, 0, 4)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ZIndex = 5
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
local TravelPage = createPage("TravelPage")
local SeaEventsPage = createPage("SeaEventsPage")

Pages.Status = StatusPage
Pages.Farm = FarmingPage
Pages["Farm Settings"] = FarmSettingsPage
Pages.Raids = RaidsPage
Pages.Fruits = FruitsPage
Pages["Local Player"] = LocalPlayerPage
Pages["Chest Farm"] = ChestFarmPage
Pages.Hop = HopPage
Pages.Travel = TravelPage
Pages["Sea Events"] = SeaEventsPage

local Container = FarmingPage

local function showTab(name)
    for pageName, page in pairs(Pages) do
        page.Visible = (pageName == name)
    end

    for tabName, tab in pairs(Tabs) do
        local activeTab = (tabName == name)
        tab.BackgroundColor3 = activeTab and COLORS.RowHover or COLORS.Sidebar
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
TravelTab.MouseButton1Click:Connect(function() showTab("Travel") end)
SeaEventsTab.MouseButton1Click:Connect(function() showTab("Sea Events") end)

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
    row.BackgroundTransparency = 0.18
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = page
    corner(row, 6)

    row.MouseEnter:Connect(function()
        row.BackgroundColor3 = COLORS.Row
    row.BackgroundTransparency = 0.08
    end)
    row.MouseLeave:Connect(function()
        row.BackgroundColor3 = COLORS.Row
    row.BackgroundTransparency = 0.18
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
        track.BackgroundTransparency = 0.12
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
    row.BackgroundTransparency = 0.18
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
local HopStatus

local function moonTargetFound(mode)
    local lighting = game:GetService("Lighting")
    local sky = lighting:FindFirstChildOfClass("Sky")
    local texture = sky and tostring(sky.MoonTextureId or "") or ""
    local id = texture:match("%d+") or ""

    if mode == "FullMoon" then
        return id == "9709149431" or id == "79932823311771"
    elseif mode == "NearMoon" then
        return id == "9709149052"
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
    nonce = nonce or {}
    local n12 = {}
    for i = 1, 12 do n12[i] = nonce[i] or 0 end
    local state = {BH_CONST[1], BH_CONST[2], BH_CONST[3], BH_CONST[4]}
    for i = 0, 7 do state[5 + i] = BH_u32LE(key, 1 + 4 * i) end
    state[13] = counter % 4294967296
    for i = 0, 2 do state[14 + i] = BH_u32LE(n12, 1 + 4 * i) end
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
    nonce = nonce or {}
    local n12 = {}
    for i = 1, 12 do n12[i] = nonce[i] or 0 end
    local state = {BH_CONST[1], BH_CONST[2], BH_CONST[3], BH_CONST[4]}
    for i = 0, 7 do state[5 + i] = BH_u32LE(key, 1 + 4 * i) end
    state[13] = 4294967295
    for i = 0, 2 do state[14 + i] = BH_u32LE(n12, 1 + 4 * i) end
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
    local environments = {}
    pcall(function() if type(getgenv) == "function" then environments[#environments + 1] = getgenv() end end)
    pcall(function() if type(getrenv) == "function" then environments[#environments + 1] = getrenv() end end)
    environments[#environments + 1] = _G

    local requesters = {}
    for _, env in ipairs(environments) do
        if type(env) == "table" then
            if type(env.request) == "function" then requesters[#requesters + 1] = env.request end
            if type(env.http_request) == "function" then requesters[#requesters + 1] = env.http_request end
        end
    end
    if type(syn) == "table" and type(syn.request) == "function" then
        requesters[#requesters + 1] = syn.request
    end

    for _, requester in ipairs(requesters) do
        local ok, result = pcall(requester, {Url = url, Method = "GET"})
        if ok and result then
            local body = result.Body or result.body
            if type(body) == "string" and #body > 0 then return true, body end
        end
    end

    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 0 then return true, body end
    return false, nil
end

-- Load the requested background after the HTTP helper exists.
do
    local function isImageBytes(body)
        if type(body) ~= "string" or #body < 32 then return false end
        local b1, b2, b3, b4 = body:byte(1, 4)
        return (b1 == 0xFF and b2 == 0xD8 and b3 == 0xFF) -- JPEG
            or (b1 == 0x89 and b2 == 0x50 and b3 == 0x4E and b4 == 0x47) -- PNG
    end
    local function applyAsset(asset)
        if asset and BackgroundImage and BackgroundImage.Parent then
            BackgroundImage.Image = asset
            return true
        end
        return false
    end
    task.spawn(function()
        if type(getcustomasset) ~= "function" or type(writefile) ~= "function" then return end
        if type(isfile) == "function" and isfile(BANTAI_BG_FILE) then
            local ok, asset = pcall(getcustomasset, BANTAI_BG_FILE)
            if ok and applyAsset(asset) then return end
        end
        for _ = 1, 3 do
            local ok, body = BH_request(BANTAI_BG_URL)
            if ok and isImageBytes(body) then
                pcall(function()
                    if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("BantaiHub") then
                        makefolder("BantaiHub")
                    end
                    writefile(BANTAI_BG_FILE, body)
                end)
                local ok2, asset = pcall(getcustomasset, BANTAI_BG_FILE)
                if ok2 and applyAsset(asset) then return end
            end
            task.wait(1.5)
        end
    end)
end

local function BH_isGuid(s)
    return type(s) == "string" and s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

-- Returns an ordered list of real job ids (youngest server first). Encoded ids
-- that can't be decoded are skipped instead of being sent to the teleport.
local function collectHopTargets(apiMode)
    local jobs, seen = {}, {}
    local function add(job)
        if type(job) ~= "string" then return end
        job = job:gsub("^%s+", ""):gsub("%s+$", "")
        if job:sub(1,9) == "NIGHTHUB|" then
            local ok, decoded = pcall(function() return BH_decodeJobId(job) end)
            if ok and type(decoded) == "string" then job = decoded end
        end
        if BH_isGuid(job) and job ~= game.JobId and not seen[job] then
            seen[job] = true
            jobs[#jobs + 1] = job
        end
    end
    local function scan(v)
        if type(v) == "string" then
            add(v)
        elseif type(v) == "table" then
            for _, x in pairs(v) do scan(x) end
        end
    end

    -- Teddy's API is used only for its two supported moon modes.
    if apiMode == "Fullmoon" or apiMode == "NearMoon" then
        local teddyMode = apiMode == "Fullmoon" and "fullmoon" or "nearmoon"
        local ok, body = BH_request("http://162.4.177.49:8080/jobid/" .. teddyMode .. "/")
        if ok and type(body) == "string" then
            local decoded
            pcall(function() decoded = HttpService:JSONDecode(body) end)
            if decoded ~= nil then scan(decoded) else for token in body:gmatch("[%w%-_]+") do add(token) end end
            if #jobs > 0 then return jobs end
        end
    end

    -- Night Hub supports the boss/island modes as well as moon modes.
    local ok, body = BH_request("http://163.223.9.144/boss/" .. tostring(apiMode):gsub(" ", "%%20"))
    if ok then
        local decoded
        pcall(function() decoded = HttpService:JSONDecode(body) end)
        if type(decoded) == "table" and type(decoded.data) == "table" then
            local entries = {}
            for _, server in pairs(decoded.data) do
                if type(server) == "table" and server.JobId
                    and tonumber(server.PlaceId) == tonumber(game.PlaceId)
                    and (tonumber(server.Players or server.Playing or server.playing or 0) or 0) < 12 then
                    local job
                    pcall(function() job = BH_decodeJobId(tostring(server.JobId)) end)
                    if BH_isGuid(job) and job ~= game.JobId then
                        entries[#entries + 1] = {Job = job, Age = tonumber(server.Age) or math.huge}
                    end
                end
            end
            table.sort(entries, function(a,b) return a.Age < b.Age end)
            for _, entry in ipairs(entries) do add(entry.Job) end
        end
    end
    return jobs, #jobs == 0 and ("No " .. tostring(apiMode) .. " server found") or nil
end

local HopModeFile = "BantaiHub/hop_mode.txt"
local HopMode = ""
local HopRunToken = 0

local function saveHopMode(mode)
    HopMode = mode or ""
    pcall(function()
        if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("BantaiHub") then makefolder("BantaiHub") end
        if type(writefile) == "function" then writefile(HopModeFile, HopMode) end
    end)
end

pcall(function()
    if type(isfile) == "function" and isfile(HopModeFile) then HopMode = (tostring(readfile(HopModeFile)):gsub("%s+", "")) end
end)
if HopMode ~= "FullMoon" and HopMode ~= "NearMoon" then HopMode = "" end

local function fallbackJob()
    local pool, seen = {}, {}
    local sb = ReplicatedStorage:FindFirstChild("__ServerBrowser")

    if sb then
        for page = 1, 100 do
            local ok, res = pcall(function()
                return sb:InvokeServer(page)
            end)
            if ok and type(res) == "table" then
                for id, info in pairs(res) do
                    local count = type(info) == "table" and tonumber(info.Count) or 0
                    if type(id) == "string" and id ~= game.JobId and count > 0 and count < 12 and not seen[id] then
                        seen[id] = true
                        pool[#pool + 1] = id
                    end
                end
            end
            if #pool >= 30 then break end
            task.wait()
        end
    end

    if #pool == 0 then
        local ok, body = BH_request(
            "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) ..
            "/servers/Public?sortOrder=Asc&limit=100"
        )
        if ok then
            local decoded
            pcall(function() decoded = HttpService:JSONDecode(body) end)
            if type(decoded) == "table" and type(decoded.data) == "table" then
                for _, srv in ipairs(decoded.data) do
                    local id = srv.id
                    local playing = tonumber(srv.playing) or 0
                    local maxPlayers = tonumber(srv.maxPlayers) or 0
                    if id and id ~= game.JobId and maxPlayers > 0 and playing < maxPlayers and not seen[id] then
                        seen[id] = true
                        pool[#pool + 1] = id
                    end
                end
            end
        end
    end

    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

local function joinServer(job)
    job = tostring(job or "")
    if job == "" or job == game.JobId then
        return false, "invalid or current server"
    end

    -- The game's own server browser is the most reliable path used by the
    -- reference script. Fall back to TeleportToPlaceInstance if needed.
    local sb = ReplicatedStorage:FindFirstChild("__ServerBrowser")
    if sb then
        local ok, result = pcall(function()
            return sb:InvokeServer("teleport", job)
        end)
        if ok and result ~= false then
            return true
        end
    end

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, job, Player)
    end)
    if ok then
        pcall(function()
            if type(queue_on_teleport) == "function" and type(isfile) == "function"
                and isfile("BantaiHub/loader.lua") then
                queue_on_teleport('loadstring(readfile("BantaiHub/loader.lua"))()')
            end
        end)
        return true
    end
    return false, tostring(err or "teleport failed")
end

local HopVisited = {}

-- One click = one server hop. There is intentionally no retry loop and no
-- saved-hop continuation after teleport.
local function startHop(mode)
    local labels = {
        FullMoon = "Full Moon", Fullmoon = "Full Moon", NearMoon = "Near Moon",
        Darkbeard = "Darkbeard", DoughKing = "Dough King", ["Dough King"] = "Dough King"
    }
    local niceName = labels[mode] or tostring(mode)
    local token = HopRunToken + 1
    HopRunToken = token
    HopBusy = true
    saveHopMode("")
    task.spawn(function()
        HopStatus.Text = "Finding " .. niceName .. " server..."
        local jobs = collectHopTargets(mode)
        if #jobs == 0 then
            local fb = fallbackJob()
            if fb then jobs = {fb} end
        end
        local job = jobs[1]
        if token ~= HopRunToken then HopBusy = false; return end
        if not job then
            HopStatus.Text = "No " .. niceName .. " server found"
            HopBusy = false
            return
        end
        HopStatus.Text = "Joining " .. niceName .. " server..."
        local joined, lastErr
        for i, candidate in ipairs(jobs) do
            if token ~= HopRunToken then HopBusy = false; return end
            joined, lastErr = joinServer(candidate)
            if joined then break end
            HopStatus.Text = "Retrying hop (" .. tostring(i) .. "/" .. tostring(math.min(#jobs, 8)) .. ")..."
            task.wait(0.15)
            if i >= 8 then break end
        end
        if not joined then HopStatus.Text = "Join error: " .. tostring(lastErr or "no server accepted the hop") end
        HopBusy = false
    end)
end

addSection(HopPage, "Server Hop", 1)
HopStatus = label(HopPage, "One-click hop: idle", UDim2.new(1,0,0,34), UDim2.new(0,2,0,0), 10, COLORS.Muted, Enum.Font.GothamMedium)
HopStatus.LayoutOrder = 2
HopStatus.TextWrapped = true
HopStatus.TextTruncate = Enum.TextTruncate.None
local FullMoonHopRow = makeAction(HopPage, "🌕 Hop to Full Moon", "Jumps to a server that has a Full Moon.", 3, function()
    if moonTargetFound("FullMoon") then HopStatus.Text = "Full Moon is already here"; return end
    startHop("Fullmoon")
end)
local NearMoonHopRow = makeAction(HopPage, "🌖 Hop to Near Moon", "Jumps to a server where the Full Moon is almost here.", 4, function()
    if moonTargetFound("NearMoon") then HopStatus.Text = "Near Moon is already here"; return end
    startHop("NearMoon")
end)
local DarkbeardHopRow = makeAction(HopPage, "☠️ Hop to Darkbeard", "Jumps to a server where Darkbeard is up.", 5, function()
    startHop("Darkbeard")
end)
local DoughKingHopRow = makeAction(HopPage, "👑 Hop to Dough King", "Jumps to a server where Dough King can be fought.", 6, function()
    startHop("Dough King")
end)
local StopHopRow = makeAction(HopPage, "🛑 Stop Hopping", "Cancels the server hop that is running.", 7, function()
    HopRunToken += 1
    HopBusy = false
    saveHopMode("")
    HopStatus.Text = "One-click hop: stopped"
end)
end -- end of Server Hop block

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

do
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
end

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
    "⚔️ Auto Farm",
    "Fights the NPCs you picked and levels you up for you.",
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
    FarmSettingsPage, "⚡ Tween Speed",
    "Sets how fast you fly to targets.",
    2, speed,
    function(box, value)
        local num = tonumber(tostring(value):match("%d+"))
        if num and num > 0 then
            speed = num
            local labels = ChestSpeedRow and ChestSpeedRow:GetChildren() or {}
            for _, child in ipairs(labels) do
                if child:IsA("TextLabel") and child ~= labels[1] then
                    child.Text = "Speed used to reach chests (change it in Farm Settings): " .. tostring(speed)
                end
            end
        end
        box.Text = tostring(speed)
    end
)

local HeightRow, HeightBox = makeInput(
    FarmSettingsPage, "🪽 Fly Height",
    "Sets how far above enemies you hover.",
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
    "🌀 Auto Raid",
    "Clears every raid wave and moves on to the next island.",
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

makeDescriptionRow(
    FruitsPage,
    "🍎 Fruit Notifier",
    "Alerts you when a fruit spawns in the server.",
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

makeAction(
    FruitsPage,
    "📍 Teleport to Fruit",
    "Takes you straight to the fruit that spawned.",
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
    cancelFeatureTween("Fruit")
    if TweenFruitMove then pcall(function() TweenFruitMove:Cancel() end); TweenFruitMove = nil end
    setTweenNoclip(false)
end

local function tweenToFruit(fruit, handle)
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not handle then return false end
    TweenFruitMoveToken += 1
    local token = TweenFruitMoveToken
    cancelFeatureTween("Fruit")
    local target = CFrame.new(handle.Position + Vector3.new(0,4,0))
    local distance = (root.Position - target.Position).Magnitude
    if distance <= 5 then return true end
    setTweenNoclip(true)
    local duration = math.max(distance / math.max(speed,1), 0.01)
    local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame=target})
    TweenFruitMove = tween
    FeatureTweens["Fruit"] = tween
    tween:Play()
    while TweenFruitEnabled and scriptRunning and token == TweenFruitMoveToken
        and tween.PlaybackState == Enum.PlaybackState.Playing do
        task.wait()
    end
    local ok = TweenFruitEnabled and scriptRunning and token == TweenFruitMoveToken
    pcall(function() tween:Cancel() end)
    if FeatureTweens["Fruit"] == tween then FeatureTweens["Fruit"] = nil end
    if TweenFruitMove == tween then TweenFruitMove = nil end
    setTweenNoclip(false)
    return ok
end

local FruitTweenRow = makeToggle(FruitsPage, "🍇 Fly to Fruits", "Flies you to every fruit that spawns.", 5, false, function(enabled)
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
    "💰 Auto Chest Farm",
    "Collects one chest after another.",
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
    "🚀 Movement: Tween",
    "Switches between flying to chests and teleporting to them.",
    4,
    function()
        ChestFarmMode = ChestFarmMode == "Tween" and "Teleport" or "Tween"
        local title = ChestModeRow and ChestModeRow:FindFirstChildWhichIsA("TextLabel")
        if title then title.Text = "🚀 Movement: " .. ChestFarmMode end
        if ChestFarmMode == "Teleport" and ChestFarmTween then
            pcall(function() ChestFarmTween:Cancel() end)
            ChestFarmTween = nil
        end
    end
)

local ChestSpeedRow = makeDescriptionRow(
    ChestFarmPage, "⚡ Chest Speed",
    "Speed used to reach chests (change it in Farm Settings): " .. tostring(speed),
    5, function() end
)

makeDescriptionRow(
    ChestFarmPage,
    "🧰 Chest Targets",
    "Only goes for chests that can still be opened.",
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
    "🔥 Auto V4",
    "Turns on Awakening (V4) as soon as your energy is full.",
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
    "💨 Auto V3",
    "Keeps your Race V3 ability turned on.",
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
    "🌊 Walk on Water",
    "Lets you walk across the sea instead of sinking.",
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

-- Full Bright (visual-only)
local function BantaiMainPart2()
local FullBrightEnabled = false
local FullBrightSaved = nil
local function setFullBright(enabled)
    FullBrightEnabled = enabled
    local Lighting = game:GetService("Lighting")
    if enabled then
        if not FullBrightSaved then
            FullBrightSaved = {
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                FogEnd = Lighting.FogEnd,
                GlobalShadows = Lighting.GlobalShadows,
            }
        end
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
    elseif FullBrightSaved then
        Lighting.Brightness = FullBrightSaved.Brightness
        Lighting.ClockTime = FullBrightSaved.ClockTime
        Lighting.FogEnd = FullBrightSaved.FogEnd
        Lighting.GlobalShadows = FullBrightSaved.GlobalShadows
        FullBrightSaved = nil
    end
end
makeToggle(LocalPlayerPage, "💡 Full Bright", "Makes the whole map bright so you can see everywhere.", 5, false, function(enabled)
    setFullBright(enabled)
end)

task.spawn(function()
    while scriptRunning do
        if FullBrightEnabled then pcall(setFullBright, true) end
        task.wait(1)
    end
end)

-- Auto Enable Haki (Night Hub method: invoke "Buso" only when HasBuso is missing)
do
    local AutoHakiEnabled = false
    makeToggle(LocalPlayerPage, "🛡️ Auto Haki", "Keeps your Buso Haki switched on.", 7, false, function(enabled)
        AutoHakiEnabled = enabled
    end)
    task.spawn(function()
        while scriptRunning do
            if AutoHakiEnabled then
                pcall(function()
                    local char = Player.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if char and hum and hum.Health > 0 and not char:FindFirstChild("HasBuso") then
                        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                        local commF = remotes and remotes:FindFirstChild("CommF_")
                        if commF then commF:InvokeServer("Buso") end
                    end
                end)
            end
            task.wait(1)
        end
    end)
end

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
RestoreCircle.Active = true
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

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
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
            if labels[2] then labels[2].Text = "Speed used to reach chests (change it in Farm Settings): " .. tostring(speed) end
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

do
local NotifierToggleLock = false
local function guardedNotifierToggle()
    if NotifierToggleLock then return end
    NotifierToggleLock = true
    toggleNotifier()
    task.delay(0.12, function() NotifierToggleLock = false end)
end
NotifierBtn.Activated:Connect(guardedNotifierToggle)
NotifierToggle.Activated:Connect(guardedNotifierToggle)
end

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
    local token = beginFeatureTween("Farm")
    local distance = (hrp.Position - targetCFrame.Position).Magnitude
    if distance <= 5 then
        cancelFeatureTween("Farm")
        return true
    end
    setTweenNoclip(true)
    local duration = math.max(distance / math.max(speed, 1), 0.01)
    local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
    FeatureTweens["Farm"] = tween
    activeTween = tween
    tween:Play()
    while isFeatureTweenCurrent("Farm", token) and active and tween.PlaybackState == Enum.PlaybackState.Playing do
        task.wait()
    end
    local ok = isFeatureTweenCurrent("Farm", token) and active
    pcall(function() tween:Cancel() end)
    if FeatureTweens["Farm"] == tween then FeatureTweens["Farm"] = nil end
    if activeTween == tween then activeTween = nil end
    setTweenNoclip(false)
    return ok
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

do
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
end

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
    cancelFeatureTween("Chest")
    ChestFarmMoving = false
    if ChestFarmTween then
        pcall(function() ChestFarmTween:Cancel() end)
        ChestFarmTween = nil
    end
    setTweenNoclip(false)
end

local function moveToChest(cframe)
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not ChestFarmEnabled then return false end

    stopChestMovement()
    local token = ChestFarmToken
    beginFeatureTween("Chest")
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
    setTweenNoclip(true)
    ChestFarmTween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = cframe})
    FeatureTweens["Chest"] = ChestFarmTween
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
    FeatureTweens["Chest"] = nil
    setTweenNoclip(false)
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

do
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
end
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
    cancelFeatureTween("Raid")
    if AutoRaidTween then
        pcall(function() AutoRaidTween:Cancel() end)
        AutoRaidTween = nil
    end
    setTweenNoclip(false)
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
    beginFeatureTween("Raid")

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
    setTweenNoclip(true)

    local duration = math.max(distance / math.max(speed, 1), 0.01)
    AutoRaidTween = TweenService:Create(
        root,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        {CFrame = targetCFrame}
    )
    FeatureTweens["Raid"] = AutoRaidTween

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
            setTweenNoclip(false)
            FeatureTweens["Raid"] = nil
            return false
        end

        char = Player.Character
        root = char and char:FindFirstChild("HumanoidRootPart")
        hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then
            pcall(function() AutoRaidTween:Cancel() end)
            setTweenNoclip(false)
            FeatureTweens["Raid"] = nil
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

do
local RaidToggleLock = false
local function guardedRaidToggle()
    if RaidToggleLock then return end
    RaidToggleLock = true
    toggleAutoRaid()
    task.delay(0.12, function() RaidToggleLock = false end)
end
RaidToggle.Activated:Connect(guardedRaidToggle)
RaidRow.Activated:Connect(guardedRaidToggle)
end

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
        cancelFeatureTween("Farm")
        if activeTween then
            pcall(function() activeTween:Cancel() end)
            activeTween = nil
        end
        setTweenNoclip(false)
        removeSuspension()
    end
end

do
local FarmToggleLock = false
local function guardedFarmToggle()
    if FarmToggleLock then return end
    FarmToggleLock = true
    toggleScript()
    task.delay(0.12, function() FarmToggleLock = false end)
end
FarmToggle.Activated:Connect(guardedFarmToggle)
FarmRow.Activated:Connect(guardedFarmToggle)
end

YesBtn.MouseButton1Click:Connect(function()
    scriptRunning = false
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
            -- Keep the user's water-walk preference through death. The water
            -- plane can reset during respawn, so reapply it after the new
            -- character and map objects finish loading.
            if WalkWaterEnabled then
                task.defer(function()
                    for i = 1, 8 do
                        if not scriptRunning or not WalkWaterEnabled then break end
                        pcall(setWaterWalk, true)
                        task.wait(0.25)
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
        task.spawn(function()
            for i = 1, 12 do
                if not scriptRunning or not WalkWaterEnabled then break end
                pcall(setWaterWalk, true)
                task.wait(0.2)
            end
        end)
    end
end)

if Player.Character then
    setupDeathListener(Player.Character)
end

-- Auto Store Fruit, matching Night Hub's CheckFruits/StoreBF behavior.
local AutoStoreFruitEnabled = false
local function findInventoryFruit()
    local backpack = Player:FindFirstChild("Backpack")
    local character = Player.Character
    local containers = {backpack, character}
    for _, container in ipairs(containers) do
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") and string.find(child.Name, "Fruit") and not child:GetAttribute("WeaponType") then
                    if child:GetAttribute("OriginalName") then return child end
                end
            end
        end
    end
    return nil
end

makeToggle(FruitsPage, "📦 Auto Store Fruit", "Stores fruits from your inventory so you never lose them.", 6, false, function(enabled)
    AutoStoreFruitEnabled = enabled
end)

task.spawn(function()
    while scriptRunning do
        if AutoStoreFruitEnabled then
            local fruit = findInventoryFruit()
            local commF = B and B.BantaiGetCommF and B.BantaiGetCommF() or nil
            if fruit and commF then
                pcall(function()
                    commF:InvokeServer("StoreFruit", fruit:GetAttribute("OriginalName"), fruit)
                end)
                task.wait(0.15)
            else
                task.wait(0.5)
            end
        else
            task.wait(0.5)
        end
    end
end)

-----------------------------------
-- BANTAI HUB ADD-ON FEATURES
-- Added after the complete original script so the original GUI/startup order
-- is left untouched. Every feature is isolated behind pcall where game APIs
-- can vary between versions.
-----------------------------------

B = {} -- shared Bantai state
B.BoatTweenSpeed = 250
B.BoatFlyHeight = 30
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
    "🧲 Bring Mobs",
    "Pulls nearby enemies into one spot so you hit them all at once.",
    7,
    false,
    function(enabled)
        B.BantaiBringMobsEnabled = enabled
    end
)

B.BantaiBringRangeRow, B.BantaiBringRangeBox = makeInput(
    FarmSettingsPage,
    "📏 Bring Range",
    "Sets how far away an enemy can be and still get pulled in.",
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
    "🎟️ Select Raid: " .. B.BantaiSelectedRaid,
    "Pick which raid you want to run.",
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
                if titleLabel then titleLabel.Text = "🎟️ Select Raid: " .. raidName end
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
    "🎫 Auto Buy Chip",
    "Buys the selected raid chip when you do not have one.",
    5,
    false,
    function(enabled)
        B.BantaiAutoBuyChip = enabled
    end
)

B.BantaiStartRaidRow = makeToggle(
    RaidsPage,
    "▶️ Auto Start Raid",
    "Starts the raid for you as soon as you have a chip.",
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
    "🌙 Moon Phase",
    "Checking...",
    2,
    function() end
)
B.BantaiLeviathanRow = makeDescriptionRow(
    StatusPage,
    "🐋 Leviathan",
    "Checking...",
    3,
    function() end
)
B.BantaiFruitStockRow = makeDescriptionRow(
    StatusPage,
    "🛒 Fruit Stock",
    "Checking...",
    4,
    function() end
)
B.BantaiMirageFruitStockRow = makeDescriptionRow(
    StatusPage,
    "🔮 Mirage Fruit Stock",
    "Checking...",
    5,
    function() end
)
B.BantaiServerAgeRow = makeDescriptionRow(
    StatusPage,
    "⏱️ Server Age",
    "Checking...",
    6,
    function() end
)

-- Fruit stock rows grow only as much as their text needs.
local function BantaiFitStockRow(row, value)
    if not row then return end
    local labels = {}
    for _, child in ipairs(row:GetChildren()) do
        if child:IsA("TextLabel") then labels[#labels + 1] = child end
    end
    local desc = labels[2]
    if not desc then return end

    local text = tostring(value or "")
    local count = 0
    for _ in text:gmatch("\n") do count += 1 end
    count += 1

    desc.TextWrapped = true
    desc.TextTruncate = Enum.TextTruncate.None
    desc.TextYAlignment = Enum.TextYAlignment.Top
    desc.Size = UDim2.new(1, -26, 0, math.max(22, count * 15))
    desc.Position = UDim2.new(0, 13, 0, 29)

    local needed = math.max(62, 40 + desc.AbsoluteSize.Y)
    row.Size = UDim2.new(1, 0, 0, needed)
end

B.BantaiFitStockRow = BantaiFitStockRow

function B.BantaiSetRowDescription(row, value)
    local labels = {}
    for _, child in ipairs(row:GetChildren()) do
        if child:IsA("TextLabel") then
            labels[#labels + 1] = child
        end
    end
    if labels[2] then
        labels[2].Text = tostring(value)
        if row == B.BantaiFruitStockRow or row == B.BantaiMirageFruitStockRow then
            BantaiFitStockRow(row, value)
        end
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

function B.BantaiFruitStockStatusAdvanced()
    local commF = B.BantaiGetCommF()
    if not commF then return "Remote unavailable" end
    local ok, response = pcall(function() return commF:InvokeServer("GetFruits", true) end)
    if not ok or type(response) ~= "table" then return "Unavailable" end
    local lines = {}
    local rarityNames = {[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Legendary",[5]="Mythical"}
    local function formatPrice(value)
        local text = tostring(math.floor(tonumber(value) or 0))
        repeat local replaced,count=text:gsub("^(-?%d+)(%d%d%d)","%1,%2"); text=replaced; if count==0 then break end until false
        return text
    end
    for _, fruit in pairs(response) do
        if type(fruit)=="table" and fruit.OnSale then
            lines[#lines+1] = string.format("__R%d__🍎 %s [%s] — %s$", tonumber(fruit.Rarity) or 0, tostring(fruit.Name or "Unknown Fruit"), rarityNames[tonumber(fruit.Rarity)] or tostring(fruit.Rarity or "Unknown"), formatPrice(fruit.Price))
        end
    end
    table.sort(lines,function(a,b)
        local ra=tonumber(a:match("__R(%d+)__")) or 0; local rb=tonumber(b:match("__R(%d+)__")) or 0
        if ra~=rb then return ra>rb end return a:lower()<b:lower()
    end)
    for i=1,#lines do lines[i]=lines[i]:gsub("__R%d+__","") end
    return #lines>0 and table.concat(lines,"\n") or "No fruits on sale"
end

function B.BantaiServerAgeStatus()
    -- DistributedGameTime is the Roblox server's elapsed uptime. It is not
    -- based on when this script loaded or when the player joined.
    local raw = tonumber(Workspace.DistributedGameTime)
    if not raw or raw < 0 then return "Server uptime unavailable" end

    local seconds = math.floor(raw)
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local sec = seconds % 60

    if days > 0 then
        return string.format("Server uptime: %dd %02dh %02dm %02ds", days, hours, minutes, sec)
    end
    return string.format("Server uptime: %02dh %02dm %02ds", hours, minutes, sec)
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
        pcall(function()
            B.BantaiSetRowDescription(B.BantaiMirageFruitStockRow, B.BantaiFruitStockStatusAdvanced())
        end)
        pcall(function()
            B.BantaiSetRowDescription(B.BantaiServerAgeRow, B.BantaiServerAgeStatus())
        end)
        task.wait(4)
    end
end)



-----------------------------------
-- BOSS FARM + SHOP EXTENSION
-----------------------------------
B.BossFarmEnabled = false
B.BossTween = nil
B.BossMoveToken = 0
B.SelectedBoss = nil
B.BossSelectRow = nil
B.BossSelectList = nil

B.WorldBosses = {
    [1] = {"The Gorilla King", "The Saw", "Bobby", "Yeti", "Mob Leader", "Vice Admiral", "Warden", "Chief Warden", "Swan", "Magma Admiral", "Fishman Lord", "Wysper", "Thunder God", "Cyborg", "Saber Expert"},
    [2] = {"Diamond", "Jeremy", "Fajita", "Don Swan", "Smoke Admiral", "Cursed Captain", "Darkbeard", "Order", "Awakened Ice Admiral", "Tide Keeper"},
    [3] = {"Stone", "Island Empress", "Rocket Admiral", "Captain Elephant", "Beautiful Pirate", "rip_indra True Form", "Longma", "Soul Reaper", "Cake Queen", "Cake Prince", "Dough King"},
}

B.SeaIndexCache = nil
function B.getSeaIndex()
    if B.SeaIndexCache then return B.SeaIndexCache end
    local function done(n) B.SeaIndexCache = n; return n end

    -- 1) The game's own map attribute (e.g. "Sea1" / "Sea2" / "Sea3").
    local okAttr, attr = pcall(function() return Workspace:GetAttribute("MAP") end)
    if okAttr and attr ~= nil then
        local text = tostring(attr):lower()
        if text:find("3", 1, true) or text:find("third", 1, true) then return done(3) end
        if text:find("2", 1, true) or text:find("second", 1, true) then return done(2) end
        if text:find("1", 1, true) or text:find("first", 1, true) then return done(1) end
    end

    -- 2) Known place ids.
    local place = tonumber(game.PlaceId)
    local seaPlaces = {
        [2753915549] = 1, [85211729168715] = 1,
        [4442272183] = 2, [79091703265657] = 2,
        [7449423635] = 3, [100117331123089] = 3,
    }
    if place and seaPlaces[place] then return done(seaPlaces[place]) end

    -- 3) Map landmarks (searched recursively because they are not always direct children).
    local map = Workspace:FindFirstChild("Map")
    if map then
        local function has(name) return map:FindFirstChild(name, true) ~= nil end
        if has("HydraIsland") or has("GreatTree") or has("CastleOnTheSea") or has("TikiOutpost") or has("Mansion") then return done(3) end
        if has("IceCastle") or has("CursedShip") or has("ForgottenIsland") or has("KingdomofRose") or has("Kingdom of Rose") then return done(2) end
        if has("Jungle") or has("Pirate") or has("Desert") or has("Marine") then return done(1) end
    end
    -- Not certain yet: do not cache, try again next call.
    return 1
end

function B.setBossTitle(name)
    if B.BossSelectRow then
        local labels = {}
        for _, child in ipairs(B.BossSelectRow:GetChildren()) do
            if child:IsA("TextLabel") then labels[#labels+1] = child end
        end
        if labels[1] then labels[1].Text = "👹 Select Boss: " .. tostring(name or "None") end
        if labels[2] then labels[2].Text = "Pick which boss you want to hunt." end
    end
end

function B.makeBossSelector()
    local currentSea = B.getSeaIndex()
    local bosses = B.WorldBosses[currentSea] or B.WorldBosses[1]
    B.CurrentBossSea = currentSea
    B.SelectedBoss = bosses[1]
    B.BossSelectRow = makeDescriptionRow(FarmingPage, "👹 Select Boss: " .. B.SelectedBoss,
        "Pick which boss you want to hunt.", 12, function(row, desc)
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
            B.BossSelectList = list
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
                    B.CurrentBossSea = B.getSeaIndex()
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

function B.refreshBossSelectorForSea()
    local sea = B.getSeaIndex()
    if B.CurrentBossSea == sea then return end
    B.CurrentBossSea = sea
    local bosses = B.WorldBosses[sea] or B.WorldBosses[1]
    B.SelectedBoss = bosses[1]
    B.setBossTitle(B.SelectedBoss)
    local list = B.BossSelectList
    if list then
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        for i, boss in ipairs(bosses) do
            local option = Instance.new("TextButton")
            option.Name = boss .. "BossOption"
            option.Size = UDim2.new(1,0,0,36)
            option.LayoutOrder = i
            option.BackgroundColor3 = COLORS.Content
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
                B.CurrentBossSea = B.getSeaIndex()
                B.setBossTitle(boss)
                list.Visible = false
                list.Size = UDim2.new(1,0,0,0)
            end)
        end
    end
end

B.BossSelectList = B.BossSelectList or nil
B.BossStatusRow = makeDescriptionRow(FarmingPage, "📡 Boss Status", "Checking...", 14, function() end)
B.BossFarmRow = makeToggle(FarmingPage, "🏆 Boss Farm", "Hunts the selected boss until it is defeated.", 15, false, function(v)
    B.BossFarmEnabled = v
    if not v then
        B.BossMoveToken += 1
        if B.BossTween then
            pcall(function() B.BossTween:Cancel() end)
            B.BossTween = nil
        end
        cancelFeatureTween("Boss")
        setTweenNoclip(false)
    end
end)

task.spawn(function()
    while scriptRunning do
        pcall(B.refreshBossSelectorForSea)
        task.wait(3)
    end
end)

function B.findBossModel()
    if not B.SelectedBoss then return nil end
    local bosses = B.WorldBosses[B.getSeaIndex()] or {}
    if not table.find(bosses, B.SelectedBoss) then
        return nil
    end
    local enemies = Workspace:FindFirstChild("Enemies")
    local m = enemies and enemies:FindFirstChild(B.SelectedBoss)
    if m and m:FindFirstChildOfClass("Humanoid") then return m end
    local replicated = ReplicatedStorage:FindFirstChild(B.SelectedBoss)
    if replicated and replicated:IsA("Model") then return replicated end
    return nil
end

function B.bossFarmStep()
    B.refreshBossSelectorForSea()
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
        B.BossMoveToken += 1
        local moveToken = B.BossMoveToken
        beginFeatureTween("Boss")
        setTweenNoclip(true)
        if B.BossTween then pcall(function() B.BossTween:Cancel() end) end
        local duration = math.max(distance / math.max(speed,1), 0.01)
        B.BossTween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame=targetCFrame})
        FeatureTweens["Boss"] = B.BossTween
        B.BossTween:Play()
        local done = false
        local conn
        conn = B.BossTween.Completed:Connect(function() done=true; if conn then conn:Disconnect() end end)
        while B.BossFarmEnabled and scriptRunning and moveToken == B.BossMoveToken and not done and hum.Health > 0 do
            task.wait()
        end
        if conn then pcall(function() conn:Disconnect() end) end
        if moveToken ~= B.BossMoveToken or not B.BossFarmEnabled or not scriptRunning then
            if B.BossTween then pcall(function() B.BossTween:Cancel() end) end
            B.BossTween = nil
            FeatureTweens["Boss"] = nil
            setTweenNoclip(false)
            return
        end
        B.BossTween = nil
        FeatureTweens["Boss"] = nil
        setTweenNoclip(false)
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
        pcall(B.refreshBossSelectorForSea)
        task.wait(1)
    end
end)

task.spawn(function()
    while scriptRunning do
        pcall(function()
            B.refreshBossSelectorForSea()
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
B.ShopTab = createTab("Shop", "◇", 11)
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
B.shopButton("🎁 Redeem All Codes", "Redeems game codes (no codes are loaded yet).", 2, function()
    -- No code list is assumed here; only documented shop purchases are enabled.
end)
B.shopButton("🏝️ Travel to Sea 1", "Takes you to the First Sea.", 3, function() B.shopCall("TravelMain") end)
B.shopButton("🏙️ Travel to Sea 2", "Takes you to the Second Sea.", 4, function() B.shopCall("TravelDressrosa") end)
B.shopButton("🌴 Travel to Sea 3", "Takes you to the Third Sea.", 5, function() B.shopCall("TravelZou") end)

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
for _,item in ipairs(B.melee) do B.shopButton("🥋 Buy "..item[1], "Buys the "..item[1].." fighting style.", B.order, item[2]); B.order+=1 end

addSection(B.ShopPage, "Haki / Ability", B.order+1); B.order+=2
B.haki = {
    {"Buy Geppo", function() B.shopCall("BuyHaki","Geppo") end},
    {"Buy Buso", function() B.shopCall("BuyHaki","Buso") end},
    {"Buy Soru", function() B.shopCall("BuyHaki","Soru") end},
    {"Buy Ken (Observation)", function() B.shopCall("KenTalk","Buy") end},
}
for _,item in ipairs(B.haki) do B.shopButton("✨ "..item[1], "Buys this ability from its trainer.", B.order, item[2]); B.order+=1 end

addSection(B.ShopPage, "Sword", B.order+1); B.order+=2
B.swords = {"Katana","Cutlass","Dual Katana","Iron Mace","Triple Katana","Pipe","Dual-Headed Blade","Soul Cane","Bisento"}
for _,name in ipairs(B.swords) do B.shopButton("🗡️ Buy "..name, "Buys the "..name.." sword.", B.order, function() B.shopCall("BuyItem", name == "Dual Katana" and "Duel Katana" or name) end); B.order+=1 end
B.shopButton("🗡️ Buy Pole V2", "Buys Pole (V2) from the Thunder God.", B.order, function() B.shopCall("ThunderGodTalk") end); B.order+=1

addSection(B.ShopPage, "Gun", B.order+1); B.order+=2
B.guns = {"Musket","Slingshot","Flintlock","Refined Flintlock","Cannon"}
for _,name in ipairs(B.guns) do B.shopButton("🔫 Buy "..name, "Buys the "..name.." gun.", B.order, function() B.shopCall("BuyItem",name) end); B.order+=1 end
B.shopButton("🔫 Buy Kabucha", "Buys the Kabucha gun.", B.order, function() B.shopCall("BlackbeardReward","Slingshot","1"); B.shopCall("BlackbeardReward","Slingshot","2") end); B.order+=1
B.shopButton("🔫 Buy Bizarre Rifle", "Buys the Bizarre Rifle with Ectoplasm.", B.order, function() B.shopCall("Ectoplasm","Buy",1) end); B.order+=1

addSection(B.ShopPage, "Accessories", B.order+1); B.order+=2
for _,name in ipairs({"Black Cape","Swordsman Hat","Tomoe Ring"}) do B.shopButton("🎩 Buy "..name, "Buys the "..name.." accessory.", B.order, function() B.shopCall("BuyItem",name) end); B.order+=1 end

addSection(B.ShopPage, "Race / Other", B.order+1); B.order+=2
B.shopButton("👻 Buy Ghoul Race", "Changes your race to Ghoul using Ectoplasm.", B.order, function() B.shopCall("Ectoplasm","Change",4) end); B.order+=1
B.shopButton("🤖 Buy Cyborg Race", "Changes your race to Cyborg.", B.order, function() B.shopCall("CyborgTrainer","Buy") end); B.order+=1
B.shopButton("♻️ Refund Stats", "Resets your stat points so you can spend them again.", B.order, function() B.shopCall("BlackbeardReward","Refund","1"); B.shopCall("BlackbeardReward","Refund","2") end); B.order+=1
B.shopButton("🎲 Reroll Race", "Rerolls your race into a new one.", B.order, function() B.shopCall("BlackbeardReward","Reroll","1"); B.shopCall("BlackbeardReward","Reroll","2") end)

-----------------------------------
-- PREHISTORIC TAB
-----------------------------------
B.PrehistoricTab = createTab("Prehistoric", "♨", 9)
B.PrehistoricPage = createPage("PrehistoricPage")
Pages.Prehistoric = B.PrehistoricPage
B.PrehistoricTab.MouseButton1Click:Connect(function() showTab("Prehistoric") end)

B.PrehistoricStatusRow = makeDescriptionRow(B.PrehistoricPage, "🦖 Prehistoric Status", "Checking...", 2, function() end)
B.SelectedPrehistoricBoat = "Guardian"
B.PrehistoricBoats = {"Guardian","Dinghy","PirateSloop","PirateBrigade","PirateGrandBrigade","MarineSloop","MarineBrigade","MarineGrandBrigade","Beast Hunter"}
B.PrehistoricBoatMode = "Own Boat"
B.PrehistoricBoatModes = {"Local Boat", "Own Boat"}

local function makeSimpleDropdown(page, title, description, order, values, initial, onSelect)
    local function getValues()
        if type(values) == "function" then
            local ok, result = pcall(values)
            if ok and type(result) == "table" then return result end
        end
        return values
    end
    local initialValues = getValues() or {}
    local selected = initial or initialValues[1]
    local row = makeDescriptionRow(page, title .. ": " .. tostring(selected), description, order, function(row, desc)
        local arrow = label(row, "⌄", UDim2.new(0,30,1,0), UDim2.new(1,-45,0,0), 18, COLORS.Accent, Enum.Font.GothamBold)
        local list = Instance.new("ScrollingFrame")
        list.Name = title:gsub("%s+", "") .. "Options"
        list.LayoutOrder = (order or 1) + 1
        list.Size = UDim2.new(1,0,0,0)
        list.BackgroundColor3 = COLORS.Row
        list.BorderSizePixel = 0
        list.ScrollBarThickness = 3
        list.ScrollBarImageColor3 = COLORS.Accent
        list.AutomaticCanvasSize = Enum.AutomaticSize.Y
        list.Visible = false
        list.Parent = page
        corner(list,6)
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0,3); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Parent = list
        local function rebuildOptions()
            for _,child in ipairs(list:GetChildren()) do
                if child:IsA("TextButton") then child:Destroy() end
            end
            local currentValues = getValues() or {}
            for i,value in ipairs(currentValues) do
                local option = Instance.new("TextButton")
            option.Size = UDim2.new(1,0,0,36); option.LayoutOrder=i
            option.BackgroundColor3=COLORS.Content; option.BackgroundTransparency=0.18; option.Text=tostring(value); option.TextColor3=COLORS.Text
            option.TextSize=10; option.Font=Enum.Font.GothamMedium; option.TextXAlignment=Enum.TextXAlignment.Left
            option.AutoButtonColor=false; option.Parent=list; corner(option,5)
                option.Activated:Connect(function()
                    selected=value
                    row:FindFirstChildWhichIsA("TextLabel").Text=title .. ": " .. tostring(value)
                    desc.Text="Selected: " .. tostring(value)
                    list.Visible=false; list.Size=UDim2.new(1,0,0,0); arrow.Text="⌄"
                    onSelect(value)
                end)
            end
        end
        rebuildOptions()
        local open=false
        row.Activated:Connect(function()
            open=not open
            if open then
                rebuildOptions()
                local currentValues = getValues() or {}
                list.Visible=true
                list.Size=UDim2.new(1,0,0,math.min(#currentValues*39+8,250))
            else
                list.Visible=false
                list.Size=UDim2.new(1,0,0,0)
            end
            arrow.Text=open and "⌃" or "⌄"
        end)
    end)
    return row
end

makeSimpleDropdown(B.PrehistoricPage, "🚤 Boat Mode", "Choose between your own boat or any boat that is already spawned.", 3, B.PrehistoricBoatModes, B.PrehistoricBoatMode, function(v) B.PrehistoricBoatMode=v end)
makeSimpleDropdown(B.PrehistoricPage, "⛵ Select Boat", "Choose which boat gets bought when you need one.", 4, B.PrehistoricBoats, B.SelectedPrehistoricBoat, function(v) B.SelectedPrehistoricBoat=v end)

B.AutoFindPrehistoric = false
B.AutoCompletePrehistoric = false
B.AutoCollectBones = false
B.AutoCollectEgg = false
B.AutoPatchLava = false

B.AutoFindPrehistoricRow = makeToggle(B.PrehistoricPage,"🌋 Auto Find Prehistoric","Sails out to sea until Prehistoric Island appears.",5,false,function(v) B.AutoFindPrehistoric=v end)
B.AutoCompletePrehistoricRow = makeToggle(B.PrehistoricPage,"🦖 Complete Prehistoric","Finds the island and clears it: lava, bones and eggs.",6,false,function(v) B.AutoCompletePrehistoric=v end)
B.AutoCollectBonesRow = makeToggle(B.PrehistoricPage,"🦴 Auto Collect Bones","Grabs every dino bone on the island.",7,false,function(v) B.AutoCollectBones=v end)
B.AutoCollectEggRow = makeToggle(B.PrehistoricPage,"🥚 Auto Collect Dragon Egg","Picks up the Dragon Egg for you.",8,false,function(v) B.AutoCollectEgg=v end)
B.AutoPatchLavaRow = makeToggle(B.PrehistoricPage,"🧯 Remove Lava","Removes the island lava so you can walk safely.",9,false,function(v) B.AutoPatchLava=v end)
B.CraftMagnetRow = makeAction(B.PrehistoricPage,"🧲 Craft Volcanic Magnet","Crafts a Volcanic Magnet for you.",10,function()
    local commF=B.BantaiGetCommF(); if commF then pcall(function() commF:InvokeServer("CraftItem","Craft","Volcanic Magnet") end) end
end)

do -- scope: Prehistoric helpers (frees top-level local slots)
local TikiBoatDock = CFrame.new(-16927.451, 9.086, 433.864)
local PREHISTORIC_SEARCH_TARGET = Vector3.new(-10000000, 31, 37016.25)
local PrehistoricZoneIndex = 1

local function getSelectedBoatModel()
    local boats=Workspace:FindFirstChild("Boats")
    if not boats then return nil end
    local character=Player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local localFallback=nil
    for _,boat in ipairs(boats:GetChildren()) do
        local seat=boat:FindFirstChildWhichIsA("VehicleSeat", true)
        if seat then
            local owner=boat:FindFirstChild("Owner", true)
            local ownerValue=owner and owner.Value
            local owned=ownerValue==Player or tostring(ownerValue)==Player.Name or tostring(ownerValue)==tostring(Player.UserId)
            if humanoid and seat.Occupant==humanoid then return boat end
            if B.PrehistoricBoatMode=="Own Boat" then
                if owned then return boat end
            else
                -- Local Boat: accept any spawned usable boat.
                localFallback=localFallback or boat
            end
        end
    end
    return localFallback
end

local function ownBoatStillExists(boat)
    if not boat or not boat.Parent then return false end
    local boats=Workspace:FindFirstChild("Boats")
    if not boats or not boat:IsDescendantOf(boats) then return false end
    local seat=boat:FindFirstChildWhichIsA("VehicleSeat", true)
    if not seat then return false end
    local owner=boat:FindFirstChild("Owner", true)
    local value=owner and owner.Value
    return value==Player or tostring(value)==Player.Name or tostring(value)==tostring(Player.UserId)
end

local function buySelectedBoat()
    local commF=B.BantaiGetCommF(); if not commF then return false end
    local char=Player.Character; local root=char and char:FindFirstChild("HumanoidRootPart")
    local dock=TikiBoatDock
    if root and (root.Position-dock.Position).Magnitude>30 then
        local distance=(root.Position-dock.Position).Magnitude
        local token=beginFeatureTween("Prehistoric")
        setTweenNoclip(true)
        local tw=TweenService:Create(root,TweenInfo.new(math.max(distance/math.max(speed,1),0.05),Enum.EasingStyle.Linear),{CFrame=dock})
        FeatureTweens["Prehistoric"]=tw
        tw:Play()
        while isFeatureTweenCurrent("Prehistoric",token) and tw.PlaybackState==Enum.PlaybackState.Playing do task.wait() end
        pcall(function() tw:Cancel() end)
        if FeatureTweens["Prehistoric"]==tw then FeatureTweens["Prehistoric"]=nil end
        setTweenNoclip(false)
        if not isFeatureTweenCurrent("Prehistoric",token) then return false end
    end
    local oldBoat=getSelectedBoatModel()
    if oldBoat and B.PrehistoricBoatMode=="Own Boat" then
        pcall(function() oldBoat:Destroy() end)
        task.wait(0.2)
    end
    local ok = pcall(function() commF:InvokeServer("BuyBoat",B.SelectedPrehistoricBoat or "Guardian") end)
    local boat=nil
    local deadline=os.clock()+5
    repeat
        task.wait(0.25)
        boat=getSelectedBoatModel()
    until boat or os.clock()>=deadline
    if boat then
        B.BantaiSetRowDescription(B.PrehistoricStatusRow,"🛥️ Boat ready at Tiki Outpost")
        return true
    end
    if ok then
        B.BantaiSetRowDescription(B.PrehistoricStatusRow,"Waiting for boat to spawn at Tiki...")
    else
        B.BantaiSetRowDescription(B.PrehistoricStatusRow,"Boat purchase failed")
    end
    return false
end

local function patchPrehistoricLava()
    local map=Workspace:FindFirstChild("Map"); local island=map and map:FindFirstChild("PrehistoricIsland")
    if not island then return end
    local core=island:FindFirstChild("Core")
    local interior=core and core:FindFirstChild("InteriorLava")
    if interior then pcall(function() interior:Destroy() end) end
    for _,obj in ipairs(island:GetDescendants()) do
        if obj.Name:lower():find("lava",1,true) and (obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("MeshPart")) then
            pcall(function() obj:Destroy() end)
        end
    end
end

local function findPrehistoricRock()
    local island=(Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("PrehistoricIsland")) or (Workspace:FindFirstChild("_WorldOrigin") and Workspace._WorldOrigin:FindFirstChild("Locations") and Workspace._WorldOrigin.Locations:FindFirstChild("Prehistoric Island"))
    local core=island and island:FindFirstChild("Core")
    local rocks=core and core:FindFirstChild("VolcanoRocks")
    if not rocks then return nil end
    for _,model in ipairs(rocks:GetChildren()) do
        if model:IsA("Model") then
            local rock=model:FindFirstChild("volcanorock")
            if rock and rock:IsA("MeshPart") then
                local c=rock.Color
                if c==Color3.fromRGB(185,53,56) or c==Color3.fromRGB(185,53,57) then return rock end
            end
        end
    end
end

local PrehistoricMoveToken = 0
local PrehistoricTween = nil
local PrehistoricBoatTween = nil
local PrehistoricBoatNoclipStates = {}

local function setBoatNoclip(boat, enabled)
    if enabled then
        if not boat then return end
        PrehistoricBoatNoclipStates = {}
        for _, obj in ipairs(boat:GetDescendants()) do
            if obj:IsA("BasePart") then
                PrehistoricBoatNoclipStates[obj] = true
                obj.CanCollide = false
            end
        end
    else
        for part in pairs(PrehistoricBoatNoclipStates) do
            if part and part.Parent then
                pcall(function() part.CanCollide = true end)
            end
        end
        PrehistoricBoatNoclipStates = {}
        if boat then
            pcall(function()
                for _, obj in ipairs(boat:GetDescendants()) do
                    if obj:IsA("BasePart") then obj.CanCollide = true end
                end
            end)
        end
    end
end

local function stopPrehistoricMovement()
    PrehistoricMoveToken += 1
    cancelFeatureTween("Prehistoric")
    if PrehistoricTween then pcall(function() PrehistoricTween:Cancel() end); PrehistoricTween=nil end
    if PrehistoricBoatTween then
        PrehistoricBoatTween.Cancelled = true
        PrehistoricBoatTween = nil
    end
    setBoatNoclip(nil, false)
    setTweenNoclip(false)
end

local function moveToCFrame(target)
    local char=Player.Character
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    PrehistoricMoveToken += 1
    local token=PrehistoricMoveToken
    cancelFeatureTween("Prehistoric")
    local distance=(root.Position-target.Position).Magnitude
    if distance<=5 then return true end
    setTweenNoclip(true)
    local tw=TweenService:Create(root,TweenInfo.new(math.max(distance/math.max(speed,1),0.05),Enum.EasingStyle.Linear),{CFrame=target})
    PrehistoricTween=tw
    FeatureTweens["Prehistoric"]=tw
    tw:Play()
    while scriptRunning and token==PrehistoricMoveToken
        and (B.AutoFindPrehistoric or B.AutoCompletePrehistoric or B.AutoCollectBones or B.AutoCollectEgg)
        and tw.PlaybackState==Enum.PlaybackState.Playing do
        task.wait()
    end
    local ok=scriptRunning and token==PrehistoricMoveToken
    pcall(function() tw:Cancel() end)
    if PrehistoricTween==tw then PrehistoricTween=nil end
    if FeatureTweens["Prehistoric"]==tw then FeatureTweens["Prehistoric"]=nil end
    setTweenNoclip(false)
    return ok
end

local function sitInPrehistoricBoat(boat)
    if not boat then return false end
    local char=Player.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    local seat=boat:FindFirstChildWhichIsA("VehicleSeat", true)
    if not hum or not seat then return false end

    if seat.Occupant ~= hum then
        pcall(function() seat:Sit(hum) end)
        task.wait(0.15)
    end
    return seat.Occupant == hum
end

local function tweenPrehistoricBoat(boat, targetPosition)
    if not boat or not targetPosition then return false end
    local seat=boat:FindFirstChildWhichIsA("VehicleSeat", true)
    local primary=boat.PrimaryPart or seat
    if not primary then return false end

    local start=boat:GetPivot()
    local target= CFrame.lookAt(
        targetPosition + Vector3.new(0, (B.BoatFlyHeight or 30), 0),
        targetPosition + Vector3.new(0, (B.BoatFlyHeight or 30), 1)
    )
    local distance=(start.Position-target.Position).Magnitude
    if distance <= 8 then
        pcall(function() boat:PivotTo(target) end)
        return true
    end

    if PrehistoricBoatTween then PrehistoricBoatTween.Cancelled=true end
    local state={Cancelled=false}
    PrehistoricBoatTween=state
    setBoatNoclip(boat, true)

    local duration=math.max(distance/(B.BoatTweenSpeed or 250), 0.08)
    local started=os.clock()
    while scriptRunning and not state.Cancelled
        and (B.AutoFindPrehistoric or B.AutoCompletePrehistoric) do
        local alpha=math.clamp((os.clock()-started)/duration, 0, 1)
        local cf=start:Lerp(target, alpha)
        pcall(function() boat:PivotTo(cf) end)
        if alpha >= 1 then break end
        RunService.Heartbeat:Wait()
    end

    local ok=scriptRunning and not state.Cancelled
    if ok then pcall(function() boat:PivotTo(target) end) end
    setBoatNoclip(boat, false)
    if PrehistoricBoatTween==state then PrehistoricBoatTween=nil end
    return ok
end

task.spawn(function()
    while scriptRunning do
        local map=Workspace:FindFirstChild("Map")
        local worldOrigin=Workspace:FindFirstChild("_WorldOrigin")
        local island=(map and map:FindFirstChild("PrehistoricIsland"))
            or (worldOrigin and worldOrigin:FindFirstChild("Locations") and worldOrigin.Locations:FindFirstChild("Prehistoric Island"))
        if B.AutoFindPrehistoric or B.AutoCompletePrehistoric then
            if island then
                stopPrehistoricMovement()
                B.BantaiSetRowDescription(B.PrehistoricStatusRow,"✅ Prehistoric Island found")
                local hum=Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
                if hum then pcall(function() hum.Sit=false end) end
            else
                local boat=getSelectedBoatModel()
                if B.PrehistoricBoatMode=="Own Boat" then
                    if not ownBoatStillExists(boat) then
                        boat=nil
                        B.BantaiSetRowDescription(B.PrehistoricStatusRow,"🛥️ Own Boat missing/destroyed • buying another...")
                        buySelectedBoat()
                        boat=getSelectedBoatModel()
                    end
                elseif not boat then
                    B.BantaiSetRowDescription(B.PrehistoricStatusRow,"🛥️ Waiting for a local boat to be spawned...")
                end
                local char=Player.Character; local hum=char and char:FindFirstChildOfClass("Humanoid")
                local seat=boat and boat:FindFirstChildWhichIsA("VehicleSeat", true)
                if boat and seat and hum and seat.Occupant~=hum then
                    moveToCFrame(seat.CFrame*CFrame.new(0,2,0))
                    sitInPrehistoricBoat(boat)
                elseif boat and seat and hum and seat.Occupant==hum then
                    -- Fly the actual boat through progressively higher deep-sea
                    -- search zones. The boat itself is noclipped only while moving.
                    local target=PREHISTORIC_SEARCH_TARGET

                    pcall(function()
                        seat.MaxSpeed=(B.BoatTweenSpeed or 250)
                        seat.ThrottleFloat=0
                        seat.SteerFloat=0
                    end)

                    tweenPrehistoricBoat(boat, target)
                    B.BantaiSetRowDescription(
                        B.PrehistoricStatusRow,
                        "🌊 Searching deep sea level "..tostring(PrehistoricZoneIndex)..
                        " • Boat tween "..tostring((B.BoatTweenSpeed or 250))..
                        " • Fly height "..tostring((B.BoatFlyHeight or 30))
                    )
                end
            end
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    while scriptRunning do
        local enabled=B.AutoCompletePrehistoric or B.AutoPatchLava
        if enabled then pcall(patchPrehistoricLava) end
        task.wait(0.35)
    end
end)

task.spawn(function()
    while scriptRunning do
        if B.AutoCollectBones or B.AutoCompletePrehistoric then
            local found=false
            for _,obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA("BasePart") and obj.Name=="DinoBone" then
                    found=true; moveToCFrame(CFrame.new(obj.Position)); if not B.AutoCompletePrehistoric then break end
                end
            end
            if not found then task.wait(0.2) end
        else task.wait(0.5) end
    end
end)

task.spawn(function()
    while scriptRunning do
        if B.AutoCollectEgg or B.AutoCompletePrehistoric then
            pcall(function()
                local net=ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Net")
                local remote=net and net:FindFirstChild("RE/CollectedDragonEgg")
                if remote then remote:FireServer() end
            end)
            task.wait(0.25)
        else task.wait(0.5) end
    end
end)

task.spawn(function()
    while scriptRunning do
        if B.AutoCompletePrehistoric then
            local rock=findPrehistoricRock()
            if rock then
                moveToCFrame(CFrame.new(rock.Position))
            end
            local enemies=Workspace:FindFirstChild("Enemies"); local golem=enemies and enemies:FindFirstChild("Lava Golem")
            if golem and golem:FindFirstChild("HumanoidRootPart") and golem:FindFirstChildOfClass("Humanoid") then
                local hum=golem:FindFirstChildOfClass("Humanoid")
                if hum.Health>0 then
                    pcall(function() hum.WalkSpeed=0; golem.HumanoidRootPart.CanCollide=false end)
                    moveToCFrame(golem.HumanoidRootPart.CFrame*CFrame.new(0,30,0))
                    local env=getSharedEnvironment(); local fastAttack=env and env.rz_FastAttack; local head=golem:FindFirstChild("Head") or golem.HumanoidRootPart
                    if fastAttack and type(fastAttack.Attack)=="function" then pcall(function() fastAttack:Attack(head,{{golem,head}}) end) end
                end
            end
        end
        task.wait(0.15)
    end
end)

end -- end Prehistoric helpers scope

-----------------------------------
-- MISC TAB
-----------------------------------
B.MiscTab = createTab("Misc", "✦", 10)
B.MiscPage = createPage("MiscPage")
Pages.Misc = B.MiscPage
B.MiscTab.MouseButton1Click:Connect(function() showTab("Misc") end)
addSection(B.MiscPage,"Menus",1)
local function openFruitDealer(kind)
    local controllers=ReplicatedStorage:FindFirstChild("Controllers")
    local ui=controllers and controllers:FindFirstChild("UI")
    local fruitShop=ui and ui:FindFirstChild("FruitShop")
    if not fruitShop then return false end
    local ok,module=pcall(require,fruitShop)
    if not ok or type(module)~="table" or type(module.Open)~="function" then return false end
    return pcall(function() module:Open(kind) end)
end
B.MiscFruitDealer=makeAction(B.MiscPage,"🍈 Fruit Dealer","Opens the Fruit Dealer shop from anywhere.",2,function() openFruitDealer("FruitDealer") end)
B.MiscMirageDealer=makeAction(B.MiscPage,"🔮 Mirage Fruit Dealer","Opens the Mirage Fruit Dealer shop from anywhere.",3,function() openFruitDealer("AdvancedFruitDealer") end)
B.MiscTitles=makeAction(B.MiscPage,"🏷️ Titles","Opens your titles so you can equip one.",4,function()
    local pg=Player:FindFirstChild("PlayerGui")
    local main=pg and pg:FindFirstChild("Main")
    local commF=B.BantaiGetCommF()
    if commF then pcall(function() commF:InvokeServer("getTitles") end) end
    task.wait(0.25)
    pg=Player:FindFirstChild("PlayerGui")
    main=pg and pg:FindFirstChild("Main")
    local titles=main and main:FindFirstChild("Titles")
    if titles and titles:IsA("GuiObject") then
        titles.Visible=true
        titles.ZIndex=200
        return
    end
    if main then
        titles=main:WaitForChild("Titles",2)
        if titles and titles:IsA("GuiObject") then
            titles.Visible=true
            titles.ZIndex=200
        end
    end
end)

-----------------------------------
-- FISHING TAB
-- Remote protocol taken from the Redz Hub source:
-- ReplicatedStorage.FishReplicated.FishingRequest (RemoteFunction) with
-- "StartCasting", "CastLineAtLocation", "Catching", "Catch", "SelectBait".
-----------------------------------
B.FishingTab = createTab("Fishing", "◎", 12)
B.FishingPage = createPage("FishingPage")
Pages.Fishing = B.FishingPage
B.FishingTab.MouseButton1Click:Connect(function() showTab("Fishing") end)

do
    local F = {
        AutoFish = false, AutoEquip = true, HideEffects = false, AutoGetChest = false, AutoSlap = false, AutoCollect = true,
        Rod = "Fishing Rod", Bait = "Basic Bait",
        CastDistance = 60, CastPower = 100, CatchDelay = 0.25,
        LastCastPosition = nil, LastResult = nil,
        Casts = 0, Caught = 0, LastStatus = "",
        WaitingForCatch = false, LastBiteAt = 0, LastCatchAt = 0,
        LastKey = nil, LastChange = os.clock(), WaterFn = nil,
    }
    B.Fishing = F
    local page = B.FishingPage

    function F.setStatus(text)
        if F.StatusRow and text ~= F.LastStatus then
            F.LastStatus = text
            B.BantaiSetRowDescription(F.StatusRow, text)
        end
    end

    function F.updateStats()
        if F.StatsRow then
            B.BantaiSetRowDescription(F.StatsRow, "Casts: " .. F.Casts .. "   |   Catches: " .. F.Caught)
        end
    end

    function F.getRemote()
        local folder = ReplicatedStorage:FindFirstChild("FishReplicated")
        local remote = folder and folder:FindFirstChild("FishingRequest")
        if remote and remote:IsA("RemoteFunction") then return remote end
        return nil
    end

    function F.request(...)
        local remote = F.getRemote()
        if not remote then return false end
        local args = table.pack(...)
        local ok, result = pcall(function()
            return remote:InvokeServer(table.unpack(args, 1, args.n))
        end)
        return ok, result
    end

    -- Fishing rewards are normally granted by the Catch request itself.
    -- This collector handles physical reward drops (when the current game
    -- version exposes them) and refreshes the local inventory view without
    -- changing the working Catch protocol.
    function F.collectRewards()
        if not F.AutoCollect then return end
        local char = Player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local keywords = {"fish", "fishing", "treasure", "chest", "bait", "relic", "material", "item"}
        local function looksLikeReward(name)
            local n = tostring(name):lower()
            for _, k in ipairs(keywords) do
                if n:find(k, 1, true) then return true end
            end
            return false
        end

        -- If the reward is a physical pickup, touch its nearest BasePart.
        -- Keep the radius small so unrelated map objects are never targeted.
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Parent and looksLikeReward(obj.Name) then
                local d = (obj.Position - root.Position).Magnitude
                if d <= 18 then
                    pcall(function()
                        if firetouchinterest then
                            firetouchinterest(root, obj, 0)
                            task.wait()
                            firetouchinterest(root, obj, 1)
                        end
                    end)
                end
            end
        end

        -- Give the client a moment to receive the server inventory update.
        task.wait(0.08)
    end

    function F.getWater(position)
        if F.WaterFn == nil then
            F.WaterFn = false
            local util = ReplicatedStorage:FindFirstChild("Util")
            local module = util and util:FindFirstChild("GetWaterHeightAtLocation")
            if module and module:IsA("ModuleScript") then
                local ok, fn = pcall(require, module)
                if ok and type(fn) == "function" then F.WaterFn = fn end
            end
        end
        if F.WaterFn then
            local ok, height = pcall(F.WaterFn, position)
            if ok and type(height) == "number" then return height end
        end
        return nil
    end

    function F.findRod()
        local containers = {Player.Character, Player:FindFirstChild("Backpack")}
        for _, container in ipairs(containers) do
            if container then
                local exact = container:FindFirstChild(F.Rod)
                if exact and exact:IsA("Tool") then return exact end
            end
        end
        for _, container in ipairs(containers) do
            if container then
                for _, tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") and tool.Name:lower():find("rod", 1, true) then return tool end
                end
            end
        end
        return nil
    end

    function F.ensureRod(char, hum)
        local rod = F.findRod()
        if not rod then return nil end
        if rod.Parent == char then return rod end
        if not F.AutoEquip then return nil end
        pcall(function() hum:EquipTool(rod) end)
        task.wait(0.15)
        if rod.Parent == char then return rod end
        return nil
    end

    -- Trigger the normal Tool client path as well as the fishing remote.
    -- This keeps the rod animation/bobber effects alive instead of doing a
    -- silent server-only cast.
    function F.activateRod(rod)
        if not rod or rod.Parent ~= Player.Character then return false end
        local ok = pcall(function()
            rod:Activate()
        end)
        return ok
    end

    local function normalizedState(value)
        if value == nil then return "" end
        return tostring(value):lower():gsub("[%s_%-]", "")
    end

    function F.isBiting(state, server)
        local a, b = normalizedState(state), normalizedState(server)
        return a == "biting" or b == "biting" or a:find("bite", 1, true) ~= nil or b:find("bite", 1, true) ~= nil
    end

    function F.isReeled(state, server)
        local a, b = normalizedState(state), normalizedState(server)
        return a == "" or a == "reeledin" or b == "reeledin" or a == "idle" or b == "idle"
    end

    function F.castPosition(root)
        local look = root.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) else flat = flat.Unit end
        local target = root.Position + flat * F.CastDistance
        local waterY = F.getWater(target) or F.getWater(root.Position) or (root.Position.Y - 3)
        return Vector3.new(target.X, waterY, target.Z)
    end

    function F.step()
        local char = Player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then
            F.setStatus("Waiting for character...")
            return
        end

        local rod = F.ensureRod(char, hum)
        if not rod then
            F.setStatus("No fishing rod found")
            return
        end

        -- The reference fishing client casts by holding the normal mouse button
        -- until the cast meter reaches ~95%, then releases it. Keep that phase
        -- intact; the previous patch only handled bite/reel and could never
        -- start a fresh cast after the first cycle.
        local playerGui = Player:FindFirstChild("PlayerGui")
        local fishingReeling = playerGui and playerGui:FindFirstChild("Fishing_Reeling")
        local serverState = rod:GetAttribute("ServerState")
        local state = rod:GetAttribute("State")
        local biting = F.isBiting(state, serverState)
        local normalizedServer = normalizedState(serverState)
        local normalizedLocal = normalizedState(state)

        if fishingReeling and fishingReeling.Enabled then
            local minigame = fishingReeling:FindFirstChild("Minigame")
            minigame = minigame and minigame:FindFirstChild("Container")
            local reelZone = minigame and minigame:FindFirstChild("ReelZone")
            local fish = minigame and minigame:FindFirstChild("Fish")
            local treasure = minigame and minigame:FindFirstChild("Treasure")
            local target = nil

            if F.AutoGetChest and treasure and treasure.Visible then
                target = treasure
            elseif fish and fish.Visible then
                target = fish
            end

            -- A visible reel target is the safest confirmation that the bite
            -- actually happened. This avoids the old premature Catch call.
            if target and target.Visible then
                F.LastBiteAt = os.clock()
            end

            if target and target.Visible and reelZone and (os.clock() - (F.LastCatchAt or 0) > 0.75) then
                local targetCenter = target.Position.X.Scale + target.Size.X.Scale * 0.5
                local reelCenter = reelZone.Position.X.Scale + reelZone.Size.X.Scale * 0.5
                local delta = targetCenter - reelCenter

                if delta > 0.03 then
                    VirtualInputManager:SendMouseButtonEvent(0,0,0,true,game,1)
                elseif delta < -0.03 then
                    VirtualInputManager:SendMouseButtonEvent(0,0,0,false,game,1)
                else
                    VirtualInputManager:SendMouseButtonEvent(0,0,0,true,game,1)
                    task.wait(0.02)
                    VirtualInputManager:SendMouseButtonEvent(0,0,0,false,game,1)
                end

                local ok, result
                if F.AutoGetChest then
                    ok, result = F.request("Catch", 1, 1)
                else
                    ok, result = F.request("Catch", 1)
                end

                if ok and result ~= false then
                    F.Caught += 1
                    F.LastResult = result
                    F.updateStats()
                    F.setStatus(F.AutoGetChest and "🎣 Chest caught • preparing next cast" or "🎣 Fish caught • preparing next cast")
                    F.WaitingForCatch = false
                    F.LastBiteAt = 0
                    F.LastCatchAt = os.clock()
                    F.LastChange = os.clock()
                    task.spawn(F.collectRewards)
                else
                    F.setStatus("🎣 Reeling...")
                end
                task.wait(0.10)
                return
            end

            -- If the reel UI is up before the target is rendered, don't send
            -- Catch yet. Give the target a moment to appear.
            F.setStatus("🎣 Reel ready — waiting for target...")
            return
        elseif biting then
            VirtualInputManager:SendMouseButtonEvent(0,0,0,true,game,1)
            task.wait(0.08)
            VirtualInputManager:SendMouseButtonEvent(0,0,0,false,game,1)
            F.LastBiteAt = os.clock()
            F.setStatus("🐟 Bite detected - entering reel")
            F.LastChange = os.clock()
            return
        end

        -- Reference behavior: after ReeledIn/Waiting/idle, hold the mouse
        -- button for the cast meter, then release and allow the game to create
        -- the next fishing cycle.
        if normalizedLocal == "reeledin" or normalizedServer == "reeledin"
            or normalizedServer == "" or normalizedServer == "waiting"
            or normalizedLocal == "idle" or normalizedServer == "idle" then
            F.setStatus("🎣 Casting...")
            VirtualInputManager:SendMouseButtonEvent(0,0,0,true,game,1)
            local started = os.clock()
            while scriptRunning and F.AutoFish and (os.clock() - started) < 1.2 do
                task.wait(0.015)
                local meter = (Player.Character and Player.Character:FindFirstChild("Fishing_Cast Meter"))
                    or (Workspace:FindFirstChild("Fishing_Cast Meter"))
                local bar = meter and meter:FindFirstChild("CastMeter") and meter.CastMeter:FindFirstChild("Bar")
                local frame = bar and bar:FindFirstChild("Frame")
                if frame and frame.Size.Y.Scale >= 0.95 then break end
            end
            VirtualInputManager:SendMouseButtonEvent(0,0,0,false,game,1)
            F.Casts += 1
            F.updateStats()
            F.WaitingForCatch = true
            F.LastChange = os.clock()
            F.setStatus("🎣 Cast • waiting for bite")
            task.wait(0.30)
            return
        end

        -- Some rod versions expose no state while the cast is active. If the
        -- cast meter exists, do not restart it; otherwise retry after a short
        -- cooldown so the loop cannot spam input.
        local meter = (Player.Character and Player.Character:FindFirstChild("Fishing_Cast Meter"))
            or (Workspace:FindFirstChild("Fishing_Cast Meter"))
        if meter then
            F.setStatus("🎣 Waiting for bite...")
            return
        end

        if os.clock() - (F.LastChange or 0) > 1.5 then
            F.WaitingForCatch = false
            F.setStatus("🎣 Restarting cast...")
        else
            F.setStatus("🎣 Waiting for fishing state...")
        end
    end

    function F.hideEffects()
        local function mute(container)
            if not container then return end
            for _, obj in ipairs(container:GetDescendants()) do
                if obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail") then
                    pcall(function() obj.Enabled = false end)
                end
            end
        end
        mute(Player.Character)
        for _, child in ipairs(Workspace:GetChildren()) do
            local n = child.Name:lower()
            if n:find("bobber", 1, true) or n:find("fishing", 1, true) or n:find("fishline", 1, true) then
                mute(child)
            end
        end
    end

    function F.scan(keyword, defaults)
        local seen, list = {}, {}
        local function add(n) if not seen[n] then seen[n] = true; list[#list + 1] = n end end
        for _, d in ipairs(defaults) do add(d) end
        for _, container in ipairs({Player:FindFirstChild("Backpack"), Player.Character}) do
            if container then
                for _, tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") and tool.Name:lower():find(keyword, 1, true) then add(tool.Name) end
                end
            end
        end
        return list
    end

    -- Workers
    task.spawn(function()
        while scriptRunning do
            if F.AutoFish then
                local ok, err = pcall(F.step)
                if not ok then F.setStatus("Error: " .. tostring(err)) task.wait(0.5) end
                task.wait(0.12)
            else
                task.wait(0.4)
            end
        end
    end)
    task.spawn(function()
        while scriptRunning do
            if F.AutoSlap then
                pcall(function()
                    local gui = Player.PlayerGui and Player.PlayerGui:FindFirstChild("FishSlapMinigame")
                    if gui and gui.Enabled then
                        local bar = gui:FindFirstChild("Bar")
                        local green = bar and bar:FindFirstChild("GreenZone")
                        local tickObj = bar and bar:FindFirstChild("Tick")
                        local button = gui:FindFirstChild("SlapButton")
                        if green and tickObj and button then
                            local y = tickObj.AbsolutePosition.Y + tickObj.AbsoluteSize.Y * 0.5
                            local center = green.AbsolutePosition.Y + green.AbsoluteSize.Y * 0.5
                            local zone = green.AbsoluteSize.Y * 0.45
                            if math.abs(y-center) <= zone and type(firesignal) == "function" then
                                firesignal(button.Activated)
                            end
                        end
                    end
                end)
            end
            task.wait(0.10)
        end
    end)
    task.spawn(function()
        while scriptRunning do
            if F.HideEffects then pcall(F.hideEffects) end
            task.wait(0.5)
        end
    end)

    -- UI
    addSection(page, "Auto Fishing", 1)
    F.StatusRow = makeDescriptionRow(page, "🎣 Fishing Status", "Idle", 2, function() end)
    makeToggle(page, "🎣 Auto Fishing", "Casts, reels in and catches fish for you.", 3, false, function(enabled)
        F.AutoFish = enabled
        if enabled then
            F.WaitingForCatch = false
            F.LastBiteAt = 0
            F.LastCatchAt = 0
            F.LastChange = os.clock()
            F.request("SelectBait", F.Bait)
        else
            F.WaitingForCatch = false
            F.LastBiteAt = 0
            F.setStatus("Idle")
        end
    end)
    makeToggle(page, "🪝 Auto Equip Rod", "Takes out your fishing rod whenever it is not in hand.", 4, true, function(enabled)
        F.AutoEquip = enabled
    end)
    makeToggle(page, "🧰 Auto Get Chest", "Grabs treasure chests that show up while you fish.", 5, false, function(enabled)
        F.AutoGetChest = enabled
    end)
    makeToggle(page, "🎁 Auto Collect Rewards", "Picks up fishing drops lying nearby.", 6, true, function(enabled)
        F.AutoCollect = enabled
        if enabled then F.setStatus("🎒 Fishing reward collection enabled") end
    end)
    makeToggle(page, "👋 Auto Slap", "Plays the slap minigame for you.", 7, false, function(enabled)
        F.AutoSlap = enabled
    end)
    makeToggle(page, "🙈 Hide Fishing Effects", "Hides the rod particles and trails for a cleaner screen.", 8, false, function(enabled)
        F.HideEffects = enabled
    end)
    F.StatsRow = makeDescriptionRow(page, "📊 Session Stats", "Casts: 0   |   Catches: 0", 9, function() end)

    addSection(page, "Equipment", 10)
    makeSimpleDropdown(page, "🎣 Fishing Rod", "Choose which rod to fish with.", 11,
        F.scan("rod", {"Fishing Rod"}), "Fishing Rod", function(v) F.Rod = v end)
    makeSimpleDropdown(page, "🪱 Fishing Lure", "Choose which bait to fish with.", 13,
        F.scan("bait", {"Basic Bait"}), "Basic Bait", function(v)
            F.Bait = v
            F.request("SelectBait", v)
        end)
    makeInput(page, "✏️ Custom Bait", "Type any bait name and press enter to use it.", 15, F.Bait, function(box, text)
        local name = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            F.Bait = name
            F.request("SelectBait", name)
        end
        box.Text = F.Bait
    end)
    makeAction(page, "🔍 Detect Rod", "Finds your rod automatically.", 16, function()
        local rods = F.scan("rod", {})
        if rods[1] then
            F.Rod = rods[1]
            F.setStatus("Rod set to " .. rods[1])
        else
            F.setStatus("No rod found in your inventory")
        end
    end)

    makeAction(page, "♻️ Reset Stats", "Sets your cast and catch counts back to zero.", 14, function()
        F.Casts = 0
        F.Caught = 0
        F.updateStats()
    end)
end



-----------------------------------
-- TRAVEL
-- Island/portal destinations are kept per sea. The reference hub uses a
-- tween-to-CFrame travel flow and requestEntrance for portal travel.
-----------------------------------
do
    local TravelIsland = nil
    local TravelBusy = false

    local TravelIslands = {
        [1] = {
            {"Starter Island", CFrame.new(1060.102, 16.507, 1545.625)}, {"Jungle", CFrame.new(-1196,11,3412)},
            {"Pirate Village", CFrame.new(-1181.309,4.751,3803.546)}, {"Desert", CFrame.new(894.489,5.14,4392.434)},
            {"Snow Island", CFrame.new(1347.807,104.668,-1319.737)}, {"MarineFord", CFrame.new(-4914.821,50.964,4281.028)},
            {"Colosseum", CFrame.new(-1577,7,-2984)}, {"Sky Island 1", CFrame.new(-4970,717,-2620)},
            {"Sky Island 2", CFrame.new(-4650,873,-1750)}, {"Sky Island 3", CFrame.new(-7894,5547,-380)},
            {"Prison", CFrame.new(4875.33,5.652,734.85)}, {"Magma Village", CFrame.new(-5247.716,12.884,8504.969)},
            {"Under Water Island", CFrame.new(61163,17,1819)}, {"Fountain City", CFrame.new(5127.128,59.501,4105.446)},
        },
        [2] = {
            {"Kingdom of Rose", CFrame.new(-429.543,71.77,1836.182)}, {"The Cafe", CFrame.new(-380.479,77.22,255.826)},
            {"Green Zone", CFrame.new(-2448.53,73.016,-3210.631)}, {"Graveyard", CFrame.new(-5410,15,-721)},
            {"Snow Mountain", CFrame.new(753.143,408.236,-5274.615)}, {"Hot and Cold", CFrame.new(-6028,15,-4905)},
            {"Cursed Ship", CFrame.new(923.402,125.057,32885.875)}, {"Ice Castle", CFrame.new(611,401,-3320)},
            {"Forgotten Island", CFrame.new(-3043,238,-10170)}, {"Ussop Island", CFrame.new(4816.862,8.46,2863.82)},
        },
        [3] = {
            {"Port Town", CFrame.new(-290,44,5450)}, {"Hydra Island", CFrame.new(5226,604,345)},
            {"Great Tree", CFrame.new(28294,14896,103)}, {"Floating Turtle", CFrame.new(-13274.528,531.821,-7579.223)},
            {"Mansion", CFrame.new(-12545,455,-7490)}, {"Haunted Castle", CFrame.new(-9515.372,164.006,5786.061)},
            {"Peanut Island", CFrame.new(-2062.748,50.474,-10232.568)}, {"Ice Cream Island", CFrame.new(-902.568,79.932,-10988.848)},
            {"Cake Island", CFrame.new(-1884.775,19.328,-11666.897)}, {"Candy Island", CFrame.new(-1014.424,149.111,-14555.963)},
            {"Tiki Outpost", CFrame.new(-16218.683,9.086,445.618)}, {"Dragon Dojo", CFrame.new(5743.319,1206.91,936.011)},
        },
    }

    local function currentSea()
        local place = tonumber(game.PlaceId)
        if place == 2753915549 then return 1 end
        if place == 4442272183 then return 2 end
        if place == 7449423635 then return 3 end
        local map = Workspace:FindFirstChild("Map")
        if map then
            if map:FindFirstChild("HydraIsland") or map:FindFirstChild("GreatTree") or map:FindFirstChild("TikiOutpost") then return 3 end
            if map:FindFirstChild("IceCastle") or map:FindFirstChild("CursedShip") or map:FindFirstChild("KingdomofRose") then return 2 end
        end
        -- Coordinates are a useful last-resort detector when streamed map names
        -- are unavailable.
        local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
        if root then
            local x,z=root.Position.X,root.Position.Z
            if z > 25000 or x < -9000 and z < -1000 then return 2 end
            if math.abs(x) > 10000 or z > 13000 then return 3 end
        end
        return 1
    end

    local function seaName(n) return n == 1 and "First Sea" or n == 2 and "Second Sea" or "Third Sea" end
    local function normalizeName(v) return tostring(v or ""):lower():gsub("[%s%p_]+","") end

    local function findIslandCFrame(name, fallback)
        local map=Workspace:FindFirstChild("Map")
        if map then
            local wanted=normalizeName(name)
            for _,obj in ipairs(map:GetChildren()) do
                if normalizeName(obj.Name)==wanted then
                    local part=obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true))
                    if part then return part.CFrame + Vector3.new(0,8,0) end
                end
            end
        end
        return fallback + Vector3.new(0,8,0)
    end

    local function getCurrentEntries()
        local sea=currentSea()
        local out={}
        for _,item in ipairs(TravelIslands[sea] or {}) do out[#out+1]=item[1] end
        return out
    end

    local function findCurrentIsland(name)
        local sea=currentSea()
        for _,item in ipairs(TravelIslands[sea] or {}) do
            if item[1]==name then return item,sea end
        end
    end

    local function travelTween(target)
        if TravelBusy then return false end
        local root=Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        TravelBusy=true
        local token=beginFeatureTween("Travel")
        setTweenNoclip(true)
        local distance=(root.Position-target.Position).Magnitude
        local tw=TweenService:Create(root,TweenInfo.new(math.max(distance/250,0.2),Enum.EasingStyle.Linear),{CFrame=target})
        FeatureTweens["Travel"]=tw; tw:Play()
        while scriptRunning and isFeatureTweenCurrent("Travel",token) and tw.PlaybackState==Enum.PlaybackState.Playing do task.wait(0.03) end
        pcall(function() tw:Cancel() end)
        if FeatureTweens["Travel"]==tw then FeatureTweens["Travel"]=nil end
        setTweenNoclip(false); TravelBusy=false
        return true
    end

    local function autoSeaLabel()
        return "Auto: "..seaName(currentSea())
    end

    local IslandRow=makeSimpleDropdown(TravelPage,"🗺️ Island","Choose which island to go to.",1,getCurrentEntries,getCurrentEntries()[1],function(v)
        TravelIsland=v
    end)
    B.BantaiSetRowDescription(IslandRow,autoSeaLabel())

    makeAction(TravelPage,"🚀 Fly to Island","Flies you to the island you picked.",3,function()
        local sea=currentSea()
        local found=TravelIsland and findCurrentIsland(TravelIsland)
        if not found then
            local entries=getCurrentEntries()
            TravelIsland=entries[1]; found=TravelIsland and findCurrentIsland(TravelIsland)
        end
        if found then
            local item=found
            travelTween(findIslandCFrame(item[1],item[2]))
            B.BantaiSetRowDescription(IslandRow,"Auto: "..seaName(sea).." • "..item[1])
        end
    end)

    makeAction(TravelPage,"🌀 Portal to Island","Teleports you to the island you picked.",4,function()
        local sea=currentSea()
        local found=TravelIsland and findCurrentIsland(TravelIsland)
        if not found then
            local entries=getCurrentEntries(); TravelIsland=entries[1]; found=TravelIsland and findCurrentIsland(TravelIsland)
        end
        if found then
            local item=found
            local commF=B.BantaiGetCommF and B.BantaiGetCommF()
            if commF then
                local target=findIslandCFrame(item[1],item[2])
                pcall(function() commF:InvokeServer("requestEntrance",target) end)
                B.BantaiSetRowDescription(IslandRow,"Portal: "..seaName(sea).." • "..item[1])
            end
        end
    end)

    makeAction(TravelPage,"🔄 Refresh Island List","Reloads the islands for the sea you are in.",5,function()
        local sea=currentSea(); local entries=getCurrentEntries()
        TravelIsland=entries[1]
        B.BantaiSetRowDescription(IslandRow,"Auto: "..seaName(sea).." • "..tostring(TravelIsland or "none"))
    end)
    makeDescriptionRow(TravelPage,"🧭 Travel Status",autoSeaLabel(),7,function() end)

    -- Keep the label truthful if the player changes sea without reopening the tab.
    task.spawn(function()
        local lastSea=nil
        while scriptRunning do
            local sea=currentSea()
            if sea~=lastSea then
                lastSea=sea
                local entries=getCurrentEntries()
                TravelIsland=entries[1]
                B.BantaiSetRowDescription(IslandRow,"Auto: "..seaName(sea).." • "..tostring(TravelIsland or "none"))
            end
            task.wait(1)
        end
    end)
end

-----------------------------------
-- SEA EVENTS
-- Start Sea Event Farming: the boat sails in a straight line (same as Auto Find
-- Prehistoric) until a selected event is within range. Then the player gets off,
-- hovers over the event and kills it with RE/RegisterAttack + RE/RegisterHit,
-- gets back on the boat and keeps sailing.
-----------------------------------
do
    local seaEventTargets = {"Shark", "Piranha", "Fish Crew Member", "Terror Shark"}
    local selectedSeaEvents = {
        Shark = true,
        Piranha = false,
        ["Fish Crew Member"] = false,
        ["Terror Shark"] = false,
    }
    local seaEventFarm = false
    local seaEventMode = "Own Boat"
    local seaEventBoatName = "Guardian"
    local SEA_EVENT_RANGE = 1500
    local SEA_SAIL_TARGET = Vector3.new(-10000000, 31, 37016.25)
    local TikiBoatDockCF = CFrame.new(-16927.451, 9.086, 433.864)

    local function normName(v) return (tostring(v or ""):lower():gsub("[%s%p_]+", "")) end

    local function seaEventLabel()
        local picked = {}
        for _, name in ipairs(seaEventTargets) do
            if selectedSeaEvents[name] then picked[#picked + 1] = name end
        end
        return #picked > 0 and table.concat(picked, ", ") or "None"
    end

    local function isSelectedSeaEventModel(model)
        if not model or not model.Parent then return false end
        local modelName = normName(model.Name)
        for _, target in ipairs(seaEventTargets) do
            if selectedSeaEvents[target] then
                local wanted = normName(target)
                local isTerror = wanted == "shark" and modelName:find("terrorshark", 1, true)
                if not isTerror and (modelName == wanted or modelName:find(wanted, 1, true)) then
                    return true
                end
            end
        end
        return false
    end

    local function modelRoot(model)
        if not model or not model.Parent then return nil end
        return model:FindFirstChild("HumanoidRootPart")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function seaEventAlive(model)
        if not model or not model.Parent then return false end
        local health = model:FindFirstChild("Health")
        if health and health:IsA("ValueBase") and type(health.Value) == "number" and health.Value <= 0 then return false end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return false end
        if model:GetAttribute("Dead") == true or model:GetAttribute("Sunk") == true then return false end
        return true
    end

    local function findSeaEvent()
        local char = Player.Character
        local myRoot = char and char:FindFirstChild("HumanoidRootPart")
        if not myRoot then return nil end
        local best, bestDist
        for _, folderName in ipairs({"Enemies", "SeaBeasts"}) do
            local folder = Workspace:FindFirstChild(folderName)
            if folder then
                for _, model in ipairs(folder:GetChildren()) do
                    if model:IsA("Model") and isSelectedSeaEventModel(model) and seaEventAlive(model) then
                        local root = modelRoot(model)
                        if root then
                            local d = (root.Position - myRoot.Position).Magnitude
                            if d <= SEA_EVENT_RANGE and (not bestDist or d < bestDist) then
                                best, bestDist = model, d
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    local function boatOwnerMatches(boat)
        local owner = boat and boat:FindFirstChild("Owner", true)
        local value = owner and owner.Value
        return value == Player
            or tostring(value) == Player.Name
            or tostring(value) == tostring(Player.UserId)
    end

    local function getSeaEventBoat()
        local boats = Workspace:FindFirstChild("Boats")
        if not boats then return nil end
        local character = Player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local localBoat
        for _, boat in ipairs(boats:GetChildren()) do
            local seat = boat:FindFirstChildWhichIsA("VehicleSeat", true)
            if seat then
                if humanoid and seat.Occupant == humanoid then return boat end
                if seaEventMode == "Own Boat" and boatOwnerMatches(boat) then return boat end
                localBoat = localBoat or boat
            end
        end
        if seaEventMode == "Local Boat" then return localBoat end
        return nil
    end

    local function goToBoatDock()
        local char = Player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local dist = (root.Position - TikiBoatDockCF.Position).Magnitude
        if dist <= 30 then return end
        local token = beginFeatureTween("SeaEventDock")
        setTweenNoclip(true)
        local tw = TweenService:Create(root, TweenInfo.new(math.max(dist / math.max(speed, 1), 0.05), Enum.EasingStyle.Linear), {CFrame = TikiBoatDockCF})
        FeatureTweens["SeaEventDock"] = tw
        tw:Play()
        while isFeatureTweenCurrent("SeaEventDock", token) and seaEventFarm and tw.PlaybackState == Enum.PlaybackState.Playing do
            task.wait()
        end
        pcall(function() tw:Cancel() end)
        if FeatureTweens["SeaEventDock"] == tw then FeatureTweens["SeaEventDock"] = nil end
        setTweenNoclip(false)
    end

    local function buySeaEventBoat()
        local commF = B.BantaiGetCommF()
        if not commF then return nil end
        goToBoatDock()
        if not seaEventFarm then return nil end
        local ok = pcall(function() commF:InvokeServer("BuyBoat", seaEventBoatName) end)
        if not ok then return nil end
        local deadline = os.clock() + 5
        repeat
            task.wait(0.25)
            local boat = getSeaEventBoat()
            if boat then return boat end
        until os.clock() >= deadline
        return getSeaEventBoat()
    end

    local function sitInSeaEventBoat(boat)
        local character = Player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local seat = boat and boat:FindFirstChildWhichIsA("VehicleSeat", true)
        if not humanoid or not seat then return false end
        if seat.Occupant == humanoid then return true end
        pcall(function()
            humanoid.Sit = false
            character:PivotTo(seat.CFrame * CFrame.new(0, 2.5, 0))
        end)
        task.wait(0.15)
        pcall(function() seat:Sit(humanoid) end)
        task.wait(0.15)
        return seat.Occupant == humanoid
    end

    local boatCollideStates = {}
    local function setBoatNoclip(boat, enabled)
        pcall(function()
            if enabled and boat then
                boatCollideStates = {}
                for _, obj in ipairs(boat:GetDescendants()) do
                    if obj:IsA("BasePart") then
                        boatCollideStates[obj] = true
                        obj.CanCollide = false
                    end
                end
            else
                for part in pairs(boatCollideStates) do
                    if part and part.Parent then part.CanCollide = true end
                end
                boatCollideStates = {}
                if boat then
                    for _, obj in ipairs(boat:GetDescendants()) do
                        if obj:IsA("BasePart") then obj.CanCollide = true end
                    end
                end
            end
        end)
    end

    -- Straight-line sailing toward the far sea target (like Auto Find Prehistoric).
    -- Returns when an event is found, the farm is stopped, or the player leaves the seat.
    local function sailStraight(boat)
        local seat = boat:FindFirstChildWhichIsA("VehicleSeat", true)
        local char = Player.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not seat or not humanoid then return end
        pcall(function()
            seat.MaxSpeed = (B.BoatTweenSpeed or 250)
            seat.ThrottleFloat = 0
            seat.SteerFloat = 0
        end)
        local pos = boat:GetPivot().Position
        local sailY = SEA_SAIL_TARGET.Y + (B.BoatFlyHeight or 0)
        local start = Vector3.new(pos.X, sailY, pos.Z)
        local dir = (Vector3.new(SEA_SAIL_TARGET.X, sailY, SEA_SAIL_TARGET.Z) - start).Unit
        local current = start
        local lastCheck = 0
        setBoatNoclip(boat, true)
        pcall(function() boat:PivotTo(CFrame.lookAt(current, current + dir)) end)
        while scriptRunning and seaEventFarm do
            local dt = RunService.Heartbeat:Wait()
            if seat.Occupant ~= humanoid or not boat.Parent then break end
            current = current + dir * ((B.BoatTweenSpeed or 250) * dt)
            pcall(function()
                boat:PivotTo(CFrame.lookAt(current, current + dir))
                seat.AssemblyLinearVelocity = Vector3.zero
            end)
            if os.clock() - lastCheck >= 0.25 then
                lastCheck = os.clock()
                if findSeaEvent() then break end
            end
        end
        setBoatNoclip(boat, false)
    end

    -- Moves the player toward a CFrame at `speed` studs/sec.
    local function moveCharacterTo(targetCFrame)
        local char = Player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local dist = (root.Position - targetCFrame.Position).Magnitude
        if dist <= 60 then
            root.CFrame = targetCFrame
            root.AssemblyLinearVelocity = Vector3.zero
            return
        end
        local step = math.min(math.max(speed, 1) * 0.05, dist)
        root.CFrame = CFrame.new(root.Position + (targetCFrame.Position - root.Position).Unit * step)
        root.AssemblyLinearVelocity = Vector3.zero
    end

    -- Same pipeline the game's combat uses: the Net module wrapper for RegisterHit
    -- (it handles the hit validation) and the raw RE/RegisterAttack remote.
    local hitWrapper, hitRaw, attackRaw
    local function getAttackRemotes()
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        local net = modules and modules:FindFirstChild("Net")
        if not net then return nil end
        if not (attackRaw and attackRaw.Parent) then
            attackRaw = net:FindFirstChild("RE/RegisterAttack")
        end
        if not (hitRaw and hitRaw.Parent) then
            hitRaw = net:FindFirstChild("RE/RegisterHit")
        end
        if not hitWrapper then
            pcall(function()
                local netRequire = require(net)
                if type(netRequire) == "table" and type(netRequire.RemoteEvent) == "function" then
                    hitWrapper = netRequire:RemoteEvent("RegisterHit", true)
                end
            end)
        end
        return attackRaw, hitWrapper, hitRaw
    end

    local function attackSeaEvent(model, part)
        local attackRemote, wrapper, raw = getAttackRemotes()
        if not attackRemote then return end

        -- Target list: the event plus every other selected event close to us.
        local list = {{model, part}}
        local char = Player.Character
        local myRoot = char and char:FindFirstChild("HumanoidRootPart")
        for _, folderName in ipairs({"Enemies", "SeaBeasts"}) do
            local folder = Workspace:FindFirstChild(folderName)
            if folder and myRoot then
                for _, other in ipairs(folder:GetChildren()) do
                    if other ~= model and other:IsA("Model") and isSelectedSeaEventModel(other) and seaEventAlive(other) then
                        local r = modelRoot(other)
                        if r and (r.Position - myRoot.Position).Magnitude <= 500 then
                            list[#list + 1] = {other, other:FindFirstChild("Head") or r}
                        end
                    end
                end
            end
        end

        local hash = tostring(Player.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15)
        pcall(function() attackRemote:FireServer(0.3) end)
        if wrapper then
            pcall(function() wrapper:FireServer(part, list, nil, nil, hash) end)
        elseif raw then
            pcall(function() raw:FireServer(part, list, nil, nil, hash) end)
        end
    end

    local function fightSeaEvent(model)
        local char = Player.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Sit then
            humanoid.Sit = false
            task.wait(0.1)
        end
        setTweenNoclip(true)
        local lastEquip = 0
        while scriptRunning and seaEventFarm and seaEventAlive(model) do
            local root = modelRoot(model)
            if not root then break end
            local c = Player.Character
            if not c or not c:FindFirstChild("HumanoidRootPart") then break end

            if not c:FindFirstChildOfClass("Tool") and os.clock() - lastEquip > 1 then
                lastEquip = os.clock()
                pcall(equipFarmWeapon)
            end

            local height = 20
            if normName(model.Name):find("terrorshark", 1, true) then
                height = root.Position.Y > -3 and 250 or 40
            end
            moveCharacterTo(root.CFrame * CFrame.new(0, height, 0))

            local part = model:FindFirstChild("Head") or root
            attackSeaEvent(model, part)
            task.wait(0.05)
        end
        setTweenNoclip(false)
    end

    local function seaEventStep()
        local model = findSeaEvent()
        if model then
            fightSeaEvent(model)
            return
        end
        local boat = getSeaEventBoat()
        if not boat and seaEventMode == "Own Boat" then
            boat = buySeaEventBoat()
        end
        if not boat then return end
        if not sitInSeaEventBoat(boat) then return end
        sailStraight(boat)
    end

    addSection(SeaEventsPage, "Sea Event Farming", 1)

    makeDescriptionRow(SeaEventsPage, "🎯 Select Events: " .. seaEventLabel(), "Choose which sea events to hunt.", 2, function(row, desc)
        local arrow = label(row, "⌄", UDim2.new(0,30,1,0), UDim2.new(1,-45,0,0), 18, COLORS.Accent, Enum.Font.GothamBold)
        local list = Instance.new("ScrollingFrame")
        list.Name = "SeaEventTargetOptions"
        list.LayoutOrder = 3
        list.Size = UDim2.new(1,0,0,0)
        list.BackgroundColor3 = COLORS.Row
        list.BorderSizePixel = 0
        list.ScrollBarThickness = 3
        list.ScrollBarImageColor3 = COLORS.Accent
        list.AutomaticCanvasSize = Enum.AutomaticSize.Y
        list.Visible = false
        list.Parent = SeaEventsPage
        corner(list,6)
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0,3)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = list

        local function rebuild()
            for _, child in ipairs(list:GetChildren()) do
                if child:IsA("TextButton") then child:Destroy() end
            end
            for i, name in ipairs(seaEventTargets) do
                local option = Instance.new("TextButton")
                option.LayoutOrder = i
                option.Size = UDim2.new(1,0,0,36)
                option.BackgroundColor3 = selectedSeaEvents[name] and COLORS.Accent or COLORS.Content
                option.BackgroundTransparency = selectedSeaEvents[name] and 0.08 or 0.18
                option.Text = (selectedSeaEvents[name] and "✓  " or "○  ") .. name
                option.TextColor3 = COLORS.Text
                option.TextSize = 10
                option.Font = Enum.Font.GothamMedium
                option.TextXAlignment = Enum.TextXAlignment.Left
                option.AutoButtonColor = false
                option.Parent = list
                corner(option,5)
                option.Activated:Connect(function()
                    selectedSeaEvents[name] = not selectedSeaEvents[name]
                    row:FindFirstChildWhichIsA("TextLabel").Text = "🎯 Select Events: " .. seaEventLabel()
                    desc.Text = "Selected: " .. seaEventLabel()
                    rebuild()
                end)
            end
        end
        rebuild()
        local open = false
        row.Activated:Connect(function()
            open = not open
            list.Visible = open
            list.Size = open and UDim2.new(1,0,0,math.min(#seaEventTargets * 39 + 8, 210)) or UDim2.new(1,0,0,0)
            arrow.Text = open and "⌃" or "⌄"
        end)
    end)

    makeSimpleDropdown(SeaEventsPage, "🚤 Boat Mode", "Choose between your own boat or any boat that is already spawned.", 4,
        {"Own Boat", "Local Boat"}, seaEventMode, function(value)
            seaEventMode = value
        end)

    makeSimpleDropdown(SeaEventsPage, "⛵ Select Boat", "Choose which boat gets bought when you need one.", 5,
        {"Guardian","Dinghy","PirateSloop","PirateBrigade","PirateGrandBrigade","MarineSloop","MarineBrigade","MarineGrandBrigade","Beast Hunter"},
        seaEventBoatName, function(value)
            seaEventBoatName = value
        end)

    makeAction(SeaEventsPage, "🛒 Buy Boat", "Buys the boat you selected.", 6, function()
        task.spawn(function() pcall(buySeaEventBoat) end)
    end)

    makeInput(SeaEventsPage, "⚡ Boat Speed", "Sets how fast your boat sails (also used by Auto Find Prehistoric).", 7, B.BoatTweenSpeed,
        function(box, value)
            local num = tonumber(tostring(value):match("%d+%.?%d*"))
            if num and num > 0 then B.BoatTweenSpeed = num end
            box.Text = tostring(B.BoatTweenSpeed)
        end)

    makeInput(SeaEventsPage, "🪽 Boat Height", "Sets how high your boat flies (also used by Auto Find Prehistoric).", 8, B.BoatFlyHeight,
        function(box, value)
            local num = tonumber(tostring(value):match("%d+%.?%d*"))
            if num and num >= 0 then B.BoatFlyHeight = num end
            box.Text = tostring(B.BoatFlyHeight)
        end)

    makeToggle(SeaEventsPage, "🌊 Start Sea Event Farming", "Finds the sea events you picked and defeats them for you.", 9, false, function(enabled)
        seaEventFarm = enabled
        if not enabled then
            cancelFeatureTween("SeaEventDock")
            setBoatNoclip(nil, false)
            setTweenNoclip(false)
        end
    end)

    task.spawn(function()
        while scriptRunning do
            if seaEventFarm then
                local ok, err = pcall(seaEventStep)
                if not ok then
                    warn("[SeaEvents] " .. tostring(err))
                    setBoatNoclip(getSeaEventBoat(), false)
                end
            end
            task.wait(0.25)
        end
    end)
end

-- Put every normal control above the panels.
for _,obj in ipairs(MainFrame:GetDescendants()) do
    if obj:IsA("GuiObject") then
        obj.ZIndex = math.max(obj.ZIndex, 4)
    end
end
PageHolder.ZIndex = 1
BackgroundImage.ZIndex = 0

-- Keep the original default tab exactly as Bantai v3 intended.
showTab("Farm")
ScreenGui.Enabled = true

end
BantaiMainPart2()