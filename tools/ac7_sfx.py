"""Extract Ace Combat 7 Wwise sound effects (Mihaly's EML, Mission 18) into plain WAVs, with their playback settings.

    python -I tools/ac7_sfx.py [--events NAME[=role],...] [--out build/ac7/sfx]

Reads only (never writes) the AC7 Wwise data:
  --xml   wwiser dump of game_se.bnk (HIRC by numeric ID)  default D:/Ace Combat PAKS/bnk's/Windows/game_se.bnk.xml
  --bnk   game_se.bnk (DIDX/DATA: in-bank media)            default next to the xml
  --pck   game_se.pck (AKPK: streamed media)                default next to the xml
  --alt   other game_se.bnk builds to compare object bytes  default the "Music Banks and Sound Effects AC7" copy
  --vgm   vgmstream-cli.exe (decodes .wem to .wav)          default E:/DOWNLOADS/Output/.data/vgmstream-cli.exe

Writes, under --out (git-ignored build/ac7/sfx):
  <EVENT>/<role>_<wemid>.wav   decoded media, one per distinct source (a looping source also gets a smpl chunk)
  <EVENT>/wem/<wemid>.wem      the raw Wwise media as stored
  <EVENT>/TREE.txt             event -> actions -> containers -> sounds, every node's own settings, then each sound's
                               full parent chain and its effective (summed) volume / pitch / attenuation / RTPCs
  summary.json                 the same, machine readable
NOTES.md next to them is written by hand from these files.

Wwise event IDs are FNV-1 (32-bit) of the lower-cased event name. Names that have no AkAudioEvent asset in the AC7
exports (CHARGE, CHARGE_END, AIMING_START, SPWP_OTH_EML_HIT, ...) were found by hashing guesses; the hash matching an
event ID in the bank is the proof.
"""
import argparse, array, json, math, os, struct, subprocess, sys, wave
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding='utf-8')

BNKDIR = "D:/Ace Combat PAKS/bnk's/Windows"
ALT_BNK = "D:/Ace Combat PAKS/Music Banks and Sound Effects AC7/Windows/game_se.bnk"
VGM = 'E:/DOWNLOADS/Output/.data/vgmstream-cli.exe'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'ac7', 'sfx')

# event name = role (file-name prefix). The first four are what wp_eml names; the rest are related events in the
# same bank (found by hash), extracted for completeness.
EVENTS = [
    ('OBJ_M18_MIHAI_SHOT', 'shot'),
    ('OBJ_M18_MIHAI_BULLET', 'flyloop'),
    ('OBJ_M18_MIHAI_BULLET_Stop', 'flyloop_stop'),
    ('OBJ_M18_MIHAI_BULLET_PASS', 'pass'),
    ('SPWP_OTH_EML_HIT', 'hit'),               # most likely SoundChannelType::EMLHit (see NOTES.md)
    ('SPWP_OTH_EML_SHOOT', 'player_shot'),
    ('SPWP_OTH_EML_PASS', 'player_pass'),
    ('SPWP_OTH_EML_PASS_Stop', 'player_pass_stop'),
    ('OBJ_M18_MIHAI_CHARGE', 'charge'),
    ('OBJ_M18_MIHAI_CHARGE_Stop', 'charge_stop'),
    ('OBJ_M18_MIHAI_CHARGE_END', 'charge_end'),
    ('OBJ_M18_MIHAI_AIMING_START', 'aiming'),
    ('OBJ_M18_MIHAI_CANCEL_STEAM_HIT', 'cancel_steam_hit'),
]

# CAkAttenuation curveToUse[] slots (bank v125 / Wwise 2017.x)
CURVE_SLOTS = ['VolumeDry', 'VolumeWetGame', 'VolumeWetUser', 'LowPassFilter', 'HighPassFilter', 'Spread', 'Focus']
SUM_PROPS = ('Volume', 'MakeUpGain', 'Pitch', 'LPF', 'HPF')
KNOWN_NAMES = {393239870: 'SFX', 438105790: 'Outside'}   # bus names recovered by hashing guesses

# file-name labels by sound or direct parent node (see NOTES.md for what each one is)
LABELS = {
    786956285: 'main',           # SHOT action 1: the shot's own sound
    37005031: 'whoosh',          # SHOT layer / BULLET_PASS target: random 1 of 6, +900 cents, flanger
    79729378: 'eml', 330201606: 'eml', 430331784: 'eml',   # SHOT layers shared with the player's EML shot
    823797498: 'far',            # SHOT layer with its own 2.5 km attenuation and bus
    656492147: 'near', 635617960: 'mid', 731998548: 'midfar', 63474965: 'far',   # EML_HIT distance layers
    1013348578: 'loop', 1009340048: 'start',                # CHARGE
}

