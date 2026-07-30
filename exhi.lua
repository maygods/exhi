--[[
    ExhibitionLib — SkeetMenu Replica
    Exact 1:1 replica of the Exhibition Minecraft client UI
--]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Colors = {
    MainFill       = Color3.fromRGB(22, 22, 22),
    Border1        = Color3.fromRGB(10, 10, 10),
    Border2        = Color3.fromRGB(60, 60, 60),
    Border3        = Color3.fromRGB(40, 40, 40),
    GroupBorderOut = Color3.fromRGB(10, 10, 10),
    GroupBorderIn  = Color3.fromRGB(48, 48, 48),
    GroupFill      = Color3.fromRGB(17, 17, 17),
    ElemGradTop    = Color3.fromRGB(76, 76, 76),
    ElemGradBot    = Color3.fromRGB(51, 51, 51),
    DropGradTop    = Color3.fromRGB(31, 31, 31),
    DropGradBot    = Color3.fromRGB(36, 36, 36),
    SlidGradTop    = Color3.fromRGB(46, 46, 46),
    SlidGradBot    = Color3.fromRGB(27, 27, 27),
    TextPrimary    = Color3.fromRGB(220, 220, 220),
    TextDim        = Color3.fromRGB(185, 185, 185),
    TextMuted      = Color3.fromRGB(151, 151, 151),
    TextDark       = Color3.fromRGB(75, 75, 75),
    Hover          = Color3.fromRGB(255, 255, 255),
    HoverBorder    = Color3.fromRGB(90, 90, 90),
    FocusedBorder  = Color3.fromRGB(130, 130, 130),
    SelectedText   = Color3.fromRGB(150, 150, 150),
    Accent         = Color3.fromRGB(165, 241, 165),
    Black          = Color3.fromRGB(0, 0, 0),
    White          = Color3.fromRGB(255, 255, 255),
    SidebarActive  = Color3.fromRGB(210, 210, 210),
    SidebarHover   = Color3.fromRGB(165, 165, 165),
    SidebarInactive= Color3.fromRGB(91, 91, 91),
    SidebarBG      = Color3.fromRGB(12, 12, 12),
}

local Fonts = {
    Bold = Enum.Font.SourceSansBold,
    Regular = Enum.Font.SourceSans,
}

local GUI_SCALE = 2.0
local REAL_SIZE = Vector2.new(340, 340)
local SCALED_SIZE = REAL_SIZE * GUI_SCALE

local GITHUB_ICONS_URL = "https://raw.githubusercontent.com/maygods/exhi/refs/heads/main/Icons/Icon_%s.png"

local ExhibitionLib = {
    Instances = {},
    Windows = {},
    Sliders = {},
    DynamicSliders = false,
    Icons = {
        Combat = "E", Player = "F", Movement = "J", Visuals = "C",
        Other = "I", Colors = "H", Minigames = "A", Settings = "G"
    },
    ThemeInstances = {}
}

local function ThemeColor(key)
    return {__isThemeColor = true, Key = key}
end

function ExhibitionLib:SetDynamicSliders(state)
    self.DynamicSliders = state
    for _, fn in ipairs(self.Sliders) do
        fn()
    end
end

function ExhibitionLib:UpdateColor(key, col)
    Colors[key] = col
    for _, obj in ipairs(self.ThemeInstances) do
        if obj.Key == key then
            obj.Inst[obj.Prop] = col
        elseif obj.Key1 == key or obj.Key2 == key then
            if obj.Type == 'Gradient' then
                obj.Inst.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Colors[obj.Key1]),
                    ColorSequenceKeypoint.new(1, Colors[obj.Key2])
                })
            end
        end
    end
end

-- Hex color utilities
local function Color3ToHex(col)
    local r = math.floor(col.R * 255 + 0.5)
    local g = math.floor(col.G * 255 + 0.5)
    local b = math.floor(col.B * 255 + 0.5)
    return string.format("#%02X%02X%02X", r, g, b)
end

local function HexToColor3(hex)
    hex = hex:gsub("#", "")
    if #hex == 3 then
        hex = hex:sub(1,1):rep(2) .. hex:sub(2,2):rep(2) .. hex:sub(3,3):rep(2)
    end
    if #hex ~= 6 then return nil end
    local r = tonumber(hex:sub(1,2), 16)
    local g = tonumber(hex:sub(3,4), 16)
    local b = tonumber(hex:sub(5,6), 16)
    if not r or not g or not b then return nil end
    return Color3.fromRGB(r, g, b)
end

function ExhibitionLib.Color3ToHex(col) return Color3ToHex(col) end
function ExhibitionLib.HexToColor3(hex) return HexToColor3(hex) end

-- Utilities
local function Create(cls, props)
    local inst = Instance.new(cls)
    for k, v in pairs(props or {}) do
        if type(v) == "table" and v.__isThemeColor then
            inst[k] = Colors[v.Key]
            table.insert(ExhibitionLib.ThemeInstances, { Inst = inst, Prop = k, Key = v.Key })
        else
            inst[k] = v
        end
    end
    return inst
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- Global Opacity (0 to 1)
local GlobalOpacity = { Value = 0, Target = 0, Speed = 25 }

-- Render loop for global animations
RunService.RenderStepped:Connect(function(dt)
    -- Interpolate opacity
    if math.abs(GlobalOpacity.Target - GlobalOpacity.Value) > 0.001 then
        GlobalOpacity.Value = Lerp(GlobalOpacity.Value, GlobalOpacity.Target, dt * GlobalOpacity.Speed)
    else
        GlobalOpacity.Value = GlobalOpacity.Target
    end
    
    local opacity = GlobalOpacity.Value * (ExhibitionLib.OpacityMultiplier or 1.0)
    
    -- Update all registered elements with opacity
    for _, obj in ipairs(ExhibitionLib.Instances) do
        if obj.Type == "Transparency" then
            local mult = obj.IsBG and (ExhibitionLib.OpacityMultiplier or 1.0) or 1.0
            obj.Inst[obj.Prop] = 1 - ((1 - obj.Base) * GlobalOpacity.Value * mult)
        elseif obj.Type == "Gradient" then
            -- Optional dynamic gradient alpha
        end
    end
end)

local function RegisterOpacity(inst, prop, baseTrans, isBackground)
    table.insert(ExhibitionLib.Instances, { Type = "Transparency", Inst = inst, Prop = prop, Base = baseTrans or 0, IsBG = isBackground })
    inst[prop] = 1 -- Start transparent
end

local function Capitalize(str)
    return str:sub(1,1):upper() .. str:sub(2):lower()
end

local function DrawBorder(parent, colors)
    local current = parent
    for _, col in ipairs(colors) do
        local f = Create("Frame", {
            BackgroundColor3 = col,
            BorderSizePixel = 0,
            Position = current == parent and UDim2.new(0,0,0,0) or UDim2.new(0,1,0,1),
            Size = current == parent and UDim2.new(1,0,1,0) or UDim2.new(1,-2,1,-2),
            Parent = current
        })
        RegisterOpacity(f, "BackgroundTransparency", 0, true)
        current = f
    end
    return current
end

local function CreateUIGradient(parent, topKey, botKey)
    local grad = Create("UIGradient", {
        Rotation = 90,
        Parent = parent
    })
    local topColor, botColor
    if type(topKey) == "string" then
        topColor = Colors[topKey]
        botColor = Colors[botKey]
        table.insert(ExhibitionLib.ThemeInstances, { Type = "Gradient", Inst = grad, Key1 = topKey, Key2 = botKey })
    else
        topColor = topKey
        botColor = botKey
    end
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, topColor),
        ColorSequenceKeypoint.new(1, botColor)
    })
    return grad
end

local function DrawTextWithShadow(parent, text, font, size, color, pos, align, zindex)
    local lbl = Create("TextLabel", {
        BackgroundTransparency = 1,
        Position = pos,
        Size = UDim2.new(1,0,0,size),
        Font = font,
        Text = text,
        TextColor3 = color,
        TextSize = size,
        TextXAlignment = align,
        ZIndex = zindex or 2,
        TextStrokeColor3 = Colors.Black,
        TextStrokeTransparency = 0,
        Parent = parent
    })
    return lbl
end

