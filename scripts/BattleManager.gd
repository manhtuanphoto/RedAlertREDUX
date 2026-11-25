class_name BattleManager
extends Node3D

const RtsData = preload("res://scripts/RtsData.gd")

enum GameMode { SKIRMISH, CAMPAIGN, AUTOBATTLE }
enum SquadState { GATHER, ATTACK, PROTECT }

const MAX_UNITS_PER_SIDE := 250
const WAVE_INTERVAL := 7.0
const SPAWN_STEP_INTERVAL := 0.45
const MAX_SPAWN_QUEUE := 30
const MAX_PROJ := 350
const MAX_EXPLOSIONS := 96
const MAX_DECALS := 180
const MAX_HUSKS := 36
const MAX_AUDIO_PLAYERS := 16
const RA_PIXEL_SIZE := 1.0 / 24.0
const BUCKET_SIZE := 6.0

const UNIT_COSTS := {
	"infantry": 60, "rocket": 90, "tank": 140, "heavy": 240,
	"artillery": 220, "heli": 260, "plane": 320,
}

const ARMOR_TYPES := {
	"infantry": "None", "rocket": "None", "engineer": "None", "tank": "Heavy", "heavy": "Heavy",
	"artillery": "Light", "heli": "Light", "plane": "Light",
	"mcv": "Heavy", "harv": "Heavy", "base": "Concrete",
	"powr": "Concrete", "apwr": "Concrete", "proc": "Concrete", "tent": "Concrete",
	"barr": "Concrete", "weap": "Concrete", "dome": "Concrete", "hpad": "Concrete",
	"afld": "Concrete", "pbox": "Concrete", "gun": "Concrete", "tsla": "Concrete", "sam": "Concrete",
	"pdox": "Concrete", "iron": "Concrete", "mslo": "Concrete",
}

const VERSUS_TABLE := {
	"bullet": { "None": 1.2, "Light": 0.4, "Heavy": 0.15, "Concrete": 0.25 },
	"missile": { "None": 0.35, "Light": 0.95, "Heavy": 1.15, "Concrete": 0.9 },
	"shell": { "None": 0.3, "Light": 0.85, "Heavy": 1.15, "Concrete": 0.8 },
	"artillery": { "None": 1.0, "Light": 0.75, "Heavy": 0.45, "Concrete": 1.0 },
	"tesla": { "None": 1.5, "Light": 1.2, "Heavy": 1.1, "Concrete": 0.8 },
}

const AI_WEIGHTS := {
	"infantry": 65.0, "rocket": 30.0, "tank": 50.0, "heavy": 25.0,
	"artillery": 24.0, "heli": 22.0, "plane": 16.0,
}

var terrain: Terrain3D
var cam_ref: RtsCamera = null

var game_mode: int = GameMode.AUTOBATTLE
var player_faction: String = "allies"
var ai_faction: String = "soviet"
var campaign_mission: int = 1
var match_active: bool = false
var fog_enabled: bool = false
var start_with_mcv: bool = false

var wave_number: int = 0
var wave_timer: float = 0.8
var spawn_step_timer: float = 0.0
var blue_count: int = 0
var red_count: int = 0
var blue_spawn_queue: Array[String] = []
var red_spawn_queue: Array[String] = []

var blue_cash: int = 2500
var red_cash: int = 2500
var cash_accum: float = 0.0
var blue_income_level: int = 1
var red_income_level: int = 1
var winner_team: int = -1
var restart_timer: float = 0.0

var power_produced: Array[int] = [0, 0]
var power_consumed: Array[int] = [0, 0]

# RTS Production Queues (Team 0 = Player, Team 1 = AI)
var player_struct_q: Dictionary = { "key": "", "progress": 0.0, "total": 1.0, "ready": false }
var player_unit_q: Dictionary = { "key": "", "progress": 0.0, "total": 1.0 }
var ai_struct_q: Dictionary = { "key": "", "progress": 0.0, "total": 1.0 }
var ai_unit_q: Dictionary = { "key": "", "progress": 0.0, "total": 1.0 }
var ai_think_timer: float = 0.5
var ai_wave_timer: float = 18.0
var attack_move_mode: bool = false

var blue_roster: Dictionary = {}
var red_roster: Dictionary = {}
var blue_base: UnitData = null
var red_base: UnitData = null

var textures: Dictionary = {}
var dir_textures: Dictionary = {}
var walk_textures: Dictionary = {}
var rotor_textures: Dictionary = {}
var cameos: Dictionary = {}
var exp_textures: Dictionary = {}
var exp_frames: Dictionary = { "fball": 18, "frag": 14, "vehhit": 17, "piff": 8, "smoke": 91 }
var crater_textures: Array[ImageTexture] = []
var scorch_textures: Array[ImageTexture] = []
var husk_textures: Dictionary = {}
var die_textures: Dictionary = {}
var hull_textures: Dictionary = {}
var turret_textures: Dictionary = {}
var decal_pool: Array[Sprite3D] = []
var decal_cursor: int = 0
var husk_pool: Array[Sprite3D] = []
var husk_cursor: int = 0

var sfx_streams: Dictionary = {}
var sfx_cooldowns: Dictionary = {}
var audio_players: Array[AudioStreamPlayer] = []
var audio_cursor: int = 0
var voice_player: AudioStreamPlayer = null
var base_attack_cooldown: float = 0.0
var nofunds_cooldown: float = 0.0

var sel_ring_mesh: TorusMesh
var sel_ring_mat: StandardMaterial3D
var hp_bg_mesh: BoxMesh
var hp_fill_mesh: BoxMesh
var hp_bg_mat: StandardMaterial3D
var hp_green_mat: StandardMaterial3D
var hp_yellow_mat: StandardMaterial3D
var hp_red_mat: StandardMaterial3D
var sell_mode: bool = false
var repair_mode: bool = false
var control_groups: Array = [[], [], [], [], []]
var last_group_tap: int = -1
var group_tap_timer: float = 0.0
var tesla_arcs: Array[Dictionary] = []
var tesla_mat: StandardMaterial3D
var sw_timers: Dictionary = { "pdox": 0.0, "iron": 0.0, "mslo": 0.0 }
var sw_totals: Dictionary = { "pdox": 20.0, "iron": 20.0, "mslo": 28.0 }
var sw_ready: Dictionary = { "pdox": false, "iron": false, "mslo": false }
var sw_targeting: String = ""

class ExplosionAnim:
	var sprite: Sprite3D
	var total_frames: int
	var elapsed: float
	var fps: float = 22.0
	var active: bool = false

var explosions: Array[ExplosionAnim] = []

class SquadData:
	var team: int
	var state: int = SquadState.GATHER
	var rally_pos: Vector3
	var gather_timer: float = 2.2
	var members: Array[UnitData] = []

class UnitData:
	var team: int
	var kind: String
	var armor_type: String = "None"
	var weapon_kind: String = "bullet"
	var pos: Vector3
	var hp: float
	var max_hp: float
	var speed: float
	var attack_range: float
	var aa_range: float = 0.0
	var min_range: float = 0.0
	var damage: float
	var cooldown: float
	var fire_rate: float
	var is_vehicle: bool = false
	var is_air: bool = false
	var is_base: bool = false
	var is_building: bool = false
	var aa_only: bool = false
	var w_tiles: int = 1
	var h_tiles: int = 1
	var power_delta: int = 0
	var altitude: float = 0.0
	var air_heading: Vector3 = Vector3.RIGHT
	var pass_timer: float = 0.0
	var dir_count: int = 1
	var y_offset: float = 1.0
	var sprite: Sprite3D
	var shadow_sprite: Sprite3D = null
	var rotor_sprite: Sprite3D = null
	var turret_sprite: Sprite3D = null
	var invuln_timer: float = 0.0
	var sel_ring: MeshInstance3D = null
	var hp_bar_bg: MeshInstance3D = null
	var hp_bar_fill: MeshInstance3D = null
	var selected: bool = false
	var repairing: bool = false
	var sold: bool = false
	var target: UnitData = null
	var forced_target: UnitData = null
	var has_move_order: bool = false
	var move_goal: Vector3 = Vector3.ZERO
	var rally_pos: Vector3 = Vector3.INF
	var attack_move: bool = false
	var harv_state: int = 0 # 0=seek_ore, 1=mining, 2=return_proc
	var harv_cargo: int = 0
	var harv_timer: float = 0.0
	var harv_ore_pos: Vector3 = Vector3.ZERO
	var squad: SquadData = null
	var path: PackedVector2Array = PackedVector2Array()
	var path_idx: int = 0
	var repath_timer: float = 0.0
	var smoke_timer: float = 0.0
	var anim_timer: float = 0.0
	var is_walking_anim: bool = false

class ProjectileData:
	var pos: Vector3
	var vel: Vector3
	var target_pos: Vector3
	var team: int
	var damage: float
	var splash: float
	var is_arc: bool
	var kind: String
	var weapon_kind: String = "bullet"
	var life: float
	var sprite: Sprite3D
	var active: bool = false

var units: Array[UnitData] = []
var squads: Array[SquadData] = []
var grid_buckets: Dictionary = {}
var squad_scan_timer: float = 0.0
var proj_pool: Array[ProjectileData] = []
var proj_textures: Dictionary = {}
var rng := RandomNumberGenerator.new()

func setup(p_terrain: Terrain3D, p_cam: RtsCamera = null) -> void:
	terrain = p_terrain
	cam_ref = p_cam
	rng.seed = 20261124
	sel_ring_mesh = TorusMesh.new()
	sel_ring_mesh.inner_radius = 0.42
	sel_ring_mesh.outer_radius = 0.54
	sel_ring_mat = StandardMaterial3D.new()
	sel_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sel_ring_mat.albedo_color = Color(0.25, 1.0, 0.35)
	hp_bg_mesh = BoxMesh.new()
	hp_bg_mesh.size = Vector3(1.0, 0.09, 0.04)
	hp_fill_mesh = BoxMesh.new()
	hp_fill_mesh.size = Vector3(0.96, 0.06, 0.05)
	hp_bg_mat = StandardMaterial3D.new(); hp_bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; hp_bg_mat.albedo_color = Color(0.08, 0.08, 0.08)
	hp_green_mat = StandardMaterial3D.new(); hp_green_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; hp_green_mat.albedo_color = Color(0.2, 0.95, 0.3)
	hp_yellow_mat = StandardMaterial3D.new(); hp_yellow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; hp_yellow_mat.albedo_color = Color(1.0, 0.85, 0.15)
	hp_red_mat = StandardMaterial3D.new(); hp_red_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; hp_red_mat.albedo_color = Color(1.0, 0.2, 0.2)
	_init_textures()
	_init_projectiles_mesh()
	_init_explosions_pool()
	_init_decals_and_husks_pool()
	_init_audio_pool()
	_init_tesla_arcs()
	start_match(GameMode.AUTOBATTLE, "allies", 250, 1, false, false)

func start_match(mode: int, p_faction: String = "allies", start_cash: int = 3000, mission_id: int = 1, p_start_mcv: bool = false, p_fog: bool = false) -> void:
	game_mode = mode
	player_faction = p_faction
	ai_faction = "soviet" if p_faction == "allies" else "allies"
	campaign_mission = mission_id
	start_with_mcv = p_start_mcv
	fog_enabled = p_fog
	match_active = true
	reset_match(start_cash)

