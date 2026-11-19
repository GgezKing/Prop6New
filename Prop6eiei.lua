-- [[ ของเล่นใหม่ Brookhaven แบบ Source code เอาไปแกะกันเองนะ Made by Lloyd(ลอยด์) ]]
-- [[ Upgraded with Compact Fast-Spinning Ball Mode + Fold/Stack Mode + Player Target Follow + Prop Color Changer + Prop Explode ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

if not lp then return end

pcall(function()
    if type(_G.PropClusterCleanup) == "function" then
        _G.PropClusterCleanup()
    end
end)

local _activeConnections = {}
local function trackConn(conn)
    if conn then
        table.insert(_activeConnections, conn)
    end
    return conn
end

_G.PropClusterCleanup = function()
    for _, conn in ipairs(_activeConnections) do
        pcall(function()
            if conn and conn.Disconnect then
                conn:Disconnect()
            end
        end)
    end
    _activeConnections = {}
end

local function resolveParentGui()
    local ok1, hui = pcall(function()
        if type(gethui) == "function" then
            return gethui()
        end
        return nil
    end)
    if ok1 and typeof(hui) == "Instance" then
        return hui
    end

    local ok2, cg = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok2 and typeof(cg) == "Instance" then
        return cg
    end

    return lp:WaitForChild("PlayerGui", 5)
end

local parentGui = resolveParentGui()
if not parentGui then return end

pcall(function()
    local old = parentGui:FindFirstChild("PropFollowerGUI")
    if old then old:Destroy() end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PropFollowerGUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = parentGui

-- [[ ControlModule for Player Inputs (WASD + Mobile Thumbstick) ]]
local cm = nil
pcall(function()
    local ps = lp:FindFirstChild("PlayerScripts")
    local pm = ps and ps:FindFirstChild("PlayerModule")
    local cMod = pm and pm:FindFirstChild("ControlModule")
    if cMod and cMod:IsA("ModuleScript") then
        local req = require(cMod)
        if type(req) == "table" and type(req.GetMoveVector) == "function" then
            cm = req
        end
    end
end)

-- [[ State Variables ]]
local isFollowing = false
local isDriving = false
local isFlying = false
local targetPlayer = lp
local heightOffset = 0.0
local rotateWithPlayer = true
local networkThread = nil
local localRenderConn = nil
local driveRenderConn = nil
local trackedProps = {}

local clusterPos = Vector3.zero
local clusterYaw = 0
local clusterCFrame = CFrame.new()
local isDragMode = false
local isTapToPlace = false
local moveSpeed = 16
local speedMultiplier = 1.0
local holdingDir = nil
local lastNetSync = 0
local lastDriveNetSync = 0

-- Fold / Stack Mode Variables
local isFoldedMode = false

-- Driving Physics Variables
local driveSpeed = 20
local vertVel = 0
local isOnGround = true
local jumpRequested = false
local savedWalkSpeed = 16
local propDriveProxy = nil

-- Abduct Feature Variables
local abductRange = 15
local isAutoAbduct = false
local lastAbductCheck = 0
local isAbducting = false

-- Void Trap Variables
local isAutoVoidOnSit = true
local isVoidingTrap = false

-- Compact Fast-Spinning Ball Mode Variables
local isBallMode = false
local ballFollowTarget = true
local ballSpinConn = nil
local lastBallNetSync = 0
local ballBaseRadius = 1.05
local ballSpinSpeedMult = 3.2
local propSpinAxes = {}

-- Prop Explode Mode Variables
local isExploding = false
local explodeConn = nil
local explodeData = {}
local lastExplodeNetSync = 0

-- [[ Prop Geometry Definitions ]]
local distSide = 1.55
local distFrontBack = 1.50

local symRel11 = {
    [1]  = CFrame.new(0, -2.8, 0) * CFrame.Angles(0, 0, 0),
    [2]  = CFrame.new(0, -1.4, distFrontBack) * CFrame.Angles(0, math.rad(90), math.rad(-90)),
    [3]  = CFrame.new(0, -1.4, -distFrontBack) * CFrame.Angles(0, math.rad(-90), math.rad(-90)),
    [4]  = CFrame.new(distSide, -1.4, 0) * CFrame.Angles(0, math.rad(180), math.rad(-90)),
    [5]  = CFrame.new(-distSide, -1.4, 0) * CFrame.Angles(0, math.rad(0), math.rad(-90)),
    [6]  = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(180)),
    [7]  = CFrame.new(0, 1.4, distFrontBack) * CFrame.Angles(0, math.rad(90), math.rad(-90)),
    [8]  = CFrame.new(0, 1.4, -distFrontBack) * CFrame.Angles(0, math.rad(-90), math.rad(-90)),
    [9]  = CFrame.new(distSide, 1.4, 0) * CFrame.Angles(0, math.rad(180), math.rad(-90)),
    [10] = CFrame.new(-distSide, 1.4, 0) * CFrame.Angles(0, math.rad(0), math.rad(-90)),
    [11] = CFrame.new(0, 2.8, 0) * CFrame.Angles(0, 0, math.rad(180)),
}

local symRel15 = {
    [1]  = CFrame.new(0, -2.8, 0) * CFrame.Angles(0, 0, 0),
    [2]  = CFrame.new(0, -1.4, distFrontBack) * CFrame.Angles(0, math.rad(90), math.rad(-90)),
    [3]  = CFrame.new(0, -1.4, -distFrontBack) * CFrame.Angles(0, math.rad(-90), math.rad(-90)),
    [4]  = CFrame.new(distSide, -1.4, 0) * CFrame.Angles(0, math.rad(180), math.rad(-90)),
    [5]  = CFrame.new(-distSide, -1.4, 0) * CFrame.Angles(0, math.rad(0), math.rad(-90)),
    [6]  = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(180)),
    [7]  = CFrame.new(0, 1.4, distFrontBack) * CFrame.Angles(0, math.rad(90), math.rad(-90)),
    [8]  = CFrame.new(0, 1.4, -distFrontBack) * CFrame.Angles(0, math.rad(-90), math.rad(-90)),
    [9]  = CFrame.new(distSide, 1.4, 0) * CFrame.Angles(0, math.rad(180), math.rad(-90)),
    [10] = CFrame.new(-distSide, 1.4, 0) * CFrame.Angles(0, math.rad(0), math.rad(-90)),
    [11] = CFrame.new(0, 2.8, 0) * CFrame.Angles(0, 0, math.rad(180)),
    [12] = CFrame.new(0, 0, distFrontBack) * CFrame.Angles(0, math.rad(90), math.rad(-90)),
    [13] = CFrame.new(0, 0, -distFrontBack) * CFrame.Angles(0, math.rad(-90), math.rad(-90)),
    [14] = CFrame.new(distSide, 0, 0) * CFrame.Angles(0, math.rad(180), math.rad(-90)),
    [15] = CFrame.new(-distSide, 0, 0) * CFrame.Angles(0, math.rad(0), math.rad(-90)),
}

local function safeInvokeSetCF(remoteObj, cf)
    if not remoteObj or not remoteObj.Parent then return end
    task.spawn(function()
        pcall(function()
            if remoteObj:IsA("RemoteFunction") then
                remoteObj:InvokeServer(cf)
            elseif remoteObj:IsA("RemoteEvent") then
                remoteObj:FireServer(cf)
            end
        end)
    end)
end

local function getMyPropsList()
    local found = {}
    local wc = workspace:FindFirstChild("WorkspaceCom")
    local folder = wc and wc:FindFirstChild("001_TrafficCones")
    if folder then
        for _, c in ipairs(folder:GetChildren()) do
            if c.Name == ("Prop" .. lp.Name) and c:FindFirstChild("SetCurrentCFrame") then
                table.insert(found, c)
            end
        end
    end
    for _, d in ipairs(workspace:GetChildren()) do
        if d:IsA("Model") and d.Name == ("Prop" .. lp.Name) and d:FindFirstChild("SetCurrentCFrame") and not table.find(found, d) then
            table.insert(found, d)
        end
    end
    return found
end

local performVoidDrop

local seatConns = {}
local function hookSeatEvents()
    for _, c in ipairs(seatConns) do
        pcall(function() c:Disconnect() end)
    end
    seatConns = {}

    for _, item in ipairs(trackedProps) do
        if item.model and item.model.Parent then
            local seat = item.model:FindFirstChildWhichIsA("Seat", true)
            if seat then
                local conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
                    if isAutoVoidOnSit and not isVoidingTrap and not isAbducting then
                        local occ = seat.Occupant
                        if occ and occ.Parent and occ.Parent ~= lp.Character then
                            local victimChar = occ.Parent
                            local victimP = Players:GetPlayerFromCharacter(victimChar)
                            local victimName = victimP and victimP.DisplayName or victimChar.Name
                            task.spawn(function()
                                if type(performVoidDrop) == "function" then
                                    performVoidDrop(victimName, victimChar, victimP)
                                end
                            end)
                        end
                    end
                end)
                table.insert(seatConns, trackConn(conn))
            end
        end
    end
end

local function applyFoldedOffsets()
    for i, item in ipairs(trackedProps) do
        local stackY = (i - 1) * 0.035
        item.relCF = CFrame.new(0, stackY, 0)
    end
end

local function bindAllProps(useSymmetricCage)
    local found = getMyPropsList()
    if #found == 0 then
        trackedProps = {}
        return 0
    end

    table.sort(found, function(a, b)
        local okA, cfA = pcall(function() return a:GetPivot() end)
        local okB, cfB = pcall(function() return b:GetPivot() end)
        return (okA and cfA.Y or 0) < (okB and cfB.Y or 0)
    end)
    trackedProps = {}

    local activeSym = (#found >= 15) and symRel15 or ((#found == 11) and symRel11 or nil)

    if useSymmetricCage and activeSym then
        local limit = math.min(#found, #activeSym)
        for i = 1, limit do
            table.insert(trackedProps, {
                model = found[i],
                setCF = found[i]:FindFirstChild("SetCurrentCFrame"),
                relCF = activeSym[i]
            })
        end
    else
        local centerPos = Vector3.zero
        for _, p in ipairs(found) do
            local ok, pv = pcall(function() return p:GetPivot() end)
            if ok and pv then
                centerPos = centerPos + pv.Position
            end
        end
        centerPos = centerPos / #found
        local rootCF = CFrame.new(centerPos)

        for _, p in ipairs(found) do
            local ok, pv = pcall(function() return p:GetPivot() end)
            table.insert(trackedProps, {
                model = p,
                setCF = p:FindFirstChild("SetCurrentCFrame"),
                relCF = (ok and pv) and rootCF:ToObjectSpace(pv) or CFrame.new()
            })
        end
    end

    if isFoldedMode then
        applyFoldedOffsets()
    end

    if #trackedProps > 0 then
        local p = trackedProps[10] and trackedProps[10].model or (trackedProps[6] and trackedProps[6].model or trackedProps[1].model)
        if p and p.Parent then
            local ok, pv = pcall(function() return p:GetPivot() end)
            if ok and pv then
                clusterCFrame = pv
                clusterPos = pv.Position
                local _, y, _ = pv:ToEulerAnglesYXZ()
                clusterYaw = y
            end
        end
    end

    pcall(hookSeatEvents)
    return #trackedProps
end

local function getItemRelCF(item, index)
    return (item and item.relCF) or CFrame.new()
end

local function updateClusterVisuals(targetRootCF)
    for i, item in ipairs(trackedProps) do
        if item.model and item.model.Parent then
            pcall(function()
                item.model:PivotTo(targetRootCF * getItemRelCF(item, i))
            end)
        end
    end
end

local function syncClusterToNetwork(targetRootCF)
    for i, item in ipairs(trackedProps) do
        if item.setCF and item.setCF.Parent then
            safeInvokeSetCF(item.setCF, targetRootCF * getItemRelCF(item, i))
        end
    end
end

local function moveClusterTo(targetRootCF)
    clusterCFrame = targetRootCF
    clusterPos = targetRootCF.Position
    local _, y, _ = targetRootCF:ToEulerAnglesYXZ()
    clusterYaw = y
    updateClusterVisuals(targetRootCF)
    syncClusterToNetwork(targetRootCF)
end

pcall(function() bindAllProps(true) end)

-- [[ UI Construction (Mobile Responsive & Scaled) ]]
local baseWidth = 315
local baseHeight = 350
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Size = UDim2.new(0, baseWidth, 0, baseHeight)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Active = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", mainFrame)
stroke.Color = Color3.fromRGB(60, 70, 95)
stroke.Thickness = 1.5

local mainScale = Instance.new("UIScale", mainFrame)
local currentScaleIdx = 1
local scaleOptions = {1.0, 0.85, 0.70, 0.55}

local function autoDetectMobileScale()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local isTouch = UserInputService.TouchEnabled
    local isMobile = isTouch or vp.Y < 540 or vp.X < 900
    if isMobile then
        if vp.Y < 380 or vp.X < 680 then
            mainScale.Scale = 0.65
            currentScaleIdx = 4
        elseif vp.Y < 480 or vp.X < 850 then
            mainScale.Scale = 0.75
            currentScaleIdx = 3
        else
            mainScale.Scale = 0.85
            currentScaleIdx = 2
        end
    else
        mainScale.Scale = 1.0
        currentScaleIdx = 1
    end
end
autoDetectMobileScale()
if workspace.CurrentCamera then
    trackConn(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(autoDetectMobileScale))
end

-- [[ Title Bar ]]
local titleBar = Instance.new("Frame", mainFrame)
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

local titleText = Instance.new("TextLabel", titleBar)
titleText.Size = UDim2.new(1, -95, 1, 0)
titleText.Position = UDim2.new(0, 10, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "📦 Prop Master (15)"
titleText.TextColor3 = Color3.fromRGB(240, 245, 255)
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 11
titleText.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -28, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(215, 55, 65)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 11
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0, 24, 0, 24)
minBtn.Position = UDim2.new(1, -54, 0, 6)
minBtn.BackgroundColor3 = Color3.fromRGB(48, 52, 70)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 11
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 5)

local scaleBtn = Instance.new("TextButton", titleBar)
scaleBtn.Size = UDim2.new(0, 24, 0, 24)
scaleBtn.Position = UDim2.new(1, -80, 0, 6)
scaleBtn.BackgroundColor3 = Color3.fromRGB(48, 52, 70)
scaleBtn.Text = "🔍"
scaleBtn.TextColor3 = Color3.new(1, 1, 1)
scaleBtn.Font = Enum.Font.GothamBold
scaleBtn.TextSize = 11
Instance.new("UICorner", scaleBtn).CornerRadius = UDim.new(0, 5)

scaleBtn.MouseButton1Click:Connect(function()
    currentScaleIdx = (currentScaleIdx % #scaleOptions) + 1
    mainScale.Scale = scaleOptions[currentScaleIdx]
    titleText.Text = string.format("📦 Prop Master (%d%%)", math.floor(scaleOptions[currentScaleIdx] * 100))
    task.delay(1.5, function()
        titleText.Text = "📦 Prop Master (15)"
    end)
end)

-- [[ Mini Floating Toggle Widget ]]
local miniToggle = Instance.new("Frame", screenGui)
miniToggle.Name = "MiniToggleWidget"
miniToggle.Size = UDim2.new(0, 96, 0, 32)
miniToggle.Position = UDim2.new(0, 16, 0, 16)
miniToggle.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
miniToggle.BackgroundTransparency = 0.1
miniToggle.BorderSizePixel = 0
miniToggle.Active = true
miniToggle.ZIndex = 50
Instance.new("UICorner", miniToggle).CornerRadius = UDim.new(0, 16)
local mtStroke = Instance.new("UIStroke", miniToggle)
mtStroke.Color = Color3.fromRGB(220, 80, 100)
mtStroke.Thickness = 1.4

local miniBtn = Instance.new("TextButton", miniToggle)
miniBtn.Size = UDim2.new(1, 0, 1, 0)
miniBtn.BackgroundTransparency = 1
miniBtn.Text = "📦 ปิดเมนู"
miniBtn.TextColor3 = Color3.fromRGB(235, 240, 255)
miniBtn.Font = Enum.Font.GothamBold
miniBtn.TextSize = 11
miniBtn.ZIndex = 51

local mDragging = false
local mDragStart = nil
local mStartPos = nil

miniBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        mDragging = false
        mDragStart = input.Position
        mStartPos = miniToggle.Position
    end
end)

trackConn(UserInputService.InputChanged:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) and mDragStart then
        local delta = input.Position - mDragStart
        if delta.Magnitude > 5 then
            mDragging = true
            miniToggle.Position = UDim2.new(
                mStartPos.X.Scale, mStartPos.X.Offset + delta.X,
                mStartPos.Y.Scale, mStartPos.Y.Offset + delta.Y
            )
        end
    end
end))

miniBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if not mDragging and mDragStart then
            mainFrame.Visible = not mainFrame.Visible
            if mainFrame.Visible then
                miniBtn.Text = "📦 ปิดเมนู"
                mtStroke.Color = Color3.fromRGB(220, 80, 100)
            else
                miniBtn.Text = "📦 เมนูกรง"
                mtStroke.Color = Color3.fromRGB(65, 120, 225)
            end
        end
        mDragStart = nil
        mDragging = false
    end
end)

-- Window Dragging
local dragging = false
local dragStart = nil
local startPos = nil

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
        stroke.Color = Color3.fromRGB(110, 170, 255)
    end
end)

trackConn(UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        if dragStart and startPos then
            local delta = input.Position - dragStart
            local scale = (mainScale and mainScale.Scale) or 1.0
            if scale <= 0 then scale = 1.0 end
            mainFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + (delta.X / scale),
                startPos.Y.Scale,
                startPos.Y.Offset + (delta.Y / scale)
            )
        end
    end
end))

trackConn(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if dragging then
            dragging = false
            dragStart = nil
            startPos = nil
            stroke.Color = Color3.fromRGB(60, 70, 95)
        end
    end
end))

local content = Instance.new("Frame", mainFrame)
content.Name = "Content"
content.Size = UDim2.new(1, -12, 1, -42)
content.Position = UDim2.new(0, 6, 0, 38)
content.BackgroundTransparency = 1

-- [[ Status & Build Row ]]
local statusCard = Instance.new("Frame", content)
statusCard.Size = UDim2.new(1, 0, 0, 26)
statusCard.BackgroundColor3 = Color3.fromRGB(26, 29, 40)
Instance.new("UICorner", statusCard).CornerRadius = UDim.new(0, 7)

local statusLabel = Instance.new("TextLabel", statusCard)
statusLabel.Size = UDim2.new(1, -70, 1, 0)
statusLabel.Position = UDim2.new(0, 8, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "🔗 เชื่อมต่อ Prop: " .. #trackedProps .. " ชิ้น (ทั้งก้อน)"
statusLabel.TextColor3 = Color3.fromRGB(120, 230, 160)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 10
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local rescanBtn = Instance.new("TextButton", statusCard)
rescanBtn.Size = UDim2.new(0, 62, 0, 20)
rescanBtn.Position = UDim2.new(1, -66, 0, 3)
rescanBtn.BackgroundColor3 = Color3.fromRGB(42, 50, 70)
rescanBtn.Text = "🔄 สแกนใหม่"
rescanBtn.TextColor3 = Color3.new(1, 1, 1)
rescanBtn.Font = Enum.Font.GothamBold
rescanBtn.TextSize = 9
Instance.new("UICorner", rescanBtn).CornerRadius = UDim.new(0, 5)

-- Top Action Row
local quickActionRow = Instance.new("Frame", content)
quickActionRow.Size = UDim2.new(1, 0, 0, 28)
quickActionRow.Position = UDim2.new(0, 0, 0, 29)
quickActionRow.BackgroundTransparency = 1

local buildBtn = Instance.new("TextButton", quickActionRow)
buildBtn.Size = UDim2.new(0.32, -2, 1, 0)
buildBtn.BackgroundColor3 = Color3.fromRGB(125, 55, 215)
buildBtn.Text = "🔨 สร้าง 15 ชิ้น"
buildBtn.TextColor3 = Color3.new(1, 1, 1)
buildBtn.Font = Enum.Font.GothamBold
buildBtn.TextSize = 10
Instance.new("UICorner", buildBtn).CornerRadius = UDim.new(0, 6)

local foldBtn = Instance.new("TextButton", quickActionRow)
foldBtn.Size = UDim2.new(0.23, -2, 1, 0)
foldBtn.Position = UDim2.new(0.32, 2, 0, 0)
foldBtn.BackgroundColor3 = Color3.fromRGB(45, 110, 210)
foldBtn.Text = "📥 พับเก็บ"
foldBtn.TextColor3 = Color3.new(1, 1, 1)
foldBtn.Font = Enum.Font.GothamBold
foldBtn.TextSize = 10
Instance.new("UICorner", foldBtn).CornerRadius = UDim.new(0, 6)

local clearBtn = Instance.new("TextButton", quickActionRow)
clearBtn.Size = UDim2.new(0.22, -2, 1, 0)
clearBtn.Position = UDim2.new(0.55, 2, 0, 0)
clearBtn.BackgroundColor3 = Color3.fromRGB(180, 45, 55)
clearBtn.Text = "🗑️ ล้างของ"
clearBtn.TextColor3 = Color3.new(1, 1, 1)
clearBtn.Font = Enum.Font.GothamBold
clearBtn.TextSize = 10
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 6)

local escapeBtn = Instance.new("TextButton", quickActionRow)
escapeBtn.Size = UDim2.new(0.23, -2, 1, 0)
escapeBtn.Position = UDim2.new(0.77, 2, 0, 0)
escapeBtn.BackgroundColor3 = Color3.fromRGB(205, 90, 30)
escapeBtn.Text = "🔓 ออกกรง"
escapeBtn.TextColor3 = Color3.new(1, 1, 1)
escapeBtn.Font = Enum.Font.GothamBold
escapeBtn.TextSize = 10
Instance.new("UICorner", escapeBtn).CornerRadius = UDim.new(0, 6)

-- [[ Tab Bar (4 Tabs: ขับกรง, ดึงคน, ขอบโลก, ตามคน) ]]
local tabBar = Instance.new("Frame", content)
tabBar.Size = UDim2.new(1, 0, 0, 28)
tabBar.Position = UDim2.new(0, 0, 0, 60)
tabBar.BackgroundColor3 = Color3.fromRGB(24, 26, 36)
Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0, 7)

local tabFreeBtn = Instance.new("TextButton", tabBar)
tabFreeBtn.Size = UDim2.new(0.25, -2, 1, 0)
tabFreeBtn.BackgroundColor3 = Color3.fromRGB(50, 70, 115)
tabFreeBtn.Text = "🕹️ ขับกรง"
tabFreeBtn.TextColor3 = Color3.new(1, 1, 1)
tabFreeBtn.Font = Enum.Font.GothamBold
tabFreeBtn.TextSize = 10
Instance.new("UICorner", tabFreeBtn).CornerRadius = UDim.new(0, 6)

local tabAbductBtn = Instance.new("TextButton", tabBar)
tabAbductBtn.Size = UDim2.new(0.25, -2, 1, 0)
tabAbductBtn.Position = UDim2.new(0.25, 1, 0, 0)
tabAbductBtn.BackgroundColor3 = Color3.fromRGB(30, 33, 46)
tabAbductBtn.Text = "🧲 ดึงคน"
tabAbductBtn.TextColor3 = Color3.fromRGB(180, 185, 205)
tabAbductBtn.Font = Enum.Font.GothamBold
tabAbductBtn.TextSize = 10
Instance.new("UICorner", tabAbductBtn).CornerRadius = UDim.new(0, 6)

local tabTrollBtn = Instance.new("TextButton", tabBar)
tabTrollBtn.Size = UDim2.new(0.25, -2, 1, 0)
tabTrollBtn.Position = UDim2.new(0.50, 1, 0, 0)
tabTrollBtn.BackgroundColor3 = Color3.fromRGB(30, 33, 46)
tabTrollBtn.Text = "🕳️ ขอบโลก"
tabTrollBtn.TextColor3 = Color3.fromRGB(180, 185, 205)
tabTrollBtn.Font = Enum.Font.GothamBold
tabTrollBtn.TextSize = 10
Instance.new("UICorner", tabTrollBtn).CornerRadius = UDim.new(0, 6)

local tabFollowBtn = Instance.new("TextButton", tabBar)
tabFollowBtn.Size = UDim2.new(0.25, -2, 1, 0)
tabFollowBtn.Position = UDim2.new(0.75, 1, 0, 0)
tabFollowBtn.BackgroundColor3 = Color3.fromRGB(30, 33, 46)
tabFollowBtn.Text = "👤 ตามคน"
tabFollowBtn.TextColor3 = Color3.fromRGB(180, 185, 205)
tabFollowBtn.Font = Enum.Font.GothamBold
tabFollowBtn.TextSize = 10
Instance.new("UICorner", tabFollowBtn).CornerRadius = UDim.new(0, 6)

-- [[ Tab Containers ]]
local tabFreeContainer = Instance.new("ScrollingFrame", content)
tabFreeContainer.Name = "FreeContainer"
tabFreeContainer.Size = UDim2.new(1, 0, 1, -92)
tabFreeContainer.Position = UDim2.new(0, 0, 0, 92)
tabFreeContainer.BackgroundTransparency = 1
tabFreeContainer.BorderSizePixel = 0
tabFreeContainer.ScrollBarThickness = 3
tabFreeContainer.ScrollBarImageColor3 = Color3.fromRGB(80, 100, 140)
tabFreeContainer.CanvasSize = UDim2.new(0, 0, 0, 425)
tabFreeContainer.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
tabFreeContainer.Visible = true

local tabAbductContainer = Instance.new("ScrollingFrame", content)
tabAbductContainer.Name = "AbductContainer"
tabAbductContainer.Size = UDim2.new(1, 0, 1, -92)
tabAbductContainer.Position = UDim2.new(0, 0, 0, 92)
tabAbductContainer.BackgroundTransparency = 1
tabAbductContainer.BorderSizePixel = 0
tabAbductContainer.ScrollBarThickness = 3
tabAbductContainer.ScrollBarImageColor3 = Color3.fromRGB(80, 100, 140)
tabAbductContainer.CanvasSize = UDim2.new(0, 0, 0, 200)
tabAbductContainer.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
tabAbductContainer.Visible = false

local tabTrollContainer = Instance.new("ScrollingFrame", content)
tabTrollContainer.Name = "TrollContainer"
tabTrollContainer.Size = UDim2.new(1, 0, 1, -92)
tabTrollContainer.Position = UDim2.new(0, 0, 0, 92)
tabTrollContainer.BackgroundTransparency = 1
tabTrollContainer.BorderSizePixel = 0
tabTrollContainer.ScrollBarThickness = 3
tabTrollContainer.ScrollBarImageColor3 = Color3.fromRGB(80, 100, 140)
tabTrollContainer.CanvasSize = UDim2.new(0, 0, 0, 230)
tabTrollContainer.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
tabTrollContainer.Visible = false
local tcLayout = Instance.new("UIListLayout", tabTrollContainer)
tcLayout.Padding = UDim.new(0, 6)

local tabFollowContainer = Instance.new("Frame", content)
tabFollowContainer.Name = "FollowContainer"
tabFollowContainer.Size = UDim2.new(1, 0, 1, -92)
tabFollowContainer.Position = UDim2.new(0, 0, 0, 92)
tabFollowContainer.BackgroundTransparency = 1
tabFollowContainer.Visible = false

local function switchTab(active)
    tabFreeContainer.Visible = (active == "free")
    tabAbductContainer.Visible = (active == "abduct")
    tabTrollContainer.Visible = (active == "troll")
    tabFollowContainer.Visible = (active == "follow")

    tabFreeBtn.BackgroundColor3 = (active == "free") and Color3.fromRGB(50, 70, 115) or Color3.fromRGB(30, 33, 46)
    tabFreeBtn.TextColor3 = (active == "free") and Color3.new(1, 1, 1) or Color3.fromRGB(180, 185, 205)

    tabAbductBtn.BackgroundColor3 = (active == "abduct") and Color3.fromRGB(50, 70, 115) or Color3.fromRGB(30, 33, 46)
    tabAbductBtn.TextColor3 = (active == "abduct") and Color3.new(1, 1, 1) or Color3.fromRGB(180, 185, 205)

    tabTrollBtn.BackgroundColor3 = (active == "troll") and Color3.fromRGB(130, 35, 75) or Color3.fromRGB(30, 33, 46)
    tabTrollBtn.TextColor3 = (active == "troll") and Color3.new(1, 1, 1) or Color3.fromRGB(180, 185, 205)

    tabFollowBtn.BackgroundColor3 = (active == "follow") and Color3.fromRGB(50, 70, 115) or Color3.fromRGB(30, 33, 46)
    tabFollowBtn.TextColor3 = (active == "follow") and Color3.new(1, 1, 1) or Color3.fromRGB(180, 185, 205)
end

tabFreeBtn.MouseButton1Click:Connect(function() switchTab("free") end)
tabAbductBtn.MouseButton1Click:Connect(function() switchTab("abduct") end)
tabTrollBtn.MouseButton1Click:Connect(function() switchTab("troll") end)
tabFollowBtn.MouseButton1Click:Connect(function() switchTab("follow") end)

-- ========================================================
-- [[ ESCAPE CAGE (UNSTUCK) IMPLEMENTATION ]]
-- ========================================================
local function escapeFromOwnCage()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local look = hrp.CFrame.LookVector
    local safePos = clusterPos + look * 7.0 + Vector3.new(0, 1, 0)
    hrp.CFrame = CFrame.new(safePos, safePos + look)

    escapeBtn.Text = "✔ หลุดแล้ว!"
    task.delay(1.5, function() escapeBtn.Text = "🔓 ออกกรง" end)
end

escapeBtn.MouseButton1Click:Connect(escapeFromOwnCage)

-- ========================================================
-- [[ DRIVE PROP MODE HUD OVERLAY ]]
-- ========================================================
local driveHud = Instance.new("Frame", screenGui)
driveHud.Name = "DriveHud"
driveHud.Size = UDim2.new(0, 380, 0, 72)
driveHud.Position = UDim2.new(0.5, -190, 0, 14)
driveHud.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
driveHud.BorderSizePixel = 0
driveHud.Visible = false
Instance.new("UICorner", driveHud).CornerRadius = UDim.new(0, 10)
local dhStroke = Instance.new("UIStroke", driveHud)
dhStroke.Color = Color3.fromRGB(50, 130, 230)
dhStroke.Thickness = 1.5

local dhTitle = Instance.new("TextLabel", driveHud)
dhTitle.Size = UDim2.new(1, -90, 0, 22)
dhTitle.Position = UDim2.new(0, 10, 0, 5)
dhTitle.BackgroundTransparency = 1
dhTitle.Text = "🎮 ขับกรง: เดิน(WASD/จอย) | กระโดด(ปุ่ม Roblox/Space)"
dhTitle.TextColor3 = Color3.fromRGB(140, 225, 255)
dhTitle.Font = Enum.Font.GothamBold
dhTitle.TextSize = 11
dhTitle.TextXAlignment = Enum.TextXAlignment.Left

local exitDriveBtn = Instance.new("TextButton", driveHud)
exitDriveBtn.Size = UDim2.new(0, 80, 0, 24)
exitDriveBtn.Position = UDim2.new(1, -86, 0, 5)
exitDriveBtn.BackgroundColor3 = Color3.fromRGB(215, 55, 65)
exitDriveBtn.Text = "🚪 ออกจากโหมด"
exitDriveBtn.TextColor3 = Color3.new(1, 1, 1)
exitDriveBtn.Font = Enum.Font.GothamBold
exitDriveBtn.TextSize = 10
Instance.new("UICorner", exitDriveBtn).CornerRadius = UDim.new(0, 6)

local dhControlsRow = Instance.new("Frame", driveHud)
dhControlsRow.Size = UDim2.new(1, -20, 0, 26)
dhControlsRow.Position = UDim2.new(0, 10, 0, 32)
dhControlsRow.BackgroundTransparency = 1

local flyToggleBtn = Instance.new("TextButton", dhControlsRow)
flyToggleBtn.Size = UDim2.new(0, 105, 1, 0)
flyToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 48, 68)
flyToggleBtn.Text = "🚶 โหมด: เดินพื้น"
flyToggleBtn.TextColor3 = Color3.fromRGB(150, 230, 170)
flyToggleBtn.Font = Enum.Font.GothamBold
flyToggleBtn.TextSize = 10
Instance.new("UICorner", flyToggleBtn).CornerRadius = UDim.new(0, 5)

