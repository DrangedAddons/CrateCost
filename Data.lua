local _, ns = ...

-- Crate materials by tooltip name. IDs checked against CraftRoute's Forever item tables.
-- Quantities are not stored: they're read from the crate's own tooltip, because live
-- amounts differ from the beta guides (Journeyman Textiles wants 20 Wool Cloth, not 40).
ns.ItemIDs = {
  -- Apprentice
  ["Linen Cloth"] = 2589, ["Light Leather"] = 2318,
  ["Copper Ore"] = 2770, ["Tin Ore"] = 2771,
  ["Peacebloom"] = 2447, ["Silverleaf"] = 765, ["Earthroot"] = 2449, ["Mageroyal"] = 785,
  ["Briarthorn"] = 2450,
  ["Strange Dust"] = 10940, ["Greater Magic Essence"] = 10939,
  ["Small Glimmering Shard"] = 10978, ["Large Glimmering Shard"] = 11084,
  ["Cured Light Hide"] = 4231, ["Bolt of Linen Cloth"] = 2996,
  ["Copper Bar"] = 2840, ["Tin Bar"] = 3576, ["Bronze Bar"] = 2841,
  ["Handful of Copper Bolts"] = 4359, ["Copper Tube"] = 4361, ["Copper Modulator"] = 4363,
  -- Journeyman
  ["Wool Cloth"] = 2592, ["Silk Cloth"] = 4306, ["Medium Leather"] = 2319,
  ["Silver Ore"] = 2775, ["Iron Ore"] = 2772,
  ["Stranglekelp"] = 3820, ["Bruiseweed"] = 2453, ["Wild Steelbloom"] = 3355,
  ["Grave Moss"] = 3369, ["Kingsblood"] = 3356,
  ["Soul Dust"] = 11083, ["Greater Astral Essence"] = 11082,
  ["Small Glowing Shard"] = 11138, ["Large Glowing Shard"] = 11139,
  ["Bolt of Woolen Cloth"] = 2997, ["Bolt of Silk Cloth"] = 4305, ["Cured Medium Hide"] = 4233,
  ["Silver Bar"] = 2842, ["Iron Bar"] = 3575,
  ["Bronze Tube"] = 4371, ["Whirring Bronze Gizmo"] = 4375, ["Bronze Framework"] = 4382,
  ["Gold Power Core"] = 10558,
  -- Expert
  ["Mageweave Cloth"] = 4338, ["Heavy Leather"] = 4234,
  ["Gold Ore"] = 2776, ["Mithril Ore"] = 3858,
  ["Liferoot"] = 3357, ["Fadeleaf"] = 3818, ["Goldthorn"] = 3821, ["Khadgar's Whisker"] = 3358,
  ["Wintersbite"] = 3819, ["Firebloom"] = 4625, ["Purple Lotus"] = 8831, ["Arthas' Tears"] = 8836,
  ["Vision Dust"] = 11137, ["Greater Mystic Essence"] = 11135,
  ["Small Radiant Shard"] = 11177, ["Large Radiant Shard"] = 11178,
  ["Bolt of Mageweave"] = 4339, ["Cured Heavy Hide"] = 4236,
  ["Mithril Bar"] = 3860, ["Steel Bar"] = 3859, ["Gold Bar"] = 3577,
  ["Iron Strut"] = 4387, ["Mithril Tube"] = 10559, ["Unstable Trigger"] = 10560,
  ["Mithril Casing"] = 10561,
  -- Artisan
  ["Runecloth"] = 14047, ["Thick Leather"] = 4304, ["Rugged Leather"] = 8170,
  ["Truesilver Ore"] = 7911, ["Thorium Ore"] = 10620, ["Dark Iron Ore"] = 11370,
  ["Golden Sansam"] = 13464, ["Sungrass"] = 8838, ["Blindweed"] = 8839,
  ["Ghost Mushroom"] = 8845, ["Gromsblood"] = 8846,
  ["Dreamfoil"] = 13463, ["Mountain Silversage"] = 13465, ["Plaguebloom"] = 13466,
  ["Icecap"] = 13467,
  ["Dream Dust"] = 11176, ["Greater Nether Essence"] = 11175,
  ["Small Brilliant Shard"] = 14343, ["Large Brilliant Shard"] = 14344,
  ["Bolt of Runecloth"] = 14048, ["Cured Thick Hide"] = 8172,
  ["Dark Iron Bar"] = 11371, ["Truesilver Bar"] = 6037, ["Thorium Bar"] = 12359,
  ["Thorium Widget"] = 15994, ["Truesilver Transformer"] = 18631, ["Thorium Tube"] = 16000,
}

