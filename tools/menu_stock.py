"""menu_stock.py : finds the stock packages Survival's main-menu pages are made from (run by tools/build_all.sh before
tools/build_survival.py; tools/re/MENU_PAGES.md). Writes build/menu/stock.json, which build_survival.py reads:
  class_tables  the game's table(s) of main-menu pages (row struct LiveMenuClassTable: MenuID -> widget class), the
                ones that list the free-mission difficulty page (CampaignFreeMissionDifficulty, the page Survival's
                SURVIVAL MODE row has always opened); the in-game one, DT_IngameMenuSettingData, is the STORE's
  page          the main-menu page itself: the widget blueprint, of those tables' pages, that imports the main menu's
                page settings DA_LiveMenuMainTopPageSettings (whose command table is DT_LiveMenuMainTopCommands, where
                SURVIVAL MODE sits); Survival's pages are copies of it
  page_class    its class (the soft reference's asset name, ..._C)
  settings      that settings asset's package
Everything is looked up by what it holds, not by a guessed path: build/scan/all_chunks.txt (tools/get_stock.sh's list
of the game's packages) gives the candidates, tools/get_stock.sh pulls them into build/stock. Nothing found: stock.json
says why, and the build makes no pages (the main menu keeps the flat rows; sv_menu.lua).
"""
import json, os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, 'scripts'))
from zenpkg import ZenPkg
import uprop, dtx

STOCK = os.path.join(ROOT, 'build', 'stock')
LIST = os.path.join(ROOT, 'build', 'scan', 'all_chunks.txt')
OUT = os.path.join(ROOT, 'build', 'menu', 'stock.json')
SETTINGS_NAME = 'DA_LiveMenuMainTopPageSettings'
DIFFICULTY_ID = 'CampaignFreeMissionDifficulty'


def game_packages():
    """Every package in the game's paks, as a path under Content ('Blueprints/UI/.../X.uasset')."""
    out = set()
    with open(LIST, encoding='utf-8', errors='replace') as f:
        for line in f:
            if 'ExportBundleData' not in line:
                continue
            for m in re.finditer(r'Live/Content/(\S+?\.(?:uasset|umap))', line):
                out.add(m.group(1))
    return sorted(out)


LISTED = {}                    # lower-case path -> the listing's own spelling (get_stock.sh greps it exactly)


def fetch(rels):
    """Pulls the packages not in build/stock yet (tools/get_stock.sh); returns the ones there now."""
    rels = [LISTED.get(r.lower(), r) for r in rels]
    want = [r for r in rels if not os.path.exists(os.path.join(STOCK, r))]
    for k in range(0, len(want), 40):
        subprocess.run(['sh', os.path.join(HERE, 'get_stock.sh')] + want[k:k + 40], check=False)
    return [r for r in rels if os.path.exists(os.path.join(STOCK, r))]


def rel_of(game_path):
    """'/Game/A/B' -> 'A/B.uasset'"""
    assert game_path.startswith('/Game/'), game_path
    return game_path[len('/Game/'):] + '.uasset'


def class_rows(rel):
    """A LiveMenuClassTable package's rows: [(MenuID, (widget package, class name))], or None if it isn't one."""
    try:
        z = ZenPkg(os.path.join(STOCK, rel))
        p = bytes(z.payloads[0])
        dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveMenuClassTable')
        if o != len(p):
            return None
    except Exception:
        return None
    rows = []
    for _, r in dt['rows']:
        f = dict((q[1], q[3]) for q in r[2])
        mid, ref = f.get('MenuID'), f.get('MenuWidgetReference')
        if mid and mid[0] == 'name' and ref and ref[0] == 'soft':
            rows.append((mid[1], (ref[1][1], ref[2][1])))
    return rows


def main():
    res = {'class_tables': [], 'page': None, 'page_class': None, 'settings': None, 'why': None}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    if not os.path.exists(LIST):
        res['why'] = 'no build/scan/all_chunks.txt (tools/get_stock.sh makes it)'
    else:
        pkgs = game_packages()
        LISTED.update((r.lower(), r) for r in pkgs)
        # the game's page tables: data tables under Datatables/UI/Menu (not the in-game ones) named for settings or classes
        cands = [r for r in pkgs if re.match(r'Datatables/', r, re.I) and not re.search(r'/IngameMenu/', r, re.I) and (
                 re.search(r'/DT_[^/]*Menu[^/]*(Setting|Class)[^/]*\.uasset$', r, re.I) or
                 (re.match(r'Datatables/UI/Menu/', r, re.I) and re.search(r'/DT_[^/]*(Setting|Class)[^/]*\.uasset$', r, re.I)))]
        tables = []
        for rel in fetch(cands):
            rows = class_rows(rel)
            if rows and any(mid == DIFFICULTY_ID for mid, _ in rows):
                tables.append((rel, rows))
        print(f'menu stock: {len(cands)} candidate page tables, {len(tables)} list {DIFFICULTY_ID}: '
              f'{[t[0] for t in tables]}')
        res['class_tables'] = ['/Game/' + rel[:-len('.uasset')] + '.' + rel.rsplit('/', 1)[1][:-len('.uasset')]
                               for rel, _ in tables]
        # the main-menu page: of those tables' pages (or, without a table, the widget blueprints named like a main
        # menu), the one that imports DA_LiveMenuMainTopPageSettings
        pages = {}
        for _, rows in tables:
            for mid, (pkg, cls) in rows:
                if pkg.startswith('/Game/'): pages[rel_of(pkg)] = (pkg, cls, mid)
        if not pages:
            for r in pkgs:
                if re.search(r'/WBP_[^/]*Main[^/]*\.uasset$', r) and not re.search(r'Ingame|/NUI/', r, re.I):
                    name = r.rsplit('/', 1)[1][:-len('.uasset')]
                    pages[r] = ('/Game/' + r[:-len('.uasset')], name + '_C', None)
        hits = []
        pages = {LISTED.get(r.lower(), r): v for r, v in pages.items()}
        for rel in fetch(sorted(pages)):
            try:
                z = ZenPkg(os.path.join(STOCK, rel))
            except Exception:
                continue
            da = [p for p in z.imp_pkgs if p.rsplit('/', 1)[-1] == SETTINGS_NAME]
            if da:
                hits.append((rel, da[0]))
        print(f'menu stock: {len(pages)} pages looked at; importing {SETTINGS_NAME}: {[h[0] for h in hits]}')
        if len(hits) > 1:                  # (a platform's variant too: the one its table calls the main menu's top)
            hits.sort(key=lambda h: (0 if re.search(r'Top', str(pages[h[0]][2]) + h[0]) else 1, h[0]))
            print(f'menu stock: taking {hits[0][0]}')
            hits = hits[:1]
        if len(hits) != 1:
            res['why'] = f'{len(hits)} pages import {SETTINGS_NAME} (one wanted): {[h[0] for h in hits]}'
        else:
            rel, da = hits[0]
            pkg, cls, mid = pages[rel]
            got = fetch([rel_of(da)])
            if not got:
                res['why'] = f'could not pull {da}'
            else:
                res.update(page=pkg, page_class=cls, settings=da, page_menu_id=mid)
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(res, f, indent=1)
    print('menu stock: ' + (f"main-menu page {res['page']} ({res['page_class']}), settings {res['settings']}"
                            if res['page'] else f"NOT found ({res['why']}): no pages this build") + f' -> {OUT}')


if __name__ == '__main__':
    main()
