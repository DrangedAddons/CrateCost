# CrateCost

A WoW Forever addon for Waylaid Crates. It prices every way of filling a crate from your Auctionator data and shows the Merchant's Favor it pays.

Needs **Auctionator**. Prices are whatever Auctionator has (AuctionatorSync keeps them shared between friends).

## Crate tooltips

Hover a Waylaid Crate:

- each bundle gets its Auctionator price, with gold, silver and copper in their own columns
- the cheapest bundle is listed first and highlighted in gold
- a Merchant's Favor line shows what the crate pays (the same whichever bundle you use)
- a Turn-in pays line shows the silver its Sealed Crate pays back. Every cost and rating has it taken off
- two **Ratings** (Best, Great, Good, Fair, Poor, Worst) under the crate's name: **to Buy** (buying the crate and filling it) and **to Fill** (filling one you already have). Under the favor line, the cost per favor both ways, with rank and how it compares to the cheapest.

Hover a Sealed Crate (a filled crate, ready to turn in). Each rank has two with the same name: white from a raw crate, green from a crafted one (Fabrics, Ingots, Parts). The tooltip says which one it is, the Merchant's Favor and silver its turn-in pays, and the total for a stack in your bags:

| Rank | Favor (white / green) | Turn-in silver (white / green) |
|---|---|---|
| Apprentice | 5 / 10 | 2s 50c / 5s |
| Journeyman | 10 / 20 | 5s / 10s |
| Expert | 15 / 30 | 7s 50c / 15s |
| Artisan | ~20 / ~40 | ~10s / ~20s |

Artisan is an estimate (marked "~") until the real numbers are known.

### How the rating works

Each crate's market cost per favor is `p = (crate AH price + cheapest bundle - turn-in silver) / favor`. Crates without a known favor or any priced bundle aren't rated. Each rated crate is compared with the cheapest one (`ratio = p / cheapest p`) and gets one of four tiers, with Best and Worst kept for the extremes:

| Tier | Ratio to the cheapest favor | Colour |
|---|---|---|
| **Best** | the cheapest crate, or within 10c per favor of it | purple |
| Great | up to 1.25x | blue |
| Good | up to 1.75x | yellow |
| Fair | up to 3x | orange |
| Poor | over 3x | red |
| **Worst** | the dearest crate, or within 10c per favor of it | deep crimson |

Tiers by ratio keep each one tight: one very expensive crate can't drag mid-priced crates up a tier. A crate with no AH price of its own shows `? to Buy`.

The **to Fill** rating is for a crate you already have: `cheapest bundle / favor`, compared with the same number as to Buy, the cheapest favor you can buy outright (crate + bundle). At or under it is Best (filling beats buying favor anywhere); above it, the same tiers. So Poor to Fill means the bundle alone costs over 3x what buying and filling the cheapest crate does. Both ratings are the same for everyone, so a crate linked in chat reads the same for whoever hovers it.

**Crafted crates** (Fabrics, Ingots, Parts) show four ratings as a grid instead: **Buy crate / Have crate** by **Buy bundle / Craft bundle**. Crafting uses the bundle that's cheapest to make from its reagents (bolts and cured hides from Tailoring / Leatherworking, parts from Engineering, bars by smelting ore). Each has a cost line; yours are white (have the crate or not, and the craft lines only with the profession). Smelting recipes are the classic ones, added by hand: the recipe source has none. The `/crates` Rating column sorts by the ratio itself.

Hovering a crate also saves its real bundle amounts for the crate list. The beta guides don't always match the live game (Journeyman Textiles wants 20 Wool Cloth, not 40).

## Home: `/crates`, `/crate`, `/writs`, `/writ` (or the minimap button)

