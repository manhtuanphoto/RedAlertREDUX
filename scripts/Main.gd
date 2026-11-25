extends Node3D

const RtsData = preload("res://scripts/RtsData.gd")

var terrain: Terrain3D
var rts_camera: RtsCamera
var battle_manager: BattleManager
var sun: DirectionalLight3D

var px_font: FontFile
var ui_theme: Theme
var hud_root: Control
var menu_overlay: ColorRect
var sidebar: Control
var minimap: MinimapWidget
var radar_offline_lbl: Label
var base_hp_label: Label
var wave_label: Label
var status_label: Label
var power_label: Label
var victory_label: Label
var hint_label: Label
var deploy_btn: Button

var sb_tex: ImageTexture
var dlg_tex: ImageTexture
var logo_tex: ImageTexture
var radar_crest_rect: TextureRect
var sidebar_rows_root: Control
var tab_bar: HBoxContainer
var rts_tab: String = "build" # "build" or "units"
var slot_buttons: Dictionary = {} # key -> { "btn": Button, "icon": TextureRect, "lbl": Label }

# RTS Input & Placement Preview
var dragging_box: bool = false
var drag_start: Vector2 = Vector2.ZERO
var rmb_down_pos: Vector2 = Vector2.ZERO
var sel_box: Panel
var place_preview: MeshInstance3D
var place_mat: StandardMaterial3D

# Fog of War (64x64 overlay)
var fog_mesh: MeshInstance3D
var fog_img: Image
var fog_tex: ImageTexture
var fog_timer: float = 0.0
var fog_explored: PackedByteArray = PackedByteArray()

# Main Menu Selections
var menu_faction: String = "allies"
var menu_cash: int = 3000
var menu_start_mcv: bool = false
var menu_fog: bool = false
var menu_map_id: String = "crossfire"

# Red Alert Power Bar & Cursors
var power_bar_bg: ColorRect
var power_bar_fill: ColorRect
var power_demand_tick: ColorRect
var ra_cursors: Dictionary = {}
var last_cursor_kind: String = ""
var sw_buttons: Dictionary = {}

func _ready() -> void:
	_setup_lighting_and_env()
	_setup_world()
	_setup_openra_hud()
	_setup_rts_helpers()
	_setup_main_menu()
	_rebuild_sidebar_slots()

func _setup_lighting_and_env() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.light_energy = 1.45
	sun.shadow_enabled = false
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _setup_world() -> void:
	terrain = Terrain3D.new()
	add_child(terrain)

	rts_camera = RtsCamera.new()
	rts_camera.bound_half_w = terrain.playable_half_w
	rts_camera.bound_half_d = terrain.playable_half_d
	add_child(rts_camera)

	battle_manager = BattleManager.new()
	add_child(battle_manager)
	battle_manager.setup(terrain, rts_camera)

func _atlas(tex: Texture2D, region: Rect2) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = region
	return at

func _make_ra_stylebox(tex: Texture2D, region: Rect2, margin: int = 8) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _atlas(tex, region)
	sb.texture_margin_left = margin
	sb.texture_margin_top = margin
	sb.texture_margin_right = margin
	sb.texture_margin_bottom = margin
	return sb

