# Brainrot Boulevard

A 3D brainrot game for make.fun's "Make the best AI Roblox brainrot game"
bounty (roblox-brainrot-01). The second entry from this account: the first,
Brainrot Lane, is a working minimal game; this one is built to hit all four
of the AI judge's criteria, especially tension and progression.

## The game

Walk the boulevard, press **E** on a brainrot to buy it, and it parks on
your base and earns money every second. Buy the next tier, upgrade, and
climb the ladder.

- **Cast (criterion 2):** 11 original characters across 5 rarities
  (Common → Rare → Epic → Legendary → Mythic), each with a readable
  scale-sized name tag (name, rarity, $/s). A **Golden** mutation (12% of
  walkers) doubles the rate and the price.
- **Tension + progression (criterion 3), all real in the code:**
  - **Rebirths** — wipe cash + brainrots for a permanent +50% income
    multiplier per rebirth (shown in the HUD).
  - **Stealing with a lock** — the Sneaky Snatcher raids on a timer and
    steals your most valuable brainrot unless your base is locked
    ($500, 60s) or you bonk him 3 times (+$100, and he drops what he took).
  - **Three upgrades** — Income Boost (+25%/level, 5 levels), Walk Speed
    (+20%/level, 3 levels), Extra Slots (+2 slots/level, 2 levels).
  - **Timed events** — a Golden Rush every ~120s (30s of all-Golden
    walkers, faster spawns) and the Snatcher raid every ~90s, both with
    a 10s warning banner.
- **Look + polish (criterion 4):** a built 3D world (plaza, boulevard
  lane with neon rails, 4 bases, trees, beacons, a live status sign),
  a clear HUD (cash, $/s with multiplier, brainrot count, rebirths,
  lock status), buy/bonk/defend banners, and a start screen.

## How it is built

- `main.ts` (Node 22, standard library only) hands the game in: it copies
  `game.rbxl`, `src/`, `screenshots/` and `PLAY.json` to `/output`,
  leaving out every name that starts with a dot, and writes
  `/output/dossier.json` with `vendor/makefun-roblox.ts`, the kit's copy,
  unchanged.
- `game.rbxl` is the place Rojo builds from `src/` and
  `default.project.json`; `screenshots/` holds captures of it; `PLAY.json`
  names no place yet (the new experience has not been published — the
  owner publishes it, then PLAY.json is filled and the entry is submitted).
- One screenshot must also be the game's first thumbnail on Roblox: the
  same picture, uploaded on the Creator Dashboard with the game's icon.

## Hard lessons baked in (from the first game)

- Rojo 7.5.1 silently drops `Position` from `$properties`: static part
  positions are 12-number `CFrame` arrays in `default.project.json`, and
  the server's `fixStaticGeometry()` corrects Baseplate/SpawnLocation at
  startup (it runs first, before the world is built) and prints
  before→after positions.
- A folder with `init.server.luau` becomes a Script whose children are
  the sibling modules: the init requires `script.GameServer`, never
  `script.Parent.X`.
- Spawn is robust: `CharacterAutoLoads=true` + a static SpawnLocation in
  the place file + a CharacterAdded teleport. The pad is CanCollide=false
  and the teleport target (y=5) sits above the plaza (top y=2), so the
  character never lands inside a solid part.
- Buying uses ProximityPrompt (E, HoldDuration 0.25, range 12,
  RequiresLineOfSight false); ClickDetector is only a secondary.
- Name tags are scale-sized BillboardGuis on an Attachment, never
  fixed-pixel AlwaysOnTop.
- Bodies are balls or axis-aligned blocks only: no cylinders, no
  CFrame.Angles / fromEulerAngles anywhere; every move is a plain
  position change.
- The client shows a DIAG panel (bottom-left, refreshed every second)
  with the player's position, distance to the lane, each key part's
  existence + position from the client's view, and the brainrot count
  the client sees — one screenshot settles "the server works but I see
  nothing".

Run it as the grader does, writing `out/` in place of `/output`:

    mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

The rules are in the kit's RULES.txt.
