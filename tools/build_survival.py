"""build_survival.py : generate Survival Mode's zen packages into mod/Content (run by tools/build_all.sh).

Every package is a stock game file with Survival's changes (Survival Mode uses nothing from another mod):
  - PL_SurvivalMode            <- PL_Mission022 (Map17 / Comona sublevels), Mission 4's sky (LIT_NEW)
  - MC_SurvivalMode            <- MC_Mission022
  - WD_SurvivalMode_global     <- WD_Mission022_global: no unit spawns at start but the airfield's targets, pool and bomber
                                  flights sized and given Survival's behaviour rows, the shuttle and the airport's AA guns /
                                  SAM sites in units of their own (split_units), Survival's NPC table
  - WD_SurvivalMode_phase01/02 <- WD_Mission022_phase01/02 (one player start each)
  - EP_SurvivalMode_global     <- EP_Mission022_global with only Survival's records (tools/survival_events.py)
  - EP_SurvivalMode_phase01/02 <- the phase EPs with every record removed
  - EF_SurvivalMode_global     <- EF_Mission022_global holding Survival's int flags (survival_events.INT_FLAGS)
  - DT_SV_MissionRows / DT_SV_MenuRows / DT_SV_ShopRows / DT_SV_NpcRows <- one-table copies of stock rows, added to the
                                  game's tables at run time by Scripts/main.lua; DT_SV_NpcMission <- DT_NPC_Mission022
  - Survival's main-menu pages (MENU_PAGES): WBP_SV_Pg* <- the game's main-menu page (tools/menu_stock.py finds it),
                                  DA_SV_Pg*Settings <- its DA_LiveMenuMainTopPageSettings, DT_SV_Pg*Commands <- rows of
                                  DT_LiveMenuMainTopCommands, DT_SV_MainMenuClassRows <- DT_IngameMenuSettingData's rows
  - /Game/LuaSource/SurvivalMode/AI/*  <- Survival's behaviour scripts (Scripts/ai)
Stock packages are pulled with tools/get_stock.sh into build/stock first.

The parts (2026-11-07: no source file over 2,000 lines, tools/checks/size_check.py). This file keeps the folders and
package helpers, the shop rows, the menu pages, the NPC rows (DT_SV_NpcRows), the NPC mission table and the behaviour
scripts (the Lua tests read their text here), the build's read-back checks, its main, and every function that reads
STOCK, OUT, ROOT, MENU_STOCK, MENU_STOCK_LUA or AI_SRC itself (tools/checks/menu_pages_test.py sets them on this module
to build into a folder of its own). The rest is in three parts, imported at the end of this file with
`from <part> import *`, so build_survival.<name> reaches every name of every part:
  - build_survival_rows.py: the radio table (DT_SV_Radio), the mission / menu rows' edits, the model rows, build_rows
  - build_survival_units.py: the level, its MC and phase world data; the world data's unit and path helpers; the units
    of the STORE's allies, the Ladons, the heavies' paths, VALKA, the Alicorn and the amphibious assault
  - build_survival_world.py: the units of the Spaceport Assault, the STORE's CIWS, the airfield's split, GONE FISHIN',
    THE FESTIVAL, THE ESCORT and THE DECOY; the global world data, its flag asset and the event packages
Each part begins with `from build_survival import *`, so it sees every name this file defines and every name of the
parts imported before it, as when this was one file. Run as a script this module is __main__: it registers itself as
build_survival first, so its parts get it and not a second copy. Import build_survival, never a part on its own.
"""
import copy, json, math, os, re, sys, struct, zlib
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, 'scripts'))
from zenpkg import ZenPkg, export_hash
import uprop, eprec
sys.path.insert(0, os.path.join(HERE, "checks"))
import survival_events, ep_dump
# (run as a script this module is __main__: its parts import it as build_survival, so it is that module too)
sys.modules.setdefault('build_survival', sys.modules[__name__])

STOCK = os.path.join(ROOT, 'build', 'stock')
OUT = os.path.join(ROOT, 'mod', 'Content')

MOD = '/Game/Mods/SurvivalMode'
PL = MOD + '/Maps/PL_SurvivalMode'
MI = MOD + '/Mission/'
M22 = '/Game/Maps/Ingame/Mission022/'

# Player start: 6 km out on the approach to Comona Airport's runway, 1500 m up, flying at the airport.
# Runway centre and heading from Mission 22's VolumeBox_LandingArea0: (1609574, -435747, 0), yaw -23.
RUNWAY = (1609574.0, -435747.0); RUNWAY_YAW = -23.0
START_BACK_CM, START_ALT_CM = 600000.0, 150000.0
_yaw = math.radians(RUNWAY_YAW)
START = (RUNWAY[0] - START_BACK_CM * math.cos(_yaw), RUNWAY[1] - START_BACK_CM * math.sin(_yaw), START_ALT_CM)
START_ROT = (0.0, RUNWAY_YAW, 0.0)   # pitch, yaw, roll

# Mission 4's sky: its lighting sublevel (sky light, sun, height fog, post process and the LiveCloudlyActor cloud
# layer) plus the world-settings values PL_Mission004 uses with it. Mission 4 leaves CloudDensityScale at its default
# and sets CloudDensityScaleBySound. (Until 2026-10-22: Mission 16's Map14 sky, clock 08:00, CloudDensityScale 0.9.)
LIT_OLD = '/Game/Maps/MapCommon/Map17/Mission022/Mission022_Common_Lit_Cloudly01'
LIT_NEW = '/Game/Maps/MapCommon/Map05/Mission004/Mission004_Common_Lit_Cloudly01'
CLOCK = (10, 10)
CLOUD_DENSITY_BY_SOUND = struct.unpack('<f', b'\x8b\x6c\xa7\x3f')[0]   # PL_Mission004's value, bit for bit (1.308)
MISSION_TIME_LIMIT = 3600.0   # seconds; Mission 22 uses 900


def stock(path):
    p = os.path.join(STOCK, path[len('/Game/'):])
    for ext in ('.umap', '.uasset'):
        if os.path.exists(p + ext): return p + ext
    raise SystemExit(f'missing stock package {path}; run tools/get_stock.sh first')


def save(z, path, ext='.uasset'):
    p = os.path.join(OUT, path[len('/Game/'):]) + ext
    os.makedirs(os.path.dirname(p), exist_ok=True)
    data = z.write(); open(p, 'wb').write(data)
    ZenPkg(data=data)   # must parse back
    print(f'{path}  {len(data)} bytes')


def rename_package(z, old_path, new_path):
    """Package path + its top-level object (export 'name' == short name) + that export's public hash."""
    old_short, new_short = old_path.rsplit('/', 1)[1], new_path.rsplit('/', 1)[1]
    i = z.export_index(old_short)
    z.rename(old_path, new_path); z.rename(old_short, new_short)
    z.set_export_public_hash(i, new_short)


def retarget_import(z, old_pkg, new_pkg):
    """Point an imported package (and its top-level object's hash) at our renamed copy."""
    old_short, new_short = old_pkg.rsplit('/', 1)[1], new_pkg.rsplit('/', 1)[1]
    hs = z.imported_hash_index(old_pkg)
    assert len(hs) == 1, (old_pkg, hs)
    assert z.imp_hashes[hs[0]] == export_hash(old_short), old_pkg
    z.imp_hashes[hs[0]] = export_hash(new_short)
    z.set_imported_package(old_pkg, new_pkg)


def package_hash(path):
    return zlib.crc32(path.lower().encode()) & 0xffffffff


# ---------------------------------------------------------------- props helpers
def props_of(z, i, sname):
    """Export payload = 4-byte prefix (zero so far) + unversioned properties + rest. Returns (props, rest)."""
    p = bytes(z.payloads[i])
    assert p[:4] == b'\0\0\0\0', p[:4]
    v, o = uprop.read_struct(uprop.Ctx(p, z.names), 4, sname)
    assert write_props(z, v) == p[:o], f'{sname}: properties do not round-trip'
    return v, p[o:]


def write_props(z, v):
    """Prefix + properties (pair with the rest returned by props_of)."""
    return b'\0\0\0\0' + uprop.write_struct(uprop.W(z.names), v)


def set_prop(props, idx, name, value):
    """props: list of (idx, name, zero, value) sorted by idx; replace or insert."""
    props[:] = [p for p in props if p[0] != idx] + [(idx, name, False, value)]
    props.sort(key=lambda p: p[0])


def drop_prop(props, idx):
    props[:] = [p for p in props if p[0] != idx]


# ---------------------------------------------------------------- menu + mission rows
# Survival's rows live in tables of its own. The Lua runtime copies them into the game's DT_LiveMissionTable and
# DT_LiveMenuMainTopCommands at run time (AddRow), so no stock or other-mod table is overridden.
DATA = MOD + '/Data/'
MISSION_ID = 9101          # must match SURVIVAL_MISSION_ID in runtime/survival_rt.c
LEVEL_ID = 70              # ELiveLevelID Test02: no stock row uses it
MENU_ARGS = 'SurvivalMode' # must match SURVIVAL_ARGS in runtime/survival_rt.c
COOP_HOST_ARGS = 'SurvivalHost'   # must match SURVIVAL_HOST_ARGS in runtime/survival_rt.c (SURVIVAL CO-OP: HOST)
COOP_JOIN_ARGS = 'SurvivalJoin'   # must match SURVIVAL_JOIN_ARGS (SURVIVAL CO-OP: JOIN)
MENU_PAGES_ARGS = 'SurvivalMenu'  # must match SURVIVAL_MENU_ARGS (SURVIVAL MODE that opens Survival's pages)
import dtx


def build_rows_table(stock_path, new_path, row_struct, src_row, new_row, edit, more=()):
    """Copy a stock DataTable package, keep one row (renamed new_row) and let edit() change its properties; `more` =
    (row name, edit) pairs: further copies of the same stock row, each edited by its own function."""
    import copy
    z = ZenPkg(stock(stock_path))
    rename_package(z, stock_path, new_path)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, row_struct)
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    out = []
    for name, ed in [(new_row, edit)] + list(more):
        row = copy.deepcopy(rows[(src_row, 0)])
        ed(row[2])
        for n in names_in(row) + [name]:
            z.nb.add(n)
        out.append(((name, 0), row))
    dt['rows'] = out
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, row_struct)
    assert chk['rows'] == dt['rows']
    save(z, new_path)


# The airfield shop (Milestone 4): rows for the landing menu (the in-game hangar's command list, after its Yes / No).
# Scripts/main.lua adds them to the game's table at run time while Survival's level is loaded and removes them after;
# their texts (SV_Shop_*) are set by Lua through the native text hook (SV_SetText), and picking one is caught by the
# native landing-menu hook (StringArgs SV_Buy_<item>), so the stock page never sees them.
SHOP_TABLE_STOCK = '/Game/Datatables/UI/Menu/IngameMenu/IngameHangar/DT_LiveMenuIngameHangarCommands'
SHOP_TABLE = DATA + 'DT_SV_ShopRows'
SHOP_ITEMS = ['Missiles', 'Special', 'Flares', 'Airfield']          # Scripts/main.lua CFG.shop.items, same names
# The STORE (user, 2026-10-23: "a special tab in there for the store items"; tools/re/AIRFIELD_SHOP_UI.md): the landing
# menu's page list is the in-game menu table, and a landing row whose StringArgs is a number opens that menu. Survival
# adds pages of its own (DT_SV_MenuClassRows -> DT_IngameMenuSettingData at the main menu: indexes 20, 21, 22),
# copies of the landing page (WBP_SV_Store*, with their own settings asset and command table), and one landing row,
# STORE ("20"). Lua checks the game's menu list for them; without them it falls back to the 4 SHOP_ITEMS rows.
# A page lists 6 rows at most, so the pages link in a ring, each with TAKE OFF (user, 2026-10-23: "add a Docks Page
# too"). The economy review (2026-10-25) added UPGRADES and TACTICAL and moved the allies onto the DOCKS page (shown as
# ALLIES): SUPPLIES (20) > UPGRADES (23) > TACTICAL (24) > AIRFIELD (21) > ALLIES (22) > SUPPLIES. 0.72.1's CIWS (user,
# 2026-10-29) left the AIRFIELD page a row short, so the AA gun, SAM site and CIWS rows have a DEFENCES page (25) of
# their own: AIRFIELD (21) > DEFENCES (25) > ALLIES (22), AIRFIELD's own ALLIES > kept. 0.72.2 put co-op's REVIVE
# (Scripts/sv_down.lua; user, 2026-10-29: "someone could land at the airfield and buy you back") in the AIRFIELD page's
# sixth row. The menu-class rows go into the game's table in this list's order, so the menu ids 20-25 follow it: keep it
# in Scripts/sv_flights.lua SHOP.menuRows' order.
STORE_PAGES = [  # (menu id, page, title key, rows: item name or (row name, title key, StringArgs))
    ('SV_Store', 'Store', 'SV_Store_Title',
     ['Rearm', 'Missiles', 'Special', 'Flares', ('SVStoreToUpgrades', 'SV_Store_ToUpgrades', '23'), 'takeoff']),
    ('SV_StoreAirfield', 'StoreAirfield', 'SV_Store_TitleAirfield',
     ['RepairAircraft', 'RepairAirfield', 'Revive', ('SVStoreToDefences', 'SV_Store_ToDefences', '25'),
      ('SVStoreToDocks', 'SV_Store_ToDocks', '22'), 'takeoff']),
    ('SV_StoreDocks', 'StoreDocks', 'SV_Store_TitleDocks',
     ['Wingmen', 'Moonchild', 'ShipAegis', 'Orders', ('SVStoreToSupplies', 'SV_Store_ToSupplies', '20'), 'takeoff']),
    ('SV_StoreUpgrades', 'StoreUpgrades', 'SV_Store_TitleUpgrades',
     ['UpAirframe', 'UpBays', 'UpGun', 'UpFlares', ('SVStoreToTactical', 'SV_Store_ToTactical', '24'), 'takeoff']),
    ('SV_StoreTactical', 'StoreTactical', 'SV_Store_TitleTactical',
     ['Airstrike', 'Ecm', 'Decoy', 'Insurance', ('SVStoreToAirfield', 'SV_Store_ToAirfield', '21'), 'takeoff']),
    ('SV_StoreDefences', 'StoreDefences', 'SV_Store_TitleDefences',
     ['AAGun', 'SAM', 'Ciws', 'VoidWatcher', ('SVStoreToDocks', 'SV_Store_ToDocks', '22'), 'takeoff']),
]
STORE_MENU_FIRST = 20       # the first page's menu id (the game's table has 20 rows): Scripts/sv_flights.lua SHOP.menuRows
# the landing page's rows, one per page they open (it lists 4 of Survival's beside its 2 stock rows): Scripts/sv_flights.lua
# SHOP.store, texts SV_Shop_Store* (sv_shop.lua shopTexts)
STORE_ROWS = [('SVShopStore', 'SV_Shop_Store', '20'), ('SVShopStoreUp', 'SV_Shop_StoreUp', '23'),
              ('SVShopStoreTac', 'SV_Shop_StoreTac', '24'), ('SVShopStoreAf', 'SV_Shop_StoreAf', '21')]
