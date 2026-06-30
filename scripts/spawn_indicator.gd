extends Node3D
## Marks where the coming wave will emerge: a small red downward triangle that
## bobs slowly over each lane that will spawn monsters THIS wave (shown only during
## the build phase). Active lanes are indices 0..tower_count-1, where tower_count =
## min(day, 4) (or 4 on a huge night) — lane 0 from day 1, lane 1 from day 2, etc.

const MAX_LANES := 4

var _gs
var _wm
var _beacons: Array = []
var _t: float = 0.0
var _active: int = 0


func _enter_tree() -> void:
	add_to_group("spawn_indicator")


func _ready() -> void:
	_gs = get_tree().get_first_node_in_group("game_state")
	_wm = get_tree().get_first_node_in_group("world_manager")
	for i in range(MAX_LANES):
		_beacons.append(_make_beacon())
	if _gs:
		_gs.phase_changed.connect(_refresh.unbind(1))
		_gs.day_changed.connect(_refresh.unbind(2))
		if _gs.has_signal("night_resolved"):
			_gs.night_resolved.connect(_refresh)
	_refresh()


func _make_beacon() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var tri := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 0.0   # apex at the bottom -> points downward
	cone.height = 0.7
	cone.radial_segments = 3   # 3 sides -> reads as a triangle
	tri.mesh = cone
	tri.position.y = 1.6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.95, 0.15, 0.13)
	# Draw over the fog: put it in the transparent pass with a higher priority than
	# the fog sheet (priority 0) and skip depth test, so distance/fog never bury it.
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 12
	m.no_depth_test = true
	tri.material_override = m
	root.add_child(tri)
	return {"root": root, "tri": tri}


func _upcoming_count() -> int:
	if _gs == null:
		return 0
	var is_huge: bool = _gs.day >= _gs.DAYS_PER_CYCLE
	if is_huge:
		return int(_gs.MAX_SPAWN_TOWERS)
	return mini(int(_gs.day), int(_gs.MAX_SPAWN_TOWERS))


func _refresh() -> void:
	# Only while the player can still prepare (build phase).
	var show_now: bool = _gs != null and _gs.is_tending()
	_active = _upcoming_count() if show_now else 0
	for i in range(_beacons.size()):
		_beacons[i]["root"].visible = show_now and i < _active


func _process(delta: float) -> void:
	if _active <= 0 or _wm == null:
		return
	_t += delta
	var bob: float = sin(_t * 1.6) * 0.25   # slow up/down bob
	for i in range(_active):
		if i >= _beacons.size():
			break
		var info: Dictionary = _wm.get_lane_spawn(i)
		var pos: Vector3 = info.get("frontier", info.get("pos", Vector3.ZERO))
		var b: Dictionary = _beacons[i]
		b["root"].global_position = Vector3(pos.x, 0.0, pos.z)
		b["tri"].position.y = 1.6 + bob
		b["tri"].rotation.y = _t * 1.3   # slow spin
