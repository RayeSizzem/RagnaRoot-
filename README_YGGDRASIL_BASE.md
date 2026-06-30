# Yggdrasil — Game Base (v0)

A minimal, runnable foundation for the tower-defense / town-builder world-tree game.
This is the skeleton the GDD's systems hang off — the clock ticks, the tree grows,
tides fire, and the world meter counts toward 7.

## Install

1. Extract `scenes/` and `scripts/` into `H:\Godotgame\yggdrasil\` (project root).
2. Follow `project_additions.txt` to register the two autoloads and set the main scene.
3. Press **F5** and pick `res://scenes/main.tscn` if prompted.

## Assign the twisted tree model

The World Tree spawns a crude placeholder (trunk + canopy) so it runs out of the box.
To use the real model:

- Open `res://scenes/world_tree.tscn` (or select the **WorldTree** node inside `main.tscn`).
- In the Inspector, find **Twisted Tree Model** and drag the twisted tree asset onto it.
- Run again — it'll instance that model and scale it up as the tree grows.

(If you'd rather I hardcode the path, send me the asset's `res://...` path.)

## What you'll see

A small debug panel (top-left):

- **Day X / 15 · Cycle N · Phase** — the 15-day clock.
- **Tree stage** — Sapling → Sentinel → Greatbough → Canopy → Worldcrown.
- **Sap into tree** — progress toward the next stage.
- **World Trees crowned: 0 / 7** — the campaign meter.

Buttons:
- **Channel Sap (+25)** — feeds the tree; watch it advance stages and scale up.
- **Advance Day** — steps the clock. On day 15 a Dark Tide fires (auto-resolves
  after ~2s for now), then the next cycle begins. Every 4th tide is a Long Night.

Channel enough Sap to hit Worldcrown and the tree reports `crowned` → the world
meter ticks up. (Crowning currently just increments the meter; Seed/escort/transit
flow is next.)

## How the files map to the GDD

| File | Role |
|------|------|
| `scripts/autoload/game_state.gd` | 15-day clock, cycles, tides, world meter |
| `scripts/autoload/resource_manager.gd` | Sap/Authority/Timber/Forage/Glow/Folk economy (scaffold) |
| `scripts/world_tree.gd` | 5-stage growth state machine; loads the tree model |
| `scripts/tide_manager.gd` | Day-15 tide responder (stub; enemy spawns go here) |
| `scripts/debug_hud.gd` | Throwaway test UI |
| `scenes/world_tree.tscn` | The tree (Node3D + ModelHolder) |
| `scenes/main.tscn` | Camera, light, ground, tree, tide manager, HUD |

## Next steps (not in this base)

- Light field / buildable zone + root-lane pathing
- Settling the first people (Humans) and the gather→Sap loop feeding `channel_sap`
- Real enemy waves in `tide_manager.gd`
- Seed → 10-unit escort → transit → found-next-continent handoff
- Per-stage tree models (swap instead of scale)
