-- Brainrot Boulevard: the server.
-- A 3D brainrot game: walkers stroll the boulevard, the player buys them
-- with E, they park on the player's base and earn money every second.
-- Progression is real in the code: rebirths (permanent multiplier),
-- a base lock that stops the Sneaky Snatcher from stealing, three
-- upgrades, and two timed events (Snatcher raid, Golden Rush).
--
-- Design notes (hard-won, do not undo):
-- * Bodies are balls or axis-aligned blocks only. No cylinders, no
--   rotation helpers anywhere; every move is a plain position change.
-- * fixStaticGeometry() runs FIRST in start(), before buildWorld():
--   Rojo 7.5.1 silently drops Position from $properties, so the server
--   corrects Baseplate/SpawnLocation at runtime and prints before->after.
-- * Spawn: CharacterAutoLoads=true + a static SpawnLocation in the place
--   file + a CharacterAdded teleport. The pad is CanCollide=false and the
--   teleport target sits ABOVE the landing surface (y=5 over plaza top y=2).
-- * Buy with ProximityPrompt (E). ClickDetector is only a secondary.
-- * Tags are scale-sized BillboardGuis on an Attachment, never
--   fixed-pixel AlwaysOnTop.
-- * The whole simulation advances through tick(dt): one function the
--   mock-runtime test drives directly. No task.wait inside the logic.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(script.Parent.BrainrotData)

local GameServer = {}

-- Geometry. Plaza top y=2, lane top y=3, base top y=3, spawn pad y=3.
GameServer.LANE_Z = -20
GameServer.LANE_X_MIN = -70
GameServer.LANE_X_MAX = 75
GameServer.SPAWN_POS = Vector3.new(0, 5, -6)
GameServer.BASE_X = { -75, -25, 25, 75 }
GameServer.BASE_Z = 38
GameServer.BASE_SLOTS = 6
GameServer.WALKER_SPEED = 6
GameServer.MAX_WALKERS = 5
GameServer.SPAWN_INTERVAL = 2.2
GameServer.RUSH_SPAWN_INTERVAL = 1.2

-- Economy.
GameServer.START_CASH = 100
GameServer.REBIRTH_BASE_COST = 1500
GameServer.REBIRTH_MULT_PER = 0.5
GameServer.LOCK_COST = 500
GameServer.LOCK_DURATION = 60
GameServer.BONK_REWARD = 100
GameServer.DEFEND_REWARD = 50
GameServer.UPGRADES = {
	incomeBoost = { name = "Income Boost", maxLevel = 5, baseCost = 1000, bonusPerLevel = 0.25, label = "+25% income" },
	walkSpeed = { name = "Walk Speed", maxLevel = 3, baseCost = 800, bonusPerLevel = 0.20, label = "+20% walk speed" },
	extraSlots = { name = "Extra Slots", maxLevel = 2, baseCost = 1500, bonusPerLevel = 2, label = "+2 base slots" },
}

-- Timers (seconds since start).
GameServer.FIRST_RAID_AT = 60
GameServer.RAID_INTERVAL = 90
GameServer.FIRST_RUSH_AT = 90
GameServer.RUSH_INTERVAL = 120
GameServer.RUSH_DURATION = 30
GameServer.RAID_WARNING = 10
GameServer.RUSH_WARNING = 10

GameServer.elapsed = 0
GameServer.spawnTimer = 0
GameServer.nextRaidAt = GameServer.FIRST_RAID_AT
GameServer.nextRushAt = GameServer.FIRST_RUSH_AT
GameServer.raidWarned = false
GameServer.rushWarned = false
GameServer.rushUntil = 0
GameServer.snatcher = nil
GameServer.walkers = {}
GameServer.players = {}
GameServer.baseOwners = {}
GameServer.signLabel = nil

-- Pure helpers (also used by the mock test through GameServer._test).

function GameServer.rebirthMultiplier(rebirths)
	return 1 + GameServer.REBIRTH_MULT_PER * rebirths
end

function GameServer.rebirthCost(rebirths)
	return GameServer.REBIRTH_BASE_COST * (rebirths + 1)
end

function GameServer.upgradeCost(kind, level)
	local def = GameServer.UPGRADES[kind]
	return def.baseCost * (level + 1)
end

