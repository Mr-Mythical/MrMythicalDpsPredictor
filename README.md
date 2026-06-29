# Mr. Mythical: DPS Predictor

Mr. Mythical: DPS Predictor helps you compare gear upgrades without running SimulationCraft on every drop.

This is not a stat weights addon. Tools like Pawn multiply your stats by fixed weights to guess at upgrades. That can work, but stats don't always add up that simply. The value of crit changes when you already have a lot of it, haste and mastery interact, and the right answer depends on your full gear set. Mr. Mythical uses a neural network trained on SimulationCraft batch data. The model is exported into the addon and runs locally on your machine, so estimates account for those interactions instead of treating every stat as a flat number. For most gear decisions, that's more accurate than traditional stat weights.

You can use it when loot shows up and you need a quick answer. The addon estimates how a piece compares to what you wear and shows **DPS vs equipped** on item tooltips, in your bags, and on journal loot. Open **Gear Advisor** with `/mrdps` to scan inventory, browse dungeon and raid drops, and rank crest upgrades.

You can also use it when a single item isn't the whole picture. **Find Loadout** searches combinations across the gear you select, so tier sets and slot synergies count, not just one swap at a time. It's not a full sim, but fast enough to use while you play. For trinkets, proc effects, and close calls, SimulationCraft is still the right tool.

---

**❤️ [Support on Patreon](https://www.patreon.com/c/mrmythical)**. Helps keep Mr. Mythical addons updated.

---

## Features

### Item tooltips

- DPS vs equipped on hover

### Gear Advisor: Bags

- Equipped item and alternates per slot
- Toggle which items to include, then equip from loadout results
- Great Vault rewards show up while the Great Vault window is open

### Gear Advisor: Dungeons & Raids

- Journal loot by instance or full current season
- Preview Champion, Hero, and Myth upgrade tracks
- Loadout results show which instance each piece comes from

### Gear Advisor: Crest upgrades

- Options ranked by DPS gained per crest spent

**Find Loadout** works in Bags and Dungeons & Raids. It evaluates full loadouts across your selected items, not single swaps. Shows progress while it runs and what to change vs what you wear now.

### Commands

- `/mrdps` opens the dashboard

## Limitations

This is an estimator, not a SimulationCraft replacement.

- Does not simulate rotations, trinket procs, or set bonus mechanics
- **Trinkets are not supported.** The model assumes BiS trinkets. Trinket slots are excluded from predictions.

For trinkets, proc effects, and close upgrade calls, use SimulationCraft.

## Download

[CurseForge](https://www.curseforge.com/wow/addons/mr-mythical-dps-predictor)

[Wago](https://addons.wago.io/addons/mrmythicaldpspredictor)

[GitHub](https://github.com/Mr-Mythical/MrMythicalDpsPredictor)

## Other Mr. Mythical addons

**[Mr. Mythical: Mythic+ Dashboard & Tooltips](https://github.com/Mr-Mythical/MrMythicalAddon)**. Keystone tooltips, score calculations, reward info, and a Mythic+ dashboard.

[CurseForge](https://www.curseforge.com/wow/addons/mr-mythical) · [Wago](https://addons.wago.io/addons/mrmythical)

**[Mr. Mythical: Leaderboard](https://github.com/Mr-Mythical/MrMythicalLeaderboard)**. Top Mythic+ runs from Raider.IO in your keystone tooltips.

[CurseForge](https://www.curseforge.com/wow/addons/mr-mythical-leaderboard) · [Wago](https://addons.wago.io/addons/mrmythicalleaderboard)

**[Mr. Mythical: Gear Check](https://github.com/Mr-Mythical/MrMythicalGearCheck)**. Checks your gear for common setup problems.

[CurseForge](https://www.curseforge.com/wow/addons/mr-mythical-gear-check) · [Wago](https://addons.wago.io/addons/mrmythicalgearcheck)

**[Mr. Mythical: Assistant](https://github.com/Mr-Mythical/MrMythicalAssistant)**. A unicorn companion with commentary and some automation.

[CurseForge](https://www.curseforge.com/wow/addons/mr-mythical-assistant) · [Wago](https://addons.wago.io/addons/mrmythicalassistant)

## Links

**[MrMythical.com](https://mrmythical.com)**. More Mythic+ and raid tools.

**[GitHub Issues](https://github.com/Mr-Mythical/MrMythicalDpsPredictor/issues)**. Bug reports and feature requests.

## Author

**Braunerr**