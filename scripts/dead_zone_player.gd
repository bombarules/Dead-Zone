class_name DeadZonePlayer
extends PlayerController

# The rogue hazmat engineer: hitscan rifle, toxic grenades, proximity mines and
# acid traps. V toggles first/third person; right mouse aims down sights.

var max_hp: float = 100.0
var hp: float = 100.0
var alive: bool = true

var mag_size: int = 30
var ammo_in_mag: int = 30
var reload_time: float = 1.4
var fire_interval: float = 0.13
var weapon_damage: float = 34.0

var grenades: int = 3
var mines: int = 4
var toxic_traps: int = 3
var trap_selected: String = "mine"

# Squad (Milestone 2): three members, one controlled body. The active member's
# stats live in the plain vars above (hp, weapon_damage, ...); each member's
# own pool is saved on switch so HP / gear persist per member.
const MEMBERS := {
	"hazmat": {"name": "HAZMAT", "max_hp": 100.0, "walk": 5.0, "sprint": 8.0, "weapon": "improvised", "damage": 34.0, "interval": 0.13, "mag": 30, "pellets": 1, "spread": 0.0, "grenade_kind": "toxic", "grenades": 3, "mines": 4, "traps": 3, "suit": Color(0.85, 0.68, 0.08), "accent": Color(0.1, 0.9, 0.4)},
	"veteran": {"name": "VETERAN", "max_hp": 150.0, "walk": 4.6, "sprint": 7.2, "weapon": "shotgun", "damage": 18.0, "interval": 0.75, "mag": 6, "pellets": 6, "spread": 0.06, "grenade_kind": "frag", "grenades": 3, "mines": 0, "traps": 0, "suit": Color(0.35, 0.38, 0.28), "accent": Color(0.9, 0.2, 0.15)},
	"survivor": {"name": "SURVIVOR", "max_hp": 70.0, "walk": 6.0, "sprint": 10.5, "weapon": "smg", "damage": 18.0, "interval": 0.07, "mag": 40, "pellets": 1, "spread": 0.02, "grenade_kind": "none", "grenades": 0, "mines": 0, "traps": 0, "suit": Color(0.55, 0.15, 0.15), "accent": Color(0.9, 0.75, 0.2)},
}
const MEMBER_ORDER := ["hazmat", "veteran", "survivor"]

var current_member: String = "hazmat"
var squad_available: Array[String] = ["hazmat"] # factory unlocks the full squad
var _member_hp: Dictionary = {}
var _member_down: Dictionary = {}
var _member_grenades: Dictionary = {}
var _member_mines: Dictionary = {}
var _member_traps: Dictionary = {}
var _invuln_timer: float = 0.0
var _slide_timer: float = 0.0

var view_mode: String = "fps" # "fps" | "tps"
var aiming: bool = false

var _fire_timer: float = 0.0
var _reload_timer: float = 0.0
var _grenade_timer: float = 0.0
var _trap_timer: float = 0.0
var _splash_timer: float = 0.0
var _walk_phase: float = 0.0
var _base_walk_speed: float = 5.0
var _base_sprint_speed: float = 8.0

var _hero: Node3D
var _hero_leg_l: Node3D
var _hero_leg_r: Node3D
var _hero_arm_l: Node3D
var _hero_arm_r: Node3D
var _hero_gun: Node3D = null
var _showcase := false # portrait mode: fixed front camera, hang-gun pose
var _showcase_pos := Vector3.ZERO
var _showcase_look := Vector3.ZERO
var _gun_view: Node3D
var _muzzle: Node3D
var _muzzle_flash: OmniLight3D
var _tps_cam_offset := Vector3(0.85, 0.6, 3.4)
var _flashlight: SpotLight3D
var _firing: bool = false

var hud: DeadZoneHUD = null
var sfx: Sfx = null
var game: DeadZone = null