func reset_match(start_cash: int = -1) -> void:
	for u in units:
		if u.is_building:
			terrain.set_footprint_solid(u.pos, u.w_tiles, u.h_tiles, false)
		if u.sprite != null:
			u.sprite.queue_free()
		if u.shadow_sprite != null:
			u.shadow_sprite.queue_free()
		if u.rotor_sprite != null:
			u.rotor_sprite.queue_free()
		if u.turret_sprite != null:
			u.turret_sprite.queue_free()
		if u.sel_ring != null:
			u.sel_ring.queue_free()
		if u.hp_bar_bg != null:
			u.hp_bar_bg.queue_free()
		if u.hp_bar_fill != null:
			u.hp_bar_fill.queue_free()
	units.clear()
	squads.clear()
	grid_buckets.clear()
	blue_spawn_queue.clear()
	red_spawn_queue.clear()
	for d in decal_pool:
		d.visible = false
	for h in husk_pool:
		h.visible = false
	decal_cursor = 0
	husk_cursor = 0
	for p in proj_pool:
		p.active = false
		p.sprite.visible = false
	for arc in tesla_arcs:
		arc["life"] = 0.0
		(arc["mi"] as MeshInstance3D).visible = false
	control_groups = [[], [], [], [], []]

	wave_number = 0
	wave_timer = 0.4
	spawn_step_timer = 0.0
	blue_count = 0
	red_count = 0
	blue_income_level = 1
	red_income_level = 1
	winner_team = -1
	restart_timer = 0.0
	attack_move_mode = false
	sell_mode = false
	repair_mode = false
	sw_targeting = ""
	sw_timers = { "pdox": 0.0, "iron": 0.0, "mslo": 0.0 }
	sw_ready = { "pdox": false, "iron": false, "mslo": false }
	player_struct_q = { "key": "", "progress": 0.0, "total": 1.0, "ready": false }
	player_unit_q = { "key": "", "progress": 0.0, "total": 1.0 }
	ai_struct_q = { "key": "", "progress": 0.0, "total": 1.0 }
	ai_unit_q = { "key": "", "progress": 0.0, "total": 1.0 }
	ai_think_timer = 0.5
	ai_wave_timer = 18.0

	var pair := _get_opposing_spawns()
	var left_sp := pair[0]
	var right_sp := pair[1]

	if game_mode == GameMode.AUTOBATTLE:
		blue_cash = 250 if start_cash < 0 else start_cash
		red_cash = 250
		blue_roster = { "infantry": 4, "rocket": 2, "tank": 2, "heavy": 1, "artillery": 1, "heli": 1, "plane": 1 }
		red_roster = { "infantry": 4, "rocket": 2, "tank": 2, "heavy": 1, "artillery": 1, "heli": 1, "plane": 1 }
		blue_base = _create_unit(0, "base", left_sp.x, left_sp.y)
		red_base = _create_unit(1, "base", right_sp.x, right_sp.y)
	elif game_mode == GameMode.SKIRMISH:
		blue_cash = 3000 if start_cash < 0 else start_cash
		red_cash = blue_cash
		if start_with_mcv:
			var mcv := _create_unit(0, "mcv", left_sp.x, left_sp.y)
			set_unit_selected(mcv, true)
		else:
			blue_base = _create_unit(0, "base", left_sp.x, left_sp.y)
			_create_unit(0, "infantry", left_sp.x + 3.0, left_sp.y + 2.0)
			_create_unit(0, "infantry", left_sp.x + 3.0, left_sp.y - 2.0)
		red_base = _create_unit(1, "base", right_sp.x, right_sp.y)
		_create_unit(1, "harv", right_sp.x - 3.5, right_sp.y + 2.0)
	else:
		_setup_campaign_mission(left_sp, right_sp)

	_recalc_power()
	if cam_ref != null:
		cam_ref.target_pos = Vector3(left_sp.x, 0.0, left_sp.y)

func _setup_campaign_mission(left_sp: Vector2, right_sp: Vector2) -> void:
	blue_cash = 2500 + (campaign_mission - 1) * 1000
	red_cash = 2000 + campaign_mission * 1500
	var p_bar := "tent" if player_faction == "allies" else "barr"
	var e_bar := "barr" if ai_faction == "soviet" else "tent"
	var e_def := "tsla" if ai_faction == "soviet" else "gun"

	if campaign_mission == 1:
		blue_base = _create_unit(0, "base", left_sp.x, left_sp.y)
		_place_building_direct(0, "powr", left_sp.x + 4.0, left_sp.y - 3.0)
		_place_building_direct(0, p_bar, left_sp.x + 4.0, left_sp.y + 3.0)
		for i in range(5):
			_create_unit(0, "infantry", left_sp.x + 7.0, left_sp.y - 2.0 + float(i))
		_create_unit(0, "tank", left_sp.x + 8.0, left_sp.y - 1.5)
		_create_unit(0, "tank", left_sp.x + 8.0, left_sp.y + 1.5)

		red_base = _create_unit(1, "base", right_sp.x, right_sp.y)
		_place_building_direct(1, "powr", right_sp.x - 4.0, right_sp.y - 3.0)
		_place_building_direct(1, e_bar, right_sp.x - 4.0, right_sp.y + 3.0)
		_place_building_direct(1, "pbox", right_sp.x - 7.0, right_sp.y - 2.0)
		_place_building_direct(1, "pbox", right_sp.x - 7.0, right_sp.y + 2.0)
		for i in range(4):
			_create_unit(1, "infantry", right_sp.x - 9.0, right_sp.y - 2.0 + float(i))
		_create_unit(1, "tank", right_sp.x - 10.0, right_sp.y)
	elif campaign_mission == 2:
		var mcv := _create_unit(0, "mcv", left_sp.x, left_sp.y)
		set_unit_selected(mcv, true)
		_create_unit(0, "harv", left_sp.x + 2.5, left_sp.y + 2.0)
		for i in range(4):
			_create_unit(0, "tank", left_sp.x + 5.0, left_sp.y - 2.0 + float(i) * 1.3)
			_create_unit(0, "rocket", left_sp.x + 4.0, left_sp.y - 2.0 + float(i) * 1.3)

		red_base = _create_unit(1, "base", right_sp.x, right_sp.y)
		_place_building_direct(1, "apwr", right_sp.x - 4.5, right_sp.y - 3.5)
		_place_building_direct(1, "proc", right_sp.x - 4.5, right_sp.y + 3.5)
		_place_building_direct(1, e_bar, right_sp.x - 8.5, right_sp.y - 2.0)
		_place_building_direct(1, "weap", right_sp.x - 8.5, right_sp.y + 2.5)
		_place_building_direct(1, e_def, right_sp.x - 11.5, right_sp.y - 2.0)
		_place_building_direct(1, e_def, right_sp.x - 11.5, right_sp.y + 2.0)
		_create_unit(1, "harv", right_sp.x - 6.0, right_sp.y + 5.0)
	else:
		blue_base = _create_unit(0, "base", left_sp.x, left_sp.y)
		_place_building_direct(0, "apwr", left_sp.x + 4.5, left_sp.y - 3.5)
		_place_building_direct(0, "proc", left_sp.x + 4.5, left_sp.y + 3.5)
		_place_building_direct(0, p_bar, left_sp.x + 8.5, left_sp.y - 2.5)
		_place_building_direct(0, "weap", left_sp.x + 8.5, left_sp.y + 2.5)
		_create_unit(0, "harv", left_sp.x + 6.0, left_sp.y + 5.0)
		_create_unit(0, "heavy", left_sp.x + 11.0, left_sp.y)

		red_base = _create_unit(1, "base", right_sp.x, right_sp.y)
		_place_building_direct(1, "apwr", right_sp.x - 4.5, right_sp.y - 3.5)
		_place_building_direct(1, "proc", right_sp.x - 4.5, right_sp.y + 3.5)
		_place_building_direct(1, e_bar, right_sp.x - 8.5, right_sp.y - 3.0)
		_place_building_direct(1, "weap", right_sp.x - 8.5, right_sp.y + 2.0)
		_place_building_direct(1, "dome", right_sp.x - 4.5, right_sp.y)
		_place_building_direct(1, "afld", right_sp.x - 8.5, right_sp.y + 6.0)
		_place_building_direct(1, e_def, right_sp.x - 12.0, right_sp.y - 3.0)
		_place_building_direct(1, e_def, right_sp.x - 12.0, right_sp.y + 3.0)
		_place_building_direct(1, "sam", right_sp.x - 11.0, right_sp.y)
		_create_unit(1, "harv", right_sp.x - 6.0, right_sp.y + 5.0)
		_create_unit(1, "plane", right_sp.x - 6.0, right_sp.y + 6.0)

func _place_building_direct(team: int, bkey: String, wx: float, wz: float) -> UnitData:
	var info: Dictionary = RtsData.STRUCTURES.get(bkey, {})
	var w_t := int(info.get("w", 2))
	var h_t := int(info.get("h", 2))
	var cell := terrain.find_nearest_walkable(terrain.world_to_grid(wx, wz))
	var wp := terrain.grid_to_world(cell)
	var b := _create_unit(team, bkey, wp.x, wp.y)
	terrain.set_footprint_solid(b.pos, w_t, h_t, true)
	return b

func _get_opposing_spawns() -> Array[Vector2]:
	var sp := terrain.spawn_positions
	if sp.size() < 2:
		return [Vector2(-30.0, 0.0), Vector2(30.0, 0.0)]
	var best_a := sp[0]
	var best_b := sp[1]
	var best_d2 := -1.0
	for i in range(sp.size()):
		for j in range(i + 1, sp.size()):
			var d2 := sp[i].distance_squared_to(sp[j])
			if d2 > best_d2:
				best_d2 = d2
				best_a = sp[i]
				best_b = sp[j]
	if best_a.x > best_b.x:
		return [best_b, best_a]
	return [best_a, best_b]

func _load_png(path: String) -> ImageTexture:
	var img := Image.new()
	img.load(path)
	return ImageTexture.create_from_image(img)

func _init_textures() -> void:
	var dir := RtsData.asset_path("ra_sprites")
	var keys := [
		"0_infantry", "0_rocket", "0_engineer", "0_tank", "0_heavy", "0_artillery", "0_heli", "0_plane", "0_base", "0_mcv", "0_harv",
		"1_infantry", "1_rocket", "1_engineer", "1_tank", "1_heavy", "1_artillery", "1_heli", "1_plane", "1_base", "1_mcv", "1_harv",
		"0_powr", "0_apwr", "0_proc", "0_tent", "0_barr", "0_weap", "0_dome", "0_hpad", "0_afld", "0_pbox", "0_gun", "0_tsla", "0_sam", "0_pdox", "0_iron", "0_mslo",
		"1_powr", "1_apwr", "1_proc", "1_tent", "1_barr", "1_weap", "1_dome", "1_hpad", "1_afld", "1_pbox", "1_gun", "1_tsla", "1_sam", "1_pdox", "1_iron", "1_mslo",
	]
	for k in keys:
		var fp := dir.path_join(k + ".png")
		if FileAccess.file_exists(fp):
			textures[k] = _load_png(fp)
		var dp := dir.path_join(k + "_dir.png")
		if FileAccess.file_exists(dp):
			dir_textures[k] = _load_png(dp)

	for f in DirAccess.get_files_at(dir):
		if f.begins_with("cameo_") and f.ends_with(".png"):
			var ckey := f.substr(6, f.length() - 10)
			cameos[ckey] = _load_png(dir.path_join(f))

	for ek in exp_frames.keys():
		var ep := dir.path_join("exp_%s.png" % ek)
		if FileAccess.file_exists(ep):
			exp_textures[ek] = _load_png(ep)

	for pk in ["shell", "missile", "bullet"]:
		var pp := dir.path_join("proj_%s.png" % pk)
		if FileAccess.file_exists(pp):
			proj_textures[pk] = _load_png(pp)

	for idx in range(1, 7):
		var cp := dir.path_join("crater_%d.png" % idx)
		if FileAccess.file_exists(cp):
			crater_textures.append(_load_png(cp))
		var sp_path := dir.path_join("scorch_%d.png" % idx)
		if FileAccess.file_exists(sp_path):
			scorch_textures.append(_load_png(sp_path))

	for hk in ["0_tank_husk", "1_tank_husk", "0_heavy_husk", "1_heavy_husk"]:
		var hp := dir.path_join(hk + ".png")
		if FileAccess.file_exists(hp):
			husk_textures[hk] = _load_png(hp)

	for dk in ["0_infantry_die", "1_infantry_die", "0_rocket_die", "1_rocket_die"]:
		var dp := dir.path_join(dk + ".png")
		if FileAccess.file_exists(dp):
			die_textures[dk] = _load_png(dp)

	for wk in ["0_infantry", "1_infantry", "0_rocket", "1_rocket", "0_engineer", "1_engineer"]:
		var wp := dir.path_join(wk + "_walk.png")
		if FileAccess.file_exists(wp):
			walk_textures[wk] = _load_png(wp)

	for tk in ["0_tank", "1_tank", "0_heavy", "1_heavy"]:
		var hp_t := dir.path_join(tk + "_hull_dir.png")
		var tp_t := dir.path_join(tk + "_turret_dir.png")
		if FileAccess.file_exists(hp_t) and FileAccess.file_exists(tp_t):
			hull_textures[tk] = _load_png(hp_t)
			turret_textures[tk] = _load_png(tp_t)

	for rk in ["heli_rotor", "hind_rotor"]:
		var rp := dir.path_join(rk + ".png")
		if FileAccess.file_exists(rp):
			rotor_textures[rk] = _load_png(rp)