local sp16 = Instance.new("TextButton", dhControlsRow)
sp16.Size = UDim2.new(0, 50, 1, 0); sp16.Position = UDim2.new(0, 115, 0, 0)
sp16.BackgroundColor3 = Color3.fromRGB(45, 95, 175); sp16.Text = "16 ปกติ"
sp16.TextColor3 = Color3.new(1, 1, 1); sp16.Font = Enum.Font.GothamBold; sp16.TextSize = 10
Instance.new("UICorner", sp16).CornerRadius = UDim.new(0, 5)

local sp28 = Instance.new("TextButton", dhControlsRow)
sp28.Size = UDim2.new(0, 50, 1, 0); sp28.Position = UDim2.new(0, 170, 0, 0)
sp28.BackgroundColor3 = Color3.fromRGB(36, 42, 58); sp28.Text = "28 วิ่ง"
sp28.TextColor3 = Color3.fromRGB(180, 185, 200); sp28.Font = Enum.Font.GothamBold; sp28.TextSize = 10
Instance.new("UICorner", sp28).CornerRadius = UDim.new(0, 5)

local sp45 = Instance.new("TextButton", dhControlsRow)
sp45.Size = UDim2.new(0, 55, 1, 0); sp45.Position = UDim2.new(0, 225, 0, 0)
sp45.BackgroundColor3 = Color3.fromRGB(36, 42, 58); sp45.Text = "45 เทอร์โบ"
sp45.TextColor3 = Color3.fromRGB(180, 185, 200); sp45.Font = Enum.Font.GothamBold; sp45.TextSize = 10
Instance.new("UICorner", sp45).CornerRadius = UDim.new(0, 5)

local hudEscapeBtn = Instance.new("TextButton", dhControlsRow)
hudEscapeBtn.Size = UDim2.new(0, 70, 1, 0); hudEscapeBtn.Position = UDim2.new(1, -70, 0, 0)
hudEscapeBtn.BackgroundColor3 = Color3.fromRGB(190, 80, 25); hudEscapeBtn.Text = "🔓 หลุดกรง"
hudEscapeBtn.TextColor3 = Color3.new(1, 1, 1); hudEscapeBtn.Font = Enum.Font.GothamBold; hudEscapeBtn.TextSize = 10
Instance.new("UICorner", hudEscapeBtn).CornerRadius = UDim.new(0, 5)
hudEscapeBtn.MouseButton1Click:Connect(escapeFromOwnCage)

local function updateDriveSpeed(val)
    driveSpeed = val
    sp16.BackgroundColor3 = (val == 16) and Color3.fromRGB(45, 95, 175) or Color3.fromRGB(36, 42, 58)
    sp28.BackgroundColor3 = (val == 28) and Color3.fromRGB(45, 95, 175) or Color3.fromRGB(36, 42, 58)
    sp45.BackgroundColor3 = (val == 45) and Color3.fromRGB(45, 95, 175) or Color3.fromRGB(36, 42, 58)
end
sp16.MouseButton1Click:Connect(function() updateDriveSpeed(16) end)
sp28.MouseButton1Click:Connect(function() updateDriveSpeed(28) end)
sp45.MouseButton1Click:Connect(function() updateDriveSpeed(45) end)

flyToggleBtn.MouseButton1Click:Connect(function()
    isFlying = not isFlying
    if isFlying then
        flyToggleBtn.Text = "🕊️ โหมด: บินอิสระ"
        flyToggleBtn.TextColor3 = Color3.fromRGB(255, 215, 100)
    else
        flyToggleBtn.Text = "🚶 โหมด: เดินพื้น"
        flyToggleBtn.TextColor3 = Color3.fromRGB(150, 230, 170)
        vertVel = 0
    end
end)

-- ========================================================
-- [[ TAB 1: FREE MOVEMENT, DRIVE, BALL, COLOR & EXPLODE ]]
-- ========================================================
local driveEnterBtn = Instance.new("TextButton", tabFreeContainer)
driveEnterBtn.Size = UDim2.new(1, 0, 0, 36)
driveEnterBtn.Position = UDim2.new(0, 0, 0, 0)
driveEnterBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 210)
driveEnterBtn.Text = "🎮 สวมวิญญาณขับกรง (WASD / จอยมือถือ / โดด)"
driveEnterBtn.TextColor3 = Color3.new(1, 1, 1)
driveEnterBtn.Font = Enum.Font.GothamBold
driveEnterBtn.TextSize = 12
Instance.new("UICorner", driveEnterBtn).CornerRadius = UDim.new(0, 7)
local deStroke = Instance.new("UIStroke", driveEnterBtn)
deStroke.Color = Color3.fromRGB(110, 190, 255)
deStroke.Thickness = 1.2

local quickTpRow = Instance.new("Frame", tabFreeContainer)
quickTpRow.Size = UDim2.new(1, 0, 0, 26)
quickTpRow.Position = UDim2.new(0, 0, 0, 42)
quickTpRow.BackgroundTransparency = 1

local bringMeBtn = Instance.new("TextButton", quickTpRow)
bringMeBtn.Size = UDim2.new(0.5, -3, 1, 0)
bringMeBtn.BackgroundColor3 = Color3.fromRGB(35, 120, 90)
bringMeBtn.Text = "🚀 ดึงมาหน้าฉัน"
bringMeBtn.TextColor3 = Color3.new(1, 1, 1)
bringMeBtn.Font = Enum.Font.GothamBold
bringMeBtn.TextSize = 11
Instance.new("UICorner", bringMeBtn).CornerRadius = UDim.new(0, 6)

local sendTargetBtn = Instance.new("TextButton", quickTpRow)
sendTargetBtn.Size = UDim2.new(0.5, -3, 1, 0)
sendTargetBtn.Position = UDim2.new(0.5, 3, 0, 0)
sendTargetBtn.BackgroundColor3 = Color3.fromRGB(130, 85, 30)
sendTargetBtn.Text = "📍 ส่งไปหาเป้าหมาย"
sendTargetBtn.TextColor3 = Color3.new(1, 1, 1)
sendTargetBtn.Font = Enum.Font.GothamBold
sendTargetBtn.TextSize = 11
Instance.new("UICorner", sendTargetBtn).CornerRadius = UDim.new(0, 6)

local setBallMode
local stopPropExplode

bringMeBtn.MouseButton1Click:Connect(function()
    if type(stopPropExplode) == "function" then stopPropExplode() end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local pos = hrp.Position + hrp.CFrame.LookVector * 6 + Vector3.new(0, heightOffset, 0)
        clusterPos = pos
        clusterCFrame = CFrame.new(pos)
        if not isBallMode then
            moveClusterTo(clusterCFrame)
        end
    end
end)

sendTargetBtn.MouseButton1Click:Connect(function()
    if type(stopPropExplode) == "function" then stopPropExplode() end
    local target = targetPlayer or lp
    local hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local pos = hrp.Position + Vector3.new(0, heightOffset, 0)
        clusterPos = pos
        clusterCFrame = CFrame.new(pos)
        if not isBallMode then
            moveClusterTo(clusterCFrame)
        end
    end
end)

local dragRow = Instance.new("Frame", tabFreeContainer)
dragRow.Size = UDim2.new(1, 0, 0, 26)
dragRow.Position = UDim2.new(0, 0, 0, 72)
dragRow.BackgroundTransparency = 1

local dragToggleBtn = Instance.new("TextButton", dragRow)
dragToggleBtn.Size = UDim2.new(0.65, -3, 1, 0)
dragToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
dragToggleBtn.Text = "🖐️ ลากด้วยเมาส์/นิ้ว: ปิด"
dragToggleBtn.TextColor3 = Color3.fromRGB(220, 225, 240)
dragToggleBtn.Font = Enum.Font.GothamBold
dragToggleBtn.TextSize = 11
Instance.new("UICorner", dragToggleBtn).CornerRadius = UDim.new(0, 6)

local tapPlaceBtn = Instance.new("TextButton", dragRow)
tapPlaceBtn.Size = UDim2.new(0.35, -3, 1, 0)
tapPlaceBtn.Position = UDim2.new(0.65, 3, 0, 0)
tapPlaceBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 70)
tapPlaceBtn.Text = "🎯 แตะพื้นวาง"
tapPlaceBtn.TextColor3 = Color3.new(1, 1, 1)
tapPlaceBtn.Font = Enum.Font.GothamBold
tapPlaceBtn.TextSize = 10
Instance.new("UICorner", tapPlaceBtn).CornerRadius = UDim.new(0, 6)

local dragBanner = Instance.new("Frame", screenGui)
dragBanner.Name = "DragBanner"
dragBanner.Size = UDim2.new(0, 360, 0, 36)
dragBanner.Position = UDim2.new(0.5, -180, 0, 10)
dragBanner.BackgroundColor3 = Color3.fromRGB(20, 85, 175)
dragBanner.BorderSizePixel = 0
dragBanner.Visible = false
Instance.new("UICorner", dragBanner).CornerRadius = UDim.new(0, 10)

local bannerLabel = Instance.new("TextLabel", dragBanner)
bannerLabel.Size = UDim2.new(1, -70, 1, 0)
bannerLabel.Position = UDim2.new(0, 12, 0, 0)
bannerLabel.BackgroundTransparency = 1
bannerLabel.Text = "🖐️ โหมดลากอิสระ: แตะ/ลากบนจอเพื่อย้ายกรง"
bannerLabel.TextColor3 = Color3.new(1, 1, 1)
bannerLabel.Font = Enum.Font.GothamBold
bannerLabel.TextSize = 11
bannerLabel.TextXAlignment = Enum.TextXAlignment.Left

local bannerClose = Instance.new("TextButton", dragBanner)
bannerClose.Size = UDim2.new(0, 52, 0, 24)
bannerClose.Position = UDim2.new(1, -60, 0, 6)
bannerClose.BackgroundColor3 = Color3.fromRGB(215, 55, 65)
bannerClose.Text = "ปิดโหมด"
bannerClose.TextColor3 = Color3.new(1, 1, 1)
bannerClose.Font = Enum.Font.GothamBold
bannerClose.TextSize = 10
Instance.new("UICorner", bannerClose).CornerRadius = UDim.new(0, 5)

local isDraggingNow = false

local function setDragMode(enable)
    isDragMode = enable
    isDraggingNow = false
    if isDragMode then
        isTapToPlace = false
        dragToggleBtn.BackgroundColor3 = Color3.fromRGB(25, 130, 220)
        dragToggleBtn.Text = "🖐️ ลากด้วยเมาส์/นิ้ว: เปิด"
        dragBanner.Visible = true
    else
        dragToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
        dragToggleBtn.Text = "🖐️ ลากด้วยเมาส์/นิ้ว: ปิด"
        dragBanner.Visible = false
        if not isBallMode and not isExploding then
            syncClusterToNetwork(clusterCFrame)
        end
    end
end

trackConn(dragToggleBtn.MouseButton1Click:Connect(function() setDragMode(not isDragMode) end))
trackConn(bannerClose.MouseButton1Click:Connect(function() setDragMode(false) end))

trackConn(tapPlaceBtn.MouseButton1Click:Connect(function()
    isTapToPlace = not isTapToPlace
    if isTapToPlace then
        setDragMode(false)
        tapPlaceBtn.BackgroundColor3 = Color3.fromRGB(220, 140, 30)
        tapPlaceBtn.Text = "📍 แตะบนจอเลย!"
    else
        tapPlaceBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 70)
        tapPlaceBtn.Text = "🎯 แตะพื้นวาง"
    end
end))

-- [[ D-Pad Directional Controller Box ]]
local dpadFrame = Instance.new("Frame", tabFreeContainer)
dpadFrame.Size = UDim2.new(1, 0, 0, 150)
dpadFrame.Position = UDim2.new(0, 0, 0, 102)
dpadFrame.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
Instance.new("UICorner", dpadFrame).CornerRadius = UDim.new(0, 8)
local dpStroke = Instance.new("UIStroke", dpadFrame)
dpStroke.Color = Color3.fromRGB(45, 52, 70)
dpStroke.Thickness = 1

local dpadTitle = Instance.new("TextLabel", dpadFrame)
dpadTitle.Size = UDim2.new(1, 0, 0, 18)
dpadTitle.BackgroundTransparency = 1
dpadTitle.Text = "🎮 ปุ่มควบคุม 6 ทิศทาง (กดแตะ / กดค้าง)"
dpadTitle.TextColor3 = Color3.fromRGB(150, 160, 185)
dpadTitle.Font = Enum.Font.GothamMedium
dpadTitle.TextSize = 10

local function createDpadBtn(text, posX, posY, sizeX, sizeY, bgCol)
    local btn = Instance.new("TextButton", dpadFrame)
    btn.Size = UDim2.new(0, sizeX, 0, sizeY)
    btn.Position = UDim2.new(0, posX, 0, posY)
    btn.BackgroundColor3 = bgCol or Color3.fromRGB(40, 46, 62)
    btn.Text = text
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local upBtn = createDpadBtn("⏫ ขึ้น", 16, 26, 74, 46, Color3.fromRGB(38, 70, 110))
local downBtn = createDpadBtn("⏬ ลง", 16, 84, 74, 46, Color3.fromRGB(38, 70, 110))
local fwdBtn = createDpadBtn("⬆️ หน้า", 120, 20, 64, 38, Color3.fromRGB(45, 85, 140))
local leftBtn = createDpadBtn("⬅️ ซ้าย", 96, 62, 52, 38, Color3.fromRGB(45, 85, 140))
local rightBtn = createDpadBtn("ขวา ➡️", 152, 62, 52, 38, Color3.fromRGB(45, 85, 140))
local backBtn = createDpadBtn("⬇️ หลัง", 120, 104, 64, 38, Color3.fromRGB(45, 85, 140))
local rotLeftBtn = createDpadBtn("⟲ หมุนซ้าย", 214, 26, 74, 46, Color3.fromRGB(55, 50, 80))
local rotRightBtn = createDpadBtn("หมุนขวา ⟳", 214, 84, 74, 46, Color3.fromRGB(55, 50, 80))

-- [[ Ball Mode UI Controls in Tab 1 ]]
local ballToggleBtn = Instance.new("TextButton", tabFreeContainer)
ballToggleBtn.Size = UDim2.new(1, 0, 0, 32)
ballToggleBtn.Position = UDim2.new(0, 0, 0, 258)
ballToggleBtn.BackgroundColor3 = Color3.fromRGB(145, 55, 200)
ballToggleBtn.Text = "⚽ บอลรวมแน่นหมุนไว: ปิด"
ballToggleBtn.TextColor3 = Color3.new(1, 1, 1)
ballToggleBtn.Font = Enum.Font.GothamBold
ballToggleBtn.TextSize = 11
Instance.new("UICorner", ballToggleBtn).CornerRadius = UDim.new(0, 7)

local ballFollowBtn = Instance.new("TextButton", tabFreeContainer)
ballFollowBtn.Size = UDim2.new(1, 0, 0, 28)
ballFollowBtn.Position = UDim2.new(0, 0, 0, 294)
ballFollowBtn.BackgroundColor3 = Color3.fromRGB(45, 95, 175)
ballFollowBtn.Text = "🎯 บอลตามผู้เล่นที่เลือก (แท็บตามคน): เปิด"
ballFollowBtn.TextColor3 = Color3.new(1, 1, 1)
ballFollowBtn.Font = Enum.Font.GothamBold
ballFollowBtn.TextSize = 10
Instance.new("UICorner", ballFollowBtn).CornerRadius = UDim.new(0, 6)

