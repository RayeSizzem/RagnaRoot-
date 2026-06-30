extends Node
## Smoothly shifts the world toward a cool, dimmer moonlit look during the ASSAULT
## (combat) phase and back to bright day during TENDING. Drives the directional Sun
## and the WorldEnvironment ambient/background by lerping a single day<->night value.

@export var transition_speed: float = 1.2   # higher = faster blend (units/sec)

# Day endpoints (match the scene's authored values).
const DAY_SUN_ENERGY := 0.95
const DAY_SUN_COLOR := Color(0.93, 0.94, 0.98)
const DAY_AMB_COLOR := Color(0.82, 0.86, 0.93)
const DAY_AMB_ENERGY := 1.25
const DAY_BG := Color(0.1, 0.11, 0.14)
# Night endpoints (moonlit: dimmer, blue tinge).
const NIGHT_SUN_ENERGY := 0.4
const NIGHT_SUN_COLOR := Color(0.55, 0.66, 1.0)
const NIGHT_AMB_COLOR := Color(0.28, 0.36, 0.6)
const NIGHT_AMB_ENERGY := 0.6
const NIGHT_BG := Color(0.03, 0.04, 0.09)

var _gs: Node
var _sun: DirectionalLight3D
var _env: Environment
var _t := 0.0        # 0 = day, 1 = night
var _target := 0.0


func _ready() -> void:
	var root := get_parent()
	_gs = get_tree().get_first_node_in_group("game_state")
	if _gs == null and root:
		_gs = root.get_node_or_null("GameState")
	if root:
		_sun = root.get_node_or_null("Sun")
		var we: WorldEnvironment = root.get_node_or_null("WorldEnvironment")
		if we and we.environment:
			_env = we.environment
	if _gs and _gs.has_signal("phase_changed"):
		_gs.phase_changed.connect(_on_phase.unbind(1))
		_on_phase()
	_apply(_t)


func _on_phase() -> void:
	if _gs == null:
		return
	var tending: bool = _gs.has_method("is_tending") and _gs.is_tending()
	_target = 0.0 if tending else 1.0


func _process(delta: float) -> void:
	if absf(_t - _target) < 0.0005:
		return
	_t = move_toward(_t, _target, transition_speed * delta)
	_apply(_t)


func _apply(t: float) -> void:
	if _sun:
		_sun.light_energy = lerpf(DAY_SUN_ENERGY, NIGHT_SUN_ENERGY, t)
		_sun.light_color = DAY_SUN_COLOR.lerp(NIGHT_SUN_COLOR, t)
	if _env:
		_env.ambient_light_color = DAY_AMB_COLOR.lerp(NIGHT_AMB_COLOR, t)
		_env.ambient_light_energy = lerpf(DAY_AMB_ENERGY, NIGHT_AMB_ENERGY, t)
		_env.background_color = DAY_BG.lerp(NIGHT_BG, t)