func _init_explosions_pool() -> void:
	for i in range(MAX_EXPLOSIONS):
		var sp := Sprite3D.new()
		sp.pixel_size = RA_PIXEL_SIZE
		sp.centered = true
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.shaded = false
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.visible = false
		add_child(sp)
		var ex := ExplosionAnim.new()
		ex.sprite = sp
		explosions.append(ex)

func _init_decals_and_husks_pool() -> void:
	for i in range(MAX_DECALS):
		var sp := Sprite3D.new()
		sp.pixel_size = RA_PIXEL_SIZE
		sp.centered = true
		sp.axis = Vector3.AXIS_Y
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sp.shaded = false
		sp.double_sided = true
		sp.render_priority = 1
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.visible = false
		add_child(sp)
		decal_pool.append(sp)

	for i in range(MAX_HUSKS):
		var sp := Sprite3D.new()
		sp.pixel_size = RA_PIXEL_SIZE
		sp.centered = true
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sp.shaded = false
		sp.double_sided = true
		sp.render_priority = 1
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.visible = false
		add_child(sp)
		husk_pool.append(sp)

func _spawn_ground_decal(pos: Vector3, is_scorch: bool) -> void:
	var pool_tex := scorch_textures if is_scorch else crater_textures
	if pool_tex.is_empty():
		return
	var tex: ImageTexture = pool_tex[rng.randi_range(0, pool_tex.size() - 1)]
	var sp := decal_pool[decal_cursor]
	decal_cursor = (decal_cursor + 1) % MAX_DECALS
	sp.texture = tex
	var gy := terrain.get_height(pos.x, pos.z)
	sp.position = Vector3(pos.x, gy + 0.10 + float(decal_cursor % 5) * 0.004, pos.z)
	sp.visible = true

func _spawn_husk(u: UnitData) -> void:
	var hk := "%d_%s_husk" % [u.team, u.kind]
	if not husk_textures.has(hk):
		return
	var tex: ImageTexture = husk_textures[hk]
	var sp := husk_pool[husk_cursor]
	husk_cursor = (husk_cursor + 1) % MAX_HUSKS
	sp.texture = tex
	var gy := terrain.get_height(u.pos.x, u.pos.z)
	sp.position = Vector3(u.pos.x, gy + tex.get_height() * RA_PIXEL_SIZE * 0.45, u.pos.z)
	sp.visible = true

func _spawn_die_anim(u: UnitData) -> void:
	var dk := "%d_%s_die" % [u.team, u.kind]
	if not die_textures.has(dk):
		return
	for ex in explosions:
		if not ex.active:
			var tex: ImageTexture = die_textures[dk]
			ex.sprite.texture = tex
			ex.sprite.hframes = 8
			ex.sprite.frame = 0
			ex.sprite.position = u.pos + Vector3(0, tex.get_height() * RA_PIXEL_SIZE * 0.45, 0)
			ex.sprite.visible = true
			ex.total_frames = 8
			ex.fps = 12.0
			ex.elapsed = 0.0
			ex.active = true
			return

func _init_audio_pool() -> void:
	var adir := RtsData.asset_path("ra_audio")
	for sname in [
		"gun13", "missile6", "cannon1", "cannon2", "turret1", "missile1",
		"kaboom1", "kaboom15", "kaboom22", "dedman1", "dedman2", "dedman3",
		"baseatk1", "nofunds1", "unitrdy1", "bleep12", "bleep11",
		"placbldg", "build5", "conscmp1", "bldgprg1", "nodeply1", "powerdn1", "newopt1",
		"tesla1", "await1", "yessir1", "vehic1", "ackno", "affirm1", "roger", "noprob",
		"chrono2", "ironcur9", "strucap1"
	]:
		var wp := adir.path_join(sname + ".wav")
		if FileAccess.file_exists(wp):
			sfx_streams[sname] = AudioStreamWAV.load_from_file(wp)
			sfx_cooldowns[sname] = 0.0

	for i in range(MAX_AUDIO_PLAYERS):
		var ap := AudioStreamPlayer.new()
		ap.volume_db = -9.0
		add_child(ap)
		audio_players.append(ap)

	voice_player = AudioStreamPlayer.new()
	voice_player.volume_db = -4.0
	add_child(voice_player)

func _play_voice(sname: String) -> void:
	if voice_player == null or not sfx_streams.has(sname):
		return
	voice_player.stream = sfx_streams[sname]
	voice_player.play()

func _play_sfx(sname: String, vol_db: float = -9.0, world_pos: Vector3 = Vector3.INF) -> void:
	if not sfx_streams.has(sname):
		return
	if float(sfx_cooldowns.get(sname, 0.0)) > 0.0:
		return
	var final_vol := vol_db
	if world_pos != Vector3.INF and cam_ref != null:
		var d := Vector2(world_pos.x - cam_ref.target_pos.x, world_pos.z - cam_ref.target_pos.z).length()
		if d > 75.0:
			return
		final_vol -= 0.18 * maxf(0.0, d - 16.0)
	sfx_cooldowns[sname] = 0.075
	var ap := audio_players[audio_cursor]
	audio_cursor = (audio_cursor + 1) % MAX_AUDIO_PLAYERS
	ap.stream = sfx_streams[sname]
	ap.volume_db = final_vol
	ap.pitch_scale = rng.randf_range(0.94, 1.06) if world_pos != Vector3.INF else 1.0
	ap.play()

func _spawn_explosion(pos: Vector3, kind: String) -> void:
	if not exp_textures.has(kind):
		return
	for ex in explosions:
		if not ex.active:
			var tex: ImageTexture = exp_textures[kind]
			var frames: int = int(exp_frames[kind])
			ex.sprite.texture = tex
			ex.sprite.hframes = frames
			ex.sprite.frame = 0
			ex.sprite.position = pos + Vector3(0, tex.get_height() * RA_PIXEL_SIZE * 0.35, 0)
			ex.sprite.visible = true
			ex.total_frames = frames
			ex.fps = 22.0 if kind != "smoke" else 28.0
			ex.elapsed = 0.0
			ex.active = true
			return

func _init_tesla_arcs() -> void:
	tesla_mat = StandardMaterial3D.new()
	tesla_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tesla_mat.albedo_color = Color(0.55, 0.92, 1.0)
	for i in range(6):
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.material_override = tesla_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		tesla_arcs.append({ "mi": mi, "life": 0.0 })

func _spawn_tesla_arc(from_pos: Vector3, to_pos: Vector3) -> void:
	for arc in tesla_arcs:
		if float(arc["life"]) <= 0.0:
			var mi: MeshInstance3D = arc["mi"]
			var im: ImmediateMesh = mi.mesh
			im.clear_surfaces()
			im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			var segs := 8
			for s in range(segs + 1):
				var t := float(s) / float(segs)
				var pt := from_pos.lerp(to_pos, t)
				if s > 0 and s < segs:
					pt += Vector3(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.25, 0.45), rng.randf_range(-0.45, 0.45))
				im.surface_add_vertex(pt)
			im.surface_end()
			mi.visible = true
			arc["life"] = 0.22
			return

func _init_projectiles_mesh() -> void:
	for i in range(MAX_PROJ):
		var sp := Sprite3D.new()
		sp.pixel_size = RA_PIXEL_SIZE
		sp.centered = true
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.shaded = false
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.visible = false
		add_child(sp)
		var pd := ProjectileData.new()
		pd.sprite = sp
		proj_pool.append(pd)

# --- Power & Tech Helpers ---
func _recalc_power() -> void:
	power_produced = [0, 0]
	power_consumed = [0, 0]
	for u in units:
		if u.hp <= 0.0 or not u.is_building:
			continue
		if u.power_delta > 0:
			power_produced[u.team] += u.power_delta
		elif u.power_delta < 0:
			power_consumed[u.team] += -u.power_delta

func get_power_ratio(team: int) -> float:
	if power_consumed[team] <= 0 or power_produced[team] >= power_consumed[team]:
		return 1.0
	return clampf(float(power_produced[team]) / maxf(1.0, float(power_consumed[team])), 0.25, 0.99)

func has_radar_online(team: int) -> bool:
	if game_mode == GameMode.AUTOBATTLE:
		return true
	return has_building(team, "dome") and power_produced[team] >= power_consumed[team]

func has_building(team: int, bkey: String) -> bool:
	for u in units:
		if u.team == team and u.hp > 0.0 and u.is_building and u.kind == bkey:
			return true
	return false

func has_prereq(team: int, prereqs: Array) -> bool:
	for req in prereqs:
		if req == "tent" or req == "barr":
			if not (has_building(team, "tent") or has_building(team, "barr")):
				return false
		elif req == "fact":
			if not has_building(team, "base"):
				return false
		elif not has_building(team, String(req)):
			return false
	return true

func find_team_building(team: int, bkey: String) -> UnitData:
	for u in units:
		if u.team == team and u.hp > 0.0 and u.is_building and u.kind == bkey:
			return u
	return null

# --- Player RTS Production & Building Placement ---
func start_rts_structure(bkey: String) -> bool:
	if winner_team != -1 or not RtsData.STRUCTURES.has(bkey):
		return false
	if player_struct_q["key"] != "":
		_play_sfx("bleep11", -7.0)
		return false
	var info: Dictionary = RtsData.STRUCTURES[bkey]
	if not has_prereq(0, info["prereq"]):
		_play_sfx("bleep11", -7.0)
		return false
	var cost: int = int(info["cost"])
	if blue_cash < cost:
		_play_sfx("bleep11", -7.0)
		if nofunds_cooldown <= 0.0:
			_play_voice("nofunds1")
			nofunds_cooldown = 4.0
		return false
	blue_cash -= cost
	player_struct_q = { "key": bkey, "progress": 0.0, "total": float(info["time"]), "ready": false }
	_play_voice("bldgprg1")
	_play_sfx("bleep12", -6.0)
	return true

func start_rts_unit(ukey: String) -> bool:
	if winner_team != -1 or not RtsData.RTS_UNITS.has(ukey):
		return false
	if player_unit_q["key"] != "":
		_play_sfx("bleep11", -7.0)
		return false
	var info: Dictionary = RtsData.RTS_UNITS[ukey]
	if not has_prereq(0, info["prereq"]):
		_play_sfx("bleep11", -7.0)
		return false
	var cost: int = int(info["cost"])
	if blue_cash < cost:
		_play_sfx("bleep11", -7.0)
		if nofunds_cooldown <= 0.0:
			_play_voice("nofunds1")
			nofunds_cooldown = 4.0
		return false
	blue_cash -= cost
	player_unit_q = { "key": ukey, "progress": 0.0, "total": float(info["time"]) }
	_play_sfx("bleep12", -6.0)
	return true

func can_place_structure_at(bkey: String, world_pos: Vector3) -> bool:
	var info: Dictionary = RtsData.STRUCTURES.get(bkey, {})
	if info.is_empty():
		return false
	var w_t := int(info["w"])
	var h_t := int(info["h"])
	if not terrain.is_footprint_buildable(world_pos, w_t, h_t):
		return false
	for u in units:
		if u.team == 0 and u.hp > 0.0 and u.is_building:
			if Vector2(u.pos.x - world_pos.x, u.pos.z - world_pos.z).length() <= 14.0:
				return true
	return false

func place_ready_structure(world_pos: Vector3) -> bool:
	if not bool(player_struct_q.get("ready", false)):
		return false
	var bkey := String(player_struct_q["key"])
	if not can_place_structure_at(bkey, world_pos):
		_play_voice("nodeply1")
		return false
	var cell := terrain.world_to_grid(world_pos.x, world_pos.z)
	var wp := terrain.grid_to_world(cell)
	var b := _place_building_direct(0, bkey, wp.x, wp.y)
	player_struct_q = { "key": "", "progress": 0.0, "total": 1.0, "ready": false }
	_recalc_power()
	_play_sfx("placbldg", -6.0, b.pos)
	if bkey == "proc":
		var sp_cell := terrain.find_nearest_walkable(terrain.world_to_grid(b.pos.x + 2.5, b.pos.z + 2.5))
		var hwp := terrain.grid_to_world(sp_cell)
		_create_unit(0, "harv", hwp.x, hwp.y)
	return true

