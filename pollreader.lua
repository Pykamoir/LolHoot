-- Player reputation viewer. Read-only, client-side.
-- Data: Players.<name>.CharacterInfo.FirstName / LastName / InterestGroups.<Group>.Value (0..101)
--       Party resolved via CharacterInfo.PoliticalParty → ReplicatedStorage.Parties.<id>.PartyName
--       PoliticalParty is unwrapped across StringValue / ObjectValue / Folder shapes.
-- Teardown: hold Right-Ctrl, or getgenv().killRepViewer()

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local UIS                = game:GetService("UserInputService")
local LocalPlayer        = Players.LocalPlayer

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
    refresh     = 0.5,
    tweenTime   = 0.5,
    maxUsers    = 200,
    trackW      = 190,
    trackH      = 9,
    rootW       = 240,
    rootH       = 400,
    viewerW     = 280,
    viewerH     = 420,
    rowH        = 26,
    rowGap      = 4,
    viewerGap   = 300,
    headerH     = 34,
    partyH      = 18,
    subRowH     = 13,
}

local INDEPENDENT  = "Independant"
local INDEP_COLOUR = Color3.fromRGB(255, 255, 255)
local PARTY_COLOUR = Color3.fromRGB(150, 175, 220)

local searchTerm = ""

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
    mk(Instance.new("UICorner"), { CornerRadius = UDim.new(0, r or 0), Parent = inst })
    return inst
end