func _ready() -> void:
	super._ready()
	add_to_group("player")
	for id in MEMBER_ORDER:
		var prof: Dictionary = MEMBERS[id]
		_member_hp[id] = float(prof["max_hp"])
		_member_down[id] = false
		_member_grenades[id] = int(prof["grenades"])
		_member_mines[id] = int(prof["mines"])
		_member_traps[id] = int(prof["traps"])
	_base_walk_speed = walk_speed
	_base_sprint_speed = sprint_speed
	_build_hero()
	_build_gun_view()
	_apply_member_look()
	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color(1.0, 0.9, 0.7)
	_flashlight.light_energy = 2.5
	_flashlight.spot_range = 18.0
	_flashlight.spot_angle = 32.0
	head.add_child(_flashlight)
	_flashlight.position = Vector3(0, 0.1, 0)
	_muzzle_flash = OmniLight3D.new()
	_muzzle_flash.light_color = Color(1.0, 0.75, 0.3)
	_muzzle_flash.light_energy = 0.0
	_muzzle_flash.omni_range = 5.0
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.28, -0.22, -0.9)
	camera.add_child(_muzzle)
	_muzzle.add_child(_muzzle_flash)
	_set_view("fps")

func _build_hero() -> void:
	# Realistic-proportioned hero (Humanoid): jointed limbs, sphere head,
	# textured worn clothing, backpack, held weapon. Visible in third person.
	# The model faces +Z, so rotate it to face the player's forward (-Z).
	_hero = Node3D.new()
	_hero.name = "HeroBody"
	_hero.rotation.y = PI
	add_child(_hero)
	_rebuild_hero_body()

func _hero_spec(id: String) -> Dictionary:
	# Clothing + gear per member, from the concept board.
	match id:
		"veteran":
			return {"height": 1.85, "bulk": 1.1, "skin": Color(0.66, 0.52, 0.41),
				"eye_color": Color(0.35, 0.42, 0.48), "freckles": 0.15, "skin_seed": "veteran",
				"acne": 0.25, "scar": true, "stubble": true, "face": "veteran",
				"shirt": Color(0.30, 0.30, 0.25), "jacket": Color(0.35, 0.38, 0.28),
				"pants": Color(0.28, 0.28, 0.24), "helmet": true,
				"helmet_color": Color(0.32, 0.34, 0.26), "backpack": true,
				"backpack_color": Color(0.30, 0.28, 0.20), "weapon": "shotgun"}
		"survivor":
			return {"height": 1.72, "skin": Color(0.74, 0.58, 0.47),
				"eye_color": Color(0.30, 0.38, 0.22), "freckles": 0.7, "skin_seed": "survivor",
				"acne": 0.35, "face": "survivor",
				"shirt": Color(0.40, 0.35, 0.32), "jacket": Color(0.55, 0.15, 0.15),
				"pants": Color(0.25, 0.26, 0.30), "hair": true,
				"hair_color": Color(0.20, 0.14, 0.08), "backpack": true,
				"backpack_color": Color(0.25, 0.22, 0.16), "weapon": "smg"}
		_:
			return {"height": 1.78, "skin": Color(0.70, 0.54, 0.42),
				"eye_color": Color(0.30, 0.20, 0.12), "freckles": 0.3, "skin_seed": "hazmat",
				"acne": 0.3,
				"shirt": Color(0.85, 0.68, 0.08), "jacket": Color(0.85, 0.68, 0.08),
				"pants": Color(0.70, 0.55, 0.10), "visor": true, "face": "hero",
				"visor_color": Color(0.1, 0.9, 0.4), "hood": true,
				"hood_color": Color(0.85, 0.68, 0.08), "backpack": true,
				"backpack_color": Color(0.35, 0.35, 0.33), "weapon": "improvised",
				"hazmat": true}

func _rebuild_hero_body() -> void:
	for child in _hero.get_children():
		child.free()
	var built: Dictionary = Humanoid.build(_hero_spec(current_member))
	_hero.add_child(built["root"])
	_hero_leg_l = built["leg_l"]
	_hero_leg_r = built["leg_r"]
	_hero_arm_l = built["arm_l"]
	_hero_arm_r = built["arm_r"]
	_hero_gun = built["gun"] as Node3D
	_hero_arm_l.rotation.x = -0.7 # left hand reaches the weapon foregrip
	_hero_arm_r.rotation.x = -1.0 # right arm holds the weapon forward

