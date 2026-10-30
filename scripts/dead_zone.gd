class_name DeadZone
extends Node

# Game manager: rounds, spawning, mid-round mutation, win / lose, ambience.
# Milestone 1: 3 rounds in the flooded garage, then the exit opens.
# Milestone 2: the garage win pushes the squad into the collapsed factory —
# 3 forward-only rooms, doors sealing behind you, then the factory win.

const TOTAL_ROUNDS := 3
const FACTORY_ROOMS := 3
const INTERMISSION := 5.0
const TRANSITION_TIME := 4.0
const ROOM_CLEAR_WAIT := 5.0

@onready var player: DeadZonePlayer = get_parent().get_node("Player")
@onready var world: LevelBase = get_parent().get_node("World")
@onready var hud: DeadZoneHUD = get_parent().get_node("HUD")
@onready var sfx: Sfx = get_parent().get_node("Sfx")

var location: String = "garage" # "garage" | "factory"
var round_num: int = 0
var room_num: int = 0
var spawn_queue: Array[String] = []
var spawn_timer: float = 0.0
var round_time: float = 0.0
var mutated_this_round: bool = false
var special_spawned: bool = false
var intermission_timer: float = 0.0
var transition_timer: float = 0.0
var room_clear_timer: float = 0.0
var state: String = "intermission" # "intermission" | "fighting" | "transition" | "room_clear" | "won" | "lost"
var _drip_timer: float = 2.0
var _groan_timer: float = 6.0

# Debug / self-test hooks (env-gated, inert in normal play):
# DZ_SELFTEST=1 auto-plays (aims, shoots, throws grenades, places traps) and
# prints progress lines; DZ_SHOT=1 saves viewport frames to /tmp.
var _selftest: bool = false
var _elapsed: float = 0.0
var _shot_marks: Array = [8.0, 30.0, 75.0, 150.0]
var _shots_done: Array = []
# Third-person captures (hero + Bombies in frame) for visual judging.
var _portrait: bool = false # DZ_PORTRAIT=1: factory portrait shoot, no combat
var _portrait_done: bool = false
var _hero_shot: bool = false # DZ_HERO=1: front portrait of the hazmat hero, no combat
var _garage_shot: bool = false # DZ_GARAGE_SHOT=1: high-angle garage shot, no combat
var _tps_shot: bool = false # DZ_TPS_SHOT=1: staged TPS shot, hero + Bombie in garage
var _bombie_shot: bool = false # DZ_BOMBIE=1: close Bombie portrait, no combat
var _face_shot: bool = false # DZ_FACE=1: close hero-face portrait behind the visor, no combat
var _survivor_shot: bool = false # DZ_SURVIVOR_FACE=1: close survivor bare-face portrait, no combat
var _veteran_shot: bool = false # DZ_VETERAN_FACE=1: close veteran face portrait, no combat
var _macro_shot: bool = false # DZ_MACRO=1: macro survivor face, camera 0.5 m out, no combat
var _arm_shot: bool = false # DZ_ARM=1: close-up of a Bombie's bare outstretched forearm (veins), no combat
var _weapon_shot: bool = false # DZ_WEAPON=1: FPS viewmodel close-up (gunmetal), no combat
var _head_shot: bool = false # DZ_HEAD=1: veteran 3/4 head shot (ear + helmet cap), no combat
var _car_shot: bool = false # DZ_CAR=1: close car shot (wheels, glass, seams), no combat
var _wall_shot: bool = false # DZ_WALL=1: close concrete wall shot, no combat
var _sky_shot: bool = false # DZ_SKY=1: camera above the garage looking at the cloudy sky, no combat
var _tree_shot: bool = false # DZ_TREE=1: staged tree assets on open ground, no combat
var _head_side_shot: bool = false # DZ_HEAD_SIDE=1: veteran profile from -X (his left side, the circled side), no combat
var _bombie_side_shot: bool = false # DZ_BOMBIE_SIDE=1: Bombie profile from +X (its left side), no combat
var _hands_shot: bool = false # DZ_HANDS=1: Bombie hands close-up (fingers, knuckles, veins), no combat
var _feet_shot: bool = false # DZ_FEET=1: Bombie feet close-up (heel, toe, sole), no combat
var _water_shot: bool = false # DZ_WATER=1: low water shot with a frozen wade splash, no combat
var _water_splashed: bool = false
var _wreckage_shot: bool = false # DZ_WRECKAGE=1: one wreckage pile close-up, no combat
var _sky_storm_shot: bool = false # DZ_SKY_STORM=1: storm-sky panorama, no combat
var _sky_aurora_shot: bool = false # DZ_SKY_AURORA=1: aurora-sky panorama, no combat
var _weapon_sg_shot: bool = false # DZ_WEAPON_SG=1: veteran shotgun FPS viewmodel close-up, no combat
var _weapon_smg_shot: bool = false # DZ_WEAPON_SMG=1: survivor SMG FPS viewmodel close-up, no combat
var _head_back_shot: bool = false # DZ_HEAD_BACK=1: veteran from behind (whole-head back: hair, ears, nape), no combat
var _bombie_back_shot: bool = false # DZ_BOMBIE_BACK=1: Bombie from behind (whole-head back), no combat
var _bombie_back2_shot: bool = false # DZ_BOMBIE_BACK2=1: Bombie back 3/4 diagnostic (parallax check for the back-view green dots), no combat
var _shot_done: bool = false
var _tps_marks: Array = [105.0, 140.0, 175.0]
var _tps_done: Array = []
var _tps_capture_timer: float = -1.0
var _status_timer: float = 0.0
var _test_grenade_timer: float = 12.0
var _test_trap_timer: float = 18.0
var _test_switch_timer: float = 20.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_selftest = OS.has_environment("DZ_SELFTEST")
	player.hud = hud
	player.sfx = sfx
	player.game = self
	# HUD builds its controls in its own _ready, which runs after ours
	# (sibling order), so initialise it deferred.
	call_deferred("_init_hud")
	_portrait = OS.get_environment("DZ_PORTRAIT") == "1"
	if _portrait:
		# Skip the garage: straight to the factory for the portrait shoot.
		call_deferred("_enter_factory")
	_hero_shot = OS.get_environment("DZ_HERO") == "1"
	_garage_shot = OS.get_environment("DZ_GARAGE_SHOT") == "1"
	_tps_shot = OS.get_environment("DZ_TPS_SHOT") == "1"
	_bombie_shot = OS.get_environment("DZ_BOMBIE") == "1"
	_face_shot = OS.get_environment("DZ_FACE") == "1"
	_survivor_shot = OS.get_environment("DZ_SURVIVOR_FACE") == "1"
	_veteran_shot = OS.get_environment("DZ_VETERAN_FACE") == "1"
	_macro_shot = OS.get_environment("DZ_MACRO") == "1"
	_arm_shot = OS.get_environment("DZ_ARM") == "1"
	_weapon_shot = OS.get_environment("DZ_WEAPON") == "1"
	_head_shot = OS.get_environment("DZ_HEAD") == "1"
	_car_shot = OS.get_environment("DZ_CAR") == "1"
	_wall_shot = OS.get_environment("DZ_WALL") == "1"
	_sky_shot = OS.get_environment("DZ_SKY") == "1"
	_tree_shot = OS.get_environment("DZ_TREE") == "1"
	_head_side_shot = OS.get_environment("DZ_HEAD_SIDE") == "1"
	_bombie_side_shot = OS.get_environment("DZ_BOMBIE_SIDE") == "1"
	_hands_shot = OS.get_environment("DZ_HANDS") == "1"
	_feet_shot = OS.get_environment("DZ_FEET") == "1"
	_water_shot = OS.get_environment("DZ_WATER") == "1"
	_wreckage_shot = OS.get_environment("DZ_WRECKAGE") == "1"
	_sky_storm_shot = OS.get_environment("DZ_SKY_STORM") == "1"
	_sky_aurora_shot = OS.get_environment("DZ_SKY_AURORA") == "1"
	_weapon_sg_shot = OS.get_environment("DZ_WEAPON_SG") == "1"
	_weapon_smg_shot = OS.get_environment("DZ_WEAPON_SMG") == "1"
	_head_back_shot = OS.get_environment("DZ_HEAD_BACK") == "1"
	_bombie_back_shot = OS.get_environment("DZ_BOMBIE_BACK") == "1"
	_bombie_back2_shot = OS.get_environment("DZ_BOMBIE_BACK2") == "1"
	_setup_sky()
	if _hero_shot:
		call_deferred("_setup_hero_shot")
	if _garage_shot:
		call_deferred("_setup_garage_shot")
	if _tps_shot:
		call_deferred("_setup_tps_shot")
	if _bombie_shot:
		call_deferred("_setup_bombie_shot")
	if _face_shot:
		call_deferred("_setup_face_shot")
	if _survivor_shot:
		call_deferred("_setup_survivor_face_shot")
	if _veteran_shot:
		call_deferred("_setup_veteran_face_shot")
	if _macro_shot:
		call_deferred("_setup_macro_shot")
	if _arm_shot:
		call_deferred("_setup_arm_shot")
	if _weapon_shot:
		call_deferred("_setup_weapon_shot")
	if _head_shot:
		call_deferred("_setup_head_shot")
	if _car_shot:
		call_deferred("_setup_car_shot")
	if _wall_shot:
		call_deferred("_setup_wall_shot")
	if _sky_shot:
		call_deferred("_setup_sky_shot")
	if _tree_shot:
		call_deferred("_setup_tree_shot")
	if _head_side_shot:
		call_deferred("_setup_head_side_shot")
	if _bombie_side_shot:
		call_deferred("_setup_bombie_side_shot")
	if _head_back_shot:
		call_deferred("_setup_head_back_shot")
	if _bombie_back_shot:
		call_deferred("_setup_bombie_back_shot")
	if _bombie_back2_shot:
		call_deferred("_setup_bombie_back2_shot")
	if _hands_shot:
		call_deferred("_setup_hands_shot")
	if _feet_shot:
		call_deferred("_setup_feet_shot")
	if _water_shot:
		call_deferred("_setup_water_shot")
	if _wreckage_shot:
		call_deferred("_setup_wreckage_shot")
	if _sky_storm_shot:
		call_deferred("_setup_sky_storm_shot")
	if _sky_aurora_shot:
		call_deferred("_setup_sky_aurora_shot")
	if _weapon_sg_shot:
		call_deferred("_setup_weapon_sg_shot")
	if _weapon_smg_shot:
		call_deferred("_setup_weapon_smg_shot")
	intermission_timer = 3.0
	state = "intermission"

