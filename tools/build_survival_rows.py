"""build_survival_rows.py : Survival's radio table and its small row tables.

The radio table (DT_SV_Radio: build_radio, RADIO_*), the generic row helpers (names_in, setv, s), the mission /
menu / co-op / settings rows' edits (edit_*_row, SETTING_ROWS, check_hangar), the model rows (build_model_rows,
mission_npc_ids) and build_rows (DT_SV_MissionRows, DT_SV_NpcRows via build_survival.build_npc_rows, the
model rows, DT_SV_MenuRows).

A part of tools/build_survival.py (its docstring has the layout): every name build_survival defines is here
through the import below, and build_survival imports this part back whole, so each name here is
build_survival.<name> too. Import build_survival (or run it), not this file.
"""
from build_survival import *  # noqa: F401,F403 (build_survival's names; it imports this part at its end)


# Radio (docs/re/MUSIC_RADIO_CAMERA.md C): the level's radio table (ChronicleWorldSettings.RadioSettings, a hard
# import) is Survival's copy of Mission 22's, with only these changes (the voices are in the global AKB_Voice bank, the
# speakers in the global DT_SpeakerTable):
RADIO_STOCK = '/Game/Datatables/Radio/DT_Rdo_ST_ms022'
RADIO = DATA + 'DT_SV_Radio'
# MOONCHILD's takeoff (01_Wave1_Ally_Take_Off): Mission 25 part 2's Savian mercenary leader, "Our economy relies on mercs
# like us." (v2501_0054), in place of "This is Singleton Flight. Providing support." (user, 2026-10-23)
RADIO_REPLACE = {('01_Wave1_Ally_Take_Off', 'v2216_0007'): ('v2501_0054', 'ms25_Savia_Mercenary_Leader')}
# The shuttle round keeps Nagase's lines and drops the Professor's (Baxter) and Tasha's (user, 2026-10-23); groups left
# empty aren't played (survival_events.SHUTTLE_RADIO)
RADIO_DROP_SPEAKERS = ('LIVE_Baxter', 'LIVE_Tasha')
RADIO_DROP_IN = ('01_Countdown_intermission_1st', '01_Countdown_mainEngine', '01_All_Wave_Hit_Shuttle_First')
# and MOONCHILD's takeoff is the mercenary's line alone (user, 2026-10-23): Singleton's "We're joining the fight in
# aircraft we took back from Sotoa." and Tasha's "Okay!" go
RADIO_DROP_LINES = {('01_Wave1_Ally_Take_Off', 'v2216_0002'), ('01_Wave1_Ally_Take_Off', 'v0003_1682')}
# the voice bank every line's <TextID>_Play event is in (build_radio checks the tells' lines against it)
VOICE_DB = '/Game/WwiseAssets/Database/DA_SoundDB_AKB_Voice'
# Speakers aren't the level's to change: the game reads them from the game instance's own DT_SpeakerTable (a copy for
# the level, 2026-10-23, changed nothing), so Scripts/main.lua switches the Savian mercenary leader to ally colours at
# run time (CFG.allies.ally_speakers).


