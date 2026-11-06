--[[
    Exhibition Dynamic ESP  —  ESP_VERSION_7_CLEANUP
    Fixes:
      - Orphan boxes now hide when their model leaves Characters/ or dies.
      - Touch-set tracking: only draw caches present this frame.
      - Death attribute detection (Dead / IsDead / Health=0 / Ragdoll).
      - Cache cleanup for orphan models that get destroyed.
      - Everything from v6 (resolver, sanity checks, spawn log) preserved.
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
        OrphanColor = Color3.fromRGB(180, 180, 180),
        TeamCheck = false, TeamColors = false,
        SkeletonColor = Color3.fromRGB(255, 255, 255),
        IncludeAccessories = false,
        SkeletonMode = "Auto",
        BoundsPadding = 0.1,
        MaxBoundsStuds = 40,
        ShowUnknownCharacters = true,
        HideDeadOrphans = true,
    },
    Cache = {},
    OrphanCache = {},
    BoundsCache = {},
    BoundsCacheTime = {},
    BoundsRefPos = {},
    ResolverCache = {},
    ResolverCacheTime = {},
    ResolverCacheSrc = {},
    CharacterSpawnLog = {},
}

print("[Exhibition ESP] Loading ESP_VERSION_7_CLEANUP...")

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
    Red = Color3.fromRGB(255, 0, 0), Yellow = Color3.fromRGB(255, 255, 0), Green = Color3.fromRGB(0, 255, 0),
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
-- CharacterSpawnLog
-----------------------------------------------------
local function HookPlayerForSpawns(plr)
    plr.CharacterAdded:Connect(function(char)
        ESP.CharacterSpawnLog[plr] = char
    end)
    if plr.Character then ESP.CharacterSpawnLog[plr] = plr.Character end
end

for _, plr in ipairs(Players:GetPlayers()) do HookPlayerForSpawns(plr) end
Players.PlayerAdded:Connect(HookPlayerForSpawns)


-----------------------------------------------------
-- Death detection
-----------------------------------------------------
-- Looks at attributes and value objects to detect "this rig is dead."
-- Also checks for Humanoid.Health = 0 if present.
local function IsModelDead(model)
    -- Humanoid (if any)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return true end

    -- Common death attributes
    local deathAttrs = {
        "Dead", "IsDead", "Death", "Died", "Ragdoll", "IsRagdoll",
        "Alive", "IsAlive", "Health", "HP",
    }
    for _, attrName in ipairs(deathAttrs) do
        local ok, val = pcall(function() return model:GetAttribute(attrName) end)
        if ok and val ~= nil then
            if type(val) == "boolean" then
                if (attrName == "Alive" or attrName == "IsAlive") and val == false then return true end
                if (attrName == "Dead" or attrName == "IsDead" or attrName == "Died" or attrName == "Ragdoll" or attrName == "IsRagdoll") and val == true then return true end
            elseif type(val) == "number" then
                if (attrName == "Health" or attrName == "HP") and val <= 0 then return true end
            end
        end
    end

    -- Value children
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BoolValue") then
            local n = child.Name:lower()
            if (n:find("dead") or n:find("ragdoll")) and child.Value then return true end
            if n:find("alive") and not child.Value then return true end
        elseif child:IsA("NumberValue") then
            local n = child.Name:lower()
            if (n == "health" or n == "hp") and child.Value <= 0 then return true end
        end
    end

    -- Model name indicates dead state
    local n = model.Name:lower()
    if n:find("dead") or n:find("ragdoll") or n:find("corpse") then return true end

    return false
end

-- Check if a similarly-named model exists in a Ragdolls/DeadBodies folder.
-- If so, the Characters/ version is almost certainly a dead state.
local function HasRagdollTwin(model)
    if not model.Name or model.Name == "" then return false end
    local ragdollFolders = { "Ragdolls", "DeadBodies", "Corpses", "Dead" }
    for _, fname in ipairs(ragdollFolders) do
        local folder = Workspace:FindFirstChild(fname)
        if folder then
            local twin = folder:FindFirstChild(model.Name)
            if twin then return true end
        end
    end
    return false
