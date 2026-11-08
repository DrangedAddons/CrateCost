# CrateCost

A WoW Forever addon for Waylaid Crates. It prices every way of filling a crate from your Auctionator data and shows the Merchant's Favor it pays.

Needs **Auctionator**. Prices are whatever Auctionator has (AuctionatorSync keeps them shared between friends).

## Crate tooltips

Hover a Waylaid Crate:

- each bundle gets its Auctionator price, with gold, silver and copper in their own columns
- the cheapest bundle is listed first and highlighted in gold
- a Merchant's Favor line shows what the crate pays (the same whichever bundle you use)

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

- Columns: recipe, profession, type, skill, required level, effect or slot, reputation, favor cost, learned. Click a header to sort.
- Search matches name, profession, type and the effect text (try "spirit" or "wrist").
- Filter by profession or "My professions", hide recipes you've learned, or show only what your current favor can buy (affordable costs are green).
- Hover a row for the game's recipe tooltip. Shift-click links it in chat.

## Settings

`/cratecost config`, right-click the minimap button, or Options > AddOns > CrateCost:

- bundle prices on crate tooltips, cheapest first, gold highlight, the Merchant's Favor line
- the minimap button (left-click: crate list, shift- or middle-click: merchant list, right-click: settings)

## Data

- Recipes, costs and reputation come from wow-professions.com's Merchant's Favor guide.

- Favor per crate comes from wow-professions.com's beta tables: raw goods 5/10/15, crafted goods (Fabrics, Ingots, Parts) 10/20/30 for Apprentice/Journeyman/Expert. Artisan is unknown so far.
- Crate item IDs are found by name at login. Material IDs and professions were checked against CraftRoute's Forever data.
