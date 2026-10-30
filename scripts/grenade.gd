class_name Grenade
extends Node3D

# Thrown toxic grenade: arcs with gravity, pops a lingering acid cloud on
# landing or after its fuse. Manual projectile — no physics body needed.

const FUSE := 1.6

var velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _done: bool = false
var _sfx: Sfx
var _kind: String = "toxic" # "toxic" (acid cloud) | "frag" (AoE blast)

func setup(vel: Vector3, sfx: Sfx, kind: String = "toxic") -> void:
	velocity = vel
	_sfx = sfx
	_kind = kind

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	if _kind == "frag":
		mat.albedo_color = Color(0.25, 0.3, 0.2) # olive drab frag
	else:
		mat.albedo_color = Color(0.85, 0.7, 0.1) # acid-yellow toxic
	mat.roughness = 0.4
	mat.metallic = 0.3
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mi.mesh = sphere
	mi.material_override = mat
	add_child(mi)

func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	velocity.y -= 20.0 * delta
	position += velocity * delta
	if position.y <= 0.2 or _age >= FUSE:
		_detonate()

func _detonate() -> void:
	_done = true
	if _kind == "frag":
		# Instant blast: falloff damage to Bombies in 4.5 m, flash + boom.
		for body in get_tree().get_nodes_in_group("bombie"):
			if body is Bombie and not (body as Bombie)._dead:
				var d := (body as Bombie).global_position.distance_to(global_position)
				if d <= 4.5:
					(body as Bombie).take_damage(120.0 * (1.0 - d / 6.0))
		var flash := OmniLight3D.new()
		flash.light_color = Color(1.0, 0.6, 0.2)
		flash.light_energy = 7.0
		flash.omni_range = 12.0
		flash.position = global_position + Vector3(0, 0.6, 0)
		get_parent().add_child(flash)
		var tw := flash.create_tween()
		tw.tween_property(flash, "light_energy", 0.0, 0.4)
		tw.tween_callback(flash.queue_free)
		if _sfx != null:
			_sfx.play("boom", -4.0)
		queue_free()
		return
	var cloud := ToxicCloud.new()
	get_parent().add_child(cloud)
	cloud.global_position = Vector3(global_position.x, 0.15, global_position.z)
	if _sfx != null:
		_sfx.play("boom", -6.0)
	queue_free()
