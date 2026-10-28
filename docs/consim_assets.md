# Construction Simulator assets for Baustellen Manager

Extracted from the user's own installation of *Construction Simulator* (Unity 2020.3 HDRP, Addressables bundles) for private, non-distributed use. Built by `tools/consim_extract/build_assets.py`; see `tools/consim_extract/README.md` for how to re-run.

Files: `game/assets/consim/<id>/<id>.glb` + `<id>.json` (metadata: dimensions, triangles, wheels, nodes, joints + limits, hydraulics, light markers, notes). Contact sheet: `docs/consim_assets.png`; pivot/joint proof renders: `docs/consim_assets_poses.png`.

## Conventions (all assets)

- Meters, Y up, glTF right-handed; Unity data converted with S = diag(1,1,-1) (no mirroring - text such as POLIZEI / BOMAG / Liebherr reads correctly in renders).
- Vehicles face **-Z**; ground contact at y = 0; X centred on the wheel track; Z = midpoint between frontmost and rearmost axle (track units for the cold planer).
- Props: base at y = 0, origin at the pole/foot (traffic lights, lamp, signs) or footprint centre.
- Wheels `wheel_fl/fr/rl/rr`, extra axles `wheel_rl2/rr2...` (trailer: all axles `wheel_rl/rr`, `wheel_rl2/rr2` ... `wheel_rl8/rr8`), drums `drum_front/drum_rear`: origin at hub centre, spin about local X (rolling forward = negative rotation about +X), steer about local Y.
- All hinge joints rotate about the node-local **X** axis, slew joints (turret, conveyor, crane column, roller articulation) about local **Y**; positive = right-hand rule. Rest pose (as exported) = 0 deg. Limits in `joint_limits_deg` come from the game's ConfigurableJoints (converted: Unity angle theta about axis a == glTF +theta about (a.x, a.y, -a.z)).
- Light markers: empty nodes `light_head_l/r`, `light_tail_l/r`, `light_brake_l/r`, `light_reverse_l/r`, `indicator_fl/fr/rl/rr` (+ `indicator_sl/sr` side repeaters), `beacon_N`, `worklight_N`, at the lamp centres. Lamp glass is split by the game's light-mask vertex colours into materials `<mat>__light_head`, `__light_tail`, `__light_brake`, `__indicator_l`, `__indicator_r`, `__light_reverse`, `__worklight` (emissiveFactor 0, `extras.light_color` = RGB to use when lit). Beacons: `beacon_N_body/beacon_N_rotator` (rotator spins about local Y), glass `RotLight_ReflectorGlass_M`.
- Hydraulic cylinders: barrel `hyd_<joint>_a` + rod `hyd_<joint>_b` parented to the two links; JSON `hydraulics` gives the local axis of each that must point at the other (look_at every frame).
- Materials: PBR metallic-roughness, ORM texture from the HDRP mask map (R=AO, G=1-smoothness, B=metallic; *_MSO_T masks = metal/smooth/AO), normal maps rebuilt from DXT5nm (OpenGL +Y). Decals/labels/grilles alphaMode MASK, glass BLEND (alpha 0.35). Textures <= 2048 px (traffic + props <= 1024), embedded JPEG/PNG. Car paint materials carry `extras.paint = true` (tint baseColorFactor per instance; a default colour is set).
- No tangents are stored (gltf-validator: 0 errors, only MESH_PRIMITIVE_GENERATED_TANGENT_SPACE warnings); Godot generates MikkTSpace tangents on import.

## P1 - player machines

