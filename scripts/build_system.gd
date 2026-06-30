extends Node3D
## Grid-snap placement around the World Tree.
## Blocks: occupied cells, the winding lanes, resource-node cells, the clear ring
## (full-grown tree footprint + a tile), unaffordable, and over a build cap.
## Left click places (when building) or selects a building (when not building).

signal buildings_changed()
signal building_selected(building)
signal selection_cleared()
signal world_tree_clicked()

@export var tile_size: float = 2.0
@export var half_extent_cells: int = 9
@export var tree_clear_radius_override: float = 0.0

var _occupied := {}                  # Vector2i -> Node3D
var _building_scene: PackedScene
var _cost := {}
var _limit := {}
var _requires := {}
var _props := {}
var _foot_offsets: Array = [Vector2i.ZERO]   # cells the building occupies, relative to anchor
var _foot_center := Vector2.ZERO             # bounding-box centre (cells) for placement/visual
var _build_ghost_root: Node3D
var _build_tiles: Array = []
var _build_tile_mat: StandardMaterial3D
var _build_mode := false
var _hero_mode := false
var _hero_species := ""
var _hero_cost := {}
var _fog_mode := false
var _fog_cost := {}
var _reloc_mode := false
var _reloc_hero = null
var _fog_ghost: MeshInstance3D
var _fog_ghost_mat: StandardMaterial3D
var _fog_marks: Node3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _buildings_root: Node3D

var _tree
var _paths
var _bank
var _field
var _wm
var _gs
var _clear_radius: float = 4.0

const HERO := preload("res://scenes/hero.tscn")
const _NO_HIT := Vector3.INF


func _ready() -> void:
	add_to_group("build_system")
	_tree = get_tree().get_first_node_in_group("world_tree")
	_paths = get_tree().get_first_node_in_group("path_system")
	_bank = get_tree().get_first_node_in_group("resource_bank")
	_field = get_tree().get_first_node_in_group("resource_field")
	_wm = get_tree().get_first_node_in_group("world_manager")
	_gs = get_tree().get_first_node_in_group("game_state")
	_clear_radius = tree_clear_radius_override
	if _clear_radius <= 0.0 and _tree and _tree.has_method("get_max_footprint_radius"):
		_clear_radius = _tree.get_max_footprint_radius() + tile_size
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)
	_make_ghost()
	_make_fog_ghost()
	_make_build_ghost()


func _make_build_ghost() -> void:
	# A pool of translucent tiles so any footprint shape (incl. the Temple's
	# T-tetromino) shows exactly the cells it will occupy.
	_build_ghost_root = Node3D.new()
	_build_ghost_root.visible = false
	add_child(_build_ghost_root)
	_build_tile_mat = StandardMaterial3D.new()
	_build_tile_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_build_tile_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.4)
	for i in range(8):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(tile_size * 0.9, 0.2, tile_size * 0.9)
		mi.mesh = bm
		mi.material_override = _build_tile_mat
		mi.visible = false
		_build_ghost_root.add_child(mi)
		_build_tiles.append(mi)


func _make_fog_ghost() -> void:
	# Block-sized highlight used while choosing which dark block to clear.
	var bs: float = 42.0
	if _wm and "BLOCK_SIZE" in _wm:
		bs = _wm.BLOCK_SIZE
	_fog_marks = Node3D.new()
	_fog_marks.name = "FogTargets"
	add_child(_fog_marks)
	_fog_ghost = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(bs * 0.94, bs * 0.94)
	_fog_ghost.mesh = pm
	_fog_ghost_mat = StandardMaterial3D.new()
	_fog_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fog_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fog_ghost_mat.no_depth_test = true
	_fog_ghost_mat.render_priority = 2
	_fog_ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.4)
	_fog_ghost.material_override = _fog_ghost_mat
	_fog_ghost.position.y = 0.2
	_fog_ghost.visible = false
	add_child(_fog_ghost)


func _make_ghost() -> void:
	_ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(tile_size * 0.9, 0.2, tile_size * 0.9)
	_ghost.mesh = bm
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.4)
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	add_child(_ghost)


