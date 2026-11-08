# CrateCost

A WoW Forever addon for Waylaid Crates. It prices every way of filling a crate from your Auctionator data and shows the Merchant's Favor it pays.

Needs **Auctionator**. Prices are whatever Auctionator has (AuctionatorSync keeps them shared between friends).

## Crate tooltips

Hover a Waylaid Crate:

- each bundle gets its Auctionator price, with gold, silver and copper in their own columns
- the cheapest bundle is listed first and highlighted in gold
- a Merchant's Favor line shows what the crate pays (the same whichever bundle you use)
- a **Rating** (Best, Great, Good, Fair, Poor, Worst) against every other crate, under the crate's name, above the price column, with its rank and how it compares to the cheapest favor under the favor line

### How the rating works

Each crate's market cost per favor is `p = (crate AH price + cheapest bundle) / favor`. Crates without a known favor or any priced bundle aren't rated. Each rated crate is compared with the cheapest one (`ratio = p / cheapest p`) and gets one of four tiers, with Best and Worst kept for the extremes:

| Tier | Ratio to the cheapest favor | Colour |
|---|---|---|
| **Best** | the cheapest crate, or within 10c per favor of it | purple |
| Great | up to 1.25x | blue |
| Good | up to 1.75x | yellow |
| Fair | up to 3x | orange |
| Poor | over 3x | red |
| **Worst** | the dearest crate, or within 10c per favor of it | deep crimson |

Tiers by ratio keep each one tight: one very expensive crate can't drag mid-priced crates up a tier. A crate with no AH price of its own is rated on its bundle alone (the tooltip says so). The `/crates` Rating column sorts by the ratio itself.

Hovering a crate also saves its real bundle amounts for the crate list. The beta guides don't always match the live game (Journeyman Textiles wants 20 Wool Cloth, not 40).

## Crate list: `/crates` (or `/crate`)

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
- **View: Market / My cost**. Market is the objective best at full AH prices. My cost counts crates you own as free and subtracts the materials you have.
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

The **Writs** button on `/crates`, `/crates writs`, or ctrl-click the minimap button: all 150 Craftsman's Writs (Alchemy, Blacksmithing, Engineering, Leatherworking, Tailoring), sorted by the cheapest reputation.

- **Writ cost**: the writ on the AH. **Buy item**: the required item on the AH. **Craft item**: its reagents, each at the vendor price (from Auctionator's vendor cache), the AH price, or crafted when that's cheaper. The cheaper of buy and craft is gold.
- **Total** = writ + the cheaper way to get the item. **Per rep** = total / the writ's reputation (75 Journeyman, 125 Expert, 200 Artisan).
- **Rating**: the crate tiers on cost per rep. A writ with no AH price is rated on the item alone and marked *.
- **Have**: W if you hold the writ, then how many of the item you have. **Today**: the writ's daily is done.
- Under the list, each Sealed envelope (a random writ of that rank): its price + the rank's average fill = the expected cost per rep.
- Filter by profession, rank, writs on the AH, writs you have, or hide those done today. Hover a row for the reagent breakdown and the recipient. Shift-click searches Auctionator (the item columns search the item, the rest the writ).
- Writ and Sealed writ tooltips in your bags show the same breakdown and rating.

## Settings

`/cratecost config`, right-click the minimap button, or Options > AddOns > CrateCost:

- bundle prices on crate tooltips, cheapest first, gold highlight, the Merchant's Favor line, the rating
- the writ rating on writ tooltips
- the minimap button (left-click: crate list, shift- or middle-click: merchant list, ctrl-click: writs, right-click: settings)

## Data

- Recipes, costs and reputation come from wow-professions.com's Merchant's Favor guide. Crafted item IDs and base stats come from CraftRoute's Forever recipe data (`tools/join.py` rebuilds Recipes.lua from both).
- Writs (writ and quest IDs, required item, skill, rank, reputation, recipient) come from wow.gg's Merchant's Favor guide. What each item is made from comes from endgametools.com's Forever profession pages (`tools/writs.py` rebuilds Writs.lua from both).
- Favor per crate comes from wow-professions.com's beta tables: raw goods 5/10/15, crafted goods (Fabrics, Ingots, Parts) 10/20/30 for Apprentice/Journeyman/Expert. Artisan is unknown so far.
- Crate item IDs are found by name at login. Material IDs and professions were checked against CraftRoute's Forever data.