func _spawn_produced_unit(team: int, ukey: String) -> void:
	var spawn_src: UnitData = null
	if ukey in ["infantry", "rocket"]:
		spawn_src = find_team_building(team, "tent")
		if spawn_src == null:
			spawn_src = find_team_building(team, "barr")
	elif ukey == "heli":
		spawn_src = find_team_building(team, "hpad")
	elif ukey == "plane":
		spawn_src = find_team_building(team, "afld")
	else:
		spawn_src = find_team_building(team, "weap")
	if spawn_src == null:
		spawn_src = blue_base if team == 0 else red_base
	if spawn_src == null:
		return
	var offset_x := 2.8 if team == 0 else -2.8
	var cell := terrain.find_nearest_walkable(terrain.world_to_grid(spawn_src.pos.x + offset_x, spawn_src.pos.z + 2.5))
	var wp := terrain.grid_to_world(cell)
	var u := _create_unit(team, ukey, wp.x, wp.y)
	if team == 0:
		_play_voice("unitrdy1")
		if not u.is_air and u.kind != "harv":
			u.has_move_order = true
			if spawn_src.rally_pos != Vector3.INF:
				u.move_goal = spawn_src.rally_pos
			else:
				u.move_goal = Vector3(wp.x + 3.0, 0.0, wp.y + rng.randf_range(-2.0, 2.0))

# --- Player Selection & Direct Orders ---
func set_unit_selected(u: UnitData, sel: bool) -> void:
	u.selected = sel
	if u.sel_ring != null:
		u.sel_ring.visible = sel

func clear_selection() -> void:
	for u in units:
		if u.selected:
			set_unit_selected(u, false)

func get_selected_units() -> Array[UnitData]:
	var out: Array[UnitData] = []
	for u in units:
		if u.team == 0 and u.hp > 0.0 and u.selected:
			out.append(u)
	return out

func select_unit_at_world(world_pos: Vector3, additive: bool) -> void:
	if not additive:
		clear_selection()
	var best: UnitData = null
	var best_d2 := 2.8 * 2.8
	for u in units:
		if u.team != 0 or u.hp <= 0.0:
			continue
		var d2 := Vector2(u.pos.x - world_pos.x, u.pos.z - world_pos.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = u
	if best != null:
		set_unit_selected(best, true)
		_play_unit_select_voice(best)

func select_units_in_screen_rect(rect: Rect2, cam: Camera3D, additive: bool) -> void:
	if not additive:
		clear_selection()
	var first_u: UnitData = null
	for u in units:
		if u.team != 0 or u.hp <= 0.0 or u.is_building:
			continue
		var sp := cam.unproject_position(u.pos)
		if rect.has_point(sp):
			set_unit_selected(u, true)
			if first_u == null:
				first_u = u
	if first_u != null:
		_play_unit_select_voice(first_u)

func _play_unit_select_voice(u: UnitData) -> void:
	if u.is_building:
		_play_sfx("bleep12", -10.0)
	elif u.is_vehicle:
		var v := ["vehic1", "yessir1", "await1"]
		_play_voice(v[rng.randi_range(0, v.size() - 1)])
	else:
		var v := ["await1", "yessir1"]
		_play_voice(v[rng.randi_range(0, v.size() - 1)])

func assign_control_group(idx: int) -> void:
	if idx < 0 or idx >= control_groups.size():
		return
	var grp := get_selected_units()
	control_groups[idx] = grp
	if not grp.is_empty():
		_play_sfx("bleep12", -8.0)

func select_control_group(idx: int) -> void:
	if idx < 0 or idx >= control_groups.size():
		return
	var raw: Array = control_groups[idx]
	var alive: Array[UnitData] = []
	for u: UnitData in raw:
		if u != null and u.hp > 0.0:
			alive.append(u)
	control_groups[idx] = alive
	if alive.is_empty():
		return
	clear_selection()
	for u in alive:
		set_unit_selected(u, true)
	_play_unit_select_voice(alive[0])
	if last_group_tap == idx and group_tap_timer > 0.0 and cam_ref != null:
		cam_ref.target_pos = Vector3(alive[0].pos.x, 0.0, alive[0].pos.z)
	last_group_tap = idx
	group_tap_timer = 0.45

func deploy_selected_mcv() -> bool:
	for u in units:
		if u.team == 0 and u.hp > 0.0 and u.selected and u.kind == "mcv":
			if not terrain.is_footprint_buildable(u.pos, 3, 3):
				_play_voice("nodeply1")
				return false
			var wp := terrain.grid_to_world(terrain.world_to_grid(u.pos.x, u.pos.z))
			u.hp = 0.0
			blue_base = _place_building_direct(0, "base", wp.x, wp.y)
			_recalc_power()
			_play_sfx("placbldg", -5.0, blue_base.pos)
			return true
	return false

func stop_selected_units() -> void:
	for u in get_selected_units():
		u.has_move_order = false
		u.forced_target = null
		u.attack_move = false
		u.path = PackedVector2Array()

func issue_right_click_order(world_pos: Vector3) -> void:
	var sel := get_selected_units()
	if sel.is_empty():
		return

	# Check if clicked on enemy unit/building
	var enemy_hit: UnitData = null
	var best_d2 := 2.6 * 2.6
	for other in units:
		if other.team == 1 and other.hp > 0.0:
			var d2 := Vector2(other.pos.x - world_pos.x, other.pos.z - world_pos.z).length_squared()
			if d2 < best_d2:
				best_d2 = d2
				enemy_hit = other

	# Check if clicked on own MCV to deploy
	if enemy_hit == null and sel.size() == 1 and sel[0].kind == "mcv":
		if Vector2(sel[0].pos.x - world_pos.x, sel[0].pos.z - world_pos.z).length() < 1.8:
			deploy_selected_mcv()
			return

	var count := sel.size()
	var cols := maxi(1, int(ceil(sqrt(float(count)))))
	var moved_any := false
	for i in range(count):
		var u := sel[i]
		if u.is_building:
			if u.kind in ["tent", "barr", "weap", "hpad", "afld"]:
				u.rally_pos = world_pos
				_play_sfx("bleep12", -8.0)
			continue
		moved_any = true
		if enemy_hit != null:
			u.forced_target = enemy_hit
			u.target = enemy_hit
			u.has_move_order = false
			u.attack_move = false
		else:
			var row := i / cols
			var col := i % cols
			var ox := (float(col) - float(cols - 1) * 0.5) * 1.4
			var oz := (float(row) - float(count / cols) * 0.5) * 1.4
			u.forced_target = null
			if not attack_move_mode:
				u.target = null
			u.attack_move = attack_move_mode
			u.has_move_order = true
			u.move_goal = Vector3(world_pos.x + ox, 0.0, world_pos.z + oz)
			u.repath_timer = 0.0
	attack_move_mode = false
	sell_mode = false
	repair_mode = false
	sw_targeting = ""
	sw_timers = { "pdox": 0.0, "iron": 0.0, "mslo": 0.0 }
	sw_ready = { "pdox": false, "iron": false, "mslo": false }
	if moved_any:
		var ack := ["ackno", "affirm1", "roger", "noprob"]
		_play_voice(ack[rng.randi_range(0, ack.size() - 1)])

func sell_building_at(world_pos: Vector3) -> bool:
	for u in units:
		if u.team == 0 and u.hp > 0.0 and u.is_building:
			if Vector2(u.pos.x - world_pos.x, u.pos.z - world_pos.z).length() <= maxf(1.5, float(u.w_tiles) * 0.7):
				var refund := 500
				if RtsData.STRUCTURES.has(u.kind):
					refund = int(RtsData.STRUCTURES[u.kind]["cost"]) / 2
				blue_cash += refund
				u.sold = true
				u.hp = 0.0
				_play_sfx("placbldg", -6.0, u.pos)
				sell_mode = false
				return true
	return false

func toggle_repair_at(world_pos: Vector3) -> bool:
	for u in units:
		if u.team == 0 and u.hp > 0.0 and u.is_building:
			if Vector2(u.pos.x - world_pos.x, u.pos.z - world_pos.z).length() <= maxf(1.5, float(u.w_tiles) * 0.7):
				if u.hp < u.max_hp:
					u.repairing = not u.repairing
					_play_sfx("bleep12", -6.0)
					repair_mode = false
					return true
	return false

func get_hover_context(world_pos: Vector3) -> String:
	if sell_mode:
		return "sell"
	if repair_mode:
		return "repair"
	var sel := get_selected_units()
	if sel.is_empty():
		return "default"
	if attack_move_mode:
		return "attack"
	for other in units:
		if other.team == 1 and other.hp > 0.0 and other.sprite.visible:
			if Vector2(other.pos.x - world_pos.x, other.pos.z - world_pos.z).length() <= 2.2:
				return "attack"
	if sel.size() == 1 and sel[0].kind == "mcv":
		if Vector2(sel[0].pos.x - world_pos.x, sel[0].pos.z - world_pos.z).length() <= 1.8:
			return "deploy"
	return "move"

# --- Autobattle Upgrades ---
func buy_unit_upgrade(kind: String) -> bool:
	if winner_team != -1 or not UNIT_COSTS.has(kind):
		return false
	var cost: int = UNIT_COSTS[kind]
	if blue_cash < cost:
		_play_sfx("bleep11", -7.0)
		if nofunds_cooldown <= 0.0:
			_play_voice("nofunds1")
			nofunds_cooldown = 4.0
		return false
	blue_cash -= cost
	var add_amt := 2 if kind == "infantry" else 1
	blue_roster[kind] = int(blue_roster.get(kind, 0)) + add_amt
	_play_sfx("bleep12", -6.0)
	return true

func buy_income_upgrade() -> bool:
	if winner_team != -1:
		return false
	var cost := 150 * blue_income_level
	if blue_cash < cost:
		_play_sfx("bleep11", -7.0)
		if nofunds_cooldown <= 0.0:
			_play_voice("nofunds1")
			nofunds_cooldown = 4.0
		return false
	blue_cash -= cost
	blue_income_level += 1
	_play_sfx("bleep12", -6.0)
	return true

func get_income_upgrade_cost() -> int:
	return 150 * blue_income_level

func _process(delta: float) -> void:
	if not match_active:
		return
	var dt := minf(delta, 0.05)

	if winner_team != -1:
		if game_mode == GameMode.AUTOBATTLE:
			restart_timer -= dt
			if restart_timer <= 0.0:
				reset_match()
		return

	if game_mode == GameMode.AUTOBATTLE:
		cash_accum += dt
		if cash_accum >= 1.0:
			cash_accum -= 1.0
			blue_cash += 28 + (blue_income_level - 1) * 14
			red_cash += 28 + (red_income_level - 1) * 14 + (wave_number / 4) * 6
			_ai_spend_cash()

		wave_timer -= dt
		if wave_timer <= 0.0:
			wave_timer = WAVE_INTERVAL
			_enqueue_wave()

		_process_spawn_queue(dt)
	else:
		_update_rts_production(dt)
		_update_skirmish_ai(dt)
		_update_superweapons(dt)

	_update_units(dt)
	_update_squads(dt)
	_update_projectiles(dt)
	_update_explosions_and_audio(dt)
	_check_rts_victory()

func _update_superweapons(dt: float) -> void:
	var p_ratio := get_power_ratio(0)
	for sw in ["pdox", "iron", "mslo"]:
		if has_building(0, sw):
			if not bool(sw_ready[sw]):
				sw_timers[sw] = float(sw_timers[sw]) + dt * p_ratio
				if float(sw_timers[sw]) >= float(sw_totals[sw]):
					sw_timers[sw] = float(sw_totals[sw])
					sw_ready[sw] = true
					_play_voice("unitrdy1")
		else:
			sw_timers[sw] = 0.0
			sw_ready[sw] = false

func trigger_superweapon(sw_key: String, world_pos: Vector3) -> bool:
	if not bool(sw_ready.get(sw_key, false)):
		return false
	sw_ready[sw_key] = false
	sw_timers[sw_key] = 0.0
	sw_targeting = ""

	if sw_key == "pdox":
		var targets := get_selected_units()
		if targets.is_empty():
			for u in units:
				if u.team == 0 and u.hp > 0.0 and u.is_vehicle and not u.is_building and not u.is_air:
					targets.append(u)
					if targets.size() >= 4:
						break
		for u in targets:
			if u.is_building or u.is_air:
				continue
			var cell := terrain.find_nearest_walkable(terrain.world_to_grid(world_pos.x + rng.randf_range(-1.5, 1.5), world_pos.z + rng.randf_range(-1.5, 1.5)))
			var wp := terrain.grid_to_world(cell)
			u.pos = Vector3(wp.x, terrain.get_height(wp.x, wp.y), wp.y)
			u.sprite.position = u.pos + Vector3(0, u.y_offset, 0)
			if u.turret_sprite != null:
				u.turret_sprite.position = u.sprite.position + Vector3(0, 0.04, 0.05)
			if u.sel_ring != null:
				u.sel_ring.position = Vector3(u.pos.x, u.pos.y + 0.12, u.pos.z)
			u.path = PackedVector2Array()
			u.has_move_order = false
		_spawn_explosion(world_pos, "vehhit")
		_play_sfx("chrono2", -4.0, world_pos)
		return true

	if sw_key == "iron":
		for u in units:
			if u.team == 0 and u.hp > 0.0 and u.is_vehicle:
				if Vector2(u.pos.x - world_pos.x, u.pos.z - world_pos.z).length() <= 6.5:
					u.invuln_timer = 8.0
		_play_sfx("ironcur9", -4.0, world_pos)
		return true

	if sw_key == "mslo":
		for k in range(5):
			var off := Vector3(rng.randf_range(-3.5, 3.5), 0.0, rng.randf_range(-3.5, 3.5))
			_spawn_explosion(world_pos + off, "fball")
			_spawn_ground_decal(world_pos + off, true)
		_play_sfx("kaboom22", -2.0, world_pos)
		for u in units:
			if u.hp <= 0.0 or u.invuln_timer > 0.0:
				continue
			var d := Vector2(u.pos.x - world_pos.x, u.pos.z - world_pos.z).length()
			if d <= 9.5:
				u.hp -= 850.0 * (1.0 - d / 12.0)
		return true
	return false

func _update_rts_production(dt: float) -> void:
	var p_ratio := get_power_ratio(0)
	if player_struct_q["key"] != "" and not bool(player_struct_q["ready"]):
		player_struct_q["progress"] += dt * p_ratio
		if float(player_struct_q["progress"]) >= float(player_struct_q["total"]):
			player_struct_q["progress"] = float(player_struct_q["total"])
			player_struct_q["ready"] = true
			_play_voice("conscmp1")

	if player_unit_q["key"] != "":
		player_unit_q["progress"] += dt * p_ratio
		if float(player_unit_q["progress"]) >= float(player_unit_q["total"]):
			var ukey := String(player_unit_q["key"])
			player_unit_q = { "key": "", "progress": 0.0, "total": 1.0 }
			_spawn_produced_unit(0, ukey)

func _update_skirmish_ai(dt: float) -> void:
	# Passive trickle so AI never deadlocks if Ore runs low
	cash_accum += dt
	if cash_accum >= 1.0:
		cash_accum -= 1.0
		red_cash += 15 if game_mode == GameMode.SKIRMISH else 22

	var a_ratio := get_power_ratio(1)
	if ai_struct_q["key"] != "":
		ai_struct_q["progress"] += dt * a_ratio
		if float(ai_struct_q["progress"]) >= float(ai_struct_q["total"]):
			var bkey := String(ai_struct_q["key"])
			ai_struct_q = { "key": "", "progress": 0.0, "total": 1.0 }
			if red_base != null and red_base.hp > 0.0:
				var ox := rng.randf_range(-11.0, -3.0)
				var oz := rng.randf_range(-9.0, 9.0)
				var b := _place_building_direct(1, bkey, red_base.pos.x + ox, red_base.pos.z + oz)
				_recalc_power()
				if bkey == "proc":
					var sp_cell := terrain.find_nearest_walkable(terrain.world_to_grid(b.pos.x - 2.5, b.pos.z + 2.5))
					var hwp := terrain.grid_to_world(sp_cell)
					_create_unit(1, "harv", hwp.x, hwp.y)

	if ai_unit_q["key"] != "":
		ai_unit_q["progress"] += dt * a_ratio
		if float(ai_unit_q["progress"]) >= float(ai_unit_q["total"]):
			var ukey := String(ai_unit_q["key"])
			ai_unit_q = { "key": "", "progress": 0.0, "total": 1.0 }
			_spawn_produced_unit(1, ukey)

	ai_think_timer -= dt
	if ai_think_timer <= 0.0:
		ai_think_timer = 1.6
		if ai_struct_q["key"] == "" and red_base != null and red_base.hp > 0.0:
			var next_b := _ai_pick_next_building()
			if next_b != "":
				var binfo: Dictionary = RtsData.STRUCTURES[next_b]
				var bcost := int(binfo["cost"])
				if red_cash >= bcost:
					red_cash -= bcost
					ai_struct_q = { "key": next_b, "progress": 0.0, "total": float(binfo["time"]) }

		if ai_unit_q["key"] == "" and red_count < 45:
			var next_u := _ai_pick_next_unit()
			if next_u != "":
				var uinfo: Dictionary = RtsData.RTS_UNITS[next_u]
				var ucost := int(uinfo["cost"])
				if red_cash >= ucost:
					red_cash -= ucost
					ai_unit_q = { "key": next_u, "progress": 0.0, "total": float(uinfo["time"]) }

	ai_wave_timer -= dt
	if ai_wave_timer <= 0.0:
		ai_wave_timer = 16.0
		var idle_ai: Array[UnitData] = []
		for u in units:
			if u.team == 1 and u.hp > 0.0 and not u.is_building and u.kind != "harv" and u.squad == null:
				idle_ai.append(u)
		if idle_ai.size() >= 4:
			var sq := SquadData.new()
			sq.team = 1
			sq.state = SquadState.ATTACK
			for u in idle_ai:
				u.squad = sq
				sq.members.append(u)
			squads.append(sq)

func _ai_pick_next_building() -> String:
	var bar_key := "barr" if ai_faction == "soviet" else "tent"
	var def_key := "tsla" if ai_faction == "soviet" else "gun"
	if power_produced[1] <= power_consumed[1] + 20:
		return "apwr" if has_building(1, "powr") and red_cash >= 500 else "powr"
	if not has_building(1, "proc"):
		return "proc"
	if not has_building(1, bar_key):
		return bar_key
	if not has_building(1, "weap"):
		return "weap"
	if not has_building(1, "dome"):
		return "dome"
	if not has_building(1, "pbox"):
		return "pbox"
	if not has_building(1, def_key):
		return def_key
	if not has_building(1, "hpad"):
		return "hpad"
	if not has_building(1, "afld"):
		return "afld"
	return ""

func _ai_pick_next_unit() -> String:
	var pool: Array[String] = []
	for k in RtsData.get_unit_order():
		if k == "mcv":
			continue
		if k == "harv" and has_building(1, "harv"):
			continue
		var info: Dictionary = RtsData.RTS_UNITS[k]
		if has_prereq(1, info["prereq"]):
			pool.append(k)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]

