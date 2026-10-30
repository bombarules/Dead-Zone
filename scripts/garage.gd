class_name Garage
extends LevelBase

# Flooded underground parking garage, built at runtime from boxes + procedural
# textures: concrete floor under murky standing water, pillar grid, rusted parked
# cars, a ramp to a mezzanine, debris, amber tube lights and a red emergency light.
# Palette: charcoal / olive concrete, acid yellow hero accents, amber + red light.

const SIZE_X := 44.0
const SIZE_Z := 36.0
const WALL_H := 5.0
const WATER_Y := 0.14

var _flicker_light: OmniLight3D
var _flicker_base: float = 2.2
var _flicker_t: float = 0.0
var _exit_light: OmniLight3D
var _exit_sign_mat: StandardMaterial3D
# Planar water reflection (RTX-on look, see _build_water): a small
# SubViewport rendering the scene from a camera mirrored across the
# water plane, refreshed every 3rd frame so it costs a fraction of a
# full second render. Wading splash droplets + ripple rings.
var _refl_viewport: SubViewport
var _refl_cam: Camera3D
var _water_mat: ShaderMaterial
var _splashes: Array = []
var _rings: Array = []
var _frame: int = 0
var _wade_t: float = 0.0

const TEX_WATER := "res://assets/textures/danny-crops/water-kingfisher-crop.webp"
const TEX_FRAMED := "res://assets/textures/danny-crops/lake-framed.webp"

var spawn_points: Array[Vector3] = []

func _ready() -> void:
	# Photographic surfaces: the concrete-wall photo on floors, walls and
	# pillars, the rusted-car photo on cars and debris — triplanar so
	# nothing stretches. Dark walls use the same photo dimmed, so the
	# stains still read. Falls back to procedural if a photo fails.
	var concrete := _make_material(photo_or(TEX_CONCRETE, _concrete_texture()), 0.18, 0.55, 0.05)
	var dark_concrete := _make_material(photo_or(TEX_CONCRETE, _concrete_texture(true)), 0.18, 0.7, 0.0, Color(0.55, 0.55, 0.55))
	# The wall photo is light grey; untinted it blows the floor out to
	# near-white under the garage lights, killing the dark mood. The floor
	# gets the same photo dimmed, pillars keep the full photo. The floor
	# is WET (flooded garage): low roughness + a little metalness so it
	# picks up the reflection probe and the amber/red lights like a wet
	# street — the RTX-on look for floors.
	var floor_concrete := _make_material(photo_or(TEX_CONCRETE, _concrete_texture()), 0.18, 0.50, 0.08, Color(0.45, 0.45, 0.45))
	var rust := _make_material(photo_or(TEX_RUST, _rust_texture()), 0.25, 0.8, 0.15)
	var parts := _make_material(photo_or(TEX_RUST_PARTS, _rust_texture()), 0.25, 0.8, 0.15)
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.06, 0.06, 0.06)
	dark_mat.roughness = 0.9
	_build_shell(concrete, dark_concrete, floor_concrete)
	_build_pillars(concrete)
	_build_cars()
	_build_ramp(dark_concrete)
	_build_slope_wedges()
	_build_fence()
	_build_stairs(dark_concrete)
	_build_debris(rust, parts, dark_mat)
	_build_water()
	_build_reflection_probe()
	_build_framed_photo()
	_build_lights()
	_build_exit()
	spawn_points = [
		Vector3(-19, 0, -15), Vector3(19, 0, -15), Vector3(-19, 0, 15),
		Vector3(19, 0, 15), Vector3(0, 0, -16), Vector3(-14, 0, 0),
		Vector3(14, 0, 0), Vector3(-7, 3.65, -14.5),
	]

func get_player_spawn() -> Vector3:
	return Vector3(0, 0.1, 14)

func random_spawn_point(min_dist_to: Vector3, min_dist: float) -> Vector3:
	var candidates: Array[Vector3] = []
	for p in spawn_points:
		if p.distance_to(min_dist_to) >= min_dist:
			candidates.append(p)
	if candidates.is_empty():
		return spawn_points[randi() % spawn_points.size()]
	return candidates[randi() % candidates.size()]

func set_exit_open(open: bool) -> void:
	if open:
		_exit_light.light_color = Color(0.2, 1.0, 0.35)
		_exit_light.light_energy = 4.0
		_exit_sign_mat.emission = Color(0.1, 1.0, 0.3)
		_exit_sign_mat.emission_enabled = true

func _process(delta: float) -> void:
	# Red emergency light flicker: mostly on, with irregular dropouts.
	_flicker_t += delta
	var f := 1.0
	var n := sin(_flicker_t * 13.0) * sin(_flicker_t * 7.3 + 1.7)
	if n > 0.86:
		f = 0.15
	elif n > 0.6:
		f = 0.55
	_flicker_light.light_energy = _flicker_base * f
	# Planar water reflection: refresh every 3rd frame from a camera
	# mirrored across the water plane (see _build_water).
	_frame += 1
	if _refl_viewport != null and _refl_cam != null and _frame % 3 == 0:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var refl := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)), Vector3(0, 2.0 * WATER_Y, 0))
			_refl_cam.global_transform = refl * cam.global_transform
			_refl_cam.fov = cam.fov
			_refl_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Wade splashes: droplets arc and fall, rings expand and fade.
	for s in _splashes.duplicate():
		s["life"] -= delta
		s["vel"].y -= 6.0 * delta
		s["mi"].position += s["vel"] * delta
		if s["life"] <= 0.0 or s["mi"].position.y < WATER_Y:
			s["mi"].queue_free()
			_splashes.erase(s)
	for r in _rings.duplicate():
		r["life"] -= delta
		var t := 1.0 - maxf(r["life"], 0.0) / 1.0
		# Expand, then collapse in the last third (the ripple
		# dissipating) — an opaque ring cannot fade by alpha.
		var sc := 0.3 + t * 0.9
		if t >= 0.7:
			sc = 1.2 * (1.0 - (t - 0.7) / 0.3)
		r["mi"].scale = Vector3(sc, 1.0, sc)
		if r["life"] <= 0.0:
			r["mi"].queue_free()
			_rings.erase(r)

