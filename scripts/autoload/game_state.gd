extends Node
## Run state. Each day is a real-time TENDING phase (build + gather) lasting
## day_seconds. Resources tick in every tick_seconds. "Advance Day" summons that
## day's wave (ASSAULT); clearing every monster completes the day. A huge wave
## hits on the last day of the cycle.

signal day_changed(day: int, cycle: int)
signal phase_changed(phase: int)
signal produce()                                   # a gather tick (TENDING only, while time remains)
signal tending_tick(time_left: float)              # per-frame, for the HUD timer
signal assault_started(day: int, tower_count: int, is_huge: bool)
signal continent_changed(index: int)
signal night_resolved()                            # wave cleared, waiting for the player to greet dawn
signal dawn_broke()                                # player advanced from a resolved night into the new day

enum Phase { TENDING, ASSAULT }

const DAYS_PER_CYCLE := 15
const TOTAL_CONTINENTS := 7
const MAX_SPAWN_TOWERS := 4

@export var day_seconds: float = 120.0     # length of the build/gather window
@export var tick_seconds: float = 10.0     # how often resources pay out

var day: int = 1
var cycle: int = 1
var phase: int = Phase.TENDING
var continent_index: int = 0
var trees_crowned: int = 0
var _awaiting_dawn: bool = false   # ASSAULT, wave cleared, waiting for the dawn press

var _time_left: float = 0.0
var _tick_accum: float = 0.0


func _enter_tree() -> void:
	add_to_group("game_state")


func _ready() -> void:
	_time_left = day_seconds
	phase_changed.emit(phase)
	day_changed.emit(day, cycle)


func _process(delta: float) -> void:
	if phase != Phase.TENDING or _time_left <= 0.0:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_tick_accum += delta
	while _tick_accum >= tick_seconds:
		_tick_accum -= tick_seconds
		produce.emit()
	tending_tick.emit(_time_left)
	if _time_left <= 0.0:
		phase_changed.emit(phase)   # building/gathering now locked until the wave is summoned


func is_tending() -> bool:
	return phase == Phase.TENDING


func is_assault() -> bool:
	return phase == Phase.ASSAULT


func can_build() -> bool:
	return phase == Phase.TENDING and _time_left > 0.0


## Tower place/destroy/upgrade and hero relocation: allowed during the build
## window AND throughout the night, unlike everything else.
func can_manage_combat() -> bool:
	return (phase == Phase.TENDING and _time_left > 0.0) or phase == Phase.ASSAULT


func is_awaiting_dawn() -> bool:
	return _awaiting_dawn


func get_time_left() -> float:
	return _time_left


## The single "Advance" button. Day -> summon the wave. A resolved night -> dawn.
func request_advance() -> void:
	if phase == Phase.TENDING:
		summon_wave()
	elif phase == Phase.ASSAULT and _awaiting_dawn:
		complete_day()


## "Advance Day" -> summon this day's wave.
func summon_wave() -> void:
	if phase != Phase.TENDING:
		return
	_awaiting_dawn = false
	phase = Phase.ASSAULT
	var is_huge: bool = day >= DAYS_PER_CYCLE
	var tower_count: int = MAX_SPAWN_TOWERS if is_huge else mini(day, MAX_SPAWN_TOWERS)
	phase_changed.emit(phase)
	assault_started.emit(day, tower_count, is_huge)


## Called by the TideManager once the wave is cleared. The day no longer rolls
## over on its own — the player must press Advance again to greet the dawn.
func mark_night_resolved() -> void:
	if phase == Phase.ASSAULT and not _awaiting_dawn:
		_awaiting_dawn = true
		night_resolved.emit()


## Greet the dawn: roll the day over (only valid once the night is resolved).
func complete_day() -> void:
	if phase != Phase.ASSAULT:
		return
	_awaiting_dawn = false
	if day >= DAYS_PER_CYCLE:
		cycle += 1
		day = 1
	else:
		day += 1
	phase = Phase.TENDING
	_time_left = day_seconds
	_tick_accum = 0.0
	phase_changed.emit(phase)
	day_changed.emit(day, cycle)
	dawn_broke.emit()


func crown_tree() -> void:
	trees_crowned = min(trees_crowned + 1, TOTAL_CONTINENTS)
	if trees_crowned >= TOTAL_CONTINENTS:
		print("[Yggdrasil] Seven lights joined. The sun returns. Campaign complete.")
