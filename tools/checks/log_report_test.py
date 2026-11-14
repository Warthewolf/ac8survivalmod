"""log_report_test.py : tools/log_report.py on made-up bundles (tools/checks/fixtures/log_report; run by log_report_test.sh).

The fixtures: a host (Kestrel, the old layout: undated logs in a folder, its clock over midnight) and a joiner (Wren,
runtime 0.32.32+'s layout: dated names, a session file, the collapsed UE4SS copy and its stats, bundle.txt, the game's
Saved/Logs and a crash folder), zipped here as the runtime zips a session. Its clock is the host's + 3:00:07. Every
name is invented. The checks: each section's key lines on each page (the host alone, the joiner's zip alone, both
together, a logs folder of two session zips), the clocks aligned and the disagreements found, every table's rows as
wide as its head (nothing from a log breaks one), no raw HTML from a log, UE4SS.log's collapsed runs counted back, a
200,000-line UE4SS.log streamed, and the checklist's anchors still in the code (--check-anchors). cases(): the smaller
bundles (solo/, pair/, fork/, rolecrash/, storeq/: 0.74.66's STOREQ on a host and a joiner, and the host's without a STORE
window, a migrated joiner, damaged zips), each for rules the big two don't reach; the checklist's tables a build each
(0.74.52's, 0.74.66's); storeq_rules(): 0.74.66's rows, the Errors section and the STOREQ table's bold agree.
"""
import os, re, shutil, subprocess, sys, time, tracemalloc, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
TOOL = os.path.join(ROOT, 'tools', 'log_report.py')
FIX = os.path.join(HERE, 'fixtures', 'log_report')
OUT = os.path.join(ROOT, 'build', 'checks', 'log_report')
STAMP = '2026-11-12_02-49-50'
fails = []


def run(*args):
    r = subprocess.run([sys.executable, '-X', 'utf8', '-I', TOOL] + list(args), capture_output=True, text=True, encoding='utf-8')
    if r.returncode:
        print(r.stdout + r.stderr)
    return r


def page(name, *bundles):
    out = os.path.join(OUT, name + '.md')
    r = run(*bundles, '-o', out)
    if r.returncode:
        fails.append('%s: log_report exited %d' % (name, r.returncode))
        return ''
    with open(out, encoding='utf-8') as f:
        return f.read()


def has(name, text, *needles):
    for n in needles:
        ok = re.search(n.pattern, text, re.M) if isinstance(n, re.Pattern) else n in text
        if not ok:
            fails.append('%s: missing %r' % (name, n.pattern if isinstance(n, re.Pattern) else n))


def once(name, text, *needles):
    for n in needles:
        if text.count(n) != 1:
            fails.append('%s: %r %d times, not once' % (name, n, text.count(n)))


def lacks(name, text, *needles):
    for n in needles:
        if (re.search(n.pattern, text, re.M) if isinstance(n, re.Pattern) else n in text):
            fails.append('%s: should not have %r' % (name, n.pattern if isinstance(n, re.Pattern) else n))


def well_formed(name, text):
    """every table's rows have the head's cell count (an unescaped | from a log would add one); no raw tag from a log"""
    head = None
    for line in text.split('\n'):
        if line.startswith('|'):
            n = len(re.findall(r'(?<!\\)(?:\\\\)*\|', line))       # (a pipe after an even run of backslashes ends a cell)
            if head is None:
                head = n
            elif n != head:
                fails.append('%s: a table row with %d cells, its head %d: %s' % (name, n, head, line[:120]))
        else:
            head = None
        bare = re.sub(r'`[^`]*`', '', line)
        for tag in re.findall(r'(?<!\\)<(/?[A-Za-z]+)', bare):
            if tag.lower() not in ('details', '/details', 'summary', '/summary'):
                fails.append('%s: a raw <%s> in the page: %s' % (name, tag, line[:120]))


def zip_dir(src, dst):
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
        for d, _, files in os.walk(src):
            for fn in sorted(files):
                full = os.path.join(d, fn)
                z.write(full, os.path.relpath(full, src).replace(os.sep, '/'))
    return dst


