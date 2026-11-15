# Changelog

## 0.44.2
- Plan view: **Scan AH** button next to the target, the same scan as the writs view (writs, items, and the crates and bundles the plan's containers need), then the plan is made again.

## 0.44.1
- `/crate`, `/crates`, `/cratecost`, `/writ` and `/writs` on their own all open Home. The words after them work the same on all of them (`list`, `writs`, `plan`, `merchant`, `cart`, `config`).

## 0.44.0
- **Home**: a landing view with three cards (Crates, Writs, Rep), each with where you stand and a button into its view. `/crates` and the minimap button open it; `/crates list` opens the crate list, `/crates plan` the plan.
- The plan is a full view of the window (Plan on the nav bar), with its own Target picker and standing line, instead of a popup.
- Nav bar: Home, Crates, Writs, Plan, Merchant, Cart, Refresh.
- New file (Home.lua): restart the game client, /reload isn't enough.

## 0.43.0
- Writ plan costs are scan-accurate. Writs Scan AH now also reads every crate and bundle deep enough for the plan's containers (the crates to fill for the favor, and the empty crates), then remakes the plan with what it read.
- Costs priced past what the scan read, or not scanned at all, are marked **~** with a note to Scan AH. A crate the scan only surveyed is no longer priced as if every listed one cost the lowest price; asking for more than the survey saw listed counts as short.
- Shipping Label row: names the writ that gets you the label (start the plan's first writ: no extra cost), or the crate to fill when the plan has no writ.

## 0.42.0
- Writ plan: the containers are laid out as steps. **1. Buy + fill** N of the crate that earns the favor cheapest, picked from the AH listings for that many crates and bundles, less the turn-in silver, with the favor you already have subtracted. **2. Buy** the receipts (your camp's scribe). **3. Buy** the cheapest empty crates. **4. Hand in** the containers. Steps 1 and 3 have [+cart]; each step's tooltip breaks it down.
- The containers are re-costed at the real favor price for that amount, so the writ / container split uses it.
- Shorter "To Friendly" heading.

## 0.41.0
- Writ plan: guides you to Friendly, then onwards. After the Shipping Label quest (assumed done), **To Friendly** is writs only; **Friendly onwards** is the cheapest mix of writs and **Notarized Shipping Containers** (empty crate + 15 Merchant's Favor = 50 rep, no daily limit).
- A container costs the cheapest empty crate on the AH (scanned listings, else Auctionator) plus 15 favor at the crate list's cheapest favor (crate + bundle - turn-in silver, per favor). The plan picks how many containers against how many writs for the lowest total.
- The container row shows the count, empty crates, favor, per rep and cost; its tooltip names your camp's scribe and the cheapest favor crate. [+cart] and Add plan to cart add the empty crates.

## 0.40.0
- Writ plan: if this character hasn't done the one-time Shipping Label quest (2,000 rep, 50 Merchant's Favor; quests 98247 / 98248), it's the plan's first step and the writs cover only the rest. Its row says to fill a crate or start a writ, or to deliver the label you already have; the tooltip names your camp's NPC.

## 0.39.0
- Writ plan: one day. The cheapest writs you can do now (not done today), each once; if they can't reach the target it says how far they get, and Regenerate the next day plans the rest. No day headings: the writs are listed best value first, with the totals at the bottom.

## 0.38.0
- Writ plan: writs done today are left out of the plan's cost and rep (they wait for tomorrow). The ones it would have picked for day 1 still show, in red as "already filled today", outside the cost and cart, so you can tell when the best writs are used up. Writs handed in after the plan was made show (done). **Show writs done today** hides them.
- **Scan AH** on the writs window: reads every writ's and item's listings, deep enough for the plan. Writ prices, ratings and the plan use them.
- Plan window: Rep, Per rep and Cost no longer overlap on long amounts (right-aligned slots, wider window).

## 0.37.0
- Writ plan: a **[+cart]** button on each writ adds the writ and its fill. **Add plan to cart** (was Add day 1 to cart) adds the whole plan's. The writ goes in unless you have it; the fill is the item, or the recipe's reagents when the plan crafts it. Writs on CD only when shown.

## 0.36.3
- Writ plan: a **Per rep** column (each writ, and each day's total) and column headings.

## 0.36.2
- Writ plan rows show the writ's full tooltip (ratings, cost lines, reagents, who to deliver to), as on the writ list, plus its day, route, cost, cost per rep and whether it's on cooldown.

## 0.36.1
- Writ plan: Today / Next day are gone. The plan ignores cooldowns and marks writs done today **(on CD today)**; **Show writs on CD** (per character, on by default) hides them. The summary line counts them.
- The plan is kept as made until **Regenerate** (or a new target), so it doesn't shift as you hand writs in. Days are numbered Day 1, Day 2, and each day's writs are sorted best value first (lowest cost per rep). **Add day 1 to cart** skips hidden writs.

## 0.35.0
- Writ plan: **Today | Next day** buttons. Next day plans from tomorrow, with every writ off cooldown again (rep as it is now); Today leaves out writs done today. The choice also drives the summary line under the envelopes.
- Writs done today are marked **(on CD today)** in the plan, and the window counts how many are on cooldown. The cart button adds the plan's first day (today or tomorrow).

## 0.34.0
- Writs: **Plan** button. The cheapest writs that reach your rep target in the fewest days: all today when today's writs can reach it, else the fewest days it takes, cheapest writs within them. Each writ once a day, not ones done today. Writs you hold are free, items in your bags count, items are crafted when you have the profession and it's cheaper, the rest is bought up the AH listings (Scan AH) or at Auctionator's price.
- The plan window lists each day's writs by hand-in NPC with rep and cost. **Add today to cart** adds today's writs and items to buy.
- The line under the envelopes sums up the plan (writs, cost, days) instead of naming one writ to repeat.

## 0.33.0
- **Scan AH** button on /crates (at the auction house). Reads the real listings for every crate and bundle material, deep enough for the list (bundle amount x crates + 25%, at least 100 units), so fills are priced up the listings instead of the cheapest price x amount. The list, crate tooltips and ratings all use it.
- Red bundle cost = not enough listed; a bundle the AH can fully supply wins over one it's short of.
- Listings are kept per realm for 30 minutes, then prices fall back to Auctionator's. The footer says which is in use.
- New file (Depth.lua): restart the game client, /reload isn't enough.

## 0.32.1
- Fixed owned counts doubling with Syndicator (Baganator) on Forever: Syndicator saves the realm as the ruleset name ("PvP"), so this character wasn't recognised and was counted twice, live and as an alt. It now asks Syndicator which character is current.

## 0.32.0
- The turn-in silver each Sealed Crate pays back (2s 50c a rank for white, double for green; Artisan estimated) now comes off the crate's cost. /crates has a green **Turn-in** column; Total cost, Per favor and every rating (to Buy, to Fill, the craft lines) are net of it.
- Waylaid Crate tooltips show a "Turn-in pays" line under Merchant's Favor.

## 0.31.0
- Sealed Crate tooltips. Each rank has a white and a green Sealed Crate with the same name; the tooltip says which one it is (raw or crafted crate), the Merchant's Favor and silver its turn-in pays, and the total for a stack in your bags. Artisan values are estimates, marked "~".

## 0.30.3
- Owned view: **Who** is the first column. Crate / Crates (Writ .. Rep on the writ list) move right into the space the cost column left; Buy puts them back.

## 0.30.2
- Owned view: the crate / writ cost column becomes **Who**, the character that has it (yours in green, "+N" when more characters have some; the row tooltip lists them all). Sortable, this character first.

## 0.30.1
- Owned counts read the bag addons' records, so alts and their banks show up without logging each one in first: Syndicator (Baganator) first, with mail; else EllesmereUI Bags' offline bank. CrateCost's own records are the fallback. Only one source is used, so nothing counts twice; this character's bags are always read live.
- Row tooltips drop the "Amounts from the beta guide" and "Shift-click: search in Auctionator" lines.

## 0.30.0
- **Buy | Owned** replaces Market / My cost, on both lists (per character). Buy: crates or writs to buy. Owned: only the ones you have, on this character, its bank, the warband bank or alts, costed as the fill alone. Together with Buy / Craft bundles (items) it picks one cell of the tooltip grid, and the Rating column shows that cell. The target is hidden in Owned.
- Alts: each character's crates and writs (bags + bank) are saved when it logs in and when its bags change. The Have column counts all of them; the row tooltip says where ("2 here, 1 on Alty"). Item tooltips count them too.
- Writs: the "Writs I have" checkbox is gone (Owned does that).
- Crates, Writs and Merchant are one window now: the nav buttons swap the view in place instead of opening another window. They share one position and the same width.

## 0.29.0
- The Crates, Writs and Merchant windows now share one layout (new UI.lua): the same window shell, a title row with the target and status on the left and the same nav bar on the right (Crates, Writs, Merchant, Cart (n), Refresh; the current window greyed out), and a filter row with search and filters on the left and gold two-part toggles on the right.
- Crates: the Target favor box moves to the title row, next to how much favor you have, and the window shows how many crates match. View and Bundles become toggles (Market | My cost, Buy bundles | Craft bundles). Same width as the Writs window, columns grouped the same way.
- Crates window position is remembered, like the others.
- Writs footer brought up to date (AH vs crafted item, data from wow.gg and endgametools.com).

## 0.28.0
- /crates: **Bundles: Buy / Craft** toggle (per character), next to View. Craft prices the Fabrics, Ingots and Parts bundles from their reagents; the bundle columns read "Cheapest to craft" / "Craft cost" and total, per favor and rating follow. Raw crates don't change.
- A crafted crate whose bundles aren't on the AH (often engineering parts) still gets its craft ratings in the tooltip grid.

## 0.27.0
- Crafted crates (Fabrics, Ingots, Parts) get the writ treatment: a 2x2 rating grid under the name, Buy crate / Have crate by Buy bundle / Craft bundle, and four cost lines. Crafting uses whichever bundle is cheapest to make, named under the lines. Raw crates keep "to Buy / to Fill".
- Recipe data now covers the crafted crates' bundle items (bolts, cured hides, engineering parts, and bars: classic smelting added by hand, the source has none). Writ craft costs can use smelting too, when ore is cheaper than the bar.

## 0.26.0
- Writ tooltips rate all four ways to do a writ, as a 2x2 grid under the name: Buy writ / Have writ by Buy item / Craft item. New: buy the writ and craft the item. All four are measured against the cheapest rep you can buy outright. "?" = a price is missing, "-" = no recipe data.
- Four cost lines to match ("Buy writ + craft item (Engineering)" etc.), per rep and against the cheapest buy. The ones for your situation are white: whether you hold the writ, and craft lines only if this character has the profession.

## 0.25.0
- Writs window: a **Buy items | Craft items** toggle (per character) replaces the separate craft columns. One set of columns (item, total, per rep, rating, target) follows the toggle; craft mode rates writ + crafted item per rep against every writ's crafted cost. The window is back to its narrower width.
- Columns are grouped: the writ | the route | the rep target | what you have.

## 0.24.0
- Writs window: new **Total (craft)** and **Per rep (craft)** columns (writ + the crafted item), sortable like the rest.
- Columns are grouped by route with a gap between groups: the writ | Buy item, Total (buy), Per rep (buy), Rating | Craft item, Total (craft), Per rep (craft) | Writs, To target | Have, Today. The window is wider to fit them.

## 0.23.0
- Writ tooltips have three ratings under the name: **to Buy**, **to Fill** and **to Craft**. to Craft = a writ you have, filled by crafting the item, against the same cheapest-buy baseline as the other two. Shown for every writ with recipe data ("?" while a reagent has no price).
- The "Craft it" line becomes the third cost line, "If you craft it (profession)": cost per rep and how it compares with the cheapest buy. White if this character has the profession.

## 0.22.0
- Writ ratings, totals, per rep, the to-target costs and the Sealed odds use the item's AH price only. They used the cheaper of buying or crafting, which assumed everyone has the profession and recipe.
- Writ tooltips add a **Craft it (profession)** line when crafting is cheaper than buying: cost per rep and how much it saves a writ. White if this character has the profession, grey if not. The Buy / Craft columns in the list still show both.
- A writ whose item has no AH price shows "? to Buy / ? to Fill".

## 0.21.0
- **to Fill** is now measured against the cheapest favor (crates) or rep (writs) you can buy outright, the same number as **to Buy**, instead of against the cheapest fill of any other crate or writ. It answers "I have this, is filling it cheaper than buying elsewhere?": Best = at or under the cheapest buy, then the usual tiers. One near-free fill can no longer push every other fill to Poor.
- Both cost lines say how they compare with the cheapest buy ("0.4x the cheapest buy"). The fill line no longer has a rank.

## 0.20.0
- Writ tooltips get the crate treatment: "X to Buy" / "Y to Fill" under the name, same size. to Buy = writ + fill per rep (the list's rating); to Fill = the fill alone per rep against the cheapest fill of any writ. A writ with no AH price shows "? to Buy".
- The cost per rep shows both ways: "If you buy it" and "If you have it" ("You have N" when you hold the writ), the one that applies to you in white.

## 0.19.1
- "to Buy" and "to Fill" are the same size under the crate name (no bigger row for the one that applies to you).

## 0.19.0
- Crate tooltips show two ratings under the name: **to Buy** (crate + cheapest bundle per favor, the rating so far) and **to Fill** (cheapest bundle per favor against the cheapest fill of any crate). A crate can be Poor to Buy and Great to Fill. Both are the same for everyone; the one that applies to you is drawn bigger (Fill if you have the crate in bags or bank).
- The cost per favor shows both ways: "If you buy it" and "If you have it" ("You have N" when you do), each with its rank. The one that applies to you is white, the other grey.
- A crate with no AH price of its own shows "? to Buy" instead of a rating based on its bundle alone.

## 0.18.9
- Shift-click links are reliable: the crate and writ windows ask the server for all their items when they open, so links are ready before you click. A click on an item that still isn't loaded waits up to 5 seconds (and polls, in case the load callback never fires) instead of 1.
- Chat no longer gets the bare name in place of a link. If an item really won't load, CrateCost says so and you shift-click again. Search boxes still get the name.

## 0.18.8
- Shift-click works like the game's own item shift-click everywhere (crate list, writ list, sealed envelope lines, recipe list): it puts a real item link in an open chat box, and the AH / Auctionator search take it as a name. Any other focused edit box gets the plain name typed in.
- Items the client hadn't cached yet (crates, writs or mats only seen on the AH) used to go in as plain text. They're loaded first now, so they link too.

## 0.18.7
- Artisan crates get an estimated Merchant's Favor (20 raw, 40 crafted: the 5/10/15 and 10/20/30 pattern continued), so they're priced per favor and rated instead of "unknown yet". The estimate shows as "~20" in the tooltip ("Merchant's Favor (estimate)") and the /crates list. Swap in the real numbers in Data.lua once they're published.

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