# Wading splash (kingfisher water): droplets frozen mid-air + an
# expanding ripple ring. Called by the player while wading, and by the
# staged water shot so droplets read frozen in the screenshot.
func spawn_wade(pos: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var drop_mat := StandardMaterial3D.new()
	# OPAQUE, not transparent: transparent droplets/ring sorted behind
	# the huge transparent water plane (whose centre is nearer the
	# camera) and the water blended over them until they vanished.
	# Opaque drops write depth, so the water behind them fails the
	# depth test and the drops read. Pale + slightly emissive so they
	# sparkle against murky water like kingfisher droplets in light.
	drop_mat.albedo_color = Color(0.75, 0.85, 0.80, 1.0)
	drop_mat.roughness = 0.15
	drop_mat.metallic = 0.3
	drop_mat.emission_enabled = true
	drop_mat.emission = Color(0.5, 0.6, 0.55)
	drop_mat.emission_energy_multiplier = 0.35
	for i in 8:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.035, 0.055)
		sm.height = sm.radius * 2.0
		mi.mesh = sm
		mi.material_override = drop_mat
		mi.position = pos + Vector3(rng.randf_range(-0.2, 0.2), 0.02, rng.randf_range(-0.2, 0.2))
		add_child(mi)
		_splashes.append({"mi": mi, "vel": Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(1.2, 2.2), rng.randf_range(-0.6, 0.6)), "life": 0.9})
	var ring_mat := StandardMaterial3D.new()
	# Opaque for the same depth reason as the droplets (see above).
	ring_mat.albedo_color = Color(0.6, 0.7, 0.65, 1.0)
	ring_mat.roughness = 0.2
	ring_mat.metallic = 0.3
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.38
	ring.mesh = tm
	ring.material_override = ring_mat
	ring.position = Vector3(pos.x, WATER_Y + 0.02, pos.z)
	ring.rotation.x = PI / 2.0
	add_child(ring)
	_rings.append({"mi": ring, "mat": ring_mat, "life": 1.0})

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
			if dark:
				# Vertical damp streaks running down the wall, like the
				# picture's stained concrete: a few dark columns + a faint
				# horizontal tide line near the bottom.
				var band := int(x / 11) % 7
				if band == 0:
					stain += 0.35
				elif band == 3:
					stain += 0.15
				if y > s - 14:
					stain += 0.2
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

func _chainlink_texture() -> ImageTexture:
	# Diamond mesh: diagonal wires on a transparent background, for the
	# mezzanine fence in the concept picture.
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var wire := Color(0.32, 0.32, 0.30, 1.0)
	var clear := Color(0, 0, 0, 0)
	for y in range(s):
		for x in range(s):
			var d1 := posmod(x + y, 16)
			var d2 := posmod(x - y, 16)
			img.set_pixel(x, y, wire if (d1 < 2 or d2 < 2) else clear)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _radial_texture() -> ImageTexture:
	# Soft round glow falloff for the haze sprites around the lights.
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in range(s):
		for x in range(s):
			var dx := float(x - 64) / 64.0
			var dy := float(y - 64) / 64.0
			var d := clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, d * d))
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

func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material, collide: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	return mi

# --- level --------------------------------------------------------------------

func _build_shell(concrete: Material, dark: Material, floor_mat: Material) -> void:
	# Floor, ceiling and perimeter walls. The floor mesh sits on visual
	# layer 4 ONLY: the main camera (all layers) still sees it, but the
	# planar-reflection camera (all layers except water + floor) does
	# not — otherwise the mirrored camera, sitting below the floor slab,
	# would see the floor's underside instead of the scene above it.
	var floor_body := _add_box(Vector3(SIZE_X, 1.0, SIZE_Z), Vector3(0, -0.5, 0), floor_mat)
	(floor_body.get_child(0) as MeshInstance3D).layers = 8
	_add_box(Vector3(SIZE_X, 0.6, SIZE_Z), Vector3(0, WALL_H + 0.3, 0), dark, false)
	var half_x := SIZE_X / 2.0
	var half_z := SIZE_Z / 2.0
	_add_box(Vector3(SIZE_X + 1.0, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, -half_z), dark)
	_add_box(Vector3(SIZE_X + 1.0, WALL_H, 1.0), Vector3(0, WALL_H / 2.0, half_z), dark)
	_add_box(Vector3(1.0, WALL_H, SIZE_Z + 1.0), Vector3(-half_x, WALL_H / 2.0, 0), dark)
	_add_box(Vector3(1.0, WALL_H, SIZE_Z + 1.0), Vector3(half_x, WALL_H / 2.0, 0), dark)

func _build_pillars(mat: Material) -> void:
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		for z in [-12.0, -4.0, 4.0, 12.0]:
			if absf(x) < 2.0 and absf(z - 12.0) < 2.0:
				continue # keep the player spawn clear
			_add_box(Vector3(1.1, WALL_H, 1.1), Vector3(x, WALL_H / 2.0, z), mat)

