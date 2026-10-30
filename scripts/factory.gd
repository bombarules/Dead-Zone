class_name Factory
extends LevelBase

# Collapsed factory, built at runtime: three forward-only rooms along -Z.
# Doors seal behind the squad; a room must be cleared before the next door
# opens. Rusted machines, conveyor belts, collapsed beams, toxic puddles,
# amber tube lights, a red emergency light and a green exit sign at the far
# end. Flat floor throughout (no mezzanine): nothing can wedge a Bombie up
# high, and every spawn point is on open floor.
# Palette: rust brown / olive-grey concrete, amber + red light, toxic green.

const WALL_H := 5.0
const ROOM_W := 20.0 # x -10..10
const ROOM_DEPTH := 14.0

# Room z-ranges: room 1: +8..-6, room 2: -6..-20, room 3: -20..-34.
const DOOR_Z := [-6.0, -20.0]
const TRIGGER_Z := [-7.5, -21.5] # z the player must cross to enter room 2 / 3

var room_spawn_points: Array = [[], [], []]

var _doors: Array[StaticBody3D] = []
var _door_shapes: Array[CollisionShape3D] = []
var _flicker_light: OmniLight3D
var _flicker_base: float = 2.0
var _flicker_t: float = 0.0
var _exit_light: OmniLight3D
var _exit_sign_mat: StandardMaterial3D

func _ready() -> void:
	# Photographic surfaces, same as the garage: concrete-wall photo on
	# floors/walls, rusted-car photo on machines and debris (triplanar,
	# no stretching). Falls back to procedural if a photo fails.
	var concrete := _make_material(photo_or(TEX_CONCRETE, _concrete_texture()), 0.18, 0.55, 0.05)
	var dark_concrete := _make_material(photo_or(TEX_CONCRETE, _concrete_texture(true)), 0.18, 0.7, 0.0, Color(0.55, 0.55, 0.55))
	# Same floor fix as the garage: the light wall photo blows out to
	# near-white under the lights, so the floor gets it dimmed. Wet
	# sheen here too (damp factory floor + puddles): low roughness so
	# the reflection probe and lights read on it.
	var floor_concrete := _make_material(photo_or(TEX_CONCRETE, _concrete_texture()), 0.18, 0.50, 0.08, Color(0.45, 0.45, 0.45))
	var rust := _make_material(photo_or(TEX_RUST, _rust_texture()), 0.25, 0.8, 0.15)
	var parts := _make_material(photo_or(TEX_RUST_PARTS, _rust_texture()), 0.25, 0.8, 0.15)
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.06, 0.06, 0.06)
	dark_mat.roughness = 0.9
	_build_shell(concrete, dark_concrete, floor_concrete)
	_build_machines(rust, dark_concrete)
	_build_beams(rust)
	_build_debris(rust, parts, dark_mat)
	_build_cables(dark_concrete)
	_build_puddles()
	_build_reflection_probe()
	_build_lights()
	_build_exit()
	room_spawn_points = [
		[Vector3(-7, 0, -4), Vector3(7, 0, -4), Vector3(-4, 0, 1), Vector3(6, 0, -1)],
		[Vector3(-7, 0, -18), Vector3(7, 0, -18), Vector3(-4, 0, -10), Vector3(6, 0, -16)],
		[Vector3(-7, 0, -31), Vector3(7, 0, -31), Vector3(-4, 0, -24), Vector3(6, 0, -30)],
	]

func get_player_spawn() -> Vector3:
	return Vector3(0, 0.1, 5)

func get_room_trigger_z(room: int) -> float:
	if room == 2:
		return TRIGGER_Z[0]
	if room == 3:
		return TRIGGER_Z[1]
	return 999.0

func random_spawn_point(min_dist_to: Vector3, min_dist: float) -> Vector3:
	var pts: Array = room_spawn_points[clampi(current_room - 1, 0, 2)]
	var candidates: Array[Vector3] = []
	for p in pts:
		if p.distance_to(min_dist_to) >= min_dist:
			candidates.append(p)
	if candidates.is_empty():
		return pts[randi() % pts.size()]
	return candidates[randi() % candidates.size()]

func set_exit_open(open: bool) -> void:
	if open:
		_exit_light.light_color = Color(0.2, 1.0, 0.35)
		_exit_light.light_energy = 4.0
		_exit_sign_mat.emission = Color(0.1, 1.0, 0.3)
		_exit_sign_mat.emission_enabled = true