-- [[ Prop Color Changer Controls in Tab 1 ]]
local function applyPropColor(color3, colorName)
    if #trackedProps == 0 then
        bindAllProps(false)
    end

    local changedCount = 0
    for _, item in ipairs(trackedProps) do
        if item.model and item.model.Parent then
            for _, desc in ipairs(item.model:GetDescendants()) do
                if desc:IsA("BasePart") then
                    desc.Color = color3
                    changedCount = changedCount + 1
                end
            end

            pcall(function()
                for _, child in ipairs(item.model:GetChildren()) do
                    if child:IsA("RemoteEvent") and (child.Name:lower():find("color") or child.Name:lower():find("paint")) then
                        child:FireServer(color3)
                    elseif child:IsA("RemoteFunction") and (child.Name:lower():find("color") or child.Name:lower():find("paint")) then
                        child:InvokeServer(color3)
                    end
                end
            end)
        end
    end

    pcall(function()
        local re = game:FindFirstChild("ReplicatedStorage") and game.ReplicatedStorage:FindFirstChild("RE")
        if re then
            for _, rem in ipairs(re:GetChildren()) do
                if rem:IsA("RemoteEvent") and (rem.Name:lower():find("prop") or rem.Name:lower():find("color")) then
                    pcall(function()
                        rem:FireServer("PropColor", color3)
                    end)
                end
            end
        end
    end)

    statusLabel.Text = string.format("🎨 สี Prop: %s (%d ชิ้น / %d พาร์ท)", colorName, #trackedProps, changedCount)
end

local colorRow = Instance.new("Frame", tabFreeContainer)
colorRow.Name = "PropColorRow"
colorRow.Size = UDim2.new(1, 0, 0, 30)
colorRow.Position = UDim2.new(0, 0, 0, 328)
colorRow.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
Instance.new("UICorner", colorRow).CornerRadius = UDim.new(0, 7)

local colorTitle = Instance.new("TextLabel", colorRow)
colorTitle.Size = UDim2.new(0, 66, 1, 0)
colorTitle.Position = UDim2.new(0, 8, 0, 0)
colorTitle.BackgroundTransparency = 1
colorTitle.Text = "🎨 สี Prop:"
colorTitle.TextColor3 = Color3.fromRGB(215, 220, 235)
colorTitle.Font = Enum.Font.GothamBold
colorTitle.TextSize = 10
colorTitle.TextXAlignment = Enum.TextXAlignment.Left

local blackColorBtn = Instance.new("TextButton", colorRow)
blackColorBtn.Size = UDim2.new(0, 72, 0, 22)
blackColorBtn.Position = UDim2.new(0, 74, 0, 4)
blackColorBtn.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
blackColorBtn.Text = "⬛ ดำ"
blackColorBtn.TextColor3 = Color3.new(1, 1, 1)
blackColorBtn.Font = Enum.Font.GothamBold
blackColorBtn.TextSize = 10
Instance.new("UICorner", blackColorBtn).CornerRadius = UDim.new(0, 5)
local blkStroke = Instance.new("UIStroke", blackColorBtn)
blkStroke.Color = Color3.fromRGB(110, 115, 130)
blkStroke.Thickness = 1

local yellowColorBtn = Instance.new("TextButton", colorRow)
yellowColorBtn.Size = UDim2.new(0, 74, 0, 22)
yellowColorBtn.Position = UDim2.new(0, 152, 0, 4)
yellowColorBtn.BackgroundColor3 = Color3.fromRGB(235, 195, 35)
yellowColorBtn.Text = "🟨 เหลือง"
yellowColorBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
yellowColorBtn.Font = Enum.Font.GothamBold
yellowColorBtn.TextSize = 10
Instance.new("UICorner", yellowColorBtn).CornerRadius = UDim.new(0, 5)

local redColorBtn = Instance.new("TextButton", colorRow)
redColorBtn.Size = UDim2.new(0, 74, 0, 22)
redColorBtn.Position = UDim2.new(0, 232, 0, 4)
redColorBtn.BackgroundColor3 = Color3.fromRGB(210, 45, 55)
redColorBtn.Text = "🟥 แดง"
redColorBtn.TextColor3 = Color3.new(1, 1, 1)
redColorBtn.Font = Enum.Font.GothamBold
redColorBtn.TextSize = 10
Instance.new("UICorner", redColorBtn).CornerRadius = UDim.new(0, 5)

blackColorBtn.MouseButton1Click:Connect(function()
    applyPropColor(Color3.fromRGB(20, 20, 24), "ดำ")
end)

yellowColorBtn.MouseButton1Click:Connect(function()
    applyPropColor(Color3.fromRGB(255, 210, 30), "เหลือง")
end)

redColorBtn.MouseButton1Click:Connect(function()
    applyPropColor(Color3.fromRGB(215, 35, 45), "แดง")
end)

-- [[ Prop Explode Button in Tab 1 ]]
local explodeToggleBtn = Instance.new("TextButton", tabFreeContainer)
explodeToggleBtn.Name = "PropExplodeBtn"
explodeToggleBtn.Size = UDim2.new(1, 0, 0, 34)
explodeToggleBtn.Position = UDim2.new(0, 0, 0, 364)
explodeToggleBtn.BackgroundColor3 = Color3.fromRGB(210, 45, 55)
explodeToggleBtn.Text = "💥 ระเบิด Prop (กระตุก + หมุนไว): ปิด"
explodeToggleBtn.TextColor3 = Color3.new(1, 1, 1)
explodeToggleBtn.Font = Enum.Font.GothamBold
explodeToggleBtn.TextSize = 11
Instance.new("UICorner", explodeToggleBtn).CornerRadius = UDim.new(0, 7)
local expStroke = Instance.new("UIStroke", explodeToggleBtn)
expStroke.Color = Color3.fromRGB(255, 110, 120)
expStroke.Thickness = 1.1

-- ========================================================
-- [[ PROP EXPLODE IMPLEMENTATION ]]
-- ========================================================
local function prepareExplodeData(props, originPos)
    explodeData = {}
    for i, prop in ipairs(props) do
        local ok, piv = pcall(function() return prop:GetPivot() end)
        local startPos = (ok and piv) and piv.Position or originPos

        local angle = (i / math.max(#props, 1)) * math.pi * 2 + (i * 0.7)
        local dir = Vector3.new(
            math.cos(angle) + math.sin(i * 2.1) * 0.4,
            0.45 + (i % 3) * 0.25,
            math.sin(angle) + math.cos(i * 1.7) * 0.4
        )
        if dir.Magnitude < 0.01 then
            dir = Vector3.new(0, 1, 0)
        else
            dir = dir.Unit
        end

        explodeData[prop] = {
            startPos = startPos,
            dir = dir,
            maxDist = 14 + (i % 5) * 4.5,
            spinSpeed = (28 + (i % 6) * 8) * ((i % 2 == 0) and 1 or -1),
            jitterAmp = 0.35 + (i % 3) * 0.12,
            phase = i * 1.35,
        }
    end
end

stopPropExplode = function(restoreCluster)
    local wasExploding = isExploding
    isExploding = false
    if explodeConn then
        explodeConn:Disconnect()
        explodeConn = nil
    end
    explodeToggleBtn.BackgroundColor3 = Color3.fromRGB(210, 45, 55)
    explodeToggleBtn.Text = "💥 ระเบิด Prop (กระตุก + หมุนไว): ปิด"

    if wasExploding and restoreCluster and not isBallMode then
        bindAllProps(not isFoldedMode)
        moveClusterTo(CFrame.new(clusterPos) * CFrame.Angles(0, clusterYaw, 0))
        statusLabel.Text = "🔗 เชื่อมต่อ Prop: " .. #trackedProps .. " ชิ้น (จัดทรงคืนแล้ว)"
    end
end

local function startPropExplode()
    if #trackedProps == 0 then
        bindAllProps(not isFoldedMode)
    end
    local props = {}
    for _, item in ipairs(trackedProps) do
        if item.model and item.model.Parent then
            table.insert(props, item.model)
        end
    end
    if #props == 0 then
        props = getMyPropsList()
    end
    if #props == 0 then
        explodeToggleBtn.Text = "❌ ไม่มี Prop ในเกม"
        task.delay(1.2, function()
            if not isExploding then
                explodeToggleBtn.Text = "💥 ระเบิด Prop (กระตุก + หมุนไว): ปิด"
            end
        end)
        return false
    end

    if isBallMode and type(setBallMode) == "function" then
        setBallMode(false)
    end

    stopPropExplode(false)

    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local originPos = (clusterPos and clusterPos.Magnitude > 1) and clusterPos or (hrp and hrp.Position or Vector3.zero)

    prepareExplodeData(props, originPos)
    isExploding = true
    explodeToggleBtn.BackgroundColor3 = Color3.fromRGB(45, 165, 100)
    explodeToggleBtn.Text = "💥 กำลังระเบิด Prop (กดเพื่อหยุด)"
    statusLabel.Text = "💥 โหมดระเบิด Prop: กระตุก + หมุนไว (" .. #props .. " ชิ้น)"

    local t0 = os.clock()
    explodeConn = trackConn(RunService.RenderStepped:Connect(function()
        if not isExploding then return end
        local elapsed = os.clock() - t0
        local shouldSync = (os.clock() - lastExplodeNetSync) > 0.06

        local jitterPhase = math.clamp(1 - (elapsed / 0.45), 0, 1)
        local blastProgress = math.clamp((elapsed - 0.25) / 0.55, 0, 1)
        local easedBlast = 1 - ((1 - blastProgress) ^ 3)

        for _, prop in ipairs(props) do
            if prop and prop.Parent then
                local d = explodeData[prop]
                if d then
                    local jx = math.sin(elapsed * 65 + d.phase) * d.jitterAmp * jitterPhase
                    local jy = math.cos(elapsed * 72 + d.phase * 1.3) * d.jitterAmp * jitterPhase
                    local jz = math.sin(elapsed * 58 + d.phase * 0.7) * d.jitterAmp * jitterPhase
                    local jitterVec = Vector3.new(jx, jy, jz)

                    local outPos = d.startPos + (d.dir * (d.maxDist * easedBlast)) + jitterVec
                    local spinCF = CFrame.Angles(
                        elapsed * d.spinSpeed,
                        elapsed * (d.spinSpeed * 1.25),
                        elapsed * (d.spinSpeed * 0.85)
                    )
                    local targetCF = CFrame.new(outPos) * spinCF

                    pcall(function()
                        prop:PivotTo(targetCF)
                    end)

                    if shouldSync then
                        local rem = prop:FindFirstChild("SetCurrentCFrame")
                        if rem and rem.Parent then
                            safeInvokeSetCF(rem, targetCF)
                        end
                    end
                end
            end
        end

        if shouldSync then
            lastExplodeNetSync = os.clock()
        end
    end))

    return true
end

explodeToggleBtn.MouseButton1Click:Connect(function()
    if not isExploding then
        startPropExplode()
    else
        stopPropExplode(true)
    end
end)

-- ========================================================
-- [[ ORIGINAL BALL MODE IMPLEMENTATION ]]
-- ========================================================
local function assignRandomSpinAxes()
    propSpinAxes = {}
    local axes = {
        Vector3.new(1, 0, 0),
        Vector3.new(-1, 0, 0),
        Vector3.new(0, 1, 0),
        Vector3.new(0, -1, 0),
        Vector3.new(0, 0, 1),
        Vector3.new(0, 0, -1),
        Vector3.new(1, 1, 0).Unit,
        Vector3.new(-1, 1, 0).Unit,
        Vector3.new(0, 1, 1).Unit,
        Vector3.new(1, 0, -1).Unit,
        Vector3.new(-1, -1, 1).Unit,
        Vector3.new(1, -1, -1).Unit,
    }
    for i = 1, math.max(#trackedProps, 15) do
        local dir = (i % 2 == 0) and 1 or -1
        local baseSpd = (4.5 + (i % 6) * 1.4) * dir
        local axis = axes[((i - 1) % #axes) + 1]
        local layerRadius = ballBaseRadius * (0.65 + ((i % 4) * 0.22))
        propSpinAxes[i] = {
            axis = axis,
            speed = baseSpd,
            orbitSpeed = (2.8 + (i % 4) * 0.9) * ((i % 2 == 0) and 1 or -1),
            phase = (i * 1.15),
            radius = layerRadius,
        }
    end
end

local function getFibonacciSpherePoint(index, total)
    if total <= 1 then return Vector3.zero end
    local goldenAngle = math.pi * (3 - math.sqrt(5))
    local y = 1 - ((index - 1) / (total - 1)) * 2
    local radiusAtY = math.sqrt(math.max(0, 1 - y * y))
    local theta = goldenAngle * (index - 1)
    return Vector3.new(
        math.cos(theta) * radiusAtY,
        y,
        math.sin(theta) * radiusAtY
    )
end

local function getBallCenter()
    if ballFollowTarget and targetPlayer and targetPlayer.Character then
        local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then
            return root.Position + Vector3.new(0, heightOffset + 1.2, 0)
        end
    end
    return clusterPos
end

setBallMode = function(enable)
    if enable then
        if isExploding and type(stopPropExplode) == "function" then
            stopPropExplode(false)
        end
        if #trackedProps == 0 then
            bindAllProps(false)
        end
        if #trackedProps == 0 then
            ballToggleBtn.Text = "❌ ไม่มี Prop ในเกม"
            task.delay(1.5, function()
                if not isBallMode then
                    ballToggleBtn.Text = "⚽ บอลรวมแน่นหมุนไว: ปิด"
                end
            end)
            return
        end

        isBallMode = true
        ballToggleBtn.BackgroundColor3 = Color3.fromRGB(45, 165, 110)
        ballToggleBtn.Text = "⚽ บอลรวมแน่นหมุนไว: เปิด"
        assignRandomSpinAxes()

        if clusterPos.Magnitude < 1 and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") then
            clusterPos = lp.Character.HumanoidRootPart.Position + Vector3.new(0, 1.5, 0)
        end

        if ballSpinConn then
            ballSpinConn:Disconnect()
            ballSpinConn = nil
        end

        local startClock = os.clock()
        ballSpinConn = RunService.RenderStepped:Connect(function()
            if not isBallMode then return end
            local elapsed = (os.clock() - startClock) * ballSpinSpeedMult
            local total = #trackedProps
            if total == 0 then return end

            local centerPos = getBallCenter()
            clusterPos = centerPos
            local rootCF = CFrame.new(centerPos)
            local shouldSync = (os.clock() - lastBallNetSync) > 0.05

            for i, item in ipairs(trackedProps) do
                if item.model and item.model.Parent then
                    local spinData = propSpinAxes[i] or {
                        axis = Vector3.new(0, 1, 0),
                        speed = 6,
                        orbitSpeed = 3,
                        phase = i,
                        radius = ballBaseRadius,
                    }

                    local unitDir = getFibonacciSpherePoint(i, total)
                    local orbitCF = CFrame.Angles(
                        elapsed * (spinData.orbitSpeed * 0.45),
                        elapsed * spinData.orbitSpeed + spinData.phase,
                        elapsed * (spinData.orbitSpeed * 0.35) * ((i % 2 == 0) and 1 or -1)
                    )
                    local offsetPos = (orbitCF * unitDir) * spinData.radius
                    local selfSpinCF = CFrame.fromAxisAngle(spinData.axis, elapsed * spinData.speed)
                    local finalCF = rootCF * CFrame.new(offsetPos) * selfSpinCF

                    pcall(function() item.model:PivotTo(finalCF) end)

                    if shouldSync and item.setCF and item.setCF.Parent then
                        safeInvokeSetCF(item.setCF, finalCF)
                    end
                end
            end

            if shouldSync then
                lastBallNetSync = os.clock()
            end
        end)
    else
        isBallMode = false
        ballToggleBtn.BackgroundColor3 = Color3.fromRGB(145, 55, 200)
        ballToggleBtn.Text = "⚽ บอลรวมแน่นหมุนไว: ปิด"
        if ballSpinConn then
            ballSpinConn:Disconnect()
            ballSpinConn = nil
        end
        bindAllProps(not isFoldedMode)
        moveClusterTo(CFrame.new(clusterPos) * CFrame.Angles(0, clusterYaw, 0))
    end
end

ballToggleBtn.MouseButton1Click:Connect(function()
    setBallMode(not isBallMode)
end)

ballFollowBtn.MouseButton1Click:Connect(function()
    ballFollowTarget = not ballFollowTarget
    if ballFollowTarget then
        ballFollowBtn.BackgroundColor3 = Color3.fromRGB(45, 95, 175)
        ballFollowBtn.Text = "🎯 บอลตามผู้เล่นที่เลือก (แท็บตามคน): เปิด"
    else
        ballFollowBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 78)
        ballFollowBtn.Text = "📌 บอลอยู่กับที่: ปิดการตาม"
    end
end)

local function startMoving(dir)
    if holdingDir == dir then return end
    if isExploding and type(stopPropExplode) == "function" then
        stopPropExplode(false)
    end
    holdingDir = dir
    task.spawn(function()
        local lastTime = os.clock()
        while holdingDir == dir do
            local now = os.clock()
            local dt = math.min(now - lastTime, 0.1)
            lastTime = now

            local cam = workspace.CurrentCamera
            local forward = cam and Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
            if forward.Magnitude > 0.001 then forward = forward.Unit else forward = Vector3.new(0, 0, -1) end
            local right = cam and Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z) or Vector3.new(1, 0, 0)
            if right.Magnitude > 0.001 then right = right.Unit else right = Vector3.new(1, 0, 0) end
            local up = Vector3.new(0, 1, 0)

            local delta = Vector3.zero
            local actualSpeed = moveSpeed * speedMultiplier * dt

            if dir == "fwd" then delta = forward * actualSpeed
            elseif dir == "back" then delta = -forward * actualSpeed
            elseif dir == "left" then delta = -right * actualSpeed
            elseif dir == "right" then delta = right * actualSpeed
            elseif dir == "up" then delta = up * actualSpeed
            elseif dir == "down" then delta = -up * actualSpeed
            elseif dir == "rotL" then clusterYaw = clusterYaw + math.rad(90 * speedMultiplier * dt)
            elseif dir == "rotR" then clusterYaw = clusterYaw - math.rad(90 * speedMultiplier * dt)
            end

            clusterPos = clusterPos + delta
            clusterCFrame = CFrame.new(clusterPos) * CFrame.Angles(0, clusterYaw, 0)
            if not isBallMode then
                updateClusterVisuals(clusterCFrame)
            end

            if not isBallMode and os.clock() - lastNetSync > 0.07 then
                lastNetSync = os.clock()
                for i, item in ipairs(trackedProps) do
                    if item.setCF and item.setCF.Parent then
                        safeInvokeSetCF(item.setCF, clusterCFrame * getItemRelCF(item, i))
                    end
                end
            end

            task.wait(0.02)
        end
    end)
end

local function stopMoving()
    holdingDir = nil
    if not isBallMode then
        syncClusterToNetwork(clusterCFrame)
    end
end

local function bindHoldEvents(btn, dir)
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            startMoving(dir)
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            stopMoving()
        end
    end)
end

bindHoldEvents(fwdBtn, "fwd")
bindHoldEvents(backBtn, "back")
bindHoldEvents(leftBtn, "left")
bindHoldEvents(rightBtn, "right")
bindHoldEvents(upBtn, "up")
bindHoldEvents(downBtn, "down")
bindHoldEvents(rotLeftBtn, "rotL")
bindHoldEvents(rotRightBtn, "rotR")

local function handleScreenRay(screenPos)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local unitRay = cam:ViewportPointToRay(screenPos.X, screenPos.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local ignore = { lp.Character }
    for _, item in ipairs(trackedProps) do
        if item.model then table.insert(ignore, item.model) end
    end
    raycastParams.FilterDescendantsInstances = ignore

    local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 350, raycastParams)
    local hitPos
    if result then
        hitPos = result.Position + Vector3.new(0, 2.8 + heightOffset, 0)
    else
        hitPos = unitRay.Origin + unitRay.Direction * 20 + Vector3.new(0, heightOffset, 0)
    end

    clusterPos = hitPos
    clusterCFrame = CFrame.new(clusterPos) * CFrame.Angles(0, clusterYaw, 0)
    if not isBallMode then
        updateClusterVisuals(clusterCFrame)
    end

    if not isBallMode and os.clock() - lastNetSync > 0.07 then
        lastNetSync = os.clock()
        for i, item in ipairs(trackedProps) do
            if item.setCF and item.setCF.Parent then
                safeInvokeSetCF(item.setCF, clusterCFrame * getItemRelCF(item, i))
            end
        end
    end
end

trackConn(UserInputService.InputBegan:Connect(function(input, gpe)
    if not isDragMode and not isTapToPlace then return end
    if gpe then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local mPos = UserInputService:GetMouseLocation()
        local okGui, guiObjects = pcall(function()
            return parentGui:GetGuiObjectsAtPosition(mPos.X, mPos.Y)
        end)
        local isOverMain = false
        if okGui and type(guiObjects) == "table" then
            for _, obj in ipairs(guiObjects) do
                if obj:IsDescendantOf(mainFrame) or obj:IsDescendantOf(dragBanner) or obj:IsDescendantOf(driveHud) then
                    isOverMain = true
                    break
                end
            end
        end
        if not isOverMain then
            if isDragMode then
                if isExploding and type(stopPropExplode) == "function" then
                    stopPropExplode(false)
                end
                isDraggingNow = true
                handleScreenRay(mPos)
            elseif isTapToPlace then
                if isExploding and type(stopPropExplode) == "function" then
                    stopPropExplode(false)
                end
                handleScreenRay(mPos)
                isTapToPlace = false
                tapPlaceBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 70)
                tapPlaceBtn.Text = "🎯 แตะพื้นวาง"
                if not isBallMode then
                    syncClusterToNetwork(clusterCFrame)
                end
            end
        end
    end
end))

trackConn(UserInputService.InputChanged:Connect(function(input, gpe)
    if not isDragMode or not isDraggingNow then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        if input.UserInputType == Enum.UserInputType.Touch or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            local mPos = UserInputService:GetMouseLocation()
            handleScreenRay(mPos)
        end
    end
end))

trackConn(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if isDraggingNow then
            isDraggingNow = false
            if not isBallMode then
                syncClusterToNetwork(clusterCFrame)
            end
        end
    end
end))

-- ========================================================
-- [[ DRIVE PROP MODE IMPLEMENTATION ]]
-- ========================================================
local jumpConns = {}

local function stopDriving()
    if not isDriving then return end
    isDriving = false
    if driveRenderConn then
        driveRenderConn:Disconnect()
        driveRenderConn = nil
    end
    for _, conn in ipairs(jumpConns) do
        pcall(function() conn:Disconnect() end)
    end
    jumpConns = {}

    driveHud.Visible = false
    mainFrame.Visible = true

    local cam = workspace.CurrentCamera
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if char and hum and hrp then
        cam.CameraSubject = hum
        hrp.Anchored = false
        hum.WalkSpeed = (savedWalkSpeed > 0) and savedWalkSpeed or 16
        hum.JumpPower = 50
    end

    if propDriveProxy then
        propDriveProxy:Destroy()
        propDriveProxy = nil
    end

    if not isBallMode and not isExploding then
        syncClusterToNetwork(clusterCFrame)
    end
end

exitDriveBtn.MouseButton1Click:Connect(stopDriving)

local function startDriving()
    if isDriving then return end
    if isExploding and type(stopPropExplode) == "function" then
        stopPropExplode(false)
    end
    if #trackedProps == 0 then bindAllProps(not isFoldedMode) end
    if #trackedProps == 0 then return end

    isDriving = true
    mainFrame.Visible = false
    driveHud.Visible = true

    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if char and hum and hrp then
        savedWalkSpeed = hum.WalkSpeed
        hum.JumpPower = 50
        hum.WalkSpeed = (savedWalkSpeed > 0) and savedWalkSpeed or 16
        hrp.Anchored = true
    end

    if not propDriveProxy or not propDriveProxy.Parent then
        propDriveProxy = Instance.new("Part")
        propDriveProxy.Name = "PropDriveProxy"
        propDriveProxy.Size = Vector3.new(2, 2, 2)
        propDriveProxy.Transparency = 1
        propDriveProxy.CanCollide = false
        propDriveProxy.CanTouch = false
        propDriveProxy.CanQuery = false
        propDriveProxy.Anchored = true
        propDriveProxy.Parent = workspace
    end

    local p = trackedProps[10] and trackedProps[10].model or (trackedProps[6] and trackedProps[6].model or trackedProps[1].model)
    if p and p.Parent then
        local ok, pv = pcall(function() return p:GetPivot() end)
        if ok and pv then
            clusterCFrame = pv
            clusterPos = pv.Position
            local _, y, _ = pv:ToEulerAnglesYXZ()
            clusterYaw = y
        end
    end
    propDriveProxy.CFrame = CFrame.new(clusterPos)

    local cam = workspace.CurrentCamera
    if cam then cam.CameraSubject = propDriveProxy end

    vertVel = 0
    isOnGround = true
    jumpRequested = false

    local function onRobloxJump()
        if not isDriving then return end
        if isFlying then
            jumpRequested = true
        elseif isOnGround then
            vertVel = 52
            isOnGround = false
        end
    end

    jumpConns = {}
    table.insert(jumpConns, UserInputService.JumpRequest:Connect(onRobloxJump))
    table.insert(jumpConns, UserInputService.InputBegan:Connect(function(inp)
        if isDriving and inp.KeyCode == Enum.KeyCode.Space then
            onRobloxJump()
        end
    end))

    if hum then
        table.insert(jumpConns, hum:GetPropertyChangedSignal("Jump"):Connect(function()
            if hum.Jump then
                onRobloxJump()
                hum.Jump = false
            end
        end))
        table.insert(jumpConns, hum.StateChanged:Connect(function(_, newState)
            if newState == Enum.HumanoidStateType.Jumping then
                onRobloxJump()
            end
        end))
    end

    pcall(function()
        local touchGui = lp:FindFirstChild("PlayerGui") and lp.PlayerGui:FindFirstChild("TouchGui")
        if touchGui then
            local jb = touchGui:FindFirstChild("JumpButton", true)
            if jb and jb:IsA("GuiButton") then
                table.insert(jumpConns, jb.InputBegan:Connect(function()
                    onRobloxJump()
                end))
            end
        end
    end)

    driveRenderConn = RunService.RenderStepped:Connect(function(dt)
        if not isDriving then return end
        local stepDt = math.clamp(dt or (1/60), 0, 0.1)

        local camCF = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new()

        local moveVec = Vector3.zero
        if cm and type(cm.GetMoveVector) == "function" then
            local okVec, v = pcall(function() return cm:GetMoveVector() end)
            if okVec and typeof(v) == "Vector3" and v.Magnitude > 0.01 then
                moveVec = v
            end
        end
        if moveVec.Magnitude < 0.01 then
            local x, z = 0, 0
            if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then z = z - 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then z = z + 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then x = x - 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then x = x + 1 end
            local raw = Vector3.new(x, 0, z)
            if raw.Magnitude > 0.01 then moveVec = raw.Unit end
        end

        if isFlying then
            local flyLook = camCF.LookVector
            local flyRight = camCF.RightVector
            local moveDir = (flyRight * moveVec.X - flyLook * moveVec.Z)

            if moveDir.Magnitude > 0.05 then
                clusterPos = clusterPos + moveDir.Unit * (driveSpeed * stepDt)
                clusterYaw = math.atan2(-flyLook.X, -flyLook.Z)
            end

            if jumpRequested or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                clusterPos = clusterPos + Vector3.new(0, driveSpeed * stepDt, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then
                clusterPos = clusterPos - Vector3.new(0, driveSpeed * stepDt, 0)
            end
            jumpRequested = false
        else
            local camFwd = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
            if camFwd.Magnitude > 0.001 then camFwd = camFwd.Unit else camFwd = Vector3.new(0, 0, -1) end
            local camRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
            if camRight.Magnitude > 0.001 then camRight = camRight.Unit else camRight = Vector3.new(1, 0, 0) end

            local moveDir = (camRight * moveVec.X - camFwd * moveVec.Z)
            local isMoving = moveDir.Magnitude > 0.05

            if isMoving then
                local forwardRayParams = RaycastParams.new()
                forwardRayParams.FilterType = Enum.RaycastFilterType.Exclude
                local ignoreList = { lp.Character }
                for _, item in ipairs(trackedProps) do
                    if item.model then table.insert(ignoreList, item.model) end
                end
                forwardRayParams.FilterDescendantsInstances = ignoreList

                local wallRay = workspace:Raycast(clusterPos, moveDir.Unit * 2.2, forwardRayParams)
                if wallRay and wallRay.Instance and wallRay.Instance.CanCollide then
                    local normal = wallRay.Normal
                    moveDir = moveDir - normal * moveDir:Dot(normal)
                end

                if moveDir.Magnitude > 0.01 then
                    clusterPos = clusterPos + moveDir.Unit * (driveSpeed * stepDt)
                end
                clusterYaw = math.atan2(-camFwd.X, -camFwd.Z)
            end

            local groundRayParams = RaycastParams.new()
            groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
            local ignoreList = { lp.Character }
            for _, item in ipairs(trackedProps) do
                if item.model then table.insert(ignoreList, item.model) end
            end
            groundRayParams.FilterDescendantsInstances = ignoreList

            local rayOrigin = Vector3.new(clusterPos.X, clusterPos.Y + 2.0, clusterPos.Z)
            local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -25, 0), groundRayParams)
            local targetGroundY = rayResult and (rayResult.Position.Y + 3.08) or nil

            local currentGrav = workspace.Gravity or 196.2

            if not isOnGround then
                vertVel = vertVel - (currentGrav * stepDt)
                clusterPos = clusterPos + Vector3.new(0, vertVel * stepDt, 0)

                if targetGroundY and vertVel <= 0 and clusterPos.Y <= targetGroundY then
                    clusterPos = Vector3.new(clusterPos.X, targetGroundY, clusterPos.Z)
                    vertVel = 0
                    isOnGround = true
                end
            else
                if targetGroundY then
                    local diff = targetGroundY - clusterPos.Y
                    if math.abs(diff) <= 2.2 then
                        clusterPos = Vector3.new(clusterPos.X, targetGroundY, clusterPos.Z)
                    elseif targetGroundY < clusterPos.Y - 2.2 then
                        isOnGround = false
                        vertVel = 0
                    end
                else
                    isOnGround = false
                    vertVel = 0
                end
            end
        end

        clusterCFrame = CFrame.new(clusterPos) * CFrame.Angles(0, clusterYaw, 0)
        propDriveProxy.CFrame = CFrame.new(clusterPos)
        if not isBallMode then
            updateClusterVisuals(clusterCFrame)
        end

        if not isBallMode and os.clock() - lastDriveNetSync > 0.06 then
            lastDriveNetSync = os.clock()
            for i, item in ipairs(trackedProps) do
                if item.setCF and item.setCF.Parent then
                    safeInvokeSetCF(item.setCF, clusterCFrame * getItemRelCF(item, i))
                end
            end
        end
    end)
