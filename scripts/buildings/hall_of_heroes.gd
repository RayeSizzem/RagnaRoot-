extends Node3D
## Hall of Heroes. Grants one hero slot per World Tree stage. A warrior who has
## trained to mastery (trait-5 + faith-5) can be PROMOTED here into a hero, at the
## cost of Holy Light — for now a placeholder paid in night's Essence until the
## Arcane Spire (Phase E) supplies real Holy Light. The old "forge for resources"
## path is gone: heroes now come only from your own veteran warriors.

const HERO := preload("res://scenes/hero.tscn")

@export var base_slots: int = 1

var _tree


func _enter_tree() -> void:
	add_to_group("hall")


func _ready() -> void:
	_tree = get_tree().get_first_node_in_group("world_tree")
	add_child(_visual())


func _visual() -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.7, 1.2, 1.7)
	base.mesh = bm
	base.position.y = 0.6
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.42, 0.38, 0.52)
	base.material_override = bmat
	root.add_child(base)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 1.35
	rm.height = 0.9
	roof.mesh = rm
	roof.position.y = 1.65
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.82, 0.66, 0.26)
	rmat.emission_enabled = true
	rmat.emission = Color(0.5, 0.4, 0.15)
	roof.material_override = rmat
	root.add_child(roof)
	return root


func capacity() -> int:
	var stage: int = _tree.stage if _tree else 0
	return base_slots + stage


func hero_count() -> int:
	return get_tree().get_nodes_in_group("hero").size()


func has_slot() -> bool:
	return hero_count() < capacity()


## Warriors who have trained to full mastery and are ready to ascend.
func eligible_warriors() -> Array:
	var out: Array = []
	for r in get_tree().get_nodes_in_group("resident"):
		if not is_instance_valid(r):
			continue
		if r.trait_key == "warrior" and int(r.faith) >= Folk.MAX_FAITH and int(r.trait_level) >= Folk.MAX_TRAIT_LEVEL:
			out.append(r)
	return out


## Holy Light cost to promote a warrior into a hero (channeled at the Arcane Spire).
func get_promote_cost() -> Dictionary:
	return {"holy_light": 100}


## Promote a mastered warrior into a hero: spend the cost, consume the settler,
## and raise a hero of the same lineage beside the Hall.
func promote(r) -> bool:
	if r == null or not is_instance_valid(r) or not has_slot():
		return false
	if r.trait_key != "warrior" or int(r.faith) < Folk.MAX_FAITH or int(r.trait_level) < Folk.MAX_TRAIT_LEVEL:
		return false
	var bank = get_tree().get_first_node_in_group("resource_bank")
	if bank and not bank.spend_many(get_promote_cost()):
		return false
	var sp: String = r.species_key
	if r.has_method("clear_job"):
		r.clear_job()
	r.queue_free()
	var h := HERO.instantiate()
	h.species_key = sp
	get_parent().add_child(h)
	var off := Vector3(randf_range(-1.6, 1.6), 0.0, 2.4)
	h.global_position = global_position + Vector3(off.x, 0.0, off.z)
	if h.has_method("set_post"):
		h.set_post(h.global_position)
	return true


func get_display_name() -> String:
	return "Hall of Heroes"


func get_info() -> String:
	return "Hall of Heroes\nHeroes %d / %d   (1 slot per tree stage)\nPromote a mastered warrior (cost %d Holy Light)" % [
		hero_count(), capacity(), int(get_promote_cost().get("holy_light", 0))
	]


func get_upgrade_cost() -> Dictionary:
	return {}


func try_upgrade(_bank) -> bool:
	return false