func open_door(idx: int) -> void:
	if idx < 0 or idx >= _doors.size():
		return
	var door := _doors[idx]
	var tw := door.create_tween()
	tw.tween_property(door, "position:y", -1.7, 0.9)
	tw.tween_callback(_door_shapes[idx].set_deferred.bind("disabled", true))

func seal_door(idx: int) -> void:
	if idx < 0 or idx >= _doors.size():
		return
	_door_shapes[idx].set_deferred("disabled", false)
	var door := _doors[idx]
	var tw := door.create_tween()
	tw.tween_property(door, "position:y", 1.7, 0.7)

func _process(delta: float) -> void:
	# Red emergency light flicker: mostly on, with irregular dropouts.
	_flicker_t += delta
	var f := 1.0
	var n := sin(_flicker_t * 11.0) * sin(_flicker_t * 6.1 + 1.3)
	if n > 0.86:
		f = 0.15
	elif n > 0.6:
		f = 0.55
	_flicker_light.light_energy = _flicker_base * f

# --- materials / textures -----------------------------------------------------

func _make_material(tex: Texture2D, world_scale: float, roughness: float, metallic: float, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(world_scale, world_scale, world_scale)
	return m

func _concrete_texture(dark: bool = false) -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var base := Color(0.16, 0.17, 0.15) if dark else Color(0.32, 0.33, 0.30)
	for y in range(s):
		for x in range(s):
			var n := randf()
			var stain := 0.0
			var dx := float(x - 64) / 64.0
			var dy := float(y - 64) / 64.0
			if dx * dx + dy * dy < 0.5:
				stain = 0.25 * randf()
			var v := clampf(0.75 + n * 0.5 - stain, 0.0, 1.2)
			img.set_pixel(x, y, base * v)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _rust_texture() -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in range(s):
		for x in range(s):
			var n := randf()
			var c: Color
			if n < 0.45:
				c = Color(0.32, 0.18, 0.10) # rust brown
			elif n < 0.75:
				c = Color(0.25, 0.24, 0.20) # grimy olive-grey
			else:
				c = Color(0.45, 0.30, 0.16) # flaked orange rust
			img.set_pixel(x, y, c * (0.7 + randf() * 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# --- geometry helpers ---------------------------------------------------------

func _add_box(box_size: Vector3, pos: Vector3, mat: Material, collide: bool = true, rot_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mi.mesh = box
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	body.add_child(mi)
	if collide:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box_size
		col.shape = shape
		body.add_child(col)
	add_child(body)
	return body

func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	return mi

# --- level --------------------------------------------------------------------

func _build_shell(concrete: Material, dark: Material, floor_mat: Material) -> void:
	# One big floor + ceiling, perimeter walls, two divider walls with a 4 m
	# doorway each at x = 0. The south wall is solid: no going back.
	_add_box(Vector3(ROOM_W, 1.0, 42.0), Vector3(0, -0.5, -13), floor_mat)
	_add_box(Vector3(ROOM_W, 0.6, 42.0), Vector3(0, WALL_H + 0.3, -13), dark, false)
	_add_box(Vector3(ROOM_W + 1.0, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, 8), dark)
	_add_box(Vector3(ROOM_W + 1.0, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, -34), dark)
	_add_box(Vector3(1.0, WALL_H, 43.0), Vector3(-10, WALL_H / 2.0, -13), dark)
	_add_box(Vector3(1.0, WALL_H, 43.0), Vector3(10, WALL_H / 2.0, -13), dark)
	for dz in DOOR_Z:
		_add_box(Vector3(8.0, WALL_H, 1.0), Vector3(-6, WALL_H / 2.0, dz), dark)
		_add_box(Vector3(8.0, WALL_H, 1.0), Vector3(6, WALL_H / 2.0, dz), dark)
		_build_door(dz, dark)

func _build_door(door_z: float, mat: Material) -> void:
	# Sliding slab: starts sealed (closed), slides down into the floor to open.
	var door := StaticBody3D.new()
	door.position = Vector3(0, 1.7, door_z)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.2, 3.4, 0.4)
	mi.mesh = box
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	door.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.2, 3.4, 0.4)
	col.shape = shape
	door.add_child(col)
	add_child(door)
	_doors.append(door)
	_door_shapes.append(col)
	# Hazard stripes on the door face.
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.85, 0.65, 0.1)
	stripe_mat.emission_enabled = true
	stripe_mat.emission = Color(0.6, 0.45, 0.05)
	stripe_mat.emission_energy_multiplier = 0.8
	var stripe := BoxMesh.new()
	stripe.size = Vector3(4.2, 0.25, 0.06)
	var smi := MeshInstance3D.new()
	smi.mesh = stripe
	smi.material_override = stripe_mat
	smi.position = Vector3(0, 0, 0.23)
	door.add_child(smi)

func _build_machines(rust: Material, dark: Material) -> void:
	# Rusted machines and conveyor belts hug the walls; the central corridor
	# (x -4..4) stays open so the squad can always kite and retreat.
	var machines: Array = [
		[Vector3(-8.5, 0.9, -2), Vector3(2.0, 1.8, 3.0)],
		[Vector3(8.5, 0.75, 3), Vector3(2.0, 1.5, 2.5)],
		[Vector3(-8.5, 1.0, -16), Vector3(2.0, 2.0, 3.0)],
		[Vector3(8.5, 0.9, -10), Vector3(2.0, 1.8, 3.0)],
		[Vector3(-8.5, 1.0, -30), Vector3(2.0, 2.0, 3.0)],
		[Vector3(8.5, 1.0, -25), Vector3(2.0, 2.0, 2.5)],
		[Vector3(7.0, 1.25, -31), Vector3(3.0, 2.5, 3.0)],
	]
	for m in machines:
		_add_box(m[1], m[0], rust)
	# Conveyor belts: long low boxes along the side walls.
	for pos in [Vector3(7.5, 0.45, -4), Vector3(-7.5, 0.45, 2), Vector3(7.5, 0.45, -16), Vector3(-7.5, 0.45, -26)]:
		_add_box(Vector3(3.0, 0.9, 6.0), pos, dark)
	# Pipes running high along the side walls (visual only, out of the way).
	for x in [-9.6, 9.6]:
		_add_box(Vector3(0.3, 0.3, 40.0), Vector3(x, 3.8, -13), rust, false)

func _build_beams(rust: Material) -> void:
	# Collapsed structural beams, leaning from the walls. Kept at the edges
	# so they read as wreckage without blocking the central lane.
	var beams: Array = [
		[Vector3(-8.6, 2.2, -3), Vector3(0.55, 0, 0.5)],
		[Vector3(8.6, 2.2, -12), Vector3(-0.5, 0, -0.4)],
		[Vector3(-8.6, 2.2, -24), Vector3(0.5, 0, 0.6)],
		[Vector3(8.6, 2.2, -30), Vector3(-0.55, 0, -0.5)],
	]
	for b in beams:
		var body := StaticBody3D.new()
		body.position = b[0]
		body.rotation = b[1]
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.5, 8.0)
		mi.mesh = box
		mi.material_override = rust
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		body.add_child(mi)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.5, 0.5, 8.0)
		col.shape = shape
		body.add_child(col)
		add_child(body)
	# Fallen beams lying flat on the floor (visual only, low enough to step over).
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 8:
		var pos := Vector3(rng.randf_range(-9, 9), 0.2, rng.randf_range(6, -32))
		_add_box(Vector3(0.4, 0.4, rng.randf_range(2.5, 4.5)), pos, rust, false, rng.randf_range(0, TAU))