end

driveEnterBtn.MouseButton1Click:Connect(startDriving)

-- ========================================================
-- [[ TAB 2: ABDUCT / PULL NEAREST PLAYER ]]
-- ========================================================
local abductCard = Instance.new("Frame", tabAbductContainer)
abductCard.Size = UDim2.new(1, 0, 0, 48)
abductCard.BackgroundColor3 = Color3.fromRGB(26, 30, 44)
Instance.new("UICorner", abductCard).CornerRadius = UDim.new(0, 8)

local abductTitle = Instance.new("TextLabel", abductCard)
abductTitle.Size = UDim2.new(1, -16, 0, 20)
abductTitle.Position = UDim2.new(0, 8, 0, 4)
abductTitle.BackgroundTransparency = 1
abductTitle.Text = "🧲 ดึงคนใกล้ตัว (สูงสุด 4 คน) เข้ากรงโดยกรงไม่ขยับหาเรา"
abductTitle.TextColor3 = Color3.fromRGB(130, 215, 255)
abductTitle.Font = Enum.Font.GothamBold
abductTitle.TextSize = 11
abductTitle.TextXAlignment = Enum.TextXAlignment.Left

local nearestTrackerLabel = Instance.new("TextLabel", abductCard)
nearestTrackerLabel.Size = UDim2.new(1, -16, 0, 20)
nearestTrackerLabel.Position = UDim2.new(0, 8, 0, 24)
nearestTrackerLabel.BackgroundTransparency = 1
nearestTrackerLabel.Text = "🔍 ตรวจจับผู้เล่นใกล้ที่สุด: กำลังสแกน..."
nearestTrackerLabel.TextColor3 = Color3.fromRGB(180, 190, 210)
nearestTrackerLabel.Font = Enum.Font.Gotham
nearestTrackerLabel.TextSize = 10
nearestTrackerLabel.TextXAlignment = Enum.TextXAlignment.Left

local rangeRow = Instance.new("Frame", tabAbductContainer)
rangeRow.Size = UDim2.new(1, 0, 0, 32)
rangeRow.Position = UDim2.new(0, 0, 0, 54)
rangeRow.BackgroundTransparency = 1