func _setup_openra_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var sb_img := Image.new()
	sb_img.load(ProjectSettings.globalize_path("res://assets/ra_ui/sidebar.png"))
	sb_tex = ImageTexture.create_from_image(sb_img)

	var dlg_img := Image.new()
	dlg_img.load(ProjectSettings.globalize_path("res://assets/ra_ui/dialog.png"))
	dlg_tex = ImageTexture.create_from_image(dlg_img)

	var logo_img := Image.new()
	logo_img.load(ProjectSettings.globalize_path("res://assets/ra_ui/loadscreen-2x.png"))
	logo_tex = ImageTexture.create_from_image(logo_img)

	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_theme = Theme.new()
	px_font = FontFile.new()
	if px_font.load_dynamic_font(ProjectSettings.globalize_path("res://assets/fonts/Tiny5-Regular.ttf")) == OK:
		px_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		px_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		ui_theme.default_font = px_font

	# Apply authentic OpenRA crimson/steel button & panel styling globally
	var btn_norm := _make_ra_stylebox(dlg_tex, Rect2(768, 128, 124, 124), 6)
	var btn_hov := _make_ra_stylebox(dlg_tex, Rect2(768, 0, 124, 124), 6)
	var btn_prs := _make_ra_stylebox(dlg_tex, Rect2(768, 256, 124, 124), 6)
	ui_theme.set_stylebox("normal", "Button", btn_norm)
	ui_theme.set_stylebox("hover", "Button", btn_hov)
	ui_theme.set_stylebox("pressed", "Button", btn_prs)
	ui_theme.set_stylebox("focus", "Button", btn_hov)
	ui_theme.set_color("font_color", "Button", Color(1.0, 0.92, 0.72))
	ui_theme.set_color("font_hover_color", "Button", Color(1.0, 1.0, 1.0))
	ui_theme.set_stylebox("panel", "PanelContainer", _make_ra_stylebox(dlg_tex, Rect2(512, 256, 124, 124), 8))
	hud_root.theme = ui_theme
	canvas.add_child(hud_root)

	# Top-Left OpenRA Brushed-Steel Status Bar (from sidebar.png)
	var top_steel := TextureRect.new()
	top_steel.texture = _atlas(sb_tex, Rect2(0, 0, 434, 42))
	top_steel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top_steel.position = Vector2(10, 8)
	top_steel.size = Vector2(460, 40)
	hud_root.add_child(top_steel)

	var top_bar := HBoxContainer.new()
	top_bar.position = Vector2(10, 5)
	top_bar.size = Vector2(440, 30)
	top_bar.add_theme_constant_override("separation", 8)
	top_steel.add_child(top_bar)

	var menu_btn := Button.new()
	menu_btn.text = " OPTIONS "
	menu_btn.add_theme_font_size_override("font_size", 11)
	menu_btn.pressed.connect(func(): _toggle_menu())
	top_bar.add_child(menu_btn)

	base_hp_label = Label.new()
	base_hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	base_hp_label.add_theme_font_size_override("font_size", 12)
	base_hp_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.65))
	top_bar.add_child(base_hp_label)

	deploy_btn = Button.new()
	deploy_btn.text = " DEPLOY (D) "
	deploy_btn.add_theme_font_size_override("font_size", 11)
	deploy_btn.visible = false
	deploy_btn.pressed.connect(func(): battle_manager.deploy_selected_mcv())
	top_bar.add_child(deploy_btn)

	# Superweapons Bar (Top-Left below status bar)
	var sw_bar := VBoxContainer.new()
	sw_bar.position = Vector2(12, 54)
	sw_bar.add_theme_constant_override("separation", 4)
	hud_root.add_child(sw_bar)
	for swk in ["pdox", "iron", "mslo"]:
		var swb := Button.new()
		swb.text = swk.to_upper()
		swb.add_theme_font_size_override("font_size", 11)
		swb.visible = false
		swb.pressed.connect(func():
			if bool(battle_manager.sw_ready.get(swk, false)):
				battle_manager.sw_targeting = swk
		)
		sw_bar.add_child(swb)
		sw_buttons[swk] = swb

	# Center Victory / Defeat Banner
	victory_label = Label.new()
	victory_label.set_anchors_preset(Control.PRESET_CENTER)
	victory_label.offset_left = -280
	victory_label.offset_right = 280
	victory_label.offset_top = -50
	victory_label.offset_bottom = 50
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.add_theme_font_size_override("font_size", 32)
	victory_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.35))
	victory_label.add_theme_color_override("font_outline_color", Color.BLACK)
	victory_label.add_theme_constant_override("outline_size", 6)
	victory_label.visible = false
	hud_root.add_child(victory_label)

	# Right Sidebar Container
	sidebar = Control.new()
	sidebar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sidebar.offset_left = -250
	sidebar.offset_right = -12
	sidebar.offset_top = 10
	sidebar.offset_bottom = 560
	sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(sidebar)

	var bg_top := TextureRect.new()
	bg_top.texture = _atlas(sb_tex, Rect2(0, 185, 238, 262))
	bg_top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg_top.position = Vector2(0, 0)
	bg_top.size = Vector2(238, 262)
	sidebar.add_child(bg_top)

	wave_label = Label.new()
	wave_label.position = Vector2(10, 8)
	wave_label.size = Vector2(218, 24)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.add_theme_font_size_override("font_size", 12)
	wave_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.62))
	bg_top.add_child(wave_label)

	radar_crest_rect = TextureRect.new()
	radar_crest_rect.texture = _atlas(sb_tex, Rect2(290, 67, 222, 222))
	radar_crest_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	radar_crest_rect.position = Vector2(8, 36)
	radar_crest_rect.size = Vector2(222, 222)
	bg_top.add_child(radar_crest_rect)

	radar_offline_lbl = Label.new()
	radar_offline_lbl.text = "NO RADAR"
	radar_offline_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radar_offline_lbl.position = Vector2(9, 232)
	radar_offline_lbl.size = Vector2(220, 22)
	radar_offline_lbl.add_theme_font_size_override("font_size", 10)
	radar_offline_lbl.add_theme_color_override("font_color", Color(0.95, 0.35, 0.30))
	radar_offline_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	radar_offline_lbl.add_theme_constant_override("outline_size", 3)
	sidebar.add_child(radar_offline_lbl)

	minimap = MinimapWidget.new()
	minimap.battle_manager = battle_manager
	minimap.rts_camera = rts_camera
	minimap.world_width = terrain.world_width
	minimap.world_depth = terrain.world_depth
	minimap.position = Vector2(9, 37)
	minimap.size = Vector2(220, 220)
	minimap.z_index = 10
	sidebar.add_child(minimap)

	var bg_money := TextureRect.new()
	bg_money.texture = _atlas(sb_tex, Rect2(0, 85, 238, 28))
	bg_money.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg_money.position = Vector2(0, 262)
	bg_money.size = Vector2(238, 28)
	sidebar.add_child(bg_money)

	status_label = Label.new()
	status_label.position = Vector2(10, 3)
	status_label.size = Vector2(218, 22)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.35))
	bg_money.add_child(status_label)

	# Vertical Red Alert Power Bar (along left edge of Sidebar)
	power_bar_bg = ColorRect.new()
	power_bar_bg.position = Vector2(10, 294)
	power_bar_bg.size = Vector2(14, 210)
	power_bar_bg.color = Color(0.08, 0.08, 0.10, 0.95)
	sidebar.add_child(power_bar_bg)

	power_bar_fill = ColorRect.new()
	power_bar_fill.position = Vector2(2, 208)
	power_bar_fill.size = Vector2(10, 0)
	power_bar_fill.color = Color(0.2, 0.95, 0.3)
	power_bar_bg.add_child(power_bar_fill)

	power_demand_tick = ColorRect.new()
	power_demand_tick.position = Vector2(0, 206)
	power_demand_tick.size = Vector2(14, 3)
	power_demand_tick.color = Color(1.0, 1.0, 1.0, 0.95)
	power_bar_bg.add_child(power_demand_tick)

	# RTS Tabs (BUILD / UNITS / REPAIR / SELL)
	tab_bar = HBoxContainer.new()
	tab_bar.position = Vector2(36, 291)
	tab_bar.size = Vector2(196, 24)
	tab_bar.add_theme_constant_override("separation", 3)
	sidebar.add_child(tab_bar)

	var b_tab := Button.new()
	b_tab.text = "BLD"
	b_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_tab.add_theme_font_size_override("font_size", 10)
	b_tab.pressed.connect(func(): rts_tab = "build"; _rebuild_sidebar_slots())
	tab_bar.add_child(b_tab)

	var u_tab := Button.new()
	u_tab.text = "UNT"
	u_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	u_tab.add_theme_font_size_override("font_size", 10)
	u_tab.pressed.connect(func(): rts_tab = "units"; _rebuild_sidebar_slots())
	tab_bar.add_child(u_tab)

	var rep_btn := Button.new()
	rep_btn.text = "REP"
	rep_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rep_btn.add_theme_font_size_override("font_size", 10)
	rep_btn.pressed.connect(func():
		battle_manager.repair_mode = not battle_manager.repair_mode
		battle_manager.sell_mode = false
	)
	tab_bar.add_child(rep_btn)

	var sell_btn := Button.new()
	sell_btn.text = "SELL"
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_btn.add_theme_font_size_override("font_size", 10)
	sell_btn.pressed.connect(func():
		battle_manager.sell_mode = not battle_manager.sell_mode
		battle_manager.repair_mode = false
	)
	tab_bar.add_child(sell_btn)

	sidebar_rows_root = Control.new()
	sidebar_rows_root.position = Vector2(0, 290)
	sidebar_rows_root.size = Vector2(238, 250)
	sidebar_rows_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sidebar.add_child(sidebar_rows_root)

	# Selection Box Overlay
	sel_box = Panel.new()
	sel_box.visible = false
	sel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = Color(0.2, 1.0, 0.35, 0.15)
	sb_style.border_color = Color(0.25, 1.0, 0.4, 0.95)
	sb_style.set_border_width_all(2)
	sel_box.add_theme_stylebox_override("panel", sb_style)
	hud_root.add_child(sel_box)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_label.offset_left = 16
	hint_label.offset_top = -34
	hint_label.offset_right = 880
	hint_label.offset_bottom = -10
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hint_label.add_theme_constant_override("outline_size", 3)
	hud_root.add_child(hint_label)