func _add_car(pos: Vector3, rot_y: float, kind: String, rust_mat: Material, tilt_x: float = 0.0, tilt_z: float = 0.0, door_open: bool = false) -> void:
	# A rusted car, grounded: body centre 0.45 m above its node, so the
	# body bottom sits at the waterline (0.14) on the floor, or deeper when
	# the node is sunk. Slight tilt reads as a flat tyre / settled suspension.
	var car := StaticBody3D.new()
	car.position = pos
	car.rotation = Vector3(tilt_x, rot_y, tilt_z)
	var body_size := Vector3(1.9, 0.62, 4.4)
	var cabin_size := Vector3(1.7, 0.55, 2.2)
	var cabin_pos := Vector3(0, 0.95, -0.2)
	var col_size := Vector3(2.0, 1.5, 4.5)
	if kind == "van":
		body_size = Vector3(1.9, 0.95, 4.6)
		cabin_size = Vector3(1.7, 0.7, 2.6)
		cabin_pos = Vector3(0, 1.15, -0.2)
	elif kind == "wagon":
		body_size = Vector3(1.9, 0.55, 5.0)
		cabin_size = Vector3(1.7, 0.5, 2.6)
		cabin_pos = Vector3(0, 0.9, -0.3)
		col_size = Vector3(2.0, 1.4, 5.1)
	# Real car shapes under the rust (Danny's sports/classic/rusted-
	# classic photos): a sedan profile — lower body, sloping hood and
	# trunk, cabin with SLOPED windshield and rear glass, bumpers,
	# grille, mirrors, headlights and taillights, detailed wheels.
	# Collision stays the same single box, so pathing and spawn points
	# are untouched. No brand logos anywhere.
	var body_y := 0.42
	var body_front := body_size.z / 2.0
	var hood_len := 1.0
	var hood_y := 0.70
	if kind == "van":
		body_y = 0.50
		hood_len = 0.6
		hood_y = 0.90
	var roof_y := cabin_pos.y + cabin_size.y / 2.0
	var shield_front_z := cabin_pos.z + cabin_size.z / 2.0
	var shield_rear_z := cabin_pos.z - cabin_size.z / 2.0
	var body_mi := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = body_size
	body_mi.mesh = body_box
	body_mi.material_override = rust_mat
	body_mi.position = Vector3(0, body_y, 0)
	car.add_child(body_mi)
	# Hood sloping down toward the front + trunk sloping down to the rear.
	var hood := MeshInstance3D.new()
	var hood_box := BoxMesh.new()
	hood_box.size = Vector3(1.85, 0.12, hood_len)
	hood.mesh = hood_box
	hood.material_override = rust_mat
	hood.position = Vector3(0, hood_y, body_front - hood_len / 2.0)
	hood.rotation.x = 0.22 if kind != "van" else 0.15
	car.add_child(hood)
	if kind != "van" and kind != "wagon":
		var trunk := MeshInstance3D.new()
		var trunk_box := BoxMesh.new()
		trunk_box.size = Vector3(1.85, 0.12, 0.9)
		trunk.mesh = trunk_box
		trunk.material_override = rust_mat
		trunk.position = Vector3(0, 0.68, -body_front + 0.45)
		trunk.rotation.x = -0.18
		car.add_child(trunk)
	if kind == "wagon":
		# Long wagon roof reaching the tailgate.
		var roof := MeshInstance3D.new()
		var roof_box := BoxMesh.new()
		roof_box.size = Vector3(1.7, 0.10, 0.95)
		roof.mesh = roof_box
		roof.material_override = rust_mat
		roof.position = Vector3(0, roof_y - 0.02, shield_rear_z - 0.45)
		car.add_child(roof)
	var cabin_mi := MeshInstance3D.new()
	var cabin_box := BoxMesh.new()
	cabin_box.size = cabin_size
	cabin_mi.mesh = cabin_box
	cabin_mi.material_override = rust_mat
	cabin_mi.position = cabin_pos
	car.add_child(cabin_mi)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.12, 0.15, 0.18)
	glass_mat.roughness = 0.15
	glass_mat.metallic = 0.7
	var chrome_mat := StandardMaterial3D.new()
	chrome_mat.albedo_color = Color(0.75, 0.74, 0.70)
	chrome_mat.roughness = 0.35
	chrome_mat.metallic = 0.9
	var tyre_mat := StandardMaterial3D.new()
	tyre_mat.albedo_color = Color(0.06, 0.06, 0.06)
	tyre_mat.roughness = 0.95
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.55, 0.54, 0.50)
	steel_mat.roughness = 0.4
	steel_mat.metallic = 0.8
	var dark_steel_mat := StandardMaterial3D.new()
	dark_steel_mat.albedo_color = Color(0.15, 0.15, 0.14)
	dark_steel_mat.roughness = 0.5
	dark_steel_mat.metallic = 0.7
	var seam_mat := StandardMaterial3D.new()
	seam_mat.albedo_color = Color(0.05, 0.05, 0.04)
	seam_mat.roughness = 0.9
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.75, 0.78, 0.72)
	lamp_mat.roughness = 0.3
	lamp_mat.metallic = 0.2
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.95, 0.8)
	lamp_mat.emission_energy_multiplier = 0.35
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.35, 0.05, 0.04)
	tail_mat.roughness = 0.3
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.1, 0.05)
	tail_mat.emission_energy_multiplier = 0.4
	var wheel_z := 1.45
	if kind == "van":
		wheel_z = 1.55
	elif kind == "wagon":
		wheel_z = 1.70
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			# Detailed wheel: tyre torus + rim ring + brake disc + hub.
			var tyre := MeshInstance3D.new()
			var ttor := TorusMesh.new()
			ttor.inner_radius = 0.20
			ttor.outer_radius = 0.34
			tyre.mesh = ttor
			tyre.material_override = tyre_mat
			tyre.position = Vector3(sx * 0.93, 0.34, sz * wheel_z)
			tyre.rotation.y = PI / 2.0
			car.add_child(tyre)
			var rim := MeshInstance3D.new()
			var rtor := TorusMesh.new()
			rtor.inner_radius = 0.12
			rtor.outer_radius = 0.17
			rim.mesh = rtor
			rim.material_override = steel_mat
			rim.position = Vector3(sx * 0.94, 0.34, sz * wheel_z)
			rim.rotation.y = PI / 2.0
			car.add_child(rim)
			var disc := MeshInstance3D.new()
			var dcyl := CylinderMesh.new()
			dcyl.top_radius = 0.13
			dcyl.bottom_radius = 0.13
			dcyl.height = 0.03
			disc.mesh = dcyl
			disc.material_override = dark_steel_mat
			disc.position = Vector3(sx * 0.92, 0.34, sz * wheel_z)
			disc.rotation.z = PI / 2.0
			car.add_child(disc)
			var hub := MeshInstance3D.new()
			var hcyl := CylinderMesh.new()
			hcyl.top_radius = 0.06
			hcyl.bottom_radius = 0.06
			hcyl.height = 0.05
			hub.mesh = hcyl
			hub.material_override = steel_mat
			hub.position = Vector3(sx * 0.95, 0.34, sz * wheel_z)
			hub.rotation.z = PI / 2.0
			car.add_child(hub)
		# Side window glass on the cabin.
		var side_glass := MeshInstance3D.new()
		var sg_box := BoxMesh.new()
		sg_box.size = Vector3(0.02, cabin_size.y * 0.7, cabin_size.z * 0.8)
		side_glass.mesh = sg_box
		side_glass.material_override = glass_mat
		side_glass.position = Vector3(sx * (cabin_size.x / 2.0 + 0.01), cabin_pos.y, cabin_pos.z)
		car.add_child(side_glass)
		# Door seams on the body sides: two vertical cuts per side.
		for dz in [0.6, -0.7]:
			var seam := MeshInstance3D.new()
			var seam_box := BoxMesh.new()
			seam_box.size = Vector3(0.02, 0.5, 0.03)
			seam.mesh = seam_box
			seam.material_override = seam_mat
			seam.position = Vector3(sx * 0.96, 0.45, dz)
			car.add_child(seam)
		# Mirror on a stalk at the cabin front sides, chrome cap.
		var stalk := MeshInstance3D.new()
		var stalk_box := BoxMesh.new()
		stalk_box.size = Vector3(0.12, 0.04, 0.04)
		stalk.mesh = stalk_box
		stalk.material_override = chrome_mat
		stalk.position = Vector3(sx * 0.91, cabin_pos.y, shield_front_z - 0.1)
		car.add_child(stalk)
		var mirror := MeshInstance3D.new()
		var mirror_box := BoxMesh.new()
		mirror_box.size = Vector3(0.06, 0.14, 0.20)
		mirror.mesh = mirror_box
		mirror.material_override = chrome_mat
		mirror.position = Vector3(sx * 0.99, cabin_pos.y + 0.02, shield_front_z - 0.1)
		car.add_child(mirror)
	# Sloped windshield + rear glass, computed from the cabin so they
	# meet the roof edge and land on the hood / trunk / tailgate.
	var ws_dy := roof_y - (body_y + body_size.y / 2.0)
	var ws_len := sqrt(0.36 + ws_dy * ws_dy)
	var ws := MeshInstance3D.new()
	var ws_box := BoxMesh.new()
	ws_box.size = Vector3(cabin_size.x * 0.94, 0.02, ws_len)
	ws.mesh = ws_box
	ws.material_override = glass_mat
	ws.position = Vector3(0, (roof_y + body_y + body_size.y / 2.0) / 2.0, shield_front_z + 0.3)
	ws.rotation.x = atan2(ws_dy, 0.6)
	car.add_child(ws)
	var rg_len := sqrt(0.25 + ws_dy * ws_dy)
	var rg := MeshInstance3D.new()
	var rg_box := BoxMesh.new()
	rg_box.size = Vector3(cabin_size.x * 0.94, 0.02, rg_len)
	rg.mesh = rg_box
	rg.material_override = glass_mat
	if kind == "wagon":
		rg.position = Vector3(0, (roof_y + body_y + body_size.y / 2.0) / 2.0, -body_front + 0.25)
		rg.rotation.x = -0.5
	else:
		rg.position = Vector3(0, (roof_y + body_y + body_size.y / 2.0) / 2.0, shield_rear_z - 0.25)
		rg.rotation.x = -atan2(ws_dy, 0.5)
	car.add_child(rg)
	# Bumpers (worn chrome), grille + surround, headlights, taillights.
	for sz in [1.0, -1.0]:
		var bumper := MeshInstance3D.new()
		var bumper_box := BoxMesh.new()
		bumper_box.size = Vector3(1.95, 0.22, 0.25)
		bumper.mesh = bumper_box
		bumper.material_override = chrome_mat
		bumper.position = Vector3(0, 0.32, sz * (body_front + 0.02))
		car.add_child(bumper)
	var grille_frame := MeshInstance3D.new()
	var gf_box := BoxMesh.new()
	gf_box.size = Vector3(1.3, 0.34, 0.05)
	grille_frame.mesh = gf_box
	grille_frame.material_override = chrome_mat
	grille_frame.position = Vector3(0, 0.55, body_front + 0.01)
	car.add_child(grille_frame)
	var grille := MeshInstance3D.new()
	var gr_box := BoxMesh.new()
	gr_box.size = Vector3(1.15, 0.26, 0.06)
	grille.mesh = gr_box
	grille.material_override = dark_steel_mat
	grille.position = Vector3(0, 0.55, body_front + 0.03)
	car.add_child(grille)
	for sx in [-1.0, 1.0]:
		var head := MeshInstance3D.new()
		var hcyl2 := CylinderMesh.new()
		hcyl2.top_radius = 0.11
		hcyl2.bottom_radius = 0.11
		hcyl2.height = 0.05
		head.mesh = hcyl2
		head.material_override = lamp_mat
		head.position = Vector3(sx * 0.62, 0.58, body_front + 0.03)
		head.rotation.x = PI / 2.0
		car.add_child(head)
		var tail := MeshInstance3D.new()
		var tail_box := BoxMesh.new()
		tail_box.size = Vector3(0.30, 0.12, 0.05)
		tail.mesh = tail_box
		tail.material_override = tail_mat
		tail.position = Vector3(sx * 0.62, 0.58, -body_front - 0.03)
		car.add_child(tail)
	if door_open:
		# Driver's door hanging open, as in the picture.
		var door := MeshInstance3D.new()
		var door_box := BoxMesh.new()
		door_box.size = Vector3(0.05, 0.6, 0.9)
		door.mesh = door_box
		door.material_override = rust_mat
		door.position = Vector3(1.3, 0.45, 0.8)
		door.rotation.y = 0.9
		car.add_child(door)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = col_size
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	car.add_child(col)
	add_child(car)