LANDING_PAGE = '/Game/Blueprints/UI/Menu/Ingame/IngameHangar/WBP_Menu_IngameHangar_Confirmation_000'
LANDING_SETTINGS = '/Game/Datatables/UI/Menu/IngameMenu/IngameHangar/DA_LiveMenuIngameHangarSettings'
MENU_TABLE = '/Game/Datatables/UI/Menu/IngameMenu/DT_IngameMenuSettingData'
UI = MOD + '/UI/'


def command_rows(z, dt, items, extra=()):
    """LiveMenuCommandsDataTable rows: an item name -> SV_Buy_<item> with SV_Shop_<item> texts; 'takeoff' -> the stock
    take-off row; (row name, title key, StringArgs) -> a page-change row. All copies of the stock take-off row."""
    yes = dict(dt['rows'])[('1', 0)]
    assert dict((q[1], q[3]) for q in yes[2])['StringArgs'] == s('-1')    # the take-off row
    rows = []
    for item in list(items) + list(extra):
        row = copy.deepcopy(yes)
        if item == 'takeoff':
            name = 'SVTakeOff'
        elif isinstance(item, tuple):
            name, key, args = item
            setv(row[2], 'TitleTextID', s(key))
            setv(row[2], 'HelpTextID', s(key + '_Help'))
            setv(row[2], 'StringArgs', s(args))
        else:
            name = 'SVShop' + item
            setv(row[2], 'TitleTextID', s('SV_Shop_' + item))
            setv(row[2], 'HelpTextID', s('SV_Shop_' + item + '_Help'))
            setv(row[2], 'StringArgs', s('SV_Buy_' + item))
        z.nb.add(name)
        rows.append(((name, 0), row))
    return rows


def commands_table(new_path, items, extra=()):
    z = ZenPkg(stock(SHOP_TABLE_STOCK))
    rename_package(z, SHOP_TABLE_STOCK, new_path)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveMenuCommandsDataTable')
    assert o == len(p), (o, len(p))
    dt['rows'] = command_rows(z, dt, items, extra)
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveMenuCommandsDataTable')
    assert chk['rows'] == dt['rows']
    save(z, new_path)


def build_shop_rows():
    # the landing page's rows: the fallback items and the STORE's (Lua adds one set or the other)
    commands_table(SHOP_TABLE, SHOP_ITEMS, STORE_ROWS)
    # every page row that opens another page names one of the pages, by its menu id (20 + its place in STORE_PAGES)
    ids = {str(STORE_MENU_FIRST + k) for k in range(len(STORE_PAGES))}
    for _, _, _, items in STORE_PAGES:
        assert len(items) <= 6, items                                    # (a page shows 6 rows)
        assert all(i[2] in ids for i in items if isinstance(i, tuple)), items
    assert all(r[2] in ids for r in STORE_ROWS) and len(STORE_ROWS) <= 4, STORE_ROWS
    lua = survival_events.runtime_lua()
    for _, _, _, items in STORE_PAGES:                                    # every item is one CFG.shop.items knows
        for i in items:
            if not isinstance(i, tuple) and i != 'takeoff':
                assert re.search(r'\n\s+' + i + r'\s+= \{', lua), f'{i}: not in Scripts/sv_config.lua CFG.shop.items'
    menu_rows = []
    for menu_id, page, title, items in STORE_PAGES:
        table, settings, widget = DATA + 'DT_SV_' + page + 'Commands', UI + 'DA_SV_' + page + 'Settings', UI + 'WBP_SV_' + page
        commands_table(table, [i for i in items if not isinstance(i, tuple) and i != 'takeoff'],
                       [i for i in items if isinstance(i, tuple)] + ['takeoff'])
        # its settings asset: the landing page's, pointing at its own command table
        z = ZenPkg(stock(LANDING_SETTINGS))
        rename_package(z, LANDING_SETTINGS, settings)
        old_t = SHOP_TABLE_STOCK
        z.rename(old_t, table); z.rename(old_t.rsplit('/', 1)[1], table.rsplit('/', 1)[1])
        assert table in z.names and old_t not in z.names
        save(z, settings)
        # the page: the landing page's widget blueprint under Survival's path (its objects keep their names: a zen
        # package's export hashes are package-relative), its settings import retargeted, its title key renamed
        z = ZenPkg(stock(LANDING_PAGE))
        z.rename(LANDING_PAGE, widget)
        retarget_import(z, LANDING_SETTINGS, settings)
        z.rename('CampaignReturnTitle_Name_Resupply', title)
        assert widget in z.names and LANDING_PAGE not in z.names
        save(z, widget)
        menu_rows.append((menu_id, widget))
    # the menu-class rows: in-game menus Survival's landing rows open by number
    z = ZenPkg(stock(MENU_TABLE))
    rename_package(z, MENU_TABLE, DATA + 'DT_SV_MenuClassRows')
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveMenuClassTable')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    hangar = [r for k, r in dt['rows'] if dict((q[1], q[3]) for q in r[2])['MenuID'] == ('name', 'IngameHagarMenu', 0)][0]
    out = []
    cls = LANDING_PAGE.rsplit('/', 1)[1] + '_C'
    mc = {n: k for k, (n, t) in uprop.U.schema('LiveMenuClassTable').items()}      # (setv knows other schemas)
    for menu_id, widget in menu_rows:
        row = copy.deepcopy(hangar)
        set_prop(row[2], mc['MenuID'], 'MenuID', ('name', menu_id, 0))
        ref = dict((q[1], q[3]) for q in row[2])['MenuWidgetReference']
        assert ref[0] == 'soft' and ref[1][1] == LANDING_PAGE and ref[2][1] == cls, ref
        set_prop(row[2], mc['MenuWidgetReference'], 'MenuWidgetReference', ('soft', ('name', widget, 0), ('name', cls, 0), ref[3]))
        name = menu_id.replace('_', '')
        for n in (menu_id, widget, name): z.nb.add(n)
        out.append(((name, 0), row))
    dt['rows'] = out
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveMenuClassTable')
    assert chk['rows'] == dt['rows']
    save(z, DATA + 'DT_SV_MenuClassRows')


# Survival's main-menu pages (user, 2026-10-27: "when you press Survival Mode, it brings you into another Menu, where you
# can select what version you want to play"; Scripts/sv_menu.lua, tools/re/MENU_PAGES.md). Each page is a copy of the
# game's own main-menu page (tools/menu_stock.py: the widget blueprint that imports DA_LiveMenuMainTopPageSettings), so
# its rows' presses reach main.dll's main-menu hook (OnMainDecide, vtable A) as SURVIVAL MODE's always have; its own
# settings asset (DA_SV_Pg<page>Settings: title, every tab's command table) and command table (DT_SV_Pg<page>Commands:
# copies of the main menu's Campaign row). DT_SV_MainMenuClassRows names the pages for the game's main-menu page table
# (MenuID SV_Pg<page>), where Lua adds them at the main menu. A row: (name, StringArgs, MenuID); its texts are
# SV_Pg_<page>_<name> / _Help (Lua sets them). StringArgs: SV_Mode_<mode> picks a mode (its MenuID opens its setup page,
# or the difficulty page for Join), SV_Go_<mode> / SV_Quick start (the difficulty page, which starts Survival),
# SV_Page_<page> opens another page, SV_Set_<what> steps a setting in place (main.dll takes the press). Keep the pages
# and rows in step with Scripts/sv_menu.lua PAGES / SET (checked below).
DIFFICULTY_PAGE = 'CampaignFreeMissionDifficulty'
MAIN_TOP_PAGE = 'Top'                                  # the main menu's own page (ELiveMenuMainIDs)
# The main menu opens a row's page by ELiveMenuMainIDs, the game's fixed list of its pages, so a row naming SV_Pg<page>
# opened nothing (test of 2026-10-29). Every row that opens one of Survival's pages names CAMPAIGN TRAINING's page instead
# (user, 2026-10-29: "feel free to use the Campaign Training and replace it completely"), and main.dll points that page's
# entry in the game's page list at the page the press opens (OnMainDecide, SV_MenuSlot). MENU_PAGES keeps which page.
# The game doesn't open the page it's on (test of 2026-10-29: the setup rows on the modes page did nothing), so the
# setup pages go through a second page PC players never see, the PS5 DualSense first-start setup (main.dll kSlotIds,
# kPageSlotOf; its own class comes back when any other main-menu entry is picked).
BORROWED_PAGE = 'CampaignTraining'
BORROWED_PAGE_2 = 'InitialSetting_DualSence'
SECOND_SLOT_PAGES = ('SV_PgOffline', 'SV_PgOnline', 'SV_PgHost')
# A page already open under the one shown isn't opened again: the game goes back to it (test of 2026-10-29: MORE RULES
# went back to the modes page), so MORE RULES has a third, the first-start Accessibility setup (main.dll slot 2).
BORROWED_PAGE_3 = 'InitialSetting_Accessibility'


def page_menu_id(menu):
    if menu in SECOND_SLOT_PAGES: return BORROWED_PAGE_2
    if menu == 'SV_PgRules': return BORROWED_PAGE_3
    return BORROWED_PAGE if menu.startswith('SV_Pg') else menu
MENU_PAGES = [
    ('Modes', [('Offline', 'SV_Mode_Offline', 'SV_PgOffline'), ('Online', 'SV_Mode_Online', 'SV_PgOnline'),
               ('Host', 'SV_Mode_Host', 'SV_PgHost'), ('Join', 'SV_Mode_Join', DIFFICULTY_PAGE),
               ('Quick', 'SV_Quick', DIFFICULTY_PAGE), ('Back', 'SV_Back', MAIN_TOP_PAGE)]),
    ('Offline', [('Go', 'SV_Go_Offline', DIFFICULTY_PAGE), ('Preset', 'SV_Set_Preset', ''), ('Zollars', 'SV_Set_Zollars', ''),
                 ('Enemies', 'SV_Set_Enemies', ''), ('Rules', 'SV_Page_Rules', 'SV_PgRules'), ('Back', 'SV_Back', 'SV_PgModes')]),
    ('Online', [('Go', 'SV_Go_Online', DIFFICULTY_PAGE), ('Preset', 'SV_Set_Preset', ''), ('Zollars', 'SV_Set_Zollars', ''),
                ('Enemies', 'SV_Set_Enemies', ''), ('Rules', 'SV_Page_Rules', 'SV_PgRules'), ('Back', 'SV_Back', 'SV_PgModes')]),
    ('Host', [('Go', 'SV_Go_Host', DIFFICULTY_PAGE), ('Lobby', 'SV_Set_Lobby', ''), ('Room', 'SV_Set_Room', ''),
              ('CoopEnemies', 'SV_Set_CoopEnemies', ''), ('Preset', 'SV_Set_Preset', ''), ('Zollars', 'SV_Set_Zollars', ''),
              ('Enemies', 'SV_Set_Enemies', ''), ('Rules', 'SV_Page_Rules', 'SV_PgRules'), ('Back', 'SV_Back', 'SV_PgModes')]),
    ('Rules', [('StartRound', 'SV_Set_StartRound', ''), ('Break', 'SV_Set_Break', ''), ('Specials', 'SV_Set_Specials', ''),
               ('Airfield', 'SV_Set_Airfield', ''), ('Pay', 'SV_Set_Pay', ''), ('Skill', 'SV_Set_Skill', ''),
               ('Reset', 'SV_Set_Reset', ''), ('Back', 'SV_Back', 'SV_PgOffline')]),
]
# BACK (test of 2026-10-29: the pages copy the main menu's top page, whose cancel goes nowhere, so MORE RULES was a dead
# end) names the page under it (any setup page's id is the same borrowed page), and the game goes back to a page that's
# already open rather than open it again (the same test: MORE RULES on the modes page's id went back to it).
MENU_STOCK = os.path.join(ROOT, 'build', 'menu', 'stock.json')            # tools/menu_stock.py
MENU_STOCK_LUA = os.path.join(ROOT, 'build', 'menu', 'sv_menu_stock.lua')  # staged into Scripts/ by build_all.sh
MAIN_COMMANDS = '/Game/Datatables/UI/Menu/MainMenu/Top/DT_LiveMenuMainTopCommands'


def check_menu_pages():
    """MENU_PAGES against Scripts/sv_menu.lua: the same pages and rows in the same order, every SV_Set_ row a setting
    (or action) it knows, every page row's MenuID one of the pages or the difficulty page."""
    lua = open(os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'sv_menu.lua'), encoding='utf-8').read()
    pages = re.findall(r'\{ name = "(\w+)", rows = \{([^}]*)\} \}', lua)
    assert [(n, re.findall(r'"(\w+)"', r)) for n, r in pages] == [(n, [x[0] for x in rows]) for n, rows in MENU_PAGES], \
        'tools/build_survival.py MENU_PAGES and Scripts/sv_menu.lua PAGES differ'
    assert re.findall(r'\{ row = "(\w+)", set = "\w+" \}', lua) == SETTING_ROWS, \
        'tools/build_survival.py SETTING_ROWS and Scripts/sv_menu.lua FLAT differ'
    ids = {'SV_Pg' + n for n, _ in MENU_PAGES} | {DIFFICULTY_PAGE, MAIN_TOP_PAGE, ''}
    for n, rows in MENU_PAGES:
        for name, args, menu in rows:
            assert menu in ids, (n, name, menu)
            assert (menu == '') == args.startswith('SV_Set_'), (n, name, args, menu)   # (a setting row opens nothing)
            if args.startswith('SV_Set_') and args[7:] not in ('Lobby', 'Reset'):
                assert re.search(r'\n    ' + args[7:] + r' = \{ (key|coop) = ', lua), f'{args}: not in Scripts/sv_menu.lua SET'
            assert len(f'SV_Pg_{n}_{name}_Help') < 48, name                  # (the runtime's text keys: DYN_KEY 48)


def page_settings(stock_da, new_da, table, title):
    """The main menu's page settings under Survival's name: its title, and every tab's command table ours."""
    z = ZenPkg(stock(stock_da))
    rename_package(z, stock_da, new_da)
    i = z.export_index(new_da.rsplit('/', 1)[1])
    v, rest = props_of(z, i, 'LiveMenuPageSettingsData')
    tabs = uprop.get(v, 'TabSettings')
    assert tabs and tabs[3][0] == 'arr' and tabs[3][1], f'{stock_da}: no TabSettings'
    short = table.rsplit('/', 1)[1]
    for n in (table, short):
        z.nb.add(n)
    for tab in tabs[3][1]:
        uprop.setp(tab, 'CommandSettings', ('soft', ('name', table, 0), ('name', short, 0), ''))
        uprop.setp(tab, 'TabTitleTextID', s(title))
        tab[2].sort(key=lambda q: q[0])                         # (setp appends; the read-back is in index order)
    uprop.setp(v, 'TitleTextID', s(title))
    v[2].sort(key=lambda q: q[0])
    z.payloads[i] = bytearray(write_props(z, v) + rest)
    chk, _ = props_of(z, i, 'LiveMenuPageSettingsData')
    assert chk == v
    save(z, new_da)
    return len(tabs[3][1])


