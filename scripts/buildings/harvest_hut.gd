extends Node3D
## Timber Hut / Mason Hut. A worksite: assign resident workers (a shared labour
## pool from housing huts). Each produce tick it harvests the nearest matching
## node, output = sum over workers of PER_WORKER x that worker's species affinity.
## Must be built within reach of a matching resource node. Upgrades add worker
## slots (3 -> 4 -> 5).

@export var family: String = "wood"   # "wood" or "mineral" — the hut's category
@export var harvest_range: float = 5.0
var resource_type: String = "timber"   # specific resource currently bound

const PER_WORKER := 12
const XP_PER_TICK := 1.0
const WORKER_CAP := [3, 4, 5]
const MAX_LEVEL := 2
const UPGRADE_COST := [{"timber": 20, "stone": 20}, {"timber": 40, "stone": 40}]

var level: int = 0
var _bank
var _field
var _node
var _workers: Array = []


func _enter_tree() -> void:
	add_to_group("hut")
	add_to_group("worksite")


func _ready() -> void:
	_bank = get_tree().get_first_node_in_group("resource_bank")
	_field = get_tree().get_first_node_in_group("resource_field")
	var gs = get_tree().get_first_node_in_group("game_state")
	if gs:
		gs.produce.connect(_on_tick)
	add_child(_make_visual())
	_bind()


func _make_visual() -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.0, 1.0)
	mi.mesh = bm
	mi.position.y = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.2) if family == "wood" else Color(0.5, 0.52, 0.55)
	mi.material_override = mat
	return mi


func _bind() -> void:
	if _field:
		_node = _field.find_nearest_family(global_position, family, harvest_range)
		if _node and is_instance_valid(_node):
			resource_type = _node.get_type()


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
	# On-trait (a Worker here): full species x trait-level x faith bonus.
	# Off-trait: base species affinity only — works, but no bonus and no XP.
	if w.has_method("is_on_trait") and w.is_on_trait(self) and w.has_method("yield_mult"):
		return w.yield_mult(resource_type)
	return w.affinity(resource_type)


func _estimated_output() -> int:
	_prune()
	var amt := 0
	for w in _workers:
		if is_instance_valid(w):
			amt += roundi(PER_WORKER * _worker_mult(w))
	return amt


func _on_tick() -> void:
	_prune()
	if _node == null or not is_instance_valid(_node) or _node.is_depleted():
		_bind()
	# on-trait workers gain a little trait XP each working tick
	for w in _workers:
		if is_instance_valid(w) and w.has_method("is_on_trait") and w.is_on_trait(self) and w.has_method("gain_trait_xp"):
			w.gain_trait_xp(XP_PER_TICK)
	var amt := _estimated_output()
	if amt > 0 and _node and is_instance_valid(_node):
		var got: int = _node.harvest(amt)
		if got > 0 and _bank:
			_bank.add(resource_type, got)


func get_display_name() -> String:
	return "Timber Hut" if family == "wood" else "Mason Hut"


func get_info() -> String:
	return "%s  Lv %d\nWorkers %d / %d   (~%d %s/10s)" % [
		get_display_name(), level + 1, worker_count(), worker_cap(),
		_estimated_output(), resource_type
	]


func get_resource_type() -> String:
	return resource_type


func get_range() -> float:
	return harvest_range


func get_per_tick() -> int:
	return _estimated_output()


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