func _build_cars() -> void:
	# Spots are the picture's: sedans, vans and a wagon, half-submerged at
	# angles all over the flooded floor, one on the central ramp, two up
	# on the mezzanine. Aged paint breaking into rust spots and peeling
	# (Danny's rusted classic): the rust photo with faded paint tints
	# — faded teal, green, blue, red-brown, grey — NOT uniform rust.
	# Paint sheen (metallic 0.35, roughness 0.5) so cars catch the amber
	# and red emergency light like the night taxi under street lights.
	var rust_a := _make_material(photo_or(TEX_RUST, _rust_texture()), 0.25, 0.5, 0.35, Color(0.55, 0.75, 0.68))
	var rust_b := _make_material(photo_or(TEX_RUST, _rust_texture()), 0.25, 0.5, 0.35, Color(0.62, 0.72, 0.55))
	var rust_c := _make_material(photo_or(TEX_RUST, _rust_texture()), 0.25, 0.5, 0.35, Color(0.55, 0.65, 0.85))
	var rust_d := _make_material(photo_or(TEX_RUST, _rust_texture()), 0.25, 0.5, 0.35, Color(0.85, 0.55, 0.48))
	var rust_e := _make_material(photo_or(TEX_RUST, _rust_texture()), 0.25, 0.5, 0.35, Color(0.75, 0.75, 0.75))
	var spots: Array = [
		# pos, yaw, kind, rust, tilt_x, tilt_z, door
		[Vector3(-13, 0.0, -8), 0.3, "sedan", rust_a, 0.06, -0.05, false],
		[Vector3(-5, -0.12, -13), -0.15, "sedan", rust_b, -0.04, 0.08, true],
		[Vector3(6, 0.0, -9), 1.62, "sedan", rust_c, 0.05, 0.06, false],
		[Vector3(13, -0.12, -13), 0.1, "van", rust_d, -0.05, -0.07, false],
		[Vector3(-14, 0.0, 2), 1.45, "wagon", rust_e, 0.07, 0.04, true],
		[Vector3(12, 0.0, 3), -1.5, "sedan", rust_a, -0.06, -0.05, false],
		[Vector3(-6, 0.0, 9), 0.05, "sedan", rust_b, 0.04, 0.07, false],
		[Vector3(9, -0.12, 11), 0.2, "van", rust_c, -0.07, 0.05, false],
		[Vector3(16, 0.0, -4), 1.57, "sedan", rust_d, 0.05, -0.06, false],
		[Vector3(-17, 0.0, -13), -0.4, "sedan", rust_e, -0.05, 0.06, false],
		[Vector3(-2, 0.0, 6), -0.9, "sedan", rust_a, 0.06, -0.04, false],
		[Vector3(4, -0.12, -2), 0.4, "wagon", rust_b, -0.04, -0.08, false],
		[Vector3(-10, 0.0, -5), 0.8, "sedan", rust_c, 0.07, 0.05, false],
		[Vector3(15, 0.0, 8), -0.7, "sedan", rust_d, -0.06, 0.07, false],
		[Vector3(-18, -0.12, 6), 1.2, "van", rust_e, 0.05, -0.05, false],
		[Vector3(4, 0.0, 12), 0.9, "sedan", rust_a, -0.05, -0.06, false],
	]
	for spot in spots:
		_add_car(spot[0], spot[1], spot[2], spot[3], spot[4], spot[5], spot[6])
	# One sedan stalled on the central ramp, nose down the slope, leaving
	# the east half of the ramp clear to walk up. Sits low on the ramp so
	# it does not block the view down from the mezzanine.
	_add_car(Vector3(-5.3, 1.13, -6.5), 0.05, "sedan", rust_d, 0.40, 0.02, false)
	# Two cars parked up on the mezzanine, as in the picture.
	_add_car(Vector3(-6.5, 3.6, -16.8), 1.57, "sedan", rust_e, 0.0, 0.0, false)
	_add_car(Vector3(-2.5, 3.6, -13.8), -0.15, "sedan", rust_b, 0.0, 0.0, false)