def main():
    os.makedirs(OUT, exist_ok=True)
    jzip = os.path.join(OUT, 'AC8Survival_%s_0.74.52-coop2mp.144.zip' % STAMP)
    zip_dir(os.path.join(FIX, 'joiner'), jzip)
    host = os.path.join(FIX, 'host')

    # ---- the host alone (the old layout, a folder)
    a = page('host', host)
    well_formed('host', a)
    has('host', a,
        '| Kestrel (host) | host (hosts co-op run 5eed1234) | 0.74.52-coop2mp.144 | 0.32.35 | 0123456789abcdef |',
        'UE4SS mods started: AC8SurvivalMode, NoisyMod',
        '> my name is \\<script\\>alert(1)\\</script\\> \\| not a table',                       # the report, escaped
        '| 3 | Osprey | 23:50:22 | 00:01:40 | 1 | 1 | 1 | 0.74.52-coop2mp.144 |',
        'refused a join: Gan\\|net \\<b\\>\\`x\\`\\</b\\> (theirs 0.74.40-coop2mp.132',
        # rounds: kinds, the round over midnight, the run's end
        '| 1 | 2 | 23:52:50 | 23:55:00 | 2:10 | special: shuttle (defend the embdir shuttle - corris) | cleared | 3 | 8 (3) |',
        '| 1 | 3 | 23:55:20 | 00:02:00 | 6:40 | ace squadron: Valkyrie | cleared |',
        '| 1 | 4 | 00:02:20 | 00:06:00 | 3:40 | special: retake (retake the spaceport) | cleared |',
        '| 1 | 5 | 00:06:20 | 00:07:31 | 1:11 | special: alicorn (submarine contact) | cleared |',
        '| 1 | 6 | 00:07:51 | - | - | normal | run over (left): round 6, score 12345',
        # lag by round: perf, SV_UnitAlive, frames and units
        '| 3 | ace squadron: Valkyrie | 45.5 | 45.5 | 1 (100%) | 380 | rounds 30.1, allies 5.0, coop 3.2 | 2.0 / 0.10 ms | 20-20 | 300 | 4 | 20 / 400 us |',
        'Tick avg by round kind: ace 45.5 ms (1 line, 5:00), normal 12.0 ms (1 line, 1:00).',
        # the STORE: the window, its events (the crumbs' too), the special's moment inside it
        '| 1 | 23:54:00 | 23:54:30 | 0:30 | 2 | 8 starts 7 ends |',
        '**\\!round 2, the shuttle lifted off (countdown over', 'RE\\_SV\\_Bracket\\_02, RE\\_SV\\_Bracket\\_03',
        '**RE\\_SV\\_Escort\\_04**', '**RE\\_SV\\_ShuttleT\\_150**', '**RE\\_SV\\_DirFree\\_04**',
        # DOWN and revives
        "| Kestrel | 23:57:00 | 23:59:41 | 2:41 | WREN | 9500 (by player 2; the run's revive 1, their 1; round 3's price) |",
        '| OSPREY | 23:58:00 | left the mission 00:01:40 | 3:40 | - | - |',
        # the link
        '| 3 | Osprey | 300 / 300 / 300 | 10 | 1 | 1 | 1 | 1 |',
        'the host\'s "left" notice: out of Survival\'s level: every joiner told this game left its run in round 6',
        # ZFA-44s
        '"could not be finished": 1', 'Helios blasts: 1, 2 enemy aircraft down by them; ZFA-44 down after its blast: 1',
        "round 6's 2 were every one of them named already at round 3 (the same objects for 3 rounds: none of them died)",
        # the shuttle, the rockets, the Alicorn, the leaderboard
        '**23:54:25 lifted off: countdown over**', "**23:54:35 lifted off: the replay's try 1**",
        '`special: rocket A escaped (its climb\'s end at 20200 m, 105 s after its launch)',
        'tank hits: fl 2 (8784 health)', 'core hits: 2, 9600 health in all, the last 00:07:30 (0 left, 0%)',
        'Run id 5eed1234; sends 1; answers: NOT stored 1.', '00:09:02 (runtime) `run sent, status 200`',
        # errors grouped (a routine "can't be said now" left out); UE4SS.log (Survival's own lines not its errors)
        "`coop: a copy here couldn't be finished (health 1800 after)`",
        'Lines by source: NoisyMod 9 (64.3%), UE4SS 3 (21.4%), AC8SurvivalMode 2 (14.3%).',
        '| 6 | 42.9% | `[Lua] [NoisyMod] polling N more object` |',
        '| 1 | 2026-11-11 23:51:00.0000000 | `[Lua] [NoisyMod] Error: something failed in its poll` |',
        # the checklist: seen, and a "no" line seen
        '| lag-1 | lag | native | `spawner: LiveUnitSpawner ...checked through GUObjectArray: yes` | yes | seen 1 (first 23:49:57) |',
        '| zfa-1 | ZFA-44s | lua | `carrier: a ZFA-44 X (...) could not be finished` | no | seen 1 (first 00:06:00) |',
        '| down-1 | DOWN host | lua | `stats: you\'re down: your flying isn\'t measured` | when | not seen |',
        '| lag-1 | lag | native | `units: the last minute: N SV_UnitAlive asks` | yes | seen 2 (first 23:52:20) |',
        '> see www\\.example.com or https\\://example.com/x')                                   # (no autolink)
    has('host', a, "- this build is older than 0.74.66: the checklist's 0.74.66 lines can't be in its logs",   # (0.74.52's:
        'Kestrel (host) runs 0.74.52-coop2mp.144, older than 0.74.66: none of these can be there.',          # 0.74.66's
        "| storeq | STORE joiner | lua | `storeq: the host's X held here: ...; fired here once it's shut` | when | not in its build |")
    once('host', a, '| Kestrel | 23:57:00 |', '| OSPREY | 23:58:00 |')                # (a DOWN said twice at once: one)
    lacks('host', a, "can't be said now", '| 1 | 2026-11-11 23:52:00', '## Clocks', '## Where the games disagree',
          'STOREQ by window', 'older than 0.74.52')

    # ---- the joiner alone (the runtime's zip of one session)
    b = page('joiner', jzip)
    well_formed('joiner', b)
    has('joiner', b,
        "| Wren (joiner) | joiner (in the host's co-op run 5eed1234; later the host by migration) | 0.74.52-coop2mp.144 | 0.32.35 |",
        '| %s |' % STAMP.replace('_', '\\_'), 'crash folders in the bundle: UECC-Windows-0A1B2C',
        '`Unhandled Exception: EXCEPTION_ACCESS_VIOLATION reading address 0x00000030 (made up for the test)`',
        'bundle.txt: 3 files added, 1 skipped or partial; UE4SS.log: 5 MB read, 1 MB copied',
        'joiner; this game is player 2.', 'The host: player 1, Kestrel.',
        '| 3 | ace squadron: Valkyrie | - | - | - | - | - | - | 20-20 | 400 | 5 | - |',
        '| 4 | special: Retake The Spaceport | 14.0 | 14.0 | 1 (68%) | 90 | coop 4.0, escort 2.0, allies 1.0 |',   # (a perf line's
        '| 5 | special: Submarine Contact | 14.0 | - | 1 (31%) | - | coop 4.0, escort 2.0, allies 1.0 |',   # window over two rounds)
        # the window: what ran (the host's forwarded), what the lines say did NOT run (~), not their explanations' names
        '| 1 | 02:57:30 | 02:59:47 | 2:17 | 3 | 8 starts 7 ends | **RE\\_SV\\_FlightOff\\_01 (h)**, RE\\_SV\\_RadioWaveA (h), '
        "\\~RE\\_SV\\_ShuttleRemove (didn't take), \\~RE\\_SV\\_WolfHold\\_15B (h) (dropped) |",
        '`coop: player 1: sys\\|refused\\|Gan\\ \\|0.74.40-coop2mp.132`',                    # (a backslash before a pipe)
        '1 windows, 2:17 in all',
        '| KESTREL | 02:57:07 | 02:59:48 | 2:41 | WREN | - |', 'asked the host to revive player 1 for 9500',
        '| Wren | 03:05:30 | 03:05:50 | 0:20 | KESTREL | - |',
        '| 1 | Kestrel | 180 / 180 / 180 | 2 | 0 | 1 | 2 | 0 |',
        'migration: the host (Kestrel) left its run in round 6 (hl\\|left)', 'migration: KESTREL (HOST) LEFT THE RUN',
        '| 5001 | 99.9% | `[Lua] [NoisyMod] Event work complete; polling stopped` |',
        '1x AceCombat8.log: `[N]LogWindows: Error: === Critical error: ===`',
        '| board-5 | co-op | native | `coop: reliable queue to player N (...) full` | no | seen 1 (first 03:09:06) |')
    lacks('joiner', b, 'RE\\_SV\\_WolfFree', '**RE\\_SV\\_ShuttleRemove')

    # ---- both: one clock (the host's), the joiner's offset, where they disagree
    c = page('both', host, jzip)
    well_formed('both', c)
    has('both', c,
        '| Wren (joiner) | +3:00:07 | 5 round clears | 9 s | 23:49:43 [02:49:50] to 00:09:01 [03:09:08] |',
        '| 1 | 3 | 23:55:20 | 00:02:00 | 6:40 | ace squadron: Valkyrie | cleared | - | - | +9 s |',
        '| 1 | 1 | 23:51:00 | 23:52:30 | 1:30 | normal | cleared | 3 | 4 (2) | +0 s |',
        '| KESTREL | 23:57:00 [02:57:07] | 23:59:41 [02:59:48] | 2:41 | WREN | - |',
        '- round 3 cleared +9 s apart (after the offset)',
        '- Wren went down at 00:05:23 [03:05:30] on its own game; the reference shows no Wren DOWN within a minute',
        '- SV\\_SpRocketEscA 0 -> 1: at 00:04:50 on the reference, between 00:03:03 [03:03:10] and 00:03:33 [03:03:40] here',
        '| Kestrel (host) | Wren (joiner) |',
        "Kestrel (host)'s log in the window |", '| **RE\\_SV\\_AllyDefendA** |')            # (the host's events in her STORE)

    # ---- a logs folder with two sessions' zips: the newest read, the other named
    logs = os.path.join(OUT, 'logsdir')
    os.makedirs(logs, exist_ok=True)
    for fn in os.listdir(logs):
        os.remove(os.path.join(logs, fn))
    old = os.path.join(logs, 'AC8Survival_2026-11-10_18-00-00_0.74.50-coop2mp.142.zip')
    with zipfile.ZipFile(old, 'w') as z:
        z.writestr('AC8SurvivalMode_lua_2026-11-10_18-00-00.log', '18:00:01 loaded, version 0.74.50-coop2mp.142\n')
    with zipfile.ZipFile(jzip) as zi, zipfile.ZipFile(os.path.join(logs, os.path.basename(jzip)), 'w') as zo:
        for info in zi.infolist():
            zo.writestr(info, zi.read(info))
    d = page('logsdir', logs)
    has('logsdir', d, '| Wren (joiner) | joiner', 'other sessions in the bundle: 2026-11-10\\_18-00-00',
        'read from AC8Survival\\_%s\\_0.74.52-coop2mp.144.zip (the newest session zip here)' % STAMP.replace('_', '\\_'))
    outer = os.path.join(OUT, 'logs_folder_zipped.zip')                  # (a player zips the whole logs folder)
    with zipfile.ZipFile(outer, 'w') as z:
        for fn in sorted(os.listdir(logs)):
            z.write(os.path.join(logs, fn), 'logs/' + fn)
    d3 = page('zip_of_zips', outer)
    has('zip_of_zips', d3, '| Wren (joiner) | joiner', 'read from logs/AC8Survival\\_%s' % STAMP.replace('_', '\\_'),
        '| 5001 | 99.9% | `[Lua] [NoisyMod] Event work complete; polling stopped` |')
    d2 = page('logsdir_old', logs, '--session', '2026-11-10_18-00-00')
    has('logsdir_old', d2, '0.74.50-coop2mp.142', 'older than 0.74.52: none of these can be there',
        "- this build is older than 0.74.52: the checklist's lines can't be in its logs",          # (every table's)
        'older than 0.74.66: none of these can be there',
        '| lag-1 | lag | native | `units: the last minute: N SV_UnitAlive asks` | yes | not in its build |')

    # ---- a big UE4SS.log, streamed: its counts
    big = os.path.join(OUT, 'big')
    os.makedirs(big, exist_ok=True)
    with open(os.path.join(big, 'AC8SurvivalMode_lua.log'), 'w', encoding='utf-8') as f:
        f.write('10:00:00 loaded, version 0.74.52-coop2mp.144\n10:00:01 round 1: 4 aircraft: 4 fighters in 2 squadrons\n')
    with open(os.path.join(big, 'UE4SS.log'), 'wb') as f:
        line = b'[2026-11-12 10:00:00.1234567] [Lua] [Flood] Event work complete; polling stopped\r\n'
        f.write(b'[2026-11-12 10:00:00.0000000] UE4SS - v3.0.1\r\n' + line * 200000)
        f.write(b'[2026-11-12 10:30:00.0000000] [Lua] [Flood] polling 7 objects\r\n')
    t0 = time.time()
    e = page('big', big)
    has('big', e, 'UE4SS.log: 200002 lines,', '| 200000 | 100.0% | `[Lua] [Flood] Event work complete; polling stopped` |',
        'Lines by source: Flood 200001 (100.0%), UE4SS 1 (0.0%).')
    if time.time() - t0 > 30:
        fails.append('big: %.0f s for a 200,000-line UE4SS.log' % (time.time() - t0))

    cases(host, jzip)
    stream_check()
    storeq_rules()

    # ---- the checklist's lines still in the code, each regex taking its sample
    r = run('--check-anchors')
    if r.returncode or ', 0 problems' not in r.stdout:
        fails.append('--check-anchors: ' + (r.stdout + r.stderr).strip()[-400:])

    for f in fails:
        print('FAIL ' + f)
    print('log_report_test: %d failures (pages in %s)' % (len(fails), os.path.relpath(OUT, ROOT).replace(os.sep, '/')))
    return 1 if fails else 0