function GameServer.boostMultiplier(boostLevel)
	return 1 + GameServer.UPGRADES.incomeBoost.bonusPerLevel * boostLevel
end

function GameServer.maxSlots(state)
	return GameServer.BASE_SLOTS + GameServer.UPGRADES.extraSlots.bonusPerLevel * state.upgrades.extraSlots
end

function GameServer.walkSpeed(state)
	return 16 * (1 + GameServer.UPGRADES.walkSpeed.bonusPerLevel * state.upgrades.walkSpeed)
end

function GameServer.baseRate(state)
	local sum = 0
	for _, owned in ipairs(state.owned) do
		sum += owned.rate
	end
	return sum
end

function GameServer.incomeRate(state)
	return GameServer.baseRate(state) * GameServer.rebirthMultiplier(state.rebirths) * GameServer.boostMultiplier(state.upgrades.incomeBoost)
end

function GameServer.slotPosition(baseIndex, slotIndex)
	local bx = GameServer.BASE_X[baseIndex]
	local col = slotIndex % 5
	local row = math.floor(slotIndex / 5)
	local x = bx - 12 + col * 6
	local z = 32 + row * 12
	return Vector3.new(x, 5, z)
end

function GameServer.lockRemaining(state)
	local left = state.lockUntil - GameServer.elapsed
	if left < 0 then
		return 0
	end
	return math.floor(left)
end

function GameServer.isLocked(state)
	return GameServer.lockRemaining(state) > 0
end

-- A part with no transparency, anchored, parented to Workspace.
function GameServer.makePart(name, size, pos, color, material, canCollide)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = pos
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = canCollide
	if canCollide == nil then
		part.CanCollide = true
	end
	part.Parent = Workspace
	return part
end

-- Rojo 7.5.1 silently drops Position from $properties, so the static
-- Baseplate and SpawnLocation arrive at (0,0,0) and bury the world.
-- Correct them here, FIRST, before anything else is built.
function GameServer.fixStaticGeometry()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		local before = baseplate.Position
		baseplate.Position = Vector3.new(0, -10, 0)
		baseplate.Size = Vector3.new(512, 20, 512)
		baseplate.Anchored = true
		print("Brainrot Boulevard: fixed Baseplate from (" .. tostring(before) .. ") to (0, -10, 0), top y=0")
	end
	local spawn = Workspace:FindFirstChild("SpawnLocation")
	if spawn then
		local before = spawn.Position
		spawn.Position = Vector3.new(0, 3, -6)
		spawn.Size = Vector3.new(10, 1, 10)
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Neutral = true
		print("Brainrot Boulevard: fixed SpawnLocation from (" .. tostring(before) .. ") to (0, 3, -6), non-collidable")
	end
end