func _build_ramp(mat: Material) -> void:
	# Wide concrete ramp in the middle, descending from the mezzanine's
	# south edge into the flood water — the picture's central ramp. The old
	# ramp floated disconnected; this one's top surface runs exactly from
	# the platform top (z=-12, y=3.6) to the floor (z=-3.5, y=0), so the
	# player and Bombies can walk it. Curbs on both sides.
	var ramp := _add_box(Vector3(4.0, 0.4, 9.23), Vector3(-4, 1.583, -7.75), mat)
	ramp.rotation.x = 0.401
	var curb_l := _add_box(Vector3(0.3, 0.5, 9.23), Vector3(-6.15, 1.7, -7.75), mat)
	curb_l.rotation.x = 0.401
	var curb_r := _add_box(Vector3(0.3, 0.5, 9.23), Vector3(-1.85, 1.7, -7.75), mat)
	curb_r.rotation.x = 0.401
	# Mezzanine platform: 10 x 6 m along the north wall, top at y=3.6.
	_add_box(Vector3(10.0, 0.4, 6.0), Vector3(-4, 3.4, -15), mat)
	# No barrier along the platform edge: Bombies must be able to walk off it
	# toward the player instead of getting wedged there.

func _build_fence() -> void:
	# Chain-link fencing along the mezzanine edge, as in the picture: the
	# west edge and the two south-edge segments either side of the ramp
	# opening. The east edge stays open where the staircase arrives.
	var tex := _chainlink_texture()
	var fence_mat := StandardMaterial3D.new()
	fence_mat.albedo_texture = tex
	fence_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fence_mat.roughness = 0.6
	fence_mat.metallic = 0.3
	fence_mat.uv1_scale = Vector3(3, 3, 3)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.25, 0.25, 0.24)
	post_mat.roughness = 0.5
	post_mat.metallic = 0.8
	var runs: Array = [
		[Vector3(-9, 4.15, -15), Vector3(0, PI / 2.0, 0), 6.0],
		[Vector3(-7.5, 4.15, -12), Vector3.ZERO, 3.0],
		[Vector3(-0.5, 4.15, -12), Vector3.ZERO, 3.0],
	]
	for run in runs:
		var plane := PlaneMesh.new()
		plane.size = Vector2(run[2], 1.1)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = fence_mat
		mi.position = run[0]
		mi.rotation = run[1]
		add_child(mi)
	# Posts at the run ends and corners.
	for p in [Vector3(-9, 4.2, -18), Vector3(-9, 4.2, -15), Vector3(-9, 4.2, -12),
			Vector3(-6, 4.2, -12), Vector3(-2, 4.2, -12), Vector3(1, 4.2, -12)]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.04
		cyl.height = 1.2
		post.mesh = cyl
		post.material_override = post_mat
		post.position = p
		add_child(post)

