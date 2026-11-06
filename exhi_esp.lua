--[[
    Exhibition Dynamic ESP
    Works with ANY rig (R6, R15, Rthro, custom, single-mesh, NPCs).
    Uses real AABB bounds computed from character parts.

    PARENTING FIX:
      Roblox filters ScreenGuis parented directly to CoreGui.
      We must use RobloxGui.Modules — the same parent ExhibitionLib uses.
      This is why the previous version ran but never rendered.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local ESP = {
    Settings = {
        Enabled = false,
        Boxes = true,
        Health = true,
        Names = true,
        Items = true,
        Skeleton = false,
        BoxMode = "Box",
        EnemyColor = Color3.fromRGB(255, 0, 0),
        FriendColor = Color3.fromRGB(0, 255, 0),
        TeamCheck = false,
        TeamColors = false,
        SkeletonColor = Color3.fromRGB(255, 255, 255),
        IncludeAccessories = false,
        SkeletonMode = "Auto",
        BoundsPadding = 0.1,
    },
    Cache = {},
    BoundsCache = {},
    BoundsCacheTime = {},
}

print("[Exhibition ESP] Loading dynamic ESP module...")

-----------------------------------------------------
-- ScreenGui parented exactly like ExhibitionLib
-----------------------------------------------------
local sg = Instance.new("ScreenGui")
local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local randName = ""
for i = 1, 16 do randName = randName .. string.sub(charset, math.random(1, #charset), math.random(1, #charset)) end
sg.Name = randName
sg.IgnoreGuiInset = true
sg.ResetOnSpawn = false
sg.DisplayOrder = 999
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(sg) end end)

-- Same parent resolution as ExhibitionLib: RobloxGui.Modules
local targetParent = CoreGui:FindFirstChild("RobloxGui") or LocalPlayer:WaitForChild("PlayerGui")
local modulesFolder = targetParent:FindFirstChild("Modules")
if not modulesFolder then
    modulesFolder = Instance.new("Folder")
    modulesFolder.Name = "Modules"
    modulesFolder.Parent = targetParent
end
sg.Parent = modulesFolder
print("[Exhibition ESP] ScreenGui parented to: " .. modulesFolder:GetFullName())

sg.AncestryChanged:Connect(function(_, parent)
    if not parent and sg.Parent ~= modulesFolder then
        task.defer(function() pcall(function() sg.Parent = modulesFolder end) end)
    end
end)

-----------------------------------------------------
-- Load-time rendering test (magenta square)
-----------------------------------------------------
local testFrame = Instance.new("Frame")
testFrame.Name = "ESP_RenderTest"
testFrame.Size = UDim2.new(0, 80, 0, 80)
testFrame.Position = UDim2.new(0, 20, 0, 20)
testFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 255)
testFrame.BorderSizePixel = 3
testFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
testFrame.ZIndex = 9999
testFrame.Parent = sg

print("[Exhibition ESP] TEST SQUARE drawn top-left. If you do NOT see a magenta square, rendering is broken.")
task.delay(8, function()
    if testFrame and testFrame.Parent then testFrame:Destroy() end
end)

-----------------------------------------------------
-- Utilities
-----------------------------------------------------
local Colors = {
    BlackTrans = Color3.fromRGB(0, 0, 0),
    Red = Color3.fromRGB(255, 0, 0),
    Yellow = Color3.fromRGB(255, 255, 0),
    Green = Color3.fromRGB(0, 255, 0),
}
local BLACK_TRANS = 1 - (150 / 255)

local function Create(cls, props)
    local inst = Instance.new(cls)
    for k, v in pairs(props or {}) do inst[k] = v end
    return inst
end

local function GetPlayerColor(plr)
    if ESP.Settings.TeamColors and plr.TeamColor and LocalPlayer.TeamColor and plr.TeamColor == LocalPlayer.TeamColor then
        return ESP.Settings.FriendColor
    end
    return ESP.Settings.EnemyColor
end

local function BlendColors(progress)
    if progress >= 0.5 then
        return Colors.Yellow:Lerp(Colors.Green, (progress - 0.5) * 2)
    else
        return Colors.Red:Lerp(Colors.Yellow, progress * 2)
    end
end

-----------------------------------------------------
-- Body utilities
-----------------------------------------------------
local PlayerUtils = {}

local function IsAccessoryPart(part)
    return part:FindFirstAncestorWhichIsA("Accessory") ~= nil
        or part:FindFirstAncestorWhichIsA("Accoutrement") ~= nil
end

local function IsToolPart(part)
    return part:FindFirstAncestorWhichIsA("Tool") ~= nil
end

function PlayerUtils.GetBodyParts(character)
    local parts = {}
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("BasePart") then
            if not ESP.Settings.IncludeAccessories and IsAccessoryPart(d) then continue end
            if IsToolPart(d) then continue end
            if d.Transparency >= 1 and d.Name ~= "HumanoidRootPart" and d ~= character.PrimaryPart then
                continue
            end
            table.insert(parts, d)
        end
    end
    if #parts == 0 then
        for _, d in ipairs(character:GetDescendants()) do
            if d:IsA("BasePart") then table.insert(parts, d) end
        end
    end
    return parts
end

function PlayerUtils.GetBoundingBox(character)
    local parts = PlayerUtils.GetBodyParts(character)
    if #parts == 0 then return nil end
    local min = Vector3.new(1e9, 1e9, 1e9)
    local max = Vector3.new(-1e9, -1e9, -1e9)
    for _, part in ipairs(parts) do
        local cf = part.CFrame
        local s = part.Size * 0.5
        for _, c in ipairs({
            cf * Vector3.new(-s.X, -s.Y, -s.Z), cf * Vector3.new(s.X, -s.Y, -s.Z),
            cf * Vector3.new(-s.X,  s.Y, -s.Z), cf * Vector3.new(s.X,  s.Y, -s.Z),
            cf * Vector3.new(-s.X, -s.Y,  s.Z), cf * Vector3.new(s.X, -s.Y,  s.Z),
            cf * Vector3.new(-s.X,  s.Y,  s.Z), cf * Vector3.new(s.X,  s.Y,  s.Z),
        }) do
            min = Vector3.new(math.min(min.X, c.X), math.min(min.Y, c.Y), math.min(min.Z, c.Z))
            max = Vector3.new(math.max(max.X, c.X), math.max(max.Y, c.Y), math.max(max.Z, c.Z))
        end
    end
    local pad = ESP.Settings.BoundsPadding
    if pad and pad > 0 then
        min = min - Vector3.new(pad, pad, pad)
        max = max + Vector3.new(pad, pad, pad)
    end
    return { Min = min, Max = max, Character = character }
end

function PlayerUtils.GetScreenBox(box, camera)
    if not box then return nil end
    local min, max = box.Min, box.Max
    local corners = {
        Vector3.new(min.X, min.Y, min.Z), Vector3.new(max.X, min.Y, min.Z),
        Vector3.new(min.X, max.Y, min.Z), Vector3.new(max.X, max.Y, min.Z),
        Vector3.new(min.X, min.Y, max.Z), Vector3.new(max.X, min.Y, max.Z),
        Vector3.new(min.X, max.Y, max.Z), Vector3.new(max.X, max.Y, max.Z),
    }
    local minX, minY, maxX, maxY = 1e9, 1e9, -1e9, -1e9
    local any = false
    for _, c in ipairs(corners) do
        local screen = camera:WorldToViewportPoint(c)
        if screen.Z > 0 then
            any = true
            minX = math.min(minX, screen.X)
            minY = math.min(minY, screen.Y)
            maxX = math.max(maxX, screen.X)
            maxY = math.max(maxY, screen.Y)
        end
    end
    if not any then return nil end
    return minX, minY, maxX, maxY
end

local BOUNDS_TTL = 0.5

function PlayerUtils.GetCachedBoundingBox(character)
    local now = os.clock()
    local cached = ESP.BoundsCache[character]
    if cached and now - (ESP.BoundsCacheTime[character] or 0) < BOUNDS_TTL then
        return cached
    end
    local box = PlayerUtils.GetBoundingBox(character)
    ESP.BoundsCache[character] = box
    ESP.BoundsCacheTime[character] = now
    return box
end

function PlayerUtils.CleanCharacter(character)
    ESP.BoundsCache[character] = nil
    ESP.BoundsCacheTime[character] = nil
end

-----------------------------------------------------
-- Skeleton links
-----------------------------------------------------
local R6_LINKS = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
local R15_LINKS = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local function GetSkeletonLinks(character)
    local mode = ESP.Settings.SkeletonMode
    if mode == "R6" then return R6_LINKS end
    if mode == "R15" then return R15_LINKS end
    if character:FindFirstChild("UpperTorso") then return R15_LINKS end
    if character:FindFirstChild("Torso") and character:FindFirstChild("Head") then return R6_LINKS end
    local links, seen = {}, {}
    for _, joint in ipairs(character:GetDescendants()) do
        if joint:IsA("Motor6D") or joint:IsA("Weld") or joint:IsA("HingeConstraint") or joint:IsA("BallSocketConstraint") then
            local p0, p1 = joint.Part0, joint.Part1
            if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
                if IsAccessoryPart(p0) or IsAccessoryPart(p1) then continue end
                if IsToolPart(p0) or IsToolPart(p1) then continue end
                local key = p0.Name .. "|" .. p1.Name
                if not seen[key] then
                    seen[key] = true
                    table.insert(links, { p0.Name, p1.Name })
                end
            end
        end
    end
    return links
end

-----------------------------------------------------
-- Drawables
-----------------------------------------------------
local LINE_POOL_SIZE = 120

local function CreateESPCache()
    local container = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        Visible = false,
        ZIndex = 100,
        Parent = sg,
    })

    local lines = {}
    for i = 1, LINE_POOL_SIZE do
        table.insert(lines, Create("Frame", {
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(0, 1, 0, 1),
            Visible = false,
            ZIndex = 100,
            Parent = container,
        }))
    end

    local nameLbl = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        TextColor3 = Color3.new(1, 1, 1),
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255),
        Size = UDim2.new(0, 200, 0, 16),
        AnchorPoint = Vector2.new(0.5, 1),
        Visible = false,
        ZIndex = 101,
        Parent = container,
    })

    local itemLbl = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSans,
        TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1),
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255),
        Size = UDim2.new(0, 200, 0, 14),
        AnchorPoint = Vector2.new(0.5, 0),
        Visible = false,
        ZIndex = 101,
        Parent = container,
    })

    local healthOuter = Create("Frame", {
        BackgroundColor3 = Colors.BlackTrans,
        BackgroundTransparency = BLACK_TRANS,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 100,
        Parent = container,
    })
    local healthInner = Create("Frame", {
        BackgroundColor3 = Colors.BlackTrans,
        BackgroundTransparency = 1 - (35 / 255),
        BorderSizePixel = 0,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        ZIndex = 100,
        Parent = healthOuter,
    })
    local healthFill = Create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 100,
        Parent = healthOuter,
    })

    local cache = {
        Container = container,
        Lines = lines,
        Name = nameLbl,
        Item = itemLbl,
        HealthOuter = healthOuter,
        HealthInner = healthInner,
        HealthFill = healthFill,
        LineIndex = 1,
    }

    function cache.Hide()
        for _, l in ipairs(lines) do l.Visible = false end
        nameLbl.Visible = false
        itemLbl.Visible = false
        healthOuter.Visible = false
    end

    function cache.HideFrom(idx)
        for i = idx, #lines do lines[i].Visible = false end
    end

    return cache