def cases(host, jzip):
    """the smaller made-up bundles: a solo run over midnight, a host and a joiner with long names, a fork, a joiner that
    became the host by migration, two players' folders in one bundle, damaged zips"""
    # ---- solo: the Lua log starts after the runtime log's midnight; a STORE from the minigame lines alone; kinds, runs
    e = page('solo', os.path.join(FIX, 'solo'))
    well_formed('solo', e)
    has('solo', e,
        '| 1 | 1 | 00:01:02 | 00:02:00 | 0:58 | bomber raid | cleared |',
        '| 1 | 2 | 00:02:20 | - | - | strike package | down: every player is down | 1 | 3 (3) |',   # (a cut-short round's stats)
        '| 2 | 1 | 00:04:30 | 00:05:30 | 1:00 | normal | cleared |',                                 # (a second run)
        '| 2 | 2 | 00:08:30 | 00:09:00 | 0:30 | special: alicorn (submarine contact) | cleared |',   # (its callout 160 s before)
        '| 1 | 23:59:55 | 00:00:40 | 0:45 | between | 8 deactivated 7 ends | RE\\_SV\\_AceKulbit\\_04, **RE\\_SV\\_AirfieldClose**, '
        '**RE\\_SV\\_CargoLaunch\\_1\\_4 (h)**, **RE\\_SV\\_FlightOff\\_02**, RE\\_SV\\_SpecFire\\_22A, '
        '\\~RE\\_SV\\_ShuttleRemove (not fired: -20), \\~RE\\_SV\\_ValkaTp\\_BAG (not fired) |',
        '| Solo Pilot | 00:03:05 | run over 00:03:22 | 0:17 | - | - |',
        "finished off by the carriers' ends: 2, 1 of them could not be",
        '"still has N up after 30 s" (finished off, yet up): 1 times, 2 planes in all, first 00:03:00',
        'sends 1; answers: not sent (network) 1, stored (replaced) 1, stored 1.',
        re.compile(r"^\| 1 \| lua \| 00:03:26 \| 00:03:26 \| `leaderboard: the run: the server answered -12007 \(the server's "
                   r"name didn't resolve"))
    lacks('solo', e, '| 00:05:50 |', re.compile(r'^\| 3 \| \d+ \| [0-9:]{8} \|'))      # (no third run)
    once('solo', e, '| Solo Pilot | 00:03:05 |')                       # (YOU'RE DOWN said again 15 s on: one DOWN)

    # ---- a host and a joiner with names over 14 characters and not ASCII (the callouts' names: Lua's string.upper, 14
    # characters), two players' folders in one folder and in one zip: a game each
    pair = os.path.join(FIX, 'pair')
    for nm, args in (('pair', [pair]), ('pair_zip', [zip_dir(pair, os.path.join(OUT, 'two_players.zip'))])):
        f = page(nm, *args)
        well_formed(nm, f)
        has(nm, f, 'the bundle holds the logs of 2 games', '| Wrenfield the Brave (joiner) | +1:00:00 | 5 round clears | 0 s |',
            "| ZOë ÅNGSTRöM-Ø | 10:06:00 | 10:10:02 | 4:02 | HERON | 7000 (by player 1; the run's revive 1, their 1; round 3's price) |",
            '| LONGNAME LEAVE | 10:07:00 | left the mission 10:08:00 | 1:00 | - | - |',
            '- rounds the reference started while this game was up but this game shows no start of: 2',
            'the host refused your revive of player 3 (NOT AT THE AIRFIELD): 7000 refunded',
            "no answer from the host on player 3's revive in 20 s", "player 3's revive refunded (7000): the host's link lost",
            'STORE: REVIVE ASKED FOR ZOë ÅNGSTRöM-Ø: THE HOST CONFIRMS IT.')
        lacks(nm, f, 'the reference shows no', 'ON STATION')
    f = page('pair_joiner', os.path.join(pair, 'wren'))
    has('pair_joiner', f, '| 1 | 5 | 11:14:18 | 11:16:00 | 1:42 | special: valka (hostiles inbound) | cleared |')   # (her mood)

    # ---- a fork: the player's link lost, gone, "X is also the host", back as another slot
    f = page('fork', os.path.join(FIX, 'fork'))
    has('fork', f, '- 10:05:00 Osprey (player 3): link lost', '- 10:06:20 Osprey (player 3): link gone',
        '- 10:07:00 two hosts: Osprey is also the host', '- 10:07:40 Osprey back in the room as player 4')
    f = page('rolecrash', os.path.join(FIX, 'rolecrash'))           # (a slot's role, then a takeover: no role line)
    has('rolecrash', f, '| rolecrash (joiner) | joiner (player 2; later the host by migration) |')

    # ---- 0.74.66's STOREQ (two players' folders: Vireo hosts, Linnet joins, her clock 2:00:00 ahead): the host's events
    # fired in its STORE or on the airfield before it, fired again once it's shut (took, refused, never took, a bomber
    # flight's orders given again), the joiner's held ones fired after her window (one not needed, one dropped, one behind
    # another, a shuttle second not played late), one fired late into a long STORE, an error outside any window
    f = page('storeq', os.path.join(FIX, 'storeq'))
    well_formed('storeq', f)
    has('storeq', f,
        # the windows' own table: what the lines inside say
        '| 1 | 20:03:20 | 20:04:10 | 0:50 | 2 | - | **RE\\_SV\\_AlcnRemove**, **RE\\_SV\\_AnomalyEnd**, **RE\\_SV\\_Escort\\_09** |',
        '| 1 | 20:06:00 [22:06:00] | 20:07:30 [22:07:30] | 1:30 | 3 | - | \\~RE\\_SV\\_AwacsRemove (h) (held), \\~RE\\_SV\\_Escort\\_07 (h) (held)',
        # the host's STOREQ: the one fired on the airfield before the STORE in its window, what came of each, the summary
        '| 1 | RE\\_SV\\_DirFree\\_04 to fire again (on the airfield, before the STORE); bomber flight EA\\_Unit\\_02\\_Air0 appeared '
        '(on the airfield, before the STORE): its orders read back; RE\\_SV\\_AnomalyEnd to fire again (STORE open); '
        'RE\\_SV\\_AlcnRemove to fire again (STORE open); RE\\_SV\\_Escort\\_09 to fire again (STORE open); RE\\_SV\\_WolfFree\\_05A '
        'to fire again (just after) | 20:04:13 5 to fire (AlcnRemove 1, AnomalyEnd 1, DirFree 1, Escort 1, WolfFree 1) | '
        '20:03:12 bomber flight',
        '; **20:04:13 RE\\_SV\\_Escort\\_09 not fired again here (not fired: the level is still loading)**; 20:04:16 RE\\_SV\\_AnomalyEnd took here '
        '(SV\\_AnomalyUp 0); 20:04:16 RE\\_SV\\_PressureB fired again here after RE\\_SV\\_AnomalyEnd',
        '; **20:04:22 RE\\_SV\\_AlcnRemove never took here in 3 tries (1 alive)**; 20:04:40 RE\\_SV\\_DirFree\\_04 fired again here; '
        '20:04:40 RE\\_SV\\_WolfFree\\_05A fired again here | **20:04:40 Escort (refused 1); AnomalyEnd (took 1); AlcnRemove '
        '(failed 1); DirFree (fired 1); WolfFree (fired 1)** |',
        '| - | - | - | **20:30:00 gate error \\[string "sv\\_rounds.lua"\\]:1440: attempt to compare nil with number** | - |',
        # the joiner's: held in her window, fired after it (on the host's clock, hers in brackets)
        '| 1 | RE\\_SV\\_Escort\\_07 (h) held (STORE open); RE\\_SV\\_AwacsRemove (h) held (STORE open); \\~RE\\_SV\\_ShuttleT\\_148 (h) '
        'not fired late (STORE open: nothing that lasts); RE\\_SV\\_LcacRemoveA (h) held (STORE open); RE\\_SV\\_DirFree\\_07 (h) '
        'behind what\'s held (RE\\_SV\\_Escort\\_07 still to fire here before it) | 20:07:33 [22:07:33] 3 to fire (AwacsRemove 1, '
        'Escort 1, LcacRemove 1) | 20:07:33 [22:07:33] RE\\_SV\\_AwacsRemove not fired here: its effect is in already '
        '(SV\\_AwacsAir 0); 20:07:33 [22:07:33] RE\\_SV\\_LcacRemoveA not fired here: SV\\_Unit\\_LcacA spawned again since;',
        '20:07:40 [22:07:40] RE\\_SV\\_Escort\\_07 fired here (held 90 s); 20:07:41 [22:07:41] RE\\_SV\\_DirFree\\_07 fired here (held 6 s) | '
        '20:07:41 [22:07:41] ShuttleT (dropped 1); AwacsRemove (already 1); LcacRemove (dropped 1); Escort (fired 1); DirFree (fired 1) |',
        '| 2 | RE\\_SV\\_AlcnAlertOff (h) held (STORE open) | - | **20:17:20 [22:17:20] RE\\_SV\\_AlcnAlertOff fired here 420 s after it '
        'came, this game\'s STORE still open (as before) (fired)** | **20:18:03 [22:18:03] AlcnAlertOff (late 1)** |',
        # its errors: the refusal, never took, a summary with them, the late fire and its summary, the errors; the
        # checklist's 0.74.66 table
        '`storeq: RE_SV_Escort_09 not fired again here (not fired: the level is still loading) (Escort: the first this time)`',
        '| Linnet (joiner) | 1 | lua | 20:18:03 [22:18:03] | 20:18:03 [22:18:03] | `storeq: done here: AlcnAlertOff (late 1)` |',
        '`storeq: RE_SV_AlcnRemove never took here in 3 tries (1 alive) (AlcnRemove: the first this time)`',
        '`storeq: done here: Escort (refused 1); AnomalyEnd (took 1)', "this game's STORE still open (as before) (fired) (AlcnAlertOff",
        "`coop: the STORE's held events here: error [string \"sv_rounds_store.lua\"]:530",
        '## Checklist: new log lines (0.74.52, 0.74.66)', "### 0.74.66's",
        "| storeq | STORE joiner | lua | `storeq: the host's X held here: ...; fired here once it's shut` | when | seen 4 (first 20:06:10 [22:06:10]) | not seen |",
        '| storeq | STORE | lua | `storeq: X never took here in N tries` | no | not seen | seen 1 (first 20:04:22) |',
        '| storeq | STORE bombers | lua | `storeq: bomber flight X has its orders here` | when | not seen | seen 1 (first 20:04:17) |',
        "| storeq | STORE | lua | `coop: the STORE's (check of X\\|hold here\\|held events here): error ` | no | seen 1 (first 20:25:00 [22:25:00]) | not seen |",
        '| storeq | STORE | lua | `storeq: done here: ` | when | seen 2 (first 20:07:41 [22:07:41]) | seen 1 (first 20:04:40) |',
        "| storeq | STORE joiner | lua | `storeq: X fired here N s after it came, this game's STORE still open` | no | "
        'seen 1 (first 20:17:20 [22:17:20]) | not seen |',
        '| Linnet (joiner) | +2:00:00 | 4 round clears | 0 s |')
    if f.count('STOREQ by window (- none of them):') != 2:                    # (one a game)
        fails.append('storeq: %d STOREQ tables, not 2' % f.count('STOREQ by window (- none of them):'))
    lacks('storeq', f, 'older than 0.74.66', 'not in its build |',
          '`storeq: RE_SV_AwacsRemove not fired here', "`storeq: RE_SV_AlcnRemove didn't take here", '`storeq: done here: ShuttleT',
          "`storeq: the host's RE_SV_ShuttleT_148", '`storeq: RE_SV_LcacRemoveA not fired here')      # (routine: not errors)

    nowin = os.path.join(OUT, 'storeq_nowin')
    shutil.rmtree(nowin, ignore_errors=True)
    os.makedirs(nowin)
    with open(os.path.join(FIX, 'storeq', 'vireo', 'AC8SurvivalMode_lua.log'), encoding='utf-8') as a, \
            open(os.path.join(nowin, 'AC8SurvivalMode_lua.log'), 'w', encoding='utf-8', newline='\n') as b:
        b.write(''.join(x for x in a if ' music: ' not in x))
    f = page('storeq_nowin', nowin)
    well_formed('storeq_nowin', f)
    has('storeq_nowin', f, 'No STORE window.\n\nSTOREQ by window (- none of them):\n\n| # |',
        '| - | RE\\_SV\\_DirFree\\_04 to fire again (on the airfield, before the STORE); ',
        '**20:30:00 gate error \\[string "sv\\_rounds.lua"\\]:1440: attempt to compare nil with number** | ')
    m = re.search(r'STOREQ by window \(- none of them\):\n\n\|[^\n]*\n\|[^\n]*\n((?:\|[^\n]*\n)*)', f)
    if not m or [x[:4] for x in m.group(1).splitlines()] != ['| - ']:
        fails.append('storeq_nowin: its STOREQ table is not the one row -')

    # ---- a joiner that became the host by migration and started rounds: its joiner rounds kept, the same run
    mig = os.path.join(OUT, 'migrated')
    shutil.rmtree(mig, ignore_errors=True)
    shutil.copytree(os.path.join(FIX, 'joiner'), mig)
    with open(os.path.join(mig, 'AC8SurvivalMode_lua_%s.log' % STAMP), 'a', encoding='utf-8', newline='\n') as fh:
        fh.write('03:09:30 round 6: 20 aircraft: 20 fighters in 10 squadrons; cap 60, up to 30 at once\n'
                 '03:12:00 round 6 clear; round 7 in 20 s\n'
                 '03:12:20 round 7: 22 aircraft: 22 fighters in 11 squadrons; cap 60, up to 30 at once\n')
    f = page('migrated', mig)
    has('migrated', f, "| Wren (joiner) | joiner (in the host's co-op run 5eed1234; later the host by migration) |",
        '| 1 | 1 | 02:51:07 | 02:52:37 | 1:30 | normal | cleared |', '| 1 | 6 | 03:07:58 | - | - | normal | not cleared (host migration) |',
        '| 1 | 6 | 03:09:30 | 03:12:00 | 2:30 | normal | cleared |', '| 1 | 7 | 03:12:20 | - | - | normal | not cleared (the log ends) |',
        '| 3 | ace squadron: Valkyrie | - | - | - | - | - | - | 20-20 | 400 | 5 | - |')
    lacks('migrated', f, re.compile(r'^\| 2 \| \d+ \| [0-9:]{8} \|'))
    f = page('both_migrated', host, mig)
    has('both_migrated', f, '| 1 | 1 | 23:51:00 | 23:52:30 | 1:30 | normal | cleared | 3 | 4 (2) | +0 s |')
    lacks('both_migrated', f, 'shows no start of')

    # ---- damaged zips: a cut session zip, a zip whose deflate stream is broken: a page that says so, no traceback
    cut = os.path.join(OUT, 'AC8Survival_%s_cut.zip' % STAMP)
    with open(jzip, 'rb') as a, open(cut, 'wb') as b:
        data = a.read()
        b.write(data[:len(data) // 2])
    has('cut', page('cut', cut), 'is not a readable zip (cut or damaged)')
    bad = os.path.join(OUT, 'bad_deflate.zip')
    with zipfile.ZipFile(bad, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('AC8SurvivalMode_lua.log', ''.join('10:%02d:00 loaded, version 0.74.52-coop2mp.144\n' % i for i in range(60)))
    with zipfile.ZipFile(bad) as z:
        i = z.infolist()[0]
    with open(bad, 'r+b') as fh:                    # (its first deflate block's type made 3: zlib's "invalid block type")
        fh.seek(i.header_offset + 26)
        n, m = [int.from_bytes(fh.read(2), 'little') for _ in range(2)]
        fh.seek(i.header_offset + 30 + n + m)
        fh.write(b'\xff')
    has('bad_deflate', page('bad_deflate', bad), 'AC8SurvivalMode\\_lua.log could not be read to its end (error)')


def storeq_rules():
    """0.74.66's checklist, the Errors section and the STOREQ table say the same: a row's sample is counted in Errors and
    bold in the table when its expect is no (a sign of trouble), and only then; a summary (a when row, whatever it holds)
    when a failure, refusal or late fire is in it"""
    sys.path.insert(0, os.path.join(ROOT, 'tools'))
    import log_report as L
    import log_report_page as P

    def counted(x):
        return bool(L.ISSUE.search(x)) and not L.NOT_ISSUE.search(x)
    for c in L.CHECKS_0_74_66:
        x, bad = c[5], c[6] == 'no'
        if x.startswith('storeq: done here: '):
            continue
        if counted(x) != bad:
            fails.append('storeq rules: %s in Errors, its row expects %s: %s' % ('counted' if counted(x) else 'not counted', c[6], x[:90]))
        if x.startswith('storeq: ') and bool(P.SQ_TROUBLE.search(x)) != bad:
            fails.append('storeq rules: %s in the STOREQ table, its row expects %s: %s' % ('bold' if not bad else 'not bold', c[6], x[:90]))
    for x, bad in [('storeq: done here: AlcnAlertOff (late 1)', True), ('storeq: done here: Escort (refused 1); DirFree (fired 1)', True),
                   ('storeq: done here: AlcnRemove (failed 1)', True), ('storeq: done here: ShuttleT (dropped 1); AwacsRemove '
                   '(already 1); HeavyRoute (unread 1); AnomalyEnd (took 1); Escort (fired 1)', False)]:
        if counted(x) != bad:
            fails.append('storeq rules: the summary %r %s in Errors' % (x, 'not counted' if bad else 'counted'))


def stream_check():
    """scan_ue4ss on a 200,000-line UE4SS.log made line by line: counted right, and never held whole (its peak memory)"""
    sys.path.insert(0, os.path.join(ROOT, 'tools'))
    import log_report as L
    line = b'[2026-11-12 10:00:00.1234567] [Lua] [Flood] Event work complete; polling stopped\r\n'

    class Lines:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def __iter__(self):
            for _ in range(200000):
                yield line

        def read(self, n=-1):                       # (a whole read: what the check is there to catch)
            return b''.join(self)[:None if n is None or n < 0 else n]
    g = L.Game(L.Bundle('x'), 0)
    tracemalloc.start()
    g.scan_ue4ss(L.Src('UE4SS.log', len(line) * 200000, Lines))
    peak = tracemalloc.get_traced_memory()[1]
    tracemalloc.stop()
    if g.ue['lines'] != 200000:
        fails.append('stream: %d lines counted, not 200000' % g.ue['lines'])
    if peak > 4 << 20:
        fails.append('stream: UE4SS.log held whole (peak %.1f MB for a 16 MB file)' % (peak / 1048576.0))


if __name__ == '__main__':
    sys.exit(main())