end


-----------------------------------------------------
-- Resolver (unchanged from v6)
-----------------------------------------------------
local SKIP_FOLDERS = { Debris = true, Ragdolls = true, Effects = true, Particles = true, Fx = true, VFX = true }

local CharacterMap = {}
local CharacterMapTime = 0
local CHARACTER_MAP_TTL = 4.0
local RESOLVER_CACHE_TTL = 0.3

local function LooksLikeCharacter(model)
    if not model:IsA("Model") then return false end
    return model:FindFirstChildOfClass("Humanoid") ~= nil
        or model:FindFirstChild("HumanoidRootPart") ~= nil
        or model:FindFirstChild("Head") ~= nil
        or model:FindFirstChild("UpperTorso") ~= nil
        or model:FindFirstChild("Torso") ~= nil
end

local function TryMatchInCharacters(plr)
    local folder = Workspace:FindFirstChild("Characters")
    if not folder then return nil, nil end

    local byName = folder:FindFirstChild(plr.Name)
    if byName and LooksLikeCharacter(byName) then return byName, "Characters[exact]" end

    local byUidName = folder:FindFirstChild(tostring(plr.UserId))
    if byUidName and LooksLikeCharacter(byUidName) then return byUidName, "Characters[UserId]" end

    for _, m in ipairs(folder:GetChildren()) do
        if not LooksLikeCharacter(m) then continue end
        local attrUid = m:GetAttribute("UserId") or m:GetAttribute("PlayerId") or m:GetAttribute("OwnerId") or m:GetAttribute("Owner")
        if attrUid == plr.UserId or attrUid == plr.Name then
            return m, "Characters[" .. m.Name .. "].attr"
        end
        for _, child in ipairs(m:GetChildren()) do
            if child:IsA("StringValue") then
                local n = child.Name:lower()
                if (n:find("player") or n == "owner" or n == "username") and child.Value == plr.Name then
                    return m, "Characters[" .. m.Name .. "]." .. child.Name
                end
            elseif child:IsA("ObjectValue") and child.Value == plr then
                return m, "Characters[" .. m.Name .. "]." .. child.Name
            end
        end
        local hum = m:FindFirstChildOfClass("Humanoid")
        if hum and (hum.DisplayName == plr.DisplayName or hum.DisplayName == plr.Name or hum.Name == plr.Name) then
            return m, "Characters[" .. m.Name .. "].Humanoid"
        end
        if #plr.Name >= 5 and #m.Name >= 5 and #m.Name <= #plr.Name + 6 then
            if m.Name:find(plr.Name, 1, true) or plr.Name:find(m.Name, 1, true) then
                return m, "Characters[" .. m.Name .. "].contains"
            end
        end
    end
    return nil, nil
end

local function RefreshCharacterMap()
    local now = os.clock()
    if now - CharacterMapTime < CHARACTER_MAP_TTL then return end
    CharacterMapTime = now
    local map = {}
    local function scan(container, depth)
        if depth > 3 then return end
        local ok, children = pcall(function() return container:GetChildren() end)
        if not ok then return end
        for _, child in ipairs(children) do
            if SKIP_FOLDERS[child.Name] then continue end
            if child:IsA("Model") then
                if LooksLikeCharacter(child) and not map[child.Name] then map[child.Name] = child end
                scan(child, depth + 1)
            elseif child:IsA("Folder") then
                scan(child, depth + 1)
            end
        end
    end
    scan(Workspace, 0)
    CharacterMap = map
end

