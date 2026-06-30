extends Node3D
## Authority for the world: blocks, fog, resources, the four dark towers, and a
## road network. Towers sit at spread-out random blocks. Each road MEANDERS to
## its OWN gate on a ring around the tree (so the four roads stay distinct), and
## lanes avoid each other's cells. Monsters spawn at towers and follow the road.
## Joins "resource_field" so huts / build system resolve us.

const TILE := 2.0
const BLOCK_CELLS := 21
const BLOCK_SIZE := 42.0
const WORLD_RADIUS := 7
const FOG_SUB := 6   # reveal-mask texels per block; >1 keeps block interiors solidly clear
const SPAWN_FOG_MARGIN := 4   # cells the spawn sits behind the frontier indicator

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

# Mineral tints (rock model recoloured) + fallback tree tints if no pine/dead model.
const GOLD_TINT := Color(0.85, 0.65, 0.18)
const RUBY_TINT := Color(0.72, 0.1, 0.16)
const DIAMOND_TINT := Color(0.6, 0.85, 0.92)
const PINE_TINT := Color(0.16, 0.36, 0.24)
const DEAD_TINT := Color(0.42, 0.36, 0.28)

@export var clusters_per_block: int = 8   # tree clusters (3-5 trees each)
@export var decor_per_block: int = 18     # grass/flowers/ferns/mushrooms ground scatter
@export var trees_per_block: int = 30
@export var rocks_per_block: int = 30
@export var min_amount: int = 300
@export var max_amount: int = 700
@export var tree_clear_radius: float = 8.0
@export var tower_count: int = 4
@export var plaza_radius: int = 1         # paved ring of cells around the trunk (3x3)
@export var min_run: int = 7              # min straight run (cells) before a road may turn
@export var max_run: int = 13             # max straight run before a road turns
@export var axis_bias: float = 1.0        # 1 = head to tree proportionally, 0 = 50/50 wander
@export var min_tower_angle_deg: float = 45.0  # min angular spread between towers (from the tree)

var _revealed := {}
var _fog := {}        # set of still-fogged blocks (Vector2i -> true)
var _mask_img: Image = null
var _mask_tex: ImageTexture = null
var _fog_root: Node3D = null
var _node_cells := {}
var _road := {}                   # Vector2i cell -> true (all lanes)
var _tower_blocks := {}
var _tower_pos: Array = []
var _lane_paths: Array = []
var _pine := {"models": [], "fallback": true}
var _dead := {"models": [], "fallback": true}
var _decor: Array = []   # [{models, weight, scale}] ground decoration

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _enter_tree() -> void:
	add_to_group("world_manager")
	add_to_group("resource_field")


func _ready() -> void:
	_plan()
	_paint_plaza()
	_draw_roads()
	_build_fog()
	_pine = _load_models([
		"res://environment/Pine_1.gltf", "res://environment/Pine_2.gltf",
		"res://environment/Pine_3.gltf", "res://environment/Pine_4.gltf",
		"res://environment/Pine_5.gltf",
	], TREES)
	_dead = _load_models([
		"res://environment/DeadTree_1.gltf", "res://environment/DeadTree_2.gltf",
		"res://environment/DeadTree_3.gltf", "res://environment/DeadTree_4.gltf",
		"res://environment/DeadTree_5.gltf",
	], TREES)
	_build_decor_pool()
	_revealed[Vector2i.ZERO] = true
	_generate_block(Vector2i.ZERO)


## Load whichever candidate models exist; fall back (with a tint) if none are found.
func _load_models(candidates: Array, fallback: Array) -> Dictionary:
	var out: Array = []
	for path in candidates:
		if ResourceLoader.exists(path):
			out.append(load(path))
	if out.is_empty():
		return {"models": fallback, "fallback": true}
	return {"models": out, "fallback": false}