-- Merchant's Favor per crate, from the wow-professions.com / forevermastery beta tables.
-- It depends only on the crate (rank + kind), not the bundle you fill it with.
-- Raw goods pay 5/10/15, crafted goods (Fabrics, Ingots, Parts) 10/20/30.
-- Artisan isn't published yet: nil shows as "unknown".
ns.Favor = {
  raw     = { Apprentice = 5,  Journeyman = 10, Expert = 15 },
  crafted = { Apprentice = 10, Journeyman = 20, Expert = 30 },
}
ns.CraftedKinds = { Fabrics = true, Ingots = true, Parts = true }
-- Every crate and its bundles, from the wow-professions.com tables (beta amounts).
-- Hovering a real crate saves its live amounts in CrateCostDB.crates, which win over these.
ns.Crates = {
  { "Apprentice Textiles",     { { "Linen Cloth", 40 }, { "Light Leather", 20 } } },
  { "Apprentice Ore",          { { "Copper Ore", 20 }, { "Tin Ore", 20 } } },
  { "Apprentice Herbs",        { { "Peacebloom", 20 }, { "Silverleaf", 20 }, { "Earthroot", 10 },
                                 { "Mageroyal", 10 }, { "Briarthorn", 10 } } },
  { "Apprentice Curiosities",  { { "Strange Dust", 20 }, { "Greater Magic Essence", 4 },
                                 { "Small Glimmering Shard", 6 }, { "Large Glimmering Shard", 2 } } },
  { "Apprentice Fabrics",      { { "Cured Light Hide", 2 }, { "Bolt of Linen Cloth", 20 } } },
  { "Apprentice Ingots",       { { "Copper Bar", 20 }, { "Tin Bar", 20 }, { "Bronze Bar", 10 } } },
  { "Apprentice Parts",        { { "Handful of Copper Bolts", 16 }, { "Copper Tube", 16 },
                                 { "Copper Modulator", 4 } } },

  { "Journeyman Textiles",     { { "Wool Cloth", 40 }, { "Silk Cloth", 40 }, { "Medium Leather", 20 } } },
  { "Journeyman Ore",          { { "Silver Ore", 10 }, { "Iron Ore", 20 } } },
  { "Journeyman Herbs",        { { "Stranglekelp", 10 }, { "Bruiseweed", 10 }, { "Wild Steelbloom", 10 },
                                 { "Grave Moss", 10 }, { "Kingsblood", 10 } } },
  { "Journeyman Curiosities",  { { "Soul Dust", 20 }, { "Greater Astral Essence", 4 },
                                 { "Small Glowing Shard", 6 }, { "Large Glowing Shard", 2 } } },
  { "Journeyman Fabrics",      { { "Bolt of Woolen Cloth", 6 }, { "Bolt of Silk Cloth", 10 },
                                 { "Cured Medium Hide", 2 } } },
  { "Journeyman Ingots",       { { "Silver Bar", 10 }, { "Iron Bar", 20 } } },
  { "Journeyman Parts",        { { "Bronze Tube", 8 }, { "Whirring Bronze Gizmo", 7 },
                                 { "Bronze Framework", 4 }, { "Gold Power Core", 45 } } },

  { "Expert Textiles",         { { "Mageweave Cloth", 40 }, { "Heavy Leather", 20 } } },
  { "Expert Ore",              { { "Gold Ore", 10 }, { "Mithril Ore", 20 } } },
  { "Earthly Expert Herbs",    { { "Liferoot", 20 }, { "Fadeleaf", 10 }, { "Goldthorn", 10 },
                                 { "Khadgar's Whisker", 10 } } },
  { "Flowering Expert Herbs",  { { "Wintersbite", 10 }, { "Firebloom", 10 }, { "Purple Lotus", 20 },
                                 { "Arthas' Tears", 10 } } },
  { "Expert Curiosities",      { { "Vision Dust", 20 }, { "Greater Mystic Essence", 4 },
                                 { "Small Radiant Shard", 6 }, { "Large Radiant Shard", 2 } } },
  { "Expert Fabrics",          { { "Bolt of Mageweave", 8 }, { "Cured Heavy Hide", 2 } } },
  { "Expert Ingots",           { { "Mithril Bar", 20 }, { "Steel Bar", 15 }, { "Gold Bar", 10 } } },
  { "Expert Parts",            { { "Iron Strut", 8 }, { "Mithril Tube", 5 }, { "Unstable Trigger", 12 },
                                 { "Mithril Casing", 5 } } },

  { "Artisan Textiles",        { { "Runecloth", 40 }, { "Thick Leather", 20 }, { "Rugged Leather", 20 } } },
  { "Artisan Ore",             { { "Truesilver Ore", 10 }, { "Thorium Ore", 20 }, { "Dark Iron Ore", 20 } } },
  { "Earthly Artisan Herbs",   { { "Golden Sansam", 10 }, { "Sungrass", 20 }, { "Blindweed", 10 },
                                 { "Ghost Mushroom", 10 }, { "Gromsblood", 10 } } },
  { "Flowering Artisan Herbs", { { "Dreamfoil", 20 }, { "Mountain Silversage", 20 }, { "Plaguebloom", 20 },
                                 { "Icecap", 20 } } },
  { "Artisan Curiosities",     { { "Dream Dust", 20 }, { "Greater Nether Essence", 4 },
                                 { "Small Brilliant Shard", 6 }, { "Large Brilliant Shard", 2 } } },
  { "Artisan Fabrics",         { { "Bolt of Runecloth", 8 }, { "Cured Thick Hide", 2 } } },
  { "Artisan Ingots",          { { "Dark Iron Bar", 2 }, { "Truesilver Bar", 10 }, { "Thorium Bar", 20 } } },
  { "Artisan Parts",           { { "Thorium Widget", 5 }, { "Truesilver Transformer", 5 },
                                 { "Thorium Tube", 2 } } },
}