func _rebuild_sidebar_slots() -> void:
	for c in sidebar_rows_root.get_children():
		c.queue_free()
	slot_buttons.clear()

	var is_rts := (battle_manager.game_mode != BattleManager.GameMode.AUTOBATTLE)
	tab_bar.visible = is_rts
	sidebar_rows_root.position.y = 316 if is_rts else 290

	var slots: Array[Dictionary] = []
	if not is_rts:
		slots = [
			{ "key": "infantry", "tex": "0_infantry", "is_cameo": false },
			{ "key": "rocket", "tex": "0_rocket", "is_cameo": false },
			{ "key": "tank", "tex": "0_tank", "is_cameo": false },
			{ "key": "heavy", "tex": "0_heavy", "is_cameo": false },
			{ "key": "artillery", "tex": "0_artillery", "is_cameo": false },
			{ "key": "heli", "tex": "0_heli", "is_cameo": false },
			{ "key": "plane", "tex": "0_plane", "is_cameo": false },
			{ "key": "income", "tex": "0_base", "is_cameo": false },
		]
	elif rts_tab == "build":
		for bkey in RtsData.get_structure_order(battle_manager.player_faction):
			slots.append({ "key": bkey, "tex": bkey, "is_cameo": true })
	else:
		for ukey in RtsData.get_unit_order():
			var ckey := RtsData.get_unit_cameo(ukey, battle_manager.player_faction)
			slots.append({ "key": ukey, "tex": ckey, "is_cameo": true })

	var num_rows := int(ceil(float(slots.size()) / 3.0))
	for row in range(num_rows):
		var bg_row := TextureRect.new()
		bg_row.texture = _atlas(sb_tex, Rect2(0, 116, 238, 47))
		bg_row.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg_row.position = Vector2(0, row * 47)
		bg_row.size = Vector2(238, 47)
		sidebar_rows_root.add_child(bg_row)

		for col in range(3):
			var idx := row * 3 + col
			if idx >= slots.size():
				continue
			var slot: Dictionary = slots[idx]
			var key: String = slot["key"]
			var btn := Button.new()
			btn.position = Vector2(41 + col * 63, 2)
			btn.size = Vector2(61, 43)
			btn.flat = true
			btn.clip_contents = true
			btn.pressed.connect(func(): _on_sidebar_slot_pressed(key))
			bg_row.add_child(btn)

			var icon := TextureRect.new()
			var tkey: String = slot["tex"]
			if slot["is_cameo"] and battle_manager.cameos.has(tkey):
				icon.texture = battle_manager.cameos[tkey]
			elif battle_manager.textures.has(tkey):
				icon.texture = battle_manager.textures[tkey]
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.position = Vector2(4, 2)
			icon.size = Vector2(53, 25)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(icon)

			var prog := ColorRect.new()
			prog.position = Vector2(0, 0)
			prog.size = Vector2(61, 0)
			prog.color = Color(0.0, 0.0, 0.0, 0.55)
			prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
			prog.visible = false
			btn.add_child(prog)

			var lbl := Label.new()
			lbl.position = Vector2(1, 26)
			lbl.size = Vector2(59, 16)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.70))
			lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			lbl.add_theme_constant_override("outline_size", 3)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(lbl)
			slot_buttons[key] = { "btn": btn, "icon": icon, "lbl": lbl, "prog": prog }

	var bg_bottom := TextureRect.new()
	bg_bottom.texture = _atlas(sb_tex, Rect2(0, 166, 238, 8))
	bg_bottom.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg_bottom.position = Vector2(0, num_rows * 47)
	bg_bottom.size = Vector2(238, 8)
	sidebar_rows_root.add_child(bg_bottom)