## Forest-floor decoration: weighted groups of small non-harvestable props.
func _build_decor_pool() -> void:
	_decor = []
	_add_decor(["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short", "Grass_Wispy_Tall"], 10, 0.32)
	_add_decor(["Flower_3_Group", "Flower_3_Single", "Flower_4_Group", "Flower_4_Single", "Clover_1", "Clover_2", "Petal_1", "Petal_2", "Petal_3"], 5, 0.3)
	_add_decor(["Fern_1"], 4, 0.34)
	_add_decor(["Bush_Common", "Bush_Common_Flowers"], 3, 0.34)
	_add_decor(["Mushroom_Common", "Mushroom_Laetiporus"], 2, 0.3)
	_add_decor(["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Square_1", "Pebble_Square_2"], 2, 0.32)


func _add_decor(names: Array, weight: int, scale: float) -> void:
	var models: Array = []
	for nm in names:
		var path := "res://environment/%s.gltf" % nm
		if ResourceLoader.exists(path):
			models.append(load(path))
	if not models.is_empty():
		_decor.append({"models": models, "weight": weight, "scale": scale})


func _scatter_decor(b: Vector2i) -> void:
	if _decor.is_empty():
		return
	var base := b * BLOCK_CELLS
	var total_w: int = 0
	for d in _decor:
		total_w += int(d["weight"])
	for i in decor_per_block:
		var cell := base + Vector2i(randi_range(-10, 10), randi_range(-10, 10))
		if _road.has(cell):
			continue
		var roll: int = randi() % total_w
		var grp = _decor[0]
		for d in _decor:
			roll -= int(d["weight"])
			if roll < 0:
				grp = d
				break
		var models: Array = grp["models"]
		var mi := (models[randi() % models.size()] as PackedScene).instantiate()
		add_child(mi)
		mi.add_to_group("decor")
		if mi is Node3D:
			var n3 := mi as Node3D
			var sc: float = grp["scale"]
			n3.position = Vector3(cell.x * TILE + randf_range(-1.0, 1.0), 0.0, cell.y * TILE + randf_range(-1.0, 1.0))
			n3.scale = Vector3.ONE * sc * randf_range(0.8, 1.2)
			n3.rotation.y = randf() * TAU


# --- planning: towers + meandering, distinct roads ---

func _plan() -> void:
	for b in _pick_tower_blocks():
		_tower_blocks[b] = true
		var start: Vector2i = b * BLOCK_CELLS
		var cells := _make_road(start, Vector2i.ZERO, _road)
		var pts: Array = []
		for c in cells:
			var cell: Vector2i = c
			if not _road.has(cell):
				_road[cell] = true
			pts.append(Vector3(cell.x * TILE, 0.0, cell.y * TILE))
		_lane_paths.append(pts)
		_tower_pos.append(pts[0] if pts.size() > 0 else Vector3.ZERO)


## Always-road plaza around the trunk so all four lanes visibly converge there.
func _paint_plaza() -> void:
	for dx in range(-plaza_radius, plaza_radius + 1):
		for dy in range(-plaza_radius, plaza_radius + 1):
			_road[Vector2i(dx, dy)] = true


func _pick_tower_blocks() -> Array:
	var blocks: Array = []
	var attempts := 0
	var min_ang: float = deg_to_rad(min_tower_angle_deg)
	while blocks.size() < tower_count and attempts < 600:
		attempts += 1
		var b := Vector2i(
			randi_range(-WORLD_RADIUS, WORLD_RADIUS),
			randi_range(-WORLD_RADIUS, WORLD_RADIUS)
		)
		if max(abs(b.x), abs(b.y)) < 3:
			continue
		var ang: float = atan2(float(b.y), float(b.x))
		var ok := true
		for other in blocks:
			var o: Vector2i = other
			var oang: float = atan2(float(o.y), float(o.x))
			if absf(angle_difference(ang, oang)) < min_ang:
				ok = false
				break
		if ok:
			blocks.append(b)
	return blocks