end

local function DrawRect(cache, x, y, w, h, col, trans)
    local l = cache.Lines[cache.LineIndex]
    if not l then return end
    l.Visible = true
    l.Position = UDim2.new(0, x, 0, y)
    l.Size = UDim2.new(0, math.max(1, w), 0, math.max(1, h))
    l.BackgroundColor3 = col
    l.BackgroundTransparency = trans or 0
    l.Rotation = 0
    cache.LineIndex = cache.LineIndex + 1
end

local function DrawRotatedLine(cache, p1, p2, color, thickness)
    local l = cache.Lines[cache.LineIndex]
    if not l then return end
    local distance = (p1 - p2).Magnitude
    if distance < 0.5 then
        cache.LineIndex = cache.LineIndex + 1
        return
    end
    l.Visible = true
    local center = (p1 + p2) / 2
    local angle = math.atan2(p2.Y - p1.Y, p2.X - p1.X)
    l.Size = UDim2.new(0, distance, 0, thickness or 1)
    l.Position = UDim2.new(0, center.X - distance / 2, 0, center.Y - (thickness or 1) / 2)
    l.Rotation = math.deg(angle)
    l.BackgroundColor3 = color
    l.BackgroundTransparency = 0
    cache.LineIndex = cache.LineIndex + 1
