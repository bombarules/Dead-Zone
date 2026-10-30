class_name DeadZoneHUD
extends CanvasLayer

# HUD built in code: HP bar, round + enemies, ammo + gear counts, crosshair,
# announcements, damage vignette, win / lose overlays.

var _hp_fill: ColorRect
var _hp_label: Label
var _round_label: Label
var _location_label: Label
var _squad_label: Label
var _location_name := "FLOODED GARAGE"
var _round_word := "ROUND"
var _ammo_label: Label
var _gear_label: Label
var _msg_label: Label
var _msg_timer: float = 0.0
var _vignette: ColorRect
var _overlay: Panel
var _overlay_title: Label
var _overlay_sub: Label
var _crosshair: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	var font_size := 20
	# --- HP bar (top-left) ---
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.position = Vector2(16, 16)
	hp_bg.size = Vector2(260, 26)
	add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.75, 0.2, 0.15)
	_hp_fill.position = Vector2(18, 18)
	_hp_fill.size = Vector2(256, 22)
	add_child(_hp_fill)
	_hp_label = _label("HP 100", Vector2(20, 44), 18, Color(1, 1, 1))
	# --- Round (top-center) ---
	_round_label = _label("ROUND 1 / 3", Vector2(0, 14), 26, Color(1, 0.8, 0.3))
	_round_label.position = Vector2(640 - 110, 14)
	_round_label.size = Vector2(220, 34)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_label = _label("FLOODED GARAGE", Vector2(0, 48), 16, Color(0.85, 0.8, 0.7))
	_location_label.position = Vector2(640 - 110, 48)
	_location_label.size = Vector2(220, 24)
	_location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# --- Ammo + gear (top-right) ---
	_ammo_label = _label("30 / 30", Vector2(0, 14), 30, Color(1, 1, 1))
	_ammo_label.position = Vector2(1020, 14)
	_ammo_label.size = Vector2(244, 40)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gear_label = _label("", Vector2(0, 54), 18, Color(0.8, 0.85, 0.8))
	_gear_label.position = Vector2(960, 54)
	_gear_label.size = Vector2(304, 26)
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# --- Crosshair (center) ---
	_crosshair = Control.new()
	_crosshair.position = Vector2(640, 360)
	_crosshair.size = Vector2(2, 2)
	add_child(_crosshair)
	for rect in [
		[Vector2(-1, -14), Vector2(2, 10)], [Vector2(-1, 4), Vector2(2, 10)],
		[Vector2(-14, -1), Vector2(10, 2)], [Vector2(4, -1), Vector2(10, 2)],
	]:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.9)
		bar.position = rect[0]
		bar.size = rect[1]
		_crosshair.add_child(bar)
	var dot := ColorRect.new()
	dot.color = Color(1, 0.85, 0.2)
	dot.position = Vector2(-2, -2)
	dot.size = Vector2(4, 4)
	_crosshair.add_child(dot)
	# --- Message (bottom-center) ---
	_msg_label = _label("", Vector2(0, 640), 22, Color(1, 0.85, 0.3))
	_msg_label.position = Vector2(340, 640)
	_msg_label.size = Vector2(600, 30)
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# --- Squad status (bottom-left) ---
	_squad_label = _label("SQUAD  [TAB]\n> HAZMAT  100/100", Vector2(16, 596), 17, Color(0.9, 0.9, 0.85))
	_squad_label.size = Vector2(240, 110)
	# --- Damage vignette ---
	_vignette = ColorRect.new()
	_vignette.color = Color(0.8, 0.05, 0.05, 0.0)
	_vignette.position = Vector2(0, 0)
	_vignette.size = Vector2(1280, 720)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	# --- Win / lose overlay ---
	_overlay = Panel.new()
	_overlay.position = Vector2(340, 220)
	_overlay.size = Vector2(600, 260)
	_overlay.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.92)
	style.border_color = Color(0.9, 0.7, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_overlay.add_theme_stylebox_override("panel", style)
	add_child(_overlay)
	_overlay_title = _label("", Vector2(0, 30), 44, Color(1, 0.8, 0.3), _overlay)
	_overlay_title.size = Vector2(600, 60)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_sub = _label("", Vector2(0, 110), 20, Color(0.9, 0.9, 0.9), _overlay)
	_overlay_sub.size = Vector2(600, 100)
	_overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# NOTE: positions assume a 1280x720 viewport (project.godot). The stretch
	# mode scales the whole UI, so these pixel positions stay proportional.

func _label(text: String, pos: Vector2, size: int, color: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	(parent if parent != null else self).add_child(l)
	return l

func _process(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_msg_label.text = ""
	if _vignette.color.a > 0.0:
		var c := _vignette.color
		c.a = maxf(0.0, c.a - delta * 1.6)
		_vignette.color = c

func set_hp(hp: float, max_hp: float) -> void:
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	_hp_fill.size.x = 256.0 * frac
	_hp_fill.color = Color(0.75, 0.2, 0.15) if frac > 0.3 else Color(0.9, 0.1, 0.05)
	_hp_label.text = "HP %d" % int(hp)

func set_location(location_name: String, round_word: String = "ROUND") -> void:
	_location_name = location_name
	_round_word = round_word
	if _location_label != null:
		_location_label.text = location_name

func set_round(round_num: int, total: int, enemies_left: int) -> void:
	_round_label.text = "%s %d / %d   —   BOMBIES LEFT: %d" % [_round_word, round_num, total, enemies_left]

func set_squad(members: Array) -> void:
	if _squad_label == null:
		return
	var lines := ["SQUAD  [TAB]"]
	for m in members:
		var d: Dictionary = m
		if bool(d["down"]):
			lines.append("X %s  DOWN" % String(d["name"]))
		else:
			var mark := "> " if bool(d["controlled"]) else "    "
			lines.append("%s%s  %d/%d" % [mark, String(d["name"]), int(d["hp"]), int(d["max_hp"])])
	_squad_label.text = "\n".join(lines)

func set_ammo(mag: int, mag_size: int, grenades: int, mines: int, traps: int) -> void:
	_ammo_label.text = "%d / %d" % [mag, mag_size]
	_gear_label.text = "GND %d   ·   MIN %d   ·   ACID %d" % [grenades, mines, traps]

func show_message(text: String, hold: float = 2.5) -> void:
	_msg_label.text = text
	_msg_timer = hold

func damage_flash() -> void:
	var c := _vignette.color
	c.a = 0.45
	_vignette.color = c

func show_win(location: String = "garage") -> void:
	_overlay_title.text = "DEAD ZONE CLEARED"
	_overlay_title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	if location == "factory":
		_overlay_sub.text = "All three factory rooms cleared. The squad pushed through — the exit is open.\nPress R to run it back."
	else:
		_overlay_sub.text = "Round 3 survived. The exit stairwell is open — the garage is yours.\nPress R to run it back."
	_overlay.visible = true
	_crosshair.visible = false

func show_lose() -> void:
	_overlay_title.text = "SQUAD DOWN"
	_overlay_title.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_overlay_sub.text = "The whole squad is down and the horde keeps coming.\nPress R to try again."
	_overlay.visible = true
	_crosshair.visible = false