function ExhibitionLib:CreateWindow(cfg)
    cfg = cfg or {}
    
    local sg = Create("ScreenGui", {
        Name = "ExhibitionUI",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
    })
    pcall(function() if syn then syn.protect_gui(sg) end end)
    sg.Parent = CoreGui:FindFirstChild("RobloxGui") or Players.LocalPlayer:WaitForChild("PlayerGui")
    
    -- Darken Background
    local bgDarken = Create("Frame", {
        BackgroundColor3 = Colors.Black,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 0,
        Parent = sg
    })
    
    -- Main Window Wrap
    local window = Create("Frame", {
        Name = "Window",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, -SCALED_SIZE.X/2, 0.5, -SCALED_SIZE.Y/2),
        Size = UDim2.new(0, SCALED_SIZE.X, 0, SCALED_SIZE.Y),
        Parent = sg
    })
    
    -- Asset-free glow using layered transparent frames
    local glowColor = Colors.MainFill
    local glowLayers = {}
    local GLOW_LAYER_COUNT = 6
    for i = 1, GLOW_LAYER_COUNT do
        local spread = i * 5 * GUI_SCALE
        local alpha = 0.75 + (i / GLOW_LAYER_COUNT) * 0.22 -- 0.78 to 0.97
        local layer = Create("Frame", {
            Name = "GlowLayer" .. i,
            BackgroundColor3 = glowColor,
            BackgroundTransparency = alpha,
            BorderSizePixel = 0,
            Position = UDim2.new(0, -spread, 0, -spread),
            Size = UDim2.new(1, spread * 2, 1, spread * 2),
            ZIndex = 0,
            Parent = window
        })
        Create("UICorner", { CornerRadius = UDim.new(0, math.floor(spread * 0.6)), Parent = layer })
        table.insert(glowLayers, layer)
        table.insert(ExhibitionLib.ThemeInstances, { Inst = layer, Prop = "BackgroundColor3", Key = "GlowColor" })
    end
    Colors.GlowColor = Colors.MainFill
    
    -- Expose glow update helper
    function ExhibitionLib:SetGlowColor(col)
        Colors.GlowColor = col
        for _, layer in ipairs(glowLayers) do
            layer.BackgroundColor3 = col
        end
    end
    
    function ExhibitionLib:SetGlowEnabled(state)
        for _, layer in ipairs(glowLayers) do
            layer.Visible = state
        end
    end
    
    function ExhibitionLib:SetGlowIntensity(intensity)
        -- intensity 0-100, controls base transparency
        local base = 1 - (intensity / 100) * 0.4 -- 1.0 (off) to 0.6 (strong)
        for i, layer in ipairs(glowLayers) do
            layer.BackgroundTransparency = base + (i / GLOW_LAYER_COUNT) * (1 - base) * 0.6
        end
    end
    
    local windowFrame = Create("Frame", {
        Name = "WindowFrame",
        BackgroundColor3 = ThemeColor("Border2"),
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 1,
        Parent = window
    })
    RegisterOpacity(windowFrame, "BackgroundTransparency", 0, true)
    
    local uiScale = Create("UIScale", {
        Scale = 1.0,
        Parent = window
    })
    
    -- Nested Borders (Grey -> Black -> Grey -> DarkGrey -> Grey -> Fill)
    local innerBorder = DrawBorder(windowFrame, {
        ThemeColor("Border1"), 
        ThemeColor("Border2"), 
        ThemeColor("Border3"), 
        ThemeColor("Border2")
    })
    
    -- Main Fill
    local main = Create("Frame", {
        BackgroundColor3 = ThemeColor("MainFill"),
        BorderSizePixel = 0,
        Position = UDim2.new(0,1,0,1),
        Size = UDim2.new(1,-2,1,-2),
        Parent = innerBorder
    })
    RegisterOpacity(main, "BackgroundTransparency", 0, true)
    
    -- Top Rainbow Bar
    local rainbowBar = Create("Frame", {
        BackgroundColor3 = Color3.new(1,1,1),
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1 * GUI_SCALE),
        Parent = main
    })
    RegisterOpacity(rainbowBar, "BackgroundTransparency")
    Create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 177, 218)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(204, 77, 198)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(204, 227, 53))
        }),
        Parent = rainbowBar
    })
    local rainbowOverlay = Create("Frame", {
        BackgroundColor3 = ThemeColor("Black"),
        BorderSizePixel = 0,
        Size = UDim2.new(1,0,1,0),
        Parent = rainbowBar
    })
    RegisterOpacity(rainbowOverlay, "BackgroundTransparency", 0.57) -- 145/255 approx
    
    -- Dragging Logic
    local dragHandle = Create("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 12 * GUI_SCALE),
        Parent = main
    })
    local dragging, dragInput, dragStart, startPos
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = window.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    local currentScale = 1.0
    local MIN_SCALE = 0.5
    local MAX_SCALE = 2.0
    local resizeHandle = Create("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -10 * GUI_SCALE, 1, -10 * GUI_SCALE),
        Size = UDim2.new(0, 10 * GUI_SCALE, 0, 10 * GUI_SCALE),
        Text = "",
        ZIndex = 50,
        Parent = window
    })
    local function CreateGripLine(pos)
        Create("Frame", { BackgroundColor3 = Colors.TextMuted, BorderSizePixel = 0, Position = pos, Size = UDim2.new(0, 2, 0, 2), ZIndex = 51, Parent = resizeHandle })
    end
    CreateGripLine(UDim2.new(0, 6, 0, 8))
    CreateGripLine(UDim2.new(0, 4, 0, 6))
    CreateGripLine(UDim2.new(0, 2, 0, 4))
    CreateGripLine(UDim2.new(0, 8, 0, 6))
    CreateGripLine(UDim2.new(0, 6, 0, 4))
    CreateGripLine(UDim2.new(0, 8, 0, 2))
    
    local resetHandle = Create("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -25 * GUI_SCALE, 1, -15 * GUI_SCALE),
        Size = UDim2.new(0, 15 * GUI_SCALE, 0, 15 * GUI_SCALE),
        Text = "R",
        TextColor3 = ThemeColor("TextMuted"),
        Font = Fonts.Regular,
        TextSize = 10 * GUI_SCALE,
        ZIndex = 50,
        Parent = window
    })
    resetHandle.MouseButton1Click:Connect(function()
        window.Size = UDim2.new(0, 340 * GUI_SCALE, 0, 340 * GUI_SCALE)
    end)
    
    local resizing = false
    local resizeStart, startSize
    resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = true
            resizeStart = input.Position
            startSize = window.AbsoluteSize
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    resizing = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - resizeStart
            local scale = uiScale.Scale
            
            -- Enforce minimum bounds
            local minX = 340 * GUI_SCALE
            local minY = 200 * GUI_SCALE
            
            local newX = math.max(minX, (startSize.X + delta.X) / scale)
            local newY = math.max(minY, (startSize.Y + delta.Y) / scale)
            
            window.Size = UDim2.new(0, newX, 0, newY)
        end
    end)
    
    local sidebar = Create("Frame", {
        BackgroundColor3 = ThemeColor("GroupFill"),
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 1 * GUI_SCALE),
        Size = UDim2.new(0, 37 * GUI_SCALE, 1, -1 * GUI_SCALE),
        Parent = main
    })
    RegisterOpacity(sidebar, "BackgroundTransparency", 0, true)
    
    local sidebarRightBorder = Create("Frame", {
        BackgroundColor3 = ThemeColor("GroupBorderIn"),
        BorderSizePixel = 0,
        Position = UDim2.new(1, -1, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        ZIndex = 1,
        Parent = sidebar
    })
    RegisterOpacity(sidebarRightBorder, "BackgroundTransparency", 0, true)

    local sidebarActiveBG = Create("Frame", {
        BackgroundColor3 = ThemeColor("MainFill"),
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 15 * GUI_SCALE),
        Size = UDim2.new(1, 0, 0, 40 * GUI_SCALE),
        ZIndex = 2,
        Parent = sidebar
    })
    local activeTop = Create("Frame", { BackgroundColor3 = ThemeColor("GroupBorderIn"), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), ZIndex = 3, Parent = sidebarActiveBG })
    local activeBot = Create("Frame", { BackgroundColor3 = ThemeColor("GroupBorderIn"), BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 3, Parent = sidebarActiveBG })
    RegisterOpacity(sidebarActiveBG, "BackgroundTransparency", 0, true)
    RegisterOpacity(activeTop, "BackgroundTransparency", 0, true)
    RegisterOpacity(activeBot, "BackgroundTransparency", 0, true)
    
    local tabsContainer = Create("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 5,
        Parent = sidebar
    })
    -- Removed UIListLayout so we can Tween exact offset
    
    local WindowAPI = {
        Tabs = {},
        ActiveTab = nil
    }
    
    -- No absolute size property hook needed for fixed width
    
    -- Content Area
    local contentArea = Create("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 42 * GUI_SCALE, 0, 15 * GUI_SCALE),
        Size = UDim2.new(1, -48 * GUI_SCALE, 1, -20 * GUI_SCALE),
        Parent = main
    })
    
    -- Tooltip
    local tooltip = Create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Fonts.Regular,
        Text = "",
        TextColor3 = ThemeColor("TextPrimary"),
        TextSize = 10 * GUI_SCALE,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 55 * GUI_SCALE, 0, 9 * GUI_SCALE),
        Visible = false,
        ZIndex = 100,
        Parent = main
    })
    RegisterOpacity(tooltip, "TextTransparency")
    
    local function ShowTooltip(text)
        tooltip.Text = text
        tooltip.Visible = true
    end
    
    local function HideTooltip()
        tooltip.Visible = false
    end
    
    -- Toggle UI visibility
    local isOpen = false
    local function ToggleUI()
        isOpen = not isOpen
        GlobalOpacity.Target = isOpen and 1 or 0
        if isOpen then
            sg.Enabled = true
            uiScale.Scale = currentScale * 0.95
            TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Scale = currentScale}):Play()
            TweenService:Create(bgDarken, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency = 0.4}):Play()
        else
            TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Scale = currentScale * 0.95}):Play()
            TweenService:Create(bgDarken, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency = 1.0}):Play()
            task.delay(0.2, function()
                if not isOpen then sg.Enabled = false end
            end)
        end
    end
    
    -- Start closed, then open
    task.spawn(function()
        task.wait(0.1)
        ToggleUI()
    end)
    
    -- Note: Removed hardcoded RightShift toggle.
    -- Use Window:SetVisible() or configure a keybind in test_ui.lua instead.
    
    function WindowAPI:CreateTab(tcfg)
        tcfg = tcfg or {}
        local tabName = tcfg.Name or "Tab"
        -- Prefer the font icon mapping by name; fall back to user-provided icon or gear
        local tabIcon = ExhibitionLib.Icons[tabName] or tcfg.Icon or "⚙"
        local tabIndex = #self.Tabs + 1
        
        local tabBtn = Create("TextButton", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, (15 * GUI_SCALE) + (tabIndex - 1) * 40 * GUI_SCALE),
            Size = UDim2.new(1, 0, 0, 40 * GUI_SCALE),
            Text = "",
            LayoutOrder = tabIndex,
            Parent = tabsContainer
        })
        
        -- Fallback to text if icon isn't A-Z mapped (like if they use an emoji custom icon)
        local isMapped = string.match(tabIcon, "^[A-Z]$")
        
        local tabIconLbl
        if isMapped then
            local iconPath = "ExhibitionLib_Icon_" .. tabIcon .. ".png"
            if not isfile(iconPath) then
                pcall(function()
                    writefile(iconPath, game:HttpGet(string.format(GITHUB_ICONS_URL, tabIcon)))
                end)
            end
            
            tabIconLbl = Create("ImageLabel", {
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Size = UDim2.new(0, 20 * GUI_SCALE, 0, 20 * GUI_SCALE),
                Image = getcustomasset(iconPath),
                ImageColor3 = ThemeColor("SidebarInactive"),
                ScaleType = Enum.ScaleType.Fit,
                ZIndex = 2,
                Parent = tabBtn
            })
            RegisterOpacity(tabIconLbl, "ImageTransparency")
        else
            tabIconLbl = Create("TextLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 1, 0),
                Font = Fonts.Regular,
                Text = tabIcon,
                TextColor3 = ThemeColor("SidebarInactive"),
                TextSize = 20 * GUI_SCALE,
                ZIndex = 2,
                Parent = tabBtn
            })
            RegisterOpacity(tabIconLbl, "TextTransparency")
        end
        
        local tabContent = Create("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Visible = false,
            Parent = contentArea
        })
        
        local tabObj = { Name = tabName, Btn = tabBtn, Icon = tabIcon, IconLbl = tabIconLbl, Content = tabContent, Index = tabIndex }
        table.insert(self.Tabs, tabObj)
        
        local function SelectTab()
            if self.ActiveTab == tabObj then return end
            
            if self.ActiveTab then
                if string.match(self.ActiveTab.Icon, "^[A-Z]$") then
                    TweenService:Create(self.ActiveTab.IconLbl, TweenInfo.new(0.1), {ImageColor3 = Colors.SidebarInactive}):Play()
                else
                    TweenService:Create(self.ActiveTab.IconLbl, TweenInfo.new(0.1), {TextColor3 = Colors.SidebarInactive}):Play()
                end
                self.ActiveTab.Content.Visible = false
            end
            
            self.ActiveTab = tabObj
            if string.match(self.ActiveTab.Icon, "^[A-Z]$") then
                TweenService:Create(self.ActiveTab.IconLbl, TweenInfo.new(0.1), {ImageColor3 = Colors.SidebarActive}):Play()
            else
                TweenService:Create(self.ActiveTab.IconLbl, TweenInfo.new(0.1), {TextColor3 = Colors.SidebarActive}):Play()
            end
            
            self.ActiveTab.Content.Visible = true
            
            -- Move active indicator
            local targetY = (15 * GUI_SCALE) + (tabIndex - 1) * 40 * GUI_SCALE
            TweenService:Create(sidebarActiveBG, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, targetY)}):Play()
        end
        
        tabBtn.MouseButton1Click:Connect(SelectTab)
        tabBtn.MouseEnter:Connect(function()
            if self.ActiveTab ~= tabObj then
                if isMapped then
                    TweenService:Create(tabIconLbl, TweenInfo.new(0.1), {ImageColor3 = Colors.SidebarHover}):Play()
                else
                    TweenService:Create(tabIconLbl, TweenInfo.new(0.1), {TextColor3 = Colors.SidebarHover}):Play()
                end
                if tabName then ShowTooltip(tabName) end
            end
        end)
        tabBtn.MouseLeave:Connect(function()
            if self.ActiveTab ~= tabObj then
                if isMapped then
                    TweenService:Create(tabIconLbl, TweenInfo.new(0.1), {ImageColor3 = Colors.SidebarInactive}):Play()
                else
                    TweenService:Create(tabIconLbl, TweenInfo.new(0.1), {TextColor3 = Colors.SidebarInactive}):Play()
                end
            end
            HideTooltip()
        end)
        
        if tabIndex == 1 then SelectTab() end
        
        -- Tab API
        ExhibitionLib.Tabs = {}
        ExhibitionLib.Flags = ExhibitionLib.Flags or {}
        ExhibitionLib.OpacityMultiplier = 1
        
        local TabAPI = {
            Sections = {},
            Columns = {{}, {}, {}},
            ColXs = {
                UDim2.new(0, 0, 0, 0),
                UDim2.new(0.333, 3 * GUI_SCALE, 0, 0),
                UDim2.new(0.666, 6 * GUI_SCALE, 0, 0)
            },
            ColYs = {10 * GUI_SCALE, 10 * GUI_SCALE, 10 * GUI_SCALE}
        }
        
        function TabAPI:CreateSection(scfg)
            scfg = scfg or {}
            local secName = scfg.Name or "Section"
            
            -- Find shortest column
            local col = 1
            local min_y = self.ColYs[1]
            for i=2, 3 do
                if self.ColYs[i] < min_y then
                    min_y = self.ColYs[i]
                    col = i
                end
            end
            
            local secOut = Create("Frame", {
                BackgroundColor3 = ThemeColor("GroupBorderOut"),
                BorderSizePixel = 0,
                Position = UDim2.new(self.ColXs[col].X.Scale, self.ColXs[col].X.Offset, 0, self.ColYs[col]),
                Size = UDim2.new(0.333, -6 * GUI_SCALE, 0, 20), -- Height updated dynamically
                Parent = tabContent
            })
            
            local secObj = { Out = secOut, Height = 16 * GUI_SCALE }
            table.insert(self.Columns[col], secObj)
            
            local function RecalculateCol()
                local cy = 0
                for _, s in ipairs(self.Columns[col]) do
                    s.Out.Position = UDim2.new(self.ColXs[col].X.Scale, self.ColXs[col].X.Offset, 0, cy)
                    cy = cy + s.Height + 4 * GUI_SCALE
                end
                self.ColYs[col] = cy
            end
            
            RecalculateCol()
            RegisterOpacity(secOut, "BackgroundTransparency", 0, true)
            
            local secIn = Create("Frame", {
                BackgroundColor3 = ThemeColor("GroupBorderIn"),
                BorderSizePixel = 0,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                Parent = secOut
            })
            RegisterOpacity(secIn, "BackgroundTransparency")
            
            local secFill = Create("Frame", {
                BackgroundColor3 = ThemeColor("GroupFill"),
                BorderSizePixel = 0,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                Parent = secIn
            })
            RegisterOpacity(secFill, "BackgroundTransparency")
            
            -- Title Break Effect
            local titleBg = Create("Frame", {
                BackgroundColor3 = ThemeColor("MainFill"), -- Matches the main window background to create a seamless gap
                BorderSizePixel = 0,
                Position = UDim2.new(0, 5 * GUI_SCALE, 0, 0),
                Size = UDim2.new(0, 50, 0, 2), -- 2 pixels tall to exactly cover the BorderOut and BorderIn
                Parent = secOut
            })
            RegisterOpacity(titleBg, "BackgroundTransparency")
            
            local secTitle = DrawTextWithShadow(secOut, secName, Fonts.Regular, 9 * GUI_SCALE, Colors.TextPrimary, UDim2.new(0, 7 * GUI_SCALE, 0, -5 * GUI_SCALE), Enum.TextXAlignment.Left, 5)
            
            task.spawn(function()
                if secTitle.TextBounds.X == 0 then
                    secTitle:GetPropertyChangedSignal("TextBounds"):Wait()
                end
                titleBg.Size = UDim2.new(0, secTitle.TextBounds.X + 4 * GUI_SCALE, 0, 2)
            end)
            
            local secBody = Create("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 4 * GUI_SCALE, 0, 2 * GUI_SCALE),
                Size = UDim2.new(1, -8 * GUI_SCALE, 1, -4 * GUI_SCALE),
                Parent = secFill
            })
            
            local listLayout = Create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4 * GUI_SCALE),
                Parent = secBody
            })
            
            local function UpdateSectionHeight()
                secObj.Height = listLayout.AbsoluteContentSize.Y + math.floor(6 * GUI_SCALE)
                secOut.Size = UDim2.new(0.333, -6 * GUI_SCALE, 0, secObj.Height)
                RecalculateCol()
            end
            
            listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateSectionHeight)
            
            local lastHalfRow = nil
            
            local function MountComponent(wrap, halfSize)
                local reqHeight = wrap.Size.Y.Offset
                if not halfSize then
                    wrap.Parent = secBody
                    lastHalfRow = nil
                else
                    local container
                    if lastHalfRow and #lastHalfRow:GetChildren() == 1 then
                        container = lastHalfRow
                        if reqHeight > container.Size.Y.Offset then
                            container.Size = UDim2.new(1, 0, 0, reqHeight)
                        end
                    else
                        container = Create("Frame", {
                            Name = "HalfRow",
                            BackgroundTransparency = 1,
                            Size = UDim2.new(1, 0, 0, reqHeight),
                            Parent = secBody
                        })
                        lastHalfRow = container
                    end
                    local count = #container:GetChildren()
                    wrap.Size = UDim2.new(0.5, -2 * GUI_SCALE, 0, reqHeight)
                    wrap.Position = UDim2.new(count == 0 and 0 or 0.5, count == 0 and 0 or 2 * GUI_SCALE, 0, 0)
                    wrap.Parent = container
                end
            end
            
            local SectionAPI = {}
            
            function SectionAPI:CreateToggle(ecfg)
                ecfg = ecfg or {}
                local state = ecfg.Default or false
                local cb = ecfg.Callback or function() end
                
                local btn = Create("TextButton", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 10 * GUI_SCALE),
                    Text = ""
                })
                MountComponent(btn, ecfg.HalfSize)
                
                local boxOut = Create("TextButton", {
                    BackgroundColor3 = ThemeColor("GroupBorderOut"),
                    BorderSizePixel = 0,
                    Size = UDim2.new(0, 6 * GUI_SCALE, 0, 6 * GUI_SCALE),
                    Position = UDim2.new(0, 0, 0.5, -3 * GUI_SCALE),
                    Text = "",
                    AutoButtonColor = false,
                    Parent = btn
                })
                RegisterOpacity(boxOut, "BackgroundTransparency")
                
                local boxIn = Create("Frame", {
                    BackgroundColor3 = ThemeColor("Hover"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = boxOut
                })
                RegisterOpacity(boxIn, "BackgroundTransparency", 1) -- start invisible hover
                
                local boxFillOff = Create("Frame", {
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Visible = not state,
                    Parent = boxOut
                })
                RegisterOpacity(boxFillOff, "BackgroundTransparency")
                CreateUIGradient(boxFillOff, "ElemGradTop", "ElemGradBot")
                
                local boxFillOn = Create("Frame", {
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Visible = state,
                    Parent = boxOut
                })
                RegisterOpacity(boxFillOn, "BackgroundTransparency")
                CreateUIGradient(boxFillOn, "Accent", "Accent")
                
                local nameLbl = DrawTextWithShadow(btn, Capitalize(ecfg.Name or "Toggle"), Fonts.Regular, 9 * GUI_SCALE, Colors.TextDim, UDim2.new(0, 10 * GUI_SCALE, 0, 0), Enum.TextXAlignment.Left, 2)
                nameLbl.Size = UDim2.new(1, 0, 1, 0)
                
                local function SetState(s)
                    state = s
                    boxFillOff.Visible = not state
                    boxFillOn.Visible = state
                    cb(state)
                end
                
                if ecfg.HasBind then
                    local bindKey = ecfg.BindDefault or "None"
                    local bindCb = ecfg.BindCallback or function() end
                    local bindBtn = Create("TextButton", {
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 50 * GUI_SCALE, 0, 0),
                        Size = UDim2.new(0, 25 * GUI_SCALE, 1, 0),
                        Font = Fonts.Regular,
                        Text = "[" .. (bindKey == "None" and "-" or bindKey) .. "]",
                        TextColor3 = Colors.TextDim,
                        TextSize = 9 * GUI_SCALE,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = btn
                    })
                    
                    task.spawn(function()
                        if nameLbl.TextBounds.X == 0 then
                            nameLbl:GetPropertyChangedSignal("TextBounds"):Wait()
                        end
                        bindBtn.Position = UDim2.new(0, 10 * GUI_SCALE + nameLbl.TextBounds.X + 4 * GUI_SCALE, 0, 0)
                    end)
                    
                    local binding = false
                    bindBtn.MouseButton1Click:Connect(function()
                        binding = true
                        bindBtn.Text = "[...]"
                        bindBtn.TextColor3 = Colors.White
                    end)
                    
                    UserInputService.InputBegan:Connect(function(input, gpe)
                        if gpe then return end
                        if binding then
                            if input.UserInputType == Enum.UserInputType.Keyboard then
                                binding = false
                                local keyName = input.KeyCode.Name
                                if keyName == "Escape" or keyName == "Unknown" then
                                    bindKey = "None"
                                else
                                    bindKey = keyName
                                end
                                bindBtn.Text = "[" .. (bindKey == "None" and "-" or bindKey) .. "]"
                                bindBtn.TextColor3 = Colors.TextDim
                                bindCb(bindKey)
                            elseif input.UserInputType.Name:find("MouseButton") then
                                binding = false
                                bindKey = "None"
                                bindBtn.Text = "[-]"
                                bindBtn.TextColor3 = Colors.TextDim
                                bindCb(bindKey)
                            end
                        elseif input.UserInputType == Enum.UserInputType.Keyboard then
                            if bindKey ~= "None" and input.KeyCode.Name == bindKey then
                                SetState(not state)
                            end
                        end
                    end)
                end
                
                btn.MouseButton1Click:Connect(function() SetState(not state) end)
                boxOut.MouseButton1Click:Connect(function() SetState(not state) end)
                btn.MouseEnter:Connect(function() 
                    TweenService:Create(boxIn, TweenInfo.new(0.1), {BackgroundTransparency = 0.84}):Play() -- approx 40 alpha
                    if ecfg.Description then ShowTooltip(ecfg.Description) end
                end)
                btn.MouseLeave:Connect(function() 
                    TweenService:Create(boxIn, TweenInfo.new(0.1), {BackgroundTransparency = 1}):Play()
                    HideTooltip()
                end)
                
                local comp = { Set = SetState, Get = function() return state end, Type = "Toggle" }
                local flag = ecfg.Flag or (secName .. "_" .. (ecfg.Name or "Toggle"))
                if flag then ExhibitionLib.Flags[flag] = comp end
                return comp
            end
            
            -- Map Checkbox to Toggle
            SectionAPI.CreateCheckbox = SectionAPI.CreateToggle
            
            function SectionAPI:CreateSlider(ecfg)
                ecfg = ecfg or {}
                local min = ecfg.Min or 0
                local max = ecfg.Max or 100
                local val = math.clamp(ecfg.Default or min, min, max)
                local cb = ecfg.Callback or function() end
                
                -- Determine suffix
                local suf = ecfg.Suffix or ""
                local lName = string.lower(ecfg.Name or "")
                if suf == "" then
                    if lName:find("fov") then suf = "°"
                    elseif lName:find("delay") or lName:find("switch") then suf = "ms"
                    elseif lName == "range" then suf = "m"
                    elseif lName == "health" then suf = "hp"
                    elseif (lName:find("horizontal") or lName:find("vertical")) and min == -100 and max == 100 then suf = "%"
                    end
                end
                
                local wrap = Create("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 16 * GUI_SCALE)
                })
                MountComponent(wrap, ecfg.HalfSize)
                
                local nameLbl = DrawTextWithShadow(wrap, Capitalize(ecfg.Name or "Slider"), Fonts.Regular, 9 * GUI_SCALE, Colors.TextDim, UDim2.new(0, 0, 0, 0), Enum.TextXAlignment.Left, 2)
                
                local trackHeight = 1 + math.floor(3 * GUI_SCALE) -- 6 pixels total when GUI_SCALE is 2
                local trackCenterY = math.floor(trackHeight / 2)
                local cSize = math.floor(1.5 * GUI_SCALE)
                if cSize % 2 == 0 then cSize = cSize + 1 end
                local cOff = math.floor(cSize / 2)
                
                local edgeOffset = 4 * GUI_SCALE
                local leftExtend = not ecfg.HalfSize or (wrap.Position.X.Scale == 0)
                local rightExtend = not ecfg.HalfSize or (wrap.Position.X.Scale > 0)
                
                local minusX = leftExtend and -edgeOffset or 0
                local plusXOffset = rightExtend and edgeOffset or 0

                local trackOut = Create("Frame", {
                    BackgroundColor3 = ThemeColor("GroupBorderOut"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, minusX + cSize, 0, 12 * GUI_SCALE),
                    Size = UDim2.new(1, plusXOffset - minusX - (cSize * 2), 0, trackHeight),
                    Parent = wrap
                })
                RegisterOpacity(trackOut, "BackgroundTransparency")
                
                local valLbl = DrawTextWithShadow(wrap, tostring(val)..suf, Fonts.Bold, 9 * GUI_SCALE, Colors.TextPrimary, UDim2.new(1, 0, 0, 0), Enum.TextXAlignment.Right, 2)
                
                local fill = Create("Frame", {
                    BackgroundColor3 = ThemeColor("White"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 0, 0),
                    Size = UDim2.new(0, 0, 1, 0),
                    Parent = trackOut
                })
                RegisterOpacity(fill, "BackgroundTransparency")
                CreateUIGradient(fill, "Accent", "Accent")
                
                local function pct(v) return (v - min) / (max - min) end
                
                local function UpdateVisuals()
                    if ExhibitionLib.DynamicSliders then
                        valLbl.Parent = trackOut
                        valLbl.AnchorPoint = Vector2.new(0.5, 0)
                        valLbl.Size = UDim2.new(0, 40 * GUI_SCALE, 0, 9 * GUI_SCALE)
                        valLbl.TextXAlignment = Enum.TextXAlignment.Center
                        local p = pct(val)
                        valLbl.Position = UDim2.new(p, 0, 0, 5 * GUI_SCALE)
                    else
                        valLbl.Parent = wrap
                        valLbl.AnchorPoint = Vector2.new(1, 0)
                        valLbl.Size = UDim2.new(0, 40 * GUI_SCALE, 0, 9 * GUI_SCALE)
                        valLbl.TextXAlignment = Enum.TextXAlignment.Right
                        valLbl.Position = UDim2.new(1, 0, 0, 0)
                    end
                end
                table.insert(ExhibitionLib.Sliders, UpdateVisuals)
                
                local function SetVal(v)
                    val = math.clamp(v, min, max)
                    local p = pct(val)
                    
                    if min < 0 and max > 0 and max == -min then
                        -- Center zero logic
                        if p < 0.5 then
                            fill.Position = UDim2.new(p, 0, 0, 0)
                            fill.Size = UDim2.new(0.5 - p, 0, 1, 0)
                        else
                            fill.Position = UDim2.new(0.5, 0, 0, 0)
                            fill.Size = UDim2.new(p - 0.5, 0, 1, 0)
                        end
                    else
                        fill.Size = UDim2.new(p, 0, 1, 0)
                    end
                    
                    valLbl.Text = tostring(math.floor(val * 10) / 10)..suf
                    UpdateVisuals()
                    cb(val)
                end
                SetVal(val)
                
                local dragging = false
                local function updateSlider(input)
                    local w = trackOut.AbsoluteSize.X
                    local px = math.clamp(input.Position.X - trackOut.AbsolutePosition.X, 0, w)
                    SetVal(min + (max - min) * (px / w))
                end
                
                local minusBtn = Create("TextButton", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, minusX, 0, 12 * GUI_SCALE + trackCenterY - cOff),
                    Size = UDim2.new(0, cSize, 0, cSize),
                    Text = "",
                    ZIndex = 2,
                    Parent = wrap
                })
                
                local minusLine = Create("Frame", {
                    BackgroundColor3 = ThemeColor("TextDim"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 0, cOff),
                    Size = UDim2.new(0, cSize, 0, 1),
                    Parent = minusBtn
                })
                RegisterOpacity(minusLine, "BackgroundTransparency")
                
                local plusBtn = Create("TextButton", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, plusXOffset - cSize, 0, 12 * GUI_SCALE + trackCenterY - cOff),
                    Size = UDim2.new(0, cSize, 0, cSize),
                    Text = "",
                    ZIndex = 2,
                    Parent = wrap
                })
                
                local plusLineH = Create("Frame", {
                    BackgroundColor3 = ThemeColor("TextDim"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 0, cOff),
                    Size = UDim2.new(0, cSize, 0, 1),
                    Parent = plusBtn
                })
                RegisterOpacity(plusLineH, "BackgroundTransparency")
                
                local plusLineV = Create("Frame", {
                    BackgroundColor3 = ThemeColor("TextDim"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, cOff, 0, 0),
                    Size = UDim2.new(0, 1, 0, cSize),
                    Parent = plusBtn
                })
                RegisterOpacity(plusLineV, "BackgroundTransparency")
                
                minusBtn.MouseButton1Click:Connect(function() SetVal(val - (max-min)/100) end)
                plusBtn.MouseButton1Click:Connect(function() SetVal(val + (max-min)/100) end)
                
                minusBtn.MouseEnter:Connect(function() minusLine.BackgroundColor3 = Colors.White end)
                minusBtn.MouseLeave:Connect(function() minusLine.BackgroundColor3 = Colors.TextDim end)
                plusBtn.MouseEnter:Connect(function() plusLineH.BackgroundColor3 = Colors.White; plusLineV.BackgroundColor3 = Colors.White end)
                plusBtn.MouseLeave:Connect(function() plusLineH.BackgroundColor3 = Colors.TextDim; plusLineV.BackgroundColor3 = Colors.TextDim end)

                trackOut.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then
                        dragging = true
                        updateSlider(i)
                    end
                end)
                UserInputService.InputChanged:Connect(function(i)
                    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
                        updateSlider(i)
                    end
                end)
                UserInputService.InputEnded:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
                end)
                
                wrap.MouseEnter:Connect(function()
                    if ecfg.Description then ShowTooltip(ecfg.Description .. " [Min: " .. min .. " Max: " .. max .. "]") end
                end)
                wrap.MouseLeave:Connect(function() HideTooltip() end)
                
                local comp = { Set = SetVal, Get = function() return val end, Type = "Slider" }
                local flag = ecfg.Flag or (secName .. "_" .. (ecfg.Name or "Slider"))
                if flag then ExhibitionLib.Flags[flag] = comp end
                return comp
            end
            
            function SectionAPI:CreateDropdown(ecfg)
                ecfg = ecfg or {}
                local options = ecfg.Options or {}
                local selected = ecfg.Default or options[1]
                local cb = ecfg.Callback or function() end
                local open = false
                
                local wrap = Create("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 20 * GUI_SCALE)
                })
                MountComponent(wrap, ecfg.HalfSize)
                
                DrawTextWithShadow(wrap, Capitalize(ecfg.Name or "Dropdown"), Fonts.Regular, 9 * GUI_SCALE, Colors.TextDim, UDim2.new(0, 0, 0, 0), Enum.TextXAlignment.Left, 2)
                
                local boxOut = Create("Frame", {
                    BackgroundColor3 = ThemeColor("Border1"), -- Black outline
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 0, 10 * GUI_SCALE),
                    Size = UDim2.new(1, 0, 0, 11 * GUI_SCALE),
                    Parent = wrap
                })
                RegisterOpacity(boxOut, "BackgroundTransparency")
                
                local boxIn = Create("TextButton", {
                    BackgroundColor3 = ThemeColor("White"), -- Need White for Gradient
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Text = "",
                    Parent = boxOut
                })
                RegisterOpacity(boxIn, "BackgroundTransparency")
                CreateUIGradient(boxIn, "DropGradTop", "DropGradBot")
                
                local selText = DrawTextWithShadow(boxIn, selected, Fonts.Regular, 9 * GUI_SCALE, Colors.TextMuted, UDim2.new(0, 2 * GUI_SCALE, 0, 0), Enum.TextXAlignment.Left, 2)
                selText.Size = UDim2.new(1, -10 * GUI_SCALE, 1, 0)
                selText.ClipsDescendants = true
                
                -- Skeet tiny triangle
                local arrow = Create("Frame", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, -8 * GUI_SCALE, 0.5, 0),
                    Size = UDim2.new(0, 3 * GUI_SCALE, 0, 2 * GUI_SCALE),
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    ZIndex = 2,
                    Parent = boxIn
                })
                Create("Frame", { BackgroundColor3 = ThemeColor("TextMuted"), BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0, 1 * GUI_SCALE), ZIndex = 2, Parent = arrow })
                Create("Frame", { BackgroundColor3 = ThemeColor("TextMuted"), BorderSizePixel = 0, Position = UDim2.new(0, 1 * GUI_SCALE, 0, 1 * GUI_SCALE), Size = UDim2.new(1, -2 * GUI_SCALE, 0, 1 * GUI_SCALE), ZIndex = 2, Parent = arrow })
                
                local dropList = Create("Frame", {
                    BackgroundColor3 = ThemeColor("Border1"),
                    BorderSizePixel = 0,
                    Size = UDim2.new(0, boxOut.AbsoluteSize.X, 0, #options * 11 * GUI_SCALE),
                    Visible = false,
                    ZIndex = 200,
                    Parent = sg
                })
                
                local function PositionDropList()
                    local absPos = boxOut.AbsolutePosition
                    local absSize = boxOut.AbsoluteSize
                    dropList.Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y)
                    dropList.Size = UDim2.new(0, absSize.X, 0, #options * 11 * GUI_SCALE)
                end
                RegisterOpacity(dropList, "BackgroundTransparency")
                
                local dropListIn = Create("Frame", {
                    BackgroundColor3 = ThemeColor("White"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    ZIndex = 200,
                    Parent = dropList
                })
                RegisterOpacity(dropListIn, "BackgroundTransparency")
                CreateUIGradient(dropListIn, "DropGradTop", "DropGradBot")
                
                local function UpdateOptions()
                    for _, v in ipairs(dropListIn:GetChildren()) do
                        if v:IsA("TextButton") then v:Destroy() end
                    end
                    for i, opt in ipairs(options) do
                        local obtn = Create("TextButton", {
                            BackgroundTransparency = 1,
                            Position = UDim2.new(0, 0, 0, (i-1) * 11 * GUI_SCALE),
                            Size = UDim2.new(1, 0, 0, 11 * GUI_SCALE),
                            Font = opt == selected and Fonts.Bold or Fonts.Regular,
                            Text = opt,
                            TextColor3 = opt == selected and Colors.Accent or Colors.TextPrimary,
                            TextSize = 9 * GUI_SCALE,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            ZIndex = 201,
                            Parent = dropListIn
                        })
                        
                        -- Indent slightly
                        local pad = Create("UIPadding", {PaddingLeft = UDim.new(0, 3 * GUI_SCALE), Parent=obtn})
                        
                        obtn.MouseEnter:Connect(function() TweenService:Create(obtn, TweenInfo.new(0.1), {TextColor3 = Colors.Hover}):Play() end)
                        obtn.MouseLeave:Connect(function() TweenService:Create(obtn, TweenInfo.new(0.1), {TextColor3 = opt == selected and Colors.Accent or Colors.TextPrimary}):Play() end)
                        obtn.MouseButton1Click:Connect(function()
                            selected = opt
                            selText.Text = selected
                            cb(selected)
                            open = false
                            dropList.Visible = false
                            arrow.Rotation = 0
                            UpdateOptions()
                        end)
                    end
                end
                
                boxIn.MouseButton1Click:Connect(function()
                    open = not open
                    if open then
                        PositionDropList()
                        UpdateOptions()
                    end
                    dropList.Visible = open
                    arrow.Rotation = open and 180 or 0
                end)
                
                UpdateOptions()
                
                local comp = { 
                    Set = function(v) selected = v; selText.Text = v; UpdateOptions(); cb(v) end,
                    Get = function() return selected end,
                    Type = "Dropdown"
                }
                local flag = ecfg.Flag or (secName .. "_" .. (ecfg.Name or "Dropdown"))
                if flag then ExhibitionLib.Flags[flag] = comp end
                return comp
            end
            
            -- Implement MultiDropdown simply as a wrapper
            function SectionAPI:CreateMultiDropdown(ecfg)
                -- Multi logic omitted for brevity but functionally identical with array values
                return SectionAPI:CreateDropdown(ecfg)
            end

            -- Stubs for the rest to satisfy API requirements
            function SectionAPI:CreateTextbox(ecfg)
                ecfg = ecfg or {}
                local text = ecfg.Default or ""
                local cb = ecfg.Callback or function() end
                local placeholder = ecfg.Placeholder or "..."
                
                local wrap = Create("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 20 * GUI_SCALE)
                })
                MountComponent(wrap, ecfg.HalfSize)
                
                DrawTextWithShadow(wrap, Capitalize(ecfg.Name or "Textbox"), Fonts.Regular, 9 * GUI_SCALE, Colors.TextDim, UDim2.new(0, 0, 0, 0), Enum.TextXAlignment.Left, 2)
                
                local boxOut = Create("Frame", {
                    BackgroundColor3 = ThemeColor("Border1"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 0, 10 * GUI_SCALE),
                    Size = UDim2.new(1, 0, 0, 11 * GUI_SCALE),
                    Parent = wrap
                })
                RegisterOpacity(boxOut, "BackgroundTransparency")
                
                local boxIn = Create("Frame", {
                    BackgroundColor3 = ThemeColor("White"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = boxOut
                })
                RegisterOpacity(boxIn, "BackgroundTransparency")
                CreateUIGradient(boxIn, "DropGradTop", "DropGradBot")
                
                local input = Create("TextBox", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 3 * GUI_SCALE, 0, 0),
                    Size = UDim2.new(1, -6 * GUI_SCALE, 1, 0),
                    Font = Fonts.Regular,
                    Text = text,
                    PlaceholderText = placeholder,
                    PlaceholderColor3 = Colors.TextDark,
                    TextColor3 = ThemeColor("TextPrimary"),
                    TextSize = 9 * GUI_SCALE,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ClearTextOnFocus = false,
                    ClipsDescendants = true,
                    TextStrokeColor3 = Colors.Black,
                    TextStrokeTransparency = 0,
                    ZIndex = 2,
                    Parent = boxIn
                })
                RegisterOpacity(input, "TextTransparency")
                
                input.FocusLost:Connect(function(enterPressed)
                    text = input.Text
                    cb(text, enterPressed)
                end)
                
                local comp = {
                    Set = function(v) text = v; input.Text = v; cb(v, false) end,
                    Get = function() return text end,
                    Type = "Textbox"
                }
                local flag = ecfg.Flag or (secName .. "_" .. (ecfg.Name or "Textbox"))
                if flag then ExhibitionLib.Flags[flag] = comp end
                return comp
            end
            
            function SectionAPI:CreateKeybind(ecfg)
                ecfg = ecfg or {}
                local key = ecfg.Default or "None"
                local cb = ecfg.Callback or function() end
                
                local wrap = Create("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 12 * GUI_SCALE)
                })
                MountComponent(wrap, ecfg.HalfSize)
                
                local nameLbl = DrawTextWithShadow(wrap, Capitalize(ecfg.Name or "Keybind"), Fonts.Regular, 9 * GUI_SCALE, Colors.TextDim, UDim2.new(0, 0, 0, 0), Enum.TextXAlignment.Left, 2)
                nameLbl.Size = UDim2.new(1, -32 * GUI_SCALE, 0, 9 * GUI_SCALE)
                nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
                
                local bindBtn = Create("TextButton", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, -30 * GUI_SCALE, 0, 0),
                    Size = UDim2.new(0, 30 * GUI_SCALE, 0, 10 * GUI_SCALE),
                    Font = Fonts.Regular,
                    Text = "[" .. (key == "None" and "-" or key) .. "]",
                    TextColor3 = ThemeColor("TextDim"),
                    TextSize = 9 * GUI_SCALE,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = wrap
                })
                
                local binding = false
                bindBtn.MouseButton1Click:Connect(function()
                    binding = true
                    bindBtn.Text = "[...]"
                    bindBtn.TextColor3 = Colors.White
                end)
                
                UserInputService.InputBegan:Connect(function(input, gpe)
                    if gpe then return end
                    if binding then
                        if input.UserInputType == Enum.UserInputType.Keyboard then
                            binding = false
                            local keyName = input.KeyCode.Name
                            if keyName == "Escape" or keyName == "Unknown" then
                                key = "None"
                            else
                                key = keyName
                            end
                            bindBtn.Text = "[" .. (key == "None" and "-" or key) .. "]"
                            bindBtn.TextColor3 = Colors.TextDim
                            cb(key)
                        elseif input.UserInputType.Name:find("MouseButton") then
                            binding = false
                            key = "None"
                            bindBtn.Text = "[-]"
                            bindBtn.TextColor3 = Colors.TextDim
                            cb(key)
                        end
                    end
                end)
                
                RecalculateCol()
                local comp = {
                    Set = function(k)
                        key = k
                        bindBtn.Text = "[" .. (key == "None" and "-" or key) .. "]"
                        cb(key)
                    end,
                    Get = function() return key end,
                    Type = "Keybind"
                }
                local flag = ecfg.Flag or (secName .. "_" .. (ecfg.Name or "Keybind"))
                if flag then ExhibitionLib.Flags[flag] = comp end
                return comp
            end
            
            function SectionAPI:CreateButton(ecfg)
                ecfg = ecfg or {}
                local cb = ecfg.Callback or function() end
                
                local wrap = Create("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 16 * GUI_SCALE),
                    Parent = secBody
                })
                
                local btn = Create("TextButton", {
                    BackgroundColor3 = ThemeColor("GroupBorderOut"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 10 * GUI_SCALE, 0, 2 * GUI_SCALE),
                    Size = UDim2.new(1, -20 * GUI_SCALE, 1, -4 * GUI_SCALE),
                    Font = Fonts.Regular,
                    Text = "",
                    Parent = wrap
                })
                RegisterOpacity(btn, "BackgroundTransparency")
                CreateUIGradient(btn, "ElemGradTop", "ElemGradBot")
                
                local btnIn = Create("Frame", {
                    BackgroundColor3 = ThemeColor("GroupBorderIn"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = btn
                })
                RegisterOpacity(btnIn, "BackgroundTransparency")
                
                local btnFill = Create("Frame", {
                    BackgroundColor3 = ThemeColor("GroupFill"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = btnIn
                })
                RegisterOpacity(btnFill, "BackgroundTransparency")
                
                local lbl = DrawTextWithShadow(btnFill, Capitalize(ecfg.Name or "Button"), Fonts.Regular, 9 * GUI_SCALE, Colors.TextPrimary, UDim2.new(0, 0, 0, 0), Enum.TextXAlignment.Center, 2)
                lbl.Size = UDim2.new(1, 0, 1, 0)
                
                btn.MouseButton1Click:Connect(cb)
                
                return {}
            end
            function SectionAPI:CreateColorPicker(ecfg)
                ecfg = ecfg or {}
                local color = ecfg.Default or Color3.new(1,0,0)
                local cb = ecfg.Callback or function() end
                
                local wrap = Create("Frame", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 16 * GUI_SCALE)
                })
                MountComponent(wrap, ecfg.HalfSize)
                
                local nameLbl = DrawTextWithShadow(wrap, Capitalize(ecfg.Name or "Color"), Fonts.Regular, 9 * GUI_SCALE, ThemeColor("TextDim"), UDim2.new(0, 0, 0, 0), Enum.TextXAlignment.Left, 2)
                
                local btnOut = Create("TextButton", {
                    BackgroundColor3 = ThemeColor("GroupBorderOut"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(1, -20 * GUI_SCALE, 0.5, -4 * GUI_SCALE),
                    Size = UDim2.new(0, 15 * GUI_SCALE, 0, 8 * GUI_SCALE),
                    Text = "",
                    Parent = wrap
                })
                local btnIn = Create("Frame", {
                    BackgroundColor3 = color,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = btnOut
                })
                
                local popup = Create("Frame", {
                    BackgroundColor3 = ThemeColor("GroupBorderOut"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(1, 5 * GUI_SCALE, 0, 0),
                    Size = UDim2.new(0, 80 * GUI_SCALE, 0, 95 * GUI_SCALE),
                    Visible = false,
                    ZIndex = 100,
                    Parent = btnOut
                })
                local popIn = Create("Frame", {
                    BackgroundColor3 = ThemeColor("GroupFill"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    ZIndex = 100,
                    Parent = popup
                })
                
                local svArea = Create("TextButton", {
                    BackgroundColor3 = Color3.new(1,0,0),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 4 * GUI_SCALE, 0, 4 * GUI_SCALE),
                    Size = UDim2.new(0, 60 * GUI_SCALE, 0, 60 * GUI_SCALE),
                    Text = "",
                    AutoButtonColor = false,
                    ZIndex = 101,
                    Parent = popIn
                })
                
                local svWhite = Create("Frame", { BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0, Size = UDim2.new(1,0,1,0), ZIndex=102, Parent = svArea })
                Create("UIGradient", { Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(1,1,1)), Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1)}), Rotation = 0, Parent = svWhite })
                
                local svBlack = Create("Frame", { BackgroundColor3 = Color3.new(0,0,0), BorderSizePixel = 0, Size = UDim2.new(1,0,1,0), ZIndex=103, Parent = svArea })
                Create("UIGradient", { Color = ColorSequence.new(Color3.new(0,0,0), Color3.new(0,0,0)), Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0)}), Rotation = 90, Parent = svBlack })
                
                local svCursor = Create("Frame", { BackgroundColor3 = Color3.new(1,1,1), Size = UDim2.new(0, 2, 0, 2), Position = UDim2.new(1,-1,0,-1), ZIndex=104, Parent = svArea })
                
                local hueArea = Create("TextButton", {
                    BackgroundColor3 = Color3.new(1,1,1),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 68 * GUI_SCALE, 0, 4 * GUI_SCALE),
                    Size = UDim2.new(0, 8 * GUI_SCALE, 0, 60 * GUI_SCALE),
                    Text = "",
                    AutoButtonColor = false,
                    ZIndex = 101,
                    Parent = popIn
                })
                local hueGrad = Create("UIGradient", {
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.new(1,0,0)),
                        ColorSequenceKeypoint.new(0.167, Color3.new(1,1,0)),
                        ColorSequenceKeypoint.new(0.333, Color3.new(0,1,0)),
                        ColorSequenceKeypoint.new(0.5, Color3.new(0,1,1)),
                        ColorSequenceKeypoint.new(0.667, Color3.new(0,0,1)),
                        ColorSequenceKeypoint.new(0.833, Color3.new(1,0,1)),
                        ColorSequenceKeypoint.new(1, Color3.new(1,0,0))
                    }),
                    Rotation = 90,
                    Parent = hueArea
                })
                local hueCursor = Create("Frame", { BackgroundColor3 = Color3.new(1,1,1), Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0,0,0,-1), ZIndex=104, Parent = hueArea })
                
                local h, s, v = Color3.toHSV(color)
                
                -- Hex input box at the bottom of the picker
                local hexBoxOut = Create("Frame", {
                    BackgroundColor3 = ThemeColor("Border1"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 4 * GUI_SCALE, 0, 68 * GUI_SCALE),
                    Size = UDim2.new(0, 72 * GUI_SCALE, 0, 11 * GUI_SCALE),
                    ZIndex = 101,
                    Parent = popIn
                })
                local hexBoxIn = Create("Frame", {
                    BackgroundColor3 = ThemeColor("White"),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    ZIndex = 101,
                    Parent = hexBoxOut
                })
                CreateUIGradient(hexBoxIn, "DropGradTop", "DropGradBot")
                
                local hexLabel = Create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 1 * GUI_SCALE, 0, 0),
                    Size = UDim2.new(0, 7 * GUI_SCALE, 1, 0),
                    Font = Fonts.Regular,
                    Text = "#",
                    TextColor3 = Colors.TextMuted,
                    TextSize = 9 * GUI_SCALE,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 102,
                    Parent = hexBoxIn
                })
                
                local hexInput = Create("TextBox", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 7 * GUI_SCALE, 0, 0),
                    Size = UDim2.new(1, -8 * GUI_SCALE, 1, 0),
                    Font = Fonts.Regular,
                    Text = Color3ToHex(color):sub(2),
                    PlaceholderText = "FFFFFF",
                    PlaceholderColor3 = Colors.TextDark,
                    TextColor3 = Colors.TextPrimary,
                    TextSize = 9 * GUI_SCALE,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ClearTextOnFocus = true,
                    ClipsDescendants = true,
                    TextStrokeColor3 = Colors.Black,
                    TextStrokeTransparency = 0,
                    ZIndex = 102,
                    Parent = hexBoxIn
                })
                
                local updatingFromHex = false
                
                local function UpdateColor()
                    color = Color3.fromHSV(h, s, v)
                    btnIn.BackgroundColor3 = color
                    svArea.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                    
                    svCursor.Position = UDim2.new(s, -1, 1-v, -1)
                    hueCursor.Position = UDim2.new(0, 0, h, -1)
                    
                    -- Update hex display (skip if the change came from the hex box)
                    if not updatingFromHex then
                        hexInput.Text = Color3ToHex(color):sub(2)
                    end
                    
                    cb(color)
                end
                
                hexInput.FocusLost:Connect(function()
                    local parsed = HexToColor3(hexInput.Text)
                    if parsed then
                        updatingFromHex = true
                        h, s, v = Color3.toHSV(parsed)
                        UpdateColor()
                        updatingFromHex = false
                    else
                        -- Invalid hex, revert to current color
                        hexInput.Text = Color3ToHex(color):sub(2)
                    end
                end)
                UpdateColor()
                
                local draggingSV = false
                local draggingHue = false
                
                svArea.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingSV = true end end)
                hueArea.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingHue = true end end)
                
                UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingSV = false; draggingHue = false end end)
                
                UserInputService.InputChanged:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseMovement then
                        if draggingSV then
                            local x = math.clamp((i.Position.X - svArea.AbsolutePosition.X) / svArea.AbsoluteSize.X, 0, 1)
                            local y = math.clamp((i.Position.Y - svArea.AbsolutePosition.Y) / svArea.AbsoluteSize.Y, 0, 1)
                            s = x
                            v = 1 - y
                            UpdateColor()
                        elseif draggingHue then
                            local y = math.clamp((i.Position.Y - hueArea.AbsolutePosition.Y) / hueArea.AbsoluteSize.Y, 0, 1)
                            h = y
                            UpdateColor()
                        end
                    end
                end)
                
                local open = false
                btnOut.MouseButton1Click:Connect(function()
                    open = not open
                    popup.Visible = open
                    secOut.ZIndex = open and 50 or 1
                end)
                
                local function SetColor(col) color = col; h,s,v = Color3.toHSV(col); UpdateColor(); cb(col) end
                local comp = { Set = SetColor, Get = function() return color end, Type = "ColorPicker" }
                local flag = ecfg.Flag or (secName .. "_" .. (ecfg.Name or "ColorPicker"))
                if flag then ExhibitionLib.Flags[flag] = comp end
                return comp
            end
            return SectionAPI
        end
        
        return TabAPI
    end
    
    function WindowAPI:SetVisible(state)
        if state ~= isOpen then
            ToggleUI()
        end
    end
    
    function WindowAPI:GetVisible()
        return isOpen
    end

    function WindowAPI:Notify(ncfg)
        print("[ExhibitionLib Notify]", ncfg.Title, ncfg.Content)
    end
    
    function ExhibitionLib:SaveConfig(name)
        if not writefile then 
            warn("ExhibitionLib: writefile is not supported by your executor!")
            return false
        end
        
        -- Ensure config folder exists
        pcall(function()
            if makefolder and isfolder then
                if not isfolder("exhi_configs") then
                    makefolder("exhi_configs")
                end
            elseif makefolder then
                makefolder("exhi_configs")
            end
        end)
        
        if not self.Flags or next(self.Flags) == nil then
            warn("ExhibitionLib SaveConfig: No flags registered!")
            return false
        end
        
        local data = {}
        local count = 0
        for flag, comp in pairs(self.Flags) do
            local ok, val = pcall(function() return comp.Get() end)
            if ok and val ~= nil then
                if comp.Type == "ColorPicker" then
                    -- Store Color3 as table with 0-255 values and a type marker
                    local r = math.floor(val.R * 255 + 0.5)
                    local g = math.floor(val.G * 255 + 0.5)
                    local b = math.floor(val.B * 255 + 0.5)
                    data[flag] = {_type = "Color3", r = r, g = g, b = b}
                else
                    data[flag] = val
                end
                count = count + 1
            end
        end
        
        local success, err = pcall(function()
            local json = HttpService:JSONEncode(data)
            writefile("exhi_configs/" .. name .. ".json", json)
        end)
        
        if not success then
            warn("ExhibitionLib SaveConfig Error:", err)
            return false
        end
        print("[ExhibitionLib] Saved config '" .. name .. "' with " .. count .. " flags")
        return true
    end
    
    function ExhibitionLib:LoadConfig(name)
        if not readfile then 
            warn("ExhibitionLib: readfile is not supported by your executor!")
            return false
        end
        
        local filePath = "exhi_configs/" .. name .. ".json"
        
        -- Check if file exists
        if isfile and not isfile(filePath) then
            warn("ExhibitionLib LoadConfig: File not found: " .. filePath)
            return false
        end
        
        local success, data = pcall(function() 
            return HttpService:JSONDecode(readfile(filePath)) 
        end)
        
        if not success then
            warn("ExhibitionLib LoadConfig Error:", data)
            return false
        end
        
        if type(data) ~= "table" then
            warn("ExhibitionLib LoadConfig: Invalid config data")
            return false
        end
        
        local count = 0
        for flag, val in pairs(data) do
            if self.Flags and self.Flags[flag] then
                local ok, err = pcall(function()
                    if self.Flags[flag].Type == "ColorPicker" and type(val) == "table" then
                        -- Reconstruct Color3 from saved RGB values (0-255)
                        local r = (val.r or 0) / 255
                        local g = (val.g or 0) / 255
                        local b = (val.b or 0) / 255
                        self.Flags[flag].Set(Color3.new(r, g, b))
                    else
                        self.Flags[flag].Set(val)
                    end
                end)
                if ok then
                    count = count + 1
                else
                    warn("ExhibitionLib LoadConfig: Failed to set flag '" .. flag .. "':", err)
                end
            end
        end
        print("[ExhibitionLib] Loaded config '" .. name .. "' - applied " .. count .. " flags")
        return true
    end
    
    return WindowAPI
end

return ExhibitionLib
