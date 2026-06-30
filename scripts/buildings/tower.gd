extends Node3D
## Defensive tower. Its `kind` (set at placement) drives range, fire rate, damage,
## targeting (single / chain / splash) and on-hit effects. Twelve kinds unlock as
## the World Tree grows. Upgrades twice: each +50% damage and +25% fire rate.

const PROJECTILE := preload("res://scenes/projectile.tscn")
const MAX_LEVEL := 2
const RATE_SCALE := 0.30  # towers fire at 30% of base rate (70% slower attack speed)
const UPGRADE_COST := [{"timber": 30, "stone": 15}, {"timber": 50, "stone": 25}]
const GARRISON_CAP := 3
const GARRISON_BONUS := 0.08   # +8% damage per garrisoned warrior

@export var kind: String = "sapshot"
@export var building_model: PackedScene

var level: int = 0
var _cd: float = 0.0
var _d: Dictionary = {}
var _garrison: Array = []


func _enter_tree() -> void:
	add_to_group("tower")


## name, unlock stage, cost, range, interval, damage, mode, and effects per kind.
## mode: "single" | "chain"(count) | "aoe"(splash). fx: slow/dot/root/knockback.
static func table() -> Dictionary:
	return {
		"sapshot":   { "air": true,"name": "Sapshot Spire",   "stage": 0, "cost": {"timber": 20, "stone": 10},  "range": 7.0,  "int": 0.55, "dmg": 8,  "mode": "single", "col": Color(1.0, 0.82, 0.35)},
		"thornlash": {"name": "Thornlash",       "stage": 0, "cost": {"timber": 25, "stone": 10},  "range": 6.0,  "int": 0.20, "dmg": 4,  "mode": "single", "col": Color(0.5, 0.85, 0.4)},
		"bramble":   {"name": "Bramble Mortar",  "stage": 1, "cost": {"timber": 40, "stone": 25},  "range": 9.0,  "int": 1.40, "dmg": 11, "mode": "aoe", "splash": 2.5, "col": Color(0.6, 0.42, 0.25)},
		"frost":     { "air": true,"name": "Frostbloom",      "stage": 1, "cost": {"timber": 45, "stone": 20},  "range": 7.0,  "int": 0.80, "dmg": 5,  "mode": "single", "fx": {"slow": {"f": 0.5, "d": 2.0}}, "col": Color(0.45, 0.8, 0.95)},
		"spark":     { "air": true,"name": "Sparkroot",       "stage": 2, "cost": {"timber": 60, "stone": 35},  "range": 7.5,  "int": 0.90, "dmg": 7,  "mode": "chain", "count": 3, "col": Color(0.5, 0.7, 1.0)},
		"ironbark":  { "air": true,"name": "Ironbark Ballista","stage": 2,"cost": {"timber": 55, "stone": 45},  "range": 11.0, "int": 1.80, "dmg": 30, "mode": "single", "col": Color(0.6, 0.62, 0.7)},
		"ember":     {"name": "Emberthorn",      "stage": 2, "cost": {"timber": 60, "stone": 30},  "range": 7.0,  "int": 0.90, "dmg": 4,  "mode": "single", "fx": {"dot": {"dps": 6.0, "d": 3.0}}, "col": Color(1.0, 0.45, 0.2)},
		"gale":      { "air": true,"name": "Gale Censer",     "stage": 3, "cost": {"timber": 70, "stone": 50},  "range": 6.5,  "int": 1.20, "dmg": 5,  "mode": "aoe", "splash": 2.2, "fx": {"knockback": 2.2}, "col": Color(0.6, 0.85, 0.82)},
		"venom":     {"name": "Venomcap",        "stage": 3, "cost": {"timber": 75, "stone": 45},  "range": 8.0,  "int": 1.50, "dmg": 3,  "mode": "aoe", "splash": 2.6, "fx": {"dot": {"dps": 5.0, "d": 4.0}}, "col": Color(0.5, 0.8, 0.3)},
		"sunspear":  { "air": true,"name": "Sunspear",        "stage": 3, "cost": {"timber": 90, "stone": 55},  "range": 13.0, "int": 1.00, "dmg": 24, "mode": "single", "col": Color(1.0, 0.96, 0.6)},
		"gravewell": {"name": "Gravewell",       "stage": 4, "cost": {"timber": 110, "stone": 80}, "range": 8.0,  "int": 2.50, "dmg": 6,  "mode": "aoe", "splash": 3.0, "fx": {"root": 1.5}, "col": Color(0.6, 0.4, 0.85)},
		"heartcannon":{ "air": true,"name": "Heartcannon",    "stage": 4, "cost": {"timber": 140, "stone": 100},"range": 11.0, "int": 3.00, "dmg": 48, "mode": "aoe", "splash": 4.0, "col": Color(0.95, 0.35, 0.3)},
	}