local function colourFor(raw)
    for _, band in ipairs(BANDS) do
        if raw >= band.min then return band.colour end
    end
    return BANDS[#BANDS].colour
end

local function getCharacters(player)
    local ci = player:FindFirstChild("CharacterInfo")
    return ci and ci:FindFirstChild("InterestGroups") or nil
end

local function getInfo(player)
    return player:FindFirstChild("CharacterInfo")
end

-- "USER1234" → "John Hall", username fallback
local function displayName(player)
    local ci = getInfo(player)
    if not ci then return player.Name end

    local first = ci:FindFirstChild("FirstName")
    local last  = ci:FindFirstChild("LastName")
    local f = first and typeof(first.Value) == "string" and first.Value ~= "" and first.Value or nil
    local l = last  and typeof(last.Value)  == "string" and last.Value  ~= "" and last.Value  or nil

    if f and l then return f .. " " .. l end
    if f then return f end
    return player.Name
end

-- unwrap PoliticalParty across StringValue / ObjectValue / Folder, then read PartyName
local function partyEntry(player)
    local ci = getInfo(player)
    local pp = ci and ci:FindFirstChild("PoliticalParty")
    if not pp then return nil end

    if pp:IsA("ObjectValue") then
        return pp.Value
    end

    local id
    if pp:IsA("ValueBase") then
        id = pp.Value
    elseif pp:IsA("Folder") then
        local s = pp:FindFirstChildWhichIsA("StringValue", true)
        id = s and s.Value
    end

    if typeof(id) ~= "string" or id == "" then return nil end
    local parties = ReplicatedStorage:FindFirstChild("Parties")
    return parties and parties:FindFirstChild(id) or nil
end

local function partyName(player)
    local entry = partyEntry(player)
    if not entry then return nil end
    local pname = entry:FindFirstChild("PartyName", true)
    local v = pname and pname:IsA("ValueBase") and pname.Value
    return (typeof(v) == "string" and v ~= "") and v or nil
end

local function partyLabel(player)
    return partyName(player) or INDEPENDENT
end

local function partyColour(player)
    return partyName(player) and PARTY_COLOUR or INDEP_COLOUR
end

-- ── shell ─────────────────────────────────────────────────────────────────
local gui = mk(Instance.new("ScreenGui"), {
    Name = "RepViewer", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 9999999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

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

local root = corner(mk(Instance.new("Frame"), {
    Name = "Root", Size = UDim2.fromOffset(CONFIG.rootW, CONFIG.rootH),
    Position = UDim2.new(0.5, -CONFIG.rootW / 2, 0.4, -CONFIG.rootH / 2),
    BackgroundColor3 = Color3.fromRGB(24, 26, 32), BorderSizePixel = 0,
    ClipsDescendants = true,
}), 8)
root.Parent = gui

mk(Instance.new("UIStroke"), {
    Color = Color3.fromRGB(60, 64, 76), Thickness = 1,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = root,
})

local header = mk(Instance.new("Frame"), {
    Size = UDim2.new(1, 0, 0, CONFIG.headerH),
    BackgroundColor3 = Color3.fromRGB(32, 35, 42), BorderSizePixel = 0, ZIndex = 1,
})
header.Parent = root

mk(Instance.new("TextLabel"), {
    Parent = header, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -40, 1, 0),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
    Text = "Players", TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Color3.fromRGB(230, 230, 235), ZIndex = 1,
})

local searchBox = corner(mk(Instance.new("TextBox"), {
    Size = UDim2.new(1, -14, 0, 22),
    Position = UDim2.fromOffset(7, CONFIG.headerH + 4),
    BackgroundColor3 = Color3.fromRGB(44, 48, 58),
    BorderSizePixel = 0, ZIndex = 1,
    Font = Enum.Font.GothamMedium, TextSize = 11,
    TextColor3 = Color3.fromRGB(230, 232, 240),
    PlaceholderText = "Search players…",
    PlaceholderColor3 = Color3.fromRGB(130, 134, 146),
    Text = "", ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
}), 5)
searchBox.Parent = root
mk(Instance.new("UIPadding"), { PaddingLeft = UDim.new(0, 8), Parent = searchBox })

local listTop = CONFIG.headerH + 32

local list = mk(Instance.new("ScrollingFrame"), {
    Parent = root, Position = UDim2.fromOffset(0, listTop),
    Size = UDim2.new(1, 0, 1, -listTop),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5,
    ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 1,
}, {
    mk(Instance.new("UIPadding"), {
        PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 7),
        PaddingRight = UDim.new(0, 7), PaddingBottom = UDim.new(0, 6),
    }),
    mk(Instance.new("UIListLayout"), {
        Padding = UDim.new(0, CONFIG.rowGap), SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

-- ── drag ──────────────────────────────────────────────────────────────────
local function makeDraggable(frame, handle)
    local dragging, startPos, startAbs

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            startPos  = input.Position
            startAbs  = frame.AbsolutePosition
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        local d = input.Position - startPos
        frame.Position = UDim2.fromOffset(startAbs.X + d.X, startAbs.Y + d.Y)
    end)
end
makeDraggable(root, header)

-- ── viewer state + openViewer ─────────────────────────────────────────────
local viewer, viewerThread, viewerRows, viewerTarget

local function makeBarRow(name)
    local row = corner(mk(Instance.new("Frame"), {
        Name = name, Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Color3.fromRGB(40, 43, 52), BorderSizePixel = 0,
        LayoutOrder = 0,
    }), 5)

    mk(Instance.new("TextLabel"), {
        Parent = row, Position = UDim2.fromOffset(7, 3), Size = UDim2.new(1, -14, 0, 13),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
        Text = name, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Color3.fromRGB(235, 235, 240), TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local bar = corner(mk(Instance.new("Frame"), {
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

    viewer = corner(mk(Instance.new("Frame"), {
        Name = "Viewer", Size = UDim2.fromOffset(CONFIG.viewerW, CONFIG.viewerH),
        Position = UDim2.new(0.5, -CONFIG.viewerW / 2 + CONFIG.viewerGap,
            0.4, -CONFIG.viewerH / 2),
        BackgroundColor3 = Color3.fromRGB(24, 26, 32), BorderSizePixel = 0,
        ClipsDescendants = true,
    }), 8)
    viewer.Parent = gui

    mk(Instance.new("UIStroke"), {
        Color = Color3.fromRGB(60, 64, 76), Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = viewer,
    })

    local vh = mk(Instance.new("Frame"), {
        Size = UDim2.new(1, 0, 0, CONFIG.headerH + CONFIG.partyH),
        BackgroundColor3 = Color3.fromRGB(32, 35, 42), BorderSizePixel = 0, ZIndex = 1,
    })
    vh.Parent = viewer

    local vName = mk(Instance.new("TextLabel"), {
        Parent = vh, Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -46, 0, 18),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
        Text = displayName(player), TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Color3.fromRGB(235, 235, 240), TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 1,
    })

    local vParty = mk(Instance.new("TextLabel"), {
        Parent = vh, Position = UDim2.fromOffset(10, 20), Size = UDim2.new(1, -46, 0, 14),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
        Text = partyLabel(player), TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = partyColour(player),
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 1,
    })

    local vClose = corner(mk(Instance.new("TextButton"), {
        Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Color3.fromRGB(180, 60, 60), Text = "×", TextSize = 16,
        Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true,
        ZIndex = 2,
    }), 6)
    vClose.Parent = vh
    vClose.MouseButton1Click:Connect(closeViewer)

    local vListTop = CONFIG.headerH + CONFIG.partyH + 6

    local vList = mk(Instance.new("ScrollingFrame"), {
        Parent = viewer, Position = UDim2.fromOffset(0, vListTop),
        Size = UDim2.new(1, 0, 1, -vListTop),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5,
        ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 1,
    }, {
        mk(Instance.new("UIPadding"), {
            PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 6),
        }),
        mk(Instance.new("UIListLayout"), { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
    })

    makeDraggable(viewer, vh)

    viewerThread = task.spawn(function()
        while viewer and viewer.Parent and player.Parent do
            vName.Text = displayName(player)
            vParty.Text = partyLabel(player)
            vParty.TextColor3 = partyColour(player)

            local groups = getCharacters(player)
            if groups then
                local ok = pcall(function()
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
                if not ok then vName.Text = displayName(player) end
            end
            task.wait(CONFIG.refresh)
        end
    end)
end

-- ── picker ────────────────────────────────────────────────────────────────
local function addUserRow(player)
    local ready = getCharacters(player) ~= nil

    local btn = corner(mk(Instance.new("TextButton"), {
        Name = player.Name, Size = UDim2.new(1, 0, 0, CONFIG.rowH + CONFIG.subRowH),
        BackgroundColor3 = Color3.fromRGB(40, 43, 52), BorderSizePixel = 0,
        AutoButtonColor = ready, LayoutOrder = ready and 0 or 1, Text = "", ZIndex = 1,
    }), 5)

    mk(Instance.new("TextLabel"), {
        Parent = btn, Position = UDim2.fromOffset(7, 2), Size = UDim2.new(1, -14, 0, 15),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
        Text = displayName(player), TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = ready and Color3.fromRGB(235, 235, 240) or Color3.fromRGB(130, 134, 146),
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 1,
    })

    mk(Instance.new("TextLabel"), {
        Parent = btn, Position = UDim2.fromOffset(7, 16), Size = UDim2.new(1, -14, 0, 12),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10,
        Text = partyLabel(player), TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = partyColour(player),
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 1,
    })

    btn.MouseButton1Click:Connect(function()
        if getCharacters(player) then openViewer(player) end
    end)
    btn.Parent = list
end

local function rebuildUserList()
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end

    local total, n, matched = 0, 0, 0
    for _, p in ipairs(Players:GetChildren()) do
        if p:IsA("Player") and n < CONFIG.maxUsers then
            n += 1
            local label = displayName(p)
            if searchTerm == "" or string.find(string.lower(label), searchTerm, 1, true) then
                matched += 1
                addUserRow(p)
                total += CONFIG.rowH + CONFIG.subRowH + CONFIG.rowGap
            end
        end
    end

    list.CanvasSize = UDim2.fromOffset(0, total + 10)

    if matched == 0 and searchTerm ~= "" then
        mk(Instance.new("TextLabel"), {
            Parent = list, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 11,
            Text = "No players match", TextColor3 = Color3.fromRGB(130, 134, 146),
            TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 9999,
        })
    end
end

local pendingRebuild = false
local function queuedRebuild()
    if pendingRebuild then return end
    pendingRebuild = true
    task.defer(function()
        pendingRebuild = false
        local ok, err = pcall(rebuildUserList)
        if not ok then warn("[RepViewer] rebuild failed: " .. tostring(err)) end
    end)
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    searchTerm = string.lower(searchBox.Text)
    queuedRebuild()
end)

local function watchCharacterInfo(player)
    task.spawn(function()
        local ci = player:FindFirstChild("CharacterInfo")
            or player:WaitForChild("CharacterInfo", 60)
        if not ci then return end

        queuedRebuild()

        local function bindValue(v)
            if v and v:IsA("ValueBase") then
                v:GetPropertyChangedSignal("Value"):Connect(queuedRebuild)
            end
        end

        for _, key in ipairs({ "FirstName", "LastName", "PoliticalParty" }) do
            bindValue(ci:FindFirstChild(key))
        end

        ci.ChildAdded:Connect(function(c)
            queuedRebuild()
            if c.Name == "FirstName" or c.Name == "LastName" or c.Name == "PoliticalParty" then
                bindValue(c)
            end
        end)
        ci.ChildRemoved:Connect(queuedRebuild)

        task.spawn(function()
            local entry = partyEntry(player)
            local pname = entry and entry:FindFirstChild("PartyName", true)
            if pname and pname:IsA("ValueBase") then
                pname:GetPropertyChangedSignal("Value"):Connect(queuedRebuild)
            end
        end)
    end)
end

-- ── boot ──────────────────────────────────────────────────────────────────
local ok, err = pcall(rebuildUserList)
if not ok then
    warn("[RepViewer] boot failed: " .. tostring(err))
    getgenv().killRepViewer()
    return
end

Players.PlayerAdded:Connect(function(p)
    queuedRebuild()
    watchCharacterInfo(p)
end)
Players.PlayerRemoving:Connect(function(p)
    if viewerTarget == p then closeViewer() end
    queuedRebuild()
end)

for _, p in ipairs(Players:GetPlayers()) do
    watchCharacterInfo(p)
end

-- ── keybind teardown ──────────────────────────────────────────────────────
UIS.InputBegan:Connect(function(input, busy)
    if busy then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        getgenv().killRepViewer()
    end
end)

getgenv().killrepviewer = getgenv().killRepViewer
getgenv().KillRepViewer = getgenv().killRepViewer

print("[RepViewer] loaded — hold Right-Ctrl to close")
