local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

local CurrencyAnimator = require(ReplicatedStorage:WaitForChild("CurrencyAnimator"))

local PickupCurrencyEvent = ReplicatedStorage:WaitForChild("PickupCurrency")
local PlayerPositionUpdate = ReplicatedStorage:WaitForChild("PlayerPositionUpdate")
local SpawnCurrencyClient = ReplicatedStorage:WaitForChild("SpawnCurrencyClient")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- Configuration
local RENDER_DISTANCE = 100
local CLOSE_RENDER_DISTANCE = 30
local COIN_SPAWN_COUNT = math.random(50, 100)
local GROUND_RAYCAST_DISTANCE = 1000
local COIN_SPACING = 15
local MAX_SPAWN_ATTEMPTS = 100

-- State
local spawnedCoins = {}
local renderedCoins = {}
local isPlayerLoaded = false
local lastPositionUpdate = 0
local positionUpdateInterval = 0.1

-- Wait for player to be fully loaded
local function waitForPlayerLoad()
    while not character or not humanoidRootPart or not humanoidRootPart.Parent do
        character = player.Character or player.CharacterAdded:Wait()
        humanoidRootPart = character:WaitForChild("HumanoidRootPart")
        task.wait(0.1)
    end
    
    -- Wait a bit more to ensure everything is loaded
    task.wait(2)
    isPlayerLoaded = true
    print("Player fully loaded, starting coin system")
end

-- Raycast to find ground level
local function findGroundLevel(position)
    local raycastResult = workspace:Raycast(position, Vector3.new(0, -GROUND_RAYCAST_DISTANCE, 0))
    if raycastResult then
        return raycastResult.Position.Y
    end
    return position.Y - 5 -- Fallback
end

-- Check if position is valid for coin spawning
local function isValidSpawnPosition(position)
    local raycastResult = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0))
    if not raycastResult then
        return false
    end
    
    -- Check if there's enough space around the position
    local radius = 3
    for i = 0, 360, 45 do
        local angle = math.rad(i)
        local checkPos = position + Vector3.new(
            math.cos(angle) * radius,
            0,
            math.sin(angle) * radius
        )
        local checkRaycast = workspace:Raycast(checkPos + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0))
        if not checkRaycast then
            return false
        end
    end
    
    return true
end