# fields left out of TREE.txt: always the same / defaults that say nothing about the sound
NOISE = {'eHircType', 'dwSectionSize', 'bIsOverrideParentFX', 'uNumFx', 'bOverrideAttachmentParams',
         'eVirtualQueueBehavior', 'eBelowThresholdBehavior', 'ulNumStateProps', 'ulNumStateGroups', 'uSourceBits',
         'idExt_4', 'cProps', 'ulNumRTPC', 'ulNumChilds', 'ulPlayListItem', 'ulActionListSize', 'ulSize', 'NumCurves',
         'bitsFXBypass', 'uFXIndex'}


def fnv1(name):
    h = 2166136261
    for b in name.lower().encode():
        h = ((h * 16777619) & 0xffffffff) ^ b
    return h


# ---------------------------------------------------------------- wwiser xml

def load_xml(path):
    txt = open(path, encoding='utf-8').read()
    root = ET.fromstring(txt[txt.index('<base>'):txt.index('</base>') + 7])
    objs = {}
    for o in root.iter('obj'):
        if not o.get('na', '').startswith('CAk'):
            continue
        for f in o.findall('fld'):
            if f.get('na') == 'ulID':
                objs[int(f.get('va'))] = o
                break
    return objs


def fv(o, name, cast=int):
    for f in o.iter('fld'):
        if f.get('na') == name:
            v = f.get('va')
            return cast(float(v)) if cast is int and '.' in v else cast(v)
    return None


def bracket(f):
    vf = f.get('vf', '')
    return vf[vf.index('[') + 1:vf.rindex(']')] if '[' in vf else f.get('va')


def children(o):
    return [int(f.get('va')) for c in o.iter('obj') if c.get('na') == 'Children'
            for f in c.findall('fld') if f.get('na') == 'ulChildID']


def props(o):
    """(plain {name: value}, ranged {name: (min, max)}) of a node's own NodeInitialParams / action params."""
    plain, ranged = {}, {}
    for b in o.iter('obj'):
        na = b.get('na', '')
        if na == 'Children':
            break
        if not na.startswith('AkPropBundle<'):
            continue
        for e in b.iter('obj'):
            if e is b:
                continue
            pid = e.find("fld[@na='pID']")
            if pid is None:
                continue
            name = bracket(pid)
            if na.startswith('AkPropBundle<RANGED'):
                ranged[name] = (float(e.find("fld[@na='min']").get('va')), float(e.find("fld[@na='max']").get('va')))
            else:
                plain[name] = float(e.find("fld[@na='pValue']").get('va'))
    return plain, ranged


def graph(c):
    return [(float(p.find("fld[@na='From']").get('va')), float(p.find("fld[@na='To']").get('va')),
             bracket(p.find("fld[@na='Interp']"))) for p in c.iter('obj') if p.get('na') == 'AkRTPCGraphPoint']


def rtpcs(o):
    out = []
    for r in o.iter('obj'):
        if r.get('na') != 'RTPC':
            continue
        out.append({'rtpc_id': fv(r, 'RTPCID'), 'type': bracket(r.find("fld[@na='rtpcType']")),
                    'accum': bracket(r.find("fld[@na='rtpcAccum']")), 'param': bracket(r.find("fld[@na='ParamID']")),
                    'scaling': bracket(r.find("fld[@na='eScaling']")), 'points': graph(r)})
        if out[-1]['scaling'] == 'dB':
            out[-1]['points_db'] = [(x, round(lin_db(y), 2), i) for x, y, i in out[-1]['points']]
    return out


def lin_db(v):
    """dB-scaled curves store a symmetric linear value: v <= 0 is gain - 1 (0 = 0 dB, -1 = silence; an attenuation
    stores -0.87410748 = -18.00 dB exactly), v > 0 is 1 - 1 / gain (a Volume RTPC stores 0.49881276 = +6.00 dB)."""
    if v <= -1:
        return float('-inf')
    if v <= 0:
        return 20 * math.log10(1.0 + v)
    return float('inf') if v >= 1 else -20 * math.log10(1.0 - v)


