extends Node
## Runs night. On "Advance Day": workers leave their worksites one by one and
## head home; once everyone's in (or a timeout), a short pause, THEN monsters
## spawn from the first `tower_count` towers. After the wave is cleared there's a
## dawn pause, the day rolls over, and workers head back out one by one.

@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@export var base_enemies_per_lane: int = 3
@export var spawn_interval: float = 0.8

@export var worker_stagger: float = 0.4     # gap between each worker setting off
@export var home_timeout: float = 6.0       # max wait for stragglers to get home
@export var spawn_delay: float = 3.0        # quiet beat after everyone's home
@export var dawn_delay: float = 3.0         # pause after the wave before day resumes

var _gs
var _wm
var _tree
var _wave_active := false

# Creatures of the Dark by earliest CYCLE + spawn weight. `cluster` makes swarm
# kinds spawn in packs; `huge_only` reserves a kind for cycle-finale nights only;
# `tough` enemies are weighted up on huge nights.
const ENEMY_POOL := [
	{"id": "mote",      "min_cycle": 1, "w": 6, "cluster": 3},
	{"id": "crawler",   "min_cycle": 1, "w": 6},
	{"id": "husk",      "min_cycle": 1, "w": 3},
	{"id": "sprinter",  "min_cycle": 2, "w": 4},
	{"id": "shade",     "min_cycle": 2, "w": 3},
	{"id": "brute",     "min_cycle": 2, "w": 3, "tough": true},
	{"id": "gnasher",   "min_cycle": 2, "w": 3},
	{"id": "ravager",   "min_cycle": 3, "w": 3, "tough": true},
	{"id": "behemoth",  "min_cycle": 3, "w": 2, "tough": true},
	{"id": "wraith",    "min_cycle": 3, "w": 2, "tough": true},
	{"id": "dread",     "min_cycle": 4, "w": 2, "tough": true},
	{"id": "nightmare", "min_cycle": 3, "w": 2, "tough": true, "huge_only": true},
]

# --- Exponential wave growth (count + HP rise with global progress) ---
const COUNT_BASE := 3.0
const COUNT_GROWTH := 1.13     # per-day multiplier on swarm size
const HP_GROWTH := 1.06        # per-day multiplier on enemy HP
const HUGE_COUNT_MULT := 4.0   # cycle-finale nights are a wall of bodies
const HUGE_HP_MULT := 1.4
const MAX_PER_LANE := 60       # safety cap so the swarm can't melt the frame rate
const MAX_TOTAL := 280         # hard ceiling on enemies alive-spawned per wave
const DAYS_PER_CYCLE := 15


func _enter_tree() -> void:
	add_to_group("tide_manager")


func _ready() -> void:
	_gs = get_tree().get_first_node_in_group("game_state")
	_wm = get_tree().get_first_node_in_group("world_manager")
	_tree = get_tree().get_first_node_in_group("world_tree")
	if _gs:
		_gs.assault_started.connect(_on_assault)
		_gs.dawn_broke.connect(_on_dawn)


func is_wave_active() -> bool:
	return _wave_active


func _on_assault(day: int, tower_count: int, is_huge: bool) -> void:
	_night_cycle(day, tower_count, is_huge)


func _on_dawn() -> void:
	# Player greeted the dawn (day already rolled over) -> workers head back out.
	_send_workers_to_work()


func _night_cycle(day: int, tower_count: int, is_huge: bool) -> void:
	if _wave_active:
		return
	_wave_active = true

	# 1. send workers home, one by one per worksite
	_send_workers_home()
	var waited := 0.0
	while not _all_workers_home() and waited < home_timeout:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2

	# 2. a held breath, then the Dark comes
	await get_tree().create_timer(spawn_delay).timeout
	await _spawn_and_wait(day, tower_count, is_huge)

	# 3. the wave is cleared — a short beat, then hand control back to the player.
	#    The day no longer rolls over automatically: they must press Advance to
	#    greet the dawn (which sends the workers back out via _on_dawn).
	await get_tree().create_timer(dawn_delay).timeout
	_wave_active = false
	if _gs:
		_gs.mark_night_resolved()