func _on_sidebar_slot_pressed(key: String) -> void:
	if battle_manager.game_mode == BattleManager.GameMode.AUTOBATTLE:
		if key == "income":
			battle_manager.buy_income_upgrade()
		else:
			battle_manager.buy_unit_upgrade(key)
	elif rts_tab == "build":
		battle_manager.start_rts_structure(key)
	else:
		battle_manager.start_rts_unit(key)

func _setup_rts_helpers() -> void:
	place_preview = MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(2.0, 0.15, 2.0)
	place_mat = StandardMaterial3D.new()
	place_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	place_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	place_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.45)
	pm.material = place_mat
	place_preview.mesh = pm
	place_preview.visible = false
	add_child(place_preview)

	# 64x64 Fog of War overlay
	fog_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	fog_img.fill(Color(0, 0, 0, 0))
	fog_tex = ImageTexture.create_from_image(fog_img)
	fog_explored.resize(64 * 64)
	fog_explored.fill(0)

	var fplane := PlaneMesh.new()
	fplane.size = Vector2(terrain.world_width, terrain.world_depth)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_texture = fog_tex
	fmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	fplane.material = fmat

	fog_mesh = MeshInstance3D.new()
	fog_mesh.mesh = fplane
	fog_mesh.position = Vector3(0.0, 1.65, 0.0)
	fog_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog_mesh.visible = false
	add_child(fog_mesh)

	# Load original RA cursors (mouse.shp)
	var cdir := ProjectSettings.globalize_path("res://assets/ra_sprites")
	for ckey in ["default", "move", "attack", "deploy", "sell", "repair"]:
		var cp := cdir.path_join("cursor_%s.png" % ckey)
		if FileAccess.file_exists(cp):
			var img := Image.new()
			img.load(cp)
			ra_cursors[ckey] = ImageTexture.create_from_image(img)