def attenuation(objs, aid):
    o = objs.get(aid)
    if o is None:
        return {'id': aid, 'missing': True}
    use = [int(f.get('va')) for f in o.iter('fld') if f.get('na', '').startswith('curveToUse')]
    tables = [t for t in o.iter('obj') if t.get('na') == 'CAkConversionTable']
    curves = {}
    for slot, idx in zip(CURVE_SLOTS, use):
        if idx < 0:
            continue
        t = tables[idx]
        sc = bracket(t.find("fld[@na='eScaling']"))
        pts = graph(t)
        c = {'curve': idx, 'scaling': sc, 'points': pts}
        if sc == 'dB':
            c['points_db'] = [(x, round(lin_db(y), 2), i) for x, y, i in pts]
        curves[slot] = c
    a = {'id': aid, 'cone': fv(o, 'bIsConeEnabled'), 'curves': curves, 'rtpcs': rtpcs(o),
         'max_distance': max((p[0] for c in curves.values() for p in c['points']), default=None)}
    if a['cone']:
        a['cone_params'] = {f.get('na'): f.get('va') for f in o.iter('fld') if f.get('na', '').startswith(('fInsideDegrees', 'fOutsideDegrees', 'fOutsideVolume', 'LoPass', 'HiPass'))}
    return a


def node_info(objs, nid):
    o = objs.get(nid)
    if o is None:
        return {'id': nid, 'type': 'MISSING'}
    plain, ranged = props(o)
    d = {'id': nid, 'type': o.get('na'), 'props': plain, 'ranged': ranged, 'parent': fv(o, 'DirectParentID'),
         'bus': fv(o, 'OverrideBusId'), 'pos_override': fv(o, 'bPositioningInfoOverrideParent'),
         'attenuation_id': fv(o, 'uAttenuationID'), 'rtpcs': rtpcs(o),
         'fx': [fv(c, 'fxID') for c in o.iter('obj') if c.get('na') == 'FXChunk'],
         'state_groups': [fv(c, 'ulStateGroupID') for c in o.iter('obj') if c.get('na') == 'AkStateGroupChunk']}
    sp = o.find(".//fld[@na='eSpatializationMode']")
    if sp is not None:
        d['spatialization'] = bracket(sp)
    if o.get('na') == 'CAkSound':
        d['source'] = {'plugin': bracket(o.find(".//fld[@na='ulPluginID']")),
                       'stream': bracket(o.find(".//fld[@na='StreamType']")),
                       'wem': fv(o, 'sourceID'), 'size': fv(o, 'uInMemoryMediaSize')}
        d['loop'] = plain.get('Loop', 1)
    if o.get('na') == 'CAkRanSeqCntr':
        for k in ('sLoopCount', 'sLoopModMin', 'sLoopModMax', 'fTransitionTime', 'wAvoidRepeatCount'):
            d[k] = fv(o, k, float if k.startswith('f') else int)
        for k in ('eTransitionMode', 'eRandomMode', 'eMode'):
            d[k] = bracket(o.find(".//fld[@na='%s']" % k))
        d['playlist'] = [(fv(i, 'ulPlayID'), fv(i, 'weight')) for i in o.iter('obj') if i.get('na') == 'AkPlaylistItem']
    if o.get('na') == 'CAkLayerCntr':
        d['layers'] = [{'id': fv(l, 'ulLayerID'), 'rtpc': fv(l, 'rtpcID'),
                        'assoc': [{'child': fv(a, 'ulAssociatedChildID'), 'gain_curve': graph(a)}
                                  for a in l.iter('obj') if a.get('na') == 'CAssociatedChildData']}
                       for l in o.iter('obj') if l.get('na') == 'CAkLayer']
        d['continuous'] = fv(o, 'bIsContinuousValidation')
    if o.get('na') == 'CAkSwitchCntr':
        d['group'] = fv(o, 'ulGroupID')
        d['default'] = fv(o, 'ulDefaultSwitch')
    d['children'] = children(o)
    return d


def pruned(e, depth, out):
    a = e.attrib
    if e.tag == 'fld':
        if a.get('na') in NOISE:
            return
        line = '%s = %s' % (a.get('na'), a.get('va'))
        if '[' in a.get('vf', ''):
            line += '  ' + a['vf'][a['vf'].index('['):]
        if a.get('hn'):
            line += '  (' + a['hn'] + ')'
        out.append('  ' * depth + line)
        for c in e:   # bitfields
            if c.get('va') not in ('0',):
                pruned(c, depth + 1, out)
        return
    kids = []
    for c in e:
        pruned(c, depth + 1, kids)
    if kids or a.get('na', '').startswith('CAk'):
        out.append('  ' * depth + '[%s]' % a.get('na'))
        out.extend(kids)


