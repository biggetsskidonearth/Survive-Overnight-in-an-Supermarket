-- ============================================================
-- Xeioa Hub / Break & Enter
-- Secure & Optimized Build
-- ============================================================

-- Anti-detection: Wrap everything in pcall & obfuscate service calls
local _G_ENV = getfenv and getfenv(0) or _G

-- Secure service getter
local function safeGetService(name)
    local ok, svc = pcall(function()
        return game:GetService(name)
    end)
    return ok and svc or nil
end

local Players         = safeGetService("Players")
local ReplicatedStorage = safeGetService("ReplicatedStorage")
local RunService      = safeGetService("RunService")
local TweenService    = safeGetService("TweenService")
local PathfindingService = safeGetService("PathfindingService")
local UserInputService = safeGetService("UserInputService")
local HttpService     = safeGetService("HttpService")
local CollectionService = safeGetService("CollectionService")
local CoreGui         = safeGetService("CoreGui")

-- Guard: Make sure we're the local player context
local LocalPlayer = Players and Players.LocalPlayer
if not LocalPlayer then
    warn("[Xeioa] Failed to get LocalPlayer. Aborting.")
    return
end

-- ============================================================
-- SECURE CACHE & STATE
-- ============================================================

local XeioaState = {
    Running        = true,
    ItemsFarmed    = 0,
    DropCount      = 0,
    PickupCount    = 0,
    Connections    = {},
    Threads        = {},
    Version        = "2.0.0",
    GameName       = "Break & Enter",
}

-- Safe disconnect all
local function cleanupAll()
    XeioaState.Running = false
    for _, conn in ipairs(XeioaState.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    for _, thread in ipairs(XeioaState.Threads) do
        pcall(function() task.cancel(thread) end)
    end
    XeioaState.Connections = {}
    XeioaState.Threads = {}
end

local function trackConnection(conn)
    table.insert(XeioaState.Connections, conn)
    return conn
end

local function trackThread(thread)
    table.insert(XeioaState.Threads, thread)
    return thread
end

-- ============================================================
-- LOAD UI LIBRARY (Obsidian)
-- ============================================================

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

local Library, ThemeManager, SaveManager

local loadOk, loadErr = pcall(function()
    Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
    ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
end)

if not loadOk or not Library then
    warn("[Xeioa] Failed to load UI Library: " .. tostring(loadErr))
    return
end

local Options = Library.Options
local Toggles = Library.Toggles

Library.ShowCustomCursor = true

-- ============================================================
-- CHARACTER MANAGEMENT (Secure)
-- ============================================================

local CharCache = {}

local function refreshCharCache()
    local char = LocalPlayer.Character
    if not char then return end
    CharCache.Character = char
    CharCache.HRP       = char:FindFirstChild("HumanoidRootPart")
    CharCache.Humanoid  = char:FindFirstChildOfClass("Humanoid")
    CharCache.Animator  = char:FindFirstChildOfClass("Animator")
        or (CharCache.Humanoid and CharCache.Humanoid:FindFirstChildOfClass("Animator"))
end

refreshCharCache()

trackConnection(LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    refreshCharCache()
end))

local function getHRP()
    if CharCache.HRP and CharCache.HRP.Parent then
        return CharCache.HRP
    end
    refreshCharCache()
    return CharCache.HRP
end

local function getHumanoid()
    if CharCache.Humanoid and CharCache.Humanoid.Parent then
        return CharCache.Humanoid
    end
    refreshCharCache()
    return CharCache.Humanoid
end

-- ============================================================
-- SECURE REMOTE WRAPPER
-- ============================================================

-- Cache remotes once
local RemoteCache = {}

local function getRemote(remoteName, remoteType)
    if RemoteCache[remoteName] then
        return RemoteCache[remoteName]
    end
    local ok, remote = pcall(function()
        return ReplicatedStorage
            :WaitForChild("Remotes", 10)
            :WaitForChild(remoteName, 10)
    end)
    if ok and remote then
        RemoteCache[remoteName] = remote
        return remote
    end
    return nil
end

local function secureFireServer(remoteName, ...)
    local args = {...}
    local remote = getRemote(remoteName)
    if not remote then
        warn("[Xeioa] Remote not found: " .. remoteName)
        return false, "RemoteNotFound"
    end
    local ok, err = pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(table.unpack(args))
        elseif remote:IsA("RemoteFunction") then
            return remote:InvokeServer(table.unpack(args))
        end
    end)
    if not ok then
        warn("[Xeioa] Remote error (" .. remoteName .. "): " .. tostring(err))
        return false, err
    end
    return true
end

local function secureInvokeServer(remoteName, ...)
    local args = {...}
    local remote = getRemote(remoteName)
    if not remote then
        warn("[Xeioa] RemoteFunction not found: " .. remoteName)
        return nil
    end
    local ok, result = pcall(function()
        return remote:InvokeServer(table.unpack(args))
    end)
    if not ok then
        warn("[Xeioa] Invoke error (" .. remoteName .. "): " .. tostring(result))
        return nil
    end
    return result
end

-- Character Event Wrapper
local function fireCharacterEvent(eventName, value)
    local char = LocalPlayer.Character
    if not char then return end
    local charEvent = char:FindFirstChild("CharacterEvent")
    if not charEvent then return end
    pcall(function()
        charEvent:FireServer(eventName, value)
    end)
end

-- ============================================================
-- GAME OBJECT REFERENCES (Safe)
-- ============================================================

local ObjectsFolder, ObjectTempStorage

local function initFolders()
    local ok1, f1 = pcall(function()
        return workspace
            :WaitForChild("Map", 10)
            :WaitForChild("Util", 10)
            :WaitForChild("Objects", 10)
    end)
    local ok2, f2 = pcall(function()
        return ReplicatedStorage:WaitForChild("ObjectTempStorage", 10)
    end)

    if ok1 and f1 then ObjectsFolder = f1 end
    if ok2 and f2 then ObjectTempStorage = f2 end