func _check_rts_victory() -> void:
	if game_mode == GameMode.AUTOBATTLE or winner_team != -1:
		return
	var p_alive := false
	var e_alive := false
	for u in units:
		if u.hp <= 0.0:
			continue
		if u.team == 0:
			p_alive = true
		elif u.team == 1:
			e_alive = true
	if not e_alive:
		winner_team = 0
	elif not p_alive:
		winner_team = 1

func _update_explosions_and_audio(dt: float) -> void:
	base_attack_cooldown = maxf(0.0, base_attack_cooldown - dt)
	nofunds_cooldown = maxf(0.0, nofunds_cooldown - dt)
	group_tap_timer = maxf(0.0, group_tap_timer - dt)
	for arc in tesla_arcs:
		if float(arc["life"]) > 0.0:
			arc["life"] = float(arc["life"]) - dt
			if float(arc["life"]) <= 0.0:
				(arc["mi"] as MeshInstance3D).visible = false
	for k in sfx_cooldowns.keys():
		if sfx_cooldowns[k] > 0.0:
			sfx_cooldowns[k] = maxf(0.0, float(sfx_cooldowns[k]) - dt)

	for ex in explosions:
		if not ex.active:
			continue
		ex.elapsed += dt
		var f := int(ex.elapsed * ex.fps)
		if f >= ex.total_frames:
			ex.active = false
			ex.sprite.visible = false
		else:
			ex.sprite.frame = f

func _ai_spend_cash() -> void:
	var inc_cost := 150 * red_income_level
	if red_income_level < blue_income_level + 1 and red_cash >= inc_cost and rng.randf() < 0.35:
		red_cash -= inc_cost
		red_income_level += 1
		return

	var blue_armor := 0
	var blue_inf := 0
	for u in units:
		if u.team == 0 and u.hp > 0.0 and not u.is_base:
			if u.armor_type == "Heavy":
				blue_armor += 1
			elif u.armor_type == "None":
				blue_inf += 1

	var choices := ["infantry", "rocket", "tank", "heavy", "artillery", "heli", "plane"]
	var weights: Array[float] = []
	var total_w := 0.0
	for k in choices:
		var w := float(AI_WEIGHTS.get(k, 25.0))
		if blue_armor > blue_inf + 2 and (k == "rocket" or k == "heavy"):
			w *= 1.85
		elif blue_inf > blue_armor + 3 and (k == "infantry" or k == "artillery"):
			w *= 1.7
		weights.append(w)
		total_w += w

	var roll := rng.randf() * total_w
	var pick := "infantry"
	var acc := 0.0
	for i in range(choices.size()):
		acc += weights[i]
		if roll <= acc:
			pick = choices[i]
			break

	var cost: int = UNIT_COSTS[pick]
	if red_cash >= cost:
		red_cash -= cost
		var add_amt := 2 if pick == "infantry" else 1
		red_roster[pick] = int(red_roster.get(pick, 0)) + add_amt

func _enqueue_wave() -> void:
	wave_number += 1
	var kinds := ["infantry", "rocket", "tank", "heavy", "artillery", "heli", "plane"]
	for team in [0, 1]:
		var q := blue_spawn_queue if team == 0 else red_spawn_queue
		var roster := blue_roster if team == 0 else red_roster
		for kind in kinds:
			var cnt: int = int(roster.get(kind, 0))
			for i in range(cnt):
				if q.size() >= MAX_SPAWN_QUEUE:
					break
				q.append(kind)

func _process_spawn_queue(dt: float) -> void:
	spawn_step_timer -= dt
	if spawn_step_timer > 0.0:
		return
	spawn_step_timer = SPAWN_STEP_INTERVAL

	var pair := _get_opposing_spawns()
	var left_spawn := pair[0]
	var right_spawn := pair[1]

	for team in [0, 1]:
		var q := blue_spawn_queue if team == 0 else red_spawn_queue
		if q.is_empty():
			continue
		var current := blue_count if team == 0 else red_count
		if current >= MAX_UNITS_PER_SIDE:
			continue

		var kind: String = q.pop_front()
		var sp_center := left_spawn if team == 0 else right_spawn
		var enemy_center := right_spawn if team == 0 else left_spawn
		var to_enemy := (enemy_center - sp_center).normalized()
		var rally_2d := sp_center + to_enemy * 8.0
		var rally_cell := terrain.find_nearest_walkable(terrain.world_to_grid(rally_2d.x, rally_2d.y))
		var rally_w := terrain.grid_to_world(rally_cell)

		var sq: SquadData = null
		for cand in squads:
			if cand.team == team and cand.state == SquadState.GATHER and cand.members.size() < 8:
				sq = cand
				break
		if sq == null:
			sq = SquadData.new()
			sq.team = team
			sq.state = SquadState.GATHER
			sq.rally_pos = Vector3(rally_w.x, terrain.get_height(rally_w.x, rally_w.y), rally_w.y)
			sq.gather_timer = 2.0
			squads.append(sq)

		var sx := clampf(sp_center.x + rng.randf_range(-5.0, 5.0), -terrain.world_width * 0.46, terrain.world_width * 0.46)
		var sz := clampf(sp_center.y + rng.randf_range(-5.0, 5.0), -terrain.world_depth * 0.44, terrain.world_depth * 0.44)
		var cell := terrain.find_nearest_walkable(terrain.world_to_grid(sx, sz))
		var wp := terrain.grid_to_world(cell)
		var u := _create_unit(team, kind, wp.x, wp.y)
		u.squad = sq
		sq.members.append(u)

