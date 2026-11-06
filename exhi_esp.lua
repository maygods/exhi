--[[
    Exhibition Dynamic ESP
    Works with ANY rig (R6, R15, Rthro, custom, single-mesh, NPCs).
    Uses real AABB bounds computed from character parts instead of a fixed box.
    Skeleton is joint-driven, so it works for custom rigs too.
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
        IncludeAccessories = true,
        SkeletonMode = "Auto", -- "Auto", "R6", "R15"
        BoundsPadding = 0.1,
    },
    Cache = {},
    BoundsCache = {},
    BoundsCacheTime = {},
}

local sg = Instance.new("ScreenGui")
local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local randName = ""
for i = 1, 16 do randName = randName .. string.sub(charset, math.random(1, #charset), math.random(1, #charset)) end
sg.Name = randName
sg.IgnoreGuiInset = true
sg.ResetOnSpawn = false
pcall(function() if syn then syn.protect_gui(sg) end end)

local targetParent = CoreGui:FindFirstChild("RobloxGui") or LocalPlayer:WaitForChild("PlayerGui")
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
local BLACK_ALPHA = 150 / 255
local BLACK_TRANS = 1 - (150 / 255)

local function Create(cls, props)
    local inst = Instance.new(cls)
    for k, v in pairs(props) do inst[k] = v end
    return inst
end

local function GetPlayerColor(plr)
    if ESP.Settings.TeamColors and plr.TeamColor == LocalPlayer.TeamColor then
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

-- Compute the world-space AABB of the character's real parts
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

    -- Optional padding so the box doesn't clip into the character
    local pad = ESP.Settings.BoundsPadding
    if pad > 0 then
        min = min - Vector3.new(pad, pad, pad)
        max = max + Vector3.new(pad, pad, pad)
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart or parts[1]

    return { Min = min, Max = max, Root = rootPart, Character = character }
end

-- Project the 3D AABB corners onto the screen and take min/max screen coordinates.
-- This works for any rig shape and any camera angle.
function PlayerUtils.GetScreenBox(box, camera)
    if not box then return nil end

    local min = box.Min
    local max = box.Max

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

    local minScreenX, minScreenY = 1e9, 1e9
    local maxScreenX, maxScreenY = -1e9, -1e9
    local anyVisible = false

    for _, corner in ipairs(corners) do
        local screen, onScreen = camera:WorldToViewportPoint(corner)
        if screen.Z > 0 then
            anyVisible = true
            minScreenX = math.min(minScreenX, screen.X)
            minScreenY = math.min(minScreenY, screen.Y)
            maxScreenX = math.max(maxScreenX, screen.X)
            maxScreenY = math.max(maxScreenY, screen.Y)
        end
    end

    if not anyVisible then return nil end

    return minScreenX, minScreenY, maxScreenX, maxScreenY
end

-- Cached bounding box access (0.5s TTL per character)
local BOUNDS_TTL = 0.5

function PlayerUtils.GetCachedBoundingBox(character)
    local now = os.clock()
    local cached = ESP.BoundsCache[character]
    if cached and now - (ESP.BoundsCacheTime[character] or 0) < BOUNDS_TTL then
        local ok = true
        for _, part in ipairs(PlayerUtils.GetBodyParts(character)) do
            if not part.Parent then ok = false break end
        end
        if ok then return cached end
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

    if mode == "R6" then
        return R6_LINKS
    elseif mode == "R15" then
        return R15_LINKS
    end

    -- Auto mode: prefer R15, then R6, then joint-based, then proximity
    if hasR15 then return R15_LINKS end
    if hasR6 then return R6_LINKS end

    -- Custom rig: build links from Motor6D / Weld joints
    local links = {}
    local seen = {}
    for _, joint in ipairs(character:GetDescendants()) do
        if joint:IsA("Motor6D") or joint:IsA("Weld") or joint:IsA("HingeConstraint") or joint:IsA("BallSocketConstraint") then
            local p0 = joint.Part0
            local p1 = joint.Part1
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

    -- Last resort: connect each part to its nearest neighbor
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
        if bestAnchor then
            table.insert(links, { bestPart.Name, bestAnchor.Name })
        end
    end
    return links
end


-----------------------------------------------------
-- Drawing utilities
-----------------------------------------------------
local function DrawLine(parent, color, trans, x, y, width, height)
    return Create("Frame", {
        BackgroundColor3 = color,
        BackgroundTransparency = trans,
        BorderSizePixel = 0,
        Position = UDim2.new(0, x, 0, y),
        Size = UDim2.new(0, math.max(1, width), 0, math.max(1, height)),
        Parent = parent,
    })
end

local function CreateESPCache()
    local container = Create("Folder", { Parent = sg })
    local lines = {}
    for i = 1, 80 do
        table.insert(lines, DrawLine(container, Color3.new(1, 1, 1), 0, 0, 0, 1, 1))
    end
    local nameLbl = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        TextColor3 = Color3.new(1, 1, 1),
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255),
        Parent = container,
    })
    local itemLbl = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSans,
        TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1),
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255),
        Parent = container,
    })
    local healthOuter = Create("Frame", {
        BackgroundColor3 = Colors.BlackTrans,
        BackgroundTransparency = 1 - (150 / 255),
        BorderSizePixel = 0,
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

    local function HideAll()
        for _, l in ipairs(lines) do l.Visible = false end
        nameLbl.Visible = false
        itemLbl.Visible = false
        healthOuter.Visible = false
    end

    return {
        Container = container,
        Lines = lines,
        Name = nameLbl,
        Item = itemLbl,
        HealthOuter = healthOuter,
        HealthInner = healthInner,
        HealthFill = healthFill,
        Hide = HideAll,
        LineIndex = 1,
    }
end

local function DrawRect(cache, x, y, w, h, col, trans)
    local l = cache.Lines[cache.LineIndex]
    if l then
        l.Visible = true
        l.Position = UDim2.new(0, x, 0, y)
        l.Size = UDim2.new(0, math.max(1, w), 0, math.max(1, h))
        l.BackgroundColor3 = col
        l.BackgroundTransparency = trans or 0
        l.Rotation = 0
        cache.LineIndex = cache.LineIndex + 1
    end
end

local function DrawRotatedLine(cache, p1, p2, color, thickness)
    local l = cache.Lines[cache.LineIndex]
    if l then
        l.Visible = true
        local distance = (p1 - p2).Magnitude
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
end

local function DrawBorderedRect(cache, x, y, endx, endy, thickness, innerCol, innerTrans, outCol, outTrans)
    DrawRect(cache, x - thickness, y - thickness, (endx - x) + thickness * 2, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, endy, (endx - x) + thickness * 2, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, y, thickness, endy - y, outCol, outTrans)
    DrawRect(cache, endx, y, thickness, endy - y, outCol, outTrans)
    if innerCol then
        DrawRect(cache, x, y, endx - x, thickness, innerCol, innerTrans)
        DrawRect(cache, x, endy - thickness, endx - x, thickness, innerCol, innerTrans)
        DrawRect(cache, x, y + thickness, thickness, endy - y - thickness * 2, innerCol, innerTrans)
        DrawRect(cache, endx - thickness, y + thickness, thickness, endy - y - thickness * 2, innerCol, innerTrans)
    end
end


-----------------------------------------------------
-- Main ESP update
-----------------------------------------------------
local function UpdateESP()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if not ESP.Cache[plr] then
                ESP.Cache[plr] = CreateESPCache()
            end
            local cache = ESP.Cache[plr]

            if not ESP.Settings.Enabled then
                if cache.Container then cache.Container.Visible = false end
                continue
            end
            if cache.Container then cache.Container.Visible = true end

            local char = plr.Character
            if not char then
                cache.Hide()
                continue
            end

            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then
                cache.Hide()
                continue
            end

            if ESP.Settings.TeamCheck and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
                cache.Hide()
                continue
            end

            local box3d = PlayerUtils.GetCachedBoundingBox(char)
            if not box3d then
                cache.Hide()
                continue
            end

            local minX, minY, maxX, maxY = PlayerUtils.GetScreenBox(box3d, Camera)
            if not minX then
                cache.Hide()
                continue
            end

            cache.LineIndex = 1
            cache.Name.Visible = false
            cache.Item.Visible = false
            cache.HealthOuter.Visible = false

            local color = GetPlayerColor(plr)
            local x, y, endx, endy = minX, minY, maxX, maxY

            -- Box
            if ESP.Settings.Boxes then
                if ESP.Settings.BoxMode == "Box" then
                    DrawBorderedRect(cache, x - 1, y - 1, endx + 1, endy + 1, 1, nil, 1, Colors.BlackTrans, BLACK_TRANS)
                    DrawBorderedRect(cache, x + 1, y + 1, endx - 1, endy - 1, 1, nil, 1, Colors.BlackTrans, BLACK_TRANS)
                    DrawBorderedRect(cache, x, y, endx, endy, 1, nil, 1, color, 0)
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
                local prog = math.clamp(hp / maxHp, 0, 1)
                local hpColor = BlendColors(prog)
                local diff = endy - y
                cache.HealthOuter.Position = UDim2.new(0, x - 6.5, 0, y - 0.5)
                cache.HealthOuter.Size = UDim2.new(0, 4, 0, diff + 1)
                cache.HealthInner.Position = UDim2.new(0, 1, 0, 1)
                cache.HealthInner.Size = UDim2.new(1, -2, 1, -2)
                cache.HealthFill.BackgroundColor3 = hpColor
                cache.HealthFill.Position = UDim2.new(0, 1, 0, 1 + (diff * (1 - prog)))
                cache.HealthFill.Size = UDim2.new(1, -2, 0, diff * prog)
            end

            -- Name
            if ESP.Settings.Names then
                cache.Name.Visible = true
                cache.Name.Text = plr.DisplayName
                if ESP.Settings.TeamColors then
                    cache.Name.TextColor3 = color
                end
                local txtSize = cache.Name.TextBounds
                cache.Name.Position = UDim2.new(0, x + (endx - x) / 2, 0, y - txtSize.Y - 2)
            end

            -- Items
            if ESP.Settings.Items then
                local tool = char:FindFirstChildOfClass("Tool")
                if tool then
                    cache.Item.Visible = true
                    cache.Item.Text = tool.Name
                    cache.Item.Position = UDim2.new(0, x + (endx - x) / 2, 0, endy + 2)
                end
            end

            -- Skeleton
            if ESP.Settings.Skeleton then
                local links = GetSkeletonLinks(char)
                for _, link in ipairs(links) do
                    local p1 = char:FindFirstChild(link[1])
                    local p2 = char:FindFirstChild(link[2])
                    if p1 and p2 then
                        local pos1, vis1 = Camera:WorldToViewportPoint(p1.Position)
                        local pos2, vis2 = Camera:WorldToViewportPoint(p2.Position)
                        if vis1 or vis2 then
                            local v1 = Vector2.new(pos1.X, pos1.Y)
                            local v2 = Vector2.new(pos2.X, pos2.Y)
                            DrawRotatedLine(cache, v1, v2, ESP.Settings.SkeletonColor, 1)
                        end
                    end
                end
            end
        end
    end
end


-----------------------------------------------------
-- Lifecycle
-----------------------------------------------------
RunService.RenderStepped:Connect(UpdateESP)

task.spawn(function()
    while true do
        task.wait(0.1)
        for plr, cache in pairs(ESP.Cache) do
            if not plr or not plr.Parent or not plr:IsDescendantOf(Players) then
                if cache and cache.Container then cache.Container:Destroy() end
                ESP.Cache[plr] = nil
            end
        end
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    if ESP.Cache[plr] then
        ESP.Cache[plr].Container:Destroy()
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

return ESP