def build_radio():
    z = ZenPkg(stock(RADIO_STOCK))
    rename_package(z, RADIO_STOCK, RADIO)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveRadioTable')
    assert o == len(p), (o, len(p))
    def field(row, n): return [q for q in row[2] if q[1] == n][0][3]
    def full(v): return v[1] if v[0] != 'name' or v[2] == 0 else f'{v[1]}_{v[2] - 1}'   # 'v0003_1682' is ('v0003', 1683)
    def setf(row, n, v): row[2][:] = [(q[0], q[1], q[2], v) if q[1] == n else q for q in row[2]]
    keep, done, dropped = [], set(), 0
    for k, row in dt['rows']:
        group, text, speaker = full(field(row, 'RadioGroupID')), full(field(row, 'TextID')), field(row, 'SpeakerID')[1]
        if (group in RADIO_DROP_IN and speaker in RADIO_DROP_SPEAKERS) or (group, text) in RADIO_DROP_LINES:
            dropped += 1
            continue
        new = RADIO_REPLACE.get((group, text))
        if new:
            setf(row, 'TextID', survival_events.fname(new[0]))
            setf(row, 'SpeakerID', ('str', new[1]))
            z.nb.add(new[0]); z.nb.add(new[1])
            done.add((group, text))
        keep.append((k, row))
    assert done == set(RADIO_REPLACE), done
    assert dropped == 7, dropped        # Baxter x3 + Tasha x1 in the countdown, Baxter on the first hit, 2 at takeoff
    # the tells' lines (behaviour roadmap P3, survival_events.TELL_LINES): one row each, a group of its own, cloned from
    # row 382 (01_Wave4_Reinforcements_Attacker: one AWACS line, Scenario on the Main channel, priority 20, shown in the
    # com window, every mission flag on) with only its group, line and speaker changed, as RADIO_REPLACE's confirmed
    # route; LimitPlayCount 0 (the play-by-play rows' "any number of times"), 'now' lines sooner and interrupting
    tpl = dict(keep)[('382', 0)]
    assert (full(field(tpl, 'TextID')), field(tpl, 'SpeakerID')[1]) == ('v0001_2857', 'LIVE_AWACS'), 'row 382 moved'
    have = {full(field(row, 'RadioGroupID')) for _, row in keep}
    voice = set(ZenPkg(stock(VOICE_DB)).names)
    tells = 0
    for grp, tid, spk, opts in survival_events.TELL_LINES:
        assert grp not in have, f'{grp}: a group Mission 22 has, or twice'
        assert tid + '_Play' in voice, f'{tid}: no voice in {VOICE_DB}'
        row = copy.deepcopy(tpl)
        setf(row, 'RadioGroupID', survival_events.fname(grp))
        setf(row, 'TextID', survival_events.fname(tid))
        setf(row, 'SpeakerID', ('str', spk))
        setf(row, 'LimitPlayCount', ('raw', 'Int8', b'\x00'))
        if opts.get('now'):
            setf(row, 'StartDelay', ('raw', 'Float', struct.pack('<f', survival_events.TELL_START_DELAY_S)))
            setf(row, 'Channel', ('enum', 'ELiveRadioChannel', ('raw', 'Byte', bytes([survival_events.TELL_CHANNEL_INTERRUPT]))))
        for n in (survival_events.fname(grp)[1], survival_events.fname(tid)[1], spk): z.nb.add(n)
        keep.append(((grp, 0), row))
        have.add(grp)
        tells += 1
    # THE DECOY's lines (survival_events.DECOY_RADIO): the tells' way, each a group of its own
    for grp, ev, tid, spk, opts in survival_events.decoy_radio():
        assert grp not in have, f'{grp}: a group Mission 22 has, or twice'
        assert tid + '_Play' in voice, f'{tid}: no voice in {VOICE_DB}'
        row = copy.deepcopy(tpl)
        setf(row, 'RadioGroupID', survival_events.fname(grp))
        setf(row, 'TextID', survival_events.fname(tid))
        setf(row, 'SpeakerID', ('str', spk))
        setf(row, 'LimitPlayCount', ('raw', 'Int8', b'\x00'))
        if opts.get('now'):
            setf(row, 'StartDelay', ('raw', 'Float', struct.pack('<f', survival_events.TELL_START_DELAY_S)))
            setf(row, 'Channel', ('enum', 'ELiveRadioChannel', ('raw', 'Byte', bytes([survival_events.TELL_CHANNEL_INTERRUPT]))))
        for n in (survival_events.fname(grp)[1], survival_events.fname(tid)[1], spk): z.nb.add(n)
        keep.append(((grp, 0), row))
        have.add(grp)
        tells += 1
    dt['rows'] = keep
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveRadioTable')
    assert chk['rows'] == dt['rows']
    save(z, RADIO)
    print(f'  radio: {len(keep)} rows ({dropped} dropped, {len(done)} replaced, {tells} tell and decoy lines)')