func _setup_sky() -> void:
	# Open-air views use the cloudy-sky photograph as the sky. The garage
	# and factory are enclosed boxes, so this never shows inside them —
	# it only appears where a camera can see out (and in the staged sky
	# shot). The photo is a cloud panorama, not a true equirectangular
	# capture, so it stretches near the zenith; from ground level it
	# reads as overcast sky.
	_set_sky_texture("res://assets/textures/media-generation-cloudy-sky-texture-0-c11783ec-90cc-423e-a3ff-6e9432b7a7ff.webp")

func _set_sky_texture(path: String) -> void:
	# Swap the environment sky to any panorama texture (cloudy default,
	# storm, aurora). Re-duplicating the current environment keeps the
	# fog_sky_affect = 0 fix from _setup_sky.
	var env_node := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null or env_node.environment == null:
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = tex
	sky.sky_material = pano
	# Assign a fresh Environment to the WorldEnvironment node instead of
	# mutating the scene's sub-resource in place: the assignment path is
	# what pushes the new background into the rendering scenario.
	var new_env := env_node.environment.duplicate() as Environment
	new_env.background_mode = Environment.BG_SKY
	new_env.sky = sky
	# Fog would otherwise swallow the sky whole: the sky sits at infinite
	# distance, so with fog_sky_affect at its default 1.0 the panorama
	# fogs 100% toward the near-black fog colour and renders black. Zero
	# here keeps the garage haze on geometry while the sky shows clouds.
	new_env.fog_sky_affect = 0.0
	env_node.environment = new_env

func _setup_hero_shot() -> void:
	# Front portrait of the hazmat hero, clean frame (no HUD), camera 2.4 m
	# in front at chest height — the concept picture's framing. A warm fill
	# light in front of the hero (portrait only) makes the suit, visor,
	# mask, hose and chest rig readable against the dark garage.
	hud.visible = false
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var hp: Vector3 = player.global_position
	player.set_showcase_camera(hp + Vector3(0, 1.45, -1.6), hp + Vector3(0, 1.05, 0))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.4
	fill.omni_range = 7.0
	fill.position = Vector3(0, 2.0, 12.0)
	add_child(fill)
	# Red rim light behind the hero, echoing the picture's red emergency
	# lights on both sides of the frame.
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.15, 0.08)
	rim.light_energy = 1.0
	rim.omni_range = 6.0
	rim.position = Vector3(2.5, 2.5, 15.5)
	add_child(rim)

func _setup_tps_shot() -> void:
	# Staged TPS gameplay shot: hero from behind at the spawn, facing
	# northwest so the west red emergency light is in frame, a shambler
	# shambling in from by the rusted sedan at (-6, 0, 9), HUD on
	# (ROUND 1/3, BOMBIES LEFT, GND/MIN/ACID) — the reference screenshot's
	# framing. The Bombie moves toward the player, so at capture time it
	# is ~4 m ahead, eyes glowing in the dark.
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.8
	player.head.rotation.x = 0.0
	player._set_view("tps")
	_spawn_portrait_bombie("shambler", Vector3(-4, 0, 10))
	# HUD mirrors the reference: round 1 of 3, one Bombie left, 14/30.
	hud.set_round(1, TOTAL_ROUNDS, 1)
	hud.set_ammo(14, 30, 3, 4, 3)

