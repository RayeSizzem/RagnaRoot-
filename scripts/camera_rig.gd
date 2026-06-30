extends Node3D
## Free-look strategy camera. The rig node is the focus point on the ground; the
## camera orbits it. The player can pan the focus across the map, orbit, and zoom,
## and snap back to the World Tree at any time.
##
## Controls:
##   W A S D / Arrows            -> pan the view across the map
##   Middle-mouse drag           -> grab-pan the map
##   Right-mouse drag            -> orbit (yaw + pitch)
##   Q / E                       -> rotate left / right
##   Mouse wheel                 -> zoom in / out
##   Home / F1                   -> recenter on the World Tree

@export var focus_height: float = 1.5
@export var distance: float = 14.0
@export var min_distance: float = 4.0
@export var max_distance: float = 320.0
@export var zoom_step: float = 2.0

@export var pitch_deg: float = 50.0
@export var min_pitch_deg: float = 12.0
@export var max_pitch_deg: float = 85.0

@export var orbit_sensitivity: float = 0.4    # degrees per pixel of drag
@export var key_rotate_speed: float = 90.0     # degrees/sec (Q/E)

@export var pan_speed: float = 0.7             # pan rate scales with zoom distance
@export var base_pan: float = 8.0              # minimum pan rate (units/sec) when zoomed in
@export var pan_drag: float = 0.018            # middle-drag world units per pixel (x distance)
@export var pan_limit: float = 300.0           # clamp focus to world bounds

var _yaw_deg: float = 0.0
var _orbiting: bool = false
var _panning: bool = false

@onready var _pitch: Node3D = $Pitch
@onready var _camera: Camera3D = $Pitch/Camera3D


func _ready() -> void:
	add_to_group("camera_rig")
	position.y = focus_height
	_apply()


## Snap the ground focus to a world position (keeps current orbit & zoom).
func focus_on(pos: Vector3) -> void:
	position.x = pos.x
	position.z = pos.z
	_clamp_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom(-zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom(zoom_step)
			MOUSE_BUTTON_RIGHT:
				_orbiting = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw_deg -= event.relative.x * orbit_sensitivity
			pitch_deg = clampf(
				pitch_deg + event.relative.y * orbit_sensitivity,
				min_pitch_deg, max_pitch_deg
			)
			_apply()
		elif _panning:
			var vecs := _cam_xz()
			var fwd: Vector3 = vecs[0]
			var right: Vector3 = vecs[1]
			var f: float = pan_drag * distance / 14.0
			position -= right * event.relative.x * f
			position += fwd * event.relative.y * f
			_clamp_focus()
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_HOME or event.keycode == KEY_F1):
		position.x = 0.0
		position.z = 0.0


func _process(delta: float) -> void:
	# Q/E rotate
	var turn := 0.0
	if Input.is_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_key_pressed(KEY_E):
		turn -= 1.0
	if turn != 0.0:
		_yaw_deg += turn * key_rotate_speed * delta
		_apply()

	# WASD / arrow pan (camera-relative)
	var vecs := _cam_xz()
	var fwd: Vector3 = vecs[0]
	var right: Vector3 = vecs[1]
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move += fwd
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move -= fwd
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move += right
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move -= right
	if move.length() > 0.0:
		var speed: float = distance * pan_speed + base_pan
		position += move.normalized() * speed * delta
		_clamp_focus()


## Camera forward & right, flattened to the ground plane (for screen-relative pan).
func _cam_xz() -> Array:
	var b := _camera.global_transform.basis
	var fwd := -b.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	var right := b.x
	right.y = 0.0
	return [fwd.normalized(), right.normalized()]


func _clamp_focus() -> void:
	position.x = clampf(position.x, -pan_limit, pan_limit)
	position.z = clampf(position.z, -pan_limit, pan_limit)
	position.y = focus_height


func _zoom(amount: float) -> void:
	distance = clampf(distance + amount, min_distance, max_distance)
	_apply()


func _apply() -> void:
	rotation.y = deg_to_rad(_yaw_deg)
	_pitch.rotation.x = -deg_to_rad(pitch_deg)
	_camera.position = Vector3(0, 0, distance)
