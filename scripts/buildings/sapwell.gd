extends Node3D
## Sapwell: channels Sap into the tree once per day (turn-based). Base 5 sap/day,
## upgrades 4 times up to 60 sap/day. Count capped by BuildSystem (1, +1 per tree
## stage, max 4). Tune SAP_PER_DAY for balance.

const SAP_PER_DAY := [5, 10, 20, 35, 60]
const MAX_LEVEL := 4
const UPGRADE_COST := [
	{"timber": 100, "stone": 50},
	{"timber": 150, "stone": 100},
	{"timber": 200, "stone": 150},
	{"timber": 300, "stone": 200},
]

@export var building_model: PackedScene

var level: int = 0
var _bank


func _enter_tree() -> void:
	add_to_group("sapwell")


func _ready() -> void:
	_bank = get_tree().get_first_node_in_group("resource_bank")
	var gs = get_tree().get_first_node_in_group("game_state")
	if gs:
		gs.produce.connect(_on_day)
	_spawn_visual()


func _spawn_visual() -> void:
	if building_model:
		add_child(building_model.instantiate())
	else:
		add_child(_placeholder())


func _placeholder() -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.6
	cyl.height = 0.8
	base.mesh = cyl
	base.position.y = 0.4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.6, 0.2)
	base.material_override = mat
	root.add_child(base)
	return root


func _on_day() -> void:
	if _bank:
		_bank.add("sap", SAP_PER_DAY[level])


func get_sap_per_day() -> int:
	return SAP_PER_DAY[level]


func get_display_name() -> String:
	return "Sapwell"


func get_info() -> String:
	return "Sapwell  Lv %d   (%d sap/10s)" % [level + 1, SAP_PER_DAY[level]]


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
