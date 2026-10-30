class_name Humanoid
extends RefCounted

# Procedural realistic-proportioned humanoid builder + grime textures.
# Limbs are cylinders with elbow/knee pivots, heads are spheres with
# helmets/hair/visors, clothing is textured (noise + stains + wear) — never
# flat colors, never single-box bodies. Used by the squad heroes and Bombies.
# Works in the GL Compatibility renderer; textures are cached per color.

static var _tex_cache: Dictionary = {}

# --- procedural textures ------------------------------------------------------

static func grime_texture(base: Color, blotch: Color, amount: float = 0.45) -> ImageTexture:
	var key := "%s|%s|%.2f" % [base.to_html(), blotch.to_html(), amount]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var blotches: Array[Vector2] = []
	for i in 6:
		blotches.append(Vector2(rng.randf_range(0, s), rng.randf_range(0, s)))
	var scratches: Array = []
	for i in 5:
		scratches.append([rng.randf_range(0, s), rng.randf_range(0, s), rng.randf_range(0, TAU), rng.randf_range(12, 40)])
	for y in range(s):
		for x in range(s):
			var n := rng.randf()
			# Subtle wear: mostly the base color, with soft darker blotches.
			var v := 0.85 + n * 0.30
			var stain := 0.0
			for b in blotches:
				var d := Vector2(x, y).distance_to(b) / 26.0
				if d < 1.0:
					stain = maxf(stain, (1.0 - d) * amount)
			for sc in scratches:
				var dx: float = float(x) - float(sc[0])
				var dy: float = float(y) - float(sc[1])
				var along: float = dx * cos(float(sc[2])) + dy * sin(float(sc[2]))
				var across: float = absf(-dx * sin(float(sc[2])) + dy * cos(float(sc[2])))
				if along > 0.0 and along < float(sc[3]) and across < 1.2:
					stain = maxf(stain, amount * 0.7)
			var c: Color = base * v
			c = c.lerp(blotch, clampf(stain, 0.0, 1.0) * 0.85)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

# Skin texture (the Nano Banana realism bar, in texture form): fine pore
# speckle, short fine lines, freckle clusters, soft uneven pigmentation —
# never a flat single-color skin, never smoothed plastic. 256 px, stamped
# features (not per-pixel feature loops) so generation stays fast. The
# texture tiles once around a head sphere, so pores read at portrait
# distance and merge into believable skin variation at gameplay distance.
# Second prompt layered on top: subtle acne dots + extra micro-wrinkle
# lines (vellus hair, catchlights, lashes live as geometry in _build_face).
static func skin_texture(base: Color, freckles: float, seed_str: String, acne: float = 0.25) -> ImageTexture:
	var key := "skin|%s|%.2f|%s|%.2f" % [base.to_html(), freckles, seed_str, acne]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	# Base pass: subtle value variation + fine pore speckle.
	for y in range(s):
		for x in range(s):
			var n := rng.randf()
			var v := 0.92 + n * 0.16
			if rng.randf() < 0.05:
				v *= 0.80 # pore dot
			elif rng.randf() < 0.03:
				v *= 1.10
			img.set_pixel(x, y, base * v)
	# Uneven pigmentation: large soft blotches, stamped.
	for i in 5:
		var cx := rng.randf_range(0, s)
		var cy := rng.randf_range(0, s)
		var r := rng.randf_range(28, 80)
		var tone := Color(0.95, 0.82, 0.75) if rng.randf() < 0.5 else Color(0.85, 0.70, 0.62)
		var strength := rng.randf_range(0.05, 0.13)
		var x0 := maxi(0, int(cx - r))
		var x1 := mini(s - 1, int(cx + r))
		var y0 := maxi(0, int(cy - r))
		var y1 := mini(s - 1, int(cy + r))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var d := Vector2(x, y).distance_to(Vector2(cx, cy)) / r
				if d < 1.0:
					var w := (1.0 - d) * strength
					var c: Color = img.get_pixel(x, y)
					img.set_pixel(x, y, c.lerp(c * tone, w))
	# Fine lines: short thin darker streaks.
	for i in 26:
		var x := rng.randf_range(0, s)
		var y := rng.randf_range(0, s)
		var a := rng.randf_range(0, TAU)
		var ln := rng.randf_range(6, 22)
		for t in range(int(ln)):
			var px := int(x + cos(a) * t)
			var py := int(y + sin(a) * t)
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, img.get_pixel(px, py) * 0.88)
	# Micro wrinkles: very short faint lines.
	for i in 30:
		var x := rng.randf_range(0, s)
		var y := rng.randf_range(0, s)
		var a := rng.randf_range(0, TAU)
		var ln := rng.randf_range(3, 9)
		for t in range(int(ln)):
			var px := int(x + cos(a) * t)
			var py := int(y + sin(a) * t)
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, img.get_pixel(px, py) * 0.94)
	# Freckles: small clusters of darker dots.
	var clusters := int(freckles * 55.0)
	for i in clusters:
		var cx := rng.randf_range(0, s)
		var cy := rng.randf_range(0, s)
		for j in rng.randi_range(3, 8):
			var px := int(cx + rng.randf_range(-4, 4))
			var py := int(cy + rng.randf_range(-4, 4))
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, img.get_pixel(px, py) * Color(0.72, 0.55, 0.45))
	# Subtle acne texture: sparse tiny reddish dots.
	var acne_dots := int(acne * 70.0)
	for i in acne_dots:
		var px := int(rng.randf_range(0, s))
		var py := int(rng.randf_range(0, s))
		img.set_pixel(px, py, img.get_pixel(px, py) * Color(0.85, 0.62, 0.55))
		if px + 1 < s:
			img.set_pixel(px + 1, py, img.get_pixel(px + 1, py) * Color(0.9, 0.7, 0.62))
	# Moles: a few larger dark dots, like the lip close-up reference.
	for i in 4:
		var cx := int(rng.randf_range(0, s))
		var cy := int(rng.randf_range(0, s))
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx * dx + dy * dy <= 5:
					var px := cx + dx
					var py := cy + dy
					if px >= 0 and px < s and py >= 0 and py < s:
						img.set_pixel(px, py, img.get_pixel(px, py) * Color(0.55, 0.38, 0.30))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

static func make_skin_mat(base: Color, freckles: float, seed_str: String, roughness: float = 0.55, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0, acne: float = 0.25) -> StandardMaterial3D:
	# Oil sheen, not matte plastic and not glossy: roughness 0.55 gives
	# skin a soft specular response under the garage lights.
	var m := StandardMaterial3D.new()
	m.albedo_texture = skin_texture(base, freckles, seed_str, acne)
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m

# Lip texture: fine vertical lip lines (striations across the lip) plus
# soft tone variation — the lip close-up reference's key detail. Lip
# boxes map U along the mouth, so vertical texture lines read as lip lines.
static func lip_texture(base: Color, seed_str: String) -> ImageTexture:
	var key := "lip|%s|%s" % [base.to_html(), seed_str]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for y in range(s):
		for x in range(s):
			# Clean vertical creases: brightness varies smoothly with x
			# (no per-column random phase — that turns lines into noise
			# that mipmapping averages away). A slow second wave keeps
			# the creases irregular instead of perfectly even.
			var stri := 0.80 + 0.20 * sin(float(x) * 0.45) + 0.05 * sin(float(x) * 0.13)
			var v := stri * (0.94 + rng.randf() * 0.12)
			img.set_pixel(x, y, base * v)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

# Iris texture: radial fiber streaks + a darker limbal ring at the edge.
# Applied to a flat cylinder cap facing the camera, so the radial pattern
# reads as an iris (a sphere's UV would smear it).
static func iris_texture(eye_col: Color, seed_str: String) -> ImageTexture:
	var key := "iris|%s|%s" % [eye_col.to_html(), seed_str]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var c := float(s) / 2.0
	for y in range(s):
		for x in range(s):
			var dx := float(x) - c
			var dy := float(y) - c
			var r := sqrt(dx * dx + dy * dy) / c
			var a := atan2(dy, dx)
			var v: float
			if r > 0.95:
				v = 0.55 # limbal ring
			elif r < 0.22:
				v = 0.5 # pupil zone (the pupil mesh covers the centre)
			else:
				v = 0.85 + 0.3 * (0.5 + 0.5 * sin(a * 24.0 + rng.randf() * 0.8))
			img.set_pixel(x, y, eye_col * v)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

# Hair texture: fine combed strands — brightness varies across strands
# (x) while streaks run along the strand (y). On the hair cap this reads
# as separate combed strands at close range instead of a solid helmet;
# the fringe strand boxes carry the same texture.
static func hair_texture(base: Color, seed_str: String) -> ImageTexture:
	var key := "hair|%s|%s" % [base.to_html(), seed_str]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var strand_v: Array[float] = []
	for x in range(s):
		# Occasional darker gap between strands.
		strand_v.append(0.75 + rng.randf() * 0.45 if rng.randf() > 0.12 else 0.55)
	for y in range(s):
		for x in range(s):
			var v := strand_v[x] * (0.95 + rng.randf() * 0.1)
			img.set_pixel(x, y, base * v)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

