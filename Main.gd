extends Node3D
## FLAPPY JONK
## A flappy-bird game rendered with real 3D (lights, shadows, bloom) but played
## flat/2D via an orthographic camera. Tap SPACE or click to flap Jonk's head,
## dodge the pipes, and catch beer cans for bonus points.

# ---------------------------------------------------------------------------
# FRIEND CONFIG — Jonk as his LEGO BrickHeadz figure: bald tan head brick
# with studs, big square black glasses, stepped brown beard, red dev shirt
# ("HTML & CSS & JavaScript & WordPress"). Beard matches the LEGO photo's
# brown; real-Jonk gray is Color(0.34, 0.33, 0.32) if preferred.
# ---------------------------------------------------------------------------
const FRIEND := {
	"name": "JONK",
	"skin": Color(0.88, 0.73, 0.55),
	"beard_color": Color(0.45, 0.25, 0.13),
}

# ---------------------------------------------------------------------------
# TUNABLES
# ---------------------------------------------------------------------------
const HEAD_X := -2.5
const GRAVITY := 22.0
const FLAP_VELOCITY := 8.6
const MAX_FALL := -16.0
const HEAD_RADIUS := 0.6          # collision radius (a touch forgiving)

const CAM_SIZE := 16.0
const FLOOR_Y := -6.6
const CEIL_Y := 7.2

const PIPE_RADIUS := 0.9
const PIPE_GAP := 5.0
const PIPE_SPACING := 6.5
const SPAWN_X := 20.0     # far enough out that pipes never pop in on wide fullscreen
const DESPAWN_X := -20.0
const GAP_MIN := -2.2
const GAP_MAX := 3.4

const BASE_SPEED := 5.5
const SPEED_PER_POINT := 0.16
const MAX_SPEED := 10.5

const BEER_POINTS := 3
const BEER_PICKUP_RADIUS := 1.15
const BEER_CHANCE := 0.55         # chance a pipe gap also holds a beer can

const SAVE_PATH := "user://highscores.json"
const MAX_SCORES := 10

# difficulty select on the retro title card (NES style): gap size, base
# scroll speed, ramp per point, speed cap
const DIFF_NAMES := ["EASY", "NORMAL", "DIFFICULT"]
const DIFF_GAP := [6.0, 5.0, 4.15]
const DIFF_BASE_SPEED := [5.0, 5.5, 6.3]
const DIFF_SPEED_PER := [0.12, 0.16, 0.22]
const DIFF_MAX_SPEED := [9.5, 10.5, 11.8]

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------
enum { STATE_MENU, STATE_PLAY, STATE_DEAD }
enum { MENU_SHOW, MENU_CARD }    # menu phase: minifig show → 80s title card

var state := STATE_MENU
var menu_phase := MENU_SHOW
var menu_phase_t := 0.0
var difficulty := 1
var pipe_gap: float = DIFF_GAP[1]
var run_base_speed: float = DIFF_BASE_SPEED[1]
var run_speed_per: float = DIFF_SPEED_PER[1]
var run_max_speed: float = DIFF_MAX_SPEED[1]
var velocity_y := 0.0
var score := 0
var speed := BASE_SPEED
var entering_name := false
var high_scores: Array = []

var head: Node3D
var pipes: Array = []            # { root, x, gap, passed, beer }
var clouds: Array = []
var since_spawn := 0.0

# UI nodes
var ui: CanvasLayer
var title_box: Control
var score_label: Label
var gameover_box: Control
var final_label: Label
var scores_label: Label
var name_row: Control
var name_edit: LineEdit
var hint_label: Label

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------
func _ready() -> void:
	randomize()
	_load_scores()
	_build_environment()
	_build_camera()
	_build_lights()
	_build_clouds()
	_build_ground()
	_build_bayou()
	head = _build_head()
	_build_intro_show()
	_build_retro_card()
	_build_ui()
	_goto_menu()
	# dev screenshot mode: `godot --path . -- --shot <dir>` captures the menu
	# and a moment of gameplay to <dir>, then quits. Used to iterate visually.
	var uargs := OS.get_cmdline_user_args()
	var idx := uargs.find("--shot")
	if idx != -1:
		_shot_dir = uargs[idx + 1] if uargs.size() > idx + 1 else "/tmp"
		_run_shot_sequence()

var _shot_dir := ""

func _run_shot_sequence() -> void:
	await get_tree().create_timer(1.5).timeout
	await _save_shot(_shot_dir + "/shot_menu.png")
	# a couple more menu frames to catch the minifig mid-jump and on a rock
	await get_tree().create_timer(0.45).timeout
	await _save_shot(_shot_dir + "/shot_menu2.png")
	await get_tree().create_timer(0.7).timeout
	await _save_shot(_shot_dir + "/shot_menu3.png")
	# wait out the attract show — the 80s title card cuts in at CARD_AFTER
	await get_tree().create_timer(5.6).timeout
	await _save_shot(_shot_dir + "/shot_card.png")
	_start_game()
	await get_tree().create_timer(3.2).timeout
	await _save_shot(_shot_dir + "/shot_play.png")
	get_tree().quit()

func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	# a real photograph of the Milky Way wrapped around the whole sky
	# (ESO/S. Brunier 360° panorama, CC BY 4.0 — credited in the README)
	var sky_mat := PanoramaSkyMaterial.new()
	var sky_img := Image.load_from_file(ProjectSettings.globalize_path("res://sky_milkyway.jpg"))
	sky_mat.panorama = ImageTexture.create_from_image(sky_img)
	sky_mat.energy_multiplier = 1.4
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.3

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05

	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.4

	# space is a vacuum — no haze
	env.fog_enabled = false
	env.ssr_enabled = true

	# punchy animation-style grade: saturated and crisp
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.3
	env.adjustment_contrast = 1.05

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_ground() -> void:
	# lunar regolith whose surface is the kill floor, plus a distant ridge
	_add(_box(Vector3(90, 4, 10)), _mat(Color(0.32, 0.32, 0.36), 0.9), Vector3(0, FLOOR_Y - 2.0, -2))
	_add(_box(Vector3(90, 0.1, 10)), _mat(Color(0.46, 0.46, 0.51), 0.85), Vector3(0, FLOOR_Y + 0.02, -2))
	_add(_box(Vector3(90, 2.5, 4)), _mat(Color(0.16, 0.16, 0.20), 1.0), Vector3(0, FLOOR_Y - 0.4, -13))
	# craters pocking the surface
	for i in range(8):
		var cr := _add(_cyl(randf_range(0.4, 1.0), 0.07), _mat(Color(0.22, 0.22, 0.26), 0.95), Vector3(randf_range(-16, 16), FLOOR_Y + 0.08, randf_range(-3.5, 0.5)))
		cr.scale.x = randf_range(1.0, 1.6)

var rocket: Node3D
var rocket_flame: Node3D
var astronaut: Node3D

