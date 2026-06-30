extends CanvasLayer
## HUD corner panels:
##  top-left   : day / cycle / phase + tending timer or assault status
##  top-right  : tree stage, Heartroot, Sapwell count, world meter + resources
##  bottom-left: Advance Day (summons the wave)

var _gs
var _tree
var _bank
var _tide

var _day_label: Label
var _status_label: Label
var _toast: Label
var _toast_time := 0.0
var _stage_label: Label
var _heart_label: Label
var _sapwell_label: Label
var _meter_label: Label
var _timber_label: Label
var _stone_label: Label
var _sap_label: Label
var _essence_label: Label
var _food_label: Label
var _light_label: Label
var _rare_label: Label
var _day_btn: Button


func _ready() -> void:
	add_to_group("hud")
	_gs = get_tree().get_first_node_in_group("game_state")
	_tree = get_tree().get_first_node_in_group("world_tree")
	_bank = get_tree().get_first_node_in_group("resource_bank")
	_tide = get_tree().get_first_node_in_group("tide_manager")

	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -320
	_toast.offset_right = 320
	_toast.offset_top = 60
	_toast.offset_bottom = 92
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color(1.0, 0.84, 0.55))
	_toast.visible = false
	add_child(_toast)

	var tl := _panel(0)
	_day_label = _label(tl)
	_status_label = _label(tl)

	var tr := _panel(1)
	_stage_label = _label(tr)
	_heart_label = _label(tr)
	_sapwell_label = _label(tr)
	_meter_label = _label(tr)
	tr.add_child(HSeparator.new())
	_timber_label = _label(tr)
	_stone_label = _label(tr)
	_sap_label = _label(tr)
	_essence_label = _label(tr)
	_food_label = _label(tr)
	_light_label = _label(tr)
	_rare_label = _label(tr)

	var cp := _panel(2)
	_day_btn = Button.new()
	_day_btn.text = "Advance Day  ▶"
	_day_btn.pressed.connect(_on_day_pressed)
	cp.add_child(_day_btn)

	if _gs:
		_gs.day_changed.connect(_refresh.unbind(2))
		_gs.phase_changed.connect(_on_phase.unbind(1))
		_gs.night_resolved.connect(_update_day_btn)
	if _tree:
		_tree.stage_changed.connect(_refresh.unbind(2))
		_tree.heartroot_changed.connect(_on_heart_changed)
		_tree.heartroot_destroyed.connect(_on_defeat)
		_tree.crowned.connect(_on_crowned)
	if _bank:
		_bank.changed.connect(_refresh.unbind(2))
	var bs = get_tree().get_first_node_in_group("build_system")
	if bs:
		bs.buildings_changed.connect(_refresh)

	_refresh()
	_on_phase()
	UiTheme.skin(self)


func _panel(corner: int) -> VBoxContainer:
	var p := PanelContainer.new()
	add_child(p)
	if corner == 0:
		p.position = Vector2(16, 16)
	elif corner == 1:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		p.offset_right = -16
		p.offset_top = 16
	else:
		p.anchor_top = 1.0
		p.anchor_bottom = 1.0
		p.grow_vertical = Control.GROW_DIRECTION_BEGIN
		p.offset_left = 16
		p.offset_bottom = -16
	var vb := VBoxContainer.new()
	p.add_child(vb)
	return vb


func _label(parent: Node) -> Label:
	var l := Label.new()
	parent.add_child(l)
	return l


func _on_day_pressed() -> void:
	if _gs:
		_gs.request_advance()


func _update_day_btn() -> void:
	if _day_btn == null or _gs == null:
		return
	if _gs.is_tending():
		_day_btn.text = "Summon the Tide  ▶"
		_day_btn.disabled = false
	elif _gs.has_method("is_awaiting_dawn") and _gs.is_awaiting_dawn():
		_day_btn.text = "Greet the Dawn  ☀"
		_day_btn.disabled = false
	else:
		_day_btn.text = "The Dark wars…"
		_day_btn.disabled = true


func _on_phase() -> void:
	_update_day_btn()
	_refresh()


func _on_crowned() -> void:
	if _gs:
		_gs.crown_tree()
	_refresh()


func _on_heart_changed(_hp: int, _max_hp: int) -> void:
	_refresh()


func _on_defeat() -> void:
	_status_label.text = "DEFEAT — the Heartroot has fallen."


func _fmt_time(t: float) -> String:
	var s: int = int(ceil(t))
	return "%d:%02d" % [s / 60, s % 60]


func _refresh() -> void:
	if _gs:
		var phase_name := "Tending" if _gs.is_tending() else "ASSAULT"
		_day_label.text = "Day %d / %d   ·   Cycle %d   ·   %s" % [
			_gs.day, _gs.DAYS_PER_CYCLE, _gs.cycle, phase_name
		]
	if _tree:
		_stage_label.text = "Tree stage: %s" % _tree.get_stage_name()
		_heart_label.text = "Heartroot: %d / %d" % [_tree.heartroot_hp, _tree.heartroot_max_hp]
	_sapwell_label.text = "Sapwells: %d" % get_tree().get_nodes_in_group("sapwell").size()
	if _gs:
		_meter_label.text = "World Trees: %d / %d" % [_gs.trees_crowned, _gs.TOTAL_CONTINENTS]
	if _bank:
		_timber_label.text = "Timber: %d" % _bank.get_amount("timber")
		_stone_label.text = "Stone: %d" % _bank.get_amount("stone")
		_sap_label.text = "Sap: %d" % _bank.get_amount("sap")
		_essence_label.text = "Night's Essence: %d" % _bank.get_amount("essence")
		var grain: int = _bank.get_amount("grain")
		var meat: int = _bank.get_amount("meat")
		_food_label.text = "Grain: %d   Meat: %d" % [grain, meat]
		_food_label.visible = grain > 0 or meat > 0
		var light: int = _bank.get_amount("holy_light")
		_light_label.text = "Holy Light: %d" % light
		_light_label.visible = light > 0
		var rare: Array = []
		for pair in [["soft_wood", "Soft"], ["hard_wood", "Hard"], ["gold", "Gold"], ["ruby", "Ruby"], ["diamond", "Diamond"]]:
			var amt: int = _bank.get_amount(pair[0])
			if amt > 0:
				rare.append("%s %d" % [pair[1], amt])
		_rare_label.text = "  ".join(rare)
		_rare_label.visible = rare.size() > 0


func notify(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast_time = 5.0


func _process(_delta: float) -> void:
	if _toast and _toast_time > 0.0:
		_toast_time -= _delta
		if _toast_time <= 0.0:
			_toast.visible = false
	if _gs == null:
		return
	if _gs.is_assault():
		var n := get_tree().get_nodes_in_group("enemy").size()
		_status_label.text = ("Enemies remaining: %d" % n) if n > 0 else "The Dark gathers…"
	elif not _status_label.text.begins_with("DEFEAT"):
		var t: float = _gs.get_time_left()
		if t > 0.0:
			_status_label.text = "Build & gather — %s left" % _fmt_time(t)
		else:
			_status_label.text = "Time's up — summon the wave"
