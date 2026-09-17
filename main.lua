local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()

getgenv().killerEspEnabled = false
getgenv().autoParryEnabled = false
getgenv().autoParryDelay = 0.1
getgenv().autoParryRange = 8

if getgenv().killerEspConnection then
    getgenv().killerEspConnection:Disconnect()
    getgenv().killerEspConnection = nil
end

local clonerefFunction = cloneref or function(instance) return instance end

local playersService = clonerefFunction(game:GetService("Players"))
local runService = clonerefFunction(game:GetService("RunService"))
local collectionService = clonerefFunction(game:GetService("CollectionService"))
local replicatedStorage = clonerefFunction(game:GetService("ReplicatedStorage"))

local localPlayer = clonerefFunction(playersService.LocalPlayer)
local currentCamera = workspace.CurrentCamera

local Window = Fluent:CreateWindow({
    Title = "Violent",
    SubTitle = "by Xin",
    Search = true,
    Icon = "skull",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "eye" })
}

local Options = Fluent.Options

if not Drawing or not Drawing.new then
    warn("Executor does not support Drawing library")
end

local espDrawings = {}
local firedParryTracks = {}
local lastParryFireTime = 0
local parryFireDebounce = 1
local autoParryEvent = nil

task.spawn(function()
    local remotesFolder = replicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then return end
    local itemsFolder = remotesFolder:WaitForChild("Items", 10)
    if not itemsFolder then return end
    local daggerFolder = itemsFolder:WaitForChild("Parrying Dagger", 10)
    if not daggerFolder then return end
    autoParryEvent = daggerFolder:WaitForChild("parry", 10)
end)

local function safeRemove(drawingObject)
    if drawingObject then
        pcall(function()
            drawingObject:Remove()
        end)
    end
end

local function hideDrawingSet(drawingSet)
    drawingSet.boxOutline.Visible = false
    drawingSet.box.Visible = false
    drawingSet.healthBarBackground.Visible = false
    drawingSet.healthBarFill.Visible = false
    drawingSet.nameText.Visible = false
    drawingSet.distanceText.Visible = false
    for _, skeletonLine in ipairs(drawingSet.skeletonLines) do
        skeletonLine.Visible = false
    end
end

local function clearAllDrawings()
    for killerInstance, drawingSet in pairs(espDrawings) do
        safeRemove(drawingSet.boxOutline)
        safeRemove(drawingSet.box)
        safeRemove(drawingSet.healthBarBackground)
        safeRemove(drawingSet.healthBarFill)
        safeRemove(drawingSet.nameText)
        safeRemove(drawingSet.distanceText)
        for _, skeletonLine in ipairs(drawingSet.skeletonLines) do
            safeRemove(skeletonLine)
        end
        espDrawings[killerInstance] = nil
    end
end

local function createDrawingSet()
    local boxOutline = Drawing.new("Square")
    boxOutline.Thickness = 3
    boxOutline.Color = Color3.new(0, 0, 0)
    boxOutline.Filled = false
    boxOutline.Visible = false

    local box = Drawing.new("Square")
    box.Thickness = 1
    box.Color = Color3.fromRGB(255, 0, 0)
    box.Filled = false
    box.Visible = false

    local healthBarBackground = Drawing.new("Square")
    healthBarBackground.Thickness = 1
    healthBarBackground.Color = Color3.new(0, 0, 0)
    healthBarBackground.Filled = true
    healthBarBackground.Visible = false

    local healthBarFill = Drawing.new("Square")
    healthBarFill.Thickness = 1
    healthBarFill.Filled = true
    healthBarFill.Visible = false

    local nameText = Drawing.new("Text")
    nameText.Size = 14
    nameText.Center = true
    nameText.Outline = true
    nameText.Color = Color3.fromRGB(255, 40, 40)
    nameText.Visible = false

    local distanceText = Drawing.new("Text")
    distanceText.Size = 12
    distanceText.Center = true
    distanceText.Outline = true
    distanceText.Color = Color3.fromRGB(255, 255, 255)
    distanceText.Visible = false

    return {
        boxOutline = boxOutline,
        box = box,
        healthBarBackground = healthBarBackground,
        healthBarFill = healthBarFill,
        nameText = nameText,
        distanceText = distanceText,
        skeletonLines = {}
    }
end

local function getDrawingSet(killerInstance)
    if not espDrawings[killerInstance] then
        espDrawings[killerInstance] = createDrawingSet()
    end
    return espDrawings[killerInstance]
end

local function resolveKillerModel(taggedInstance)
    local success, killerModel = pcall(function()
        if taggedInstance:IsA("Player") then
            return taggedInstance.Character
        end
        return taggedInstance
    end)
    if success then
        return killerModel
    end
    return nil
end