## cost = {"timber":n,"stone":n}; limit = {} or {"group","base","per_stage","max"}
func toggle_build(scene: PackedScene, cost: Dictionary, limit: Dictionary = {}, requires: Dictionary = {}, props: Dictionary = {}, foot: Array = [1, 1], shape: Array = []) -> void:
	if _build_mode and _building_scene == scene:
		_cancel()
	else:
		_building_scene = scene
		_cost = cost
		_limit = limit
		_requires = requires
		_props = props
		_set_footprint(foot, shape)
		_build_mode = true
		_hero_mode = false
		_fog_mode = false
		_reloc_mode = false
		_ghost.visible = false
		_build_ghost_root.visible = true


## Define the footprint from either an explicit cell list (`shape`) or a w×d rect.
func _set_footprint(foot: Array, shape: Array) -> void:
	_foot_offsets = []
	if not shape.is_empty():
		for o in shape:
			_foot_offsets.append(Vector2i(int(o[0]), int(o[1])))
	else:
		var w: int = int(foot[0])
		var d: int = int(foot[1])
		for i in range(w):
			for j in range(d):
				_foot_offsets.append(Vector2i(i, j))
	var minx := 999
	var maxx := -999
	var miny := 999
	var maxy := -999
	for o in _foot_offsets:
		minx = mini(minx, o.x)
		maxx = maxi(maxx, o.x)
		miny = mini(miny, o.y)
		maxy = maxi(maxy, o.y)
	_foot_center = Vector2((minx + maxx) * 0.5, (miny + maxy) * 0.5)
	# lay out the ghost tiles for this shape
	for i in range(_build_tiles.size()):
		var on: bool = i < _foot_offsets.size()
		_build_tiles[i].visible = on
		if on:
			var off: Vector2i = _foot_offsets[i]
			_build_tiles[i].position = Vector3(off.x * tile_size, 0.1, off.y * tile_size)


func _footprint_cells(anchor: Vector2i) -> Array:
	var cells: Array = []
	for o in _foot_offsets:
		cells.append(anchor + o)
	return cells


func _footprint_center(anchor: Vector2i) -> Vector3:
	var w := _to_world(anchor)
	return Vector3(w.x + _foot_center.x * tile_size, 0.0, w.z + _foot_center.y * tile_size)


func _footprint_buildable(anchor: Vector2i) -> bool:
	for c in _footprint_cells(anchor):
		if not _cell_buildable(c):
			return false
	return true


func is_placing() -> bool:
	return _build_mode or _hero_mode or _fog_mode or _reloc_mode


func begin_hero_placement(species: String, cost: Dictionary) -> void:
	_build_mode = false
	_building_scene = null
	if _build_ghost_root:
		_build_ghost_root.visible = false
	_hero_mode = true
	_fog_mode = false
	_hero_species = species
	_hero_cost = cost
	_ghost.visible = true


func begin_fog_targeting(cost: Dictionary) -> void:
	_build_mode = false
	_building_scene = null
	if _build_ghost_root:
		_build_ghost_root.visible = false
	_hero_mode = false
	_ghost.visible = false
	_fog_mode = true
	_fog_cost = cost
	_fog_ghost.visible = true
	_rebuild_fog_marks()


func _rebuild_fog_marks() -> void:
	for c in _fog_marks.get_children():
		c.queue_free()
	if _wm == null or not _wm.has_method("revealable_blocks"):
		return
	var bs: float = _wm.BLOCK_SIZE if ("BLOCK_SIZE" in _wm) else 42.0
	for b in _wm.revealable_blocks():
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(bs * 0.96, bs * 0.96)
		mi.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.render_priority = 1
		mat.albedo_color = Color(0.45, 0.85, 1.0, 0.16)
		mi.material_override = mat
		mi.position = _wm.block_center(b) + Vector3(0, 0.16, 0)
		_fog_marks.add_child(mi)


func _clear_fog_marks() -> void:
	if _fog_marks:
		for c in _fog_marks.get_children():
			c.queue_free()


func _cancel() -> void:
	_build_mode = false
	_building_scene = null
	_hero_mode = false
	_fog_mode = false
	_reloc_mode = false
	_reloc_hero = null
	_ghost.visible = false
	if _build_ghost_root:
		_build_ghost_root.visible = false
	if _fog_ghost:
		_fog_ghost.visible = false
	_clear_fog_marks()


