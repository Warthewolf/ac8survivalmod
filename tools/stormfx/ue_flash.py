"""ue_flash.py : NS_SV_CloudFlash, Survival's own lightning flash in the clouds, in the AC8 template project (UE 5.4,
$AC8_LIVE_PROJECT), under /Game/Mods/SurvivalMode/StormFx (tools/stormfx/README.md). Run by tools/stormfx/build.sh:

  UnrealEditor.exe $AC8_LIVE_PROJECT/Live.uproject -ExecutePythonScript=tools/stormfx/ue_flash.py
      -EnablePlugins=CascadeToNiagaraConverter
  (the full editor, not -run=pythonscript: the converter's AddEmptyEmitter builds Niagara's editor view models, which need
  Slate; the commandlet crashed in FNiagaraEmitterHandleViewModel::Initialize, 2026-11-17. SV_QUIT=1: the editor closed
  at the end, done or not)

Built through Epic's CascadeToNiagaraConverter scripting API (FXConverterUtilitiesLibrary): an empty emitter, Niagara's
own modules and their inputs, curve inputs, the sprite renderer, then the system's compile. Why our own: Mission 12's
NS_CloudLightning is three looping spawn-rate emitters, so one switched on at a bolt flashes at a random moment, not with
it (docs/re/THUNDER.md). This one bursts at activation: every Activate / ResetSystem flashes at once.
- one CPU emitter (no compute shaders of ours), world space, once; 3 sprites in a sphere, AC8's own
  MI_NearCloudLightning001 (a stub at its path here, never packed: AC8's material and shaders draw it in game, hard rules
  42 / 58), its 4x4 flipbook played over the flash, colour and alpha on a flicker curve (strike, dip, re-strike, fade).
Writes build/stormfx/ue_flash.log; its last line "done" when it all went in.
"""
import os
import unreal

ROOT = os.environ.get('SV_ROOT')       # (Unreal's own Python has no tools/env.py: build.sh passes the main tree's folder)
if not ROOT:
    raise RuntimeError("SV_ROOT isn't set: run this through tools/stormfx/build.sh (it passes the main tree's folder)")
OUT = os.path.join(ROOT, 'build', 'stormfx')
DEST = '/Game/Mods/SurvivalMode/StormFx'
NAME = 'NS_SV_CloudFlash'
# AC8's own (stubs here, never packed: the game's real ones load in their place)
MAT_STUB = '/Game/Base/Material/VFX/Lightning/M_VFX_NearCloudLightning'
MI_STUB = '/Game/VFX/Environment/Common/Lightning/CloudLightning/MI_NearCloudLightning001'
# the flash (seconds, metres, its 4x4 flipbook)
LIFE_S, SPRITES, SIZE_M, SPREAD_M, FRAMES, SUBUV = 1.4, 3, 2600.0, 600.0, 16, (4, 4)
FLICKER = [(0.00, 1.00), (0.05, 0.30), (0.10, 0.95), (0.17, 0.20), (0.25, 0.70), (0.36, 0.12), (0.55, 0.05), (1.00, 0.0)]
BRIGHT = 6.0                           # the colour's peak (the material's own blue x this)
LOG = os.path.join(OUT, 'ue_flash.log')
AT = unreal.AssetToolsHelpers.get_asset_tools()
EAL = unreal.EditorAssetLibrary
FX = unreal.FXConverterUtilitiesLibrary
lines = []

# Niagara's own scripts and enums (as the converter's Paths.py names them, UE 5.4)
S_EMITTER_STATE = '/Niagara/Modules/Emitter/EmitterState.EmitterState'
S_BURST = '/Niagara/Modules/Emitter/SpawnBurst_Instantaneous.SpawnBurst_Instantaneous'
S_INIT = '/Niagara/Modules/Spawn/Initialization/V2/InitializeParticle.InitializeParticle'
S_SHAPE = '/Niagara/Modules/Spawn/Location/V2/ShapeLocation.ShapeLocation'
S_SUBUV = '/Niagara/Modules/Update/SubUV/SubUVAnimation.SubUVAnimation'
S_COLOR = '/Niagara/Modules/Update/Color/Color.Color'
S_STATE = '/Niagara/Modules/Update/Lifetime/ParticleState.ParticleState'
D_FLOAT_CURVE = '/Niagara/DynamicInputs/ValueFromCurve/FloatFromCurve.FloatFromCurve'
D_VECTOR_CURVE = '/Niagara/DynamicInputs/ValueFromCurve/VectorFromCurve.VectorFromCurve'
D_COLOR = '/Niagara/DynamicInputs/LinearColor/MakeLinearColorFromVectorAndFloat.MakeLinearColorFromVectorAndFloat'
E_LIFE = '/Niagara/Enums/ENiagaraEmitterLifeCycleMode.ENiagaraEmitterLifeCycleMode'
E_INACTIVE = '/Niagara/Enums/ENiagaraInactiveMode.ENiagaraInactiveMode'
E_LOOP = '/Niagara/Enums/ENiagara_EmitterStateOptions.ENiagara_EmitterStateOptions'
E_SIZE = '/Niagara/Enums/ENiagara_SizeScaleMode.ENiagara_SizeScaleMode'
E_SHAPE = '/Niagara/Enums/Location/ENiagara_LocationShapes.ENiagara_LocationShapes'