def drop_menu_pages():
    """No pages this build: none left from an earlier one either (mod/Content is not cleaned between builds)."""
    import glob
    gone = []
    for pat in (DATA + 'DT_SV_Pg*Commands', UI + 'DA_SV_Pg*Settings', UI + 'WBP_SV_Pg*', DATA + 'DT_SV_MainMenuClassRows'):
        for f in glob.glob(os.path.join(OUT, pat[len('/Game/'):]) + '.uasset'):
            os.remove(f); gone.append(os.path.basename(f))
    if os.path.exists(MENU_STOCK_LUA): os.remove(MENU_STOCK_LUA)
    if gone: print(f'  menu pages: removed {len(gone)} left from an earlier build')


def build_menu_pages():
    check_menu_pages()
    os.makedirs(os.path.dirname(MENU_STOCK_LUA), exist_ok=True)
    st = json.load(open(MENU_STOCK, encoding='utf-8')) if os.path.exists(MENU_STOCK) else {'why': 'no build/menu/stock.json (tools/menu_stock.py)'}
    if not st.get('page'):
        print(f"  menu pages: SKIPPED ({st.get('why')}); the main menu keeps the flat rows")
        drop_menu_pages()
        return
    page, cls, settings = st['page'], st['page_class'], st['settings']
    widgets = []
    for name, rows in MENU_PAGES:
        table, da, widget = DATA + f'DT_SV_Pg{name}Commands', UI + f'DA_SV_Pg{name}Settings', UI + f'WBP_SV_Pg{name}'
        edits = []
        for row, args, menu in rows:
            def edit(props, row=row, args=args, menu=menu, page_name=name):
                edit_menu_row(props)
                setv(props, 'CommandID', ('name', f'Main_SV_{page_name}_{row}', 0))
                setv(props, 'TitleTextID', s(f'SV_Pg_{page_name}_{row}'))
                setv(props, 'HelpTextID', s(f'SV_Pg_{page_name}_{row}_Help'))
                setv(props, 'MenuID', s(page_menu_id(menu)))
                setv(props, 'StringArgs', s(args))
            edits.append((f'SV{name}{row}', edit))
        build_rows_table(MAIN_COMMANDS, table, 'LiveMenuCommandsDataTable', 'Campaign', edits[0][0], edits[0][1], more=edits[1:])
        tabs = page_settings(settings, da, table, f'SV_Pg_{name}_Title')
        # the page: the main menu's widget blueprint under Survival's path (its objects keep their names: a zen
        # package's export hashes are package-relative), its settings import retargeted
        z = ZenPkg(stock(page))
        z.rename(page, widget)
        retarget_import(z, settings, da)
        assert widget in z.names and page not in z.names
        save(z, widget)
        widgets.append((f'SV_Pg{name}', widget))
        print(f'  menu pages: {name}, {len(rows)} rows, {tabs} tab(s)')
    # the class rows: Survival's pages for the game's main-menu page table (the row struct of the in-game one)
    z = ZenPkg(stock(MENU_TABLE))
    rename_package(z, MENU_TABLE, DATA + 'DT_SV_MainMenuClassRows')
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveMenuClassTable')
    assert o == len(p), (o, len(p))
    src = dt['rows'][0][1]
    mc = {n: k for k, (n, t) in uprop.U.schema('LiveMenuClassTable').items()}
    out = []
    for menu_id, widget in widgets:
        row = copy.deepcopy(src)
        ref = dict((q[1], q[3]) for q in row[2])['MenuWidgetReference']
        assert ref[0] == 'soft', ref
        set_prop(row[2], mc['MenuID'], 'MenuID', ('name', menu_id, 0))
        set_prop(row[2], mc['MenuWidgetReference'], 'MenuWidgetReference', ('soft', ('name', widget, 0), ('name', cls, 0), ref[3]))
        name = menu_id.replace('_', '')
        for n in (menu_id, widget, cls, name): z.nb.add(n)
        out.append(((name, 0), row))
    dt['rows'] = out
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveMenuClassTable')
    assert chk['rows'] == dt['rows']
    save(z, DATA + 'DT_SV_MainMenuClassRows')
    # what the runtime needs to know of the stock (Scripts/sv_menu.lua reads it; build_all.sh stages it)
    lua = ['-- made by tools/build_survival.py from tools/menu_stock.py\'s finds: the game\'s main-menu page Survival\'s pages',
           '-- copy (its class) and the game\'s main-menu page tables (Survival\'s pages go in them at start)',
           'return {', f'    page_class = "{cls}",',
           '    class_tables = { ' + ', '.join(f'"{t}"' for t in st.get('class_tables', [])) + ' },', '}', '']
    open(MENU_STOCK_LUA, 'w', encoding='utf-8', newline='\n').write('\n'.join(lua))
    print(f'  menu pages: {len(widgets)} pages, copies of {page} ({cls}); page tables {st.get("class_tables")}')


# Named aces and squadrons of skill tiers 6-10 (main.lua CFG.aces; user, 2026-10-22: "build it with this line up, but
# custom names"). For each tier and airframe key: a lead row (a flight's first aircraft: the ace, under its own name) and
# a wing row (the rest: the squadron's name), DT_NPC copies of the stock rows below (their skins come along) with
# Survival's text key as callsign (GameObjectDisplayName02, as the shuttle's): main.lua sets the texts from CFG.aces
# through the text hook, so players rename them in survival.ini. Keep in step with main.lua ACE_ROSTER.
ACES = [  # (tier, key, lead DT_NPC row, wing DT_NPC row)
    ('mercenary', 'f15c',    'OP1004_f15c_Shark_01',   'OP1004_f15c_Shark_02'),
    ('mercenary', 'su35',    'OP1028_su35_Ventus_01',  'OP1028_su35_Ventus_02'),
    ('mercenary', 'typhoon', 'OP1011_typn_01',         'OP1011_typn_01'),
    ('legend',    'su47',    'OP1026_su47_01',         'OP1026_su47_01'),
    ('legend',    'rafale',  'OP1014_rflm_Savia_01',   'OP1014_rflm_Savia_01'),
    ('demon',     'f22a',    'OP1005_f22a_01',         'OP1005_f22a_01'),
    ('demon',     'su57',    'OP1021_su57_02',         'OP1021_su57_02'),
    ('phantom',   'su57',    'OP1021_su57_Shadow_24',  'OP1021_su57_Shadow_25'),
    ('phantom',   'typhoon', 'OP1011_typn_Shadow_33',  'OP1011_typn_Shadow_32'),
    ('phantom',   'su47',    'OP1026_su47_Shadow_144', 'OP1026_su47_Shadow_145'),
    ('reaper',    'su57',    'OP1021_su57_Named',      'OP1021_su57_Shadow_26'),
    ('reaper',    'f22a',    'OP1005_f22a_Named',      'OP1005_f22a_Shadow_99'),
    ('reaper',    'typhoon', 'OP1011_typn_Named',      'OP1011_typn_Shadow_37'),
    ('reaper',    'rafale',  'OP1014_rflm_Named',      'OP1011_typn_Shadow_39'),
    ('reaper',    'adfx02',  'OP1021_su57_Named',      'OP1021_su57_Named'),        # model: ACE_MODELS
    # the Anomaly's MINDRIPPER (lead) and its guards (wing): main.lua CFG.specials.anomaly names them
    ('anomaly',   'f04e',    'OP1003_f04e_Named',      'OP1003_f04e_Named'),
    # AB.L..IN (lead; no wing flies): main.lua CFG.specials.glitch names it and its squadron tag
    ('glitch',    'e18g',    'OP1010_e18g_Named',      'OP1010_e18g_Named'),
    # VALKA (lead; no wing flies): Mission 26's x40a with its railguns (survival_events.VALKA_*) until the X-02S is
    # built; main.lua CFG.specials.valka names her
    ('valka',     'x40a',    'OP1016_x40a_MS26',       'OP1016_x40a_MS26'),
]
# Airframes only Online Mode has (user, 2026-10-22: "ADFX-02 appears in the Online Mode"): their model rows are in
# DT_NPC_Model_ON, not the campaign's DT_NPC_Model, so DT_SV_ModelRows carries copies (GameObjectId 1 like every
# campaign model, Survival's text key for the aircraft name) that main.lua adds to DT_NPC_Model at the main menu, and
# the ace rows above (copies of a campaign row, for its fire-control and weapon ids) are given that model, no skin.
# Their blueprints (/Game/OnlineMode/Blueprint/AI/Actors/Plane/...) derive from the campaign's BP_AIPlane_Pawn.
# (tier, key) -> (DT_SV_ModelRows row, DT_NPC_Model_ON row, text key). Keep in step with main.lua ACE.models.
ACE_MODELS = {
    ('reaper', 'adfx02'): ('SV_Model_adfx', 'OP1038_adfx02_L001', 'SV_Ac_adfx'),
}
MODEL_ON = '/Game/OnlineMode/DataTables/AI/NPC/DT_NPC_Model_ON'
MODEL_CP = '/Game/Datatables/AI/NPC/Model/DT_NPC_Model'          # (the campaign's: the CIWS's model row is checked there)


def ace_rows(tier, key):
    """(lead, wing), each (DT_SV_NpcMission row, DT_NPC row, text key); no numeric tails (hard rule 17)."""
    b = f'{tier}_{key}'
    return ((f'sv_ace_{b}_l', f'SV_Ace_{b}_L', f'SV_Ace_{b}'), (f'sv_ace_{b}_w', f'SV_Ace_{b}_W', f'SV_Sqn_{tier}'))


