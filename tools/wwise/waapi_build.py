"""waapi_build.py : Survival's own Wwise objects in the sound project (AC8_WWISE_PROJECT's Wwise project), through
WAAPI over local HTTP (Python's standard library only; WwiseConsole waapi-server --http-port PORT must be running).

    python -I tools/wwise/waapi_build.py <port> <spec.json> [--wait] [--bank NAME | --bank-each]
    --wait: wait up to 60 s for the server; --bank: every event into that SoundBank, generated for Windows;
    --bank-each: each event its own SoundBank (SVB_<event>), any other bank of the Default Work Unit deleted
    ((2026-11-24) each cooked event asset carries the whole bank its event is in: six events in one 9.4 MB bank made a
    56 MB container; a bank each, each asset carries its own media only)

spec.json (machine paths stay out of the repo: the spec is written per run, sources from .env's folders):
    {"bus": "sfx",
     "units_per_m": 10,
     "attenuations": [{"name": "SV_Att_Far", "radius_m": 3000, "curve": [[0, 0], [500, -10], [1500, -25], [3000, -200]]}],
     "sounds": [{"name": "SV_SolgBreakBig", "wav": "<path>", "attenuation": "SV_Att_Far", "volume": 0},
                {"name": "SV_UlyAmbient", "wav": "<path>", "positioning": "2d", "loop": true, "volume": -12}],
     "events": [{"name": "Play_SV_SolgBreakBig", "play": "SV_SolgBreakBig"}]}

The bus is named as AC8's own (Init.bnk: Master Audio Bus > PreMaster > sfx, id 393239870 = FNV-1 of "sfx"): Wwise
IDs are hashes of names, so a sound routed to our "sfx" plays on the game's sfx bus (the effects volume) and our banks
never ship an Init.bnk of their own. A sound is 3D (position from the emitter, listener relative, with its attenuation)
unless "positioning": "2d" (the speakers as it is: no position, no attenuation); "loop": true loops it until stopped.
(2026-11-24) ListenerRelativeRouting is written either way, never left to Wwise's default (the 0.75.66 SOLG test: "doesnt
sound like the solg noise gets further from me").
Distances: metres in the spec, written as metres x units_per_m (default 100: UE centimetres). AC8's listener scales every
attenuation by 10 (DefaultListenerScalingFactor=10 in its Live/Config/DefaultGame.ini: a curve's distances are 10x on
the ground), so AC8's units_per_m is 10 (the ulysound autotest of 0.75.103: written in centimetres, an impact meant to be
silent at 15 km was as loud at 16 km as at 0.3 km). radius_m (or radius_max, in Wwise units) is the curve's end.
"""
import json
import sys
import time
import urllib.request

PORT, SPEC = int(sys.argv[1]), json.load(open(sys.argv[2], encoding='utf-8'))
BANK = sys.argv[sys.argv.index('--bank') + 1] if '--bank' in sys.argv else None
EACH = '--bank-each' in sys.argv
UPM = float(SPEC.get('units_per_m', 100))                # (Wwise units a metre on the ground: AC8's 10, see above)


def call(uri, args=None, options=None):
    body = json.dumps({'uri': uri, 'args': args or {}, 'options': options or {}}).encode()
    req = urllib.request.Request('http://127.0.0.1:%d/waapi' % PORT, data=body, headers={'Content-Type': 'application/json'})
    try:
        return json.load(urllib.request.urlopen(req, timeout=60))
    except urllib.error.HTTPError as e:
        sys.exit('%s failed: %s' % (uri, e.read().decode('utf-8', 'replace')[:600]))


def first(waql):
    r = call('ak.wwise.core.object.get', {'waql': waql}, {'return': ['id', 'name', 'path', 'type']})['return']
    return r[0] if r else None


if '--wait' in sys.argv:
    for _ in range(30):
        try:
            call('ak.wwise.core.getInfo'); break
        except (OSError, SystemExit):
            time.sleep(2)
master = first('$ from type Bus where name = "Master Audio Bus"')
bus = call('ak.wwise.core.object.create', {'parent': master['id'], 'type': 'Bus', 'name': SPEC['bus'], 'onNameConflict': 'merge'})
print('bus', SPEC['bus'], bus['id'], 'under', master['path'])
amh = first('$ from type WorkUnit where name = "Default Work Unit" and parent.name = "Actor-Mixer Hierarchy"') \
    or first('$ from type WorkUnit where name = "Default Work Unit" and parent.name = "Containers"')
atw = first('$ from type WorkUnit where name = "Default Work Unit" and parent.name = "Attenuations"')
evw = first('$ from type WorkUnit where name = "Default Work Unit" and parent.name = "Events"')
att = {}
for a in SPEC.get('attenuations', []):
    o = call('ak.wwise.core.object.create', {'parent': atw['id'], 'type': 'Attenuation', 'name': a['name'], 'onNameConflict': 'merge'})
    radius = a['radius_m'] * UPM if 'radius_m' in a else a['radius_max']
    call('ak.wwise.core.object.setProperty', {'object': o['id'], 'property': 'RadiusMax', 'value': radius})
    if a.get('curve'):                                   # [[metres, dB], ...]: the volume over distance (game units = cm)
        pts = [{'x': m * UPM, 'y': db, 'shape': 'Linear'} for m, db in a['curve']]
        call('ak.wwise.core.object.setAttenuationCurve', {'object': o['id'], 'curveType': 'VolumeDryUsage', 'use': 'Custom',
                                                         'points': pts})
    att[a['name']] = o['id']
    print('attenuation', a['name'], o['id'], 'radius %.0f units (%.0f m at %g units a metre)' % (radius, radius / UPM, UPM))