def names_in(v):
    """Every FName string a property value uses."""
    out = []
    if isinstance(v, tuple):
        if v and v[0] == 'name': out.append(v[1])
        for x in v: out += names_in(x)
    elif isinstance(v, list):
        for x in v: out += names_in(x)
    return out


def setv(props, name, value):
    """Set (or add) a property of a row by name."""
    sc = uprop.U.schema('LiveLevelTable') if any(p[1] == 'MissionID' for p in props) else uprop.U.schema('LiveMenuCommandsDataTable')
    idx = [i for i, (n, t) in sc.items() if n == name][0]
    set_prop(props, idx, name, value)


def s(text): return ('str', text)


HANGAR_LEVEL_ID = 0x0F    # must match HANGAR_MENU_ID in runtime/survival_rt.c: the hangar the runtime travels to


def check_hangar(props):
    """The hangar level the runtime travels to is 10 + TravelHangarMap; the row's hangar lighting and sublevels belong
    to that hangar. If they don't match, the hangar loads without light (test 5)."""
    th = [p for p in props if p[1] == 'TravelHangarMap'][0][3][2][2][0]
    subs = [p for p in props if p[1] == 'HangarSubLevelList'][0][3][1]
    assert 10 + th == HANGAR_LEVEL_ID, f'row travels to hangar level {10 + th}, runtime to {HANGAR_LEVEL_ID}'
    want = f'/Game/Maps/Hangar/Hangar{HANGAR_LEVEL_ID - 11:03d}/'
    assert all(sl[1][1].startswith(want) for sl in subs), [sl[1][1] for sl in subs]


def edit_mission_row(props):
    check_hangar(props)
    setv(props, 'MissionID', ('raw', 'Int', struct.pack('<i', MISSION_ID)))
    setv(props, 'LevelId', ('enum', 'ELiveLevelID', ('raw', 'UInt32', struct.pack('<I', LEVEL_ID))))
    setv(props, 'LevelStringID', s('Survival Mode'))
    drop_prop(props, [p for p in props if p[1] == 'ActivityID'][0][0])          # no platform activity
    setv(props, 'MapReference', ('soft', ('name', PL, 0), ('name', PL.rsplit('/', 1)[1], 0), ''))
    setv(props, 'StartupSortNumber', ('raw', 'Int', struct.pack('<i', 91)))
    for k, v in (('MissionNameID', 'SV_Mission_Name'), ('MissionSubtitleTextID', 'SV_Mission_Subtitle'),
                 ('MissionNumberTextID', 'SV_Mission_Number'), ('MissionNumberOnlyTextID', 'SV_Mission_Number'),
                 ('MapNameID', 'SV_Mission_Location'), ('MissionClearConditionID', 'SV_Mission_Objective'),
                 ('MissionOperationTextID', 'SV_Mission_Name'), ('MissionObjectiveTextID', 'SV_Mission_Briefing'),
                 # ((2026-11-08) the user: "we need to change the date to sometime in 2015": Survival's own date, not
                 # Mission 22's 08.Feb.2030 (the runtime's SV_Mission_Date, in the game's own form; its time stays 0530)
                 ('MissionDateTextID', 'SV_Mission_Date')):
        setv(props, k, s(v))
    setv(props, 'MissionClearConditionIDs', ('arr', [s('SV_Mission_Objective'), s('SV_Mission_Objective')]))
    setv(props, 'CheckpointTextIndices', ('arr', []))                         # Mission 22's checkpoints
    # No wingmen in the hangar (Survival flies none). Mission 22's row offers Tasha and Coster with the save's plane and
    # skin; on a friend's save that skin list was empty and the hangar's "Wingman1 Info" panel crashed reading it
    # (minidump of 2026-10-22: 0x1479a4153, a null read of entry n-1). WingmanType None x3, as Mission 015's row.
    for k in ('HangarSelectWingman1st', 'HangarSelectWingman2nd', 'HangarSelectWingman3rd'):
        st = [p for p in props if p[1] == k][0][3]
        st[2][:] = [(q[0], q[1], True, None) if q[1] == 'WingmanType' else q for q in st[2]]


