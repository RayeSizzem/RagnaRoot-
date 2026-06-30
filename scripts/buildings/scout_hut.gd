extends Node3D
## Scout Hut. Clearing fog (from its selection panel) lets the player CHOOSE which
## dark block to reveal — but only blocks touching already-cleared land. Each block
## costs 200 timber, 200 stone, 500 sap.

const FOG_COST := {"timber": 200, "stone": 200, "sap": 500}


func _enter_tree() -> void:
	add_to_group("scout_hut")


func _ready() -> void:
	add_child(_make_visual())


func _make_visual() -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.8, 0.8)
	base.mesh = bm
	base.position.y = 0.4
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.75, 0.78, 0.85)
	base.material_override = bmat
	root.add_child(base)
	var mast := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 1.6
	mast.mesh = cyl
	mast.position.y = 1.5
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.9, 0.9, 0.95)
	mmat.emission_enabled = true
	mmat.emission = Color(0.6, 0.8, 1.0)
	mast.material_override = mmat
	root.add_child(mast)
	return root


func get_display_name() -> String:
	return "Scout Hut"


func get_info() -> String:
	return "Scout Hut   (choose a dark block touching cleared land)"


func get_fog_cost() -> Dictionary:
	return FOG_COST


func clear_fog(bank, wm) -> bool:
	if bank == null or wm == null:
		return false
	if not bank.can_afford(FOG_COST):
		return false
	if wm.reveal_nearest(global_position):
		bank.spend_many(FOG_COST)
		return true
	return false
