"""Build CrateCost's Writs.lua: every Craftsman's Writ from wow.gg's Merchant's Favor guide
(writ item, quest, required item, skill, rank, reputation, recipient), joined with
endgametools.com's Forever profession pages for what each required item is made from
(followed down through crafted reagents such as bolts and cured leather), plus the bundle
items of the crafted Waylaid Crates (Fabrics, Ingots, Parts) read from Data.lua next to the
output, so crate tooltips can price crafting a bundle too.
usage: writs.py <wow.gg merchants-favor page .html> <sources dir> <Writs.lua out>
Save the pages first:
  curl -sL -A "Mozilla/5.0" https://wow.gg/guides/merchants-favor -o wowgg.html
  for p in alchemy blacksmithing engineering leatherworking tailoring enchanting mining; do
    curl -sL -A "Mozilla/5.0" https://endgametools.com/en/wow-forever/professions/$p -o sources/endgametools_$p.html
  done"""
import re, sys, os, html, collections

page, srcdir, dest = sys.argv[1:4]
s = open(page, encoding='utf-8').read()


def text(x):
    return html.unescape(re.sub(r'<[^>]+>', '', x)).strip()


writs = []
for m in re.finditer(r'<table', s):
    tb = s[m.start():s.find('</table>', m.start())]
    if 'Writ and quest' not in tb:
        continue
    heads = re.findall(r'statPriority__title[^>]*>([^<]+)<', s[max(0, m.start() - 3000):m.start()])
    prof = text(heads[-1])
    for tr in re.findall(r'<tr class="GuideContent_contentTable__row[^"]*">(.*?)</tr>', tb, re.S):
        d = dict(re.findall(r'<td data-label="([^"]+)"[^>]*>(.*?)</td>', tr, re.S))
        w = d['Writ and quest']
        req = re.search(r'item=(\d+)".*?</a>\s*\D*?(\d+)', d['Required Items'], re.S)
        rec = text(d.get('Recipient', ''))
        # "Alyce · Arathi Highlands" -> "Alyce (Arathi Highlands)"
        rec = re.sub(r'\s*[·•—-]\s*', ' (', rec, count=1) + ')' if rec else ''
        writs.append(dict(
            prof=prof, writ=int(re.search(r'item=(\d+)', w).group(1)),
            quest=int(re.search(r'quest=(\d+)', w).group(1)),
            name=html.unescape(re.search(r'Writ: ([^<]+)</a>', w).group(1)).strip(),
            item=int(req.group(1)), qty=int(req.group(2)),
            skill=int(text(d['Crafting Skill']) or 0), rank=text(d['Writ Level']),
            rep=int(text(d['Reputation'])), recipient=rec))

# endgametools.com profession pages: item -> (makes, profession, reagents). The first recipe
# for an item wins (the pages list low skill first).
crafts = {}
for fn in sorted(os.listdir(srcdir)):
    m = re.match(r'endgametools_([a-z-]+)\.html$', fn)
    if not m:
        continue
    p = m.group(1).replace('-', ' ').title()
    page_s = open(os.path.join(srcdir, fn), encoding='utf-8').read()
    for li in re.finditer(r"<li id='r\d+' class='recipe'[^>]*>(.*?)</li>", page_s, re.S):
        body = li.group(1)
        t = re.search(r"<p class='recipe-title'><a href='/en/wow-forever/items/(\d+)'[^>]*>(.*?)</a>", body)
        if not t:
            continue
        item = int(t.group(1))
        mk = re.match(r'(\d+)\s*\S\s*', text(t.group(2)))   # "2 × Fire Oil"
        reagents = []
        for para in re.findall(r'<p>(.*?)</p>', body, re.S):
            if para.startswith('Reagents:'):
                for a2 in re.finditer(r"<a href='/en/wow-forever/items/(\d+)'[^>]*>(.*?)</a>", para):
                    n = re.match(r'(\d+)\s*\S', text(a2.group(2)))
                    reagents.append((int(a2.group(1)), int(n.group(1)) if n else 1))
        if reagents and item not in crafts:
            crafts[item] = (int(mk.group(1)) if mk else 1, p, reagents)