local rangeLabel = Instance.new("TextLabel", rangeRow)
rangeLabel.Size = UDim2.new(0, 105, 1, 0)
rangeLabel.BackgroundTransparency = 1
rangeLabel.Text = "ระยะค้นหา: 15 studs"
rangeLabel.TextColor3 = Color3.fromRGB(255, 215, 120)
rangeLabel.Font = Enum.Font.GothamBold
rangeLabel.TextSize = 10
rangeLabel.TextXAlignment = Enum.TextXAlignment.Left

local r10 = Instance.new("TextButton", rangeRow)
r10.Size = UDim2.new(0, 34, 0, 24); r10.Position = UDim2.new(0, 110, 0, 4)
r10.BackgroundColor3 = Color3.fromRGB(36, 40, 54); r10.Text = "10"
r10.TextColor3 = Color3.fromRGB(180, 185, 200); r10.Font = Enum.Font.GothamBold; r10.TextSize = 10
Instance.new("UICorner", r10).CornerRadius = UDim.new(0, 5)

local r15 = Instance.new("TextButton", rangeRow)
r15.Size = UDim2.new(0, 34, 0, 24); r15.Position = UDim2.new(0, 148, 0, 4)
r15.BackgroundColor3 = Color3.fromRGB(45, 95, 175); r15.Text = "15"
r15.TextColor3 = Color3.new(1, 1, 1); r15.Font = Enum.Font.GothamBold; r15.TextSize = 10
Instance.new("UICorner", r15).CornerRadius = UDim.new(0, 5)

local r20 = Instance.new("TextButton", rangeRow)
r20.Size = UDim2.new(0, 34, 0, 24); r20.Position = UDim2.new(0, 186, 0, 4)
r20.BackgroundColor3 = Color3.fromRGB(36, 40, 54); r20.Text = "20"
r20.TextColor3 = Color3.fromRGB(180, 185, 200); r20.Font = Enum.Font.GothamBold; r20.TextSize = 10
Instance.new("UICorner", r20).CornerRadius = UDim.new(0, 5)

local r30 = Instance.new("TextButton", rangeRow)
r30.Size = UDim2.new(0, 34, 0, 24); r30.Position = UDim2.new(0, 224, 0, 4)
r30.BackgroundColor3 = Color3.fromRGB(36, 40, 54); r30.Text = "30"
r30.TextColor3 = Color3.fromRGB(180, 185, 200); r30.Font = Enum.Font.GothamBold; r30.TextSize = 10
Instance.new("UICorner", r30).CornerRadius = UDim.new(0, 5)

local r50 = Instance.new("TextButton", rangeRow)
r50.Size = UDim2.new(0, 34, 0, 24); r50.Position = UDim2.new(0, 262, 0, 4)
r50.BackgroundColor3 = Color3.fromRGB(36, 40, 54); r50.Text = "50"
r50.TextColor3 = Color3.fromRGB(180, 185, 200); r50.Font = Enum.Font.GothamBold; r50.TextSize = 10
Instance.new("UICorner", r50).CornerRadius = UDim.new(0, 5)

local function updateRange(val)
    abductRange = val
    rangeLabel.Text = string.format("ระยะค้นหา: %d studs", val)
    r10.BackgroundColor3 = (val == 10) and Color3.fromRGB(45, 95, 175) or Color3.fromRGB(36, 40, 54)
    r15.BackgroundColor3 = (val == 15) and Color3.fromRGB(45, 95, 175) or Color3.fromRGB(36, 40, 54)
    r20.BackgroundColor3 = (val == 20) and Color3.fromRGB(45, 95, 175) or Color3.fromRGB(36, 40, 54)
    r30.BackgroundColor3 = (val == 30) and Color3.fromRGB(45, 95, 175) or Color3.fromRGB(36, 40, 54)
    r50.BackgroundColor3 = (val == 50) and Color3.fromRGB(45, 95, 175) or Color3.fromRGB(36, 40, 54)
end
r10.MouseButton1Click:Connect(function() updateRange(10) end)
r15.MouseButton1Click:Connect(function() updateRange(15) end)
r20.MouseButton1Click:Connect(function() updateRange(20) end)
r30.MouseButton1Click:Connect(function() updateRange(30) end)
r50.MouseButton1Click:Connect(function() updateRange(50) end)

local abductActionBtn = Instance.new("TextButton", tabAbductContainer)
abductActionBtn.Size = UDim2.new(1, 0, 0, 42)
abductActionBtn.Position = UDim2.new(0, 0, 0, 92)
abductActionBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 110)
abductActionBtn.Text = "🧲 ดึงคนใกล้ที่สุด (สูงสุด 4 คน) มาขังในกรงทันที!"
abductActionBtn.TextColor3 = Color3.new(1, 1, 1)
abductActionBtn.Font = Enum.Font.GothamBold
abductActionBtn.TextSize = 12
Instance.new("UICorner", abductActionBtn).CornerRadius = UDim.new(0, 8)
local aStroke = Instance.new("UIStroke", abductActionBtn)
aStroke.Color = Color3.fromRGB(255, 110, 170)
aStroke.Thickness = 1.2

local autoAbductToggleBtn = Instance.new("TextButton", tabAbductContainer)
autoAbductToggleBtn.Size = UDim2.new(1, 0, 0, 28)
autoAbductToggleBtn.Position = UDim2.new(0, 0, 0, 140)
autoAbductToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 45, 62)
autoAbductToggleBtn.Text = "⚡ ดูดคนอัตโนมัติเมื่อเดินเข้าใกล้: ปิด"
autoAbductToggleBtn.TextColor3 = Color3.fromRGB(200, 205, 220)
autoAbductToggleBtn.Font = Enum.Font.GothamBold
autoAbductToggleBtn.TextSize = 10
Instance.new("UICorner", autoAbductToggleBtn).CornerRadius = UDim.new(0, 6)

autoAbductToggleBtn.MouseButton1Click:Connect(function()
    isAutoAbduct = not isAutoAbduct
    if isAutoAbduct then
        autoAbductToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 130, 80)
        autoAbductToggleBtn.Text = "⚡ ดูดคนอัตโนมัติเมื่อเดินเข้าใกล้: เปิด"
        autoAbductToggleBtn.TextColor3 = Color3.new(1, 1, 1)
    else
        autoAbductToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 45, 62)
        autoAbductToggleBtn.Text = "⚡ ดูดคนอัตโนมัติเมื่อเดินเข้าใกล้: ปิด"
        autoAbductToggleBtn.TextColor3 = Color3.fromRGB(200, 205, 220)
    end
end)

local function isPlayerInCage(p)
    if not p or not p.Character then return false end
    local pChar = p.Character
    local pHrp = pChar:FindFirstChild("HumanoidRootPart")

    for _, item in ipairs(trackedProps) do
        if item.model and item.model.Parent then
            local seat = item.model:FindFirstChildWhichIsA("Seat", true)
            if seat and seat.Occupant and seat.Occupant.Parent == pChar then
                return true
            end
        end
    end

    if pHrp and clusterPos and clusterPos.Magnitude > 1 then
        local dist = (pHrp.Position - clusterPos).Magnitude
        if dist < 5.5 then
            return true
        end
    end

    return false
end

local function isPropOccupied(item)
    if not item or not item.model or not item.model.Parent then return false end
    local seat = item.model:FindFirstChildWhichIsA("Seat", true)
    if seat and seat.Occupant and seat.Occupant.Parent and seat.Occupant.Parent ~= lp.Character then
        return true
    end
    return false
end