func _setup_bombie_shot() -> void:
	# Close Bombie portrait: a shambler stands facing the camera ~1.1 m
	# away, face at frame centre, HUD hidden, warm fill from the camera
	# side + red rim behind — the skin texture, sockets and glowing eyes
	# must read at this distance. The Bombie's speed is zeroed so it
	# holds still instead of walking into the lens.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var b := Bombie.new()
	b.setup("shambler", 1, player)
	get_parent().add_child(b)
	b.global_position = Vector3(0, 0, 11.8)
	b.speed = 0.0
	b.died.connect(_on_bombie_died)
	player.set_showcase_camera(Vector3(0.12, 1.78, 12.95), Vector3(0, 1.68, 11.8))
	player.hide_hero_body()
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 0.9
	fill.omni_range = 7.0
	# Off-axis, not flat frontal: gentle modeling shadows, so the skin
	# texture and face features model instead of washing out.
	fill.position = Vector3(1.5, 2.2, 13.5)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.15, 0.08)
	rim.light_energy = 1.0
	rim.omni_range = 6.0
	rim.position = Vector3(2.5, 2.5, 10.0)
	add_child(rim)

func _setup_survivor_face_shot() -> void:
	# Bare-face macro demo: the survivor (freckles, hazel eyes, strand
	# hair) faces the camera ~1.1 m away — pores, lip lines, strands,
	# catchlights must read. HUD hidden, warm off-axis fill + red rim.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._switch_to("survivor")
	player.set_showcase_camera(Vector3(0, 1.70, 12.9), Vector3(0, 1.62, 14))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 7.0
	fill.position = Vector3(1.2, 2.0, 12.5)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.15, 0.08)
	rim.light_energy = 1.0
	rim.omni_range = 6.0
	rim.position = Vector3(2.5, 2.5, 15.5)
	add_child(rim)

func _setup_veteran_face_shot() -> void:
	# Veteran face portrait: the veteran (grey hair, cheek scar, stubble,
	# blue-grey eyes) faces the camera ~1.1 m away — the baked photo face
	# under the helmet cap must read as a photograph. HUD hidden, warm
	# off-axis fill + red rim, same rig as the survivor face shot.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._switch_to("veteran")
	player.set_showcase_camera(Vector3(0, 1.74, 12.9), Vector3(0, 1.66, 14))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 7.0
	fill.position = Vector3(1.2, 2.0, 12.5)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.15, 0.08)
	rim.light_energy = 1.0
	rim.omni_range = 6.0
	rim.position = Vector3(2.5, 2.5, 15.5)
	add_child(rim)

func _setup_face_shot() -> void:
	# Close hero-face portrait: the hazmat hero faces the camera ~1.1 m
	# away — the face behind the green visor must read as a real face
	# with skin texture, not a flat fill. HUD hidden, warm fill + red rim.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player.set_showcase_camera(Vector3(0, 1.74, 12.9), Vector3(0, 1.68, 14))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.4
	fill.omni_range = 7.0
	fill.position = Vector3(0, 2.0, 12.5)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.15, 0.08)
	rim.light_energy = 1.0
	rim.omni_range = 6.0
	rim.position = Vector3(2.5, 2.5, 15.5)
	add_child(rim)

func _setup_macro_shot() -> void:
	# Macro demo: the survivor faces the camera 0.5 m away, so the face
	# fills a third of the frame — pores, lip lines, hair strands and
	# catchlights must resolve at this range (the macro-detail bar).
	# HUD hidden, warm off-axis fill + red rim.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._switch_to("survivor")
	player.set_showcase_camera(Vector3(0, 1.70, 13.4), Vector3(0, 1.64, 14))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 7.0
	fill.position = Vector3(1.2, 2.0, 12.5)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.15, 0.08)
	rim.light_energy = 1.0
	rim.omni_range = 6.0
	rim.position = Vector3(2.5, 2.5, 15.5)
	add_child(rim)

func _setup_garage_shot() -> void:
	# High-angle shot from the mezzanine's south edge, straight down the
	# central ramp across the flooded floor — the concept picture's
	# viewpoint: ramp, half-submerged cars, pillars, amber tube, debris.
	# Camera sits above the fence (eye 5.25 m, fence top 4.7 m), in the
	# ramp opening between the fence segments, clear of the pillars at
	# (0,-12) and (-8,-12); HUD and viewmodel hidden for a clean frame.
	hud.visible = false
	player.global_position = Vector3(-4, 3.65, -12.5)
	player.rotation.y = PI
	player.head.rotation.x = -0.5
	player._set_view("fps")
	player._gun_view.visible = false

func _setup_arm_shot() -> void:
	# Arm-vein close-up: a shambler stands still facing the camera, arms
	# out in front — its bare forearm fills the frame, so the veiny-arm
	# photograph (raised veins, pores, fine hairs) must read at ~0.8 m.
	# HUD hidden, warm fill from the camera side.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var b := Bombie.new()
	b.setup("shambler", 1, player)
	get_parent().add_child(b)
	b.global_position = Vector3(0, 0, 11.8)
	b.speed = 0.0
	b.died.connect(_on_bombie_died)
	# Tighter than before: 1.0 m from the left forearm so the taper,
	# veins and torn-flesh band fill the frame instead of the whole body.
	player.set_showcase_camera(Vector3(0.75, 1.35, 13.3), Vector3(0.3, 1.1, 12.45))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.0
	fill.omni_range = 7.0
	fill.position = Vector3(1.2, 2.0, 13.0)
	add_child(fill)

func _setup_weapon_shot() -> void:
	# FPS viewmodel close-up: the improvised gun in first person, so the
	# gunmetal photograph (scratched worn steel, oil sheen) must read on
	# the receiver and pipes instead of a black slab. HUD hidden, warm
	# fill so the metal is lit.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._set_view("fps")
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.0
	fill.omni_range = 7.0
	fill.position = Vector3(0.5, 2.0, 13.0)
	add_child(fill)

func _setup_head_shot() -> void:
	# Whole-head shot, 3/4 angle: the veteran faces the camera from his
	# right side, so one photographic ear AND the helmet cap (olive
	# photograph, scratches, chips) are in frame with the face plate.
	# HUD hidden, warm off-axis fill + red rim, same rig as the face shots.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._switch_to("veteran")
	player.set_showcase_camera(Vector3(0.65, 1.75, 13.1), Vector3(0, 1.68, 14))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 7.0
	fill.position = Vector3(1.2, 2.0, 12.5)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.15, 0.08)
	rim.light_energy = 1.0
	rim.omni_range = 6.0
	rim.position = Vector3(2.5, 2.5, 15.5)
	add_child(rim)

