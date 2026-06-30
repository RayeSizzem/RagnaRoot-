extends CanvasLayer
## Main menu (on launch) and pause menu (Esc / ☰). Pauses the whole game while
## open. Resume returns to play; Restart reloads a fresh run; Main Menu abandons
## to the title; Quit exits.

enum State { MAIN, PAUSE, SETTINGS, PLAYING, GAME_OVER }

static var _skip_main := false   # set by Restart so the reloaded scene skips the title

var _backdrop: ColorRect
var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _btns: VBoxContainer
var _menu_btn: Button
var _state := State.MAIN
var _settings_from := State.MAIN
var _build


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_apply_scaling()
	get_window().theme = UiTheme.build_theme()
	_build = get_tree().get_first_node_in_group("build_system")
	_build_ui()
	UiTheme.skin(self)
	if _skip_main:
		_skip_main = false
		_play()
	else:
		_show_main()
	call_deferred("_connect_defeat")


## Wire the Heartroot's fall to the Game Over screen (deferred so the World Tree has
## registered its group by the time we look for it).
func _connect_defeat() -> void:
	var tree := get_tree().get_first_node_in_group("world_tree")
	if tree and tree.has_signal("heartroot_destroyed") and not tree.heartroot_destroyed.is_connected(_show_game_over):
		tree.heartroot_destroyed.connect(_show_game_over)


## Scale all UI with the window/screen, keeping the 3D viewport at native res.
func _apply_scaling() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(1152, 648)


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.03, 0.05, 0.03, 0.78)
	_backdrop.anchor_right = 1.0
	_backdrop.anchor_bottom = 1.0
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 38)
	if UiTheme.display_font():
		_title.add_theme_font_override("font", UiTheme.display_font())
	_title.add_theme_color_override("font_color", UiTheme.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 17)
	_subtitle.add_theme_color_override("font_color", Color(0.86, 0.84, 0.78))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size = Vector2(320, 0)
	_subtitle.visible = false
	vb.add_child(_subtitle)

	_btns = VBoxContainer.new()
	_btns.add_theme_constant_override("separation", 6)
	vb.add_child(_btns)

	_menu_btn = Button.new()
	_menu_btn.text = "☰ Menu"
	_menu_btn.anchor_left = 0.5
	_menu_btn.anchor_right = 0.5
	_menu_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_btn.offset_top = 10.0
	_menu_btn.offset_bottom = 40.0
	_menu_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_btn.pressed.connect(_toggle_pause)
	add_child(_menu_btn)


func _make_buttons(items: Array) -> void:
	for c in _btns.get_children():
		c.queue_free()
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.custom_minimum_size = Vector2(220, 0)
		b.pressed.connect(it[1])
		_btns.add_child(b)


func _show_main() -> void:
	_state = State.MAIN
	get_tree().paused = true
	_subtitle.visible = false
	_backdrop.color = Color(0.03, 0.05, 0.03, 0.78)
	_title.text = "YGGDRASIL"
	_make_buttons([["Play", _play], ["Settings", _show_settings.bind(State.MAIN)], ["Quit", _quit]])
	_set_menu_visible(true)
	_menu_btn.visible = false


## Shown when the Heartroot falls. Pauses the run and offers a restart / exit.
func _show_game_over() -> void:
	if _state == State.GAME_OVER:
		return
	_state = State.GAME_OVER
	get_tree().paused = true
	_title.text = "The Heartroot Has Fallen"
	_subtitle.text = _run_summary()
	_subtitle.visible = true
	_make_buttons([["Try Again", _restart], ["Main Menu", _to_main], ["Quit", _quit]])
	_backdrop.color = Color(0.09, 0.01, 0.01, 0.85)   # grim red wash over the ruined grove
	_set_menu_visible(true)
	_menu_btn.visible = false


func _run_summary() -> String:
	var gs := get_tree().get_first_node_in_group("game_state")
	if gs == null:
		return "The Dark has taken the grove."
	return "You held the Tree until Cycle %d, Day %d.\nWorld Trees crowned: %d / %d" % [
		gs.cycle, gs.day, gs.trees_crowned, gs.TOTAL_CONTINENTS
	]


func _show_pause() -> void:
	_state = State.PAUSE
	get_tree().paused = true
	_subtitle.visible = false
	_title.text = "Paused"
	_make_buttons([["Resume", _play], ["Restart", _restart], ["Settings", _show_settings.bind(State.PAUSE)], ["Main Menu", _to_main], ["Quit", _quit]])
	_set_menu_visible(true)
	_menu_btn.visible = false


func _play() -> void:
	_state = State.PLAYING
	get_tree().paused = false
	_set_menu_visible(false)
	_menu_btn.visible = true


func _set_menu_visible(v: bool) -> void:
	_backdrop.visible = v
	_panel.visible = v


func _toggle_pause() -> void:
	if _state == State.PLAYING:
		_show_pause()
	elif _state == State.PAUSE:
		_play()


func _restart() -> void:
	_skip_main = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_main() -> void:
	_skip_main = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _show_settings(from_state: int) -> void:
	_settings_from = from_state
	_state = State.SETTINGS
	get_tree().paused = true
	_title.text = "Settings — Resolution"
	_make_buttons([
		["1280 × 720", _set_resolution.bind(1280, 720)],
		["1600 × 900", _set_resolution.bind(1600, 900)],
		["1920 × 1080", _set_resolution.bind(1920, 1080)],
		["2560 × 1440", _set_resolution.bind(2560, 1440)],
		["Fullscreen", _set_fullscreen],
		["Windowed", _set_windowed],
		["Back", _settings_back],
	])
	_set_menu_visible(true)
	_menu_btn.visible = false


func _set_resolution(w: int, h: int) -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	var sz := Vector2i(w, h)
	DisplayServer.window_set_size(sz)
	win.size = sz
	var screen: Vector2i = DisplayServer.screen_get_size()
	var pos: Vector2i = (screen - sz) / 2
	DisplayServer.window_set_position(pos)
	win.position = pos
	print("[Yggdrasil] Requested %dx%d -> window is now %s (embedded? resize is ignored when run inside the editor's Game view)" % [w, h, win.size])


func _set_fullscreen() -> void:
	get_window().mode = Window.MODE_FULLSCREEN


func _set_windowed() -> void:
	get_window().mode = Window.MODE_WINDOWED


func _settings_back() -> void:
	if _settings_from == State.MAIN:
		_show_main()
	else:
		_show_pause()


func _quit() -> void:
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _state == State.MAIN or _state == State.GAME_OVER:
			return
		if _state == State.PLAYING and _build and _build.has_method("is_placing") and _build.is_placing():
			return   # let build/hero placement cancel first
		_toggle_pause()
		get_viewport().set_input_as_handled()