func _process(_delta: float) -> void:
	if _build_mode:
		_update_build_ghost()
	elif _hero_mode:
		_update_hero_ghost()
	elif _fog_mode:
		_update_fog_ghost()
	elif _reloc_mode:
		_update_reloc_ghost()


func _update_fog_ghost() -> void:
	var hit := _ground_point()
	if hit == _NO_HIT or _wm == null:
		_fog_ghost.visible = false
		return
	var b: Vector2i = _wm.world_to_block(hit)
	var c: Vector3 = _wm.block_center(b)
	_fog_ghost.position = Vector3(c.x, 0.2, c.z)
	var ok: bool = _wm.is_block_revealable(b) and _can_afford_fog() and _can_build_now()
	_fog_ghost.visible = _wm.is_block_revealable(b)
	_fog_ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.42) if ok else Color(1.0, 0.4, 0.35, 0.42)


func _can_afford_fog() -> bool:
	return _bank == null or _bank.can_afford(_fog_cost)


func _can_build_now() -> bool:
	return _gs == null or not _gs.has_method("can_build") or _gs.can_build()


func _update_build_ghost() -> void:
	var hit := _ground_point()
	if hit == _NO_HIT:
		_build_ghost_root.visible = false
		return
	_build_ghost_root.visible = true
	var anchor := _to_cell(hit)
	var aw := _to_world(anchor)
	_build_ghost_root.position = Vector3(aw.x, 0.0, aw.z)
	var ok := _footprint_buildable(anchor) and _can_afford() and not _at_cap() and _meets_requirement(anchor) and _build_phase_ok()
	_build_tile_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)


func _update_hero_ghost() -> void:
	var hit := _ground_point()
	if hit == _NO_HIT:
		_ghost.visible = false
		return
	_ghost.visible = true
	_ghost.position = Vector3(hit.x, 0.2, hit.z)
	var ok := _hero_placeable(hit)
	_ghost_mat.albedo_color = Color(0.95, 0.85, 0.3, 0.5) if ok else Color(1.0, 0.3, 0.3, 0.4)


func _hero_placeable(hit: Vector3) -> bool:
	if _gs and _gs.has_method("can_build") and not _gs.can_build():
		return false
	var cell := _to_cell(hit)
	if _wm and _wm.has_method("is_cell_revealed") and not _wm.is_cell_revealed(cell):
		return false
	var hall = get_tree().get_first_node_in_group("hall")
	if hall == null or not hall.has_slot():
		return false
	if _bank and not _bank.can_afford(_hero_cost):
		return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _build_mode:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel()
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_try_place()
	elif _hero_mode:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel()
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_place_hero()
	elif _fog_mode:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel()
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_try_reveal_fog()
	elif _reloc_mode:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel()
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_do_relocate()
	else:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_try_select()


func _try_select() -> void:
	var hit := _ground_point()
	if hit == _NO_HIT:
		return
	var cell := _to_cell(hit)
	var c := _to_world(cell)
	if Vector2(c.x, c.z).length() < _clear_radius:
		selection_cleared.emit()
		world_tree_clicked.emit()
		return
	if _occupied.has(cell):
		building_selected.emit(_occupied[cell])
		return
	var hero = _nearest_hero(hit, 1.6)
	if hero:
		building_selected.emit(hero)
		return
	var res = _nearest_resident(hit, 1.3)
	if res:
		building_selected.emit(res)
		return
	selection_cleared.emit()


## Open the selection panel for an arbitrary node (used by the People roster).
func select_node(n) -> void:
	if n != null and is_instance_valid(n):
		building_selected.emit(n)


func _nearest_resident(pos: Vector3, max_dist: float):
	var best = null
	var best_d: float = max_dist * max_dist
	for r in get_tree().get_nodes_in_group("resident"):
		if not is_instance_valid(r):
			continue
		var d: float = Vector2(r.global_position.x - pos.x, r.global_position.z - pos.z).length_squared()
		if d <= best_d:
			best_d = d
			best = r
	return best


