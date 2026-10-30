class_name Bombie
extends CharacterBody3D

# A mutating Bombie: shambler, runner, tank or exploder. Chases the player,
# swipes in range, mutates mid-round (faster, tougher, redder). Built as a
# realistic-proportioned humanoid (Humanoid) with glowing eyes.

signal died(b: Bombie)

const GRAVITY := 20.0

var btype: String = "shambler"
var max_hp: float = 60.0
var hp: float = 60.0
var speed: float = 1.6
var attack_damage: float = 8.0
var attack_range: float = 1.9
var attack_cooldown: float = 1.5
var mutated: bool = false
var slow_timer: float = 0.0

var _attack_timer: float = 0.0
var _walk_phase: float = 0.0
var _dead: bool = false
var _sink_timer: float = -1.0
var _pos_last: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
var _sidestep_timer: float = 0.0
var _sidestep_sign: float = 1.0
var _player: Node3D = null
var _skin_mat: StandardMaterial3D
# Skin texture carries the base color; albedo_color is only a tint (white =
# untinted, redder after mutation, bright on a hit flash).
var _skin_base: Color = Color.WHITE
var _body: Node3D = null
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _eye_mat: StandardMaterial3D
# Exploder state: charges the player, primes a fuse in range, then detonates.
var _primed: bool = false
var _fuse_timer: float = 0.0
var _pulse_t: float = 0.0

func setup(p_type: String, round_num: int, player: Node3D) -> void:
	btype = p_type
	_player = player
	var hp_scale := 1.0 + 0.15 * float(round_num - 1)
	var speed_scale := 1.0 + 0.08 * float(round_num - 1)
	match p_type:
		"runner":
			max_hp = 40.0 * hp_scale
			speed = 3.9 * speed_scale
			attack_damage = 6.0
			scale = Vector3(0.92, 0.95, 0.92)
		"tank":
			max_hp = 260.0 * hp_scale
			speed = 1.15 * speed_scale
			attack_damage = 16.0
			attack_range = 2.2
			scale = Vector3(1.35, 1.3, 1.35)
		"exploder":
			# Bloated, fast, glowing. No melee swipe: it primes a fuse in
			# range and detonates. Shot dead before the fuse ends, it just dies.
			max_hp = 90.0 * hp_scale
			speed = 2.6 * speed_scale
			attack_damage = 0.0
			attack_range = 2.4
			scale = Vector3(1.15, 1.1, 1.15)
		_:
			max_hp = 60.0 * hp_scale
			speed = 1.6 * speed_scale
			attack_damage = 8.0
	hp = max_hp

func _ready() -> void:
	add_to_group("bombie")
	collision_layer = 2
	collision_mask = 1
	_build_body()
	# Collision capsule.
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.9
	col.shape = shape
	col.position = Vector3(0, 0.95, 0)
	add_child(col)

func _bombie_spec() -> Dictionary:
	# Torn clothing, skin showing, per-type palette — from the concept board.
	match btype:
		"runner":
			return {"height": 1.75, "skin": Color(0.60, 0.61, 0.54),
				"freckles": 0.1, "skin_seed": "runner", "acne": 0.15,
				"shirt": Color(0.45, 0.25, 0.20), "pants": Color(0.20, 0.20, 0.22),
				"zombie": true, "hair": true, "patchy_hair": true, "hair_color": Color(0.25, 0.18, 0.10),
				"face": "zombie", "face_tint": Color(0.92, 1.0, 0.92)}
		"tank":
			return {"height": 1.8, "bulk": 1.25, "skin": Color(0.52, 0.54, 0.48),
				"skin_seed": "tank", "acne": 0.15,
				"shirt": Color(0.25, 0.25, 0.24), "pants": Color(0.20, 0.20, 0.19),
				"zombie": true, "face": "zombie", "face_tint": Color(0.82, 0.86, 0.82)}
		"exploder":
			return {"height": 1.85, "skin": Color(0.85, 0.45, 0.12),
				"skin_seed": "exploder", "acne": 0.1,
				"shirt": Color(0.30, 0.25, 0.20), "pants": Color(0.22, 0.20, 0.18),
				"zombie": true, "bloated": true,
				"skin_emission": Color(1.0, 0.45, 0.08), "skin_emission_energy": 1.0,
				"face": "zombie", "face_tint": Color(1.0, 0.72, 0.50)}
		_:
			return {"height": 1.8, "skin": Color(0.58, 0.60, 0.52),
				"freckles": 0.1, "skin_seed": "shambler", "acne": 0.15,
				"shirt": Color(0.35, 0.32, 0.28), "pants": Color(0.22, 0.22, 0.20),
				"zombie": true, "hair": true, "patchy_hair": true, "hair_color": Color(0.15, 0.12, 0.08),
				"face": "zombie", "face_tint": Color(1.0, 1.0, 1.0)}

func _build_body() -> void:
	# Realistic-proportioned infected (Humanoid): jointed cylinder limbs,
	# sphere head with glowing eyes, torn textured clothing, skin showing.
	# setup() must run before add_child so btype is set when _ready builds.
	if _body != null:
		_body.free()
	var built: Dictionary = Humanoid.build(_bombie_spec())
	_body = built["root"]
	add_child(_body)
	_leg_l = built["leg_l"]
	_leg_r = built["leg_r"]
	_arm_l = built["arm_l"]
	_arm_r = built["arm_r"]
	_skin_mat = built["skin_mat"]
	_eye_mat = built["eye_mat"]

