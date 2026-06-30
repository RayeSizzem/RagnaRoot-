extends Node3D
## A creature of the Dark. Follows its lane to the Heartroot, takes tower fire,
## and can be afflicted by status effects (slow / burn / poison / root / knockback).
## Its kind (set before _ready) drives hp, speed, damage, size and colour; tougher
## kinds are summoned as the cycles deepen.

@export var speed: float = 6.0
const MOVE_SCALE := 0.30  # all monsters move at 30% of their table speed (70% slower)
@export var max_hp: int = 30
@export var damage_to_root: int = 5

## Set by the tide before the node enters the tree.
var kind: String = "crawler"
var hp_scale: float = 1.0

# Drops: meaningful early, fading as the tree (stage) grows.
const DROP_TIMBER_BASE := 6
const DROP_STONE_BASE := 4
const DROP_FALLOFF := 1
const DROP_MIN := 1
const ESSENCE_PER_KILL := 1

var _hp: int
var _tree
var _wm
var _path: Array = []
var _idx: int = 0

var _body: MeshInstance3D
var _mat: StandardMaterial3D
var _base_color := Color(0.8, 0.15, 0.15)
var _size := 1.0

var _bar_root: Node3D
var _fill_pivot: Node3D
var _bar_width := 1.0

# --- status ---
var _slow_factor := 1.0
var _slow_t := 0.0
var _root_t := 0.0
var _dot_dps := 0.0
var _dot_t := 0.0
var _dot_accum := 0.0
var _dead := false

# --- traits (counter layer) ---
const ARMORED_DIRECT_MULT := 0.5   # armored take half from direct hits; DoT ignores it
const SHIELD_HITS := 3             # direct hits absorbed before HP (rapid/chain strip fast)
const SWIFT_VULN_MULT := 1.5       # swift take +50% while slowed or rooted
const REGEN_FRAC := 0.04           # regen 4% max HP per second...
const REGEN_DELAY := 1.5           # ...after this long without taking damage
var _armored := false
var _swift := false
var _flying := false
var _shield := 0
var _regen := 0.0
var _since_hit := 999.0
var _regen_accum := 0.0
var _shell: MeshInstance3D


func _enter_tree() -> void:
	add_to_group("enemy")


## name, hp, speed, dmg, size, colour for each creature of the Dark.
func _kind_table() -> Dictionary:
	return {
		"mote":      {"hp": 18,  "spd": 7.0,  "dmg": 3,  "size": 0.7, "col": Color(0.55, 0.12, 0.12), "tr": []},
		"crawler":   {"hp": 30,  "spd": 6.0,  "dmg": 5,  "size": 1.0, "col": Color(0.8, 0.15, 0.15), "tr": []},
		"husk":      {"hp": 60,  "spd": 4.0,  "dmg": 6,  "size": 1.25, "col": Color(0.4, 0.28, 0.22), "tr": ["armored"]},
		"sprinter":  {"hp": 22,  "spd": 10.0, "dmg": 4,  "size": 0.85, "col": Color(0.95, 0.55, 0.2), "tr": ["swift"]},
		"brute":     {"hp": 90,  "spd": 4.5,  "dmg": 10, "size": 1.4, "col": Color(0.5, 0.1, 0.3), "tr": ["armored"]},
		"shade":     {"hp": 45,  "spd": 6.5,  "dmg": 6,  "size": 1.0, "col": Color(0.22, 0.2, 0.3), "tr": ["flying"]},
		"gnasher":   {"hp": 70,  "spd": 7.0,  "dmg": 8,  "size": 1.1, "col": Color(0.7, 0.35, 0.1), "tr": ["swift"]},
		"ravager":   {"hp": 80,  "spd": 5.5,  "dmg": 14, "size": 1.2, "col": Color(0.75, 0.1, 0.1), "tr": ["shielded"]},
		"behemoth":  {"hp": 160, "spd": 3.5,  "dmg": 12, "size": 1.7, "col": Color(0.3, 0.22, 0.35), "tr": ["armored", "regenerating"]},
		"wraith":    {"hp": 60,  "spd": 9.0,  "dmg": 8,  "size": 1.0, "col": Color(0.45, 0.5, 0.7), "tr": ["swift", "flying"]},
		"dread":     {"hp": 140, "spd": 5.0,  "dmg": 16, "size": 1.4, "col": Color(0.5, 0.05, 0.2), "tr": ["armored", "shielded"]},
		"nightmare": {"hp": 300, "spd": 4.0,  "dmg": 25, "size": 2.1, "col": Color(0.12, 0.02, 0.18), "tr": ["armored", "shielded", "regenerating"]},
	}