func _setup_car_shot() -> void:
	# Close car shot: FPS camera south-east of the sedan at (-6, 0, 9),
	# looking at it from a 3/4 rear angle so the side (wheels, door
	# seams, side glass) reads, not just the rear. HUD and viewmodel
	# hidden, warm fill so the car is lit.
	hud.visible = false
	player.global_position = Vector3(-4.5, 0.1, 14.5)
	# Face the car: forward for yaw θ is (-sin θ, -cos θ); the car sits
	# north-west of the camera, so θ ≈ 0.27.
	player.rotation.y = 0.27
	player.head.rotation.x = -0.05
	player._set_view("fps")
	player._gun_view.visible = false
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 9.0
	fill.position = Vector3(-6, 2.5, 11.0)
	add_child(fill)

func _setup_wall_shot() -> void:
	# Close concrete-wall shot: FPS camera 2.5 m from the north wall, so
	# the concrete photograph (cracks, damp streaks, stains) must read.
	# HUD and viewmodel hidden, neutral fill so the texture is judged on
	# its own detail, not the red emergency light.
	hud.visible = false
	player.global_position = Vector3(2, 0.1, -15.5)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._set_view("fps")
	player._gun_view.visible = false
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.95, 0.85)
	fill.light_energy = 1.0
	fill.omni_range = 8.0
	fill.position = Vector3(2, 2.5, -14.0)
	add_child(fill)

func _setup_sky_shot() -> void:
	# Sky shot: the showcase camera floats above the garage roof looking
	# mostly horizontally (slightly up), so the frame is the cloudy-sky
	# panorama's horizon band wired into the environment. The garage
	# ceiling blocks any sky view from inside, which is why the camera
	# sits outside. HUD hidden.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player.set_showcase_camera(Vector3(0, 8.0, 14), Vector3(0, 12.0, -30))

func _setup_tree_shot() -> void:
	# Tree asset shot (staged, not gameplay): ONE photographic tree
	# OUTDOORS — east of the garage (x=30, past the 22 m wall) against
	# the sky panorama, on a dark ground disc, camera framing the
	# whole tree. The earlier indoor framing put a 6 m tree inside a
	# ~4 m garage, so the crown clipped the ceiling and read as discs.
	# HUD hidden, warm fill so bark and foliage read.
	# The player stays on the garage floor at spawn: outside the garage
	# there is no floor collision, so a player moved outdoors falls
	# through the void and drags the (child) camera down with it —
	# the first outdoor attempt captured from y=-4.5, under the disc.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var t := TreeModel.build(6.0, 100)
	t.position = Vector3(48, 0, 10)
	get_parent().add_child(t)
	var ground := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 7.0
	gc.bottom_radius = 7.0
	gc.height = 0.1
	ground.mesh = gc
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.15, 0.13)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position = Vector3(48, -0.05, 10)
	get_parent().add_child(ground)
	player.set_showcase_camera(Vector3(48, 2.6, 16), Vector3(50, 3.4, 10))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 12.0
	fill.position = Vector3(48, 4.0, 13.0)
	add_child(fill)

func _setup_head_side_shot() -> void:
	# One-piece-skin gate, side view: the veteran in profile from -X —
	# his LEFT side, the side Danny circled. The head must read as one
	# real head, not a mask: no plate rim, no seam, no doubled face.
	# Same warm fill + red rim rig as the front head shot.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._switch_to("veteran")
	player.set_showcase_camera(Vector3(-1.4, 1.70, 14), Vector3(0, 1.68, 14))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 7.0
	fill.position = Vector3(-1.5, 2.0, 12.5)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.15, 0.08)
	rim.light_energy = 1.0
	rim.omni_range = 6.0
	rim.position = Vector3(2.5, 2.5, 15.5)
	add_child(rim)

func _setup_bombie_side_shot() -> void:
	# One-piece-skin gate for Bombies, side view: a shambler in profile
	# from +X — its LEFT side (it faces +Z toward the player). Gaunt
	# photographic face must be the head's own skin, glow integrated.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var b := Bombie.new()
	b.setup("shambler", 1, player)
	get_parent().add_child(b)
	b.global_position = Vector3(0, 0, 11.8)
	b.speed = 0.0
	b.died.connect(_on_bombie_died)
	player.set_showcase_camera(Vector3(0.9, 1.70, 11.8), Vector3(0, 1.68, 11.8))
	player.hide_hero_body()
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.0
	fill.omni_range = 7.0
	fill.position = Vector3(1.5, 2.0, 12.5)
	add_child(fill)

func _setup_head_back_shot() -> void:
	# Whole-head gate, BACK view: the veteran from behind — the back
	# of the head must read as one real head (hair, both ears from
	# behind, nape), no seam at the back, no plate edge. Same warm
	# fill + red rim rig as the other head shots.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._switch_to("veteran")
	player.set_showcase_camera(Vector3(0, 1.70, 15.4), Vector3(0, 1.68, 14))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 7.0
	fill.position = Vector3(-1.5, 2.0, 15.5)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.15, 0.08)
	rim.light_energy = 1.0
	rim.omni_range = 6.0
	rim.position = Vector3(2.5, 2.5, 12.5)
	add_child(rim)

func _setup_bombie_back_shot() -> void:
	# Whole-head gate, BACK view: a shambler from behind — back of
	# the head (hair, nape, ears from behind), no seam, no doubled
	# face, glow not visible from behind (eyes face forward).
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var b := Bombie.new()
	b.setup("shambler", 1, player)
	get_parent().add_child(b)
	b.global_position = Vector3(0, 0, 11.8)
	b.speed = 0.0
	b.died.connect(_on_bombie_died)
	player.set_showcase_camera(Vector3(0, 1.70, 10.9), Vector3(0, 1.68, 11.8))
	player.hide_hero_body()
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.0
	fill.omni_range = 7.0
	fill.position = Vector3(1.5, 2.0, 10.5)
	add_child(fill)

func _setup_bombie_back2_shot() -> void:
	# Diagnostic twin of the back shot: same shambler, camera off-axis
	# and closer (back-right 3/4). If the back view's green dots are a
	# distant background light (exit sign) they shift with parallax or
	# vanish; if they are glued to the head they stay at the neck.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var b := Bombie.new()
	b.setup("shambler", 1, player)
	get_parent().add_child(b)
	b.global_position = Vector3(0, 0, 11.8)
	b.speed = 0.0
	b.died.connect(_on_bombie_died)
	player.set_showcase_camera(Vector3(0.5, 1.75, 11.0), Vector3(0, 1.70, 11.8))
	player.hide_hero_body()
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.0
	fill.omni_range = 7.0
	fill.position = Vector3(1.5, 2.0, 10.5)
	add_child(fill)

