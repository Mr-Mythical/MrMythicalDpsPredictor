# Mr. Mythical: DPS Predictor

> **Estimated DPS upgrades for gear stat changes, powered by an exported neural model trained on SimulationCraft batch data.**

## What Does This Addon Do?

Mr. Mythical: DPS Predictor helps you evaluate gear upgrades without running full simulations. It uses a machine-learning model exported from SimulationCraft training data to estimate how stat changes affect your DPS compared to what you currently have equipped.

The main interface is **Gear Advisor**, a single window where you pick your hero talent profile, browse upgrade options, and search for optimal loadouts. Estimates can also appear directly on item tooltips as you hover gear in bags, loot windows, and vendors.

---

**❤️ Support development on [Patreon](https://www.patreon.com/c/mrmythical)** - Help keep Mr. Mythical and all our addons updated and feature-rich!

---

## Key Features

### **Item Tooltips**
See upgrade value at a glance while you play:
- **DPS vs equipped** on item tooltips (toggle in Gear Advisor)
- **Hero talent aware** — pick the profile that matches your current build
- **Compare all hero builds** (optional) — show estimates for every hero talent profile your spec supports

### **Gear Advisor — Bags**
Search your inventory for the best gear combinations:
- **Per-slot overview** — equipped item plus alternates, with DPS vs equipped on each candidate
- **Toggle selection** — choose which items participate in loadout search
- **Find Loadout** — searches combinations across selected items to find synergistic upgrades (tier sets, paired slots, and more)
- **Great Vault** — vault rewards are included automatically while the Great Vault window is open
- **Equip** — one-click equip for bag items from loadout results

### **Gear Advisor — Dungeons & Raids**
Plan loot upgrades from the Encounter Journal:
- **Instance picker** — single dungeon/raid or all current-season instances
- **Upgrade track preview** — Champion, Hero, and Myth track item levels
- **Per-slot scoring** — compare journal loot against your equipped gear
- **Find Loadout** — combination search across selected loot for best full loadout
- **Source tracking** — loadout results show which instance each piece comes from

### **Gear Advisor — Crest Upgrades**
Spend crests wisely:
- **Crest upgrade ranking** — options sorted by DPS vs equipped per crest spent
- **Upgrades-only filter** — focus on meaningful gains

### **Loadout Search**
Go beyond single-item upgrades:
- **Combination engine** — evaluates full loadouts, not isolated item swaps
- **Smart pruning** — tier set and embellishment rules reduce impossible combinations
- **Progress feedback** — combination counts and scan progress while searching
- **Current vs recommended** — results show what you wear now and what to change

### **Command & Access**
- `/mrdps` — open Gear Advisor
- **Minimap button** — left-click to open Gear Advisor
- **Addon compartment** — available from the addon menu on supported clients

## Important Limitations

Mr. Mythical: DPS Predictor is an **estimator**, not a SimulationCraft replacement.

- Does **not** simulate rotations, trinket procs, or set bonus mechanics in full
- **Trinkets are not supported** — the model assumes BiS trinkets; trinket slots are excluded from predictions
- **Hero talent profile must match your build** — specs with multiple hero trees (e.g. Hunter Survival) need the correct profile selected
- **MID1 tier scope** — model coverage matches the exported training tier; install a newer release when Mr. Mythical ships an updated model

For trinkets, proc effects, and close upgrade calls, use SimulationCraft.

## Requirements

- **World of Warcraft: Retail** (Interface version 120007)
- **`ModelData.lua`** must be present (included in release packages)
- Not compatible with Classic era clients

## Download

Get the latest version from your preferred addon manager:

[Download on CurseForge](https://www.curseforge.com/wow/addons/mr-mythical-dps-predictor)

[Download on Wago](https://addons.wago.io/addons/mrmythicaldpspredictor)

[Source on GitHub](https://github.com/Mr-Mythical/MrMythicalDpsPredictor)

## Installation

### Addon managers (recommended)
Install via CurseForge or Wago using the links above. Addon managers handle updates automatically.

### Manual install
1. Download the latest release from CurseForge, Wago, or GitHub
2. Ensure the addon folder is named **`MrMythicalDpsPredictor`** (it must match `MrMythicalDpsPredictor.toc`)
3. Copy the folder to `World of Warcraft\_retail_\Interface\AddOns\`
4. Confirm `ModelData.lua` is inside the folder
5. Restart WoW or type `/reload`
6. Type `/mrdps` or click the minimap button to open Gear Advisor
7. Select your **hero talent profile** if your spec has more than one

## Getting Started

1. Open Gear Advisor with `/mrdps` or the minimap button
2. Choose the **hero talent profile** that matches your current talents
3. Enable **Tooltip DPS vs equipped** if you want estimates on item hover
4. Pick a tab:
   - **Bags** — scan inventory and find combined loadouts
   - **Dungeons & Raids** — browse and plan journal loot upgrades
   - **Crest Upgrades** — rank crest spending by value
5. Toggle items you want considered, then click **Find Loadout** (Bags or Dungeons & Raids)

## Related Addons

Looking for more tools from Mr. Mythical? Check out our companion addons:

**[Mr. Mythical: Mythic+ Dashboard & Tooltips](https://github.com/Mr-Mythical/MrMythicalAddon)** - Enhanced keystone tooltips, score calculations, reward info, and a Mythic+ dashboard.

[Download on CurseForge](https://www.curseforge.com/wow/addons/mr-mythical)

[Download on Wago](https://addons.wago.io/addons/mrmythical)

**[Mr. Mythical: Leaderboard](https://github.com/Mr-Mythical/MrMythicalLeaderboard)** - Display top Mythic+ runs from Raider.IO directly in your keystone tooltips.

[Download on CurseForge](https://www.curseforge.com/wow/addons/mr-mythical-leaderboard)

[Download on Wago](https://addons.wago.io/addons/mrmythicalleaderboard)

**[Mr. Mythical: Gear Check](https://github.com/Mr-Mythical/MrMythicalGearCheck)** - Comprehensive gear validation for detecting common gear issues and preparation problems.

[Download on CurseForge](https://www.curseforge.com/wow/addons/mr-mythical-gear-check)

[Download on Wago](https://addons.wago.io/addons/mrmythicalgearcheck)

**[Mr. Mythical: Assistant](https://github.com/Mr-Mythical/MrMythicalAssistant)** - A sophisticated unicorn companion with witty commentary and helpful automation.

[Download on CurseForge](https://www.curseforge.com/wow/addons/mr-mythical-assistant)

[Download on Wago](https://addons.wago.io/addons/mrmythicalassistant)

## More Tools & Resources

Visit **[MrMythical.com](https://mrmythical.com)** for additional Mythic+ & Raid tools.

### **Want to report a bug or suggest a feature?**
Visit our [GitHub Issues](https://github.com/Mr-Mythical/MrMythicalDpsPredictor/issues) page for bug reports and feature requests.

## Author

**Braunerr** - Addon developer

---

**Mr. Mythical: DPS Predictor - Neural-model gear upgrade estimates with combination loadout search.**

*Part of the Mr. Mythical addon ecosystem.*