local function collectSkeletonJoints(killerModel)
    local skeletonJoints = {}
    for _, descendant in ipairs(killerModel:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            local jointPart0 = descendant.Part0
            local jointPart1 = descendant.Part1
            if jointPart0 and jointPart1 and jointPart0.Parent == killerModel and jointPart1.Parent == killerModel then
                table.insert(skeletonJoints, {jointPart0, jointPart1})
            end
        end
    end
    return skeletonJoints
end

local function updateSkeletonLines(drawingSet, skeletonJoints)
    local requiredLineCount = #skeletonJoints * 2

    while #drawingSet.skeletonLines < requiredLineCount do
        local boneLine = Drawing.new("Line")
        boneLine.Thickness = 1
        boneLine.Color = Color3.fromRGB(255, 255, 255)
        boneLine.Visible = false
        table.insert(drawingSet.skeletonLines, boneLine)
    end

    while #drawingSet.skeletonLines > requiredLineCount do
        local extraLine = table.remove(drawingSet.skeletonLines)
        safeRemove(extraLine)
    end
end

local function isSelfBusy()
    local playerCharacter = localPlayer.Character
    if not playerCharacter then
        return true
    end

    if playerCharacter:GetAttribute("IsDead") or playerCharacter:GetAttribute("IsCarried") or playerCharacter:GetAttribute("IsHooked") then
        return true
    end

    local myRootPart = playerCharacter:FindFirstChild("HumanoidRootPart")
    if not myRootPart then
        return true
    end

    if collectionService:HasTag(myRootPart, "doing action") then
        return true
    end

    return false
end

local function tryAutoParry(killerModel, killerRootPart)
    if not getgenv().autoParryEnabled then
        return
    end

    if not autoParryEvent then
        return
    end

    local playerCharacter = localPlayer.Character
    if not playerCharacter then
        return
    end

    if killerModel == playerCharacter then
        return
    end

    if not playerCharacter:FindFirstChild("Parrying Dagger") then
        return
    end

    if isSelfBusy() then
        return
    end

    local myRootPart = playerCharacter:FindFirstChild("HumanoidRootPart")
    if not myRootPart then
        return
    end

    local distanceToKiller = (killerRootPart.Position - myRootPart.Position).Magnitude
    if distanceToKiller > getgenv().autoParryRange then
        return
    end

    local killerHumanoid = killerModel:FindFirstChildOfClass("Humanoid")
    if not killerHumanoid then
        return
    end

    local killerAnimator = killerHumanoid:FindFirstChildOfClass("Animator")
    if not killerAnimator then
        return
    end

    local success, playingTracks = pcall(killerAnimator.GetPlayingAnimationTracks, killerAnimator)
    if not success or not playingTracks then
        return
    end

    for _, animTrack in ipairs(playingTracks) do
        local trackPriorityValue = animTrack.Priority.Value
        if trackPriorityValue >= Enum.AnimationPriority.Action.Value and not firedParryTracks[animTrack] then
            firedParryTracks[animTrack] = true

            local now = os.clock()
            if now - lastParryFireTime >= parryFireDebounce then
                lastParryFireTime = now
                task.delay(getgenv().autoParryDelay, function()
                    pcall(function()
                        autoParryEvent:FireServer()
                    end)
                end)
            end
        end
    end
end

local function pruneParryTracks()
    for animTrack in pairs(firedParryTracks) do
        local success, isPlaying = pcall(function()
            return animTrack.IsPlaying
        end)
        if not success or not isPlaying then
            firedParryTracks[animTrack] = nil
        end
    end
end

local function updateKillerEsp()
    if not currentCamera or not currentCamera.Parent then
        currentCamera = workspace.CurrentCamera
    end
    if not currentCamera then
        return
    end

    local activeKillers = {}
    local taggedKillers = collectionService:GetTagged("Killer")

    for _, taggedInstance in ipairs(taggedKillers) do
        local killerModel = resolveKillerModel(taggedInstance)

        if killerModel and killerModel.Parent then
            local killerRootPart = killerModel:FindFirstChild("HumanoidRootPart")
            local killerHumanoid = killerModel:FindFirstChildOfClass("Humanoid")

            if killerRootPart and killerHumanoid and killerHumanoid.Health > 0 then
                activeKillers[killerModel] = true

                tryAutoParry(killerModel, killerRootPart)

                if not getgenv().killerEspEnabled then
                    continue
                end

                local drawingSet = getDrawingSet(killerModel)
                local rootScreenPosition, onScreen = currentCamera:WorldToViewportPoint(killerRootPart.Position)

                if onScreen then
                    local headScreenPosition = currentCamera:WorldToViewportPoint(killerRootPart.Position + Vector3.new(0, 2.9, 0))
                    local legScreenPosition = currentCamera:WorldToViewportPoint(killerRootPart.Position - Vector3.new(0, 2.9, 0))

                    local boxHeight = math.abs(legScreenPosition.Y - headScreenPosition.Y)
                    local boxWidth = boxHeight / 2
                    local boxLeft = rootScreenPosition.X - boxWidth / 2
                    local boxTop = headScreenPosition.Y

                    drawingSet.boxOutline.Size = Vector2.new(boxWidth, boxHeight)
                    drawingSet.boxOutline.Position = Vector2.new(boxLeft, boxTop)
                    drawingSet.boxOutline.Visible = true

                    drawingSet.box.Size = Vector2.new(boxWidth, boxHeight)
                    drawingSet.box.Position = Vector2.new(boxLeft, boxTop)
                    drawingSet.box.Visible = true

                    local healthPercent = math.clamp(killerHumanoid.Health / math.max(killerHumanoid.MaxHealth, 1), 0, 1)
                    local healthBarHeight = boxHeight * healthPercent

                    drawingSet.healthBarBackground.Size = Vector2.new(4, boxHeight)
                    drawingSet.healthBarBackground.Position = Vector2.new(boxLeft - 7, boxTop)
                    drawingSet.healthBarBackground.Visible = true

                    drawingSet.healthBarFill.Color = Color3.fromRGB(math.floor(255 * (1 - healthPercent)), math.floor(255 * healthPercent), 0)
                    drawingSet.healthBarFill.Size = Vector2.new(4, healthBarHeight)
                    drawingSet.healthBarFill.Position = Vector2.new(boxLeft - 7, boxTop + (boxHeight - healthBarHeight))
                    drawingSet.healthBarFill.Visible = true

                    local killerPlayer = playersService:GetPlayerFromCharacter(killerModel)
                    drawingSet.nameText.Text = killerPlayer and killerPlayer.Name or killerModel.Name
                    drawingSet.nameText.Position = Vector2.new(rootScreenPosition.X, boxTop - 18)
                    drawingSet.nameText.Visible = true

                    local distanceInStuds = math.floor((killerRootPart.Position - currentCamera.CFrame.Position).Magnitude)
                    drawingSet.distanceText.Text = distanceInStuds .. "m"
                    drawingSet.distanceText.Position = Vector2.new(rootScreenPosition.X, boxTop + boxHeight + 4)
                    drawingSet.distanceText.Visible = true

                    local skeletonJoints = collectSkeletonJoints(killerModel)
                    updateSkeletonLines(drawingSet, skeletonJoints)

                    for jointIndex, jointPair in ipairs(skeletonJoints) do
                        local boneLine = drawingSet.skeletonLines[(jointIndex - 1) * 2 + 1]
                        local startScreenPosition = currentCamera:WorldToViewportPoint(jointPair[1].Position)
                        local endScreenPosition = currentCamera:WorldToViewportPoint(jointPair[2].Position)

                        if startScreenPosition.Z > 0 and endScreenPosition.Z > 0 then
                            boneLine.From = Vector2.new(startScreenPosition.X, startScreenPosition.Y)
                            boneLine.To = Vector2.new(endScreenPosition.X, endScreenPosition.Y)
                            boneLine.Visible = true
                        else
                            boneLine.Visible = false
                        end
                    end
                else
                    hideDrawingSet(drawingSet)
                end
            end
        end
    end

    for killerInstance, drawingSet in pairs(espDrawings) do
        if not activeKillers[killerInstance] then
            safeRemove(drawingSet.boxOutline)
            safeRemove(drawingSet.box)
            safeRemove(drawingSet.healthBarBackground)
            safeRemove(drawingSet.healthBarFill)
            safeRemove(drawingSet.nameText)
            safeRemove(drawingSet.distanceText)
            for _, skeletonLine in ipairs(drawingSet.skeletonLines) do
                safeRemove(skeletonLine)
            end
            espDrawings[killerInstance] = nil
        end
    end
end

local function onRenderStep()
    pruneParryTracks()

    if getgenv().killerEspEnabled and Drawing and Drawing.new then
        updateKillerEsp()
    else
        for _, drawingSet in pairs(espDrawings) do
            hideDrawingSet(drawingSet)
        end
    end
end

local espToggle = Tabs.Main:AddToggle("EspToggle", {
    Title = "ESP",
    Default = false
})

espToggle:OnChanged(function(toggleValue)
    getgenv().killerEspEnabled = toggleValue
    if not toggleValue then
        clearAllDrawings()
    end
end)

local autoParryToggle = Tabs.Main:AddToggle("AutoParryToggle", {
    Title = "Auto Parry",
    Default = false
})

autoParryToggle:OnChanged(function(toggleValue)
    getgenv().autoParryEnabled = toggleValue
end)

local parryDelaySlider = Tabs.Main:AddSlider("ParryDelaySlider", {
    Title = "Parry Delay",
    Description = "วินาทีที่หน่วงหลังจับสัญญาณฟัน",
    Default = 0.1,
    Min = 0,
    Max = 0.5,
    Rounding = 2,
    Callback = function(sliderValue)
        getgenv().autoParryDelay = sliderValue
    end
})

local parryRangeSlider = Tabs.Main:AddSlider("ParryRangeSlider", {
    Title = "Parry Range",
    Description = "ระยะห่างสูงสุด (studs) ที่จะพยายาม parry",
    Default = 8,
    Min = 3,
    Max = 20,
    Rounding = 1,
    Callback = function(sliderValue)
        getgenv().autoParryRange = sliderValue
    end
})

Fluent:Notify({
    Title = "Violent",
    Content = "Loaded. ESP + Auto Parry ready.",
    Duration = 5
})

getgenv().killerEspConnection = runService.RenderStepped:Connect(onRenderStep)

Window:SelectTab(1)
