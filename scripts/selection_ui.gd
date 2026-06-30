extends CanvasLayer
## Shows the selected building's info and an Upgrade button (top-right).
## Click a building to select; click empty ground to clear.

var _bank
var _current
var _panel: PanelContainer
var _info: Label
var _up_btn: Button
var _fog_btn: Button
var _channel_btn: Button
var _mend_btn: Button
var _destroy_btn: Button
var _reloc_btn: Button
var _wm
var _gs
var _bs
var _picker_mode := "assign"
var _work_box: VBoxContainer
var _house_box: VBoxContainer
var _house_btn: Button
var _roster_box: VBoxContainer
var _roster_panel: PanelContainer
var _roster_title: Label
var _assign_btn: Button
var _assign_box: VBoxContainer
var _assign_panel: PanelContainer
var _assign_title: Label
var _remove_btn: Button
var _assign_open := false
var _cam
var _row: HBoxContainer
const SP := ["human", "elf", "dwarf"]
const HOUSE_LABEL := {"human": "Human Lodge", "elf": "Elven Bower", "dwarf": "Dwarven Hold"}


func _ready() -> void:
	_bank = get_tree().get_first_node_in_group("resource_bank")
	_wm = get_tree().get_first_node_in_group("world_manager")
	_gs = get_tree().get_first_node_in_group("game_state")
	_bs = get_tree().get_first_node_in_group("build_system")
	_cam = get_tree().get_first_node_in_group("camera_rig")
	if _bs:
		_bs.building_selected.connect(_on_selected)
		_bs.selection_cleared.connect(_on_cleared)
	if _gs:
		_gs.phase_changed.connect(_on_phase_shift.unbind(1))
		if _gs.has_signal("night_resolved"):
			_gs.night_resolved.connect(_on_phase_shift)
	_build_ui()
	UiTheme.skin(self)


func _on_phase_shift() -> void:
	if _panel and _panel.visible and _current != null and is_instance_valid(_current):
		_refresh()


func _build_ui() -> void:
	_row = HBoxContainer.new()
	_row.anchor_left = 0.5
	_row.anchor_right = 0.5
	_row.anchor_top = 1.0
	_row.anchor_bottom = 1.0
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_row.offset_bottom = -16
	_row.add_theme_constant_override("separation", 12)
	add_child(_row)

	_panel = PanelContainer.new()
	_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	_panel.visible = false
	_row.add_child(_panel)

	var vb := VBoxContainer.new()
	_panel.add_child(vb)
	_info = Label.new()
	vb.add_child(_info)

	_up_btn = Button.new()
	_up_btn.text = "Upgrade"
	_up_btn.pressed.connect(_on_upgrade)
	vb.add_child(_up_btn)
	_fog_btn = Button.new()
	_fog_btn.text = "Clear Fog"
	_fog_btn.pressed.connect(_on_clear_fog)
	vb.add_child(_fog_btn)
	_channel_btn = Button.new()
	_channel_btn.text = "Channel Holy Light"
	_channel_btn.pressed.connect(_on_channel)
	vb.add_child(_channel_btn)
	_mend_btn = Button.new()
	_mend_btn.text = "Mend Heartroot"
	_mend_btn.pressed.connect(_on_mend)
	vb.add_child(_mend_btn)
	_reloc_btn = Button.new()
	_reloc_btn.text = "Relocate"
	_reloc_btn.pressed.connect(_on_relocate)
	vb.add_child(_reloc_btn)
	# Worksite controls: Assign opens a separate settler-picker panel.
	_work_box = VBoxContainer.new()
	vb.add_child(_work_box)
	_assign_btn = Button.new()
	_assign_btn.text = "Assign Worker"
	_assign_btn.pressed.connect(_on_assign_toggle)
	_work_box.add_child(_assign_btn)
	_remove_btn = Button.new()
	_remove_btn.text = "Remove worker"
	_remove_btn.pressed.connect(_on_remove_worker)
	_work_box.add_child(_remove_btn)

	_house_box = VBoxContainer.new()
	vb.add_child(_house_box)
	_house_btn = Button.new()
	_house_btn.text = "Upgrade Dwelling…"
	_house_btn.pressed.connect(_on_house_toggle)
	_house_box.add_child(_house_btn)

	_destroy_btn = Button.new()
	_destroy_btn.text = "Destroy"
	_destroy_btn.pressed.connect(_on_destroy)
	vb.add_child(_destroy_btn)

	# --- Roster panel: who lives/works here (sits beside the info panel) ---
	_roster_panel = _make_side_panel()
	_roster_title = _make_panel_title(_roster_panel, "Residents")
	_roster_box = _panel_list_box(_roster_panel)

	# --- Assign-picker panel: choose a settler (sits beside the others) ---
	_assign_panel = _make_side_panel()
	_assign_title = _make_panel_title(_assign_panel, "Assign Worker")
	_assign_box = _panel_list_box(_assign_panel)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_assign)
	(_assign_panel.get_child(0) as VBoxContainer).add_child(close)