end

initFolders()

-- ============================================================
-- ITEM CATEGORY DEFINITIONS
-- ============================================================

local Categories = {
    Furniture = {
        "BallPit","Bathtub","Bed","BigCrate","BigFridge","BigMetal",
        "BlueChair","BlueCouch","BlueTrashCan","Carpet","Counter",
        "CouchK","EndTable","Fridge","GreenChair","GreenCouch",
        "GreenTrashCan","KidChair","KidTable","Mirror","OfficeChair",
        "Pallet","PaletteFloor","Plant","PlantLeafy","RedChair","RedCouch",
        "RoundTable","Shelf","Sink","SinkCounter","SmallCrate","SmallMetal",
        "Stair","Television","Toilet","ToiletPaper","TvTable","LaptopB",
        "BlueTrashCan","GreenTrashCan","BigFridge","BigMetal","BigCrate",
        "SmallCrate","SmallMetal",
    },
    Food = {
        "Burger","Cola","Pizza","Sandwich","Water","Soda",
        "Apple","Donut","Cake","Cookie","Chips","Juice",
        "Coffee","Milk","Bread","Cheese","Hotdog","Fries",
        "Taco","Popcorn","IceCream","Candy","Ramen","Soup",
    },
    Keys = {
        "RedCube","BlueCube","GreenCube","YellowCube","PurpleCube",
        "OrangeCube","PinkCube","WhiteCube","BlackCube",
    },
    Misc = {
        "BasicFlashlight_Standard","Flashlight","Candle","Lantern",
        "Radio","Phone","Camera","Binoculars","Compass",
        "Key","Lockpick","Crowbar","Hammer","Screwdriver",
    },
    Decorations = {
        "ChristmasLight","Domino","Fence","GroundLight","Ladder",
        "LeftArch","LightUpPencil","LightVariant1","Model","Part",
        "Picture","Pillar","RightArch","RoofFill","Roofill",
        "ShedRoof","ShedWall","StreamingA","TopArch","ToyBlock",
        "ToyCircle","ToyWedge","WallLight","WeirdLight","WoodBark",
        "fire","light","GroundLight","WeirdLight","WallLight",
    },
}

-- Build lookup sets
local Sets = {}
for catName, catList in pairs(Categories) do
    Sets[catName] = {}
    for _, name in ipairs(catList) do
        Sets[catName][name] = true
    end
end

local function getItemCategory(name)
    for catName, set in pairs(Sets) do
        if set[name] then return catName end
    end
    return nil
end

-- ============================================================
-- OBJECT SCANNING
-- ============================================================

local function scanObjects(folder, filterSet, excludeSet)
    local results = {}
    local seen = {}
    if not folder then return results end
    for _, obj in ipairs(folder:GetChildren()) do
        local name = obj.Name
        if not seen[name] then
            local pass = true
            if filterSet  and not filterSet[name]  then pass = false end
            if excludeSet and excludeSet[name]      then pass = false end
            if pass then
                seen[name] = true
                table.insert(results, name)
            end
        end
    end
    table.sort(results)
    return results
end

local function getAllPickupableNames()
    local names = {}
    local seen  = {}

    -- From ObjectTempStorage
    if ObjectTempStorage then
        for _, obj in ipairs(ObjectTempStorage:GetChildren()) do
            if not Sets.Decorations[obj.Name] and not seen[obj.Name] then
                seen[obj.Name] = true
                table.insert(names, obj.Name)
            end
        end
    end

    -- From Objects folder
    if ObjectsFolder then
        for _, obj in ipairs(ObjectsFolder:GetChildren()) do
            local name = obj.Name
            if not Sets.Decorations[name] and not seen[name] then
                local hasPickup = obj:FindFirstChild("PickupPP", true)
                    or obj:FindFirstChild("Main")
                    or obj:FindFirstChildWhichIsA("BasePart")
                if hasPickup then
                    seen[name] = true
                    table.insert(names, name)
                end
            end
        end
    end

    table.sort(names)
    if #names == 0 then table.insert(names, "None") end
    return names
end

local function getFurnitureNames()
    return scanObjects(ObjectTempStorage, nil, Sets.Decorations)
end

-- ============================================================
-- MOVEMENT UTILITIES (Secure Tween / Pathfind)
-- ============================================================

local MovementBusy = false

local function safeTweenTo(position, speed)
    if MovementBusy then return false end
    local hrp = getHRP()
    if not hrp then return false end

    speed = math.clamp(speed or 64, 1, 500)
    local dist = (hrp.Position - position).Magnitude
    local tweenTime = math.max(dist / speed, 0.05)

    MovementBusy = true
    local ok, err = pcall(function()
        -- Bypass network ownership issues by setting CFrame directly in steps
        local steps = math.ceil(tweenTime * 30)
        local startCF = hrp.CFrame
        local endCF   = CFrame.new(position)
        for i = 1, steps do
            if not XeioaState.Running then break end
            hrp.CFrame = startCF:Lerp(endCF, i / steps)
            task.wait(1 / 60)
        end
    end)
    MovementBusy = false
    if not ok then warn("[Xeioa] TweenTo error: " .. tostring(err)) end
    return ok
end

local function safePathfindTo(targetPos, speed)
    local hrp = getHRP()
    local hum = getHumanoid()
    if not hrp or not hum then return false end

    local path = PathfindingService:CreatePath({
        AgentRadius   = 2,
        AgentHeight   = 5,
        AgentCanJump  = true,
        AgentCanClimb = true,
        Costs         = { Water = 100 },
    })

    local ok, err = pcall(function()
        path:ComputeAsync(hrp.Position, targetPos)
    end)

    if not ok or path.Status ~= Enum.PathStatus.Success then
        -- Fallback: tween
        return safeTweenTo(targetPos, speed)
    end

    local waypoints = path:GetWaypoints()
    for i, wp in ipairs(waypoints) do
        if not XeioaState.Running then return false end
        if not hrp.Parent or not hum.Parent then return false end
        if wp.Action == Enum.PathWaypointAction.Jump then
            hum.Jump = true
        end
        hum:MoveTo(wp.Position)
        local arrived = hum.MoveToFinished:Wait(5)
        if not arrived then
            -- Retry with tween if stuck
            safeTweenTo(targetPos, speed or 32)
            return true
        end
    end
    return true