func _make_road(start: Vector2i, target: Vector2i, avoid: Dictionary) -> Array:
	# Segmented "staircase": straight runs of min_run..max_run, turning only at
	# segment ends, so a road bends at most ~3 times per block. Runs are shortened
	# if they would hit another lane, which keeps the four roads separate.
	var path: Array = [start]
	var cur := start
	var guard := 0
	while cur != target and guard < 1000:
		guard += 1
		var dx: int = target.x - cur.x
		var dy: int = target.y - cur.y
		if dx == 0 and dy == 0:
			break
		var axis: int
		if dx == 0:
			axis = 1
		elif dy == 0:
			axis = 0
		else:
			var px := float(abs(dx)) / float(abs(dx) + abs(dy))
			var pick := 0.5 + (px - 0.5) * axis_bias
			axis = 0 if randf() < pick else 1
		var sd: Vector2i
		var rem: int
		if axis == 0:
			sd = Vector2i(signi(dx), 0)
			rem = abs(dx)
		else:
			sd = Vector2i(0, signi(dy))
			rem = abs(dy)
		var run: int = mini(randi_range(min_run, max_run), rem)
		run = _clamp_run(cur, sd, run, avoid)
		if run <= 0:
			# blocked immediately by another lane -> turn onto the other axis to route around
			var alt: Vector2i = Vector2i(0, signi(dy)) if axis == 0 else Vector2i(signi(dx), 0)
			if alt == Vector2i.ZERO:
				alt = sd
			cur = cur + alt
			path.append(cur)
			continue
		for i in range(run):
			cur = cur + sd
			path.append(cur)
	return path


## How far a straight run can go before it would ride onto another lane.
func _clamp_run(cur: Vector2i, dir: Vector2i, run: int, avoid: Dictionary) -> int:
	var n := 0
	var c := cur
	for i in range(run):
		c = c + dir
		if max(abs(c.x), abs(c.y)) > plaza_radius + 1 and avoid.has(c):
			break
		n += 1
	return n


func is_road_cell(cell: Vector2i) -> bool:
	return _road.has(cell)


func get_tower_positions() -> Array:
	return _tower_pos


func get_lane_paths() -> Array:
	return _lane_paths


func _world_to_cell(v: Vector3) -> Vector2i:
	return Vector2i(roundi(v.x / TILE), roundi(v.z / TILE))


## Where this lane's monsters should appear: the last still-dark cell before the
## revealed area (scanning from the tree outward). As fog clears the spawn moves
## toward the tower; once the whole lane is revealed it returns the tower itself.
## Returns { "pos": Vector3, "path": Array[Vector3] } (path runs spawn -> tree).
func get_lane_spawn(lane_index: int) -> Dictionary:
	if lane_index < 0 or lane_index >= _lane_paths.size():
		return {"pos": Vector3.ZERO, "path": [], "frontier": Vector3.ZERO}
	var pts: Array = _lane_paths[lane_index]
	if pts.is_empty():
		return {"pos": Vector3.ZERO, "path": [], "frontier": Vector3.ZERO}
	# The VISIBLE ROAD TIP is the outermost still-revealed cell: scan inward from the
	# outer end and take the first revealed one. (Scanning the other way latches onto
	# inner bends that merely clip a fogged block, which is why the marker drifted.)
	var tip_i := pts.size() - 1
	for i in range(pts.size()):
		if is_cell_revealed(_world_to_cell(pts[i])):
			tip_i = i
			break
	# Push the spawn outward to the nearest FULLY-DARK cell (coverage ~0), so monsters
	# are guaranteed invisible at spawn — a fixed cell margin can land in the half-lit
	# transition band and flash. Stay as close to the fog line as geometry allows.
	var spawn_i := tip_i
	var steps := 0
	while spawn_i - 1 >= 0 and steps < 14:
		spawn_i -= 1
		steps += 1
		if fog_clear_at(pts[spawn_i]) < 0.04:
			break
	return {"pos": pts[spawn_i], "path": pts.slice(spawn_i), "frontier": pts[tip_i]}


func _draw_roads() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.24, 0.16)
	for key in _road.keys():
		var c: Vector2i = key
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(TILE, TILE)
		mi.mesh = q
		mi.material_override = mat
		mi.rotation.x = -PI / 2.0
		mi.position = Vector3(c.x * TILE, 0.03, c.y * TILE)
		add_child(mi)


# --- fog ---