func _ready() -> void:
	var t: Dictionary = _kind_table()
	var d: Dictionary = t.get(kind, t["crawler"])
	max_hp = int(round(float(d["hp"]) * hp_scale))
	speed = float(d["spd"]) * MOVE_SCALE
	damage_to_root = d["dmg"]
	_size = d["size"]
	_base_color = d["col"]
	_hp = max_hp
	var traits: Array = d.get("tr", [])
	_armored = "armored" in traits
	_swift = "swift" in traits
	_flying = "flying" in traits
	if "shielded" in traits:
		_shield = SHIELD_HITS
	if "regenerating" in traits:
		_regen = REGEN_FRAC * float(max_hp)
	_bar_width = clampf(_size, 0.8, 2.0)
	_tree = get_tree().get_first_node_in_group("world_tree")
	_wm = get_tree().get_first_node_in_group("world_manager")
	_build_body()
	_apply_trait_visuals()
	_build_healthbar()
	# Start fully hidden. tide_manager sets global_position AFTER add_child, so the
	# spawn frame would otherwise render the body at full alpha (a flash through the
	# fog) before the first _process runs the fade. Begin invisible; the fog fade
	# brings it in once it's actually on lit ground.
	if _mat:
		var c: Color = _mat.albedo_color
		c.a = 0.0
		_mat.albedo_color = c
	if _body:
		_body.visible = false
	if _bar_root:
		_bar_root.visible = false
	if _shell and is_instance_valid(_shell):
		_shell.visible = false


## Telegraph traits so the player can read the threat: armored plating, a shield
## shell, a regen glow, and a hovering offset for fliers.
func _apply_trait_visuals() -> void:
	if _flying and _body:
		_body.position.y = 0.5 * _size + 1.0   # hover above the ground
	if _mat:
		if _armored:
			_mat.metallic = 0.85
			_mat.roughness = 0.35
			_mat.albedo_color = _base_color.darkened(0.15)
		if _regen > 0.0:
			_mat.emission_enabled = true
			_mat.emission = Color(0.2, 0.9, 0.3)
			_mat.emission_energy_multiplier = 0.4
	if _shield > 0:
		_shell = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.7 * _size
		sm.height = 1.4 * _size
		_shell.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.7, 1.0, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shell.material_override = mat
		_shell.position.y = (0.5 * _size) + (1.0 if _flying else 0.0)
		add_child(_shell)


func set_path(points: Array) -> void:
	_path = points
	_idx = 0


func _build_body() -> void:
	_body = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7 * _size, 1.0 * _size, 0.7 * _size)
	_body.mesh = bm
	_body.position.y = 0.5 * _size
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _base_color
	# Draw above the fog sheets and allow per-frame alpha so the enemy fades exactly
	# with the fog at its feet instead of being darkened by neighbouring fog sheets.
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.render_priority = 6
	_body.material_override = _mat
	add_child(_body)


func _build_healthbar() -> void:
	_bar_root = Node3D.new()
	_bar_root.position.y = 1.1 * _size + 0.4
	add_child(_bar_root)
	_bar_root.add_child(_make_quad(Color(0.08, 0.0, 0.0), _bar_width, 0.16, 0.0))
	_fill_pivot = Node3D.new()
	_fill_pivot.position.x = -_bar_width / 2.0
	_bar_root.add_child(_fill_pivot)
	var fill := _make_quad(Color(0.25, 0.9, 0.35), _bar_width, 0.14, 0.01)
	fill.position.x = _bar_width / 2.0
	_fill_pivot.add_child(fill)


