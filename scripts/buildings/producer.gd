extends Node3D
## A staffed PRODUCER worksite (Farmstead -> Grain, Pasture -> Meat). Unlike the
## harvest huts it binds to no resource node: it simply produces while staffed.
## A worker posted here earns the on-trait bonus + trait XP only if their trait
## matches `worksite_group` (farmer for a Farmstead, shepherd for a Pasture);
## anyone else still works, but at base output with no bonus and no XP.

@export var worksite_group: String = "farmstead"   # group + trait this site rewards
@export var produces: String = "grain"
@export var display_label: String = "Farmstead"
@export var foot_w: int = 2
@export var foot_d: int = 2
@export var tint: Color = Color(0.55, 0.62, 0.3)

const TILE := 2.0
const PER_WORKER := 8
const XP_PER_TICK := 1.0
const WORKER_CAP := [3, 4, 5]
const MAX_LEVEL := 2
const UPGRADE_COST := [{"timber": 40, "stone": 20}, {"timber": 80, "stone": 40}]

var level: int = 0
var _bank
var _workers: Array = []


func _enter_tree() -> void:
	add_to_group("worksite")
	add_to_group(worksite_group)


func _ready() -> void:
	_bank = get_tree().get_first_node_in_group("resource_bank")
	var gs = get_tree().get_first_node_in_group("game_state")
	if gs:
		gs.produce.connect(_on_tick)
	add_child(_make_visual())


func _make_visual() -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(foot_w * TILE * 0.92, 1.1, foot_d * TILE * 0.92)
	mi.mesh = bm
	mi.position.y = 0.55
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mi.material_override = mat
	return mi


func _prune() -> void:
	_workers = _workers.filter(func(x): return is_instance_valid(x))


func worker_cap() -> int:
	return WORKER_CAP[level]


func worker_count() -> int:
	_prune()
	return _workers.size()


func available_slots() -> int:
	return worker_cap() - worker_count()


func assign_species(sp: String) -> bool:
	if available_slots() <= 0:
		return false
	var r = _find_idle(sp)
	if r == null:
		return false
	_workers.append(r)
	r.set_job(self)
	return true



func assign_resident(r) -> bool:
	if r == null or not is_instance_valid(r) or r.has_job():
		return false
	if available_slots() <= 0:
		return false
	_workers.append(r)
	r.set_job(self)
	return true

func remove_worker() -> bool:
	_prune()
	if _workers.is_empty():
		return false
	var r = _workers.pop_back()
	if is_instance_valid(r):
		r.clear_job()
	return true


func _find_idle(sp: String):
	var fallback = null
	for r in get_tree().get_nodes_in_group("resident"):
		if not is_instance_valid(r) or r.species_key != sp or r.has_job():
			continue
		if r.has_method("is_on_trait") and r.is_on_trait(self):
			return r
		if fallback == null:
			fallback = r
	return fallback


func _worker_mult(w) -> float:
	if w.has_method("is_on_trait") and w.is_on_trait(self) and w.has_method("yield_mult"):
		return w.yield_mult(produces)
	return w.affinity(produces)   # off-trait: base only (1.0 for food), no bonus


func _estimated_output() -> int:
	_prune()
	var amt := 0
	for w in _workers:
		if is_instance_valid(w):
			amt += roundi(PER_WORKER * _worker_mult(w))
	return amt


func _on_tick() -> void:
	_prune()
	for w in _workers:
		if is_instance_valid(w) and w.has_method("is_on_trait") and w.is_on_trait(self) and w.has_method("gain_trait_xp"):
			w.gain_trait_xp(XP_PER_TICK)
	var amt := _estimated_output()
	if amt > 0 and _bank:
		_bank.add(produces, amt)


func get_display_name() -> String:
	return display_label


func get_info() -> String:
	return "%s  Lv %d\nWorkers %d / %d   (~%d %s/10s)" % [
		display_label, level + 1, worker_count(), worker_cap(),
		_estimated_output(), produces
	]


func get_per_tick() -> int:
	return _estimated_output()


func get_resource_type() -> String:
	return produces


func get_workers() -> Array:
	_prune()
	return _workers


func get_upgrade_cost() -> Dictionary:
	if level >= MAX_LEVEL:
		return {}
	return UPGRADE_COST[level]


func try_upgrade(bank) -> bool:
	if level >= MAX_LEVEL:
		return false
	var c: Dictionary = UPGRADE_COST[level]
	if bank and bank.spend_many(c):
		level += 1
		return true
	return false