def dump(objs, nid, depth=0, drop_children=False):
    o = objs.get(nid)
    if o is None:
        return ['  ' * depth + 'MISSING %d' % nid]
    out = []
    pruned(o, depth, out)
    if drop_children:
        cut = [i for i, l in enumerate(out) if l.strip() == '[Children]']
        if cut:
            out = out[:cut[0]] + ['  ' * (depth + 2) + '(children: %d)' % len(children(o))]
    return out


# ---------------------------------------------------------------- media

def bnk_media(path):
    """{wem id: (offset, size)} of a bank's in-memory media (offset absolute in the file)."""
    media, didx, data = {}, None, None
    with open(path, 'rb') as f:
        off = 0
        while True:
            f.seek(off)
            h = f.read(8)
            if len(h) < 8:
                break
            tag, size = struct.unpack('<4sI', h)
            if tag == b'DIDX':
                didx = f.read(size)
            elif tag == b'DATA':
                data = off + 8
            off += 8 + size
    for i in range(0, len(didx), 12):
        wid, o, s = struct.unpack_from('<3I', didx, i)
        media[wid] = (data + o, s)
    return media


def bnk_hirc(path):
    """{object id: raw bytes} of a bank's HIRC chunk (for comparing builds)."""
    with open(path, 'rb') as f:
        buf = f.read()
    off = 0
    while off < len(buf):
        tag, size = struct.unpack_from('<4sI', buf, off)
        if tag == b'HIRC':
            n, p, out = struct.unpack_from('<I', buf, off + 8)[0], off + 12, {}
            for _ in range(n):
                t, s, i = struct.unpack_from('<BII', buf, p)
                out[i] = buf[p:p + 5 + s]
                p += 5 + s
            return out
        off += 8 + size
    return {}


BUILTIN = ['None', 'Distance', 'Azimuth', 'Elevation', 'EmitterCone', 'Obstruction', 'Occlusion', 'ListenerCone']
BUS_PROPS = {2: 'Pitch', 3: 'LPF', 4: 'HPF', 5: 'BusVolume'}


def init_bank(path):
    """Init.bnk (v125): buses {id: (parent, {prop: value})} from HIRC, game parameters {id: (default, built-in)}
    from STMG. Hand-parsed: STMG = f32 volume threshold, u16 max voices, state groups, switch groups, params."""
    buses, params = {}, {}
    if not os.path.exists(path):
        return buses, params
    buf = open(path, 'rb').read()
    off = 0
    while off < len(buf):
        tag, size = struct.unpack_from('<4sI', buf, off)
        body = buf[off + 8:off + 8 + size]
        if tag == b'HIRC':
            p = 4
            for _ in range(struct.unpack_from('<I', body, 0)[0]):
                t, s, i = struct.unpack_from('<BII', body, p)
                if t == 8:       # CAkBus: parent bus, then a prop bundle (u8 count, ids, f32 values)
                    q = p + 9
                    parent, c = struct.unpack_from('<IB', body, q)
                    ids = body[q + 5:q + 5 + c]
                    vals = struct.unpack_from('<%df' % c, body, q + 5 + c)
                    buses[i] = (parent, {BUS_PROPS.get(k, k): v for k, v in zip(ids, vals)})
                p += 5 + s
        elif tag == b'STMG':
            p = 6
            n = struct.unpack_from('<I', body, p)[0]
            p += 4
            for _ in range(n):
                p += 8
                p += 4 + 12 * struct.unpack_from('<I', body, p)[0]
            n = struct.unpack_from('<I', body, p)[0]
            p += 4
            for _ in range(n):
                p += 9
                p += 4 + 12 * struct.unpack_from('<I', body, p)[0]
            n = struct.unpack_from('<I', body, p)[0]
            p += 4
            for _ in range(n):
                rid, val, rt, ru, rd, bi = struct.unpack_from('<IfIffB', body, p)
                params[rid] = {'default': val, 'builtin': BUILTIN[bi] if bi < len(BUILTIN) else bi,
                               'ramp': rt, 'ramp_up': ru, 'ramp_down': rd}
                p += 21
        off += 8 + size
    return buses, params


def bus_chain(buses, bid):
    out = []
    while bid and bid in buses:
        parent, pr = buses[bid]
        out.append((bid, {k: v for k, v in pr.items() if k in BUS_PROPS.values()}))
        bid = parent
    return out