func _create_unit(team: int, kind: String, x: float, z: float) -> UnitData:
	var u := UnitData.new()
	u.team = team
	u.kind = kind
	u.pos = Vector3(x, terrain.get_height(x, z), z)
	var pixel_scale := RA_PIXEL_SIZE
	u.armor_type = String(ARMOR_TYPES.get(kind, "None"))

	if RtsData.STRUCTURES.has(kind):
		var sinfo: Dictionary = RtsData.STRUCTURES[kind]
		u.is_building = true
		u.is_vehicle = true
		u.max_hp = float(sinfo.get("hp", 800.0))
		u.w_tiles = int(sinfo.get("w", 2))
		u.h_tiles = int(sinfo.get("h", 2))
		u.power_delta = int(sinfo.get("power", 0))
		u.speed = 0.0
		if bool(sinfo.get("defense", false)):
			u.attack_range = float(sinfo.get("range", 6.0))
			u.damage = float(sinfo.get("dmg", 30.0))
			u.fire_rate = float(sinfo.get("rate", 1.2))
			u.weapon_kind = String(sinfo.get("weapon", "bullet"))
			u.aa_only = bool(sinfo.get("aa_only", false))
		else:
			u.attack_range = 0.0
			u.fire_rate = 99.0
	else:
		match kind:
			"base":
				u.max_hp = 4500.0; u.speed = 0.0; u.attack_range = 0.0; u.damage = 0.0; u.fire_rate = 99.0
				u.is_vehicle = true; u.is_base = true; u.is_building = true; u.w_tiles = 3; u.h_tiles = 3; u.weapon_kind = "shell"
			"mcv":
				u.max_hp = 600.0; u.speed = 1.22; u.attack_range = 0.0; u.damage = 0.0; u.fire_rate = 99.0; u.is_vehicle = true
			"harv":
				u.max_hp = 700.0; u.speed = 1.45; u.attack_range = 0.0; u.damage = 0.0; u.fire_rate = 99.0; u.is_vehicle = true
			"infantry":
				u.max_hp = 55.0; u.speed = 1.32; u.attack_range = 5.0; u.damage = 11.0; u.fire_rate = 0.80; u.is_vehicle = false; u.weapon_kind = "bullet"
			"rocket":
				u.max_hp = 60.0; u.speed = 1.32; u.attack_range = 5.0; u.aa_range = 7.5; u.damage = 24.0; u.fire_rate = 2.00; u.is_vehicle = false; u.weapon_kind = "missile"
			"engineer":
				u.max_hp = 45.0; u.speed = 1.32; u.attack_range = 0.0; u.damage = 0.0; u.fire_rate = 99.0; u.is_vehicle = false
			"tank":
				var tank_spd := 1.76 if team == 0 else 1.56
				u.max_hp = 210.0; u.speed = tank_spd; u.attack_range = 4.75; u.damage = 36.0 if team == 0 else 44.0; u.fire_rate = 2.00 if team == 0 else 2.20; u.is_vehicle = true; u.weapon_kind = "shell"
			"heavy":
				u.max_hp = 380.0; u.speed = 1.05; u.attack_range = 4.75; u.aa_range = 6.5; u.damage = 62.0; u.fire_rate = 2.40; u.is_vehicle = true; u.weapon_kind = "shell"
			"artillery":
				var art_rng := 12.0 if team == 0 else 10.0
				u.max_hp = 140.0; u.speed = 1.76; u.attack_range = art_rng; u.min_range = 4.0; u.damage = 70.0 if team == 0 else 120.0; u.fire_rate = 3.40 if team == 0 else 7.20; u.is_vehicle = true; u.weapon_kind = "artillery"
			"heli":
				var heli_spd := 3.64 if team == 0 else 2.73
				u.max_hp = 140.0; u.speed = heli_spd; u.attack_range = 5.0; u.aa_range = 4.0 if team == 0 else 0.0; u.damage = 28.0 if team == 0 else 14.0; u.fire_rate = 1.36 if team == 0 else 0.40; u.is_vehicle = true; u.is_air = true; u.altitude = 3.2; u.weapon_kind = "missile" if team == 0 else "bullet"
			"plane":
				var plane_spd := 4.35 if team == 0 else 5.44
				u.max_hp = 100.0; u.speed = plane_spd; u.attack_range = 5.0 if team == 0 else 9.0; u.damage = 18.0 if team == 0 else 65.0; u.fire_rate = 0.25 if team == 0 else 2.00; u.is_vehicle = true; u.is_air = true; u.altitude = 4.8; u.weapon_kind = "bullet" if team == 0 else "missile"

	var kstr := "%d_%s" % [team, kind]
	var tex: ImageTexture = textures.get(kstr, textures["0_base"])
	u.y_offset = tex.get_height() * pixel_scale * 0.45
	if u.is_air:
		u.pos.y += u.altitude
		u.air_heading = Vector3.RIGHT if team == 0 else Vector3.LEFT
	u.hp = u.max_hp
	u.cooldown = rng.randf_range(0.0, minf(u.fire_rate, 1.0))

	var sp := Sprite3D.new()
	if hull_textures.has(kstr):
		u.dir_count = 32
		sp.texture = hull_textures[kstr]
		sp.hframes = u.dir_count
		sp.frame = (u.dir_count * 3 / 4) if team == 0 else (u.dir_count / 4)
	elif dir_textures.has(kstr):
		u.dir_count = 16 if kind == "plane" else (32 if u.is_vehicle else 8)
		sp.texture = dir_textures[kstr]
		sp.hframes = u.dir_count
		sp.frame = (u.dir_count * 3 / 4) if team == 0 else (u.dir_count / 4)
	else:
		u.dir_count = 1
		sp.texture = tex
	sp.pixel_size = pixel_scale
	sp.centered = true
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.position = u.pos + Vector3(0, u.y_offset, 0)
	add_child(sp)
	u.sprite = sp

	if turret_textures.has(kstr):
		var tsp := Sprite3D.new()
		tsp.texture = turret_textures[kstr]
		tsp.hframes = 32
		tsp.frame = sp.frame
		tsp.pixel_size = pixel_scale
		tsp.centered = true
		tsp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tsp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		tsp.shaded = true
		tsp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		tsp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tsp.render_priority = 1
		tsp.position = sp.position + Vector3(0, 0.04, 0.05)
		add_child(tsp)
		u.turret_sprite = tsp

	if team == 0:
		var ring := MeshInstance3D.new()
		ring.mesh = sel_ring_mesh
		ring.material_override = sel_ring_mat
		var rscale := 1.8 if u.is_building else (1.1 if u.is_vehicle else 0.7)
		ring.scale = Vector3(rscale, 0.3, rscale)
		ring.position = Vector3(u.pos.x, terrain.get_height(u.pos.x, u.pos.z) + 0.12, u.pos.z)
		ring.visible = false
		add_child(ring)
		u.sel_ring = ring

	var hbg := MeshInstance3D.new()
	hbg.mesh = hp_bg_mesh
	hbg.material_override = hp_bg_mat
	var bw := 1.4 if u.is_building else (0.95 if u.is_vehicle else 0.55)
	hbg.scale = Vector3(bw, 1.0, 1.0)
	hbg.position = sp.position + Vector3(0, u.y_offset + 0.28, 0)
	hbg.visible = false
	add_child(hbg)
	u.hp_bar_bg = hbg

	var hfill := MeshInstance3D.new()
	hfill.mesh = hp_fill_mesh
	hfill.material_override = hp_green_mat
	hfill.scale = Vector3(bw, 1.0, 1.0)
	hfill.position = hbg.position
	hfill.visible = false
	add_child(hfill)
	u.hp_bar_fill = hfill

	if u.is_air:
		var sh := Sprite3D.new()
		sh.texture = sp.texture
		sh.hframes = sp.hframes
		sh.frame = sp.frame
		sh.pixel_size = pixel_scale
		sh.centered = true
		sh.axis = Vector3.AXIS_Y
		sh.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sh.shaded = false
		sh.modulate = Color(0.0, 0.0, 0.0, 0.45)
		sh.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sh.position = Vector3(u.pos.x, terrain.get_height(u.pos.x, u.pos.z) + 0.08, u.pos.z)
		add_child(sh)
		u.shadow_sprite = sh

		if kind == "heli":
			var rk := "heli_rotor" if team == 0 else "hind_rotor"
			if rotor_textures.has(rk):
				var rsp := Sprite3D.new()
				rsp.texture = rotor_textures[rk]
				rsp.hframes = 4
				rsp.frame = 0
				rsp.pixel_size = pixel_scale
				rsp.centered = true
				rsp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				rsp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				rsp.shaded = false
				rsp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
				rsp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				rsp.render_priority = 2
				rsp.position = sp.position + Vector3(0, 0.08, 0.08)
				add_child(rsp)
				u.rotor_sprite = rsp

	units.append(u)
	if not u.is_building:
		if team == 0:
			blue_count += 1
		else:
			red_count += 1
	return u

func _set_unit_facing(u: UnitData, dir_x: float, dir_z: float, is_moving: bool = false) -> void:
	if u.dir_count <= 1:
		return
	var angle := atan2(-dir_x, -dir_z)
	var norm := fposmod(angle / TAU, 1.0)
	var dir_idx := int(round(norm * float(u.dir_count))) % u.dir_count
	var kstr := "%d_%s" % [u.team, u.kind]
	if not u.is_vehicle and walk_textures.has(kstr):
		if is_moving:
			if not u.is_walking_anim:
				u.is_walking_anim = true
				u.sprite.texture = walk_textures[kstr]
				u.sprite.hframes = 48
			var step := int(u.anim_timer * 9.0) % 6
			u.sprite.frame = dir_idx * 6 + step
			return
		elif u.is_walking_anim:
			u.is_walking_anim = false
			u.sprite.texture = dir_textures[kstr]
			u.sprite.hframes = u.dir_count
	u.sprite.frame = dir_idx

func _rebuild_spatial_grid() -> void:
	grid_buckets.clear()
	for u in units:
		if u.hp <= 0.0:
			continue
		var bx := int(floor(u.pos.x / BUCKET_SIZE))
		var bz := int(floor(u.pos.z / BUCKET_SIZE))
		var key := Vector2i(bx, bz)
		if not grid_buckets.has(key):
			grid_buckets[key] = []
		grid_buckets[key].append(u)

func _query_nearby_units(pos: Vector3, radius: float) -> Array[UnitData]:
	var res: Array[UnitData] = []
	var r_cells := int(ceil(radius / BUCKET_SIZE))
	var cx := int(floor(pos.x / BUCKET_SIZE))
	var cz := int(floor(pos.z / BUCKET_SIZE))
	for dz in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if grid_buckets.has(key):
				for item: UnitData in grid_buckets[key]:
					res.append(item)
	return res

func _compute_separation(u: UnitData) -> Vector3:
	var sep_rad := 0.9 if u.is_vehicle else 0.52
	var sep_rad2 := sep_rad * sep_rad
	var push := Vector3.ZERO
	var neighbors := _query_nearby_units(u.pos, sep_rad)
	for other: UnitData in neighbors:
		if other == u or other.hp <= 0.0:
			continue
		var diff: Vector3 = u.pos - other.pos
		diff.y = 0.0
		var d2: float = diff.length_squared()
		if d2 > 0.0001 and d2 < sep_rad2:
			var d := sqrt(d2)
			push += (diff / d) * ((sep_rad - d) / sep_rad)
		elif d2 <= 0.0001:
			push += Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
	return push

func _update_squads(dt: float) -> void:
	squad_scan_timer -= dt
	var check_bases := false
	if squad_scan_timer <= 0.0:
		squad_scan_timer = 0.8
		check_bases = true

	var base_threat := [false, false]
	if check_bases:
		for team in [0, 1]:
			var my_base := blue_base if team == 0 else red_base
			if my_base != null and my_base.hp > 0.0:
				var near := _query_nearby_units(my_base.pos, 15.0)
				for other in near:
					if other.team != team and other.hp > 0.0 and my_base.pos.distance_squared_to(other.pos) <= 225.0:
						base_threat[team] = true
						break

	for i in range(squads.size() - 1, -1, -1):
		var sq := squads[i]
		for m_idx in range(sq.members.size() - 1, -1, -1):
			if sq.members[m_idx].hp <= 0.0:
				sq.members.remove_at(m_idx)
		if sq.members.is_empty():
			squads.remove_at(i)
			continue

		if sq.state == SquadState.GATHER:
			sq.gather_timer -= dt
			if sq.gather_timer <= 0.0 or sq.members.size() >= 8:
				sq.state = SquadState.ATTACK

		if check_bases:
			if base_threat[sq.team]:
				sq.state = SquadState.PROTECT
			elif sq.state == SquadState.PROTECT:
				sq.state = SquadState.ATTACK

