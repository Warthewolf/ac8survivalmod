# THE DEAL: WAR & HAYTHORN's Yes / No vote (2026-11-12; the user's dev install only; not yet run in game)

The user's design (2026-11-11 / 2026-11-12): by chance, on some specials, an allied, marked F/A-18F Super Hornet named
**WAR & HAYTHORN** joins the players. War (she; no flight experience, the WSO seat) asks whether they want to cut a deal:
carry on the special with higher stakes (YES) or not (NO). Every player votes, solo too; the most votes win, a tie is NO.
Then the Hornet leaves, with subtitles saying so. A deal taken pays extra cash. Subtitles only, no voice.

Code: `Scripts/sv_deal.lua` (one DEV ONLY block: out of every release and TESTER zip, TANACORN ones too:
tools/strip_test_only.py, tools/dev_only.py); its hooks: the NEXT row (sv_hud.lua) and the messages
(sv_coop_migration.lua), each in a DEV ONLY block. Settings: `CFG.specials.deal` (in sv_deal.lua while it's the dev
install's; set in CFG_DEFAULTS too, so it's no edit for the leaderboard and no difference the co-op host sends).

## 1. How a deal runs
| Step | What | Settings |
| --- | --- | --- |
| roll | once a round, offer_after_s into a special's round (never in your STORE: SPC.storeShut), the special's kind rolled against its chance; a kind not listed never | `kinds` (D1: which kinds and chances are still the user's call), `offer_after_s` 45 |
| offer | the Hornet spawned ahead and to the right of you, flying your way; War's introduction (an exchange) | `hornet` |
| open | War asks; the callout THE DEAL; the NEXT row `THE DEAL: CTRL+A YES / CTRL+X NO   YES y  NO n   0:30   YOU: YES` | `vote_s` 30, `keys`, `intro_max_s` |
| close | the clock out, or every player answered; YES wins only with more votes; a tie, or nobody: NO | `allow_change` (the last answer counts) |
| result | War's line for YES / NO / a tie / nobody; the result on the row result_row_s | `result_row_s` 8 |
| leave | leave_after_s later the leaving lines; the Hornet taken off leave_s after them (SV_Recycle, on a timer: hard rule 4) | `leave_after_s` 7, `hornet.leave_s` 25 |
| pay | YES only, at the round's clear: what this game earned from the close to the clear again x (kills_x - 1) (its own: COOP.payOwn), and the host's bonus to everyone (addCredits: co-op's "cr", split as a special's pay); a round moving on uncleared: nothing | `pay` (kills_x 2, bonus 5000 + 250 a round: a proposal) |
| stakes | what YES does to the round itself | `stakes` (D2: the user's call, none yet) |

The clock holds while the game is paused. A new run drops a deal that was on.

## 2. Co-op (host-authoritative)
| Message | From, to | Fields | Guards (tools/checks/coop_guard_test.lua: host "vt", joiner "dl", "dr") |
| --- | --- | --- | --- |
| `dl` | host, everyone | id, kind, secs left, yes, no | id whole 1-1e6; kind a word of 16 or fewer; secs 0-120; counts 0-24 |
| `vt` | joiner, host | id, 1 / 0 | a slot in range and not the host's; the open vote's id; 0 or 1 only; nothing after the close |
| `dr` | host, everyone | id, yes, no, 1 / 0 | as dl's |
`dl` goes reliable as the vote opens and as a vote comes in, unreliable every resend_s (a player linking mid-vote gets it).
War's lines go to the joiners as the host's other subtitles do ("sb"), the Hornet as its spawns do, the callout as "co".
A joiner drops a vote with no result 10 s after its close (the host gone).

## 3. Still to do
- **R (the game's own Yes / No).** `LiveActivateYesNoExecution` (Mission 8) and `ULiveYesNoRadioWorldSubsystem`: its args,
  how the answer comes back, its buttons (a pad!), whether it opens more than once a level and in co-op. Needs the
  game's paks (tools/checks/ep_dump.py on Mission 8's event package). Until then the keys are UE4SS's: keyboard only.
- **The Hornet's unit.** `SV_Unit_DealHornet` (an allied F/A-18F, the campaign's f18f, flying MOONCHILD's set, not the
  aces': hard rule 22) with its name key `SV_DealHornet`, ALLY-marked with a target box (hard rule 32): world data and
  rows as VOID WATCHER 1's (tools/survival_events.py AWACS_*, build_survival_units.py). Until a build has it, the deal goes
  on without the plane (`deal: the Hornet: ... not spawned (no such unit or aircraft)`).
- D1 (which kinds, their chances), D2 (what YES does, how much it pays), D3 (whether a vote can change).
- When it ships: the lines into config/subtitles.ini (`python -I tools/subtitles.py merge`), its settings into survival.ini.

## 4. Log lines
`deal: offered on round R (<kind>, chance C, rolled X): the Hornet up|not up, the vote opens in N s`,
`deal: round R (<kind>): no offer (rolled X, chance C)`, `deal: the Hornet: <unit> up 1.5 km ahead of you (WAR & HAYTHORN)`,
`deal: vote N open for 30 s (P players)`, `deal: player S votes YES|NO`, `deal: vote N closed (the clock ran out | everyone
answered): YES y, NO n: TAKEN|REFUSED (the most votes | a tie is no | nobody answered: no)`, `deal: the stakes for <kind>:
none yet`, `deal: round R cleared with the deal: +X (earned E x 1.00 more) + bonus B`, `deal: the Hornet taken off (...)`;
a joiner: `deal: the host's vote N open (<kind>, S s left)`, `deal: your vote on N: YES (sent to the host)`, `deal: the
host's vote N closed: ...`.

## 5. Test checklist (dev install)
1. Solo, Ctrl+H in a round: the Hornet ahead and right (its box WAR & HAYTHORN, allied), War's two lines, then her ask,
   the callout, the NEXT row counting down from 0:30.
2. Ctrl+A: closed at once, TAKEN, War's yes line, the row's result; 7 s on the leaving lines; 25 s later the Hornet gone.
3. Clear the round: `deal: round R cleared with the deal` and THE DEAL PAID's callout.
4. Ctrl+H again next round, Ctrl+X: REFUSED; once more, no answer: NO after 30 s.
5. Pause during a vote: the clock holds.
6. Co-op, two players: the joiner sees the Hornet, the lines, the row; its Ctrl+A / Ctrl+X reaches the host (`deal: player 2
   votes ...`); one YES, one NO: a tie, REFUSED; both YES: TAKEN, each game paid its own extra, the bonus on both.
7. Ctrl+A / Ctrl+X do nothing in the game itself (UE4SS doesn't take the key from the game).
Checks without the game: `sh tools/checks/deal_test.sh` (the part, a release's and TESTER's copies) and
`sh tools/checks/coop_guard_test.sh`.