func _setup_main_menu() -> void:
	menu_overlay = ColorRect.new()
	menu_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_overlay.color = Color(0.03, 0.02, 0.02, 0.90)
	menu_overlay.visible = true
	hud_root.add_child(menu_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_overlay.add_child(center)

	var panel := PanelContainer.new()
	var pstyle := _make_ra_stylebox(dlg_tex, Rect2(0, 0, 470, 470), 12)
	pstyle.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(490, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var crest := TextureRect.new()
	crest.texture = _atlas(logo_tex, Rect2(0, 0, 512, 512))
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.custom_minimum_size = Vector2(110, 110)
	vbox.add_child(crest)

	var title := Label.new()
	title.text = "RED ALERT REDUX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.30))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	vbox.add_child(title)

	# Faction Toggle
	var fac_row := HBoxContainer.new()
	fac_row.add_theme_constant_override("separation", 8)
	vbox.add_child(fac_row)
	var fac_lbl := Label.new(); fac_lbl.text = "Faction:"; fac_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fac_row.add_child(fac_lbl)
	var fac_btn := Button.new()
	fac_btn.text = "ALLIES (2TNK / ARTY / HELI)"
	fac_btn.pressed.connect(func():
		menu_faction = "soviet" if menu_faction == "allies" else "allies"
		fac_btn.text = "ALLIES (2TNK / ARTY / HELI)" if menu_faction == "allies" else "SOVIET (3TNK / V2RL / TESLA)"
	)
	fac_row.add_child(fac_btn)

	# Map Selector
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 8)
	vbox.add_child(map_row)
	var map_lbl := Label.new(); map_lbl.text = "Map:"; map_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_row.add_child(map_lbl)
	var map_btn := Button.new()
	map_btn.text = "Crossfire (128x128)"
	map_btn.pressed.connect(func():
		if menu_map_id == "crossfire":
			menu_map_id = "a-nuclear-winter"
			map_btn.text = "A Nuclear Winter (100x70)"
		elif menu_map_id == "a-nuclear-winter":
			menu_map_id = "fort-lonestar"
			map_btn.text = "Fort Lonestar (48x48)"
		else:
			menu_map_id = "crossfire"
			map_btn.text = "Crossfire (128x128)"
	)
	map_row.add_child(map_btn)

	# Cash & Start Mode & Fog
	var opt_row := HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 8)
	vbox.add_child(opt_row)
	var cash_btn := Button.new()
	cash_btn.text = "Cash: $3000"
	cash_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash_btn.pressed.connect(func():
		menu_cash = 5000 if menu_cash == 3000 else (1500 if menu_cash == 5000 else 3000)
		cash_btn.text = "Cash: $%d" % menu_cash
	)
	opt_row.add_child(cash_btn)

	var mcv_btn := Button.new()
	mcv_btn.text = "Start: Base"
	mcv_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mcv_btn.pressed.connect(func():
		menu_start_mcv = not menu_start_mcv
		mcv_btn.text = "Start: MCV" if menu_start_mcv else "Start: Base"
	)
	opt_row.add_child(mcv_btn)

	var fog_btn := Button.new()
	fog_btn.text = "Fog: OFF"
	fog_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fog_btn.pressed.connect(func():
		menu_fog = not menu_fog
		fog_btn.text = "Fog: ON" if menu_fog else "Fog: OFF"
	)
	opt_row.add_child(fog_btn)

	# Mode Buttons
	var sk_btn := Button.new()
	sk_btn.text = "PLAY SKIRMISH (100% RED ALERT RTS)"
	sk_btn.add_theme_font_size_override("font_size", 15)
	sk_btn.pressed.connect(func(): _launch_mode(BattleManager.GameMode.SKIRMISH, 1))
	vbox.add_child(sk_btn)

	var camp_lbl := Label.new()
	camp_lbl.text = "--- CAMPAIGN MISSIONS ---"
	camp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(camp_lbl)

	var camp_row := HBoxContainer.new()
	camp_row.add_theme_constant_override("separation", 6)
	vbox.add_child(camp_row)
	var m_names := ["M1: Outpost", "M2: Harvester", "M3: Overlord"]
	for i in range(3):
		var m_id := i + 1
		var mb := Button.new()
		mb.text = m_names[i]
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.pressed.connect(func(): _launch_mode(BattleManager.GameMode.CAMPAIGN, m_id))
		camp_row.add_child(mb)

	var ab_btn := Button.new()
	ab_btn.text = "PLAY AUTOBATTLE MODE"
	ab_btn.pressed.connect(func(): _launch_mode(BattleManager.GameMode.AUTOBATTLE, 1))
	vbox.add_child(ab_btn)

	var close_btn := Button.new()
	close_btn.text = "RESUME CURRENT MATCH"
	close_btn.pressed.connect(func(): menu_overlay.visible = false)
	vbox.add_child(close_btn)

func _launch_mode(mode: int, mission_id: int) -> void:
	menu_overlay.visible = false
	terrain.reload_map(menu_map_id)
	rts_camera.bound_half_w = terrain.playable_half_w
	rts_camera.bound_half_d = terrain.playable_half_d
	minimap.world_width = terrain.world_width
	minimap.world_depth = terrain.world_depth
	(fog_mesh.mesh as PlaneMesh).size = Vector2(terrain.world_width, terrain.world_depth)
	fog_explored.fill(0)
	battle_manager.start_match(mode, menu_faction, menu_cash, mission_id, menu_start_mcv, menu_fog)
	_rebuild_sidebar_slots()

