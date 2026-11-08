# Changelog

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
