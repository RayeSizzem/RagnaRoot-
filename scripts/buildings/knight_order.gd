extends Node3D
## The Knight Order (2×1 footprint). Warriors posted here train — gaining warrior
## trait XP (on-trait) — toward the faith-5 / trait-5 mastery that lets the Hall of
## Heroes promote them. Only warriors may be posted here. Produces no resources.

const TILE := 2.0
const SLOTS := 4
const XP_PER_TICK := 1.0

var _workers: Array = []


func _enter_tree() -> void:
	add_to_group("worksite")
	add_to_group("knight_order")


func _ready() -> void:
	var gs = get_tree().get_first_node_in_group("game_state")
	if gs:
		gs.produce.connect(_on_tick)
	add_child(_make_visual())


func _make_visual() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.52, 0.58)
	# 2×1 barracks: two stone blocks side by side (local cells at x = -1 and +1).
	for x in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(TILE * 0.92, 1.0, TILE * 0.92)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(x, 0.5, 0.0)
		root.add_child(mi)
	# a martial banner spike on the right block
	var spike := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.18
	cyl.height = 1.6
	spike.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.85, 0.3, 0.28)
	spike.material_override = sm
	spike.position = Vector3(1.0, 1.8, 0.0)
	root.add_child(spike)
	return root


func _prune() -> void:
	_workers = _workers.filter(func(x): return is_instance_valid(x))


func worker_cap() -> int:
	return SLOTS


func worker_count() -> int:
	_prune()
	return _workers.size()


func available_slots() -> int:
	return worker_cap() - worker_count()


## Only warriors may train at the Knight Order.
func accepts_resident(r) -> bool:
	return r != null and is_instance_valid(r) and r.trait_key == "warrior"


func assign_resident(r) -> bool:
	if not accepts_resident(r) or r.has_job():
		return false
	if available_slots() <= 0:
		return false
	_workers.append(r)
	r.set_job(self)
	return true


func assign_species(sp: String) -> bool:
	if available_slots() <= 0:
		return false
	var r = _find_idle(sp)
	if r == null:
		return false
	return assign_resident(r)


func remove_worker() -> bool:
	_prune()
	if _workers.is_empty():
		return false
	var r = _workers.pop_back()
	if is_instance_valid(r):
		r.clear_job()
	return true


func _find_idle(sp: String):
	for r in get_tree().get_nodes_in_group("resident"):
		if is_instance_valid(r) and r.species_key == sp and not r.has_job() and accepts_resident(r):
			return r
	return null


func _on_tick() -> void:
	_prune()
	for w in _workers:
		if is_instance_valid(w) and w.has_method("gain_trait_xp"):
			w.gain_trait_xp(XP_PER_TICK)


func get_workers() -> Array:
	_prune()
	return _workers


func get_roster_label() -> String:
	return "Knights"


func get_assign_label() -> String:
	return "Assign Warrior"


func get_display_name() -> String:
	return "Knight Order"


func get_info() -> String:
	return "Knight Order\nWarriors %d / %d   (training toward mastery)" % [worker_count(), worker_cap()]