func _toggle_menu() -> void:
	menu_overlay.visible = not menu_overlay.visible

func _screen_to_ground(screen_pos: Vector2) -> Dictionary:
	var cam := rts_camera.camera
	var ro := cam.project_ray_origin(screen_pos)
	var rd := cam.project_ray_normal(screen_pos)
	if absf(rd.y) < 0.001:
		return { "hit": false }
	var t := -ro.y / rd.y
	if t < 0.0:
		return { "hit": false }
	var pt := ro + rd * t
	return { "hit": true, "pos": Vector3(pt.x, terrain.get_height(pt.x, pt.z), pt.z) }

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if bool(battle_manager.player_struct_q.get("ready", false)):
				battle_manager.player_struct_q["ready"] = false
			else:
				_toggle_menu()
			return
		if event.keycode == KEY_D:
			battle_manager.deploy_selected_mcv()
		elif event.keycode == KEY_S:
			battle_manager.stop_selected_units()
		elif event.keycode == KEY_A:
			battle_manager.attack_move_mode = not battle_manager.attack_move_mode
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			var gidx: int = int(event.keycode) - int(KEY_1)
			if Input.is_key_pressed(KEY_CTRL):
				battle_manager.assign_control_group(gidx)
			else:
				battle_manager.select_control_group(gidx)

	if menu_overlay.visible or battle_manager.game_mode == BattleManager.GameMode.AUTOBATTLE:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if battle_manager.sw_targeting != "":
					var hit := _screen_to_ground(event.position)
					if hit["hit"]:
						battle_manager.trigger_superweapon(battle_manager.sw_targeting, hit["pos"])
					return
				if battle_manager.sell_mode:
					var hit := _screen_to_ground(event.position)
					if hit["hit"]:
						battle_manager.sell_building_at(hit["pos"])
					return
				if battle_manager.repair_mode:
					var hit := _screen_to_ground(event.position)
					if hit["hit"]:
						battle_manager.toggle_repair_at(hit["pos"])
					return
				if bool(battle_manager.player_struct_q.get("ready", false)):
					var hit := _screen_to_ground(event.position)
					if hit["hit"]:
						battle_manager.place_ready_structure(hit["pos"])
					return
				dragging_box = true
				drag_start = event.position
			else:
				if dragging_box:
					dragging_box = false
					sel_box.visible = false
					var d := drag_start.distance_to(event.position)
					var additive := Input.is_key_pressed(KEY_SHIFT)
					if d < 8.0:
						var hit := _screen_to_ground(event.position)
						if hit["hit"]:
							battle_manager.select_unit_at_world(hit["pos"], additive)
					else:
						var r := Rect2(drag_start, event.position - drag_start).abs()
						battle_manager.select_units_in_screen_rect(r, rts_camera.camera, additive)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if battle_manager.sw_targeting != "":
					battle_manager.sw_targeting = ""
					return
				if battle_manager.sell_mode or battle_manager.repair_mode:
					battle_manager.sell_mode = false
					battle_manager.repair_mode = false
					return
				if bool(battle_manager.player_struct_q.get("ready", false)):
					battle_manager.player_struct_q["ready"] = false
					return
				rmb_down_pos = event.position
			else:
				if rmb_down_pos.distance_to(event.position) < 8.0:
					var hit := _screen_to_ground(event.position)
					if hit["hit"]:
						battle_manager.issue_right_click_order(hit["pos"])

	elif event is InputEventMouseMotion and dragging_box:
		var r := Rect2(drag_start, event.position - drag_start).abs()
		sel_box.position = r.position
		sel_box.size = r.size
		sel_box.visible = (r.size.x > 6.0 or r.size.y > 6.0)

