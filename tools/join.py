"""Join the scraped Merchant's Favor recipes with CraftRoute's Forever recipe data
(item ID, category, stats) and write CrateCost's Recipes.lua.
usage: join.py <out.txt> <CraftRoute Data dir> <Recipes.lua out>"""
import re, sys, os, collections

out_txt, crdir, dest = sys.argv[1:4]

# CraftRoute: spell -> {item, cat, stats, q}
cr = {}
for fn in os.listdir(crdir):
    if not fn.endswith('Recipes.lua'):
        continue
    for line in open(os.path.join(crdir, fn), encoding='utf-8'):
        m = re.match(r'\s*\[(\d+)\] = \{ name = "((?:[^"\\]|\\.)*)"(.*)\},?\s*$', line)
        if not m:
            continue
        body = m.group(3)
        d = {'name': m.group(2)}
        for k in ('item', 'q'):
            mm = re.search(r'\b%s = (\d+)' % k, body)
            if mm: d[k] = int(mm.group(1))
        for k in ('cat', 'stats'):
            mm = re.search(r'\b%s = "((?:[^"\\]|\\.)*)"' % k, body)
            if mm: d[k] = mm.group(1)
        cr[int(m.group(1))] = d

lines = open(out_txt, encoding='utf-8').read().splitlines()
plan = ([('Alchemy', 'Potion'), ('Alchemy', 'Elixir')] + [('Blacksmithing', 'Armor')] * 5 +
        [('Cooking', 'Smoothie')] + [('Enchanting', 'Enchant')] * 3 +
        [('Enchanting', 'Relic'), ('Enchanting', 'Caster gear')] +
        [('Engineering', 'Explosive')] * 2 + [('Engineering', 'Gear'), ('Engineering', 'Gadget'),
        ('Engineering', 'Part')] + [('Leatherworking', 'Armor')] * 6 +
        [('Leatherworking', 'Armor kit')] + [('Tailoring', 'Armor')] * 6 + [('Tailoring', 'Bag')])

ARMOR = ('Cloth', 'Leather', 'Mail', 'Plate')
SLOT_FROM_CAT = {
    'Belts': 'Waist', 'Waist': 'Waist', 'Gloves': 'Hands', 'Hands': 'Hands', 'Boots': 'Feet',
    'Feet': 'Feet', 'Helms': 'Head', 'Head': 'Head', 'Chests': 'Chest', 'Chest': 'Chest',
    'Legs': 'Legs', 'Leggings': 'Legs', 'Shoulders': 'Shoulder', 'Shoulder': 'Shoulder',
    'Bracers': 'Wrist', 'Wrist': 'Wrist',
}
ENCH_SLOT = {'Necklace': 'Neck', 'Weapon': 'Weapon', '2H Weapon': 'Two-hand weapon',
             'Chest': 'Chest', 'Bracer': 'Wrist', 'Cloak': 'Back', 'Gloves': 'Hands',
             'Off-Hand': 'Off-hand'}

def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def clean_stats(s):
    # CraftRoute appends tools after " · Needs ..." - drop them
    parts = [p.strip() for p in s.split('·')]
    keep = []
    for p in parts:
        if p.startswith('Needs ') or p.startswith('Requires '):
            break  # the rest are tools
        if p:
            keep.append(p)
    parts = keep
    return ' · '.join(parts)

