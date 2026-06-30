extends Node3D
## The World Tree. Grows by drawing banked Sap each day (capped), leaving surplus
## sap available for expansion (fog clearing). Crowning produces the Seed.

signal stage_changed(stage: int, stage_name: String)
signal sap_progress_changed(current: int, needed: int)
signal crowned()
signal heartroot_changed(hp: int, max_hp: int)
signal heartroot_destroyed()

enum Stage { SAPLING, SENTINEL, GREATBOUGH, CANOPY, WORLDCROWN }

const STAGE_NAMES := ["Sapling", "Sentinel", "Greatbough", "Canopy", "Worldcrown"]
const STAGE_THRESHOLDS := [100, 250, 500, 900, 1500]
const STAGE_SCALE := [0.5, 1.0, 1.8, 2.8, 4.0]

@export var twisted_tree_model: PackedScene = preload("res://environment/TwistedTree_4.gltf")
@export var heartroot_max_hp: int = 100
@export var footprint_radius: float = 1.5

var stage: int = Stage.SAPLING
var sap_into_tree: int = 0
var heartroot_hp: int = 100


@onready var _holder: Node3D = $ModelHolder


func _enter_tree() -> void:
	add_to_group("world_tree")


func _ready() -> void:
	heartroot_hp = heartroot_max_hp
	_spawn_model()
	_apply_stage_visual()
	stage_changed.emit(stage, STAGE_NAMES[stage])
	sap_progress_changed.emit(sap_into_tree, STAGE_THRESHOLDS[stage])
	heartroot_changed.emit(heartroot_hp, heartroot_max_hp)


func _spawn_model() -> void:
	for c in _holder.get_children():
		c.queue_free()
	if twisted_tree_model:
		_holder.add_child(twisted_tree_model.instantiate())
	else:
		_holder.add_child(_make_placeholder())


func _make_placeholder() -> Node3D:
	var root := Node3D.new()
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.15
	tm.bottom_radius = 0.25
	tm.height = 1.5
	trunk.mesh = tm
	trunk.position.y = 0.75
	root.add_child(trunk)
	var canopy := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.8
	sm.height = 1.6
	canopy.mesh = sm
	canopy.position.y = 1.9
	root.add_child(canopy)
	return root


func channel_sap(amount: int) -> void:
	if stage >= Stage.WORLDCROWN:
		return
	sap_into_tree += amount
	var needed: int = STAGE_THRESHOLDS[stage]
	while sap_into_tree >= needed and stage < Stage.WORLDCROWN:
		sap_into_tree -= needed
		_advance_stage()
		needed = STAGE_THRESHOLDS[stage]
	sap_progress_changed.emit(sap_into_tree, STAGE_THRESHOLDS[stage])


func _advance_stage() -> void:
	stage += 1
	_apply_stage_visual()
	stage_changed.emit(stage, STAGE_NAMES[stage])
	if stage == Stage.WORLDCROWN:
		crowned.emit()


func _apply_stage_visual() -> void:
	var s: float = STAGE_SCALE[stage]
	_holder.scale = Vector3(s, s, s)


func damage_heartroot(amount: int) -> void:
	heartroot_hp = max(heartroot_hp - amount, 0)
	heartroot_changed.emit(heartroot_hp, heartroot_max_hp)
	if heartroot_hp == 0:
		heartroot_destroyed.emit()
		push_warning("[Yggdrasil] The Heartroot has fallen. The light goes out.")


## Restore Heartroot HP (Holy Light mending). Returns HP actually healed.
func heal_heartroot(amount: int) -> int:
	if heartroot_hp <= 0:
		return 0
	var before: int = heartroot_hp
	heartroot_hp = min(heartroot_hp + amount, heartroot_max_hp)
	var healed: int = heartroot_hp - before
	if healed > 0:
		heartroot_changed.emit(heartroot_hp, heartroot_max_hp)
	return healed


func heartroot_missing() -> int:
	return heartroot_max_hp - heartroot_hp


func is_heartroot_destroyed() -> bool:
	return heartroot_hp <= 0


func get_max_footprint_radius() -> float:
	return footprint_radius * STAGE_SCALE[STAGE_SCALE.size() - 1]


func get_trunk_radius() -> float:
	return footprint_radius * STAGE_SCALE[stage]


func get_stage_name() -> String:
	return STAGE_NAMES[stage]


func get_sap_needed() -> int:
	return STAGE_THRESHOLDS[stage]


func is_crowned() -> bool:
	return stage >= Stage.WORLDCROWN
