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
    print(f'  the deal: {DEAL_ASK} opens AC8\'s Yes / No ({DEAL_QUESTION}); its answer in {DEAL_FLAG} '
          f'(1 YES / 2 NO / 3 silence): {len(g.trig) - n_trig} triggers, {len(g.ex) - n_ex} executions')
