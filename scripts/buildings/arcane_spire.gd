extends Node3D
## The Arcane Spire (1×1). Staffed by arcanists, who channel the night's Essence
## into HOLY LIGHT on command. Holy Light mends the Heartroot and is spent at the
## Hall of Heroes to promote warriors. Arcanists train here (on-trait) toward
## mastery; a more skilled spire channels far more Light per command.

const TILE := 2.0
const SLOTS := 3
const XP_PER_TICK := 1.0
# Holy Light a single arcanist draws per channel, by trait level (L1..L5).
const CHANNEL_YIELD := [25, 40, 60, 80, 100]
const MEND_LIGHT := 20   # Holy Light spent per mend
const MEND_HEAL := 25    # Heartroot HP restored per mend

var _workers: Array = []
var _bank
var _tree


func _enter_tree() -> void:
	add_to_group("worksite")
	add_to_group("spire")


func _ready() -> void:
	_bank = get_tree().get_first_node_in_group("resource_bank")
	_tree = get_tree().get_first_node_in_group("world_tree")
	var gs = get_tree().get_first_node_in_group("game_state")
	if gs:
		gs.produce.connect(_on_tick)
	add_child(_make_visual())


func _make_visual() -> Node3D:
	var root := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.6
	cyl.height = 2.2
	shaft.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.5, 0.45, 0.7)
	shaft.material_override = bm
	shaft.position.y = 1.1
	root.add_child(shaft)
	# floating light crystal at the tip
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	orb.mesh = sm
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(1.0, 0.96, 0.7)
	om.emission_enabled = true
	om.emission = Color(1.0, 0.95, 0.65)
	om.emission_energy_multiplier = 1.4
	orb.material_override = om
	orb.position.y = 2.6
	root.add_child(orb)
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


## Only arcanists may serve at the Spire.
func accepts_resident(r) -> bool:
	return r != null and is_instance_valid(r) and r.trait_key == "arcanist"


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
	return "Arcanists"


func get_assign_label() -> String:
	return "Assign Arcanist"


# --- Holy Light channeling -------------------------------------------------

## How much Light the staffed arcanists could draw right now, capped by Essence.
func get_channel_amount() -> int:
	_prune()
	var potential := 0
	for w in _workers:
		if is_instance_valid(w):
			var lv: int = clampi(int(w.trait_level), 1, CHANNEL_YIELD.size())
			potential += CHANNEL_YIELD[lv - 1]
	var essence: int = _bank.get_amount("essence") if _bank else 0
	return mini(potential, essence)


func can_channel() -> bool:
	return get_channel_amount() > 0


## Convert Essence into Holy Light, 1:1, up to the staffed throughput.
func channel_holy_light() -> int:
	var amt: int = get_channel_amount()
	if amt <= 0 or _bank == null:
		return 0
	if not _bank.spend("essence", amt):
		return 0
	_bank.add("holy_light", amt)
	return amt


# --- Mending the Heartroot -------------------------------------------------

func get_mend_light() -> int:
	return MEND_LIGHT


func get_mend_heal() -> int:
	return MEND_HEAL


func can_mend() -> bool:
	if _bank == null or _tree == null:
		return false
	if _bank.get_amount("holy_light") < MEND_LIGHT:
		return false
	if _tree.has_method("heartroot_missing"):
		return _tree.heartroot_missing() > 0
	return true


func mend_heartroot() -> int:
	if not can_mend():
		return 0
	if not _bank.spend("holy_light", MEND_LIGHT):
		return 0
	if _tree.has_method("heal_heartroot"):
		return _tree.heal_heartroot(MEND_HEAL)
	return 0


func get_display_name() -> String:
	return "Arcane Spire"


func get_info() -> String:
	return "Arcane Spire\nArcanists %d / %d   (channel ~%d Light)\nHoly Light: %d" % [
		worker_count(), worker_cap(), get_channel_amount(),
		_bank.get_amount("holy_light") if _bank else 0
	]