func _build_fog() -> void:
	# Single continuous fog sheet driven by a per-block reveal MASK (see
	# shaders/fog_mask.gdshader). _fog is now just the SET of still-fogged blocks
	# (no per-block geometry), and reveal flips a texel in the mask. A few stacked
	# sheets give the fog height; because each is one plane there are no interior
	# seams, no grid, and no z-fighting flicker.
	var g := 2 * WORLD_RADIUS + 1
	# One block = FOG_SUB x FOG_SUB texels. Each revealed block is filled as a solid
	# square so its whole interior stays clear (no build-in-fog); bilinear filtering
	# then only rounds the OUTER corners of the revealed blob, not every block corner.
	var m := g * FOG_SUB
	_mask_img = Image.create(m, m, false, Image.FORMAT_RGBA8)
	_mask_img.fill(Color(0, 0, 0, 1)) # 0 = fogged everywhere
	# centre block starts revealed
	_fill_block_pixels(Vector2i.ZERO)
	_mask_tex = ImageTexture.create_from_image(_mask_img)

	for bx in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for bz in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			var b := Vector2i(bx, bz)
			if b == Vector2i.ZERO:
				continue
			_fog[b] = true

	var shader: Shader = null
	if ResourceLoader.exists("res://shaders/fog_mask.gdshader"):
		shader = load("res://shaders/fog_mask.gdshader")
	if shader == null:
		return # fog disabled rather than crashing if the shader is missing

	var span: float = float(g) * BLOCK_SIZE
	var layers := [
		{"y": 0.3, "a": 1.0, "c": Color(0.012, 0.012, 0.016)},
		{"y": 1.9, "a": 0.42, "c": Color(0.016, 0.016, 0.022)},
		{"y": 3.4, "a": 0.28, "c": Color(0.02, 0.02, 0.028)},
		{"y": 4.9, "a": 0.18, "c": Color(0.024, 0.024, 0.032)},
	]
	_fog_root = Node3D.new()
	_fog_root.name = "FogSheets"
	add_child(_fog_root)
	for layer in layers:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("reveal_mask", _mask_tex)
		var c: Color = layer["c"]
		mat.set_shader_parameter("fog_color", Vector3(c.r, c.g, c.b))
		mat.set_shader_parameter("base_alpha", layer["a"])
		mat.set_shader_parameter("block_size", BLOCK_SIZE)
		mat.set_shader_parameter("grid_size", float(g))
		mat.set_shader_parameter("world_radius", float(WORLD_RADIUS))
		mat.set_shader_parameter("edge_sharpness", 0.7)
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(span, span)
		mi.mesh = plane
		mi.material_override = mat
		mi.position.y = layer["y"]
		_fog_root.add_child(mi)


func _set_block_revealed_pixel(b: Vector2i) -> void:
	if _mask_img == null:
		return
	_fill_block_pixels(b)
	if _mask_tex != null:
		_mask_tex.update(_mask_img)


## Paint block b as a solid FOG_SUB x FOG_SUB white square in the reveal mask.
func _fill_block_pixels(b: Vector2i) -> void:
	if _mask_img == null:
		return
	var ox: int = (b.x + WORLD_RADIUS) * FOG_SUB
	var oy: int = (b.y + WORLD_RADIUS) * FOG_SUB
	for dx in FOG_SUB:
		for dy in FOG_SUB:
			_mask_img.set_pixel(ox + dx, oy + dy, Color(1, 1, 1, 1))


func is_revealed(b: Vector2i) -> bool:
	return _revealed.has(b)


func cell_block(cell: Vector2i) -> Vector2i:
	return Vector2i(
		roundi(float(cell.x) / float(BLOCK_CELLS)),
		roundi(float(cell.y) / float(BLOCK_CELLS))
	)


func is_cell_revealed(cell: Vector2i) -> bool:
	return _revealed.has(cell_block(cell))


