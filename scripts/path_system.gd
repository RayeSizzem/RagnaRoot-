extends Node3D
## Four winding lanes from the edge to the root, built as 4-connected cell paths:
## every cell shares an EDGE with the next/previous one (never a corner), so the
## road never forms diagonal hops or 2x2 blobs. Enemies follow the cell centres.

@export var tile_size: float = 2.0
@export var spawn_distance: float = 20.0
@export var amplitude: float = 4.0
@export var frequency: float = 0.55
@export var path_color: Color = Color(0.32, 0.24, 0.16)

var _lane_paths: Array = []      # Array of Array[Vector3], edge -> centre
var _path_cells := {}            # Vector2i -> true


func _enter_tree() -> void:
	add_to_group("path_system")


func _ready() -> void:
	_build_lanes()
	_draw_paths()


func _build_lanes() -> void:
	var m_max := int(round(spawn_distance / tile_size))
	var amp_cells := amplitude / tile_size
	# [main axis index (0=x,1=y), sign] for East, West, South, North
	var lanes := [[0, 1], [0, -1], [1, 1], [1, -1]]
	for lane_def in lanes:
		var axis: int = lane_def[0]
		var sgn: int = lane_def[1]
		var perp := 1 - axis
		var cells: Array = []
		var cur := _with_comp(Vector2i.ZERO, axis, sgn * m_max)   # edge, on-axis
		cells.append(cur)
		var main := m_max - 1
		while main >= 0:
			var t := float(main) * tile_size
			# envelope is 0 at both ends so spawn is on-axis and the lane reaches centre
			var env := sin(PI * float(main) / float(m_max))
			var desired := int(round(amp_cells * env * sin(frequency * t)))
			var cur_lat := _get_comp(cur, perp)
			# move sideways one cell at a time first (orthogonal steps only)
			while cur_lat != desired:
				var s := signi(desired - cur_lat)
				cur = _with_comp(cur, perp, cur_lat + s)
				cells.append(cur)
				cur_lat += s
			# then step one cell inward
			cur = _with_comp(cur, axis, sgn * main)
			cells.append(cur)
			main -= 1
		_register_lane(cells)


func _register_lane(cells: Array) -> void:
	var pts: Array = []
	for c in cells:
		var cell: Vector2i = c
		_path_cells[cell] = true
		pts.append(Vector3(cell.x * tile_size, 0.0, cell.y * tile_size))
	_lane_paths.append(pts)


func _get_comp(v: Vector2i, idx: int) -> int:
	return v.x if idx == 0 else v.y


func _with_comp(v: Vector2i, idx: int, val: int) -> Vector2i:
	if idx == 0:
		return Vector2i(val, v.y)
	return Vector2i(v.x, val)


func is_path_cell(cell: Vector2i) -> bool:
	return _path_cells.has(cell)


func get_lane_paths() -> Array:
	return _lane_paths


func _draw_paths() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = path_color
	for cell in _path_cells.keys():
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(tile_size, tile_size)
		mi.mesh = q
		mi.material_override = mat
		mi.rotation.x = -PI / 2.0
		mi.position = Vector3(cell.x * tile_size, 0.03, cell.y * tile_size)
		add_child(mi)
