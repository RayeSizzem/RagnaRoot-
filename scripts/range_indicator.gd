extends Node3D
## Shows a ground ring for the currently selected unit's range: towers (attack),
## heroes (engagement/aggro), harvest huts (gather radius). Follows the unit if it
## moves, recolours by type, and hides when nothing applicable is selected.

var _bs
var _selected
var _disc: MeshInstance3D
var _ring: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D


func _enter_tree() -> void:
	add_to_group("range_indicator")


func _ready() -> void:
	_bs = get_tree().get_first_node_in_group("build_system")
	if _bs:
		_bs.building_selected.connect(_on_selected)
		_bs.selection_cleared.connect(_on_cleared)
	_build()
	visible = false


func _build() -> void:
	_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.02
	cyl.radial_segments = 48
	_disc.mesh = cyl
	_disc.position.y = 0.25
	_fill_mat = _mk_mat()
	_disc.material_override = _fill_mat
	add_child(_disc)

	_ring = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.95
	tor.outer_radius = 1.0
	tor.rings = 64
	_ring.mesh = tor
	_ring.position.y = 0.28
	_ring_mat = _mk_mat()
	_ring.material_override = _ring_mat
	add_child(_ring)


func _mk_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1, 1, 1, 0.2)
	return m


func _on_selected(unit) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.has_method("get_range"):
		_clear()
		return
	_selected = unit
	var r: float = unit.get_range()
	_disc.scale = Vector3(r, 1.0, r)
	_ring.scale = Vector3(r, 1.0, r)
	var col := _color_for(unit)
	_fill_mat.albedo_color = Color(col.r, col.g, col.b, 0.08)
	_ring_mat.albedo_color = Color(col.r, col.g, col.b, 0.6)
	global_position = unit.global_position
	visible = true


func _color_for(unit) -> Color:
	if unit.is_in_group("tower"):
		return Color(1.0, 0.4, 0.3)
	if unit.is_in_group("hero"):
		return Color(1.0, 0.85, 0.3)
	return Color(0.4, 0.9, 0.5)


func _on_cleared() -> void:
	_clear()


func _clear() -> void:
	_selected = null
	visible = false


func _process(_dt: float) -> void:
	if not visible:
		return
	if _selected and is_instance_valid(_selected):
		global_position = _selected.global_position
	else:
		_clear()