func _build_debris(rust: Material, parts_mat: Material, dark_mat: Material) -> void:
	# Scrap-pile standard (Danny's two scrap photos): dense tangled
	# wreckage — crushed bodies, twisted panels, cables, rusted motors,
	# gears and rotors — instead of the old clean rubble chunks.
	# Visual only, like the old chunks, so nothing becomes a wedge spot
	# and the corridor stays open.
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in 10:
		var px := rng.randf_range(-8, 8)
		var pz := rng.randf_range(6, -32)
		if absf(px) < 2.5:
			continue # keep the central corridor open
		var pile := Node3D.new()
		pile.position = Vector3(px, 0, pz)
		pile.rotation.y = rng.randf_range(0, TAU)
		add_child(pile)
		build_wreckage_pile(pile, rust, parts_mat, dark_mat, rng)
	# A few big crates with real collision, tucked against the walls.
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(-9, 0.6, 6), rust)
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(9, 0.6, -8), rust)
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(-9, 0.6, -22), rust)
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(9, 1.8, -22), rust)
	# Rusted barrels with real collision, hugging the walls (corridor stays open).
	for pos in [Vector3(-9.2, 0.45, -2), Vector3(-9.2, 0.45, -10), Vector3(9.2, 0.45, -16), Vector3(9.2, 0.45, -28), Vector3(-9.2, 0.45, -30)]:
		_add_barrel(pos, rust)

