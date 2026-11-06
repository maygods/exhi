--[[
    Exhibition Dynamic ESP
    Works with ANY rig (R6, R15, Rthro, custom, single-mesh, NPCs).
    Uses real AABB bounds computed from character parts instead of a fixed box.
    Skeleton is joint-driven, so it works for custom rigs too.

    FIX NOTES vs previous version:
      - Container is a Frame (GuiObject) not a Folder, so .Visible works.
      - All drawables start hidden; stale lines are cleared every frame.
      - Default IncludeAccessories = false to match original behaviour.
      - Added pcall guards around CoreGui access.
      - Added sg.DisplayOrder so other GUIs don't cover it.
      - Added print on load so you can confirm the module is the new one.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

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

-- ScreenGui with high DisplayOrder so it renders above game UI
local sg = Instance.new("ScreenGui")
local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local randName = ""
for i = 1, 16 do randName = randName .. string.sub(charset, math.random(1, #charset), math.random(1, #charset)) end
sg.Name = randName
sg.IgnoreGuiInset = true
sg.ResetOnSpawn = false
sg.DisplayOrder = 100
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(sg) end end)

local targetParent
do
    local ok, gui = pcall(function() return CoreGui:FindFirstChild("RobloxGui") end)
    if ok and gui then
        targetParent = gui
    else
        targetParent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local modulesFolder = targetParent:FindFirstChild("Modules")
if not modulesFolder then
    modulesFolder = Instance.new("Folder")
    modulesFolder.Name = "Modules"
    modulesFolder.Parent = targetParent
end
sg.Parent = modulesFolder

sg.AncestryChanged:Connect(function(_, parent)
    if not parent and sg.Parent ~= modulesFolder then
        task.defer(function() pcall(function() sg.Parent = modulesFolder end) end)
    end
end)

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
        local p = (progress - 0.5) * 2
        return Colors.Yellow:Lerp(Colors.Green, p)
    else
        local p = progress * 2
        return Colors.Red:Lerp(Colors.Yellow, p)
    end
end


-----------------------------------------------------
-- Dynamic body utilities
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
        for _, corner in ipairs({
            cf * Vector3.new(-s.X, -s.Y, -s.Z),
            cf * Vector3.new( s.X, -s.Y, -s.Z),
            cf * Vector3.new(-s.X,  s.Y, -s.Z),
            cf * Vector3.new( s.X,  s.Y, -s.Z),
            cf * Vector3.new(-s.X, -s.Y,  s.Z),
            cf * Vector3.new( s.X, -s.Y,  s.Z),
            cf * Vector3.new(-s.X,  s.Y,  s.Z),
            cf * Vector3.new( s.X,  s.Y,  s.Z),
        }) do
            min = Vector3.new(math.min(min.X, corner.X), math.min(min.Y, corner.Y), math.min(min.Z, corner.Z))
            max = Vector3.new(math.max(max.X, corner.X), math.max(max.Y, corner.Y), math.max(max.Z, corner.Z))
        end
    end

    local pad = ESP.Settings.BoundsPadding
    if pad and pad > 0 then
        min = min - Vector3.new(pad, pad, pad)
        max = max + Vector3.new(pad, pad, pad)
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart or parts[1]
    return { Min = min, Max = max, Root = rootPart, Character = character }
end

function PlayerUtils.GetScreenBox(box, camera)
    if not box then return nil end
    local min, max = box.Min, box.Max
    local corners = {
        Vector3.new(min.X, min.Y, min.Z),
        Vector3.new(max.X, min.Y, min.Z),
        Vector3.new(min.X, max.Y, min.Z),
        Vector3.new(max.X, max.Y, min.Z),
        Vector3.new(min.X, min.Y, max.Z),
        Vector3.new(max.X, min.Y, max.Z),
        Vector3.new(min.X, max.Y, max.Z),
        Vector3.new(max.X, max.Y, max.Z),
    }
    local minX, minY, maxX, maxY = 1e9, 1e9, -1e9, -1e9
    local any = false
    for _, c in ipairs(corners) do
        local screen, _ = camera:WorldToViewportPoint(c)
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
-- Skeleton graph (works for any rig)
-----------------------------------------------------
local R6_LINKS = {
    { "Head", "Torso" },
    { "Torso", "Left Arm" },
    { "Torso", "Right Arm" },
    { "Torso", "Left Leg" },
    { "Torso", "Right Leg" },
}

local R15_LINKS = {
    { "Head", "UpperTorso" },
    { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" },
    { "LeftUpperArm", "LeftLowerArm" },
    { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" },
    { "RightUpperArm", "RightLowerArm" },
    { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" },
    { "LeftUpperLeg", "LeftLowerLeg" },
    { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" },
    { "RightUpperLeg", "RightLowerLeg" },
    { "RightLowerLeg", "RightFoot" },
}

local function GetSkeletonLinks(character)
    local mode = ESP.Settings.SkeletonMode
    local hasR15 = character:FindFirstChild("UpperTorso") ~= nil
    local hasR6 = character:FindFirstChild("Torso") ~= nil and character:FindFirstChild("Head") ~= nil

    if mode == "R6" then return R6_LINKS end
    if mode == "R15" then return R15_LINKS end
    if hasR15 then return R15_LINKS end
    if hasR6 then return R6_LINKS end

    -- Custom rig: joint-based graph
    local links = {}
    local seen = {}
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
    if #links > 0 then return links end

    -- Last resort: nearest-neighbour chain
    local parts = PlayerUtils.GetBodyParts(character)
    if #parts <= 1 then return {} end
    local connected = { [parts[1]] = true }
    local ordered = { parts[1] }
    while #ordered < #parts do
        local bestPart, bestDist, bestAnchor = nil, math.huge, nil
        for _, p in ipairs(parts) do
            if not connected[p] then
                for _, anchor in ipairs(ordered) do
                    local d = (p.Position - anchor.Position).Magnitude
                    if d < bestDist then
                        bestDist = d
                        bestPart = p
                        bestAnchor = anchor
                    end
                end
            end
        end
        if not bestPart then break end
        connected[bestPart] = true
        table.insert(ordered, bestPart)
        if bestAnchor then table.insert(links, { bestPart.Name, bestAnchor.Name }) end
    end
    return links
end


-----------------------------------------------------
-- Drawing utilities
-----------------------------------------------------
local LINE_POOL_SIZE = 120

local function DrawLine(parent, x, y, w, h)
    return Create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = UDim2.new(0, x, 0, y),
        Size = UDim2.new(0, math.max(1, w), 0, math.max(1, h)),
        Visible = false,
        Parent = parent,
    })
end

local function CreateESPCache()
    -- Use a Frame (GuiObject) so .Visible works.
    local container = Create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 0, 0),
        Visible = false,
        Parent = sg,
    })

    local lines = {}
    for i = 1, LINE_POOL_SIZE do
        table.insert(lines, DrawLine(container, 0, 0, 1, 1))
    end

    local nameLbl = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        TextColor3 = Color3.new(1, 1, 1),
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255),
        Size = UDim2.new(0, 200, 0, 16),
        Visible = false,
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
        Visible = false,
        Parent = container,
    })

    local healthOuter = Create("Frame", {
        BackgroundColor3 = Colors.BlackTrans,
        BackgroundTransparency = BLACK_TRANS,
        BorderSizePixel = 0,
        Visible = false,
        Parent = container,
    })

    local healthInner = Create("Frame", {
        BackgroundColor3 = Colors.BlackTrans,
        BackgroundTransparency = 1 - (35 / 255),
        BorderSizePixel = 0,
        Parent = healthOuter,
    })

    local healthFill = Create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
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

    function cache.HideFrom(index)
        for i = index, #lines do lines[i].Visible = false end
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
    l.BorderSizePixel = 0
    cache.LineIndex = cache.LineIndex + 1
