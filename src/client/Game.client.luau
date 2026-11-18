-- Brainrot Boulevard: the client.
-- Start screen, HUD (top-right, clear of Roblox's top-left menu buttons),
-- upgrade / rebirth / lock buttons, event banners, and the DIAG panel
-- (bottom-left, refreshed every second from the CLIENT's view, so one
-- screenshot settles "the server works but I see nothing").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudUpdate = ReplicatedStorage:WaitForChild("HudUpdate")
local Warning = ReplicatedStorage:WaitForChild("Warning")
local Banner = ReplicatedStorage:WaitForChild("Banner")
local TeleportRequest = ReplicatedStorage:WaitForChild("TeleportRequest")
local UpgradeRequest = ReplicatedStorage:WaitForChild("UpgradeRequest")
local RebirthRequest = ReplicatedStorage:WaitForChild("RebirthRequest")
local LockRequest = ReplicatedStorage:WaitForChild("LockRequest")

local gui = Instance.new("ScreenGui")
gui.Name = "BoulevardGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Start screen.
local startScreen = Instance.new("Frame")
startScreen.Name = "StartScreen"
startScreen.Size = UDim2.fromScale(1, 1)
startScreen.BackgroundColor3 = Color3.fromRGB(30, 30, 70)
startScreen.BackgroundTransparency = 0.15
startScreen.BorderSizePixel = 0
startScreen.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0.12, 0)
title.Size = UDim2.new(0.8, 0, 0.12, 0)
title.BackgroundTransparency = 1
title.Text = "BRAINROT BOULEVARD"
title.TextColor3 = Color3.fromRGB(255, 220, 0)
title.TextScaled = true
title.Font = Enum.Font.SourceSansBold
title.Parent = startScreen

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.AnchorPoint = Vector2.new(0.5, 0)
subtitle.Position = UDim2.new(0.5, 0, 0.26, 0)
subtitle.Size = UDim2.new(0.8, 0, 0.06, 0)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Buy brainrots with E  •  Earn $ every second  •  Rebirth, lock your base, bonk the Snatcher!"
subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
subtitle.TextScaled = true
subtitle.Font = Enum.Font.SourceSans
subtitle.Parent = startScreen

local playButton = Instance.new("TextButton")
playButton.Name = "PlayButton"
playButton.AnchorPoint = Vector2.new(0.5, 0)
playButton.Position = UDim2.new(0.5, 0, 0.38, 0)
playButton.Size = UDim2.new(0.25, 0, 0.1, 0)
playButton.BackgroundColor3 = Color3.fromRGB(90, 200, 90)
playButton.Text = "PLAY"
playButton.TextColor3 = Color3.fromRGB(255, 255, 255)
playButton.TextScaled = true
playButton.Font = Enum.Font.SourceSansBold
playButton.Parent = startScreen

local howTo = Instance.new("TextLabel")
howTo.Name = "HowTo"
howTo.AnchorPoint = Vector2.new(0.5, 0)
howTo.Position = UDim2.new(0.5, 0, 0.52, 0)
howTo.Size = UDim2.new(0.7, 0, 0.2, 0)
howTo.BackgroundTransparency = 1
howTo.Text = "Walk to the boulevard lane and press E on a brainrot to buy it.\nIt parks on your base and earns money every second.\nBuy upgrades, lock your base against the Sneaky Snatcher,\nand Rebirth for a permanent income multiplier!"
howTo.TextColor3 = Color3.fromRGB(220, 220, 220)
howTo.TextScaled = true
howTo.Font = Enum.Font.SourceSans
howTo.Parent = startScreen