func _build_bayou() -> void:
	# SPACE! Starfield, glowing moon, planets, rockets on the lunar surface,
	# and one little rocket cruising across the sky.
	# NOTE: the camera is orthographic, so distance doesn't shrink things —
	# background props must be modeled small to read as far away.

	# (the starfield is now the real Milky Way panorama on the sky itself)

	# the moon — a real photograph (Gregory H. Revera, CC BY-SA 3.0);
	# its black background lifts away with additive blending
	_photo_quad("res://moon_real.jpg", Vector2(4.6, 4.37), true, Vector3(6.0, 4.5, -16))

	# the real Saturn (Cassini mosaic, NASA/JPL) — black lifts away additively
	var saturn := _photo_quad("res://saturn_real.jpg", Vector2(3.4, 1.74), true, Vector3(-7.5, 6.0, -17))
	saturn.rotation_degrees = Vector3(0, 0, 8)

	# real rockets parked on the surface — a Soyuz, a New Shepard booster,
	# and a Falcon 9, each lifted from real photos. All different, no clones.
	# Sizes keep true-ish relative proportions (photo aspect ratios).
	_photo_quad("res://rocket_soyuz.png", Vector2(0.38, 3.4), false, Vector3(-11.5, FLOOR_Y + 1.7, -12))
	_photo_quad("res://rocket_shepard.png", Vector2(0.9, 2.0), false, Vector3(-2.5, FLOOR_Y + 1.0, -10.5))
	_photo_quad("res://rocket_falcon.png", Vector2(0.4, 2.7), false, Vector3(8.0, FLOOR_Y + 1.35, -13))

	# the flying rocket — a real Falcon 9, lifted out of a Space Force launch
	# photo (public domain), with a glowing exhaust attached
	rocket = Node3D.new()
	rocket.position = Vector3(-16, 4.0, -9)
	rocket.rotation_degrees = Vector3(0, 0, -90)  # nose points +X (flight direction)
	add_child(rocket)
	_photo_quad("res://rocket_real.png", Vector2(0.19, 2.4), false, Vector3.ZERO, rocket)
	var flame_outer := CylinderMesh.new()
	flame_outer.top_radius = 0.13
	flame_outer.bottom_radius = 0.0
	flame_outer.height = 0.8
	rocket_flame = _add(flame_outer, _mat(Color(1.0, 0.55, 0.1), 0.4, 0.0, true, 3.0), Vector3(0, -1.55, 0), rocket)
	var flame_inner := CylinderMesh.new()
	flame_inner.top_radius = 0.07
	flame_inner.bottom_radius = 0.0
	flame_inner.height = 0.5
	_add(flame_inner, _mat(Color(1.0, 0.9, 0.4), 0.3, 0.0, true, 5.0), Vector3(0, -1.42, 0), rocket)

	# Earth — the Blue Marble (Apollo 17, on black → additive)
	_photo_quad("res://earth_real.jpg", Vector2(1.6, 1.6), true, Vector3(-2.5, 6.8, -16))

	# an astronaut on a spacewalk (Bruce McCandless, 1984), drifting slowly
	astronaut = _photo_quad("res://astronaut_real.png", Vector2(1.15, 1.3), false, Vector3(-9.0, 2.5, -7))

func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE
	cam.position = Vector3(0, 0, 22)
	cam.current = true
	add_child(cam)

func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	# hard white sunlight, space-style
	key.rotation_degrees = Vector3(-35, -30, 0)
	key.light_energy = 1.4
	key.light_color = Color(1.0, 0.98, 0.95)
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # no sun disc in the starfield
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	add_child(key)

	# cool blue rim light from behind — classic sci-fi
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 150, 0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.4, 0.6, 1.0)
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # don't paint a 2nd sun on the sky
	add_child(fill)