end

-- ============================================================
-- PROXIMITY PROMPT SECURE FIRE
-- ============================================================

local function secureFireProximityPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    local ok = pcall(function()
        -- Extend range temporarily
        local oldDist = prompt.MaxActivationDistance
        local oldLOS  = prompt.RequiresLineOfSight
        prompt.MaxActivationDistance = 9e9
        prompt.RequiresLineOfSight   = false

        -- Try built-in executor function
        if fireproximityprompt then
            fireproximityprompt(prompt)
        else
            -- Manual trigger
            prompt:InputHoldBegin()
            task.wait(prompt.HoldDuration + 0.05)
            prompt:InputHoldEnd()
        end

        -- Restore
        task.delay(0.5, function()
            pcall(function()
                prompt.MaxActivationDistance = oldDist
                prompt.RequiresLineOfSight   = oldLOS
            end)
        end)
    end)
    return ok
end

local function findProximityPrompt(model)
    if not model then return nil end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
    return nil
end

-- ============================================================
-- PICKUP / DROP CORE FUNCTIONS
-- ============================================================

local function pickupFurniture(name)
    local obj
    -- Priority: ObjectTempStorage → ObjectsFolder
    if ObjectTempStorage then
        obj = ObjectTempStorage:FindFirstChild(name)
    end
    if not obj and ObjectsFolder then
        obj = ObjectsFolder:FindFirstChild(name)
    end
    if not obj then return false, "NotFound" end

    local result = secureInvokeServer("RequestPickup", obj)
    if result ~= false then
        XeioaState.PickupCount += 1
        return true
    end
    return false, "InvokeFailed"
end

local function pickupItem(name)
    local sources = {
        LocalPlayer.Character,
        LocalPlayer:FindFirstChild("Backpack"),
    }
    for _, src in ipairs(sources) do
        if src then
            local item = src:FindFirstChild(name)
                or src:FindFirstChild(name .. " ") -- handle trailing space
            if item then
                local ok = secureFireServer("RequestPickupItem", item)
                if ok then
                    XeioaState.PickupCount += 1
                    return true
                end
            end
        end
    end
    return false, "ItemNotFound"
end

local function dropAtHRP()
    local hrp = getHRP()
    if not hrp then return false end
    local cf = hrp.CFrame
    local result = secureInvokeServer("DropObject", cf)
    XeioaState.DropCount += 1
    return true
end

local function bringItem(name, category)
    local ok, err
    if category == "Furniture" then
        ok, err = pickupFurniture(name)
    else
        ok, err = pickupItem(name)
    end

    if ok then
        task.wait(0.25)
        dropAtHRP()
        XeioaState.ItemsFarmed += 1
        return true
    end
    return false, err
end

local function setSprinting(state)
    fireCharacterEvent("SprintingAndMoving", state)
end

-- ============================================================
-- UI WINDOW
-- ============================================================

local Window = Library:CreateWindow({
    Title  = "Xeioa Hub",
    Footer = "v" .. XeioaState.Version .. "  |  " .. XeioaState.GameName,
    Icon   = 95816097006870,
    NotifySide      = "Right",
    ShowCustomCursor = true,
    AutoShow = true,
})

