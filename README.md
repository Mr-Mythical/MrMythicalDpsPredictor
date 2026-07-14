# Mr. Mythical: DPS Predictor & Gearing Dashboard

**Gearing dashboard for your best loadout from your bags or the season, optimal crest upgrades, and Great Vault advice - powered by a neural-net DPS prediction model.**

Loot drops. Everyone's waiting. Is it an upgrade?

Mr. Mythical: DPS Predictor & Gearing Dashboard answers that on every tooltip, and the same model powers everything in the dashboard: scan **every drop in the current raid and Mythic+ season** to build your best possible gear set, rank **every crest upgrade you can afford** by DPS gained per crest spent, and pick the right Great Vault reward before you lock it in.

---

**❤️ [Support on Patreon](https://www.patreon.com/c/mrmythical)**. Helps keep Mr. Mythical addons updated.

**💬 [Join the Discord](https://discord.gg/jHMvF4VZMw)**. Questions, feedback, and prediction talk welcome.

---



## Not another stat weights addon

Most gear tools multiply your stats by fixed weights and add them up. That approximation breaks down constantly: the value of a stat drops as you stack it, haste and mastery interact differently for every spec, and the "right" answer depends on your entire gear set, not one number per stat.

Mr. Mythical: DPS Predictor & Gearing Dashboard uses a **neural network trained on large batches of SimulationCraft data**, with dedicated profiles for every DPS and tank spec, including hero talent variants. The trained model ships inside the addon and runs entirely on your machine. There are no server calls, no importing weights, and nothing to configure. Because the model has seen how stats actually interact across thousands of simulated gear sets, it captures diminishing returns and stat synergies that flat weights simply can't.

It's not a full simulation, but it's dramatically closer to one than stat weights, and it's fast enough to answer while the loot roll is still open.

## Instant answers on every tooltip

Hover any item and see its predicted DPS change versus what you're wearing, right on the tooltip. Works in your bags, on loot, in the Adventure Journal, and in chat links.

Item tooltip showing +1335 DPS versus the equipped item

## Your best loadout, not just single swaps

Open the gearing dashboard with `/mrdps`. The **Bags** tab scans everything you own and searches for your best possible *combination* of gear. This matters because upgrades aren't independent: swapping your belt can change which ring is best. The Find Loadout engine evaluates full loadouts, so slot synergies count, then shows you exactly what to equip, with one-click **Equip** buttons.

Gearing Dashboard Bags tab showing the best loadout with per-slot recommendations and Equip buttons

## Scan the entire season for your best possible gear

The **Dungeons & Raids** tab scans journal loot from a single instance or the **entire current season** and finds the strongest set of drops for your character. Preview items on Champion, Hero, or Myth upgrade tracks, and see exactly which boss and instance every recommended piece comes from, so you know precisely which dungeons to run and which bosses to target.

Dungeons & Raids tab showing best-in-slot recommendations from across the season with their sources

## Spend your crests where they matter most

Crests are limited, so spending them well matters. The **Crest Upgrades** tab reads your currencies, evaluates every upgrade you can afford, and builds a step-by-step plan ranked by **DPS gained per crest spent**.

Crest Upgrades tab showing a ranked step-by-step upgrade plan with DPS per crest

## Great Vault, decided

When you open the Great Vault, the addon evaluates every reward on offer and tells you which one is your biggest DPS gain, before you lock in your pick.

Great Vault window with the addon recommending the highest-DPS reward

## Features at a glance

- **DPS vs. equipped on every item tooltip**, instantly and locally
- **Neural network predictions** trained on SimulationCraft data, per spec and hero talent
- **Find Loadout**: searches gear combinations, not single swaps, so set and slot synergies count
- **Full season scan**: find your best possible gear across all current raid and dungeon loot
- **Upgrade track preview**: compare drops at Champion, Hero, and Myth item levels
- **Crest upgrade planner**: ranked by DPS gained per crest spent
- **Great Vault advisor**: know your best pick before you choose
- **Supports all DPS and tank specs**, including hero talent profiles



## Commands

- `/mrdps` — open the gearing dashboard



## Honest limitations

This is a fast estimator, not a SimulationCraft replacement.

- Rotations, trinket procs, and set bonus mechanics are not simulated
- **Trinkets are not supported.** The model assumes best-in-slot trinkets, and trinket slots are excluded from predictions

For trinket comparisons, proc-heavy effects, and razor-thin upgrade calls, SimulationCraft remains the right tool. For everything else, this gets you a near-sim answer in the time it takes to hover an item.

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