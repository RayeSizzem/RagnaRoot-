extends CanvasLayer
## Roster menu. Toggle with the "P" icon (bottom-right, just left of Build) or the
## P key. Lists every settler; clicking one focuses the camera on them and opens
## their info panel — so you can inspect individuals without hunting for the tiny
## figures in the crowded tree/hut areas.

var _bs
var _cam
var _panel: PanelContainer
var _list: VBoxContainer
var _tracked = null   # resident the camera is locked onto while the panel is open


func _ready() -> void:
	_bs = get_tree().get_first_node_in_group("build_system")
	_cam = get_tree().get_first_node_in_group("camera_rig")
	_build_ui()
	UiTheme.skin(self)


func _build_ui() -> void:
	var btn := Button.new()
	btn.text = "P"
	btn.anchor_left = 1.0
	btn.anchor_top = 1.0
	btn.anchor_right = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -136   # sits to the left of the Build (B) button
	btn.offset_top = -72
	btn.offset_right = -80
	btn.offset_bottom = -16
	btn.pressed.connect(_toggle)
	add_child(btn)

	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -276
	_panel.offset_top = -430
	_panel.offset_right = -16
	_panel.offset_bottom = -84
	_panel.visible = false
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "People"
	title.add_theme_font_size_override("font_size", 16)
	if UiTheme.display_font():
		title.add_theme_font_override("font", UiTheme.display_font())
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(248, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)


func _process(_delta: float) -> void:
	# Keep the camera locked on the tracked settler while the roster is open.
	if not _panel.visible:
		return
	if _tracked != null and is_instance_valid(_tracked):
		if _cam and _cam.has_method("focus_on"):
			_cam.focus_on(_tracked.global_position)
	else:
		_tracked = null


func _toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh_list()
	else:
		_tracked = null   # closing the roster releases the camera


func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var residents: Array = get_tree().get_nodes_in_group("resident")
	residents.sort_custom(_by_name)
	var any := false
	for r in residents:
		if not is_instance_valid(r):
			continue
		any = true
		var b := Button.new()
		b.custom_minimum_size = Vector2(228, 0)
		b.text = _row_text(r)
		b.pressed.connect(_on_pick.bind(r))
		_list.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "No settlers yet."
		_list.add_child(l)
	UiTheme.skin(self)


func _by_name(a, b) -> bool:
	var na: String = a.display_name if is_instance_valid(a) else ""
	var nb: String = b.display_name if is_instance_valid(b) else ""
	return na < nb


func _row_text(r) -> String:
	var nm: String = r.display_name
	var g: String = "F" if r.gender == "f" else "M"
	var tr: String = Folk.TRAIT_LABEL.get(r.trait_key, "?")
	var status := ""
	if r.has_method("has_job") and r.has_job():
		status = "  ⚒" if (r.has_method("is_on_trait") and r.is_on_trait(r.get_job())) else "  ·"
	elif r.has_method("has_home") and not r.has_home():
		status = "  homeless %dd" % r.days_homeless
	return "%s (%s)\n%s  L%d   Faith %d%s" % [nm, g, tr, r.trait_level, r.faith, status]


func _on_pick(r) -> void:
	if not is_instance_valid(r):
		_tracked = null
		_refresh_list()
		return
	_tracked = r   # lock the camera onto this settler until panel close / another pick
	if _cam and _cam.has_method("focus_on"):
		_cam.focus_on(r.global_position)
	if _bs and _bs.has_method("select_node"):
		_bs.select_node(r)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		_toggle()
