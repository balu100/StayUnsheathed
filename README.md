# StayUnsheathed (Standalone)

Keep your weapon **unsheathed** automatically when conditions allow.

This version is **standalone (no Ace3)** and is written to be **safe with Retail aura privacy (“secret” values)**.

## Features

* Auto-unsheath when you are **currently sheathed** (never accidentally sheath).
* Respects common restrictions:

  * No unsheathing in **combat** (configurable in code).
  * Avoids unsheathing while **in vehicle** / **pseudo-vehicle** auras (e.g., gliders).
  * Avoids unsheathing while **swimming and moving**.
  * Optional behavior in **resting areas (cities)**.
* Low overhead:

  * Uses a periodic ticker (`C_Timer.NewTicker`).
  * Uses `UNIT_AURA` (player-only) for faster reaction to aura/state changes.

## Compatibility

* Target: **WoW Retail (12.x)**.
* Uses `C_UnitAuras.GetAuraDataByIndex` when available; falls back to `UnitAura` for older clients.
* Handles “secret” aura fields safely via `pcall()`.

## Installation

1. Download / clone into:

   * `World of Warcraft/_retail_/Interface/AddOns/StayUnsheathed/`
2. Ensure these files exist:

   * `StayUnsheathed.toc`
   * `StayUnsheathed.lua`
3. No external libraries required.

## `.toc` setup

Make sure your `.toc` includes:

```toc
## SavedVariablesPerCharacter: StayUnsheathedDB
```

Remove any Ace3 `## OptionalDeps:` / `## Dependencies:` and any `libs\...` includes.

## Commands

* `/su help` — show help
* `/su status` — show current settings
* `/su enable` / `/su disable` / `/su toggle`
* `/su togglespec` — enable/disable per current spec
* `/su togglecity` — allow/deny in resting areas
* `/su setchecktimer X` — set ticker interval (seconds, minimum 1)

## How it works

* `UNIT_AURA` (for `player`) triggers an immediate re-check when your auras change.
* A repeating ticker also checks your sheath state every **X seconds** as a safety net.
* If you are **sheathed** and all conditions pass, it calls `ToggleSheath()`.

### Pseudo-vehicle detection

Some glider/vehicle-like effects are detected via a list of known spell IDs.
Retail can mark aura fields as **“secret”**; this addon protects lookups with `pcall()` to prevent errors.

## Configuration

Most settings are available via slash commands and stored in per-character SavedVariables:

* `EnabledState` (bool)
* `CityUnsheathed` (bool)
* `SheathStateCheckTimerInSeconds` (number)
* `Specs[]` (per-spec enable flags)

SavedVariables live in `WTF/Account/<AccountName>/<Realm>/<Character>/SavedVariables/`.

## Performance notes

* Uses `UNIT_AURA` (player-only) to react quickly to aura/state changes.
* The ticker still runs as a safety net; worst-case reaction time is bounded by the ticker interval.

Optional: If you prefer fewer event wakeups and can tolerate slower reaction time, you can disable aura-driven checks:

1. Remove `"UNIT_AURA",` from the `EVENTS` list.
2. Delete the `if event == "UNIT_AURA" then ... end` handler branch.

After this, behavior relies on the ticker + major events only.

## Troubleshooting

* If the addon doesn’t unsheath:

  * Ensure it’s enabled: `/su status`
  * Confirm you’re not in combat, in a vehicle, pseudo-vehicle, or swimming while moving.
  * Reduce interval: `/su setchecktimer 1`

## Development

* Single-file addon logic in `StayUnsheathed.lua`.
* No framework dependencies.