def same_but_children(old, new, kids):
    """True when two builds of an object differ only in their section size and children list."""
    if old == new:
        return True
    if not kids or new is None:
        return False
    pat = struct.pack('<%dI' % (len(kids) + 1), len(kids), *kids)
    o = old.find(pat)
    if o < 0:
        return False
    n2 = struct.unpack_from('<I', new, o)[0]
    return old[5:o] == new[5:o] and old[o + 4 + 4 * len(kids):] == new[o + 4 + 4 * n2:]


def pck_streams(path):
    """{wem id: (offset, size)} of an AKPK package's streamed files (32-bit IDs)."""
    with open(path, 'rb') as f:
        head = f.read(8)
        assert head[:4] == b'AKPK', path
        hsize = struct.unpack_from('<I', head, 4)[0]
        h = f.read(hsize)
    ver, lang_sz, bank_sz, stm_sz = struct.unpack_from('<4I', h, 0)
    ext = 4 + 12 + lang_sz + bank_sz + stm_sz != hsize        # newer AKPK adds an externals LUT
    p = 16 + (4 if ext else 0) + lang_sz + bank_sz
    n = struct.unpack_from('<I', h, p)[0]
    out = {}
    for k in range(n):
        wid, block, fsize, start, lang = struct.unpack_from('<5I', h, p + 4 + k * 20)
        out[wid] = (start * block, fsize)
    return out