func _mk(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _build_gun_view() -> void:
	# First-person viewmodel: cylinder barrel + receiver, per member weapon.
	_gun_view = Node3D.new()
	_gun_view.position = Vector3(0.30, -0.26, -0.68)
	# Slight yaw so the gun's side details (tank, wire, gauge, mag)
	# face the camera instead of the receiver box filling the frame
	# edge-on; aiming is camera-centred, so this is cosmetic only.
	_gun_view.rotation.y = -0.18
	camera.add_child(_gun_view)
	Humanoid.build_gun_view(_gun_view, String(MEMBERS[current_member]["weapon"]), MEMBERS[current_member]["accent"])

func _set_view(mode: String) -> void:
	view_mode = mode
	_hero.visible = (mode == "tps")
	_gun_view.visible = (mode == "fps")
	if mode == "fps":
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
	if hud != null:
		hud.show_message("Third-person view" if mode == "tps" else "First-person view")

func set_showcase_camera(pos: Vector3, look: Vector3) -> void:
	# Portrait mode (DZ_HERO): fixed camera in front of the hero, hero in
	# third person, arms hanging at the sides with the improvised gun held
	# down at the right side — the concept picture's pose. The walk cycle
	# is skipped in showcase mode so the pose holds.
	_showcase = true
	_showcase_pos = pos
	_showcase_look = look
	_set_view("tps")
	_hero.visible = true
	_gun_view.visible = false
	_hero_arm_l.rotation.x = 0.06
	_hero_arm_r.rotation.x = -0.12
	_hero_arm_l.rotation.z = -0.08
	_hero_arm_r.rotation.z = 0.08
	if _hero_gun != null:
		# Held angled across the thigh, barrel down-forward, hand at the
		# gun's middle, tucked against the body — the picture's carry,
		# not a vertical pillar floating beside the hero.
		_hero_gun.position = Vector3(0.28, 1.05, 0.16)
		_hero_gun.rotation = Vector3(-1.1, -0.25, 0.45)

func hide_hero_body() -> void:
	# Staged Bombie shots are about the Bombie: the hero body stands at
	# the player position, and from the straight-back camera he lines up
	# directly behind the Bombie — his green visor peeks around the
	# Bombie's neck and reads as eye glow bleeding through the head
	# (proven by parallax: the off-axis back shot shows the visor on
	# the hero, and the Bombie's head clean). Hide him for Bombie shots.
	_hero.visible = false

# --- squad --------------------------------------------------------------------

func _save_member_state() -> void:
	_member_hp[current_member] = hp
	_member_grenades[current_member] = grenades
	_member_mines[current_member] = mines
	_member_traps[current_member] = toxic_traps

func _load_member_state(id: String) -> void:
	var prof: Dictionary = MEMBERS[id]
	current_member = id
	max_hp = float(prof["max_hp"])
	hp = float(_member_hp[id])
	weapon_damage = float(prof["damage"])
	fire_interval = float(prof["interval"])
	mag_size = int(prof["mag"])
	ammo_in_mag = mag_size
	grenades = int(_member_grenades[id])
	mines = int(_member_mines[id])
	toxic_traps = int(_member_traps[id])
	_base_walk_speed = float(prof["walk"])
	_base_sprint_speed = float(prof["sprint"])
	_apply_member_look()
	if hud != null:
		hud.set_hp(hp, max_hp)
		hud.set_ammo(ammo_in_mag, mag_size, grenades, mines, toxic_traps)
		hud.set_squad(_squad_status())

func _apply_member_look() -> void:
	# Rebuild the hero body + FPS viewmodel for the current member (new suit,
	# gear, helmet/hair, backpack, weapon) — realistic-proportioned, textured.
	if _hero != null:
		_rebuild_hero_body()
	if _gun_view != null:
		Humanoid.build_gun_view(_gun_view, String(MEMBERS[current_member]["weapon"]), MEMBERS[current_member]["accent"])

func _squad_status() -> Array:
	var out: Array = []
	for id in squad_available:
		var live_hp := hp if id == current_member else float(_member_hp[id])
		out.append({
			"name": String(MEMBERS[id]["name"]),
			"hp": 0.0 if bool(_member_down[id]) else live_hp,
			"max_hp": float(MEMBERS[id]["max_hp"]),
			"down": bool(_member_down[id]),
			"controlled": id == current_member,
		})
	return out

func switch_to_next() -> void:
	if squad_available.size() <= 1:
		return
	var idx := squad_available.find(current_member)
	for i in range(1, squad_available.size() + 1):
		var cand: String = squad_available[(idx + i) % squad_available.size()]
		if not bool(_member_down[cand]):
			_switch_to(cand)
			return
	if hud != null:
		hud.show_message("No other squad member is up")

func _switch_to(id: String) -> void:
	if id == current_member or bool(_member_down[id]):
		return
	_save_member_state()
	_load_member_state(id)
	_invuln_timer = 1.0
	if hud != null:
		hud.show_message("Now controlling: %s" % String(MEMBERS[id]["name"]))
	if sfx != null:
		sfx.play("beep", -6.0)

func activate_squad() -> void:
	# The veteran and survivor join at the factory entrance.
	squad_available = ["hazmat", "veteran", "survivor"]
	heal_all()
	if hud != null:
		hud.set_squad(_squad_status())
		hud.show_message("SQUAD ASSEMBLED — Tab switches members", 4.0)

func heal_all() -> void:
	for id in MEMBER_ORDER:
		_member_hp[id] = float(MEMBERS[id]["max_hp"])
		_member_down[id] = false
		_member_grenades[id] = int(MEMBERS[id]["grenades"])
		_member_mines[id] = int(MEMBERS[id]["mines"])
		_member_traps[id] = int(MEMBERS[id]["traps"])
	_load_member_state(current_member)

func revive_downed_at_checkpoint() -> void:
	# Room clear: the squad regroups. Downed members get back up at half
	# health — three quarters if the veteran (field care) is still standing.
	_save_member_state()
	var veteran_up := squad_available.has("veteran") and not bool(_member_down["veteran"])
	var frac := 0.75 if veteran_up else 0.5
	var revived: Array[String] = []
	for id in squad_available:
		if bool(_member_down[id]):
			_member_down[id] = false
			_member_hp[id] = float(MEMBERS[id]["max_hp"]) * frac
			revived.append(String(MEMBERS[id]["name"]))
	if not revived.is_empty():
		if hud != null:
			hud.show_message("SQUAD REGROUPS — %s back up" % ", ".join(revived))
	_load_member_state(current_member)

func restock() -> void:
	_save_member_state()
	for id in squad_available:
		_member_grenades[id] = mini(int(_member_grenades[id]) + 1, 5)
		if id == "hazmat":
			_member_mines[id] = mini(int(_member_mines[id]) + 1, 6)
			_member_traps[id] = mini(int(_member_traps[id]) + 1, 5)
	_load_member_state(current_member)

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if not alive:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_firing = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			aiming = mb.pressed
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_R:
				_start_reload()
			KEY_G:
				_throw_grenade()
			KEY_1:
				trap_selected = "mine"
				_place_trap()
			KEY_2:
				trap_selected = "toxic"
				_place_trap()
			KEY_Q:
				_place_trap()
			KEY_V:
				_set_view("tps" if view_mode == "fps" else "fps")
			KEY_F:
				_flashlight.visible = not _flashlight.visible
			KEY_TAB:
				switch_to_next()

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_invuln_timer -= delta
	# Water wading: shallow water slows the player; Bombies runners don't care.
	var in_water := global_position.y < 0.35
	var wading := 0.8 if in_water else 1.0
	# Survivor slide: sprint + Ctrl for a short burst with a low profile.
	_slide_timer -= delta
	if current_member == "survivor" and _slide_timer <= 0.0 and Input.is_key_pressed(KEY_CTRL) and Input.is_action_pressed("sprint") and is_on_floor():
		_slide_timer = 0.7
	var slide_boost := 1.6 if _slide_timer > 0.0 else 1.0
	walk_speed = _base_walk_speed * wading * slide_boost
	sprint_speed = _base_sprint_speed * wading * slide_boost
	if _slide_timer > 0.0:
		head.position.y = lerpf(head.position.y, 1.15, delta * 12.0)
	else:
		head.position.y = lerpf(head.position.y, 1.6, delta * 12.0)
	super._physics_process(delta)
	_fire_timer -= delta
	_reload_timer -= delta
	_grenade_timer -= delta
	_trap_timer -= delta
	if _reload_timer <= 0.0 and _firing and ammo_in_mag > 0:
		_shoot()
	if _reload_timer > 0.0 and ammo_in_mag == 0:
		pass
	# Walk cycle for the third-person hero + water splash sounds.
	var planar := Vector2(velocity.x, velocity.z).length()
	_walk_phase += planar * delta * 1.9
	var swing := sin(_walk_phase) * clampf(planar / 4.0, 0.0, 1.0) * 0.5
	if _hero.visible and not _showcase:
		_hero_leg_l.rotation.x = swing
		_hero_leg_r.rotation.x = -swing
		_hero_arm_l.rotation.x = -0.7 + swing * 0.2
		_hero_arm_r.rotation.x = -1.0 + swing * 0.2
	if in_water and planar > 1.0:
		_splash_timer -= delta
		if _splash_timer <= 0.0:
			_splash_timer = 0.55
			if sfx != null:
				sfx.play("splash", -12.0)
			# Wade splash, kingfisher-style: droplets + ripple ring at
			# the feet. Defensive: only the garage level has spawn_wade.
			var world := get_parent().get_node_or_null("World")
			if world != null and world.has_method("spawn_wade"):
				world.spawn_wade(Vector3(global_position.x, 0.14, global_position.z))
	# ADS: narrow the FOV and steady the viewmodel.
	var target_fov := 50.0 if aiming else 70.0
	if absf(camera.fov - target_fov) > 0.2:
		camera.fov = lerpf(camera.fov, target_fov, delta * 10.0)
	if view_mode == "fps":
		var target_x := -0.26 if aiming else 0.0
		_gun_view.position.x = lerpf(_gun_view.position.x, 0.30 + target_x, delta * 10.0)
	# Third-person camera: over-the-shoulder boom behind the player — or the
	# fixed portrait camera in showcase mode.
	if view_mode == "tps":
		if _showcase:
			camera.global_position = camera.global_position.lerp(_showcase_pos, 1.0 - pow(0.001, delta))
			camera.look_at(_showcase_look, Vector3.UP)
		else:
			_update_tps_camera(delta)

func _update_tps_camera(delta: float) -> void:
	# Camera sits behind + right of the player, looking along the head pitch.
	var yaw := rotation.y
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dist := 2.1 if aiming else _tps_cam_offset.z
	var off := 0.45 if aiming else _tps_cam_offset.x
	var eye: Vector3 = global_position + Vector3(0, 1.7, 0)
	var desired: Vector3 = eye + back * dist + right * off + Vector3(0, _tps_cam_offset.y - 1.0, 0)
	# Pull the camera in when a wall is behind the player, so it never ends
	# up inside the geometry (ray from the eye, world layer only, self excluded).
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, desired)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var hit_dist: float = (hit["position"] as Vector3).distance_to(eye)
		var dir := (desired - eye).normalized()
		desired = eye + dir * minf(maxf(hit_dist - 0.3, 0.4), (desired - eye).length())
	# Keep the camera out of the floor; clamp height.
	desired.y = maxf(desired.y, 0.6)
	camera.global_position = camera.global_position.lerp(desired, 1.0 - pow(0.0005, delta))
	var look_target: Vector3 = global_position + Vector3(0, 1.4, 0) - back * 9.0
	# Apply head pitch to the look target.
	var pitch := head.rotation.x
	look_target.y += -sin(pitch) * 9.0
	camera.look_at(look_target, Vector3.UP)
	# The hero faces where the body faces; the camera orbits behind it.