local function ResolveCharacter(plr)
    local now = os.clock()
    local cached = ESP.ResolverCache[plr]
    local cachedTime = ESP.ResolverCacheTime[plr] or 0
    if now - cachedTime < RESOLVER_CACHE_TTL then
        if cached and typeof(cached) == "Instance" and cached.Parent then
            return cached, ESP.ResolverCacheSrc[plr] or "cached"
        end
        if cached == false then
            return nil, tostring(ESP.ResolverCacheSrc[plr] or "cached-miss")
        end
    end

    local result, source = nil, "unresolved"
    if plr.Character then result, source = plr.Character, "Player.Character" end
    if not result then
        local cap = ESP.CharacterSpawnLog[plr]
        if cap and typeof(cap) == "Instance" and cap.Parent then result, source = cap, "CharacterAdded log" end
    end
    if not result then
        local m, s = TryMatchInCharacters(plr)
        if m then result, source = m, s or "Characters" end
    end
    if not result then
        local direct = Workspace:FindFirstChild(plr.Name)
        if direct and LooksLikeCharacter(direct) then result, source = direct, "Workspace." .. plr.Name end
    end
    if not result then
        RefreshCharacterMap()
        local byUid = CharacterMap[tostring(plr.UserId)]
        if byUid and byUid.Parent then result, source = byUid, "Cached[UserId]" end
    end
    if not result then
        local byName = CharacterMap[plr.Name]
        if byName and byName.Parent then result, source = byName, "Cached[exact]" end
    end
    if not result then
        for name, model in pairs(CharacterMap) do
            if model.Parent and #name >= 5 and #plr.Name >= 5 and math.abs(#name - #plr.Name) <= 4 then
                if name:find(plr.Name, 1, true) or plr.Name:find(name, 1, true) then
                    result, source = model, "Fuzzy[" .. name .. "]"
                    break
                end
            end
        end
    end

    ESP.ResolverCache[plr] = result or false
    ESP.ResolverCacheTime[plr] = now
    ESP.ResolverCacheSrc[plr] = source or "unresolved"
    return result, source or "unresolved"
end


-----------------------------------------------------
-- Bounds
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
            if d.Transparency >= 1 and d.Name ~= "HumanoidRootPart" and d ~= character.PrimaryPart then continue end
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
    local dims = max - min
    if dims.X > ESP.Settings.MaxBoundsStuds or dims.Y > ESP.Settings.MaxBoundsStuds or dims.Z > ESP.Settings.MaxBoundsStuds then return nil end
    if dims.Magnitude < 0.5 then return nil end
    local pad = ESP.Settings.BoundsPadding
    if pad and pad > 0 then
        min = min - Vector3.new(pad, pad, pad)
        max = max + Vector3.new(pad, pad, pad)
    end
    return { Min = min, Max = max, Character = character, Ref = parts[1] }
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
            minX = math.min(minX, screen.X); minY = math.min(minY, screen.Y)
            maxX = math.max(maxX, screen.X); maxY = math.max(maxY, screen.Y)
        end
    end
    if not any then return nil end
    return minX, minY, maxX, maxY
end

local BOUNDS_TTL = 0.05
local BOUNDS_MOVE_EPS = 0.08

function PlayerUtils.GetCachedBoundingBox(character)
    local now = os.clock()
    local cached = ESP.BoundsCache[character]
    local cachedTime = ESP.BoundsCacheTime[character] or 0
    local refPos = ESP.BoundsRefPos[character]
    if cached and refPos and now - cachedTime < BOUNDS_TTL then
        if cached.Ref and cached.Ref.Parent and (cached.Ref.Position - refPos).Magnitude < BOUNDS_MOVE_EPS then
            return cached
        end
    end
    local box = PlayerUtils.GetBoundingBox(character)
    ESP.BoundsCache[character] = box
    ESP.BoundsCacheTime[character] = now
    if box and box.Ref then ESP.BoundsRefPos[character] = box.Ref.Position end
    return box
end


-----------------------------------------------------
-- Drawables
-----------------------------------------------------
local LINE_POOL_SIZE = 120

