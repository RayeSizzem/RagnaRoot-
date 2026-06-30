extends Node3D
## The Temple (T-tetromino footprint). Priestesses posted here level their trait
## (on-trait), and the Temple is the colony's endgame GATE: once the settlement
## holds 3 priestesses at faith-5 + trait-5 (and a Temple exists), it becomes
## "consecrated", which lifts the faith-4 cap on everyone else -> unlocking trait-5
## across the whole population. The Temple itself produces no resources.

const TILE := 2.0
const SLOTS := 5
const XP_PER_TICK := 1.0
# Visual cell centres (local), matching the build footprint [[0,0],[1,0],[2,0],[1,1]]
# whose bounding centre is (1, 0.5): local = (offset - centre) * TILE.
const CELLS := [Vector3(-2, 0, -1), Vector3(0, 0, -1), Vector3(2, 0, -1), Vector3(0, 0, 1)]

var _workers: Array = []
var _attr


func _enter_tree() -> void:
	add_to_group("worksite")
	add_to_group("temple")


func _ready() -> void:
	_attr = get_tree().get_first_node_in_group("attraction")
	var gs = get_tree().get_first_node_in_group("game_state")
	if gs:
		gs.produce.connect(_on_tick)
	add_child(_make_visual())


func _make_visual() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.83, 0.72)
	for c in CELLS:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(TILE * 0.94, 0.6, TILE * 0.94)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(c.x, 0.3, c.z)
		root.add_child(mi)
	# luminous spire on the centre of the bar
	var spire := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.7
	cyl.height = 2.6
	spire.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.97, 0.92, 0.62)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.95, 0.65)
	sm.emission_energy_multiplier = 0.7
	spire.material_override = sm
	spire.position = Vector3(0.0, 1.6, -1.0)
	root.add_child(spire)
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


## Prefer an idle on-trait resident (a priestess) so the Temple staffs the right
## people; fall back to any idle of that species if none are available.
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


func _on_tick() -> void:
	_prune()
	for w in _workers:
		if is_instance_valid(w) and w.has_method("is_on_trait") and w.is_on_trait(self) and w.has_method("gain_trait_xp"):
			w.gain_trait_xp(XP_PER_TICK)


func get_workers() -> Array:
	_prune()
	return _workers


func get_display_name() -> String:
	return "Temple"


func get_info() -> String:
	var maxed := 0
	var consecrated := false
	if _attr and _attr.has_method("maxed_priestess_count"):
		maxed = _attr.maxed_priestess_count()
	if _attr and _attr.has_method("is_consecrated"):
		consecrated = _attr.is_consecrated()
	var status: String = "Consecrated ✦" if consecrated else "Unconsecrated"
	return "Temple\nPriestesses %d / %d\n%s  (%d/3 maxed)" % [worker_count(), worker_cap(), status, maxed]