local Tabs = {
    Main      = Window:AddTab("Main",      "home"),
    Furniture = Window:AddTab("Furniture", "box"),
    Items     = Window:AddTab("Items",     "package"),
    AutoFarm  = Window:AddTab("AutoFarm",  "zap"),
    Teleport  = Window:AddTab("Teleport",  "map-pin"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- ============================================================
-- ██ MAIN TAB ██
-- ============================================================

local MainLeft  = Tabs.Main:AddLeftGroupbox("Player Controls")
local MainRight = Tabs.Main:AddRightGroupbox("Info & Status")

-- Sprint
MainLeft:AddToggle("SprintToggle", {
    Text    = "Auto Sprint",
    Default = false,
    Tooltip = "Automatically notify server of sprinting state",
    Callback = function(v) setSprinting(v) end,
})

-- Walk speed
MainLeft:AddSlider("WalkSpeed", {
    Text      = "Walk Speed",
    Default   = 16,
    Min       = 0,
    Max       = 250,
    Rounding  = 0,
    Tooltip   = "Set character walk speed",
    Callback  = function(v)
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = v end
    end,
})

-- Jump Power
MainLeft:AddSlider("JumpPower", {
    Text     = "Jump Power",
    Default  = 50,
    Min      = 0,
    Max      = 350,
    Rounding = 0,
    Tooltip  = "Set character jump power",
    Callback = function(v)
        local hum = getHumanoid()
        if hum then hum.JumpPower = v end
    end,
})

MainLeft:AddDivider()

-- NoClip
MainLeft:AddToggle("NoClipToggle", {
    Text    = "NoClip",
    Default = false,
    Tooltip = "Disable collision for character parts",
    Risky   = true,
})

-- Infinite Jump
MainLeft:AddToggle("InfJump", {
    Text    = "Infinite Jump",
    Default = false,
    Tooltip = "Allow jumping while airborne",
})

trackConnection(UserInputService.JumpRequest:Connect(function()
    if Toggles.InfJump and Toggles.InfJump.Value then
        local hum = getHumanoid()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

-- G key: instant drop
MainLeft:AddLabel("Press [G] to instantly drop held item", true)

-- Auto Start
MainLeft:AddDivider()
local AutoStartBox = Tabs.Main:AddLeftGroupbox("Auto Start")

AutoStartBox:AddToggle("AutoStartLoop", {
    Text    = "Auto Start Loop",
    Default = false,
    Tooltip = "Continuously pathfind to start & trigger interaction",
})

AutoStartBox:AddButton({
    Text    = "Go to Start Position",
    Tooltip = "Pathfind to (312, 37, -458) & trigger proximity prompts",
    Func    = function()
        Library:Notify({ Title = "Navigation", Description = "Pathfinding to start...", Time = 3 })

        local target = Vector3.new(312, 37, -458)
        local reached = safePathfindTo(target, 32)

        if reached then
            task.wait(0.3)
            -- Fire all nearby proximity prompts
            local hrp = getHRP()
            if hrp then
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if obj:IsA("ProximityPrompt") and obj.Enabled then
                        local part = obj.Parent
                        if part and part:IsA("BasePart") then
                            if (hrp.Position - part.Position).Magnitude <= 20 then
                                secureFireProximityPrompt(obj)
                                task.wait(0.05)
                            end
                        end
                    end
                end
            end

            task.wait(3)
            Library:Notify({ Title = "Navigation", Description = "Auto start complete!", Time = 3 })
        else
            Library:Notify({ Title = "Navigation", Description = "Could not reach start!", Time = 3 })
        end
    end,
})

-- Auto start loop
trackThread(task.spawn(function()
    while XeioaState.Running do
        task.wait(2)
        if Toggles.AutoStartLoop and Toggles.AutoStartLoop.Value then
            local target = Vector3.new(312, 37, -458)
            safePathfindTo(target, 32)
            task.wait(0.3)
            local hrp = getHRP()
            if hrp then
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if obj:IsA("ProximityPrompt") and obj.Enabled then
                        local part = obj.Parent
                        if part and part:IsA("BasePart") then
                            if (hrp.Position - part.Position).Magnitude <= 20 then
                                secureFireProximityPrompt(obj)
                                task.wait(0.05)
                            end
                        end
                    end
                end
            end
            task.wait(3)
        end
    end
end))

-- NoClip loop
trackThread(task.spawn(function()
    while XeioaState.Running do
        task.wait(1 / 60)
        if Toggles.NoClipToggle and Toggles.NoClipToggle.Value then
            local char = LocalPlayer.Character
            if char then
                for _, p in ipairs(char:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.CanCollide = false
                    end
                end
            end
        end
    end
end))

-- Info Panel
MainRight:AddLabel("Xeioa Hub  |  " .. XeioaState.GameName, true)
MainRight:AddDivider()
MainRight:AddLabel("Tabs:\n• Furniture — pickup/bring objects\n• Items — food / keys / misc\n• AutoFarm — automated loops\n• Teleport — quick travel\n\n[G] = Instant drop held item\n[RightShift] = Toggle menu", true)

MainRight:AddDivider()
MainRight:AddLabel("Session Stats", false, "SessionStatsLabel")

-- Update stats every 2s
trackThread(task.spawn(function()
    while XeioaState.Running do
        task.wait(2)
        pcall(function()
            if Options.SessionStatsLabel then
                Options.SessionStatsLabel:SetText(
                    string.format(
                        "Picked Up: %d\nDropped: %d\nFarmed: %d",
                        XeioaState.PickupCount,
                        XeioaState.DropCount,
                        XeioaState.ItemsFarmed
                    )
                )
            end
        end)
    end
end))

-- ============================================================
-- ██ FURNITURE TAB ██
-- ============================================================

local FurnitureLeft  = Tabs.Furniture:AddLeftGroupbox("Pickup")
local FurnitureRight = Tabs.Furniture:AddRightGroupbox("Bring")

local function buildFurnitureList()
    local list = getFurnitureNames()
    if #list == 0 then list = Categories.Furniture end
    table.sort(list)
    return list
end

local furnitureList = buildFurnitureList()

-- Pickup side
FurnitureLeft:AddDropdown("FurnitureSelect", {
    Values     = furnitureList,
    Default    = 1,
    Multi      = false,
    Text       = "Select Furniture",
    Searchable = true,
    Tooltip    = "Furniture items from ObjectTempStorage & Map",
})

FurnitureLeft:AddButton({
    Text    = "Refresh List",
    Tooltip = "Re-scan game for available furniture",
    Func    = function()
        local newList = buildFurnitureList()
        Options.FurnitureSelect:SetValues(newList)
        if #newList > 0 then Options.FurnitureSelect:SetValue(newList[1]) end
        Library:Notify({ Title = "Furniture", Description = "Found " .. #newList .. " items", Time = 2 })
    end,
})

FurnitureLeft:AddButton({
    Text    = "Pickup Selected",
    Tooltip = "Send RequestPickup for the selected furniture",
    Func    = function()
        local sel = Options.FurnitureSelect.Value
        if not sel or sel == "None" then return end
        local ok, err = pickupFurniture(sel)
        Library:Notify({
            Title       = "Furniture",
            Description = ok and ("✔ Picked up " .. sel) or ("✘ Failed: " .. tostring(err)),
            Time        = 3,
        })
    end,
})

FurnitureLeft:AddButton({
    Text    = "Drop at Position",
    Tooltip = "Drop currently held item at your HRP position",
    Func    = function()
        dropAtHRP()
        Library:Notify({ Title = "Furniture", Description = "Dropped at your position", Time = 2 })
    end,
})

FurnitureLeft:AddDivider()

-- Quick-pickup all from ObjectTempStorage
FurnitureLeft:AddButton({
    Text        = "Pickup ALL from Storage",
    DoubleClick = true,
    Tooltip     = "Double-click: picks up everything in ObjectTempStorage",
    Risky       = true,
    Func        = function()
        if not ObjectTempStorage then return end
        local count = 0
        for _, obj in ipairs(ObjectTempStorage:GetChildren()) do
            if not Sets.Decorations[obj.Name] then
                pcall(function()
                    secureInvokeServer("RequestPickup", obj)
                    task.wait(0.15)
                    dropAtHRP()
                    task.wait(0.2)
                    count += 1
                end)
            end
        end
        Library:Notify({ Title = "Pickup ALL", Description = "Done! (" .. count .. " items)", Time = 3 })
    end,
})

-- Bring side
FurnitureRight:AddDropdown("FurnitureBringSelect", {
    Values     = furnitureList,
    Default    = 1,
    Multi      = false,
    Text       = "Select Furniture to Bring",
    Searchable = true,
})

FurnitureRight:AddButton({
    Text    = "Bring Once",
    Tooltip = "Pickup + drop at your position (no teleport)",
    Func    = function()
        local sel = Options.FurnitureBringSelect.Value
        if not sel or sel == "None" then return end
        local ok = bringItem(sel, "Furniture")
        Library:Notify({
            Title       = "Bring",
            Description = ok and ("✔ Brought " .. sel) or ("✘ Could not bring " .. sel),
            Time        = 3,
        })
    end,
})

FurnitureRight:AddToggle("FurnitureBringLoop", {
    Text    = "Auto Bring Loop",
    Default = false,
    Tooltip = "Continuously bring selected furniture item",
})

FurnitureRight:AddSlider("FurnitureBringDelay", {
    Text     = "Loop Delay (s)",
    Default  = 1,
    Min      = 0.2,
    Max      = 10,
    Rounding = 1,
})

FurnitureRight:AddDivider()

FurnitureRight:AddButton({
    Text        = "Bring ALL Map Furniture",
    DoubleClick = true,
    Risky       = true,
    Tooltip     = "Double-click: iterates all Objects folder furniture",
    Func        = function()
        if not ObjectsFolder then return end
        local count = 0
        for _, obj in ipairs(ObjectsFolder:GetChildren()) do
            if not XeioaState.Running then break end
            if Sets.Furniture[obj.Name] then
                pcall(function()
                    secureInvokeServer("RequestPickup", obj)
                    task.wait(0.2)
                    dropAtHRP()
                    task.wait(0.25)
                    count += 1
                end)
            end
        end
        Library:Notify({ Title = "Bring ALL", Description = "Done! (" .. count .. " items)", Time = 3 })
    end,
})

-- Furniture loop thread
trackThread(task.spawn(function()
    while XeioaState.Running do
        task.wait(0.5)
        if Toggles.FurnitureBringLoop and Toggles.FurnitureBringLoop.Value then
            local delay = Options.FurnitureBringDelay and Options.FurnitureBringDelay.Value or 1
            local sel   = Options.FurnitureBringSelect.Value
            if sel and sel ~= "None" then
                bringItem(sel, "Furniture")
            end
            task.wait(math.max(delay - 0.5, 0.1))
        end
    end
end))

-- ============================================================
-- ██ ITEMS TAB ██
-- ============================================================

local FoodBox = Tabs.Items:AddLeftGroupbox("Food")
local KeysBox = Tabs.Items:AddRightGroupbox("Keys")
local MiscBox = Tabs.Items:AddLeftGroupbox("Misc")

-- ── Food ──────────────────────────────────────────────────
FoodBox:AddDropdown("FoodSelect", {
    Values     = Categories.Food,
    Default    = 1,
    Multi      = false,
    Text       = "Select Food",
    Searchable = true,
})

FoodBox:AddButton({
    Text = "Pickup Selected",
    Func = function()
        local sel = Options.FoodSelect.Value
        if not sel then return end
        local ok, err = pickupItem(sel)
        Library:Notify({
            Title       = "Food",
            Description = ok and "✔ Picked up " .. sel or "✘ Failed: " .. tostring(err),
            Time        = 3,
        })
    end,
})

FoodBox:AddButton({
    Text = "Bring to Position",
    Func = function()
        local sel = Options.FoodSelect.Value
        if not sel then return end
        bringItem(sel, "Food")
        Library:Notify({ Title = "Food", Description = "Brought " .. sel, Time = 2 })
    end,
})

FoodBox:AddToggle("FoodLoop", {
    Text    = "Auto Bring Loop",
    Default = false,
})

FoodBox:AddSlider("FoodLoopDelay", {
    Text = "Loop Delay (s)", Default = 1, Min = 0.2, Max = 10, Rounding = 1,
})

-- ── Keys ──────────────────────────────────────────────────
KeysBox:AddDropdown("KeySelect", {
    Values     = Categories.Keys,
    Default    = 1,
    Multi      = false,
    Text       = "Select Key",
    Searchable = true,
})

KeysBox:AddButton({
    Text = "Pickup Selected Key",
    Func = function()
        local sel = Options.KeySelect.Value
        if not sel then return end
        local ok, err = pickupItem(sel)
        Library:Notify({
            Title       = "Keys",
            Description = ok and "✔ Picked up " .. sel or "✘ " .. tostring(err),
            Time        = 3,
        })
    end,
})

KeysBox:AddButton({
    Text = "Bring Key",
    Func = function()
        local sel = Options.KeySelect.Value
        if not sel then return end
        bringItem(sel, "Key")
        Library:Notify({ Title = "Keys", Description = "Brought " .. sel, Time = 2 })
    end,
})

KeysBox:AddToggle("KeyLoop", {
    Text    = "Auto Bring Loop",
    Default = false,
})

KeysBox:AddSlider("KeyLoopDelay", {
    Text = "Loop Delay (s)", Default = 1, Min = 0.2, Max = 10, Rounding = 1,
})

-- ── Misc ──────────────────────────────────────────────────
MiscBox:AddDropdown("MiscSelect", {
    Values     = Categories.Misc,
    Default    = 1,
    Multi      = false,
    Text       = "Select Misc Item",
    Searchable = true,
})

MiscBox:AddButton({
    Text = "Pickup Selected",
    Func = function()
        local sel = Options.MiscSelect.Value
        if not sel then return end
        local ok, err = pickupItem(sel)
        Library:Notify({
            Title       = "Misc",
            Description = ok and "✔ " .. sel or "✘ " .. tostring(err),
            Time        = 3,
        })
    end,
})

MiscBox:AddButton({
    Text = "Bring to Position",
    Func = function()
        local sel = Options.MiscSelect.Value
        if not sel then return end
        bringItem(sel, "Misc")
        Library:Notify({ Title = "Misc", Description = "Brought " .. sel, Time = 2 })
    end,
})

MiscBox:AddToggle("MiscLoop", {
    Text    = "Auto Bring Loop",
    Default = false,
})

MiscBox:AddSlider("MiscLoopDelay", {
    Text = "Loop Delay (s)", Default = 1, Min = 0.2, Max = 10, Rounding = 1,
})

-- Item loops
trackThread(task.spawn(function()
    while XeioaState.Running do
        task.wait(0.5)

        -- Food
        if Toggles.FoodLoop and Toggles.FoodLoop.Value then
            local delay = Options.FoodLoopDelay and Options.FoodLoopDelay.Value or 1
            bringItem(Options.FoodSelect.Value, "Food")
            task.wait(math.max(delay - 0.5, 0.1))
        end

        -- Keys
        if Toggles.KeyLoop and Toggles.KeyLoop.Value then
            local delay = Options.KeyLoopDelay and Options.KeyLoopDelay.Value or 1
            bringItem(Options.KeySelect.Value, "Key")
            task.wait(math.max(delay - 0.5, 0.1))
        end

        -- Misc
        if Toggles.MiscLoop and Toggles.MiscLoop.Value then
            local delay = Options.MiscLoopDelay and Options.MiscLoopDelay.Value or 1
            bringItem(Options.MiscSelect.Value, "Misc")
            task.wait(math.max(delay - 0.5, 0.1))
        end
    end
end))

-- ============================================================
-- ██ AUTO FARM TAB ██
-- ============================================================

local AFLeft  = Tabs.AutoFarm:AddLeftGroupbox("Farm Settings")
local AFRight = Tabs.AutoFarm:AddRightGroupbox("Farm Controls")

AFLeft:AddToggle("AutoFarmEnabled", {
    Text  = "Enable Auto Farm",
    Default = false,
    Risky = true,
    Tooltip = "Master toggle — runs all enabled farm categories",
})

AFLeft:AddToggle("AFfurniture", {
    Text = "Farm Furniture", Default = true,
})
AFLeft:AddToggle("AFfood", {
    Text = "Farm Food", Default = false,
})
AFLeft:AddToggle("AFkeys", {
    Text = "Farm Keys", Default = false,
})
AFLeft:AddToggle("AFmisc", {
    Text = "Farm Misc", Default = false,
})

AFLeft:AddDivider()

AFLeft:AddSlider("AFDelay", {
    Text     = "Delay Between Items (s)",
    Default  = 0.4,
    Min      = 0.05,
    Max      = 5,
    Rounding = 2,
})

AFLeft:AddToggle("AFAutoDrop", {
    Text    = "Auto Drop After Pickup",
    Default = true,
    Tooltip = "Drop item at HRP after each pickup",
})

AFLeft:AddToggle("AFInstantPP", {
    Text    = "Instant Proximity Prompts",
    Default = false,
    Tooltip = "Auto-fire all nearby proximity prompts",
})

AFLeft:AddSlider("AFPPRange", {
    Text     = "Proximity Prompt Range",
    Default  = 30,
    Min      = 5,
    Max      = 200,
    Rounding = 0,
})

-- Stats panel
AFRight:AddLabel("Farm Stats", false, "AFStatsLabel")

AFRight:AddDivider()

AFRight:AddButton({
    Text    = "Trigger Nearby Prompts",
    Tooltip = "Fire all proximity prompts within range once",
    Func    = function()
        local hrp   = getHRP()
        local range = Options.AFPPRange and Options.AFPPRange.Value or 30
        local count = 0
        if not hrp then return end
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") and obj.Enabled then
                local part = obj.Parent
                if part and part:IsA("BasePart") then
                    if (hrp.Position - part.Position).Magnitude <= range then
                        secureFireProximityPrompt(obj)
                        count += 1
                        task.wait(0.05)
                    end
                end
            end
        end
        Library:Notify({ Title = "Prompts", Description = "Triggered " .. count .. " prompts", Time = 3 })
    end,
})

AFRight:AddButton({
    Text        = "Bring ALL Storage Items",
    DoubleClick = true,
    Risky       = true,
    Func        = function()
        if not ObjectTempStorage then return end
        local count = 0
        for _, obj in ipairs(ObjectTempStorage:GetChildren()) do
            if not Sets.Decorations[obj.Name] then
                pcall(function()
                    secureInvokeServer("RequestPickup", obj)
                    task.wait(0.15)
                    dropAtHRP()
                    task.wait(0.2)
                    count += 1
                end)
            end
        end
        Library:Notify({ Title = "Bring ALL", Description = count .. " items done", Time = 3 })
    end,
})

AFRight:AddButton({
    Text        = "Bring ALL Map Objects",
    DoubleClick = true,
    Risky       = true,
    Func        = function()
        if not ObjectsFolder then return end
        local count = 0
        for _, obj in ipairs(ObjectsFolder:GetChildren()) do
            if not Sets.Decorations[obj.Name] then
                local pp = findProximityPrompt(obj)
                if pp or obj:FindFirstChild("Main") then
                    pcall(function()
                        secureInvokeServer("RequestPickup", obj)
                        task.wait(0.2)
                        dropAtHRP()
                        task.wait(0.25)
                        count += 1
                    end)
                end
            end
        end
        Library:Notify({ Title = "Bring ALL Map", Description = count .. " items done", Time = 3 })
    end,
})

-- Auto Farm main loop
trackThread(task.spawn(function()
    while XeioaState.Running do
        task.wait(0.5)

        -- Update stats label
        pcall(function()
            if Options.AFStatsLabel then
                Options.AFStatsLabel:SetText(
                    "Farmed: " .. XeioaState.ItemsFarmed ..
                    "\nPickups: " .. XeioaState.PickupCount ..
                    "\nDrops: " .. XeioaState.DropCount
                )
            end
        end)

        if not (Toggles.AutoFarmEnabled and Toggles.AutoFarmEnabled.Value) then
            task.wait(0.5)
            continue
        end

        local delay    = Options.AFDelay and Options.AFDelay.Value or 0.4
        local autoDrop = Toggles.AFAutoDrop and Toggles.AFAutoDrop.Value

        -- Furniture
        if Toggles.AFfurniture and Toggles.AFfurniture.Value and ObjectTempStorage then
            for _, obj in ipairs(ObjectTempStorage:GetChildren()) do
                if not (Toggles.AutoFarmEnabled and Toggles.AutoFarmEnabled.Value) then break end
                if not Sets.Decorations[obj.Name] then
                    pcall(function()
                        secureInvokeServer("RequestPickup", obj)
                        task.wait(0.15)
                        if autoDrop then dropAtHRP() end
                        XeioaState.ItemsFarmed += 1
                    end)
                    task.wait(delay)
                end
            end
        end

        -- Food
        if Toggles.AFfood and Toggles.AFfood.Value then
            local char = LocalPlayer.Character
            local bp   = LocalPlayer:FindFirstChild("Backpack")
            for _, foodName in ipairs(Categories.Food) do
                if not (Toggles.AutoFarmEnabled and Toggles.AutoFarmEnabled.Value) then break end
                local item = (char and char:FindFirstChild(foodName))
                    or (bp and bp:FindFirstChild(foodName))
                if item then
                    pcall(function()
                        secureFireServer("RequestPickupItem", item)
                        task.wait(0.15)
                        if autoDrop then dropAtHRP() end
                        XeioaState.ItemsFarmed += 1
                    end)
                    task.wait(delay)
                end
            end
        end

        -- Keys
        if Toggles.AFkeys and Toggles.AFkeys.Value then
            local char = LocalPlayer.Character
            for _, keyName in ipairs(Categories.Keys) do
                if not (Toggles.AutoFarmEnabled and Toggles.AutoFarmEnabled.Value) then break end
                local item = char and char:FindFirstChild(keyName)
                if item then
                    pcall(function()
                        secureFireServer("RequestPickupItem", item)
                        task.wait(0.15)
                        if autoDrop then dropAtHRP() end
                        XeioaState.ItemsFarmed += 1
                    end)
                    task.wait(delay)
                end
            end
        end

        -- Misc
        if Toggles.AFmisc and Toggles.AFmisc.Value then
            local char = LocalPlayer.Character
            for _, miscName in ipairs(Categories.Misc) do
                if not (Toggles.AutoFarmEnabled and Toggles.AutoFarmEnabled.Value) then break end
                local item = char and char:FindFirstChild(miscName)
                if item then
                    pcall(function()
                        secureFireServer("RequestPickupItem", item)
                        task.wait(0.15)
                        if autoDrop then dropAtHRP() end
                        XeioaState.ItemsFarmed += 1
                    end)
                    task.wait(delay)
                end
            end
        end

        -- Instant Proximity Prompts
        if Toggles.AFInstantPP and Toggles.AFInstantPP.Value then
            local hrp   = getHRP()
            local range = Options.AFPPRange and Options.AFPPRange.Value or 30
            if hrp then
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if obj:IsA("ProximityPrompt") and obj.Enabled then
                        local part = obj.Parent
                        if part and part:IsA("BasePart") then
                            if (hrp.Position - part.Position).Magnitude <= range then
                                secureFireProximityPrompt(obj)
                                task.wait(0.03)
                            end
                        end
                    end
                end
            end
        end
    end
end))

-- ============================================================
-- ██ TELEPORT TAB ██
-- ============================================================

local TPLeft  = Tabs.Teleport:AddLeftGroupbox("Quick Teleport")
local TPRight = Tabs.Teleport:AddRightGroupbox("Object Teleport")

local Locations = {
    ["Start Position"] = Vector3.new(312, 37, -458),
    ["Map Center"]     = Vector3.new(384, 35, -443),
    ["Object Area"]    = Vector3.new(384, 35, -443),
}

local locNames = {}
for n in pairs(Locations) do table.insert(locNames, n) end
table.sort(locNames)

TPLeft:AddToggle("TPUseTween", {
    Text    = "Smooth Tween Movement",
    Default = true,
    Tooltip = "Smooth tween vs instant teleport",
})

TPLeft:AddSlider("TPSpeed", {
    Text     = "Tween Speed",
    Default  = 80,
    Min      = 10,
    Max      = 500,
    Rounding = 0,
})

TPLeft:AddDropdown("TPLocation", {
    Values     = locNames,
    Default    = 1,
    Multi      = false,
    Text       = "Quick Location",
    Searchable = false,
})

TPLeft:AddButton({
    Text = "Teleport",
    Func = function()
        local sel = Options.TPLocation.Value
        if sel and Locations[sel] then
            local pos = Locations[sel]
            if Toggles.TPUseTween and Toggles.TPUseTween.Value then
                safeTweenTo(pos, Options.TPSpeed.Value)
            else
                local hrp = getHRP()
                if hrp then hrp.CFrame = CFrame.new(pos) end
            end
            Library:Notify({ Title = "Teleport", Description = "→ " .. sel, Time = 2 })
        end
    end,
})

TPLeft:AddDivider()

-- Custom coordinates
TPLeft:AddInput("TPX", { Default = "312", Numeric = true, Text = "X", Placeholder = "X" })
TPLeft:AddInput("TPY", { Default = "37",  Numeric = true, Text = "Y", Placeholder = "Y" })
TPLeft:AddInput("TPZ", { Default = "-458",Numeric = true, Text = "Z", Placeholder = "Z" })

TPLeft:AddButton({
    Text = "Teleport to Coords",
    Func = function()
        local x = tonumber(Options.TPX.Value) or 0
        local y = tonumber(Options.TPY.Value) or 0
        local z = tonumber(Options.TPZ.Value) or 0
        local pos = Vector3.new(x, y, z)
        if Toggles.TPUseTween and Toggles.TPUseTween.Value then
            safeTweenTo(pos, Options.TPSpeed.Value)
        else
            local hrp = getHRP()
            if hrp then hrp.CFrame = CFrame.new(pos) end
        end
        Library:Notify({ Title = "Teleport", Description = string.format("(%.0f, %.0f, %.0f)", x, y, z), Time = 2 })
    end,
})

-- Object teleport side
local allObjNames = getAllPickupableNames()

TPRight:AddDropdown("TPObjSelect", {
    Values     = allObjNames,
    Default    = 1,
    Multi      = false,
    Text       = "Select Object",
    Searchable = true,
})

TPRight:AddButton({
    Text = "Refresh Object List",
    Func = function()
        local newList = getAllPickupableNames()
        Options.TPObjSelect:SetValues(newList)
        if #newList > 0 then Options.TPObjSelect:SetValue(newList[1]) end
        Library:Notify({ Title = "Objects", Description = "Found " .. #newList, Time = 2 })
    end,
})

TPRight:AddButton({
    Text    = "Teleport to Object",
    Tooltip = "Smooth tween to selected object",
    Func    = function()
        local sel = Options.TPObjSelect.Value
        if not sel then return end
        local obj = ObjectsFolder and ObjectsFolder:FindFirstChild(sel)
        if not obj then return end
        local part = obj:FindFirstChild("Main") or obj:FindFirstChildWhichIsA("BasePart")
        if part then
            local pos = part.Position + Vector3.new(0, 3, 0)
            if Toggles.TPUseTween and Toggles.TPUseTween.Value then
                safeTweenTo(pos, Options.TPSpeed.Value)
            else
                local hrp = getHRP()
                if hrp then hrp.CFrame = CFrame.new(pos) end
            end
            Library:Notify({ Title = "Teleport", Description = "→ " .. sel, Time = 2 })
        end
    end,
})

TPRight:AddButton({
    Text    = "Teleport & Pickup",
    Tooltip = "Tween to object, trigger prompt, pickup, drop at position",
    Func    = function()
        local sel = Options.TPObjSelect.Value
        if not sel then return end
        local obj = ObjectsFolder and ObjectsFolder:FindFirstChild(sel)
        if not obj then return end
        local part = obj:FindFirstChild("Main") or obj:FindFirstChildWhichIsA("BasePart")
        if part then
            local pos = part.Position + Vector3.new(0, 3, 0)
            safeTweenTo(pos, Options.TPSpeed.Value)
            task.wait(0.4)

            -- Fire prompt
            local pp = findProximityPrompt(obj)
            if pp then secureFireProximityPrompt(pp) end

            -- Remote pickup
            pcall(function()
                secureInvokeServer("RequestPickup", obj)
            end)

            task.wait(0.3)
            dropAtHRP()

            Library:Notify({ Title = "Pickup", Description = "✔ " .. sel, Time = 2 })
        end
    end,
})

-- ============================================================
-- ██ KEYBINDS ██
-- ============================================================

-- G = instant drop
trackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.G then
        dropAtHRP()
        Library:Notify({ Title = "Drop", Description = "Dropped held item", Time = 1 })
    end
end))

-- ============================================================
-- ██ UI SETTINGS TAB ██
-- ============================================================

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

MenuGroup:AddToggle("KeybindMenuOpen", {
    Default  = Library.KeybindFrame.Visible,
    Text     = "Open Keybind Menu",
    Callback = function(v) Library.KeybindFrame.Visible = v end,
})

MenuGroup:AddToggle("ShowCustomCursor", {
    Text     = "Custom Cursor",
    Default  = true,
    Callback = function(v) Library.ShowCustomCursor = v end,
})

MenuGroup:AddDropdown("NotificationSide", {
    Values   = { "Left", "Right" },
    Default  = "Right",
    Text     = "Notification Side",
    Callback = function(v) Library:SetNotifySide(v) end,
})

MenuGroup:AddDropdown("DPIDropdown", {
    Values   = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
    Default  = "100%",
    Text     = "DPI Scale",
    Callback = function(v)
        v = v:gsub("%%", "")
        Library:SetDPIScale(tonumber(v))
    end,
})

MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", {
    Default = "RightShift",
    NoUI    = true,
    Text    = "Toggle Menu",
})

MenuGroup:AddButton({
    Text        = "Unload Xeioa Hub",
    DoubleClick = true,
    Risky       = true,
    Func        = function()
        Library:Unload()
    end,
})

Library.ToggleKeybind = Options.MenuKeybind

Library:OnUnload(function()
    cleanupAll()
    print("[Xeioa Hub] Unloaded cleanly.")
end)

-- ============================================================
-- THEME & SAVE MANAGERS
-- ============================================================

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("XeioaHub")
SaveManager:SetFolder("XeioaHub/" .. XeioaState.GameName)

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()

-- ============================================================
-- STARTUP
-- ============================================================

Library:Notify({
    Title       = "Xeioa Hub  |  " .. XeioaState.GameName,
    Description = "v" .. XeioaState.Version .. " loaded!\n[G] = Drop Item  |  [RightShift] = Menu",
    Time        = 5,
})

print(string.format("[Xeioa Hub v%s] Loaded for %s", XeioaState.Version, XeioaState.GameName))
