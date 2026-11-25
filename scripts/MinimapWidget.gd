class_name MinimapWidget
extends Control

var battle_manager: BattleManager
var rts_camera: RtsCamera
var world_width: float = 58.0
var world_depth: float = 58.0
var dragging: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(220, 220)
	size = Vector2(220, 220)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			dragging = mb.pressed
			if dragging:
				_jump_from_local(mb.position)
	elif event is InputEventMouseMotion and dragging:
		_jump_from_local((event as InputEventMouseMotion).position)

func _jump_from_local(pos: Vector2) -> void:
	if rts_camera == null:
		return
	var u := clampf(pos.x / maxf(1.0, size.x), 0.0, 1.0)
	var v := clampf(pos.y / maxf(1.0, size.y), 0.0, 1.0)
	var wx := (u - 0.5) * world_width
	var wz := (v - 0.5) * world_depth
	rts_camera.jump_to(wx, wz)

func _draw() -> void:
	if battle_manager != null and battle_manager.terrain != null and battle_manager.terrain.diffuse_texture != null:
		draw_texture_rect(battle_manager.terrain.diffuse_texture, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.10, 0.12, 1.0), true)

	if battle_manager != null:
		for u in battle_manager.units:
			var mx := (u.pos.x / world_width + 0.5) * size.x
			var my := (u.pos.z / world_depth + 0.5) * size.y
			var col := Color(0.28, 0.62, 1.0) if u.team == 0 else Color(1.0, 0.30, 0.25)
			var sz := 3.5 if u.is_vehicle else 2.2
			draw_rect(Rect2(mx - sz * 0.5, my - sz * 0.5, sz, sz), col, true)

	if rts_camera != null:
		var cx := (rts_camera.position.x / world_width + 0.5) * size.x
		var cy := (rts_camera.position.z / world_depth + 0.5) * size.y
		var box_w := clampf(rts_camera.current_distance * 2.1, 20.0, size.x * 0.92)
		var box_h := box_w * 0.58
		draw_rect(Rect2(cx - box_w * 0.5, cy - box_h * 0.5, box_w, box_h), Color(1.0, 1.0, 1.0, 0.92), false, 1.2)
