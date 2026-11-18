-- Brainrot Boulevard: the cast.
-- Eleven original, absurd, meme-born characters on a ladder of five
-- rarities. Nothing here is copied from Steal a Brainrot or from the
-- earlier Brainrot Lane entry: every name, rate and price is new.
-- A Golden mutation (12% of walkers) doubles the rate and the price.

local BrainrotData = {}

BrainrotData.RARITY_COLORS = {
	Common = Color3.fromRGB(200, 200, 200),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(170, 90, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic = Color3.fromRGB(255, 60, 110),
}

BrainrotData.CAST = {
	{ name = "Sir Waddlesworth", rarity = "Common", rate = 4, price = 40, shape = "Ball", color = Color3.fromRGB(255, 220, 90), blurb = "a duck in a top hat who waddles for coins" },
	{ name = "Bloop the Blob", rarity = "Common", rate = 8, price = 80, shape = "Ball", color = Color3.fromRGB(110, 220, 110), blurb = "a jelly blob that hums elevator music" },
	{ name = "Captain Crumb", rarity = "Common", rate = 14, price = 140, shape = "Block", color = Color3.fromRGB(170, 120, 70), blurb = "a cookie pirate hunting for crumbs" },
	{ name = "Professor Picklejar", rarity = "Rare", rate = 25, price = 250, shape = "Ball", color = Color3.fromRGB(90, 180, 90), blurb = "a pickle in a lab coat, very serious" },
	{ name = "DJ Disco Duck", rarity = "Rare", rate = 45, price = 450, shape = "Ball", color = Color3.fromRGB(255, 120, 200), blurb = "a duck with headphones who drops beats" },
	{ name = "Baron von Bounce", rarity = "Epic", rate = 80, price = 800, shape = "Ball", color = Color3.fromRGB(150, 90, 255), blurb = "a bouncing baron in a velvet cape" },
	{ name = "Queen Quokka", rarity = "Epic", rate = 130, price = 1300, shape = "Block", color = Color3.fromRGB(255, 150, 60), blurb = "a quokka queen who smiles at gold" },
	{ name = "Sir Reginald Rumble", rarity = "Legendary", rate = 250, price = 2500, shape = "Ball", color = Color3.fromRGB(230, 60, 60), blurb = "a rumbling knight of the boulevard" },
	{ name = "Madame Moonbeam", rarity = "Legendary", rate = 400, price = 4000, shape = "Ball", color = Color3.fromRGB(180, 220, 255), blurb = "a moonbeam in a ballgown" },
	{ name = "The Golden Gherkin", rarity = "Mythic", rate = 500, price = 5000, shape = "Ball", color = Color3.fromRGB(255, 215, 0), blurb = "the one true gherkin, gilded" },
	{ name = "Emperor Moonpie", rarity = "Mythic", rate = 900, price = 9000, shape = "Block", color = Color3.fromRGB(60, 60, 180), blurb = "emperor of the midnight snack" },
}

-- Rarity weights for the spawn roll: commons show up most, mythics rarely.
BrainrotData.RARITY_WEIGHTS = {
	Common = 52,
	Rare = 26,
	Epic = 14,
	Legendary = 6,
	Mythic = 2,
}

BrainrotData.GOLDEN_CHANCE = 0.12

-- Pick one cast member, weighted by rarity. Returns the def table.
function BrainrotData.pickRandom()
	local total = 0
	for _, w in pairs(BrainrotData.RARITY_WEIGHTS) do
		total += w
	end
	local roll = math.random() * total
	local acc = 0
	local chosenRarity = "Common"
	for rarity, w in pairs(BrainrotData.RARITY_WEIGHTS) do
		acc += w
		if roll <= acc then
			chosenRarity = rarity
			break
		end
	end
	local pool = {}
	for _, def in ipairs(BrainrotData.CAST) do
		if def.rarity == chosenRarity then
			table.insert(pool, def)
		end
	end
	return pool[math.random(1, #pool)]
end

-- Roll the Golden mutation. Returns true when this walker is Golden.
function BrainrotData.rollGolden()
	return math.random() < BrainrotData.GOLDEN_CHANCE
end

-- The display rate and price of a walker, after the Golden multiplier.
function BrainrotData.walkerRate(def, golden)
	if golden then
		return def.rate * 2
	end
	return def.rate
end

function BrainrotData.walkerPrice(def, golden)
	if golden then
		return def.price * 2
	end
	return def.price
end

-- The tag line shown above a walker: name, rarity, $/s.
function BrainrotData.tagText(def, golden)
	local prefix = ""
	if golden then
		prefix = "Golden "
	end
	return prefix .. def.name .. "  " .. def.rarity .. "  $" .. tostring(BrainrotData.walkerRate(def, golden)) .. "/s"
end

return BrainrotData
