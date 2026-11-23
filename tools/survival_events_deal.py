"""survival_events_deal.py: THE DEAL's events (docs/re/DEAL.md; Scripts/sv_deal.lua). Part of survival_events.py (it imports
this at its end; build_events calls build_deal).

AC8's own Yes / No prompt, as Mission 8 asks its questions (EP_Mission008_global: "Default_PostRadioEvent_55"
LiveActivateYesNoExecution { the question's id }, then three triggers on that id, areaB_YesNoEvent: Left = YES,
areaB_YesNoEvent_0: Right = NO, areaB_YesNoEvent_1: TimeOut = silence; Mission 8's replies show which is which:
01_Question_B_Yes / _No / _silence). Lua fires RE_SV_DealAsk on each player's game when War asks (the user,
2026-11-23: "theres a Yes or No system already built into ACE8"); the answer comes back in the int flag SV_DealAns:
0 asked, 1 YES, 2 NO, 3 silence.
"""
import os

from survival_events import *  # noqa: F401,F403 (survival_events' names; it imports this part at its end)

DEAL_QUESTION = 'SV_Deal_Question'          # (our question's id: the prompt and its triggers match on it)
DEAL_ASK = 'RE_SV_DealAsk'
DEAL_FLAG = 'SV_DealAns'
DEAL_ANSWERS = (('areaB_YesNoEvent', 'Left', 'SV_DealYes', 1),
                ('areaB_YesNoEvent_0', 'Right', 'SV_DealNo', 2),
                ('areaB_YesNoEvent_1', 'TimeOut', 'SV_DealSilent', 3))
INT_FLAGS += [DEAL_FLAG]  # noqa: F405
# ((2026-11-23, the autotest: no prompt showed) a question id is a row of DT_YesNo (LiveYesNoDataTable: YesNoID, its
# AnswerTimeLimit, the YES / NO buttons' texts; Mission 8's 4 s, Mission 12's 3 s; the question itself is the radio
# line said with it). Survival's own row in its own table, DT_SV_YesNo (build_survival_rows.py), which Lua adds to
# DT_YesNo at the main menu (sv_deal.lua dealSetup; a world subsystem's, read as the level loads), its time the vote's
DEAL_YESNO_TABLE = 'DT_SV_YesNo'
DEAL_ANSWER_S = 30.0                        # (sv_deal.lua vote_s)
# ((2026-11-23, the 2nd autotest: the row in, still no prompt) Mission 8 asks over the radio: its question is a radio row
# (DT_Rdo_ST_ms008, e.g. row 497, AWACS's "01_D_Aegis_CIWS_Defense") naming the question (YesNoID, bUseYesNoSubtitle:
# the Yes / No under the line in the com window), played by LiveRadioPlayExecution (Default_PostRadioEvent_54), and the
# line's post (type 25, Default_PostRadioEvent_55) activates it. Survival's: DT_SV_Radio's group SV_DealRadio_Ask, that
# row cloned with our question and a text-only line, TextID SV_Radio_DealAsk (no voice: War is subtitles only; its text
# set by Lua, SV_SetText; docs/re/RADIO_LOCALISATION.md 2c's text-only route, first tried here)
DEAL_RADIO_GROUP, DEAL_RADIO_TEXT = 'SV_DealRadio_Ask', 'SV_Radio_DealAsk'
DEAL_RADIO_SOURCE = ('/Game/Datatables/Radio/DT_Rdo_ST_ms008', '497', '01_D_Aegis_CIWS_Defense')
# ((2026-11-23, the 3rd autotest: no radio window) the row's mission flags (bM01...) are Mission 8's: every one set, as
# the tells' template row 382. And a voiced twin, the user's "try the box with a real voice line, or a silent one":
# SV_DealRadio_AskV, the same row with its own stock voice (AWACS, v0001_1460), fired by RE_SV_DealAskV (the test's)
DEAL_RADIO_VOICED = ('SV_DealRadio_AskV', 'RE_SV_DealAskV')
# ((2026-11-23, the 6th autotest: neither line played, a DECOY line did) the voiced twin played by Survival's own radio
# node (Mission 22's CompositeEvent_CountDown_1, THE DECOY's) with its Yes / No activated at once; and a control,
# SV_DealRadio_AskN (RE_SV_DealAskN): the same line with no YesNoID, to see whether naming a Yes / No stops a line playing
DEAL_RADIO_CONTROL = ('SV_DealRadio_AskN', 'RE_SV_DealAskN')
# WAR & HAYTHORN's F/A-18F (the user: "War and Haythorn's Super Hornet will appear randomly ... between rounds. They appear
# as an allied aircraft and the player gets the event zoom in on their aircraft when they appear"; "after each deal has
# been made, War and Haythorn turn around and exit the combat zone and despawn"): an allied unit as the ESCORT's KMG
# fighters (build_survival_world.py: MOONCHILD's unit copied, its row survival_events_escort.ESC_ROWS['sv_deal_f18f']),
# spawned by Lua (SV_Spawn) ahead of you; RE_SV_DealCam its event zoom (the shuttle's focus camera, Mission 22's
# LookAt_Event_Camera_ms22-01), RE_SV_DealLeave its way out of the area (DEAL_PATH_OUT, far north east), then recycled
DEAL_UNIT, DEAL_OBJ = 'SV_Unit_DealHornet', 'SV_Obj_DealHornet'
DEAL_ROW = 'sv_deal_f18f'
DEAL_NAME_KEY = 'SV_DealHornet'             # (its box's text, WAR & HAYTHORN: set by Lua, SV_SetText)
DEAL_CAM, DEAL_CAM_S = 'RE_SV_DealCam', 4.0
DEAL_LEAVE = 'RE_SV_DealLeave'
DEAL_PATH_OUT = 'SV_Path_DealHornetOut'
DEAL_OUT_SPEED = '950.0'                    # km/h
DEAL_OUT_PTS = [(5500000.0, 2600000.0, 350000.0), (9000000.0, 4200000.0, 350000.0)]   # cm: ~45 km NE of the airfield, on out, 3.5 km up

