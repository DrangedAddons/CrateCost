# Changelog

## 0.18.6
- Sealed writ tooltip odds: the likeliest tier is drawn bigger than the title and the others smaller, so the most probable outcome stands out. Tiers stay in quality order and the columns still line up. A tie draws all tied tiers big.

## 0.18.5
- Fixed "writ tooltip error: attempt to perform arithmetic on a secret number value" on Sealed writ tooltips. The odds columns are measured on CrateCost's own font string (a tooltip's report secret widths on Forever), and if the tooltip's position comes back secret the odds stay under the name instead of erroring.

## 0.18.4
- Sealed writ tooltip odds sit at the right, as two columns: the rating (right-justified) then its percent (left-justified, lined up).
- The odds read rating first everywhere ("Best 76%"), including the Writs window's envelope lines.

## 0.18.3
- Sealed writ tooltips stack the tier odds one per line under the name.

## 0.18.2
- Sealed writ tooltips put the tier odds right under the envelope's name ("76% Best  9% Good  16% Fair"), above the Use text, instead of in a list near the bottom. The details stay below with a one-line note on how they're worked out.

## 0.18.1
- Sealed writ envelopes no longer get one rating (the writ inside is random). Each shows the odds of each tier instead, e.g. "10% Great  30% Good  60% Poor": every writ of that rank rated as if it came out of the envelope (envelope price + its fill, per rep). Writs with no price yet are counted separately.
- The envelope lines are stacked one per rank, full width.

## 0.18.0
- Writs window shows your standing with the trade camp (Azeroth Commerce Authority / Durotar Supply and Logistics), e.g. "Neutral 1,200 / 3,000". If the camp isn't in your reputation list yet it counts as Neutral 0.
- **Target** dropdown (Friendly, Honored, Revered, Exalted; per character): shows the rep still needed, and each writ gets **Writs** (how many of it reach the target) and **To <target>** (what that many cost). Both sort.
- A line under the list names the cheapest shown writ to repeat until the target, with its total and the days it takes (each writ is a daily).
- Writ and Sealed writ tooltips show how many writs or envelopes reach the target and the cost.

## 0.17.1
- `/writs` and `/writ` open the writ list.

## 0.17.0
- **Writs** window (`/crates writs`, the Writs button on `/crates`, or ctrl-click the minimap button): all 150 Craftsman's Writs with the writ's AH price, the required item's AH price, the cost to craft it, the total, cost per reputation and a rating.
- Craft cost prices each reagent at Auctionator's vendor price, else its AH price, or crafts it when that's cheaper (bolts, cured leather and so on). The cheaper of buying and crafting the item is gold and counts toward the total.
- Ratings use the crate tiers (Best, Great, Good, Fair, Poor, Worst) on cost per reputation. Writs without an AH price are rated on the item alone and marked *.
- Under the list: each Sealed writ envelope's price plus that rank's average fill cost, as an expected cost per reputation.
- Columns for rank, skill, rep, what you hold (W = the writ, then the item count) and whether it's done today (each writ is a daily). Filter by profession, rank, writs on the AH, writs you have, or hide those done today.
- Writ and Sealed writ item tooltips show the same breakdown and rating (setting: "Rate Craftsman's Writs on their tooltips").
- Data: the writs come from wow.gg's Merchant's Favor guide and the recipes from endgametools.com, built by `tools/writs.py`. No other addon is needed.
- The rating setting's tooltip no longer says 0-10.

## 0.16.0
- Merchant list: **Sort by stat** dropdown, like CraftRoute's. Pick a stat (under Attributes, Spell, Physical, Defense, Resistances, Bags; only stats something in the list has) and switch between highest and lowest first. The stat's value leads each row's Effect cell, rows without it go last, and clicking a column header returns to column sorting.

## 0.15.0
- **Best** and **Worst** are kept for the single cheapest and dearest crate per favor (and any within 10c per favor of them), in their own colours: purple and deep crimson.
- The top ratio tier (up to 1.25x the cheapest) is now **Great**.

## 0.14.0
- Rating is four tiers with fixed, distinct colours instead of a 0-10 gradient: **Best** (up to 1.25x the cheapest favor, blue), **Good** (up to 1.75x, yellow), **Fair** (up to 3x, orange), **Poor** (over 3x, red).
- Tiers are set by the ratio to the cheapest crate, so crates sharing a label cost about the same per favor and one very expensive crate doesn't shift everyone else's rating.
- The `/crates` Rating column shows the tier and sorts by the ratio.

## 0.13.7
- The rating label moves to the right, under the crate name's row and above the bundle prices, lined up with the price column.