func _setup_hands_shot() -> void:
	# Hands gate: a shambler stands still, arms out in front, camera
	# close on one hand — separate fingers with knuckles, palm lines,
	# veins and wrinkles must read against Danny's hands photos.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var b := Bombie.new()
	b.setup("shambler", 1, player)
	get_parent().add_child(b)
	b.global_position = Vector3(0, 0, 11.8)
	b.speed = 0.0
	b.died.connect(_on_bombie_died)
	player.set_showcase_camera(Vector3(0.6, 1.35, 13.2), Vector3(0.0, 1.15, 12.2))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 7.0
	fill.position = Vector3(1.0, 2.0, 12.8)
	add_child(fill)

func _setup_feet_shot() -> void:
	# Feet gate: a shambler stands still, camera low at foot height —
	# heel, foot body, toe and sole must read as feet, never squares.
	# NOTE: the Bombie stands on the MEZZANINE, not the garage floor —
	# the floor is flooded (water y=0.14) and the feet would be
	# submerged in murk; the mezzanine platform top (y=3.6) is dry.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var b := Bombie.new()
	b.setup("shambler", 1, player)
	get_parent().add_child(b)
	b.global_position = Vector3(-4, 3.6, -15)
	b.speed = 0.0
	b.died.connect(_on_bombie_died)
	# Feet gate, CLOSE: the old camera sat 1.9 m out, so the boots
	# read as distant smudges. Camera 0.8 m out, just above foot
	# height, looking down at the feet — heel, foot body, toe and
	# sole must fill the frame.
	player.set_showcase_camera(Vector3(-3.6, 3.78, -14.2), Vector3(-4, 3.64, -15))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.0
	fill.omni_range = 7.0
	fill.position = Vector3(-2.5, 4.6, -13.0)
	add_child(fill)

func _setup_water_shot() -> void:
	# Water gate: camera low over the flood water looking across it, so
	# ripples, sparkle and the planar reflection read. The wade splash
	# is spawned just before capture (see _selftest_tick) so droplets
	# read frozen mid-air, kingfisher-style. HUD hidden.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player.set_showcase_camera(Vector3(1.5, 1.0, 0.8), Vector3(0, 0.14, -1))

func _setup_wreckage_shot() -> void:
	# Wreckage gate: one scrap pile built at a fixed spot (no RNG hunt)
	# — crushed car body, twisted panels, cables, motor, gear, rotor —
	# camera close so every distinct rusted piece reads.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	var world := get_parent().get_node_or_null("World")
	if world != null and world.has_method("build_wreckage_pile"):
		var rust := StandardMaterial3D.new()
		rust.albedo_texture = load("res://assets/textures/media-generation-rusted-car-texture-0-0e20dbdc-aedb-4cbd-96af-1f893241d2ea.webp")
		rust.roughness = 0.8
		rust.metallic = 0.15
		var parts := StandardMaterial3D.new()
		parts.albedo_texture = load("res://assets/textures/danny-crops/rust-parts-crop.webp")
		parts.roughness = 0.8
		parts.metallic = 0.15
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.06, 0.06, 0.06)
		dark.roughness = 0.9
		var pile := Node3D.new()
		pile.position = Vector3(0, 0, 10)
		world.add_child(pile)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		world.build_wreckage_pile(pile, rust, parts, dark, rng)
	player.set_showcase_camera(Vector3(0, 0.85, 11.9), Vector3(0, 0.5, 10))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.2
	fill.omni_range = 8.0
	fill.position = Vector3(1.0, 2.5, 11.5)
	add_child(fill)

func _setup_sky_storm_shot() -> void:
	# Storm-sky panorama (Danny's clean storm-sea photo, mirror-wrapped):
	# same above-roof camera as the overcast sky shot.
	_set_sky_texture("res://assets/textures/danny-crops/storm-sky-pano.webp")
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player.set_showcase_camera(Vector3(0, 8.0, 14), Vector3(0, 12.0, -30))

func _setup_sky_aurora_shot() -> void:
	# Aurora-sky panorama (Danny's clean aurora photo, mirror-wrapped):
	# same above-roof camera as the overcast sky shot.
	_set_sky_texture("res://assets/textures/danny-crops/aurora-sky-pano.webp")
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player.set_showcase_camera(Vector3(0, 8.0, 14), Vector3(0, 12.0, -30))

func _setup_weapon_sg_shot() -> void:
	# Veteran shotgun viewmodel close-up: tactical shape must read —
	# pistol grip, vented shroud, ghost ring, extended tube, brake.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._switch_to("veteran")
	player._set_view("fps")
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.0
	fill.omni_range = 7.0
	fill.position = Vector3(0.5, 2.0, 13.0)
	add_child(fill)

func _setup_weapon_smg_shot() -> void:
	# Survivor SMG viewmodel close-up: tan finish, curved mag, vertical
	# foregrip, top rail, red-dot sight must read.
	hud.visible = false
	player.global_position = Vector3(0, 0.1, 14)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player._switch_to("survivor")
	player._set_view("fps")
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.68, 0.38)
	fill.light_energy = 1.0
	fill.omni_range = 7.0
	fill.position = Vector3(0.5, 2.0, 13.0)
	add_child(fill)

