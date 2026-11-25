class_name Terrain3D
extends Node3D

var world_width: float = 58.0
var world_depth: float = 58.0
var border_margin: float = 1.0 # 1-tile hidden buffer around playable Bounds
var playable_half_w: float = 28.0
var playable_half_d: float = 28.0
var grid_x: int = 58
var grid_z: int = 58

var diffuse_texture: ImageTexture
var height_grid: PackedFloat32Array = PackedFloat32Array()
var walkable_grid: PackedByteArray = PackedByteArray()
var astar: AStarGrid2D
var spawn_positions: Array[Vector2] = []
var resource_cells: Dictionary = {} # Vector2i -> int (1=Gold, 2=Gem)
var current_map_id: String = "crossfire"
var mesh_instance: MeshInstance3D

func _ready() -> void:
	_load_ra_map()
	_build_astar()
	_build_terrain_mesh()
	_build_bounds_mask()

func reload_map(map_id: String) -> void:
	if map_id == current_map_id and mesh_instance != null:
		return
	current_map_id = map_id
	for c in get_children():
		c.queue_free()
	mesh_instance = null
	spawn_positions.clear()
	resource_cells.clear()
	_load_ra_map()
	_build_astar()
	_build_terrain_mesh()
	_build_bounds_mask()

func _load_ra_map() -> void:
	var base_dir := ProjectSettings.globalize_path("res://assets/ra_maps/" + current_map_id)
	if not DirAccess.dir_exists_absolute(base_dir):
		base_dir = ProjectSettings.globalize_path("res://assets/ra_map")
	var meta_path := base_dir.path_join("ra_map_meta.json")
	var diff_path := base_dir.path_join("ra_map_diffuse.png")
	var height_path := base_dir.path_join("ra_map_height.png")

	var diff_img := Image.new()
	diff_img.load(diff_path)
	diffuse_texture = ImageTexture.create_from_image(diff_img)

	var h_img := Image.new()
	h_img.load(height_path)
	grid_x = h_img.get_width()
	grid_z = h_img.get_height()
	world_width = float(grid_x)
	world_depth = float(grid_z)
	playable_half_w = maxf(4.0, world_width * 0.5 - border_margin)
	playable_half_d = maxf(4.0, world_depth * 0.5 - border_margin)

	var raw := PackedFloat32Array()
	raw.resize(grid_x * grid_z)
	for z in range(grid_z):
		for x in range(grid_x):
			var v := h_img.get_pixel(x, z).r
			var h := 0.0
			if v < 0.25:
				h = -1.45 # Water / River
			elif v > 0.80:
				h = 3.10 # Cliff / Rock
			elif v > 0.56:
				h = 0.55 # Rough
			elif v < 0.42:
				h = -0.35 # Beach
			raw[z * grid_x + x] = h

	height_grid.resize(grid_x * grid_z)
	for z in range(grid_z):
		for x in range(grid_x):
			var sum := 0.0
			var wsum := 0.0
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx := clampi(x + dx, 0, grid_x - 1)
					var nz := clampi(z + dz, 0, grid_z - 1)
					var w := 2.0 if (dx == 0 and dz == 0) else 1.0
					sum += raw[nz * grid_x + nx] * w
					wsum += w
			height_grid[z * grid_x + x] = sum / wsum

	var meta_text := FileAccess.get_file_as_string(meta_path)
	var meta: Dictionary = JSON.parse_string(meta_text)

	walkable_grid.resize(grid_x * grid_z)
	walkable_grid.fill(1)
	if meta.has("walkable"):
		var w_arr: Array = meta["walkable"]
		for i in range(mini(w_arr.size(), walkable_grid.size())):
			walkable_grid[i] = int(w_arr[i])

	if meta.has("spawns"):
		for s in meta["spawns"]:
			var wx := float(s["x"]) - world_width * 0.5 + 0.5
			var wz := float(s["y"]) - world_depth * 0.5 + 0.5
			spawn_positions.append(Vector2(wx, wz))

	if meta.has("props"):
		_spawn_ra_props(meta["props"])

	if meta.has("resources"):
		for r in meta["resources"]:
			resource_cells[Vector2i(int(r["x"]), int(r["y"]))] = int(r["type"])

