local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")
local Lighting         = game:GetService("Lighting")
local CoreGui          = game:GetService("CoreGui")

local LP       = Players.LocalPlayer
local char     = LP.Character or LP.CharacterAdded:Wait()
local hrp      = char:WaitForChild("HumanoidRootPart")
local hum      = char:WaitForChild("Humanoid")

--==================================================================
-- STATE
--==================================================================
local State = {
    AutoSteal     = false,
    SilentSteal   = true,
    SafeZoneAfter = true,
    AntiAFK       = false,
    NoGravity     = false,
    InfJump       = false,
    Fly           = false,
    WalkSpeed     = 16,
    JumpPower     = 50,
    SelectedEgg   = nil,
    AutoDelay     = 2,
    UIHidden      = false,
}

--==================================================================
-- EGG SCANNER  (exact egg names, filters out models/decoration)
--==================================================================
local function getEggs()
    local eggs = {}
    local eggFolder = Workspace:FindFirstChild("Eggs")
        or Workspace:FindFirstChild("Egg")
        or Workspace:FindFirstChild("SpawnedEggs")
    local roots = eggFolder and {eggFolder} or {Workspace}

    for _, root in ipairs(roots) do
        for _, obj in ipairs(root:GetDescendants()) do
            if not obj:IsA("BasePart") and not obj:IsA("Model") then continue end
            local n = obj.Name
            -- egg parts almost always contain "Egg" and are named after their type
            local lname = n:lower()
            if (lname:find("egg") or lname:find("golden") or lname:find("rainbow")
                or lname:find("cyber") or lname:find("dragon"))
                and not lname:find("guardian")
                and not lname:find("pedestal")
                and not lname:find("decor")
                and not lname:find("shard")
                and not lname:find("particle")
                and not lname:find("effect")
                and not lname:find("beam")
                and not lname:find("outline")
                and not lname:find("highlight")
                and not lname:find("base") then
                table.insert(eggs, obj)
            end
        end
    end
    return eggs
end

local function eggLabel(egg)
    return egg.Name:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
end

local function uniqueEggLabels()
    local seen, list = {}, {}
    for _, e in ipairs(getEggs()) do
        local label = eggLabel(e)
        if not seen[label] then
            seen[label] = true
            table.insert(list, label)
        end
    end
    table.sort(list)
    return list
end

local function findEggByLabel(label)
    for _, e in ipairs(getEggs()) do
        if eggLabel(e) == label then return e end
    end
end

--==================================================================
-- SAFE ZONE DETECTION
--==================================================================
local function getSafeZone()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local n = obj.Name:lower()
        if (n:find("safezone") or n:find("safe zone") or n:find("safe_area")
            or n:find("spawn") or n:find("hub") or n:find("base")) and obj:IsA("BasePart") then
            return obj
        end
    end
    return nil
end

--==================================================================
-- MAIN STEAL LOGIC
--==================================================================
local stealing = false

