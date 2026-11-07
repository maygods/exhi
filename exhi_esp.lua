--[[
    Exhibition Dynamic ESP  —  HARDENED (gethui)
    Works with ANY rig (R6, R15, Rthro, custom, single-mesh, NPCs).
    Uses gethui() for all GUI parenting to bypass CoreGui scans.
    Randomises every ScreenGui and GuiObject name to defeat signature scanning.
    Includes v8 death detection (attributes, ragdoll proximity, fall+stuck).
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
        DeadFallThreshold = 0.4,
        DeadStuckSeconds = 1.5,
        RagdollProximity = 4,
    },
    Cache = {}, OrphanCache = {},
    BoundsCache = {}, BoundsCacheTime = {}, BoundsRefPos = {},
    ResolverCache = {}, ResolverCacheTime = {}, ResolverCacheSrc = {},
    CharacterSpawnLog = {},
    MotionHistory = {},
}

-----------------------------------------------------
-- Random name generator (defeats signature scans)
-----------------------------------------------------
local function RandomName()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local s = ""
    for _ = 1, 16 do
        local idx = math.random(1, #chars)
        s = s .. chars:sub(idx, idx)
    end
    return s
end

-----------------------------------------------------
-- Hidden GUI parent (gethui)
-----------------------------------------------------
local function GetHiddenParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    -- Fallback: syn.protect_gui + cloneref
    if syn and syn.protect_gui then
        local sg = Instance.new("ScreenGui")
        pcall(function() syn.protect_gui(sg) end)
        if cloneref then
            pcall(function() sg.Parent = cloneref(CoreGui) end)
        else
            pcall(function() sg.Parent = CoreGui end)
        end
        return sg.Parent, sg
    end
    -- Last resort
    return LocalPlayer:WaitForChild("PlayerGui")
end

local espParent, preEspGui = GetHiddenParent()
local sg = preEspGui or Instance.new("ScreenGui")
sg.Name = RandomName()
sg.IgnoreGuiInset = true
sg.ResetOnSpawn = false
sg.DisplayOrder = 999
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = espParent

print("[Exhibition ESP] Hardened module loaded (gethui).")

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
-- Death detection
-----------------------------------------------------
local RAGDOLL_FOLDERS = { "Ragdolls", "DeadBodies", "Corpses", "Dead" }

local function FindNearbyRagdoll(model)
    local mpos
    local ok, pivot = pcall(function() return model:GetPivot().Position end)
    if ok and pivot then mpos = pivot
    elseif model.PrimaryPart then mpos = model.PrimaryPart.Position end
    if not mpos then return false end

    local prox = ESP.Settings.RagdollProximity
    for _, fname in ipairs(RAGDOLL_FOLDERS) do
        local folder = Workspace:FindFirstChild(fname)
        if folder then
            for _, r in ipairs(folder:GetChildren()) do
                if r:IsA("Model") then
                    local rpos
                    local ok2, rp = pcall(function() return r:GetPivot().Position end)
                    if ok2 and rp then rpos = rp
                    elseif r.PrimaryPart then rpos = r.PrimaryPart.Position end
                    if rpos and (mpos - rpos).Magnitude <= prox then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function GetRefPart(model)
    if model.PrimaryPart then return model.PrimaryPart end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp end
    local head = model:FindFirstChild("Head")
    if head then return head end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function IsCorpseByMotion(model)
    local ref = GetRefPart(model)
    if not ref then return false end

    local now = os.clock()
    local hist = ESP.MotionHistory[model]
    if not hist then
        ESP.MotionHistory[model] = { LastPos = ref.Position, LastMoveTime = now, FallStartTime = nil }
        return false
    end

    local moved = (ref.Position - hist.LastPos).Magnitude > 0.5
    if moved then
        hist.LastPos = ref.Position
        hist.LastMoveTime = now
        hist.FallStartTime = nil
        return false
    end

    local up = ref.CFrame.UpVector
    local fallen = up.Y < ESP.Settings.DeadFallThreshold
    if not fallen then
        hist.FallStartTime = nil
        return false
    end

    if not hist.FallStartTime then
        hist.FallStartTime = now
        return false
    end

    return (now - hist.FallStartTime) >= ESP.Settings.DeadStuckSeconds
end

local function IsModelDead(model)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return true, "humanoid" end

    local deathAttrs = {
        "Dead", "IsDead", "Death", "Died", "Ragdoll", "IsRagdoll",
        "Alive", "IsAlive", "Health", "HP",
    }
    for _, attrName in ipairs(deathAttrs) do
        local ok, val = pcall(function() return model:GetAttribute(attrName) end)
        if ok and val ~= nil then
            if type(val) == "boolean" then
                if (attrName == "Alive" or attrName == "IsAlive") and val == false then return true, "attr " .. attrName end
                if (attrName == "Dead" or attrName == "IsDead" or attrName == "Died" or attrName == "Ragdoll" or attrName == "IsRagdoll") and val == true then return true, "attr " .. attrName end
            elseif type(val) == "number" then
                if (attrName == "Health" or attrName == "HP") and val <= 0 then return true, "attr " .. attrName .. "=" .. val end
            end
        end
    end

    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BoolValue") then
            local n = child.Name:lower()
            if (n:find("dead") or n:find("ragdoll")) and child.Value then return true, "BoolValue " .. child.Name end
            if n:find("alive") and not child.Value then return true, "BoolValue " .. child.Name end
        elseif child:IsA("NumberValue") then
            local n = child.Name:lower()
            if (n == "health" or n == "hp") and child.Value <= 0 then return true, "NumberValue " .. child.Name end
        end
    end

    local n = model.Name:lower()
    if n:find("dead") or n:find("ragdoll") or n:find("corpse") then return true, "name" end
    return false, nil
end

local function IsOrphanDead(model)
    local byAttr, reason = IsModelDead(model)
    if byAttr then return true, reason end
    if FindNearbyRagdoll(model) then return true, "nearby ragdoll" end
    if IsCorpseByMotion(model) then return true, "fallen+stuck" end
    return false, nil
end

-----------------------------------------------------
-- Universal character resolution
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
    local byUid = folder:FindFirstChild(tostring(plr.UserId))
    if byUid and LooksLikeCharacter(byUid) then return byUid, "Characters[UserId]" end
    for _, m in ipairs(folder:GetChildren()) do
        if not LooksLikeCharacter(m) then continue end
        local attrUid = m:GetAttribute("UserId") or m:GetAttribute("PlayerId") or m:GetAttribute("OwnerId") or m:GetAttribute("Owner")
        if attrUid == plr.UserId or attrUid == plr.Name then return m, "Characters[" .. m.Name .. "].attr" end
        for _, c in ipairs(m:GetChildren()) do
            if c:IsA("StringValue") then
                local n = c.Name:lower()
                if (n:find("player") or n == "owner" or n == "username") and c.Value == plr.Name then
                    return m, "Characters[" .. m.Name .. "]." .. c.Name
                end
            elseif c:IsA("ObjectValue") and c.Value == plr then
                return m, "Characters[" .. m.Name .. "]." .. c.Name
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
    local function scan(c, d)
        if d > 3 then return end
        local ok, children = pcall(function() return c:GetChildren() end)
        if not ok then return end
        for _, ch in ipairs(children) do
            if SKIP_FOLDERS[ch.Name] then continue end
            if ch:IsA("Model") then
                if LooksLikeCharacter(ch) and not map[ch.Name] then map[ch.Name] = ch end
                scan(ch, d + 1)
            elseif ch:IsA("Folder") then scan(ch, d + 1) end
        end
    end
    scan(Workspace, 0)
    CharacterMap = map
end

local function ResolveCharacter(plr)
    local now = os.clock()
    local cached = ESP.ResolverCache[plr]
    local ct = ESP.ResolverCacheTime[plr] or 0
    if now - ct < RESOLVER_CACHE_TTL then
        if cached and typeof(cached) == "Instance" and cached.Parent then
            return cached, ESP.ResolverCacheSrc[plr] or "cached"
        end
        if cached == false then return nil, tostring(ESP.ResolverCacheSrc[plr] or "cached-miss") end
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
-- Bounds + drawables
-----------------------------------------------------
local PlayerUtils = {}

local function IsAccessoryPart(p)
    return p:FindFirstAncestorWhichIsA("Accessory") ~= nil or p:FindFirstAncestorWhichIsA("Accoutrement") ~= nil
end
local function IsToolPart(p) return p:FindFirstAncestorWhichIsA("Tool") ~= nil end

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
    if pad and pad > 0 then min = min - Vector3.new(pad, pad, pad); max = max + Vector3.new(pad, pad, pad) end
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
    local ct = ESP.BoundsCacheTime[character] or 0
    local rp = ESP.BoundsRefPos[character]
    if cached and rp and now - ct < BOUNDS_TTL then
        if cached.Ref and cached.Ref.Parent and (cached.Ref.Position - rp).Magnitude < BOUNDS_MOVE_EPS then
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
-- Drawables (randomised names)
-----------------------------------------------------
local LINE_POOL = 120

local function CreateESPCache()
    local container = Create("Frame", {
        Name = RandomName(),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), Visible = false, ZIndex = 100, Parent = sg,
    })
    local lines = {}
    for i = 1, LINE_POOL do
        table.insert(lines, Create("Frame", {
            Name = RandomName(),
            BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0,
            BorderSizePixel = 0, Size = UDim2.new(0, 1, 0, 1), Visible = false, ZIndex = 100, Parent = container,
        }))
    end
    local nameLbl = Create("TextLabel", {
        Name = RandomName(),
        BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 14,
        TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.new(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255), Size = UDim2.new(0, 200, 0, 16),
        AnchorPoint = Vector2.new(0.5, 1), Visible = false, ZIndex = 101, Parent = container,
    })
    local healthOuter = Create("Frame", {
        Name = RandomName(),
        BackgroundColor3 = Colors.BlackTrans, BackgroundTransparency = BLACK_TRANS,
        BorderSizePixel = 0, Visible = false, ZIndex = 100, Parent = container,
    })
    local healthFill = Create("Frame", {
        Name = RandomName(),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 100, Parent = healthOuter,
    })
    local cache = {
        Container = container, Lines = lines, Name = nameLbl,
        HealthOuter = healthOuter, HealthFill = healthFill, LineIndex = 1,
    }
    function cache.Hide()
        for _, l in ipairs(lines) do l.Visible = false end
        nameLbl.Visible = false; healthOuter.Visible = false
    end
    function cache.HideFrom(i) for j = i, #lines do lines[j].Visible = false end end
    function cache.Destroy() if container then container:Destroy() end end
    return cache
