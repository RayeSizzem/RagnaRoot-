extends RefCounted
class_name UiTheme
## Shared woodland / mythological UI skin. Built once and assigned to the window
## so every Control inherits it: warm bark-brown panels with bright bronze/gold
## borders, mossy-green accents, parchment text, gold titles. Cinzel for titles
## & buttons, Spectral for body.

const GOLD := Color(0.92, 0.76, 0.4)
const PARCHMENT := Color(0.93, 0.87, 0.75)
const DIM := Color(0.58, 0.53, 0.43)
const BRONZE := Color(0.62, 0.47, 0.24)        # visible metal trim
const BRONZE_LIT := Color(0.85, 0.66, 0.34)    # hover / highlight
const MOSS := Color(0.27, 0.34, 0.17)          # green accent

static var _display: FontFile
static var _body: FontFile
static var _theme: Theme


## Cached single theme instance shared across all UIs.
static func shared() -> Theme:
	if _theme == null:
		_theme = build_theme()
	return _theme


## Apply the skin to a CanvasLayer's UI. CanvasLayer breaks theme inheritance,
## so each UI must set the theme on its top-level Controls explicitly.
static func skin(node: Node) -> void:
	var th := shared()
	for c in node.get_children():
		if c is Control:
			c.theme = th


static func display_font() -> FontFile:
	if _display == null and ResourceLoader.exists("res://ui/fonts/Cinzel.ttf"):
		_display = load("res://ui/fonts/Cinzel.ttf")
	return _display


static func body_font() -> FontFile:
	if _body == null and ResourceLoader.exists("res://ui/fonts/Spectral-Regular.ttf"):
		_body = load("res://ui/fonts/Spectral-Regular.ttf")
	return _body


static func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


static func _btn(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := _box(bg, border, bw, 6)
	s.content_margin_left = 13.0
	s.content_margin_right = 13.0
	s.content_margin_top = 7.0
	s.content_margin_bottom = 7.0
	return s


## Ornate 9-patch frame for panels; flat bark fallback if the texture is missing.
static func _frame() -> StyleBox:
	if ResourceLoader.exists("res://ui/frame_panel.png"):
		var sb := StyleBoxTexture.new()
		sb.texture = load("res://ui/frame_panel.png")
		sb.set_texture_margin_all(32.0)
		sb.content_margin_left = 18.0
		sb.content_margin_right = 18.0
		sb.content_margin_top = 18.0
		sb.content_margin_bottom = 18.0
		return sb
	var f := _box(Color(0.15, 0.11, 0.07, 0.96), BRONZE, 2, 9)
	f.set_content_margin_all(14.0)
	return f


static func build_theme() -> Theme:
	var t := Theme.new()
	var body := body_font()
	var disp := display_font()
	if body:
		t.default_font = body
	t.default_font_size = 16

	t.set_color("font_color", "Label", PARCHMENT)

	# Panels — ornate 9-patch bronze/gold frame (falls back to flat if missing)
	var panel := _frame()
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel.duplicate())

	# Buttons — carved wood plaques, bronze trim, gold on hover
	if disp:
		t.set_font("font", "Button", disp)
	t.set_font_size("font_size", "Button", 16)
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", BRONZE_LIT)
	t.set_color("font_focus_color", "Button", PARCHMENT)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_stylebox("normal", "Button", _btn(Color(0.26, 0.19, 0.11), BRONZE, 2))
	t.set_stylebox("hover", "Button", _btn(Color(0.36, 0.27, 0.14), BRONZE_LIT, 2))
	t.set_stylebox("pressed", "Button", _btn(Color(0.18, 0.13, 0.08), BRONZE, 2))
	t.set_stylebox("disabled", "Button", _btn(Color(0.16, 0.15, 0.13, 0.7), Color(0.3, 0.27, 0.2), 1))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# Tabs — mossy green when active, bark when not
	if disp:
		t.set_font("font", "TabContainer", disp)
	t.set_font_size("font_size", "TabContainer", 15)
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_color("font_hovered_color", "TabContainer", PARCHMENT)
	var tab_sel := _box(MOSS, BRONZE_LIT, 2, 6)
	tab_sel.set_content_margin_all(8.0)
	var tab_un := _box(Color(0.16, 0.12, 0.08), BRONZE, 1, 6)
	tab_un.set_content_margin_all(8.0)
	var tab_hov := _box(Color(0.22, 0.17, 0.1), BRONZE_LIT, 1, 6)
	tab_hov.set_content_margin_all(8.0)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	t.set_stylebox("panel", "TabContainer", _frame())

	# Progress bars — bronze frame, mossy-gold fill
	t.set_stylebox("background", "ProgressBar", _box(Color(0.08, 0.07, 0.05), BRONZE, 1, 4))
	t.set_stylebox("fill", "ProgressBar", _box(Color(0.5, 0.62, 0.26), BRONZE_LIT, 0, 4))
	t.set_color("font_color", "ProgressBar", PARCHMENT)

	return t
