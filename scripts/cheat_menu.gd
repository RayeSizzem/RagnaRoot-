extends CanvasLayer
## Developer cheat menu for playtesting. Type "Yggdrasil" anywhere in-game to
## toggle it. Grants resources and a few progression shortcuts.

const CODE := "yggdrasil"

var _bank
var _tree
var _wm
var _gs
var _attr
var _panel: PanelContainer
var _buf := ""


func _ready() -> void:
	_bank = get_tree().get_first_node_in_group("resource_bank")
	_tree = get_tree().get_first_node_in_group("world_tree")
	_wm = get_tree().get_first_node_in_group("world_manager")
	_gs = get_tree().get_first_node_in_group("game_state")
	_attr = get_tree().get_first_node_in_group("attraction")
	_build_ui()
	UiTheme.skin(self)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.unicode != 0:
		var ch := char(event.unicode).to_lower()
		if ch.length() == 1 and ch >= "a" and ch <= "z":
			_buf += ch
			if _buf.length() > CODE.length():
				_buf = _buf.substr(_buf.length() - CODE.length())
			if _buf == CODE:
				_buf = ""
				_toggle()


func _toggle() -> void:
	_panel.visible = not _panel.visible


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -150
	_panel.offset_right = 150
	_panel.offset_top = -210
	_panel.offset_bottom = 210
	_panel.visible = false

	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "DEV CHEATS"
	title.add_theme_font_size_override("font_size", 18)
	if UiTheme.display_font():
		title.add_theme_font_override("font", UiTheme.display_font())
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "type \"Yggdrasil\" to toggle"
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vb.add_child(sub)

	_add_btn(vb, "+500 Timber", func(): _give("timber", 500))
	_add_btn(vb, "+500 Stone", func(): _give("stone", 500))
	_add_btn(vb, "+1000 Sap", func(): _give("sap", 1000))
	_add_btn(vb, "+2000 Everything", _give_all)
	_add_btn(vb, "Grow Tree (+1000 sap)", _grow_tree)
	_add_btn(vb, "Reveal All Fog", _reveal_all)
	_add_btn(vb, "Spawn Settler", _spawn_settler)
	_add_btn(vb, "Kill All Enemies", _kill_enemies)
	_add_btn(vb, "Crown Tree (+1/7)", _crown)
	_add_btn(vb, "Close", _toggle)


func _add_btn(parent: Node, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	parent.add_child(b)


func _give(kind: String, amount: int) -> void:
	if _bank:
		_bank.add(kind, amount)


func _give_all() -> void:
	if not _bank:
		return
	for k in ["sap", "authority", "timber", "stone", "forage", "glow", "folk", "essence"]:
		_bank.add(k, 2000)


func _grow_tree() -> void:
	if _tree and _tree.has_method("channel_sap"):
		_tree.channel_sap(1000)


func _reveal_all() -> void:
	if _wm and _wm.has_method("reveal_all"):
		_wm.reveal_all()


func _spawn_settler() -> void:
	if _attr and _attr.has_method("debug_spawn_random"):
		_attr.debug_spawn_random()


func _kill_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()


func _crown() -> void:
	if _gs and _gs.has_method("crown_tree"):
		_gs.crown_tree()