end

local function DrawBorderedRect(cache, x, y, ex, ey, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, y - thickness, (ex - x) + thickness * 2, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, ey, (ex - x) + thickness * 2, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, y, thickness, ey - y, outCol, outTrans)
    DrawRect(cache, ex, y, thickness, ey - y, outCol, outTrans)
end

-----------------------------------------------------
-- Main loop with verbose first-frame logging
-----------------------------------------------------
local drawnOnce = false

local function UpdateESP()
    local camera = Workspace.CurrentCamera
    if not camera then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end

        if not ESP.Cache[plr] then
            ESP.Cache[plr] = CreateESPCache()
        end
        local cache = ESP.Cache[plr]

        if not ESP.Settings.Enabled then
            cache.Container.Visible = false
            cache.Hide()
            continue
        end

        local char = plr.Character
        if not char then
            cache.Container.Visible = false
            cache.Hide()
            continue
        end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then
            cache.Container.Visible = false
            cache.Hide()
            continue
        end

        if ESP.Settings.TeamCheck and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
            cache.Container.Visible = false
            cache.Hide()
            continue
        end

        local box3d = PlayerUtils.GetCachedBoundingBox(char)
        if not box3d then
            cache.Container.Visible = false
            cache.Hide()
            continue
        end

        local minX, minY, maxX, maxY = PlayerUtils.GetScreenBox(box3d, camera)
        if not minX or maxX <= minX or maxY <= minY then
            cache.Container.Visible = false
            cache.Hide()
            continue
        end

        -- Log the very first successful draw for debugging
        if not drawnOnce then
            drawnOnce = true
            print(string.format("[Exhibition ESP] First draw: %s at screen (%d,%d) to (%d,%d)",
                plr.Name, minX, minY, maxX, maxY))
        end

        cache.Container.Visible = true
        cache.LineIndex = 1
        cache.Name.Visible = false
        cache.Item.Visible = false
        cache.HealthOuter.Visible = false

        local color = GetPlayerColor(plr)
        local x, y, ex, ey = minX, minY, maxX, maxY

        if ESP.Settings.Boxes then
            local mode = ESP.Settings.BoxMode
            if mode == "Box" then
                DrawBorderedRect(cache, x - 1, y - 1, ex + 1, ey + 1, 1, Colors.BlackTrans, BLACK_TRANS)
                DrawBorderedRect(cache, x + 1, y + 1, ex - 1, ey - 1, 1, Colors.BlackTrans, BLACK_TRANS)
                DrawBorderedRect(cache, x, y, ex, ey, 1, color, 0)
            elseif mode == "Corner A" or mode == "Split" then
                local len = (ex - x) / 4
                local vLen = (ey - y) / 4
                DrawRect(cache, x, y, 1, vLen, color, 0)
                DrawRect(cache, x, y, len, 1, color, 0)
                DrawRect(cache, ex, y, 1, vLen, color, 0)
                DrawRect(cache, ex - len, y, len, 1, color, 0)
                DrawRect(cache, x, ey - vLen, 1, vLen, color, 0)
                DrawRect(cache, x, ey, len, 1, color, 0)
                DrawRect(cache, ex, ey - vLen, 1, vLen, color, 0)
                DrawRect(cache, ex - len, ey, len, 1, color, 0)
            end
        end

        if ESP.Settings.Health and hum then
            cache.HealthOuter.Visible = true
            local hp = hum.Health
            local maxHp = hum.MaxHealth
            if maxHp <= 0 then maxHp = 100 end
            local prog = math.clamp(hp / maxHp, 0, 1)
            local diff = ey - y
            cache.HealthOuter.Position = UDim2.new(0, x - 6, 0, y)
            cache.HealthOuter.Size = UDim2.new(0, 4, 0, diff)
            cache.HealthFill.BackgroundColor3 = BlendColors(prog)
            cache.HealthFill.Position = UDim2.new(0, 1, 0, 1 + (diff - 2) * (1 - prog))
            cache.HealthFill.Size = UDim2.new(1, -2, 0, math.max(0, (diff - 2) * prog))
        end

        if ESP.Settings.Names then
            cache.Name.Visible = true
            cache.Name.Text = (plr.DisplayName ~= "" and plr.DisplayName) or plr.Name
            cache.Name.TextColor3 = ESP.Settings.TeamColors and color or Color3.new(1, 1, 1)
            cache.Name.Position = UDim2.new(0, x + (ex - x) / 2, 0, y - 3)
        end

        if ESP.Settings.Items then
            local tool = char:FindFirstChildOfClass("Tool")
            if tool then
                cache.Item.Visible = true
                cache.Item.Text = tool.Name
                cache.Item.Position = UDim2.new(0, x + (ex - x) / 2, 0, ey + 3)
            end
        end

        if ESP.Settings.Skeleton then
            for _, link in ipairs(GetSkeletonLinks(char)) do
                local p1 = char:FindFirstChild(link[1])
                local p2 = char:FindFirstChild(link[2])
                if p1 and p2 then
                    local s1, v1 = camera:WorldToViewportPoint(p1.Position)
                    local s2, v2 = camera:WorldToViewportPoint(p2.Position)
                    if v1 or v2 then
                        DrawRotatedLine(cache, Vector2.new(s1.X, s1.Y), Vector2.new(s2.X, s2.Y), ESP.Settings.SkeletonColor, 1)
                    end
                end
            end
        end

        cache.HideFrom(cache.LineIndex)
    end