func _update_fog_of_war(dt: float) -> void:
	var active_fog := battle_manager.fog_enabled and battle_manager.game_mode != BattleManager.GameMode.AUTOBATTLE
	fog_mesh.visible = active_fog
	if not active_fog:
		for u in battle_manager.units:
			u.sprite.visible = true
		return

	fog_timer -= dt
	if fog_timer > 0.0:
		return
	fog_timer = 0.25

	var visible_now := PackedByteArray()
	visible_now.resize(64 * 64)
	visible_now.fill(0)

	var sx := 64.0 / terrain.world_width
	var sz := 64.0 / terrain.world_depth
	for u in battle_manager.units:
		if u.team != 0 or u.hp <= 0.0:
			continue
		var cx := int((u.pos.x + terrain.world_width * 0.5) * sx)
		var cz := int((u.pos.z + terrain.world_depth * 0.5) * sz)
		var rad := 6 if u.is_building else 5
		var r2 := rad * rad
		for dz in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if dx * dx + dz * dz > r2:
					continue
				var fx := cx + dx
				var fz := cz + dz
				if fx >= 0 and fz >= 0 and fx < 64 and fz < 64:
					var idx := fz * 64 + fx
					visible_now[idx] = 1
					fog_explored[idx] = 1

	for y in range(64):
		for x in range(64):
			var idx := y * 64 + x
			if visible_now[idx] == 1:
				fog_img.set_pixel(x, y, Color(0, 0, 0, 0.0))
			elif fog_explored[idx] == 1:
				fog_img.set_pixel(x, y, Color(0, 0, 0, 0.45))
			else:
				fog_img.set_pixel(x, y, Color(0, 0, 0, 0.92))
	fog_tex.update(fog_img)

	for u in battle_manager.units:
		if u.team == 0:
			u.sprite.visible = true
			continue
		var fx := clampi(int((u.pos.x + terrain.world_width * 0.5) * sx), 0, 63)
		var fz := clampi(int((u.pos.z + terrain.world_depth * 0.5) * sz), 0, 63)
		u.sprite.visible = (visible_now[fz * 64 + fx] == 1)