The landing view: your **reputation** across the top (the camp, a standing bar, a **Target** picker and rep to go, the Shipping Label quest, the rep plan's writs, containers and cost, **Open the rep plan**), then three tiles:

- **Crates**: crates you have (every character), Sealed Crates waiting to be handed in (and their favor), the cheapest favor crate and the AH scan's age. **Open crates**.
- **Merchant's Favor**: favor you have, a **Target** box and what's left, the favor plan's crates and cost. **Open the favor plan**.
- **Writs**: writs done today, writs you have, the cheapest rep writ. **Open writs**.

**Open the plan with the AH** (Home and both plans, per character, on by default): opening the auction house opens the plan you used last.

The bar on every view: **Home** (the way between views), **Cart** and **Refresh**. Merchant is on the favor card. `/crates list` opens the crate list, `/crates plan` the rep plan. The rep plan has its own **Target** picker, **Scan AH** and standing line.

## Buying at the auction house

When CrateCost makes a shopping list (a plan's **Create shopping list**, or the cart's), the **shopping dock** opens beside the auction house (or `/crates buy`, or the **Shopping list** button on the AH's right edge). It works through the list one item at a time: it searches the AH, shows what buying the rest of that item costs now against what CrateCost planned (over or under), and **Buy now** then **Confirm** buys a commodity in one purchase for the whole amount; an auction is bought a stack at a time. Then it moves to the next. **Skip**, an amount box, **Rescan item**, **Rescan list** (every item's price now on its row), and a menu on the list name to switch to any other Auctionator shopping list. The game only allows a purchase from a click.

The dock is [ShoppingDock](https://github.com/DrangedAddons/ShoppingDock), carried inside CrateCost (`ShoppingDock.lua`). Other addons that carry it (CraftRoute) share the same single dock and its *Show shopping list dock* setting.

## Buying at the vendor

With a vendor open, the favor plan's wanted recipes and the checklists' steps that a vendor sells (each wanted recipe, the Forged Delivery Receipts) show a **Buy** button: it buys the right item, the amount the step still needs.

## Closing

Closing a view (its X or Escape) goes back to Home; closing Home closes the window.

## Plan options

Two tickboxes in both plans (per character, shared, on by default):

**Buy | Craft** (top right of both plans, per character, shared, Craft by default): **Buy** buys everything on the AH, no crafting. **Craft** makes what your professions can, a writ's item when you have the profession at its skill, and Fabrics, Ingots and Parts bundles, when that's cheaper than buying; everything else is bought. Crafted rows say "craft", and the cart leaves crafted items out.

- **Use writs/crates you have**: writs you hold (any character) are free in the rep plan; crates you hold and the Sealed Crates in your bags count in the favor plan and for the rep plan's container favor. They're used where they're worth it: a writ you hold costs nothing, so it's picked first among writs worth the same rep. Untick to plan as if you had none.
- **Use materials in bags & bank**: items and bundle materials you already have count, and the cart leaves them out. Untick to buy everything on the AH.

## Checklists

**Checklist** (on Home and in each plan's footer) pops out a small window with just the plan's steps, a progress bar on top (rep to the target, or favor) and a count on the steps that have one ("78 / 90 crates"). Everything ticks itself:

- quests and writs handed in (a writ done during the plan stays done past the daily reset);
- Sealed Crates as they leave your bags;
- receipts and notarized containers counted in your bags by name, plus those already used;
- empty Waylaid Crates in your bags;
- favor earned and containers handed in, from your favor and rep since the plan was made.

Writ and crate steps show the item with its icon and quality colour (hover for its tooltip), and under them the fill with how many you have of what's still needed. The step you're on is highlighted gold, done steps green, and a step with a count fills as it goes. Hover a step for its details. It drags anywhere, resizes from its bottom-right corner, scales with Ctrl + mouse wheel, shows a scrollbar when there's more than fits, scrolls to where you're up to, reopens after a reload, and starts again with a new plan.

## Checklists

**Checklist** (on Home and in each plan's footer) pops out a small window with just the plan's steps: do the Shipping Label quest, fulfil this writ, hand in these Sealed Crates, buy + fill these crates, buy 120 receipts, buy 120 empty crates, hand in the containers, reach the target. Steps the game can see tick themselves (quests and writs handed in, Sealed Crates gone, favor or the target reached); the rest you tick by clicking. Hover a step for its details. It opens at the first step not done, scrolls, can be dragged anywhere, and reopens after a reload if it was open. A new plan (Regenerate, another target) starts the list fresh.

## Favor plan

Two panes. On the **left**, the Merchant's recipes and items: search them, show only your professions or hide what you've learned, hover for the item or recipe, and **Add** what you want (**Drop** takes it off). On the **right**, the plan: your wanted list first, each with its favor and a running total of what's still to buy, then how to get that favor. The target follows the wanted list (untick **Target = wanted recipes**, or type a number, for your own).

Favor you have and Sealed Crates in your bags count first, then the one-time Shipping Label quest (50 favor), then crates picked one at a time from the scanned listings: each next crate is the cheapest per favor, so a kind is dropped once its cheap crates or bundles run out (near the target, one that finishes it for less wins). Crates you hold and materials in your bags come first, the rest is bought up the AH listings, less the turn-in silver; only crates your level can fill. Each row: buy + fill N of a crate, with which bundle, favor, per favor and cost, and [+cart]; hover for the breakdown. With a vendor open, **Buy** shows on the wanted recipes it sells. **Scan AH** reads every crate and bundle deep enough for what's left, then remakes the plan; costs past what it read are marked **~**.

## Crate list: `/crates list` (or Crates on the nav bar)

Every Waylaid Crate, sorted by the cheapest Merchant's Favor:

| Column | |
|---|---|
| Crate | name, coloured by rank |
| Crates | how many you need for the target favor |
| Crate cost | the crate's own AH price |
| Best bundle | material, amount, price per unit |
| Bundle cost / Total cost | the materials, and crate + materials |
| Favor / Per favor | favor per crate, and total cost per favor |
| Rating | Best / Great / Good / Fair / Poor / Worst against the other crates (see above) |
| Have | crates in your bags and bank |

- Click a header to sort; click again to reverse.
- Search by crate or material name.
- The dropdown filters by crate type, or by the profession a material comes from (then only that profession's bundles count).
- **Target favor**: type how much you want (say 60) and every cost, and the cart, covers the crates needed to reach it.
- Crates, Writs and Merchant are three views of one window: the nav bar on the right of the title row (**Crates, Writs, Merchant, Cart, Refresh**; the view you're in is greyed out) swaps the view in place. Each has the title and target on the top row, search and filters on the second row, and the mode toggles at its right end.
- **Buy / Owned** (per character). Buy: crates to buy, crate + bundle. Owned: only the crates you have, on this character, its bank, the warband bank or alts (read from Syndicator / Baganator or EllesmereUI Bags' offline bank when either is installed, so alts count straight away; otherwise an alt counts once it has logged in with CrateCost), costed as filling all of them, with materials on this character subtracted. The **Who** column (first in the Owned view, in place of the crate cost) names the character that has them, "+N" for more; the row tooltip lists every one. The target only applies to Buy.
- **Buy bundles / Craft bundles** (per character). Craft prices the Fabrics, Ingots and Parts bundles as made from their reagents: the bundle column becomes **Cheapest to craft / Craft cost**, and total, per favor and rating follow (the rating is buy crate + craft bundle). Other crates are the same either way. The cart still adds the bundle items.
- **Scan AH** (at the auction house): reads the real listings for every crate and bundle material, deep enough for what the list needs (bundle amount x crates, plus 25%, at least 100 units). Fills are then priced up the listings: 10 Bruiseweed with 5 listed at 1s and the rest at 2s costs 15s, not 10s. The tooltips and ratings use the same listings. A **red** bundle cost means the AH doesn't have enough listed; a bundle it can fully supply is picked over one it's short of. Listings are used for 30 minutes, then prices fall back to Auctionator's lowest price x amount. The footer says which is in use. While it runs the button becomes a progress bar with the status inside; click the bar to stop (what was read is kept).
- Hover a row for every bundle's price. Shift-click a row to search Auctionator: the bundle columns search the material, the rest the crate.

## Shopping cart

**[+cart]** on a row adds the crate and its best bundle's materials. The cart lets you tick items, change amounts and remove them, then **Create Shopping List** makes an Auctionator shopping list. The cart is kept per character.

## Merchant list

The **Merchant** button on `/crates`, `/crates merchant`, or shift-click (or middle-click) the minimap button: all 308 recipes the Durotar Supply / Azeroth Commerce vendors sell for Merchant's Favor, plus the mount, pet, tabard, title and profession certifications.

- Columns: favorite star, recipe, profession, type (armor type for gear), skill, required level, slot, effect, reputation, favor cost, learned. Click a header to sort.
- Effect is the item's stats or the potion / enchant effect, plus the crafted item's Equip / Use lines once the game has loaded the item.
- Search matches name, profession, type, slot and effect, with short forms like CraftRoute's (int, agi, sp, mp5) and amounts ("+9 int").
- **Stats** dropdown: tick stats to show only items that have all of them, and type a minimum to need at least that much.
- **Sort by stat**: order the list by one stat (grouped like CraftRoute: Attributes, Spell, Physical, Defense, Resistances, Bags), highest or lowest first. The value leads the Effect column and rows without the stat go last. Click a column header to go back to column sorting.
- Click the star to favorite a row (kept per character). **Favorites only** shows just those; the star header sorts favorites first.
- Filter by profession or "My professions", hide recipes you've learned, or show only what your current favor can buy (affordable costs are green).
- Hover a row for the crafted item's tooltip (the enchant's for enchants). Shift-click links it in chat.

## Writs

The **Writs** button on the nav bar, `/crates writs`, or ctrl-click the minimap button: all 150 Craftsman's Writs (Alchemy, Blacksmithing, Engineering, Leatherworking, Tailoring), sorted by the cheapest reputation.

- **Buy items | Craft items** toggle (per character): which way the list gets each writ's item. Buy uses the AH price; Craft uses the item crafted from its reagents (needs the profession). The item, total, per rep, rating and target columns follow it. In craft mode a writ with no recipe data shows "-".
- **Writ cost**: the writ on the AH. **Buy item**: the required item on the AH. **Craft item**: its reagents, each at the vendor price (from Auctionator's vendor cache), the AH price, or crafted when that's cheaper. The cheaper of buy and craft is gold.
- **Total** = writ + the item bought on the AH. Ratings and totals don't assume you can craft: crafting needs the profession and recipe. Writ tooltips show four ratings as a grid under the name: **Buy writ / Have writ** by **Buy item / Craft item**, all against the cheapest rep you can buy outright (buy writ + buy item), with one cost line each. Lines for your situation are white (whether you hold the writ; craft lines only if you have the profession). A writ whose item has no AH price isn't rated. **Per rep** = total / the writ's reputation (75 Journeyman, 125 Expert, 200 Artisan).
- **Rating**: the crate tiers on cost per rep. A writ with no AH price is rated on the item alone and marked *.
- Writ tooltips show two ratings under the name, like crates: **to Buy** (writ + fill per rep) and **to Fill** (the fill alone per rep, for a writ you already have, against the cheapest rep you can buy outright: writ + fill), and the cost per rep both ways. A writ with no AH price shows `? to Buy`.
- **Have**: W if you hold the writ, then how many of the item you have. **Today**: the writ's daily is done.
- **Standing** with the trade camp is shown at the top. Pick a **Target** standing (per character) and each writ shows how many of it you'd need (**Writs**) and what they'd cost (**To <target>**). The line under the envelopes sums up the plan.
- **Plan** (under the envelopes): the cheapest writs you can do now that reach your target. If you haven't done the one-time **Shipping Label** quest yet (fill any crate or start a writ, deliver the label at the camp: 2,000 rep and 50 Merchant's Favor), it's the plan's first step and the writs only cover the rest. Then it goes in stages: **To Friendly** in writs (Notarized Shipping Containers need Friendly), then **Friendly onwards**, the cheapest mix of writs and **Notarized Shipping Containers**: a Forged Delivery Receipt (15 Merchant's Favor) on an empty Waylaid Crate, 50 rep each, no daily limit. A container costs the cheapest empty crate on the AH plus 15 favor at the cheapest favor the crate list can buy (crate + bundle, less the turn-in silver, per favor); favor you already have counts at that price. Writs cheaper per rep than a container are used first, containers cover the rest. The containers are laid out step by step (the favor they earn and spend shows grey in the Rep column, not counted as rep): **1. Buy + fill** N of the crate that earns the favor cheapest (picked from the AH listings for that many, with its bundle, less the turn-in silver; favor you have is subtracted), **2. Buy** the receipts from your scribe, **3. Buy** the empty crates (the cheapest on the AH), **4. Hand in** the containers. Steps 1 and 3 have [+cart] buttons; hover any step for the breakdown. A cost marked **~** goes past what the AH scan read (or wasn't scanned), so it's too low: **Scan AH** on the writs window reads every writ and item, and every crate and bundle deep enough for the plan's containers, then remakes the plan with the real listings. The Shipping Label row names the writ that gives you the label (starting the plan's first writ), so it costs nothing extra. Each writ is a daily, so each is used once and writs already done today are left out; if they can't reach the target the plan says how far they get, and **Regenerate** the next day plans the rest. Writs you hold come first (free), items in your bags count, items are crafted when you have the profession and that's cheaper, and everything else is bought up the AH listings (Scan AH, else Auctionator's price). The window lists the writs best value first (lowest cost per rep), with how to get the writ and the item, rep, cost per rep and cost; hover one for the writ's full tooltip and its place in the plan. The writs the plan would have picked if they weren't done yet stay listed in **red** as "already filled today" (outside the cost and the cart), so you can see when the best writs are used up; writs handed in after the plan was made show **(done)**. **Show writs done today** (per character, on by default) hides both. The plan stays as it was made while you hand writs in or prices move; **Regenerate** makes it again (a new target does too). **Create shopping list** gathers the whole plan's buys (each writ unless you have it, its fill or the fill's reagents when the plan crafts it, the containers' crates and bundles), opens them for review (untick, change amounts, name it), then makes the Auctionator shopping list. The cart isn't touched.
- **Scan AH** (writs window, at the auction house): reads the listings for every writ and its item, deep enough for the plan, the same way as the crate list's scan. Writ prices, ratings and the plan use them for 30 minutes.
- Under the list, each Sealed envelope (a random writ of that rank): its price + the rank's average fill = the average cost per rep, and the **odds** of each tier: every writ of the rank rated as if it came out of the envelope (envelope price + its fill). This assumes each writ of a rank is equally likely, and writs without a price aren't counted.
- **Buy / Owned** works like the crate list's: Owned lists only writs you have (including bank, warband bank and alts), costed as the item alone. Filter by profession, rank, writs on the AH, or hide those done today. Hover a row for the reagent breakdown and the recipient. Shift-click searches Auctionator (the item columns search the item, the rest the writ).
- Writ and Sealed writ tooltips in your bags show the same breakdown and rating.

## Settings

`/cratecost config`, right-click the minimap button, or Options > AddOns > CrateCost:

- bundle prices on crate tooltips, cheapest first, gold highlight, the Merchant's Favor line, the rating
- the writ rating on writ tooltips
- the minimap button (left-click: crate list, shift- or middle-click: merchant list, ctrl-click: writs, right-click: settings)

## Data

- Recipes, costs and reputation come from wow-professions.com's Merchant's Favor guide. Crafted item IDs and base stats come from CraftRoute's Forever recipe data (`tools/join.py` rebuilds Recipes.lua from both).
- Writs (writ and quest IDs, required item, skill, rank, reputation, recipient) come from wow.gg's Merchant's Favor guide. What each item is made from comes from endgametools.com's Forever profession pages (`tools/writs.py` rebuilds Writs.lua from both).
- Favor per crate comes from wow-professions.com's beta tables: raw goods 5/10/15, crafted goods (Fabrics, Ingots, Parts) 10/20/30 for Apprentice/Journeyman/Expert. Artisan isn't published yet, so CrateCost uses an estimate of 20 raw / 40 crafted, shown as "~20" and labelled as an estimate.
- Crate item IDs are found by name at login. Material IDs and professions were checked against CraftRoute's Forever data.