func take_damage(amount: float) -> void:
	if not alive:
		return
	if _invuln_timer > 0.0:
		return
	hp = maxf(0.0, hp - amount)
	if sfx != null:
		sfx.play("hurt", -4.0)
	if hud != null:
		hud.set_hp(hp, max_hp)
		hud.set_squad(_squad_status())
		hud.damage_flash()
	if hp <= 0.0:
		hp = 0.0
		_member_down[current_member] = true
		_member_hp[current_member] = 0.0
		if hud != null:
			hud.set_squad(_squad_status())
		# Auto-switch to the next member still standing; lose only when the
		# whole squad is down.
		var idx := squad_available.find(current_member)
		for i in range(1, squad_available.size() + 1):
			var cand: String = squad_available[(idx + i) % squad_available.size()]
			if not bool(_member_down[cand]):
				if hud != null:
					hud.show_message("%s IS DOWN — switching to %s" % [String(MEMBERS[current_member]["name"]), String(MEMBERS[cand]["name"])])
				_switch_to(cand)
				return
		alive = false
		if game != null:
			game.on_player_down()

func _start_reload() -> void:
	if _reload_timer > 0.0 or ammo_in_mag == mag_size:
		return
	_reload_timer = reload_time
	ammo_in_mag = mag_size
	if sfx != null:
		sfx.play("reload")
	if hud != null:
		hud.set_ammo(ammo_in_mag, mag_size, grenades, mines, toxic_traps)

