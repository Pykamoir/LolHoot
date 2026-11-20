-- Player reputation viewer. Read-only, client-side.
-- Data: Players.<name>.CharacterInfo.InterestGroups.<Group>.Value  (range 0..101)
-- Teardown: getgenv().killRepViewer()

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local LocalPlayer  = Players.LocalPlayer

local MAX = 101

local GROUPS = {
    "Defense Industry", "Environmentalists", "Financial Industry", "Immigrants",
    "Middle Class", "Nationalists", "Native Americans", "Parents", "Poor",
    "Resources Industry", "Rich", "Technology Industry", "Youth",
}

-- Lower-inclusive, upper-exclusive. Higher entries win.
local BANDS = {
    { min = 101, colour = Color3.fromRGB(255, 200, 60) },  -- gold, exact cap
    { min = 80,  colour = Color3.fromRGB(90, 255, 90) },   -- bright green
    { min = 70,  colour = Color3.fromRGB(60, 205, 70) },   -- slightly darker green
    { min = 60,  colour = Color3.fromRGB(70, 165, 60) },   -- darker green
    { min = 50,  colour = Color3.fromRGB(175, 200, 55) },  -- yellowish green
    { min = 40,  colour = Color3.fromRGB(240, 150, 40) },  -- orange
    { min = 30,  colour = Color3.fromRGB(235, 95, 45) },   -- reddish orange
    { min = 20,  colour = Color3.fromRGB(215, 60, 50) },   -- more reddish orange
    { min = 10,  colour = Color3.fromRGB(200, 40, 45) },   -- red
    { min = 0,   colour = Color3.fromRGB(140, 15, 20) },   -- deep red
}

local CONFIG = {
    refresh   = 0.5,
    tweenTime = 0.5,
    maxUsers  = 60,
    trackW    = 190,
    trackH    = 9,
}

-- ── teardown, hoisted so it exists before anything can throw ──────────────
getgenv().killRepViewer = function()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local existing = pg and pg:FindFirstChild("RepViewer")
    if existing then existing:Destroy() end
end