function GameServer.buildWorld()
	-- Plaza (top y=2) and the boulevard lane (top y=3) with neon rails.
	GameServer.makePart("PlazaFloor", Vector3.new(220, 2, 150), Vector3.new(0, 1, 10), Color3.fromRGB(80, 200, 90), Enum.Material.Grass)
	GameServer.makePart("ConveyorLane", Vector3.new(180, 2, 10), Vector3.new(0, 2, GameServer.LANE_Z), Color3.fromRGB(60, 60, 90), Enum.Material.SmoothPlastic)
	GameServer.makePart("RailNorth", Vector3.new(180, 1, 1), Vector3.new(0, 3.5, -25), Color3.fromRGB(255, 220, 0), Enum.Material.Neon, false)
	GameServer.makePart("RailSouth", Vector3.new(180, 1, 1), Vector3.new(0, 3.5, -15), Color3.fromRGB(255, 220, 0), Enum.Material.Neon, false)
	-- Four bases (top y=3).
	for i, bx in ipairs(GameServer.BASE_X) do
		local base = GameServer.makePart("Base" .. tostring(i), Vector3.new(30, 1, 30), Vector3.new(bx, 2.5, GameServer.BASE_Z), Color3.fromRGB(120, 90, 200), Enum.Material.SmoothPlastic)
		base.Name = "Base" .. tostring(i)
		local plate = GameServer.makePart("BasePlate" .. tostring(i), Vector3.new(26, 0.5, 26), Vector3.new(bx, 3.2, GameServer.BASE_Z), Color3.fromRGB(200, 170, 255), Enum.Material.Neon, false)
		plate.Name = "BasePlate" .. tostring(i)
	end
	-- Trees around the plaza edge.
	for i = 1, 10 do
		local angle = (i - 1) * (math.pi * 2 / 10)
		local tx = math.cos(angle) * 100
		local tz = 10 + math.sin(angle) * 62
		GameServer.makePart("TreeTrunk" .. tostring(i), Vector3.new(2, 6, 2), Vector3.new(tx, 5, tz), Color3.fromRGB(120, 80, 40), Enum.Material.Wood)
		local leaves = GameServer.makePart("TreeLeaves" .. tostring(i), Vector3.new(9, 9, 9), Vector3.new(tx, 12, tz), Color3.fromRGB(40, 160, 60), Enum.Material.SmoothPlastic)
		leaves.Shape = Enum.PartType.Ball
	end
	-- Two tall yellow beacon pillars (never collide; one offset so the
	-- player never spawns inside it).
	GameServer.makePart("BeaconSpawn", Vector3.new(2, 30, 2), Vector3.new(4, 15, -6), Color3.fromRGB(255, 220, 0), Enum.Material.Neon, false)
	GameServer.makePart("BeaconLane", Vector3.new(2, 30, 2), Vector3.new(0, 15, GameServer.LANE_Z), Color3.fromRGB(255, 220, 0), Enum.Material.Neon, false)
	-- The big sign at the back, with a live status line on its face.
	local sign = GameServer.makePart("BoulevardSign", Vector3.new(48, 10, 2), Vector3.new(0, 14, -52), Color3.fromRGB(40, 40, 90), Enum.Material.SmoothPlastic)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "SignGui"
	surface.Face = Enum.NormalId.Front
	surface.Parent = sign
	local title = Instance.new("TextLabel")
	title.Name = "SignTitle"
	title.Size = UDim2.fromScale(1, 0.55)
	title.BackgroundTransparency = 1
	title.Text = "BRAINROT BOULEVARD"
	title.TextColor3 = Color3.fromRGB(255, 220, 0)
	title.TextScaled = true
	title.Font = Enum.Font.SourceSansBold
	title.Parent = surface
	local status = Instance.new("TextLabel")
	status.Name = "SignStatus"
	status.Position = UDim2.fromScale(0, 0.55)
	status.Size = UDim2.fromScale(1, 0.45)
	status.BackgroundTransparency = 1
	status.Text = "SERVER ALIVE"
	status.TextColor3 = Color3.fromRGB(255, 255, 255)
	status.TextScaled = true
	status.Font = Enum.Font.SourceSans
	status.Parent = surface
	GameServer.signLabel = status
	print("Brainrot Boulevard: world built (plaza, lane, 4 bases, 10 trees, sign, beacons)")
end