static func make_hair_mat(base: Color, seed_str: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = hair_texture(base, seed_str)
	m.roughness = 0.9
	return m

static func mat(base: Color, roughness: float = 0.9, metallic: float = 0.0, blotch: Color = Color(0.08, 0.07, 0.06), amount: float = 0.45, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = grime_texture(base, blotch, amount)
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m

static func glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.2
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

# --- baked photographic faces -------------------------------------------------
#
# AI-generated portrait textures mapped onto a curved face plate: a
# spherical patch hugging the skull (radius 0.128*s vs skull 0.115*s, so it
# sits proud without z-fighting and tracks the head pivot). The patch spans
# azimuth ±50° and polar -75°..+30° around the skull centre (0, 0.10*s, 0);
# its UVs map into a crop rect of the portrait (image coords, origin
# top-left) so the plain studio background never shows — the crop's top
# rows tuck under the hair cap / helmet brim / hood like real hair over a
# forehead. Godot UV v=0 is the top of the imported image (screenshot-
# verified: v_uv = 1 - v_top flips the face upside down).
# The old procedural face geometry is NOT built where a plate is used,
# otherwise the character gets a double face (except the Bombie's glowing
# eye overlay, which the photo eyes do not carry).
static var _face_tex_cache: Dictionary = {}

static func face_texture(kind: String) -> Texture2D:
	if _face_tex_cache.has(kind):
		return _face_tex_cache[kind]
	var path := ""
	match kind:
		"hero":
			path = "res://assets/faces/media-generation-hero-face-0-4a5594a5-e21b-469a-835c-05343878649d.webp"
		"veteran":
			path = "res://assets/faces/media-generation-veteran-face-0-7f7a4ff7-7935-4dc1-9970-a00f4d3cb6c3.webp"
		"survivor":
			path = "res://assets/faces/media-generation-survivor-face-0-10744a75-4271-453e-b969-fa9762e4afd4.webp"
		"zombie":
			path = "res://assets/faces/media-generation-bombie-face-0-a0039a1d-4176-45e3-bf6f-b5b7a5ec8e2b.webp"
	if path == "":
		return null
	var tex := load(path) as Texture2D
	_face_tex_cache[kind] = tex
	return tex

# --- baked photographic surface textures ------------------------------------
# Same method as the face plates: generated photographs mapped onto the
# models, so cloth, skin, metal and headgear read as photographs instead
# of flat procedural colour. The photo carries the detail, the tint
# carries the character's palette.
const TEX_ARM := "res://assets/textures/media-generation-veiny-arm-skin-0-892fb4fd-4570-49c1-895f-52518f8973dd.webp"
# Same photo rotated 90 degrees: on a limb cylinder, U wraps around the
# limb and V runs along it, so the original (veins along the photo's long
# axis) wraps the veins AROUND the arm. The rotated copy puts the veins
# along V — i.e. along the forearm, the way real veins run.
const TEX_ARM_V := "res://assets/textures/veiny-arm-skin-vertical.webp"
const TEX_CLOTH := "res://assets/textures/media-generation-torn-fabric-texture-0-2db0a327-f02b-40c9-bd79-b2b928878bda.webp"
const TEX_GUNMETAL := "res://assets/textures/media-generation-worn-gunmetal-0-be51100b-477a-4a75-a2de-d9c0d2b6516a.webp"
const TEX_WOOD := "res://assets/textures/media-generation-wood-grain-stock-texture-0-ece8219c-d89c-4619-9818-cad6e2779008.webp"
const TEX_HELMET := "res://assets/textures/media-generation-worn-helmet-texture-0-eabced65-29c6-4203-8bb9-5774dc1e0dcb.webp"
const TEX_LEATHER := "res://assets/textures/media-generation-worn-boot-leather-0-e9c40703-e0b0-4047-b268-07829a4ad146.webp"
const TEX_MUSCLE := "res://assets/textures/media-generation-muscle-fibre-0-b277cf09-c49f-4bce-9f9c-ed4485ce7af0.webp"

static var _photo_tex_cache: Dictionary = {}

static func photo_tex(path: String) -> Texture2D:
	if _photo_tex_cache.has(path):
		return _photo_tex_cache[path]
	var tex := load(path) as Texture2D
	_photo_tex_cache[path] = tex
	return tex

static func photo_mat(path: String, tint: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = photo_tex(path)
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = roughness
	m.metallic = metallic
	return m

static func cloth_mat(base: Color) -> StandardMaterial3D:
	# The cloth photo is dark; lift the character colour toward white so
	# the weave and fray detail survives the tint instead of crushing to
	# black. Hue stays the character's, detail stays the photograph's.
	return photo_mat(TEX_CLOTH, base.lerp(Color.WHITE, 0.55), 0.95, 0.0)

static func bone_mat() -> StandardMaterial3D:
	# Pale bone, matte, slightly warm — the skeleton layer. Bones are
	# built inside every body (they set the proportions) but hidden
	# under muscle/skin/clothes; they are never shown in play.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.83, 0.74)
	m.roughness = 0.85
	return m

static func muscle_mat(tint: Color) -> StandardMaterial3D:
	# Striated red muscle fibre photograph, tinted per character
	# (gaunt Bombies darker). The muscle layer sits over bone and
	# under skin/clothes; never shown — hidden internal structure only.
	return photo_mat(TEX_MUSCLE, tint, 0.55, 0.0)

static func veiny_skin_mat(base: Color) -> StandardMaterial3D:
	# Bare skin, photographic: the veiny forearm photo (rotated so the
	# veins run along the limb), tinted to the character — raised veins,
	# pores and fine hairs at close range.
	return photo_mat(TEX_ARM_V, base.lerp(Color.WHITE, 0.35), 0.55, 0.0)

const TEX_PALM := "res://assets/textures/danny-crops/palm-crop.webp"
const TEX_HAND_BACK := "res://assets/textures/danny-crops/hand-back-crop.webp"

# --- ONE-PIECE head skin ---------------------------------------------------
# Danny's rule: "one piece real skin" — the face must be the head's OWN
# skin, not a mask plate stuck on. The old curved plate (azimuth +-50 deg,
# sitting proud of the skull) had a visible rim, and its edge showed a
# second partial face on the side of the head — "it looks like he's
# wearing a mask." So there is NO plate anymore. Each character gets ONE
# 2048x1024 texture for the WHOLE head sphere (assets/faces/*-head-skin):
# u = azimuth around the head (face centred at u=0.5), v = polar angle
# (v=0 top pole). The face photo sits in the centre (azimuth -50..+50,
# phi +30..-75 — the old plate's extents, so the face reads identically
# from the front); the sides/back are the same portrait's own skin tones
# extended featurelessly, with no seam where the texture wraps at the
# back. One sphere, one texture, no rim, no doubling, no mask edge —
# and the edges that remain (helmet brim, hood, hair, ears, jaw) sit ON
# the skin instead of cutting across it.
# The Bombie's glow is baked INTO the skin too: the emission map is
# black except soft discs over the photographic irises (with a dark
# pupil hole), so the eyes glow from the skin instead of floating discs
# sitting on a plate.
static var _head_skin_cache: Dictionary = {}

static func head_skin_tex(kind: String) -> Texture2D:
	if _head_skin_cache.has(kind):
		return _head_skin_cache[kind]
	var path := "res://assets/faces/%s-head-skin.webp" % kind
	if kind == "veteran" or kind == "zombie":
		# Whole-head wrap (front/side/back photos on one head-shaped
		# mesh) replaces the old front+extended-skin texture.
		var wrap := "res://assets/faces/%s-head-wrap.webp" % kind
		if ResourceLoader.exists(wrap):
			path = wrap
	var tex := load(path) as Texture2D
	_head_skin_cache[kind] = tex
	return tex

# --- anatomy: one continuous skin, deep-set eyes, skeleton + muscle ----
# The head sphere is built by hand (Godot's SphereMesh UVs do not put
# the face where the texture expects it). This builder optionally cuts
# eye HOLES through the sphere at the given eye directions, so real
# eyeballs can sit RECESSED inside skull sockets — eyes set INTO the
# head, never pasted on its surface. Without holes, anything behind the
# surface is hidden by the opaque sphere, so pasted-on eyes were the
# only option; with holes, the socket rim is the hole edge itself.
static func _eye_dir(az_deg: float, phi_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var ph := deg_to_rad(phi_deg)
	return Vector3(cos(ph) * sin(az), sin(ph), cos(ph) * cos(az))

static func _custom_head_sphere(head: Node, s: float, radius: float, centre_y: float, mat: Material, eye_dirs: Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 64
	var nv := 48
	var r := radius * s
	for iy in range(nv + 1):
		var phi := deg_to_rad(lerp(90.0, -90.0, float(iy) / float(nv)))
		for ix in range(nu + 1):
			var az := deg_to_rad(lerp(-180.0, 180.0, float(ix) / float(nu)))
			var pos := Vector3(
				r * cos(phi) * sin(az),
				centre_y * s + r * sin(phi),
				r * cos(phi) * cos(az))
			st.set_normal((pos - Vector3(0, centre_y * s, 0)).normalized())
			st.set_uv(Vector2(float(ix) / float(nu), float(iy) / float(nv)))
			st.add_vertex(pos)
	for iy in range(nv):
		for ix in range(nu):
			# Eye holes: skip any triangle whose centre falls inside
			# an eye ellipse (azimuth +-8 deg, phi +-7 deg around the
			# eye direction) so the eyeball can sit recessed behind
			# the skin surface instead of pasted on it.
			var skip := false
			if not eye_dirs.is_empty():
				var caz: float = lerp(-180.0, 180.0, (float(ix) + 0.5) / float(nu))
				var cphi: float = lerp(90.0, -90.0, (float(iy) + 0.5) / float(nv))
				for e in eye_dirs:
					if absf(caz - float(e[0])) <= 8.0 and absf(cphi - float(e[1])) <= 7.0:
						skip = true
						break
			if skip:
				continue
			var a := iy * (nu + 1) + ix
			var b := a + 1
			var c := a + (nu + 1)
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	head.add_child(mi)
	return mi

# Whole-head wrap mesh: an oval with a jaw, NOT a sphere. The wrap
# texture (front/side/back photos) is painted for a head shape; a
# sphere stretches the jaw and pinches the crown. Same 64x48 grid and
# same UV convention as _custom_head_sphere (u=0.5 front, v=0 crown,
# v=1 chin/neck), so wrap textures map identically.
static func _wrap_radius(phi_deg: float) -> float:
	# Radius factor of 0.115 at each control phi; linear between.
	var pts := [[90.0, 0.26], [60.0, 0.77], [30.0, 0.94], [0.0, 0.97], [-20.0, 0.90], [-40.0, 0.77], [-60.0, 0.52], [-90.0, 0.13]]
	for i in range(pts.size() - 1):
		var p0 = pts[i]
		var p1 = pts[i + 1]
		if phi_deg <= float(p0[0]) and phi_deg >= float(p1[0]):
			var t := (float(p0[0]) - phi_deg) / (float(p0[0]) - float(p1[0]))
			return lerpf(float(p0[1]), float(p1[1]), t)
	return float(pts[pts.size() - 1][1])

static func _wrap_point(az_deg: float, phi_deg: float, s: float, centre_y: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var ph := deg_to_rad(phi_deg)
	var r := 0.115 * s * _wrap_radius(phi_deg)
	var pos := Vector3(r * cos(ph) * sin(az) * 0.92, centre_y * s + r * sin(ph), r * cos(ph) * cos(az) * 1.02)
	if phi_deg < 0.0:
		pos.z += 0.008 * s * minf(1.0, -phi_deg / 45.0)
	return pos

static func _head_wrap(head: Node, s: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 64
	var nv := 48
	for iy in range(nv + 1):
		var phi := 90.0 - 180.0 * float(iy) / float(nv)
		for ix in range(nu + 1):
			var az := -180.0 + 360.0 * float(ix) / float(nu)
			var pos := _wrap_point(az, phi, s, 0.10)
			st.set_normal((pos - Vector3(0, 0.10 * s, 0)).normalized())
			st.set_uv(Vector2(float(ix) / float(nu), float(iy) / float(nv)))
			st.add_vertex(pos)
	for iy in range(nv):
		for ix in range(nu):
			var a := iy * (nu + 1) + ix
			var b := a + 1
			var c := a + (nu + 1)
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	head.add_child(mi)

# One eye, set INTO its socket: a dark socket disc behind the hole, the
# eyeball recessed so its front stays BEHIND the skin surface, the
# pupil and catchlight further back still, and a supraorbital ridge
# (bone above the socket) casting the deep-set shadow line. All fronts
# sit below the 0.115*s skin surface, so the eye reads as sitting in
# the skull, not stuck on the face. eye_dirs use the head-sphere
# convention: centre (0, 0.10*s, 0), face toward +Z. `shift` moves the
# whole assembly back for the smaller bare skull (radius 0.105).
static func _socket_and_eye(head: Node, s: float, az_deg: float, phi_deg: float, eye_mat: Material, pupil_mat: Material, catch_mat: Material, ridge_mat: Material, ridge: bool, shift: float = 0.0) -> void:
	var centre := Vector3(0, 0.10 * s, 0)
	var dir := _eye_dir(az_deg, phi_deg)
	var dark_m := StandardMaterial3D.new()
	dark_m.albedo_color = Color(0.02, 0.02, 0.02)
	dark_m.roughness = 0.9
	# Socket interior: dark flattened disc behind the eyeball, showing
	# as a dark ring around it through the hole.
	_sphere(head, 0.024 * s, centre + dir * (0.096 * s + shift), dark_m, Vector3(1.0, 1.0, 0.3))
	# Eyeball, recessed: front at 0.098+0.014 = 0.112 < 0.115 surface.
	_sphere(head, 0.014 * s, centre + dir * (0.098 * s + shift), eye_mat)
	# Pupil on the eyeball's front, still behind the skin surface.
	_sphere(head, 0.005 * s, centre + dir * (0.109 * s + shift), pupil_mat)
	if catch_mat != null:
		_sphere(head, 0.002 * s, centre + dir * (0.112 * s + shift) + Vector3(-0.004 * s, 0.004 * s, 0), catch_mat)
	if ridge:
		# Supraorbital ridge: a thin bone bar just above the socket.
		var rdir := _eye_dir(az_deg, phi_deg + 9.0)
		var rb := _box(head, Vector3(0.05 * s, 0.010 * s, 0.012 * s), centre + rdir * (0.116 * s + shift), ridge_mat)
		rb.rotation.z = -0.06 if az_deg < 0 else 0.06

static func _head_sphere(head: Node, s: float, kind: String, dim: float, tint: Color, glow_color: Color, glow_energy: float) -> bool:
	# Full head sphere with its own UVs (Godot's SphereMesh UVs do not
	# put the face where the texture expects it, so the sphere is built
	# by hand: azimuth -180..+180, phi +90..-90, same winding the old
	# plate used, verified front-facing by screenshot).
	var tex := head_skin_tex(kind)
	if tex == null:
		return false
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = tint * Color(dim, dim, dim, 1.0)
	mat.roughness = 0.55 # same oil sheen as the procedural skin
	# NOTE: do NOT use a full-head emission map for the zombie glow. A
	# mostly-black emission map on this sphere rendered the WHOLE head
	# glowing white-yellow (verified: face mean [142,125,78] with the
	# map, [82,64,42] without it — the map path is broken on this mesh,
	# mechanism unclear, so the glow is discrete eye spheres instead,
	# the way it worked in the plate era).
	# NO eye holes on photo heads: cutting holes through the photo and
	# inserting 3D eyeballs was tried and REVERTED — the 64x48 triangle
	# grid makes square holes, the socket discs read as black squares,
	# and the white balls read as googly doll eyes, far worse than the
	# photo's own painted eyes (verified in the head-whole shot). The
	# painted eyes ARE the eyes: they sit in the photo's own lids,
	# lashes and socket shading, they never protrude, and the head
	# stays one continuous photographic piece. True holes + recessed
	# eyeballs live only on the bare anatomy skull, where bone + dark
	# sockets read correctly.
	if kind == "veteran" or kind == "zombie":
		_head_wrap(head, s, mat)
	else:
		_custom_head_sphere(head, s, 0.115, 0.10, mat, [])
	var dark_m := StandardMaterial3D.new()
	dark_m.albedo_color = Color(0.02, 0.02, 0.02)
	dark_m.roughness = 0.4
	if kind == "zombie":
		# Sunken glow, nearly flush: the glow spheres sit almost
		# inside the skin surface (front 0.118, just 0.003 proud) in
		# the photo's own dark sunken eye area, pupils flush at
		# 0.115 — light coming FROM the socket, not a disc stuck on.
		# (The old 0.118-centre/0.135-pupil version stuck out 0.020
		# and read as headlights; the recessed-in-holes version made
		# square holes. This is the middle that reads right.)
		var glow_m := glow_mat(glow_color, glow_energy)
		# Iris positions on the wrap texture (front photo irises):
		# az -14 / +15 deg, phi +14 deg. Glow sits 0.003 proud of
		# the wrap surface over the photo's own sunken eyes.
		for eye in [[-14.0, 14.0], [15.0, 14.0]]:
			var surf := _wrap_point(float(eye[0]), float(eye[1]), s, 0.10)
			var dir := (surf - Vector3(0, 0.10 * s, 0)).normalized()
			var centre := Vector3(0, 0.10 * s, 0)
			_sphere(head, 0.014 * s, centre + dir * (0.099 * s), glow_m)
			_sphere(head, 0.005 * s, centre + dir * (0.105 * s), dark_m)
	return true

# --- mesh helpers -------------------------------------------------------------

static func _box(parent: Node, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func _cyl(parent: Node, radius: float, height: float, pos: Vector3, material: Material, radius_top: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if radius_top < 0.0 else radius_top
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func _sphere(parent: Node, radius: float, pos: Vector3, material: Material, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func _pivot(parent: Node, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p

static func _patch(parent: Node, pos: Vector3, rot_z: float, material: Material, s: float) -> MeshInstance3D:
	# Duct-tape patch: thin grey rectangle, slightly rotated like tape.
	var mi := _box(parent, Vector3(0.09 * s, 0.06 * s, 0.012 * s), pos, material)
	mi.rotation.z = rot_z
	return mi

static func _cyl2(parent: Node, top_radius: float, bottom_radius: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
	# Tapered cylinder: shoulders wider than waist, thighs wider than
	# ankles. Taper is what makes a body read as a body instead of a box.
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func _torus(parent: Node, inner_radius: float, outer_radius: float, pos: Vector3, material: Material, rot_x: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation.x = rot_x
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

# --- merged small boxes (one draw call per hand / foot) --------------------
# Hands need palm + 4 fingers + thumb and feet need heel + foot + toe:
# dozens of tiny boxes per character would double the scene's draw
# calls. So each hand and each foot is ONE SurfaceTool mesh built from
# transformed boxes. Entries: {"size": Vector3, "pos": Vector3,
# "rot": Vector3 (euler XYZ)} — all in the parent pivot's local space.
static func _merged_boxes(parent: Node, boxes: Array, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
		Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
		Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5),
	]
	# Quads, counter-clockwise seen from outside each face.
	var faces := [
		[4, 5, 6, 7, Vector3(0, 0, 1)],
		[1, 0, 3, 2, Vector3(0, 0, -1)],
		[5, 1, 2, 6, Vector3(1, 0, 0)],
		[0, 4, 7, 3, Vector3(-1, 0, 0)],
		[3, 7, 6, 2, Vector3(0, 1, 0)],
		[0, 1, 5, 4, Vector3(0, -1, 0)],
	]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var vi := 0
	for b in boxes:
		var basis := Basis.from_euler(b["rot"])
		var size: Vector3 = b["size"]
		var pos: Vector3 = b["pos"]
		for f in faces:
			for k in 4:
				var c: Vector3 = corners[f[k]]
				st.set_normal(basis * f[4])
				st.set_uv(uvs[k])
				st.add_vertex(basis * Vector3(c.x * size.x, c.y * size.y, c.z * size.z) + pos)
			st.add_index(vi)
			st.add_index(vi + 1)
			st.add_index(vi + 2)
			st.add_index(vi)
			st.add_index(vi + 2)
			st.add_index(vi + 3)
			vi += 4
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	parent.add_child(mi)

# --- hands: palm + separate fingers with knuckles, not blobs --------------
# Danny's bar (his hands photos): separate fingers with knuckle bulges
# at the joints, a thumb set apart at an angle, veins and palm lines —
# never a smooth mitten. Fingers are built incrementally along their
# curl direction so the segments join at the joints; each joint gets a
# slightly wider knuckle box, which is what makes a finger read as a
# finger instead of a stick. Two meshes per hand: palm (palm-line photo)
# and fingers+thumb (hand-back photo: veins, knuckles, wrinkles).
static func _build_hand(elbow: Node, s: float, skin_mat: Material, palm_mat: Material, mirror: float) -> void:
	var palm_y := -0.315 * s
	_merged_boxes(elbow, [
		{"size": Vector3(0.075, 0.09, 0.028) * s, "pos": Vector3(0, palm_y, 0), "rot": Vector3.ZERO},
	], palm_mat)
	var finger_boxes: Array = []
	# Four fingers: index, middle (longest), ring, pinky (shortest).
	var specs := [
		{"x": -0.0285, "len": 0.075, "fan": -0.10},
		{"x": -0.0095, "len": 0.085, "fan": -0.03},
		{"x": 0.0095, "len": 0.080, "fan": 0.03},
		{"x": 0.0285, "len": 0.060, "fan": 0.10},
	]
	for spec in specs:
		var cursor := Vector3(spec["x"] * s, (palm_y - 0.045 * s), 0)
		var curl := 0.10
		var parts := [
			{"len": spec["len"] * 0.42, "w": 0.016},
			{"len": 0.012, "w": 0.019}, # knuckle
			{"len": spec["len"] * 0.33, "w": 0.015},
			{"len": 0.011, "w": 0.018}, # knuckle
			{"len": spec["len"] * 0.25, "w": 0.013},
		]
		for part in parts:
			var rot := Vector3(curl, 0, spec["fan"])
			var dir := Basis.from_euler(rot) * Vector3(0, -1, 0)
			var half: float = part["len"] * 0.5 * s
			finger_boxes.append({"size": Vector3(part["w"], part["len"], 0.018) * s,
				"pos": cursor + dir * half, "rot": rot})
			cursor += dir * part["len"] * s
			curl += 0.08
	# Thumb: set apart on the midline side, angled out ~40 degrees.
	var tc := Vector3(mirror * 0.042 * s, (palm_y + 0.01 * s), 0)
	var tcur := 0.15
	for part in [
		{"len": 0.040, "w": 0.018},
		{"len": 0.011, "w": 0.021}, # knuckle
		{"len": 0.034, "w": 0.015},
	]:
		var rot := Vector3(tcur, 0, mirror * 0.7)
		var dir := Basis.from_euler(rot) * Vector3(0, -1, 0)
		var half: float = part["len"] * 0.5 * s
		finger_boxes.append({"size": Vector3(part["w"], part["len"], 0.019) * s,
			"pos": tc + dir * half, "rot": rot})
		tc += dir * part["len"] * s
		tcur += 0.10
	_merged_boxes(elbow, finger_boxes, skin_mat)

# --- feet: heel + foot body + toe, not squares or flat wedges ------------
# Danny's bar ("nobody has square feet"): a foot has a heel block at
# the back, a foot body, a narrower rounded toe at the front and a sole
# strip — one merged mesh, same bottom height as the old boot so every
# character still stands on the floor exactly as before.
static func _build_foot(knee: Node, s: float, boot_mat: Material, dark_mat: Material, toe_out: float) -> void:
	# A pivot so the whole foot turns out slightly (toe-out), as before.
	var pivot := _pivot(knee, Vector3.ZERO)
	pivot.rotation.y = toe_out
	_merged_boxes(pivot, [
		{"size": Vector3(0.11, 0.14, 0.11) * s, "pos": Vector3(0, -0.36 * s, 0), "rot": Vector3.ZERO}, # ankle
		{"size": Vector3(0.11, 0.10, 0.09) * s, "pos": Vector3(0, -0.43 * s, -0.055 * s), "rot": Vector3.ZERO}, # heel
		{"size": Vector3(0.11, 0.07, 0.20) * s, "pos": Vector3(0, -0.445 * s, 0.04 * s), "rot": Vector3.ZERO}, # foot body
		{"size": Vector3(0.095, 0.05, 0.09) * s, "pos": Vector3(0, -0.45 * s, 0.165 * s), "rot": Vector3.ZERO}, # toe
	], boot_mat)
	_merged_boxes(pivot, [
		{"size": Vector3(0.115, 0.02, 0.30) * s, "pos": Vector3(0, -0.47 * s, 0.03 * s), "rot": Vector3.ZERO}, # sole
	], dark_mat)

# --- anatomy layers: skeleton inside, muscle over it, skin over that ---
# build() puts these inside every body. In normal play they are hidden
# (visible=false on the parent hides the whole subtree, so they cost
# no draw calls) — they set the body's proportions and joints. They
# are NEVER shown in play: no anatomy mode, no visible wounds showing
# bone or muscle (Danny's correction). Coordinates
# match build()'s limbs exactly (same hip/shoulder heights, same
# segment lengths), so bones sit inside the muscles they shape.
static func _build_hand_bones(parent: Node, s: float, bone_m: Material, x: float, palm_y: float, mirror: float) -> void:
	# Finger bones: thin boxes following the same finger layout as
	# _build_hand (same x offsets, lengths, fan, curl), so each bone
	# sits inside its finger segment. Knuckle joints are slightly
	# wider than the shafts, like real phalanges — otherwise the
	# fingers read as uniform sticks. A wrist bridge links the
	# forearm bones to the palm (carpals).
	_box(parent, Vector3(0.025 * s, 0.03 * s, 0.02 * s), Vector3(x, palm_y + 0.03 * s, 0), bone_m)
	_box(parent, Vector3(0.03 * s, 0.02 * s, 0.012 * s), Vector3(x, palm_y, 0), bone_m)
	var specs := [
		{"x": -0.0285, "len": 0.075, "fan": -0.10},
		{"x": -0.0095, "len": 0.085, "fan": -0.03},
		{"x": 0.0095, "len": 0.080, "fan": 0.03},
		{"x": 0.0285, "len": 0.060, "fan": 0.10},
	]
	for spec in specs:
		var cursor := Vector3(x + spec["x"] * s, (palm_y - 0.045 * s), 0)
		var curl := 0.10
		for part in [{"len": spec["len"] * 0.42, "w": 0.007}, {"len": 0.012, "w": 0.010}, {"len": spec["len"] * 0.33, "w": 0.007}, {"len": 0.011, "w": 0.010}, {"len": spec["len"] * 0.25, "w": 0.006}]:
			var rot := Vector3(curl, 0, spec["fan"])
			var dir := Basis.from_euler(rot) * Vector3(0, -1, 0)
			var half: float = part["len"] * 0.5 * s
			var b := _box(parent, Vector3(part["w"] * s, part["len"] * s, part["w"] * s), cursor + dir * half, bone_m)
			b.rotation = rot
			cursor += dir * part["len"] * s
			curl += 0.08
	var tc := Vector3(x + mirror * 0.042 * s, (palm_y + 0.01 * s), 0)
	var tcur := 0.15
	for part in [{"len": 0.040, "w": 0.008}, {"len": 0.011, "w": 0.011}, {"len": 0.034, "w": 0.007}]:
		var rot := Vector3(tcur, 0, mirror * 0.7)
		var dir := Basis.from_euler(rot) * Vector3(0, -1, 0)
		var half: float = part["len"] * 0.5 * s
		var b := _box(parent, Vector3(part["w"] * s, part["len"] * s, part["w"] * s), tc + dir * half, bone_m)
		b.rotation = rot
		tc += dir * part["len"] * s
		tcur += 0.10

static func _build_foot_bones(parent: Node, s: float, bone_m: Material, x: float, knee_y: float) -> void:
	# Foot bones inside the foot-shaped boot: heel bone, metatarsals,
	# four toe bones + a big-toe bone, matching _build_foot's volumes.
	_box(parent, Vector3(0.05 * s, 0.05 * s, 0.05 * s), Vector3(x, knee_y - 0.43 * s, -0.055 * s), bone_m)
	_box(parent, Vector3(0.08 * s, 0.02 * s, 0.14 * s), Vector3(x, knee_y - 0.445 * s, 0.04 * s), bone_m)
	for i in 4:
		var tx := x + (-0.03 + 0.02 * float(i)) * s
		_box(parent, Vector3(0.012 * s, 0.012 * s, 0.05 * s), Vector3(tx, knee_y - 0.45 * s, 0.175 * s), bone_m)
	_box(parent, Vector3(0.018 * s, 0.014 * s, 0.05 * s), Vector3(x - 0.035 * s, knee_y - 0.45 * s, 0.175 * s), bone_m)

static func _build_skeleton(root: Node, s: float, bulk: float, bone_m: Material, eye_col: Color, zombie: bool) -> Node3D:
	var skel := Node3D.new()
	root.add_child(skel)
	var hip_y := 0.95 * s
	var shoulder_y := 1.56 * s
	# Skull: bone sphere slightly smaller than the skin head (0.105 vs
	# 0.115), with eye holes, a jaw, and a teeth strip. Eyeballs sit
	# recessed in the sockets (iris for people, glow for Bombies).
	var head := _pivot(skel, Vector3(0, 1.66 * s, 0))
	_custom_head_sphere(head, s, 0.105, 0.10, bone_m, [[-23.4, 10.0], [23.4, 10.0]])
	_box(head, Vector3(0.10 * s, 0.05 * s, 0.09 * s), Vector3(0, 0.015 * s, 0.01 * s), bone_m)
	_box(head, Vector3(0.07 * s, 0.012 * s, 0.012 * s), Vector3(0, -0.005 * s, 0.055 * s), bone_m)
	# Nasal cavity: a dark wedge on the skull front, below the eyes.
	_box(head, Vector3(0.018 * s, 0.03 * s, 0.01 * s), Vector3(0, 0.065 * s, 0.098 * s), mat(Color(0.05, 0.04, 0.03), 0.9))
	var white_m := mat(Color(0.92, 0.90, 0.86), 0.5)
	var dark_m := mat(Color(0.05, 0.04, 0.03), 0.9)
	var iris_m := StandardMaterial3D.new()
	iris_m.albedo_texture = iris_texture(eye_col, eye_col.to_html())
	iris_m.roughness = 0.4
	for eye in [[-23.4, 10.0], [23.4, 10.0]]:
		# Bare-skull sockets: the whole eye assembly shifts back
		# 0.010*s so the eyeball front (0.102) stays behind the
		# smaller skull surface (0.105), not proud of it.
		_socket_and_eye(head, s, float(eye[0]), float(eye[1]), white_m, dark_m, null, bone_m, true, -0.010 * s)
		var dir := _eye_dir(float(eye[0]), float(eye[1]))
		var iris := _cyl(head, 0.009 * s, 0.004 * s, Vector3(0, 0.10 * s, 0) + dir * (0.101 * s), iris_m)
		iris.rotation.x = PI / 2.0
	# Spine: stacked vertebrae down the torso centre.
	for i in 5:
		_box(skel, Vector3(0.05 * s, 0.035 * s, 0.04 * s), Vector3(0, (1.58 - 0.11 * float(i)) * s, -0.02 * s), bone_m)
	# Ribcage: a barrel of flattened tori around the chest.
	for i in 5:
		var rr := (0.16 - 0.012 * absf(float(i) - 2.0)) * s
		var rib := _torus(skel, rr, rr + 0.015 * s, Vector3(0, (1.52 - 0.07 * float(i)) * s, 0), bone_m, PI / 2.0)
		rib.scale = Vector3(1.0, 1.0, 0.75)
	# Pelvis: flattened hip bowl.
	_sphere(skel, 0.14 * s, Vector3(0, hip_y, 0), bone_m, Vector3(1.15, 0.75, 0.85))
	for sx in [-1.0, 1.0]:
		var ax: float = sx * 0.27 * s * bulk
		# Humerus + elbow joint + radius/ulna pair.
		_cyl2(skel, 0.022 * s, 0.020 * s, 0.30 * s, Vector3(ax, shoulder_y - 0.15 * s, 0), bone_m)
		_sphere(skel, 0.028 * s, Vector3(ax, shoulder_y - 0.30 * s, 0), bone_m)
		_cyl2(skel, 0.016 * s, 0.014 * s, 0.28 * s, Vector3(ax - 0.012 * s, shoulder_y - 0.44 * s, 0), bone_m)
		_cyl2(skel, 0.016 * s, 0.014 * s, 0.28 * s, Vector3(ax + 0.012 * s, shoulder_y - 0.44 * s, 0), bone_m)
		_build_hand_bones(skel, s, bone_m, ax, shoulder_y - 0.615 * s, 1.0 if sx < 0 else -1.0)
		var lx: float = sx * 0.12 * s
		# Femur + knee joint + tibia/fibula pair.
		_cyl2(skel, 0.028 * s, 0.024 * s, 0.42 * s, Vector3(lx, hip_y - 0.21 * s, 0), bone_m)
		_sphere(skel, 0.032 * s, Vector3(lx, hip_y - 0.42 * s, 0), bone_m)
		_cyl2(skel, 0.020 * s, 0.016 * s, 0.40 * s, Vector3(lx - 0.012 * s, hip_y - 0.62 * s, 0), bone_m)
		_cyl2(skel, 0.012 * s, 0.010 * s, 0.40 * s, Vector3(lx + 0.018 * s, hip_y - 0.62 * s, 0), bone_m)
		_build_foot_bones(skel, s, bone_m, lx, hip_y - 0.42 * s)
	return skel

static func _build_muscle(root: Node, s: float, bulk: float, mus_m: Material) -> Node3D:
	var mus := Node3D.new()
	root.add_child(mus)
	var hip_y := 0.95 * s
	var shoulder_y := 1.56 * s
	# Pectorals over the upper ribs, abdomen blocks below them.
	_sphere(mus, 0.11 * s, Vector3(-0.10 * s * bulk, 1.50 * s, 0.16 * s), mus_m, Vector3(1.0, 0.7, 0.5))
	_sphere(mus, 0.11 * s, Vector3(0.10 * s * bulk, 1.50 * s, 0.16 * s), mus_m, Vector3(1.0, 0.7, 0.5))
	for row in 3:
		for sx in [-1.0, 1.0]:
			_box(mus, Vector3(0.08 * s, 0.07 * s, 0.03 * s), Vector3(sx * 0.055 * s, (1.32 - 0.09 * float(row)) * s, 0.19 * s), mus_m)
	# Trapezius: neck-to-shoulder slope.
	_box(mus, Vector3(0.30 * s, 0.06 * s, 0.10 * s), Vector3(0, 1.60 * s, -0.02 * s), mus_m)
	for sx in [-1.0, 1.0]:
		var ax: float = sx * 0.27 * s * bulk
		_sphere(mus, 0.085 * s, Vector3(ax, shoulder_y, 0), mus_m) # deltoid
		_cyl2(mus, 0.055 * s * bulk, 0.045 * s * bulk, 0.30 * s, Vector3(ax, shoulder_y - 0.15 * s, 0.03 * s), mus_m) # biceps, front
		_cyl2(mus, 0.050 * s * bulk, 0.040 * s * bulk, 0.30 * s, Vector3(ax, shoulder_y - 0.15 * s, -0.03 * s), mus_m) # triceps, back
		_cyl2(mus, 0.050 * s * bulk, 0.040 * s * bulk, 0.28 * s, Vector3(ax, shoulder_y - 0.44 * s, 0), mus_m) # forearm mass
		var lx: float = sx * 0.12 * s
		_cyl2(mus, 0.085 * s * bulk, 0.065 * s * bulk, 0.42 * s, Vector3(lx, hip_y - 0.21 * s, 0.02 * s), mus_m) # quad, front
		_cyl2(mus, 0.075 * s * bulk, 0.060 * s * bulk, 0.42 * s, Vector3(lx, hip_y - 0.21 * s, -0.02 * s), mus_m) # hamstring, back
		_sphere(mus, 0.065 * s, Vector3(lx, hip_y - 0.55 * s, -0.03 * s), mus_m, Vector3(1.0, 1.3, 0.9)) # calf bulge
	return mus

# --- humanoid -----------------------------------------------------------------
#
# --- a real face ---------------------------------------------------------------
#
# Eye whites + iris + pupil (or sunken sockets + glowing eyes for Bombies),
# brows with slight asymmetry, nose bridge + tip + nostrils, lips, ears,
# under-eye shadow. Positions sit just proud of the skull sphere's surface
# at each height, so nothing sinks into the head or floats off it from the
# front. Proportions: eyes one eye-width apart at mid-head, nose centred,
# mouth below the nose — no slimming, no exaggeration.
static func _build_face(head: Node, s: float, skin_m: Material, eye_col: Color, brow_col: Color, shadow_col: Color, zombie: bool, eye_glow_m: Material, dim: bool, scar: bool, stubble: bool) -> void:
	var shadow_m := mat(shadow_col, 0.9)
	var lip_col := Color(0.42, 0.24, 0.20) if zombie else Color(0.58, 0.33, 0.30)
	var lip_m := StandardMaterial3D.new()
	lip_m.albedo_texture = lip_texture(lip_col, "lip")
	lip_m.roughness = 0.6
	var dark_m := mat(Color(0.05, 0.04, 0.03), 0.9)
	if zombie:
		for sx in [-1.0, 1.0]:
			_box(head, Vector3(0.055 * s, 0.045 * s, 0.012 * s), Vector3(sx * 0.046 * s, 0.12 * s, 0.108 * s), shadow_m)
			# Glowing iris with a dark pupil core: reads as an eye, not a
			# headlight disc, while still burning bright in the dark.
			_sphere(head, 0.024 * s, Vector3(sx * 0.045 * s, 0.12 * s, 0.112 * s), eye_glow_m)
			_sphere(head, 0.011 * s, Vector3(sx * 0.045 * s, 0.12 * s, 0.13 * s), dark_m)
	else:
		var white_m := mat(Color(0.92, 0.90, 0.86), 0.5)
		var iris_m := StandardMaterial3D.new()
		iris_m.albedo_texture = iris_texture(eye_col, eye_col.to_html())
		iris_m.roughness = 0.4
		for sx in [-1.0, 1.0]:
			_sphere(head, 0.021 * s, Vector3(sx * 0.045 * s, 0.12 * s, 0.105 * s), white_m, Vector3(1.0, 0.75, 0.55))
			# Flat iris disc facing the camera: the radial fiber texture
			# reads as a real iris (a sphere's UV would smear it).
			var iris := _cyl(head, 0.011 * s, 0.004 * s, Vector3(sx * 0.045 * s, 0.12 * s, 0.118 * s), iris_m)
			iris.rotation.x = PI / 2.0
			_sphere(head, 0.0055 * s, Vector3(sx * 0.045 * s, 0.12 * s, 0.124 * s), dark_m)
		if dim:
			# Faint eye reflections behind the hazmat visor pane.
			var glint := glow_mat(Color(0.7, 1.0, 0.8), 2.0)
			_sphere(head, 0.008 * s, Vector3(-0.04 * s, 0.13 * s, 0.126 * s), glint)
			_sphere(head, 0.008 * s, Vector3(0.04 * s, 0.13 * s, 0.126 * s), glint)
	# Brows: left a touch higher, tilts differ — no two sides identical.
	# Zombie brows are thinner and sparser. Real brows get a few short
	# hair strands along the brow line so the edge never reads as paint.
	var brow_m := mat(brow_col, 0.95)
	var brow_h := 0.008 * s if zombie else 0.012 * s
	var bl := _box(head, Vector3(0.05 * s, brow_h, 0.01 * s), Vector3(-0.046 * s, 0.178 * s, 0.085 * s), brow_m)
	bl.rotation.z = 0.12
	var br := _box(head, Vector3(0.05 * s, brow_h, 0.01 * s), Vector3(0.046 * s, 0.172 * s, 0.085 * s), brow_m)
	br.rotation.z = -0.05
	if not zombie:
		for k in 3:
			var bx := -0.06 * s + 0.03 * s * float(k)
			var bstrand := _box(head, Vector3(0.004 * s, 0.016 * s, 0.004 * s), Vector3(bx, 0.182 * s, 0.088 * s), brow_m)
			bstrand.rotation.z = 0.3 - 0.2 * float(k)
		for k in 3:
			var bx2 := 0.03 * s + 0.03 * s * float(k)
			var bstrand2 := _box(head, Vector3(0.004 * s, 0.016 * s, 0.004 * s), Vector3(bx2, 0.176 * s, 0.088 * s), brow_m)
			bstrand2.rotation.z = -0.3 + 0.2 * float(k)
	# Nose: bridge + tip + nostrils.
	_box(head, Vector3(0.018 * s, 0.07 * s, 0.02 * s), Vector3(0, 0.075 * s, 0.105 * s), skin_m)
	_sphere(head, 0.016 * s, Vector3(0, 0.035 * s, 0.10 * s), skin_m, Vector3(1.0, 0.8, 0.7))
	_sphere(head, 0.005 * s, Vector3(-0.012 * s, 0.028 * s, 0.108 * s), dark_m)
	_sphere(head, 0.005 * s, Vector3(0.012 * s, 0.028 * s, 0.108 * s), dark_m)
	# Lips: upper thinner than lower.
	_box(head, Vector3(0.055 * s, 0.012 * s, 0.012 * s), Vector3(0, -0.002 * s, 0.055 * s), lip_m)
	_box(head, Vector3(0.05 * s, 0.016 * s, 0.012 * s), Vector3(0, -0.018 * s, 0.055 * s), lip_m)
	# Ears: slightly different sizes, like real ones.
	_sphere(head, 0.028 * s, Vector3(-0.112 * s, 0.09 * s, 0), skin_m, Vector3(0.5, 1.0, 0.7))
	_sphere(head, 0.026 * s, Vector3(0.112 * s, 0.088 * s, 0), skin_m, Vector3(0.5, 1.0, 0.7))
	# Under-eye shadow: thin darker patches below each eye.
	_box(head, Vector3(0.045 * s, 0.014 * s, 0.008 * s), Vector3(-0.045 * s, 0.085 * s, 0.112 * s), shadow_m)
	_box(head, Vector3(0.045 * s, 0.014 * s, 0.008 * s), Vector3(0.045 * s, 0.085 * s, 0.112 * s), shadow_m)
	if not zombie:
		# Catchlights: tiny bright reflections on each iris — eyes in
		# sharp focus read as alive, not painted. (Dim visor faces keep
		# their green glints instead.)
		if not dim:
			var catch_m := glow_mat(Color(1.0, 1.0, 1.0), 1.5)
			_sphere(head, 0.003 * s, Vector3(-0.049 * s, 0.125 * s, 0.128 * s), catch_m)
			_sphere(head, 0.003 * s, Vector3(0.041 * s, 0.125 * s, 0.128 * s), catch_m)
		# Upper lash line: a thin dark strip above each eye.
		var lash_l := _box(head, Vector3(0.05 * s, 0.006 * s, 0.006 * s), Vector3(-0.045 * s, 0.142 * s, 0.108 * s), dark_m)
		lash_l.rotation.z = 0.05
		var lash_r := _box(head, Vector3(0.05 * s, 0.006 * s, 0.006 * s), Vector3(0.045 * s, 0.142 * s, 0.108 * s), dark_m)
		lash_r.rotation.z = -0.05
		# Crow's feet: micro wrinkles at the outer eye corners.
		for sx in [-1.0, 1.0]:
			var cf1 := _box(head, Vector3(0.016 * s, 0.004 * s, 0.004 * s), Vector3(sx * 0.075 * s, 0.115 * s, 0.10 * s), shadow_m)
			cf1.rotation.z = sx * 0.5
			var cf2 := _box(head, Vector3(0.014 * s, 0.004 * s, 0.004 * s), Vector3(sx * 0.073 * s, 0.105 * s, 0.10 * s), shadow_m)
			cf2.rotation.z = sx * 0.9
		# Vellus hair: sparse fine fuzz on cheeks and temples — the
		# peach-fuzz detail that keeps skin from reading as plastic.
		var vellus_m := mat(Color(0.45, 0.38, 0.30), 0.95)
		for sx in [-1.0, 1.0]:
			var v1 := _box(head, Vector3(0.006 * s, 0.03 * s, 0.006 * s), Vector3(sx * 0.075 * s, 0.05 * s, 0.072 * s), vellus_m)
			v1.rotation.z = -sx * 0.2
			var v2 := _box(head, Vector3(0.006 * s, 0.025 * s, 0.006 * s), Vector3(sx * 0.10 * s, 0.10 * s, 0.057 * s), vellus_m)
			v2.rotation.z = sx * 0.15
	if scar:
		var scar_m := mat(Color(0.78, 0.62, 0.52), 0.8)
		var sc := _box(head, Vector3(0.008 * s, 0.07 * s, 0.006 * s), Vector3(0.06 * s, 0.06 * s, 0.09 * s), scar_m)
		sc.rotation.z = 0.4
	if stubble:
		var stub_m := mat(Color(0.20, 0.16, 0.12), 0.95)
		_box(head, Vector3(0.05 * s, 0.05 * s, 0.01 * s), Vector3(-0.045 * s, 0.0 * s, 0.04 * s), stub_m)
		_box(head, Vector3(0.05 * s, 0.05 * s, 0.01 * s), Vector3(0.045 * s, 0.0 * s, 0.04 * s), stub_m)

static func _build_hazmat_face(head: Node, s: float, tape_mat: Material, mask_mat: Material, filter_mat: Material, visor_pane_mat: Material, dark_mat: Material, face_skin_m: Material, eye_col: Color, shadow_col: Color, skin_ok: bool) -> void:
	# The picture's face, piece by piece. The visor is a CURVED band (a
	# cylinder ring) around the head, not a flat box — it wraps like the
	# picture's visor, with dark frame rings top and bottom, the face
	# faintly visible behind the green pane, and crack lines across it.
	# Below it, a proper respirator: rounded mask body, central mouthpiece,
	# two big round cheek filters with dark intake caps, taped straps.
	# The hood is bigger now (r 0.145), so the band's front arc pokes out
	# of it while the back half stays hidden inside the hood.
	# The face behind the pane is the one-piece head skin (dimmed), built
	# in build() — NO plate here: a plate under the visor would be a
	# second face on the same head (the mask artifact). The old dim
	# procedural face below is only a fallback if the skin texture is
	# missing. The hood sits behind it, so the face reads through the
	# green pane.
	if not skin_ok:
		_build_face(head, s, face_skin_m, eye_col, Color(0.12, 0.09, 0.07), shadow_col, false, dark_mat, true, false, false)
	# Open tube (no caps): just the curved visor surface, no green lid.
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.14 * s
	band_mesh.bottom_radius = 0.14 * s
	band_mesh.height = 0.11 * s
	band_mesh.cap_top = false
	band_mesh.cap_bottom = false
	var band := MeshInstance3D.new()
	band.mesh = band_mesh
	band.material_override = visor_pane_mat
	band.position = Vector3(0, 0.12 * s, 0.01 * s)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	head.add_child(band)
	# Frame rings top and bottom of the band — thin, so they read as a
	# visor rim, not a helmet brim.
	_torus(head, 0.14 * s, 0.148 * s, Vector3(0, 0.175 * s, 0.01 * s), dark_mat, PI / 2.0)
	_torus(head, 0.14 * s, 0.148 * s, Vector3(0, 0.065 * s, 0.01 * s), dark_mat, PI / 2.0)
	# Crack lines across the pane's front arc.
	var c1 := _box(head, Vector3(0.004 * s, 0.11 * s, 0.004 * s), Vector3(-0.03 * s, 0.12 * s, 0.15 * s), dark_mat)
	c1.rotation.z = 0.5
	var c2 := _box(head, Vector3(0.004 * s, 0.09 * s, 0.004 * s), Vector3(0.04 * s, 0.12 * s, 0.15 * s), dark_mat)
	c2.rotation.z = -0.7
	# Gas mask: rounded respirator body + central mouthpiece + dual big
	# round cheek filters with dark intake caps.
	_sphere(head, 0.06 * s, Vector3(0, 0.03 * s, 0.08 * s), mask_mat, Vector3(1.3, 0.9, 0.7))
	var mouth := _cyl(head, 0.045 * s, 0.05 * s, Vector3(0, 0.03 * s, 0.12 * s), mask_mat)
	mouth.rotation.x = PI / 2.0
	for sx in [-1.0, 1.0]:
		var rim := _cyl(head, 0.048 * s, 0.02 * s, Vector3(sx * 0.075 * s, 0.04 * s, 0.10 * s), dark_mat)
		rim.rotation.x = PI / 2.0
		var filt := _cyl(head, 0.045 * s, 0.05 * s, Vector3(sx * 0.075 * s, 0.04 * s, 0.11 * s), filter_mat)
		filt.rotation.x = PI / 2.0
		var cap := _cyl(head, 0.035 * s, 0.015 * s, Vector3(sx * 0.075 * s, 0.04 * s, 0.135 * s), dark_mat)
		cap.rotation.x = PI / 2.0
		# Taped strap from the mask to the hood side.
		var strap := _box(head, Vector3(0.10 * s, 0.03 * s, 0.015 * s), Vector3(sx * 0.11 * s, 0.07 * s, 0.04 * s), tape_mat)
		strap.rotation.y = sx * 0.5
	# Duct-tape patches on the hood (positions sit on the pulled-back hood
	# sphere's surface, so they read as tape on the hood, not floaters).
	_patch(head, Vector3(0, 0.24 * s, 0.055 * s), 0.1, tape_mat, s)
	_patch(head, Vector3(-0.10 * s, 0.17 * s, 0.055 * s), 0.4, tape_mat, s)
	_patch(head, Vector3(0.10 * s, 0.15 * s, 0.055 * s), -0.3, tape_mat, s)

# spec keys (all optional, sensible defaults):
#   height, skin, shirt, pants, boots, jacket, helmet (bool), helmet_color,
#   hair (bool), hair_color, patchy_hair (bool), hood (bool), hood_color,
#   visor (bool), visor_color, backpack (bool), backpack_color,
#   zombie (bool), bloated (bool), bulk (float),
#   weapon ("rifle" | "shotgun" | "smg" | "" | "improvised"), eye_glow (Color),
#   eye_color (Color), freckles (float), skin_seed (String), acne (float),
#   scar (bool), stubble (bool),
#   skin_emission (Color), skin_emission_energy (float), hazmat (bool),
#   face ("hero" | "veteran" | "survivor" | "zombie" | ""), face_tint (Color)
# Returns: {root, leg_l, leg_r, arm_l, arm_r, head, skin_mat, eye_mat, gun}

static func build(spec: Dictionary) -> Dictionary:
	var height: float = float(spec.get("height", 1.8))
	var s := height / 1.8
	var bulk: float = float(spec.get("bulk", 1.0))
	var skin_col: Color = spec.get("skin", Color(0.72, 0.55, 0.42))
	var shirt_col: Color = spec.get("shirt", Color(0.4, 0.4, 0.35))
	var pants_col: Color = spec.get("pants", Color(0.25, 0.26, 0.28))
	var boots_col: Color = spec.get("boots", Color(0.15, 0.12, 0.1))
	var jacket_col: Color = spec.get("jacket", shirt_col)
	var zombie: bool = bool(spec.get("zombie", false))
	var bloated: bool = bool(spec.get("bloated", false))
	var skin_emission: Color = spec.get("skin_emission", Color(0, 0, 0))
	var skin_emission_energy: float = float(spec.get("skin_emission_energy", 0.0))

	var skin_mat := make_skin_mat(skin_col, float(spec.get("freckles", 0.25)), String(spec.get("skin_seed", "default")), 0.55, skin_emission, skin_emission_energy, float(spec.get("acne", 0.25)))
	# The head behind the hazmat visor sits in shadow: a darkened skin
	# texture there (applied after the hazmat flag is read below), so the
	# face reads dim through the green pane instead of washing it pale.
	var head_skin_mat := skin_mat
	# Photographic clothing: torn-fabric photo per garment colour, not one
	# flat cloth colour. Bare skin (arms, hands, ears, head sides/back)
	# uses the veiny-arm photo tinted to the character.
	var shirt_mat := cloth_mat(shirt_col)
	var jacket_mat := cloth_mat(jacket_col)
	var pants_mat := cloth_mat(pants_col)
	var boots_mat := photo_mat(TEX_LEATHER, boots_col.lerp(Color.WHITE, 0.4), 0.75, 0.05)
	var dark_mat := mat(Color(0.14, 0.14, 0.13), 0.85, 0.1)
	# Photographic gunmetal for every weapon: scratched worn steel with an
	# oil sheen, lifted slightly so it still reads in the dark garage.
	# Grips/stocks get dark worn fabric.
	var metal_mat := photo_mat(TEX_GUNMETAL, Color(1.2, 1.2, 1.2), 0.4, 0.8)
	var grip_mat := photo_mat(TEX_CLOTH, Color(0.30, 0.30, 0.30), 0.95, 0.0)
	var bare_skin_mat := veiny_skin_mat(skin_col)
	# Zombie eyes burn brighter in the dark — the reference screenshot's
	# Bombie is two glowing eyes by a rusted car. Bigger, too, so they
	# read at a distance in the dark garage.
	var eye_mat := glow_mat(spec.get("eye_glow", Color(1.0, 0.1, 0.05)), 8.0 if zombie else 4.0)

	# Hazmat hero (concept picture): acid-yellow suit, heavily grimed —
	# especially the lower legs — with grey duct tape, a cracked green
	# visor, gas mask, coiled hose and a chest rig. Only the hazmat builder
	# uses these materials; veteran / survivor / Bombies are untouched.
	var hazmat: bool = bool(spec.get("hazmat", false))
	if hazmat:
		head_skin_mat = make_skin_mat(skin_col * 0.55, float(spec.get("freckles", 0.25)), String(spec.get("skin_seed", "default")) + "_dim", 0.55, skin_emission, skin_emission_energy, float(spec.get("acne", 0.25)))
	var tape_mat := mat(Color(0.45, 0.45, 0.42), 0.85, 0.0, Color(0.2, 0.2, 0.18), 0.4)
	var glove_mat := photo_mat(TEX_LEATHER, Color(0.35, 0.35, 0.33).lerp(Color.WHITE, 0.4), 0.9, 0.0)
	var mask_mat := mat(Color(0.25, 0.25, 0.24), 0.4, 0.6, Color(0.1, 0.08, 0.05), 0.5)
	var filter_mat := mat(Color(0.38, 0.38, 0.36), 0.5, 0.5, Color(0.15, 0.12, 0.08), 0.5)
	var canister_mat := mat(Color(0.55, 0.55, 0.52), 0.4, 0.3, Color(0.2, 0.15, 0.08), 0.4)
	var hose_mat := mat(Color(0.30, 0.30, 0.25), 0.9, 0.0, Color(0.1, 0.09, 0.06), 0.5)
	var leg_mat := pants_mat
	var boot_mat_haz := boots_mat
	if hazmat:
		shirt_mat = cloth_mat(Color(0.80, 0.64, 0.09))
		jacket_mat = shirt_mat
		pants_mat = cloth_mat(Color(0.78, 0.62, 0.10))
		leg_mat = cloth_mat(Color(0.70, 0.54, 0.10))
		boot_mat_haz = photo_mat(TEX_LEATHER, Color(0.32, 0.28, 0.22).lerp(Color.WHITE, 0.4), 0.75, 0.05)
	var visor_pane_mat := StandardMaterial3D.new()
	visor_pane_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visor_pane_mat.albedo_color = Color(0.08, 0.45, 0.22, 0.6)
	visor_pane_mat.emission_enabled = true
	visor_pane_mat.emission = Color(0.08, 0.8, 0.3)
	visor_pane_mat.emission_energy_multiplier = 1.2
	visor_pane_mat.roughness = 0.15

	var root := Node3D.new()
	var hip_y := 0.95 * s
	var shoulder_y := 1.56 * s

	# ANATOMY LAYERS: every person is skeleton inside, muscle over it,
	# ONE continuous skin over that, clothes on top. The skeleton and
	# muscle are built for every character; in normal play they are
	# hidden inside the body (visible=false hides the whole subtree,
	# so they cost no draw calls) and they set the proportions and
	# joints.
	var bone_m := bone_mat()
	var mus_m := muscle_mat(skin_col * 0.85 if zombie else Color(1.0, 0.95, 0.95))
	# NO anatomy mode: skeleton + muscle are hidden internal structure
	# only (Danny's correction — the anatomy pictures were an example
	# of what is UNDERNEATH the skin, never to be shown). Any spec
	# asking for anatomy gets a normal clothed body instead.
	var skel := _build_skeleton(root, s, bulk, bone_m, spec.get("eye_color", Color(0.25, 0.18, 0.12)), zombie)
	skel.visible = false
	var mus := _build_muscle(root, s, bulk, mus_m)
	mus.visible = false

	# Legs: hip pivot > thigh > knee pivot > shin + boot. Feet slightly apart,
	# toes angled out a touch — nobody stands at perfect attention.
	var leg_l := _pivot(root, Vector3(-0.12 * s, hip_y, 0))
	var leg_r := _pivot(root, Vector3(0.12 * s, hip_y, 0))
	for leg in [leg_l, leg_r]:
		# Hazmat: baggy trousers gathered at the ankle, filthiest at the
		# bottom, dark knee pads, duct-tape patches, dirty work boots.
		# Tapered limbs (thigh wider than ankle) read as legs, not posts.
		var thigh_top := 0.10 * s * bulk if hazmat else 0.09 * s * bulk
		var thigh_bot := 0.08 * s * bulk if hazmat else 0.072 * s * bulk
		var shin_top := 0.078 * s * bulk if hazmat else 0.068 * s * bulk
		var shin_bot := 0.062 * s * bulk if hazmat else 0.055 * s * bulk
		_cyl2(leg, thigh_top, thigh_bot, 0.42 * s, Vector3(0, -0.21 * s, 0), leg_mat)
		# Small quad shape on the thigh front, subordinate to the limb.
		_sphere(leg, 0.070 * s * bulk, Vector3(0, -0.14 * s, 0.045 * s), leg_mat, Vector3(1.0, 1.4, 0.7))
		var knee := _pivot(leg, Vector3(0, -0.42 * s, 0))
		_cyl2(knee, shin_top, shin_bot, 0.40 * s, Vector3(0, -0.20 * s, 0), leg_mat)
		# Small calf shape on the shin back, subordinate to the limb.
		_sphere(knee, 0.050 * s * bulk, Vector3(0, -0.10 * s, -0.045 * s), leg_mat, Vector3(1.0, 1.4, 0.7))
		var boot_mat_use := boot_mat_haz if hazmat else boots_mat
		# Foot-shaped boot, not a box + wedge: heel, foot body, toe,
		# sole — with the same slight toe-out per foot as before.
		_build_foot(knee, s, boot_mat_use, dark_mat, 0.08 if leg == leg_l else -0.08)
		if hazmat:
			_box(knee, Vector3(0.11 * s, 0.13 * s, 0.04 * s), Vector3(0, -0.02 * s, 0.08 * s), mat(Color(0.16, 0.16, 0.15), 0.9, 0.0))
			_patch(leg, Vector3(0, -0.20 * s, 0.10 * s), 0.2, tape_mat, s)
			_patch(knee, Vector3(0, -0.22 * s, 0.085 * s), -0.3, tape_mat, s)
			_torus(knee, 0.075 * s, 0.095 * s, Vector3(0, -0.38 * s, 0), leg_mat, PI / 2.0)

	# Pelvis, belt, torso — round and tapered, not stacked boxes. The
	# torso is a tapered cylinder (shoulders wider than waist) with round
	# shoulder caps; chest pockets and straps sit on its curved front.
	_cyl2(root, 0.20 * s * bulk, 0.17 * s * bulk, 0.18 * s, Vector3(0, 1.02 * s, 0), pants_mat)
	_cyl(root, 0.21 * s * bulk, 0.06 * s, Vector3(0, 1.12 * s, 0), dark_mat)
	_cyl2(root, 0.235 * s * bulk, 0.19 * s * bulk, 0.42 * s, Vector3(0, 1.33 * s, 0), shirt_mat)
	_cyl2(root, 0.25 * s * bulk, 0.21 * s * bulk, 0.30 * s, Vector3(0, 1.44 * s, 0), jacket_mat)
	_sphere(root, 0.09 * s, Vector3(-0.25 * s * bulk, 1.56 * s, 0), jacket_mat)
	_sphere(root, 0.09 * s, Vector3(0.25 * s * bulk, 1.56 * s, 0), jacket_mat)
	_box(root, Vector3(0.12 * s, 0.12 * s, 0.03 * s), Vector3(-0.10 * s, 1.48 * s, 0.22 * s), shirt_mat)
	_box(root, Vector3(0.12 * s, 0.12 * s, 0.03 * s), Vector3(0.10 * s, 1.48 * s, 0.22 * s), shirt_mat)

	if hazmat:
		# Chest rig from the picture: belt buckle, twin metal canisters on
		# the belt, hip pouches, diagonal chest straps, duct-tape patches.
		# Positions sit on the round torso's front surface.
		_box(root, Vector3(0.09 * s, 0.05 * s, 0.025 * s), Vector3(0, 1.12 * s, 0.225 * s), metal_mat)
		for sx in [-1.0, 1.0]:
			_cyl(root, 0.04 * s, 0.15 * s, Vector3(sx * 0.085 * s, 1.06 * s, 0.22 * s), canister_mat)
			_cyl(root, 0.045 * s, 0.03 * s, Vector3(sx * 0.085 * s, 1.15 * s, 0.22 * s), mask_mat)
			_box(root, Vector3(0.11 * s, 0.13 * s, 0.07 * s), Vector3(sx * 0.19 * s, 1.06 * s, 0.12 * s), mat(Color(0.30, 0.28, 0.20), 0.95, 0.0, Color(0.08, 0.07, 0.05), 0.55))
			var strap := _box(root, Vector3(0.05 * s, 0.42 * s, 0.02 * s), Vector3(sx * 0.08 * s, 1.40 * s, 0.22 * s), dark_mat)
			strap.rotation.z = -sx * 0.35
		_box(root, Vector3(0.10 * s, 0.12 * s, 0.06 * s), Vector3(0.13 * s, 1.42 * s, 0.20 * s), mat(Color(0.30, 0.28, 0.20), 0.95, 0.0, Color(0.08, 0.07, 0.05), 0.55))
		_patch(root, Vector3(-0.12 * s, 1.50 * s, 0.215 * s), 0.15, tape_mat, s)
		_patch(root, Vector3(0.12 * s, 1.50 * s, 0.215 * s), -0.2, tape_mat, s)
		_patch(root, Vector3(0, 1.30 * s, 0.225 * s), 0.05, tape_mat, s)
	if zombie:
		# Torn clothing: irregular skin patches where the shirt has rotted
		# through, plus jagged frayed strips hanging from the shirt hem —
		# torn, not cut straight. Patches are rotated and fray-edged so
		# they read as tears, not pasted rectangles.
		var p1 := _box(root, Vector3(0.09 * s, 0.07 * s, 0.02 * s), Vector3(-0.08 * s, 1.38 * s, 0.225 * s), skin_mat)
		p1.rotation.z = 0.15
		var p2 := _box(root, Vector3(0.07 * s, 0.10 * s, 0.02 * s), Vector3(0.12 * s, 1.24 * s, 0.21 * s), skin_mat)
		p2.rotation.z = -0.2
		_box(root, Vector3(0.06 * s, 0.06 * s, 0.02 * s), Vector3(0.02 * s, 1.44 * s, 0.225 * s), skin_mat)
		var fp := _box(root, Vector3(0.02 * s, 0.06 * s, 0.02 * s), Vector3(-0.02 * s, 1.36 * s, 0.225 * s), shirt_mat)
		fp.rotation.z = 0.4
		for f in 3:
			var fstrip := _box(root, Vector3(0.03 * s, (0.14 + 0.08 * float(f)) * s, 0.02 * s), Vector3((0.10 + 0.05 * float(f)) * s, (0.98 - 0.02 * float(f)) * s, 0.19 * s), shirt_mat)
			fstrip.rotation.z = 0.15 + 0.2 * float(f)
		# Torn wound: dark torn flesh + a skin flap, NO bone or muscle
		# showing (anatomy stays underneath, never visible).
		_box(root, Vector3(0.14 * s, 0.10 * s, 0.015 * s), Vector3(0.02 * s, 1.30 * s, 0.225 * s), mat(Color(0.22, 0.06, 0.04), 0.9, 0.0))
		var rflap := _box(root, Vector3(0.03 * s, 0.05 * s, 0.012 * s), Vector3(-0.06 * s, 1.30 * s, 0.23 * s), skin_mat)
		rflap.rotation.z = 0.6
	if bloated:
		# Swollen belly + glowing cracks.
		_sphere(root, 0.24 * s, Vector3(0, 1.25 * s, 0.06 * s), skin_mat, Vector3(1.0, 0.85, 0.9))
		var crack_mat := glow_mat(Color(1.0, 0.5, 0.05), 5.0)
		_box(root, Vector3(0.28 * s, 0.05 * s, 0.03 * s), Vector3(0, 1.30 * s, 0.24 * s), crack_mat)

	# Head: sphere skull + a real face (whites/iris/pupil, brows, nose,
	# lips, ears, under-eye shadow) — or sunken sockets + glowing eyes
	# for Bombies. The hazmat face is built dim inside the visor block.
	var head := _pivot(root, Vector3(0, 1.66 * s, 0))
	# ONE-PIECE head: the whole head is one sphere with one skin texture
	# (face in front, continuous skin at the sides/back) — no plate, no
	# rim, no doubled side face, no mask. Falls back to the old skull +
	# procedural face if the skin texture failed to load.
	var head_photo_mat := veiny_skin_mat(skin_col * 0.55) if hazmat else bare_skin_mat
	var eye_col: Color = spec.get("eye_color", Color(0.25, 0.18, 0.12))
	var brow_col: Color = spec.get("hair_color", Color(0.12, 0.09, 0.07))
	var face_shadow_col := skin_col * (0.36 if hazmat else 0.65)
	var face_kind: String = String(spec.get("face", ""))
	var use_wrap := face_kind == "veteran" or face_kind == "zombie"
	var head_ok := false
	if face_kind != "":
		head_ok = _head_sphere(head, s, face_kind, 0.62 if hazmat else 1.0,
			spec.get("face_tint", Color.WHITE),
			spec.get("eye_glow", Color(1.0, 0.1, 0.05)), 8.0 if zombie else 4.0)
	if not head_ok:
		# Fallback skull: same hand-built sphere, NO eye holes — the
		# procedural face's eyes sit on the surface (the old look),
		# which beats square holes around doll eyes. True recessed
		# eyes live on the bare anatomy skull only.
		_custom_head_sphere(head, s, 0.115, 0.10, head_photo_mat, [])
		if zombie:
			_build_face(head, s, head_skin_mat, eye_col, brow_col, face_shadow_col, true, eye_mat, false, false, false)
		elif not bool(spec.get("visor", false)):
			_build_face(head, s, head_skin_mat, eye_col, brow_col, face_shadow_col, false, eye_mat, false, bool(spec.get("scar", false)), bool(spec.get("stubble", false)))
	# Ears on every NON-wrap character. Wrap heads carry their own
	# photographic ears in the texture — separate spheres would
	# double the ear and break the "face connects to ear" read.
	if not use_wrap:
		_sphere(head, 0.028 * s, Vector3(-0.112 * s, 0.09 * s, 0), head_photo_mat, Vector3(0.5, 1.0, 0.7))
		_sphere(head, 0.026 * s, Vector3(0.112 * s, 0.088 * s, 0), head_photo_mat, Vector3(0.5, 1.0, 0.7))
	if not use_wrap and bool(spec.get("hair", false)):
		var hair_m := make_hair_mat(spec.get("hair_color", Color(0.12, 0.09, 0.06)), String(spec.get("skin_seed", "default")) + "_hair")
		_sphere(head, 0.12 * s, Vector3(0, 0.17 * s, -0.01 * s), hair_m, Vector3(1.0, 0.62, 1.05))
		# Strands, not a helmet: a fringe over the forehead at varied
		# lengths and tilts, plus side strands — slightly messy, never
		# uniform. Patchy (zombie) hair gets fewer, shorter strands.
		var patchy := bool(spec.get("patchy_hair", false))
		var n_strands := 6 if patchy else 12
		for i in n_strands:
			var fx := -0.09 * s + (0.18 * s * float(i) / maxf(1.0, float(n_strands - 1)))
			var flen := ((0.05 + 0.004 * float((i * 37) % 10)) if patchy else (0.08 + 0.005 * float((i * 37) % 10))) * s
			var strand := _box(head, Vector3(0.014 * s, flen, 0.008 * s), Vector3(fx, (0.20 * s - flen * 0.5), 0.11 * s), hair_m)
			strand.rotation.z = 0.06 * float((i * 53) % 7 - 3)
			strand.rotation.x = 0.15
		for sx in [-1.0, 1.0]:
			var side := _box(head, Vector3(0.012 * s, 0.10 * s, 0.008 * s), Vector3(sx * 0.11 * s, 0.12 * s, 0.02 * s), hair_m)
			side.rotation.z = -sx * 0.1
	if bool(spec.get("hood", false)):
		# Hazmat hood: big rounded shell over the top/back of the head,
		# pulled back so the face sits in its opening (in front of the
		# hood surface) instead of buried inside it — the visor band
		# frames the face, the mask covers the lower face.
		_sphere(head, 0.145 * s, Vector3(0, 0.14 * s, -0.05 * s), cloth_mat(spec.get("hood_color", Color(0.85, 0.68, 0.08))), Vector3(1.0, 0.95, 1.0))
	if bool(spec.get("helmet", false)):
		# High cap, not a ball: the brim sits above the brows so the
		# veteran's face stays visible below it. Lifted + slimmed for
		# wrap heads so the texture's own ears stay visible below the
		# brim (the old cap swallowed the narrower wrap head's ears).
		# Side hair + nape boxes are skipped on wrap heads: the wrap
		# photos already show hair at the sides and nape.
		var helm_mat := photo_mat(TEX_HELMET, spec.get("helmet_color", Color(0.3, 0.32, 0.25)).lerp(Color.WHITE, 0.5), 0.5, 0.4)
		_sphere(head, 0.13 * s, Vector3(0, 0.22 * s, -0.03 * s), helm_mat, Vector3(1.0, 0.62, 1.0))
		if not use_wrap:
			var side_m := make_hair_mat(Color(0.18, 0.14, 0.10), "helmet_side")
			for sx in [-1.0, 1.0]:
				_box(head, Vector3(0.012 * s, 0.07 * s, 0.03 * s), Vector3(sx * 0.115 * s, 0.08 * s, 0.0), side_m)
			_box(head, Vector3(0.08 * s, 0.05 * s, 0.012 * s), Vector3(0, 0.06 * s, -0.11 * s), side_m)
	if bool(spec.get("visor", false)):
		if hazmat:
			_build_hazmat_face(head, s, tape_mat, mask_mat, filter_mat, visor_pane_mat, dark_mat, head_skin_mat, eye_col, face_shadow_col, head_ok)
		else:
			_box(head, Vector3(0.16 * s, 0.07 * s, 0.03 * s), Vector3(0, 0.11 * s, 0.11 * s), glow_mat(spec.get("visor_color", Color(0.1, 0.9, 0.4)), 1.2))
	if zombie:
		head.rotation.z = 0.1

	# Arms: shoulder pivot > upper arm > elbow pivot > forearm + hand.
	# Zombies hold their arms out in front.
	var arm_l := _pivot(root, Vector3(-0.27 * s * bulk, shoulder_y, 0))
	var arm_r := _pivot(root, Vector3(0.27 * s * bulk, shoulder_y, 0))
	for arm in [arm_l, arm_r]:
		var upper_mat: Material = shirt_mat if not zombie else bare_skin_mat
		# Real arm shape: tapered upper arm (shoulder wider than
		# elbow), NO bicep bulge sphere — the bulges read as bread
		# rolls. The elbow is a small joint sphere, not a bulge.
		_cyl2(arm, 0.056 * s * bulk, 0.048 * s * bulk, 0.30 * s, Vector3(0, -0.15 * s, 0), upper_mat)
		var elbow := _pivot(arm, Vector3(0, -0.30 * s, 0))
		_sphere(elbow, 0.046 * s * bulk, Vector3(0, 0, 0), upper_mat)
		if zombie:
			# Torn forearm: continuous tapered skin with a short dark
			# torn-flesh band where the flesh is stripped — NO bones
			# or muscle strands showing. The hand hangs from the
			# lower section, unchanged.
			_cyl2(elbow, 0.050 * s * bulk, 0.046 * s * bulk, 0.15 * s, Vector3(0, -0.075 * s, 0), bare_skin_mat)
			_cyl2(elbow, 0.046 * s * bulk, 0.044 * s * bulk, 0.05 * s, Vector3(0, -0.175 * s, 0), mat(Color(0.22, 0.06, 0.04), 0.9, 0.0))
			_cyl2(elbow, 0.044 * s * bulk, 0.040 * s * bulk, 0.08 * s, Vector3(0, -0.24 * s, 0), bare_skin_mat)
			var flap1 := _box(elbow, Vector3(0.02 * s, 0.03 * s, 0.01 * s), Vector3(-0.05 * s, -0.155 * s, 0.03 * s), skin_mat)
			flap1.rotation.z = 0.5
			var flap2 := _box(elbow, Vector3(0.02 * s, 0.03 * s, 0.01 * s), Vector3(0.05 * s, -0.195 * s, 0.03 * s), skin_mat)
			flap2.rotation.z = -0.4
		else:
			# Tapered forearm (elbow wider than wrist), no bulge.
			_cyl2(elbow, 0.050 * s * bulk, 0.040 * s * bulk, 0.28 * s, Vector3(0, -0.14 * s, 0), jacket_mat)
		# Real hand, not a mitten: palm + separate fingers with knuckles
		# + a thumb set apart (Danny's hands photos). Bare hands: palm
		# lines on the palm (his palm-line photo), veins/knuckles on the
		# fingers (his veiny hand-back photo); hazmat gloves: grey
		# rubber fingers, no palm lines.
		var hand_skin := glove_mat if hazmat else photo_mat(TEX_HAND_BACK, skin_col.lerp(Color.WHITE, 0.35), 0.55, 0.0)
		var hand_palm := glove_mat if hazmat else photo_mat(TEX_PALM, skin_col.lerp(Color.WHITE, 0.35), 0.6, 0.0)
		_build_hand(elbow, s, hand_skin, hand_palm, 1.0 if arm == arm_l else -1.0)
		if hazmat:
			# Grey rubber gauntlet cuff + duct-tape patch on the upper arm.
			_cyl(elbow, 0.075 * s * bulk, 0.10 * s, Vector3(0, -0.26 * s, 0), glove_mat)
			_patch(arm, Vector3(0, -0.15 * s, 0.07 * s), 0.25, tape_mat, s)
		if zombie:
			# Torn sleeve: skin shows at the forearm, cloth frays at the cuff.
			_box(elbow, Vector3(0.07 * s, 0.10 * s, 0.02 * s), Vector3(0, -0.12 * s, 0.055 * s), skin_mat)
			var fray := _box(elbow, Vector3(0.02 * s, 0.08 * s, 0.02 * s), Vector3(0.05 * s, -0.20 * s, 0.05 * s), shirt_mat)
			fray.rotation.z = 0.3
	if zombie:
		arm_l.rotation.x = -1.25
		arm_r.rotation.x = -1.25

	# Backpack with pouches + shoulder straps.
	if bool(spec.get("backpack", false)):
		var pack_mat := cloth_mat(spec.get("backpack_color", Color(0.3, 0.28, 0.2)))
		_box(root, Vector3(0.34 * s, 0.46 * s, 0.16 * s), Vector3(0, 1.38 * s, -0.24 * s), pack_mat)
		_box(root, Vector3(0.20 * s, 0.12 * s, 0.12 * s), Vector3(0, 1.64 * s, -0.24 * s), pack_mat)
		_box(root, Vector3(0.08 * s, 0.18 * s, 0.12 * s), Vector3(-0.19 * s, 1.32 * s, -0.24 * s), pack_mat)
		_box(root, Vector3(0.08 * s, 0.18 * s, 0.12 * s), Vector3(0.19 * s, 1.32 * s, -0.24 * s), pack_mat)
		_box(root, Vector3(0.06 * s, 0.42 * s, 0.02 * s), Vector3(-0.14 * s, 1.45 * s, 0.20 * s), dark_mat)
		_box(root, Vector3(0.06 * s, 0.42 * s, 0.02 * s), Vector3(0.14 * s, 1.45 * s, 0.20 * s), dark_mat)

	if hazmat:
		# Coiled ribbed hose: a ring around the neck, a loop hanging on the
		# chest, two runs down to the chest rig. Positions sit on the
		# round torso's front surface.
		_torus(root, 0.15 * s, 0.19 * s, Vector3(0, 1.60 * s, 0), hose_mat, PI / 2.0)
		_torus(root, 0.09 * s, 0.115 * s, Vector3(0.02 * s, 1.32 * s, 0.24 * s), hose_mat, 0.0)
		_cyl(root, 0.018 * s, 0.42 * s, Vector3(-0.13 * s, 1.38 * s, 0.21 * s), hose_mat)
		_cyl(root, 0.018 * s, 0.42 * s, Vector3(0.13 * s, 1.38 * s, 0.21 * s), hose_mat)

	# Held weapon, at shoulder height so the barrel reads over the shoulder
	# from behind in third person. Worn steel: light enough to read in the dark.
	var weapon: String = String(spec.get("weapon", ""))
	var gun: Node3D = null
	if weapon != "":
		gun = Node3D.new()
		gun.position = Vector3(0.30 * s, 1.32 * s, 0.28 * s)
		# Angle the barrel across the body so it reads as a line from
		# directly behind in third person (a barrel pointing straight away
		# from the camera foreshortens to a dot). The bulky improvised gun
		# gets a stronger angle — this also fixes the M2 TPS readability gap.
		gun.rotation.y = -0.35 if weapon == "improvised" else -0.25
		root.add_child(gun)
		_build_weapon(gun, weapon, metal_mat, dark_mat, grip_mat)

	return {
		"root": root, "leg_l": leg_l, "leg_r": leg_r,
		"arm_l": arm_l, "arm_r": arm_r, "head": head,
		"skin_mat": skin_mat, "eye_mat": eye_mat, "gun": gun,
	}

static func _build_weapon(gun: Node3D, kind: String, metal_mat: Material, dark_mat: Material, grip_mat: Material) -> void:
	# Receiver + stock + magazine are common; the barrel differs per weapon.
	# Model forward is +Z: barrel forward, stock behind.
	_box(gun, Vector3(0.09, 0.12, 0.42), Vector3(0, 0, 0), metal_mat)
	_box(gun, Vector3(0.07, 0.10, 0.18), Vector3(0, -0.01, -0.30), grip_mat) # stock
	_box(gun, Vector3(0.05, 0.07, 0.06), Vector3(0, -0.06, 0.0), grip_mat) # grip
	match kind:
		"improvised":
			# The picture's gun: bulky, built from pipes and canisters,
			# with tubes, a red wire and a pressure gauge — a chunky
			# silhouette, not a rifle. Worn steel (low metalness) so it
			# reads as metal in a dark room instead of a black slab.
			var gun_mat := photo_mat(TEX_GUNMETAL, Color(1.2, 1.2, 1.2), 0.4, 0.6)
			var gun_dark := photo_mat(TEX_GUNMETAL, Color(0.55, 0.55, 0.55), 0.45, 0.5)
			_box(gun, Vector3(0.10, 0.13, 0.40), Vector3(0, 0, 0), gun_mat)
			var ib := _cyl(gun, 0.045, 0.40, Vector3(0, 0.02, 0.40), gun_mat)
			ib.rotation.x = PI / 2.0
			var ib2 := _cyl(gun, 0.03, 0.34, Vector3(0.06, 0.02, 0.38), gun_mat)
			ib2.rotation.x = PI / 2.0
			var tank := _cyl(gun, 0.05, 0.24, Vector3(0, -0.13, 0.10), gun_dark)
			tank.rotation.x = PI / 2.0
			var top_tank := _cyl(gun, 0.035, 0.16, Vector3(0, 0.12, 0.05), gun_dark)
			top_tank.rotation.x = PI / 2.0
			var tube1 := _cyl(gun, 0.014, 0.30, Vector3(0.07, -0.02, 0.25), dark_mat)
			tube1.rotation.x = PI / 2.0
			var wire := _cyl(gun, 0.012, 0.26, Vector3(-0.07, -0.05, 0.15), mat(Color(0.6, 0.1, 0.08), 0.7, 0.0))
			wire.rotation.x = PI / 2.0
			var gauge := _cyl(gun, 0.03, 0.02, Vector3(0, 0.10, 0.20), dark_mat)
			var gauge_face := _cyl(gun, 0.025, 0.005, Vector3(0, 0.115, 0.20), mat(Color(0.9, 0.9, 0.85), 0.6, 0.0))
			var brake := _cyl(gun, 0.055, 0.12, Vector3(0, 0.02, 0.60), gun_dark)
			brake.rotation.x = PI / 2.0
			# Wood furniture (Danny's wood-stock references): the
			# improvised gun's buttstock and grip are wood, not cloth.
			# Slightly larger than the common stock/grip so they cover them.
			var wood_mat := photo_mat(TEX_WOOD, Color(1.0, 1.0, 1.0), 0.6, 0.0)
			_box(gun, Vector3(0.075, 0.105, 0.19), Vector3(0, -0.01, -0.30), wood_mat)
			_box(gun, Vector3(0.055, 0.075, 0.065), Vector3(0, -0.06, 0.0), wood_mat)
		"shotgun":
			# Danny's tactical reference: black pump shotgun, pistol-grip
			# stock, vented barrel shroud, ghost-ring sights, extended
			# magazine tube nearly to the muzzle, slotted muzzle brake.
			# NOT a plain tube and NOT the old twin barrels.
			var poly := mat(Color(0.10, 0.10, 0.10), 0.6, 0.05)
			var barrel := _cyl(gun, 0.030, 0.52, Vector3(0, 0.03, 0.42), metal_mat)
			barrel.rotation.x = PI / 2.0
			var tube := _cyl(gun, 0.024, 0.46, Vector3(0, -0.035, 0.40), metal_mat)
			tube.rotation.x = PI / 2.0
			var brake := _cyl(gun, 0.038, 0.09, Vector3(0, 0.03, 0.70), metal_mat)
			brake.rotation.x = PI / 2.0
			# Vented shroud: long forend over the tube with vent slots.
			_box(gun, Vector3(0.10, 0.07, 0.30), Vector3(0, -0.03, 0.36), poly)
			for vz in [0.26, 0.34, 0.42]:
				_box(gun, Vector3(0.104, 0.012, 0.03), Vector3(0, 0.008, vz), dark_mat)
			# Ribbed pump forend around the tube, forward of the receiver.
			_box(gun, Vector3(0.095, 0.075, 0.12), Vector3(0, -0.035, 0.24), poly)
			for pz in [0.20, 0.24, 0.28]:
				_box(gun, Vector3(0.099, 0.079, 0.012), Vector3(0, -0.035, pz), dark_mat)
			# Pistol-grip stock: angled grip + buttstock over the common stock.
			var pgrip := _box(gun, Vector3(0.055, 0.16, 0.08), Vector3(0, -0.10, -0.16), poly)
			pgrip.rotation.x = 0.35
			_box(gun, Vector3(0.075, 0.11, 0.20), Vector3(0, -0.01, -0.31), poly)
			# Ghost-ring rear sight (torus) + front post.
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.014
			tm.outer_radius = 0.024
			ring.mesh = tm
			ring.material_override = metal_mat
			ring.position = Vector3(0, 0.095, -0.14)
			gun.add_child(ring)
			_box(gun, Vector3(0.02, 0.06, 0.02), Vector3(0, 0.09, 0.62), metal_mat)
		"smg":
			# Danny's tan SMG reference: flat-dark-earth finish, curved
			# magazine, vertical foregrip, top rail, short barrel, black
			# grip and furniture. The tan receiver box is slightly larger
			# than the common receiver so it covers it.
			var tan_mat := photo_mat(TEX_GUNMETAL, Color(1.15, 0.95, 0.68), 0.5, 0.55)
			_box(gun, Vector3(0.095, 0.125, 0.44), Vector3(0, 0, 0), tan_mat)
			var b3 := _cyl(gun, 0.022, 0.24, Vector3(0, 0.02, 0.33), metal_mat)
			b3.rotation.x = PI / 2.0
			var cmag := _box(gun, Vector3(0.05, 0.20, 0.09), Vector3(0, -0.14, 0.04), grip_mat)
			cmag.rotation.x = 0.25
			_box(gun, Vector3(0.08, 0.03, 0.20), Vector3(0, 0.075, 0.08), metal_mat) # top rail
			# Red-dot sight on the rail (Danny's red-dot pistol photo
			# shows the sight type; the SMG carries one here).
			_box(gun, Vector3(0.032, 0.035, 0.05), Vector3(0, 0.108, 0.10), dark_mat)
			_box(gun, Vector3(0.012, 0.012, 0.006), Vector3(0, 0.108, 0.072), mat(Color(0.1, 0.0, 0.0), 0.4, 0.0, Color(0, 0, 0), 0.0, Color(1.0, 0.1, 0.05), 2.0))
			var vfg := _box(gun, Vector3(0.04, 0.10, 0.05), Vector3(0, -0.09, 0.22), grip_mat)
			vfg.rotation.x = 0.15
			_box(gun, Vector3(0.06, 0.09, 0.14), Vector3(0, -0.02, -0.30), grip_mat) # skeleton stock
		_:
			# M16-style rifle: carry handle, curved magazine, front sight
			# post, handguard, muzzle brake — Danny's rifle photo.
			var b4 := _cyl(gun, 0.035, 0.44, Vector3(0, 0.02, 0.43), metal_mat)
			b4.rotation.x = PI / 2.0
			var rmag := _box(gun, Vector3(0.06, 0.16, 0.10), Vector3(0, -0.12, 0.02), grip_mat)
			rmag.rotation.x = 0.2
			_box(gun, Vector3(0.04, 0.05, 0.20), Vector3(0, 0.08, 0.05), grip_mat) # carry handle
			_box(gun, Vector3(0.03, 0.09, 0.03), Vector3(0, 0.07, 0.62), metal_mat) # front sight
			_box(gun, Vector3(0.085, 0.09, 0.20), Vector3(0, 0.01, 0.28), grip_mat) # handguard
			var rbrake := _cyl(gun, 0.042, 0.07, Vector3(0, 0.02, 0.66), metal_mat)
			rbrake.rotation.x = PI / 2.0

# First-person viewmodel: cylinder barrel + receiver + grip, per weapon kind.
static func build_gun_view(parent: Node3D, kind: String, accent: Color) -> void:
	for child in parent.get_children():
		child.free()
	var metal_mat := photo_mat(TEX_GUNMETAL, Color(1.2, 1.2, 1.2), 0.4, 0.8)
	var dark_mat := mat(Color(0.12, 0.12, 0.11), 0.8, 0.2)
	var grip_mat := photo_mat(TEX_CLOTH, Color(0.30, 0.30, 0.30), 0.95, 0.0)
	var accent_mat := mat(accent.darkened(0.55), 0.5, 0.1, Color(0.1, 0.08, 0.04), 0.4)
	match kind:
		"improvised":
			# The SAME improvised gun the hero holds in third person:
			# chunky receiver, twin pipes, under-tank, top canister,
			# tube, red wire, gauge, cylinder muzzle brake — mirrored to
			# the FPS forward (-Z). Worn steel, not a black slab.
			var gun_mat := photo_mat(TEX_GUNMETAL, Color(1.2, 1.2, 1.2), 0.4, 0.6)
			var gun_dark := photo_mat(TEX_GUNMETAL, Color(0.55, 0.55, 0.55), 0.45, 0.5)
			_box(parent, Vector3(0.10, 0.13, 0.40), Vector3(0, 0, 0.05), gun_mat)
			var ib := _cyl(parent, 0.045, 0.52, Vector3(0, 0.02, -0.30), gun_mat)
			ib.rotation.x = PI / 2.0
			var ib2 := _cyl(parent, 0.03, 0.40, Vector3(0.06, 0.02, -0.28), gun_mat)
			ib2.rotation.x = PI / 2.0
			var tk := _cyl(parent, 0.05, 0.24, Vector3(0, -0.13, -0.05), gun_dark)
			tk.rotation.x = PI / 2.0
			var top_tank := _cyl(parent, 0.035, 0.16, Vector3(0, 0.12, -0.05), gun_dark)
			top_tank.rotation.x = PI / 2.0
			var tube1 := _cyl(parent, 0.014, 0.30, Vector3(0.07, -0.02, -0.25), dark_mat)
			tube1.rotation.x = PI / 2.0
			var wire := _cyl(parent, 0.009, 0.26, Vector3(-0.055, -0.05, -0.15), mat(Color(0.6, 0.1, 0.08), 0.7, 0.0))
			wire.rotation.x = PI / 2.0
			var gauge := _cyl(parent, 0.03, 0.02, Vector3(0, 0.10, -0.20), dark_mat)
			var gauge_face := _cyl(parent, 0.025, 0.005, Vector3(0, 0.115, -0.20), mat(Color(0.9, 0.9, 0.85), 0.6, 0.0))
			var brake := _cyl(parent, 0.055, 0.12, Vector3(0, 0.02, -0.58), gun_dark)
			brake.rotation.x = PI / 2.0
			_box(parent, Vector3(0.05, 0.12, 0.08), Vector3(0, -0.10, 0.20), grip_mat)
			# Wood grip, matching the TPS improvised gun's wood furniture.
			var wood_mat := photo_mat(TEX_WOOD, Color(1.0, 1.0, 1.0), 0.6, 0.0)
			_box(parent, Vector3(0.055, 0.125, 0.085), Vector3(0, -0.10, 0.20), wood_mat)
		"shotgun":
			# Tactical viewmodel, forward -Z: single barrel, extended
			# tube, vented shroud, ghost-ring sight, pistol grip.
			var poly := mat(Color(0.10, 0.10, 0.10), 0.6, 0.05)
			var sb := _cyl(parent, 0.032, 0.60, Vector3(0, 0.01, -0.30), metal_mat)
			sb.rotation.x = PI / 2.0
			var st := _cyl(parent, 0.026, 0.52, Vector3(0, -0.04, -0.28), metal_mat)
			st.rotation.x = PI / 2.0
			_box(parent, Vector3(0.09, 0.10, 0.30), Vector3(0, 0, 0.05), metal_mat)
			_box(parent, Vector3(0.10, 0.07, 0.26), Vector3(0, -0.04, -0.28), poly)
			for vz in [-0.20, -0.28, -0.36]:
				_box(parent, Vector3(0.104, 0.012, 0.03), Vector3(0, 0.005, vz), dark_mat)
			var sring := MeshInstance3D.new()
			var stm := TorusMesh.new()
			stm.inner_radius = 0.014
			stm.outer_radius = 0.024
			sring.mesh = stm
			sring.material_override = metal_mat
			sring.position = Vector3(0, 0.075, 0.12)
			parent.add_child(sring)
			var spg := _box(parent, Vector3(0.055, 0.14, 0.08), Vector3(0, -0.09, 0.16), poly)
			spg.rotation.x = -0.35
		"smg":
			# Tan viewmodel: tan receiver over the common shape, curved
			# mag, vertical foregrip, top rail.
			var tan_mat := photo_mat(TEX_GUNMETAL, Color(1.15, 0.95, 0.68), 0.5, 0.55)
			var mb := _cyl(parent, 0.025, 0.34, Vector3(0, 0.01, -0.18), metal_mat)
			mb.rotation.x = PI / 2.0
			_box(parent, Vector3(0.085, 0.105, 0.36), Vector3(0, 0, 0.05), tan_mat)
			var cm := _box(parent, Vector3(0.05, 0.18, 0.09), Vector3(0, -0.13, 0.02), grip_mat)
			cm.rotation.x = -0.25
			_box(parent, Vector3(0.07, 0.03, 0.18), Vector3(0, 0.065, -0.02), metal_mat) # top rail
			_box(parent, Vector3(0.032, 0.035, 0.05), Vector3(0, 0.098, -0.02), dark_mat) # red-dot sight
			_box(parent, Vector3(0.012, 0.012, 0.006), Vector3(0, 0.098, 0.008), mat(Color(0.1, 0.0, 0.0), 0.4, 0.0, Color(0, 0, 0), 0.0, Color(1.0, 0.1, 0.05), 2.0))
			var vg := _box(parent, Vector3(0.04, 0.10, 0.05), Vector3(0, -0.09, -0.16), grip_mat)
			vg.rotation.x = -0.15
		_:
			var rb := _cyl(parent, 0.028, 0.58, Vector3(0, 0.01, -0.30), metal_mat)
			rb.rotation.x = PI / 2.0
			_box(parent, Vector3(0.08, 0.10, 0.40), Vector3(0, 0, 0.05), metal_mat)
			var rcm := _box(parent, Vector3(0.05, 0.16, 0.09), Vector3(0, -0.12, 0.02), grip_mat)
			rcm.rotation.x = -0.2
			_box(parent, Vector3(0.04, 0.05, 0.18), Vector3(0, 0.07, 0.10), grip_mat) # carry handle
			_box(parent, Vector3(0.085, 0.09, 0.20), Vector3(0, 0.01, -0.22), grip_mat) # handguard
			_box(parent, Vector3(0.03, 0.08, 0.03), Vector3(0, 0.06, -0.55), metal_mat) # front sight
	_box(parent, Vector3(0.09, 0.06, 0.16), Vector3(0, -0.05, 0.18), accent_mat)