## Fog clarity at a world position in [0,1] (1 = clear, 0 = solid fog). Mirrors the
## fog shader (high-res mask + bilinear + the same smoothstep) so enemies fade
## exactly with what the player sees instead of popping on a coarse per-block grid.
func fog_clear_at(p: Vector3) -> float:
	if _mask_img == null:
		return 1.0
	var g := 2 * WORLD_RADIUS + 1
	var m := g * FOG_SUB
	var fx: float = (p.x / BLOCK_SIZE + float(WORLD_RADIUS) + 0.5) / float(g) * float(m) - 0.5
	var fz: float = (p.z / BLOCK_SIZE + float(WORLD_RADIUS) + 0.5) / float(g) * float(m) - 0.5
	var x0: int = floori(fx)
	var z0: int = floori(fz)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var r00: float = _mask_r(x0, z0, m)
	var r10: float = _mask_r(x0 + 1, z0, m)
	var r01: float = _mask_r(x0, z0 + 1, m)
	var r11: float = _mask_r(x0 + 1, z0 + 1, m)
	var revealed: float = lerpf(lerpf(r00, r10, tx), lerpf(r01, r11, tx), tz)
	var soft: float = lerpf(0.12, 0.05, 0.7)
	return smoothstep(0.45 - soft, 0.45, revealed)


func _mask_r(x: int, y: int, m: int) -> float:
	if x < 0 or y < 0 or x >= m or y >= m:
		return 0.0
	return _mask_img.get_pixel(x, y).r


func _has_revealed_neighbor(b: Vector2i) -> bool:
	for d in DIRS:
		if _revealed.has(b + d):
			return true
	return false


func reveal_nearest(from_pos: Vector3) -> bool:
	var best := Vector2i.ZERO
	var best_d := INF
	var found := false
	for key in _fog.keys():
		var b: Vector2i = key
		if not _has_revealed_neighbor(b):
			continue
		var c := Vector3(b.x * BLOCK_SIZE, 0.0, b.y * BLOCK_SIZE)
		var d := from_pos.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = b
			found = true
	if not found:
		return false
	_reveal(best)
	return true


func world_to_block(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / BLOCK_SIZE), roundi(pos.z / BLOCK_SIZE))


func block_center(b: Vector2i) -> Vector3:
	return Vector3(b.x * BLOCK_SIZE, 0.0, b.y * BLOCK_SIZE)


## A fogged block the player may choose to clear: still dark AND touching land
## that's already revealed (so the frontier only ever grows outward, no islands).
func is_block_revealable(b: Vector2i) -> bool:
	return _fog.has(b) and _has_revealed_neighbor(b)


func revealable_blocks() -> Array:
	var out: Array = []
	for key in _fog.keys():
		if _has_revealed_neighbor(key):
			out.append(key)
	return out


func reveal_block(b: Vector2i) -> bool:
	if not is_block_revealable(b):
		return false
	_reveal(b)
	return true


func reveal_all() -> void:
	# Reveal + populate every block. Spread across frames so a full 15x15 reveal
	# doesn't freeze the game while it instantiates resources.
	for key in _fog.keys().duplicate():
		var b: Vector2i = key
		if not _fog.has(b):
			continue
		_fog.erase(b)
		_set_block_revealed_pixel(b)
		_revealed[b] = true
		_generate_block(b)
		await get_tree().process_frame


func _reveal(b: Vector2i) -> void:
	if _fog.has(b):
		_fog.erase(b)
	_set_block_revealed_pixel(b)
	_revealed[b] = true
	_generate_block(b)


# --- content ---

func _generate_block(b: Vector2i) -> void:
	if _tower_blocks.has(b):
		_place_dark_tower(b)
	_scatter_trees(b)
	_scatter_rocks(b)
	_scatter_decor(b)


## 0 at the central block, 1 at the world edge — drives pine & mineral rarity.
func _dist_t(b: Vector2i) -> float:
	var ring: int = maxi(absi(b.x), absi(b.y))
	return clampf(float(ring) / float(WORLD_RADIUS), 0.0, 1.0)


## Trees grow in clusters of 3-5 (forest patches). Pine (soft wood) grows ever more
## common further from the World Tree; common trees (timber) dominate near it.
func _scatter_trees(b: Vector2i) -> void:
	var base := b * BLOCK_CELLS
	var dist_t := _dist_t(b)
	var pine_chance: float = lerpf(0.05, 0.78, dist_t)
	for ci in clusters_per_block:
		var center := base + Vector2i(randi_range(-8, 8), randi_range(-8, 8))
		var is_pine := randf() < pine_chance
		var rtype: String = "soft_wood" if is_pine else "timber"
		var models: Array = _pine["models"] if is_pine else TREES
		var tint = PINE_TINT if (is_pine and _pine["fallback"]) else null
		var n_trees: int = randi_range(3, 5)
		for ti in n_trees:
			var cell := center + Vector2i(randi_range(-2, 2), randi_range(-2, 2))
			_try_place_node(cell, rtype, models, tint, randi_range(min_amount, max_amount))