def build_npc_rows():
    """DT_SV_NpcRows: the shuttle's row and the aces' rows, which main.lua adds to DT_NPC at the main menu (before the
    level loads: the spawner reads them then)."""
    path = '/Game/Datatables/AI/NPC/DT_NPC'
    z = ZenPkg(stock(path))
    rename_package(z, path, DATA + 'DT_SV_NpcRows')
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveNpcDataTable')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    name_idx = [k for k, (n, t) in uprop.U.schema('LiveNpcDataTable').items() if n == 'GameObjectDisplayName02'][0]
    shuttle = copy.deepcopy(rows[('OP0057_sstb_01', 0)])
    edit_shuttle_npc(shuttle[2])
    out = [((survival_events.SHUTTLE_NPC, 0), shuttle)]
    schema = uprop.U.schema('LiveNpcDataTable')
    model_idx = [k for k, (n, t) in schema.items() if n == 'ModelId'][0]
    skin_idx = [k for k, (n, t) in schema.items() if n == 'AirframeSkinId'][0]
    emptied = []
    for tier, key, lead, wing in ACES:
        for src, (_, npc, text) in zip((lead, wing), ace_rows(tier, key)):
            f = survival_events.fname(src)
            row = copy.deepcopy(rows[(f[1], f[2])])
            # (0.73.77, G1) a scripted sure kill's slot emptied (the Phantom Su-47s' NPC_FCS_PlaneMsl302 and Mission 19's
            # hit missile, the Reaper F-22 wings' NPC_FCS_PlaneMsl100): Lua gives a free slot from 3 a special weapon
            for q in [q for q in row[2] if q[1].startswith('NpcFCSId') and q[3] and q[3][0] == 'name']:
                why = certain_kill(q[3][1] if q[3][2] == 0 else f'{q[3][1]}_{q[3][2] - 1}')
                if why:
                    drop_prop(row[2], q[0])
                    emptied.append(f'{npc} {q[1]}: {why}')
            set_prop(row[2], name_idx, 'GameObjectDisplayName02', s(text))
            if (tier, key) in ACE_MODELS:
                set_prop(row[2], model_idx, 'ModelId', ('name', ACE_MODELS[(tier, key)][0], 0))
                drop_prop(row[2], skin_idx)                               # the model's own look
            out.append(((npc, 0), row))
    # the STORE's allies (survival_events.ALLY_*): MOONCHILD (an F-22 under its squadron's name key), each ship's hull
    # (under its name key) and turrets (as they are: main.lua gives every one of them fire control of its own)
    m22 = mission_npc_ids()
    allies = [(survival_events.ALLY_AIR_SOURCE_NPC, survival_events.ALLY_AIR_NPC, survival_events.ALLY_AIR_NAME_KEY),
              (survival_events.ALLY_WINGMEN_SOURCE_NPC, survival_events.ALLY_WINGMEN_NPC, survival_events.ALLY_WINGMEN_NAME_KEY),
              (survival_events.AWACS_SOURCE_NPC, survival_events.AWACS_NPC, survival_events.AWACS_NAME_KEY)]
    allies += [(m22[src], npc, None) for src, (_, npc) in survival_events.DEFENCE_ROWS.items()]   # the airfield's defences

    for key, _, hull, _ in survival_events.ALLY_SHIPS:
        _, npc, text = survival_events.ally_ship_rows(key)
        allies.append((m22[hull], npc, text))
        allies += [(m22[t], survival_events.ally_turret_rows(t)[1], None) for t in survival_events.ALLY_TURRETS[key]]
    # (the STORE's ships: their hulls' and turrets' ChildNPCId naming the allied turret rows, SV_Turret_<row>_Ally: a ship's
    # parts spawn on the rows its hull's DT_NPC row names (hard rule 38), so with the stock ChildNPCId the turrets flew the
    # stock rows and never got their own fire control: the user's "aegis ships still don't engage far enough" of 2026-10-23,
    # found with the Spaceport fleet's of 2026-10-31; user: "I want it fixed also")
    ally_kid = {m22[t]: survival_events.ally_turret_rows(t)[1] for k, _, _, _ in survival_events.ALLY_SHIPS
                for t in survival_events.ALLY_TURRETS[k]}
    ally_ship_rows = ({survival_events.ally_ship_rows(k)[1] for k, _, _, _ in survival_events.ALLY_SHIPS}
                      | {survival_events.ally_turret_rows(t)[1] for k, _, _, _ in survival_events.ALLY_SHIPS
                         for t in survival_events.ALLY_TURRETS[k]})
    ally_shown = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    ally_remapped = 0
    for src, npc, text in allies:
        f = survival_events.fname(src)
        row = copy.deepcopy(rows[(f[1], f[2])])
        if npc in ally_ship_rows:
            for i, q in enumerate(row[2]):
                if q[1] == 'ChildNPCId' and q[3]:
                    kids = []
                    for k in q[3][1]:
                        assert ally_shown(k) in ally_kid, f'{npc}: its child {ally_shown(k)} has no allied turret row'
                        kids.append(('name', ally_kid[ally_shown(k)], 0))
                        ally_remapped += 1
                    row[2][i] = (q[0], q[1], q[2], ('arr', kids))
        if text: set_prop(row[2], name_idx, 'GameObjectDisplayName02', s(text))
        if npc == survival_events.AWACS_NPC:              # VOID WATCHER 1 on Survival's model row (no MAGNOLIA name)
            set_prop(row[2], model_idx, 'ModelId', ('name', survival_events.AWACS_MODEL, 0))
        if npc == survival_events.ALLY_WINGMEN_NPC:      # SNIPER's LAAMs where the F-16C's standard missile is
            was, now = survival_events.ALLY_WINGMEN_MISSILE
            swapped = 0
            for i, q in enumerate(row[2]):
                if q[1].startswith('NpcFCSId') and q[3] == ('name', was, 0):
                    row[2][i] = (q[0], q[1], q[2], ('name', now, 0))
                    swapped += 1
            assert swapped == 1, f'{npc}: {was} in {swapped} fire-control slots, 1 expected'
            z.nb.add(now)
        out.append(((npc, 0), row))
    # the Spaceport fleet's turrets and armed hulls (survival_events.SP_TURRETS / SP_HULLS): copies of their stock rows,
    # every ChildNPCId naming the fleet's own copy (a ship's parts spawn on the rows its hull's row names: hard rule 38)
    shown = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    fleet_of = {(stock_npc or m22[src]): npc for src, _, npc, stock_npc in survival_events.SP_TURRETS}
    remapped = 0
    for src, npc in ([(stock_npc or m22[src], npc) for src, _, npc, stock_npc in survival_events.SP_TURRETS]
                     + [(stock, npc) for _, npc, stock in survival_events.SP_HULLS]):
        f = survival_events.fname(src)
        row = copy.deepcopy(rows[(f[1], f[2])])
        for i, q in enumerate(row[2]):
            if q[1] == 'ChildNPCId' and q[3]:
                kids = []
                for k in q[3][1]:
                    assert shown(k) in fleet_of, f'{npc}: its child {shown(k)} has no fleet row (SP_TURRETS)'
                    kids.append(('name', fleet_of[shown(k)], 0))
                    remapped += 1
                row[2][i] = (q[0], q[1], q[2], ('arr', kids))
        out.append(((npc, 0), row))
    assert remapped == 3 + 1 + 1 + 4, remapped              # (the Aegis's 3 and its mount's artillery, the boat's, the Ford's 4)
    assert ally_remapped == 3 + 1, ally_remapped           # (the Aegis's 3 turrets and its gun mount's artillery)
    # the STORE's CIWS (survival_events.DEFENCE_CIWS*): the game's land Phalanx on its allied model row (no NpcFCSId: its
    # blueprint's own arms fire, until main.lua gives it one: CFG.shop.items.Airfield.defences.ciws.fcs_row)
    f = survival_events.fname(survival_events.DEFENCE_CIWS_NPC)
    ciws = copy.deepcopy(rows[(f[1], f[2])])
    assert not any(q[1].startswith('NpcFCSId') and q[3] for q in ciws[2]), 'the CIWS row names a fire control now'
    zm = ZenPkg(stock(MODEL_CP))                       # (the game's model row, never ours: its blueprint is the ally's)
    dm, _ = dtx.parse(uprop.Ctx(bytes(zm.payloads[0]), zm.names), 0, 'LiveModelDataTable')
    bp = dict((q[1], q[3]) for q in dict(dm['rows'])[(survival_events.DEFENCE_CIWS_MODEL, 0)][2])['BlueprintClass']
    assert bp[0] == 'soft' and bp[2][1] == 'BP_GR033_ciws_CP_Ally_C', bp            # (Scripts/sv_allies.lua DEF_CLASSES)
    set_prop(ciws[2], model_idx, 'ModelId', ('name', survival_events.DEFENCE_CIWS_MODEL, 0))
    out.append(((survival_events.DEFENCE_CIWS_ROW[1], 0), ciws))
    # the Ladons (survival_events.LADON*): the stock Ladon under each one's name key (main.lua: name, health, speed)
    for L in survival_events.ladons():
        row = copy.deepcopy(rows[(survival_events.LADON_NPC_SOURCE, 0)])
        set_prop(row[2], name_idx, 'GameObjectDisplayName02', s(L['name_key']))
        comps = [q for q in row[2] if q[1] == 'ChildNPCComponentNames'][0][3][1]   # its CIWS: the pulse cannon pods
        pulse = survival_events.fname(survival_events.LADON_PULSE_NPC)
        row[2][:] = [(q[0], q[1], q[2], ('arr', [pulse if (c[1] in survival_events.LADON_CIWS and c[2] == 0) else k
                                                  for c, k in zip(comps, q[3][1])])) if q[1] == 'ChildNPCId' else q for q in row[2]]
        assert sum(1 for k in [q for q in row[2] if q[1] == 'ChildNPCId'][0][3][1] if k == pulse) == len(survival_events.LADON_CIWS)
        out.append(((L['npc'], 0), row))
    # GONE FISHIN's shoal (survival_events.FISH_*): the stock invisible turret pawn GR000_dummy (BP_GR000_dummy_CP: no mesh,
    # no wreck, no children) with the boats' durability rows (the stock row has none: no damage table to take a hit by),
    # Survival's name key and its own model row (FISH_MODEL: MaxHealth FISH_HEALTH), no score
    se = survival_events
    f = se.fname(se.FISH_NPC_SOURCE)
    row = copy.deepcopy(rows[(f[1], f[2])])
    have = dict((q[1], q) for q in row[2])
    assert not any(q[1].startswith('NpcFCSId') and q[3] for q in row[2]) and not have['ChildNPCId'][3][1], 'GR000_dummy changed'
    assert have['BaseScore'][3] is None and have['ModelId'][3] == ('name', se.FISH_MODEL_SOURCE, 0), (have['BaseScore'], have['ModelId'])
    for name, value in (('WeaponDurabilityId', ('name', se.FISH_DURABILITY[0], 0)),
                        ('ExplosionDurabilityId', ('name', se.FISH_DURABILITY[1], 0)),
                        ('GameObjectDisplayName02', s(se.FISH_SUB_KEY)), ('ModelId', ('name', se.FISH_MODEL, 0))):
        set_prop(row[2], [k for k, (n, t) in schema.items() if n == name][0], name, value)
    out.append(((se.FISH_NPC, 0), row))
    # THE ESCORT's allied rows and the ZFA-44 host, THE DECOY's weaponless UAV (survival_events.ESCORT_DECOY_NPC_ROWS): copies
    # of the campaign's plain rows; an allied model with no skin row (the model's own look), MOONCHILD's behaviour set
    # (its row's LuaSet: hard rule 22, never NLID_0400_CP), the UAV's weapons emptied (its laser pod is its blueprint's)
    zm = ZenPkg(stock(MODEL_CP))
    models = {k[0] for k, _ in dtx.parse(uprop.Ctx(bytes(zm.payloads[0]), zm.names), 0, 'LiveModelDataTable')[0]['rows']}
    f = survival_events.fname(survival_events.ALLY_AIR_SOURCE_NPC)
    ally_set = dict((q[1], q[3]) for q in rows[(f[1], f[2])][2])['LuaSetId']
    assert ally_set and ally_set[1] != 'NLID_0400_CP', ally_set
    sidx = lambda n: [k for k, (nm, t) in schema.items() if nm == n][0]
    for npc, src, model, fly_ally, unarmed, key, full in survival_events.ESCORT_DECOY_NPC_ROWS:
        f = survival_events.fname(src)
        row = copy.deepcopy(rows[(f[1], f[2])])
        if model:
            assert model in models, f'{npc}: no model row {model}'
            set_prop(row[2], model_idx, 'ModelId', ('name', model, 0))
            drop_prop(row[2], skin_idx)
        if fly_ally:
            set_prop(row[2], sidx('LuaSetId'), 'LuaSetId', ally_set)
        if unarmed:
            row[2][:] = [q for q in row[2] if not q[1].startswith('NpcFCSId')]
        if key:
            set_prop(row[2], name_idx, 'GameObjectDisplayName02', s(key))
        if full:                                             # (the plain Su-47 flies at x0.8; its hit spheres kept)
            for q in [q for q in row[2] if q[1].endswith('Coefficient') and q[1] != 'SphereCollisionRadiusCoefficient']:
                set_prop(row[2], q[0], q[1], ('raw', 'Float', struct.pack('<f', 1.0)))
        assert survival_events.fname(npc)[2] == 0, npc
        zfa_twin = {survival_events.ZFA_NPC: (survival_events.ZFA_MODEL_SV, survival_events.ZFA_TLS_NPC),
                    survival_events.ZFA_DRONE_NPC: (survival_events.ZFA_DRONE_MODEL_SV, survival_events.ZFA_DRONE_TLS_NPC)}.get(npc)
        if zfa_twin:                            # ((2026-11-07) its box: "ZFA-44" over ZFA_SUB_KEY's, never its host's name:
            # the name is the model row's (GameObjectDisplayName01): Survival's copy of its host's, ZFA_MODEL_SV / _DRONE_)
            set_prop(row[2], model_idx, 'ModelId', ('name', zfa_twin[0], 0))
            set_prop(row[2], name_idx, 'GameObjectDisplayName02', s(survival_events.ZFA_SUB_KEY))
        out.append(((npc, 0), row))
        if zfa_twin:                            # (2026-11-07) ... and its twin with the anti-missile laser in the gun's slot
            slot = f'NpcFCSId{survival_events.ZFA_TLS_SLOT}'   # ((0.74.12) the user: "swap the guns out for the Laser Interceptor")
            assert [q[3] for q in row[2] if q[1] == slot] == [('name', survival_events.ZFA_TLS_GUN, 0)], (npc, slot, 'not the gun')
            tls = copy.deepcopy(row)
            set_prop(tls[2], sidx(slot), slot, ('name', survival_events.ZFA_TLS_FCS_ROW, 0))
            assert survival_events.fname(zfa_twin[1])[2] == 0
            out.append(((zfa_twin[1], 0), tls))
    print('  escort / decoy DT_NPC rows (Lua adds them at the main menu): '
          + ', '.join(f'{r[0]} ({r[1]}' + (f' on {r[2]}' if r[2] else '') + (', unarmed' if r[4] else '') + ')'
                      for r in survival_events.ESCORT_DECOY_NPC_ROWS) + f'; their behaviour set {ally_set[1]}; '
          + f'{survival_events.ZFA_TLS_NPC} ({survival_events.ZFA_NPC} with {survival_events.ZFA_TLS_FCS_ROW} in slot '
          + f'{survival_events.ZFA_TLS_SLOT})')
    for k, row in out:
        for n in names_in(row) + [k[0]]: z.nb.add(n)
    dt['rows'] = out
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveNpcDataTable')
    assert chk['rows'] == dt['rows']
    print(f'  DT_SV_NpcRows: {len(out)} rows ({len(ACES)} aces and their wings, {len(allies)} allies, the CIWS on '
          f'{survival_events.DEFENCE_CIWS_MODEL})')
    print(f'  aces: {len(emptied)} scripted sure-kill slots emptied (G1)' + ''.join(f'\n    {e}' for e in emptied))
    save(z, DATA + 'DT_SV_NpcRows')


def check_no_certain_kill():
    """(0.73.77, plan G1) Fails the build when a row Survival builds for an enemy, or a fire control the Lua puts on one
    (CFG.special.fcs, the bosses' weapons ...), carries a scripted sure kill (certain_kill; hard rule 36). Every
    DT_SV_NpcMission row but the allies' and the co-op stand-ins' (<row>_svcp: damage 0) is followed to the DT_NPC row it
    flies (the stock DT_NPC, DT_SV_NpcRows, DT_SV_AlcnNpc; for a row whose DT_NPC row Lua clones, its source's: <row>_sv[bcd]
    the row's, the roles' and probes' NPC_SOURCE's) and down every ChildNPCId (ships', the Ladons', the Alicorn's parts).
    Reads the packages this build saved."""
    plain = lambda k: k[0] if k[1] == 0 else f'{k[0]}_{k[1] - 1}'
    nm = lambda v: plain(v[1:3]) if v and v[0] == 'name' else None

    def load(path, st, built=True):
        fn = os.path.join(OUT, path[len('/Game/'):]) + '.uasset' if built else stock(path)
        z = ZenPkg(data=open(fn, 'rb').read())
        dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
        return {plain(k): dict((q[1], q[3]) for q in r[2]) for k, r in dt['rows']}
    npc = load('/Game/Datatables/AI/NPC/DT_NPC', 'LiveNpcDataTable', built=False)
    for t in ('DT_SV_NpcRows', 'DT_SV_AlcnNpc'): npc.update(load(DATA + t, 'LiveNpcDataTable'))
    mission = load(NPC_TABLE, 'LiveNpcMissionDataTable')
    se = survival_events
    allied = ({se.ALLY_AIR_ROW, se.ALLY_WINGMEN_ROW, se.AWACS_ROW, se.DEFENCE_CIWS_ROW[0], se.SHUTTLE_NPC_ROW}
              | {row for row, _ in se.DEFENCE_ROWS.values()}
              | {se.ally_ship_rows(k)[0] for k, _, _, _ in se.ALLY_SHIPS}
              | {se.ally_turret_rows(t)[0] for k, _, _, _ in se.ALLY_SHIPS for t in se.ALLY_TURRETS[k]}
              | se.ESCORT_ALLIED_ROWS)                     # (THE ESCORT's: CHARLENE, her escorts, the cargo ships, the ZFA-44s)
    bad = []

    def carries(row, path, seen):
        if row in seen: return
        seen.add(row)
        r = npc.get(row)
        if r is None:
            bad.append(f'{path}: no DT_NPC row {row} (what does it carry?)'); return
        for i in range(6):
            f = nm(r.get(f'NpcFCSId{i}'))
            why = f and certain_kill(f)
            if why: bad.append(f'{path} slot {i}: {why}')
        kids = r.get('ChildNPCId')
        for k in (kids[1] if kids and kids[0] == 'arr' else []):
            carries(nm(k), f'{path} > {nm(k)}', seen)

    def source(m, depth=0):
        n = nm(mission[m].get('NpcId'))
        if n in npc or depth > 4: return n
        b = re.match(r'^(.*)_sv[bcd]?$', m)
        if b and b.group(1) in mission: return source(b.group(1), depth + 1)
        if NPC_SOURCE.get(m) in mission: return source(NPC_SOURCE[m], depth + 1)
        return n
    enemies = [m for m in sorted(mission) if m not in allied and not m.endswith(COOP_STANDIN_SUFFIX[0])]
    for m in enemies:
        n = source(m)
        carries(n, f'{m} -> {n}', set())
    lua_fcs = sorted(set(re.findall(r'"(NPC_FCS_\w+)"', survival_events.runtime_lua())))
    for f in lua_fcs:
        why = certain_kill(f)
        if why: bad.append(f'Scripts/*.lua names {why}')
    if bad:
        raise SystemExit('G1: a scripted sure kill on an enemy (hard rule 36; PLAIN_NPC_IDS, build_npc_rows):\n  '
                         + '\n  '.join(bad))
    print(f'  sure kills: none on {len(enemies)} enemy rows (their parts too) nor on the {len(lua_fcs)} fire controls '
          f'the Lua names (G1)')


