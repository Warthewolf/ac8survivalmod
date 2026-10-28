"""menu_pages_test.py : tools/menu_stock.py and tools/build_survival.py build_menu_pages on synthetic stock packages (no
game needed): a main-menu page table listing the free-mission difficulty page and the main-menu page, that page (a widget
blueprint importing DA_LiveMenuMainTopPageSettings), its settings (two tabs), DT_LiveMenuMainTopCommands with a Campaign
row and DT_IngameMenuSettingData, all made with tools/zenpkg.py in a temporary folder. Checks what the builder writes:
every page's command table (rows, StringArgs, MenuIDs, text keys), settings (title, every tab's command table), widget
blueprint (its settings import on Survival's copy, the right hash), the class rows and Scripts/sv_menu_stock.lua.
  python -X utf8 -I tools/checks/menu_pages_test.py
"""
import json, os, shutil, struct, sys, tempfile, types
HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS); sys.path.insert(0, os.path.join(TOOLS, 'scripts')); sys.path.insert(0, HERE)
from zenpkg import ZenPkg, NameBatch, name_hash, export_hash
import uprop, dtx
sys.modules.setdefault('ep_dump', types.ModuleType('ep_dump'))   # (build_survival imports it; scriptobjs.pkl is local)
import menu_stock
import build_survival as B

fails = 0


def check(ok, what):
    global fails
    print(('  ok   ' if ok else '  FAIL ') + what)
    if not ok: fails += 1


def make_pkg(path, export, names, payload_fn, imports=()):
    """A zen package: one export `export`, names (the package path and export first), imports [(package, object)];
    payload_fn(names) -> the export's bytes (names: the final name list, for uprop.W)."""
    names = [path, export] + [n for n in names if n not in (path, export)]
    hv = b'\0' * 8
    z = ZenPkg.__new__(ZenPkg)
    z.hasver, z.name_idx, z.name_num, z.flags, z.cooked_header_size = 0, 0, 0, 0, 0
    z.nb = NameBatch(names, [struct.pack('<Q', name_hash(n)) for n in names], hv)
    z.bulkmap, z.bundles, z.dep_hdr, z.dep_ent, z.ipn_tail, z.tail = b'', b'', b'', b'', b'', b''
    pk = [p for p, _ in imports]
    z.ipn = NameBatch(list(dict.fromkeys(pk)), [struct.pack('<Q', name_hash(n)) for n in dict.fromkeys(pk)], hv)
    z.imp_pkg_nums = [0] * len(z.ipn.names)
    z.imp_hashes = [export_hash(o) for _, o in imports]
    z.imports = [(2 << 62) | (z.ipn.names.index(p) << 32) | i for i, (p, _) in enumerate(imports)]
    e = bytearray(72)
    struct.pack_into('<II', e, 16, 1, 0)
    struct.pack_into('<Q', e, 56, export_hash(export))
    z.exports = [e]
    z.payloads = [bytearray(payload_fn(names))]
    return ZenPkg(data=z.write())


def soft(pkg, asset): return ('soft', ('name', pkg, 0), ('name', asset, 0), '')


def struct_of(sname, fields):
    sc = {n: k for k, (n, t) in uprop.U.schema(sname).items()}
    return ('struct', sname, sorted([(sc[n], n, False, v) for n, v in fields], key=lambda p: p[0]))


def dt_payload(rowstruct, rows):
    def f(names):
        dt = dict(pre=b'\0' * 4, top=('struct', 'DataTable', []), gf=0, rows=[((n, 0), struct_of(rowstruct, fl)) for n, fl in rows])
        return dtx.write(uprop.W(names), dt)
    return f


def names_of(rows):
    out = []
    for n, fl in rows:
        out.append(n)
        out += B.names_in([v for _, v in fl])
    return out


def save(stock, path, z):
    p = os.path.join(stock, path[len('/Game/'):] + '.uasset')
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'wb').write(z.write())