func _ready() -> void:
	var t: Dictionary = table()
	_d = t.get(kind, t["sapshot"])
	if building_model:
		add_child(building_model.instantiate())
	else:
		add_child(_placeholder())


func _placeholder() -> Node3D:
	var col: Color = _d.get("col", Color(0.6, 0.66, 0.78))
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.6, 0.9)
	base.mesh = bm
	base.position.y = 0.3
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = col.darkened(0.35)
	base.material_override = bmat
	root.add_child(base)
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.24
	cyl.height = 1.1
	barrel.mesh = cyl
	barrel.position.y = 1.05
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = col
	cmat.emission_enabled = true
	cmat.emission = col
	cmat.emission_energy_multiplier = 0.4
	barrel.material_override = cmat
	root.add_child(barrel)
	return root


func _process(delta: float) -> void:
	if _cd > 0.0:
		_cd -= delta
		return
	var targets: Array = _acquire()
	if targets.size() > 0:
		_fire(targets)
		_cd = _interval_now()


func _acquire() -> Array:
	var first: Node = _nearest_in_range()
	if first == null:
		return []
	if _d.get("mode", "single") == "chain":
		var out: Array = [first]
		var count: int = _d.get("count", 3)
		var hop2: float = 16.0   # chain hops up to ~4 units between enemies
		while out.size() < count:
			var nxt: Node = _nearest_to(out[out.size() - 1].global_position, out, hop2)
			if nxt == null:
				break
			out.append(nxt)
		return out
	return [first]


func _fire(targets: Array) -> void:
	var splash: float = _d.get("splash", 0.0)
	var fx: Dictionary = _d.get("fx", {})
	var col: Color = _d.get("col", Color(1.0, 0.85, 0.4))
	for tgt in targets:
		if not is_instance_valid(tgt):
			continue
		var p := PROJECTILE.instantiate()
		get_tree().current_scene.add_child(p)
		p.global_position = global_position + Vector3(0, 1.2, 0)
		p.setup(tgt, _damage_now(), fx, splash, col)


func _damage_now() -> int:
	var base: int = _d.get("dmg", 8)
	var raw: float = float(base) * pow(1.5, level)
	raw *= 1.0 + GARRISON_BONUS * float(garrison_count())
	return int(round(raw))


func _interval_now() -> float:
	var base: float = _d.get("int", 0.55)
	# Towers fire at 30% of their table rate (70% slower) -> interval lengthened.
	return base * pow(0.8, level) / RATE_SCALE


func _range() -> float:
	return _d.get("range", 7.0)


func _nearest_in_range() -> Node:
	var air: bool = _d.get("air", false)
	var best: Node = null
	var best_d: float = _range() * _range()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if not air and e.has_method("is_flying") and e.is_flying():
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best


func _nearest_to(pos: Vector3, exclude: Array, max_hop2: float) -> Node:
	var air: bool = _d.get("air", false)
	var best: Node = null
	var best_d: float = max_hop2
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or exclude.has(e):
			continue
		if not air and e.has_method("is_flying") and e.is_flying():
			continue
		var d: float = pos.distance_squared_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best


func get_range() -> float:
	return _range()


func get_display_name() -> String:
	return _d.get("name", "Tower")


func get_info() -> String:
	var g: int = garrison_count()
	var bonus: String = ""
	if g > 0:
		bonus = "   +%d%% dmg" % int(round(GARRISON_BONUS * 100.0 * g))
	return "%s  Lv %d   (dmg %d, %.2fs)%s\nGarrison %d / %d" % [
		get_display_name(), level + 1, _damage_now(), _interval_now(), bonus, g, GARRISON_CAP
	]


# --- Garrison: spare warriors stationed here add combat punch (warriors only) ---

func _prune_garrison() -> void:
	_garrison = _garrison.filter(func(x): return is_instance_valid(x))


func garrison_count() -> int:
	_prune_garrison()
	return _garrison.size()


func worker_cap() -> int:
	return GARRISON_CAP


func worker_count() -> int:
	return garrison_count()


func available_slots() -> int:
	return GARRISON_CAP - garrison_count()


func accepts_resident(r) -> bool:
	return r != null and is_instance_valid(r) and r.trait_key == "warrior"


func assign_resident(r) -> bool:
	if not accepts_resident(r) or r.has_job():
		return false
	if available_slots() <= 0:
		return false
	_garrison.append(r)
	r.set_job(self)
	return true


func remove_worker() -> bool:
	_prune_garrison()
	if _garrison.is_empty():
		return false
	var r = _garrison.pop_back()
	if is_instance_valid(r):
		r.clear_job()
	return true


func get_workers() -> Array:
	_prune_garrison()
	return _garrison


func get_roster_label() -> String:
	return "Garrison"


func get_assign_label() -> String:
	return "Assign Garrison"


func is_combat_building() -> bool:
	return true


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
