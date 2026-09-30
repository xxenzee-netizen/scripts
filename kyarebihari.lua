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
local AutoV4Enabled = false
local AutoV3Enabled = false
local WalkWaterEnabled = false
local WaterPlatform = nil
local WaterHeartbeat = nil

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
-- UI is created at the end with the same RedzLib UI used by redz(1).txt.
-- The feature logic below remains unchanged.
local ScreenGui = {
    Destroy = function() end
}

local StatusLabel = {
    Text = ""
}

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

local function renderNotifierToggle(enabled)
end

local function toggleNotifier()
    NotifierEnabled = not NotifierEnabled
    renderNotifierToggle(NotifierEnabled)

    if NotifierEnabled then
        StatusLabel.Text = "Status: Searching for fruits..."

        if WorkspaceConnection then
            WorkspaceConnection:Disconnect()
            WorkspaceConnection = nil
        end

        WorkspaceConnection = Workspace.ChildAdded:Connect(function(child)
            if string.find(child.Name, "Fruit") or child.Name == "Fruit " then
                trackFruit(child)
            end
        end)

        scanForFruits()
        if CurrentFruit then
            trackFruit(CurrentFruit)
        else
            StatusLabel.Text = "Status: No fruit currently spawned"
        end
    else
        StatusLabel.Text = "Status: Disabled"
        if WorkspaceConnection then
            WorkspaceConnection:Disconnect()
            WorkspaceConnection = nil
        end
        CurrentFruit = nil
    end
end

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
-- LOCAL PLAYER
-----------------------------------
local OriginalWaterSize = nil
local WaterSizeConnection = nil

local function setWaterWalk(enabled)
    WalkWaterEnabled = enabled

    if WaterSizeConnection then
        WaterSizeConnection:Disconnect()
        WaterSizeConnection = nil
    end

    local map = Workspace:FindFirstChild("Map")
    local water = map and map:FindFirstChild("WaterBase-Plane")

    if not water or not water:IsA("BasePart") then
        return
    end

    if OriginalWaterSize == nil then
        OriginalWaterSize = water.Size
    end

    local enabledSize = Vector3.new(1000, 80, 1000)
    local disabledSize = Vector3.new(1000, 112, 1000)

    if enabled then
        pcall(function()
            water.Size = enabledSize
        end)

        WaterSizeConnection = game:GetService("RunService").Heartbeat:Connect(function()
            if not scriptRunning or not WalkWaterEnabled then
                return
            end

            local currentMap = Workspace:FindFirstChild("Map")
            local currentWater = currentMap and currentMap:FindFirstChild("WaterBase-Plane")

            if currentWater and currentWater:IsA("BasePart") then
                pcall(function()
                    currentWater.Size = enabledSize
                end)
            end
        end)
    else
        pcall(function()
            water.Size = disabledSize
        end)
        OriginalWaterSize = nil
    end
end


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
    local waterState = false
    while scriptRunning do
        if AutoV4Enabled then startAutoV4() end
        if AutoV3Enabled then startAutoV3() end

        if WalkWaterEnabled and not waterState then
            waterState = true
            setWaterWalk(true)
        elseif not WalkWaterEnabled and waterState then
            waterState = false
            setWaterWalk(false)
        end

        task.wait(0.2)
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

local function renderRaidToggle(enabled)
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

-----------------------------------
-- KEY BINDING / CLEANUP
-----------------------------------
local function pressJ()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.J, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.J, false, game)
    end)
end

local function cleanup()
    scriptRunning = false
    active = false
    AutoRaidActive = false

    pcall(function()
        StopRaidTween()
    end)

    if activeTween then
        pcall(function()
            activeTween:Cancel()
        end)
        activeTween = nil
    end

    if WorkspaceConnection then
        WorkspaceConnection:Disconnect()
        WorkspaceConnection = nil
    end

    pcall(removeSuspension)
    pcall(function()
        setWaterWalk(false)
    end)
end

-----------------------------------
-- REDZ UI (SAME UI LIBRARY AS redz(1).txt)
-- Structure is taken from the source UI; only branding/theme are changed.
-----------------------------------
local redzlib = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/farehamhz/RedzLib/main/RedzLib"
))()

redzlib:SetTheme("Purple")

local Window = redzlib:MakeWindow({
    Title = "AETHER HUB : Blox Fruits",
    SubTitle = "by NotThatAnik",
    SaveFolder = "Aether Hub | redz lib"
})

local StatusTab = Window:MakeTab({"Status/Server", "server"})
local FarmingTab = Window:MakeTab({"Farming", "home"})
local FarmSettingsTab = Window:MakeTab({"Farm Settings", "settings"})
local RaidsTab = Window:MakeTab({"Raids", "waves"})
local FruitsTab = Window:MakeTab({"Fruits", "cherry"})
local LocalPlayerTab = Window:MakeTab({"Local Player", "user"})

-- Status
-- Status/Server intentionally left empty for future additions.

-- Farming
FarmingTab:AddSection({"Farm Tool"})

local availableMobs = {}
do
    local seen = {}
    for _, obj in ipairs(getPotentialNPCs()) do
        if IsDamageableNPC(obj) and not seen[obj.Name] then
            seen[obj.Name] = true
            table.insert(availableMobs, obj.Name)
        end
    end
    table.sort(availableMobs)
end
table.insert(availableMobs, 1, "All Damageable")