end

-----------------------------------------------------
-- Render loop
-----------------------------------------------------
local errorCount = 0
local lastEnabled = nil

RunService.RenderStepped:Connect(function()
    if ESP.Settings.Enabled ~= lastEnabled then
        print("[Exhibition ESP] Enabled changed to: " .. tostring(ESP.Settings.Enabled))
        lastEnabled = ESP.Settings.Enabled
    end

    local ok, err = pcall(UpdateESP)
    if not ok then
        errorCount = errorCount + 1
        if errorCount <= 3 then
            warn("[Exhibition ESP] Error #" .. errorCount .. ": " .. tostring(err))
        end
    end
end)

-- Watchdog: if SG gets deleted by anti-cheat, re-parent it
task.spawn(function()
    while task.wait(1) do
        if not sg.Parent then
            warn("[Exhibition ESP] ScreenGui was destroyed! Attempting re-parent...")
            pcall(function() sg.Parent = modulesFolder end)
        end
    end
end)

-- Cache cleanup
task.spawn(function()
    while task.wait(0.5) do
        for plr, cache in pairs(ESP.Cache) do
            if not plr or not plr.Parent then
                if cache and cache.Container then pcall(function() cache.Container:Destroy() end) end
                ESP.Cache[plr] = nil
            end
        end
        for char in pairs(ESP.BoundsCache) do
            if not char or not char.Parent then
                ESP.BoundsCache[char] = nil
                ESP.BoundsCacheTime[char] = nil
            end
        end
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    if ESP.Cache[plr] then
        pcall(function() ESP.Cache[plr].Container:Destroy() end)
        ESP.Cache[plr] = nil
    end
    if plr.Character then
        PlayerUtils.CleanCharacter(plr.Character)
    end
end)

print("[Exhibition ESP] Loaded. Look for the magenta test square, then toggle 'Enabled' to test.")

return ESP