local function performAbduct()
    if isAbducting then return end
    if isExploding and type(stopPropExplode) == "function" then
        stopPropExplode(false)
    end
    isAbducting = true

    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        abductActionBtn.Text = "❌ ไม่พบตัวละครของคุณ"
        task.wait(1.5)
        abductActionBtn.Text = "🧲 ดึงคนใกล้ที่สุด (สูงสุด 4 คน) มาขังในกรงทันที!"
        isAbducting = false
        return
    end

    if #trackedProps == 0 then bindAllProps(not isFoldedMode) end
    if #trackedProps == 0 then
        abductActionBtn.Text = "❌ ไม่มี Prop ในเกม (กรุณากดสร้างกรงก่อน)"
        task.wait(1.5)
        abductActionBtn.Text = "🧲 ดึงคนใกล้ที่สุด (สูงสุด 4 คน) มาขังในกรงทันที!"
        isAbducting = false
        return
    end

    local homeCF = clusterCFrame
    if not homeCF or homeCF.Position.Magnitude < 1 then
        homeCF = hrp.CFrame * CFrame.new(0, 0, -6)
        clusterCFrame = homeCF
        clusterPos = homeCF.Position
    end

    local freeProps = {}
    for _, item in ipairs(trackedProps) do
        if not isPropOccupied(item) then
            table.insert(freeProps, item)
        end
    end

    if #freeProps == 0 then
        abductActionBtn.Text = "❌ กรงเต็มแล้ว! ทุกเบาะมีคนนั่งหมดแล้ว"
        abductActionBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 50)
        task.wait(2)
        abductActionBtn.Text = "🧲 ดึงคนใกล้ที่สุด (สูงสุด 4 คน) มาขังในกรงทันที!"
        abductActionBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 110)
        isAbducting = false
        return
    end

    local refPos = homeCF.Position
    local candidates = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local pChar = p.Character
            local pHrp = pChar.HumanoidRootPart
            local pHum = pChar:FindFirstChildOfClass("Humanoid")
            if pHum and pHum.Health > 0 and not isPlayerInCage(p) then
                local dist = (pHrp.Position - refPos).Magnitude
                if dist <= abductRange then
                    table.insert(candidates, {player = p, char = pChar, hrp = pHrp, dist = dist})
                end
            end
        end
    end

    if #candidates == 0 then
        abductActionBtn.Text = string.format("❌ ไม่พบใครนอกกรงในระยะ %d studs!", abductRange)
        abductActionBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 70)
        task.wait(1.5)
        abductActionBtn.Text = "🧲 ดึงคนใกล้ที่สุด (สูงสุด 4 คน) มาขังในกรงทันที!"
        abductActionBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 110)
        isAbducting = false
        return
    end

    table.sort(candidates, function(a, b) return a.dist < b.dist end)

    local maxTargets = math.min(4, #freeProps, #candidates)
    local targets = {}
    local targetNames = {}
    for i = 1, maxTargets do
        table.insert(targets, candidates[i])
        table.insert(targetNames, candidates[i].player.DisplayName)
    end
    local namesStr = table.concat(targetNames, ", ")

    abductActionBtn.Text = string.format("🚀 ปล่อยเบาะว่างไปดึง %d คน (%s)...", #targets, namesStr)
    abductActionBtn.BackgroundColor3 = Color3.fromRGB(220, 110, 30)

    local assignedGrabs = {}
    local usedFreeProps = {}

    if #targets == 1 and #freeProps >= 4 then
        local t = targets[1]
        local _, tYaw, _ = t.hrp.CFrame:ToEulerAnglesYXZ()
        local tRootCF = CFrame.new(t.hrp.Position) * CFrame.Angles(0, tYaw, 0)
        table.insert(assignedGrabs, {item = freeProps[1], targetPropCF = tRootCF * CFrame.new(0, -1.0, 0)})
        table.insert(assignedGrabs, {item = freeProps[2], targetPropCF = tRootCF * CFrame.new(0, 0.4, 1.45) * CFrame.Angles(0, math.rad(90), math.rad(-90))})
        table.insert(assignedGrabs, {item = freeProps[3], targetPropCF = tRootCF * CFrame.new(0, 0.4, -1.45) * CFrame.Angles(0, math.rad(-90), math.rad(-90))})
        table.insert(assignedGrabs, {item = freeProps[4], targetPropCF = tRootCF * CFrame.new(0, 2.0, 0) * CFrame.Angles(0, 0, math.rad(180))})
        for i = 1, 4 do usedFreeProps[freeProps[i]] = true end
    elseif #targets == 2 and #freeProps >= 4 then
        local t1, t2 = targets[1], targets[2]
        local _, y1, _ = t1.hrp.CFrame:ToEulerAnglesYXZ()
        local _, y2, _ = t2.hrp.CFrame:ToEulerAnglesYXZ()
        local r1 = CFrame.new(t1.hrp.Position) * CFrame.Angles(0, y1, 0)
        local r2 = CFrame.new(t2.hrp.Position) * CFrame.Angles(0, y2, 0)
        table.insert(assignedGrabs, {item = freeProps[1], targetPropCF = r1 * CFrame.new(0, -1.0, 0)})
        table.insert(assignedGrabs, {item = freeProps[2], targetPropCF = r1 * CFrame.new(0, 0.4, 1.45) * CFrame.Angles(0, math.rad(90), math.rad(-90))})
        table.insert(assignedGrabs, {item = freeProps[3], targetPropCF = r2 * CFrame.new(0, -1.0, 0)})
        table.insert(assignedGrabs, {item = freeProps[4], targetPropCF = r2 * CFrame.new(0, 0.4, 1.45) * CFrame.Angles(0, math.rad(90), math.rad(-90))})
        for i = 1, 4 do usedFreeProps[freeProps[i]] = true end
    else
        for idx, t in ipairs(targets) do
            local item = freeProps[idx]
            local _, tYaw, _ = t.hrp.CFrame:ToEulerAnglesYXZ()
            local seatCF = CFrame.new(t.hrp.Position) * CFrame.Angles(0, tYaw, 0) * CFrame.new(0, -1.0, 0)
            table.insert(assignedGrabs, {item = item, targetPropCF = seatCF})
            usedFreeProps[item] = true
        end
    end

    for i, item in ipairs(trackedProps) do
        if not usedFreeProps[item] then
            if item.model and item.setCF then
                local partCF = homeCF * getItemRelCF(item, i)
                pcall(function() item.model:PivotTo(partCF) end)
                safeInvokeSetCF(item.setCF, partCF)
            end
        end
    end

    for _, grab in ipairs(assignedGrabs) do
        local item = grab.item
        local tCF = grab.targetPropCF
        if item.model and item.setCF then
            pcall(function() item.model:PivotTo(tCF) end)
            safeInvokeSetCF(item.setCF, tCF)
        end
    end

    local seatWaitStart = os.clock()
    while os.clock() - seatWaitStart < 0.16 do
        local allSeated = true
        for _, grab in ipairs(assignedGrabs) do
            local seat = grab.item.model and grab.item.model:FindFirstChildWhichIsA("Seat", true)
            if not (seat and seat.Occupant) then
                allSeated = false
                break
            end
        end
        if allSeated then break end
        RunService.Heartbeat:Wait()
    end

    abductActionBtn.Text = string.format("🧲 ดึง %d คนเข้ามารวมกับกรงหลัก...", #targets)
    local steps = 4
    for s = 1, steps do
        local alpha = s / steps
        for idx, grab in ipairs(assignedGrabs) do
            local item = grab.item
            local startCF = grab.targetPropCF
            local dockCF = homeCF * getItemRelCF(item, idx)
            if item and item.model and item.setCF then
                local currentCF = startCF:Lerp(dockCF, alpha)
                pcall(function() item.model:PivotTo(currentCF) end)
                safeInvokeSetCF(item.setCF, currentCF)
            end
        end
        task.wait(0.02)
    end

    if not isBallMode then
        moveClusterTo(homeCF)
    end

    abductActionBtn.Text = string.format("✔ ดึง %d คนขังในกรงสำเร็จ!", #targets)
    abductActionBtn.BackgroundColor3 = Color3.fromRGB(35, 150, 85)
    isAbducting = false

    task.delay(1.0, function()
        if not isAbducting then
            abductActionBtn.Text = "🧲 ดึงคนใกล้ที่สุด (สูงสุด 4 คน) มาขังในกรงทันที!"
            abductActionBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 110)
        end
    end)
end

abductActionBtn.MouseButton1Click:Connect(performAbduct)

trackConn(RunService.Heartbeat:Connect(function()
    if os.clock() - lastAbductCheck > 0.04 then
        lastAbductCheck = os.clock()
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local refPos = (clusterPos and clusterPos.Magnitude > 1) and clusterPos or hrp.Position
            local candidates = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    local pChar = p.Character
                    local pHrp = pChar.HumanoidRootPart
                    local pHum = pChar:FindFirstChildOfClass("Humanoid")
                    if pHum and pHum.Health > 0 and not isPlayerInCage(p) then
                        local dist = (pHrp.Position - refPos).Magnitude
                        if dist <= abductRange then
                            table.insert(candidates, {player = p, dist = dist})
                        end
                    end
                end
            end

            table.sort(candidates, function(a, b) return a.dist < b.dist end)

            if #candidates > 0 then
                local nearest = candidates[1]
                local targetCount = math.min(#candidates, 4)
                nearestTrackerLabel.Text = string.format("🔍 พบ %d คนนอกกรง (ใกล้สุด: %s - %.1f studs)", targetCount, nearest.player.DisplayName, nearest.dist)
                nearestTrackerLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
                if isAutoAbduct and not isAbducting then
                    task.spawn(performAbduct)
                end
            else
                nearestTrackerLabel.Text = "🔍 ตรวจจับคนนอกกรง: ไม่พบเป้าหมายใหม่ในระยะ"
                nearestTrackerLabel.TextColor3 = Color3.fromRGB(160, 170, 185)
            end
        end
    end
end))

-- ========================================================
-- [[ TAB 3: TROLL & CHAOS SUITE (วาร์ปลงสุดขอบโลก) ]]
-- ========================================================
performVoidDrop = function(victimName, directVictimChar, directVictimPlayer)
    if isVoidingTrap then return end
    if isExploding and type(stopPropExplode) == "function" then
        stopPropExplode(false)
    end
    isVoidingTrap = true

    if #trackedProps == 0 then bindAllProps(not isFoldedMode) end
    if #trackedProps == 0 then isVoidingTrap = false; return end

    local savedCF = clusterCFrame

    local ok, err = pcall(function()
        local victimList = {}
        for _, item in ipairs(trackedProps) do
            if item.model and item.model.Parent then
                local seat = item.model:FindFirstChildWhichIsA("Seat", true)
                if seat and seat.Occupant and seat.Occupant.Parent and seat.Occupant.Parent ~= lp.Character then
                    local vChar = seat.Occupant.Parent
                    local vPlayer = Players:GetPlayerFromCharacter(vChar)
                    local exists = false
                    for _, v in ipairs(victimList) do
                        if v.char == vChar then exists = true; break end
                    end
                    if not exists then
                        table.insert(victimList, {
                            char = vChar,
                            player = vPlayer,
                            hum = vChar:FindFirstChildOfClass("Humanoid"),
                            name = vPlayer and vPlayer.DisplayName or vChar.Name
                        })
                    end
                end
            end
        end

        if #victimList == 0 and directVictimChar then
            table.insert(victimList, {
                char = directVictimChar,
                player = directVictimPlayer or Players:GetPlayerFromCharacter(directVictimChar),
                hum = directVictimChar:FindFirstChildOfClass("Humanoid"),
                name = (directVictimPlayer and directVictimPlayer.DisplayName) or (directVictimChar and directVictimChar.Name) or (victimName or "เหยื่อ")
            })
        end

        local victimNames = {}
        for _, v in ipairs(victimList) do
            table.insert(victimNames, v.name)
        end
        local victimNamesStr = #victimNames > 0 and table.concat(victimNames, ", ") or (victimName or "เหยื่อ")

        dragBanner.BackgroundColor3 = Color3.fromRGB(225, 40, 40)
        bannerLabel.Text = "⚡ วาร์ปสู่ขอบแมพ (Y: -480) เป้าหมาย: " .. victimNamesStr
        dragBanner.Visible = true

        local edgePos = Vector3.new(savedCF.Position.X, -480, savedCF.Position.Z)
        local edgeCF = CFrame.new(edgePos) * savedCF.Rotation
        if not isBallMode then
            moveClusterTo(edgeCF)
        end
        task.wait(0.2)

        bannerLabel.Text = "🌪️ ทิ้งดิ่งสู่ก้นบึ้งนรก 2 วินาที (-4,000 Studs)... เหยื่อ: " .. victimNamesStr

        local plungeDuration = 2.0
        local plungeStart = os.clock()
        local startY = -480
        local targetY = -4000
        local ejected = false
        local lastSync = 0

        while true do
            local elapsed = os.clock() - plungeStart
            local progress = math.min(elapsed / plungeDuration, 1.0)
            local eased = progress * progress
            local currentY = startY + (targetY - startY) * eased
            local tilt = savedCF.Rotation * CFrame.Angles(math.rad(180 * progress), 0, 0)
            local curCF = CFrame.new(savedCF.Position.X, currentY, savedCF.Position.Z) * tilt

            clusterCFrame = curCF
            clusterPos = curCF.Position
            if not isBallMode then
                updateClusterVisuals(curCF)
            end

            if not isBallMode and os.clock() - lastSync > 0.08 then
                lastSync = os.clock()
                for i, item in ipairs(trackedProps) do
                    if item.setCF and item.setCF.Parent then
                        safeInvokeSetCF(item.setCF, curCF * getItemRelCF(item, i))
                    end
                end
            end

            if progress >= 0.5 and not ejected then
                ejected = true
                for _, item in ipairs(trackedProps) do
                    if item.model then
                        local seat = item.model:FindFirstChildWhichIsA("Seat", true)
                        if seat then seat.Disabled = true end
                    end
                end
            end

            if progress >= 1.0 then break end
            RunService.Heartbeat:Wait()
        end

        task.wait(0.15)
        for _, item in ipairs(trackedProps) do
            if item.model then
                local seat = item.model:FindFirstChildWhichIsA("Seat", true)
                if seat then seat.Disabled = false end
            end
        end

        bannerLabel.Text = "🔍 กำลังตรวจจับสถานะชีพจรของเหยื่อทั้งหมด..."
        local checkStart = os.clock()
        local allDead = false

        while os.clock() - checkStart < 3.5 do
            local deadCount = 0
            for _, v in ipairs(victimList) do
                local isDead = false
                if v.hum and (v.hum.Health <= 0 or v.hum:GetState() == Enum.HumanoidStateType.Dead) then
                    isDead = true
                elseif not v.char or not v.char.Parent then
                    isDead = true
                elseif v.player and v.player.Character and v.player.Character ~= v.char then
                    isDead = true
                elseif v.char and (not v.char:FindFirstChild("HumanoidRootPart") or not v.char:FindFirstChild("Head")) then
                    isDead = true
                end
                if isDead then deadCount = deadCount + 1 end
            end

            if #victimList > 0 and deadCount >= #victimList then
                allDead = true
                break
            end
            task.wait(0.1)
        end

        if allDead and #victimList > 0 then
            bannerLabel.Text = "💀 ยืนยันการตาย 100%! เหยื่อทั้ง " .. #victimList .. " คน สิ้นชีพสู่ก้นบึ้งเรียบร้อย!"
            dragBanner.BackgroundColor3 = Color3.fromRGB(170, 20, 20)
        else
            bannerLabel.Text = "✔ ดรอปลงสุดขอบโลกเรียบร้อย! กำลังนำกรงกลับ..."
            dragBanner.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
        end
    end)

    if not ok then
        warn("performVoidDrop error:", err)
    end

    if savedCF then
        pcall(function()
            clusterCFrame = savedCF
            clusterPos = savedCF.Position
            if not isBallMode then
                moveClusterTo(savedCF)
                task.wait(0.1)
                syncClusterToNetwork(savedCF)
            end
        end)
    end

    task.delay(3.0, function()
        dragBanner.Visible = false
        dragBanner.BackgroundColor3 = Color3.fromRGB(20, 85, 175)
        bannerLabel.Text = "🖐️ โหมดลากอิสระ: แตะ/ลากบนจอเพื่อย้ายกรง"
    end)

    isVoidingTrap = false
end

local autoVoidToggleBtn = Instance.new("TextButton", tabTrollContainer)
autoVoidToggleBtn.Size = UDim2.new(1, -6, 0, 42)
autoVoidToggleBtn.BackgroundColor3 = Color3.fromRGB(150, 30, 45)
autoVoidToggleBtn.Text = "⚡ วาร์ปลงสุดขอบโลกเมื่อมีคนนั่ง: เปิด"
autoVoidToggleBtn.TextColor3 = Color3.new(1, 1, 1)
autoVoidToggleBtn.Font = Enum.Font.GothamBold
autoVoidToggleBtn.TextSize = 11
Instance.new("UICorner", autoVoidToggleBtn).CornerRadius = UDim.new(0, 8)
local avStroke = Instance.new("UIStroke", autoVoidToggleBtn)
avStroke.Color = Color3.fromRGB(240, 80, 100)
avStroke.Thickness = 1.2

autoVoidToggleBtn.MouseButton1Click:Connect(function()
    isAutoVoidOnSit = not isAutoVoidOnSit
    if isAutoVoidOnSit then
        autoVoidToggleBtn.BackgroundColor3 = Color3.fromRGB(150, 30, 45)
        autoVoidToggleBtn.Text = "⚡ วาร์ปลงสุดขอบโลกเมื่อมีคนนั่ง: เปิด"
        avStroke.Color = Color3.fromRGB(240, 80, 100)
    else
        autoVoidToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 58)
        autoVoidToggleBtn.Text = "⚡ วาร์ปลงสุดขอบโลกเมื่อมีคนนั่ง: ปิด"
        avStroke.Color = Color3.fromRGB(60, 68, 88)
    end
end)

local dropVoidBtn = Instance.new("TextButton", tabTrollContainer)
dropVoidBtn.Size = UDim2.new(1, -6, 0, 52)
dropVoidBtn.BackgroundColor3 = Color3.fromRGB(195, 30, 45)
dropVoidBtn.Text = "🕳️ วาร์ปไปขอบแมพ + ทิ้งดิ่ง 2 วิสู่ก้นบึ้ง (Void Drop)"
dropVoidBtn.TextColor3 = Color3.new(1, 1, 1)
dropVoidBtn.Font = Enum.Font.GothamBold
dropVoidBtn.TextSize = 12
Instance.new("UICorner", dropVoidBtn).CornerRadius = UDim.new(0, 8)
local dvStroke = Instance.new("UIStroke", dropVoidBtn)
dvStroke.Color = Color3.fromRGB(255, 90, 110)
dvStroke.Thickness = 1.4

dropVoidBtn.MouseButton1Click:Connect(function()
    task.spawn(function() performVoidDrop(nil) end)
end)

local voidInfoCard = Instance.new("Frame", tabTrollContainer)
voidInfoCard.Size = UDim2.new(1, -6, 0, 95)
voidInfoCard.BackgroundColor3 = Color3.fromRGB(25, 28, 40)
Instance.new("UICorner", voidInfoCard).CornerRadius = UDim.new(0, 8)
local viStroke = Instance.new("UIStroke", voidInfoCard)
viStroke.Color = Color3.fromRGB(55, 65, 90)
viStroke.Thickness = 1

local voidInfoLabel = Instance.new("TextLabel", voidInfoCard)
voidInfoLabel.Size = UDim2.new(1, -16, 1, -12)
voidInfoLabel.Position = UDim2.new(0, 8, 0, 6)
voidInfoLabel.BackgroundTransparency = 1
voidInfoLabel.Text = "💀 ขั้นตอนการทำงาน:\n1. วาร์ปกรงลงสู่ขอบแมพใต้ดิน (Y = -480)\n2. ทิ้งดิ่งเร็วๆ 2 วินาที สู่ก้นบึ้งนรก (-4,000 Studs)\n3. ดีดเบาะส่งเหยื่อร่วงสู่ Void ลับแล\n4. ตรวจชีพจรยืนยันการตาย 100% แล้วนำกรงกลับ"
voidInfoLabel.TextColor3 = Color3.fromRGB(180, 195, 220)
voidInfoLabel.Font = Enum.Font.GothamMedium
voidInfoLabel.TextSize = 10
voidInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
voidInfoLabel.TextYAlignment = Enum.TextYAlignment.Top

tabTrollContainer.CanvasSize = UDim2.new(0, 0, 0, 210)

local lastSeatCheck = 0
trackConn(RunService.Heartbeat:Connect(function()
    if isAutoVoidOnSit and not isVoidingTrap and not isAbducting and os.clock() - lastSeatCheck > 0.03 then
        lastSeatCheck = os.clock()
        if #trackedProps > 0 then
            for _, item in ipairs(trackedProps) do
                if item.model and item.model.Parent then
                    local seat = item.model:FindFirstChildWhichIsA("Seat", true)
                    if seat and seat.Occupant and seat.Occupant.Parent and seat.Occupant.Parent ~= lp.Character then
                        local victimChar = seat.Occupant.Parent
                        local victimP = Players:GetPlayerFromCharacter(victimChar)
                        local victimName = victimP and victimP.DisplayName or victimChar.Name
                        task.spawn(function()
                            performVoidDrop(victimName, victimChar, victimP)
                        end)
                        break
                    end
                end
            end
        end
    end
end))

-- ========================================================
-- [[ TAB 4: PLAYER FOLLOW (TARGET SELECTION) ]]
-- ========================================================
local targetCard = Instance.new("Frame", tabFollowContainer)
targetCard.Size = UDim2.new(1, 0, 0, 28)
targetCard.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
Instance.new("UICorner", targetCard).CornerRadius = UDim.new(0, 7)

local targetLabel = Instance.new("TextLabel", targetCard)
targetLabel.Size = UDim2.new(1, -12, 1, 0)
targetLabel.Position = UDim2.new(0, 8, 0, 0)
targetLabel.BackgroundTransparency = 1
targetLabel.Text = "🎯 เป้าหมาย: " .. targetPlayer.DisplayName .. " (@" .. targetPlayer.Name .. ")"
targetLabel.TextColor3 = Color3.fromRGB(140, 215, 255)
targetLabel.Font = Enum.Font.GothamMedium
targetLabel.TextSize = 11
targetLabel.TextXAlignment = Enum.TextXAlignment.Left

local followBtn = Instance.new("TextButton", tabFollowContainer)
followBtn.Size = UDim2.new(1, 0, 0, 32)
followBtn.Position = UDim2.new(0, 0, 0, 32)
followBtn.BackgroundColor3 = Color3.fromRGB(40, 165, 95)
followBtn.Text = "▶ เริ่มติดตามเป้าหมาย"
followBtn.TextColor3 = Color3.new(1, 1, 1)
followBtn.Font = Enum.Font.GothamBold
followBtn.TextSize = 11
Instance.new("UICorner", followBtn).CornerRadius = UDim.new(0, 7)

local settingsRow = Instance.new("Frame", tabFollowContainer)
settingsRow.Size = UDim2.new(1, 0, 0, 26)
settingsRow.Position = UDim2.new(0, 0, 0, 68)
settingsRow.BackgroundTransparency = 1

local offsetLabel = Instance.new("TextLabel", settingsRow)
offsetLabel.Size = UDim2.new(0, 105, 1, 0)
offsetLabel.BackgroundTransparency = 1
offsetLabel.Text = "ความสูง (Y): +0.0"
offsetLabel.TextColor3 = Color3.fromRGB(200, 205, 220)
offsetLabel.Font = Enum.Font.Gotham
offsetLabel.TextSize = 11
offsetLabel.TextXAlignment = Enum.TextXAlignment.Left

local downOffsetBtn = Instance.new("TextButton", settingsRow)
downOffsetBtn.Size = UDim2.new(0, 32, 0, 22); downOffsetBtn.Position = UDim2.new(0, 108, 0, 2)
downOffsetBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 70); downOffsetBtn.Text = "▼ -1"
downOffsetBtn.TextColor3 = Color3.new(1, 1, 1); downOffsetBtn.Font = Enum.Font.GothamBold; downOffsetBtn.TextSize = 9
Instance.new("UICorner", downOffsetBtn).CornerRadius = UDim.new(0, 4)

local upOffsetBtn = Instance.new("TextButton", settingsRow)
upOffsetBtn.Size = UDim2.new(0, 32, 0, 22); upOffsetBtn.Position = UDim2.new(0, 144, 0, 2)
upOffsetBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 70); upOffsetBtn.Text = "▲ +1"
upOffsetBtn.TextColor3 = Color3.new(1, 1, 1); upOffsetBtn.Font = Enum.Font.GothamBold; upOffsetBtn.TextSize = 9
Instance.new("UICorner", upOffsetBtn).CornerRadius = UDim.new(0, 4)

local rotBtn = Instance.new("TextButton", settingsRow)
rotBtn.Size = UDim2.new(1, -182, 0, 22); rotBtn.Position = UDim2.new(0, 182, 0, 2)
rotBtn.BackgroundColor3 = Color3.fromRGB(38, 42, 58); rotBtn.Text = "🔄 หมุนตาม: เปิด"
rotBtn.TextColor3 = Color3.fromRGB(150, 255, 180); rotBtn.Font = Enum.Font.GothamBold; rotBtn.TextSize = 9
Instance.new("UICorner", rotBtn).CornerRadius = UDim.new(0, 4)

local searchBox = Instance.new("TextBox", tabFollowContainer)
searchBox.Size = UDim2.new(1, 0, 0, 24)
searchBox.Position = UDim2.new(0, 0, 0, 98)
searchBox.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
searchBox.PlaceholderText = "🔍 ค้นหาผู้เล่นเพื่อติดตาม..."
searchBox.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
searchBox.Text = ""
searchBox.TextColor3 = Color3.new(1, 1, 1)
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 11
Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 5)