def edit_menu_row(props):
    setv(props, 'CommandID', ('name', 'Main_Top_SurvivalMode', 0))
    setv(props, 'TitleTextID', s('SV_Menu_Title'))
    setv(props, 'HelpTextID', s('SV_Menu_Help'))
    setv(props, 'MenuID', s('CampaignFreeMissionDifficulty'))   # the game's own free-mission difficulty page
    setv(props, 'StringArgs', s(MENU_ARGS))
    for k in ('ParentNewFlagTrigger', 'RefFeature'):
        hit = [p for p in props if p[1] == k]
        if hit: drop_prop(props, hit[0][0])


def edit_coop_row(props, what, args):
    """SURVIVAL CO-OP: HOST / JOIN (user, 2026-10-26: "a cleaner way for players to join ... like a 6 year old being able
    to do it", then "can't we have it so people can select who is hosting and who is joining from ingame?"): the same
    entry as SURVIVAL MODE, its own texts and StringArgs; the runtime opens co-op for the run, as host or joiner, when
    one is picked (main.dll OnMainDecide, SV_MenuChoice; Lua adds the rows only when CFG.coop.enabled)."""
    edit_menu_row(props)
    setv(props, 'CommandID', ('name', f'Main_Top_SurvivalCoop{what}', 0))
    setv(props, 'TitleTextID', s(f'SV_Menu_Coop{what}Title'))
    setv(props, 'HelpTextID', s(f'SV_Menu_Coop{what}Help'))
    setv(props, 'StringArgs', s(args))


def edit_coop_host_row(props): edit_coop_row(props, 'Host', COOP_HOST_ARGS)
def edit_coop_join_row(props): edit_coop_row(props, 'Join', COOP_JOIN_ARGS)


# The main menu's flat settings rows, below SURVIVAL CO-OP: JOIN, for when the game's page list doesn't take Survival's
# pages (Scripts/sv_menu.lua FLAT: Lua decides what each one steps and shows, STARTING ZOLLARS, ENEMY AIRCRAFT, START AT
# ROUND and BREAK BETWEEN ROUNDS; main.dll OnMainDecide takes the press, StringArgs SV_Set_<row>, texts
# SV_Menu_Set<row>Title / Help). The names are coop.11's rows', so its containers' rows work with today's Lua.
SETTING_ROWS = ['Room', 'Enemies', 'Start', 'Break']


def edit_setting_row(what):
    def edit(props):
        edit_menu_row(props)
        setv(props, 'CommandID', ('name', f'Main_Top_SurvivalSet{what}', 0))
        setv(props, 'TitleTextID', s(f'SV_Menu_Set{what}Title'))
        setv(props, 'HelpTextID', s(f'SV_Menu_Set{what}Help'))
        setv(props, 'StringArgs', s(f'SV_Set_{what}'))
    return edit


def edit_pages_row(props):
    """SURVIVAL MODE when the game has Survival's pages (MENU_PAGES; Scripts/sv_menu.lua adds this row or the flat ones):
    it opens the modes page (through CAMPAIGN TRAINING's: BORROWED_PAGE); main.dll OnMainDecide lets it through only once Lua found the pages in
    the game's page list (SV_MenuPages)."""
    edit_menu_row(props)
    setv(props, 'CommandID', ('name', 'Main_Top_SurvivalMenu', 0))
    setv(props, 'MenuID', s(page_menu_id('SV_PgModes')))
    setv(props, 'StringArgs', s(MENU_PAGES_ARGS))


