"""spec.py : the LaserFx commandlet's spec (tools/laser7/README.md): AC7's swing curve, its two beam effects (fxspec.py
of build/ac7/laser/json's dumps, their materials and meshes mapped onto ue_import.py's rebuilt ones) and the weapon
blueprint BP_SV_LaserInterceptor on AC8's own ALiveLaserInterceptor with AC7's wp_LaserInterceptor values in AC8's
units (AC7's world is 1 unit ~0.1 m, AC8's 1 unit = 1 cm: distances x10).

  python -I tools/laser7/spec.py  ->  build/laser7/laser7.spec.json
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fxspec

ROOT = os.environ.get('SV_ROOT', r'E:\ACE8 Survival Mode')
JSON = os.path.join(ROOT, 'build', 'ac7', 'laser', 'json')
OUT = os.path.join(ROOT, 'build', 'laser7')
DEST = '/Game/Mods/SurvivalMode/Laser7'
AC7_TO_AC8 = 10.0                                   # (AC7's world units ~0.1 m; AC8's 1 cm)
# AC7's wp_LaserInterceptor CDO (docs/re/LASER_INTERCEPTOR.md 1a; the user's own copy the same, 2026-11-07)
AC7 = {'RayDistance': 12400.0, 'RayRadius': 150.0, 'LifeTime': 6.0, 'Damage': 10.0}
ASSETS = {'m_TLS_01': 'M_SV_TLS_01', 'm_TLS_01_wire': 'M_SV_TLS_01_wire', 'm_TLS_02': 'M_SV_TLS_02',
          'm_TLS_03': 'M_SV_TLS_03', 'SM_TLS_01': 'SM_SV_TLS_01', 'SM_TLS_projectile_root': 'SM_SV_TLS_projectile_root',
          'SM_TLS_projectile_tip': 'SM_SV_TLS_projectile_tip'}
FX = {'FX_UAV_TLS_Muzzleflash01': 'FX_SV_UAV_TLS_Muzzleflash01', 'FX_UAV_TLS_Muzzleflash02': 'FX_SV_UAV_TLS_Muzzleflash02'}
CURVE, BP = 'CUR_SV_LaserInterceptorSwingRate', 'BP_SV_LaserInterceptor'


def ref(cls, name):
    return "%s'%s/%s.%s'" % (cls, DEST, name, name)


def build():
    amap = {k: DEST + '/' + v for k, v in ASSETS.items()}
    systems = []
    for src, name in FX.items():
        s = fxspec.system_spec(fxspec.load(os.path.join(JSON, src + '.json')), amap)
        s['asset'] = name
        systems.append(s)
    # the beam's components: where AC7's blueprint put them (X -30 of its units), x10 into AC8's world, so their
    # emitters keep AC7's numbers; their particle parameters (BeamLength = RayDistance / 10, LaserScale) are set each
    # tick by Survival's Lua (AC7's blueprint graph: its ubergraph, docs/re/LASER_INTERCEPTOR.md 1d)
    comp = lambda fx: {'Template': ref('ParticleSystem', FX[fx]), 'RelativeLocation': '(X=%g,Y=0,Z=0)' % (-30 * AC7_TO_AC8),
                       'RelativeScale3D': '(X=%g,Y=%g,Z=%g)' % ((AC7_TO_AC8,) * 3)}
    # AC7's blueprint kept its beam's particle parameters on MainLaser (and set them again each tick, the same values):
    # BeamLength (RayDistance in AC7 units: the component's x10 makes it AC8's 1.24 km, LaserScale 1), BeamLifeTime (its
    # LifeTime + EndLaserMaxTime 0.2) and LightLifeTime (its LifeTime - 0.5)
    params = ('((Name="BeamLength",ParamType=PSPT_Vector,Vector=(X=%g,Y=1,Z=1)),'
              '(Name="BeamLifeTime",ParamType=PSPT_Scalar,Scalar=%g),'
              '(Name="LightLifeTime",ParamType=PSPT_Scalar,Scalar=%g))') % (AC7['RayDistance'], AC7['LifeTime'] + 0.2, AC7['LifeTime'] - 0.5)
    spec = {
        'root': DEST,
        'curve': {'asset': CURVE, 'keys': [{'t': 0.0, 'v': 0.0, 'interp': 'cubic'}, {'t': 1.0, 'v': 1.0, 'interp': 'linear'}]},
        'systems': systems,
        'blueprint': {
            'asset': BP, 'parent': '/Script/Live.LiveLaserInterceptor',
            'cdo': {'RayDistance': '%g' % (AC7['RayDistance'] * AC7_TO_AC8), 'RayRadius': '%g' % (AC7['RayRadius'] * AC7_TO_AC8),
                    'InterceptAngle': '180', 'SearchInterval': '0.5', 'InterceptTime': '1', 'bInertia': 'False',
                    'SwingRateCurve': ref('CurveFloat', CURVE), 'LifeTime': '%g' % AC7['LifeTime'],
                    'damage': '%g' % AC7['Damage'], 'WeaponID': 'WID_AI_laser_interceptor', 'bIsBaseAttached': 'True',
                    'EndLaserMaxTime': '0.2', 'EndLaserTimer': '0.2', 'LaserScale': '1'},
            'components': {'MainLaser': dict(comp('FX_UAV_TLS_Muzzleflash01'), InstanceParameters=params),
                           'EndLaser': dict(comp('FX_UAV_TLS_Muzzleflash02'), InstanceParameters=params, bAutoActivate='False')},
        },
    }
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, 'laser7.spec.json')
    json.dump(spec, open(out, 'w', encoding='utf-8'), indent=1)
    n = sum(len(l['modules']) for s in systems for e in s['emitters'] for l in e['lods'])
    print('laser7 spec: curve %s, %d systems (%d modules), blueprint %s -> %s' % (CURVE, len(systems), n, BP, out))


if __name__ == '__main__':
    build()