func _update_harvester(u: UnitData, dt: float) -> void:
	var proc := find_team_building(u.team, "proc")
	var goal := u.pos
	var move_needed := false

	if u.has_move_order:
		goal = u.move_goal
		move_needed = true
		if Vector2(u.pos.x - goal.x, u.pos.z - goal.z).length() < 1.2:
			u.has_move_order = false
	elif u.harv_state == 0:
		if u.harv_ore_pos == Vector3.ZERO:
			var ore := terrain.find_nearest_resource(u.pos)
			u.harv_ore_pos = Vector3(ore.x, 0.0, ore.y)
		goal = u.harv_ore_pos
		if Vector2(u.pos.x - goal.x, u.pos.z - goal.z).length() < 1.8:
			u.harv_state = 1
			u.harv_timer = 3.0
		else:
			move_needed = true
	elif u.harv_state == 1:
		u.harv_timer -= dt
		if u.harv_timer <= 0.0:
			u.harv_cargo = 600
			u.harv_state = 2
	elif u.harv_state == 2:
		if proc != null and proc.hp > 0.0:
			goal = proc.pos
			if Vector2(u.pos.x - goal.x, u.pos.z - goal.z).length() < 3.2:
				if u.team == 0:
					blue_cash += u.harv_cargo
				else:
					red_cash += u.harv_cargo
				u.harv_cargo = 0
				u.harv_state = 0
				u.harv_ore_pos = Vector3.ZERO
			else:
				move_needed = true

	if move_needed:
		_move_ground_unit(u, goal, dt)

func _move_ground_unit(u: UnitData, goal_pos: Vector3, dt: float) -> void:
	if u.repath_timer <= 0.0 or u.path_idx >= u.path.size():
		u.repath_timer = rng.randf_range(0.55, 0.95)
		u.path = terrain.find_path_world(u.pos, goal_pos)
		u.path_idx = 0

	var move_dir := Vector3.ZERO
	if u.path_idx < u.path.size():
		var wp := u.path[u.path_idx]
		var to_wp := Vector3(wp.x - u.pos.x, 0.0, wp.y - u.pos.z)
		if to_wp.length_squared() < 0.45:
			u.path_idx += 1
		elif to_wp.length_squared() > 0.001:
			move_dir = to_wp.normalized()
	else:
		var direct := Vector3(goal_pos.x - u.pos.x, 0.0, goal_pos.z - u.pos.z)
		if direct.length_squared() > 0.01:
			move_dir = direct.normalized()

	var sep := _compute_separation(u)
	if move_dir.length_squared() > 0.001 or sep.length_squared() > 0.01:
		var combined := move_dir + sep * 0.85
		if combined.length_squared() > 0.001:
			var step_dir := combined.normalized()
			u.anim_timer += dt
			if move_dir.length_squared() > 0.001:
				_set_unit_facing(u, move_dir.x, move_dir.z, true)
			var spd_mult := 1.0 if move_dir.length_squared() > 0.001 else 0.45
			var nx := clampf(u.pos.x + step_dir.x * u.speed * spd_mult * dt, -terrain.world_width * 0.48, terrain.world_width * 0.48)
			var nz := clampf(u.pos.z + step_dir.z * u.speed * spd_mult * dt, -terrain.world_depth * 0.48, terrain.world_depth * 0.48)
			if terrain.is_walkable_cell(terrain.world_to_grid(nx, nz)):
				u.pos.x = nx
				u.pos.z = nz
			elif terrain.is_walkable_cell(terrain.world_to_grid(nx, u.pos.z)):
				u.pos.x = nx
			elif terrain.is_walkable_cell(terrain.world_to_grid(u.pos.x, nz)):
				u.pos.z = nz
			else:
				u.repath_timer = 0.0
			u.pos.y = terrain.get_height(u.pos.x, u.pos.z)
			u.sprite.position = u.pos + Vector3(0, u.y_offset, 0)
			if u.turret_sprite != null:
				u.turret_sprite.position = u.sprite.position + Vector3(0, 0.04, 0.05)
				if u.target == null:
					u.turret_sprite.frame = u.sprite.frame
			if u.sel_ring != null:
				u.sel_ring.position = Vector3(u.pos.x, u.pos.y + 0.12, u.pos.z)

func _update_units(dt: float) -> void:
	_rebuild_spatial_grid()
	var dead_indices: Array[int] = []
	var total := units.size()
	var pair := _get_opposing_spawns()
	var left_spawn := pair[0]
	var right_spawn := pair[1]

	for i in range(total):
		var u := units[i]
		if u.hp <= 0.0:
			dead_indices.append(i)
			continue

		if u.invuln_timer > 0.0:
			u.invuln_timer = maxf(0.0, u.invuln_timer - dt)
			u.sprite.modulate = Color(1.0, 0.35, 0.25) if u.invuln_timer > 0.0 else Color.WHITE
			if u.turret_sprite != null:
				u.turret_sprite.modulate = u.sprite.modulate

		if u.kind == "heavy" and u.hp < u.max_hp * 0.5:
			u.hp = minf(u.max_hp * 0.5, u.hp + 3.5 * dt)

		if u.is_vehicle and u.hp < u.max_hp * 0.45:
			u.smoke_timer -= dt
			if u.smoke_timer <= 0.0:
				u.smoke_timer = rng.randf_range(0.65, 1.15)
				_spawn_explosion(u.pos + Vector3(0, 0.25, 0), "smoke")

		u.cooldown -= dt
		u.repath_timer -= dt

		if u.hp_bar_bg != null and u.hp_bar_fill != null:
			var show_hp := u.selected or (u.hp < u.max_hp)
			u.hp_bar_bg.visible = show_hp and u.sprite.visible
			u.hp_bar_fill.visible = show_hp and u.sprite.visible
			if show_hp:
				var hp_pos := u.sprite.position + Vector3(0, u.y_offset + 0.28, 0)
				u.hp_bar_bg.position = hp_pos
				var ratio := clampf(u.hp / maxf(1.0, u.max_hp), 0.0, 1.0)
				var bw := 1.4 if u.is_building else (0.95 if u.is_vehicle else 0.55)
				u.hp_bar_fill.scale = Vector3(maxf(0.02, bw * ratio), 1.0, 1.0)
				u.hp_bar_fill.position = hp_pos + Vector3((ratio - 1.0) * bw * 0.48, 0.0, 0.01)
				u.hp_bar_fill.material_override = hp_green_mat if ratio > 0.5 else (hp_yellow_mat if ratio > 0.25 else hp_red_mat)

		if u.is_building:
			if u.repairing and u.team == 0:
				if u.hp >= u.max_hp:
					u.repairing = false
				elif blue_cash >= 2:
					u.hp = minf(u.max_hp, u.hp + 38.0 * dt)
					if rng.randf() < dt * 8.0:
						blue_cash = maxi(0, blue_cash - 2)
			if u.attack_range > 0.0:
				var powered := (power_produced[u.team] >= power_consumed[u.team]) or u.power_delta >= 0
				if u.kind == "tsla" and not powered:
					continue
				if u.target == null or u.target.hp <= 0.0 or u.pos.distance_squared_to(u.target.pos) > pow(u.attack_range, 2.0):
					u.target = _find_best_enemy(u)
				if u.target != null and u.pos.distance_to(u.target.pos) <= u.attack_range:
					if u.cooldown <= 0.0:
						u.cooldown = u.fire_rate
						_fire_projectile(u, u.target)
			continue

		if u.kind == "harv":
			_update_harvester(u, dt)
			continue

		if u.kind == "mcv":
			if u.has_move_order:
				_move_ground_unit(u, u.move_goal, dt)
				if Vector2(u.pos.x - u.move_goal.x, u.pos.z - u.move_goal.z).length() < 1.0:
					u.has_move_order = false
			continue

		if u.kind == "engineer":
			if u.forced_target != null and u.forced_target.hp > 0.0 and u.forced_target.is_building:
				if Vector2(u.pos.x - u.forced_target.pos.x, u.pos.z - u.forced_target.pos.z).length() <= 2.4:
					var b := u.forced_target
					if b.team != u.team:
						b.team = u.team
						var btex := "%d_%s" % [u.team, b.kind]
						if textures.has(btex):
							b.sprite.texture = textures[btex]
						_recalc_power()
						_play_voice("strucap1")
					else:
						b.hp = minf(b.max_hp, b.hp + 600.0)
					u.sold = true
					u.hp = 0.0
				else:
					_move_ground_unit(u, u.forced_target.pos, dt)
			elif u.has_move_order:
				_move_ground_unit(u, u.move_goal, dt)
				if Vector2(u.pos.x - u.move_goal.x, u.pos.z - u.move_goal.z).length() < 1.0:
					u.has_move_order = false
			continue

		# Target acquisition
		if u.forced_target != null and u.forced_target.hp > 0.0:
			u.target = u.forced_target
		elif game_mode != GameMode.AUTOBATTLE and u.team == 0 and u.has_move_order and not u.attack_move:
			u.target = null
		elif u.target == null or u.target.hp <= 0.0 or u.pos.distance_squared_to(u.target.pos) > pow(maxf(u.attack_range, u.aa_range) * 1.45, 2.0):
			u.target = _find_best_enemy(u)

		var enemy_base := right_spawn if u.team == 0 else left_spawn
		var my_base := left_spawn if u.team == 0 else right_spawn
		var goal_pos := u.pos
		var should_march := false

		if game_mode == GameMode.AUTOBATTLE or u.team == 1:
			goal_pos = Vector3(enemy_base.x, 0.0, enemy_base.y)
			should_march = true
			if u.squad != null and u.squad.state == SquadState.GATHER and u.target == null:
				goal_pos = u.squad.rally_pos
			elif u.squad != null and u.squad.state == SquadState.PROTECT:
				var defend_target := _find_best_enemy_near(u, Vector3(my_base.x, 0.0, my_base.y), 20.0)
				if defend_target != null:
					u.target = defend_target
				else:
					goal_pos = Vector3(my_base.x, 0.0, my_base.y)
		elif u.has_move_order:
			goal_pos = u.move_goal
			should_march = true
			if Vector2(u.pos.x - goal_pos.x, u.pos.z - goal_pos.z).length() < 1.0:
				u.has_move_order = false
				u.attack_move = false
				should_march = false

		var attacking := false
		var kiting := false
		if u.target != null:
			var to_enemy := u.target.pos - u.pos
			to_enemy.y = 0.0
			var dist := to_enemy.length()
			var eff_range := u.aa_range if (u.target.is_air and u.aa_range > 0.0) else u.attack_range
			if u.min_range > 0.0 and dist < u.min_range and dist > 0.1:
				kiting = true
				goal_pos = u.pos - to_enemy.normalized() * 6.0
				should_march = true
			elif dist <= eff_range:
				attacking = true
				if u.turret_sprite != null:
					var tangle := atan2(-to_enemy.x, -to_enemy.z)
					u.turret_sprite.frame = int(round(fposmod(tangle / TAU, 1.0) * 32.0)) % 32
				else:
					_set_unit_facing(u, to_enemy.x, to_enemy.z)
				if u.cooldown <= 0.0:
					u.cooldown = u.fire_rate * rng.randf_range(0.9, 1.1)
					_fire_projectile(u, u.target)
			elif game_mode == GameMode.AUTOBATTLE or u.team == 1 or u.forced_target != null or u.attack_move:
				goal_pos = u.target.pos
				should_march = true

		if u.is_air:
			u.anim_timer += dt
			if u.kind == "plane":
				u.pass_timer = maxf(0.0, u.pass_timer - dt)
				var desired := (goal_pos - u.pos)
				desired.y = 0.0
				if u.pass_timer <= 0.0 and desired.length_squared() > 1.0 and should_march:
					var target_dir := desired.normalized()
					u.air_heading = u.air_heading.lerp(target_dir, minf(1.0, dt * 2.2)).normalized()
				if attacking and u.pass_timer <= 0.0:
					u.pass_timer = 1.65
				if should_march or attacking:
					_set_unit_facing(u, u.air_heading.x, u.air_heading.z)
					u.pos.x = clampf(u.pos.x + u.air_heading.x * u.speed * dt, -terrain.world_width * 0.49, terrain.world_width * 0.49)
					u.pos.z = clampf(u.pos.z + u.air_heading.z * u.speed * dt, -terrain.world_depth * 0.49, terrain.world_depth * 0.49)
			elif not attacking and should_march:
				var to_goal := Vector3(goal_pos.x - u.pos.x, 0.0, goal_pos.z - u.pos.z)
				if to_goal.length_squared() > 0.25:
					var hdir := to_goal.normalized()
					_set_unit_facing(u, hdir.x, hdir.z)
					u.pos.x = clampf(u.pos.x + hdir.x * u.speed * dt, -terrain.world_width * 0.48, terrain.world_width * 0.48)
					u.pos.z = clampf(u.pos.z + hdir.z * u.speed * dt, -terrain.world_depth * 0.48, terrain.world_depth * 0.48)

			var gy_air := terrain.get_height(u.pos.x, u.pos.z)
			u.pos.y = gy_air + u.altitude
			u.sprite.position = u.pos + Vector3(0, u.y_offset, 0)
			if u.sel_ring != null:
				u.sel_ring.position = Vector3(u.pos.x, gy_air + 0.12, u.pos.z)
			if u.shadow_sprite != null:
				u.shadow_sprite.frame = u.sprite.frame
				u.shadow_sprite.position = Vector3(u.pos.x + 0.35, gy_air + 0.09, u.pos.z + 0.35)
			if u.rotor_sprite != null:
				u.rotor_sprite.frame = int(u.anim_timer * 25.0) % 4
				var hub_y := 0.08 if u.team == 0 else 0.0
				u.rotor_sprite.position = u.sprite.position + Vector3(0, hub_y, 0.08)
		elif not attacking and should_march:
			if kiting:
				var away := Vector3(goal_pos.x - u.pos.x, 0.0, goal_pos.z - u.pos.z)
				if away.length_squared() > 0.01:
					var step_dir := away.normalized()
					u.anim_timer += dt
					_set_unit_facing(u, step_dir.x, step_dir.z, true)
					var nx := clampf(u.pos.x + step_dir.x * u.speed * dt, -terrain.world_width * 0.48, terrain.world_width * 0.48)
					var nz := clampf(u.pos.z + step_dir.z * u.speed * dt, -terrain.world_depth * 0.48, terrain.world_depth * 0.48)
					if terrain.is_walkable_cell(terrain.world_to_grid(nx, nz)):
						u.pos.x = nx; u.pos.z = nz
					u.pos.y = terrain.get_height(u.pos.x, u.pos.z)
					u.sprite.position = u.pos + Vector3(0, u.y_offset, 0)
					if u.sel_ring != null:
						u.sel_ring.position = Vector3(u.pos.x, u.pos.y + 0.12, u.pos.z)
			else:
				_move_ground_unit(u, goal_pos, dt)

	for idx in range(dead_indices.size() - 1, -1, -1):
		var di := dead_indices[idx]
		var du := units[di]
		if du.is_building:
			terrain.set_footprint_solid(du.pos, du.w_tiles, du.h_tiles, false)
		du.sprite.queue_free()
		if du.shadow_sprite != null:
			du.shadow_sprite.queue_free()
		if du.rotor_sprite != null:
			du.rotor_sprite.queue_free()
		if du.turret_sprite != null:
			du.turret_sprite.queue_free()
		if du.sel_ring != null:
			du.sel_ring.queue_free()
		if du.hp_bar_bg != null:
			du.hp_bar_bg.queue_free()
		if du.hp_bar_fill != null:
			du.hp_bar_fill.queue_free()
		if du.sold:
			units.remove_at(di)
			continue
		if du.is_base:
			_spawn_explosion(du.pos, "fball")
			_play_sfx("kaboom22", -4.0, du.pos)
			if game_mode == GameMode.AUTOBATTLE:
				winner_team = 1 if du.team == 0 else 0
				restart_timer = 4.0
		elif du.is_building:
			_spawn_explosion(du.pos, "fball")
			_spawn_ground_decal(du.pos, true)
			_play_sfx("kaboom22", -6.0, du.pos)
		else:
			if du.is_vehicle:
				_spawn_explosion(du.pos, "fball")
				if not du.is_air:
					_spawn_ground_decal(du.pos, true)
					_spawn_husk(du)
				_play_sfx("kaboom15" if rng.randf() < 0.5 else "kaboom1", -7.0, du.pos)
			else:
				_spawn_die_anim(du)
				_play_sfx("dedman%d" % rng.randi_range(1, 3), -12.0, du.pos)
			if du.team == 0:
				blue_count -= 1
				if game_mode == GameMode.AUTOBATTLE:
					red_cash += 14
			else:
				red_count -= 1
				if game_mode == GameMode.AUTOBATTLE:
					blue_cash += 14
		units.remove_at(di)
	if not dead_indices.is_empty():
		_recalc_power()