def edit_shuttle_npc(props):
    """The shuttle's DT_NPC row (Mission 22's OP0057_sstb_01) under Survival's name key: the text hook shows
    main.lua CFG.specials.shuttle.name for it (user, 2026-10-22: "EMBDIR Shuttle - CORRIS", not Spruce Goose)."""
    assert dict((p[1], p[3]) for p in props)['GameObjectDisplayName02'] == s('ContainerAircraft_Name_SpruceGoose')
    idx = [p[0] for p in props if p[1] == 'GameObjectDisplayName02'][0]
    set_prop(props, idx, 'GameObjectDisplayName02', s('SV_Shuttle_Name'))


def mission_npc_ids():
    """Mission 22's NPC mission rows -> the DT_NPC row each names (NpcId), as plain strings."""
    z = ZenPkg(stock(NPC_TABLE_STOCK))
    dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveNpcMissionDataTable')
    plain = lambda n, k: n if k == 0 else f'{n}_{k - 1}'
    return {plain(*k): plain(*dict((q[1], q[3]) for q in r[2])['NpcId'][1:3]) for k, r in dt['rows']}


def build_model_rows():
    """DT_SV_ModelRows: ACE_MODELS' copies of Online Mode model rows, for main.lua to add to DT_NPC_Model."""
    z = ZenPkg(stock(MODEL_ON))
    rename_package(z, MODEL_ON, DATA + 'DT_SV_ModelRows')
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveModelDataTable')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    schema = uprop.U.schema('LiveModelDataTable')
    idx = {n: k for k, (n, t) in schema.items()}
    out = []
    for new, src, text in ACE_MODELS.values():
        f = survival_events.fname(src)
        row = copy.deepcopy(rows[(f[1], f[2])])
        set_prop(row[2], idx['GameObjectDisplayName01'], 'GameObjectDisplayName01', s(text))
        set_prop(row[2], idx['GameObjectId'], 'GameObjectId', ('raw', 'Int', struct.pack('<i', 1)))
        out.append(((new, 0), row))
    # VOID WATCHER 1's (survival_events.AWACS_MODEL): the campaign's Magnolia row under the game's plain E-767 name
    zc = ZenPkg(stock(MODEL_CP))
    dc, _ = dtx.parse(uprop.Ctx(bytes(zc.payloads[0]), zc.names), 0, 'LiveModelDataTable')
    crow = dict(dc['rows'])
    f = survival_events.fname(survival_events.AWACS_MODEL_SOURCE)
    row = copy.deepcopy(crow[(f[1], f[2])])
    names = dict((q[1], q[3]) for q in row[2])
    assert names['GameObjectDisplayName01'] == s('ContainerAllyCallsign_Name_Magnolia'), names['GameObjectDisplayName01']
    set_prop(row[2], idx['GameObjectDisplayName01'], 'GameObjectDisplayName01', s(survival_events.AWACS_MODEL_NAME))
    out.append(((survival_events.AWACS_MODEL, 0), row))
    # GONE FISHIN's shoal (survival_events.FISH_MODEL): the campaign's GR000_dummy model row (its blueprint, 100 HP) with
    # FISH_HEALTH and Survival's name key
    f = survival_events.fname(survival_events.FISH_MODEL_SOURCE)
    row = copy.deepcopy(crow[(f[1], f[2])])
    names = dict((q[1], q[3]) for q in row[2])
    assert names['BlueprintClass'][2][1] == 'BP_GR000_dummy_CP_C', names['BlueprintClass']
    set_prop(row[2], idx['MaxHealth'], 'MaxHealth', ('raw', 'Float', struct.pack('<f', survival_events.FISH_HEALTH)))
    set_prop(row[2], idx['GameObjectDisplayName01'], 'GameObjectDisplayName01', s(survival_events.FISH_NAME_KEY))
    out.append(((survival_events.FISH_MODEL, 0), row))
    # THE TANICORN's milestone 0 mount (survival_events.TANI_MODEL; docs/re/TANICORN.md): GR000_dummy's model row again,
    # its blueprint Survival's own BP_SV_Tani_T5 (tools/tanicorn; its container ships with TANI=1 only), TANI_HEALTH
    f = survival_events.fname(survival_events.FISH_MODEL_SOURCE)
    row = copy.deepcopy(crow[(f[1], f[2])])
    bpq = [q for q in row[2] if q[1] == 'BlueprintClass'][0]
    assert bpq[3][0] == 'soft' and bpq[3][2][1] == 'BP_GR000_dummy_CP_C', bpq
    row[2][:] = [(q[0], q[1], q[2], ('soft', ('name', survival_events.TANI_BP, 0), ('name', survival_events.TANI_BP_CLASS, 0), ''))
                 if q[1] == 'BlueprintClass' else q for q in row[2]]
    set_prop(row[2], idx['MaxHealth'], 'MaxHealth', ('raw', 'Float', struct.pack('<f', survival_events.TANI_HEALTH)))
    set_prop(row[2], idx['GameObjectDisplayName01'], 'GameObjectDisplayName01', s(survival_events.TANI_NAME_KEY))
    out.append(((survival_events.TANI_MODEL, 0), row))
    # (0.74.60) the hull's model row (survival_events.TANI_HULL_*): the same, its blueprint BP_SV_Tani_HULL
    row = copy.deepcopy(crow[(f[1], f[2])])
    row[2][:] = [(q[0], q[1], q[2], ('soft', ('name', survival_events.TANI_HULL_BP, 0), ('name', survival_events.TANI_HULL_BP_CLASS, 0), ''))
                 if q[1] == 'BlueprintClass' else q for q in row[2]]
    set_prop(row[2], idx['MaxHealth'], 'MaxHealth', ('raw', 'Float', struct.pack('<f', survival_events.TANI_HULL_HEALTH)))
    set_prop(row[2], idx['GameObjectDisplayName01'], 'GameObjectDisplayName01', s(survival_events.TANI_HULL_NAME_KEY))
    out.append(((survival_events.TANI_HULL_MODEL, 0), row))
    # ((2026-11-07) the user: the ZFA-44s' boxes read "SU-47") the ZFA-44 host's model: the allied Su-47's (ZFA_MODEL) whole
    # but its name, ZFA_NAME_KEY ("ZFA-44", Lua's text)
    f = survival_events.fname(survival_events.ZFA_MODEL)
    assert (f[1], f[2]) in crow, survival_events.ZFA_MODEL
    row = copy.deepcopy(crow[(f[1], f[2])])
    set_prop(row[2], idx['GameObjectDisplayName01'], 'GameObjectDisplayName01', s(survival_events.ZFA_NAME_KEY))
    assert survival_events.fname(survival_events.ZFA_MODEL_SV)[2] == 0
    out.append(((survival_events.ZFA_MODEL_SV, 0), row))
    # ((2026-11-07) the launched ZFA-44s on Mission 16's allied container drone) its model row: the drone's whole but its name
    # (ZFA_NAME_KEY) and its health (ZFA_DRONE_HEALTH, the Su-47's, not the drone's 6)
    f = survival_events.fname(survival_events.ZFA_DRONE_MODEL)
    assert (f[1], f[2]) in crow, survival_events.ZFA_DRONE_MODEL
    row = copy.deepcopy(crow[(f[1], f[2])])
    names = dict((q[1], q[3]) for q in row[2])
    assert names['BlueprintClass'][2][1] == 'BP_OP0018_uavc_CP_Ally_C', names['BlueprintClass']
    set_prop(row[2], idx['GameObjectDisplayName01'], 'GameObjectDisplayName01', s(survival_events.ZFA_NAME_KEY))
    set_prop(row[2], idx['MaxHealth'], 'MaxHealth', ('raw', 'Float', struct.pack('<f', survival_events.ZFA_DRONE_HEALTH)))
    assert survival_events.fname(survival_events.ZFA_DRONE_MODEL_SV)[2] == 0
    out.append(((survival_events.ZFA_DRONE_MODEL_SV, 0), row))
    for n in (survival_events.TANI_BP, survival_events.TANI_BP_CLASS, survival_events.TANI_HULL_BP,
              survival_events.TANI_HULL_BP_CLASS): z.nb.add(n)
    for k, row in out:
        for n in names_in(row) + [k[0]]: z.nb.add(n)
    dt['rows'] = out
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveModelDataTable')
    assert chk['rows'] == dt['rows']
    print(f'  DT_SV_ModelRows: {len(out)} rows')
    save(z, DATA + 'DT_SV_ModelRows')