-- Generate random spawn positions
local function generateSpawnPositions()
    local positions = {}
    local attempts = 0
    
    while #positions < COIN_SPAWN_COUNT and attempts < MAX_SPAWN_ATTEMPTS do
        attempts = attempts + 1
        
        -- Generate random position within a reasonable area
        local randomX = math.random(-500, 500)
        local randomZ = math.random(-500, 500)
        local startPos = Vector3.new(randomX, 1000, randomZ)
        
        local groundY = findGroundLevel(startPos)
        local spawnPos = Vector3.new(randomX, groundY + 2, randomZ)
        
        if isValidSpawnPosition(spawnPos) then
            -- Check if position is far enough from existing positions
            local tooClose = false
            for _, existingPos in ipairs(positions) do
                if (spawnPos - existingPos).Magnitude < COIN_SPACING then
                    tooClose = true
                    break
                end
            end
            
            if not tooClose then
                table.insert(positions, spawnPos)
            end
        end
    end
    
    print("Generated " .. #positions .. " coin spawn positions")
    return positions
end

-- Create coin model
local function createCoinModel()
    local coinModel = Instance.new("Model")
    coinModel.Name = "Currency"
    
    local coinPart = Instance.new("Part")
    coinPart.Name = "Coin"
    coinPart.Shape = Enum.PartType.Cylinder
    coinPart.Size = Vector3.new(0.2, 1, 1)
    coinPart.Material = Enum.Material.Metal
    coinPart.BrickColor = BrickColor.new("Bright yellow")
    coinPart.Anchored = true
    coinPart.CanCollide = false
    coinPart.Parent = coinModel
    
    -- Add sparkle effect
    local sparkle = Instance.new("Sparkles")
    sparkle.SparkleColor = Color3.fromRGB(255, 215, 0)
    sparkle.Enabled = false
    sparkle.Parent = coinPart
    
    return coinModel
end

-- Spawn coins at generated positions
local function spawnCoins()
    local spawnPositions = generateSpawnPositions()
    
    for i, position in ipairs(spawnPositions) do
        local coinModel = createCoinModel()
        local coinPart = coinModel:FindFirstChild("Coin")
        
        if coinPart then
            coinPart.CFrame = CFrame.new(position)
            
            -- Store coin data
            local coinData = {
                model = coinModel,
                position = position,
                guid = HttpService:GenerateGUID(),
                isRendered = false
            }
            
            spawnedCoins[coinData.guid] = coinData
            
            -- Create touch detection
            local touchPart = Instance.new("Part")
            touchPart.Name = "TouchPart"
            touchPart.Shape = Enum.PartType.Ball
            touchPart.Size = Vector3.new(4, 4, 4)
            touchPart.Transparency = 1
            touchPart.CanCollide = false
            touchPart.Anchored = true
            touchPart.CFrame = coinPart.CFrame
            touchPart.Parent = coinModel
            
            touchPart.Touched:Connect(function(hit)
                local character = player.Character
                if character and hit:IsDescendantOf(character) then
                    collectCoin(coinData.guid)
                end
            end)
        end
    end
    
    print("Spawned " .. #spawnPositions .. " coins")
end

-- Collect coin
local function collectCoin(coinGuid)
    local coinData = spawnedCoins[coinGuid]
    if not coinData or not coinData.model or not coinData.model.Parent then
        return
    end
    
    -- Remove from spawned coins
    spawnedCoins[coinGuid] = nil
    renderedCoins[coinGuid] = nil
    
    -- Animate pickup
    CurrencyAnimator.animatePickup(coinData.model)
    
    -- Fire server event
    PickupCurrencyEvent:FireServer(coinGuid)
end

-- Update coin rendering based on distance
local function updateCoinRendering()
    if not isPlayerLoaded or not humanoidRootPart then return end
    
    local playerPos = humanoidRootPart.Position
    
    for guid, coinData in pairs(spawnedCoins) do
        if coinData.model and coinData.model.Parent then
            local distance = (coinData.position - playerPos).Magnitude
            
            if distance <= RENDER_DISTANCE then
                if not coinData.isRendered then
                    -- Render coin
                    coinData.isRendered = true
                    renderedCoins[guid] = coinData
                    
                    -- Start animation if close enough
                    if distance <= CLOSE_RENDER_DISTANCE then
                        CurrencyAnimator.animateCurrency(coinData.model, player, nil, coinData.position)
                    end
                end
            else
                if coinData.isRendered then
                    -- Unrender coin
                    coinData.isRendered = false
                    renderedCoins[guid] = nil
                    
                    if coinData.model then
                        coinData.model:Destroy()
                    end
                end
            end
        end
    end
end

-- Update player position
local function updatePlayerPosition()
    if not isPlayerLoaded or not humanoidRootPart then return end
    
    local currentTime = tick()
    if currentTime - lastPositionUpdate >= positionUpdateInterval then
        PlayerPositionUpdate:FireServer(character.Name)
        lastPositionUpdate = currentTime
    end
end

-- Handle server coin spawns
SpawnCurrencyClient.OnClientEvent:Connect(function(itemName, moneyAmount, spawnPosition, playerUserId, sfxSoundId, dropId)
    if playerUserId == player.UserId then
        local coinModel = createCoinModel()
        local coinPart = coinModel:FindFirstChild("Coin")
        
        if coinPart then
            coinPart.CFrame = CFrame.new(spawnPosition)
            
            local coinData = {
                model = coinModel,
                position = spawnPosition,
                guid = dropId,
                isRendered = true
            }
            
            spawnedCoins[dropId] = coinData
            renderedCoins[dropId] = coinData
            
            -- Create touch detection
            local touchPart = Instance.new("Part")
            touchPart.Name = "TouchPart"
            touchPart.Shape = Enum.PartType.Ball
            touchPart.Size = Vector3.new(4, 4, 4)
            touchPart.Transparency = 1
            touchPart.CanCollide = false
            touchPart.Anchored = true
            touchPart.CFrame = coinPart.CFrame
            touchPart.Parent = coinModel
            
            touchPart.Touched:Connect(function(hit)
                local character = player.Character
                if character and hit:IsDescendantOf(character) then
                    collectCoin(dropId)
                end
            end)
            
            -- Animate the coin
            CurrencyAnimator.animateCurrency(coinModel, player, sfxSoundId, spawnPosition)
        end
    end
end)

-- Main loop
local function main()
    waitForPlayerLoad()
    spawnCoins()
    
    RunService.Heartbeat:Connect(function()
        updatePlayerPosition()
        updateCoinRendering()
    end)
end

-- Start the system
main()