func _build_stairs(mat: Material) -> void:
	# Staircase along the north wall, rising westward from the floor (x=8)
	# to the mezzanine's east edge (x=1), lit red at the top — the picture's
	# staircase. A sloped collision ramp sits just under the visual steps
	# so the player and Bombies can actually walk it; its top surface runs
	# exactly from the floor (x=9, y=0) to the platform top (x=1, y=3.6).
	var slope := _add_box(Vector3(8.77, 0.3, 1.8), Vector3(5.0, 1.636, -17.2), mat)
	slope.rotation.z = -0.4227
	for i in 12:
		var x := 8.0 - float(i) * 0.62
		var slope_y := 4.05 - 0.45 * x
		_add_box(Vector3(0.66, 0.30, 1.7), Vector3(x, slope_y - 0.10, -17.2), mat, false)
	# Red emergency light at the top of the stairs + a red sign on the wall.
	var red := OmniLight3D.new()
	red.position = Vector3(0.0, 4.5, -16.0)
	red.light_color = Color(1.0, 0.1, 0.08)
	red.light_energy = 2.0
	red.omni_range = 10.0
	add_child(red)
	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = Color(0.4, 0.05, 0.04)
	sign_mat.emission_enabled = true
	sign_mat.emission = Color(1.0, 0.1, 0.08)
	sign_mat.emission_energy_multiplier = 1.5
	var sign := MeshInstance3D.new()
	var sign_box := BoxMesh.new()
	sign_box.size = Vector3(1.0, 0.4, 0.08)
	sign.mesh = sign_box
	sign.material_override = sign_mat
	sign.position = Vector3(0.5, 4.2, -17.4)
	add_child(sign)

func _build_slope_wedges() -> void:
	# Collision-only wedges filling the hollow narrowing gap under the
	# sloped slabs (ramp + stairs). A Bombie chasing the player can walk
	# under a raised slab into the pinch and wedge there, with no line
	# of sight through the slab — the garage round-3 stall. The wedges
	# have NO mesh (no visual change): their top planes sit 0.1 below
	# (ramp) or flush with (stairs) the slab tops, so walking surfaces
	# are identical and nothing can get under a slab. The mezzanine
	# platform (3.2 m clearance underneath) is not a narrowing gap and
	# needs no wedge. Verified by recomputation from the slab geometry.
	var ramp_wedge := StaticBody3D.new()
	ramp_wedge.position = Vector3(-4, -0.588, -7.75)
	ramp_wedge.rotation.x = 0.401
	var rs := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(4.0, 4.2, 9.23)
	rs.shape = rb
	ramp_wedge.add_child(rs)
	add_child(ramp_wedge)
	var stair_wedge := StaticBody3D.new()
	stair_wedge.position = Vector3(5.0, -0.502, -17.2)
	stair_wedge.rotation.z = -0.4227
	var ss := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	sb.size = Vector3(8.77, 4.2, 1.8)
	ss.shape = sb
	stair_wedge.add_child(ss)
	add_child(stair_wedge)