func _can_target_unit(u: UnitData, other: UnitData) -> bool:
	if u.aa_only and not other.is_air:
		return false
	if not other.is_air:
		return true
	return u.kind == "rocket" or u.kind == "heavy" or u.kind == "sam" or (u.kind == "heli" and u.team == 0)

func _score_target(u: UnitData, other: UnitData) -> float:
	var dist := u.pos.distance_to(other.pos)
	var vs_map: Dictionary = VERSUS_TABLE.get(u.weapon_kind, {})
	var vs := float(vs_map.get(other.armor_type, 1.0))
	var wounded_bonus := 1.15 if other.hp < other.max_hp * 0.4 else 1.0
	return (vs * wounded_bonus) / (dist + 3.0)

func _find_best_enemy(u: UnitData) -> UnitData:
	var scan_r := maxf(maxf(u.attack_range, u.aa_range) * 1.6, 28.0) if (game_mode == GameMode.AUTOBATTLE or u.team == 1) else maxf(u.attack_range, u.aa_range) * 1.25
	var candidates := _query_nearby_units(u.pos, scan_r)
	var best: UnitData = null
	var best_score := -1.0
	for other in candidates:
		if other.team == u.team or other.hp <= 0.0 or not _can_target_unit(u, other):
			continue
		if game_mode != GameMode.AUTOBATTLE and u.team == 0 and u.pos.distance_to(other.pos) > scan_r:
			continue
		var sc := _score_target(u, other)
		if sc > best_score:
			best_score = sc
			best = other
	if best != null or (game_mode != GameMode.AUTOBATTLE and u.team == 0):
		return best

	for other in units:
		if other.team == u.team or other.hp <= 0.0 or not _can_target_unit(u, other):
			continue
		var sc := _score_target(u, other)
		if sc > best_score:
			best_score = sc
			best = other
	return best

func _find_best_enemy_near(u: UnitData, center: Vector3, radius: float) -> UnitData:
	var candidates := _query_nearby_units(center, radius)
	var r2 := radius * radius
	var best: UnitData = null
	var best_score := -1.0
	for other in candidates:
		if other.team == u.team or other.hp <= 0.0 or not _can_target_unit(u, other):
			continue
		if center.distance_squared_to(other.pos) > r2:
			continue
		var sc := _score_target(u, other)
		if sc > best_score:
			best_score = sc
			best = other
	return best

func _fire_projectile(attacker: UnitData, target: UnitData) -> void:
	if attacker.kind == "tsla":
		var from_p := attacker.pos + Vector3(0, attacker.y_offset + 0.65, 0)
		var to_p := target.pos + Vector3(0, target.y_offset * 0.6, 0)
		_spawn_tesla_arc(from_p, to_p)
		var vs_map: Dictionary = VERSUS_TABLE.get("tesla", {})
		var mult := float(vs_map.get(target.armor_type, 1.0))
		if target.invuln_timer <= 0.0:
			target.hp -= attacker.damage * mult
		if target.team == 0 and target.is_building and base_attack_cooldown <= 0.0:
			_play_voice("baseatk1")
			base_attack_cooldown = 14.0
		_spawn_explosion(to_p, "vehhit")
		_play_sfx("tesla1", -6.0, attacker.pos)
		return

	var p: ProjectileData = null
	for cand in proj_pool:
		if not cand.active:
			p = cand
			break
	if p == null:
		return

	p.active = true
	p.team = attacker.team
	p.damage = attacker.damage
	var use_tusk := (attacker.kind == "heavy" and (target.is_air or target.armor_type == "None"))
	p.weapon_kind = "missile" if use_tusk else attacker.weapon_kind
	p.pos = attacker.pos + Vector3(0, attacker.y_offset + 0.35, 0)
	p.target_pos = target.pos + Vector3(0, target.y_offset * 0.6, 0)
	p.is_arc = (attacker.kind == "artillery")
	p.splash = 4.2 if attacker.kind == "artillery" else (2.4 if attacker.kind == "heavy" and not use_tusk else 0.0)

	if p.weapon_kind == "bullet":
		p.kind = "bullet"
	elif p.weapon_kind == "missile":
		p.kind = "missile"
	else:
		p.kind = "shell"

	var to_t := p.target_pos - p.pos
	var dist := maxf(1.0, to_t.length())
	if p.is_arc:
		var flight_time := clampf(dist / 18.0, 0.6, 1.8)
		p.vel = Vector3(to_t.x / flight_time, (to_t.y + 0.5 * 22.0 * flight_time * flight_time) / flight_time, to_t.z / flight_time)
		p.life = flight_time + 0.25
	else:
		var spd := 48.0 if attacker.kind == "tsla" else (38.0 if attacker.kind == "infantry" else 28.0)
		p.vel = to_t.normalized() * spd
		p.life = dist / spd + 0.15

	if proj_textures.has(p.kind):
		p.sprite.texture = proj_textures[p.kind]
		if p.kind == "missile":
			p.sprite.hframes = 32
			var angle := atan2(-p.vel.x, -p.vel.z)
			p.sprite.frame = int(round(fposmod(angle / TAU, 1.0) * 32.0)) % 32
		else:
			p.sprite.hframes = 1
			p.sprite.frame = 0
		p.sprite.position = p.pos
		p.sprite.visible = true

	match attacker.kind:
		"infantry", "pbox":
			_play_sfx("gun13", -13.0, attacker.pos)
		"rocket", "sam":
			_play_sfx("missile6", -11.0, attacker.pos)
		"tank", "gun":
			_play_sfx("cannon1", -9.0, attacker.pos)
		"heavy":
			_play_sfx("missile6" if use_tusk else "cannon2", -8.0, attacker.pos)
		"artillery":
			_play_sfx("missile1" if attacker.team == 1 else "turret1", -8.0, attacker.pos)
		"tsla":
			_play_sfx("turret1", -6.0, attacker.pos)
		"heli", "plane":
			_play_sfx("missile6" if attacker.weapon_kind == "missile" else "gun13", -10.0, attacker.pos)

func _update_projectiles(dt: float) -> void:
	for p in proj_pool:
		if not p.active:
			continue
		p.life -= dt
		if p.is_arc:
			p.vel.y -= 22.0 * dt
		p.pos += p.vel * dt

		var ground_y := terrain.get_height(p.pos.x, p.pos.z)
		if p.life <= 0.0 or p.pos.y <= ground_y + 0.15:
			_detonate_projectile(p)
			p.active = false
			p.sprite.visible = false
			continue

		p.sprite.position = p.pos

func _detonate_projectile(p: ProjectileData) -> void:
	var hit_rad := maxf(2.2, p.splash)
	var hit_rad2 := hit_rad * hit_rad
	var vs_map: Dictionary = VERSUS_TABLE.get(p.weapon_kind, {})
	for u in units:
		if u.team == p.team or u.hp <= 0.0:
			continue
		var d2 := u.pos.distance_squared_to(p.pos)
		if d2 <= hit_rad2:
			if u.invuln_timer <= 0.0:
				var mult := float(vs_map.get(u.armor_type, 1.0))
				u.hp -= p.damage * mult
			if u.team == 0 and u.is_building and base_attack_cooldown <= 0.0:
				_play_voice("baseatk1")
				base_attack_cooldown = 14.0
			if p.splash <= 0.0:
				break

	if p.splash > 0.0:
		_spawn_explosion(p.pos, "frag")
		_spawn_ground_decal(p.pos, true)
		_play_sfx("kaboom1", -10.0, p.pos)
	elif p.damage >= 20.0:
		_spawn_explosion(p.pos, "vehhit")
		if rng.randf() < 0.75:
			_spawn_ground_decal(p.pos, true)
	else:
		_spawn_explosion(p.pos, "piff")