func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, grid_x, grid_z)
	astar.cell_size = Vector2(1.0, 1.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for z in range(grid_z):
		for x in range(grid_x):
			if walkable_grid[z * grid_x + x] == 0:
				astar.set_point_solid(Vector2i(x, z), true)

func world_to_grid(x: float, z: float) -> Vector2i:
	var gx := clampi(int(floor(x + world_width * 0.5)), 0, grid_x - 1)
	var gz := clampi(int(floor(z + world_depth * 0.5)), 0, grid_z - 1)
	return Vector2i(gx, gz)

func grid_to_world(g: Vector2i) -> Vector2:
	return Vector2(float(g.x) - world_width * 0.5 + 0.5, float(g.y) - world_depth * 0.5 + 0.5)

func is_walkable_cell(g: Vector2i) -> bool:
	if g.x < 0 or g.y < 0 or g.x >= grid_x or g.y >= grid_z:
		return false
	return walkable_grid[g.y * grid_x + g.x] == 1

func is_footprint_buildable(world_pos: Vector3, w_tiles: int, h_tiles: int) -> bool:
	var c := world_to_grid(world_pos.x, world_pos.z)
	var half_w := w_tiles / 2
	var half_h := h_tiles / 2
	for dz in range(-half_h, h_tiles - half_h):
		for dx in range(-half_w, w_tiles - half_w):
			var g := Vector2i(c.x + dx, c.y + dz)
			if not is_walkable_cell(g):
				return false
			if resource_cells.has(g):
				return false
	return true

func set_footprint_solid(world_pos: Vector3, w_tiles: int, h_tiles: int, solid: bool) -> void:
	var c := world_to_grid(world_pos.x, world_pos.z)
	var half_w := w_tiles / 2
	var half_h := h_tiles / 2
	for dz in range(-half_h, h_tiles - half_h):
		for dx in range(-half_w, w_tiles - half_w):
			var g := Vector2i(c.x + dx, c.y + dz)
			if g.x >= 0 and g.y >= 0 and g.x < grid_x and g.y < grid_z:
				walkable_grid[g.y * grid_x + g.x] = 0 if solid else 1
				astar.set_point_solid(g, solid)

func find_nearest_resource(world_pos: Vector3) -> Vector2:
	if resource_cells.is_empty():
		return Vector2.ZERO
	var c := world_to_grid(world_pos.x, world_pos.z)
	var best_g := Vector2i(-1, -1)
	var best_d2 := 9999999
	for g: Vector2i in resource_cells.keys():
		var dx := g.x - c.x
		var dz := g.y - c.y
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_g = g
	if best_g.x >= 0:
		return grid_to_world(best_g)
	return Vector2.ZERO

func find_nearest_walkable(target: Vector2i) -> Vector2i:
	if is_walkable_cell(target):
		return target
	for r in range(1, 10):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2i(target.x + dx, target.y + dz)
				if is_walkable_cell(c):
					return c
	return target

func find_path_world(from_pos: Vector3, to_pos: Vector3) -> PackedVector2Array:
	var s := find_nearest_walkable(world_to_grid(from_pos.x, from_pos.z))
	var e := find_nearest_walkable(world_to_grid(to_pos.x, to_pos.z))
	var pts := astar.get_id_path(s, e)
	var out := PackedVector2Array()
	for i in range(1, pts.size()):
		out.append(grid_to_world(pts[i]))
	return out

func get_height(x: float, z: float) -> float:
	if height_grid.is_empty():
		return 0.0
	var fx := clampf(x + world_width * 0.5, 0.0, float(grid_x - 1) - 0.001)
	var fz := clampf(z + world_depth * 0.5, 0.0, float(grid_z - 1) - 0.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var x1 := mini(x0 + 1, grid_x - 1)
	var z1 := mini(z0 + 1, grid_z - 1)
	var tx := fx - float(x0)
	var tz := fz - float(z0)

	var h00 := height_grid[z0 * grid_x + x0]
	var h10 := height_grid[z0 * grid_x + x1]
	var h01 := height_grid[z1 * grid_x + x0]
	var h11 := height_grid[z1 * grid_x + x1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func _build_terrain_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_w := world_width * 0.5
	var half_d := world_depth * 0.5

	for iz in range(grid_z - 1):
		for ix in range(grid_x - 1):
			var x0 := -half_w + float(ix)
			var x1 := x0 + 1.0
			var z0 := -half_d + float(iz)
			var z1 := z0 + 1.0

			var v00 := Vector3(x0, height_grid[iz * grid_x + ix], z0)
			var v10 := Vector3(x1, height_grid[iz * grid_x + ix + 1], z0)
			var v01 := Vector3(x0, height_grid[(iz + 1) * grid_x + ix], z1)
			var v11 := Vector3(x1, height_grid[(iz + 1) * grid_x + ix + 1], z1)

			var uv00 := Vector2(float(ix) / float(grid_x), float(iz) / float(grid_z))
			var uv10 := Vector2(float(ix + 1) / float(grid_x), float(iz) / float(grid_z))
			var uv01 := Vector2(float(ix) / float(grid_x), float(iz + 1) / float(grid_z))
			var uv11 := Vector2(float(ix + 1) / float(grid_x), float(iz + 1) / float(grid_z))

			st.set_uv(uv00); st.add_vertex(v00)
			st.set_uv(uv10); st.add_vertex(v10)
			st.set_uv(uv11); st.add_vertex(v11)

			st.set_uv(uv00); st.add_vertex(v00)
			st.set_uv(uv11); st.add_vertex(v11)
			st.set_uv(uv01); st.add_vertex(v01)

	st.generate_normals()
	var mesh := st.commit()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = diffuse_texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.92
	mat.metallic = 0.0
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)

func _build_water_plane() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(world_width, world_depth)
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.position = Vector3(0.0, -0.58, 0.0)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.10, 0.28, 0.48, 0.72)
	mat.roughness = 0.14
	mat.metallic = 0.35
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

func _build_bounds_mask() -> void:
	# Godot 3D equivalent of OpenRA's EnableScissor(Bounds):
	# 4 unshaded pure-black masks occluding the 1-tile outer buffer and anything outside playable Bounds.
	var mask_mat := StandardMaterial3D.new()
	mask_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask_mat.albedo_color = Color.BLACK

	var pad := 220.0
	var mask_y := 12.0
	var hw := playable_half_w
	var hd := playable_half_d

	var rects := [
		[Vector3(0.0, mask_y, -hd - pad * 0.5), Vector2((hw + pad) * 2.0, pad)],
		[Vector3(0.0, mask_y,  hd + pad * 0.5), Vector2((hw + pad) * 2.0, pad)],
		[Vector3(-hw - pad * 0.5, mask_y, 0.0), Vector2(pad, hd * 2.0)],
		[Vector3( hw + pad * 0.5, mask_y, 0.0), Vector2(pad, hd * 2.0)],
	]

	for r in rects:
		var pm := PlaneMesh.new()
		pm.size = r[1]
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.position = r[0]
		mi.material_override = mask_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func _spawn_ra_props(props: Array) -> void:
	var sprite_dir := ProjectSettings.globalize_path("res://assets/ra_sprites")
	var cache: Dictionary = {}
	var half_w := world_width * 0.5
	var half_d := world_depth * 0.5

	for p in props:
		var p_type: String = str(p.get("type", "t01"))
		if not cache.has(p_type):
			var img_path := sprite_dir.path_join("prop_%s.png" % p_type)
			if not FileAccess.file_exists(img_path):
				continue
			var img := Image.new()
			img.load(img_path)
			cache[p_type] = ImageTexture.create_from_image(img)

		var tex: ImageTexture = cache[p_type]
		var fw := float(p.get("w", 1))
		var fd := float(p.get("h", 1))
		var tx := float(p["x"]) - half_w + fw * 0.5
		var tz := float(p["y"]) - half_d + fd * 0.5
		var ty := get_height(tx, tz)
		if ty < -0.5:
			continue

		var sp := Sprite3D.new()
		sp.texture = tex
		sp.pixel_size = 1.0 / 24.0 # Exact OpenRA scale: 24px = 1 tile
		sp.centered = true
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.shaded = true
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var h_world := tex.get_height() * sp.pixel_size * 0.46
		sp.position = Vector3(tx, ty + h_world, tz)
		add_child(sp)