def say(msg):
    lines.append(msg)
    unreal.log('[stormfx] ' + msg)
    os.makedirs(OUT, exist_ok=True)
    with open(LOG, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def stubs():
    """AC8's material and instance at their own paths, only for the editor (build.sh never packs them)."""
    if not EAL.does_asset_exist(MAT_STUB):
        d, n = MAT_STUB.rsplit('/', 1)
        m = AT.create_asset(n, d, unreal.Material, unreal.MaterialFactoryNew())
        m.set_editor_property('blend_mode', unreal.BlendMode.BLEND_ADDITIVE)
        m.set_editor_property('shading_model', unreal.MaterialShadingModel.MSM_UNLIT)
        m.set_editor_property('used_with_niagara_sprites', True)
        EAL.save_asset(MAT_STUB)
        say(f'stub {MAT_STUB} (additive, unlit, Niagara sprites; never packed)')
    if not EAL.does_asset_exist(MI_STUB):
        d, n = MI_STUB.rsplit('/', 1)
        mi = AT.create_asset(n, d, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
        mi.set_editor_property('parent', EAL.load_asset(MAT_STUB))
        EAL.save_asset(MI_STUB)
        say(f'stub {MI_STUB} on {MAT_STUB} (never packed)')
    return EAL.load_asset(MI_STUB)


TEMPLATE = '/Niagara/DefaultAssets/Templates/CascadeConversion/CompletelyEmpty'


def template():
    """The converter's AddEmptyEmitter loads Niagara's CompletelyEmpty emitter template, which some UE 5.4 installs lack
    (no /Niagara/DefaultAssets/Templates at all: the first build, 2026-11-17, stopped in CastChecked there). Made once, empty
    (no modules, no renderer), in the Niagara plugin's own content: an addition, nothing of the engine's changed."""
    if EAL.does_asset_exist(TEMPLATE):
        return
    d, n = TEMPLATE.rsplit('/', 1)
    f = unreal.NiagaraEmitterFactoryNew()
    for prop in ('add_default_modules_and_renderers_to_empty_emitter', 'b_add_default_modules_and_renderers_to_empty_emitter'):
        try:
            f.set_editor_property(prop, False)
            break
        except Exception:
            pass
    AT.create_asset(n, d, unreal.NiagaraEmitter, f)
    EAL.save_asset(TEMPLATE)
    say(f'made {TEMPLATE} (the converter\'s empty emitter template, missing from this UE install)')


def key(t, v):
    k = unreal.RichCurveKeyBP()
    k.set_editor_property('time', t)
    k.set_editor_property('value', v)
    try:                                # (linear is FRichCurveKey's default; RichCurveKeyBP doesn't expose InterpMode in 5.4)
        k.set_editor_property('interp_mode', unreal.RichCurveInterpMode.RCIM_LINEAR)
    except Exception:
        pass
    return k


def keys(scale=1.0):
    return [key(t, v * scale) for t, v in FLICKER]


def args(path, version=None):
    a = FX.create_asset_data(path)
    return unreal.CreateScriptContextArgs(a, version) if version else unreal.CreateScriptContextArgs(a)


def dyn(path, params, kind, version=None):
    c = FX.create_script_context(args(path, version))
    for n, v in params.items():
        c.set_parameter(n, v)
    return FX.create_script_input_dynamic(c, kind)


def main():
    say(f'into {DEST}/{NAME}')
    mi = stubs()
    template()
    path = DEST + '/' + NAME
    if EAL.does_asset_exist(path):
        EAL.delete_asset(path)
    system = AT.create_asset(NAME, DEST, unreal.NiagaraSystem, unreal.NiagaraSystemFactoryNew())
    sc = FX.create_system_conversion_context(system)
    em = sc.add_empty_emitter('Flash')
    em.set_sim_target(unreal.NiagaraSimTarget.CPU_SIM)
    em.set_local_space(False)
    I = unreal.NiagaraScriptInputType
    EU, PS, PU = (unreal.ScriptExecutionCategory.EMITTER_UPDATE, unreal.ScriptExecutionCategory.PARTICLE_SPAWN,
                  unreal.ScriptExecutionCategory.PARTICLE_UPDATE)

    st = em.find_or_add_module_script('EmitterState', args(S_EMITTER_STATE, [1, 0]), EU)
    st.set_parameter('Life Cycle Mode', FX.create_script_input_enum(E_LIFE, 'Self'))
    st.set_parameter('Inactive Response', FX.create_script_input_enum(E_INACTIVE, 'Complete (Let Particles Finish then Kill Emitter)'))
    st.set_parameter('Loop Behavior', FX.create_script_input_enum(E_LOOP, 'Once'))
    st.set_parameter('Loop Duration', FX.create_script_input_float(LIFE_S + 0.2))
    say('emitter state: self, once, %.1f s, complete when switched off' % (LIFE_S + 0.2))

    b = em.find_or_add_module_script('SpawnBurst', args(S_BURST, [1, 1]), EU)
    b.set_parameter('Spawn Count', FX.create_script_input_int(SPRITES))
    b.set_parameter('Spawn Time', FX.create_script_input_float(0.0))
    say(f'a burst of {SPRITES} at activation')

    ini = em.find_or_add_module_script('InitializeParticle', args(S_INIT, [1, 0]), PS)
    ini.set_parameter('Lifetime', FX.create_script_input_float(LIFE_S))
    ini.set_parameter('Sprite Size Mode', FX.create_script_input_enum(E_SIZE, 'Non-Uniform'))
    ini.set_parameter('Sprite Size', FX.create_script_input_vec2(unreal.Vector2D(SIZE_M * 100.0, SIZE_M * 100.0)), True, True)
    say(f'each sprite {SIZE_M:.0f} m, {LIFE_S} s')

    sh = em.find_or_add_module_script('ShapeLocation', args(S_SHAPE), PS)
    sh.set_parameter('Shape Primitive', FX.create_script_input_enum(E_SHAPE, 'Sphere'))
    sh.set_parameter('Sphere Radius', FX.create_script_input_float(SPREAD_M * 100.0))
    say(f'spread in a sphere of {SPREAD_M:.0f} m')

    sub = em.find_or_add_module_script('SubUVAnimation', args(S_SUBUV), PU)
    sub.set_parameter('Number Of Frames', FX.create_script_input_float(float(FRAMES)))
    say(f'its flipbook: {FRAMES} frames ({SUBUV[0]}x{SUBUV[1]}) over the flash')

    rgb = dyn(D_VECTOR_CURVE, {'VectorCurve': FX.create_script_input_di(FX.create_vec3_curve_di(keys(BRIGHT), keys(BRIGHT), keys(BRIGHT)))},
              I.VEC3, [1, 0])
    alpha = dyn(D_FLOAT_CURVE, {'FloatCurve': FX.create_script_input_di(FX.create_float_curve_di(keys()))}, I.FLOAT, [1, 0])
    col = em.find_or_add_module_script('Color', args(S_COLOR), PU)
    col.set_parameter('Color', dyn(D_COLOR, {'Vector (RGB)': rgb, 'Float (Alpha)': alpha}, I.LINEAR_COLOR))
    say('colour and alpha on the flicker: ' + ', '.join('%.2f:%.2f' % kv for kv in FLICKER) + f' (colour x{BRIGHT})')

    em.find_or_add_module_script('ParticleState', args(S_STATE, [1, 1]), PU)

    r = unreal.NiagaraSpriteRendererProperties()
    r.set_editor_property('material', mi)
    r.set_editor_property('sub_image_size', unreal.Vector2D(*SUBUV))
    r.set_editor_property('sub_image_blend', False)
    em.add_renderer('SpriteRenderer', r)
    say(f'sprite renderer: {MI_STUB} (AC8\'s in game), sub images {SUBUV}')

    sc.finalize()
    EAL.save_asset(path)
    say(f'saved {path}')
    say('done')


try:
    main()
except Exception as e:                  # (the log's last line says so; build.sh stops on it)
    import traceback
    say('FAILED: ' + repr(e))
    for ln in traceback.format_exc().splitlines():
        say('  ' + ln)
if os.environ.get('SV_QUIT') == '1':    # (the full editor's run: closed once it's written)
    unreal.SystemLibrary.quit_editor()