-- Where each material comes from, for the /crates profession filter. Crafted ones checked
-- against CraftRoute's Forever recipe files (Iron Strut is Engineering there).
ns.Professions = { "Cloth (drops)", "Skinning", "Leatherworking", "Tailoring", "Mining",
                   "Herbalism", "Enchanting", "Engineering" }
ns.MatProf = {}
local function Tag(prof, list) for _, m in ipairs(list) do ns.MatProf[m] = prof end end
Tag("Cloth (drops)", { "Linen Cloth", "Wool Cloth", "Silk Cloth", "Mageweave Cloth", "Runecloth" })
Tag("Skinning", { "Light Leather", "Medium Leather", "Heavy Leather", "Thick Leather", "Rugged Leather" })
Tag("Leatherworking", { "Cured Light Hide", "Cured Medium Hide", "Cured Heavy Hide", "Cured Thick Hide" })
Tag("Tailoring", { "Bolt of Linen Cloth", "Bolt of Woolen Cloth", "Bolt of Silk Cloth", "Bolt of Mageweave",
                   "Bolt of Runecloth" })
Tag("Mining", { "Copper Ore", "Tin Ore", "Silver Ore", "Iron Ore", "Gold Ore", "Mithril Ore", "Truesilver Ore",
                "Thorium Ore", "Dark Iron Ore", "Copper Bar", "Tin Bar", "Bronze Bar", "Silver Bar", "Iron Bar",
                "Gold Bar", "Mithril Bar", "Steel Bar", "Truesilver Bar", "Thorium Bar", "Dark Iron Bar" })
Tag("Herbalism", { "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp",
                   "Bruiseweed", "Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf",
                   "Goldthorn", "Khadgar's Whisker", "Wintersbite", "Firebloom", "Purple Lotus", "Arthas' Tears",
                   "Golden Sansam", "Sungrass", "Blindweed", "Ghost Mushroom", "Gromsblood", "Dreamfoil",
                   "Mountain Silversage", "Plaguebloom", "Icecap" })
Tag("Enchanting", { "Strange Dust", "Soul Dust", "Vision Dust", "Dream Dust", "Greater Magic Essence",
                    "Greater Astral Essence", "Greater Mystic Essence", "Greater Nether Essence",
                    "Small Glimmering Shard", "Large Glimmering Shard", "Small Glowing Shard", "Large Glowing Shard",
                    "Small Radiant Shard", "Large Radiant Shard", "Small Brilliant Shard", "Large Brilliant Shard" })
Tag("Engineering", { "Handful of Copper Bolts", "Copper Tube", "Copper Modulator", "Bronze Tube",
                     "Whirring Bronze Gizmo", "Bronze Framework", "Gold Power Core", "Iron Strut", "Mithril Tube",
                     "Unstable Trigger", "Mithril Casing", "Thorium Widget", "Truesilver Transformer", "Thorium Tube" })
