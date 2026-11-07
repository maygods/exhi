--[[
    Exhibition Dynamic ESP  —  v10 Standalone

    Cleanup-aware, works with any rig (R6, R15, Rthro, custom, single-mesh).
    Touch-set pattern: every cache not drawn this frame is auto-hidden and
    destroyed if its model left Workspace.Characters or its player left.

    Use:
        local ESP = loadstring(game:HttpGet("<your ESP URL>"))()
        ESP.Settings.Enabled = true
        ESP.Settings.Boxes = true
        ESP.Settings.Names = true
        ESP.Settings.Health = true
        ESP.Settings.Items = true
        ESP.Settings.Skeleton = false
        ESP.Settings.BoxMode = "Box"           -- "Box" | "Split" | "Corner A" | "Corner B"
        ESP.Settings.EnemyColor = Color3.fromRGB(255, 0, 0)
        ESP.Settings.FriendColor = Color3.fromRGB(0, 255, 0)
        ESP.Settings.SkeletonColor = Color3.fromRGB(255, 255, 255)
        ESP.Settings.TeamCheck = false
        ESP.Settings.TeamColors = false
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local ESP = {
    Settings = {
        Enabled = false,
        Boxes = true, Health = true, Names = true, Items = true, Skeleton = false,
        BoxMode = "Box",
        EnemyColor = Color3.fromRGB(255, 0, 0),
        FriendColor = Color3.fromRGB(0, 255, 0),
        SkeletonColor = Color3.fromRGB(255, 255, 255),
        OrphanColor = Color3.fromRGB(180, 180, 180),
        TeamCheck = false, TeamColors = false,
        IncludeAccessories = false,
    },
    Cache = {},
    OrphanCache = {},
}

-----------------------------------------------------
-- ScreenGui
-----------------------------------------------------
local sg = Instance.new("ScreenGui")
sg.Name = "ESP_" .. tostring(math.random(100000, 999999))
sg.IgnoreGuiInset = true
sg.ResetOnSpawn = false
sg.DisplayOrder = 100
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(sg) end end)

local parent
if gethui then
    local ok, h = pcall(gethui)
    if ok and h then parent = h end
end
sg.Parent = parent or CoreGui

sg.AncestryChanged:Connect(function(_, p)
    if not p then
        task.defer(function() pcall(function() sg.Parent = parent or CoreGui end) end)
    end
end)

-----------------------------------------------------
-- Helpers
-----------------------------------------------------
local function Create(cls, props)
    local i = Instance.new(cls)
    for k, v in pairs(props or {}) do i[k] = v end
    return i
end

local function IsAccessoryPart(part)
    return part:FindFirstAncestorWhichIsA("Accessory") ~= nil
        or part:FindFirstAncestorWhichIsA("Accoutrement") ~= nil
end

local function IsToolPart(part)
    return part:FindFirstAncestorWhichIsA("Tool") ~= nil
end

local function GetBodyParts(character)
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

local function GetBounds(character)
    local parts = GetBodyParts(character)
    if #parts == 0 then return nil end
    local min = Vector3.new(1e9, 1e9, 1e9)
    local max = Vector3.new(-1e9, -1e9, -1e9)
    for _, p in ipairs(parts) do
        local cf = p.CFrame
        local s = p.Size * 0.5
        for _, c in ipairs({
            cf * Vector3.new(-s.X, -s.Y, -s.Z), cf * Vector3.new( s.X, -s.Y, -s.Z),
            cf * Vector3.new(-s.X,  s.Y, -s.Z), cf * Vector3.new( s.X,  s.Y, -s.Z),
            cf * Vector3.new(-s.X, -s.Y,  s.Z), cf * Vector3.new( s.X, -s.Y,  s.Z),
            cf * Vector3.new(-s.X,  s.Y,  s.Z), cf * Vector3.new( s.X,  s.Y,  s.Z),
        }) do
            min = Vector3.new(math.min(min.X, c.X), math.min(min.Y, c.Y), math.min(min.Z, c.Z))
            max = Vector3.new(math.max(max.X, c.X), math.max(max.Y, c.Y), math.max(max.Z, c.Z))
        end
    end
    return { Min = min, Max = max }
end

local function GetScreenBox(box, camera)
    if not box then return nil end
    local corners = {
        Vector3.new(box.Min.X, box.Min.Y, box.Min.Z),
        Vector3.new(box.Max.X, box.Min.Y, box.Min.Z),
        Vector3.new(box.Min.X, box.Max.Y, box.Min.Z),
        Vector3.new(box.Max.X, box.Max.Y, box.Min.Z),
        Vector3.new(box.Min.X, box.Min.Y, box.Max.Z),
        Vector3.new(box.Max.X, box.Min.Y, box.Max.Z),
        Vector3.new(box.Min.X, box.Max.Y, box.Max.Z),
        Vector3.new(box.Max.X, box.Max.Y, box.Max.Z),
    }
    local minX, minY, maxX, maxY = 1e9, 1e9, -1e9, -1e9
    local any = false
    for _, c in ipairs(corners) do
        local sp = camera:WorldToViewportPoint(c)
        if sp.Z > 0 then
            any = true
            minX = math.min(minX, sp.X); minY = math.min(minY, sp.Y)
            maxX = math.max(maxX, sp.X); maxY = math.max(maxY, sp.Y)
        end
    end
    if not any then return nil end
    return minX, minY, maxX, maxY
end

local function GetSkeletonLinks(character)
    local hasR15 = character:FindFirstChild("UpperTorso") ~= nil
    if hasR15 then
        return {
            { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
            { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
            { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
            { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
            { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
        }
    end
    return {
        { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
        { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
    }
end

-----------------------------------------------------
-- Cache creation (Frame-based, cleanup-aware)
-----------------------------------------------------
local function CreateCache()
    local container = Create("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), Visible = false, ZIndex = 100, Parent = sg,
    })
    local lines = {}
    for i = 1, 120 do
        lines[i] = Create("Frame", {
            BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0,
            BorderSizePixel = 0, Size = UDim2.new(0, 1, 0, 1),
            Visible = false, ZIndex = 100, Parent = container,
        })
    end
    local nameLbl = Create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 14,
        TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.new(0, 0, 0),
        TextStrokeTransparency = 1 - (190/255), Size = UDim2.new(0, 200, 0, 16),
        AnchorPoint = Vector2.new(0.5, 1), Visible = false, ZIndex = 101, Parent = container,
    })
    local itemLbl = Create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.new(0, 0, 0),
        TextStrokeTransparency = 1 - (190/255), Size = UDim2.new(0, 200, 0, 14),
        AnchorPoint = Vector2.new(0.5, 0), Visible = false, ZIndex = 101, Parent = container,
    })
    local healthOuter = Create("Frame", {
        BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1 - (150/255),
        BorderSizePixel = 0, Visible = false, ZIndex = 100, Parent = container,
    })
    local healthFill = Create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 100, Parent = healthOuter,
    })

    local cache = {
        Container = container, Lines = lines, Name = nameLbl, Item = itemLbl,
        HealthOuter = healthOuter, HealthFill = healthFill, LineIndex = 1,
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
    function cache.Destroy()
        if container then pcall(function() container:Destroy() end) end
    end
    return cache
end

-----------------------------------------------------
-- Drawing
-----------------------------------------------------
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

local function DrawBorder(cache, x, y, ex, ey, t, col, trans)
    DrawRect(cache, x - t, y - t, (ex - x) + t*2, t, col, trans)
    DrawRect(cache, x - t, ey, (ex - x) + t*2, t, col, trans)
    DrawRect(cache, x - t, y, t, ey - y, col, trans)
    DrawRect(cache, ex, y, t, ey - y, col, trans)
end

local function DrawRotatedLine(cache, p1, p2, color, thickness)
    local l = cache.Lines[cache.LineIndex]
    if not l then return end
    local distance = (p1 - p2).Magnitude
    if distance < 0.5 then cache.LineIndex = cache.LineIndex + 1; return end
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

local function GetColor(plr)
    if ESP.Settings.TeamColors and plr.TeamColor and LocalPlayer.TeamColor
       and plr.TeamColor == LocalPlayer.TeamColor then
        return ESP.Settings.FriendColor
    end
    return ESP.Settings.EnemyColor
end

local function DrawBoxFor(cache, character, box3d, camera, color, name, hpProg, itemName)
    local minX, minY, maxX, maxY = GetScreenBox(box3d, camera)
    if not minX or maxX <= minX or maxY <= minY then return false end

    cache.Container.Visible = true
    cache.LineIndex = 1
    cache.Name.Visible = false
    cache.Item.Visible = false
    cache.HealthOuter.Visible = false

    local x, y, ex, ey = minX, minY, maxX, maxY

    -- Box
    if ESP.Settings.Boxes then
        if ESP.Settings.BoxMode == "Box" then
            DrawBorder(cache, x - 1, y - 1, ex + 1, ey + 1, 1, Color3.new(0, 0, 0), 1 - (150/255))
            DrawBorder(cache, x + 1, y + 1, ex - 1, ey - 1, 1, Color3.new(0, 0, 0), 1 - (150/255))
            DrawBorder(cache, x, y, ex, ey, 1, color, 0)
        elseif ESP.Settings.BoxMode == "Corner A" then
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
        elseif ESP.Settings.BoxMode == "Split" then
            DrawRect(cache, x, y, 1, ey - y, color, 0)
            DrawRect(cache, ex, y, 1, ey - y, color, 0)
            DrawRect(cache, x, y + (ey - y) / 2, ex - x, 1, color, 0)
        else
            -- Corner B
            local len = (ex - x) / 3
            local vLen = (ey - y) / 3
            DrawRect(cache, x, y + len, 1, vLen, color, 0)
            DrawRect(cache, x + len, y, len, 1, color, 0)
            DrawRect(cache, ex, y, 1, vLen, color, 0)
            DrawRect(cache, ex - len, y, len, 1, color, 0)
            DrawRect(cache, x, ey - vLen, 1, vLen, color, 0)
            DrawRect(cache, x, ey, len, 1, color, 0)
            DrawRect(cache, ex, ey - vLen, 1, vLen, color, 0)
            DrawRect(cache, ex - len, ey, len, 1, color, 0)
        end
    end

    -- Health
    if hpProg and ESP.Settings.Health then
        cache.HealthOuter.Visible = true
        local diff = ey - y
        cache.HealthOuter.Position = UDim2.new(0, x - 6, 0, y)
        cache.HealthOuter.Size = UDim2.new(0, 4, 0, diff)
        local hpCol = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 255, 0), hpProg)
        cache.HealthFill.BackgroundColor3 = hpCol
        cache.HealthFill.Position = UDim2.new(0, 1, 0, 1 + (diff - 2) * (1 - hpProg))
        cache.HealthFill.Size = UDim2.new(1, -2, 0, math.max(0, (diff - 2) * hpProg))
    end

    -- Name
    if name and ESP.Settings.Names then
        cache.Name.Visible = true
        cache.Name.Text = name
        cache.Name.TextColor3 = color
        cache.Name.Position = UDim2.new(0, x + (ex - x) / 2, 0, y - 3)
    end

    -- Item
    if itemName and ESP.Settings.Items then
        cache.Item.Visible = true
        cache.Item.Text = itemName
        cache.Item.Position = UDim2.new(0, x + (ex - x) / 2, 0, ey + 3)
    end

    -- Skeleton
    if ESP.Settings.Skeleton and character then
        for _, link in ipairs(GetSkeletonLinks(character)) do
            local p1 = character:FindFirstChild(link[1])
            local p2 = character:FindFirstChild(link[2])
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
    return true