FarmingTab:AddDropdown({
    Name = "Select Mob",
    Description = "Select the NPC to farm",
    Options = availableMobs,
    Default = "All Damageable",
    Callback = function(value)
        targetMobs = {}
        if value ~= "All Damageable" then
            targetMobs[value] = true
        end
    end
})

FarmingTab:AddDropdown({
    Name = "Attack Multiplier",
    Description = "Attack multiplier used by farming",
    Options = {"1x", "2x", "3x", "5x", "10x", "25x", "50x", "100x"},
    Default = "1x",
    Callback = function(value)
        local n = tonumber(tostring(value):match("%d+"))
        if n then
            attackMultiplier = math.clamp(n, 1, 100)
        end
    end
})

FarmingTab:AddToggle({
    Name = "Start Farm",
    Description = "Automatically farm the selected damageable NPC",
    Default = false,
    Callback = function(value)
        if active == value then return end

        active = value
        pressJ()

        if active then
            startLoop()
        else
            if activeTween then
                pcall(function()
                    activeTween:Cancel()
                end)
                activeTween = nil
            end
            removeSuspension()
        end
    end
})

FarmingTab:AddButton({
    Name = "Refresh Mob List",
    Description = "Refresh available NPC names",
    Callback = function()
        -- The target finder itself always reads live NPCs.
        -- This button intentionally does not alter the active farming loop.
    end
})

-- Farm Settings
FarmSettingsTab:AddSection({"Settings Farming"})

FarmSettingsTab:AddDropdown({
    Name = "Tween Speed",
    Description = "Auto Farm movement speed",
    Options = {"50", "100", "150", "200", "250", "300", "400", "500"},
    Default = tostring(speed),
    Callback = function(value)
        local n = tonumber(value)
        if n and n > 0 then
            speed = n
        end
    end
})

FarmSettingsTab:AddDropdown({
    Name = "Fly Height",
    Description = "Height above the target NPC",
    Options = {"5", "8", "10", "12", "15", "20", "25", "30"},
    Default = tostring(flyHeight),
    Callback = function(value)
        local n = tonumber(value)
        if n and n >= 0 then
            flyHeight = n
        end
    end
})

-- Raids
RaidsTab:AddSection({"Auto Raid"})

RaidsTab:AddToggle({
    Name = "Auto Pirate Raid",
    Description = "Kill raid NPCs, stay above them, then move to the next raid island",
    Default = false,
    Callback = function(value)
        if AutoRaidActive == value then return end

        AutoRaidActive = value
        if AutoRaidActive then
            StartAutoRaid()
        else
            StopRaidTween()
        end
    end
})

-- Fruits
FruitsTab:AddSection({"Fruit / Check Stock"})

FruitsTab:AddToggle({
    Name = "Fruit Notifier",
    Description = "Detect spawned fruits and track their distance",
    Default = false,
    Callback = function(value)
        if NotifierEnabled == value then return end

        NotifierEnabled = value

        if NotifierEnabled then
            if WorkspaceConnection then
                WorkspaceConnection:Disconnect()
                WorkspaceConnection = nil
            end

            WorkspaceConnection = Workspace.ChildAdded:Connect(function(child)
                if string.find(child.Name, "Fruit") or child.Name == "Fruit " then
                    trackFruit(child)
                end
            end)

            scanForFruits()
            if CurrentFruit then
                trackFruit(CurrentFruit)
            end
        else
            if WorkspaceConnection then
                WorkspaceConnection:Disconnect()
                WorkspaceConnection = nil
            end
            CurrentFruit = nil
        end
    end
})

FruitsTab:AddButton({
    Name = "Teleport to Spawned Fruit",
    Description = "Teleport to the currently detected fruit",
    Callback = function()
        if CurrentFruit then
            local handle = CurrentFruit:FindFirstChild("Handle")
                or CurrentFruit:FindFirstChildOfClass("Part")
                or CurrentFruit:FindFirstChildOfClass("MeshPart")

            if handle and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                if active then
                    active = false
                    if activeTween then
                        pcall(function()
                            activeTween:Cancel()
                        end)
                        activeTween = nil
                    end
                    removeSuspension()
                end

                Player.Character.HumanoidRootPart.CFrame =
                    CFrame.new(handle.Position + Vector3.new(0, 4, 0))
            end
        end
    end
})

-- Local Player
LocalPlayerTab:AddSection({"Local Player"})

LocalPlayerTab:AddToggle({
    Name = "Auto Turn On V4",
    Description = "Automatically activate V4 when Race Energy is available",
    Default = false,
    Callback = function(value)
        AutoV4Enabled = value
    end
})

LocalPlayerTab:AddToggle({
    Name = "Auto Turn On V3",
    Description = "Automatically activate V3",
    Default = false,
    Callback = function(value)
        AutoV3Enabled = value
    end
})

LocalPlayerTab:AddToggle({
    Name = "Walk on Water",
    Description = "Use the WaterBase-Plane method from redz(1).txt",
    Default = false,
    Callback = function(value)
        setWaterWalk(value)
    end
})

Window:SelectTab(FarmingTab)

local function setupDeathListener(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then
        hum.Died:Connect(function()
            AutoRaidActive = false
            StopRaidTween()
            removeSuspension()
            if WaterSizeConnection then
                WaterSizeConnection:Disconnect()
                WaterSizeConnection = nil
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
