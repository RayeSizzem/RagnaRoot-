extends Node3D
## A harvestable node holding a finite amount. Trees yield wood (timber / soft_wood
## / hard_wood); rocks yield minerals (stone / gold / ruby / diamond). An optional
## tint recolours the model (used for the coloured mineral rocks). Huts deplete it;
## it removes itself when empty.

@export var model_scale: float = 0.3

const WOOD := ["timber", "soft_wood", "hard_wood"]

var resource_type: String = "timber"
var amount: int = 500
var _model_scene: PackedScene
var _tint = null   # Color or null


func _enter_tree() -> void:
	add_to_group("resource_node")


func setup(rtype: String, amt: int, model: PackedScene, tint = null) -> void:
	resource_type = rtype
	amount = amt
	_model_scene = model
	_tint = tint


func _ready() -> void:
	if _model_scene:
		var m := _model_scene.instantiate()
		add_child(m)
		if m is Node3D:
			(m as Node3D).scale = Vector3.ONE * model_scale
		if _tint != null:
			_apply_tint(m, _tint)


## Recolour every mesh in the model (used for mineral rocks / fallback tree types).
func _apply_tint(root: Node, col: Color) -> void:
	if root is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		if resource_type == "gold" or resource_type == "diamond":
			mat.metallic = 0.6
			mat.roughness = 0.3
			mat.emission_enabled = true
			mat.emission = col * 0.25
		(root as MeshInstance3D).material_override = mat
	for c in root.get_children():
		_apply_tint(c, col)


func harvest(n: int) -> int:
	var g: int = min(n, amount)
	amount -= g
	if amount <= 0:
		queue_free()
	return g


func is_depleted() -> bool:
	return amount <= 0


func get_type() -> String:
	return resource_type


func get_family() -> String:
	return "wood" if WOOD.has(resource_type) else "mineral"
