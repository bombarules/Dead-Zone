class_name LevelBase
extends Node3D

# Shared interface for the two locations (Garage, Factory) so the game
# manager can swap worlds without knowing which one is loaded. Subclasses
# override the methods they use; the defaults are harmless no-ops.
#
# Photographic surfaces (same method as the baked face plates): the
# concrete-wall and rusted-car photographs replace the old procedural
# noise textures. photo_or() falls back to the procedural texture if a
# photo fails to load, so a missing file never breaks the level.
const TEX_CONCRETE := "res://assets/textures/media-generation-concrete-wall-texture-0-ba314e59-a43f-4b7f-a7b7-6dbc5ca53119.webp"
const TEX_RUST := "res://assets/textures/media-generation-rusted-car-texture-0-0e20dbdc-aedb-4cbd-96af-1f893241d2ea.webp"
const TEX_RUST_PARTS := "res://assets/textures/danny-crops/rust-parts-crop.webp"

static var _photo_cache: Dictionary = {}

static func photo_tex(path: String) -> Texture2D:
	if _photo_cache.has(path):
		return _photo_cache[path]
	var t := load(path) as Texture2D
	_photo_cache[path] = t
	return t

static func photo_or(path: String, fallback: Texture2D) -> Texture2D:
	var t := photo_tex(path)
	return t if t != null else fallback

var current_room: int = 1

# --- wreckage piles (Danny's scrap standard) -------------------------------
# The old debris was clean geometric chunks. A real scrap pile is dense
# and tangled: a crushed car body, twisted panels, cable loops, and
# recognizable rusted mechanical parts — a ribbed motor, a toothed gear,
# a rotor, housings — every piece a distinct shape, all rusted (Danny's
# two scrap photos). build_wreckage_pile fills one pile node with those
# pieces; the caller adds one low, wide collision box so the pile stays
# an obstacle without any wedge gaps. Visual only besides that box.
func _wreck_mesh(pile: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	pile.add_child(mi)

func _wreck_box(pile: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = size
	_wreck_mesh(pile, m, pos, mat, rot)

func _wreck_cyl(pile: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	_wreck_mesh(pile, m, pos, mat, rot)

func build_wreckage_pile(pile: Node3D, rust_mat: Material, parts_mat: Material, dark_mat: Material, rng: RandomNumberGenerator) -> void:
	# Crushed car body: flattened body + tilted cabin + a wheel. The body
	# slab is tilted (not flat-horizontal) so it reads as wreckage, and
	# the stack rises to ~0.9 m so the pile has a heaped silhouette.
	_wreck_box(pile, Vector3(1.9, 0.45, 0.95), Vector3(0, 0.25, 0), rust_mat, Vector3(0.18, rng.randf_range(0, TAU), 0.12))
	_wreck_box(pile, Vector3(0.9, 0.4, 0.8), Vector3(0.2, 0.62, 0.1), rust_mat, Vector3(0.25, rng.randf_range(0, TAU), -0.15))
	# A leaning slab propped against the heap for a jagged silhouette.
	_wreck_box(pile, Vector3(1.2, 0.06, 0.6), Vector3(-0.7, 0.55, 0.3), rust_mat, Vector3(-0.5, 0.4, 0.35))
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.16
	wheel.outer_radius = 0.30
	_wreck_mesh(pile, wheel, Vector3(0.8, 0.3, 0.5), dark_mat, Vector3(PI / 2.0, 0, rng.randf_range(0, TAU)))
	# Twisted panels: thin boxes bent at odd angles, layered over the body.
	for i in 3:
		_wreck_box(pile, Vector3(0.9 + rng.randf_range(-0.2, 0.3), 0.05, 0.5), Vector3(rng.randf_range(-0.6, 0.6), 0.62 + 0.14 * float(i), rng.randf_range(-0.4, 0.4)), rust_mat, Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0, TAU), rng.randf_range(-0.4, 0.4)))
	# Tangled cables: thin tori looping out of the pile.
	for i in 2:
		var cable := TorusMesh.new()
		cable.inner_radius = 0.22
		cable.outer_radius = 0.26
		_wreck_mesh(pile, cable, Vector3(rng.randf_range(-0.5, 0.5), 0.45, rng.randf_range(-0.4, 0.4)), dark_mat, Vector3(rng.randf_range(0, TAU), rng.randf_range(0, TAU), 0))
	# Rusted mechanical parts, each a distinct shape (second scrap photo):
	# a ribbed motor (cylinder + fins), a toothed gear, a wound rotor.
	_wreck_cyl(pile, 0.16, 0.16, 0.5, Vector3(-0.6, 0.35, -0.3), parts_mat, Vector3(PI / 2.0, 0, rng.randf_range(0, TAU)))
	for f in 4:
		_wreck_box(pile, Vector3(0.05, 0.4, 0.36), Vector3(-0.6, 0.35, -0.3), parts_mat, Vector3(PI / 2.0, 0, float(f) * PI / 2.0))
	var gear := CylinderMesh.new()
	gear.top_radius = 0.22
	gear.bottom_radius = 0.22
	gear.height = 0.08
	_wreck_mesh(pile, gear, Vector3(0.5, 0.42, -0.4), parts_mat, Vector3(0, 0, rng.randf_range(0, TAU)))
	for t in 6:
		var a := float(t) / 6.0 * TAU
		_wreck_box(pile, Vector3(0.07, 0.08, 0.07), Vector3(0.5 + cos(a) * 0.22, 0.42, -0.4 + sin(a) * 0.22), parts_mat)
	_wreck_cyl(pile, 0.11, 0.11, 0.4, Vector3(0.1, 0.3, 0.45), parts_mat, Vector3(PI / 2.0 + 0.4, 0, 0.5))
	# A couple of rusted plates / housings to finish the layering.
	_wreck_box(pile, Vector3(0.5, 0.06, 0.4), Vector3(-0.2, 0.7, 0.2), parts_mat, Vector3(0.3, rng.randf_range(0, TAU), 0.2))

func get_player_spawn() -> Vector3:
	return Vector3.ZERO

func random_spawn_point(min_dist_to: Vector3, min_dist: float) -> Vector3:
	return Vector3.ZERO

func set_exit_open(open: bool) -> void:
	pass

func get_room_trigger_z(room: int) -> float:
	return 999.0

func open_door(idx: int) -> void:
	pass

func seal_door(idx: int) -> void:
	pass
