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


def build_deal(g, flag, stock_ep):
    m8 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission008', 'EP_Mission008_global.uasset')
    t_ask = g.foreign_template(m8, 'LiveActivateYesNoExecution', 'Default_PostRadioEvent_55')
    assert arg_values(t_ask) == ['ms08_01_Question_Detonation'], arg_values(t_ask)  # noqa: F405
    n_trig, n_ex = len(g.trig), len(g.ex)
    g.trigger('RE_SpawnEnemy_kokatu_1st', DEAL_ASK)              # (a remote event: Lua's SV_Event fires it)
    flag(DEAL_ASK, DEAL_FLAG, 'Set', 0)                        # (asked: no answer yet)
    g.execute(t_ask, DEAL_ASK, {0: DEAL_QUESTION}, delay=0.1)
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
    print(f'  the deal: {DEAL_ASK} opens AC8\'s Yes / No ({DEAL_QUESTION}); its answer in {DEAL_FLAG} '
          f'(1 YES / 2 NO / 3 silence): {len(g.trig) - n_trig} triggers, {len(g.ex) - n_ex} executions')
