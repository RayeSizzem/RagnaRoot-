extends Node3D
## A named hero unit. Stationed freely (even on roads); patrols around its post
## and strikes any monster that wanders within aggro range. Race sets the stats.
## (v1: heroes deal damage but aren't yet attacked by monsters.)

var species_key := "human"
var hero_name := "Hero"

const SPECIES := {
	"human": {"label": "Human Knight", "hp": 140, "dmg": 13, "range": 3.0, "interval": 0.7, "speed": 7.0, "aggro": 16.0, "color": Color(0.30, 0.50, 0.92), "size": 1.0},
	"elf":   {"label": "Elven Ranger", "hp": 90, "dmg": 17, "range": 11.0, "interval": 0.6, "speed": 8.0, "aggro": 22.0, "color": Color(0.32, 0.82, 0.45), "size": 0.9},
	"dwarf": {"label": "Dwarven Warden", "hp": 210, "dmg": 22, "range": 2.6, "interval": 1.0, "speed": 5.0, "aggro": 13.0, "color": Color(0.85, 0.55, 0.28), "size": 1.15},
}

const NAMES := {
	"human": ["Aldric", "Mira", "Cedric", "Rowan", "Elara"],
	"elf":   ["Faelar", "Sylwen", "Aerith", "Thalindra", "Naeris"],
	"dwarf": ["Borin", "Dagna", "Thrain", "Hilda", "Grumli"],
}

var _max_hp := 100
var _hp := 100
var _dmg := 10
var _range := 3.0
var _interval := 0.7
var _speed := 6.0
var _aggro := 15.0
var _post := Vector3.ZERO
var _cd := 0.0
var _body: MeshInstance3D


func _enter_tree() -> void:
	add_to_group("hero")


func _ready() -> void:
	var d: Dictionary = SPECIES.get(species_key, SPECIES["human"])
	_max_hp = d["hp"]
	_hp = _max_hp
	_dmg = d["dmg"]
	_range = d["range"]
	_interval = d["interval"]
	_speed = d["speed"]
	_aggro = d["aggro"]
	hero_name = _pick_name(species_key)
	_build_body(d["color"], d["size"])
	_build_label()


func set_post(p: Vector3) -> void:
	_post = p


func _pick_name(sp: String) -> String:
	var pool: Array = NAMES.get(sp, ["Hero"])
	return pool[randi() % pool.size()]


func _build_body(color: Color, size: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.4
	_body = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25 * size
	cyl.bottom_radius = 0.35 * size
	cyl.height = 1.2 * size
	_body.mesh = cyl
	_body.position.y = 0.6 * size
	_body.material_override = mat
	add_child(_body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.28 * size
	sph.height = 0.56 * size
	head.mesh = sph
	head.position.y = 1.35 * size
	head.material_override = mat
	add_child(head)


func _build_label() -> void:
	var lbl := Label3D.new()
	lbl.text = hero_name
	lbl.position.y = 2.0
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 48
	lbl.outline_size = 8
	add_child(lbl)


func _process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	var target = _nearest_enemy()
	if target != null:
		var d: float = global_position.distance_to(target.global_position)
		if d > _range:
			_move_toward(target.global_position, delta)
		elif _cd <= 0.0:
			if target.has_method("take_damage"):
				target.take_damage(_dmg)
			_cd = _interval
			_swing()
	elif global_position.distance_to(_post) > 0.5:
		_move_toward(_post, delta)


func _nearest_enemy():
	var best = null
	var best_d := 1.0e20
	var leash := _aggro * _aggro
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if _post.distance_squared_to(e.global_position) > leash:
			continue
		var cd2: float = global_position.distance_squared_to(e.global_position)
		if cd2 < best_d:
			best_d = cd2
			best = e
	return best


func _move_toward(pos: Vector3, delta: float) -> void:
	var to := pos - global_position
	to.y = 0.0
	if to.length() > 0.05:
		global_position += to.normalized() * _speed * delta
		rotation.y = atan2(to.x, to.z)


func _swing() -> void:
	if _body:
		_body.scale = Vector3(1.3, 0.85, 1.3)
		var t := create_tween()
		t.tween_property(_body, "scale", Vector3.ONE, 0.15)


func take_damage(amount: int) -> void:
	_hp -= amount
	if _hp <= 0:
		queue_free()


func get_range() -> float:
	return _aggro


func get_info() -> String:
	return "%s\n(dmg %d, reach %.0f, range %.0f)" % [get_display_name(), _dmg, _range, _aggro]


func get_display_name() -> String:
	var d: Dictionary = SPECIES.get(species_key, SPECIES["human"])
	return "%s the %s" % [hero_name, d["label"]]