def check_fishing_build():
    """(2026-11-06) GONE FISHIN' and THE FESTIVAL read back from the packages this build saved: every unit the build
    contract names, by the name SV_Spawn gives (a digit tail split as the engine splits it), with its objects, rows, side
    and spots (each object at its unit's height: SV_Spawn keeps the offsets); every path the records name; every record
    Lua fires, each exec's objects / units / paths in the world data; the rows Lua adds at the main menu."""
    se = survival_events
    plain = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    load = lambda path: ZenPkg(data=open(os.path.join(OUT, path[len('/Game/'):]) + '.uasset', 'rb').read())
    zw = load(MI + 'WD_SurvivalMode_global')
    w, _ = props_of(zw, zw.export_index('WD_SurvivalMode_global'), 'LiveWorldData')
    units = {plain([q for q in u[2] if q[1] == 'Name'][0][3]): u for u in [p for p in w[2] if p[1] == 'UnitDescList'][0][3][1]}
    paths = {plain([q for q in el[2] if q[1] == 'Name'][0][3]): el for el in [p for p in w[2] if p[1] == 'AIPathDescList'][0][3][1]}
    objs = {}
    def walk(ob, unit):
        objs[plain([q for q in ob[2] if q[1] == 'Name'][0][3])] = unit
        for ch in (field_of(ob, 'ChildAIObjectDescs') or ('arr', []))[1]:
            walk(ch, unit)
    for un, u in units.items():
        for ob in objects_of(u): walk(ob, un)
    faction = lambda u: field_of(u, 'Faction')[2][2][0]
    want = []                                  # (unit, [objects], row, faction)
    for key, unit, obj, (gx, gy), pts in se.fish_units():
        want.append((unit, [f'{obj}_{k}' for k in range(se.FISH_PER_GROUND)], se.FISH_ROW, 2))
    want.append((se.SAL_BOAT_UNIT, [se.SAL_BOAT_OBJ], se.SAL_BOAT_ROW, 1))
    want += [(F['unit'], F['objs'], se.FEST_BOMBER_ROW, 2) for F in se.fest_bombers()]
    want += [(M['unit'], M['objs'], se.FEST_CM_ROW, 2) for M in se.fest_missiles()]
    want += [(unit, [obj], se.FEST_LIGHT_ROW, 1) for unit, obj, _, _ in se.fest_lights()]
    want.append((se.FEST_TOWN_UNIT, [f'{se.FEST_TOWN_OBJ}_{k}' for k in range(len(se.FEST_TOWN_BOXES))], se.DECOY_MARK_ROW, 1))
    for unit, names, row, side in want:
        assert unit in units, f'{unit} not in the world data'
        u = units[unit]
        assert survival_events.fname(unit) == [q for q in u[2] if q[1] == 'Name'][0][3], unit
        got = [plain(field_of(ob, 'Name')) for ob in objects_of(u)]
        assert got == names, (unit, got)
        assert all(field_of(ob, 'MissionNpcID') == ('name', row, 0) for ob in objects_of(u)), unit
        assert faction(u) == side and not field_of(u, 'bIsSpawnFromStart'), unit
        uz = spot_of(u)[2]
        assert all(abs(spot_of(ob)[2] - uz) < 0.5 for ob in objects_of(u)), (unit, 'an object off its unit height')
    # ((2026-11-07) the town's boxes: each object its own callsign key, at its spot, invincible, out of every attack)
    town = objects_of(units[se.FEST_TOWN_UNIT])
    for ob, (key, pt) in zip(town, se.fest_town()):
        assert field_of(ob, 'GameObjectDisplayNameID02') == ('name', key, 0), (key, field_of(ob, 'GameObjectDisplayNameID02'))
        assert all(field_of(ob, f) == ('raw', 'Bool', b'\x01') for f in ('bShowHUDBox', 'bShowCallSignForAlly', 'bIsInvincible',
                   'bIsInvincibleFromAI', 'bIsInvincibleFromWingman', 'bIsAttackTargetsException')), key
        assert math.dist(spot_of(ob), pt) < 1.0 and not field_of(ob, 'bIsLanding') and not field_of(ob, 'TargetMarkType'), key
    beams = [ch for unit, obj, _, _ in se.fest_lights() for ch in field_of(objects_of(units[unit])[0], 'ChildAIObjectDescs')[1]]
    assert len(beams) == len(se.FEST_LIGHTS) and all(
        field_of(field_of(ch, 'Data'), 'MissionNpcID') == ('name', se.FEST_BEAM_ROW, 0) for ch in beams), 'searchlight parts'
    lanes = {lane for M in se.fest_missiles() for lane, _ in M['lanes']}
    for name in [F[k] for F in se.fest_bombers() for k in ('path', 'side_path')] + sorted(lanes):
        assert name in paths and field_of(paths[name], 'ControlType')[2][2] == b'', name     # (hard rule 35)
    # the records
    ze = load(MI + 'EP_SurvivalMode_global')
    _, _, _, T, E, _ = ep_dump.load_bytes(ze)
    show = lambda v: ep_dump.show(v, ze)
    trig = [show(ep_dump.fields(t)['EventName']) for t in T]
    events = [ev for F in se.fest_bombers() for ev in (F['ev'], F['up'])] + [ev for M in se.fest_missiles() for ev in [M['ev']] + M['hits']]
    for ev in events:
        assert trig.count(ev) == 1, (ev, trig.count(ev))
    n_ex = 0
    for e in E:
        f = ep_dump.fields(e)
        ev = show(f['ConnectionEventName'])
        if ev not in events: continue
        n_ex += 1
        args = [show(ep_dump.fields(a)['Value']) for a in f['ArgsInfo'][1]]
        cls = show(f['ExecutionClass'])
        if cls in ('LiveAIPathExecution',):
            assert args[2] in paths and (args[0] in objs or args[1] in units), (ev, args[:3])
        elif cls in ('LiveEnableLandingGear', 'LiveAIEngagementOrder', 'LiveSetLookAheadTimeSec', 'LiveDestroyUnitExecution'):
            assert any(a in objs or a in units for a in args[:3]), (ev, cls, args[:3])
        else:
            assert cls == 'LiveFlagOperation_IntExecution', (ev, cls)
    # the rows (DT_SV_NpcMission, DT_SV_NpcRows, DT_SV_ModelRows, DT_SV_AlcnNpc / Model)
    def table(path, st):
        z = load(path)
        dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
        return {plain(('name',) + k): dict((q[1], q[3]) for q in r[2]) for k, r in dt['rows']}
    mission = table(NPC_TABLE, 'LiveNpcMissionDataTable')
    for row, npc in ((se.FISH_ROW, se.FISH_NPC), (se.SAL_BOAT_ROW, se.SAL_BOAT_NPC), (se.FEST_CM_ROW, 'OP0039_slcmp_01'),
                     (se.FEST_LIGHT_ROW, se.FEST_LIGHT_NPC), (se.FEST_BEAM_ROW, 'GR053_seli_light_01'), (se.FEST_BOMBER_ROW, 'OP0012_t160_01')):
        assert plain(mission[row]['NpcId']) == npc, (row, mission[row]['NpcId'])
    assert struct.unpack('<f', mission[se.SAL_BOAT_ROW]['MinHealth'][2])[0] == se.SAL_BOAT_MIN_HEALTH
    npc = table(DATA + 'DT_SV_NpcRows', 'LiveNpcDataTable')[se.FISH_NPC]
    assert (plain(npc['ModelId']), plain(npc['WeaponDurabilityId']), plain(npc['ExplosionDurabilityId']), npc['GameObjectDisplayName02'])         == (se.FISH_MODEL,) + se.FISH_DURABILITY + (s(se.FISH_SUB_KEY),), npc
    model = table(DATA + 'DT_SV_ModelRows', 'LiveModelDataTable')[se.FISH_MODEL]
    assert struct.unpack('<f', model['MaxHealth'][2])[0] == se.FISH_HEALTH, model['MaxHealth']
    alc = table(DATA + 'DT_SV_AlcnNpc', 'LiveNpcDataTable')
    alm = table(DATA + 'DT_SV_AlcnModel', 'LiveModelDataTable')
    assert se.FEST_LIGHT_NPC in alc and 'GR053_seli_light_01' in alc and {'GR053_seli', 'GR053_seli_light'} <= set(alm), 'searchlight rows'
    print(f'  fishing / festival: {len(want)} units, {len(events)} events ({n_ex} execs) and their rows read back from the '
          f'packages: all there')