func _nearest_hero(pos: Vector3, max_dist: float):
	var best = null
	var best_d: float = max_dist * max_dist
	for h in get_tree().get_nodes_in_group("hero"):
		if not is_instance_valid(h):
			continue
		var d: float = Vector2(h.global_position.x - pos.x, h.global_position.z - pos.z).length_squared()
		if d <= best_d:
			best_d = d
			best = h
	return best


func _try_place() -> void:
	if not _build_phase_ok():
		return
	var hit := _ground_point()
	if hit == _NO_HIT:
		return
	var anchor := _to_cell(hit)
	if not _footprint_buildable(anchor) or not _can_afford() or _at_cap() or not _meets_requirement(anchor):
		return
	if _bank:
		_bank.spend_many(_cost)
	var b := _building_scene.instantiate()
	for k in _props:
		b.set(k, _props[k])
	_buildings_root.add_child(b)
	var center := _footprint_center(anchor)
	b.position = center
	b.set_meta("build_cost", _cost.duplicate())
	b.set_meta("cell", anchor)
	var cells := _footprint_cells(anchor)
	b.set_meta("cells", cells)
	for c in cells:
		_occupied[c] = b
	buildings_changed.emit()


## Tower placement is allowed at night; everything else only during the day.
func _placing_is_tower() -> bool:
	return _props.has("kind")


func _build_phase_ok() -> bool:
	if _gs == null:
		return true
	if _placing_is_tower() and _gs.has_method("can_manage_combat"):
		return _gs.can_manage_combat()
	return (not _gs.has_method("can_build")) or _gs.can_build()


func _place_hero() -> void:
	var hit := _ground_point()
	if hit == _NO_HIT or not _hero_placeable(hit):
		return
	if _bank:
		_bank.spend_many(_hero_cost)
	var h := HERO.instantiate()
	h.species_key = _hero_species
	_buildings_root.add_child(h)
	h.global_position = Vector3(hit.x, 0.0, hit.z)
	h.set_post(h.global_position)
	_cancel()


# ---- Destroying buildings -------------------------------------------------

## Whether the given placed building may be destroyed in the current phase.
func can_destroy(b) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	if b.is_in_group("hero"):
		return false   # heroes are relocated, not destroyed
	if _gs == null:
		return true
	if b.is_in_group("tower") and _gs.has_method("can_manage_combat"):
		return _gs.can_manage_combat()
	return (not _gs.has_method("can_build")) or _gs.can_build()


## Refund half the build cost (floored). Occupied housing displaces its residents
## to homeless and re-runs allocation; worksites release their workers' jobs.
func destroy_building(b) -> bool:
	if not can_destroy(b):
		return false
	var cost: Dictionary = b.get_meta("build_cost", {}) if b.has_meta("build_cost") else {}
	if _bank and not cost.is_empty():
		for k in cost:
			var refund: int = int(cost[k]) / 2
			if refund > 0:
				_bank.add(k, refund)

	var was_housing := false
	if b.has_method("get_residents"):
		was_housing = true
		for r in b.get_residents():
			if is_instance_valid(r) and r.has_method("go_homeless"):
				r.go_homeless()
	if b.has_method("get_workers"):
		for w in b.get_workers():
			if is_instance_valid(w) and w.has_method("clear_job"):
				w.clear_job()

	# unhook from the grid (every footprint cell)
	if b.has_meta("cells"):
		for c in b.get_meta("cells"):
			if _occupied.get(c) == b:
				_occupied.erase(c)
	else:
		var cell = b.get_meta("cell", null) if b.has_meta("cell") else null
		if cell != null and _occupied.has(cell):
			_occupied.erase(cell)
		else:
			for key in _occupied.keys():
				if _occupied[key] == b:
					_occupied.erase(key)
					break

	# leave the housing group immediately so re-allocation ignores it
	if b.is_in_group("housing"):
		b.remove_from_group("housing")
	b.queue_free()
	buildings_changed.emit()
	selection_cleared.emit()

	if was_housing:
		var attr = get_tree().get_first_node_in_group("attraction")
		if attr and attr.has_method("rehome_homeless"):
			attr.rehome_homeless()
	return true