func _build_reflection_probe() -> void:
	# Static probe over the factory floor: damp concrete and machine
	# metal pick up the lights and structure (UPDATE_ONCE, static scene).
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0, 2.5, -13)
	probe.extents = Vector3(10, 4, 20)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

func _add_barrel(pos: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 0.9
	col.shape = shape
	body.add_child(col)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.35
	mesh.height = 0.9
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mi)
	add_child(body)

func _build_cables(dark: Material) -> void:
	# Hanging cables from the ceiling, visual only, slight sag.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 8:
		var h := rng.randf_range(1.5, 3.0)
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.03
		cyl.height = h
		mi.mesh = cyl
		mi.material_override = dark
		mi.position = Vector3(rng.randf_range(-8, 8), 5.4 - h / 2.0, rng.randf_range(6, -32))
		mi.rotation.z = rng.randf_range(-0.12, 0.12)
		add_child(mi)

func _build_puddles() -> void:
	# Toxic green puddles on the floor (visual only).
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.5, 0.1, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.55, 0.08)
	mat.emission_energy_multiplier = 0.7
	mat.roughness = 0.1
	for pos in [Vector3(-5, 0.02, -1), Vector3(5, 0.02, 4), Vector3(-6, 0.02, -14), Vector3(4, 0.02, -18), Vector3(-5, 0.02, -28), Vector3(6, 0.02, -24)]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.4
		cyl.bottom_radius = 1.4
		cyl.height = 0.04
		_add_mesh(cyl, pos, mat)

func _tube_light(pos: Vector3, color: Color, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 16.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	add_child(light)
	var tube_mat := StandardMaterial3D.new()
	tube_mat.albedo_color = color
	tube_mat.emission_enabled = true
	tube_mat.emission = color
	tube_mat.emission_energy_multiplier = 3.0
	var tube := BoxMesh.new()
	tube.size = Vector3(3.0, 0.08, 0.18)
	var mi := MeshInstance3D.new()
	mi.mesh = tube
	mi.material_override = tube_mat
	mi.position = pos + Vector3(0, 0.25, 0)
	add_child(mi)
	return light

func _build_lights() -> void:
	_tube_light(Vector3(0, 4.4, 1), Color(1.0, 0.62, 0.25), 2.4)
	_tube_light(Vector3(0, 4.4, -13), Color(1.0, 0.62, 0.25), 2.2)
	_tube_light(Vector3(0, 4.4, -27), Color(1.0, 0.55, 0.2), 2.0)
	_flicker_light = _tube_light(Vector3(-8, 4.4, -16), Color(1.0, 0.12, 0.08), _flicker_base)
	# Cold work light over the far room.
	var spill := OmniLight3D.new()
	spill.position = Vector3(6, 3.5, -29)
	spill.light_color = Color(0.55, 0.7, 0.9)
	spill.light_energy = 1.2
	spill.omni_range = 12.0
	add_child(spill)
	# Sickly green glow over the big toxic puddle in room 2.
	var toxic_glow := OmniLight3D.new()
	toxic_glow.position = Vector3(-6, 1.2, -14)
	toxic_glow.light_color = Color(0.2, 0.9, 0.15)
	toxic_glow.light_energy = 1.0
	toxic_glow.omni_range = 7.0
	add_child(toxic_glow)

func _build_exit() -> void:
	# Exit door + EXIT sign on the far (north) wall of room 3.
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.12, 0.14, 0.12)
	door_mat.roughness = 0.6
	door_mat.metallic = 0.4
	_add_box(Vector3(2.4, 3.4, 0.4), Vector3(0, 1.7, -33.6), door_mat)
	_exit_sign_mat = StandardMaterial3D.new()
	_exit_sign_mat.albedo_color = Color(0.05, 0.2, 0.08)
	_exit_sign_mat.emission_enabled = true
	_exit_sign_mat.emission = Color(0.1, 0.6, 0.2)
	_exit_sign_mat.emission_energy_multiplier = 1.5
	var sign := BoxMesh.new()
	sign.size = Vector3(1.6, 0.5, 0.1)
	var mi := MeshInstance3D.new()
	mi.mesh = sign
	mi.material_override = _exit_sign_mat
	mi.position = Vector3(0, 3.9, -33.4)
	add_child(mi)
	_exit_light = OmniLight3D.new()
	_exit_light.position = Vector3(0, 3.6, -32.0)
	_exit_light.light_color = Color(0.2, 1.0, 0.35)
	_exit_light.light_energy = 0.8
	_exit_light.omni_range = 8.0
	add_child(_exit_light)