func _init_hud() -> void:
	hud.set_hp(player.hp, player.max_hp)
	hud.set_ammo(player.ammo_in_mag, player.mag_size, player.grenades, player.mines, player.toxic_traps)
	hud.set_round(0, TOTAL_ROUNDS, 0)
	hud.set_location("FLOODED GARAGE")
	hud.set_squad(player._squad_status())
	hud.show_message("BOMBIES: DEAD ZONE — hold the flooded garage", 4.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_R and (state == "won" or state == "lost"):
			get_tree().paused = false
			get_tree().reload_current_scene()

func _process(delta: float) -> void:
	_elapsed += delta
	if _selftest:
		_selftest_tick(delta)
	if state == "won" or state == "lost":
		if _selftest:
			var fname := "dz-shot-lose.png"
			if state == "won":
				fname = "dz2-shot-win.png" if location == "factory" else "dz-shot-win.png"
			_capture(fname)
			print("[SELFTEST] %s at t=%.1f %s round=%d room=%d" % [state.to_upper(), _elapsed, location, round_num, room_num])
			get_tree().quit()
		return
	# Ambience: drips and distant groans while the garage breathes.
	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = randf_range(1.5, 5.0)
		sfx.play("drip", -14.0)
	_groan_timer -= delta
	if _groan_timer <= 0.0:
		_groan_timer = randf_range(4.0, 10.0)
		if alive_count() > 0:
			sfx.play("groan", -10.0)
	if state == "transition":
		# Garage cleared: the squad is on the move to the factory.
		transition_timer -= delta
		if transition_timer <= 0.0:
			_enter_factory()
		return
	if state == "room_clear":
		# The next door stands open: the squad must walk through it.
		room_clear_timer -= delta
		if player.global_position.z < world.get_room_trigger_z(room_num + 1):
			world.seal_door(room_num - 1)
			_start_room(room_num + 1)
		elif room_clear_timer <= 0.0:
			room_clear_timer = ROOM_CLEAR_WAIT
			hud.show_message("Push through the open door", 3.0)
		return
	if state == "intermission":
		intermission_timer -= delta
		if intermission_timer <= 0.0:
			_start_round(round_num + 1)
		return
	# Fighting.
	round_time += delta
	spawn_timer -= delta
	if not spawn_queue.is_empty() and spawn_timer <= 0.0:
		spawn_timer = _spawn_interval()
		_spawn_next()
	# Mid-round mutation: after 40 seconds the survivors change.
	if not mutated_this_round and round_time >= 40.0:
		mutated_this_round = true
		var count := 0
		for b in get_tree().get_nodes_in_group("bombie"):
			if b is Bombie:
				(b as Bombie).mutate()
				count += 1
		if count > 0:
			hud.show_message("WARNING: THE BOMBIES ARE MUTATING", 3.5)
			sfx.play("sting", -4.0)
	# Special infected on a timer: first at 45 s into round 2, then one per
	# round — and one per factory room from room 2 on.
	if not special_spawned and round_time >= 45.0:
		var special_round := (location == "garage" and round_num >= 2) or (location == "factory" and room_num >= 2)
		if special_round:
			special_spawned = true
			_spawn_special()
	var alive := alive_count()
	var shown_num := round_num if location == "garage" else room_num
	var shown_total := TOTAL_ROUNDS if location == "garage" else FACTORY_ROOMS
	hud.set_round(shown_num, shown_total, alive + spawn_queue.size())
	if spawn_queue.is_empty() and alive == 0:
		_round_cleared()

func alive_count() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("bombie"):
		if b is Bombie and not (b as Bombie)._dead:
			n += 1
	return n

func _spawn_interval() -> float:
	return maxf(0.55, 1.3 - 0.2 * float(round_num))

func _round_composition(n: int) -> Array[String]:
	var comp: Array[String] = []
	match n:
		1:
			for i in 6:
				comp.append("shambler")
		2:
			for i in 7:
				comp.append("shambler")
			for i in 3:
				comp.append("runner")
		3:
			for i in 8:
				comp.append("shambler")
			for i in 4:
				comp.append("runner")
			for i in 2:
				comp.append("tank")
		_:
			for i in 6:
				comp.append("shambler")
	comp.shuffle()
	return comp

func _start_round(n: int) -> void:
	round_num = n
	round_time = 0.0
	mutated_this_round = false
	special_spawned = false
	spawn_queue = _round_composition(n)
	spawn_timer = 0.5
	state = "fighting"
	hud.show_message("ROUND %d — they know you're here" % n, 3.0)
	sfx.play("sting", -6.0)

func _spawn_next() -> void:
	var type: String = spawn_queue.pop_front()
	var b := Bombie.new()
	# setup() BEFORE add_child: btype must be set when _ready builds the body.
	b.setup(type, round_num if location == "garage" else room_num + 3, player)
	get_parent().add_child(b)
	b.global_position = world.random_spawn_point(player.global_position, 9.0)
	b.died.connect(_on_bombie_died)

func _spawn_special() -> void:
	var b := Bombie.new()
	# setup() BEFORE add_child: btype must be set when _ready builds the body.
	b.setup("exploder", round_num if location == "garage" else room_num + 3, player)
	get_parent().add_child(b)
	b.global_position = world.random_spawn_point(player.global_position, 9.0)
	b.died.connect(_on_bombie_died)
	hud.show_message("WARNING: SOMETHING BIG IS COMING", 3.5)
	sfx.play("sting", -4.0)

func _on_bombie_died(_b: Bombie) -> void:
	pass # counts are derived live from the group

func _round_cleared() -> void:
	if location == "factory":
		_room_cleared()
		return
	if round_num >= TOTAL_ROUNDS:
		_start_factory_transition()
		return
	state = "intermission"
	intermission_timer = INTERMISSION
	hud.show_message("ROUND %d CLEARED — next wave in %d seconds" % [round_num, int(INTERMISSION)], 4.0)
	player.restock()

func _start_factory_transition() -> void:
	state = "transition"
	transition_timer = TRANSITION_TIME
	hud.show_message("GARAGE CLEARED — the squad pushes to the factory", 4.0)
	sfx.play("sting")

func _enter_factory() -> void:
	# Swap the world: the garage goes, the factory comes in.
	_clear_leftover_projectiles()
	if world != null and is_instance_valid(world):
		world.queue_free()
	var factory := Factory.new()
	factory.name = "World"
	get_parent().add_child(factory)
	world = factory
	location = "factory"
	# The full squad assembles at the factory entrance, fresh and healed.
	player.activate_squad()
	player.global_position = factory.get_player_spawn()
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	player.velocity = Vector3.ZERO
	hud.set_location("COLLAPSED FACTORY", "ROOM")
	if _selftest:
		_capture("dz2-factory.png")
		print("[SELFTEST] ENTERED FACTORY at t=%.1f" % _elapsed)
	_start_room(1)

func _start_room(n: int) -> void:
	room_num = n
	round_time = 0.0
	mutated_this_round = false
	special_spawned = false
	world.current_room = n
	spawn_queue = _factory_composition(n)
	spawn_timer = 0.5
	state = "fighting"
	hud.set_round(n, FACTORY_ROOMS, spawn_queue.size())
	hud.show_message("FACTORY — ROOM %d — clear it to move on" % n, 3.0)
	sfx.play("sting", -6.0)
	if _selftest and n > 1:
		_capture("dz2-room%d.png" % n)
	if _portrait and n == 1:
		# Portrait lineup: one of each type, 10-12 m in front of the player
		# so the t=2.0 capture catches them mid-approach, not on top of us.
		_spawn_portrait_bombie("exploder", Vector3(-2.0, 0, -5.0))
		_spawn_portrait_bombie("tank", Vector3(2.0, 0, -5.0))
		_spawn_portrait_bombie("runner", Vector3(0, 0, -7.0))

func _spawn_portrait_bombie(type: String, pos: Vector3) -> void:
	var b := Bombie.new()
	b.setup(type, 1, player)
	get_parent().add_child(b)
	b.global_position = pos
	b.died.connect(_on_bombie_died)

func _room_cleared() -> void:
	if room_num >= FACTORY_ROOMS:
		state = "won"
		world.set_exit_open(true)
		hud.show_message("EXIT OPEN", 4.0)
		hud.show_win("factory")
		sfx.play("sting")
		return
	# Checkpoint: regroup, revive the downed, open the next door.
	player.revive_downed_at_checkpoint()
	player.restock()
	world.open_door(room_num - 1)
	state = "room_clear"
	room_clear_timer = ROOM_CLEAR_WAIT
	hud.show_message("ROOM %d CLEARED — push through the open door" % room_num, 4.0)
	sfx.play("sting", -6.0)

func _factory_composition(n: int) -> Array[String]:
	var comp: Array[String] = []
	match n:
		1:
			for i in 5:
				comp.append("shambler")
			for i in 2:
				comp.append("runner")
		2:
			for i in 6:
				comp.append("shambler")
			for i in 3:
				comp.append("runner")
		3:
			for i in 6:
				comp.append("shambler")
			for i in 4:
				comp.append("runner")
			for i in 2:
				comp.append("tank")
		_:
			for i in 5:
				comp.append("shambler")
	comp.shuffle()
	return comp

func _clear_leftover_projectiles() -> void:
	# Traps / clouds / grenades left in the garage must not linger in the
	# factory, which shares the same coordinate space.
	for child in get_parent().get_children():
		if child is Trap or child is ToxicCloud or child is Grenade:
			child.queue_free()

func _capture(fname: String) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img.save_png("/tmp/" + fname)
	print("[SELFTEST] saved /tmp/" + fname)

func _selftest_tick(delta: float) -> void:
	if _hero_shot or _garage_shot or _tps_shot or _bombie_shot or _face_shot or _survivor_shot or _macro_shot or _veteran_shot or _arm_shot or _weapon_shot or _head_shot or _car_shot or _wall_shot or _sky_shot or _tree_shot or _head_side_shot or _bombie_side_shot or _hands_shot or _feet_shot or _water_shot or _wreckage_shot or _sky_storm_shot or _sky_aurora_shot or _weapon_sg_shot or _weapon_smg_shot or _head_back_shot or _bombie_back_shot or _bombie_back2_shot:
		# Still-life captures: no combat, capture once the camera settles,
		# quit before the first round starts (intermission is 3 s).
		if _water_shot and not _water_splashed and _elapsed >= 1.6:
			# Splash well before capture (not the same frame): the
			# screenshot reads the last rendered frame, so a splash
			# spawned in the capture frame would not be in the image.
			_water_splashed = true
			var world := get_parent().get_node_or_null("World")
			if world != null and world.has_method("spawn_wade"):
				world.spawn_wade(Vector3(0, 0.14, -1))
		if not _shot_done and _elapsed >= 2.0:
			_shot_done = true
			print("[SHOT] cam=", player.camera.global_position)
			var fname := "garage-exact.png"
			if _hero_shot:
				fname = "hero-real.png"
			elif _tps_shot:
				fname = "tps-real.png"
			elif _bombie_shot:
				fname = "bombie-real.png"
			elif _face_shot:
				fname = "hero-face-real.png"
			elif _survivor_shot:
				fname = "survivor-face-real.png"
			elif _veteran_shot:
				fname = "veteran-face-real.png"
			elif _macro_shot:
				fname = "macro-real.png"
			elif _arm_shot:
				fname = "arm-veins.png"
			elif _weapon_shot:
				fname = "weapon-gunmetal.png"
			elif _head_shot:
				fname = "head-whole.png"
			elif _car_shot:
				fname = "car-photo.png"
			elif _wall_shot:
				fname = "wall-photo.png"
			elif _sky_shot:
				fname = "sky-photo.png"
			elif _tree_shot:
				fname = "tree-photo.png"
			elif _head_side_shot:
				fname = "head-side.png"
			elif _bombie_side_shot:
				fname = "bombie-side.png"
			elif _hands_shot:
				fname = "hands-fingers.png"
			elif _feet_shot:
				fname = "feet-shape.png"
			elif _water_shot:
				fname = "water-splash.png"
			elif _wreckage_shot:
				fname = "wreckage-pile.png"
			elif _sky_storm_shot:
				fname = "sky-storm.png"
			elif _sky_aurora_shot:
				fname = "sky-aurora.png"
			elif _weapon_sg_shot:
				fname = "weapon-shotgun.png"
			elif _weapon_smg_shot:
				fname = "weapon-smg.png"
			elif _head_back_shot:
				fname = "head-back.png"
			elif _bombie_back_shot:
				fname = "bombie-back.png"
			elif _bombie_back2_shot:
				fname = "bombie-back2.png"
			_capture(fname)
		if _elapsed >= 2.8:
			get_tree().quit()
		return
	if _portrait:
		# Portrait shoot: stand in TPS, face the lineup, capture, quit.
		player.rotation.y = 0.0
		player.head.rotation.x = 0.0
		player._set_view("tps")
		player._firing = false
		_set_test_move("", false)
		if not _portrait_done and _elapsed >= 2.0:
			_portrait_done = true
			_capture("dz2-portrait.png")
		if _elapsed >= 4.0:
			get_tree().quit()
		return
	for t in _shot_marks:
		if _elapsed >= t and not _shots_done.has(t):
			_shots_done.append(t)
			_capture("dz-shot-%d.png" % int(t))
	# Third-person captures: switch to TPS, let the camera settle a few
	# frames, capture the hero + Bombies, then switch back to FPS.
	for t in _tps_marks:
		if _elapsed >= t and not _tps_done.has(t):
			_tps_done.append(t)
			player._set_view("tps")
			_tps_capture_timer = 0.6
	if _tps_capture_timer > 0.0:
		_tps_capture_timer -= delta
		if _tps_capture_timer <= 0.0:
			_capture("dz2-tps-%d.png" % int(_elapsed))
			player._set_view("fps")
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = 5.0
		print("[SELFTEST] t=%.0f %s round=%d room=%d state=%s alive=%d queue=%d member=%s hp=%.0f ammo=%d gren=%d mines=%d traps=%d" % [
			_elapsed, location, round_num, room_num, state, alive_count(), spawn_queue.size(),
			player.current_member, player.hp, player.ammo_in_mag, player.grenades, player.mines, player.toxic_traps])
	if _elapsed > 450.0:
		print("[SELFTEST] TIMEOUT state=%s %s round=%d room=%d" % [state, location, round_num, room_num])
		get_tree().quit()
		return
	if state == "room_clear":
		# Walk through the open door into the next room: face -Z, move
		# forward, steer onto the doorway centre (x = 0).
		player.rotation.y = 0.0
		player._firing = false
		var px := player.global_position.x
		if px > 0.4:
			_set_test_move("move_left", true)
		elif px < -0.4:
			_set_test_move("move_right", true)
		else:
			_set_test_move("move_forward", true)
		return
	if state == "transition":
		player._firing = false
		_set_test_move("", false)
		return
	if state != "fighting" or not player.alive:
		player._firing = false
		_set_test_move("", false)
		return
	# Long-stall tracking: reset whenever the alive count changes
	# (a kill or a fresh spawn); count up only while fighting with
	# an empty queue and a stable alive count.
	var ac := alive_count()
	if ac != _last_alive:
		_last_alive = ac
		_seek_timer = 0.0
	elif spawn_queue.is_empty() and ac > 0:
		_seek_timer += delta
	# Pick the nearest living Bombie with a clear line of sight; fall back to
	# the nearest overall and strafe until a lane opens up.
	var target: Bombie = null
	var best := 1e9
	var nearest_any: Bombie = null
	var best_any := 1e9
	for b in get_tree().get_nodes_in_group("bombie"):
		if b is Bombie and not (b as Bombie)._dead:
			var d := (b as Bombie).global_position.distance_to(player.global_position)
			if d < best_any:
				best_any = d
				nearest_any = b as Bombie
			if d < best and _has_los(b as Bombie):
				best = d
				target = b as Bombie
	if target != null:
		var dir: Vector3 = target.global_position - player.global_position
		dir.y = 0.0
		player.rotation.y = atan2(-dir.x, -dir.z)
		# Aim the head at the target's chest (matters for Bombies up on the
		# mezzanine: a level ray passes under them).
		var to_chest: Vector3 = (target.global_position + Vector3(0, 1.2, 0)) - player.camera.global_position
		var horiz := Vector2(to_chest.x, to_chest.z).length()
		player.head.rotation.x = clampf(atan2(to_chest.y, horiz), -1.4, 1.4)
		player._firing = true
		# Kite: back away when the target closes in.
		_set_test_move("move_back", best < 6.0)
	else:
		player._firing = false
		if nearest_any != null and _escape_timer <= 0.0 and _seek_phase_timer <= 0.0:
			var dir2: Vector3 = nearest_any.global_position - player.global_position
			dir2.y = 0.0
			player.rotation.y = atan2(-dir2.x, -dir2.z)
		if _seek_phase_timer > 0.0:
			# Wall-follow in progress: push forward, do not re-face.
			_seek_phase_timer -= delta
			_set_test_move("move_forward", true)
			if _seek_phase_timer <= 0.0:
				_seek_timer = 0.0
		elif _seek_timer > 45.0 and nearest_any != null and _escape_timer <= 0.0:
			_seek_phase_timer = 6.0
			_seek_side = not _seek_side
			player.rotation.y += PI / 2.0 if _seek_side else -PI / 2.0
			print("[SELFTEST] SEEK wall-follow from ", player.global_position)
			_set_test_move("move_forward", true)
		elif _escape_timer > 0.0:
			# Escape in progress: back out, turn, push forward.
			# Overrides the normal cycle until the escape ends.
			_escape_timer -= delta
			if _escape_phase == 0:
				_set_test_move("move_back", true)
				if _escape_timer <= 0.0:
					_escape_phase = 1
					_escape_timer = 2.0
					player.rotation.y += 2.1
			else:
				_set_test_move("move_forward", true)
				if _escape_timer <= 0.0:
					_escape_phase = 0
					_unstick_timer = 0.0
					_unstick_pos = player.global_position
		else:
			# No lane: close the distance, then strafe, until a lane opens up.
			var phase := int(_elapsed) % 6
			if phase < 3:
				_set_test_move("move_forward", true)
			elif phase < 5:
				_set_test_move("move_left", true)
			else:
				_set_test_move("move_right", true)
			# Stuck tracking: no meaningful movement while fighting.
			if nearest_any != null:
				if _unstick_pos == Vector3.INF or player.global_position.distance_to(_unstick_pos) > 0.5:
					_unstick_pos = player.global_position
					_unstick_timer = 0.0
				else:
					_unstick_timer += delta
					if _unstick_timer > 8.0:
						_escape_timer = 1.5
						_escape_phase = 0
						_unstick_timer = 0.0
						print("[SELFTEST] UNSTUCK escape from ", player.global_position)
	# Exercise squad switching: rotate members on a timer, and swap off a
	# member who is nearly down.
	_test_switch_timer -= delta
	if _test_switch_timer <= 0.0:
		_test_switch_timer = 22.0
		player.switch_to_next()
	if player.hp < player.max_hp * 0.25:
		player.switch_to_next()
	# Exercise the engineer's kit on a timer (traps are hazmat-only).
	_test_grenade_timer -= delta
	if _test_grenade_timer <= 0.0:
		_test_grenade_timer = 14.0
		player._throw_grenade()
	_test_trap_timer -= delta
	if _test_trap_timer <= 0.0:
		_test_trap_timer = 16.0
		if player.current_member == "hazmat":
			player.trap_selected = "mine" if randf() < 0.5 else "toxic"
			player._place_trap()

var _held_test_move: String = ""
# Harness unstick (test driver only, NOT gameplay): the selftest's
# simple forward/strafe cycle can wedge the player in a pocket
# (pile + car, crate + wall) forever — a human would back out and
# turn. If the player hasn't moved in 8 s while fighting without a
# lane, run an escape: back up 1.5 s, turn ~120°, push forward 2 s.
var _unstick_pos := Vector3.INF
var _unstick_timer := 0.0
var _escape_timer := 0.0
var _escape_phase := 0
# Long-stall seek (test driver only, NOT gameplay): the no-LoS cycle
# faces the nearest Bombie and pushes forward, but a Bombie wedged
# in a pocket (or a player wedged against an obstacle) can stall
# that forever — the player strafes enough that the 8 s unstick
# never fires, yet no lane ever opens. If nothing dies for 45 s
# while fighting with an empty queue, wall-follow: turn 90° (sides
# alternate) and push along the obstacle for 6 s, then re-face and
# retry. A human player sidesteps around the obstacle instead of
# pushing it forever.
var _seek_timer := 0.0
var _last_alive := -1
var _seek_phase_timer := 0.0
var _seek_side := false

func _set_test_move(action: String, pressed: bool) -> void:
	if action == _held_test_move and pressed:
		return
	if _held_test_move != "":
		var up := InputEventAction.new()
		up.action = _held_test_move
		up.pressed = false
		Input.parse_input_event(up)
		_held_test_move = ""
	if pressed and action != "":
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		Input.parse_input_event(ev)
		_held_test_move = action

func _has_los(b: Bombie) -> bool:
	var from: Vector3 = player.camera.global_position
	var to: Vector3 = b.global_position + Vector3(0, 1.2, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 3, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit["collider"] == b

func on_player_down() -> void:
	if state == "lost":
		return
	state = "lost"
	hud.show_lose()
	sfx.play("sting", -2.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
