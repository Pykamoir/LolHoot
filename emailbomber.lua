-- EagleGui Mass Mailer — standalone UI. Run in an executor with injected instance layer.
-- Toggle with RightShift.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local SendEmail = RS:WaitForChild("EagleRemotes"):WaitForChild("Press"):WaitForChild("SendEmail")

local BATCH, DELAY = 3, 3
local selected = {}

-- remove an existing instance if you re-run
if game.Players.LocalPlayer.PlayerGui:FindFirstChild("MassMailerUI") then
    game.Players.LocalPlayer.PlayerGui.MassMailerUI:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "MassMailerUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local win = Instance.new("Frame")
win.Size = UDim2.fromOffset(340, 430)
win.Position = UDim2.new(0.5, -170, 0.5, -215)
win.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
win.BorderSizePixel = 0
win.Active = true
win.Draggable = true
win.Parent = gui
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 8)

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 30)
bar.BackgroundColor3 = Color3.fromRGB(38, 38, 44)
bar.BorderSizePixel = 0
bar.Parent = win
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(235, 235, 240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Mass Mailer"
title.Parent = bar

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(24, 24)
close.Position = UDim2.new(1, -30, 0, 3)
close.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
close.Text = "x"
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.GothamBold
close.TextSize = 12
close.Parent = bar
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 4)
close.Activated:Connect(function() win.Visible = false end)

-- drag (the Frame.Draggable property is legacy and unreliable inside GUIs)
local dragging, dragIn, dragPos
bar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging, dragIn, dragPos = true, i.Position, win.Position
    end
end)
game:GetService("UserInputService").InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragIn
        win.Position = UDim2.new(dragPos.X.Scale, dragPos.X.Offset + d.X, dragPos.Y.Scale, dragPos.Y.Offset + d.Y)
    end
end)
game:GetService("UserInputService").InputEnded:Connect(function()
    dragging = false
end)

local function label(y, text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -20, 0, 14)
    l.Position = UDim2.fromOffset(10, y)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextSize = 11
    l.TextColor3 = Color3.fromRGB(150, 150, 160)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = win
    return l
end

label(36, "Subject")
local subj = Instance.new("TextBox")
subj.Size = UDim2.new(1, -20, 0, 26)
subj.Position = UDim2.fromOffset(10, 52)
subj.BackgroundColor3 = Color3.fromRGB(44, 44, 50)
subj.TextColor3 = Color3.fromRGB(235, 235, 240)
subj.PlaceholderText = "Put Subject Here"
subj.PlaceholderColor3 = Color3.fromRGB(110, 110, 120)
subj.Font = Enum.Font.Gotham
subj.TextSize = 12
subj.TextXAlignment = Enum.TextXAlignment.Left
subj.ClearTextOnFocus = false
subj.ClipsDescendants = true
subj.Parent = win
Instance.new("UICorner", subj).CornerRadius = UDim.new(0, 4)
Instance.new("UIPadding", subj).PaddingLeft = UDim.new(0, 5)
subj:GetPropertyChangedSignal("Text"):Connect(function()
    if #subj.Text > 120 then subj.Text = subj.Text:sub(1, 120) end
end)

label(84, "Content")
local body = Instance.new("TextBox")
body.Size = UDim2.new(1, -20, 0, 110)
body.Position = UDim2.fromOffset(10, 100)
body.BackgroundColor3 = Color3.fromRGB(44, 44, 50)
body.TextColor3 = Color3.fromRGB(235, 235, 240)
body.PlaceholderText = "Put Content Here"
body.PlaceholderColor3 = Color3.fromRGB(110, 110, 120)
body.Font = Enum.Font.Gotham
body.TextSize = 12
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextWrapped = true
body.MultiLine = true
body.ClearTextOnFocus = false
body.Parent = win
Instance.new("UICorner", body).CornerRadius = UDim.new(0, 4)
Instance.new("UIPadding", body).PaddingLeft = UDim.new(0, 5)
Instance.new("UIPadding", body).PaddingTop = UDim.new(0, 5)

label(216, "Party filter (none = everyone)")

local partyList = Instance.new("Frame")
partyList.Size = UDim2.new(1, -20, 0, 30)
partyList.Position = UDim2.fromOffset(10, 232)
partyList.BackgroundTransparency = 1
partyList.Parent = win

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 4)
layout.Parent = partyList