-- HUD (top-right; the top-left corner belongs to Roblox's menu buttons).
local hud = Instance.new("Frame")
hud.Name = "Hud"
hud.AnchorPoint = Vector2.new(1, 0)
hud.Position = UDim2.new(1, -10, 0, 10)
hud.Size = UDim2.new(0, 260, 0, 150)
hud.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hud.BackgroundTransparency = 0.35
hud.BorderSizePixel = 0
hud.Parent = gui

local function hudLine(name, y, text)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.new(0, 10, 0, y)
	label.Size = UDim2.new(1, -20, 0, 22)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 18
	label.Font = Enum.Font.SourceSansBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = hud
	return label
end

local cashLabel = hudLine("Cash", 8, "Cash: $100")
local rateLabel = hudLine("Rate", 32, "$0/s")
local countLabel = hudLine("Count", 56, "Brainrots: 0/6")
local rebirthLabel = hudLine("Rebirths", 80, "Rebirths: 0 (x1)")
local lockLabel = hudLine("Lock", 104, "Base: Unlocked")
local rushLabel = hudLine("Rush", 128, "")

-- Buttons (right side, under the HUD).
local buttons = Instance.new("Frame")
buttons.Name = "Buttons"
buttons.AnchorPoint = Vector2.new(1, 0)
buttons.Position = UDim2.new(1, -10, 0, 170)
buttons.Size = UDim2.new(0, 260, 0, 260)
buttons.BackgroundTransparency = 1
buttons.Parent = gui

local function makeButton(name, y, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.new(0, 0, 0, y)
	button.Size = UDim2.new(1, 0, 0, 36)
	button.BackgroundColor3 = color
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 16
	button.Font = Enum.Font.SourceSansBold
	button.Parent = buttons
	return button
end

local boostButton = makeButton("IncomeBoost", 0, "Income Boost ($1000)", Color3.fromRGB(90, 160, 255))
local speedButton = makeButton("WalkSpeed", 44, "Walk Speed ($800)", Color3.fromRGB(90, 160, 255))
local slotsButton = makeButton("ExtraSlots", 88, "Extra Slots ($1500)", Color3.fromRGB(90, 160, 255))
local rebirthButton = makeButton("Rebirth", 132, "Rebirth ($1500)", Color3.fromRGB(170, 90, 255))
local lockButton = makeButton("LockBase", 176, "Lock Base ($500)", Color3.fromRGB(255, 170, 0))
local teleportButton = makeButton("Teleport", 220, "Teleport to Lane", Color3.fromRGB(255, 120, 60))

boostButton.MouseButton1Click:Connect(function()
	UpgradeRequest:FireServer("incomeBoost")
end)
speedButton.MouseButton1Click:Connect(function()
	UpgradeRequest:FireServer("walkSpeed")
end)
slotsButton.MouseButton1Click:Connect(function()
	UpgradeRequest:FireServer("extraSlots")
end)
rebirthButton.MouseButton1Click:Connect(function()
	RebirthRequest:FireServer()
end)
lockButton.MouseButton1Click:Connect(function()
	LockRequest:FireServer()
end)
teleportButton.MouseButton1Click:Connect(function()
	TeleportRequest:FireServer()
end)

-- Warning + result banners (top-centre).
local bannerLabel = Instance.new("TextLabel")
bannerLabel.Name = "Banner"
bannerLabel.AnchorPoint = Vector2.new(0.5, 0)
bannerLabel.Position = UDim2.new(0.5, 0, 0.08, 0)
bannerLabel.Size = UDim2.new(0.7, 0, 0.06, 0)
bannerLabel.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
bannerLabel.BackgroundTransparency = 0.2
bannerLabel.Text = ""
bannerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
bannerLabel.TextScaled = true
bannerLabel.Font = Enum.Font.SourceSansBold
bannerLabel.Visible = false
bannerLabel.Parent = gui

local bannerUntil = 0
local function showBanner(text, color)
	bannerLabel.Text = text
	bannerLabel.BackgroundColor3 = color
	bannerLabel.Visible = true
	bannerUntil = os.clock() + 4
end

Warning.OnClientEvent:Connect(function(text)
	showBanner(text, Color3.fromRGB(200, 30, 30))
end)
Banner.OnClientEvent:Connect(function(text, color)
	showBanner(text, color)
end)

-- DIAG panel (bottom-left, from the CLIENT's view).
local diag = Instance.new("TextLabel")
diag.Name = "Diag"
diag.AnchorPoint = Vector2.new(0, 1)
diag.Position = UDim2.new(0, 10, 1, -10)
diag.Size = UDim2.new(0, 420, 0, 170)
diag.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
diag.BackgroundTransparency = 0.2
diag.TextColor3 = Color3.fromRGB(255, 255, 0)
diag.TextSize = 15
diag.Font = Enum.Font.Code
diag.TextXAlignment = Enum.TextXAlignment.Left
diag.TextYAlignment = Enum.TextYAlignment.Top
diag.Text = "DIAG: waiting..."
diag.Parent = gui

local function partLine(name)
	local part = Workspace:FindFirstChild(name)
	if part then
		local p = part.Position
		return name .. ": YES (" .. tostring(math.floor(p.X)) .. ", " .. tostring(math.floor(p.Y)) .. ", " .. tostring(math.floor(p.Z)) .. ")"
	end
	return name .. ": MISSING"
end

local function refreshDiag()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local you = "you: ?"
	local dist = "dist to lane: ?"
	if root then
		local p = root.Position
		you = "you: (" .. tostring(math.floor(p.X)) .. ", " .. tostring(math.floor(p.Y)) .. ", " .. tostring(math.floor(p.Z)) .. ")"
		dist = "dist to lane: " .. tostring(math.floor(math.abs(p.Z - (-20))))
	end
	local seen = 0
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChild("Body") and child:FindFirstChild("NameTag") then
			seen += 1
		end
	end
	diag.Text = "DIAG\n"
		.. you .. "  " .. dist .. "\n"
		.. partLine("Baseplate") .. "\n"
		.. partLine("PlazaFloor") .. "\n"
		.. partLine("ConveyorLane") .. "\n"
		.. partLine("SpawnLocation") .. "\n"
		.. "brainrots seen: " .. tostring(seen)
end

-- HUD updates from the server.
HudUpdate.OnClientEvent:Connect(function(data)
	cashLabel.Text = "Cash: $" .. tostring(data.cash)
	rateLabel.Text = "$" .. tostring(data.rate) .. "/s (x" .. tostring(data.multiplier) .. ")"
	countLabel.Text = "Brainrots: " .. tostring(data.brainrots) .. "/" .. tostring(data.maxSlots)
	rebirthLabel.Text = "Rebirths: " .. tostring(data.rebirths) .. " (x" .. tostring(data.multiplier) .. ")"
	if data.lockRemaining > 0 then
		lockLabel.Text = "Base: LOCKED " .. tostring(data.lockRemaining) .. "s"
	else
		lockLabel.Text = "Base: Unlocked"
	end
	if data.rushActive then
		rushLabel.Text = "GOLDEN RUSH!"
	else
		rushLabel.Text = ""
	end
	boostButton.Text = "Income Boost Lv" .. tostring(data.boostLevel) .. " ($" .. tostring(data.boostCost) .. ")"
	speedButton.Text = "Walk Speed Lv" .. tostring(data.speedLevel) .. " ($" .. tostring(data.speedCost) .. ")"
	slotsButton.Text = "Extra Slots Lv" .. tostring(data.slotsLevel) .. " ($" .. tostring(data.slotsCost) .. ")"
	rebirthButton.Text = "Rebirth ($" .. tostring(data.rebirthCost) .. ") -> x" .. tostring(data.multiplier + 0.5)
	lockButton.Text = "Lock Base ($" .. tostring(data.lockCost) .. ", 60s)"
end)

playButton.MouseButton1Click:Connect(function()
	startScreen.Visible = false
	TeleportRequest:FireServer()
end)

-- Refresh loop: DIAG every second, hide banners after 4s.
task.spawn(function()
	while true do
		task.wait(1)
		refreshDiag()
		if bannerLabel.Visible and os.clock() > bannerUntil then
			bannerLabel.Visible = false
		end
	end
end)
