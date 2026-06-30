extends Node3D
## Housing. A Wooden Hut houses generic settlers; upgrade it into a species hut
## (Elven Bower / Dwarven Hold / Human Lodge) for more capacity, single-species.
## Residents immigrate over time up to capacity. Assign them to harvesting huts.

const RESIDENT := preload("res://scenes/resident.tscn")
const WOODEN_CAP := 4
const SPECIES_CAP := {"human": 12, "elf": 12, "dwarf": 12}
const UPGRADE_COST := {"timber": 120, "stone": 80}
const NAMES := {"human": "Human Lodge", "elf": "Elven Bower", "dwarf": "Dwarven Hold"}

var species := "human"
var is_wooden := true

var _residents: Array = []
var _gs
var _roof_mat: StandardMaterial3D


func _enter_tree() -> void:
	add_to_group("housing")


func _ready() -> void:
	_gs = get_tree().get_first_node_in_group("game_state")
	add_child(_visual())
	_claim_starters()
	var attr = get_tree().get_first_node_in_group("attraction")
	if attr and attr.has_method("rehome_homeless"):
		attr.rehome_homeless()


func _visual() -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.8, 1.1)
	base.mesh = bm
	base.position.y = 0.4
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.45, 0.32, 0.2)
	base.material_override = bmat
	root.add_child(base)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 0.9
	rm.height = 0.6
	roof.mesh = rm
	roof.position.y = 1.1
	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = Color(0.35, 0.25, 0.15)
	roof.material_override = _roof_mat
	root.add_child(roof)
	return root


func capacity() -> int:
	return WOODEN_CAP if is_wooden else int(SPECIES_CAP.get(species, 4))


func _prune() -> void:
	_residents = _residents.filter(func(x): return is_instance_valid(x))


func resident_count() -> int:
	_prune()
	return _residents.size()


func get_residents() -> Array:
	_prune()
	return _residents


func _accept_resident(r) -> void:
	_residents.append(r)
	if r.has_method("set_home"):
		r.set_home(self)


func assigned_count() -> int:
	_prune()
	var n := 0
	for r in _residents:
		if r.has_job():
			n += 1
	return n


func has_room_for(sp: String) -> bool:
	_prune()
	if _residents.size() >= capacity():
		return false
	return is_wooden or species == sp


func add_resident(sp: String, identity: Dictionary = {}) -> bool:
	if not has_room_for(sp):
		return false
	var r := RESIDENT.instantiate()
	r.setup(sp, self)
	add_child(r)
	r.global_position = global_position
	if r.has_method("init_identity"):
		var g: String = identity.get("gender", Folk.roll_gender())
		var tr: String = identity.get("trait", Folk.roll_trait(g))
		var f: int = int(identity.get("faith", 1))
		var nm: String = String(identity.get("name", ""))
		r.init_identity(g, tr, f, nm)
	_residents.append(r)
	return true


## The first housing hut built takes in the homeless starting settlers
## (2 humans + 2 elves), regardless of species, up to capacity.
func _claim_starters() -> void:
	if get_tree().get_nodes_in_group("housing").size() != 1:
		return
	for r in get_tree().get_nodes_in_group("resident"):
		if _residents.size() >= capacity():
			break
		if is_instance_valid(r) and r.has_method("has_home") and not r.has_home():
			r.set_home(self)
			_residents.append(r)


## Player choice: turn a Wooden Hut into a species hut.
func upgrade_into(sp: String, bank) -> bool:
	if not is_wooden or not SPECIES_CAP.has(sp):
		return false
	if bank and not bank.spend_many(UPGRADE_COST):
		return false
	species = sp
	is_wooden = false
	if _roof_mat:
		var d := {"human": Color(0.3, 0.5, 0.9), "elf": Color(0.3, 0.82, 0.45), "dwarf": Color(0.85, 0.55, 0.28)}
		_roof_mat.albedo_color = d.get(sp, Color.WHITE)
	_prune()
	var keep: Array = []
	for r in _residents:
		if not is_instance_valid(r):
			continue
		if r.species_key == sp:
			keep.append(r)
		else:
			_displace(r)
	_residents = keep
	# Newly opened species slots should pull in homeless settlers of that species.
	var attr = get_tree().get_first_node_in_group("attraction")
	if attr and attr.has_method("rehome_homeless"):
		attr.rehome_homeless()
	return true


## Move a mismatched resident to another hut of its species, else make homeless.
func _displace(r) -> void:
	for h in get_tree().get_nodes_in_group("housing"):
		if h == self:
			continue
		if h.has_method("has_room_for") and h.has_room_for(r.species_key) and h.has_method("_accept_resident"):
			h._accept_resident(r)
			return
	if r.has_method("go_homeless"):
		r.go_homeless()


func get_display_name() -> String:
	return "Wooden Hut" if is_wooden else String(NAMES.get(species, "Hut"))


func get_info() -> String:
	return "%s\nResidents %d / %d   (%d working)" % [
		get_display_name(), resident_count(), capacity(), assigned_count()
	]


func can_become() -> bool:
	return is_wooden


func get_become_cost() -> Dictionary:
	return UPGRADE_COST