local count = Instance.new("TextLabel")
count.Size = UDim2.new(1, -20, 0, 14)
count.Position = UDim2.fromOffset(10, 266)
count.BackgroundTransparency = 1
count.Font = Enum.Font.Gotham
count.TextSize = 11
count.TextColor3 = Color3.fromRGB(150, 150, 160)
count.TextXAlignment = Enum.TextXAlignment.Left
count.Text = "—"
count.Parent = win

local log = Instance.new("TextLabel")
log.Size = UDim2.new(1, -20, 0, 74)
log.Position = UDim2.fromOffset(10, 284)
log.BackgroundColor3 = Color3.fromRGB(20, 20, 23)
log.TextColor3 = Color3.fromRGB(160, 200, 160)
log.Font = Enum.Font.Code
log.TextSize = 10
log.TextXAlignment = Enum.TextXAlignment.Left
log.TextYAlignment = Enum.TextYAlignment.Top
log.TextWrapped = true
log.Text = ""
log.Parent = win
Instance.new("UICorner", log).CornerRadius = UDim.new(0, 4)

local logBuf = {}
local function put(s)
    table.insert(logBuf, s)
    while #logBuf > 6 do table.remove(logBuf, 1) end
    log.Text = table.concat(logBuf, "\n")
end

local send = Instance.new("TextButton")
send.Size = UDim2.new(1, -20, 0, 30)
send.Position = UDim2.new(0, 10, 1, -40)
send.BackgroundColor3 = Color3.fromRGB(60, 130, 90)
send.TextColor3 = Color3.new(1, 1, 1)
send.Font = Enum.Font.GothamBold
send.TextSize = 13
send.Text = "Send"
send.Parent = win
Instance.new("UICorner", send).CornerRadius = UDim.new(0, 5)

local function partyOf(plr)
    local ci = plr:FindFirstChild("CharacterInfo")
    local pv = ci and ci:FindFirstChild("PoliticalParty")
    return pv and tostring(pv.Value):lower() or ""
end

local function partyDefs()
    local out = {}
    local root = RS:FindFirstChild("Parties")
    if not root then return out end
    for _, folder in ipairs(root:GetChildren()) do
        local nv = folder:FindFirstChild("PartyName")
        if nv then table.insert(out, { key = folder.Name:lower(), name = tostring(nv.Value) }) end
    end
    return out
end

local function matching()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if next(selected) == nil or selected[partyOf(p)] then table.insert(out, p.UserId) end
        end
    end
    return out
end

local function refreshCount()
    count.Text = ("%d players match"):format(#matching())
end

local function drawParties()
    partyList:ClearAllChildren()
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Horizontal
    l.Padding = UDim.new(0, 4)
    l.Parent = partyList
    for _, d in ipairs(partyDefs()) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(0, 26)
        b.AutomaticSize = Enum.AutomaticSize.X
        b.BackgroundColor3 = selected[d.key] and Color3.fromRGB(60, 130, 90) or Color3.fromRGB(44, 44, 50)
        b.TextColor3 = Color3.fromRGB(235, 235, 240)
        b.Font = Enum.Font.Gotham
        b.TextSize = 11
        b.Text = "  " .. d.name .. "  "
        b.Parent = partyList
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        b.Activated:Connect(function()
            selected[d.key] = not selected[d.key] or nil
            b.BackgroundColor3 = selected[d.key] and Color3.fromRGB(60, 130, 90) or Color3.fromRGB(44, 44, 50)
            refreshCount()
        end)
    end
    refreshCount()
end

local busy = false
send.Activated:Connect(function()
    if busy then return end
    local content = body.Text
    local subject = subj.Text
    if content == "" then return put("abort: empty content") end
    local targets = matching()
    if #targets == 0 then return put("abort: 0 targets") end
    busy = true
    put(("sending %d in %d batches"):format(#targets, math.ceil(#targets / BATCH)))
    for i = 1, #targets, BATCH do
        local group = {}
        for j = i, math.min(i + BATCH - 1, #targets) do table.insert(group, targets[j]) end
        SendEmail:FireServer({
            seed = nil,
            subject = subject:sub(1, 120),
            content = content:sub(1, 4000),
            recips = group,
        })
        task.wait(DELAY)
    end
    busy = false
    put("done")
end)

gui:GetPropertyChangedSignal("Parent"):Connect(function() if not gui.Parent then gui:Destroy() end end)

drawParties()
task.spawn(function()
    while gui.Parent do
        refreshCount()
        task.wait(5)
    end
end)

-- rebind the window to RightShift after a close
game:GetService("UserInputService").InputBegan:Connect(function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift then
        win.Visible = not win.Visible
    end
end)