local function stealEgg(egg)
    if stealing or not egg or not egg.Parent then return end
    stealing = true
    local ok, err = pcall(function()
        local targetPos
        if egg:IsA("BasePart") then
            targetPos = egg.CFrame
        else
            targetPos = egg:GetPivot()
        end

        -- silent steal: put guardians to sleep
        if State.SilentSteal then
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("Model") and d.Name:lower():find("guardian") then
                    if d:FindFirstChildOfClass("Humanoid") then
                        d:FindFirstChildOfClass("Humanoid").PlatformStand = true
                        d:FindFirstChildOfClass("Humanoid").WalkSpeed = 0
                        d:FindFirstChildOfClass("Humanoid").JumpPower = 0
                    end
                    for _, part in ipairs(d:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                            part.Anchored = true
                        end
                    end
                end
            end
            if getgenv and getgenv().silent then pcall(getgenv().silent) end
        end

        -- teleport to egg
        local oldCF = hrp.CFrame
        hrp.CFrame = targetPos + Vector3.new(0, 3, 0)
        task.wait(0.08)

        -- fire touch / click
        for _, obj in ipairs(egg:GetChildren()) do
            if obj:IsA("ClickDetector") then
                fireclickdetector(obj)
            elseif obj:IsA("ProximityPrompt") then
                fireproximityprompt(obj)
            end
        end
        if egg:IsA("BasePart") then
            for _, obj in ipairs(egg:GetChildren()) do
                if obj:IsA("ClickDetector") then fireclickdetector(obj) end
            end
        end
        -- simulate touch
        local fakeTouch = Instance.new("Part")
        fakeTouch.Size = Vector3.new(2, 2, 2)
        fakeTouch.CanCollide = false
        fakeTouch.Transparency = 1
        fakeTouch.Anchored = true
        fakeTouch.CFrame = targetPos
        fakeTouch.Parent = Workspace
        firetouchinterest(hrp, fakeTouch, 0)
        task.wait(0.05)
        firetouchinterest(hrp, fakeTouch, 1)
        fakeTouch:Destroy()

        -- collect via remote if present (game-specific fallback)
        for _, remote in ipairs(game:GetDescendants()) do
            if remote:IsA("RemoteFunction") or remote:IsA("RemoteEvent") then
                local rn = remote.Name:lower()
                if rn:find("collect") or rn:find("steal") or rn:find("toucheck")
                    or rn:find("egg") or rn:find("claim") then
                    pcall(function()
                        if remote:IsA("RemoteFunction") then
                            remote:InvokeServer(egg)
                        else
                            remote:FireServer(egg)
                        end
                    end)
                end
            end
        end

        -- wait for egg to vanish (means success)
        local t0 = tick()
        while egg.Parent and tick() - t0 < 1.5 do task.wait(0.05) end
        local success = (egg.Parent == nil)

        -- safezone teleport
        if State.SafeZoneAfter then
            local sz = getSafeZone()
            if sz then
                hrp.CFrame = sz.CFrame + Vector3.new(0, 5, 0)
            else
                hrp.CFrame = oldCF
            end
        end
        return success
    end)
    stealing = false
    if not ok then warn("[StealAnEgg] " .. tostring(err)) end
end

--==================================================================
-- ANTI AFK
--==================================================================
local vu = game:GetService("VirtualUser")
LP.Idled:Connect(function()
    if not State.AntiAFK then return end
    vu:CaptureController()
    vu:ClickButton2(Vector2.new())
end)

--==================================================================
-- NO GRAVITY / WALK / JUMP / INF JUMP
--==================================================================
RunService.Heartbeat:Connect(function()
    if State.NoGravity and hrp then
        hrp.Velocity = Vector3.new(hrp.Velocity.X, 0, hrp.Velocity.Z)
    end
    if hum then
        hum.WalkSpeed = State.WalkSpeed
        hum.JumpPower  = State.JumpPower
    end
end)

UserInputService.JumpRequest:Connect(function()
    if State.InfJump and hum then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

--==================================================================
-- FLY
--==================================================================
local flyBodyGyro, flyBodyVel
local function startFly()
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = Vector3.zero
    bv.Parent = hrp
    flyBodyVel = bv
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.P = 1e4
    bg.Parent = hrp
    flyBodyGyro = bg
end
local function stopFly()
    if flyBodyVel then flyBodyVel:Destroy() end
    if flyBodyGyro then flyBodyGyro:Destroy() end
end

RunService.RenderStepped:Connect(function()
    if not State.Fly or not flyBodyVel then return end
    local cam = Workspace.CurrentCamera
    local move = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += cam.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= cam.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= cam.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += cam.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end
    if move.Magnitude > 0 then move = move.Unit * (State.WalkSpeed * 3) end
    flyBodyVel.Velocity = move
    flyBodyGyro.CFrame = cam.CFrame
end)

--==================================================================
-- AUTO STEAL LOOP
--==================================================================
task.spawn(function()
    while task.wait(State.AutoDelay) do
        if State.AutoSteal and State.SelectedEgg then
            local egg = findEggByLabel(State.SelectedEgg)
            if egg then stealEgg(egg) end
        end
    end
end)

--==================================================================
-- GUI
--==================================================================
-- remove old
for _, g in ipairs(CoreGui:GetChildren()) do
    if g.Name == "StealAnEggUI" then g:Destroy() end
end

local function round(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = inst
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "StealAnEggUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

-- main overlay
local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 240, 0, 320)
Main.Position = UDim2.new(0, 20, 0, 20)
Main.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui
round(Main, 10)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 0, 30)
Title.Position = UDim2.new(0, 12, 0, 4)
Title.BackgroundTransparency = 1
Title.Text = "🥚 Steal An Egg"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextColor3 = Color3.fromRGB(240, 240, 240)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 22, 0, 22)
CloseBtn.Position = UDim2.new(1, -30, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Parent = Main
round(CloseBtn, 6)

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -20, 1, -50)
Scroll.Position = UDim2.new(0, 10, 0, 40)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 4
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.Parent = Main

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 6)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Parent = Scroll

-- helper: toggle row
local function Toggle(parent, label, key, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 26)
    row.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    row.BorderSizePixel = 0
    row.Parent = parent
    round(row, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -50, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 34, 0, 18)
    btn.Position = UDim2.new(1, -42, 0, 4)
    btn.BackgroundColor3 = State[key] and Color3.fromRGB(60, 180, 100) or Color3.fromRGB(60, 60, 70)
    btn.Text = State[key] and "ON" or "OFF"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Parent = row
    round(btn, 4)

    btn.MouseButton1Click:Connect(function()
        State[key] = not State[key]
        btn.BackgroundColor3 = State[key] and Color3.fromRGB(60, 180, 100) or Color3.fromRGB(60, 60, 70)
        btn.Text = State[key] and "ON" or "OFF"
        if callback then callback(State[key]) end
    end)
    return row