local function CreateESPCache()
    local container = Create("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), Visible = false, ZIndex = 100, Parent = sg,
    })
    local lines = {}
    for i = 1, LINE_POOL_SIZE do
        table.insert(lines, Create("Frame", {
            BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0,
            BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(0, 1, 0, 1), Visible = false, ZIndex = 100, Parent = container,
        }))
    end
    local nameLbl = Create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 14,
        TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.new(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255), Size = UDim2.new(0, 200, 0, 16),
        AnchorPoint = Vector2.new(0.5, 1), Visible = false, ZIndex = 101, Parent = container,
    })
    local itemLbl = Create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.new(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255), Size = UDim2.new(0, 200, 0, 14),
        AnchorPoint = Vector2.new(0.5, 0), Visible = false, ZIndex = 101, Parent = container,
    })
    local healthOuter = Create("Frame", {
        BackgroundColor3 = Colors.BlackTrans, BackgroundTransparency = BLACK_TRANS,
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
        nameLbl.Visible = false; itemLbl.Visible = false; healthOuter.Visible = false
    end
    function cache.HideFrom(idx)
        for i = idx, #lines do lines[i].Visible = false end
    end
    function cache.Destroy()
        if container then container:Destroy() end
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

local function DrawBorderedRect(cache, x, y, ex, ey, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, y - thickness, (ex - x) + thickness * 2, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, ey, (ex - x) + thickness * 2, thickness, outCol, outTrans)
    DrawRect(cache, x - thickness, y, thickness, ey - y, outCol, outTrans)
    DrawRect(cache, ex, y, thickness, ey - y, outCol, outTrans)
end

local function DrawBoxFor(cache, box3d, camera, color, name, hpProg)
    local minX, minY, maxX, maxY = PlayerUtils.GetScreenBox(box3d, camera)
    if not minX or maxX <= minX or maxY <= minY then return false end

    cache.Container.Visible = true
    cache.LineIndex = 1
    cache.Name.Visible = false; cache.Item.Visible = false; cache.HealthOuter.Visible = false

    local x, y, ex, ey = minX, minY, maxX, maxY

    if ESP.Settings.Boxes then
        if ESP.Settings.BoxMode == "Box" then
            DrawBorderedRect(cache, x - 1, y - 1, ex + 1, ey + 1, 1, Colors.BlackTrans, BLACK_TRANS)
            DrawBorderedRect(cache, x + 1, y + 1, ex - 1, ey - 1, 1, Colors.BlackTrans, BLACK_TRANS)
            DrawBorderedRect(cache, x, y, ex, ey, 1, color, 0)
        else
            local len = (ex - x) / 4
            local vLen = (ey - y) / 4
            DrawRect(cache, x, y, 1, vLen, color, 0); DrawRect(cache, x, y, len, 1, color, 0)
            DrawRect(cache, ex, y, 1, vLen, color, 0); DrawRect(cache, ex - len, y, len, 1, color, 0)
            DrawRect(cache, x, ey - vLen, 1, vLen, color, 0); DrawRect(cache, x, ey, len, 1, color, 0)
            DrawRect(cache, ex, ey - vLen, 1, vLen, color, 0); DrawRect(cache, ex - len, ey, len, 1, color, 0)
        end
    end

    if hpProg and ESP.Settings.Health then
        cache.HealthOuter.Visible = true
        local diff = ey - y
        cache.HealthOuter.Position = UDim2.new(0, x - 6, 0, y)
        cache.HealthOuter.Size = UDim2.new(0, 4, 0, diff)
        cache.HealthFill.BackgroundColor3 = BlendColors(hpProg)
        cache.HealthFill.Position = UDim2.new(0, 1, 0, 1 + (diff - 2) * (1 - hpProg))
        cache.HealthFill.Size = UDim2.new(1, -2, 0, math.max(0, (diff - 2) * hpProg))
    end

    if name and ESP.Settings.Names then
        cache.Name.Visible = true
        cache.Name.Text = name
        cache.Name.TextColor3 = color
        cache.Name.Position = UDim2.new(0, x + (ex - x) / 2, 0, y - 3)
    end

    cache.HideFrom(cache.LineIndex)
    return true
end


-----------------------------------------------------
-- Update loop with touch-set cleanup
-----------------------------------------------------
local matchedModels = {}
local touchedOrphans = {}
local lastSkipReason = {}

local function UpdateESP()
    local camera = Workspace.CurrentCamera
    if not camera then return end

    for k in pairs(matchedModels) do matchedModels[k] = nil end
    for k in pairs(touchedOrphans) do touchedOrphans[k] = nil end

    -- Player pass
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if not ESP.Cache[plr] then ESP.Cache[plr] = CreateESPCache() end
        local cache = ESP.Cache[plr]

        if not ESP.Settings.Enabled then
            cache.Container.Visible = false; cache.Hide()
            lastSkipReason[plr] = "disabled"
            continue
        end

        local char, source = ResolveCharacter(plr)
        source = tostring(source or "unknown")

        if not char then
            cache.Container.Visible = false; cache.Hide()
            lastSkipReason[plr] = "no char (" .. source .. ")"
            continue
        end

        matchedModels[char] = plr

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then
            cache.Container.Visible = false; cache.Hide()
            lastSkipReason[plr] = "dead"
            continue
        end

        if ESP.Settings.TeamCheck and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
            cache.Container.Visible = false; cache.Hide()
            lastSkipReason[plr] = "team"
            continue
        end

        local box3d = PlayerUtils.GetCachedBoundingBox(char)
        if not box3d then
            cache.Container.Visible = false; cache.Hide()
            lastSkipReason[plr] = "no bounds"
            continue
        end

        local color = GetPlayerColor(plr)
        local displayName = (plr.DisplayName ~= "" and plr.DisplayName) or plr.Name
        local hpProg = hum and math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1) or nil

        local drawn = DrawBoxFor(cache, box3d, camera, color, displayName, hpProg)
        if drawn then
            lastSkipReason[plr] = nil
        else
            cache.Container.Visible = false; cache.Hide()
            lastSkipReason[plr] = "offscreen"
        end
    end

    -- Orphan pass
    if ESP.Settings.ShowUnknownCharacters then
        local charsFolder = Workspace:FindFirstChild("Characters")
        if charsFolder then
            for _, m in ipairs(charsFolder:GetChildren()) do
                if not m:IsA("Model") then continue end
                if matchedModels[m] then continue end   -- owned by a player

                if not ESP.OrphanCache[m] then ESP.OrphanCache[m] = CreateESPCache() end
                local cache = ESP.OrphanCache[m]

                if not ESP.Settings.Enabled then
                    cache.Container.Visible = false; cache.Hide()
                    continue
                end

                -- Death checks
                if ESP.Settings.HideDeadOrphans then
                    if IsModelDead(m) or HasRagdollTwin(m) then
                        cache.Container.Visible = false; cache.Hide()
                        continue
                    end
                end

                local box3d = PlayerUtils.GetCachedBoundingBox(m)
                if not box3d then
                    cache.Container.Visible = false; cache.Hide()
                    continue
                end

                touchedOrphans[m] = true

                local drawn = DrawBoxFor(cache, box3d, camera, ESP.Settings.OrphanColor, "??? (" .. m.Name .. ")", nil)
                if not drawn then
                    cache.Container.Visible = false; cache.Hide()
                end
            end
        end
    end

    -- CLEANUP: hide and destroy orphan caches whose model wasn't touched this frame
    for model, cache in pairs(ESP.OrphanCache) do
        if not touchedOrphans[model] then
            -- Not iterated this frame → model left Characters/ or died
            cache.Container.Visible = false
            cache.Hide()

            -- If the model is destroyed (Parent nil) or no longer in Characters/, drop the cache entirely
            local stillExists = model and model.Parent ~= nil
            local stillInCharacters = false
            if stillExists then
                local parent = model.Parent
                while parent do
                    if parent.Name == "Characters" then
                        stillInCharacters = true
                        break
                    end
                    parent = parent.Parent
                end
            end
            if not stillInCharacters then
                pcall(function() cache.Destroy() end)
                ESP.OrphanCache[model] = nil
                ESP.BoundsCache[model] = nil
                ESP.BoundsCacheTime[model] = nil
                ESP.BoundsRefPos[model] = nil
            end
        end
    end
end


-----------------------------------------------------
-- Diagnostics
-----------------------------------------------------
function ESP:Diagnose()
    print("════════ ESP DIAGNOSTIC V7 ════════")
    print("Enabled:", ESP.Settings.Enabled)
    print("ShowUnknown:", ESP.Settings.ShowUnknownCharacters, "| HideDead:", ESP.Settings.HideDeadOrphans)

    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        print("Characters (", #chars:GetChildren(), "children):")
        for _, m in ipairs(chars:GetChildren()) do
            local dead = IsModelDead(m)
            local twin = HasRagdollTwin(m)
            local parts = 0
            if m:IsA("Model") then
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("BasePart") then parts = parts + 1 end
                end
            end
            print(string.format("  '%s' parts=%d dead=%s ragdollTwin=%s cached=%s",
                m.Name, parts, tostring(dead), tostring(twin), tostring(ESP.OrphanCache[m] ~= nil)))
        end
    end
    print("Orphan caches:", #(function()
        local n = 0
        for _ in pairs(ESP.OrphanCache) do n = n + 1 end
        return {n}
    end)())
    print("════════════════════════════════")
end

-- Inspect a specific model's state (useful for finding the death marker)
function ESP:InspectModel(name)
    local chars = Workspace:FindFirstChild("Characters")
    if not chars then print("No Characters folder"); return end
    local m = chars:FindFirstChild(name)
    if not m then print("Model '" .. name .. "' not found in Characters"); return end
    print("─── Inspecting model '" .. name .. "' ───")
    print("  Name:", m.Name, "| ClassName:", m.ClassName)
    print("  Parent:", m.Parent and m.Parent:GetFullName() or "nil")
    print("  Humanoid:", tostring(m:FindFirstChildOfClass("Humanoid")))
    print("  Attributes:")
    local attrs = m:GetAttributes()
    if next(attrs) == nil then print("    (none)")
    else for k, v in pairs(attrs) do print("    " .. k .. " = " .. tostring(v)) end end
    print("  Direct children with values:")
    for _, c in ipairs(m:GetChildren()) do
        if c:IsA("ValueBase") then print("    " .. c.ClassName .. "[" .. c.Name .. "] = " .. tostring(c.Value))
        elseif c:IsA("Humanoid") then print("    Humanoid[" .. c.Name .. "] Health=" .. c.Health .. "/" .. c.MaxHealth) end
    end
    print("  IsModelDead:", tostring(IsModelDead(m)))
    print("  HasRagdollTwin:", tostring(HasRagdollTwin(m)))
    print("──────────────────────────────")
end

_G.ESP = ESP

local errorCount = 0
local lastEnabled = nil

RunService.RenderStepped:Connect(function()
    if ESP.Settings.Enabled ~= lastEnabled then
        print("[Exhibition ESP] Enabled changed to: " .. tostring(ESP.Settings.Enabled))
        lastEnabled = ESP.Settings.Enabled
        if ESP.Settings.Enabled then task.delay(1, function() ESP:Diagnose() end) end
    end
    local ok, err = pcall(UpdateESP)
    if not ok then
        errorCount = errorCount + 1
        if errorCount <= 5 then
            warn("[Exhibition ESP] Error #" .. errorCount .. ": " .. tostring(err))
        end
    end
end)

print("[Exhibition ESP] Loaded v7. Orphan cleanup active.")
print("  ESP:InspectModel('2')  — dump model state")
print("  ESP:Diagnose()         — full report")
return ESP
