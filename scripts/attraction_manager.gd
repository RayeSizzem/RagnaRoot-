extends Node
## Drives population. Each attracted species fills a counter (points/day) and
## spawns a settler into matching housing at 100. Attraction BUILDINGS (grafted
## on the tree, chosen from the Tree menu) switch a species on, or boost the two
## starter species. No housing room -> the counter holds at 100 (never wasted).

const RESIDENT := preload("res://scenes/resident.tscn")
const THRESHOLD := 100.0

const SPECIES := ["human", "elf", "dwarf"]
const BASE_RATE := {"human": 80.0, "elf": 60.0, "dwarf": 0.0}
const BUILT_RATE := {"human": 140.0, "elf": 120.0, "dwarf": 100.0}
const UNLOCK_STAGE := {"human": 0, "elf": 0, "dwarf": 3}
const BUILDING_NAME := {"human": "Human Tavern", "elf": "Elven Tea Terrace", "dwarf": "Smithy Burrow"}
const STAGE_NAMES := ["Sapling", "Sentinel", "Greatbough", "Canopy", "Worldcrown"]
const BUILD_COST := {"timber": 500, "stone": 500, "sap": 200}

var _built := {}
var _counter := {}
var _gs
var _tree
var _bank


func _enter_tree() -> void:
	add_to_group("attraction")


func _ready() -> void:
	_gs = get_tree().get_first_node_in_group("game_state")
	_tree = get_tree().get_first_node_in_group("world_tree")
	_bank = get_tree().get_first_node_in_group("resource_bank")
	for sp in SPECIES:
		_counter[sp] = 0.0
	if _gs:
		_gs.day_changed.connect(_on_day)
	call_deferred("_spawn_starters")


func species_list() -> Array:
	return SPECIES


func rate(sp: String) -> float:
	if _built.has(sp):
		return float(BUILT_RATE.get(sp, 0.0))
	return float(BASE_RATE.get(sp, 0.0))


func is_built(sp: String) -> bool:
	return _built.has(sp)


func unlock_stage(sp: String) -> int:
	return int(UNLOCK_STAGE.get(sp, 99))


func unlock_stage_name(sp: String) -> String:
	var i: int = unlock_stage(sp)
	return STAGE_NAMES[i] if (i >= 0 and i < STAGE_NAMES.size()) else "?"


func is_unlocked(sp: String) -> bool:
	var stage: int = _tree.stage if _tree else 0
	return stage >= unlock_stage(sp)


func building_name(sp: String) -> String:
	return String(BUILDING_NAME.get(sp, "Attraction"))


func can_build(sp: String) -> bool:
	return is_unlocked(sp) and not _built.has(sp)


func build_cost() -> Dictionary:
	return BUILD_COST


func build_attraction(sp: String) -> bool:
	if not can_build(sp):
		return false
	if _bank and not _bank.can_afford(BUILD_COST):
		return false
	if _bank:
		_bank.spend_many(BUILD_COST)
	_built[sp] = true
	_spawn_one(sp, true)   # instant +1 on construction
	return true


## Move any homeless settler into a housing hut of its species with room.
## Fixes settlers (displaced, or spawned while full) that never found a bed.
func rehome_homeless() -> void:
	for r in get_tree().get_nodes_in_group("resident"):
		if not is_instance_valid(r) or r.has_home():
			continue
		var sp: String = r.species_key
		for h in get_tree().get_nodes_in_group("housing"):
			if h.has_method("has_room_for") and h.has_room_for(sp) and h.has_method("_accept_resident"):
				h._accept_resident(r)
				break


const FOOD_UPKEEP := 1   # grain+meat eaten per resident per day
const MAX_HOMELESS := 20 # at this many homeless, immigration freezes


func _on_day(_day: int = 0, _cycle: int = 0) -> void:
	# Daily upkeep: the colony eats from a pooled grain+meat stock. Fed -> faith
	# creeps up; short -> famine, everyone loses a faith level. Early on faith is
	# floored so famine is painless; it only bites once you've raised faith.
	var fed: bool = _food_check()
	var consecrated: bool = is_consecrated()
	for r in get_tree().get_nodes_in_group("resident"):
		if not is_instance_valid(r):
			continue
		if r.has_method("set_temple_consecrated"):
			r.set_temple_consecrated(consecrated)
		if r.has_method("advance_day"):
			r.advance_day(fed)
	rehome_homeless()
	_process_homeless_attrition()
	# Immigration freezes while the homeless pool is maxed out — house people first.
	if _homeless_count() >= MAX_HOMELESS:
		return
	for sp in SPECIES:
		var r: float = rate(sp)
		if r <= 0.0:
			continue
		_counter[sp] += r
		while _counter[sp] >= THRESHOLD:
			if _spawn_one(sp, false):
				_counter[sp] -= THRESHOLD
			else:
				_counter[sp] = THRESHOLD   # no room: hold full until housing opens up
				break


func _homeless_count() -> int:
	var n := 0
	for r in get_tree().get_nodes_in_group("resident"):
		if is_instance_valid(r) and r.has_method("has_home") and not r.has_home():
			n += 1
	return n


## Tick days-homeless on the still-unhoused and roll departures. Leavers free their
## job and vanish, with a brief on-screen notice to the player.
func _process_homeless_attrition() -> void:
	var leavers: Array = []
	for r in get_tree().get_nodes_in_group("resident"):
		if not is_instance_valid(r):
			continue
		if r.has_method("has_home") and not r.has_home() and r.has_method("mark_homeless_day"):
			if r.mark_homeless_day():
				leavers.append(r)
	if leavers.is_empty():
		return
	var names: Array = []
	for r in leavers:
		names.append(String(r.get("display_name")))
		if r.has_method("clear_job"):
			r.clear_job()
		r.queue_free()
	var msg: String
	if names.size() == 1:
		msg = "%s left — too long without a home." % names[0]
	elif names.size() == 2:
		msg = "%s and %s left — too long without a home." % [names[0], names[1]]
	else:
		msg = "%s and %d others left — too long without a home." % [names[0], names.size() - 1]
	_notify(msg)