def main():
    tmp = tempfile.mkdtemp(prefix='sv_menu_pages_')
    try:
        stock, out, menu = (os.path.join(tmp, d) for d in ('stock', 'content', 'menu'))
        PAGE = '/Game/Blueprints/UI/Menu/Main/WBP_Menu_MainTop_000'
        OTHER = '/Game/Blueprints/UI/Menu/Campaign/WBP_Menu_FreeMissionDifficulty_000'
        DA = '/Game/Datatables/UI/Menu/MainMenu/Top/DA_LiveMenuMainTopPageSettings'
        CMDS = '/Game/Datatables/UI/Menu/MainMenu/Top/DT_LiveMenuMainTopCommands'
        CLASS = '/Game/Datatables/UI/Menu/MainMenu/DT_MainMenuSettingData'
        INGAME = B.MENU_TABLE
        rows = [('NewRow', [('MenuID', ('name', 'MainTop', 0)), ('MenuWidgetReference', soft(PAGE, 'WBP_Menu_MainTop_000_C'))]),
                ('NewRow_0', [('MenuID', ('name', 'CampaignFreeMissionDifficulty', 0)),
                              ('MenuWidgetReference', soft(OTHER, 'WBP_Menu_FreeMissionDifficulty_000_C'))])]
        save(stock, CLASS, make_pkg(CLASS, 'DT_MainMenuSettingData', names_of(rows), dt_payload('LiveMenuClassTable', rows)))
        ing = [('NewRow', [('MenuID', ('name', 'RetryMenu', 0)), ('MenuWidgetReference', soft('/Game/X/WBP_Retry', 'WBP_Retry_C'))])]
        save(stock, INGAME, make_pkg(INGAME, 'DT_IngameMenuSettingData', names_of(ing), dt_payload('LiveMenuClassTable', ing)))
        camp = [('Campaign', [('CommandID', ('name', 'Main_Top_Campaign', 0)), ('TitleTextID', ('str', 'MainTop_Campaign')),
                              ('HelpTextID', ('str', 'MainTop_Campaign_Help')), ('MenuID', ('str', 'CampaignTop')),
                              ('StringArgs', ('str', ''))]),
                ('QuitGame', [('CommandID', ('name', 'Main_Top_Quit', 0)), ('TitleTextID', ('str', 'MainTop_Quit'))])]
        save(stock, CMDS, make_pkg(CMDS, 'DT_LiveMenuMainTopCommands', names_of(camp), dt_payload('LiveMenuCommandsDataTable', camp)))
        tab = lambda t: struct_of('LiveMenuTabSettings', [('TabTitleTextID', ('str', t)), ('CommandSettings', soft(CMDS, 'DT_LiveMenuMainTopCommands')),
                                                         ('DefaultHelpTextID', ('str', 'MainTop_Help'))])
        da_props = struct_of('LiveMenuPageSettingsData', [('TitleTextID', ('str', 'MainTop_Title')), ('TabSettings', ('arr', [tab('A'), tab('B')]))])
        save(stock, DA, make_pkg(DA, 'DA_LiveMenuMainTopPageSettings', [CMDS, 'DT_LiveMenuMainTopCommands'],
                                 lambda names: b'\0\0\0\0' + uprop.write_struct(uprop.W(names), da_props)))
        save(stock, PAGE, make_pkg(PAGE, 'WBP_Menu_MainTop_000', ['WBP_Menu_MainTop_000_C'], lambda n: b'\0' * 16,
                                   imports=[(DA, 'DA_LiveMenuMainTopPageSettings'), ('/Game/X/WBP_Common', 'WBP_Common')]))
        save(stock, OTHER, make_pkg(OTHER, 'WBP_Menu_FreeMissionDifficulty_000', [], lambda n: b'\0' * 16,
                                    imports=[('/Game/X/DA_Other', 'DA_Other')]))
        os.makedirs(os.path.join(tmp, 'scan'))
        lst = os.path.join(tmp, 'scan', 'all_chunks.txt')
        with open(lst, 'w') as f:
            for i, p in enumerate((CLASS, INGAME, CMDS, DA, PAGE, OTHER)):
                f.write(f'{i} {i:016x} ExportBundleData 123 ../../../Live/Content/{p[len("/Game/"):]}.uasset\n')
        # discovery
        menu_stock.STOCK, menu_stock.LIST, menu_stock.OUT = stock, lst, os.path.join(menu, 'stock.json')
        menu_stock.main()
        st = json.load(open(os.path.join(menu, 'stock.json')))
        check(st['page'] == PAGE and st['page_class'] == 'WBP_Menu_MainTop_000_C' and st['settings'] == DA,
              f"menu_stock: the main-menu page, its class and settings found ({st.get('page')}, {st.get('why')})")
        check(st['class_tables'] == [CLASS + '.DT_MainMenuSettingData'], f"menu_stock: the page table, not the in-game one ({st['class_tables']})")
        # the build
        B.STOCK, B.OUT = stock, out
        B.MENU_STOCK, B.MENU_STOCK_LUA = os.path.join(menu, 'stock.json'), os.path.join(menu, 'sv_menu_stock.lua')
        B.build_menu_pages()
        cls = 'WBP_Menu_MainTop_000_C'
        for name, prows in B.MENU_PAGES:
            p = lambda path: os.path.join(out, path[len('/Game/'):] + '.uasset')
            z = ZenPkg(p(B.DATA + f'DT_SV_Pg{name}Commands'))
            dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveMenuCommandsDataTable')
            got = [(n, dict((q[1], q[3]) for q in r[2])) for (n, _), r in dt['rows']]
            want = [(f'SV{name}{row}', args, menu_id) for row, args, menu_id in prows]
            ok = [n for n, _ in got] == [w[0] for w in want] and all(
                f['StringArgs'] == ('str', w[1]) and f['MenuID'] == ('str', B.page_menu_id(w[2])) and f['TitleTextID'] == ('str', f'SV_Pg_{name}_{w[0][2 + len(name):]}')
                and f['HelpTextID'] == ('str', f'SV_Pg_{name}_{w[0][2 + len(name):]}_Help') for (_, f), w in zip(got, want))
            check(ok, f'{name}: {len(got)} command rows, their StringArgs, MenuIDs and text keys')
            z = ZenPkg(p(B.UI + f'DA_SV_Pg{name}Settings'))
            v, _ = B.props_of(z, 0, 'LiveMenuPageSettingsData')
            tabs = uprop.get(v, 'TabSettings')[3][1]
            tbl = B.DATA + f'DT_SV_Pg{name}Commands'
            check(uprop.get(v, 'TitleTextID')[3] == ('str', f'SV_Pg_{name}_Title') and len(tabs) == 2 and all(
                uprop.get(t, 'CommandSettings')[3] == soft(tbl, tbl.rsplit('/', 1)[1]) for t in tabs),
                f'{name}: its settings: title, both tabs on its own command table')
            z = ZenPkg(p(B.UI + f'WBP_SV_Pg{name}'))
            da = B.UI + f'DA_SV_Pg{name}Settings'
            k = z.imp_pkgs.index(da) if da in z.imp_pkgs else -1
            hs = [x & 0xffffffff for x in z.imports if x >> 62 == 2 and (x >> 32) & 0x3fffffff == k]
            check(k >= 0 and DA not in z.imp_pkgs and len(hs) == 1 and z.imp_hashes[hs[0]] == export_hash(da.rsplit('/', 1)[1])
                  and B.UI + f'WBP_SV_Pg{name}' in z.names and PAGE not in z.names, f'{name}: its page, the settings import on its own')
        z = ZenPkg(os.path.join(out, (B.DATA + 'DT_SV_MainMenuClassRows')[len('/Game/'):] + '.uasset'))
        dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveMenuClassTable')
        got = {dict((q[1], q[3]) for q in r[2])['MenuID'][1]: dict((q[1], q[3]) for q in r[2])['MenuWidgetReference'] for _, r in dt['rows']}
        check(sorted(got) == sorted(f'SV_Pg{n}' for n, _ in B.MENU_PAGES) and all(
            got[f'SV_Pg{n}'] == soft(B.UI + f'WBP_SV_Pg{n}', cls) for n, _ in B.MENU_PAGES), 'the class rows: every page, its widget class')
        check([n for (n, _), _ in dt['rows']] == [f'SVPg{n}' for n, _ in B.MENU_PAGES], 'the class rows are named as sv_menu.lua looks them up')
        lua = open(os.path.join(menu, 'sv_menu_stock.lua')).read()
        check(f'page_class = "{cls}"' in lua and CLASS + '.DT_MainMenuSettingData' in lua, 'Scripts/sv_menu_stock.lua names the class and the table')
        try:
            from lupa import lua54
            t = lua54.LuaRuntime().execute(lua)
            check(t['page_class'] == cls and t['class_tables'][1] == CLASS + '.DT_MainMenuSettingData', 'sv_menu_stock.lua runs (Lua 5.4)')
        except ImportError:
            print('  (no lupa: sv_menu_stock.lua not run)')
        # no page found: no pages, none left from before
        json.dump({'page': None, 'why': 'test'}, open(os.path.join(menu, 'stock.json'), 'w'))
        B.build_menu_pages()
        left = [f for d, _, fs in os.walk(out) for f in fs if 'SV_Pg' in f or 'MainMenuClassRows' in f]
        check(not left and not os.path.exists(os.path.join(menu, 'sv_menu_stock.lua')), f'no page found: the earlier pages removed ({left})')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('menu pages: all passed' if fails == 0 else f'menu pages: {fails} FAILED')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