# The music player's added tracks (tools/music_tracks.py; user, 2026-11-08: "add all the named music into the music
# player"): Survival's own table of rows for the game's DT_SoundMusicPlayerBGM, which Scripts/sv_music.lua adds while
# Survival's level is on (each only when its bank is loaded) and takes out after. A row is a copy of the stock Title row
# (no unlock, no origin, its camera set) with the track's title key, title, origin and tab.
MUSIC_TABLE_STOCK = '/Game/Datatables/Sound/DT_SoundMusicPlayerBGM'
MUSIC_TABLE = DATA + 'DT_SV_MusicRows'
MUSIC_TEMPLATE_ROW = 'AKE_Bgm_MUSICPLAYER_BGM_TITLE_Play'
JUKEBOX_TABLE_STOCK = '/Game/OnlineMode/DataTables/Information/JukeBox/DT_JukeBoxMusic'
MUSIC_DB_STOCK = '/Game/WwiseAssets/Database/DA_SoundDB_'    # + the bank: its events (the build checks each is 2D)


def music_track_list():
    """every track Survival adds (tools/music_tracks.py all_tracks over the stock jukebox's rows; music_lengths.py's too)"""
    import music_tracks
    zj = ZenPkg(stock(JUKEBOX_TABLE_STOCK))
    dj, _ = dtx.parse(uprop.Ctx(bytes(zj.payloads[0]), zj.names), 0, 'LiveJukeBoxMusicDataTable')
    jrows = []
    for key, row in dj['rows']:
        f = {q[1]: q[3] for q in row[2]}
        jrows.append((f['ResourceName'][1], f['TitleText'][1], f['OriginTextID'][1]))
    assert len(jrows) == 77, len(jrows)
    return music_tracks.all_tracks(jrows)


