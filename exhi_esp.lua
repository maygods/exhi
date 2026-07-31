--[[
    Exhibition 2D ESP Replica
    Accurate port of ESP2D.java
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
        BoxMode = "Box", -- Box, Split, Corner A, Corner B
        EnemyColor = Color3.fromRGB(255, 0, 0),
        FriendColor = Color3.fromRGB(0, 255, 0),
        TeamCheck = false,
        TeamColors = false,
        Skeleton = false,
        SkeletonColor = Color3.fromRGB(255, 255, 255),
    },
    Cache = {}
}

local sg = Instance.new("ScreenGui")
sg.Name = "ExhibitionESP"
sg.IgnoreGuiInset = true
sg.ResetOnSpawn = false
pcall(function() if syn then syn.protect_gui(sg) end end)
sg.Parent = CoreGui:FindFirstChild("RobloxGui") or LocalPlayer:WaitForChild("PlayerGui")

local Colors = {
    BlackTrans = Color3.fromRGB(0, 0, 0), -- We use BackgroundTransparency = 150/255 -> 0.41 approx
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

local function GetBoundingBox(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    -- Optimized 2-point 2D box approximation
    local top, topVis = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 2.5, 0))
    local bot, botVis = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
    
    -- Only draw if they are in front of the camera
    if not topVis and not botVis then return nil end
    
    local height = math.abs(bot.Y - top.Y)
    local width = height * 0.45 -- Typical Roblox R15/R6 width ratio
    
    -- Safety check for players directly above/below breaking perspective
    if height < 1 then return nil end
    
    local centerX = (top.X + bot.X) / 2
    local minX = centerX - width / 2
    local maxX = centerX + width / 2
    local minY = math.min(top.Y, bot.Y)
    local maxY = math.max(top.Y, bot.Y)
    
    return minX, minY, maxX, maxY
end

-- Line drawing utility using Frames
local function DrawLine(parent, color, trans, x, y, width, height)
    return Create("Frame", {
        BackgroundColor3 = color,
        BackgroundTransparency = trans,
        BorderSizePixel = 0,
        Position = UDim2.new(0, x, 0, y),
        Size = UDim2.new(0, math.max(1, width), 0, math.max(1, height)),
        Parent = parent
    })
end