func take_damage(amount: float, headshot: bool = false) -> void:
	if _dead:
		return
	hp -= amount
	# Hit flash: brief skin brighten (texture x bright tint).
	_skin_mat.albedo_color = Color(1.5, 1.5, 1.5)
	var t := get_tree().create_timer(0.08)
	t.timeout.connect(func() -> void:
		if not _dead:
			_skin_mat.albedo_color = _skin_base
	)
	if hp <= 0.0:
		die()

func mutate() -> void:
	if _dead or mutated:
		return
	mutated = true
	speed *= 1.25
	max_hp += 30.0
	hp += 30.0
	scale *= 1.12
	_skin_base = Color(0.6, 0.3, 0.25)
	_skin_mat.albedo_color = _skin_base
	_eye_mat.emission_energy_multiplier = 7.0

func _detonate() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	# Explosion thump (same "boom" stream and -4.0 balance as grenades).
	# The Sfx node is a sibling under the scene root; guarded so a
	# missing node never breaks the detonation.
	var sfx_node := get_parent().get_node_or_null("Sfx")
	if sfx_node != null and sfx_node.has_method("play"):
		sfx_node.play("boom", -4.0)
	# AoE damage to the player only: no friendly fire between squad members,
	# and Bombies do not hurt each other.
	if _player != null and is_instance_valid(_player):
		var d := _player.global_position.distance_to(global_position)
		if d <= 3.5 and _player.has_method("take_damage"):
			_player.take_damage(35.0 * (1.0 - d / 5.0))
	_spawn_explosion_visual()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	queue_free()

func _spawn_explosion_visual() -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.55, 0.15)
	flash.light_energy = 8.0
	flash.omni_range = 12.0
	flash.position = global_position + Vector3(0, 1.0, 0)
	get_parent().add_child(flash)
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sphere.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.15, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 5.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material_override = mat
	sphere.position = global_position + Vector3(0, 1.0, 0)
	get_parent().add_child(sphere)
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.45)
	tw.parallel().tween_property(sphere, "scale", Vector3(3.5, 3.5, 3.5), 0.45)
	tw.tween_callback(flash.queue_free)
	tw.tween_callback(sphere.queue_free)

func die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	# Fall flat and sink after a moment.
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -PI / 2.0, 0.35)
	tw.tween_property(self, "position:y", -0.4, 2.5).set_delay(1.2)
	tw.tween_callback(queue_free).set_delay(0.5)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	if _player == null or not is_instance_valid(_player):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.01 else Vector3.ZERO
	# Face the player.
	if dist > 0.05:
		rotation.y = atan2(dir.x, dir.z)
	# Separation from other bombies.
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("bombie"):
		if other == self or not (other is Bombie) or other._dead:
			continue
		var d: Vector3 = global_position - other.global_position
		d.y = 0.0
		var l := d.length()
		if l > 0.01 and l < 1.3:
			push += d.normalized() * (1.3 - l)
	var eff_speed := speed
	if slow_timer > 0.0:
		eff_speed *= 0.55
		slow_timer -= delta
	# Water: runners keep full speed, everyone else is slightly slowed.
	if btype != "runner":
		eff_speed *= 0.95
	# Exploder: no melee swipe — prime a fuse in range, then detonate.
	if btype == "exploder":
		_pulse_t += delta
		if _primed:
			_fuse_timer -= delta
			_skin_mat.emission_energy_multiplier = 5.0 + sin(_pulse_t * 30.0) * 3.0
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			_pos_last = global_position
			if _fuse_timer <= 0.0:
				_detonate()
			return
		_skin_mat.emission_energy_multiplier = 1.6 + sin(_pulse_t * 6.0) * 1.0
		if dist <= attack_range:
			_primed = true
			_fuse_timer = 0.9
	_attack_timer -= delta
	if btype != "exploder" and dist <= attack_range and _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		if _player.has_method("take_damage"):
			_player.take_damage(attack_damage)
		_arm_l.rotation.x = -2.0
		_arm_r.rotation.x = -2.0
	# Unstick: if we are barely moving while trying to reach the player
	# (wedged on a car or pillar), sidestep around the obstacle.
	var moved := global_position.distance_to(_pos_last)
	var expected := eff_speed * delta
	if dist > attack_range and expected > 0.001 and moved < expected * 0.4:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	if _stuck_timer > 1.5:
		_stuck_timer = 0.0
		_sidestep_timer = 1.2
		_sidestep_sign = -_sidestep_sign
	velocity.x = (dir.x * eff_speed) + push.x * 2.0
	velocity.z = (dir.z * eff_speed) + push.z * 2.0
	if _sidestep_timer > 0.0:
		_sidestep_timer -= delta
		var perp := Vector3(-dir.z, 0.0, dir.x) * _sidestep_sign
		velocity.x += perp.x * eff_speed * 0.9
		velocity.z += perp.z * eff_speed * 0.9
	move_and_slide()
	_pos_last = global_position
	# Walk cycle.
	var planar := Vector2(velocity.x, velocity.z).length()
	_walk_phase += planar * delta * 2.4
	var swing := sin(_walk_phase) * clampf(planar / 2.0, 0.0, 1.0) * 0.5
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	if _attack_timer < attack_cooldown - 0.25:
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -1.2 + swing * 0.4, delta * 8.0)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.2 - swing * 0.4, delta * 8.0)