local playerScroll = Instance.new("ScrollingFrame", tabFollowContainer)
playerScroll.Size = UDim2.new(1, 0, 1, -128)
playerScroll.Position = UDim2.new(0, 0, 0, 128)
playerScroll.BackgroundColor3 = Color3.fromRGB(16, 17, 24)
playerScroll.BorderSizePixel = 0
playerScroll.ScrollBarThickness = 4
Instance.new("UICorner", playerScroll).CornerRadius = UDim.new(0, 6)
local pListLayout = Instance.new("UIListLayout", playerScroll)
pListLayout.Padding = UDim.new(0, 3)
local pListPad = Instance.new("UIPadding", playerScroll)
pListPad.PaddingTop = UDim.new(0, 3); pListPad.PaddingLeft = UDim.new(0, 3); pListPad.PaddingRight = UDim.new(0, 3)

local function refreshPlayerList()
    for _, child in ipairs(playerScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    local filter = searchBox.Text:lower()
    local players = Players:GetPlayers()
    table.sort(players, function(a, b)
        if a == lp then return true elseif b == lp then return false end
        return a.Name:lower() < b.Name:lower()
    end)
    local count = 0
    for _, p in ipairs(players) do
        local dName, uName = p.DisplayName, p.Name
        if filter == "" or dName:lower():find(filter) or uName:lower():find(filter) then
            count = count + 1
            local btn = Instance.new("TextButton", playerScroll)
            btn.Size = UDim2.new(1, -4, 0, 24)
            btn.BackgroundColor3 = (p == targetPlayer) and Color3.fromRGB(45, 90, 150) or Color3.fromRGB(26, 28, 38)
            btn.Text = (p == lp and "⭐ " or "  ") .. dName .. " (@" .. uName .. ")"
            btn.TextColor3 = (p == targetPlayer) and Color3.new(1, 1, 1) or Color3.fromRGB(200, 205, 220)
            btn.Font = Enum.Font.GothamMedium
            btn.TextSize = 11
            btn.TextXAlignment = Enum.TextXAlignment.Left
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
            btn.MouseButton1Click:Connect(function()
                targetPlayer = p
                targetLabel.Text = "🎯 เป้าหมาย: " .. p.DisplayName .. " (@" .. p.Name .. ")"
                refreshPlayerList()
            end)
        end
    end
    playerScroll.CanvasSize = UDim2.new(0, 0, 0, count * 28 + 6)
end

searchBox:GetPropertyChangedSignal("Text"):Connect(refreshPlayerList)
trackConn(Players.PlayerAdded:Connect(refreshPlayerList))
trackConn(Players.PlayerRemoving:Connect(refreshPlayerList))
refreshPlayerList()

local function startFollowing()
    if isFollowing then return end
    if isExploding and type(stopPropExplode) == "function" then
        stopPropExplode(false)
    end
    isFollowing = true
    followBtn.BackgroundColor3 = Color3.fromRGB(215, 55, 65)
    followBtn.Text = "⏹ หยุดติดตาม"

    if localRenderConn then
        localRenderConn:Disconnect()
        localRenderConn = nil
    end

    localRenderConn = RunService.RenderStepped:Connect(function()
        if not isFollowing then return end
        local activeTarget = targetPlayer or lp
        if activeTarget and activeTarget.Character then
            local root = activeTarget.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local targetPos = root.Position + Vector3.new(0, heightOffset, 0)
                local _, yaw, _ = root.CFrame:ToEulerAnglesYXZ()
                local targetRot = rotateWithPlayer and CFrame.Angles(0, yaw, 0) or CFrame.new()
                local targetRootCF = CFrame.new(targetPos) * targetRot

                clusterCFrame = targetRootCF
                clusterPos = targetPos
                clusterYaw = yaw
                if not isBallMode then
                    updateClusterVisuals(targetRootCF)
                end
            end
        end
    end)

    networkThread = task.spawn(function()
        while isFollowing do
            local activeTarget = targetPlayer or lp
            if not isBallMode and activeTarget and activeTarget.Character then
                local root = activeTarget.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local targetPos = root.Position + Vector3.new(0, heightOffset, 0)
                    local _, yaw, _ = root.CFrame:ToEulerAnglesYXZ()
                    local targetRot = rotateWithPlayer and CFrame.Angles(0, yaw, 0) or CFrame.new()
                    local targetRootCF = CFrame.new(targetPos) * targetRot

                    for i, item in ipairs(trackedProps) do
                        if item.setCF and item.setCF.Parent then
                            safeInvokeSetCF(item.setCF, targetRootCF * getItemRelCF(item, i))
                        end
                    end
                end
            end
            task.wait(0.06)
        end
    end)
end

local function stopFollowing()
    isFollowing = false
    followBtn.BackgroundColor3 = Color3.fromRGB(40, 165, 95)
    followBtn.Text = "▶ เริ่มติดตามเป้าหมาย"
    if localRenderConn then
        localRenderConn:Disconnect()
        localRenderConn = nil
    end
    networkThread = nil
end

followBtn.MouseButton1Click:Connect(function()
    if isFollowing then
        stopFollowing()
    else
        if #trackedProps == 0 then bindAllProps(not isFoldedMode) end
        startFollowing()
    end
end)

upOffsetBtn.MouseButton1Click:Connect(function()
    heightOffset = heightOffset + 0.5
    offsetLabel.Text = string.format("ความสูง (Y): %+.1f", heightOffset)
end)

downOffsetBtn.MouseButton1Click:Connect(function()
    heightOffset = heightOffset - 0.5
    offsetLabel.Text = string.format("ความสูง (Y): %+.1f", heightOffset)
end)

rotBtn.MouseButton1Click:Connect(function()
    rotateWithPlayer = not rotateWithPlayer
    rotBtn.Text = rotateWithPlayer and "🔄 หมุนตาม: เปิด" or "🔒 หมุนตาม: ปิด"
    rotBtn.TextColor3 = rotateWithPlayer and Color3.fromRGB(150, 255, 180) or Color3.fromRGB(255, 180, 150)
end)

-- [[ AUTO-BUILD (UP TO 15 PROPS) & FOLD MODE ]]
local isBuilding = false
local function autoBuildCage()
    if isBuilding then return end
    if isExploding and type(stopPropExplode) == "function" then
        stopPropExplode(false)
    end
    isBuilding = true
    buildBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
    buildBtn.Text = "⏳ เตรียมของ..."

    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        buildBtn.Text = "❌ ไม่พบตัวละคร"
        task.wait(1.5)
        buildBtn.Text = "🔨 สร้าง 15 ชิ้น"
        buildBtn.BackgroundColor3 = Color3.fromRGB(125, 55, 215)
        isBuilding = false
        return
    end

    local props = getMyPropsList()
    if #props >= 15 then
        buildBtn.Text = "⏳ จัดทรงกรงเป๊ะ..."
        bindAllProps(not isFoldedMode)
        statusLabel.Text = "🔗 เชื่อมต่อ Prop: " .. #trackedProps .. " ชิ้น (กรงพร้อม)"
        local target = targetPlayer or lp
        local targetChar = (target and target.Character) or char
        local targetHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        if targetHrp then
            local targetPos = targetHrp.Position + Vector3.new(0, heightOffset, 0)
            local _, yaw, _ = targetHrp.CFrame:ToEulerAnglesYXZ()
            local targetRot = rotateWithPlayer and CFrame.Angles(0, yaw, 0) or CFrame.new()
            clusterPos = targetPos
            clusterCFrame = CFrame.new(targetPos) * targetRot
            if not isBallMode then
                moveClusterTo(clusterCFrame)
            end
        end
        buildBtn.Text = "✔ กรงพร้อม 15 ชิ้นแล้ว!"
        buildBtn.BackgroundColor3 = Color3.fromRGB(40, 175, 110)
        task.wait(1.5)
        buildBtn.Text = "🔨 สร้าง 15 ชิ้น"
        buildBtn.BackgroundColor3 = Color3.fromRGB(125, 55, 215)
        isBuilding = false
        return
    end

    local pm = lp.Backpack and lp.Backpack:FindFirstChild("PropMaker") or (char and char:FindFirstChild("PropMaker"))
    if not pm then
        buildBtn.Text = "⏳ เบิก PropMaker..."
        pcall(function()
            local re = game.ReplicatedStorage:FindFirstChild("RE")
            local t1 = re and re:FindFirstChild("1Too1l")
            if t1 then t1:InvokeServer("PickingTools", "PropMaker") end
        end)
        task.wait(0.35)
        pm = lp.Backpack and lp.Backpack:FindFirstChild("PropMaker") or (char and char:FindFirstChild("PropMaker"))
    end

    pcall(function()
        local re = game.ReplicatedStorage:FindFirstChild("RE")
        local c1 = re and re:FindFirstChild("1Clea1rTool1s")
        if c1 then c1:FireServer("RequestingPropFeatureName", "FloorCushion", "Decor") end
    end)
    task.wait(0.2)

    props = getMyPropsList()
    if #props == 0 and pm then
        buildBtn.Text = "⏳ วางชิ้นแรก..."
        pm.Parent = char
        task.wait(0.25)
        local tpm = pm:FindFirstChild("Tool_PropMake")
        local targetPart = workspace.Terrain
        local targetPos = hrp.Position + hrp.CFrame.LookVector * 5 + Vector3.new(0, -1, 0)
        if tpm then
            pcall(function() tpm:FireServer(targetPart, targetPos) end)
        end

        local waited = 0
        while #props == 0 and waited < 3 do
            task.wait(0.2)
            waited = waited + 0.2
            props = getMyPropsList()
        end

        if pm.Parent == char and lp:FindFirstChild("Backpack") then
            pm.Parent = lp.Backpack
        end
    end

    props = getMyPropsList()
    if #props == 0 then
        buildBtn.Text = "❌ ล้มเหลว (ลองกดล้างของ)"
        task.wait(2)
        buildBtn.Text = "🔨 สร้าง 15 ชิ้น"
        buildBtn.BackgroundColor3 = Color3.fromRGB(125, 55, 215)
        isBuilding = false
        return
    end

    local dups = 0
    while #props < 15 and #props > 0 and dups < 20 do
        buildBtn.Text = string.format("⏳ ปั๊ม (%d/15)...", #props)
        local p = props[1]
        local dup = p and p:FindFirstChild("DuplicateProp")
        if dup then
            pcall(function() dup:InvokeServer() end)
        end
        task.wait(0.18)
        props = getMyPropsList()
        dups = dups + 1
    end

    buildBtn.Text = "⏳ จัดทรงกรงเป๊ะ..."
    bindAllProps(not isFoldedMode)
    statusLabel.Text = "🔗 เชื่อมต่อ Prop: " .. #trackedProps .. " ชิ้น (กรงพร้อม)"

    local target = targetPlayer or lp
    local targetChar = (target and target.Character) or char
    local targetHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if targetHrp then
        local targetPos = targetHrp.Position + Vector3.new(0, heightOffset, 0)
        local _, yaw, _ = targetHrp.CFrame:ToEulerAnglesYXZ()
        local targetRot = rotateWithPlayer and CFrame.Angles(0, yaw, 0) or CFrame.new()
        clusterPos = targetPos
        clusterCFrame = CFrame.new(targetPos) * targetRot
        if not isBallMode then
            moveClusterTo(clusterCFrame)
        end
    end

    buildBtn.Text = "✔ สร้าง 15 ชิ้นสำเร็จ!"
    buildBtn.BackgroundColor3 = Color3.fromRGB(40, 175, 110)
    task.wait(2)
    buildBtn.Text = "🔨 สร้าง 15 ชิ้น"
    buildBtn.BackgroundColor3 = Color3.fromRGB(125, 55, 215)
    isBuilding = false
end

buildBtn.MouseButton1Click:Connect(function()
    task.spawn(autoBuildCage)
end)

clearBtn.MouseButton1Click:Connect(function()
    if isExploding and type(stopPropExplode) == "function" then
        stopPropExplode(false)
    end
    clearBtn.Text = "⏳ กำลังลบ..."
    local list = getMyPropsList()
    for _, p in ipairs(list) do
        local del = p and p:FindFirstChild("DeleteProp")
        if del then
            task.spawn(function() pcall(function() del:InvokeServer() end) end)
        end
    end
    pcall(function()
        local rems = game.ReplicatedStorage:FindFirstChild("Remotes")
        local delAll = rems and rems:FindFirstChild("PS_PropDeleteAll")
        if delAll then delAll:FireServer() end
    end)
    task.wait(0.6)
    trackedProps = {}
    isFoldedMode = false
    foldBtn.BackgroundColor3 = Color3.fromRGB(45, 110, 210)
    foldBtn.Text = "📥 พับเก็บ"
    statusLabel.Text = "🔗 เชื่อมต่อ Prop: 0 ชิ้น (ล้างแล้ว)"
    clearBtn.Text = "✔ ล้างหมดแล้ว"
    clearBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
    task.wait(1.5)
    clearBtn.Text = "🗑️ ล้างของ"
    clearBtn.BackgroundColor3 = Color3.fromRGB(180, 45, 55)
end)

foldBtn.MouseButton1Click:Connect(function()
    if isExploding and type(stopPropExplode) == "function" then
        stopPropExplode(false)
    end
    if #trackedProps == 0 then
        bindAllProps(true)
    end
    if #trackedProps == 0 then
        foldBtn.Text = "❌ ไม่มีของ"
        task.delay(1.2, function()
            foldBtn.Text = isFoldedMode and "📤 กางกรง" or "📥 พับเก็บ"
        end)
        return
    end

    isFoldedMode = not isFoldedMode

    if isFoldedMode then
        applyFoldedOffsets()
        foldBtn.BackgroundColor3 = Color3.fromRGB(40, 165, 105)
        foldBtn.Text = "📤 กางกรง"
        statusLabel.Text = "📥 โหมดพับเก็บ: รวมซ้อนกัน " .. #trackedProps .. " ชิ้น"
    else
        bindAllProps(true)
        foldBtn.BackgroundColor3 = Color3.fromRGB(45, 110, 210)
        foldBtn.Text = "📥 พับเก็บ"
        statusLabel.Text = "🔗 เชื่อมต่อ Prop: " .. #trackedProps .. " ชิ้น (ทรงกรง)"
    end

    local target = targetPlayer or lp
    if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
        local root = target.Character.HumanoidRootPart
        local targetPos = root.Position + Vector3.new(0, heightOffset, 0)
        local _, yaw, _ = root.CFrame:ToEulerAnglesYXZ()
        local targetRot = rotateWithPlayer and CFrame.Angles(0, yaw, 0) or CFrame.new()
        clusterPos = targetPos
        clusterCFrame = CFrame.new(targetPos) * targetRot
        if not isBallMode then
            moveClusterTo(clusterCFrame)
        end
    elseif not isBallMode then
        moveClusterTo(CFrame.new(clusterPos) * CFrame.Angles(0, clusterYaw, 0))
    end
end)

rescanBtn.MouseButton1Click:Connect(function()
    local count = bindAllProps(not isFoldedMode)
    statusLabel.Text = "🔗 เชื่อมต่อ Prop: " .. count .. " ชิ้น (ทั้งก้อน)"
    rescanBtn.Text = "✔ ครบแล้ว"
    task.delay(1.2, function() rescanBtn.Text = "🔄 สแกนใหม่" end)
end)

-- [[ Window Controls ]]
local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        content.Visible = false
        mainFrame.Size = UDim2.new(0, baseWidth, 0, 36)
        minBtn.Text = "＋"
    else
        content.Visible = true
        mainFrame.Size = UDim2.new(0, baseWidth, 0, baseHeight)
        minBtn.Text = "—"
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
    miniBtn.Text = "📦 เมนูกรง"
    mtStroke.Color = Color3.fromRGB(65, 120, 225)
end)