func _shoot() -> void:
	if _fire_timer > 0.0 or _reload_timer > 0.0:
		return
	_fire_timer = fire_interval
	ammo_in_mag -= 1
	if sfx != null:
		# Per-weapon recorded shots (same trigger, same -6.0 balance):
		# veteran shotgun, survivor SMG, everyone else rifle.
		var shot_name := "shot"
		if current_member == "veteran":
			shot_name = "shotgun"
		elif current_member == "survivor":
			shot_name = "smg"
		sfx.play(shot_name, -6.0)
	_muzzle_flash.light_energy = 4.0
	var clear := get_tree().create_timer(0.05)
	clear.timeout.connect(func() -> void: _muzzle_flash.light_energy = 0.0)
	if hud != null:
		hud.set_ammo(ammo_in_mag, mag_size, grenades, mines, toxic_traps)
	# Hitscan ray(s) from the camera through the crosshair. Shotguns fire a
	# spread of pellets; rifles and SMGs fire one.
	var pellets: int = int(MEMBERS[current_member]["pellets"])
	var spread: float = float(MEMBERS[current_member]["spread"])
	for p in pellets:
		var from := camera.global_position
		var dir := -camera.global_transform.basis.z
		if spread > 0.0:
			var right := camera.global_transform.basis.x
			var up := camera.global_transform.basis.y
			dir = (dir + right * randf_range(-spread, spread) + up * randf_range(-spread, spread)).normalized()
		var to := from + dir * 80.0
		var query := PhysicsRayQueryParameters3D.create(from, to, 3, [get_rid()])
		var space := get_world_3d().direct_space_state
		var hit: Dictionary = space.intersect_ray(query)
		var end: Vector3 = to
		if not hit.is_empty():
			end = hit["position"]
			var collider: Object = hit["collider"]
			if collider is Bombie:
				var b := collider as Bombie
				var headshot: bool = (hit["position"] as Vector3).y > b.global_position.y + 1.45
				b.take_damage(weapon_damage * (2.0 if headshot else 1.0), headshot)
				if sfx != null:
					sfx.play("hit", -8.0)
				if hud != null and headshot:
					hud.show_message("HEADSHOT")
		_spawn_tracer(_muzzle.global_position, end)
	if ammo_in_mag <= 0:
		_start_reload()

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 0.5:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, dist)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.01, 0.01, 0.01), 0.07)
	tw.tween_callback(mi.queue_free)