end

-----------------------------------------------------
-- Main update (touch-set cleanup)
-----------------------------------------------------
local touchedPlayers = {}
local touchedOrphans = {}

local function Update()
    local camera = Workspace.CurrentCamera
    if not camera then return end

    for k in pairs(touchedPlayers) do touchedPlayers[k] = nil end
    for k in pairs(touchedOrphans) do touchedOrphans[k] = nil end

    if not ESP.Settings.Enabled then
        for _, cache in pairs(ESP.Cache) do
            cache.Container.Visible = false
            cache.Hide()
        end
        for _, cache in pairs(ESP.OrphanCache) do
            cache.Container.Visible = false
            cache.Hide()
        end
        return
    end

    -- Player pass
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if not ESP.Cache[plr] then ESP.Cache[plr] = CreateCache() end
        local cache = ESP.Cache[plr]

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
        if ESP.Settings.TeamCheck and plr.Team and LocalPlayer.Team
           and plr.Team == LocalPlayer.Team then
            cache.Container.Visible = false
            cache.Hide()
            continue
        end

        local box3d = GetBounds(char)
        if box3d then
            touchedPlayers[plr] = true
            local hpProg = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            local tool = char:FindFirstChildOfClass("Tool")
            local itemName = tool and tool.Name or nil
            local drawn = DrawBoxFor(cache, char, box3d, camera, GetColor(plr), plr.DisplayName, hpProg, itemName)
            if not drawn then
                cache.Container.Visible = false
                cache.Hide()
            end
        else
            cache.Container.Visible = false
            cache.Hide()
        end
    end

    -- Orphan pass (unclaimed Characters folder models)
    local folder = Workspace:FindFirstChild("Characters")
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            if not m:IsA("Model") then continue end
            local belongsToTracked = false
            for plr in pairs(touchedPlayers) do
                if plr.Character == m then belongsToTracked = true; break end
            end
            if belongsToTracked then continue end

            if not ESP.OrphanCache[m] then ESP.OrphanCache[m] = CreateCache() end
            local cache = ESP.OrphanCache[m]
            touchedOrphans[m] = true

            local box3d = GetBounds(m)
            if box3d then
                local drawn = DrawBoxFor(cache, m, box3d, camera, ESP.Settings.OrphanColor, "??? (" .. m.Name .. ")", nil, nil)
                if not drawn then
                    cache.Container.Visible = false
                    cache.Hide()
                end
            else
                cache.Container.Visible = false
                cache.Hide()
            end
        end
    end

    -- Cleanup player caches
    for plr, cache in pairs(ESP.Cache) do
        if not touchedPlayers[plr] then
            cache.Container.Visible = false
            cache.Hide()
        end
        if not plr or not plr.Parent then
            pcall(cache.Destroy)
            ESP.Cache[plr] = nil
        end
    end

    -- Cleanup orphan caches
    for m, cache in pairs(ESP.OrphanCache) do
        if not touchedOrphans[m] then
            cache.Container.Visible = false
            cache.Hide()
            local stillInFolder = false
            if m and m.Parent then
                local p = m.Parent
                while p do
                    if p.Name == "Characters" then stillInFolder = true; break end
                    p = p.Parent
                end
            end
            if not stillInFolder then
                pcall(cache.Destroy)
                ESP.OrphanCache[m] = nil
            end
        end
    end
end

RunService.RenderStepped:Connect(function()
    pcall(Update)
end)

Players.PlayerRemoving:Connect(function(plr)
    local cache = ESP.Cache[plr]
    if cache then
        pcall(cache.Destroy)
        ESP.Cache[plr] = nil
    end
end)

print("[Exhibition ESP] Loaded (v10 standalone)")
return ESP
