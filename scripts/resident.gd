extends Node3D
## A settler. Lives in a housing hut (or homeless, meandering near the tree).
## Commutes to its assigned worksite during the day and home at night — but only
## once "released" (staggered by the day/night controller). Species sets affinity.

const AFFINITY := {
	"human": {"timber": 1.0, "stone": 1.0},
	"elf":   {"timber": 1.4, "stone": 0.7, "soft_wood": 1.4, "hard_wood": 0.9},
	"dwarf": {"timber": 0.7, "stone": 1.4, "hard_wood": 1.3, "gold": 1.3, "ruby": 1.3, "diamond": 1.3},
}
const COLORS := {
	"human": Color(0.30, 0.50, 0.92),
	"elf":   Color(0.32, 0.82, 0.45),
	"dwarf": Color(0.85, 0.55, 0.28),
}

var species_key := "human"
# --- identity (Phase A) ---
var gender := "m"
var trait_key := "worker"
var trait_level := 1
var trait_xp := 0.0
var faith := 1
var faith_progress := 0.0
var display_name := "Settler"
var days_homeless := 0
var _temple_consecrated := false   # set by the colony once a Temple exists (Phase C)
var _pip_mat: StandardMaterial3D
var _home
var _job
var _gs
var _speed := 4.0
var _offset := Vector3.ZERO
var _idle_anchor := Vector3.ZERO
var _mat: StandardMaterial3D
var _hold := 0.0
var _meander_target := Vector3.ZERO
var _meander_timer := 0.0
var _tree


func _enter_tree() -> void:
	add_to_group("resident")


func setup(sp: String, home) -> void:
	species_key = sp
	_home = home


func _ready() -> void:
	_gs = get_tree().get_first_node_in_group("game_state")
	_tree = get_tree().get_first_node_in_group("world_tree")
	_offset = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	_meander_target = _idle_anchor
	_build()


func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = COLORS.get(species_key, Color.WHITE)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.22
	cyl.height = 0.7
	mi.mesh = cyl
	mi.position.y = 0.35
	mi.material_override = _mat
	add_child(mi)
	# small trait pip on top (recoloured once identity is assigned)
	var pip := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.1
	pm.height = 0.2
	pip.mesh = pm
	pip.position.y = 0.82
	_pip_mat = StandardMaterial3D.new()
	_pip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pip_mat.albedo_color = Folk.TRAIT_COLOR.get(trait_key, Color.WHITE)
	pip.material_override = _pip_mat
	add_child(pip)


## Assign gender / trait / starting faith (called right after instantiation).
func init_identity(g: String, tr: String, f: int, nm: String = "") -> void:
	gender = g
	trait_key = tr
	faith = clampi(f, 1, Folk.MAX_FAITH)
	display_name = nm if nm != "" else Folk.name_for(g)
	if _pip_mat:
		_pip_mat.albedo_color = Folk.TRAIT_COLOR.get(trait_key, Color.WHITE)


func set_temple_consecrated(on: bool) -> void:
	_temple_consecrated = on


func _faith_cap() -> int:
	if trait_key == "priestess" or _temple_consecrated:
		return Folk.MAX_FAITH
	return Folk.FAITH_CAP_NO_TEMPLE


## On-trait if posted to the building group this trait earns its bonus in.
func is_on_trait(building) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	var grp: String = Folk.TRAIT_WORKSITE.get(trait_key, "")
	return grp != "" and building.is_in_group(grp)


## Full output multiplier when working ON-TRAIT: species affinity x trait level x faith.
func yield_mult(rtype: String) -> float:
	return affinity(rtype) * Folk.trait_mult(trait_level) * Folk.faith_prod(faith)


func xp_rate() -> float:
	return Folk.faith_xprate(faith)


## Grant trait XP for one on-trait work tick. Trait-5 is locked behind faith-5, so
## progress parks at level 4 until faith maxes (which needs a consecrated Temple).
func gain_trait_xp(base: float) -> void:
	if trait_level >= Folk.MAX_TRAIT_LEVEL:
		return
	if trait_level >= 4 and faith < Folk.MAX_FAITH:
		return   # parked at 4 — waiting on faith 5
	trait_xp += base * xp_rate()
	var req: float = Folk.xp_req(trait_level)
	while trait_xp >= req and trait_level < Folk.MAX_TRAIT_LEVEL:
		trait_xp -= req
		trait_level += 1
		if trait_level >= Folk.MAX_TRAIT_LEVEL:
			trait_xp = 0.0
			break
		if trait_level >= 4 and faith < Folk.MAX_FAITH:
			trait_xp = 0.0   # reached the level-4 wall
			break
		req = Folk.xp_req(trait_level)


## Daily faith tick. Fed -> faith creeps up (slow); famine -> drop one level (fast).
func advance_day(fed: bool) -> void:
	if fed:
		if faith < _faith_cap():
			faith_progress += 1.0
			if faith_progress >= Folk.FED_DAYS_PER_FAITH:
				faith_progress = 0.0
				faith += 1
		else:
			faith_progress = 0.0
	else:
		if faith > 1:
			faith -= 1
		faith_progress = 0.0


## Advance one day of homelessness and roll whether the settler leaves for good.
## Days 1–5 are safe; the chance then ramps 5/15/25/50/75% and holds at 75%.
func mark_homeless_day() -> bool:
	days_homeless += 1
	return randf() < _leave_chance(days_homeless)


func _leave_chance(d: int) -> float:
	match d:
		1, 2, 3, 4, 5:
			return 0.0
		6:
			return 0.05
		7:
			return 0.15
		8:
			return 0.25
		9:
			return 0.50
		_:
			return 0.75