## Rocks yield stone; the further out, the higher the chance of rare minerals
## (gold, then ruby, then diamond at the deep edges).
func _scatter_rocks(b: Vector2i) -> void:
	var base := b * BLOCK_CELLS
	var dist_t := _dist_t(b)
	for i in rocks_per_block:
		var cell := base + Vector2i(randi_range(-9, 9), randi_range(-9, 9))
		var rtype := "stone"
		var tint = null
		var amt := randi_range(min_amount, max_amount)
		if randf() < dist_t * 0.05:
			var r := randf()
			if dist_t > 0.8 and r < 0.22:
				rtype = "diamond"
				tint = DIAMOND_TINT
				amt = randi_range(60, 160)
			elif dist_t > 0.5 and r < 0.5:
				rtype = "ruby"
				tint = RUBY_TINT
				amt = randi_range(90, 200)
			else:
				rtype = "gold"
				tint = GOLD_TINT
				amt = randi_range(120, 280)
		_try_place_node(cell, rtype, ROCKS, tint, amt)


func _try_place_node(cell: Vector2i, rtype: String, models: Array, tint, amt: int) -> void:
	if models.is_empty() or _road.has(cell) or _node_cells.has(cell):
		return
	var wpos := Vector3(cell.x * TILE, 0.0, cell.y * TILE)
	if Vector2(wpos.x, wpos.z).length() < tree_clear_radius:
		return
	var n := NODE.instantiate()
	var model: PackedScene = models[randi() % models.size()]
	n.setup(rtype, amt, model, tint)
	add_child(n)
	n.position = wpos
	_node_cells[cell] = n


func _place_dark_tower(b: Vector2i) -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 2.2
	cyl.height = 12.0
	body.mesh = cyl
	body.position = Vector3(b.x * BLOCK_SIZE, 6.0, b.y * BLOCK_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.05, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.05, 0.12)
	mat.emission_energy_multiplier = 1.5
	body.material_override = mat
	body.add_to_group("dark_tower")
	add_child(body)
	# a grove of dead trees (hard wood) clings to the dark tower
	var base := b * BLOCK_CELLS
	var count: int = randi_range(16, 28)
	for i in count:
		var cell := base + Vector2i(randi_range(-7, 7), randi_range(-7, 7))
		var tint = DEAD_TINT if _dead["fallback"] else null
		_try_place_node(cell, "hard_wood", _dead["models"], tint, randi_range(min_amount, max_amount))


# --- resource queries ---

func is_node_cell(cell: Vector2i) -> bool:
	if _node_cells.has(cell):
		if is_instance_valid(_node_cells[cell]):
			return true
		_node_cells.erase(cell)
	return false


func has_resource_near(cell: Vector2i, rtype: String, cell_range: int) -> bool:
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n) or n.get_type() != rtype or n.is_depleted():
			continue
		var nc := Vector2i(
			roundi(n.global_position.x / TILE),
			roundi(n.global_position.z / TILE)
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


## Nearest node of a resource FAMILY ("wood" / "mineral"); huts bind by family
## and yield whatever specific resource the bound node provides.
func find_nearest_family(pos: Vector3, family: String, rng: float):
	var best = null
	var best_d := rng * rng
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n) or n.is_depleted():
			continue
		if n.has_method("get_family") and n.get_family() != family:
			continue
		var d := pos.distance_squared_to(n.global_position)
		if d <= best_d:
			best_d = d
			best = n
	return best


func has_resource_family(cell: Vector2i, family: String, cell_range: int) -> bool:
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n) or n.is_depleted():
			continue
		if n.has_method("get_family") and n.get_family() != family:
			continue
		var nc := Vector2i(roundi(n.global_position.x / TILE), roundi(n.global_position.z / TILE))
		if max(abs(nc.x - cell.x), abs(nc.y - cell.y)) <= cell_range:
			return true
	return false
