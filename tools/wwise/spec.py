"""spec.py : Survival's own Wwise sounds, the spec tools/wwise/build.sh hands waapi_build.py (2026-11-24).
    python -I tools/wwise/spec.py [out.json]      (default build/wwise/spec.json; prints what it left out and why)
The sources stay outside git: the SOLG's test sound in the sound project's Sources folder (AC8_WWISE_PROJECT, .env),
ULYSSES' in build/ulysses/sounds (python tools/ulysses/sounds.py: AC:I's Stardust set, the user's exception of
2026-11-23). Distances in metres on the ground: AC8's Wwise units are UE centimetres, but its listener scales every
attenuation by 10 (DefaultListenerScalingFactor=10, its Live/Config/DefaultGame.ini), so a metre is 10 units
(UNITS_PER_M; the ulysound autotest of 0.75.103 heard centimetre curves 10x too wide). Volumes start from the mix Survival's XAudio2 player gave ULYSSES (its master
-24 dB plus each sound's dB in sv_config_arc.lua's specials.ulysses.sounds), now on AC8's sfx bus (the effects volume).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import env                                               # (tools/env.py: .env's settings)

REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
ULY = os.path.join(REPO, 'build', 'ulysses', 'sounds')

UNITS_PER_M = 10
ATTENUATIONS = [
    # (the SOLG's test of 2026-11-23: a 3 km fade)
    {'name': 'SV_Att_Far', 'radius_m': 3000, 'curve': [[0, 0], [500, -10], [1500, -25], [3000, -200]]},
    # ULYSSES: a fragment's whistle heard from ~7 km, the core's and the impacts' from 15-20 km
    {'name': 'SV_Att_UlyFall', 'radius_m': 7000, 'curve': [[0, 0], [800, -6], [2500, -18], [5000, -36], [7000, -200]]},
    {'name': 'SV_Att_UlyFallBig', 'radius_m': 20000, 'curve': [[0, 0], [2500, -6], [7000, -18], [14000, -36], [20000, -200]]},
    {'name': 'SV_Att_UlyBoom', 'radius_m': 15000, 'curve': [[0, 0], [1500, -6], [5000, -18], [11000, -36], [15000, -200]]},
]
# (name, source, settings): the event is Play_<name without SV_>, as Play_SV_<...>
SOUNDS = [
    ('SV_SolgBreakBig', ('project', 'Sources/SV_SolgBreakBig.wav'), {'attenuation': 'SV_Att_Far'}),
    ('SV_UlyFall', ('ulysses', 'fall_small.wav'), {'attenuation': 'SV_Att_UlyFall', 'loop': True, 'volume': -20}),
    ('SV_UlyFallBig', ('ulysses', 'fall_big.wav'), {'attenuation': 'SV_Att_UlyFallBig', 'loop': True, 'volume': -16}),
    ('SV_UlyBoom', ('ulysses', 'explosion.wav'), {'attenuation': 'SV_Att_UlyBoom', 'volume': -18}),
    ('SV_UlyEncounter', ('ulysses', 'encounter.wav'), {'positioning': '2d', 'volume': -24}),
    ('SV_UlyAmbient', ('ulysses', 'ambient.wav'), {'positioning': '2d', 'loop': True, 'volume': -27}),
]


def main(out):
    project = env.need('AC8_WWISE_PROJECT', "Survival's sound project (AC8Sound.uproject with the Wwise 2024.1.11 plugin)")
    roots = {'project': project, 'ulysses': ULY}
    sounds, events, left = [], [], []
    for name, (root, rel), settings in SOUNDS:
        wav = os.path.join(roots[root], rel)
        if not os.path.isfile(wav):
            left.append('%s (no %s)' % (name, wav))
            continue
        sounds.append(dict({'name': name, 'wav': wav.replace('\\', '/')}, **settings))
        events.append({'name': 'Play_' + name, 'play': name})
    used = {s.get('attenuation') for s in sounds}
    spec = {'bus': 'sfx', 'units_per_m': UNITS_PER_M, 'attenuations': [a for a in ATTENUATIONS if a['name'] in used],
            'sounds': sounds, 'events': events}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(spec, f, indent=1)
    print('wwise spec: %d sounds, %d events -> %s' % (len(sounds), len(events), out))
    for x in left:
        print('wwise spec: left out', x)
    return 0 if sounds else 1


if __name__ == '__main__':
    sys.exit(main(os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(REPO, 'build', 'wwise', 'spec.json')))