func get_display_name() -> String:
	return display_name


func get_info() -> String:
	var tl: String = Folk.TRAIT_LABEL.get(trait_key, trait_key)
	var g: String = "female" if gender == "f" else "male"
	var lvl_line: String = "%s  ·  trait Lv %d/%d" % [tl, trait_level, Folk.MAX_TRAIT_LEVEL]
	if trait_level >= 4 and faith < Folk.MAX_FAITH:
		lvl_line += "  (needs faith 5)"
	var faith_line: String = "Faith %d/%d" % [faith, Folk.MAX_FAITH]
	if faith >= _faith_cap() and faith < Folk.MAX_FAITH:
		faith_line += "   (capped — needs Temple)"
	var sp_name: String = species_key.capitalize()
	return "%s  ·  %s  ·  %s\n%s\n%s\n%s" % [display_name, sp_name, g, lvl_line, faith_line, _posting_text()]


func _posting_text() -> String:
	if has_job():
		var nm: String = _job.get_display_name() if _job.has_method("get_display_name") else "worksite"
		if is_on_trait(_job):
			return "Working: %s  (on-trait ✓)" % nm
		return "Working: %s  (off-trait — no bonus)" % nm
	if not has_home():
		var unit: String = "day" if days_homeless == 1 else "days"
		return "Homeless — %d %s" % [days_homeless, unit]
	return "Housed"


func set_species(sp: String) -> void:
	species_key = sp
	if _mat:
		_mat.albedo_color = COLORS.get(sp, Color.WHITE)


func set_idle_anchor(p: Vector3) -> void:
	_idle_anchor = p
	_meander_target = p


func has_home() -> bool:
	return _home != null and is_instance_valid(_home)


func set_home(h) -> void:
	_home = h
	if h != null:
		days_homeless = 0


## Become homeless: drift around the tree until housing opens up.
func go_homeless() -> void:
	_home = null
	days_homeless = 0
	var ang := randf() * TAU
	_idle_anchor = Vector3(cos(ang), 0.0, sin(ang)) * randf_range(4.0, 7.0)
	_meander_target = _idle_anchor
	_meander_timer = 0.0


func set_job(j) -> void:
	_job = j


func clear_job() -> void:
	_job = null


func get_job():
	return _job


func has_job() -> bool:
	return _job != null and is_instance_valid(_job)


func affinity(rtype: String) -> float:
	var t: Dictionary = AFFINITY.get(species_key, {})
	return float(t.get(rtype, 1.0))


## Stagger control: don't start moving for `delay` seconds.
func release_in(delay: float) -> void:
	_hold = delay


func _keep_out() -> float:
	if _tree and _tree.has_method("get_trunk_radius"):
		return _tree.get_trunk_radius() + 1.2
	return 2.5


func _at_work_phase() -> bool:
	return _gs != null and _gs.is_tending() and has_job()


func _home_anchor() -> Vector3:
	if has_home():
		return _home.global_position
	return _meander_target


func is_home() -> bool:
	return global_position.distance_to(_home_anchor()) < 2.5


func _target() -> Vector3:
	if _at_work_phase():
		return _job.global_position + _offset
	return _home_anchor() + _offset


func _process(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
	if not _at_work_phase() and not has_home():
		_meander(delta)
	if _hold > 0.0:
		return
	var spd := _speed
	if not _at_work_phase() and not has_home():
		spd *= 0.4   # homeless + meandering: amble at 40% speed
	_step_avoiding_tree(_target(), spd, delta)


## Move toward target but never walk through the trunk: steer around the
## tree's current keep-out circle (centred at the origin) and hard-clamp out.
func _step_avoiding_tree(target: Vector3, spd: float, delta: float) -> void:
	var pos2 := Vector2(global_position.x, global_position.z)
	var tgt2 := Vector2(target.x, target.z)
	var to := tgt2 - pos2
	if to.length() < 0.1:
		return
	var dir := to.normalized()
	var keep := _keep_out()
	var d_origin := pos2.length()
	if d_origin < keep:
		var outward := pos2.normalized() if d_origin > 0.01 else Vector2(1, 0)
		dir = (outward + _tangential(pos2, tgt2)).normalized()
	elif _segment_hits_circle(pos2, tgt2, keep):
		dir = _tangential(pos2, tgt2)
	var nxt := pos2 + dir * spd * delta
	if nxt.length() < keep:
		nxt = nxt.normalized() * keep
	global_position = Vector3(nxt.x, global_position.y, nxt.y)


func _tangential(pos2: Vector2, tgt2: Vector2) -> Vector2:
	var radial := pos2.normalized() if pos2.length() > 0.01 else Vector2(1, 0)
	var t1 := Vector2(-radial.y, radial.x)
	var to_t := (tgt2 - pos2).normalized()
	return t1 if t1.dot(to_t) >= (-t1).dot(to_t) else -t1


func _segment_hits_circle(a: Vector2, b: Vector2, r: float) -> bool:
	var ab := b - a
	var denom: float = maxf(ab.length_squared(), 0.0001)
	var t: float = clampf(-a.dot(ab) / denom, 0.0, 1.0)
	return (a + ab * t).length() < r


func _meander(delta: float) -> void:
	_meander_timer -= delta
	if _meander_timer <= 0.0:
		_meander_timer = randf_range(2.5, 5.0)
		var ang := randf() * TAU
		var inner: float = maxf(_keep_out() + 1.0, 4.0)
		var rad := randf_range(inner, inner + 4.0)
		_meander_target = Vector3(cos(ang), 0.0, sin(ang)) * rad