| id | source | tris | size | joints / notes | known issues |
|---|---|---:|---:|---|---|
| `excavator_a918` | Liebherr A 918 Compact litronic wheeled excavator | 33,603 | 3.9 MB | 6.9 x 3.1 x 4.2 m; limits: boom [-105.0, 0.0], boom2 [-10.0, 75.0], stick [-30.0, 50.0], bucket [-90.0, 75.0], blade [-36.5, 0.0]; 4 wheels r=0.55 | Rest pose = lower boom fully raised (game prefab pose). Hydraulic hoses are runtime splines in the game -> not included. Cylinders must be aimed at runtime (look_at data in JSON). Bucket linkage (bucket_link_a/b) is static unless the 4-bar is solved. |
| `truck_tipper` | MAN TGS 6x4 with Meiller P330 rear tipper body | 45,645 | 7.6 MB | 8.4 x 2.9 x 3.3 m; limits: tipper_body [0.0, 47.0], tailgate [-60, 10]; 6 wheels r=0.55 | Telescopic tipping cylinder: aim hyd_tipper_a at hyd_tipper_b and slide the 3 stages yourself. Tailgate hangs freely in the game (limits are a suggestion). |
| `tractor_tgx` | MAN TGX 4x2 semi-tractor | 28,515 | 4.7 MB | 6.3 x 3.0 x 3.9 m; 4 wheels r=0.54 | Beacons are the game's generic rotating-beacon prefab grafted onto the RotatingLight anchors. fifth_wheel is ~7 cm below trailer kingpin height (suspension). |
| `tractor_tgx_heavy` | MAN TGX 8x4 heavy-haulage tractor | 37,753 | 4.7 MB | 7.8 x 3.0 x 3.9 m; 8 wheels r=0.54 | Same as tractor_tgx; 8x4 heavy-haulage version. |
| `trailer_lowbed` | Heavy-duty 8-axle lowbed semi-trailer with pendulum axles and rear loading ramp | 16,894 | 2.4 MB | 20.3 x 3.9 x 2.8 m; limits: ramp [0.0, 20.0]; 16 wheels r=0.41 | Ramp is one piece with two tracks (no separate ramp_left/right in the source). Pendulum-axle swing arms kept but not articulated. |
| `cold_planer_bm2000` | Bomag BM 2000/75 cold milling machine | 34,343 | 3.4 MB | 15.4 x 2.8 x 5.0 m; limits: conveyor [-60.0, 60.0], track_fl [-35, 35], track_fr [-35, 35]; 8 wheels r=0.18 | Track chains are part of the static track-unit meshes (rollers can spin). Conveyor inclination is fixed (no pitch joint in the source). No head/tail lamps on the machine (work lights + beacon only). |
| `roller_bw141` | Bomag BW 141 AD-5 articulated tandem asphalt roller | 30,036 | 4.0 MB | 4.4 x 2.1 x 3.2 m; limits: rear_body [-17.5, 17.5]; 2 wheels r=0.55 | Source has brake/reverse/indicator lamps but no separate tail lamps. |
| `van_crew` | Crew van / panel van | 11,100 | 1.0 MB | 4.9 x 2.2 x 2.0 m; 4 wheels r=0.36 |  |

## P1 - traffic

| id | source | tris | size | joints / notes | known issues |
|---|---|---:|---:|---|---|
| `car_hatchback` | Traffic car - hatchback | 15,606 | 1.2 MB | 4.9 x 2.1 x 1.6 m; 4 wheels r=0.35 |  |
| `car_citycar` | Traffic car - city car | 14,692 | 1.2 MB | 3.6 x 2.0 x 1.5 m; 4 wheels r=0.30 |  |
| `car_estate` | Traffic car - estate wagon | 15,987 | 1.2 MB | 4.9 x 2.2 x 1.5 m; 4 wheels r=0.36 |  |
| `car_suv_compact` | Traffic car - compact SUV | 16,066 | 1.2 MB | 4.2 x 2.0 x 1.5 m; 4 wheels r=0.36 |  |
| `car_crossover` | Traffic car - crossover | 15,150 | 1.2 MB | 4.7 x 2.1 x 1.5 m; 4 wheels r=0.35 |  |
| `car_mpv` | Traffic car - compact MPV | 14,771 | 1.2 MB | 4.7 x 2.1 x 1.6 m; 4 wheels r=0.34 |  |
| `car_premium` | Traffic car - premium compact saloon | 14,397 | 1.1 MB | 5.0 x 2.1 x 1.7 m; 4 wheels r=0.35 |  |
| `car_minicompact` | Traffic car - mini compact | 13,872 | 1.1 MB | 3.7 x 1.9 x 1.5 m; 4 wheels r=0.31 |  |
| `car_police_eu` | Traffic car - EU police car | 17,808 | 1.6 MB | 4.9 x 2.1 x 1.7 m; 4 wheels r=0.35 | Prefab has no light anchors: light markers estimated from the bounding box. Blue roof lights = beacon_blue_l/r. |
| `van_big` | Large van (Sprinter class) | 12,977 | 1.1 MB | 6.9 x 2.4 x 2.7 m; 4 wheels r=0.39 |  |
| `truck_traffic_cabover` | Traffic rigid truck, European cab-over box truck | 17,839 | 1.6 MB | 7.7 x 2.8 x 3.1 m; 4 wheels r=0.44 |  |
| `truck_traffic_scania` | Scania G500 6x2 semi-tractor, usable as traffic truck or tractor | 28,298 | 2.4 MB | 6.5 x 3.0 x 3.5 m; 6 wheels r=0.55 | Player tractor from the game, usable as traffic truck (has fifth_wheel). |

## P1 - props