end

local function DrawRect(c, x, y, w, h, col, tr)
    local l = c.Lines[c.LineIndex]
    if not l then return end
    l.Visible = true
    l.Position = UDim2.new(0, x, 0, y)
    l.Size = UDim2.new(0, math.max(1, w), 0, math.max(1, h))
    l.BackgroundColor3 = col
    l.BackgroundTransparency = tr or 0
    l.Rotation = 0
    c.LineIndex = c.LineIndex + 1
end

local function DrawBorder(c, x, y, ex, ey, t, col, tr)
    DrawRect(c, x - t, y - t, (ex - x) + t*2, t, col, tr)
    DrawRect(c, x - t, ey, (ex - x) + t*2, t, col, tr)
    DrawRect(c, x - t, y, t, ey - y, col, tr)
    DrawRect(c, ex, y, t, ey - y, col, tr)
end

local function DrawBoxFor(cache, box3d, camera, color, name, hpProg)
    local minX, minY, maxX, maxY = PlayerUtils.GetScreenBox(box3d, camera)
    if not minX or maxX <= minX or maxY <= minY then return false end
    cache.Container.Visible = true
    cache.LineIndex = 1
    cache.Name.Visible = false; cache.HealthOuter.Visible = false
    local x, y, ex, ey = minX, minY, maxX, maxY

    if ESP.Settings.Boxes then
        if ESP.Settings.BoxMode == "Box" then
            DrawBorder(cache, x - 1, y - 1, ex + 1, ey + 1, 1, Colors.BlackTrans, BLACK_TRANS)
            DrawBorder(cache, x + 1, y + 1, ex - 1, ey - 1, 1, Colors.BlackTrans, BLACK_TRANS)
            DrawBorder(cache, x, y, ex, ey, 1, color, 0)
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
-- Update loop
-----------------------------------------------------
local matchedModels, touchedOrphans = {}, {}
local lastSkipReason = {}
local lastDeathReason = {}

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
        if not char then
            cache.Container.Visible = false; cache.Hide()
            lastSkipReason[plr] = "no char (" .. tostring(source) .. ")"
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
            continue
        end

        local box3d = PlayerUtils.GetCachedBoundingBox(char)
        if not box3d then
            cache.Container.Visible = false; cache.Hide()
            continue
        end

        local color = GetPlayerColor(plr)
        local displayName = (plr.DisplayName ~= "" and plr.DisplayName) or plr.Name
        local hpProg = hum and math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1) or nil
        local drawn = DrawBoxFor(cache, box3d, camera, color, displayName, hpProg)
        if not drawn then cache.Container.Visible = false; cache.Hide() end
    end

    -- Orphan pass
    if ESP.Settings.ShowUnknownCharacters then
        local charsFolder = Workspace:FindFirstChild("Characters")
        if charsFolder then
            for _, m in ipairs(charsFolder:GetChildren()) do
                if not m:IsA("Model") then continue end
                if matchedModels[m] then continue end

                if not ESP.OrphanCache[m] then ESP.OrphanCache[m] = CreateESPCache() end
                local cache = ESP.OrphanCache[m]

                if not ESP.Settings.Enabled then
                    cache.Container.Visible = false; cache.Hide()
                    continue
                end

                if ESP.Settings.HideDeadOrphans then
                    local dead, reason = IsOrphanDead(m)
                    if dead then
                        cache.Container.Visible = false; cache.Hide()
                        lastDeathReason[m] = reason
                        continue
                    end
                    lastDeathReason[m] = nil
                end

                local box3d = PlayerUtils.GetCachedBoundingBox(m)
                if not box3d then
                    cache.Container.Visible = false; cache.Hide()
                    continue
                end

                touchedOrphans[m] = true
                local drawn = DrawBoxFor(cache, box3d, camera, ESP.Settings.OrphanColor, "??? (" .. m.Name .. ")", nil)
                if not drawn then cache.Container.Visible = false; cache.Hide() end
            end
        end
    end

    -- Cleanup
    for model, cache in pairs(ESP.OrphanCache) do
        if not touchedOrphans[model] then
            cache.Container.Visible = false
            cache.Hide()
            local stillInCharacters = false
            if model and model.Parent then
                local p = model.Parent
                while p do
                    if p.Name == "Characters" then stillInCharacters = true; break end
                    p = p.Parent
                end
            end
            if not stillInCharacters then
                pcall(cache.Destroy)
                ESP.OrphanCache[model] = nil
                ESP.BoundsCache[model] = nil
                ESP.BoundsCacheTime[model] = nil
                ESP.BoundsRefPos[model] = nil
                ESP.MotionHistory[model] = nil
                lastDeathReason[model] = nil
            end
        end
    end