func _build_debris(mat: Material, parts_mat: Material, dark_mat: Material) -> void:
	# Scrap-pile standard (Danny's two scrap photos): dense tangled
	# wreckage, not clean chunks. 12 piles scattered like the old
	# chunks (same seed area), each a crushed car body + twisted panels
	# + cables + rusted motor, gear and rotor, on one low wide
	# collision box so piles stay obstacles without wedge gaps.
	# Kept clear of the ramp corridor and the player spawn.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var placed := 0
	var tries := 0
	while placed < 12 and tries < 60:
		tries += 1
		var px := rng.randf_range(-20, 20)
		var pz := rng.randf_range(-16, 16)
		if px > -6.5 and px < -1.5 and pz > -13.0 and pz < -3.0:
			continue # ramp corridor
		if Vector2(px, pz).distance_to(Vector2(0, 14)) < 2.5:
			continue # player spawn
		var pile := Node3D.new()
		pile.position = Vector3(px, 0, pz)
		pile.rotation.y = rng.randf_range(0, TAU)
		add_child(pile)
		build_wreckage_pile(pile, mat, parts_mat, dark_mat, rng)
		var col := StaticBody3D.new()
		col.position = Vector3(px, 0.35, pz)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 0.7, 1.6)
		shape.shape = box
		col.add_child(shape)
		add_child(col)
		placed += 1
	# Crates stacked near the south wall.
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(18, 0.6, 12), mat)
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(18, 0.6, 13.4), mat)
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(18, 1.8, 12.7), mat)
	# Scattered planks, tyres, rusted barrels and broken pillar stubs —
	# the rubble the picture is full of.
	var plank_mat := StandardMaterial3D.new()
	plank_mat.albedo_color = Color(0.30, 0.24, 0.16)
	plank_mat.roughness = 0.95
	for i in 6:
		_add_box(Vector3(2.2, 0.08, 0.3), Vector3(rng.randf_range(-18, 18), 0.2, rng.randf_range(-14, 14)), plank_mat, false, rng.randf_range(0, TAU))
	var tyre_mat := StandardMaterial3D.new()
	tyre_mat.albedo_color = Color(0.08, 0.08, 0.08)
	tyre_mat.roughness = 0.95
	for p in [Vector3(-10, 0.2, 6), Vector3(8, 0.2, -6), Vector3(-3, 0.2, 13)]:
		var tyre := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.22
		torus.outer_radius = 0.38
		tyre.mesh = torus
		tyre.material_override = tyre_mat
		tyre.position = p
		tyre.rotation.x = PI / 2.0
		add_child(tyre)
	for p in [Vector3(-16, 0.45, 8), Vector3(15, 0.45, -8), Vector3(2, 0.45, -12)]:
		var barrel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.35
		cyl.bottom_radius = 0.35
		cyl.height = 0.9
		barrel.mesh = cyl
		barrel.material_override = mat
		barrel.position = p
		add_child(barrel)
		var col := StaticBody3D.new()
		col.position = p
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.7, 0.9, 0.7)
		shape.shape = box
		col.add_child(shape)
		add_child(col)
	for p in [Vector3(-12, 0.65, -2), Vector3(6, 0.65, 14)]:
		_add_box(Vector3(1.0, 1.3, 1.0), p, mat)
		var cap := _add_box(Vector3(1.1, 0.4, 1.1), p + Vector3(0.2, 0.7, 0.1), mat, false)
		cap.rotation.z = 0.15

func _build_water() -> void:
	# Kingfisher water (Danny's photos): moving ripples, reflections,
	# sparkle, murky depth — plus the RTX-on look: a planar reflection
	# (see _build_reflection below) sampled through the ripple
	# distortion, and Danny's own kingfisher splash photo as a detail
	# layer. Murk blotches fake the depth you can almost see into;
	# honestly, that is a pattern, not true depth (no depth texture).
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec4 shallow_color : source_color = vec4(0.32, 0.30, 0.18, 0.72);
uniform vec4 deep_color : source_color = vec4(0.12, 0.14, 0.09, 0.85);
uniform float ripple_speed = 0.6;
uniform sampler2D reflection_tex;
uniform float reflection_strength = 0.35;
uniform sampler2D water_detail;
uniform bool has_detail = false;
varying vec2 wuv;
void vertex() {
	wuv = VERTEX.xz;
	VERTEX.y += sin(VERTEX.x * 0.8 + TIME * ripple_speed) * 0.02 + cos(VERTEX.z * 0.7 + TIME * ripple_speed * 0.8) * 0.02;
}
void fragment() {
	float r = sin(wuv.x * 0.9 + TIME * 0.7) * cos(wuv.y * 1.1 - TIME * 0.5);
	float g = sin((wuv.x + wuv.y) * 0.6 - TIME * 0.4);
	float h = sin(wuv.x * 2.3 - TIME * 1.1) * cos(wuv.y * 2.0 + TIME * 0.9);
	float mixv = clamp(0.5 + 0.22 * r + 0.22 * g + 0.12 * h, 0.0, 1.0);
	// Murk blotches: large slow variation, the almost-see-into depth.
	float murk = 0.5 + 0.5 * sin(wuv.x * 0.18 + TIME * 0.05) * sin(wuv.y * 0.22 - TIME * 0.04);
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, mixv) * (0.75 + 0.4 * murk);
	float alpha = mix(deep_color.a, shallow_color.a, mixv);
	if (has_detail) {
		vec2 duv = wuv * 0.08 + vec2(TIME * 0.008, TIME * 0.005);
		vec3 det = texture(water_detail, duv).rgb;
		float lum = dot(det, vec3(0.33));
		col = mix(col, col * (0.8 + 0.5 * lum), 0.35);
	}
	// Planar reflection through the ripple distortion: the mirrored
	// scene (pillars, cars, lights) shimmering on the water.
	vec2 ruv = SCREEN_UV + vec2(r * 0.03, g * 0.03);
	vec3 refl = texture(reflection_tex, ruv).rgb;
	col = mix(col, refl, reflection_strength);
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = 0.15;
	METALLIC = 0.35;
	SPECULAR = 0.9;
	// View-dependent brightness: brighter at grazing angles, like a
	// real reflective surface catching the lights.
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), vec3(0.0, 1.0, 0.0)), 0.0, 1.0), 2.0);
	// Warm sparkle where the amber light catches the ripples.
	float spark = pow(clamp(0.5 + 0.5 * sin(wuv.x * 2.1 + TIME * 1.3) * sin(wuv.y * 1.7 - TIME * 1.1), 0.0, 1.0), 6.0);
	EMISSION = vec3(1.0, 0.55, 0.2) * spark * 0.5 + col * fres * 0.10;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var det := photo_or(TEX_WATER, null)
	if det != null:
		mat.set_shader_parameter("water_detail", det)
		mat.set_shader_parameter("has_detail", true)
	_water_mat = mat
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE_X, SIZE_Z)
	plane.subdivide_width = 24
	plane.subdivide_depth = 20
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, WATER_Y, 0)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Visual layer 2 ONLY: the main camera (all layers) sees the water,
	# but the reflection camera (all except water + floor) must not —
	# it renders the mirrored scene, not the water itself.
	mi.layers = 2
	add_child(mi)
	# Planar reflection: a small SubViewport rendering the SAME world
	# from a camera mirrored across the water plane (updated every 3rd
	# frame in _process). Low resolution on purpose — 320x180, refreshed
	# at a third the rate, costs a fraction of a full second render,
	# and the ripple distortion hides the softness. This is the RTX-on
	# look for water (a mirrored render), NOT literal ray tracing:
	# Godot's GL Compatibility renderer has no RTX path tracing.
	_refl_viewport = SubViewport.new()
	_refl_viewport.size = Vector2i(320, 180)
	_refl_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_refl_viewport.world_3d = get_viewport().world_3d
	_refl_cam = Camera3D.new()
	_refl_cam.fov = 70.0
	_refl_cam.near = 0.1
	_refl_cam.far = 100.0
	# All layers except 2 (water) and 4 (floor slab, whose underside
	# would block the mirrored camera sitting below it).
	_refl_cam.cull_mask = 0xFFFFF & ~2 & ~8
	_refl_viewport.add_child(_refl_cam)
	add_child(_refl_viewport)
	mat.set_shader_parameter("reflection_tex", _refl_viewport.get_texture())