func _make_quad(color: Color, w: float, h: float, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	mi.position.z = z
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	return mi


func _process(delta: float) -> void:
	if _dead:
		return
	_tick_status(delta)
	if _dead:
		return
	var blocked := _root_t > 0.0
	if not blocked:
		var target_pos: Vector3 = Vector3.ZERO
		if _path.size() > 0 and _idx < _path.size():
			target_pos = _path[_idx]
		var to := target_pos - global_position
		to.y = 0.0
		var dist := to.length()
		if dist <= 0.3:
			_idx += 1
			if _idx >= _path.size():
				if _tree:
					_tree.damage_heartroot(damage_to_root)
				queue_free()
				return
		else:
			var spd: float = speed * _slow_factor
			global_position += to.normalized() * spd * delta
	_update_visibility()
	_face_bar_to_camera()


func _tick_status(delta: float) -> void:
	if _slow_t > 0.0:
		_slow_t -= delta
		if _slow_t <= 0.0:
			_slow_factor = 1.0
	if _root_t > 0.0:
		_root_t -= delta
	if _dot_t > 0.0:
		_dot_t -= delta
		_dot_accum += _dot_dps * delta
		if _dot_accum >= 1.0:
			var d: int = int(_dot_accum)
			_dot_accum -= float(d)
			take_damage(d, true)   # burn/poison is true damage: ignores armor & shield
	if _regen > 0.0 and not _dead:
		_since_hit += delta
		if _since_hit >= REGEN_DELAY and _hp < max_hp:
			_regen_accum += _regen * delta
			if _regen_accum >= 1.0:
				var h: int = int(_regen_accum)
				_regen_accum -= float(h)
				_hp = mini(_hp + h, max_hp)
				_update_bar()


# --- status application (called by towers / projectiles) ---
func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = minf(_slow_factor, factor)
	_slow_t = maxf(_slow_t, duration)


func apply_root(duration: float) -> void:
	_root_t = maxf(_root_t, duration)


func apply_dot(dps: float, duration: float) -> void:
	_dot_dps = maxf(_dot_dps, dps)
	_dot_t = maxf(_dot_t, duration)


func apply_knockback(dist: float) -> void:
	var out := global_position
	out.y = 0.0
	if out.length() > 0.05:
		global_position += out.normalized() * dist


func _update_visibility() -> void:
	if _wm == null:
		return
	# Fade with the actual fog coverage, but keep the enemy fully hidden until it is
	# clearly past the fog line — the spawn sits only a few cells into the dark, where
	# raw coverage is small-but-nonzero, which otherwise showed a faint flash on spawn.
	var clear: float = _wm.fog_clear_at(global_position)
	var a: float = smoothstep(0.55, 0.9, clear)
	if _mat:
		var c: Color = _mat.albedo_color
		c.a = a
		_mat.albedo_color = c
	if _body:
		_body.visible = a > 0.01
	if _shell and is_instance_valid(_shell):
		_shell.visible = a > 0.4
	if _bar_root:
		_bar_root.visible = a > 0.6


func _face_bar_to_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and _bar_root:
		var dir := cam.global_position - _bar_root.global_position
		_bar_root.rotation.y = atan2(dir.x, dir.z)


func take_damage(amount: int, true_damage: bool = false) -> void:
	if _dead:
		return
	_since_hit = 0.0
	if not true_damage:
		# Shield: each direct hit strips one charge and is fully absorbed. Rapid-fire
		# and chain towers (many hits) break it fast; one big hit only strips one.
		if _shield > 0:
			_shield -= 1
			if _shield <= 0 and is_instance_valid(_shell):
				_shell.queue_free()
				_shell = null
			_flash()
			return
		# Armor halves direct damage (DoT bypasses this entirely).
		if _armored:
			amount = int(ceil(float(amount) * ARMORED_DIRECT_MULT))
		# Swift creatures are vulnerable while slowed or rooted.
		if _swift and (_slow_factor < 0.999 or _root_t > 0.0):
			amount = int(round(float(amount) * SWIFT_VULN_MULT))
	_hp -= amount
	_update_bar()
	_flash()
	if _hp <= 0:
		_dead = true
		_drop()
		queue_free()


func _update_bar() -> void:
	var ratio: float = clampf(float(_hp) / float(max_hp), 0.0, 1.0)
	if _fill_pivot:
		_fill_pivot.scale.x = ratio


func is_flying() -> bool:
	return _flying


func _flash() -> void:
	if _mat:
		_mat.albedo_color = Color(1, 1, 1)
		var t := create_tween()
		t.tween_property(_mat, "albedo_color", _base_color, 0.12)
	if _body:
		_body.scale = Vector3.ONE * 1.25
		var t2 := create_tween()
		t2.tween_property(_body, "scale", Vector3.ONE, 0.12)


func _drop() -> void:
	var bank = get_tree().get_first_node_in_group("resource_bank")
	if bank == null:
		return
	var stage: int = _tree.stage if (_tree and is_instance_valid(_tree)) else 0
	var t: int = maxi(DROP_TIMBER_BASE - stage * DROP_FALLOFF, DROP_MIN)
	var s: int = maxi(DROP_STONE_BASE - stage * DROP_FALLOFF, DROP_MIN)
	bank.add("timber", t)
	bank.add("stone", s)
	bank.add("essence", ESSENCE_PER_KILL)
