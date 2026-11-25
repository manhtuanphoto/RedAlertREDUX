class_name RtsCamera
extends Node3D

@export var pan_speed: float = 42.0
@export var min_zoom: float = 12.0
@export var max_zoom: float = 36.0
@export var zoom_step: float = 3.0
@export var pitch_deg: float = -56.0

var target_pos: Vector3 = Vector3.ZERO
var target_zoom: float = 22.0
var current_distance: float = 22.0
var bound_half_w: float = 28.0
var bound_half_d: float = 28.0
var is_ortho: bool = true
var dragging: bool = false
var camera: Camera3D

func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 1.0
	camera.far = 400.0
	add_child(camera)
	set_camera_mode(true)
	_update_transform(1.0)

func set_camera_mode(ortho: bool) -> void:
	is_ortho = ortho
	if is_ortho:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 24.0
	_update_transform(1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			target_zoom = clampf(target_zoom - zoom_step, min_zoom, max_zoom)
			_clamp_target()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_zoom = clampf(target_zoom + zoom_step, min_zoom, max_zoom)
			_clamp_target()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			dragging = mb.pressed
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		var scale_pan := current_distance * 0.0018
		target_pos.x -= mm.relative.x * scale_pan
		target_pos.z -= mm.relative.y * scale_pan * 1.25
		_clamp_target()

func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0

	if move.length_squared() > 0.0:
		move = move.normalized()
		var speed := pan_speed * (current_distance / 32.0)
		target_pos.x += move.x * speed * delta
		target_pos.z += move.y * speed * delta
		_clamp_target()

	_update_transform(minf(1.0, delta * 12.0))

func jump_to(world_x: float, world_z: float) -> void:
	target_pos.x = world_x
	target_pos.z = world_z
	_clamp_target()

func _clamp_target() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var aspect := vp_size.x / maxf(1.0, vp_size.y)
	var ortho_size := current_distance * 0.78
	var half_view_w := ortho_size * 0.5 * aspect
	var half_view_d := (ortho_size * 0.5) / maxf(0.25, absf(sin(deg_to_rad(pitch_deg))))

	var limit_x := maxf(0.0, bound_half_w - half_view_w)
	var limit_z := maxf(0.0, bound_half_d - half_view_d)
	target_pos.x = clampf(target_pos.x, -limit_x, limit_x)
	target_pos.z = clampf(target_pos.z, -limit_z, limit_z)

func _update_transform(weight: float) -> void:
	current_distance = lerpf(current_distance, target_zoom, weight)
	position = position.lerp(target_pos, weight)

	var pitch_rad := deg_to_rad(pitch_deg)
	var dir := Vector3(0.0, -sin(pitch_rad), cos(pitch_rad))

	if is_ortho:
		# Keep camera far back in Ortho so hills/trees never clip the near plane
		camera.size = current_distance * 0.78
		camera.position = dir * 110.0
	else:
		# Low-FOV (24 deg) HD-2D perspective matched to the exact same visual scale as Ortho
		camera.position = dir * (current_distance * 1.85)

	camera.look_at(position, Vector3.UP)
