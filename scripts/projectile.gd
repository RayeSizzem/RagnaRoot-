extends Node3D
## A shot fired by a tower. Homes onto its target, deals damage on impact, and
## applies the tower's on-hit effects. With a splash radius it hits everything
## near the impact point; otherwise just the target. Fizzles if the target dies.

@export var speed: float = 22.0
var damage: int = 8
var _target: Node
var _effects: Dictionary = {}
var _splash: float = 0.0
var _color := Color(1.0, 0.85, 0.4)
var _last_pos := Vector3.ZERO


func setup(target: Node, dmg: int, effects: Dictionary = {}, splash: float = 0.0, color: Color = Color(1.0, 0.85, 0.4)) -> void:
	_target = target
	damage = dmg
	_effects = effects
	_splash = splash
	_color = color


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.emission_enabled = true
	mat.emission = _color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return
	var aim: Vector3 = _target.global_position + Vector3(0, 0.5, 0)
	_last_pos = global_position
	var to := aim - global_position
	var dist := to.length()
	var step := speed * delta
	if dist <= step or dist < 0.25:
		_impact(aim)
		queue_free()
		return
	global_position += to / dist * step


func _impact(at: Vector3) -> void:
	if _splash > 0.0:
		var r2 := _splash * _splash
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.global_position.distance_squared_to(at) <= r2:
				_hit(e)
	elif is_instance_valid(_target):
		_hit(_target)


func _hit(e: Node) -> void:
	if e.has_method("take_damage"):
		e.take_damage(damage)
	if _effects.has("slow") and e.has_method("apply_slow"):
		var s: Dictionary = _effects["slow"]
		e.apply_slow(s["f"], s["d"])
	if _effects.has("dot") and e.has_method("apply_dot"):
		var d: Dictionary = _effects["dot"]
		e.apply_dot(d["dps"], d["d"])
	if _effects.has("root") and e.has_method("apply_root"):
		e.apply_root(_effects["root"])
	if _effects.has("knockback") and e.has_method("apply_knockback"):
		e.apply_knockback(_effects["knockback"])