| id | source | tris | size | joints / notes | known issues |
|---|---|---:|---:|---|---|
| `pipe_old_10m` | Old (worn) 10 m pipe section, interior-textured, from the pipe rehabilitation set | 983 | 0.1 MB | 10.0 x 1.1 x 1.2 m |  |
| `pipe_new_10m` | New 10 m pipe section | 512 | 0.1 MB | 10.0 x 1.1 x 1.1 m |  |
| `pipe_10m` | Generic painted pipeline pipe 10 m | 64 | 0.1 MB | 10.0 x 1.1 x 1.1 m |  |
| `trafficlight_eu_large` | EU traffic light, large mast arm with 3 signal heads | 5,860 | 1.0 MB | 0.6 x 10.4 x 8.4 m |  |
| `trafficlight_eu_medium` | EU traffic light, medium mast arm with 2 straight signal heads | 3,976 | 0.9 MB | 0.6 x 5.2 x 8.2 m |  |
| `trafficlight_eu_short` | EU traffic light on a short pole: car signal head (straight) + pedestrian head | 5,362 | 1.0 MB | 0.7 x 0.6 x 3.7 m | Car head grafted onto Pivot_TrafficLight_01 (the game spawns heads at runtime). |
| `trafficlight_eu_pedestrian` | EU pedestrian traffic light on a short pole | 1,882 | 0.9 MB | 0.4 x 0.6 x 3.7 m |  |
| `trafficlight_eu_head_straight` | EU car signal head, 3 lamps, straight | 1,740 | 0.9 MB | 0.5 x 0.3 x 1.0 m |  |
| `trafficlight_eu_head_left` | EU car signal head with left-arrow lenses | 1,740 | 0.9 MB | 0.5 x 0.3 x 1.0 m |  |
| `street_lamp` | EU double-arm street lamp | 1,616 | 0.7 MB | 7.8 x 0.4 x 11.0 m | Taken from the game's "StreetLamp_Double" cargo prefab (stored lying down) and stood upright; lamp-head markers derived from geometry. |

## P2

| id | source | tris | size | joints / notes | known issues |
|---|---|---:|---:|---|---|
| `truck_flatbed` | CAT CT660 6x4 flatbed truck with Palfinger PK 27002 loading crane | 39,911 | 6.1 MB | 10.0 x 3.0 x 3.7 m; limits: crane_boom [0.0, 130.0], crane_jib [0.0, 177.0]; 6 wheels r=0.55 | US-style CAT CT660 (no EU flatbed crane truck with a usable prefab). Crane cylinders static; stabiliser legs not re-parented. |
| `excavation_support` | Trench shoring / excavation support panels (two panels + spreader bracket) | 5,632 | 2.7 MB | 3.0 x 1.1 x 2.0 m |  |
| `tree_beech` | European beech | 6,519 | 1.9 MB | 5.9 x 5.3 x 9.9 m |  |
| `tree_oak` | European oak | 29,246 | 2.9 MB | 8.7 x 9.1 x 7.9 m | TVE vegetation shader colour tint not reproduced (autumn-looking albedo); no wind. |
| `tree_maple` | Red maple | 15,953 | 3.1 MB | 6.8 x 8.3 x 10.0 m | Red maple (autumn colours are the albedo); no wind. |
| `tree_birch` | Birch | 16,076 | 2.6 MB | 13.5 x 12.9 x 15.9 m |  |
| `tree_young` | Young deciduous street tree | 2,464 | 0.3 MB | 2.6 x 2.4 x 4.6 m |  |
| `sign_construction` | German road sign 123 "Arbeitsstelle" (roadworks) on post | 276 | 0.7 MB | 0.1 x 0.9 x 2.8 m |  |
| `sign_tempo30` | German speed limit 30 sign on post | 486 | 0.7 MB | 0.1 x 0.6 x 2.7 m |  |
| `traffic_cone` | Traffic cone / Leitkegel | 584 | 0.4 MB | 0.3 x 0.3 x 0.6 m |  |

## Not delivered (P2)

- `floodlight_tower`: the game only has mesh-only bundles (`DLC2_Floodlighttower`, `FloodLight_20m_01`) that are placed by baked scenes; no prefab binds them to materials, so no faithful export.
- `construction_fence`: no EU construction-fence (Bauzaun) prefab exists; fence meshes are baked into map chunks. `traffic_cone`, `sign_construction` and `excavation_support` were delivered instead.

## Coupling

`tractor_tgx`, `tractor_tgx_heavy`, `truck_traffic_scania` have an empty `fifth_wheel`; `trailer_lowbed` has `kingpin`. Place the trailer so kingpin == fifth_wheel (kingpin is ~7 cm higher than the tractors' fifth wheel at rest; lower the trailer front or accept the gap).

Total assets: 40.