## A panel that sits in the bottom row beside the info panel, bottom-aligned.
func _make_side_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_SHRINK_END
	p.visible = false
	_row.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	p.add_child(col)
	return p


func _make_panel_title(panel: PanelContainer, text: String) -> Label:
	var col := panel.get_child(0) as VBoxContainer
	var t := Label.new()
	t.text = text
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(t)
	return t


## A scrollable list box (capped height) inside a side panel's column.
func _panel_list_box(panel: PanelContainer) -> VBoxContainer:
	var col := panel.get_child(0) as VBoxContainer
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.clip_contents = true
	col.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)
	return box


func _on_selected(b) -> void:
	_current = b
	_assign_open = false
	_assign_panel.visible = false
	_panel.visible = true
	_refresh()


func _on_cleared() -> void:
	_current = null
	_panel.visible = false
	_roster_panel.visible = false
	_assign_panel.visible = false


func _on_clear_fog() -> void:
	if _gs and _gs.has_method("can_build") and not _gs.can_build():
		return
	if _current == null or not _current.has_method("get_fog_cost"):
		return
	if _bs == null or not _bs.has_method("begin_fog_targeting"):
		# Fallback to the old auto-reveal if the build system is unavailable.
		if _current.has_method("clear_fog"):
			_current.clear_fog(_bank, _wm)
			_refresh()
		return
	if _bank and not _bank.can_afford(_current.get_fog_cost()):
		return
	_bs.begin_fog_targeting(_current.get_fog_cost())


func _on_channel() -> void:
	if _current and _current.has_method("channel_holy_light"):
		_current.channel_holy_light()
		_refresh()


func _on_mend() -> void:
	if _current and _current.has_method("mend_heartroot"):
		_current.mend_heartroot()
		_refresh()


func _on_destroy() -> void:
	if _current == null or _bs == null or not _bs.has_method("destroy_building"):
		return
	if _bs.has_method("can_destroy") and not _bs.can_destroy(_current):
		return
	_bs.destroy_building(_current)
	# building is gone; panel will be hidden by the selection_cleared signal


func _on_relocate() -> void:
	if _current == null or _bs == null or not _bs.has_method("begin_hero_relocation"):
		return
	if not _current.is_in_group("hero"):
		return
	_bs.begin_hero_relocation(_current)
	_panel.visible = false


func _refund_text(b) -> String:
	if b == null or not b.has_meta("build_cost"):
		return "Destroy"
	var cost: Dictionary = b.get_meta("build_cost", {})
	var parts: Array = []
	for k in cost:
		var half: int = int(cost[k]) / 2
		if half > 0:
			parts.append("%d%s" % [half, String(k).substr(0, 1).to_upper()])
	if parts.is_empty():
		return "Destroy"
	return "Destroy  (refund %s)" % ", ".join(parts)


func _member_text(r) -> String:
	var nm: String = r.display_name
	var trv: String = Folk.TRAIT_LABEL.get(r.trait_key, "?")
	return "%s · %s L%d" % [nm, trv, r.trait_level]


func _on_roster_pick(r) -> void:
	if not is_instance_valid(r):
		_refresh()
		return
	if _cam and _cam.has_method("focus_on"):
		_cam.focus_on(r.global_position)
	if _bs and _bs.has_method("select_node"):
		_bs.select_node(r)