-- ── builders ──────────────────────────────────────────────────────────────
local function mk(inst, props, children)
    for k, v in pairs(props or {}) do inst[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    return inst
end

local function corner(inst, r)
    mk(Instance.new("UICorner"), { CornerRadius = UDim.new(r or 0, 0), Parent = inst })
    return inst
end

local function chrome(frame, radius)
    corner(frame, radius)
    mk(Instance.new("UIStroke"), {
        Color = Color3.fromRGB(60, 64, 76), Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame,
    })
    return frame
end

local function colourFor(raw)
    for _, band in ipairs(BANDS) do
        if raw >= band.min then return band.colour end
    end
    return BANDS[#BANDS].colour
end

local function getGroups(player)
    local ci = player:FindFirstChild("CharacterInfo")
    return ci and ci:FindFirstChild("InterestGroups") or nil
end

-- ── shell ─────────────────────────────────────────────────────────────────
local gui = mk(Instance.new("ScreenGui"), {
    Name = "RepViewer", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

-- full teardown now that the live objects are in scope
getgenv().killRepViewer = function()
    if viewerThread then task.cancel(viewerThread); viewerThread = nil end
    for _, r in pairs(viewerRows or {}) do
        if r.tween then r.tween:Cancel() end
    end
    viewerRows = {}
    if viewer then viewer:Destroy(); viewer = nil end
    viewerTarget = nil
    if gui then gui:Destroy() end
end

local root = chrome(mk(Instance.new("Frame"), {
    Name = "Root", Size = UDim2.fromOffset(240, 400), Position = UDim2.new(0, 24, 0, 120),
    BackgroundColor3 = Color3.fromRGB(24, 26, 32), BackgroundTransparency = 0.06,
    BorderSizePixel = 0,
}), 8)

local header = corner(mk(Instance.new("Frame"), {
    Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(32, 35, 42),
    BorderSizePixel = 0,
}), 8)
header.Parent = root

mk(Instance.new("TextLabel"), {
    Parent = header, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -40, 1, 0),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
    Text = "Players", TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Color3.fromRGB(230, 230, 235),
})

local refreshBtn = corner(mk(Instance.new("TextButton"), {
    Size = UDim2.new(1, -14, 0, 22), Position = UDim2.fromOffset(7, 38),
    BackgroundColor3 = Color3.fromRGB(44, 48, 58), Text = "Refresh player list",
    Font = Enum.Font.GothamMedium, TextSize = 11,
    TextColor3 = Color3.fromRGB(220, 222, 230), AutoButtonColor = true,
}), 5)
refreshBtn.Parent = root

local list = mk(Instance.new("ScrollingFrame"), {
    Parent = root, Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 1, -66),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
}, {
    mk(Instance.new("UIPadding"), { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }),
    mk(Instance.new("UIListLayout"), { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local function makeDraggable(frame, handle)
    local dragging, startPos, startOrigin
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startOrigin = true, input.Position, frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        local d = input.Position - startPos
        frame.Position = UDim2.fromOffset(startOrigin.X.Offset + d.X, startOrigin.Y.Offset + d.Y)
    end)
end
makeDraggable(root, header)

-- ── viewer state + openViewer defined before the picker uses it ───────────
local viewer, viewerThread, viewerRows, viewerTarget

local function makeBarRow(name)
    local row = corner(mk(Instance.new("Frame"), {
        Name = name, Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Color3.fromRGB(40, 43, 52), BackgroundTransparency = 0.25,
        BorderSizePixel = 0, LayoutOrder = 0,
    }), 5)

    mk(Instance.new("TextLabel"), {
        Parent = row, Position = UDim2.fromOffset(7, 3), Size = UDim2.new(1, -14, 0, 13),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
        Text = name, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Color3.fromRGB(235, 235, 240), TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local bar = chrome(mk(Instance.new("Frame"), {
        Name = "FillBar", Position = UDim2.fromOffset(7, 19),
        Size = UDim2.fromOffset(CONFIG.trackW, CONFIG.trackH),
        BackgroundColor3 = Color3.fromRGB(20, 22, 27), BorderSizePixel = 0,
    }), 1)

    local indicator = corner(mk(Instance.new("Frame"), {
        Name = "Indicator", Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = BANDS[#BANDS].colour, BorderSizePixel = 0,
    }), 1)
    indicator.Parent = bar
    bar.Parent = row

    return { frame = row, indicator = indicator, tween = nil }
end

local function applyValue(r, raw)
    local v = math.floor(tonumber(raw) or 0)
    local frac = math.clamp(v / MAX, 0, 1)

    if r.tween then r.tween:Cancel() end
    r.tween = TweenService:Create(r.indicator,
        TweenInfo.new(CONFIG.tweenTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
        { Size = UDim2.new(frac, 0, 1, 0), BackgroundColor3 = colourFor(v) })
    r.tween:Play()

    r.frame.LayoutOrder = 100 - frac * 100
end

local function closeViewer()
    if viewerThread then task.cancel(viewerThread); viewerThread = nil end
    for _, r in pairs(viewerRows or {}) do
        if r.tween then r.tween:Cancel() end
    end
    viewerRows = {}
    if viewer then viewer:Destroy(); viewer = nil end
    viewerTarget = nil
end

function openViewer(player)
    closeViewer()
    viewerTarget, viewerRows = player, {}

    viewer = chrome(mk(Instance.new("Frame"), {
        Name = "Viewer", Size = UDim2.fromOffset(280, 420),
        Position = UDim2.new(0, 290, 0, 120),
        BackgroundColor3 = Color3.fromRGB(24, 26, 32), BackgroundTransparency = 0.06,
        BorderSizePixel = 0,
    }), 8)
    viewer.Parent = gui

    local vh = corner(mk(Instance.new("Frame"), {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(32, 35, 42),
        BorderSizePixel = 0,
    }), 8)
    vh.Parent = viewer

    mk(Instance.new("TextLabel"), {
        Parent = vh, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -46, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
        Text = player.Name, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Color3.fromRGB(230, 230, 235), TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local vClose = corner(mk(Instance.new("TextButton"), {
        Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Color3.fromRGB(180, 60, 60), Text = "×", TextSize = 16,
        Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true,
    }), 6)
    vClose.Parent = vh
    vClose.MouseButton1Click:Connect(closeViewer)

    local vHint = mk(Instance.new("TextLabel"), {
        Parent = viewer, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
        Text = "Waiting for CharacterInfo…", TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(160, 165, 180),
    }, { mk(Instance.new("UIPadding"), { PaddingLeft = UDim.new(0, 10) }) })

    local vList = mk(Instance.new("ScrollingFrame"), {
        Parent = viewer, Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 1, -58),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5,
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
    }, {
        mk(Instance.new("UIPadding"), { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
        mk(Instance.new("UIListLayout"), { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
    })

    makeDraggable(viewer, vh)

    viewerThread = task.spawn(function()
        while viewer and viewer.Parent and player.Parent do
            local groups = getGroups(player)
            if groups then
                local ok, err = pcall(function()
                    vHint.Text = ""
                    for _, name in ipairs(GROUPS) do
                        local stat = groups:FindFirstChild(name)
                        if stat and stat:IsA("ValueBase") then
                            local r = viewerRows[name]
                            if not r then r = makeBarRow(name); viewerRows[name] = r end
                            if r.frame.Parent ~= vList then r.frame.Parent = vList end
                            r.frame.Visible = true
                            applyValue(r, stat.Value)
                        else
                            local r = viewerRows[name]
                            if r then r.frame.Visible = false end
                        end
                    end
                end)
                if not ok then vHint.Text = "poll error: " .. tostring(err) end
            else
                vHint.Text = player.Name .. ": CharacterInfo not replicated yet"
            end
            task.wait(CONFIG.refresh)
        end
    end)
end

-- ── picker (now safely after openViewer) ──────────────────────────────────
local function addUserRow(player)
    local ready = getGroups(player) ~= nil

    local btn = corner(mk(Instance.new("TextButton"), {
        Name = player.Name, Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Color3.fromRGB(40, 43, 52), BackgroundTransparency = 0.25,
        BorderSizePixel = 0, Text = "", AutoButtonColor = ready, LayoutOrder = ready and 0 or 1,
    }), 5)

    mk(Instance.new("TextLabel"), {
        Parent = btn, Position = UDim2.fromOffset(7, 0), Size = UDim2.new(1, -14, 1, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
        Text = player.Name, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = ready and Color3.fromRGB(235, 235, 240) or Color3.fromRGB(130, 134, 146),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    btn.MouseButton1Click:Connect(function()
        if getGroups(player) then openViewer(player) end
    end)
    btn.Parent = list
end

local function rebuildUserList()
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if n >= CONFIG.maxUsers then break end
        n += 1
        addUserRow(p)
    end
end

-- ── boot ──────────────────────────────────────────────────────────────────
local ok, err = pcall(rebuildUserList)
if not ok then
    warn("[RepViewer] boot failed: " .. tostring(err))
    getgenv().killRepViewer()
    return
end

refreshBtn.MouseButton1Click:Connect(rebuildUserList)
Players.PlayerAdded:Connect(rebuildUserList)
Players.PlayerRemoving:Connect(function(p)
    if viewerTarget == p then closeViewer() end
    rebuildUserList()
end)

print("[RepViewer] loaded — kill with getgenv().killRepViewer()")