def vgm_info(vgm, path):
    r = subprocess.run([vgm, '-I', '-m', path], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.startswith('{'):
            return json.loads(line)
    return {'error': (r.stdout + r.stderr)[-400:]}


def wav_info(path):
    with wave.open(path, 'rb') as w:
        info = {'rate': w.getframerate(), 'channels': w.getnchannels(), 'frames': w.getnframes(),
                'seconds': round(w.getnframes() / w.getframerate(), 3), 'bits': w.getsampwidth() * 8}
        if w.getsampwidth() == 2:
            a = array.array('h', w.readframes(w.getnframes()))
            if sys.byteorder != 'little':
                a.byteswap()
            if len(a):
                peak = max(max(a), -min(a))
                rms = math.sqrt(sum(x * x for x in a) / len(a))
                info['peak_dbfs'] = round(20 * math.log10(max(peak, 1) / 32768), 2)
                info['rms_dbfs'] = round(20 * math.log10(max(rms, 1) / 32768), 2)
    return info


# ---------------------------------------------------------------- walk

def walk_event(objs, name):
    eid = fnv1(name)
    ev = objs.get(eid)
    if ev is None or ev.get('na') != 'CAkEvent':
        return None
    actions, sounds, tree = [], [], []
    for f in ev.iter('fld'):
        if f.get('na') != 'ulActionID':
            continue
        aid = int(f.get('va'))
        ao = objs.get(aid)
        plain, ranged = props(ao)
        act = {'id': aid, 'type': bracket(ao.find(".//fld[@na='ulActionType']")), 'target': fv(ao, 'idExt'),
               'props': plain, 'ranged': ranged, 'bank': fv(ao, 'fileID')}
        actions.append(act)

        def down(nid, path):
            n = node_info(objs, nid)
            tree.append((len(path), n, act['id']))
            if n['type'] == 'CAkSound':
                sounds.append({'action': aid, 'path': path + [nid], 'node': n})
            for c in n['children']:
                down(c, path + [nid])
        down(act['target'], [])
    return {'name': name, 'id': eid, 'actions': actions, 'sounds': sounds, 'tree': tree}


def chain(objs, nid):
    out = []
    while nid:
        n = node_info(objs, nid)
        out.append(n)
        if n['type'] == 'MISSING':
            break
        nid = n['parent']
    return out


def effective(objs, sound_id):
    ch = chain(objs, sound_id)
    eff = {k: round(sum(n.get('props', {}).get(k, 0.0) for n in ch), 3) for k in SUM_PROPS}
    eff['ranged'] = [(n['id'], k, v) for n in ch for k, v in n.get('ranged', {}).items()]
    eff['ranged_sum'] = {}
    for _, k, (lo, hi) in eff['ranged']:
        a, b = eff['ranged_sum'].get(k, (0.0, 0.0))
        eff['ranged_sum'][k] = (a + lo, b + hi)
    pos = next((n for n in ch if n.get('pos_override')), None)
    eff['positioning_from'] = pos['id'] if pos else None
    eff['attenuation_id'] = pos['attenuation_id'] if pos else None
    eff['spatialization'] = pos.get('spatialization') if pos else None
    eff['bus'] = next((n['bus'] for n in ch if n.get('bus')), None)
    eff['rtpcs'] = [(n['id'], r) for n in ch for r in n.get('rtpcs', [])]
    eff['fx'] = [(n['id'], x) for n in ch for x in n.get('fx', [])]
    eff['states'] = [(n['id'], s) for n in ch for s in n.get('state_groups', [])]
    eff['other_props'] = [(n['id'], k, v) for n in ch for k, v in n.get('props', {}).items() if k not in SUM_PROPS]
    return ch, eff


def fmt_node(n):
    s = '%s %d' % (n['type'], n['id'])
    if n.get('props'):
        s += '  props ' + ', '.join('%s=%g' % kv for kv in n['props'].items())
    if n.get('ranged'):
        s += '  rand ' + ', '.join('%s[%g..%g]' % (k, a, b) for k, (a, b) in n['ranged'].items())
    if n.get('pos_override'):
        s += '  positioning override (atten %s, %s)' % (n['attenuation_id'], n.get('spatialization'))
    if n.get('bus'):
        s += '  bus %d' % n['bus']
    if n.get('fx'):
        s += '  fx %s' % n['fx']
    if n.get('rtpcs'):
        s += '  rtpcs %s' % [(r['rtpc_id'], r['param']) for r in n['rtpcs']]
    if n.get('state_groups'):
        s += '  states %s' % n['state_groups']
    if n['type'] == 'CAkSound':
        src = n['source']
        s += '  wem %d (%s, %s, %d B)  Loop=%s' % (src['wem'], src['plugin'], src['stream'], src['size'],
                                                  'infinite' if n['loop'] == 0 else int(n['loop']))
    if n['type'] == 'CAkRanSeqCntr':
        s += '  %s/%s loop=%s avoidRepeat=%s transition=%s %gms playlist=%s' % (
            n['eMode'], n['eRandomMode'], 'infinite' if n['sLoopCount'] == 0 else n['sLoopCount'],
            n['wAvoidRepeatCount'], n['eTransitionMode'], n['fTransitionTime'], n['playlist'])
    if n['type'] == 'CAkLayerCntr':
        s += '  every child plays at once'
        for l in n['layers']:
            s += '; layer %d crossfades on game param %d: ' % (l['id'], l['rtpc']) + ', '.join(
                'child %d gain %s' % (a['child'], [(x, y, i) for x, y, i in a['gain_curve']]) for a in l['assoc'])
    if n['type'] == 'CAkSwitchCntr':
        s += '  switch group %s default %s' % (n['group'], n['default'])
    return s


def fmt_atten(a):
    lines = ['attenuation %d  max distance %s  cone %s' % (a['id'], a.get('max_distance'), a.get('cone'))]
    for slot, c in a.get('curves', {}).items():
        pts = c.get('points_db') or c['points']
        unit = ' dB' if c.get('points_db') else ''
        lines.append('    %-14s ' % slot + '  '.join('(%g, %g%s, %s)' % (x, y, unit, i) for x, y, i in pts))
    for r in a.get('rtpcs', []):
        lines.append('    rtpc %s -> %s %s' % (r['rtpc_id'], r['param'], r['points']))
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--xml', default=BNKDIR + '/game_se.bnk.xml')
    ap.add_argument('--bnk', default=None)
    ap.add_argument('--pck', default=None)
    ap.add_argument('--alt', default=ALT_BNK)
    ap.add_argument('--vgm', default=VGM)
    ap.add_argument('--out', default=OUT)
    ap.add_argument('--events', default=None, help='NAME[=role],... (default: the EML set)')
    args = ap.parse_args()
    d = os.path.dirname(args.xml)
    bnk = args.bnk or os.path.join(d, 'game_se.bnk')
    pck = args.pck or os.path.join(d, 'game_se.pck')
    events = EVENTS if not args.events else [
        (e.split('=')[0], e.split('=')[1] if '=' in e else e.lower()) for e in args.events.split(',')]
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)

    print('loading', args.xml)
    objs = load_xml(args.xml)
    buses, params = init_bank(os.path.join(d, 'Init.bnk'))
    media = bnk_media(bnk)
    streams = pck_streams(pck) if os.path.exists(pck) else {}
    hirc = bnk_hirc(bnk)
    alt = bnk_hirc(args.alt) if args.alt and os.path.exists(args.alt) else {}
    alt_media = bnk_media(args.alt) if alt else {}
    print('objects %d, in-bank media %d, streamed %d' % (len(objs), len(media), len(streams)))

    summary = {'xml': args.xml, 'bnk': bnk, 'pck': pck, 'alt': args.alt, 'events': [],
               'game_params': {k: v for k, v in params.items()}, 'buses': buses}
    with open(bnk, 'rb') as bf, (open(pck, 'rb') if streams else open(bnk, 'rb')) as pf:
        for name, role in events:
            ev = walk_event(objs, name)
            if ev is None:
                print('%-32s %d: not an event in this bank' % (name, fnv1(name)))
                summary['events'].append({'name': name, 'id': fnv1(name), 'missing': True})
                continue
            edir = os.path.join(out, name)
            os.makedirs(edir, exist_ok=True)
            T = ['%s  (event id %d = FNV-1 of "%s")' % (name, ev['id'], name.lower()), '']
            T.append('== actions')
            for a in ev['actions']:
                T.append('  %s %d -> target %d  props %s rand %s' % (a['type'], a['id'], a['target'], a['props'], a['ranged']))
            T += ['', '== hierarchy below each action target (own settings only; volumes dB, pitch cents)']
            for depth, n, aid in ev['tree']:
                T.append('  ' * (depth + 1) + fmt_node(n))
            # every node touched: event, actions, targets and below, plus all ancestors
            touched = {ev['id']} | {a['id'] for a in ev['actions']} | {n['id'] for _, n, _ in ev['tree']}
            sounds_out, done_wem, attens = [], {}, {}
            plays = {a['id'] for a in ev['actions'] if a['type'].startswith('Play')}
            for s in ev['sounds']:
                sid = s['node']['id']
                ch, eff = effective(objs, sid)
                touched |= {n['id'] for n in ch}
                touched |= {x for _, x in eff['fx']}   # effect plug-ins (CAkFxCustom) the chain inserts
                src = s['node']['source']
                wid = src['wem']
                eff['bus_chain'] = bus_chain(buses, eff['bus'])
                eff['bus_volume_sum'] = round(sum(v.get('BusVolume', 0) for _, v in eff['bus_chain']), 2)
                for _, r in eff['rtpcs']:
                    r['game_param'] = params.get(r['rtpc_id'])
                rec = {'sound': sid, 'path': s['path'], 'action': s['action'], 'wem': wid, 'source': src,
                       'loop': s['node']['loop'], 'effective': eff, 'chain': [n['id'] for n in ch]}
                if eff['attenuation_id']:
                    attens[eff['attenuation_id']] = attenuation(objs, eff['attenuation_id'])
                for n in ch:
                    if n.get('pos_override') and n.get('attenuation_id'):
                        attens.setdefault(n['attenuation_id'], attenuation(objs, n['attenuation_id']))
                if s['action'] not in plays:
                    rec['media'] = {'where': 'not extracted: this event only stops it (see the event that plays it)'}
                    sounds_out.append(rec)
                    continue
                if wid not in done_wem:
                    wem = os.path.join(edir, 'wem', '%d.wem' % wid)
                    if wid in media:
                        o, sz = media[wid]
                        bf.seek(o)
                        blob = bf.read(sz)
                        where = 'bnk'
                    elif wid in streams:
                        o, sz = streams[wid]
                        pf.seek(o)
                        blob = pf.read(sz)
                        where = 'pck'
                    else:
                        blob, where = None, 'NOT FOUND'
                    info = {'where': where}
                    if blob:
                        os.makedirs(os.path.dirname(wem), exist_ok=True)
                        with open(wem, 'wb') as w:
                            w.write(blob)
                        info['wem_bytes'] = len(blob)
                        if alt_media and wid in alt_media:
                            with open(args.alt, 'rb') as af:
                                af.seek(alt_media[wid][0])
                                info['same_in_alt'] = af.read(alt_media[wid][1]) == blob
                        vi = vgm_info(args.vgm, wem)
                        info['vgmstream'] = vi
                        loops = bool(vi.get('loopingInfo'))
                        lab = LABELS.get(sid) or LABELS.get(s['node']['parent'])
                        wav = os.path.join(edir, '%s%s_%d.wav' % (role, '_' + lab if lab else '', wid))
                        cmd = [args.vgm, '-i', '-o', wav, wem]
                        if loops:
                            cmd = [args.vgm, '-L', '-l', '1', '-F', '-o', wav, wem]
                        r = subprocess.run(cmd, capture_output=True, text=True)
                        if os.path.exists(wav):
                            info['wav'] = os.path.relpath(wav, out).replace('\\', '/')
                            info['wav_info'] = wav_info(wav)
                        else:
                            info['decode_error'] = (r.stdout + r.stderr)[-400:]
                    done_wem[wid] = info
                rec['media'] = done_wem[wid]
                sounds_out.append(rec)

            T += ['', '== sounds: full parent chain (sound first) and effective values (sums over the chain)']
            for rec in sounds_out:
                eff = rec['effective']
                m = rec['media']
                wi = m.get('wav_info', {})
                vi = m.get('vgmstream', {})
                T.append('  sound %d  wem %d  [%s]  %s  %s Hz %s ch %s s  peak %s / rms %s dBFS  wem loop points %s  Loop prop %s' % (
                    rec['sound'], rec['wem'], m['where'], m.get('wav', '-'), wi.get('rate'), wi.get('channels'),
                    wi.get('seconds'), wi.get('peak_dbfs'), wi.get('rms_dbfs'), vi.get('loopingInfo'),
                    'infinite' if rec['loop'] == 0 else int(rec['loop'])))
                T.append('    volume %+g dB, make-up %+g dB, pitch %+g cents, LPF %g, HPF %g' % tuple(eff[k] for k in SUM_PROPS))
                if eff['ranged']:
                    T.append('    randomizers %s  (sum %s)' % (eff['ranged'], eff['ranged_sum']))
                T.append('    positioning from %s: attenuation %s, %s' % (eff['positioning_from'], eff['attenuation_id'], eff['spatialization']))
                if eff['rtpcs']:
                    for nid, r in eff['rtpcs']:
                        T.append('    rtpc on %d: game param %s (%s; Init.bnk: %s) -> %s %s%s' % (
                            nid, r['rtpc_id'], r['type'], r.get('game_param'), r['param'], r['scaling'], r['points']))
                        if r.get('points_db'):
                            T.append('        as dB: %s' % r['points_db'])
                if eff['fx']:
                    T.append('    fx %s' % eff['fx'])
                if eff['states']:
                    T.append('    state groups %s' % eff['states'])
                if eff['other_props']:
                    T.append('    other props %s' % eff['other_props'])
                T.append('    bus (first OverrideBusId up the chain) %s %s; bus chain to master %s = %+g dB BusVolume' % (
                    eff['bus'], KNOWN_NAMES.get(eff['bus'], ''), eff['bus_chain'], eff['bus_volume_sum']))
                for n in chain(objs, rec['sound'])[1:]:
                    T.append('      ^ ' + fmt_node(n))
            T += ['', '== attenuations (x = distance in game units; dB curves converted from their stored linear values, see lin_db)']
            for a in attens.values():
                T += ['  ' + l for l in fmt_atten(a)]
            if alt:
                diff = sorted(i for i in touched if hirc.get(i) != alt.get(i))
                real = [i for i in diff if not same_but_children(hirc.get(i), alt.get(i), children(objs[i]) if i in objs else [])]
                T += ['', '== compare with %s: %d of %d touched objects differ %s; other than in their children lists: %s' % (
                    args.alt, len(diff), len(touched), diff, real or 'none')]
            T += ['', '== raw wwiser fields of every touched object (defaults pruned)']
            for i in sorted(touched):
                T += dump(objs, i, 1, drop_children=objs.get(i) is not None and objs[i].get('na') == 'CAkActorMixer')
            with open(os.path.join(edir, 'TREE.txt'), 'w', encoding='utf-8') as w:
                w.write('\n'.join(T) + '\n')
            summary['events'].append({'name': name, 'role': role, 'id': ev['id'], 'actions': ev['actions'],
                                      'tree': [(dp, n) for dp, n, _ in ev['tree']], 'sounds': sounds_out,
                                      'attenuations': list(attens.values()),
                                      'alt_differs_beyond_children': sorted(
                                          i for i in touched if alt and not same_but_children(
                                              hirc.get(i), alt.get(i), children(objs[i]) if i in objs else []))})
            print('%-32s %10d  actions %s  sounds %d  wems %s' % (
                name, ev['id'], [a['type'] for a in ev['actions']], len(sounds_out),
                ['%d:%ss' % (k, v.get('wav_info', {}).get('seconds')) for k, v in done_wem.items()]))
    with open(os.path.join(out, 'summary.json'), 'w', encoding='utf-8') as w:
        json.dump(summary, w, indent=1, default=str)
    print('wrote', out)


if __name__ == '__main__':
    main()