# endgametools has no smelting recipes, so the classic ones (ore -> bar) are added by hand for
# the Ingots crates. Mining; one ore per bar except Bronze (copper + tin bar -> 2), Steel (iron
# bar + coal) and Dark Iron (8 ore).
SMELT = {
    2840: [(2770, 1)], 3576: [(2771, 1)], 2842: [(2775, 1)], 3575: [(2772, 1)],
    3577: [(2776, 1)], 3860: [(3858, 1)], 6037: [(7911, 1)], 12359: [(10620, 1)],
    11371: [(11370, 8)], 3859: [(3575, 1), (3857, 1)],
}
for bar, rg in SMELT.items():
    crafts.setdefault(bar, (1, 'Mining', rg))
crafts.setdefault(2841, (2, 'Mining', [(2840, 1), (3576, 1)]))   # Bronze Bar

# the crafted crates' bundle items, by name from Data.lua (ns.Crates + ns.ItemIDs)
data = open(os.path.join(os.path.dirname(os.path.abspath(dest)), 'Data.lua'), encoding='utf-8').read()
ids = {n: int(i) for n, i in re.findall(r'\["([^"]+)"\]\s*=\s*(\d+)', data[:data.index('ns.Favor')])}
crate_items = []
for m in re.finditer(r'\{ "(\w+ (?:Fabrics|Ingots|Parts))",\s*\{(.*?)\} \},?\n', data, re.S):
    for name in re.findall(r'\{ "([^"]+)", \d+ \}', m.group(2)):
        if name in ids:
            crate_items.append(ids[name])
        else:
            print('crate item without an ID:', name)

need, seen = [w['item'] for w in writs] + crate_items, set()
while need:
    i = need.pop()
    if i in seen or i not in crafts:
        continue
    seen.add(i)
    need.extend(r for r, _ in crafts[i][2])

missing = [w['name'] for w in writs if w['item'] not in crafts]
crate_missing = [i for i in crate_items if i not in crafts]


def q(x):
    return '"' + x.replace('\\', '\\\\').replace('"', '\\"') + '"'


RANKS = {'Journeyman': 262888, 'Expert': 262889, 'Artisan': 262890}
with open(dest, 'w', encoding='utf-8', newline='\n') as f:
    f.write('''-- Craftsman's Writs, from wow.gg's Merchant's Favor guide joined with endgametools.com's
-- profession pages. Generated by tools/writs.py - do not edit by hand.
local _, ns = ...

-- Sealed envelopes (a random writ of that rank) and the reputation a writ of that rank gives.
ns.WritRanks = {
''')
    for r, rep in (('Journeyman', 75), ('Expert', 125), ('Artisan', 200)):
        f.write('  %s = { rep = %d, sealed = %d },\n' % (r, rep, RANKS[r]))
    f.write('''}

-- writ item, quest, name, profession, rank, skill, reputation, required item, count, recipient
ns.Writs = {
''')
    for w in writs:
        f.write('  {%d, %d, %s, %s, %s, %d, %d, %d, %d, %s},\n' % (
            w['writ'], w['quest'], q(w['name']), q(w['prof']), q(w['rank']), w['skill'], w['rep'],
            w['item'], w['qty'], q(w['recipient'])))
    f.write('''}

-- What the required items, the crafted crates' bundle items (and their crafted reagents) are
-- made from. Smelting is the classic recipes, added by hand (endgametools has none):
-- [item] = { makes, profession, {reagent, count}, ... }
ns.Crafts = {
''')
    for i in sorted(seen):
        mk, p, rg = crafts[i]
        f.write('  [%d] = { %d, %s, %s },\n' % (i, mk, q(p), ', '.join('{%d, %d}' % r for r in rg)))
    f.write('}\n')

print(len(writs), 'writs,', len(seen), 'crafts,', collections.Counter(w['prof'] for w in writs))
print('no recipe for:', missing)
print(len(crate_items), 'crate bundle items, no recipe for:', crate_missing)
