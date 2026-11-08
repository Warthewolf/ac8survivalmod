# Comona Island (Map17): map reference

Research of 2026-11-06 (user: "do research into Comona Map ... go over the textures and details and learn everything from
it so that you can utilize the map"). Read-only work on the game's paks; nothing in Survival changed. Every number here
comes from the stock packages unless it is marked otherwise:

- **[data]** read from the game's files (the source is named),
- **[inferred]** reasoned from data, not read directly,
- **[in-game check]** still needs a test in the game.

The data, the scripts that made it and the decoded textures are in `E:\ACE8 Survival Mode\build\research\comona\`
(git-ignored; `manifest.json` there lists every file). Look at `comona_overview.png` first: it is the whole island chain
with its places labelled, plus close-ups of the spaceport and the airport.

Related notes: hard rule 27 (from Lua, terrain traces only work near the player, so map data has to come from files),
[AIRFIELD_SUPPLY.md](AIRFIELD_SUPPLY.md) (Mission 22's airport units, volumes and paths),
[SPECIAL_ROUNDS.md](SPECIAL_ROUNDS.md) (the shuttle pad, the amphibious beaches),
[SPACEPORT_ASSAULT.md](SPACEPORT_ASSAULT.md) and `tools/data/spaceport_buildings.json` (building boxes within 5 km of the
shuttle pad), and `SURVIVAL_SPEC.md` (Comona as Survival's map).

## 1. In short

- The map is a flat chain of keys about 52 km long, running WSW to ENE: the spaceport island in the west and the airport
  key in the east-centre, joined by bridges, with more keys and a town to the east. **[data]**
- **Units:** cm. **North = -Y, east = +X**, Z is up. PL_Mission022 has four TextRenderActors labelled `NORTH` at
  (0, -50 km), `SOUTH` at (0, +50 km), `EAST` at (+50 km, 0) and `WEST` at (-50 km, 0). Mission 22's `Unit_dummyN0` /
  `Unit_dummyS0` are placed at -Y / +Y. The HUD radar map draws -Y at the top and +X on the right. **[data]**
- To turn a yaw into a compass heading: **heading = (90 + yaw) mod 360**, where yaw is UE yaw in degrees from +X towards +Y.
  The runway's yaw of -23 gives 067. **[data]**
- **Sea surface: z 350 (3.5 m).** It is a 200 x 200 km collision plane plus a sea mesh on every tile. **[data]**
- **Land: flat at z 500 (5.0 m)**, highest point 5.46 m. The modelled sea floor drops within about 100 m of the shore to a
  flat -16.1 m (deepest -18.1 m). There are no hills: the only height comes from buildings, towers, trees and bridges.
  **[data]**
- **Airport:** one runway, 07/25, 1,500 x 30 m. Its centre is (1610476, -436143) and it lies at yaw -23: heading 067 from
  the west end, 247 from the east end. **[data]**
- **Spaceport:** two launch complexes, at (-1383310, -41346) and (-1324263, 59704); the vehicle assembly building (VAB),
  the control centre, and an unmarked 2.4 km landing strip. **[data, the strip from texture]**
- **Combat zone** (Mission 22, also Survival's): 80 x 80 km centred on (-707336, -261895), 40 km tall. The land's east tip
  at x 32.97 km touches its east edge at x 32.93 km. **[data]**

## 2. The level set

### Survival's level and the stock missions on Map17 [data]

`PL_SurvivalMode` is a copy of `PL_Mission022` (`tools/build_survival.py` build_pl). It keeps every Mission 22 sublevel
except the lighting one, which it swaps for `Mission004_Common_Lit_Cloudly01` (Map05's sky; clock 10:10). Mission 22 runs
at 05:30; Mission 19 is set at 15:00 ("Moonlight and Shadows").

| Level | Bytes | What it holds (actors by class) | Mission 22 / Survival | Mission 19 |
| --- | ---: | --- | :-: | :-: |
| `Maps/Ingame/Mission022/PL_Mission022` | 15 k | LiveWorldSettings (minimap textures, clock 05:30), BP_DefaultUnitSpawner, 4 compass TextRenderActors, 2 gauntlet locators (one at the spaceport (-1381140, 80060), one at the airport (1605000, -425330)) | persistent | - |
| `Mission022_MiniGame` | 66 k | 87 BP_MinigameAreaLanding, 11 BP_MinigameAerialControlVolume, BP_ControlTower_AirPort_Mission022 (the landing / STORE minigame), BP_MinigameAreaLimitVolume, 2 player points, a ForceGearDown volume | yes | - |
| `Map17_Env_Terrain001` | 12 k | 23 StaticMeshActors: the 22 terrain tiles and `SM_TER_Map17_WaterCollisionAll_I12`, all at the origin (their vertices are already in world space) | yes | yes |
| `Map17_Env_ComonaAirport` | 6.5 M | 4,383 StaticMeshActors (1,970 fence pieces, about 2,000 light fixtures of which 1,049 are emissive glows, hangars, tower, navaids, warehouses, parked cars), 291 decals (tyre marks, leaks, sand, dirt), 3 windsocks, an InstancedFoliageActor | yes | yes |
| `Map17_Env_CityMap001` | 1.1 M | 2,770 StaticMeshActors: the spaceport's unique meshes (`SM_UNI_*`), warehouses, houses, apartments, shops, marinas, yachts, ships, breakwaters, street lights; one WaterZone | yes | yes |
| `Map17_Env_CityHda001_Baked` | 717 k | 3 actors holding 5,438 instanced houses (`SM_HOU_*`, baked from Houdini) | yes | yes |
| `Map17_Env_CityTraffic001` | 90 k | the road and sidewalk meshes (`SM_ROD_Map17_Road001/Sidewalk001`, world space, x -15.9..32.9 km), 6 bridge decks and 7 bridge walkways (world-space spline meshes), 602 street lights, 16 traffic lights | yes | yes |
| `Map17_Env_Foliage_Baked` | 17.9 M | 19 actors holding 136,164 plants (bushes, silk floss, junipers, Indian almond, areca and Washingtonia palms, ash, osage orange, slash pine) | yes | yes |
| `Map17_Env_MassAI` | 2.5 M | ZoneGraphData (the traffic lanes) and BP_TrafficVehicleSpawner | yes | yes |
| `Map17_SND_AmbientActor` | 2 k | BP_SoundAmbientActor | yes | - |
| `Mission022_Common_Env_Sea` | 700 k | 1,561 StaticMeshActors (the sea: see section 5), BP_LiveWaveController (WaveViewDistance 89,250) | yes | - |
| `Mission022_Env_CityLighting001` | 458 k | night lights: 498 PointLights, 40 SpotLights, 247 emissive light meshes, a HoudiniAssetActor | yes | - |
| `Mission022_Common_Lit_Cloudly01` | 14 k | sky, sun, clouds, post-process (Mission 22's dawn) | Mission 22 only | - |
| `Mission022_Common_Env_CityMap001`, `Mission019_Common_Env_CityMap001` | 2 k | empty | yes | yes |
| `Mission019_Common_Lit_Cloudly01`, `Mission019_Common_VFX`, `Map17_Env_Sea` | | Mission 19's sky, 8 Niagara actors, and its own sea level (not pulled) | - | yes |

Each level's class counts are in `level_classes.json`; every mesh placement is in `placements_<level>.json`; lights,
decals and volumes are in `placements_comp_<level>.json`.

### Map texts and names [data] (build/research/loc CP_en.tsv)

| ID | Text |
| --- | --- |
| `MissionLocation_Name_ms19` / `_ms22` | Comona Space Base |
| `MissionLatitude_Name_ms22` / `MissionLongitude_Name_ms22` | 15°48'59"S, 16°35'58"W |
| `Text_Place_CinIGC_13` | Comona Islands |
| `Text_Bri_ProperMoun_043` | COMONA SPACE BASE |
| `Text_Bri_ProperMoun_050` | COMONA CONTROL CENTER |
| `Msg_Bri_Ms220010_T0190_v0011` | "You can resupply and rearm at the air base on the eastern end of the Comona archipelago." (it is on the eastern island group) |
| speakers `ms22_Comona_Space_Base_Air_Traffic_Controller(_A/_B/_C)` | Comona Control Tower, Comona Space Base Launch Control |

The game's text gives no other place names: no names for the keys, the town, the bridges or the harbours. The names in
this note (Airport key, East key, Middle key ...) are descriptive ones made up for this note.

## 3. Coordinates

- **The Map17 tile grid [data].** Each tile is 443,370 cm (4.43 km) square. There are 16 columns, `01`..`16`, along +X,
  and 8 rows, `A`..`H`, along +Y. The grid covers x -3,546,960..+3,546,960 (70.9 km) and y -1,773,480..+1,773,480
  (35.5 km). Tile `<row><col>` covers x from (col - 9) x 443,370 and y from (row index - 4) x 443,370. The 22 tiles with
  land are B14-16, C12-15, D05-06, D10-13, E05-09, E11 and F04-06. The airport is in C12/D12 (the runway is 70 m from
  their seam), the shuttle pad is in E06, and the rocket pad is in D05.
- **Land extents [data]:** x -19.27..+32.97 km, y -11.63..+7.33 km. There are 46.4 km² of land in 102 separate pieces
  (25 of them over 0.05 km²).
- **The combat zone [data]:** `WD_Mission022_global` CombatZone0 is centred on (-707336, -261895), 8,000,000 x 8,000,000
  x 4,000,000 cm in size. So it spans x -47.07..+32.93 km and y -42.62..+37.38 km. Survival's
  `Scripts/sv_ai.lua ZONE` keeps a 3 km margin inside it (a 37 km half-width).
- **The HUD radar map [data].** `LiveWorldSettings.MiniMapBattleGridSettings` uses `T_HUD_RadarMap_M22_000` (960 px,
  BC7, the map is in its alpha). `MiniMapEnlargedGridSettings` uses `..._highres` (3360 px). Fitting their coastline to the
  terrain (94 % / 97 % overlap) shows both cover a **100 x 100 km square centred on the combat zone**: about 104 m a pixel
  at 960 px. Its printed grid is 7 x 7 squares of 10 km: **columns A..G west to east, rows 1..7 north to south**, centred on
  the zone, with a 5 km unlettered margin out to the zone's edge.
  - Square edges: x = -707,336 - 3,500,000 + k x 1,000,000 and y = -261,895 - 3,500,000 + k x 1,000,000.
  - The spaceport is in C4, the long bridge in D4/E4, the airport in F4, and the East key in G3/G4. The land past
    x 27.93 km lies east of column G.
  - `pois.json` gives each place's square.
  - Mission 19's radar map is centred elsewhere: about (-21.8, -30.4) km, with the islands in its south-east.
- **The briefing minimap [inferred].** `T_UI_Briefing_Minimap_M22_000` matches `DT_LiveMissionTable` Mission022's
  `BriefingMapOrigin` (-1403668, -1680948). It is about 126-133 km across (`BriefingMapRange` 12,638,105).
- **Names in Mission 22's world data [data]:** `AreaA_*` = the spaceport (marks at (-1407795, 102354)), `AreaB_*` = the
  airport (`AreaB_MarkActor0` (1609640, -436414), Survival's `AIRFIELD` anchor).

## 4. Terrain

### What it is [data]

The terrain is **not a UE Landscape**: there is no heightmap, weightmap or landscape component anywhere. It is 22 static
meshes, `Environments/Terrain/Ground/Map17/Mesh/SM_TER_Map17_<tile>_I04`, each with its vertices in world space. That is
why `Map17_Env_Terrain001` is only 11 KB.

- **Render geometry** is Nanite. Each tile has a .ubulk of about 8 MB (magic `NF`); it was not decoded.
- **Collision** is a Chaos triangle mesh inside each package's `BodySetup_0`: int32 N, N x FVector3f (world cm), an int32
  large-index flag, int32 T, then T x 3 indices (uint16, or int32 with the flag set). Tiles hold 5,782 to 31,906 vertices.
  This is what the game's traces and ground units stand on, so the elevation data here is the collision surface.
  - Extractor: `scripts/colmesh.py`. Rasterizer: `scripts/rast.c`.
  - Products: `height_20m.npy` (int16 cm, 3547 x 1773 cells, row 0 = north edge, -32768 = no terrain) and
    `height_100m.json` (the same at 100 m, as JSON, with its transform).
  - Masks: `landmask_20m.png` (white = land above z 350, blue = sea with a modelled floor, dark = sea-only tiles) and
    `islands.json` (connected land areas).
- **Check against the user's in-game marks** (coast_marks, `LCAC_LANES`, `SPACEPORT_BEACHES`):
  - All eight beach marks read land at 4.7-5.0 m in the grid. Beach B was 3.93 m in game and reads 4.72 m in the grid: it
    sits on a 20 m shore slope.
  - The sea-level mark (z 350 in game) reads -16.1 m in the grid, because the in-game trace hit the sea plane.
- **Heights:**
  - Land is 5.00 m almost everywhere; the highest point is 5.46 m (F04).
  - The sea floor near the coast: 2.2 km² of it is at z 0..3.5 m (under less than 3.5 m of water), 2.1 km² at z -5..0 m,
    and 3.4 km² at z -15..-5 m.
  - Further out it is a flat -16.1 m, which means 19.6 m of water.
  - The 106 sea-only tiles have no floor at all: nothing lies under the sea plane there.
- **The turquoise shallows and reefs are only painted on.** The colour tiles show wide flats, but the geometry under them
  is mostly the -16 m floor.
- **Inland water:** `SM_TER_Map17_WaterCollisionAll_I12` (8,905 vertices, z 0.2-7 m, 1.67 km²) lies entirely over land
  cells: the ponds and lagoons on the spaceport island, the middle key's pond and some canal heads. The canals of the
  airport and East-key towns are cut below the sea plane, so they read as sea in the mask. **[data; what the water mesh is
  for is inferred]**

### Islands [data] (islands.json; the bridges are not terrain, so islands joined by a bridge count as separate)

| Name used in this note | Centroid (km) | Area | Length | What is on it |
| --- | --- | ---: | ---: | --- |
| Spaceport island (west) | (-13.81, 1.64) | 16.6 km² | 8.6 km | Comona Space Base: 2 launch complexes, VAB, control centre, landing strip; warehouses; a residential strip in the south |
| Airport key (east-central) | (14.10, -3.26) | 9.9 km² | 10.0 km | Comona Airport; a town of about 2,700 houses with residential canals and marinas; bridge 4 lands at its west end (8.8, -2.2), by a small marina and town (9.0-10.0, -2.1) |
| East key | (23.49, -7.04) | 7.8 km² | 11.9 km | a long residential key: canals, about 1,000 houses, the main road |
| Round island | (10.98, -1.00) | 3.5 km² | 2.9 km | mostly vegetation (an oval of green), with houses on its east side; it lies just south of the airport key's west end, where bridge 4 lands |
| Middle key | (-5.15, 2.27) | 2.1 km² | 3.6 km | between bridges 5 and 4; houses, a marina at (-3.78, 1.62), a pond |
| East tip keys | (29.9, -9.35), (32.0, -11.2) ... | 0.1-1 km² | | the end of the chain past bridges 1 and 2, with a resort-like housing block at (29.9, -9.3) |
| 19 smaller islets | | 0.05-1 km² | | `islands.json` |

## 5. Textures and look [data]

### Terrain colour and area masks (decoded to PNG)

Every tile has one colour texture and, on land tiles, one area mask:

- **`T_TER_Map17_<tile>_I04_D`**: 4096 x 4096, DXT1, an ordinary texture (not virtual), about 1.08 m a pixel. It is a
  photo-real aerial image: roads, canals, roofs, the runway's markings, reefs.
- **`_M`** (the AreaMask): 4096, DXT1, land tiles only.
- **Material:** `MI_TER_Map17_<tile>_I04`, parented to `MP_TER_Map17_I04`, which is parented to `M_TerrainBase_Dev`.
  - `Base_BasecolorMap` = the tile's `_D` texture; `AreaMask` = its `_M` texture.
  - Detail layers are picked by the mask's channels: **R** = `T_Concrete_Granular` (tiling 300), **G** =
    `T_Grass_A_Detail` (tiling 40), **B** = `T_Concrete_Detail_Sandy` (tiling 30), black = `T_Ground_Detail_SaltLake`
    (tiling 80); Cyan is unused (flat white).
  - The static switch `USE_LayerWater` (an ocean layer in the terrain material: `MLI_Ocean_Map17_Env`, `RT_LiveWaves2`)
    is on for 16 tiles and off for B14, B16, C15, D10, E09 and E11.
- **What the mask's colours show [inferred, by looking]:** blue = pavement (runways, roads, aprons), green = vegetation,
  red = built ground, magenta = sand, yellow (R+G) = sea.
- **Decoded files:**
  - `tex/map17_colour_256.png`: the whole 16 x 8 grid at 256 px a tile, north up.
  - `tex/map17_areamask_256.png`: the same for the masks.
  - `tex/tiles/`: every tile at 256 px, land tiles at 1024 px, and C12 / D12 (airport) and E05 / E06 (spaceport) at
    4096 px.
  - `tex/airport_2m.png`, `tex/spaceport_strip_8m.png`: close-ups.
  - `scripts/mosaic.py <x0 y0 x1 y1 km> <m/px> <out>` renders any rectangle from the tiles.
- `T_TER_Map17_WC` is a 2048 px DXT1 image of the whole chain at low resolution: probably the far-distance colour map.
  Its exact footprint was not fitted (about 56 km). **[inferred]**
- The look is the Florida Keys: the airport key closely resembles a real Keys town with its airport, canals and marinas.
  **[inferred from the imagery]**

### HUD and briefing maps

| Texture | Size | Format | Contents |
| --- | --- | --- | --- |
| `UI/Texture/HUD/Radar/Background/T_HUD_RadarMap_M22_000` | 960 | BC7 | alpha: coastline (white), land fill (grey) and the lettered 10 km grid; RGB is white |
| `..._M22_000_highres` | 3360 | BC7 | the same area at 30 m a pixel, without the grid |
| `T_HUD_RadarMap_M19_000(_highres)` | 960 / 3360 | BC7 | Mission 19's frame |
| `UI/Texture/Briefing/Background/T_UI_Briefing_Minimap_M22_000` | 960 | BC7 | the briefing frame |
| `BriefingDebriefing/Common/TerrainHeighMap/T_Map17_HeightMesh_I26` | CPU copy 1024 x 1024 G16 (GPU 4 x 4 DXT1) | | the briefing's height map, the mission table's `HeightMapRef`; not decoded (the terrain collision is better) |
| `Environments/Terrain/Ground/RadarMap/Map17/SM_Map17_HeightMapMesh_I04`, `SM_Map17_Contour_I04` | 25 x 25 m local mesh | | the briefing table's 3D map and contour meshes |

Decoded: `tex/T_HUD_RadarMap_M22_000_A.png`, `_highres_A.png`, the M19 ones, and `T_UI_Briefing_Minimap_M22_000_A.png`.
The fitted world-to-pixel mappings are in `radar_fit.json`.

### Sea and water

`Mission022_Common_Env_Sea` holds:

- **128 tile sea planes**, `SM_TER_Map17_<tile>_Sea_I04`: one flat 4.43 km plane per grid cell, at z 350.
  - Their material, `MI_TER_Map17_<tile>_Sea_I04`, is parented to `/Game/Sea/Mission019_Sea/MI_OceanH00_Mission019_TilemeshBase`.
  - Each takes the same tile's `_D` colour texture, which is why the sea shows the painted shallows.
- **1,430 `SM_TER_Map17_Loop_Sea_I04` planes** (4.43 km each). They carry the ocean out to x -93..+89 km and
  y -120..+49 km.
- **`SM_TER_SeaCollision_I04`**: a 200 x 200 km collision plane at z 350.
- **`SM_SeaBaseMesh`** at scale 50 and z -10 m, and **`SM_TER_Map07_Seabed001_I04`** (borrowed from Map07) at scale 8 and
  z -16 m, at (-34.3, 40.7) km.
- **BP_LiveWaveController**.
- The ocean layer is `MLI_Ocean_Map17_Env` (`ML_Ocean`, using `T_Foam_D_2` and `T_Water_H_2`).

## 6. Places

Every place below is in `pois.json` with x, y, z (cm), size, HUD square and source. Coordinates are in km, (x, y).

### Comona Airport (airport key; HUD F4) [data]

Sources: `Map17_Env_ComonaAirport`, `runway.json`.

- **Runway 07/25**, 1,500 x 30 m (the edge lights, `SM_AFB_Runwaylights_I27`, sit ±15 m from the centre line, along
  -742..+758 m).
  - **Thresholds:** west (rwy 07) at **(1541439, -406838)**, east (rwy 25) at **(1679514, -465447)**. Yaw -23; heading
    **067 / 247**.
  - Centre-line lights run ±884 m and approach lights out to -1,186 / +1,164 m.
  - The paved ground mesh, `SM_AFB_ComonaSpaceBaseGround001_I09`, is 2.71 km long, placed at (1609740, -435830) at yaw -23.
  - Mission 22's `VolumeBox_LandingArea0` sits at (1609574, -435747).
  - Formula for a point t m along and s m to the side (s > 0 = south side): x = 1609740 + 100 (0.92050 t + 0.39073 s),
    y = -435830 + 100 (-0.39073 t + 0.92050 s).
- **Parallel taxiway** about 57 m south (SSE) of the centre line, -759..+1208 m along it. **Aprons and parking frames**
  (62 of them) lie 75-145 m south.
- **Buildings:**

  | What | Where |
  | --- | --- |
  | control tower `SM_AFB_ControlTower004_I24` | (16.03, -4.20) |
  | ASR radar | (16.97, -4.61) |
  | hangars `SM_AFB_Hangar004/008` | (16.53-16.67, -4.39..-4.45) |
  | hangars `SM_AFB_Hangar011/016` | (17.25-17.28, -4.66..-4.80) |
  | security gate | (16.09, -4.23) |
  | rotating beacons | (15.05, -3.75) and (17.01, -4.85) |
  | TACANs | (15.00, -3.72) and (17.20, -4.74) |
  | ILS localizers | (15.26, -4.00) and (16.92, -4.71) |
  | glide-slope antennas and PAPIs | by each threshold |
  | windsock | (16.74, -4.65) |
  | apron light masts | 31 of them |
  | warehouses and parked cars | south-east |

- **The airport town** lies on both sides of the runway: about 2,700 houses (`SM_HOU`), shops and apartments along the
  main road on the south side, and residential canals opening south (SSE) to the sea.
- **Mission 22 and Survival units** here (AA guns, SAM sites, the landing dummies, the notify cylinder): see
  [AIRFIELD_SUPPLY.md](AIRFIELD_SUPPLY.md).

### Comona Space Base (spaceport island; HUD C4) [data]

Sources: `Map17_Env_CityMap001` `SM_UNI_*`, Mission 19 / 22 world data.

| Place | Position (cm) | Size / top |
| --- | --- | --- |
| Launch complex 1 (rocket pad; Mission 19's rocket 0) | (-1383310, -41346) | pad 930 x 560 m, rocket lift top about 131 m; four 200 m lightning towers round it; water tower 98 m |
| Launch complex 2 (shuttle pad; Mission 22's shuttle, Mission 19's rocket 1) | (-1324263, 59704) | same pad, shuttle lift; four 200 m towers; water tower 98 m |
| Vehicle assembly building | (-1517263, 134667) | 116 m |
| Rocket hangar / gantry crane / fire station | (-1516794, 105077) / (-1521469, 112541) / (-1526705, 121309) | 12 / 35 / 22 m |
| Shuttle lift (by the landing strip) | (-1492336, 54804) | |
| Spaceport hangar | (-1425074, -41983) | 26 m |
| Comona Control Center (`ControlCenter_common`) | (-1497330, 150122) | the Mission 19 / 22 target |
| **Landing strip 02/20** | ends (-1548644, 121381) S and (-1449624, -101854) N; centre (-1492362, -5504) | 2.44 km long, heading 024 / 204; **texture only** (see below) |
| Spaceport west beaches 1-4 | `tools/survival_events.py` SPACEPORT_BEACHES | the user's marks |

- **The landing strip** was fitted to the paved channel of the D05 / E05 area masks. The ground under it is flat at
  z 500. Nothing in the level data marks it (no lights, no ground mesh, no landing volume), so whether an aircraft can use
  it as a runway is an **[in-game check]**.
- Warehouses and an industrial area fill the island's middle and north. A residential strip runs along its southern
  shore and out to the islets towards bridge 6.
- `tools/data/spaceport_buildings.json` has 1,344 oriented building boxes within 5 km of the shuttle pad.

### Bridges [data: bounds only; the spans are Nanite, so their centre lines are approximate]

Source: `Map17_Env_CityTraffic001` `SM_ROD_SplineMeshBridge_Map17_000N_I21` (each has a walkway mesh too).

| Bridge | Approximate ends (km) | Length | Deck top | Joins |
| --- | --- | ---: | ---: | --- |
| 6 | (-11.98, 4.34) to (-10.73, 4.18) | 1.3 km | 17 m | the spaceport island's south-east tip to the islets |
| 5 | (-8.85, 3.48) to (-6.55, 2.98) | 2.4 km | 17 m | the islets to the middle key |
| **4** | (-4.27, 2.00) to (8.80, -2.24) | **13.7 km** | **36 m** | the middle key's east end to the airport key's west end: the long bridge, over open water |
| 3 | (18.17, -4.79) to (18.42, -4.87) | 0.26 km | 8 m | the airport key to the islet east of it |
| 1 | (28.95, -9.99) to (29.49, -10.22) | 0.55 km | 10 m | the East key's end to the east tip keys |
| 2 | (30.29, -10.52) to (30.79, -10.74) | 0.50 km | 10 m | the east tip keys |

The road runs the whole chain from x -15.9 to 32.9 km (`SM_ROD_Map17_Road001_I21`, Nanite). Street lights (about 830)
and the colour tiles show where it goes. The ZoneGraph's lanes in `Map17_Env_MassAI` were not decoded.

### Harbours and marinas [data] (static yachts, ships, marina piers, breakwaters in CityMap001)

| Where (km) | What | From the runway centre |
| --- | --- | --- |
| (20.13, -5.26) | 64 yachts, 4 ships: the largest marina | 4.1 km at 077 |
| (19.83, -4.55) | 19 yachts, 2 ships | 3.7 km at 087 |
| (18.27, -5.35) | marina piers (6) | 2.4 km at 065 |
| (10.03, -2.06) | 14 yachts, 3 ships (the airport key's west end, by bridge 4) | 6.5 km at 249 |
| (-3.78, 1.62) | marina piers and 16 yachts (middle key) | |
| (4.01, -1.35) | 8 breakwaters (on bridge 4's line) | |

### Built-up areas, vegetation, night lights [data]

- **Buildings.** The densest area is the airport key's town: about 3,200 placements. The rest, roughly west to east:
  - the spaceport island: about 450 warehouses and houses, plus the spaceport itself;
  - a packed trailer-home park on the middle key's eastern islet: about 750, at (-3.6, 1.5);
  - the islets just east of the airport: about 840, round the two big marinas (18.3-20.9 km);
  - the East key: about 550 houses at 23-27 km;
  - the east-tip keys: about 470 at 29-30.7 km, plus 51 at 32.4 km;
  - small groups along the western keys.

  The building clusters are in `pois.json` (kind `district`).
- **Vegetation.** 136,164 plants. The densest areas are the spaceport island (61,000), the round island (15,000), the
  airport key's mangrove band north of the runway (14,000) and the western tail (10,000). Trees reach 39 m (slash pine)
  and 35 m (coconut palm).
- **Night lighting** (`Mission022_Env_CityLighting001`, part of Survival's level):
  - 498 point lights, 40 spot lights and 247 emissive light meshes.
  - 138 of the lights are within 3 km of the runway. 36 of the 40 spot lights are the airport's apron floodlights, at
    z 32.1 m (about 27 m above the ground; three of them at z 12 m), along (15.54-17.31, -4.98..-4.02). The other 4 are
    at the shuttle pad, z 30-32 m.
  - 127 lights are within 3 km of the shuttle pad, and 97 by the VAB. The rest are spread along the towns.
  - Separately, the airport level has about 2,000 runway, taxiway, approach and apron light fixtures (1,049 of them
    emissive glow meshes).
  - Whether they glow under Survival's 10:10 sky, or under a night sky, is an **[in-game check]**.
- **Tall obstacles for low flying:**

  | Obstacle | Top |
  | --- | ---: |
  | 8 lightning towers round the two pads | 200 m |
  | launch pad structures | 125 m |
  | VAB | 116 m |
  | rocket lift (its base is 18 m up) | 131 m |
  | water towers | 98 m |
  | bridge 4's deck | 36 m |
  | trees | about 39 m |
  | warehouses | 33 m |

### Survival's own anchors (links)

- `AIRFIELD` = (1609639, -436414) (`Scripts/sv_core.lua`).
- The player start, 6 km out on the approach at 1.5 km up (`tools/build_survival.py` START).
- The amphibious beaches A-D and their sea starts (`tools/survival_events.py LCAC_LANES`; [SPECIAL_ROUNDS.md](SPECIAL_ROUNDS.md)).
- The Spaceport Assault's beaches, sea marks, troop spots and island spots ([SPACEPORT_ASSAULT.md](SPACEPORT_ASSAULT.md),
  `tools/spaceport_spots.py`).
- VOID WATCHER 1's 6 km orbit over the airfield (`survival_events.AWACS_*`).
- The heavy bombers' sectors A-H at compass 0, 45 ... 315 from the airfield (`HEAVY_SECTORS`).
- Bearings in `sv_spawn.lua`, which already use north = -Y.
- The combat zone (`sv_ai.lua ZONE`).

## 7. Using the map

### Rules for placing things

- **Ground objects:**
  - Land is flat at **z 500**: put ground units and objects at 500 on land.
  - Ships sit on the sea plane at about z 300-350 (Mission 22's ships are at 300).
  - Landing craft paths run at z -20.
  - A point is land if `height_20m.npy` reads more than 350.
  - Don't trace at run time to find land away from the player (hard rule 27): traces hit the sea collision plane.
- **Sea targets:** open water lies everywhere off the chain.
  - Over the 22 terrain tiles there is a modelled floor: -16.1 m, so 19.6 m of water. It shelves up within about
    100 m of the shore.
  - Over the other tiles there is no floor at all.
  - The painted reefs and flats are not shallow in the geometry, so they don't block ships.
  - The canals in the airport and East-key towns are open to the sea in the geometry, but they are 20-40 m wide.
- **Clearance from buildings:**
  - The spaceport check (`tools/scan_spaceport_buildings.py` -> `tools/data/spaceport_buildings.json`;
    `tools/spaceport_spots.py` keeps spots 20 m clear) covers only 5 km round the shuttle pad.
  - The airport key is the most built-up place on the map. Its town packs about 2,700 houses round the runway, so spots
    there need the same check.
  - `scan_spaceport_buildings.py` has its centre (`PAD`) and radius hard-coded. A `--centre` argument would let it scan
    the airport town (an open item).
  - The placements here (`placements_Map17_Env_CityMap001.json`, `_CityHda001_Baked`, `_ComonaAirport`) are the input.
- **Aircraft paths:** stay above the 200 m towers near the pads. Bridge 4 is a 13.7 km straight line over open water
  between the two halves of the chain: a natural raid route and chokepoint.
- **The combat zone:** the land's east end touches the zone's east edge. Inside the zone there is 28 km of open sea
  west of the spaceport, and 30-42 km of it to the north and to the south of the chain.

### Open questions

- Whether the night lights (CityLighting001, the airport's emissive lights) show under Survival's sky or a night sky.
  **[in-game check]**
- Whether the spaceport's landing strip can be used for landings. **[in-game check]**
- The exact centre lines of the roads and bridges (Nanite, and the ZoneGraph wasn't decoded). The colour tiles show both.
- The footprint of `T_TER_Map17_WC`, the briefing minimap's exact frame, and the exact use of the inland water mesh.
- The sun's direction and the time of day are being researched separately.

## 8. For the fishing round

- **Sea spots near the airport [data].** Open sea at 2.5 km from the runway centre (all on the -16.1 m floor, 19.6 m of
  water):

  | Bearing | Point (km) | Distance to land |
  | --- | --- | ---: |
  | 000 (N) | (16.10, -6.86) | 1.06 km |
  | 030 | (17.35, -6.52) | 0.36 km |
  | 150 | (17.35, -2.19) | 1.84 km |
  | 180 (S) | (16.10, -1.86) | 1.64 km |
  | 210 | (14.85, -2.19) | 0.84 km |
  | 300 | (13.93, -5.61) | 1.50 km |
  | 330 | (14.85, -6.52) | 1.78 km |

  At 1.5 km from the centre the sea comes within 20-300 m of land on several bearings.
- **A home for the fishing boat:** the marinas east of the runway, at 2.4-4.1 km on bearings 065-087, the largest at
  (20.13, -5.26). They are static yachts and ships, so a boat placed there fits the scenery.
- **The airfield at night:** Survival's level already has Mission 22's night lighting (apron floodlights, runway and
  approach light meshes, street lights), so a night round needs no new lights. Whether they switch on with a night sky
  needs a test.