def check_escort_decoy_build():
    """(2026-11-06) THE ESCORT, its cargo ships and THE DECOY read back from the packages this build saved: every unit the
    build contracts name, by the name SV_Spawn gives (a digit tail split as the engine splits it; the launch units exactly
    as the container launchers' arms name them), with its objects, rows, side, callsign key and parts; every path the
    records name (and its control type, as VOID WATCHER's proven orbit's); every remote event Lua fires, once each, and
    every exec's objects / units / paths / flags / radio groups there; the rows (DT_SV_NpcMission, DT_SV_NpcRows,
    DT_SV_Radio)."""
    se = survival_events
    plain = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    load = lambda path: ZenPkg(data=open(os.path.join(OUT, path[len('/Game/'):]) + '.uasset', 'rb').read())
    zw = load(MI + 'WD_SurvivalMode_global')
    w, _ = props_of(zw, zw.export_index('WD_SurvivalMode_global'), 'LiveWorldData')
    units = {plain([q for q in u[2] if q[1] == 'Name'][0][3]): u for u in [p for p in w[2] if p[1] == 'UnitDescList'][0][3][1]}
    paths = {plain([q for q in el[2] if q[1] == 'Name'][0][3]): el for el in [p for p in w[2] if p[1] == 'AIPathDescList'][0][3][1]}
    objs = {}

    def walk(ob, unit):
        objs[plain([q for q in ob[2] if q[1] == 'Name'][0][3])] = unit
        for ch in (field_of(ob, 'ChildAIObjectDescs') or ('arr', []))[1]:
            walk(ch, unit)
    for un, u in units.items():
        for ob in objects_of(u): walk(ob, un)
    faction = lambda u: field_of(u, 'Faction')[2][2][0]
    kids = lambda ob: [plain([q for q in ch[2] if q[1] == 'Name'][0][3]) for ch in (field_of(ob, 'ChildAIObjectDescs') or ('arr', []))[1]]
    want = []                      # (unit, [objects], row, faction or None, callsign key or None, [parts of the first object])
    for a in se.esc_aircraft():
        want.append((a['unit'], [a['obj']], a['row'], 1, a['name_key'], []))
    for s_, unit, obj, row, _, _, _, _, launcher in se.CARGO_SHIPS:
        want.append((unit, [obj], row, 1, se.CARGO_NAME_KEY,
                     sorted(f'{obj}_{c}' for c in ('BP_VE021_ctslf_cntus_01_CP', 'BP_VE021_ctslf_cntus_02_CP',
                                                   'BP_VE021_ctslf_cntus_03_CP', 'BP_VE021_stgr_Base')
                            if c in (launcher, 'BP_VE021_stgr_Base', 'BP_VE021_ctslf_cntus_02_CP'))))
        for n, dunit, dobjs in se.CARGO_ARMS[s_]:
            want.append((dunit, dobjs, se.ZFA_DRONE_ROW, 1, se.ZFA_SUB_KEY, []))
    for L, unit, obj, _ in se.ZFA_FALLBACK:
        want.append((unit, [f'{obj}_{k}' for k in range(se.ZFA_FALLBACK_N)], se.ZFA_ROW, 1, se.ZFA_SUB_KEY, []))
    want.append((se.DECOY_BAIT_UNIT, [se.DECOY_BAIT_OBJ], se.DECOY_BAIT_ROW, 2, None, [f'{se.DECOY_BAIT_OBJ}_{se.DECOY_POD}']))
    want.append((se.DECOY_BAIT_MARK_UNIT, [se.DECOY_BAIT_MARK_OBJ], se.DECOY_MARK_ROW, None, None, []))
    for _, unit, obj, munit, mobj in se.decoy_uavs():
        want.append((unit, [obj], se.DECOY_UAV_ROW, 2, None, [f'{obj}_{se.DECOY_POD}']))
        want.append((munit, [mobj], se.DECOY_MARK_ROW, None, None, []))
    for unit, obj in se.DECOY_SPEARS:
        want.append((unit, [obj], se.DECOY_SPEAR_ROW, None, None, [f'{obj}_TargetingDummy']))
    for unit, names, row, side, key, parts in want:
        assert unit in units, f'{unit} not in the world data'
        u = units[unit]
        assert survival_events.fname(unit) == [q for q in u[2] if q[1] == 'Name'][0][3], unit
        got = [plain(field_of(ob, 'Name')) for ob in objects_of(u)]
        assert got == names, (unit, got)
        assert all(field_of(ob, 'MissionNpcID') == ('name', row, 0) for ob in objects_of(u)), unit
        assert (side is None or faction(u) == side) and not field_of(u, 'bIsSpawnFromStart'), unit
        if key:
            assert all(field_of(ob, 'GameObjectDisplayNameID02') == ('name', key, 0) and
                       field_of(ob, 'bShowCallSignForAlly') == ('raw', 'Bool', b'\x01') for ob in objects_of(u)), (unit, key)
        assert sorted(kids(objects_of(u)[0])) == sorted(parts), (unit, kids(objects_of(u)[0]), parts)
    marks = [munit for _, _, _, munit, _ in se.decoy_uavs()] + [se.DECOY_BAIT_MARK_UNIT] + [u_ for u_, _ in se.DECOY_SPEARS]
    assert all(field_of(ob, 'bIsInvincible') and field_of(ob, 'bIsAttackTargetsException') for m in marks for ob in objects_of(units[m]))
    assert field_of(objects_of(units[se.ESC_CHAR_UNIT])[0], 'TargetMarkType') == ('enum', 'ELiveTargetMarkType', ('raw', 'Byte', b'\x03'))
    # the paths (ControlType as VOID WATCHER's arcs: no tube control, hard rule 35)
    ct = field_of(paths[se.AWACS_ARC_A], 'ControlType')
    want_paths = [se.ESC_PATH_ROUTE, se.ESC_PATH_FINAL, se.ESC_PATH_CIRCUIT] + [a['route'] for a in se.esc_aircraft()[1:]]
    want_paths += [f'SV_Path_{k}Slot{S}' for S, _ in se.ESC_SLOTS for k in ('Taxi', 'Stop')]
    want_paths += [se.zfa_climb_path(c[0], k) for c in se.CARGO_SHIPS for k in range(se.ZFA_PER_ARM)]
    for name in want_paths:
        assert name in paths and field_of(paths[name], 'ControlType') == ct, (name, ct)
    # the records
    ze = load(MI + 'EP_SurvivalMode_global')
    _, _, _, T, E, _ = ep_dump.load_bytes(ze)
    show = lambda v: ep_dump.show(v, ze)
    trig = [show(ep_dump.fields(t)['EventName']) for t in T]
    events = [ev for evs in se.ESC_EVENTS.values() for ev in evs] + ['RE_SV_EscortReset']
    events += [se.cargo_launch_event(s_, n) for s_ in se.CARGO_ARMS for n, _, _ in se.CARGO_ARMS[s_]]
    events += [se.zfa_climb_event(s_, n) for s_ in se.CARGO_ARMS for n, _, _ in se.CARGO_ARMS[s_]]
    events += [se.zfa_tls_event(s_, n) for s_ in se.CARGO_ARMS for n, _, _ in se.CARGO_ARMS[s_]] + [se.zfa_tls_event(f[0]) for f in se.ZFA_FALLBACK]
    events += [se.zfa_cover_event(s_, n) for s_ in se.CARGO_ARMS for n, _, _ in se.CARGO_ARMS[s_]] + [se.zfa_cover_event(f[0]) for f in se.ZFA_FALLBACK]
    events += [f'RE_SV_CargoRemove_{c[0]}' for c in se.CARGO_SHIPS] + [f'RE_SV_ZfaGo{f[0]}' for f in se.ZFA_FALLBACK]
    events += ['RE_SV_DecoyBaitLaser', 'RE_SV_DecoyBaitLaserOff', 'RE_SV_DecoyBaitPing', 'RE_SV_DecoyKill', 'SV_DecoySpearImpact']
    events += [f'RE_SV_DecoySpear_{k + 1}' for k in range(len(se.DECOY_SPEARS))]
    events += [f'RE_SV_Decoy{x}_{nn:02d}' for nn, *_ in se.decoy_uavs() for x in ('LaserOn', 'LaserOff', 'MarkOnMe')]
    events += [ev for _, ev, _, _, _ in se.decoy_radio()]
    contract = (['RE_SV_CharGo', 'RE_SV_CharFinal', 'RE_SV_CharRoll', 'RE_SV_CharTaxi', 'RE_SV_CharStop']
                + [f'RE_SV_Esc{n}{x}' for n, _, _, _ in se.ESC_ESCORTS for x in ('Go', 'Orbit', 'Final', 'Roll', 'Taxi', 'Stop')]
                + ['RE_SV_DecoyBaitLaser', 'RE_SV_DecoyKill'] + [f'RE_SV_DecoyLaserOn_{k:02d}' for k in range(1, 36)]
                + [f'RE_SV_DecoyLaserOff_{k:02d}' for k in range(1, 36)] + [f'RE_SV_DecoySpear_{k}' for k in range(1, 5)]
                + [f'RE_SV_DecoyRadio_{x}' for x in ('Lock', 'Incoming', 'Imminent', 'Hit', 'Brief')])
    assert set(contract) <= set(events), sorted(set(contract) - set(events))
    for ev in events:
        assert trig.count(ev) == 1, (ev, trig.count(ev))
    zr = load(RADIO)
    radio = {plain(('name',) + k) for k, _ in dtx.parse(uprop.Ctx(bytes(zr.payloads[0]), zr.names), 0, 'LiveRadioTable')[0]['rows']}
    mine = set(events) | {t for t in trig if t.startswith(('SV_CharUp', 'SV_EscUp', 'SV_CargoUp', 'SV_ZfaUp', 'SV_DecoyBaitUp',
                                                             'SV_DecoyUavUp_', 'SV_CharEnd')) or
                          any(t.startswith(f'SV_{n}End') for n, _, _, _ in se.ESC_ESCORTS)}
    flags = {se.fname(x) for x in se.INT_FLAGS}
    n_ex, classes = 0, {}
    for e in E:
        f = ep_dump.fields(e)
        ev = show(f['ConnectionEventName'])
        if ev not in mine: continue
        n_ex += 1
        args = [show(ep_dump.fields(a)['Value']) for a in f['ArgsInfo'][1]]
        cls = show(f['ExecutionClass'])
        classes[cls] = classes.get(cls, 0) + 1
        for c in f['ConditionalStatementTables'][1]:
            cv = [show(ep_dump.fields(a)['Value']) for a in ep_dump.fields(c)['ArgsInfo'][1]]
            assert se.fname(cv[0]) in flags, (ev, cv)
        if cls == 'LiveAIPathExecution':
            assert args[2] in paths and args[0] in objs, (ev, args[:3])
        elif cls == 'LiveFireOneShotWeapon':
            assert args[1] in objs and args[2] in ('Player', 'NoneSelect'), (ev, args[:3])
        elif cls == 'LiveAirshipLaserDesignate':
            assert args[0] in objs and args[2] in objs and args[8] == 'NoneSelect', (ev, args)
        elif cls in ('LiveAirshipStopLaserDesignate', 'LiveEnableLandingGear', 'LiveAIPathExitExecution'):
            assert args[0] in objs, (ev, cls, args[:2])
        elif cls in ('LiveSetCommonAttribute', 'LiveActorTeleportExecution'):
            assert args[1] in objs, (ev, cls, args[:3])
        elif cls in ('LiveAIEngagementOrder', 'LiveAIChangeEnemySearchType'):
            assert args[0] in objs or args[1] in units, (ev, cls, args[:3])
        elif cls in ('LiveUnitMoveActor', 'LiveChangeUnitRadius'):
            assert args[0] in units and (cls != 'LiveUnitMoveActor' or args[1] in objs or args[12] == 'NearPlayer'), (ev, cls, args[:3])
        elif cls in ('LiveSetActiveGameObjectExecution', 'LiveBattleNavigationExecution'):
            assert args[1] in units, (ev, cls, args[:3])
        elif cls == 'LiveFlagOperation_IntExecution':
            assert se.fname(args[0]) in flags, (ev, args)
        elif cls == 'LiveRadioPlayExecution':
            assert args[0] in radio, (ev, args)
        elif cls == 'LiveUniqueStateMachineTransitionEvent':  # (a carrier's container opened / closed: Mission 17's)
            assert args[0] in objs and args[1] in ('ToOpen', 'ToClose'), (ev, args)
        else:
            assert cls == 'LiveDestroyPlayerPlaneExecution' and not args, (ev, cls, args)
    impact = [t for t in T if show(ep_dump.fields(t)['EventName']) == 'SV_DecoySpearImpact'][0]
    assert [show(ep_dump.fields(a)['Value']) for a in ep_dump.fields(impact)['ArgsInfo'][1]] == [se.DECOY_SPEAR_TAG]
    # the rows
    def table(path, st):
        z = load(path)
        dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
        return {plain(('name',) + k): dict((q[1], q[3]) for q in r[2]) for k, r in dt['rows']}
    mission = table(NPC_TABLE, 'LiveNpcMissionDataTable')
    npc = table(DATA + 'DT_SV_NpcRows', 'LiveNpcDataTable')
    for row, _, src, nid, hp in se.ESCORT_DECOY_MISSION_ROWS:
        assert row in mission, row
        assert nid is None or plain(mission[row]['NpcId']) == nid, (row, mission[row]['NpcId'])
        assert hp is None or struct.unpack('<f', mission[row]['MaxHealthDifference'][2])[0] == hp, (row, hp)
    for row, src, model, fly_ally, unarmed, key, full in se.ESCORT_DECOY_NPC_ROWS:
        r = npc[row]
        want_model = {se.ZFA_NPC: se.ZFA_MODEL_SV, se.ZFA_DRONE_NPC: se.ZFA_DRONE_MODEL_SV}.get(row, model)  # (its own: its name)
        assert model is None or plain(r['ModelId']) == want_model, (row, r['ModelId'])
        assert not fly_ally or plain(r['LuaSetId']) == 'NLID_0003_CP', (row, r['LuaSetId'])
        assert not unarmed or not any(k.startswith('NpcFCSId') and v for k, v in r.items()), row
        assert plain(r['LuaSetId']) != 'NLID_0400_CP', row
    # ((2026-11-07) "ZFA-44" on its box, never "SU-47": both host rows on SV_Model_Zfa, named ZFA_NAME_KEY there, and
    # ZFA_SUB_KEY under it)
    zm = table(DATA + 'DT_SV_ModelRows', 'LiveModelDataTable')
    assert se.ZFA_MODEL_SV in zm and zm[se.ZFA_MODEL_SV]['GameObjectDisplayName01'] == s(se.ZFA_NAME_KEY), zm.get(se.ZFA_MODEL_SV)
    for zr, zmod in ((se.ZFA_NPC, se.ZFA_MODEL_SV), (se.ZFA_TLS_NPC, se.ZFA_MODEL_SV), (se.ZFA_DRONE_NPC, se.ZFA_DRONE_MODEL_SV),
                     (se.ZFA_DRONE_TLS_NPC, se.ZFA_DRONE_MODEL_SV)):
        assert plain(npc[zr]['ModelId']) == zmod and npc[zr]['GameObjectDisplayName02'] == s(se.ZFA_SUB_KEY), \
            (zr, npc[zr].get('ModelId'), npc[zr].get('GameObjectDisplayName02'))
    # ((2026-11-07) the launched ZFA-44s on the allied container drone: its model row named ZFA-44, the Su-47's health)
    dm = zm.get(se.ZFA_DRONE_MODEL_SV) or {}
    assert dm.get('GameObjectDisplayName01') == s(se.ZFA_NAME_KEY) and struct.unpack('<f', dm['MaxHealth'][2])[0] == se.ZFA_DRONE_HEALTH \
        and dm['BlueprintClass'][2][1] == 'BP_OP0018_uavc_CP_Ally_C', dm
    print(f'  escort / decoy: {len(want)} units, {len(want_paths)} paths, {len(events)} events ({n_ex} execs: '
          + ', '.join(f'{c} {n}' for c, n in sorted(classes.items())) + ') and their rows read back from the packages: all there')


def check_zfa_laser_build():
    """(2026-11-07) The ZFA-44s' anti-missile laser read back from the packages this build saved: its arm
    BP_FCS_SV_ZfaTLS (named for its path; it imports exactly BP_SwingTLS_ForMSL's 7 public exports and its weapon class
    is that one; its launcher a LauncherCommon on the host's body at the gun socket, all round; its AIControlCIWS missiles
    only), its fire-control row in DT_SV_NpcFCS, DT_SV_NpcRows' laser twin of the ZFA-44 host (its gun's slot that row, the rest
    the host's), the interception trigger and its count, and the names Lua uses (Scripts/sv_config.lua's carrier.zfa)."""
    se = survival_events
    plain = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    load = lambda path: ZenPkg(data=open(os.path.join(OUT, path[len('/Game/'):]) + '.uasset', 'rb').read())
    u64 = lambda e, at: struct.unpack_from('<Q', e, at)[0]
    z = load(se.ZFA_TLS_FCS_PKG)
    tls, ecm = ZenPkg(stock(se.ZFA_TLS_WEAPON)), ZenPkg(stock(se.ZFA_TLS_LAUNCHER_SOURCE))
    tls_pub = sorted(u64(e, 56) for e in tls.exports if u64(e, 56))
    assert z.names[z.name_idx] == se.ZFA_TLS_FCS_PKG and z.imp_pkgs == [se.ZFA_TLS_WEAPON], (z.names[z.name_idx], z.imp_pkgs)
    got = sorted(z.imp_hashes[x & 0xffffffff] for x in z.imports if x >> 62 == 2)
    assert got == tls_pub and len(z.imp_hashes) == len(tls_pub), ('the laser imports', [hex(h) for h in got])
    wc = dict((q[1], q[3]) for q in props_of(z, z.export_index('LiveFCSModule_ProjectileCommon_0'), 'LiveFCSModule_ProjectileCommon')[0][2])
    w = z.imports[-wc['WeaponClass'][1] - 1]
    assert w >> 62 == 2 and z.imp_hashes[w & 0xffffffff] == export_hash(se.ZFA_TLS_WEAPON.rsplit('/', 1)[1] + '_C'), wc
    li = z.export_index('LiveFCSModule_LauncherBoneControl_0')
    el = ecm.export_index('LiveFCSModule_LauncherCommon_0')
    assert (u64(z.exports[li], 32), u64(z.exports[li], 48)) == (u64(ecm.exports[el], 32), u64(ecm.exports[el], 48)), 'launcher class'
    lc = dict((q[1], q[3]) for q in props_of(z, li, 'LiveFCSModule_LauncherCommon')[0][2] if not q[2])
    perf, fc = (dict((q[1], q) for q in lc[f][2]) for f in ('Performance', 'FireControl'))
    assert lc['MeshComponentName'] == ('name', ZFA_TLS_MESH, 0) and ('SlotSocketPrefix' not in perf or perf['SlotSocketPrefix'][2]), lc
    assert fc['LauncherDirection'][3][2] == ('raw', 'Byte', b'\x01'), fc['LauncherDirection']        # SlotSocket
    assert struct.unpack('<f', fc['CaptureAngleRange'][3][2])[0] == 180.0, fc['CaptureAngleRange']
    ai = dict((q[1], q[3]) for q in props_of(z, z.export_index('LiveFCSModule_AIControlCIWS_0'), 'LiveFCSModule_AIControlCIWS')[0][2])
    assert ai['bSearchMissileOnly'] == ('raw', 'Bool', b'\x01'), ai
    cls = z.export_name(0)

    def table(path, st):
        zt = load(path)
        dt, _ = dtx.parse(uprop.Ctx(bytes(zt.payloads[0]), zt.names), 0, st)
        return {plain(('name',) + k): dict((q[1], q[3]) for q in r[2]) for k, r in dt['rows']}
    fcs = table(se.ZFA_TLS_FCS_TABLE, 'LiveNpcFCSDataTable')
    assert list(fcs) == [se.ZFA_TLS_FCS_ROW], list(fcs)
    r = fcs[se.ZFA_TLS_FCS_ROW]
    assert r['FCSBlueprintClass'] == ('soft', ('name', se.ZFA_TLS_FCS_PKG, 0), ('name', cls, 0), ''), r['FCSBlueprintClass']
    assert r['NpcWeaponId'] is None and r['NpcAIModuleId'] is None, r
    assert [struct.unpack('<f', r[f][2])[0] for f in ('CaptureDistance', 'CaptureAngleRange')] == [3000.0, 180.0], r
    npc = table(DATA + 'DT_SV_NpcRows', 'LiveNpcDataTable')
    slot = f'NpcFCSId{se.ZFA_TLS_SLOT}'
    for host, twin in ((se.ZFA_NPC, se.ZFA_TLS_NPC), (se.ZFA_DRONE_NPC, se.ZFA_DRONE_TLS_NPC)):
        a, b = npc[host], npc[twin]
        assert b.get(slot) == ('name', se.ZFA_TLS_FCS_ROW, 0) and a.get(slot) == ('name', se.ZFA_TLS_GUN, 0), (host, a.get(slot), b.get(slot))
        assert {f: v for f, v in a.items() if f != slot} == {f: v for f, v in b.items() if f != slot}, (host, 'the twin differs')
    # the interception count
    ze = load(MI + 'EP_SurvivalMode_global')
    _, _, _, T, E, _ = ep_dump.load_bytes(ze)
    show = lambda v: ep_dump.show(v, ze)
    trig = [t for t in T if show(ep_dump.fields(t)['EventName']) == se.ZFA_TLS_EVENT]
    assert len(trig) == 1 and show(ep_dump.fields(trig[0])['EventType']) == '65', len(trig)
    vals = [show(ep_dump.fields(x)['Value']) for x in ep_dump.fields(trig[0])['ArgsInfo'][1]]
    assert vals == ['WID_tls', 'NoneSelect', 'NoneSelect', 'NoneSelect', 'true'], vals
    ex = [e for e in E if show(ep_dump.fields(e)['ConnectionEventName']) == se.ZFA_TLS_EVENT]
    assert [(show(ep_dump.fields(e)['ExecutionClass']), [show(ep_dump.fields(x)['Value']) for x in ep_dump.fields(e)['ArgsInfo'][1]])
            for e in ex] == [('LiveFlagOperation_IntExecution', [se.ZFA_TLS_FLAG, 'Add', '1'])], ex
    # Lua's names for them (Scripts/sv_config.lua CFG.allies.carrier.zfa)
    lua = survival_events.runtime_lua()
    for want in (f'dt_npc = "{se.ZFA_NPC}"', f'laser_row = "{se.ZFA_TLS_NPC}"', f'laser_fcs_row = "{se.ZFA_TLS_FCS_ROW}"',
                 f'dt_npc_drone = "{se.ZFA_DRONE_NPC}"', f'laser_row_drone = "{se.ZFA_DRONE_TLS_NPC}"',
                 f'model_drone = "{se.ZFA_DRONE_MODEL_SV}"',
                 f'laser_slot = {se.ZFA_TLS_SLOT},',
                 f'laser_fcs_table = "{se.ZFA_TLS_FCS_TABLE}.{se.ZFA_TLS_FCS_TABLE.rsplit("/", 1)[1]}"',
                 f'laser_flag = "{se.ZFA_TLS_FLAG}"'):
        assert want in lua, f'Scripts/sv_config.lua: no {want}'
    print(f'  zfa laser: {se.ZFA_TLS_FCS_PKG} (imports the 7 of {se.ZFA_TLS_WEAPON.rsplit("/", 1)[1]}, LauncherCommon on '
          f'{ZFA_TLS_MESH}, missiles only), {se.ZFA_TLS_FCS_ROW}, {se.ZFA_TLS_NPC} slot {se.ZFA_TLS_SLOT} and '
          f'{se.ZFA_TLS_EVENT} -> {se.ZFA_TLS_FLAG} read back from the packages: all there')