func _refresh_roster_panel() -> void:
	for c in _roster_box.get_children():
		c.queue_free()
	var has_roster: bool = _current != null and (_current.has_method("get_workers") or _current.has_method("get_residents"))
	_roster_panel.visible = has_roster
	if not has_roster:
		return
	var members: Array = []
	var head := "Workers"
	if _current.has_method("get_workers"):
		members = _current.get_workers()
		head = "Workers"
	else:
		members = _current.get_residents()
		head = "Residents"
	if _current.has_method("get_roster_label"):
		head = _current.get_roster_label()
	_roster_title.text = "%s  (%d)" % [head, members.size()]
	for r in members:
		if not is_instance_valid(r):
			continue
		var b := Button.new()
		b.text = _member_text(r)
		b.pressed.connect(_on_roster_pick.bind(r))
		_roster_box.add_child(b)
	if members.is_empty():
		var l := Label.new()
		l.text = "Nobody yet."
		_roster_box.add_child(l)
	UiTheme.skin(self)
	_size_list(_roster_box)


func _on_assign_toggle() -> void:
	_assign_open = not _assign_open
	if _assign_open:
		_rebuild_assign_list()
	_assign_panel.visible = _assign_open


func _on_house_toggle() -> void:
	_picker_mode = "become"
	_assign_open = not _assign_open
	if _assign_open:
		_rebuild_assign_list()
	_assign_panel.visible = _assign_open


func _on_become_pick(sp: String) -> void:
	_assign_open = false
	_assign_panel.visible = false
	_on_become(sp)


func _close_assign() -> void:
	_assign_open = false
	_assign_panel.visible = false


func _rebuild_assign_list() -> void:
	for c in _assign_box.get_children():
		c.queue_free()
	if _picker_mode == "become":
		_assign_title.text = "Upgrade Dwelling"
		var hcost: Dictionary = _current.get_become_cost() if _current.has_method("get_become_cost") else {}
		var can_h: bool = (_gs == null) or _gs.can_build()
		var hafford: bool = (_bank == null) or _bank.can_afford(hcost)
		for sp in SP:
			var b := Button.new()
			b.text = "Become %s (%dT %dS)" % [HOUSE_LABEL.get(sp, sp), hcost.get("timber", 0), hcost.get("stone", 0)]
			b.disabled = not (can_h and hafford)
			b.pressed.connect(_on_become_pick.bind(sp))
			_assign_box.add_child(b)
		UiTheme.skin(self)
		_size_list(_assign_box)
		return
	if _picker_mode == "promote":
		_assign_title.text = "Promote Warrior"
		var elig: Array = _current.eligible_warriors() if _current.has_method("eligible_warriors") else []
		for r in elig:
			if not is_instance_valid(r):
				continue
			var b := Button.new()
			b.text = "%s · Warrior L%d ✦" % [r.display_name, r.trait_level]
			b.pressed.connect(_on_assign_pick.bind(r))
			_assign_box.add_child(b)
		if elig.is_empty():
			var l := Label.new()
			l.text = "No warriors ready."
			_assign_box.add_child(l)
		UiTheme.skin(self)
		_size_list(_assign_box)
		return
	# assign mode
	var open: int = _current.available_slots() if _current.has_method("available_slots") else 0
	var lbl: String = _current.get_assign_label() if _current.has_method("get_assign_label") else "Assign Worker"
	var warriors_only: bool = _current.has_method("accepts_resident")
	_assign_title.text = "%s  (%d slot%s)" % [lbl, open, "" if open == 1 else "s"]
	var any := false
	for r in get_tree().get_nodes_in_group("resident"):
		if not is_instance_valid(r) or r.has_job():
			continue
		if warriors_only and not _current.accepts_resident(r):
			continue
		any = true
		var b := Button.new()
		var hint := ""
		if r.has_method("is_on_trait") and r.is_on_trait(_current):
			hint = "   ✓on-trait"
		b.text = "%s · %s%s" % [r.display_name, Folk.TRAIT_LABEL.get(r.trait_key, "?"), hint]
		b.disabled = open <= 0
		b.pressed.connect(_on_assign_pick.bind(r))
		_assign_box.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "No idle warriors." if warriors_only else "No idle settlers."
		_assign_box.add_child(l)
	UiTheme.skin(self)
	_size_list(_assign_box)