def build_music_rows():
    import music_tracks
    tracks = music_track_list()
    # ((2026-11-08) "Music was selected but nothing played": the lobby jukebox's events are 3D, MaxAttenuation 600, and
    # the music player's game object is far from the listener) every added event in its bank and 2D, as the stock ones
    from zen import Zen
    att = {}
    for db in sorted({t[4] for t in tracks}):
        path = MUSIC_DB_STOCK + db
        zd = Zen(stock(path))
        cd = uprop.Ctx(zd.d, zd.names)
        main = [e for e in zd.exports if e['name'] == path.rsplit('/', 1)[1]][0]
        v, _ = uprop.read_struct(cd, zd.header_size + main['off'], 'LiveSoundDatabaseBankAsset')
        for b in {q[1]: q[3] for q in v[2]}['Banks'][1]:
            for e in {q[1]: q[3] for q in b[2]}['Events'][1]:
                ef = {q[1]: q[3] for q in e[2]}
                ma = ef.get('MaxAttenuation')
                att[(db, ef['Name'][1])] = struct.unpack('<i', ma[2])[0] if ma else 0
    for t in tracks:
        assert (t[4], t[0]) in att, f'{t[0]} is in no event of {t[4]}'
        assert att[(t[4], t[0])] == 0, f'{t[0]} is a 3D event (MaxAttenuation {att[(t[4], t[0])]}): silent in the music player'
    # ((2026-11-08) Saint Alessia's run of 0.74.32: "hush still ended abruptly") every looping Online Mode track has its one
    # pass in sv_music.lua's SONG LENGTHS (tools/music_lengths.py write: the .wem's loop end)
    lua = open(os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'sv_music.lua'), encoding='utf-8').read()
    lens = dict(re.findall(r'(AKE_Bgm_Online_\w+_Play) = (\d+),', lua[lua.index('-- BEGIN SONG LENGTHS'):lua.index('-- END SONG LENGTHS')]))
    missing = [t[0] for t in tracks if t[0].startswith('AKE_Bgm_Online_') and t[0] not in lens]
    assert not missing, f'no SONG LENGTHS in sv_music.lua for {missing}: run tools/music_lengths.py write'
    z = ZenPkg(stock(MUSIC_TABLE_STOCK))
    rename_package(z, MUSIC_TABLE_STOCK, MUSIC_TABLE)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveSoundMusicInfoRow')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    stock_keys = {k[0] for k in rows}
    idx = {n: k for k, (n, t) in uprop.U.schema('LiveSoundMusicInfoRow').items()}
    tmpl = rows[(MUSIC_TEMPLATE_ROW, 0)]
    have = {q[1]: q for q in tmpl[2]}
    assert have['bIsEnableUnlock'][2] and have['OriginTextID'][2], 'the template row has no unlock and no origin'

    def tag(v): return ('enum', 'ELiveSoundMusicFilterTag', ('raw', 'Byte', bytes([v])))
    out = []
    for i, t in enumerate(tracks, 1):
        ev, _, title, origin, bank, filt = t
        assert ev not in stock_keys, ev
        assert survival_events.fname(ev)[2] == 0, ev
        row = copy.deepcopy(tmpl)
        key = music_tracks.title_key(i, t)
        assert t[1] or survival_events.fname(key)[2] == 0, key    # (Survival's keys: no numeric tail, hard rule 17)
        set_prop(row[2], idx['TitleTextID'], 'TitleTextID', survival_events.fname(key))   # (split as the game does)
        set_prop(row[2], idx['TitleString'], 'TitleString', s(title))
        if origin:
            set_prop(row[2], idx['OriginTextID'], 'OriginTextID', ('name', music_tracks.origin_key(origin), 0))
            set_prop(row[2], idx['OriginString'], 'OriginString', s(music_tracks.ORIGINS[origin]))
        for n in ('Filter1', 'Filter2', 'Filter3', 'ColorSetType'):
            set_prop(row[2], idx[n], n, tag(filt))
        out.append(((ev, 0), row))
    for k, row in out:
        for n in names_in(row) + [k[0]]: z.nb.add(n)
    dt['rows'] = out
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveSoundMusicInfoRow')
    assert chk['rows'] == dt['rows']
    banks = {}
    for t in tracks: banks[t[4]] = banks.get(t[4], 0) + 1
    print(f'  DT_SV_MusicRows: {len(out)} tracks (' + ', '.join(f'{b} {n}' for b, n in banks.items()) + ')')
    save(z, MUSIC_TABLE)


def build_rows():
    build_music_rows()
    build_rows_table('/Game/Datatables/Information/DT_LiveMissionTable', DATA + 'DT_SV_MissionRows',
                     'LiveLevelTable', 'Mission022', 'SurvivalMode', edit_mission_row)
    build_npc_rows()
    build_model_rows()
    build_rows_table('/Game/Datatables/UI/Menu/MainMenu/Top/DT_LiveMenuMainTopCommands', DATA + 'DT_SV_MenuRows',
                     'LiveMenuCommandsDataTable', 'Campaign', 'SurvivalMode', edit_menu_row,
                     more=[('SurvivalCoopHost', edit_coop_host_row), ('SurvivalCoopJoin', edit_coop_join_row),
                           ('SurvivalMenu', edit_pages_row)] + [(f'SurvivalSet{w}', edit_setting_row(w)) for w in SETTING_ROWS])