# ---------------------------------------------------------------- NPC mission table
# The spawner caches the aircraft of every row of the world data's NPC table once, when the level starts, and a
# spawn only looks there (tools/re/EVENTS_AIRCRAFT.md): a row added at run time never spawns. So Survival's world
# data points at its own copy of Mission 22's table, with Survival's rows added here. A row's NpcId (a DT_NPC row)
# may be one that main.lua adds to DT_NPC at run time, as long as that happens before the level loads.
NPC_TABLE_STOCK = '/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission022'
NPC_TABLE = MOD + '/Data/DT_SV_NpcMission'
NPC_ROWS = set()           # its row names, filled by build_npc_table
NPC_SOURCE = {}            # (0.73.77) each Survival row whose DT_NPC row Lua makes -> the mission row it was copied from
# Rows copied whole from other missions' NPC tables (names and values only, no object references): the heavy bombers
# of Mission 4 (Milestone 3). Their blueprints are loaded by the spawner from the NpcId's DT_NPC row.
NPC_IMPORT = [('/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission004', ['t160_common', 'tu95_common']),
              # the amphibious assault's landing craft and troops (survival_events.LCAC_*), Mission 13's
              ('/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission013', ['lcac_common', 'btr9_common']),
              # the Ladons' own rows (survival_events.LADON*: LADON_SOURCE_ROW's copies; its parts name no mission row:
              # they come with its DT_NPC row's ChildNPCId)
              ('/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission016', []),
              # the Alicorn's own mission row (its parts name none): Online Mode's EB_002
              ('/Game/OnlineMode/DataTables/AI/NPC/Mission/DT_NPC_Mission_EB_002_ON', ['alcn_01']),
              # the Spaceport Retake's rockets and their debris (survival_events.SP_ROCKET_ROWS: (Survival's name,
              # Mission 19's), Mission 19's names end in a numeric tail: copied under Survival's)
              ('/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission019', survival_events.SP_ROCKET_ROWS)] + list(
              survival_events.SP_ISLAND_ROWS.items()) + [   # (the retake's island enemies: Mission 6's and 7's rows)
              # THE FESTIVAL's cruise missile (survival_events.FEST_CM_*): Mission 30's path-flown SLCM, under Survival's name
              ('/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission030', [(survival_events.FEST_CM_ROW, survival_events.FEST_CM_SOURCE_ROW)]),
              # its searchlights (survival_events.FEST_LIGHT_*): Online Mode C_011's vehicle and its light, under Survival's
              # names (their DT_NPC_ON rows ride in the Alicorn's tables: build_alicorn_rows)
              ('/Game/OnlineMode/DataTables/AI/NPC/Mission/DT_NPC_Mission_C_011_ON', survival_events.FEST_LIGHT_ROWS)]
LADON_TABLE_NOTE = 'DT_NPC_Mission016'
NPC_EXTRA = [   # (new row, copy of Mission 22's row, NpcId)  - names without a numeric tail (hard rule 17)
    ('sv_probe_pkg', 'm29a_common', 'SV_m29a_ProbePkg'),   # behaviour probe (main.lua): packaged script
    ('sv_probe_rt',  'm29a_common', 'SV_m29a_ProbeRt'),    # behaviour probe: run-time LuaScript
    (survival_events.SHUTTLE_NPC_ROW, 'sstb_common', survival_events.SHUTTLE_NPC),   # Comona Defense's shuttle (its name)
    (survival_events.VALKA_EML_ROW, 'gepa_common', survival_events.VALKA_EML_NPC),   # VALKA's opener railgun (a turret row)
    (survival_events.FISH_ROW, survival_events.FISH_ROW_TEMPLATE, survival_events.FISH_NPC),   # GONE FISHIN's shoals
] + [  # the fighter roles' behaviour rows (survival_events.ROLE_ROW, P1): DT_NPC rows Scripts/sv_rows.lua rolesSetup makes
    (row, 'f16c_common', npc) for row, npc in survival_events.ROLE_NPC.items()]
# Enemy search (main.lua CFG.search): for each of these rows a copy <row>_sv whose NpcId is <its NpcId>_SV, the DT_NPC
# copy main.lua adds at run time with Survival's 25 km AI module. Keep in step with main.lua CFG.aircraft.
SEARCH_AIRCRAFT = ['f16c_common', 'f18e_common', 'f15e_common', 'f14d_common', 'm21b_common',
                   'm29a_common', 'su47_common', 'su33_common', 'su34_common',
                   # the economy review's (2026-10-25): main.lua CFG.variety.late and CFG.jammer.aircraft
                   'f02a_common', 'f15c_common', 'f35c_common', 'su35_common', 'rflm_common', 'typn_common',
                   'su57_common', 'f22a_common', 'e18g_common', 'j39e_common']
# Pool aircraft Mission 22's table hasn't got: (new mission row, Mission 22 row it's shaped like, DT_NPC row). The Su-47
# (user, 2026-10-23: "add SU-47's in instead of the MiG-31's"): the campaign's plain enemy Su-47. The rest (economy
# review of 2026-10-25: "use the whole aircraft pool"): the campaign's plain enemy rows of the named aces' airframes and
# a few more, joining the pool round by round (main.lua CFG.variety), and the jammer's EA-18G (CFG.jammer).
POOL_EXTRA = [('su47_common', 'su33_common', 'OP1026_su47_01'),
              ('f02a_common', 'f16c_common', 'OP1002_f02a_01'),
              ('f15c_common', 'f15e_common', 'OP1004_f15c_01'),
              ('f35c_common', 'f18e_common', 'OP1006_f35c_01'),
              ('su35_common', 'su33_common', 'OP1028_su35_01'),
              ('rflm_common', 'f18e_common', 'OP1014_rflm_01'),
              ('typn_common', 'f18e_common', 'OP1011_typn_01'),
              ('su57_common', 'su33_common', 'OP1021_su57_01'),
              ('f22a_common', 'f15e_common', 'OP1005_f22a_01'),
              ('e18g_common', 'f18e_common', 'OP1010_e18g_01'),
              # the co-op stand-ins of the player planes the list above hadn't got (Scripts/sv_config.lua
              # CFG.coop.airframes; the user, 2026-10-30: "someone who was flying the FA-36 was registering as flying the
              # F-16"): each one's plain campaign enemy row (build/research/ai/dt_npc.tsv), not in the enemy pool
              ('fa36_common', 'f18e_common', 'OP1018_fa36_01'),
              ('ea36_common', 'f18e_common', 'OP1019_ea36_01'),
              ('f04e_common', 'f16c_common', 'OP1003_f04e_01'),
              ('f18c_common', 'f18e_common', 'OP1007_f18c_01'),
              ('f15j_common', 'f15e_common', 'OP1012_f15j_01'),
              ('a06e_common', 'f18e_common', 'OP1013_a06e_01'),
              ('su25_common', 'su34_common', 'OP1015_su25_01'),
              ('x40a_common', 'f15e_common', 'OP1016_x40a_01'),
              ('mr2k_common', 'f16c_common', 'OP1017_mr2k_01'),
              ('e06b_common', 'f18e_common', 'OP1031_e06b_01')]
# Survival COOP's stand-ins (Scripts/sv_coop.lua, the weapon sync; tools/re/COOP.md 8): each other player's plane flies
# <row>_svcp for its airframe's row (Scripts/sv_config.lua CFG.coop.airframes and default, read from the Lua), whose
# NpcId <its NpcId>_SVCP is the DT_NPC copy sv_coop.lua COOP.syncSetup makes at the main menu with every weapon on
# damage-0 rows, so what a stand-in fires on another game only shows (user, 2026-10-29: "work out aircraft syncing,
# such as missiles being fired"). Letters at the end: hard rule 17.
COOP_STANDIN_SUFFIX = ('_svcp', '_SVCP')


def coop_standin_rows():
    """The mission rows a co-op stand-in flies: CFG.coop.airframes' values and its default, from the Lua."""
    lua = survival_events.runtime_lua()
    m = re.search(r'\n    coop = \{.*?airframes = \{([^}]*)\},\s*default = "(\w+)"', lua, re.S)
    assert m, 'Scripts/sv_config.lua: no CFG.coop.airframes / default'
    rows = sorted(set(re.findall(r'=\s*"(\w+)"', m.group(1))) | {m.group(2)})
    assert rows and all(not r[-1:].isdigit() for r in rows), rows
    return rows


# Difficulty spikes (main.lua CFG.spikes; user, 2026-10-22: "every 7 rounds ... a difficulty spike across the board"):
# each level after the first gets its own rows, <row>_sv<letter> -> <NpcId>_SV<LETTER>, whose DT_NPC copies main.lua
# gives that level's fire control. Letters, not digits: hard rule 17. Keep in step with main.lua SPIKE_SUFFIX.
SPIKE_SUFFIXES = ['b', 'c', 'd']

# (0.73.77, plan G1) No scripted sure kills on enemies. A stock mission's "hit missile" fire controls (BP_FCS_HitMSL_*,
# which launch BP_MSL_certain_kill_*: homing 180 deg, turning without limit, flares do nothing; hard rule 36) are meant
# for its events alone (CaptureDistance 0: their AI never picks them), but Scripts/sv_rows.lua copies every
# NPC_FCS_PlaneMsl* slot onto Survival's missile fire control with a capture distance, so their AI fired them: Mission
# 22's F/A-18E row (OP1032_f18e_Ally_MS22) carries NPC_FCS_PlaneMsl300 (Missile_300, 9999 damage) in slot 5, which
# one-shot cressendo twice in round 6 (150 HP each) and liljojofett in round 41 of the 0.73.76 runs; the Phantom Su-47s
# carry NPC_FCS_PlaneMsl302 (the same) and the Reaper F-22 wings NPC_FCS_PlaneMsl100. Mission 22's Su-33 row
# (OP1030_su33_02) carries Mission 13's scripted anti-ship pair (1200 damage, unlimited turn). The stock mission rows
# that name such a row are pointed at the airframe's plain campaign enemy row instead (the one every other mission's
# <airframe>_common names: Flr / Gun / Msl only), and the aces' copies (build_npc_rows) have those slots emptied;
# check_no_certain_kill fails the build on any enemy row that still carries one.
PLAIN_NPC_IDS = {'f18e_common': ('OP1032_f18e_Ally_MS22', 'OP1032_f18e_01'),   # mission row: (stock NpcId, plain)
                 'su33_common': ('OP1030_su33_02', 'OP1030_su33_01')}
CERTAIN_KILL_DAMAGE = 1000.0       # a weapon this strong takes a whole health bar (a player's is 100-300 HP)
CERTAIN_KILL_TURN = 10000.0        # MaxRotationAngle of the scripted kills: a missile that turns without limit
_FCS_TABLES = {}


def npc_fcs_tables():
    """(fire control rows, weapon rows): the campaign's DT_NPC_FCS / DT_NPC_Weapon and Online Mode's _ON tables, each
    plain row name -> {property: value} (a campaign row first)."""
    if not _FCS_TABLES:
        def load(path, st):
            z = ZenPkg(stock(path))
            dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
            return {(k[0] if k[1] == 0 else f'{k[0]}_{k[1] - 1}'): dict((q[1], q[3]) for q in r[2]) for k, r in dt['rows']}
        for key, st, paths in (('fcs', 'LiveNpcFCSDataTable', ['/Game/Datatables/AI/NPC/FCS/DT_NPC_FCS',
                                                                 ON_NPC + 'DT_NPC_FCS_ON']),
                               ('wpn', 'LiveNpcWeaponDataTable', ['/Game/Datatables/AI/NPC/Weapon/DT_NPC_Weapon',
                                                                   ON_NPC + 'DT_NPC_Weapon_ON'])):
            t = {}
            for path in paths:
                for k, v in load(path, st).items(): t.setdefault(k, v)
            _FCS_TABLES[key] = t
    return _FCS_TABLES['fcs'], _FCS_TABLES['wpn']


def certain_kill(fcs_row):
    """Why fire control `fcs_row` is a scripted sure kill, or None: a hit missile's blueprint (BP_FCS_HitMSL_*) or one
    named certain, or a weapon of CERTAIN_KILL_DAMAGE or more, or one turning CERTAIN_KILL_TURN deg (no flare shakes it)."""
    fcs, wpn = npc_fcs_tables()
    r = fcs.get(fcs_row)
    if r is None: return None
    bp = r.get('FCSBlueprintClass')
    cls = bp[2][1] if bp and bp[0] == 'soft' and bp[2] and bp[2][0] == 'name' else ''
    w = r.get('NpcWeaponId')
    wname = (w[1] if w[2] == 0 else f'{w[1]}_{w[2] - 1}') if w and w[0] == 'name' else None
    wr = wpn.get(wname, {}) if wname else {}
    f = lambda v: struct.unpack('<f', v[2])[0] if v and v[0] == 'raw' and v[1] == 'Float' else 0.0
    dmg, turn = f(wr.get('damage')), f(wr.get('MaxRotationAngle'))
    if 'hitmsl' in cls.lower() or 'certain' in cls.lower() or dmg >= CERTAIN_KILL_DAMAGE or turn >= CERTAIN_KILL_TURN:
        return f'{fcs_row} ({cls or "?"}, weapon {wname}: {dmg:.0f} damage, turns {turn:.0f} deg)'
    return None