func _throw_grenade() -> void:
	if _grenade_timer > 0.0:
		return
	var kind: String = String(MEMBERS[current_member]["grenade_kind"])
	if kind == "none" or grenades <= 0:
		if hud != null:
			hud.show_message("No grenades")
		return
	_grenade_timer = 1.0
	grenades -= 1
	_member_grenades[current_member] = grenades
	var g := Grenade.new()
	get_parent().add_child(g)
	g.global_position = camera.global_position + -camera.global_transform.basis.z * 0.6 + Vector3(0, -0.1, 0)
	var dir := -camera.global_transform.basis.z
	g.setup(dir * 13.0 + Vector3(0, 4.5, 0), sfx, kind)
	if hud != null:
		hud.set_ammo(ammo_in_mag, mag_size, grenades, mines, toxic_traps)

func _place_trap() -> void:
	if _trap_timer > 0.0:
		return
	if current_member != "hazmat":
		if hud != null:
			hud.show_message("Only the engineer carries traps")
		return
	if trap_selected == "mine" and mines <= 0:
		if hud != null:
			hud.show_message("No mines left")
		return
	if trap_selected == "toxic" and toxic_traps <= 0:
		if hud != null:
			hud.show_message("No acid traps left")
		return
	_trap_timer = 0.6
	var dir := -transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var pos: Vector3 = global_position + dir * 2.0
	pos.y = 0.15
	var trap := Trap.new()
	get_parent().add_child(trap)
	trap.global_position = pos
	trap.setup(trap_selected, sfx)
	if trap_selected == "mine":
		mines -= 1
		_member_mines[current_member] = mines
	else:
		toxic_traps -= 1
		_member_traps[current_member] = toxic_traps
	if sfx != null:
		sfx.play("beep", -6.0)
	if hud != null:
		hud.set_ammo(ammo_in_mag, mag_size, grenades, mines, toxic_traps)
		hud.show_message("Mine placed" if trap_selected == "mine" else "Acid trap placed")