func _spawn_and_wait(day: int, tower_count: int, is_huge: bool) -> void:
	var lanes: Array = _wm.get_lane_paths() if _wm else []
	var n: int = mini(tower_count, lanes.size())
	var cyc: int = _gs.cycle if _gs else 1
	# Global day index drives exponential growth: cycle 1 day 1 = 1, and it only
	# climbs from there — the cycle finale (day 15) is a deliberate spike.
	var p: int = (cyc - 1) * DAYS_PER_CYCLE + day
	var per_lane: int = int(round(COUNT_BASE * pow(COUNT_GROWTH, float(p - 1))))
	var hp_scale: float = pow(HP_GROWTH, float(p - 1))
	if is_huge:
		per_lane = int(round(float(per_lane) * HUGE_COUNT_MULT))
		hp_scale *= HUGE_HP_MULT
	per_lane = mini(per_lane, MAX_PER_LANE)

	var spawned: int = 0
	for i in per_lane:
		for li in range(n):
			if spawned >= MAX_TOTAL:
				break
			var entry: Dictionary = _pick_entry(cyc, is_huge)
			var cluster: int = entry.get("cluster", 1)
			for c in range(cluster):
				if spawned >= MAX_TOTAL:
					break
				_spawn_enemy(li, entry["id"], hp_scale)
				spawned += 1
		await get_tree().create_timer(spawn_interval).timeout
		if spawned >= MAX_TOTAL:
			break

	while get_tree().get_nodes_in_group("enemy").size() > 0:
		if _tree and _tree.is_heartroot_destroyed():
			break
		await get_tree().create_timer(0.3).timeout


func _send_workers_home() -> void:
	for ws in get_tree().get_nodes_in_group("worksite"):
		if not ws.has_method("get_workers"):
			continue
		var i := 0
		for r in ws.get_workers():
			if is_instance_valid(r):
				r.release_in(i * worker_stagger)
				i += 1


func _send_workers_to_work() -> void:
	for hut in get_tree().get_nodes_in_group("housing"):
		if not hut.has_method("get_residents"):
			continue
		var i := 0
		for r in hut.get_residents():
			if is_instance_valid(r) and r.has_job():
				r.release_in(i * worker_stagger)
				i += 1
	var j := 0
	for r in get_tree().get_nodes_in_group("resident"):
		if is_instance_valid(r) and r.has_job() and not r.has_home():
			r.release_in(j * worker_stagger)
			j += 1


func _all_workers_home() -> bool:
	for r in get_tree().get_nodes_in_group("resident"):
		if is_instance_valid(r) and r.has_job() and r.has_method("is_home") and not r.is_home():
			return false
	return true


func _pick_entry(cyc: int, is_huge: bool) -> Dictionary:
	var total: int = 0
	var weights: Array = []
	for entry in ENEMY_POOL:
		if entry.get("min_cycle", 1) > cyc:
			continue
		if entry.get("huge_only", false) and not is_huge:
			continue
		var w: int = entry["w"]
		if is_huge and entry.get("tough", false):
			w *= 3   # huge nights lean on the heavy hitters
		weights.append({"entry": entry, "w": w})
		total += w
	if total <= 0:
		return ENEMY_POOL[1]   # crawler fallback
	var roll: int = randi() % total
	for ww in weights:
		roll -= ww["w"]
		if roll < 0:
			return ww["entry"]
	return ENEMY_POOL[1]


func _spawn_enemy(lane_index: int, kind: String, hp_scale: float) -> void:
	var info: Dictionary = _wm.get_lane_spawn(lane_index) if _wm else {"pos": Vector3.ZERO, "path": []}
	var path: Array = info.get("path", [])
	var e := enemy_scene.instantiate()
	e.set("kind", kind)
	e.set("hp_scale", hp_scale)
	add_child(e)
	e.global_position = info.get("pos", Vector3.ZERO)
	if e.has_method("set_path"):
		e.set_path(path.duplicate())