rows, t, hdr, missing = [], -1, None, []
cats = collections.Counter()
i = lines.index('## Recipes by Profession') + 1
for l in lines[i:]:
    if l.startswith('##'):
        break
    c = [x.strip() for x in l.split(' | ')]
    if 'Recipe' in c:
        hdr, t = c, t + 1
        continue
    prof, typ = plan[t]
    d = dict(zip(hdr, c))
    m = re.match(r'(.*?) \{(\d+)\}$', d['Recipe'])
    name, spell = m.group(1), int(m.group(2))
    info = cr.get(spell, {})
    if not info:
        missing.append(name)
    cat = info.get('cat', '')
    cats[cat] += 1
    effect = d.get('Effect', '')
    slot = d.get('Slot', '')
    if typ == 'Enchant':
        mm = re.match(r'Enchant (.+?) - ', name)
        slot = ENCH_SLOT.get(mm.group(1), mm.group(1)) if mm else ''
    if typ == 'Armor':
        # armor type from the slot text ("Waist, Mail") or CraftRoute's category ("Mail Belts")
        kind = next((a for a in ARMOR if a in slot or cat.startswith(a)), None)
        if kind:
            typ = kind
        elif prof == 'Tailoring':
            typ = 'Cloth'
        elif re.search(r'Weapon|Polearm|Mace|Staff|Sword|Axe|Dagger', slot):
            typ = 'Weapon'
        slot = slot.split(',')[0].strip()
    elif ',' in slot:
        s, kind = [x.strip() for x in slot.split(',', 1)]
        slot, typ = s, kind if kind in ARMOR else typ
    stats = clean_stats(info.get('stats', ''))
    if typ == 'Bag':
        slot = 'Bag'
    if not effect:
        effect = stats
    elif stats and stats not in effect:
        effect = effect  # page effect text is the one players read; stats feed the filter
    rep = {'': 0, 'Friendly': 1, 'Honored': 2}[d.get('Reputation', '')]
    req = d.get('Req. / Level', '') or '0'
    rows.append('  {%s, "%s", "%s", %s, %s, %d, %s, %s, %s, %d, %d},' % (
        q(name), prof, typ, d['Prof. / Skill'], d['Cost'], rep, req, q(effect), q(slot), spell,
        info.get('item', 0)))

assert t == len(plan) - 1

others = [('Reins of the Pack Kodo', 6000, 4, 60, 'Mount', 'Needs Journeyman Riding', 262766),
          ('Packmule Treat', 1500, 3, 0, 'Pet', '', 284664),
          ('Advertising License Application', 1200, 2, 0, 'Title', '', 270887),
          ('Durotar Supply and Logistics Tabard', 200, 4, 0, 'Tabard', 'Horde', 262764),
          ('Azeroth Commerce Authority Tabard', 200, 4, 0, 'Tabard', 'Alliance', 262765)]
for p, iid in [('Alchemy', 271621), ('Blacksmithing', 271622), ('Enchanting', 271624),
               ('Engineering', 271625), ('Leatherworking', 271626), ('Tailoring', 271627)]:
    others.append((p + ' Certification', 1000, 0, 0, 'Title', 'Needs 300 ' + p, iid))

with open(dest, 'w', encoding='utf-8', newline='\r\n') as f:
    f.write('''-- Merchant's Favor recipes (vendors at the Durotar Supply / Azeroth Commerce camps), from
-- wow-professions.com/forever/merchants-favor-durotar-supply-azeroth-commerce, joined with
-- CraftRoute's Forever recipe data for the crafted item and its stats (tools/join.py).
-- Fields: name, profession, type, skill, favor cost, reputation (0 none, 1 Friendly,
-- 2 Honored, 3 Revered, 4 Exalted), required level, effect (the guide's text, or the crafted
-- item's base stats from CraftRoute), slot, spell ID, crafted item ID (0 = none / unknown).

local ADDON, ns = ...

ns.Recipes = {
''')
    f.write('\n'.join(rows) + '\n}\n\n')
    f.write('''-- Other Merchant's Favor rewards: name, cost, reputation, level, type, note, item ID.
ns.FavorItems = {
''')
    for n, c, r, lv, kind, note, iid in others:
        f.write('  {%s, %d, %d, %d, "%s", %s, %d},\n' % (q(n), c, r, lv, kind, q(note), iid))
    f.write('}\n')

print(len(rows), 'recipes;', len(missing), 'not in CraftRoute:', missing)
print(cats.most_common(60))
