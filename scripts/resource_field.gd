extends Node3D
## Scatters tree (timber) and rock (stone) nodes around the outer ring, avoiding
## lanes. Provides cell-blocking, nearest-node lookup, and adjacency checks.

const NODE := preload("res://scenes/resource_node.tscn")
const TREES := [
	preload("res://environment/CommonTree_1.gltf"),
	preload("res://environment/CommonTree_2.gltf"),
	preload("res://environment/CommonTree_3.gltf"),
	preload("res://environment/CommonTree_4.gltf"),
	preload("res://environment/CommonTree_5.gltf"),
]
const ROCKS := [
	preload("res://environment/Rock_Medium_1.gltf"),
	preload("res://environment/Rock_Medium_2.gltf"),
	preload("res://environment/Rock_Medium_3.gltf"),
]

@export var tile_size: float = 2.0
@export var edge_inner_cells: int = 8   # square frame: keep nodes near the rim
@export var edge_outer_cells: int = 10  # map edge (40x40 ground -> +/-10 cells)
@export var tree_count: int = 90
@export var rock_count: int = 90
@export var min_amount: int = 300
@export var max_amount: int = 700

var _cells := {}        # Vector2i -> node
var _paths


func _enter_tree() -> void:
	add_to_group("resource_field")


func _ready() -> void:
	_paths = get_tree().get_first_node_in_group("path_system")
	_scatter("timber", TREES, tree_count)
	_scatter("stone", ROCKS, rock_count)


func _scatter(rtype: String, models: Array, count: int) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 30:
		attempts += 1
		var cell := _random_ring_cell()
		if _cells.has(cell):
			continue
		if _paths and _paths.is_path_cell(cell):
			continue
		var n := NODE.instantiate()
		var amt := randi_range(min_amount, max_amount)
		var model: PackedScene = models[randi() % models.size()]
		n.setup(rtype, amt, model)
		add_child(n)
		n.position = Vector3(cell.x * tile_size, 0.0, cell.y * tile_size)
		_cells[cell] = n
		placed += 1


func _random_ring_cell() -> Vector2i:
	# sample inside a square frame so edges and corners are filled evenly
	for _i in range(40):
		var x := randi_range(-edge_outer_cells, edge_outer_cells)
		var y := randi_range(-edge_outer_cells, edge_outer_cells)
		if max(abs(x), abs(y)) >= edge_inner_cells:
			return Vector2i(x, y)
	return Vector2i(edge_outer_cells, edge_outer_cells)


func is_node_cell(cell: Vector2i) -> bool:
	if _cells.has(cell):
		var n = _cells[cell]
		if is_instance_valid(n):
			return true
		_cells.erase(cell)
	return false


func has_resource_near(cell: Vector2i, rtype: String, cell_range: int) -> bool:
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n) or n.get_type() != rtype or n.is_depleted():
			continue
		var nc := Vector2i(
			roundi(n.global_position.x / tile_size),
			roundi(n.global_position.z / tile_size)
		)
		if max(abs(nc.x - cell.x), abs(nc.y - cell.y)) <= cell_range:
			return true
	return false


func find_nearest_node(pos: Vector3, rtype: String, rng: float):
	var best = null
	var best_d := rng * rng
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n) or n.get_type() != rtype or n.is_depleted():
			continue
		var d := pos.distance_squared_to(n.global_position)
		if d <= best_d:
			best_d = d
			best = n
	return best