# ---- Relocating heroes ----------------------------------------------------

func begin_hero_relocation(hero) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	_build_mode = false
	_building_scene = null
	if _build_ghost_root:
		_build_ghost_root.visible = false
	_hero_mode = false
	_fog_mode = false
	_reloc_hero = hero
	_reloc_mode = true
	_ghost.visible = true


func _update_reloc_ghost() -> void:
	var hit := _ground_point()
	if hit == _NO_HIT:
		_ghost.visible = false
		return
	_ghost.visible = true
	_ghost.position = Vector3(hit.x, 0.2, hit.z)
	var ok := _reloc_placeable(hit)
	_ghost_mat.albedo_color = Color(0.95, 0.85, 0.3, 0.5) if ok else Color(1.0, 0.3, 0.3, 0.4)


func _reloc_placeable(hit: Vector3) -> bool:
	if _gs and _gs.has_method("can_manage_combat") and not _gs.can_manage_combat():
		return false
	var cell := _to_cell(hit)
	if _wm and _wm.has_method("is_cell_revealed") and not _wm.is_cell_revealed(cell):
		return false
	return true


func _do_relocate() -> void:
	var hit := _ground_point()
	if hit == _NO_HIT or not _reloc_placeable(hit):
		return
	if is_instance_valid(_reloc_hero):
		_reloc_hero.global_position = Vector3(hit.x, 0.0, hit.z)
		if _reloc_hero.has_method("set_post"):
			_reloc_hero.set_post(_reloc_hero.global_position)
	_cancel()


func _try_reveal_fog() -> void:
	if _wm == null or not _can_build_now():
		return
	var hit := _ground_point()
	if hit == _NO_HIT:
		return
	var b: Vector2i = _wm.world_to_block(hit)
	if not _wm.is_block_revealable(b) or not _can_afford_fog():
		return
	if _bank:
		_bank.spend_many(_fog_cost)
	_wm.reveal_block(b)
	# Frontier grew — refresh the eligible markers; stay in mode so the player can
	# keep clearing while they can afford it (right-click / Esc to exit).
	_rebuild_fog_marks()
	if not _can_afford_fog():
		_cancel()


func _cell_buildable(cell: Vector2i) -> bool:
	if _wm and _wm.has_method("is_cell_revealed"):
		if not _wm.is_cell_revealed(cell):
			return false
	elif abs(cell.x) > half_extent_cells or abs(cell.y) > half_extent_cells:
		return false
	if _occupied.has(cell):
		return false
	if _wm and _wm.has_method("is_road_cell") and _wm.is_road_cell(cell):
		return false
	if _wm and _wm.has_method("is_node_cell") and _wm.is_node_cell(cell):
		return false
	var c := _to_world(cell)
	if Vector2(c.x, c.z).length() < _clear_radius:
		return false
	return true


func _can_afford() -> bool:
	if _bank == null:
		return true
	return _bank.can_afford(_cost)


func _at_cap() -> bool:
	if _limit.is_empty():
		return false
	var grp: String = _limit.get("group", "")
	var base: int = _limit.get("base", 0)
	var per: int = _limit.get("per_stage", 0)
	var mx: int = _limit.get("max", 0)
	var stage: int = _tree.stage if _tree else 0
	var cap := base + per * stage
	if mx > 0:
		cap = min(cap, mx)
	return get_tree().get_nodes_in_group(grp).size() >= cap


func _meets_requirement(cell: Vector2i) -> bool:
	if _requires.is_empty():
		return true
	if _requires.get("housing", false):
		if get_tree().get_nodes_in_group("housing").is_empty():
			return false
	var fam: String = _requires.get("family", "")
	if fam != "":
		var cells: int = _requires.get("cells", 2)
		if _wm and _wm.has_method("has_resource_family"):
			return _wm.has_resource_family(cell, fam, cells)
	return true


func _to_cell(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / tile_size), roundi(world.z / tile_size))


func _to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * tile_size, 0.0, cell.y * tile_size)


func _ground_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return _NO_HIT
	var mouse := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return _NO_HIT
	var t := -origin.y / dir.y
	if t <= 0.0:
		return _NO_HIT
	return origin + dir * t