func _on_assign_pick(r) -> void:
	if _picker_mode == "promote":
		if _gs and _gs.has_method("can_build") and not _gs.can_build():
			return
		if _current and _current.has_method("promote") and is_instance_valid(r):
			_current.promote(r)
		_refresh()
		var slot: bool = _current.has_method("has_slot") and _current.has_slot()
		var more: bool = _current.has_method("eligible_warriors") and not _current.eligible_warriors().is_empty()
		if _assign_open and slot and more:
			_rebuild_assign_list()
		else:
			_close_assign()
		return
	# assign mode
	if not _assign_allowed(_current):
		return
	if _current and _current.has_method("assign_resident") and is_instance_valid(r):
		_current.assign_resident(r)
	_refresh()
	var open: int = _current.available_slots() if (_current and _current.has_method("available_slots")) else 0
	if open <= 0:
		_close_assign()
	elif _assign_open:
		_rebuild_assign_list()


## Garrisoning a combat building (tower) is allowed mid-assault; everything else
## is gated to the build/tending phase.
func _assign_allowed(b) -> bool:
	if _gs == null:
		return true
	if b and b.has_method("is_combat_building") and b.is_combat_building():
		if _gs.has_method("can_manage_combat"):
			return _gs.can_manage_combat()
		return true
	return (not _gs.has_method("can_build")) or _gs.can_build()


## Cap a list box's scroll height to its content, up to a maximum.
## Cap a list box's scroll window to at most 5 rows; taller lists scroll. The row
## height is measured from the first real button so it matches the themed font.
func _size_list(box: VBoxContainer) -> void:
	var scroll = box.get_parent()
	if scroll == null:
		return
	var rows: int = maxi(box.get_child_count(), 1)
	var row_h: float = 64.0
	for c in box.get_children():
		var mh: float = c.get_combined_minimum_size().y
		if mh > 1.0:
			row_h = mh
			break
	var shown: int = mini(rows, 5)
	scroll.custom_minimum_size.y = shown * (row_h + 2.0) + 2.0


func _on_remove_worker() -> void:
	if _gs and not _gs.can_build():
		return
	if _current and _current.has_method("remove_worker"):
		_current.remove_worker()
		_refresh()


func _on_become(species: String) -> void:
	if _gs and not _gs.can_build():
		return
	if _current and _current.has_method("upgrade_into"):
		_current.upgrade_into(species, _bank)
		_refresh()
func _action_allowed(combat: bool) -> bool:
	if _gs == null:
		return true
	if combat and _gs.has_method("can_manage_combat"):
		return _gs.can_manage_combat()
	return (not _gs.has_method("can_build")) or _gs.can_build()


func _on_upgrade() -> void:
	var is_tower: bool = _current != null and _current.is_in_group("tower")
	if not _action_allowed(is_tower):
		return
	if _current and _current.has_method("try_upgrade"):
		_current.try_upgrade(_bank)
		_refresh()


