"""waapi_build.py : Survival's own Wwise objects in the sound project (AC8_WWISE_PROJECT's Wwise project), through
WAAPI over local HTTP (Python's standard library only; WwiseConsole waapi-server --http-port PORT must be running).

    python -I tools/wwise/waapi_build.py <port> <spec.json> [--wait] [--bank NAME]
    --wait: wait up to 60 s for the server; --bank: every event into that SoundBank, generated for Windows

spec.json (machine paths stay out of the repo: the spec is written per run, sources from .env's folders):
    {"bus": "sfx",
     "attenuations": [{"name": "SV_Att_Far", "radius_max": 300000, "curve": [[0, 0], [500, -10], [1500, -25], [3000, -200]]}],
     "sounds": [{"name": "SV_SolgBreakBig", "wav": "<path>", "attenuation": "SV_Att_Far", "volume": 0}],
     "events": [{"name": "Play_SV_SolgBreakBig", "play": "SV_SolgBreakBig"}]}

The bus is named as AC8's own (Init.bnk: Master Audio Bus > PreMaster > sfx, id 393239870 = FNV-1 of "sfx"): Wwise
IDs are hashes of names, so a sound routed to our "sfx" plays on the game's sfx bus (the effects volume) and our banks
never ship an Init.bnk of their own. Every object is 3D (position from the emitter) with its attenuation.
"""
import json
import sys
import time
import urllib.request

PORT, SPEC = int(sys.argv[1]), json.load(open(sys.argv[2], encoding='utf-8'))
BANK = sys.argv[sys.argv.index('--bank') + 1] if '--bank' in sys.argv else None


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
    call('ak.wwise.core.object.setProperty', {'object': o['id'], 'property': 'RadiusMax', 'value': a['radius_max']})
    if a.get('curve'):                                   # [[metres, dB], ...]: the volume over distance (game units = cm)
        pts = [{'x': m * 100.0, 'y': db, 'shape': 'Linear'} for m, db in a['curve']]
        call('ak.wwise.core.object.setAttenuationCurve', {'object': o['id'], 'curveType': 'VolumeDryUsage', 'use': 'Custom',
                                                         'points': pts})
    att[a['name']] = o['id']
    print('attenuation', a['name'], o['id'], 'radius', a['radius_max'])
snd = {}
for s in SPEC.get('sounds', []):
    r = call('ak.wwise.core.audio.import', {'importOperation': 'useExisting', 'default': {'importLanguage': 'SFX'},
                                             'imports': [{'audioFile': s['wav'], 'objectPath': amh['path'] + '\\<Sound SFX>' + s['name']}]},
             {'return': ['id', 'name', 'type']})
    o = next(x for x in r['objects'] if x.get('type') == 'Sound')
    sid = o['id']
    call('ak.wwise.core.object.setReference', {'object': sid, 'reference': 'OutputBus', 'value': bus['id']})
    call('ak.wwise.core.object.setProperty', {'object': sid, 'property': 'OverridePositioning', 'value': True})
    call('ak.wwise.core.object.setProperty', {'object': sid, 'property': '3DSpatialization', 'value': 1})   # (position)
    if s.get('attenuation'):
        call('ak.wwise.core.object.setProperty', {'object': sid, 'property': 'EnableAttenuation', 'value': True})
        call('ak.wwise.core.object.setReference', {'object': sid, 'reference': 'Attenuation', 'value': att[s['attenuation']]})
    if s.get('volume'):
        call('ak.wwise.core.object.setProperty', {'object': sid, 'property': 'Volume', 'value': s['volume']})
    snd[s['name']] = sid
    print('sound', s['name'], sid, '-> bus', SPEC['bus'])
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
if BANK:
    sbw = first('$ from type WorkUnit where name = "Default Work Unit" and parent.name = "SoundBanks"')
    bank = call('ak.wwise.core.object.create', {'parent': sbw['id'], 'type': 'SoundBank', 'name': BANK, 'onNameConflict': 'merge'})
    for e in SPEC.get('events', []):
        ev = first('$ from type Event where name = "%s"' % e['name'])
        call('ak.wwise.core.soundbank.setInclusions', {'soundbank': bank['id'], 'operation': 'add',
                                                       'inclusions': [{'object': ev['id'], 'filter': ['events', 'structures', 'media']}]})
call('ak.wwise.core.project.save')
print('saved')
if BANK:
    call('ak.wwise.core.soundbank.generate', {'soundbanks': [{'name': BANK}], 'platforms': ['Windows'], 'writeToDisk': True})
    print('generated', BANK)