snd = {}
for s in SPEC.get('sounds', []):
    r = call('ak.wwise.core.audio.import', {'importOperation': 'useExisting', 'default': {'importLanguage': 'SFX'},
                                             'imports': [{'audioFile': s['wav'], 'objectPath': amh['path'] + '\\<Sound SFX>' + s['name']}]},
             {'return': ['id', 'name', 'type']})
    o = next(x for x in r['objects'] if x.get('type') == 'Sound')
    sid = o['id']
    call('ak.wwise.core.object.setReference', {'object': sid, 'reference': 'OutputBus', 'value': bus['id']})
    call('ak.wwise.core.object.setProperty', {'object': sid, 'property': 'OverridePositioning', 'value': True})
    flat = s.get('positioning') == '2d'
    call('ak.wwise.core.object.setProperty', {'object': sid, 'property': 'ListenerRelativeRouting', 'value': not flat})
    call('ak.wwise.core.object.setProperty', {'object': sid, 'property': '3DSpatialization', 'value': 0 if flat else 1})  # (position)
    call('ak.wwise.core.object.setProperty', {'object': sid, 'property': 'EnableAttenuation', 'value': bool(s.get('attenuation')) and not flat})
    if s.get('attenuation') and not flat:
        call('ak.wwise.core.object.setReference', {'object': sid, 'reference': 'Attenuation', 'value': att[s['attenuation']]})
    call('ak.wwise.core.object.setProperty', {'object': sid, 'property': 'IsLoopingEnabled', 'value': bool(s.get('loop'))})
    if s.get('loop'):
        call('ak.wwise.core.object.setProperty', {'object': sid, 'property': 'IsLoopingInfinite', 'value': True})
    call('ak.wwise.core.object.setProperty', {'object': sid, 'property': 'Volume', 'value': float(s.get('volume', 0))})
    snd[s['name']] = sid
    print('sound', s['name'], sid, '-> bus', SPEC['bus'], '2d' if flat else '3d', 'loop' if s.get('loop') else 'once',
          '%+.0f dB' % float(s.get('volume', 0)))
for e in SPEC.get('events', []):
    # (kept, never replaced: a new GUID orphans its Unreal asset, which reconcile then refuses to overwrite)
    have = first('$ from type Event where name = "%s"' % e['name'])
    if have:
        o = have
        acts = call('ak.wwise.core.object.get', {'from': {'id': [o['id']]}, 'transform': [{'select': ['children']}]},
                    {'return': ['id']})['return']
        for a in acts:
            call('ak.wwise.core.object.setReference', {'object': a['id'], 'reference': 'Target', 'value': snd[e['play']]})
    else:
        o = call('ak.wwise.core.object.create', {'parent': evw['id'], 'type': 'Event', 'name': e['name'], 'onNameConflict': 'fail',
                                                 'children': [{'type': 'Action', 'name': '', '@ActionType': 1, '@Target': snd[e['play']]}]})
    print('event', e['name'], o['id'], 'plays', e['play'])
BANKS = []
if BANK or EACH:
    sbw = first('$ from type WorkUnit where name = "Default Work Unit" and parent.name = "SoundBanks"')
    plan = [('SVB_' + e['name'], [e]) for e in SPEC.get('events', [])] if EACH else [(BANK, SPEC.get('events', []))]
    keep = {name for name, _ in plan}
    if EACH:                                             # (no event in two banks: an old shared one goes)
        have = call('ak.wwise.core.object.get', {'from': {'id': [sbw['id']]}, 'transform': [{'select': ['children']}]},
                    {'return': ['id', 'name', 'type']})['return']
        for b in have:
            if b.get('type') == 'SoundBank' and b['name'] not in keep:
                call('ak.wwise.core.object.delete', {'object': b['id']})
                print('bank', b['name'], 'deleted (a bank each now)')
    for name, evs in plan:
        bank = call('ak.wwise.core.object.create', {'parent': sbw['id'], 'type': 'SoundBank', 'name': name, 'onNameConflict': 'merge'})
        for e in evs:
            ev = first('$ from type Event where name = "%s"' % e['name'])
            call('ak.wwise.core.soundbank.setInclusions', {'soundbank': bank['id'], 'operation': 'add',
                                                           'inclusions': [{'object': ev['id'], 'filter': ['events', 'structures', 'media']}]})
        BANKS.append(name)
call('ak.wwise.core.project.save')
print('saved')
if BANKS:
    call('ak.wwise.core.soundbank.generate', {'soundbanks': [{'name': b} for b in BANKS], 'platforms': ['Windows'], 'writeToDisk': True})
    print('generated', ', '.join(BANKS))