func _refresh() -> void:
	if _current == null:
		return
	_info.text = _current.get_info() if _current.has_method("get_info") else "Building"
	_refresh_roster_panel()
	var is_promote: bool = _current.has_method("promote")
	var is_work: bool = _current.has_method("assign_resident")
	var is_house: bool = _current.has_method("upgrade_into")
	var house_pick: bool = is_house and _current.can_become()
	_work_box.visible = is_work or is_promote
	_house_box.visible = house_pick
	if not (is_work or is_promote or house_pick):
		_assign_panel.visible = false
		_assign_open = false
	if house_pick and not (is_work or is_promote):
		_picker_mode = "become"
	if is_work:
		_picker_mode = "assign"
		var can_a: bool = _assign_allowed(_current)
		var open: int = _current.available_slots() if _current.has_method("available_slots") else 0
		var lbl: String = _current.get_assign_label() if _current.has_method("get_assign_label") else "Assign Worker"
		_assign_btn.text = "%s  (%d slot%s)" % [lbl, open, "" if open == 1 else "s"]
		_assign_btn.disabled = (not can_a) or open <= 0
		_remove_btn.visible = true
		_remove_btn.disabled = (not can_a) or (_current.has_method("worker_count") and _current.worker_count() <= 0)
	elif is_promote:
		_picker_mode = "promote"
		var n: int = _current.eligible_warriors().size() if _current.has_method("eligible_warriors") else 0
		var can_p: bool = (_gs == null) or _gs.can_build()
		var slot: bool = _current.has_slot() if _current.has_method("has_slot") else true
		var cost: Dictionary = _current.get_promote_cost() if _current.has_method("get_promote_cost") else {}
		var afford: bool = (_bank == null) or _bank.can_afford(cost)
		_assign_btn.text = "Promote Warrior  (%d ready)" % n
		_assign_btn.disabled = (not can_p) or n <= 0 or (not slot) or (not afford)
		_remove_btn.visible = false
	if _assign_open and (is_work or is_promote or _picker_mode == "become"):
		_rebuild_assign_list()
	if _house_box.visible:
		var hcost: Dictionary = _current.get_become_cost() if _current.has_method("get_become_cost") else {}
		var can_h: bool = (_gs == null) or _gs.can_build()
		var hafford: bool = (_bank == null) or _bank.can_afford(hcost)
		_house_btn.text = "Upgrade Dwelling (%dT %dS)…" % [hcost.get("timber", 0), hcost.get("stone", 0)]
		_house_btn.disabled = not (can_h and hafford)
	_fog_btn.visible = _current.has_method("clear_fog")
	if _fog_btn.visible and _current.has_method("get_fog_cost"):
		var fc: Dictionary = _current.get_fog_cost()
		_fog_btn.text = "Clear Fog — pick block (%dW %dS %d Sap)" % [fc.get("timber", 0), fc.get("stone", 0), fc.get("sap", 0)]
	_channel_btn.visible = _current.has_method("channel_holy_light")
	if _channel_btn.visible:
		var amt: int = _current.get_channel_amount() if _current.has_method("get_channel_amount") else 0
		_channel_btn.text = "Channel Holy Light  (%d Essence → %d Light)" % [amt, amt]
		_channel_btn.disabled = amt <= 0
	_mend_btn.visible = _current.has_method("mend_heartroot")
	if _mend_btn.visible:
		var ml: int = _current.get_mend_light() if _current.has_method("get_mend_light") else 0
		var mh: int = _current.get_mend_heal() if _current.has_method("get_mend_heal") else 0
		_mend_btn.text = "Mend Heartroot  (%d Light → +%d HP)" % [ml, mh]
		_mend_btn.disabled = not (_current.has_method("can_mend") and _current.can_mend())

	var is_hero: bool = _current.is_in_group("hero")
	var is_resident: bool = _current.is_in_group("resident")
	_reloc_btn.visible = is_hero
	if is_hero:
		var can_move: bool = (_gs == null) or (not _gs.has_method("can_manage_combat")) or _gs.can_manage_combat()
		_reloc_btn.disabled = not can_move
	_destroy_btn.visible = not is_hero and not is_resident and _bs != null and _bs.has_method("destroy_building")
	if _destroy_btn.visible:
		_destroy_btn.text = _refund_text(_current)
		_destroy_btn.disabled = _bs.has_method("can_destroy") and not _bs.can_destroy(_current)
	if _current.has_method("promote") or _current.has_method("upgrade_into"):
		_up_btn.visible = false
	elif _current.has_method("get_upgrade_cost"):
		_up_btn.visible = true
		var c: Dictionary = _current.get_upgrade_cost()
		if c.is_empty():
			_up_btn.text = "Max level"
			_up_btn.disabled = true
		else:
			_up_btn.text = "Upgrade (%dT %dS)" % [c.get("timber", 0), c.get("stone", 0)]
			var is_tower: bool = _current.is_in_group("tower")
			var afford: bool = (_bank == null) or _bank.can_afford(c)
			_up_btn.disabled = not (_action_allowed(is_tower) and afford)
	else:
		_up_btn.visible = false
