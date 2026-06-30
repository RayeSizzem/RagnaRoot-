extends CanvasLayer
## World Tree popup (click the tree). Two tabs: Tree (growth + sap) and
## Attractions (graft an on-tree structure to call each people to the tree).

var _bank
var _tree
var _gs
var _attr
var _panel: PanelContainer
var _yield_label: Label
var _prog_label: Label
var _bank_label: Label
var _attr_btns: Array = []


func _ready() -> void:
	_bank = get_tree().get_first_node_in_group("resource_bank")
	_tree = get_tree().get_first_node_in_group("world_tree")
	_gs = get_tree().get_first_node_in_group("game_state")
	_attr = get_tree().get_first_node_in_group("attraction")
	var bs = get_tree().get_first_node_in_group("build_system")
	if bs:
		bs.world_tree_clicked.connect(_on_open)
		bs.building_selected.connect(_hide.unbind(1))
		bs.selection_cleared.connect(_hide)
	if _gs:
		_gs.produce.connect(_refresh)
		_gs.day_changed.connect(_refresh.unbind(2))
	if _bank:
		_bank.changed.connect(_refresh.unbind(2))
	if _tree:
		_tree.sap_progress_changed.connect(_refresh.unbind(2))
		_tree.stage_changed.connect(_refresh.unbind(2))
	_build_ui()
	UiTheme.skin(self)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -16
	_panel.visible = false
	add_child(_panel)

	var vb := VBoxContainer.new()
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "World Tree"
	title.add_theme_font_size_override("font_size", 16)
	if UiTheme.display_font():
		title.add_theme_font_override("font", UiTheme.display_font())
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(340, 200)
	vb.add_child(tabs)

	# --- Tree tab ---
	var tree_page := VBoxContainer.new()
	tree_page.name = "Tree"
	tabs.add_child(tree_page)
	_yield_label = Label.new()
	tree_page.add_child(_yield_label)
	_prog_label = Label.new()
	tree_page.add_child(_prog_label)
	_bank_label = Label.new()
	tree_page.add_child(_bank_label)
	var send_row := Label.new()
	send_row.text = "Send sap to tree:"
	tree_page.add_child(send_row)
	var hb := HBoxContainer.new()
	tree_page.add_child(hb)
	_add_send(hb, 25)
	_add_send(hb, 50)
	_add_send(hb, 100)

	# --- Attractions tab ---
	var attr_page := VBoxContainer.new()
	attr_page.name = "Attractions"
	tabs.add_child(attr_page)
	if _attr:
		for sp in _attr.species_list():
			var b := Button.new()
			b.set_meta("sp", sp)
			b.pressed.connect(_on_build_attraction.bind(sp))
			attr_page.add_child(b)
			_attr_btns.append(b)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_hide)
	vb.add_child(close)


func _add_send(parent: Node, amount: int) -> void:
	var b := Button.new()
	b.text = "+%d" % amount
	b.pressed.connect(_send.bind(amount))
	parent.add_child(b)


func _on_open() -> void:
	_panel.visible = true
	_refresh()


func _hide() -> void:
	_panel.visible = false


func _send(amount: int) -> void:
	if _tree and _tree.is_crowned():
		_refresh()
		return
	if _bank and _bank.spend("sap", amount):
		if _tree:
			_tree.channel_sap(amount)
	_refresh()


func _on_build_attraction(sp: String) -> void:
	if _gs and _gs.has_method("can_build") and not _gs.can_build():
		return
	if _attr and _attr.build_attraction(sp):
		_refresh()


func _refresh() -> void:
	var t_day := 0
	var s_day := 0
	var sap_day := 0
	for h in get_tree().get_nodes_in_group("worksite"):
		if h.has_method("get_per_tick") and h.has_method("get_resource_type"):
			var rt: String = h.get_resource_type()
			if rt == "timber":
				t_day += h.get_per_tick()
			elif rt == "stone":
				s_day += h.get_per_tick()
	for sw in get_tree().get_nodes_in_group("sapwell"):
		if sw.has_method("get_sap_per_day"):
			sap_day += sw.get_sap_per_day()
	_yield_label.text = "Gain per 10s:  +%d timber   +%d stone   +%d sap" % [t_day, s_day, sap_day]
	if _tree:
		if _tree.is_crowned():
			_prog_label.text = "CROWNED — Seed ready"
		else:
			_prog_label.text = "Sap into tree:  %d / %d  (stage: %s)" % [
				_tree.sap_into_tree, _tree.get_sap_needed(), _tree.get_stage_name()
			]
	var banked: int = _bank.get_amount("sap") if _bank else 0
	_bank_label.text = "Banked sap available:  %d" % banked
	_refresh_attractions()


func _refresh_attractions() -> void:
	if _attr == null:
		return
	var c: Dictionary = _attr.build_cost()
	var afford: bool = (_bank == null) or _bank.can_afford(c)
	for b in _attr_btns:
		var sp: String = b.get_meta("sp")
		var bname: String = _attr.building_name(sp)
		if _attr.is_built(sp):
			b.text = "✓ %s — drawing %s (%d/day)" % [bname, sp.capitalize(), int(_attr.rate(sp))]
			b.disabled = true
		elif not _attr.is_unlocked(sp):
			b.text = "%s — unlocks at %s" % [bname, _attr.unlock_stage_name(sp)]
			b.disabled = true
		else:
			b.text = "Build %s  (%dT %dS %dSap)" % [bname, c.get("timber", 0), c.get("stone", 0), c.get("sap", 0)]
			b.disabled = not afford