def build_npc_table():
    z = ZenPkg(stock(NPC_TABLE_STOCK))
    rename_package(z, NPC_TABLE_STOCK, NPC_TABLE)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveNpcMissionDataTable')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    npc_idx = [k for k, (n, t) in uprop.U.schema('LiveNpcMissionDataTable').items() if n == 'NpcId'][0]
    # (0.73.77, G1) the stock rows that named a sure kill: on their airframe's plain enemy row (PLAIN_NPC_IDS), before
    # anything below copies them or names their <NpcId>_SV clones
    for mrow, (was, plain) in PLAIN_NPC_IDS.items():
        have = [q for q in rows[(mrow, 0)][2] if q[0] == npc_idx][0][3]
        assert (have[1] if have[2] == 0 else f'{have[1]}_{have[2] - 1}') == was, f'{mrow}: NpcId {have}, {was} expected'
        nid = survival_events.fname(plain)
        set_prop(rows[(mrow, 0)][2], npc_idx, 'NpcId', nid)
        z.nb.add(nid[1])
        print(f'  {mrow}: {was} -> {plain} (no scripted sure kill: G1)')
    NPC_SOURCE.clear()
    extra = list(NPC_EXTRA)
    # (the Spaceport Assault's enemy ships, survival_events.SP_NPC_ROWS: shaped as an Aegis hull or turret row; SAL's boat,
    # survival_events.FISH_NPC_ROWS, the same way: the stock boat row's name ends in digits)
    for new_row, src, npc in POOL_EXTRA + survival_events.SP_NPC_ROWS + survival_events.FISH_NPC_ROWS:
        assert (new_row, 0) not in rows, new_row
        row = copy.deepcopy(rows[(src, 0)])
        nid = survival_events.fname(npc)                                    # (its numeric tail: hard rule 17)
        set_prop(row[2], npc_idx, 'NpcId', nid)
        for n in (new_row, nid[1]): z.nb.add(n)
        rows[(new_row, 0)] = row
        dt['rows'].append(((new_row, 0), row))
    # SAL's boat afloat: MinHealth 1 on its mission row, as the stock allied ships carry it (Mission 24's wasp_Ally)
    mh_idx = [k for k, (n, t) in uprop.U.schema('LiveNpcMissionDataTable').items() if n == 'MinHealth'][0]
    set_prop(rows[(survival_events.SAL_BOAT_ROW, 0)][2], mh_idx, 'MinHealth',
             ('raw', 'Float', struct.pack('<f', survival_events.SAL_BOAT_MIN_HEALTH)))
    for src in SEARCH_AIRCRAFT:
        npc = [p for p in rows[(src, 0)][2] if p[0] == npc_idx][0][3]          # ('name', base, number)
        base = npc[1] if npc[2] == 0 else f'{npc[1]}_{npc[2] - 1}'
        extra.append((src + '_sv', src, base + '_SV'))
        for suf in SPIKE_SUFFIXES:
            extra.append((src + '_sv' + suf, src, base + '_SV' + suf.upper()))
    # the co-op stand-ins' damage-0 rows (COOP_STANDIN_SUFFIX): <row>_svcp -> <its NpcId>_SVCP, made by Lua
    standins = coop_standin_rows()
    missing = [r for r in standins if (r, 0) not in rows]
    assert not missing, f'CFG.coop.airframes names rows DT_SV_NpcMission lacks: {missing}'
    for src in standins:
        npc = [p for p in rows[(src, 0)][2] if p[0] == npc_idx][0][3]
        base = npc[1] if npc[2] == 0 else f'{npc[1]}_{npc[2] - 1}'
        extra.append((src + COOP_STANDIN_SUFFIX[0], src, base + COOP_STANDIN_SUFFIX[1]))
    print(f'  co-op stand-ins: {len(standins)} damage-0 rows ({", ".join(r + COOP_STANDIN_SUFFIX[0] for r in standins)})')
    # the aces (ACES): <row> -> its DT_SV_NpcRows row, and like the search aircraft <row>_sv[b|c|d] -> <that>_SV[B|C|D]
    for tier, key, _, _ in ACES:
        for row, npc, _ in ace_rows(tier, key):
            extra.append((row, 'f16c_common', npc))
            for suf in [''] + SPIKE_SUFFIXES:
                extra.append((row + '_sv' + suf, 'f16c_common', npc + '_SV' + suf.upper()))
    # the STORE's allies (survival_events.ALLY_*): MOONCHILD on Mission 22's allied F/A-18 row, each ship's hull and
    # turrets on copies of Mission 22's rows, all pointing at DT_SV_NpcRows copies (their names, their fire control)
    extra.append((survival_events.ALLY_AIR_ROW, 'f18e_common', survival_events.ALLY_AIR_NPC))
    extra.append((survival_events.ALLY_WINGMEN_ROW, 'f18e_common', survival_events.ALLY_WINGMEN_NPC))
    extra.append((survival_events.AWACS_ROW, survival_events.AWACS_ROW_TEMPLATE, survival_events.AWACS_NPC))
    for src, (row, npc) in survival_events.DEFENCE_ROWS.items():           # the airfield's AA guns and SAM sites
        extra.append((row, src, npc))
    extra.append((survival_events.DEFENCE_CIWS_ROW[0], survival_events.DEFENCE_CIWS_MISSION_SOURCE,   # and the CIWS
                  survival_events.DEFENCE_CIWS_ROW[1]))
    for _, mrow, npc, _ in survival_events.SP_TURRETS:        # the Spaceport fleet's turrets (their own fire control)
        extra.append((mrow, survival_events.SP_TURRET_SHAPE, npc))
    for mrow, npc, _ in survival_events.SP_HULLS:              # and its armed hulls (their ChildNPCId: the turrets')
        extra.append((mrow, 'aegs_common', npc))
    for key, _, hull, _ in survival_events.ALLY_SHIPS:
        row, npc, _ = survival_events.ally_ship_rows(key)
        extra.append((row, hull, npc))
        for t in survival_events.ALLY_TURRETS[key]:
            extra.append(survival_events.ally_turret_rows(t)[:1] + (t,) + survival_events.ally_turret_rows(t)[1:])
    for new_row, src, npc in extra:
        assert not any(c.isdigit() for c in new_row[-1:] + npc[-1:]), new_row
        row = copy.deepcopy(rows[(src, 0)])
        set_prop(row[2], npc_idx, 'NpcId', ('name', npc, 0))
        for n in (new_row, npc): z.nb.add(n)
        dt['rows'].append(((new_row, 0), row))
        NPC_SOURCE[new_row] = src                                       # (check_no_certain_kill: a Lua-made row's)
    for table, wanted in NPC_IMPORT:
        zs = ZenPkg(stock(table))
        ds, os_ = dtx.parse(uprop.Ctx(bytes(zs.payloads[0]), zs.names), 0, 'LiveNpcMissionDataTable')
        assert os_ == len(zs.payloads[0])
        srows = dict(ds['rows'])
        if table.endswith('DT_NPC_Mission016'):          # the Ladons' own rows: Mission 16's, on Survival's NPC rows
            for L in survival_events.ladons():
                row = copy.deepcopy(srows[(survival_events.LADON_SOURCE_ROW, 0)])
                set_prop(row[2], npc_idx, 'NpcId', ('name', L['npc'], 0))
                for n in names_in(row) + [L['row'], L['npc']]: z.nb.add(n)
                dt['rows'].append(((L['row'], 0), row))
                extra.append((L['row'], LADON_TABLE_NOTE, L['npc']))
        for r in wanted:
            r, src = r if isinstance(r, tuple) else (r, r)          # (a row copied under a name of Survival's)
            assert (r, 0) not in rows and survival_events.fname(r)[2] == 0, r   # (a name the engine keeps whole)
            f = survival_events.fname(src)
            row = copy.deepcopy(srows[(f[1], f[2])])
            assert not any(p[3] and p[3][0] == 'obj' for p in row[2]), r              # names and values only
            for n in names_in(row) + [r]: z.nb.add(n)
            dt['rows'].append(((r, 0), row))
            extra.append((r, table.rsplit('/', 1)[1], None))
    # THE ESCORT and THE DECOY (survival_events.ESCORT_DECOY_MISSION_ROWS): Mission 22's rows' shape or another mission's
    # row whole (names and values only), under Survival's names (no digit split: hard rule 17), NpcId and health set
    md_idx = [k for k, (n, t) in uprop.U.schema('LiveNpcMissionDataTable').items() if n == 'MaxHealthDifference'][0]
    other = {}
    for new_row, table, src, npc, hp in survival_events.ESCORT_DECOY_MISSION_ROWS:
        assert (new_row, 0) not in rows and survival_events.fname(new_row)[2] == 0, new_row
        if table is None:
            row = copy.deepcopy(rows[(src, 0)])
        else:
            if table not in other:
                zs = ZenPkg(stock(table))
                other[table] = dict(dtx.parse(uprop.Ctx(bytes(zs.payloads[0]), zs.names), 0, 'LiveNpcMissionDataTable')[0]['rows'])
            f = survival_events.fname(src)
            row = copy.deepcopy(other[table][(f[1], f[2])])
            assert not any(p[3] and p[3][0] == 'obj' for p in row[2]), new_row              # names and values only
        if npc:
            nid = survival_events.fname(npc)
            set_prop(row[2], npc_idx, 'NpcId', nid)
            z.nb.add(nid[1])
        if hp is not None:
            set_prop(row[2], md_idx, 'MaxHealthDifference', ('raw', 'Float', struct.pack('<f', hp)))
        for n in names_in(row) + [new_row]: z.nb.add(n)
        rows[(new_row, 0)] = row
        dt['rows'].append(((new_row, 0), row))
        extra.append((new_row, (table or NPC_TABLE_STOCK).rsplit('/', 1)[1], npc))
    print('  escort / decoy rows: ' + ', '.join(f'{r} ({(t or NPC_TABLE_STOCK).rsplit("_", 1)[-1]} {s_} -> {n or s_}'
                                                + (f', +{h:.0f} HP' if h else '') + ')'
                                                for r, t, s_, n, h in survival_events.ESCORT_DECOY_MISSION_ROWS))
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveNpcMissionDataTable')
    assert chk['rows'] == dt['rows']
    NPC_ROWS.update(k[0] for k, _ in dt['rows'])          # build_wd_global checks the flights' behaviour rows
    print(f'  {len(dt["rows"])} rows ({len(extra)} Survival rows)')
    save(z, NPC_TABLE)


# ---------------------------------------------------------------- AI behaviour scripts
# Survival's own enemy behaviour trees (LuaScript assets: Code / ImportPath / LuaInitializePath, see
# tools/re/AI_BEHAVIOURS.md). Source in mod/UE4SS/AC8SurvivalMode/Scripts/ai/<name>.lua (the Lua runtime reads the
# same file); the package is a copy of a stock LA_ script package with our source and our own module name.
AI_SRC = os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'ai')
LUA_TEMPLATE = '/Game/LuaSource/Chronicle/AI/LA_PursueTarget_0011'
LUA_SCRIPTS = ['LA_SV_ProbePursue', 'LA_SV_MoveAway', 'LA_SV_TailChase', 'LA_SV_ProvokeNear', 'LA_SV_Escape',
               # the fighter roles' (behaviour roadmap P1, Scripts/sv_config.lua CFG.behaviour_sets): Lancer, Wolf, Skirmisher
               'LA_SV_LancerPass', 'LA_SV_LancerZoom', 'LA_SV_LancerBreak', 'LA_SV_WolfDrag', 'LA_SV_WolfStrike',
               'LA_SV_SkirmPass', 'LA_SV_SkirmExtend']


# The game's Lua require() (AceCombat8.exe 0x144eb8c00) loads module "A.B.C" with StaticLoadObject from
# /Game/LuaSource/A/B/C and runs that LuaScript's Code, so a behaviour script must live at the path its
# LuaInitializePath names: /Game/LuaSource/SurvivalMode/AI/<name> (a folder only Survival uses). Test 17: at
# /Game/Mods/SurvivalMode/AI it was never found and the probe MiGs flew stock.
LUA_DIR = '/Game/LuaSource/SurvivalMode/AI/'


def build_lua_scripts():
    # every script a behaviour set names (Scripts/sv_config.lua CFG.behaviour_sets) is packed: a set naming one that isn't
    # is never made (setsSetup: "not made (script X not in the container)") and its flights fly the fallback set
    import re
    lua = survival_events.runtime_lua()
    sets = lua[lua.index('behaviour_sets = {'):lua.index('-- reactions (user, 2026-10-22')]
    named = set(re.findall(r'"(LA_SV_\w+)"', sets))
    assert named and named <= set(LUA_SCRIPTS), f'behaviour sets name scripts not packed: {sorted(named - set(LUA_SCRIPTS))}'
    for name in LUA_SCRIPTS:
        code = open(os.path.join(AI_SRC, name + '.lua'), encoding='utf-8').read().replace('\r\n', '\n').replace('\n', '\r\n')
        new_path = LUA_DIR + name
        z = ZenPkg(stock(LUA_TEMPLATE))
        rename_package(z, LUA_TEMPLATE, new_path)
        props, rest = props_of(z, 0, 'LuaScript')
        vals = props[2]                                          # LuaScript: 0 Code, 1 ImportPath, 2 LuaInitializePath
        set_prop(vals, 0, 'Code', s(code))
        set_prop(vals, 1, 'ImportPath', s('../../AssetWork/LuaSource/SurvivalMode/AI/' + name + '.lua'))
        set_prop(vals, 2, 'LuaInitializePath', s('SurvivalMode.AI.' + name))
        z.payloads[0] = bytearray(write_props(z, props) + rest)
        chk, _ = props_of(z, 0, 'LuaScript')
        assert dict((p[1], p[3]) for p in chk[2])['LuaInitializePath'] == s('SurvivalMode.AI.' + name)
        save(z, new_path)


# ---------------------------------------------------------------- the parts (this file's docstring)
# Each imports every name above (from build_survival import *) and comes back here whole. A part already loaded on its
# own would come back empty: import build_survival, never a part.
for _part in ('build_survival_rows', 'build_survival_units', 'build_survival_world'):
    assert _part not in sys.modules, f'import build_survival (it loads its parts), not {_part} on its own'
del _part
from build_survival_rows import *    # noqa: E402,F401,F403  the radio table, the mission / menu rows, the model rows
from build_survival_units import *   # noqa: E402,F401,F403  the level, MC, phases; unit / path helpers; older specials
from build_survival_world import *   # noqa: E402,F401,F403  the newer rounds' units; the world data, flags and events


if __name__ == '__main__':
    build_radio()
    build_alicorn_rows()
    build_lua_scripts()
    build_npc_table()
    build_shop_rows()
    build_rows()
    build_zfa_laser()                    # (2026-11-07: the ZFA-44s' anti-missile laser's arm and its fire-control row)
    check_no_certain_kill()              # (0.73.77, G1: after the NPC tables it reads are saved)
    try:
        build_menu_pages()
    except Exception:                    # (the rest of the build still comes: the main menu keeps the flat rows)
        import traceback
        traceback.print_exc()
        print('  menu pages: FAILED (above); no pages this build, the main menu keeps the flat rows')
        drop_menu_pages()
    build_pl()
    build_mc()
    build_wd_global(); build_wd_phase(1); build_wd_phase(2)
    build_ef()
    build_ep('global', ef=True)
    build_ep('phase01')
    build_ep('phase02')
    check_fishing_build()                # (2026-11-06: GONE FISHIN' and THE FESTIVAL read back from the saved packages)
    check_escort_decoy_build()           # (2026-11-06: THE ESCORT, its cargo ships and THE DECOY read back the same way)
    check_zfa_laser_build()              # (2026-11-07: the ZFA-44s' laser: its arm, rows and interception count)
    print('player start', tuple(round(x) for x in START), 'yaw', RUNWAY_YAW)