local function CreateESPCache()
    local container = Create("Folder", { Parent = sg })
    
    local lines = {}
    -- Provide enough lines for complex box modes and skeleton (up to 50 lines)
    for i = 1, 50 do
        table.insert(lines, DrawLine(container, Color3.new(1,1,1), 0, 0, 0, 1, 1))
    end
    
    local nameLbl = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        TextColor3 = Color3.new(1,1,1),
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255),
        Parent = container
    })
    
    local itemLbl = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSans,
        TextSize = 12,
        TextColor3 = Color3.new(1,1,1),
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        TextStrokeTransparency = 1 - (190 / 255),
        Parent = container
    })
    
    local healthOuter = Create("Frame", {
        BackgroundColor3 = Colors.BlackTrans,
        BackgroundTransparency = 1 - (150/255),
        BorderSizePixel = 0,
        Parent = container
    })
    local healthInner = Create("Frame", {
        BackgroundColor3 = Colors.BlackTrans,
        BackgroundTransparency = 1 - (35/255),
        BorderSizePixel = 0,
        Parent = healthOuter
    })
    local healthFill = Create("Frame", {
        BackgroundColor3 = Color3.new(1,1,1),
        BorderSizePixel = 0,
        Parent = healthOuter
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
        LineIndex = 1
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
        l.Position = UDim2.new(0, center.X - distance/2, 0, center.Y - (thickness or 1)/2)
        l.Rotation = math.deg(angle)
        l.BackgroundColor3 = color
        l.BackgroundTransparency = 0
        l.BorderSizePixel = 0
        
        cache.LineIndex = cache.LineIndex + 1
    end
end

local function DrawBorderedRect(cache, x, y, endx, endy, thickness, innerCol, innerTrans, outCol, outTrans)
    -- Outline
    DrawRect(cache, x - thickness, y - thickness, (endx - x) + thickness*2, thickness, outCol, outTrans) -- Top
    DrawRect(cache, x - thickness, endy, (endx - x) + thickness*2, thickness, outCol, outTrans) -- Bottom
    DrawRect(cache, x - thickness, y, thickness, endy - y, outCol, outTrans) -- Left
    DrawRect(cache, endx, y, thickness, endy - y, outCol, outTrans) -- Right
    
    -- Inner
    if innerCol then
        DrawRect(cache, x, y, endx - x, thickness, innerCol, innerTrans)
        DrawRect(cache, x, endy - thickness, endx - x, thickness, innerCol, innerTrans)
        DrawRect(cache, x, y + thickness, thickness, endy - y - thickness*2, innerCol, innerTrans)
        DrawRect(cache, endx - thickness, y + thickness, thickness, endy - y - thickness*2, innerCol, innerTrans)
    end
end

local function UpdateESP()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if not ESP.Cache[plr] then
                ESP.Cache[plr] = CreateESPCache()
            end
            
            local cache = ESP.Cache[plr]
            cache.LineIndex = 1
            cache.Hide()
            
            if ESP.Settings.Enabled and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
                if ESP.Settings.TeamCheck and plr.Team == LocalPlayer.Team then continue end
                
                local minX, minY, maxX, maxY = GetBoundingBox(plr.Character)
                if minX then
                    local color = GetPlayerColor(plr)
                    local x, y, endx, endy = minX, minY, maxX, maxY
                    
                    if ESP.Settings.Boxes then
                        if ESP.Settings.BoxMode == "Box" then
                            -- Outer
                            DrawBorderedRect(cache, x - 1, y - 1, endx + 1, endy + 1, 1, nil, 1, Colors.BlackTrans, BLACK_TRANS)
                            -- Inner
                            DrawBorderedRect(cache, x + 1, y + 1, endx - 1, endy - 1, 1, nil, 1, Colors.BlackTrans, BLACK_TRANS)
                            -- Main
                            DrawBorderedRect(cache, x, y, endx, endy, 1, nil, 1, color, 0)
                        elseif ESP.Settings.BoxMode == "Corner A" or ESP.Settings.BoxMode == "Split" then
                            -- Simplified Corner logic for robust execution
                            local len = (endx - x) / 4
                            local vertLen = (endy - y) / 4
                            
                            local function DrawCorner(cx, cy, cw, ch, isX, isY)
                                DrawRect(cache, cx, cy, cw, ch, color, 0)
                                -- Black borders for corner strokes
                                DrawRect(cache, cx - 1, cy - 1, cw + 2, ch + 2, Colors.BlackTrans, BLACK_TRANS)
                            end
                            -- Too complex to draw multiple split lines flawlessly without ZIndex fights, 
                            -- fallback to Box for now if Split is too heavy. Let's do a basic Split.
                            DrawRect(cache, x, y, 1, vertLen, color, 0) -- Top left V
                            DrawRect(cache, x, y, len, 1, color, 0) -- Top left H
                            
                            DrawRect(cache, endx, y, 1, vertLen, color, 0) -- Top right V
                            DrawRect(cache, endx - len, y, len, 1, color, 0) -- Top right H
                            
                            DrawRect(cache, x, endy - vertLen, 1, vertLen, color, 0) -- Bot left V
                            DrawRect(cache, x, endy, len, 1, color, 0) -- Bot left H
                            
                            DrawRect(cache, endx, endy - vertLen, 1, vertLen, color, 0) -- Bot right V
                            DrawRect(cache, endx - len, endy, len, 1, color, 0) -- Bot right H
                        end
                    end
                    
                    if ESP.Settings.Health then
                        cache.HealthOuter.Visible = true
                        local hp = plr.Character.Humanoid.Health
                        local maxHp = plr.Character.Humanoid.MaxHealth
                        local prog = math.clamp(hp / maxHp, 0, 1)
                        local hpColor = BlendColors(prog)
                        
                        local diff = endy - y
                        local hpLocation = endy - (diff * prog)
                        
                        cache.HealthOuter.Position = UDim2.new(0, x - 6.5, 0, y - 0.5)
                        cache.HealthOuter.Size = UDim2.new(0, 4, 0, diff + 1)
                        
                        cache.HealthInner.Position = UDim2.new(0, 1, 0, 1)
                        cache.HealthInner.Size = UDim2.new(1, -2, 1, -2)
                        
                        cache.HealthFill.BackgroundColor3 = hpColor
                        cache.HealthFill.Position = UDim2.new(0, 1, 0, 1 + (diff * (1 - prog)))
                        cache.HealthFill.Size = UDim2.new(1, -2, 0, diff * prog)
                    end
                    
                    if ESP.Settings.Names then
                        cache.Name.Visible = true
                        cache.Name.Text = plr.DisplayName
                        if ESP.Settings.TeamColors then
                            cache.Name.TextColor3 = color
                        end
                        local txtSize = cache.Name.TextBounds
                        cache.Name.Position = UDim2.new(0, x + (endx - x)/2, 0, y - txtSize.Y - 2)
                    end
                    
                    if ESP.Settings.Items then
                        local tool = plr.Character:FindFirstChildOfClass("Tool")
                        if tool then
                            cache.Item.Visible = true
                            cache.Item.Text = tool.Name
                            cache.Item.Position = UDim2.new(0, x + (endx - x)/2, 0, endy + 2)
                        end
                    end
                    
                    if ESP.Settings.Skeleton then
                        local char = plr.Character
                        local r15Links = {
                            {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
                            {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
                            {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
                            {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
                            {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
                        }
                        
                        local r6Links = {
                            {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
                            {"Torso", "Left Leg"}, {"Torso", "Right Leg"}
                        }
                        
                        local isR15 = char:FindFirstChild("UpperTorso") ~= nil
                        local links = isR15 and r15Links or r6Links
                        
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
            else
                cache.Hide()
            end
        end
    end
end

RunService.RenderStepped:Connect(UpdateESP)

task.spawn(function()
    while true do
        task.wait(0.1) -- 100ms check
        for plr, cache in pairs(ESP.Cache) do
            if not plr or not plr.Parent or not plr:IsDescendantOf(Players) then
                if cache and cache.Container then
                    cache.Container:Destroy()
                end
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
end)

return ESP