## 0.13.6
- Rating colours run red, orange, pale cream, then blue for the best, instead of ending in green (too close to the game's own green tooltip text).

## 0.13.5
- The crate list is built once and kept: names, bundles, item IDs and favor only change when a hovered crate shows new amounts or a new crate ID is found. Each refresh only re-prices it and recounts what you own, reusing the same tables.
- Auctionator prices are kept for one second, so a crate list refresh, its ratings and a crate tooltip don't look up the same items over and over.

## 0.13.4
- Efficiency pass:
  - Item tooltips that aren't Waylaid Crates are skipped by item ID before any work.
  - Crate ratings are cached (one crate tooltip used to work them out twice, on every tooltip refresh) and recomputed when crate data changes or after 5 seconds for new prices.
  - Hovering a crate only writes saved data when its bundles changed.
  - Crate item IDs ship with the addon, so the login scan of 200 item IDs is skipped (the crate list's Refresh button still scans).
  - Merchant list: learned recipes are checked when the window opens or you learn something, not on every keystroke; sort keys are worked out once per refresh; currency updates for other currencies no longer refresh it.

## 0.13.3
- The rating label sits right under the crate's name instead of at the top right, still big and outlined.

## 0.13.2
- The title-row rating is just the label (Best, Great, Good...) in a bigger outlined font. The score number is gone from it.

## 0.13.1
- The rating sits on the crate tooltip's title row, right of the name ("8.2 Great"). The rank and per-favor line stays under the favor line.

## 0.13.0
- Crate rating, 0-10, on crate tooltips, the `/crates` row tooltip and a sortable Rating column. It compares the crate's market cost per Merchant's Favor (crate + cheapest bundle) with every other crate on a log scale: 10 = the cheapest favor, 0 = the dearest. Labels: Best, Great, Good, Fair, Poor, Worst. The tooltip also shows its rank and how many times the cheapest favor it costs.
- Setting to hide the rating line.

## 0.12.1
- The Merchant list opens below and right of the crate list instead of on top of it, and remembers where you drag it. Clicking either window brings it to the front.

## 0.12.0
- Merchant list: separate Slot and Effect columns. Gear shows its stats (from CraftRoute's data) and its Equip / Use lines; Type shows the armor type.
- Stats filter like CraftRoute's: tick stats, optionally with a minimum. Search understands short forms (int, sp, mp5) and amounts ("+9 int").
- Favorites: click a row's star (per character), tick Favorites only, or sort favorites first.
- Hovering a row shows the crafted item's tooltip.

## 0.11.4
- The recipe list is now the **Merchant** list: Merchant button on `/crates` and in settings, `/crates merchant` (`/crates recipes` still works).

## 0.11.3
- Fixed: the X buttons on the crate list, recipe list, cart and settings windows now close them.

## 0.11.2
- Fixed: the recipe list opened as a blank window that wouldn't close. It registered an event this client doesn't have.

## 0.11.1
- `/crate` works as well as `/crates`.

## 0.11.0
- Renamed to **CrateCost** (was CrateValue). Settings: `/cratecost config`. `/crates` is unchanged.
- Merchant's Favor recipe list: every recipe the favor vendors sell, plus the mount, pet, tabard, title and certifications. Search, sort by any column, filter by profession or your own professions, hide learned recipes, or show only what you can afford. Open it from the Recipes button on `/crates`, `/crates recipes`, or shift-click the minimap button.

## 0.10.0
- Icon: the game's Merchant's Favor coin.
- Minimap button (left-click: crate list, right-click: settings) and an AddOn compartment entry.
- Settings window: `/cratevalue config`, the minimap button, or Options > AddOns > CrateValue. Turn the tooltip prices, cheapest-first order, gold highlight and Merchant's Favor line on or off, and hide the minimap button.

## 0.9.0
- Target favor: type how much Merchant's Favor you want and every cost, the new Crates column and the cart cover the crates needed to reach it.
- The row cart button is a red [+cart] button.

## 0.8.0
- Shopping cart: [+cart] on a `/crates` row adds the crate and its best bundle. The cart makes an Auctionator shopping list.
- Best bundle shows material, amount and unit price in aligned columns.

## 0.7.0
- Shift-click a `/crates` row to search Auctionator for the crate or its material.
- Column order: Crate, Crate cost, Best bundle, Bundle cost, Total cost.

## 0.6.0
- Crate tooltips list the cheapest bundle first.
- `/crates`: Bundle cost column, and a dropdown filtering by crate type or the profession a material comes from.

## 0.5.0
- Tooltip prices sit on their bundle's row, with gold, silver and copper in fixed columns.
- `/crates`: sortable columns, search, the crate's own AH price in the total, and a Market / My cost view.

## 0.4.0
- `/crates` window: every Waylaid Crate sorted by cost per Merchant's Favor.

## 0.1.0
- Auctionator price for each bundle on a Waylaid Crate tooltip, and the crate's Merchant's Favor.