func _process(delta: float) -> void:
	_update_fog_of_war(delta)

	var radar_on := battle_manager.has_radar_online(0)
	minimap.visible = radar_on
	radar_offline_lbl.visible = not radar_on
	if radar_crest_rect != null:
		var r_rect := Rect2(290, 67, 222, 222) if battle_manager.player_faction == "allies" else Rect2(290, 290, 222, 222)
		(radar_crest_rect.texture as AtlasTexture).region = r_rect

	var is_rts := (battle_manager.game_mode != BattleManager.GameMode.AUTOBATTLE)
	power_bar_bg.visible = is_rts
	if is_rts:
		var mode_txt := "SKIRMISH" if battle_manager.game_mode == BattleManager.GameMode.SKIRMISH else ("MISSION %d" % battle_manager.campaign_mission)
		wave_label.text = "%s (%s)" % [mode_txt, battle_manager.player_faction.to_upper()]
		var p_prod: int = battle_manager.power_produced[0]
		var p_cons: int = battle_manager.power_consumed[0]
		status_label.text = "$%d  |  PWR %d/%d  |  %d FPS" % [battle_manager.blue_cash, p_prod, p_cons, Engine.get_frames_per_second()]
		hint_label.text = "Left-Drag: Select  |  Right-Click: Move/Attack  |  D: Deploy MCV  |  A: Attack-Move  |  S: Stop  |  ESC: Menu"

		var max_pwr := maxf(200.0, float(maxi(p_prod, p_cons)) * 1.2)
		var fill_h := clampf((float(p_prod) / max_pwr) * 206.0, 0.0, 206.0)
		power_bar_fill.position.y = 208.0 - fill_h
		power_bar_fill.size.y = fill_h
		power_bar_fill.color = Color(0.2, 0.95, 0.3) if p_prod >= p_cons else (Color(1.0, 0.85, 0.15) if p_prod >= p_cons * 0.6 else Color(1.0, 0.25, 0.2))
		var dem_h := clampf((float(p_cons) / max_pwr) * 206.0, 0.0, 206.0)
		power_demand_tick.position.y = 208.0 - dem_h

		# Dynamic Red Alert Mouse Cursor
		var ckind := "default"
		if not menu_overlay.visible:
			var mpos := get_viewport().get_mouse_position()
			if mpos.x < get_viewport().get_visible_rect().size.x - 255.0:
				var hit_c := _screen_to_ground(mpos)
				if hit_c["hit"]:
					ckind = battle_manager.get_hover_context(hit_c["pos"])
		if ckind != last_cursor_kind and ra_cursors.has(ckind):
			last_cursor_kind = ckind
			var tex: Texture2D = ra_cursors[ckind]
			var hs := Vector2.ZERO if ckind == "default" else tex.get_size() * 0.5
			Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, hs)
	else:
		if last_cursor_kind != "default" and ra_cursors.has("default"):
			last_cursor_kind = "default"
			Input.set_custom_mouse_cursor(ra_cursors["default"], Input.CURSOR_ARROW, Vector2.ZERO)
		wave_label.text = "WAVE %d (%.0fs)" % [battle_manager.wave_number, maxf(0.0, battle_manager.wave_timer)]
		status_label.text = "$%d   |   B:%d  R:%d   |   %d FPS" % [
			battle_manager.blue_cash,
			battle_manager.blue_count,
			battle_manager.red_count,
			Engine.get_frames_per_second()
		]
		hint_label.text = "Sidebar: Upgrade Waves  |  ESC: Switch to Skirmish / Campaign  |  WASD / Right-Drag: Pan"

	var bhp := int(maxf(0.0, battle_manager.blue_base.hp)) if battle_manager.blue_base != null and battle_manager.blue_base.hp > 0.0 else 0
	var rhp := int(maxf(0.0, battle_manager.red_base.hp)) if battle_manager.red_base != null and battle_manager.red_base.hp > 0.0 else 0
	base_hp_label.text = " PLAYER BASE: %d HP   |   ENEMY BASE: %d HP " % [bhp, rhp]

	# Show Deploy MCV button if MCV selected
	var has_mcv_sel := false
	for u in battle_manager.get_selected_units():
		if u.kind == "mcv":
			has_mcv_sel = true
			break
	deploy_btn.visible = has_mcv_sel

	for swk: String in sw_buttons.keys():
		var swb: Button = sw_buttons[swk]
		var has_sw := is_rts and battle_manager.has_building(0, swk)
		swb.visible = has_sw
		if has_sw:
			var nm := "CHRONO" if swk == "pdox" else ("IRON" if swk == "iron" else "NUKE")
			if battle_manager.sw_targeting == swk:
				swb.text = " %s: CLICK TARGET " % nm
			elif bool(battle_manager.sw_ready.get(swk, false)):
				swb.text = " %s: READY! " % nm
			else:
				var rem := int(maxf(0.0, float(battle_manager.sw_totals[swk]) - float(battle_manager.sw_timers[swk])))
				swb.text = " %s (%ds) " % [nm, rem]

	# Placement preview
	if is_rts and bool(battle_manager.player_struct_q.get("ready", false)):
		var bkey := String(battle_manager.player_struct_q["key"])
		var binfo: Dictionary = RtsData.STRUCTURES.get(bkey, {})
		var hit := _screen_to_ground(get_viewport().get_mouse_position())
		if hit["hit"]:
			var w_t := float(binfo.get("w", 2))
			var h_t := float(binfo.get("h", 2))
			place_preview.scale = Vector3(w_t * 0.5, 1.0, h_t * 0.5)
			var cell := terrain.world_to_grid(hit["pos"].x, hit["pos"].z)
			var wp := terrain.grid_to_world(cell)
			var py := terrain.get_height(wp.x, wp.y)
			place_preview.position = Vector3(wp.x, py + 0.15, wp.y)
			var ok := battle_manager.can_place_structure_at(bkey, place_preview.position)
			place_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.5) if ok else Color(1.0, 0.2, 0.2, 0.5)
			place_preview.visible = true
		else:
			place_preview.visible = false
	else:
		place_preview.visible = false

	# Update Sidebar slot labels & cameo clock progress overlay
	for key: String in slot_buttons.keys():
		var slot: Dictionary = slot_buttons[key]
		var lbl: Label = slot["lbl"]
		var icon: TextureRect = slot["icon"]
		var prog: ColorRect = slot["prog"]
		prog.visible = false
		if not is_rts:
			if key == "income":
				lbl.text = "+$ Lv%d $%d" % [battle_manager.blue_income_level, battle_manager.get_income_upgrade_cost()]
			else:
				var cnt: int = int(battle_manager.blue_roster.get(key, 0))
				var cost: int = int(BattleManager.UNIT_COSTS[key])
				lbl.text = "x%d $%d" % [cnt, cost]
		elif rts_tab == "build":
			var info: Dictionary = RtsData.STRUCTURES[key]
			var unlocked := battle_manager.has_prereq(0, info["prereq"])
			icon.modulate = Color.WHITE if unlocked else Color(0.35, 0.35, 0.35, 0.7)
			if battle_manager.player_struct_q["key"] == key:
				if bool(battle_manager.player_struct_q["ready"]):
					lbl.text = "READY!"
				else:
					var ratio := clampf(float(battle_manager.player_struct_q["progress"]) / float(battle_manager.player_struct_q["total"]), 0.0, 1.0)
					prog.visible = true
					prog.size.y = 43.0 * (1.0 - ratio)
					lbl.text = "%d%%" % int(100.0 * ratio)
			else:
				lbl.text = "$%d" % int(info["cost"])
		else:
			var info: Dictionary = RtsData.RTS_UNITS[key]
			var unlocked := battle_manager.has_prereq(0, info["prereq"])
			icon.modulate = Color.WHITE if unlocked else Color(0.35, 0.35, 0.35, 0.7)
			if battle_manager.player_unit_q["key"] == key:
				var ratio := clampf(float(battle_manager.player_unit_q["progress"]) / float(battle_manager.player_unit_q["total"]), 0.0, 1.0)
				prog.visible = true
				prog.size.y = 43.0 * (1.0 - ratio)
				lbl.text = "%d%%" % int(100.0 * ratio)
			else:
				lbl.text = "$%d" % int(info["cost"])

	if battle_manager.winner_team != -1:
		victory_label.visible = true
		var side := "VICTORY!" if battle_manager.winner_team == 0 else "DEFEAT!"
		if not is_rts:
			victory_label.text = "%s\nNext match in %.0fs..." % [side, maxf(0.0, battle_manager.restart_timer)]
		else:
			victory_label.text = "%s\nPress ESC for Menu" % side
	else:
		victory_label.visible = false