func _notify(text: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("notify"):
		hud.notify(text)


## Eat from the pooled grain+meat stock (grain first). Returns whether the whole
## colony was fed; consumes whatever is available either way.
## --- Temple consecration (Phase C) ---
## The colony is "consecrated" once a Temple exists AND at least 3 priestesses have
## reached faith-5 + trait-5. That lifts the faith-4 cap on everyone else, which in
## turn unlocks trait-5 across the whole population.
## Spawn one settler of a random currently-unlocked species, routed through the
## normal immigration path (into housing if there's room, else homeless). Used by
## the dev cheat menu; integrates cleanly with identity rolling + housing.
func debug_spawn_random() -> void:
	var pool: Array = []
	for sp in SPECIES:
		if is_unlocked(sp):
			pool.append(sp)
	if pool.is_empty():
		pool = ["human"]
	var sp: String = pool[randi() % pool.size()]
	_spawn_one(sp, true)
	rehome_homeless()


func maxed_priestess_count() -> int:
	var n := 0
	for r in get_tree().get_nodes_in_group("resident"):
		if not is_instance_valid(r):
			continue
		if r.get("trait_key") == "priestess" and int(r.get("faith")) >= Folk.MAX_FAITH and int(r.get("trait_level")) >= Folk.MAX_TRAIT_LEVEL:
			n += 1
	return n


func temple_exists() -> bool:
	return not get_tree().get_nodes_in_group("temple").is_empty()


func is_consecrated() -> bool:
	return temple_exists() and maxed_priestess_count() >= 3


func _food_check() -> bool:
	if _bank == null:
		return true
	var pop := 0
	for r in get_tree().get_nodes_in_group("resident"):
		if is_instance_valid(r):
			pop += 1
	var need: int = pop * FOOD_UPKEEP
	if need <= 0:
		return true
	var grain: int = _bank.get_amount("grain")
	var meat: int = _bank.get_amount("meat")
	var avail: int = grain + meat
	var take: int = mini(need, avail)
	var g_take: int = mini(grain, take)
	if g_take > 0:
		_bank.spend("grain", g_take)
	if take - g_take > 0:
		_bank.spend("meat", take - g_take)
	return avail >= need


## Roll a newcomer's identity, keeping enough women that a Temple stays reachable.
func _roll_identity(force_trait: String = "") -> Dictionary:
	var g: String = Folk.roll_gender()
	if force_trait == "" and _female_fraction() < Folk.FEMALE_RATIO_FLOOR:
		g = "f"
	var tr: String = force_trait if force_trait != "" else Folk.roll_trait(g)
	return {"gender": g, "trait": tr, "faith": 1, "name": _unique_name(g)}


## Pick a gender-appropriate name not already in use; if the pool is exhausted,
## append a roman numeral (e.g. "Cael II").
func _unique_name(g: String) -> String:
	var used := {}
	for r in get_tree().get_nodes_in_group("resident"):
		if is_instance_valid(r):
			used[String(r.get("display_name"))] = true
	var pool: Array = (Folk.FEMALE_NAMES if g == "f" else Folk.MALE_NAMES).duplicate()
	pool.shuffle()
	for nm in pool:
		if not used.has(nm):
			return nm
	var base: String = pool[0]
	var i := 2
	while used.has("%s %s" % [base, _roman(i)]):
		i += 1
	return "%s %s" % [base, _roman(i)]


func _roman(n: int) -> String:
	var table := [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]
	var s := ""
	var x := n
	for pair in table:
		while x >= int(pair[0]):
			s += String(pair[1])
			x -= int(pair[0])
	return s


func _female_fraction() -> float:
	var total := 0
	var fem := 0
	for r in get_tree().get_nodes_in_group("resident"):
		if not is_instance_valid(r):
			continue
		total += 1
		if r.get("gender") == "f":
			fem += 1
	if total <= 0:
		return 1.0
	return float(fem) / float(total)


func _spawn_one(sp: String, allow_homeless: bool) -> bool:
	var identity: Dictionary = _roll_identity()
	for h in get_tree().get_nodes_in_group("housing"):
		if h.has_method("has_room_for") and h.has_room_for(sp):
			h.add_resident(sp, identity)
			return true
	if allow_homeless:
		_spawn_homeless(sp, identity)
		return true
	return false


func _spawn_starters() -> void:
	# Founders are all plain workers, so the opening colony is stable.
	for i in 2:
		_spawn_homeless("human", _roll_identity("worker"))
	for i in 2:
		_spawn_homeless("elf", _roll_identity("worker"))


func _spawn_homeless(sp: String, identity: Dictionary = {}) -> void:
	if identity.is_empty():
		identity = _roll_identity()
	var ang: float = randf() * TAU
	var anchor := Vector3(cos(ang), 0.0, sin(ang)) * 7.0
	var r := RESIDENT.instantiate()
	r.setup(sp, null)
	add_child(r)
	r.global_position = anchor
	if r.has_method("init_identity"):
		r.init_identity(identity["gender"], identity["trait"], int(identity["faith"]), String(identity.get("name", "")))
	if r.has_method("set_idle_anchor"):
		r.set_idle_anchor(anchor)