-- A scale-sized name tag on an Attachment above a body. The tag shrinks
-- with distance, so it gives real distance feedback.
function GameServer.makeTag(parent, attachPart, text, rarity)
	local attach = Instance.new("Attachment")
	attach.Name = "NameTagAnchor"
	attach.Position = Vector3.new(0, 3.5, 0)
	attach.Parent = attachPart
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Adornee = attach
	gui.Size = UDim2.fromScale(8, 2.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	gui.MaxDistance = 150
	gui.AlwaysOnTop = false
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Name = "TagText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.Parent = gui
	if rarity then
		local color = BrainrotData.RARITY_COLORS[rarity]
		if color then
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end
	return gui
end

function GameServer.makeBody(def, golden, pos)
	local model = Instance.new("Model")
	model.Name = def.name
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(4, 4, 4)
	body.Position = pos
	body.Anchored = false
	body.CanCollide = false
	if def.shape == "Ball" then
		body.Shape = Enum.PartType.Ball
	end
	if golden then
		body.Color = Color3.fromRGB(255, 215, 0)
		body.Material = Enum.Material.Neon
	else
		body.Color = def.color
		body.Material = Enum.Material.SmoothPlastic
	end
	body.Parent = model
	-- A big transparent hitbox, so E always has something to grab.
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(7, 7, 7)
	hitbox.Position = pos
	hitbox.Anchored = false
	hitbox.CanCollide = false
	hitbox.Transparency = 1
	hitbox.Parent = model
	model.Parent = Workspace
	return model, body, hitbox
end

function GameServer.spawnWalker(forceGolden)
	if #GameServer.walkers >= GameServer.MAX_WALKERS then
		return nil
	end
	local def = BrainrotData.pickRandom()
	local golden = forceGolden or BrainrotData.rollGolden()
	local rate = BrainrotData.walkerRate(def, golden)
	local price = BrainrotData.walkerPrice(def, golden)
	local x = GameServer.LANE_X_MIN
	local pos = Vector3.new(x, 5, GameServer.LANE_Z)
	local model, body, hitbox = GameServer.makeBody(def, golden, pos)
	GameServer.makeTag(model, body, BrainrotData.tagText(def, golden), def.rarity)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy $" .. tostring(price)
	prompt.ObjectText = BrainrotData.tagText(def, golden)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = hitbox
	-- ClickDetector kept only as a secondary way to buy.
	local click = Instance.new("ClickDetector")
	click.Name = "BuyClick"
	click.MaxActivationDistance = 200
	click.Parent = hitbox
	local walker = {
		model = model,
		body = body,
		hitbox = hitbox,
		prompt = prompt,
		click = click,
		def = def,
		golden = golden,
		rate = rate,
		price = price,
		x = x,
	}
	table.insert(GameServer.walkers, walker)
	prompt.Triggered:Connect(function(player)
		GameServer.buyWalker(player, walker)
	end)
	click.MouseClick:Connect(function(player)
		GameServer.buyWalker(player, walker)
	end)
	print("Brainrot Boulevard: walker joined the lane: " .. BrainrotData.tagText(def, golden) .. " (" .. tostring(#GameServer.walkers) .. " walking)")
	return walker
end

function GameServer.removeWalker(walker)
	for i, w in ipairs(GameServer.walkers) do
		if w == walker then
			table.remove(GameServer.walkers, i)
			break
		end
	end
	if walker.model then
		walker.model:Destroy()
	end
end

function GameServer.newPlayerState(player)
	return {
		player = player,
		cash = GameServer.START_CASH,
		owned = {},
		rebirths = 0,
		upgrades = { incomeBoost = 0, walkSpeed = 0, extraSlots = 0 },
		lockUntil = 0,
		baseIndex = 1,
	}
end

function GameServer.assignBase(player)
	local n = 0
	for _ in pairs(GameServer.players) do
		n += 1
	end
	local baseIndex = (n % #GameServer.BASE_X) + 1
	GameServer.baseOwners[baseIndex] = player
	return baseIndex
end

function GameServer.teleportToLane(player)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(GameServer.SPAWN_POS)
		print("Brainrot Boulevard: teleported " .. player.Name .. " to the lane")
	end
end

function GameServer.buyWalker(player, walker)
	local state = GameServer.players[player]
	if not state then
		return false
	end
	if walker.price > state.cash then
		return false
	end
	if #state.owned >= GameServer.maxSlots(state) then
		return false
	end
	-- The walker must still be on the lane.
	local stillThere = false
	for _, w in ipairs(GameServer.walkers) do
		if w == walker then
			stillThere = true
			break
		end
	end
	if not stillThere then
		return false
	end
	state.cash -= walker.price
	local slotIndex = #state.owned
	local pos = GameServer.slotPosition(state.baseIndex, slotIndex)
	local model, body, hitbox = GameServer.makeBody(walker.def, walker.golden, pos)
	body.Anchored = true
	hitbox:Destroy()
	GameServer.makeTag(model, body, BrainrotData.tagText(walker.def, walker.golden), walker.def.rarity)
	local owned = {
		def = walker.def,
		golden = walker.golden,
		rate = walker.rate,
		model = model,
		body = body,
		slotIndex = slotIndex,
	}
	table.insert(state.owned, owned)
	GameServer.removeWalker(walker)
	GameServer.pushHud(player)
	print("Brainrot Boulevard: " .. player.Name .. " bought " .. BrainrotData.tagText(walker.def, walker.golden) .. " for $" .. tostring(walker.price) .. " (cash $" .. tostring(state.cash) .. ")")
	return true
end

function GameServer.tryUpgrade(player, kind)
	local state = GameServer.players[player]
	if not state then
		return false
	end
	local def = GameServer.UPGRADES[kind]
	if not def then
		return false
	end
	local level = state.upgrades[kind]
	if level >= def.maxLevel then
		return false
	end
	local cost = GameServer.upgradeCost(kind, level)
	if state.cash < cost then
		return false
	end
	state.cash -= cost
	state.upgrades[kind] = level + 1
	if kind == "walkSpeed" then
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = GameServer.walkSpeed(state)
			end
		end
	end
	GameServer.pushHud(player)
	print("Brainrot Boulevard: " .. player.Name .. " bought " .. def.name .. " level " .. tostring(level + 1) .. " for $" .. tostring(cost))
	return true
end

function GameServer.tryRebirth(player)
	local state = GameServer.players[player]
	if not state then
		return false
	end
	local cost = GameServer.rebirthCost(state.rebirths)
	if state.cash < cost then
		return false
	end
	for _, owned in ipairs(state.owned) do
		if owned.model then
			owned.model:Destroy()
		end
	end
	state.owned = {}
	state.cash = 0
	state.rebirths += 1
	GameServer.pushHud(player)
	GameServer.sendBanner(player, "REBIRTH! Income now x" .. tostring(GameServer.rebirthMultiplier(state.rebirths)), Color3.fromRGB(170, 90, 255))
	print("Brainrot Boulevard: " .. player.Name .. " rebirthed (x" .. tostring(GameServer.rebirthMultiplier(state.rebirths)) .. ")")
	return true
end

function GameServer.tryLock(player)
	local state = GameServer.players[player]
	if not state then
		return false
	end
	if GameServer.isLocked(state) then
		return false
	end
	if state.cash < GameServer.LOCK_COST then
		return false
	end
	state.cash -= GameServer.LOCK_COST
	state.lockUntil = GameServer.elapsed + GameServer.LOCK_DURATION
	GameServer.pushHud(player)
	GameServer.sendBanner(player, "BASE LOCKED for " .. tostring(GameServer.LOCK_DURATION) .. "s — the Snatcher cannot steal!", Color3.fromRGB(80, 160, 255))
	print("Brainrot Boulevard: " .. player.Name .. " locked the base for " .. tostring(GameServer.LOCK_DURATION) .. "s")
	return true
end

-- The Snatcher: an NPC thief who walks the lane to a base. He steals the
-- most valuable brainrot unless the base is locked or the player bonks
-- him 3 times first.
function GameServer.chooseSnatcherTarget()
	local bestPlayer = nil
	local bestValue = 0
	for player, state in pairs(GameServer.players) do
		for _, owned in ipairs(state.owned) do
			if owned.rate > bestValue then
				bestValue = owned.rate
				bestPlayer = player
			end
		end
	end
	return bestPlayer
end

function GameServer.spawnSnatcher()
	if GameServer.snatcher then
		return nil
	end
	local target = GameServer.chooseSnatcherTarget()
	if not target then
		return nil
	end
	local state = GameServer.players[target]
	local bx = GameServer.BASE_X[state.baseIndex]
	local pos = Vector3.new(GameServer.LANE_X_MIN, 5, GameServer.LANE_Z)
	local model = Instance.new("Model")
	model.Name = "SneakySnatcher"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(5, 5, 5)
	body.Position = pos
	body.Shape = Enum.PartType.Ball
	body.Color = Color3.fromRGB(200, 30, 30)
	body.Material = Enum.Material.Neon
	body.Anchored = false
	body.CanCollide = false
	body.Parent = model
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(8, 8, 8)
	hitbox.Position = pos
	hitbox.Anchored = false
	hitbox.CanCollide = false
	hitbox.Transparency = 1
	hitbox.Parent = model
	GameServer.makeTag(model, body, "Sneaky Snatcher — Bonk me 3x!", nil)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BonkPrompt"
	prompt.ActionText = "Bonk!"
	prompt.ObjectText = "Sneaky Snatcher"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = hitbox
	model.Parent = Workspace
	local snatcher = {
		model = model,
		body = body,
		hitbox = hitbox,
		prompt = prompt,
		target = target,
		targetX = bx,
		x = GameServer.LANE_X_MIN,
		z = GameServer.LANE_Z,
		phase = "approaching",
		bonks = 0,
		stolen = nil,
		grabTimer = 0,
	}
	GameServer.snatcher = snatcher
	prompt.Triggered:Connect(function(player)
		GameServer.bonkSnatcher(player)
	end)
	print("Brainrot Boulevard: raid started, the Snatcher is on the lane")
	return snatcher
end

function GameServer.bonkSnatcher(player)
	local snatcher = GameServer.snatcher
	if not snatcher then
		return false
	end
	snatcher.bonks += 1
	if snatcher.bonks >= 3 then
		-- Driven off: drop anything he stole, pay the bonk reward.
		if snatcher.stolen then
			local state = GameServer.players[snatcher.target]
			if state then
				local pos = GameServer.slotPosition(state.baseIndex, snatcher.stolen.slotIndex)
				local model, body, hitbox = GameServer.makeBody(snatcher.stolen.def, snatcher.stolen.golden, pos)
				body.Anchored = true
				hitbox:Destroy()
				GameServer.makeTag(model, body, BrainrotData.tagText(snatcher.stolen.def, snatcher.stolen.golden), snatcher.stolen.def.rarity)
				snatcher.stolen.model = model
				snatcher.stolen.body = body
				table.insert(state.owned, snatcher.stolen)
				snatcher.stolen = nil
			end
		end
		local state = GameServer.players[snatcher.target]
		if state then
			state.cash += GameServer.BONK_REWARD
			GameServer.pushHud(snatcher.target)
		end
		GameServer.sendBanner(player, "Bonked! " .. player.Name .. " earned $" .. tostring(GameServer.BONK_REWARD) .. "!", Color3.fromRGB(255, 60, 60))
		print("Brainrot Boulevard: bonked! " .. player.Name .. " earned $" .. tostring(GameServer.BONK_REWARD))
		GameServer.removeSnatcher()
		return true
	end
	return true
end

function GameServer.removeSnatcher()
	if GameServer.snatcher and GameServer.snatcher.model then
		GameServer.snatcher.model:Destroy()
	end
	GameServer.snatcher = nil
end

function GameServer.stealMostValuable(snatcher)
	local state = GameServer.players[snatcher.target]
	if not state or #state.owned == 0 then
		return false
	end
	local bestIndex = 1
	local bestRate = 0
	for i, owned in ipairs(state.owned) do
		if owned.rate > bestRate then
			bestRate = owned.rate
			bestIndex = i
		end
	end
	local stolen = table.remove(state.owned, bestIndex)
	if stolen.model then
		stolen.model:Destroy()
		stolen.model = nil
		stolen.body = nil
	end
	snatcher.stolen = stolen
	snatcher.phase = "fleeing"
	GameServer.pushHud(snatcher.target)
	print("Brainrot Boulevard: the Snatcher stole " .. BrainrotData.tagText(stolen.def, stolen.golden) .. " — bonk him 3x to get it back!")
	return true
end

function GameServer.stepSnatcher(dt)
	local snatcher = GameServer.snatcher
	if not snatcher then
		return
	end
	local speed = 5
	if snatcher.phase == "approaching" then
		-- Walk along the lane, then turn toward the target base.
		if snatcher.x < snatcher.targetX then
			snatcher.x += speed * dt
			snatcher.body.Position = Vector3.new(snatcher.x, 5, GameServer.LANE_Z)
			snatcher.hitbox.Position = Vector3.new(snatcher.x, 5, GameServer.LANE_Z)
		else
			snatcher.phase = "grabbing"
			snatcher.grabTimer = 0
		end
	elseif snatcher.phase == "grabbing" then
		snatcher.grabTimer += dt
		local state = GameServer.players[snatcher.target]
		if state and GameServer.isLocked(state) then
			-- Locked base: he bounces off, the player is paid for defending.
			state.cash += GameServer.DEFEND_REWARD
			GameServer.pushHud(snatcher.target)
			GameServer.sendBanner(snatcher.target, "DEFENDED! The Snatcher bounced off your lock (+$" .. tostring(GameServer.DEFEND_REWARD) .. ")", Color3.fromRGB(80, 160, 255))
			print("Brainrot Boulevard: Snatcher bounced off a locked base (+$" .. tostring(GameServer.DEFEND_REWARD) .. ")")
			GameServer.removeSnatcher()
			return
		end
		if snatcher.grabTimer >= 3 then
			if not GameServer.stealMostValuable(snatcher) then
				GameServer.removeSnatcher()
			end
		end
	elseif snatcher.phase == "fleeing" then
		if snatcher.x < GameServer.LANE_X_MAX then
			snatcher.x += speed * 1.5 * dt
			snatcher.body.Position = Vector3.new(snatcher.x, 5, GameServer.LANE_Z)
			snatcher.hitbox.Position = Vector3.new(snatcher.x, 5, GameServer.LANE_Z)
		else
			-- He got away with it.
			print("Brainrot Boulevard: the Snatcher escaped with a brainrot!")
			GameServer.removeSnatcher()
		end
	end
end

function GameServer.stepWalkers(dt)
	for i = #GameServer.walkers, 1, -1 do
		local walker = GameServer.walkers[i]
		walker.x += GameServer.WALKER_SPEED * dt
		if walker.x >= GameServer.LANE_X_MAX then
			GameServer.removeWalker(walker)
		else
			walker.body.Position = Vector3.new(walker.x, 5, GameServer.LANE_Z)
			walker.hitbox.Position = Vector3.new(walker.x, 5, GameServer.LANE_Z)
		end
	end
end

function GameServer.pushHud(player)
	local state = GameServer.players[player]
	if not state then
		return
	end
	local hud = ReplicatedStorage:FindFirstChild("HudUpdate")
	if not hud then
		return
	end
	local rate = GameServer.incomeRate(state)
	hud:FireClient(player, {
		cash = math.floor(state.cash),
		rate = math.floor(rate),
		multiplier = GameServer.rebirthMultiplier(state.rebirths),
		brainrots = #state.owned,
		maxSlots = GameServer.maxSlots(state),
		rebirths = state.rebirths,
		rebirthCost = GameServer.rebirthCost(state.rebirths),
		boostLevel = state.upgrades.incomeBoost,
		boostCost = GameServer.upgradeCost("incomeBoost", state.upgrades.incomeBoost),
		speedLevel = state.upgrades.walkSpeed,
		speedCost = GameServer.upgradeCost("walkSpeed", state.upgrades.walkSpeed),
		slotsLevel = state.upgrades.extraSlots,
		slotsCost = GameServer.upgradeCost("extraSlots", state.upgrades.extraSlots),
		lockRemaining = GameServer.lockRemaining(state),
		lockCost = GameServer.LOCK_COST,
		rushActive = GameServer.elapsed < GameServer.rushUntil,
		snatcherActive = GameServer.snatcher ~= nil,
	})
end

function GameServer.sendBanner(player, text, color)
	local banner = ReplicatedStorage:FindFirstChild("Banner")
	if banner then
		banner:FireClient(player, text, color)
	end
end

function GameServer.broadcastWarning(text)
	local warning = ReplicatedStorage:FindFirstChild("Warning")
	if warning then
		warning:FireAllClients(text)
	end
end

-- The whole simulation, advanced by dt seconds. The main loop calls this
-- every 0.1s; the mock test calls it directly.
function GameServer.tick(dt)
	GameServer.elapsed += dt
	-- Walker spawns.
	GameServer.spawnTimer += dt
	local interval = GameServer.SPAWN_INTERVAL
	if GameServer.elapsed < GameServer.rushUntil then
		interval = GameServer.RUSH_SPAWN_INTERVAL
	end
	if GameServer.spawnTimer >= interval then
		GameServer.spawnTimer = 0
		local forceGolden = GameServer.elapsed < GameServer.rushUntil
		GameServer.spawnWalker(forceGolden)
	end
	GameServer.stepWalkers(dt)
	-- Snatcher raid on its timer, with a warning first.
	if not GameServer.snatcher and GameServer.elapsed >= GameServer.nextRaidAt - GameServer.RAID_WARNING and not GameServer.raidWarned then
		GameServer.raidWarned = true
		GameServer.broadcastWarning("THE SNATCHER IS COMING! Lock your base or get ready to bonk!")
	end
	if GameServer.elapsed >= GameServer.nextRaidAt then
		GameServer.nextRaidAt += GameServer.RAID_INTERVAL
		GameServer.raidWarned = false
		if GameServer.spawnSnatcher() then
			GameServer.broadcastWarning("THE SNATCHER IS HERE! Bonk him 3x!")
		end
	end
	GameServer.stepSnatcher(dt)
	-- Golden Rush on its timer, with a warning first.
	if GameServer.elapsed >= GameServer.nextRushAt - GameServer.RUSH_WARNING and not GameServer.rushWarned then
		GameServer.rushWarned = true
		GameServer.broadcastWarning("GOLDEN RUSH in 10s! Every walker will be Golden!")
	end
	if GameServer.elapsed >= GameServer.nextRushAt then
		GameServer.nextRushAt += GameServer.RUSH_INTERVAL
		GameServer.rushWarned = false
		GameServer.rushUntil = GameServer.elapsed + GameServer.RUSH_DURATION
		GameServer.broadcastWarning("GOLDEN RUSH! All walkers are Golden for " .. tostring(GameServer.RUSH_DURATION) .. "s!")
		print("Brainrot Boulevard: Golden Rush started")
	end
	-- Income ticks once a second (tracked in whole seconds).
	if math.floor(GameServer.elapsed) > math.floor(GameServer.elapsed - dt) then
		for player, state in pairs(GameServer.players) do
			local rate = GameServer.incomeRate(state)
			if rate > 0 then
				state.cash += rate
			end
			GameServer.pushHud(player)
		end
		if GameServer.signLabel then
			GameServer.signLabel.Text = "SERVER ALIVE • " .. tostring(#GameServer.walkers) .. " walkers • " .. tostring(math.floor(GameServer.elapsed)) .. "s"
		end
	end
end

function GameServer.onPlayerAdded(player)
	local state = GameServer.newPlayerState(player)
	state.baseIndex = GameServer.assignBase(player)
	GameServer.players[player] = state
	-- Leaderstats Cash, so the leaderboard shows the money too.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	local cashValue = Instance.new("IntValue")
	cashValue.Name = "Cash"
	cashValue.Value = state.cash
	cashValue.Parent = leaderstats
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = GameServer.walkSpeed(state)
		task.wait(0.1)
		GameServer.teleportToLane(player)
		print("Brainrot Boulevard: " .. player.Name .. " spawned at (" .. tostring(GameServer.SPAWN_POS) .. ")")
	end)
	print("Brainrot Boulevard: " .. player.Name .. " joined with $" .. tostring(state.cash) .. " (base " .. tostring(state.baseIndex) .. ")")
	GameServer.pushHud(player)
end

function GameServer.onPlayerRemoving(player)
	local state = GameServer.players[player]
	if state then
		for _, owned in ipairs(state.owned) do
			if owned.model then
				owned.model:Destroy()
			end
		end
	end
	GameServer.players[player] = nil
end

function GameServer.setupRemotes()
	local function makeRemote(name)
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
		return remote
	end
	makeRemote("HudUpdate")
	makeRemote("Warning")
	makeRemote("Banner")
	local teleport = makeRemote("TeleportRequest")
	teleport.OnServerEvent:Connect(function(player)
		GameServer.teleportToLane(player)
	end)
	local upgrade = makeRemote("UpgradeRequest")
	upgrade.OnServerEvent:Connect(function(player, kind)
		GameServer.tryUpgrade(player, kind)
	end)
	local rebirth = makeRemote("RebirthRequest")
	rebirth.OnServerEvent:Connect(function(player)
		GameServer.tryRebirth(player)
	end)
	local lock = makeRemote("LockRequest")
	lock.OnServerEvent:Connect(function(player)
		GameServer.tryLock(player)
	end)
end

function GameServer.start()
	GameServer.fixStaticGeometry()
	GameServer.setupRemotes()
	GameServer.buildWorld()
	Players.PlayerAdded:Connect(function(player)
		GameServer.onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		GameServer.onPlayerRemoving(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		GameServer.onPlayerAdded(player)
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			GameServer.tick(0.1)
		end
	end)
	print("Brainrot Boulevard: live — walkers spawning, buy with E, rebirths, locks, raids and Golden Rush")
end

-- Internals exposed for the mock-runtime test only.
GameServer._test = {
	rebirthMultiplier = GameServer.rebirthMultiplier,
	rebirthCost = GameServer.rebirthCost,
	upgradeCost = GameServer.upgradeCost,
	boostMultiplier = GameServer.boostMultiplier,
	maxSlots = GameServer.maxSlots,
	walkSpeed = GameServer.walkSpeed,
	baseRate = GameServer.baseRate,
	incomeRate = GameServer.incomeRate,
	slotPosition = GameServer.slotPosition,
	lockRemaining = GameServer.lockRemaining,
	isLocked = GameServer.isLocked,
}

return GameServer