# ---------------------------------------------------------------------------
# MESH HELPERS
# ---------------------------------------------------------------------------
func _mat(color: Color, rough := 0.6, metal := 0.0, emit := false, emit_e := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit_e
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _sphere(r: float, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 40
	s.rings = 22
	s.is_hemisphere = hemi
	return s

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 32
	return c

func _trapezoid(top_w: float, bot_w: float, h: float, top_d: float, bot_d: float) -> ArrayMesh:
	# a box that tapers toward the top — the real minifig torso shape
	# (2 studs wide at the hips, narrower at the shoulders)
	var t := h / 2.0
	var corners := [
		Vector3(-top_w / 2, t, -top_d / 2), Vector3(top_w / 2, t, -top_d / 2),
		Vector3(top_w / 2, t, top_d / 2), Vector3(-top_w / 2, t, top_d / 2),
		Vector3(-bot_w / 2, -t, -bot_d / 2), Vector3(bot_w / 2, -t, -bot_d / 2),
		Vector3(bot_w / 2, -t, bot_d / 2), Vector3(-bot_w / 2, -t, bot_d / 2),
	]
	var faces := [
		[0, 1, 2, 3], [7, 6, 5, 4],  # top, bottom
		[3, 2, 6, 7], [1, 0, 4, 5],  # front, back
		[0, 3, 7, 4], [2, 1, 5, 6],  # left, right
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = corners[f[0]]
		var b: Vector3 = corners[f[1]]
		var c: Vector3 = corners[f[2]]
		var d: Vector3 = corners[f[3]]
		st.set_normal((d - a).cross(b - a).normalized())
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
	return st.commit()

var _tex_cache := {}

func _photo_quad(res_path: String, size: Vector2, additive := false, pos := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	# a billboard carrying a real photograph; additive blend lifts away a
	# pure-black background (perfect for astro photos). Textures are cached
	# so repeat spawns (obstacles!) don't re-decode the file.
	if not _tex_cache.has(res_path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(res_path))
		_tex_cache[res_path] = ImageTexture.create_from_image(img)
	var tex: ImageTexture = _tex_cache[res_path]
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi

func _add(mesh: Mesh, mat: Material, pos := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi

# ---------------------------------------------------------------------------
# THE HEAD
# ---------------------------------------------------------------------------
func _build_head() -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(HEAD_X, 0, 0)
	add_child(pivot)

	# LEGO BrickHeadz-style Jonk: blocky plastic bricks, matched to the LEGO
	# photo (square black glasses, round tile eyes with a highlight, stepped
	# beard, studs on the bald head). Modeled facing +Z, then turned partway
	# toward the direction of travel — a 3/4 view, so the camera still sees
	# the face (glasses, eyes, beard) the way BrickHeadz are meant to be seen.
	var model := Node3D.new()
	model.rotation_degrees = Vector3(0, 55, 0)
	model.scale = Vector3(0.7, 0.7, 0.7)
	model.position = Vector3(0, 0.5, 0)  # recentre: torso hangs below the pivot
	pivot.add_child(model)

	var skin := _mat(FRIEND.skin, 0.35)
	var black := _mat(Color(0.05, 0.05, 0.06), 0.25)

	# the head brick
	_add(_box(Vector3(1.6, 1.8, 1.6)), skin, Vector3.ZERO, model)
	# studs on top — unmistakably LEGO (pale plates like the photo)
	var stud_mat := _mat(Color(0.93, 0.90, 0.84), 0.35)
	for sx in [-0.4, 0.4]:
		for sz in [-0.4, 0.4]:
			_add(_cyl(0.19, 0.14), stud_mat, Vector3(sx, 0.97, sz), model)

	# eyes: cream tile backing + big round black eye + white highlight stud
	var tile := _mat(Color(0.9, 0.85, 0.74), 0.3)
	for x in [-0.42, 0.42]:
		_add(_box(Vector3(0.62, 0.62, 0.05)), tile, Vector3(x, 0.22, 0.81), model)
		var eye := _add(_cyl(0.26, 0.07), black, Vector3(x, 0.22, 0.85), model)
		eye.rotation_degrees = Vector3(90, 0, 0)
		_add(_box(Vector3(0.11, 0.11, 0.03)), _mat(Color(0.95, 0.95, 0.97), 0.2), Vector3(x - 0.09, 0.3, 0.9), model)

	# nose brick
	_add(_box(Vector3(0.32, 0.34, 0.28)), _mat(FRIEND.skin.darkened(0.06), 0.35), Vector3(0, -0.18, 0.85), model)

	# ear plates sticking out at the sides
	for x in [-0.85, 0.85]:
		_add(_box(Vector3(0.14, 0.42, 0.42)), skin, Vector3(x, 0.05, -0.1), model)

	_build_torso(model)
	_build_beard(model)
	_build_glasses(model)
	return pivot

func _build_torso(model: Node3D) -> void:
	# the red dev shirt from the photo, complete with the classic print
	var red := _mat(Color(0.78, 0.09, 0.1), 0.45)
	var hands := _mat(FRIEND.skin, 0.35)
	_add(_box(Vector3(1.5, 1.15, 1.05)), red, Vector3(0, -1.95, 0), model)
	# arm panels + hands
	for x in [-0.82, 0.82]:
		_add(_box(Vector3(0.16, 0.85, 0.65)), red, Vector3(x, -1.8, 0.05), model)
		_add(_box(Vector3(0.2, 0.28, 0.28)), hands, Vector3(x, -2.32, 0.3), model)
	# shirt print
	var lbl := Label3D.new()
	lbl.text = "HTML &\nCSS &\nJavaScript &\nWordPress"
	lbl.font_size = 44
	lbl.pixel_size = 0.004
	lbl.modulate = Color(1, 1, 1)
	lbl.position = Vector3(0, -1.93, 0.54)
	model.add_child(lbl)

func _build_beard(model: Node3D) -> void:
	# stepped LEGO bricks — dark-and-gray like the real Jonk (the LEGO photo
	# has brown; change FRIEND.beard_color to match it if preferred)
	var m := _mat(FRIEND.beard_color, 0.4)
	var m_dark := _mat(FRIEND.beard_color.darkened(0.3), 0.45)

	# mustache brick under the nose
	_add(_box(Vector3(1.05, 0.24, 0.2)), m_dark, Vector3(0, -0.4, 0.88), model)
	# beard plate over the lower face, with a dark mouth slot
	_add(_box(Vector3(1.2, 0.55, 0.15)), m, Vector3(0, -0.65, 0.84), model)
	_add(_box(Vector3(0.6, 0.14, 0.06)), _mat(Color(0.1, 0.07, 0.06), 0.5), Vector3(0, -0.62, 0.93), model)
	# cheek slabs running up the sides of the face
	for x in [-0.72, 0.72]:
		_add(_box(Vector3(0.22, 0.85, 0.3)), m, Vector3(x, -0.42, 0.72), model)
	# jaw wrap: one brick wider than the head so it reads as its own layer
	_add(_box(Vector3(1.7, 0.6, 1.65)), m, Vector3(0, -1.0, 0.05), model)
	# chin steps
	_add(_box(Vector3(1.25, 0.5, 0.5)), m, Vector3(0, -1.05, 0.75), model)
	_add(_box(Vector3(0.95, 0.4, 0.4)), m_dark, Vector3(0, -1.5, 0.55), model)

func _build_glasses(model: Node3D) -> void:
	# oversized square frames, proud of the face, exactly like the LEGO photo
	var frame := _mat(Color(0.06, 0.06, 0.07), 0.2)
	for x in [-0.44, 0.44]:
		_add(_box(Vector3(0.98, 0.17, 0.17)), frame, Vector3(x, 0.62, 0.96), model)
		_add(_box(Vector3(0.98, 0.17, 0.17)), frame, Vector3(x, -0.18, 0.96), model)
		_add(_box(Vector3(0.17, 0.97, 0.17)), frame, Vector3(x - 0.41, 0.22, 0.96), model)
		_add(_box(Vector3(0.17, 0.97, 0.17)), frame, Vector3(x + 0.41, 0.22, 0.96), model)
	# bridge
	_add(_box(Vector3(0.3, 0.16, 0.16)), frame, Vector3(0, 0.32, 0.96), model)
	# temple arms running back along the head
	for x in [-0.86, 0.86]:
		_add(_box(Vector3(0.14, 0.14, 1.7)), frame, Vector3(x, 0.5, 0.05), model)

# ---------------------------------------------------------------------------
# INTRO SHOW — Jonk as a complete classic LEGO minifigure, hopping between
# dangerous space rocks on the title screen.
#
# Built to the real minifig blueprint (modeled in actual millimeters, then
# scaled): 40 mm tall, head a Ø10.2 mm cylinder with one stud, trapezoid
# torso (15.8 mm at the hips, narrower at the shoulders), arms with the
# molded elbow bend, C-clamp hands whose outer diameter matches a stud on
# 3.18 mm wrist pegs, a separate hip piece, and blocky legs with forward
# feet that only swing at the hip — no knees, just like the real thing.
# ---------------------------------------------------------------------------
const MF_SCALE := 0.065          # mm → world units
const JUMP_DUR := 0.85
const JUMP_ARC := 1.1

var intro_root: Node3D
var minifig: Node3D
var fig_arm_l: Node3D
var fig_arm_r: Node3D
var fig_leg_l: Node3D
var fig_leg_r: Node3D
var intro_rocks: Array = []      # { node, base_y, phase, top }

var _on_rock := 0
var _hop_dir := 1
var _jumping := false
var _jump_t := 0.0
var _jump_from_pos := Vector3.ZERO
var _face_dir := 1.0
var _squash := 0.0

func _build_intro_show() -> void:
	intro_root = Node3D.new()
	add_child(intro_root)
	# a warm little spotlight so the star of the show pops out of the dusk
	var spot := OmniLight3D.new()
	spot.position = Vector3(0, -3.2, 5.0)
	spot.omni_range = 10.0
	spot.light_energy = 1.6
	spot.light_color = Color(1.0, 0.92, 0.8)
	intro_root.add_child(spot)
	# three of the actual in-game obstacles — the nebula dust columns —
	# rising from the lunar surface for Jonk to hop between
	intro_rocks.append(_build_intro_pillar(-3.1, -5.3, 0))
	intro_rocks.append(_build_intro_pillar(-0.05, -4.95, 1))
	intro_rocks.append(_build_intro_pillar(3.0, -5.4, 2))
	minifig = _build_minifig()
	minifig.scale = Vector3.ONE * MF_SCALE
	intro_root.add_child(minifig)
	minifig.position = _stand_pos(0)

func _build_intro_pillar(x: float, tip_y: float, seed_i: int) -> Dictionary:
	# the very same Pillars of Creation photos the game throws at you,
	# scaled down and planted in the regolith (bottoms run offscreen)
	var w := 1.35 + 0.15 * (seed_i % 2)
	var h := w * (13.0 / 2.4)
	var tex := "res://pillar1_real.png" if (seed_i % 2 == 0) else "res://pillar2_real.png"
	var quad := _photo_quad(tex, Vector2(w, h), false, Vector3(x, tip_y - h / 2.0 + 0.55, 1.5), intro_root)
	# the photo has a sliver of transparent air above the tip — plant the feet
	# a touch lower so they actually touch nebula, not vacuum
	return { "node": quad, "base_y": quad.position.y, "phase": seed_i * 2.1, "top": h / 2.0 - 0.95 }

func _stand_pos(i: int) -> Vector3:
	var r: Dictionary = intro_rocks[i]
	return r.node.position + Vector3(0, r.top, 0)

func _build_minifig() -> Node3D:
	# origin at the soles of the feet; everything in real minifig millimeters
	var fig := Node3D.new()

	var skin := _mat(FRIEND.skin, 0.35)
	var red := _mat(Color(0.78, 0.09, 0.1), 0.45)
	var jeans := _mat(Color(0.13, 0.27, 0.52), 0.5)
	var jeans_dark := _mat(Color(0.10, 0.21, 0.42), 0.55)
	var black := _mat(Color(0.05, 0.05, 0.06), 0.25)

	# --- legs: blocky, forward feet, hinge only at the hip ---
	fig_leg_l = _build_leg(fig, -1, jeans)
	fig_leg_r = _build_leg(fig, 1, jeans)

	# --- hip piece: crossbar the legs hang from + center block ---
	_add(_box(Vector3(15.6, 2.8, 5.7)), jeans_dark, Vector3(0, 15.4, 0), fig)
	_add(_box(Vector3(2.0, 3.4, 5.0)), jeans_dark, Vector3(0, 13.4, -0.2), fig)

	# --- torso: the tapered brick with the red dev shirt ---
	var torso_mat := _mat(Color(0.78, 0.09, 0.1), 0.45)
	torso_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(_trapezoid(12.0, 15.5, 10.5, 5.6, 7.4), torso_mat, Vector3(0, 21.95, 0), fig)
	var lbl := Label3D.new()
	lbl.text = "HTML &\nCSS &\nJavaScript &\nWordPress"
	lbl.font_size = 40
	lbl.pixel_size = 0.042
	lbl.position = Vector3(0, 22.0, 3.9)
	fig.add_child(lbl)

	# --- arms with molded elbow bend + C-clamp hands ---
	fig_arm_l = _build_arm(fig, -1, red, skin)
	fig_arm_r = _build_arm(fig, 1, red, skin)

	# --- neck + head: cylinder, one stud, printed-style flat face ---
	_add(_cyl(2.7, 1.8), red, Vector3(0, 28.0, 0), fig)
	_add(_cyl(5.1, 8.5), skin, Vector3(0, 33.15, 0), fig)
	_add(_cyl(2.4, 1.7), skin, Vector3(0, 38.2, 0), fig)  # the stud — bald as ever

	# eyes: flat printed discs with a highlight (no 3D nose — faces are prints!)
	for x in [-1.9, 1.9]:
		var eye := _add(_cyl(0.85, 0.25), black, Vector3(x, 34.3, 4.78), fig)
		eye.rotation_degrees = Vector3(90, 0, 0)
		_add(_box(Vector3(0.35, 0.35, 0.15)), _mat(Color(0.95, 0.95, 0.97), 0.2), Vector3(x - 0.3, 34.55, 4.95), fig)

	# the trademark oversized square glasses, proud of the face
	var frame := _mat(Color(0.06, 0.06, 0.07), 0.2)
	for x in [-2.05, 2.05]:
		_add(_box(Vector3(4.3, 0.75, 0.75)), frame, Vector3(x, 36.05, 5.0), fig)
		_add(_box(Vector3(4.3, 0.75, 0.75)), frame, Vector3(x, 32.55, 5.0), fig)
		_add(_box(Vector3(0.75, 4.25, 0.75)), frame, Vector3(x - 1.8, 34.3, 5.0), fig)
		_add(_box(Vector3(0.75, 4.25, 0.75)), frame, Vector3(x + 1.8, 34.3, 5.0), fig)
	_add(_box(Vector3(1.2, 0.7, 0.7)), frame, Vector3(0, 34.9, 5.05), fig)
	for x in [-4.9, 4.9]:
		_add(_box(Vector3(0.6, 0.6, 7.5)), frame, Vector3(x, 35.2, 1.2), fig)

	# the beard: wraps the chin and hangs below the head like the real piece
	var beard := _mat(FRIEND.beard_color, 0.4)
	var beard_dark := _mat(FRIEND.beard_color.darkened(0.3), 0.45)
	_add(_box(Vector3(5.4, 1.3, 1.0)), beard_dark, Vector3(0, 31.4, 4.95), fig)   # mustache
	_add(_box(Vector3(7.6, 3.8, 1.2)), beard, Vector3(0, 29.0, 4.55), fig)        # chin slab
	_add(_box(Vector3(3.0, 0.9, 0.5)), _mat(Color(0.1, 0.07, 0.06), 0.5), Vector3(0, 29.6, 5.25), fig)  # mouth
	for s in [-1, 1]:
		var cheek := _add(_box(Vector3(1.5, 4.6, 1.3)), beard, Vector3(s * 3.2, 31.2, 4.05), fig)
		cheek.rotation_degrees = Vector3(0, -s * 38, 0)

	return fig

func _build_leg(fig: Node3D, s: int, mat: Material) -> Node3D:
	# pivot sits exactly on the hip crossbar, like the real hinge
	var piv := Node3D.new()
	piv.position = Vector3(s * 4.0, 12.5, 0)
	fig.add_child(piv)
	# rounded thigh top that turns under the crossbar
	var thigh := _add(_cyl(3.7, 7.2), mat, Vector3.ZERO, piv)
	thigh.rotation_degrees = Vector3(0, 0, 90)
	# the leg block, then the foot jutting forward — heel flush with the calf
	_add(_box(Vector3(7.3, 9.3, 5.4)), mat, Vector3(0, -4.7, 0), piv)
	_add(_box(Vector3(7.3, 3.4, 8.6)), mat, Vector3(0, -10.8, 1.6), piv)
	return piv

func _build_arm(fig: Node3D, s: int, sleeve: Material, skin: Material) -> Node3D:
	var piv := Node3D.new()
	piv.position = Vector3(s * 6.4, 25.2, 0)
	fig.add_child(piv)
	_add(_sphere(2.6), sleeve, Vector3(s * 0.4, 0.3, 0), piv)          # shoulder boss
	var upper := _add(_cyl(2.1, 5.4), sleeve, Vector3(s * 0.8, -2.6, 0), piv)
	upper.rotation_degrees = Vector3(0, 0, s * 9)                       # slight outward flare
	# the permanent molded forward bend at the elbow
	var elbow := Node3D.new()
	elbow.position = Vector3(s * 1.3, -5.2, 0.3)
	elbow.rotation_degrees = Vector3(-30, 0, 0)
	piv.add_child(elbow)
	_add(_sphere(2.15), sleeve, Vector3.ZERO, elbow)
	_add(_cyl(1.95, 4.6), sleeve, Vector3(0, -2.0, 0), elbow)
	# the famous 3.18 mm wrist peg, hand-colored like the real part
	_add(_cyl(1.59, 2.2), skin, Vector3(0, -4.9, 0), elbow)
	var hand := _build_hand(FRIEND.skin)
	hand.position = Vector3(0, -6.6, 0)
	elbow.add_child(hand)
	if s == 1:
		# the right C-clamp grips a tiny "the bäär" can, of course
		var can := Node3D.new()
		can.position = Vector3(0, -6.6, 2.4)
		can.rotation_degrees = Vector3(30, 0, 0)   # counter the elbow bend → upright
		elbow.add_child(can)
		_add(_cyl(2.1, 5.4), _mat(Color(0.93, 0.90, 0.83), 0.5, 0.0, true, 0.25), Vector3.ZERO, can)
		_add(_cyl(1.85, 0.7), _mat(Color(0.75, 0.77, 0.80), 0.2, 0.95), Vector3(0, 2.9, 0), can)
		_add(_cyl(2.15, 0.5), _mat(Color(0.75, 0.77, 0.80), 0.2, 0.95), Vector3(0, -2.8, 0), can)
		var blob := _add(_sphere(1.1), _mat(Color(0.96, 0.62, 0.11), 0.55), Vector3(0, -0.4, 1.6), can)
		blob.scale = Vector3(1.25, 1.0, 0.55)
	return piv

func _build_hand(color: Color) -> Node3D:
	# the C-clamp: a ring with a slot, outer Ø the same as a stud — carved
	# with CSG so the opening is a real gap you can see through
	var hand := Node3D.new()
	hand.rotation_degrees = Vector3(0, 0, 90)   # ring axis sideways, opening forward
	var m := _mat(color, 0.35)
	var ring := CSGCylinder3D.new()
	ring.radius = 2.45
	ring.height = 3.2
	ring.sides = 20
	ring.material = m
	hand.add_child(ring)
	var hole := CSGCylinder3D.new()
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	hole.radius = 1.45
	hole.height = 3.6
	hole.sides = 16
	hole.material = m
	ring.add_child(hole)
	var slot := CSGBox3D.new()
	slot.operation = CSGShape3D.OPERATION_SUBTRACTION
	slot.size = Vector3(2.2, 3.6, 2.4)
	slot.position = Vector3(0, 0, 1.6)
	slot.material = m
	ring.add_child(slot)
	return hand

func _animate_intro(delta: float, tsec: float) -> void:
	# the dust columns shimmer ever so slightly, like they do out there
	for r in intro_rocks:
		r.node.position.y = r.base_y + sin(tsec * 0.7 + r.phase) * 0.06

	var air := 0.0
	if _jumping:
		_jump_t += delta / JUMP_DUR
		var t: float = clamp(_jump_t, 0.0, 1.0)
		var p := _jump_from_pos.lerp(_stand_pos(_jump_to), t)
		p.y += sin(t * PI) * JUMP_ARC
		minifig.position = p
		air = sin(t * PI)
		if _jump_t >= 1.0:
			_jumping = false
			_on_rock = _jump_to
			_on_rock_timer = 0.0
			_squash = 1.0
	else:
		_on_rock_timer += delta
		minifig.position = _stand_pos(_on_rock)
		if _on_rock_timer > 1.1:
			_start_jump()

	# face where he's headed — a 3/4 view so the glasses stay visible
	minifig.rotation.y = lerp_angle(minifig.rotation.y, deg_to_rad(38.0 * _face_dir), 8.0 * delta)

	# limbs: flung in flight (hip-hinge only!), relaxed sway on the rock
	var sway := sin(tsec * 2.2) * 0.05
	fig_arm_l.rotation.x = lerp(fig_arm_l.rotation.x, -2.5 * air + sway, 10.0 * delta)
	fig_arm_r.rotation.x = lerp(fig_arm_r.rotation.x, -2.9 * air - sway, 10.0 * delta)
	fig_leg_l.rotation.x = lerp(fig_leg_l.rotation.x, -0.85 * air, 10.0 * delta)
	fig_leg_r.rotation.x = lerp(fig_leg_r.rotation.x, 0.45 * air, 10.0 * delta)

	# landing squash-and-stretch
	_squash = max(0.0, _squash - 3.5 * delta)
	minifig.scale = MF_SCALE * Vector3(1.0 + 0.13 * _squash, 1.0 - 0.18 * _squash, 1.0 + 0.13 * _squash)

var _jump_to := 0
var _on_rock_timer := 0.0

func _start_jump() -> void:
	_jump_to = _on_rock + _hop_dir
	if _jump_to < 0 or _jump_to >= intro_rocks.size():
		_hop_dir = -_hop_dir
		_jump_to = _on_rock + _hop_dir
	_jump_from_pos = minifig.position
	_face_dir = 1.0 if _stand_pos(_jump_to).x > minifig.position.x else -1.0
	_jump_t = 0.0
	_jumping = true

# ---------------------------------------------------------------------------
# THE 80s TITLE CARD — the intro show hard-cuts to a DuckTales-NES-style
# screen: royal blue, fat tilted pixel logo with Jonk peeking over it (beer
# raised, of course), blinking GAME START, a difficulty row that actually
# works, and green corporate small print. Font: Press Start 2P (OFL).
# ---------------------------------------------------------------------------
const CARD_AFTER := 7.0          # seconds of minifig show before the card

var retro_root: Node3D
var retro_font: FontFile
var start_label: Label3D
var diff_label: Label3D
var card_hand: Node3D

func _retro_label(txt: String, fs: int, pix: float, color: Color, pos: Vector3, tilt := 0.0, outline := 0) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font = retro_font
	l.font_size = fs
	l.pixel_size = pix
	l.modulate = color
	l.position = pos
	l.rotation_degrees = Vector3(0, 0, tilt)
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # crisp pixels
	if outline > 0:
		l.outline_size = outline
		l.outline_modulate = Color(0.05, 0.02, 0.0)
	else:
		l.outline_size = 0
	retro_root.add_child(l)
	return l

func _build_retro_card() -> void:
	retro_font = FontFile.new()
	retro_font.load_dynamic_font(ProjectSettings.globalize_path("res://pixel_font.ttf"))
	retro_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	retro_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	retro_font.generate_mipmaps = false

	retro_root = Node3D.new()
	add_child(retro_root)

	# the royal blue void, close to the camera so it swallows the whole scene
	var bg := QuadMesh.new()
	bg.size = Vector2(60, 18)
	_add(bg, _mat_unshaded(Color(0.13, 0.23, 0.72)), Vector3(0, 0, 3), retro_root)

	# the logo: two fat tilted words with a hard drop shadow, NES-style
	var shadow := Color(0.32, 0.13, 0.02)
	var face := Color(0.87, 0.52, 0.10)
	_retro_label("FLAPPY", 32, 0.037, shadow, Vector3(-0.51, 2.87, 4.9), 5.0)
	_retro_label("FLAPPY", 32, 0.037, face, Vector3(-0.4, 3.0, 5.0), 5.0, 8)
	_retro_label("JONK", 32, 0.05, shadow, Vector3(0.79, 1.22, 4.9), 5.0)
	_retro_label("JONK", 32, 0.05, face, Vector3(0.9, 1.35, 5.0), 5.0, 8)
	_retro_label("TM", 8, 0.028, Color(0.9, 0.9, 0.9), Vector3(4.05, 0.62, 5.0))

	start_label = _retro_label("GAME START", 16, 0.022, Color(0.92, 0.92, 0.92), Vector3(0, -1.3, 5.0))
	diff_label = _retro_label("", 16, 0.0165, Color(0.91, 0.55, 0.58), Vector3(0, -2.15, 5.0))
	_refresh_diff_label()
	_retro_label("< >  PICK YOUR POISON", 8, 0.019, Color(0.55, 0.62, 0.85), Vector3(0, -2.75, 5.0))

	var green := Color(0.55, 0.76, 0.55)
	_retro_label("(C) THE WALT JONK COMPANY", 16, 0.0145, green, Vector3(0, -3.9, 5.0))
	_retro_label("PRODUCED BY LARS-ERIK LTD.", 16, 0.0145, green, Vector3(0, -4.5, 5.0))
	_retro_label("BÄÄR U.S.A. INC", 16, 0.0145, green, Vector3(0, -5.1, 5.0))

	# the raised C-clamp hand with the bäär, peeking over the logo beside
	# the head — Scrooge has a top hat, Jonk has a beer
	card_hand = Node3D.new()
	card_hand.position = Vector3(-1.5, 3.85, 4.2)
	card_hand.rotation_degrees = Vector3(0, 0, -18)
	card_hand.scale = Vector3.ONE * 0.16
	retro_root.add_child(card_hand)
	var sleeve := _add(_cyl(2.4, 6.0), _mat(Color(0.78, 0.09, 0.1), 0.45), Vector3(0, -5.0, 0), card_hand)
	sleeve.rotation_degrees = Vector3(0, 0, 0)
	_add(_cyl(1.59, 2.2), _mat(FRIEND.skin, 0.35), Vector3(0, -1.6, 0), card_hand)
	var hand := _build_hand(FRIEND.skin)
	hand.position = Vector3(0, 0, 0)
	card_hand.add_child(hand)
	var can := Node3D.new()
	can.position = Vector3(0, 0, 2.3)
	card_hand.add_child(can)
	_add(_cyl(2.1, 5.4), _mat(Color(0.93, 0.90, 0.83), 0.5, 0.0, true, 0.3), Vector3.ZERO, can)
	_add(_cyl(1.85, 0.7), _mat(Color(0.75, 0.77, 0.80), 0.2, 0.95), Vector3(0, 2.9, 0), can)
	_add(_cyl(2.15, 0.5), _mat(Color(0.75, 0.77, 0.80), 0.2, 0.95), Vector3(0, -2.8, 0), can)
	var blob := _add(_sphere(1.1), _mat(Color(0.96, 0.62, 0.11), 0.55), Vector3(0, -0.4, 1.7), can)
	blob.scale = Vector3(1.25, 1.0, 0.55)

func _mat_unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _refresh_diff_label() -> void:
	var parts := []
	for i in range(DIFF_NAMES.size()):
		parts.append(("*" + DIFF_NAMES[i]) if i == difficulty else DIFF_NAMES[i])
	diff_label.text = "   ".join(parts)

func _enter_card() -> void:
	menu_phase = MENU_CARD
	menu_phase_t = 0.0
	intro_root.visible = false
	title_box.visible = false
	retro_root.visible = true
	# the flappy head takes Scrooge's spot: peeking over the logo's top-left
	head.visible = true
	head.position = Vector3(-2.95, 3.65, 4.2)
	head.rotation_degrees = Vector3(0, -30, 0)   # mostly face the camera
	head.scale = Vector3.ONE * 1.15

func _animate_card(delta: float, tsec: float) -> void:
	# Scrooge-style idle bob for head and raised beer, blinking start prompt
	head.position.y = 3.65 + sin(tsec * 2.3) * 0.1
	head.rotation.z = sin(tsec * 1.7) * 0.05
	card_hand.position.y = 3.85 + sin(tsec * 2.3 + 0.6) * 0.12
	card_hand.rotation.z = deg_to_rad(-18) + sin(tsec * 2.3) * 0.08
	start_label.visible = int(tsec * 2.2) % 2 == 0

# ---------------------------------------------------------------------------
# CLOUDS (parallax backdrop)
# ---------------------------------------------------------------------------
func _build_clouds() -> void:
	# a clear dusk sky reads more real than primitive blob clouds — the
	# fireflies, haze, and moss carry the atmosphere instead
	pass

# ---------------------------------------------------------------------------
# PIPES + BEER CANS
# ---------------------------------------------------------------------------
func _spawn_pipe(x: float) -> void:
	var root := Node3D.new()
	var gap: float = randf_range(GAP_MIN, GAP_MAX)
	root.position = Vector3(x, 0, 0)
	add_child(root)

	# the obstacles are the Pillars of Creation (JWST) — real nebula dust
	# columns rising from below and hanging from above. Being gas, they
	# stretch to any column length without looking wrong. The narrow tip
	# pokes 0.5 past the gap edge as a visual grace zone: brushing the very
	# tip doesn't kill, because the collision cylinder starts where the
	# pillar is wider.
	var tex_path := "res://pillar1_real.png" if (pipes.size() % 2 == 0) else "res://pillar2_real.png"
	var half := pipe_gap / 2.0
	var pil_h := 13.0
	var top_p := _photo_quad(tex_path, Vector2(2.4, pil_h), false, Vector3(0, gap + half + pil_h / 2.0 - 0.5, 0), root)
	top_p.rotation_degrees = Vector3(0, 0, 180)  # tip hanging down into the gap
	_photo_quad(tex_path, Vector2(2.4, pil_h), false, Vector3(0, gap - half - pil_h / 2.0 + 0.5, 0), root)

	var beer: Node3D = null
	if randf() < BEER_CHANCE:
		beer = _build_beer(root, gap)

	pipes.append({ "root": root, "x": x, "gap": gap, "passed": false, "beer": beer })

func _build_beer(root: Node3D, gap: float) -> Node3D:
	var can := Node3D.new()
	can.position = Vector3(0, gap, 0)
	root.add_child(can)
	# "the bäär" can: cream body (faint glow so it stays findable at dusk)
	_add(_cyl(0.32, 0.82), _mat(Color(0.93, 0.90, 0.83), 0.5, 0.0, true, 0.25), Vector3.ZERO, can)
	# silver rims top and bottom
	_add(_cyl(0.28, 0.1), _mat(Color(0.75, 0.77, 0.80), 0.2, 0.95), Vector3(0, 0.45, 0), can)
	_add(_cyl(0.33, 0.07), _mat(Color(0.75, 0.77, 0.80), 0.2, 0.95), Vector3(0, -0.43, 0), can)
	# the orange bear blob on the label (head + ear + snout)
	var orange := _mat(Color(0.96, 0.62, 0.11), 0.55)
	var bear := _add(_sphere(0.17), orange, Vector3(-0.02, -0.14, 0.24), can)
	bear.scale = Vector3(1.25, 1.0, 0.55)
	_add(_sphere(0.055), orange, Vector3(-0.13, 0.02, 0.27), can)
	_add(_sphere(0.06), orange, Vector3(0.14, -0.08, 0.28), can)
	# label text
	var lbl := Label3D.new()
	lbl.text = "the\nbäär"
	lbl.font_size = 36
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.1, 0.1, 0.1)
	lbl.position = Vector3(0, 0.16, 0.33)
	can.add_child(lbl)
	can.rotation_degrees = Vector3(0, 0, 18)
	return can

func _clear_pipes() -> void:
	for p in pipes:
		p.root.queue_free()
	pipes.clear()

# ---------------------------------------------------------------------------
# GAME FLOW
# ---------------------------------------------------------------------------
func _goto_menu() -> void:
	state = STATE_MENU
	menu_phase = MENU_SHOW
	menu_phase_t = 0.0
	_clear_pipes()
	velocity_y = 0.0
	head.position = Vector3(HEAD_X, 0, 0)
	head.rotation = Vector3.ZERO
	head.scale = Vector3.ONE
	head.visible = false           # the intro minifig takes the stage instead
	intro_root.visible = true
	retro_root.visible = false
	title_box.visible = true
	gameover_box.visible = false
	score_label.visible = false
	# top 5 only on the menu — the minifig show needs its stage
	_refresh_scores_label(scores_label, 5)

func _start_game() -> void:
	state = STATE_PLAY
	_clear_pipes()
	score = 0
	_beer_count = 0
	# apply the difficulty picked on the title card
	pipe_gap = DIFF_GAP[difficulty]
	run_base_speed = DIFF_BASE_SPEED[difficulty]
	run_speed_per = DIFF_SPEED_PER[difficulty]
	run_max_speed = DIFF_MAX_SPEED[difficulty]
	speed = run_base_speed
	velocity_y = FLAP_VELOCITY
	since_spawn = PIPE_SPACING
	head.position = Vector3(HEAD_X, 0, 0)
	head.rotation = Vector3.ZERO
	head.scale = Vector3.ONE
	head.visible = true
	intro_root.visible = false
	retro_root.visible = false
	title_box.visible = false
	gameover_box.visible = false
	score_label.visible = true
	score_label.text = "0"

func _die() -> void:
	if state != STATE_PLAY:
		return
	state = STATE_DEAD
	score_label.visible = false
	if _beer_count > 0:
		final_label.text = "SCORE  %d\n🍺 %d beers caught" % [score, _beer_count]
	else:
		final_label.text = "SCORE  %d" % score
	gameover_box.visible = true
	var qualifies := high_scores.size() < MAX_SCORES or score > int(high_scores.back().score)
	if qualifies and score > 0:
		entering_name = true
		name_row.visible = true
		hint_label.text = "New high score! Enter your name:"
		name_edit.text = ""
		name_edit.grab_focus()
	else:
		entering_name = false
		name_row.visible = false
		hint_label.text = "SPACE / click to play again"
	_refresh_scores_label(gameover_scores)

var _beer_count := 0
var gameover_scores: Label

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# secret: Cmd/Ctrl+Shift+K wipes the high-score list
		if event.keycode == KEY_K and event.shift_pressed and (event.meta_pressed or event.ctrl_pressed):
			_clear_high_scores()
			return
		match event.keycode:
			KEY_SPACE:
				_primary_action()
			KEY_LEFT:
				_nudge_difficulty(-1)
			KEY_RIGHT:
				_nudge_difficulty(1)
			KEY_F, KEY_F11:
				_toggle_fullscreen()
			KEY_ESCAPE:
				if get_window().mode == Window.MODE_FULLSCREEN:
					get_window().mode = Window.MODE_WINDOWED
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_primary_action()
	# game controllers (PlayStation etc.): any face button flaps, Options = fullscreen
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y:
				_primary_action()
			JOY_BUTTON_DPAD_LEFT:
				_nudge_difficulty(-1)
			JOY_BUTTON_DPAD_RIGHT:
				_nudge_difficulty(1)
			JOY_BUTTON_START:
				_toggle_fullscreen()

func _nudge_difficulty(dir: int) -> void:
	if state != STATE_MENU or menu_phase != MENU_CARD:
		return
	difficulty = clampi(difficulty + dir, 0, DIFF_NAMES.size() - 1)
	_refresh_diff_label()

func _toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _primary_action() -> void:
	match state:
		STATE_MENU:
			# 80s flow: the attract show cuts to the title card first,
			# GAME START on the card actually starts
			if menu_phase == MENU_SHOW:
				_enter_card()
			else:
				_start_game()
		STATE_PLAY:
			velocity_y = FLAP_VELOCITY
		STATE_DEAD:
			if entering_name:
				return
			_goto_menu()
			_start_game()

func _on_name_submitted(_t := "") -> void:
	var nm := name_edit.text.strip_edges().to_upper()
	if nm == "":
		nm = FRIEND.name
	_save_score(nm, score)
	entering_name = false
	name_row.visible = false
	hint_label.text = "SPACE / click to play again"
	_refresh_scores_label(gameover_scores)

# ---------------------------------------------------------------------------
# MAIN LOOP
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# drifting clouds everywhere
	for c in clouds:
		c.position.x -= 0.4 * delta
		if c.position.x < -12:
			c.position.x = 12
			c.position.y = randf_range(2.5, 6.5)

	var tsec := Time.get_ticks_msec() / 1000.0

	# the astronaut drifts weightlessly, tumbling ever so slowly
	if astronaut != null:
		astronaut.position.x += 0.12 * delta
		astronaut.position.y = 2.5 + sin(tsec * 0.35) * 0.7
		astronaut.rotation.z = sin(tsec * 0.2) * 0.35
		if astronaut.position.x > 14.0:
			astronaut.position.x = -14.0

	# the background rocket cruises by on a gentle sine, flame flickering
	if rocket != null:
		rocket.position.x += 3.0 * delta
		rocket.position.y = 4.0 + sin(tsec * 0.8) * 0.6
		if rocket.position.x > 18.0:
			rocket.position.x = -18.0
			rocket.position.z = -8.0 - randf() * 4.0
		if rocket_flame != null:
			rocket_flame.scale.y = 1.0 + sin(tsec * 22.0) * 0.25

	if state == STATE_MENU:
		menu_phase_t += delta
		if menu_phase == MENU_SHOW:
			_animate_intro(delta, tsec)
			if menu_phase_t > CARD_AFTER:
				_enter_card()
		else:
			_animate_card(delta, tsec)
		return

	if state != STATE_PLAY:
		return

	# autopilot for dev screenshot mode
	if _shot_dir != "" and velocity_y < 0.0 and head.position.y < 0.5:
		velocity_y = FLAP_VELOCITY

	speed = min(run_max_speed, run_base_speed + score * run_speed_per)

	# physics
	velocity_y = max(MAX_FALL, velocity_y - GRAVITY * delta)
	head.position.y += velocity_y * delta

	# flappy tilt: nose up when rising, nose-dive when falling (profile view →
	# tilt is a roll around the screen axis)
	var target_tilt: float = clamp(velocity_y / 16.0, -0.9, 0.5)
	head.rotation.z = lerp(head.rotation.z, target_tilt, 10.0 * delta)

	# ceiling clamp, floor death
	if head.position.y > CEIL_Y:
		head.position.y = CEIL_Y
		velocity_y = min(velocity_y, 0.0)
	if head.position.y - HEAD_RADIUS < FLOOR_Y:
		_die()
		return

	# spawn pipes on a fixed spacing
	since_spawn += speed * delta
	if since_spawn >= PIPE_SPACING:
		since_spawn -= PIPE_SPACING
		_spawn_pipe(SPAWN_X)

	# move + test pipes
	var to_remove := []
	for p in pipes:
		p.x -= speed * delta
		p.root.position.x = p.x

		# spin beer cans for a little shine
		if p.beer != null and is_instance_valid(p.beer):
			p.beer.rotation.y += 3.0 * delta

		# scoring when a pipe passes the head
		if not p.passed and p.x < HEAD_X:
			p.passed = true
			score += 1
			score_label.text = str(score)

		# collision with pipe body
		if abs(p.x - HEAD_X) < (PIPE_RADIUS + HEAD_RADIUS):
			var half := pipe_gap / 2.0
			if head.position.y > p.gap + half - HEAD_RADIUS or head.position.y < p.gap - half + HEAD_RADIUS:
				_die()
				return

		# beer pickup
		if p.beer != null and is_instance_valid(p.beer):
			var bpos := Vector3(p.x, p.gap, 0)
			if Vector2(bpos.x - HEAD_X, bpos.y - head.position.y).length() < BEER_PICKUP_RADIUS:
				_collect_beer(p)

		if p.x < DESPAWN_X:
			to_remove.append(p)

	for p in to_remove:
		p.root.queue_free()
		pipes.erase(p)

func _collect_beer(p: Dictionary) -> void:
	score += BEER_POINTS
	_beer_count += 1
	score_label.text = str(score)
	_beer_pop(Vector3(p.x, p.gap, 0.2))
	p.beer.queue_free()
	p.beer = null

func _beer_pop(pos: Vector3) -> void:
	# a quick burst of glowing motes that fly out and fade
	for i in range(10):
		var mat := _mat(Color(1.0, 0.8, 0.25, 1.0), 0.3, 0.2, true, 1.2)
		var m := _add(_sphere(0.08), mat, pos)
		var ang := randf() * TAU
		var dir := Vector3(cos(ang), sin(ang), randf_range(-0.3, 0.3)) * randf_range(1.0, 2.2)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(m, "position", pos + dir, 0.5).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tw.chain().tween_callback(m.queue_free)

# ---------------------------------------------------------------------------
# HIGH SCORES (persistent, local)
# ---------------------------------------------------------------------------
func _load_scores() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		high_scores = [
			{ "name": "AXEL", "score": 21 },
			{ "name": "BEER GOD", "score": 16 },
			{ "name": "JONK", "score": 12 },
			{ "name": "LISA", "score": 8 },
			{ "name": "NOOB", "score": 3 },
		]
		_write_scores()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_ARRAY:
		high_scores = data
	_sort_scores()

func _write_scores() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(high_scores))
	f.close()

func _sort_scores() -> void:
	high_scores.sort_custom(func(a, b): return int(a.score) > int(b.score))
	if high_scores.size() > MAX_SCORES:
		high_scores.resize(MAX_SCORES)

func _clear_high_scores() -> void:
	high_scores = []
	_write_scores()
	_refresh_scores_label(scores_label)
	_refresh_scores_label(gameover_scores)
	_toast("HIGH SCORES CLEARED 🍺")

func _toast(msg: String) -> void:
	var t := _make_label(38, Color(1.0, 0.9, 0.4))
	t.text = msg
	t.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	t.grow_horizontal = Control.GROW_DIRECTION_BOTH
	t.grow_vertical = Control.GROW_DIRECTION_BOTH
	ui.add_child(t)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(t, "modulate:a", 0.0, 0.6)
	tw.tween_callback(t.queue_free)

func _save_score(nm: String, sc: int) -> void:
	high_scores.append({ "name": nm, "score": sc })
	_sort_scores()
	_write_scores()

func _refresh_scores_label(label: Label, limit := MAX_SCORES) -> void:
	if label == null:
		return
	var lines := ["— HIGH SCORES —"]
	var rank := 1
	for e in high_scores:
		if rank > limit:
			break
		lines.append("%2d.  %-10s %5d" % [rank, str(e.name).left(10), int(e.score)])
		rank += 1
	label.text = "\n".join(lines)

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _make_label(size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	# live score (top center)
	score_label = _make_label(96)
	score_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_label.position.y = 40
	ui.add_child(score_label)

	# --- title / menu ---
	title_box = _panel()
	# leave the bottom of the screen undimmed — that's the minifig's stage
	title_box.offset_bottom = -380
	ui.add_child(title_box)
	var tv := VBoxContainer.new()
	tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 14)
	title_box.add_child(tv)
	tv.add_child(_center(_make_label(72, Color(1.0, 0.85, 0.3)), "FLAPPY %s" % FRIEND.name))
	tv.add_child(_center(_make_label(30), "Flap through the pipes.\nCatch the beer cans! 🍺"))
	scores_label = _make_label(26, Color(0.95, 0.97, 1.0))
	tv.add_child(_center(scores_label, ""))
	tv.add_child(_center(_make_label(34, Color(0.8, 1.0, 0.85)), "▶  SPACE / CLICK / 🎮 ✕ to start"))
	tv.add_child(_center(_make_label(24, Color(0.75, 0.85, 0.95)), "F = fullscreen   ·   ESC = windowed"))

	# --- game over ---
	gameover_box = _panel()
	gameover_box.visible = false
	ui.add_child(gameover_box)
	var gv := VBoxContainer.new()
	gv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gv.alignment = BoxContainer.ALIGNMENT_CENTER
	gv.add_theme_constant_override("separation", 12)
	gameover_box.add_child(gv)
	gv.add_child(_center(_make_label(64, Color(1.0, 0.5, 0.4)), "GAME OVER"))
	final_label = _make_label(40)
	gv.add_child(_center(final_label, "SCORE 0"))
	gameover_scores = _make_label(24, Color(0.95, 0.97, 1.0))
	gv.add_child(_center(gameover_scores, ""))

	name_row = HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "YOUR NAME"
	name_edit.max_length = 10
	name_edit.custom_minimum_size = Vector2(260, 48)
	name_edit.add_theme_font_size_override("font_size", 26)
	name_edit.text_submitted.connect(_on_name_submitted)
	var save_btn := Button.new()
	save_btn.text = "SAVE"
	save_btn.add_theme_font_size_override("font_size", 26)
	save_btn.pressed.connect(_on_name_submitted)
	name_row.add_child(name_edit)
	name_row.add_child(save_btn)
	gv.add_child(_center_control(name_row))

	hint_label = _make_label(30, Color(0.8, 1.0, 0.85))
	gv.add_child(_center(hint_label, ""))

func _panel() -> Control:
	var p := ColorRect.new()
	p.color = Color(0.05, 0.07, 0.12, 0.45)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return p

func _center(label: Label, text: String) -> Control:
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _center_control(c: Control) -> Control:
	var wrap := CenterContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(c)
	return wrap