end

-- helper: slider row
local function Slider(parent, label, key, min, max, step, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 48)
    row.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    row.BorderSizePixel = 0
    row.Parent = parent
    round(row, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -12, 0, 18)
    lbl.Position = UDim2.new(0, 8, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Text = label .. ": " .. tostring(State[key])
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local bar = Instance.new("TextButton")
    bar.Size = UDim2.new(1, -16, 0, 12)
    bar.Position = UDim2.new(0, 8, 0, 28)
    bar.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    bar.Text = ""
    bar.AutoButtonColor = false
    bar.Parent = row
    round(bar, 6)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((State[key] - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(90, 160, 255)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    round(fill, 6)

    local dragging = false
    local function setFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = math.floor((min + (max - min) * rel) / step + 0.5) * step
        State[key] = val
        lbl.Text = label .. ": " .. tostring(val)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        if callback then callback(val) end
    end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(i.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            setFromX(i.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return row
end

-- dropdown row
local function Dropdown(parent, label, key, getList, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 30)
    row.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    row.BorderSizePixel = 0
    row.Parent = parent
    round(row, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -30, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label .. ": " .. (State[key] or "none")
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 20, 1, 0)
    arrow.Position = UDim2.new(1, -22, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "▾"
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 14
    arrow.TextColor3 = Color3.fromRGB(180, 180, 190)
    arrow.Parent = row

    local list = Instance.new("ScrollingFrame")
    list.Size = UDim2.new(1, -8, 0, 140)
    list.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 4
    list.Visible = false
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.Parent = row
    round(list, 6)

    local ll = Instance.new("UIListLayout")
    ll.Padding = UDim.new(0, 2)
    ll.Parent = list

    local function rebuild()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local items = getList()
        for _, name in ipairs(items) do
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, -4, 0, 22)
            b.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
            b.Text = name
            b.Font = Enum.Font.Gotham
            b.TextSize = 11
            b.TextColor3 = Color3.fromRGB(220, 220, 220)
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.Parent = list
            round(b, 4)
            b.MouseButton1Click:Connect(function()
                State[key] = name
                lbl.Text = label .. ": " .. name
                list.Visible = false
                if callback then callback(name) end
            end)
        end
    end

    local open = false
    row.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            open = not open
            if open then rebuild() end
            list.Visible = open
            arrow.Text = open and "▴" or "▾"
        end
    end)
    return row
end

-- build controls
Toggle(Scroll, "Auto Steal", "AutoSteal")
Toggle(Scroll, "Silent Steal (guard sleep)", "SilentSteal")
Toggle(Scroll, "Safe Zone after grab", "SafeZoneAfter")
Toggle(Scroll, "Anti AFK", "AntiAFK")
Toggle(Scroll, "No Gravity", "NoGravity")
Toggle(Scroll, "Infinite Jump", "InfJump")
Toggle(Scroll, "Fly", "Fly", function(v)
    if v then startFly() else stopFly() end
end)
Slider(Scroll, "Walk Speed", "WalkSpeed", 16, 200, 1)
Slider(Scroll, "Jump Power", "JumpPower", 50, 300, 1)
Slider(Scroll, "Auto Delay (s)", "AutoDelay", 0.5, 10, 0.5)
Dropdown(Scroll, "Egg", "SelectedEgg", uniqueEggLabels, function(name)
    local egg = findEggByLabel(name)
    if egg then
        hrp.CFrame = (egg:IsA("BasePart") and egg.CFrame or egg:GetPivot()) + Vector3.new(0, 3, 0)
    end
end)

-- refresh egg list occasionally
task.spawn(function()
    while task.wait(10) do
        if not ScreenGui.Parent then break end
    end
end)

--==================================================================
-- MINI OVERLAY (toggle orb)
--==================================================================
local Mini = Instance.new("TextButton")
Mini.Name = "Mini"
Mini.Size = UDim2.new(0, 44, 0, 44)
Mini.Position = UDim2.new(0, 20, 0, 20)
Mini.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
Mini.Text = "🥚"
Mini.Font = Enum.Font.GothamBold
Mini.TextSize = 20
Mini.TextColor3 = Color3.fromRGB(255, 255, 255)
Mini.Visible = false
Mini.Active = true
Mini.Draggable = true
Mini.Parent = ScreenGui
round(Mini, 22)

CloseBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    Mini.Visible = true
end)
Mini.MouseButton1Click:Connect(function()
    Main.Visible = true
    Mini.Visible = false
end)

--==================================================================
-- CHARACTER RESPAWN REHOOK
--==================================================================
LP.CharacterAdded:Connect(function(newChar)
    char = newChar
    hrp  = newChar:WaitForChild("HumanoidRootPart")
    hum  = newChar:WaitForChild("Humanoid")
    if State.Fly then
        stopFly()
        startFly()
    end
end)

print("[StealAnEgg] loaded — no key, absolute LeakWorm")