# The deals' targets (the user: "a Podarge transport flight that the players can go and destroy", "a tip-off on a large
# enemy fleet", "C-130s nearby carrying goods for Emblem Direct"; "The Target will arrive in the next round"): Lua
# (sv_deal.lua) spawns them as that round starts and orders them onto their routes (RE_SV_DealPodargeGo /
# RE_SV_DealCargoGo); the fleet is the Spaceport round's own enemy ships (sv_spaceport.lua SPORT.fleet), no new unit.
_AF = (1609639.0, -436414.0)                # the airfield, cm (survival_events.AIRFIELD_KM); north is -y


def _af(dx_km, dy_km, alt_cm): return (_AF[0] + dx_km * 1e5, _AF[1] + dy_km * 1e5, alt_cm)


# the Podarge: Mission 12's Norn (AC8's Podarge: Mission 25 day 2's "It's a Podarge!"; Mission 12's PodargeDead light),
# EAUnit01_Norn0 with its 16 parts (its Cargo1 slot, a carried ldbs3a_A, left out), ported as the Ladons are
# (build_survival_units.py deal_units); its mission rows Mission 12's (build_survival.py NPC_IMPORT), the body's under
# Survival's name. West to east, ~9 km south of the runway
DEAL_PODARGE_WD = '/Game/Maps/Ingame/Mission012/WD_Mission012_global'
DEAL_PODARGE_SOURCE, DEAL_PODARGE_SOURCE_ROW = 'EAUnit01_Norn0', 'norn_01'
DEAL_PODARGE_UNIT, DEAL_PODARGE_OBJ, DEAL_PODARGE_ROW = 'SV_Unit_DealPodarge', 'SV_Obj_DealPodarge', 'sv_deal_podarge'
DEAL_PODARGE_DROP = ('Cargo1',)
DEAL_PODARGE_PART_ROWS = (['norn_LargeEngine_L1', 'norn_LargeEngine_R1', 'norn_LeftAirIntake', 'norn_RightAirIntake',
                           'norn_Turret_L1', 'norn_Turret_R1', 'norn_VLS_L1', 'norn_VLS_R1']
                          + [f'norn_Wing_{s}{k}' for s in 'LR' for k in range(1, 5)])
