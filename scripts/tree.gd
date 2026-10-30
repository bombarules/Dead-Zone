class_name TreeModel
extends RefCounted

# Reusable photographic tree for outdoor locations. Built for the future
# overpass — it is NOT placed in the garage or factory flow.
#
# Danny's bar (his windswept coastal tree photo): a thin trunk with
# natural bends, an irregular wind-shaped crown, fine needle-like
# foliage you can almost see through — nothing symmetrical, nothing
# cone-shaped or blob-shaped. So this is NOT a straight trunk with
# round canopy blobs anymore: the trunk is four segments that lean
# further and further downwind, the branches are sparse and mostly on
# the downwind side, and the crown is small flattened needle tufts with
# GAPS between them (sky shows through), swept sideways, each a
# different size. The crown texture is Danny's own tree photo cropped
# to its needle foliage, with the generated wind-blown needle texture
# as variation on some tufts.
const TEX_BARK := "res://assets/textures/media-generation-tree-bark-texture-0-e71d5dbf-59a8-409c-a97a-3e4a3b4b22e2.webp"
const TEX_NEEDLE := "res://assets/textures/media-generation-windswept-needle-foliage-textu-0-06abbb0c-476e-4ea3-ae69-074c2db34bac.webp"
const TEX_CROWN := "res://assets/textures/danny-crops/foliage-crop.webp"

const TEX_CLUSTER := "res://assets/textures/danny-crops/foliage-cluster-alpha.webp"

static var _cache: Dictionary = {}

static var _cluster_mat: Material = null

static func _cluster_material() -> Material:
	if _cluster_mat != null:
		return _cluster_mat
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(TEX_CLUSTER)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.95
	_cluster_mat = m
	return m

static func _tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t := load(path) as Texture2D
	_cache[path] = t
	return t

static func _mat(path: String, tint: Color, roughness: float, repeat: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(path)
	m.albedo_color = tint
	m.roughness = roughness
	m.uv1_scale = repeat
	return m

static func build(height: float = 6.0, seed_val: int = 0) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var k := height / 6.0
	var bark := _mat(TEX_BARK, Color(0.92, 0.90, 0.88), 0.95, Vector3(2, 3, 1))
	# Wind direction: the whole tree leans and streams toward +X.
	var wind := Vector3(1, 0, 0.15).normalized()
	# Trunk: four stacked segments, each leaning further downwind than
	# the last, so the trunk bends instead of standing straight. Thin:
	# a coastal tree's trunk is a fraction of its height.
	var pos := Vector3.ZERO
	var lean := 0.05
	var r_bot := 0.11 * k
	for i in 4:
		var seg_h := height * 0.22
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r_bot * 0.78
		cm.bottom_radius = r_bot
		cm.height = seg_h
		seg.mesh = cm
		seg.material_override = bark
		# Segment centre: previous top, shifted downwind by the lean.
		var dir := (Vector3(0, 1, 0) + wind * lean).normalized()
		seg.position = pos + dir * (seg_h * 0.5)
		seg.rotation.z = -lean * 0.9
		seg.rotation.x = lean * 0.13
		root.add_child(seg)
		pos += dir * seg_h
		r_bot *= 0.78
		lean += 0.07
	# Sparse branches, mostly on the downwind side, angling up and out.
	for i in 4:
		var br := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.015 * k
		bc.bottom_radius = 0.035 * k
		bc.height = height * (0.22 + rng.randf_range(-0.04, 0.06))
		br.mesh = bc
		br.material_override = bark
		var t := 0.55 + 0.12 * float(i)
		br.position = Vector3(pos.x * t, height * (0.52 + 0.09 * float(i)), pos.z * t)
		# Downwind branches reach further; one short upwind branch for
		# asymmetry (a real tree is never all one way).
		var side := 1.0 if i < 3 else -1.0
		br.rotation.z = side * (0.9 + rng.randf_range(-0.15, 0.15))
		br.rotation.y = rng.randf_range(0, TAU)
		root.add_child(br)
	# Crown: crossed alpha-cutout clusters — the photo's OWN wind-shaped
	# crown silhouette (Danny's coastal tree, sky cut out in PIL, 24%
	# opaque so real gaps show through), three planes crossed at 60°
	# per cluster so it reads as foliage mass from every angle and
	# never as a sphere, disc or blob. The silhouette is the photo's,
	# not geometry's. Three clusters: the main crown, a downwind wisp
	# and a small upwind wisp.
	var clusters := [
		{"off": Vector3(0.9, 0.86, 0.1), "w": 2.6},
		{"off": Vector3(2.0, 0.82, -0.2), "w": 1.7},
		{"off": Vector3(-0.2, 0.88, 0.2), "w": 1.4},
	]
	var cm := _cluster_material()
	for c in clusters:
		for j in 3:
			var cl := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(c["w"] * k, c["w"] * k * 210.0 / 445.0)
			cl.mesh = pm
			cl.material_override = cm
			cl.position = Vector3(c["off"].x * k, c["off"].y * height, c["off"].z * k)
			cl.rotation.y = float(j) * PI / 3.0
			root.add_child(cl)
	return root
