extends CanvasLayer
## Building menu. Toggle with the "B" icon (bottom-right) or the B key.
## Tabs: Towers (12 kinds, unlocked as the World Tree grows), Resources, Misc.

const TOWER := preload("res://scenes/tower.tscn")
const TOWER_SCRIPT := preload("res://scripts/buildings/tower.gd")
const SAPWELL := preload("res://scenes/buildings/sapwell.tscn")
const TIMBER_HUT := preload("res://scenes/buildings/timber_hut.tscn")
const MASON_HUT := preload("res://scenes/buildings/mason_hut.tscn")
const FARMSTEAD := preload("res://scenes/buildings/farmstead.tscn")
const PASTURE := preload("res://scenes/buildings/pasture.tscn")
const WOODEN_HUT := preload("res://scenes/buildings/wooden_hut.tscn")
const SCOUT_HUT := preload("res://scenes/buildings/scout_hut.tscn")
const HALL := preload("res://scenes/buildings/hall_of_heroes.tscn")
const TEMPLE := preload("res://scenes/buildings/temple.tscn")
const KNIGHT_ORDER := preload("res://scenes/buildings/knight_order.tscn")
const ARCANE_SPIRE := preload("res://scenes/buildings/arcane_spire.tscn")
const STAGE_NAMES := ["Sapling", "Sentinel", "Greatbough", "Canopy", "Worldcrown"]

var _build
var _tree
var _panel: PanelContainer
var _categories: Array = []
var _tower_buttons: Array = []   # [{btn, item}]


func _ready() -> void:
	_build = get_tree().get_first_node_in_group("build_system")
	_tree = get_tree().get_first_node_in_group("world_tree")
	_categories = [
		{"title": "Towers", "items": _tower_items()},
		{"title": "Resources", "items": [
			{"name": "Wooden Hut", "scene": WOODEN_HUT, "cost": {"timber": 20, "stone": 5}, "limit": {}, "requires": {}},
			{"name": "Timber Hut", "scene": TIMBER_HUT, "cost": {"timber": 20, "stone": 10}, "limit": {}, "requires": {"family": "wood", "cells": 2, "housing": true}},
			{"name": "Mason Hut", "scene": MASON_HUT, "cost": {"timber": 20, "stone": 10}, "limit": {}, "requires": {"family": "mineral", "cells": 2, "housing": true}},
			{"name": "Farmstead", "scene": FARMSTEAD, "cost": {"timber": 60, "stone": 30}, "limit": {}, "requires": {"housing": true}, "foot": [2, 2]},
			{"name": "Pasture", "scene": PASTURE, "cost": {"timber": 60, "stone": 30}, "limit": {}, "requires": {"housing": true}, "foot": [2, 2]},
		]},
		{"title": "Misc", "items": [
			{"name": "Sapwell", "scene": SAPWELL, "cost": {"timber": 50, "stone": 50},
				"limit": {"group": "sapwell", "base": 1, "per_stage": 1, "max": 4}, "requires": {"housing": true}},
			{"name": "Scout Hut", "scene": SCOUT_HUT, "cost": {"timber": 100, "stone": 100}, "limit": {}, "requires": {"housing": true}},
			{"name": "Temple", "scene": TEMPLE, "cost": {"timber": 400, "stone": 400, "sap": 300}, "limit": {"group": "temple", "base": 1, "per_stage": 1, "max": 3}, "requires": {"housing": true}, "shape": [[0, 0], [1, 0], [2, 0], [1, 1]]},
			{"name": "Knight Order", "scene": KNIGHT_ORDER, "cost": {"timber": 150, "stone": 120}, "limit": {"group": "knight_order", "base": 1, "per_stage": 1, "max": 3}, "requires": {"housing": true}, "foot": [2, 1]},
			{"name": "Arcane Spire", "scene": ARCANE_SPIRE, "cost": {"timber": 120, "stone": 150, "sap": 150}, "limit": {"group": "spire", "base": 1, "per_stage": 1, "max": 3}, "requires": {"housing": true}},
			{"name": "Hall of Heroes", "scene": HALL, "cost": {"timber": 1000, "stone": 1000},
				"limit": {"group": "hall", "base": 1, "per_stage": 0, "max": 1}, "requires": {"housing": true}},
		]},
	]
	_build_ui()
	UiTheme.skin(self)


## Build the 12 tower options from the tower data table, ordered by unlock stage.
func _tower_items() -> Array:
	var t: Dictionary = TOWER_SCRIPT.table()
	var items: Array = []
	for st in range(5):
		for key in t.keys():
			var d: Dictionary = t[key]
			if int(d["stage"]) == st:
				items.append({
					"name": d["name"], "scene": TOWER, "cost": d["cost"],
					"limit": {}, "requires": {"housing": true},
					"props": {"kind": key}, "stage": st,
				})
	return items


func _build_ui() -> void:
	var btn := Button.new()
	btn.text = "B"
	btn.anchor_left = 1.0
	btn.anchor_top = 1.0
	btn.anchor_right = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -72
	btn.offset_top = -72
	btn.offset_right = -16
	btn.offset_bottom = -16
	btn.pressed.connect(_toggle_menu)
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
	title.text = "Build"
	title.add_theme_font_size_override("font_size", 16)
	if UiTheme.display_font():
		title.add_theme_font_override("font", UiTheme.display_font())
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	outer.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(248, 300)
	outer.add_child(tabs)

	for cat in _categories:
		var scroll := ScrollContainer.new()
		scroll.name = cat.title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 4)
		scroll.add_child(page)
		for opt in cat.items:
			var c: Dictionary = opt.cost
			var b := Button.new()
			b.custom_minimum_size = Vector2(228, 0)
			b.pressed.connect(_on_option.bind(opt))
			page.add_child(b)
			if opt.has("stage"):
				_tower_buttons.append({"btn": b, "item": opt})
				_set_tower_text(b, opt)
			else:
				b.text = "%s\n%dT  %dS" % [opt.name, c.get("timber", 0), c.get("stone", 0)]


func _set_tower_text(b: Button, opt: Dictionary) -> void:
	var c: Dictionary = opt.cost
	var st: int = opt.stage
	var unlocked: bool = _tree != null and _tree.stage >= st
	if unlocked:
		b.disabled = false
		b.text = "%s\n%dT  %dS" % [opt.name, c.get("timber", 0), c.get("stone", 0)]
	else:
		b.disabled = true
		b.text = "🔒 %s\nUnlocks: %s" % [opt.name, STAGE_NAMES[st]]


func _refresh_towers() -> void:
	for entry in _tower_buttons:
		_set_tower_text(entry.btn, entry.item)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_B:
		_toggle_menu()


func _toggle_menu() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh_towers()


func _on_option(opt: Dictionary) -> void:
	if _build:
		_build.toggle_build(opt.scene, opt.cost, opt.get("limit", {}), opt.get("requires", {}), opt.get("props", {}), opt.get("foot", [1, 1]), opt.get("shape", []))
	_panel.visible = false