func _build_reflection_probe() -> void:
	# Static reflection probe over the garage floor: wet concrete and
	# glossy car paint pick up the pillars, cars and amber/red lights
	# from it (UPDATE_ONCE — the scene is static except characters,
	# and characters not reflecting is an honest, invisible trade).
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0, 2.2, 0)
	probe.extents = Vector3(22, 3, 18)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

func _build_framed_photo() -> void:
	# A survivor's keepsake, hung framed on the north wall under the
	# mezzanine: Danny's whole lake photo, framed — a legitimate use
	# of a whole photo (it hangs AS a photo, it is not a material).
	var tex := photo_or(TEX_FRAMED, null)
	if tex == null:
		return
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.08, 0.07, 0.06)
	frame_mat.roughness = 0.6
	frame_mat.metallic = 0.2
	var photo_mat := StandardMaterial3D.new()
	photo_mat.albedo_texture = tex
	photo_mat.roughness = 0.7
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.6)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = photo_mat
	mi.position = Vector3(-6, 2.0, -17.44)
	add_child(mi)
	# Frame: top, bottom, left, right bars around the photo.
	for fb_data in [[Vector3(0.96, 0.05, 0.03), Vector3(0, 0.31, 0)],
			[Vector3(0.96, 0.05, 0.03), Vector3(0, -0.31, 0)],
			[Vector3(0.05, 0.66, 0.03), Vector3(0.48, 0, 0)],
			[Vector3(0.05, 0.66, 0.03), Vector3(-0.48, 0, 0)]]:
		var fb := MeshInstance3D.new()
		var fbox := BoxMesh.new()
		fbox.size = fb_data[0]
		fb.mesh = fbox
		fb.material_override = frame_mat
		fb.position = Vector3(-6, 2.0, -17.45) + fb_data[1]
		add_child(fb)

func _tube_light(pos: Vector3, color: Color, energy: float, length: float = 3.0) -> OmniLight3D:
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
	tube_mat.emission_energy_multiplier = 2.2
	var tube := BoxMesh.new()
	tube.size = Vector3(length, 0.08, 0.18)
	var mi := MeshInstance3D.new()
	mi.mesh = tube
	mi.material_override = tube_mat
	mi.position = pos + Vector3(0, 0.25, 0)
	add_child(mi)
	return light

func _haze_glow(pos: Vector3, color: Color, size: Vector2) -> void:
	# Billboarded soft glow around a light — the haze in the picture's air.
	var m := StandardMaterial3D.new()
	m.albedo_texture = _radial_texture()
	m.albedo_color = Color(color.r, color.g, color.b, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = m
	mi.position = pos
	add_child(mi)

func _build_lights() -> void:
	# The picture's one long amber tube light, centre ceiling, plus two
	# smaller fill tubes. Red emergency light flickers in the west; the
	# staircase gets its own red light (see _build_stairs).
	_tube_light(Vector3(0, 4.4, -2), Color(1.0, 0.62, 0.25), 3.0, 6.0)
	_tube_light(Vector3(-14, 4.4, 8), Color(1.0, 0.62, 0.25), 1.2)
	_tube_light(Vector3(14, 4.4, -6), Color(1.0, 0.62, 0.25), 1.2)
	_flicker_light = _tube_light(Vector3(-16, 4.4, 12), Color(1.0, 0.12, 0.08), _flicker_base)
	# Haze glow around the main tube and the red lights.
	_haze_glow(Vector3(0, 4.3, -2), Color(1.0, 0.6, 0.25), Vector2(7, 3.5))
	_haze_glow(Vector3(0.0, 4.4, -16.0), Color(1.0, 0.12, 0.08), Vector2(4, 2))
	_haze_glow(Vector3(-16, 4.3, 12), Color(1.0, 0.12, 0.08), Vector2(4, 2))
	# Cold spill from the stairwell.
	var spill := OmniLight3D.new()
	spill.position = Vector3(18, 3.5, -15)
	spill.light_color = Color(0.55, 0.7, 0.9)
	spill.light_energy = 1.0
	spill.omni_range = 12.0
	add_child(spill)

func _build_exit() -> void:
	# Stairwell door + EXIT sign on the north-east wall.
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.12, 0.14, 0.12)
	door_mat.roughness = 0.6
	door_mat.metallic = 0.4
	_add_box(Vector3(2.4, 3.4, 0.4), Vector3(18, 1.7, -17.4), door_mat)
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
	mi.position = Vector3(18, 3.9, -17.2)
	add_child(mi)
	_exit_light = OmniLight3D.new()
	_exit_light.position = Vector3(18, 3.6, -16.0)
	_exit_light.light_color = Color(0.2, 1.0, 0.35)
	_exit_light.light_energy = 0.8
	_exit_light.omni_range = 8.0
	add_child(_exit_light)