end

local function DrawRotatedLine(cache, p1, p2, color, thickness)
    local l = cache.Lines[cache.LineIndex]
    if not l then return end
    l.Visible = true
    local distance = (p1 - p2).Magnitude
    if distance < 0.1 then
        cache.LineIndex = cache.LineIndex + 1
        return
    end
    local center = (p1 + p2) / 2
    local angle = math.atan2(p2.Y - p1.Y, p2.X - p1.X)
    l.Size = UDim2.new(0, distance, 0, thickness or 1)
    l.Position = UDim2.new(0, center.X - distance / 2, 0, center.Y - (thickness or 1) / 2)
    l.Rotation = math.deg(angle)
    l.BackgroundColor3 = color
    l.BackgroundTransparency = 0
    l.BorderSizePixel = 0
    cache.LineIndex = cache.LineIndex + 1
end

local function DrawBorderedRect(cache, x, y, endx, endy, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, y - thickness, (endx - x) + thickness * 2, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, endy, (endx - x) + thickness * 2, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, y, thickness, endy - y, outCol, outTrans)
    DrawRect(cache, endx, y, thickness, endy - y, outCol, outTrans)
end


-----------------------------------------------------
-- Main ESP update
-----------------------------------------------------
local function UpdateESP()
    local camera = Workspace.CurrentCamera
    if not camera then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
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

            -- We have something to draw
            cache.Container.Visible = true
            cache.LineIndex = 1
            cache.Name.Visible = false
            cache.Item.Visible = false
            cache.HealthOuter.Visible = false

            local color = GetPlayerColor(plr)
            local x, y, endx, endy = minX, minY, maxX, maxY

            -- Box
            if ESP.Settings.Boxes then
                if ESP.Settings.BoxMode == "Box" then
                    DrawBorderedRect(cache, x - 1, y - 1, endx + 1, endy + 1, 1, Colors.BlackTrans, BLACK_TRANS)
                    DrawBorderedRect(cache, x + 1, y + 1, endx - 1, endy - 1, 1, Colors.BlackTrans, BLACK_TRANS)
                    DrawBorderedRect(cache, x, y, endx, endy, 1, color, 0)
                elseif ESP.Settings.BoxMode == "Corner A" or ESP.Settings.BoxMode == "Split" then
                    local len = (endx - x) / 4
                    local vertLen = (endy - y) / 4
                    DrawRect(cache, x, y, 1, vertLen, color, 0)
                    DrawRect(cache, x, y, len, 1, color, 0)
                    DrawRect(cache, endx, y, 1, vertLen, color, 0)
                    DrawRect(cache, endx - len, y, len, 1, color, 0)
                    DrawRect(cache, x, endy - vertLen, 1, vertLen, color, 0)
                    DrawRect(cache, x, endy, len, 1, color, 0)
                    DrawRect(cache, endx, endy - vertLen, 1, vertLen, color, 0)
                    DrawRect(cache, endx - len, endy, len, 1, color, 0)
                end
            end

            -- Health
            if ESP.Settings.Health and hum then
                cache.HealthOuter.Visible = true
                local hp = hum.Health
                local maxHp = hum.MaxHealth
                if maxHp <= 0 then maxHp = 100 end
                local prog = math.clamp(hp / maxHp, 0, 1)
                local hpColor = BlendColors(prog)
                local diff = endy - y
                cache.HealthOuter.Position = UDim2.new(0, x - 6, 0, y)
                cache.HealthOuter.Size = UDim2.new(0, 4, 0, diff)
                cache.HealthInner.Position = UDim2.new(0, 1, 0, 1)
                cache.HealthInner.Size = UDim2.new(1, -2, 1, -2)
                cache.HealthFill.BackgroundColor3 = hpColor
                cache.HealthFill.Position = UDim2.new(0, 1, 0, 1 + (diff - 2) * (1 - prog))
                cache.HealthFill.Size = UDim2.new(1, -2, 0, math.max(0, (diff - 2) * prog))
            end

            -- Name
            if ESP.Settings.Names then
                cache.Name.Visible = true
                cache.Name.Text = plr.DisplayName ~= "" and plr.DisplayName or plr.Name
                if ESP.Settings.TeamColors then
                    cache.Name.TextColor3 = color
                else
                    cache.Name.TextColor3 = Color3.new(1, 1, 1)
                end
                cache.Name.Size = UDim2.new(0, math.max(50, (endx - x) + 40), 0, 16)
                local txtSize = cache.Name.TextBounds
                cache.Name.Position = UDim2.new(0, x + (endx - x) / 2 - cache.Name.Size.X.Offset / 2, 0, y - txtSize.Y - 3)
            end

            -- Items
            if ESP.Settings.Items then
                local tool = char:FindFirstChildOfClass("Tool")
                if tool then
                    cache.Item.Visible = true
                    cache.Item.Text = tool.Name
                    cache.Item.Size = UDim2.new(0, math.max(50, (endx - x) + 40), 0, 14)
                    cache.Item.Position = UDim2.new(0, x + (endx - x) / 2 - cache.Item.Size.X.Offset / 2, 0, endy + 3)
                end
            end

            -- Skeleton
            if ESP.Settings.Skeleton then
                local links = GetSkeletonLinks(char)
                for _, link in ipairs(links) do
                    local p1 = char:FindFirstChild(link[1])
                    local p2 = char:FindFirstChild(link[2])
                    if p1 and p2 then
                        local pos1, vis1 = camera:WorldToViewportPoint(p1.Position)
                        local pos2, vis2 = camera:WorldToViewportPoint(p2.Position)
                        if vis1 or vis2 then
                            DrawRotatedLine(cache, Vector2.new(pos1.X, pos1.Y), Vector2.new(pos2.X, pos2.Y), ESP.Settings.SkeletonColor, 1)
                        end
                    end
                end
            end

            -- Hide any lines we didn't reuse this frame
            cache.HideFrom(cache.LineIndex)
        end
    end
end


-----------------------------------------------------
-- Lifecycle
-----------------------------------------------------
RunService.RenderStepped:Connect(function()
    pcall(UpdateESP)
end)

task.spawn(function()
    while true do
        task.wait(0.1)
        for plr, cache in pairs(ESP.Cache) do
            if not plr or not plr.Parent then
                if cache and cache.Container then pcall(function() cache.Container:Destroy() end) end
                ESP.Cache[plr] = nil
            end
        end
        -- Sweep stale bounds caches for characters no longer in the world
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

Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function(char)
        PlayerUtils.CleanCharacter(char)
    end)
end)

print("[Exhibition ESP] Loaded. Toggle 'Enabled' in the ESP section to test.")

return ESP