end

-----------------------------------------------------
-- Diagnostics
-----------------------------------------------------
local function CountOrphans()
    local n = 0
    for _ in pairs(ESP.OrphanCache) do n = n + 1 end
    return n
end

function ESP:Diagnose()
    print("════════ ESP DIAGNOSTIC (gethui) ════════")
    print("Enabled:", ESP.Settings.Enabled, "| HideDead:", ESP.Settings.HideDeadOrphans)

    local chars = Workspace:FindFirstChild("Characters")
    if chars then
        print("Characters (" .. #chars:GetChildren() .. "):")
        for _, m in ipairs(chars:GetChildren()) do
            if not m:IsA("Model") then continue end
            local dead, reason = IsOrphanDead(m)
            local ref = GetRefPart(m)
            local upY = ref and ref.CFrame.UpVector.Y or 0
            local moved = ref and ESP.MotionHistory[m] and (ref.Position - ESP.MotionHistory[m].LastPos).Magnitude or 0
            local parts = 0
            for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
            print(string.format("  '%s' parts=%d dead=%s(%s) upY=%.2f moved=%.2f",
                m.Name, parts, tostring(dead), reason or "-", upY, moved))
        end
    end

    local ragdolls = Workspace:FindFirstChild("Ragdolls")
    if ragdolls then
        print("Ragdolls (" .. #ragdolls:GetChildren() .. "):")
        for _, r in ipairs(ragdolls:GetChildren()) do
            local pos
            local ok, pv = pcall(function() return r:GetPivot().Position end)
            if ok then pos = pv end
            print(string.format("  '%s' class=%s pos=%s", r.Name, r.ClassName, pos and tostring(pos) or "?"))
        end
    end

    print("Orphan caches:", CountOrphans())
    print("════════════════════════════════")
end

function ESP:InspectModel(name)
    local chars = Workspace:FindFirstChild("Characters")
    if not chars then print("No Characters"); return end
    local m = chars:FindFirstChild(name)
    if not m then print("Model '" .. name .. "' not found"); return end
    print("─── Inspect '" .. name .. "' ───")
    local dead, reason = IsOrphanDead(m)
    print("  IsOrphanDead:", dead, "| reason:", reason or "-")
    local ref = GetRefPart(m)
    if ref then
        print("  Ref:", ref.Name, "| pos:", ref.Position, "| upY:", ref.CFrame.UpVector.Y)
        print("  Velocity:", ref.AssemblyLinearVelocity)
    end
    local hist = ESP.MotionHistory[m]
    if hist then
        print("  Motion: moved=" .. tostring((ref and (ref.Position - hist.LastPos).Magnitude or 0)) ..
              " | lastMove=" .. tostring(os.clock() - hist.LastMoveTime) .. "s ago" ..
              " | fallTimer=" .. (hist.FallStartTime and tostring(os.clock() - hist.FallStartTime) or "nil"))
    else
        print("  Motion: no history")
    end
    print("  Attributes:")
    for k, v in pairs(m:GetAttributes()) do print("    " .. k .. " = " .. tostring(v)) end
    print("  Near ragdoll:", FindNearbyRagdoll(m))
    print("──────────────────────────────")
end

_G.ESP = ESP

-----------------------------------------------------
-- Lifecycle
-----------------------------------------------------
local errorCount, lastEnabled = 0, nil

RunService.RenderStepped:Connect(function()
    if ESP.Settings.Enabled ~= lastEnabled then
        print("[Exhibition ESP] Enabled = " .. tostring(ESP.Settings.Enabled))
        lastEnabled = ESP.Settings.Enabled
        if ESP.Settings.Enabled then task.delay(1, function() ESP:Diagnose() end) end
    end
    local ok, err = pcall(UpdateESP)
    if not ok then
        errorCount = errorCount + 1
        if errorCount <= 5 then warn("[Exhibition ESP] Error #" .. errorCount .. ": " .. tostring(err)) end
    end
end)

print("[Exhibition ESP] Hardened module ready. Use ESP:Diagnose() or ESP:InspectModel('name').")
return ESP