DEAL_PODARGE_PATH, DEAL_PODARGE_GO, DEAL_PODARGE_SPEED = 'SV_Path_DealPodarge', 'RE_SV_DealPodargeGo', '450.0'
DEAL_PODARGE_PTS = [_af(-38, 12, 280000.0), _af(-20, 10, 280000.0), _af(0, 9, 280000.0), _af(20, 7, 280000.0),
                    _af(40, 4, 280000.0)]
# Emblem Direct's cargo: three C-130s (AC8's OP0054_c130_01), a copy of Survival's heavy flight (EA_Unit_01_Air2, as
# THE FESTIVAL's) on a row of Mission 4's Tu-160 (NLID_1000: a large aircraft); north to south past the runway's east,
# a lane each 600 m apart
DEAL_CARGO_UNIT, DEAL_CARGO_OBJ, DEAL_CARGO_ROW = 'SV_Unit_DealCargo', 'SV_Obj_DealCargo', 'sv_deal_cargo'
DEAL_CARGO_SOURCE, DEAL_CARGO_NPC, DEAL_CARGO_N = 'EA_Unit_01_Air2', 'OP0054_c130_01', 3
DEAL_CARGO_OBJS = [f'{DEAL_CARGO_OBJ}_{k}' for k in range(DEAL_CARGO_N)]
DEAL_CARGO_GO, DEAL_CARGO_SPEED = 'RE_SV_DealCargoGo', '420.0'
DEAL_CARGO_LANES = [('A', 0.0), ('B', -0.6), ('C', 0.6)]


def deal_cargo_route(side_km):
    return [_af(-6 + side_km, -36, 220000.0), _af(2 + side_km, -18, 220000.0), _af(10 + side_km, 0, 220000.0),
            _af(16 + side_km, 18, 220000.0), _af(22 + side_km, 38, 220000.0)]


DEAL_CARGO_PATHS = [f'SV_Path_DealCargo{t}' for t, _ in DEAL_CARGO_LANES]
DEAL_TARGET_AREA_M, DEAL_TARGET_ALT_M = 90000.0, (0.0, 12000.0)
ESCORT_DECOY_MISSION_ROWS += [(DEAL_CARGO_ROW, '/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission004', 't160_common',  # noqa: F405
                               DEAL_CARGO_NPC, None)]


def build_deal(g, flag, stock_ep):
    m8 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission008', 'EP_Mission008_global.uasset')
    t_ask = g.foreign_template(m8, 'LiveActivateYesNoExecution', 'Default_PostRadioEvent_55')
    assert arg_values(t_ask) == ['ms08_01_Question_Detonation'], arg_values(t_ask)  # noqa: F405
    t_radio = g.foreign_template(m8, 'LiveRadioPlayExecution', 'Default_PostRadioEvent_54')
    assert arg_values(t_radio)[0] == '01_Question_Detonation', arg_values(t_radio)  # noqa: F405
    t_post = g.foreign_trig_template(m8, 'Default_PostRadioEvent_55')
    assert arg_values(t_post)[0] == '01_Question_Detonation', arg_values(t_post)  # noqa: F405
    n_trig, n_ex = len(g.trig), len(g.ex)
    g.trigger('RE_SpawnEnemy_kokatu_1st', DEAL_ASK)              # (a remote event: Lua's SV_Event fires it)
    flag(DEAL_ASK, DEAL_FLAG, 'Set', 0)                        # (asked: no answer yet)
    g.execute(t_radio, DEAL_ASK, {0: DEAL_RADIO_GROUP}, delay=0.1)      # War's question on the radio, the Yes / No under it
    post = 'SV_DealAskPosted'
    g.trigger(None, post, template=t_post, arg_changes={0: DEAL_RADIO_GROUP})
    g.execute(t_ask, post, {0: DEAL_QUESTION})
    t_radio22 = g.exec_template('LiveRadioPlayExecution', 'CompositeEvent_CountDown_1')
    vgrp, vev = DEAL_RADIO_VOICED
    g.trigger('RE_SpawnEnemy_kokatu_1st', vev)
    flag(vev, DEAL_FLAG, 'Set', 0)
    g.execute(t_ask, vev, {0: DEAL_QUESTION})
    g.execute(t_radio22, vev, {0: vgrp}, delay=0.1)
    cgrp, cev = DEAL_RADIO_CONTROL
    g.trigger('RE_SpawnEnemy_kokatu_1st', cev)
    g.execute(t_radio22, cev, {0: cgrp}, delay=0.1)
    for stock_trig, button, name, value in DEAL_ANSWERS:
        t = g.foreign_trig_template(m8, stock_trig)
        assert arg_values(t) == ['ms08_01_Question_Detonation', button], (stock_trig, arg_values(t))  # noqa: F405
        g.trigger(None, name, template=t, arg_changes={0: DEAL_QUESTION})
        flag(name, DEAL_FLAG, 'Set', value)
    # the Hornet's event zoom and its way out
    t_cam_on = g.exec_template('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == SHUTTLE)  # noqa: F405
    t_cam_off = g.exec_template('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == 'NoneSelect')
    assert arg_values(t_cam_on)[4] == 'LookAt_Event_Camera_ms22-01', arg_values(t_cam_on)  # noqa: F405
    g.trigger('RE_SpawnEnemy_kokatu_1st', DEAL_CAM)
    g.execute(t_cam_on, DEAL_CAM, {0: DEAL_OBJ})
    g.execute(t_cam_off, DEAL_CAM, delay=DEAL_CAM_S)
    m16 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission016', 'EP_Mission016_global.uasset')
    t_path = g.foreign_template(m16, 'LiveAIPathExecution', 'PathFinish_Ladon0_0', lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0')
    assert arg_values(t_path)[:5] == ['B_Obj_01_Air0_Ladon0', 'NoneSelect', '01_Air0_Ladon_Path2', 'NoneSelect', '2000.0'], arg_values(t_path)  # noqa: F405
    g.trigger('RE_SpawnEnemy_kokatu_1st', DEAL_LEAVE)
    g.execute(t_path, DEAL_LEAVE, {0: DEAL_OBJ, 2: DEAL_PATH_OUT, 4: DEAL_OUT_SPEED})
    # the targets onto their routes
    g.trigger('RE_SpawnEnemy_kokatu_1st', DEAL_PODARGE_GO)
    g.execute(t_path, DEAL_PODARGE_GO, {0: DEAL_PODARGE_OBJ, 2: DEAL_PODARGE_PATH, 4: DEAL_PODARGE_SPEED}, delay=0.5)
    g.trigger('RE_SpawnEnemy_kokatu_1st', DEAL_CARGO_GO)
    for o, path in zip(DEAL_CARGO_OBJS, DEAL_CARGO_PATHS):
        g.execute(t_path, DEAL_CARGO_GO, {0: o, 2: path, 4: DEAL_CARGO_SPEED}, delay=0.5)
    print(f'  the deal: {DEAL_ASK} opens AC8\'s Yes / No ({DEAL_QUESTION}); its answer in {DEAL_FLAG} '
          f'(1 YES / 2 NO / 3 silence): {len(g.trig) - n_trig} triggers, {len(g.ex) - n_ex} executions')
