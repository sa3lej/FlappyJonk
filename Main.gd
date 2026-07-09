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
const SETTINGS_PATH := "user://settings.json"
const MAX_SCORES := 10
const FLAP_SFX_PATH := "res://jonk_flap.wav"   # Jonk's voice memo, one per flap
const CRASH_SFX_PATH := "res://crash.wav"      # for meeting the Pillars of Creation
const BEER_SFX_PATH := "res://beer.wav"        # for catching a bäär
const MUSIC_PATH := "res://title_music.wav"    # chiptune loop (tools/make_title_music.py)

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

var state := STATE_MENU
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
var cam: Camera3D
var _shake := 0.0
var flap_sfx: AudioStreamPlayer
var crash_sfx: AudioStreamPlayer
var beer_sfx: AudioStreamPlayer
var menu_music: AudioStreamPlayer
var music_on := false            # title tune is opt-in: T toggles it
var muted := false
var card_snd_label: Label3D
var flap_arm_l: Node3D
var flap_arm_r: Node3D
var _flap_pulse := 0.0
var pipes: Array = []            # { root, x, gap, passed, beer }
var clouds: Array = []
var since_spawn := 0.0

# UI nodes
var ui: CanvasLayer
var score_label: Label
var gameover_box: Control
var final_label: Label
var name_row: Control
var name_edit: LineEdit
var hint_label: Label

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------
func _ready() -> void:
	randomize()
	_load_scores()
	_load_settings()
	_build_audio()
	_build_environment()
	_build_camera()
	_build_lights()
	_build_clouds()
	_build_ground()
	_build_bayou()
	head = _build_head()
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
	# `godot --path . -- --play <dir>` lets the pilot play a full run:
	# it chases the pipe gaps for real, screenshots along the way, and
	# prints the final score before quitting.
	idx = uargs.find("--play")
	if idx != -1:
		_play_dir = uargs[idx + 1] if uargs.size() > idx + 1 else "/tmp"
		_run_play_sequence()
	if uargs.has("--test-restart"):
		_run_restart_test()

func _run_restart_test() -> void:
	# regression tests for the game-over flow: gamepad name entry must
	# work, and ONE press must always get you back into the game.
	# The REAL family leaderboard is snapshotted and fully restored —
	# a filter scrub once let fake scores push real ones off the capped
	# list and ate them permanently.
	var scores_backup: Array = high_scores.duplicate(true)
	await get_tree().create_timer(0.8).timeout

	# phase 0: on the title card, Triangle toggles sound, Circle the melody
	var m0 := muted
	var t0 := music_on
	_push_pad(JOY_BUTTON_Y)
	var tri_ok := muted != m0
	_push_pad(JOY_BUTTON_Y)
	_push_pad(JOY_BUTTON_B)
	var ring_ok := music_on != t0
	_push_pad(JOY_BUTTON_B)
	print("TEST triangle_mutes=%s ring_toggles_music=%s" % [tri_ok, ring_ok])

	# phase 1: gamepad — spin B, X locks it, spin B, X locks, X saves "BB",
	# X starts the next game: the whole X-X-X flow
	_start_game()
	await get_tree().create_timer(0.5).timeout
	score = 999
	_die()
	await get_tree().create_timer(0.3).timeout
	_push_pad(JOY_BUTTON_DPAD_UP)    # a letter appears: "A"
	_push_pad(JOY_BUTTON_DPAD_UP)    # spun to "B"
	_push_pad(JOY_BUTTON_A)          # X locks it — NOTHING new may appear
	var no_ghost_a: bool = name_edit.text == "B"
	print("TEST pad_typed=%s no_ghost_a=%s" % [name_edit.text, no_ghost_a])
	var not_saved_by_x: bool = entering_name
	_push_pad(JOY_BUTTON_DPAD_UP)    # second letter appears: "BA"
	_push_pad(JOY_BUTTON_DPAD_UP)    # spun to "BB"
	_push_pad(JOY_BUTTON_A)          # lock
	_push_pad(JOY_BUTTON_A)          # nothing pending -> saves "BB"
	var pad_saved: bool = str(high_scores[0].name) == "BB" and not entering_name and not_saved_by_x and no_ghost_a
	_push_pad(JOY_BUTTON_A)          # and one more X starts the game
	await get_tree().create_timer(0.2).timeout
	var pad_restarts := state == STATE_PLAY

	# phase 2: keyboard — space in the focused name field saves + restarts
	score = 998
	_die()
	await get_tree().create_timer(0.5).timeout
	var uargs := OS.get_cmdline_user_args()
	var ti := uargs.find("--test-restart")
	if ti + 1 < uargs.size() and not uargs[ti + 1].begins_with("--"):
		await _save_shot(uargs[ti + 1] + "/test_confetti.png")
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().create_timer(0.3).timeout
	print("TEST_RESULT pad_name_saved=%s pad_restarts=%s kbd_restarts=%s" % [pad_saved, pad_restarts, state == STATE_PLAY])
	# put the family leaderboard back exactly as it was
	high_scores = scores_backup
	_write_scores()
	get_tree().quit()

func _push_pad(btn: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = true
	get_viewport().push_input(e)

var _shot_dir := ""
var _play_dir := ""
var _cheat_pilot := false        # secret in-game autopilot (Cmd/Ctrl+Shift+A)
var _pilot_flew := false         # piloted runs stay off the high-score list
var pilot_label: Label

func _run_play_sequence() -> void:
	await get_tree().create_timer(0.6).timeout
	_start_game()
	var shots := 0
	var t := 0.0
	while state == STATE_PLAY and t < 180.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if fmod(t, 8.0) < 0.4 and shots < 16:
			shots += 1
			await _save_shot(_play_dir + "/play_%02d.png" % shots)
	await get_tree().create_timer(0.6).timeout
	await _save_shot(_play_dir + "/play_final.png")
	print("PILOT_SCORE=%d BEERS=%d" % [score, _beer_count])
	get_tree().quit()

func _run_shot_sequence() -> void:
	await get_tree().create_timer(1.5).timeout
	await _save_shot(_shot_dir + "/shot_menu.png")
	# a second frame catches the other blink state of GAME START
	await get_tree().create_timer(0.5).timeout
	await _save_shot(_shot_dir + "/shot_menu2.png")
	_start_game()
	await get_tree().create_timer(3.2).timeout
	await _save_shot(_shot_dir + "/shot_play.png")
	_die()
	await get_tree().create_timer(0.4).timeout
	await _save_shot(_shot_dir + "/shot_gameover.png")
	get_tree().quit()

func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _build_audio() -> void:
	# all audio goes through the import system (load) so the same code
	# works in dev runs AND inside an exported app's pack.
	# Missing file = silent game, no drama.
	flap_sfx = AudioStreamPlayer.new()
	add_child(flap_sfx)
	if ResourceLoader.exists(FLAP_SFX_PATH):
		flap_sfx.stream = load(FLAP_SFX_PATH)
	crash_sfx = AudioStreamPlayer.new()
	add_child(crash_sfx)
	if ResourceLoader.exists(CRASH_SFX_PATH):
		crash_sfx.stream = load(CRASH_SFX_PATH)
	beer_sfx = AudioStreamPlayer.new()
	add_child(beer_sfx)
	if ResourceLoader.exists(BEER_SFX_PATH):
		beer_sfx.stream = load(BEER_SFX_PATH)
	menu_music = AudioStreamPlayer.new()
	menu_music.volume_db = -6.0
	add_child(menu_music)
	if ResourceLoader.exists(MUSIC_PATH):
		var m: AudioStreamWAV = load(MUSIC_PATH)
		m.loop_mode = AudioStreamWAV.LOOP_FORWARD
		m.loop_begin = 0
		m.loop_end = m.data.size() / 2   # frames (16-bit mono)
		menu_music.stream = m
	AudioServer.set_bus_mute(0, muted)

func _flap() -> void:
	velocity_y = FLAP_VELOCITY
	_flap_pulse = 1.0
	if flap_sfx.stream != null:
		flap_sfx.play()   # retriggering cuts the previous cry — rapid-fire JONKs

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		muted = bool(data.get("muted", false))
		music_on = bool(data.get("music_on", false))

func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "muted": muted, "music_on": music_on }))
	f.close()

func _toggle_music() -> void:
	music_on = not music_on
	_save_settings()
	if music_on and state == STATE_MENU and menu_music.stream != null:
		menu_music.play()
	elif not music_on:
		menu_music.stop()
	_toast("MUSIC ON" if music_on else "MUSIC OFF")

func _toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	_save_settings()
	card_snd_label.visible = muted
	_toast("SOUND OFF" if muted else "SOUND ON")

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	# a real photograph of the Milky Way wrapped around the whole sky
	# (ESO/S. Brunier 360° panorama, CC BY 4.0 — credited in the README)
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://sky_milkyway.jpg")
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
	cam = Camera3D.new()
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

var _tex_cache := {}

func _photo_quad(res_path: String, size: Vector2, additive := false, pos := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	# a billboard carrying a real photograph; additive blend lifts away a
	# pure-black background (perfect for astro photos). Textures are cached
	# so repeat spawns (obstacles!) don't re-decode the file.
	if not _tex_cache.has(res_path):
		_tex_cache[res_path] = load(res_path)
	var tex: Texture2D = _tex_cache[res_path]
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
	# arm panels + hands, hinged at the shoulders so they can flap
	for x in [-0.82, 0.82]:
		var piv := Node3D.new()
		piv.position = Vector3(x, -1.35, 0.05)
		model.add_child(piv)
		_add(_box(Vector3(0.16, 0.85, 0.65)), red, Vector3(0, -0.45, 0), piv)
		_add(_box(Vector3(0.2, 0.28, 0.28)), hands, Vector3(0, -0.97, 0.25), piv)
		if x < 0.0:
			flap_arm_l = piv
		else:
			flap_arm_r = piv
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
# THE 80s TITLE CARD — the menu IS a DuckTales-NES-style screen: royal blue,
# fat tilted pixel logo with pixel-art LEGO-Jonk peeking over it (beer
# raised, of course), blinking GAME START, a difficulty row that actually
# works, and green corporate small print. Font: Press Start 2P (OFL).
# ---------------------------------------------------------------------------
var retro_root: Node3D
var retro_font: FontFile
var start_label: Label3D
var diff_label: Label3D
var hiscore_label: Label3D
var card_jonk: MeshInstance3D

const SPRITE_COLORS := {
	"S": Color(0.88, 0.73, 0.55),   # skin
	"K": Color(0.05, 0.05, 0.06),   # glasses / mouth
	"W": Color(0.95, 0.95, 0.95),   # eye white / can / shirt print
	"B": Color(0.45, 0.25, 0.13),   # beard
	"R": Color(0.82, 0.12, 0.12),   # shirt / sleeve
	"J": Color(0.18, 0.33, 0.66),   # jeans
	"H": Color(0.11, 0.21, 0.46),   # hip piece
	"V": Color(0.75, 0.77, 0.80),   # can rims
	"O": Color(0.96, 0.62, 0.11),   # the bäär bear
	"Y": Color(0.94, 0.88, 0.76),   # the stud — its own piece, its own shine
	"T": Color(0.96, 0.85, 0.68),   # plastic sheen on the head
	"P": Color(0.97, 0.38, 0.33),   # plastic sheen on the shirt
	"L": Color(0.36, 0.53, 0.86),   # plastic sheen on the legs / foot fronts
	"C": Color(0.90, 0.85, 0.74),   # cream eye tiles, like the game head
	"N": Color(0.78, 0.58, 0.38),   # the nose brick
	"M": Color(0.30, 0.16, 0.08),   # mustache, darker than the beard
}

func _rect(g: Array, x: int, y: int, w: int, h: int, ch: String) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if yy >= 0 and yy < g.size() and xx >= 0 and xx < g[yy].size():
				g[yy][xx] = ch

func _jonk_grid() -> Array:
	# Jonk assembled from rectangles, the way LEGO intended — proportions and
	# part seams taken from the real minifig: big cylinder head with rounded
	# corners and its stud, glasses with skin-and-eyes visible INSIDE the
	# lenses, smoothly tapering trapezoid torso, arms separated from the
	# torso by dark joint seams, C-clamp hands, hip piece bridging the split
	# blocky legs, and bright foot fronts. Hand-placed plastic sheen patches
	# (research: glossy material = small, focused specular highlights).
	var W := 56
	var H := 64
	var g := []
	for y in range(H):
		var row := []
		row.resize(W)
		row.fill(".")
		g.append(row)

	# — the bäär, raised high in the right fist —
	_rect(g, 41, 0, 8, 1, "V")
	_rect(g, 40, 1, 10, 7, "W")
	_rect(g, 41, 1, 1, 6, "T")      # glossy aluminum glint down the side
	_rect(g, 43, 2, 4, 3, "O")
	_rect(g, 43, 6, 4, 1, "K")      # a whisper of label text
	_rect(g, 40, 7, 10, 1, "V")     # bottom rim peeking above the fist
	_rect(g, 39, 8, 12, 5, "S")     # fist wrapping the can
	_rect(g, 41, 13, 3, 2, "S")     # wrist peg
	_rect(g, 40, 15, 5, 8, "R")     # raised sleeve
	_rect(g, 40, 15, 1, 6, "P")     # sleeve gloss
	_rect(g, 38, 23, 7, 5, "R")     # shoulder — column 37 stays open: joint seam

	# — head: the boxy BrickHeadz brick from the game, two pale studs up top —
	_rect(g, 18, 2, 5, 2, "Y")
	_rect(g, 29, 2, 5, 2, "Y")
	_rect(g, 18, 2, 1, 1, "T")      # gleam on the studs
	_rect(g, 29, 2, 1, 1, "T")
	_rect(g, 15, 4, 22, 19, "S")    # big square head brick — no cylinder here
	_rect(g, 15, 4, 1, 1, ".")      # just a hint of corner chamfer
	_rect(g, 36, 4, 1, 1, ".")
	_rect(g, 16, 5, 12, 1, "T")     # glossy L-shaped rim light on the brick
	_rect(g, 16, 5, 1, 8, "T")

	# — the trademark oversized square glasses, 2px-thick frames —
	for fx in [14, 27]:
		_rect(g, fx, 8, 11, 2, "K")          # top bar
		_rect(g, fx, 15, 11, 2, "K")         # bottom bar
		_rect(g, fx, 10, 2, 5, "K")          # frame sides
		_rect(g, fx + 9, 10, 2, 5, "K")
	_rect(g, 25, 10, 2, 2, "K")     # bridge
	# cream eye tiles + big round eye discs + glints, like the game head
	_rect(g, 16, 10, 7, 5, "C")
	_rect(g, 29, 10, 7, 5, "C")
	# eyes glancing up-right, straight at the bäär
	_rect(g, 19, 10, 4, 4, "K")
	_rect(g, 32, 10, 4, 4, "K")
	for c in [[19, 10], [22, 10], [19, 13], [22, 13], [32, 10], [35, 10], [32, 13], [35, 13]]:
		_rect(g, c[0], c[1], 1, 1, "C")      # rounded eye corners
	_rect(g, 21, 10, 1, 1, "W")     # glints, up toward the can
	_rect(g, 34, 10, 1, 1, "W")

	# — nose brick, mustache, mouth slot, jaw wrap wider than the head —
	_rect(g, 12, 15, 3, 3, "S")     # ear plates sticking out, like the game head
	_rect(g, 37, 15, 3, 3, "S")
	_rect(g, 15, 15, 2, 6, "B")     # sideburn slabs
	_rect(g, 35, 15, 2, 6, "B")
	_rect(g, 17, 19, 18, 2, "M")    # mustache, dark
	_rect(g, 24, 17, 4, 3, "N")     # the nose brick
	_rect(g, 13, 21, 26, 2, "B")    # jaw wrap, clearly wider than the head
	_rect(g, 17, 21, 2, 1, "M")     # drooping mustache ends
	_rect(g, 33, 21, 2, 1, "M")
	_rect(g, 15, 22, 4, 1, "M")     # dark brick-step accents in the beard
	_rect(g, 33, 22, 4, 1, "M")
	_rect(g, 23, 21, 6, 1, "K")     # mouth slot

	# — torso: smooth trapezoid, shoulders clipped —
	_rect(g, 15, 23, 22, 5, "R")
	_rect(g, 14, 28, 24, 5, "R")
	_rect(g, 13, 33, 26, 4, "R")
	_rect(g, 12, 37, 28, 4, "R")
	_rect(g, 15, 23, 1, 1, ".")
	_rect(g, 36, 23, 1, 1, ".")
	_rect(g, 16, 24, 3, 3, "P")     # sheen on the chest
	_rect(g, 21, 28, 10, 1, "W")    # three ragged lines of shirt print,
	_rect(g, 21, 30, 7, 1, "W")     # like actual text
	_rect(g, 21, 32, 9, 1, "W")
	# stepped chin blocks hanging over the chest, like the game's beard
	_rect(g, 18, 23, 16, 2, "B")
	_rect(g, 22, 25, 8, 2, "M")

	# — left arm out, ending in the iconic open C-clamp —
	_rect(g, 9, 23, 5, 5, "R")      # column 14 stays open: joint seam
	_rect(g, 8, 28, 5, 5, "R")
	_rect(g, 9, 23, 1, 4, "P")      # sleeve gloss
	_rect(g, 9, 33, 3, 2, "S")      # wrist peg
	_rect(g, 5, 35, 8, 7, "S")      # hand block...
	_rect(g, 7, 37, 3, 3, ".")      # ...bored hollow...
	_rect(g, 5, 37, 2, 2, ".")      # ...slotted open: the C-clamp

	# — hip piece bridging the legs, blocky legs, bright foot fronts —
	_rect(g, 12, 41, 28, 2, "H")    # hip crossbar
	_rect(g, 22, 43, 8, 2, "H")     # crotch block between the leg tops
	_rect(g, 12, 43, 13, 14, "J")
	_rect(g, 27, 43, 13, 14, "J")
	_rect(g, 14, 45, 3, 3, "L")     # sheen on the thighs
	_rect(g, 29, 45, 3, 3, "L")
	_rect(g, 11, 57, 14, 6, "J")    # feet, a nudge wider than the legs
	_rect(g, 27, 57, 14, 6, "J")
	_rect(g, 11, 59, 14, 4, "L")    # bright foot fronts facing the camera
	_rect(g, 27, 59, 14, 4, "L")
	return g

func _build_jonk_sprite() -> MeshInstance3D:
	# SNES-era pipeline: the 8-bit grid is upscaled 2x with the Scale2x/EPX
	# algorithm (rounds the staircase corners), then auto-shaded — top-lit
	# highlights, bottom shadows — and finally traced with a dark outline.
	var grid := _jonk_grid()
	var h := grid.size()
	var w: int = grid[0].size()
	var base := Image.create(w, h, false, Image.FORMAT_RGBA8)
	base.fill(Color(0, 0, 0, 0))
	for y in range(h):
		for x in range(w):
			var ch: String = grid[y][x]
			if SPRITE_COLORS.has(ch):
				base.set_pixel(x, y, SPRITE_COLORS[ch])

	# --- Scale2x (EPX) ---
	var w2 := w * 2
	var h2 := h * 2
	var img := Image.create(w2, h2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(h):
		for x in range(w):
			var p := base.get_pixel(x, y)
			var a := base.get_pixel(x, y - 1) if y > 0 else Color(0, 0, 0, 0)
			var d := base.get_pixel(x, y + 1) if y < h - 1 else Color(0, 0, 0, 0)
			var c := base.get_pixel(x - 1, y) if x > 0 else Color(0, 0, 0, 0)
			var b := base.get_pixel(x + 1, y) if x < w - 1 else Color(0, 0, 0, 0)
			var e0 := a if (c == a and c != d and a != b) else p
			var e1 := b if (a == b and a != c and b != d) else p
			var e2 := c if (d == c and d != b and c != a) else p
			var e3 := b if (b == d and b != a and d != c) else p
			img.set_pixel(x * 2, y * 2, e0)
			img.set_pixel(x * 2 + 1, y * 2, e1)
			img.set_pixel(x * 2, y * 2 + 1, e2)
			img.set_pixel(x * 2 + 1, y * 2 + 1, e3)

	# --- auto-shading (light from the top-left) + outline ---
	var flat := Image.new()
	flat.copy_from(img)
	var outline := Color(0.05, 0.04, 0.09)
	for y in range(h2):
		for x in range(w2):
			var p := flat.get_pixel(x, y)
			if p.a < 0.5:
				# transparent pixel touching the figure becomes the outline
				for n in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
					var nx: int = x + n.x
					var ny: int = y + n.y
					if nx >= 0 and nx < w2 and ny >= 0 and ny < h2 and flat.get_pixel(nx, ny).a >= 0.5:
						img.set_pixel(x, y, outline)
						break
				continue
			var up_open := y == 0 or flat.get_pixel(x, y - 1).a < 0.5
			var down_open := y == h2 - 1 or flat.get_pixel(x, y + 1).a < 0.5
			var left_open := x == 0 or flat.get_pixel(x - 1, y).a < 0.5
			var right_open := x == w2 - 1 or flat.get_pixel(x + 1, y).a < 0.5
			if up_open:
				img.set_pixel(x, y, p.lightened(0.35))
			elif left_open:
				img.set_pixel(x, y, p.lightened(0.15))
			elif down_open:
				img.set_pixel(x, y, p.darkened(0.3))
			elif right_open:
				img.set_pixel(x, y, p.darkened(0.12))

	var tex := ImageTexture.create_from_image(img)
	var q := QuadMesh.new()
	var px := 0.023                        # 2x pixels, same world size
	q.size = Vector2(w2 * px, h2 * px)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	retro_root.add_child(mi)
	return mi

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
	# imported with antialiasing off + subpixel disabled (pixel_font.ttf.import)
	retro_font = load("res://pixel_font.ttf")

	retro_root = Node3D.new()
	add_child(retro_root)

	# the title floats in front of the real Milky Way — the live space
	# scene (moon, rockets, drifting astronaut) IS the backdrop, with just
	# a whisper of dark so the pixel text pops
	var bg := QuadMesh.new()
	bg.size = Vector2(60, 18)
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color(0.01, 0.02, 0.06, 0.38)
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add(bg, tint, Vector3(0, 0, 3), retro_root)

	# the logo: fat tilted words with a beveled 16-bit look — golden
	# highlight up-left, deep shadow down-right
	var shadow := Color(0.30, 0.12, 0.02)
	var hilite := Color(1.0, 0.82, 0.38)
	var face := Color(0.89, 0.53, 0.10)
	_retro_label("FLAPPY", 32, 0.037, shadow, Vector3(-0.29, 2.06, 4.85), 5.0)
	_retro_label("FLAPPY", 32, 0.037, hilite, Vector3(-0.46, 2.27, 4.9), 5.0)
	_retro_label("FLAPPY", 32, 0.037, face, Vector3(-0.4, 2.2, 5.0), 5.0, 8)
	_retro_label("JONK", 32, 0.05, shadow, Vector3(1.01, 0.41, 4.85), 5.0)
	_retro_label("JONK", 32, 0.05, hilite, Vector3(0.84, 0.62, 4.9), 5.0)
	_retro_label("JONK", 32, 0.05, face, Vector3(0.9, 0.55, 5.0), 5.0, 8)
	_retro_label("TM", 8, 0.028, Color(0.9, 0.9, 0.9), Vector3(4.05, -0.18, 5.0))

	hiscore_label = _retro_label("HI-SCORE  0", 16, 0.017, Color(0.92, 0.92, 0.92), Vector3(0, 6.9, 5.0))
	start_label = _retro_label("GAME START", 16, 0.022, Color(0.92, 0.92, 0.92), Vector3(0, -1.9, 5.0))
	diff_label = _retro_label("", 16, 0.0165, Color(0.91, 0.55, 0.58), Vector3(0, -2.7, 5.0))
	_refresh_diff_label()
	_retro_label("< >  PICK YOUR POISON", 8, 0.019, Color(0.55, 0.62, 0.85), Vector3(0, -3.3, 5.0))

	var green := Color(0.55, 0.76, 0.55)
	_retro_label("(C) THE WALT JONK COMPANY", 16, 0.0145, green, Vector3(0, -4.4, 5.0))
	_retro_label("PRODUCED BY LARS-ERIK LTD.", 16, 0.0145, green, Vector3(0, -5.0, 5.0))
	_retro_label("BÄÄR U.S.A. INC", 16, 0.0145, green, Vector3(0, -5.6, 5.0))
	_retro_label("SPACE / CLICK TO START  F = FULLSCREEN  M = SOUND  T = MUSIC", 8, 0.0125, Color(0.72, 0.78, 0.95), Vector3(0, -7.3, 5.0))
	card_snd_label = _retro_label("SOUND OFF", 8, 0.019, Color(0.95, 0.5, 0.4), Vector3(0, 6.35, 5.0))
	card_snd_label.visible = muted

	# pixel-art LEGO-Jonk standing proudly ON his own logo, bäär raised
	# high, leaning with the letters — nothing covers him up here
	card_jonk = _build_jonk_sprite()
	card_jonk.position = Vector3(-2.6, 3.87, 4.6)
	card_jonk.rotation_degrees = Vector3(0, 0, 5.0)

func _refresh_diff_label() -> void:
	var parts := []
	for i in range(DIFF_NAMES.size()):
		parts.append(("*" + DIFF_NAMES[i]) if i == difficulty else DIFF_NAMES[i])
	diff_label.text = "   ".join(parts)

func _animate_card(_delta: float, tsec: float) -> void:
	# Jonk stands perfectly still (he has a beer to hold) —
	# only the start prompt blinks, NES-style
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
	# THE bäär — a photo of the actual can, subject-lifted from the shot
	var can := Node3D.new()
	can.position = Vector3(0, gap, 0)
	root.add_child(can)
	_photo_quad("res://beer_real.png", Vector2(0.62, 1.1), false, Vector3.ZERO, can)
	can.rotation_degrees = Vector3(0, 0, 12)
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
	_clear_pipes()
	velocity_y = 0.0
	head.position = Vector3(HEAD_X, 0, 0)
	head.rotation = Vector3.ZERO
	head.visible = false           # pixel-Jonk fronts the title card instead
	retro_root.visible = true
	gameover_box.visible = false
	score_label.visible = false
	var top := int(high_scores[0].score) if high_scores.size() > 0 else 0
	hiscore_label.text = "HI-SCORE  %d" % top
	if music_on and menu_music.stream != null and not menu_music.playing:
		menu_music.play()

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
	since_spawn = PIPE_SPACING
	_pilot_flew = false
	pilot_label.visible = false
	# a still-running death plunge would drag the fresh run into the floor
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	head.position = Vector3(HEAD_X, 0, 0)
	head.rotation = Vector3.ZERO
	head.visible = true
	retro_root.visible = false
	menu_music.stop()
	_flap()   # liftoff — with the war cry, of course
	gameover_box.visible = false
	score_label.visible = true
	score_label.text = "0"

func _die() -> void:
	if state != STATE_PLAY:
		return
	state = STATE_DEAD
	_shake = 0.8
	if _play_dir != "":
		# autopsy line for pilot tuning
		var near := ""
		for p in pipes:
			if absf(p.x - HEAD_X) < 8.0:
				near += " (dx=%.1f gap=%.1f)" % [p.x - HEAD_X, p.gap]
		print("DEATH score=%d y=%.2f v=%.1f speed=%.1f%s" % [score, head.position.y, velocity_y, speed, near])
	# the classic flappy death plunge: tumble off the bottom of the screen
	_death_tween = create_tween().set_parallel(true)
	_death_tween.tween_property(head, "position:y", -12.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_death_tween.tween_property(head, "rotation:z", -2.6, 0.8)
	score_label.visible = false
	if _beer_count > 0:
		final_label.text = "SCORE %d\n%d BÄÄRS CAUGHT" % [score, _beer_count]
	else:
		final_label.text = "SCORE %d" % score
	gameover_box.visible = true
	pilot_label.visible = false
	var qualifies := high_scores.size() < MAX_SCORES or score > int(high_scores.back().score)
	if _pilot_flew:
		# machines don't get on the family leaderboard
		entering_name = false
		name_row.visible = false
		hint_label.text = "AUTOPILOT RUNS DON'T COUNT!"
	elif qualifies and score > 0:
		entering_name = true
		name_row.visible = true
		hint_label.text = "NEW HI-SCORE! TYPE YOUR NAME\nUP/DOWN = LETTER   X = LOCK\nX AGAIN = SAVE   CIRCLE = ERASE"
		name_edit.text = ""
		_pad_editing = false
		name_edit.grab_focus()
		_confetti()
	else:
		entering_name = false
		name_row.visible = false
		hint_label.text = "SPACE / CLICK TO PLAY AGAIN"
	_refresh_scores_label(gameover_scores)

var _beer_count := 0
var _death_tween: Tween
var gameover_scores: Label

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	# pad name entry runs BEFORE the GUI layer, so the focused LineEdit
	# can never swallow or reinterpret a controller button
	if event is InputEventJoypadButton and event.pressed and state == STATE_DEAD and entering_name:
		_gamepad_name_input(event.button_index)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# secret: Cmd/Ctrl+Shift+K wipes the high-score list
		if event.keycode == KEY_K and event.shift_pressed and (event.meta_pressed or event.ctrl_pressed):
			_clear_high_scores()
			return
		# secret: Cmd/Ctrl+Shift+A hands the controls to the autopilot
		if event.keycode == KEY_A and event.shift_pressed and (event.meta_pressed or event.ctrl_pressed):
			_cheat_pilot = not _cheat_pilot
			_toast("AUTOPILOT ENGAGED" if _cheat_pilot else "AUTOPILOT OFF")
			return
		match event.keycode:
			KEY_SPACE:
				_primary_action()
			KEY_LEFT:
				_nudge_difficulty(-1)
			KEY_RIGHT:
				_nudge_difficulty(1)
			KEY_M:
				_toggle_mute()
			KEY_T:
				_toggle_music()
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
			JOY_BUTTON_Y:
				# Triangle: sound on/off — on the title card only,
				# mid-flight it flaps like everything else
				if state == STATE_MENU:
					_toggle_mute()
				else:
					_primary_action()
			JOY_BUTTON_B:
				# Circle: title melody on/off
				if state == STATE_MENU:
					_toggle_music()
				else:
					_primary_action()
			JOY_BUTTON_A, JOY_BUTTON_X:
				_primary_action()
			JOY_BUTTON_DPAD_LEFT:
				_nudge_difficulty(-1)
			JOY_BUTTON_DPAD_RIGHT:
				_nudge_difficulty(1)
			JOY_BUTTON_START:
				_toggle_fullscreen()

const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZÅÄÖ0123456789"

var _pad_editing := false        # a letter is being spun and isn't locked yet

func _gamepad_name_input(btn: int) -> void:
	# letters ONLY appear when you spin the d-pad. X locks the current
	# letter (nothing new appears), and X with nothing unlocked SAVES —
	# so X can never, ever conjure up an unwanted A. Circle erases.
	var t := name_edit.text
	match btn:
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			if not _pad_editing:
				if t.length() < name_edit.max_length:
					name_edit.text = t + "A"
					_pad_editing = true
			else:
				var dir := 1 if btn == JOY_BUTTON_DPAD_UP else -1
				var i := NAME_CHARS.find(t[-1])
				name_edit.text = t.left(t.length() - 1) + NAME_CHARS[wrapi(i + dir, 0, NAME_CHARS.length())]
		JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_START:
			if _pad_editing:
				_pad_editing = false           # letter locked in
			else:
				_on_name_submitted()           # nothing pending — save
		JOY_BUTTON_B, JOY_BUTTON_DPAD_LEFT:
			name_edit.text = t.left(t.length() - 1)
			_pad_editing = false

func _nudge_difficulty(dir: int) -> void:
	if state != STATE_MENU:
		return
	difficulty = clampi(difficulty + dir, 0, DIFF_NAMES.size() - 1)
	_refresh_diff_label()

func _toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _primary_action() -> void:
	match state:
		STATE_MENU:
			_start_game()
		STATE_PLAY:
			_flap()
		STATE_DEAD:
			if entering_name:
				# don't swallow the press — bank the name (empty → JONK)
				# and get straight back into the game
				_on_name_submitted()
			_goto_menu()
			_start_game()

func _on_name_submitted(_t := "") -> void:
	if not entering_name:
		return  # already saved — no double entries from eager fingers
	var nm := name_edit.text.strip_edges().to_upper()
	if nm == "":
		nm = FRIEND.name
	_save_score(nm, score)
	entering_name = false
	name_row.visible = false
	name_edit.release_focus()
	hint_label.text = "SPACE / CLICK TO PLAY AGAIN"
	_refresh_scores_label(gameover_scores)

func _on_name_gui_input(event: InputEvent) -> void:
	# arcade names don't have spaces — SPACE in the name field means
	# "save and play again", so one press always restarts
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		name_edit.accept_event()
		_on_name_submitted()
		_goto_menu()
		_start_game()

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

	# death rattle: a short decaying camera shake
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		var s := _shake * _shake * 0.5
		cam.h_offset = randf_range(-s, s)
		cam.v_offset = randf_range(-s, s)
	elif cam.h_offset != 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

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
		_animate_card(delta, tsec)
		return

	if state != STATE_PLAY:
		return

	# the pilot: aim for the center of the next gap, flap when the next
	# split second would carry us below it (drives --shot/--play modes and
	# the secret in-game cheat)
	if _shot_dir != "" or _play_dir != "" or _cheat_pilot:
		_pilot_flew = true
		pilot_label.visible = _cheat_pilot and int(Time.get_ticks_msec() / 300) % 3 != 0
		# physics-aware pilot: always aim for the NEXT gap's center, and let
		# two guards enforce the current pipe's safe band for exactly as
		# long as its collision window can still touch us — hold a flap
		# that would peak into the top pillar, force one if coasting would
		# sink below the bottom before we are clear.
		var a: Dictionary
		var b: Dictionary
		for i in range(pipes.size()):
			if pipes[i].x > HEAD_X - (PIPE_RADIUS + HEAD_RADIUS + 0.05):
				a = pipes[i]
				if i + 1 < pipes.size():
					b = pipes[i + 1]
				break
		var target := -0.8
		if not a.is_empty():
			target = (b.gap if not b.is_empty() else a.gap) - 0.8
		var want: bool = head.position.y < target and velocity_y < 0.0
		if not a.is_empty():
			var dx: float = a.x - HEAD_X
			var w := PIPE_RADIUS + HEAD_RADIUS + 0.05
			if dx > w:
				# approaching: bang-bang reachability. Flap at the last
				# moment max climb (avg FLAP_VELOCITY/2) still reaches the
				# band bottom by entry; hold once a flap's peak could no
				# longer be dived off before entry.
				var t_in: float = (dx - w) / speed
				if velocity_y < 0.0 and head.position.y + 0.5 * FLAP_VELOCITY * t_in < a.gap - 1.5:
					want = true
				var t_fall: float = maxf(0.0, t_in - FLAP_VELOCITY / GRAVITY)
				var drop: float = 0.5 * GRAVITY * t_fall * t_fall if t_fall < 0.73 else 5.8 - MAX_FALL * (t_fall - 0.73)
				if want and head.position.y + 1.68 - drop > a.gap + 1.7:
					want = false
			elif dx > -w:
				# inside the collision window: hard band rules
				var t_e: float = (dx + w) / speed
				var t_up: float = minf(t_e, FLAP_VELOCITY / GRAVITY)
				var rise: float = FLAP_VELOCITY * t_up - 0.5 * GRAVITY * t_up * t_up
				if want and head.position.y + rise > a.gap + 1.85:
					want = false
				if velocity_y < 0.0 and head.position.y < a.gap - 1.6:
					# bounce off the band floor — unless we can coast out
					# through what is left of the window before sinking
					# under it (a full-height bounce here is what used to
					# throw us into the NEXT pipe's top pillar)
					var t1: float = maxf(0.0, (velocity_y - MAX_FALL) / GRAVITY)
					var y_exit: float
					if t_e <= t1:
						y_exit = head.position.y + velocity_y * t_e - 0.5 * GRAVITY * t_e * t_e
					else:
						y_exit = head.position.y + velocity_y * t1 - 0.5 * GRAVITY * t1 * t1 + MAX_FALL * (t_e - t1)
					if y_exit < a.gap - 1.85:
						want = true
		if want:
			_flap()

	# arms flap on every flap — up fast, then settle
	_flap_pulse = max(0.0, _flap_pulse - 3.2 * delta)
	var wing := sin(minf(_flap_pulse, 1.0) * PI) * 1.9
	flap_arm_l.rotation.z = -wing
	flap_arm_r.rotation.z = wing

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
			# the can is a photo billboard now — sway, don't spin thin
			p.beer.rotation.z = 0.12 + sin(tsec * 3.0 + p.gap) * 0.18

		# scoring when a pipe passes the head
		if not p.passed and p.x < HEAD_X:
			p.passed = true
			score += 1
			score_label.text = str(score)

		# collision with pipe body
		if abs(p.x - HEAD_X) < (PIPE_RADIUS + HEAD_RADIUS):
			var half := pipe_gap / 2.0
			if head.position.y > p.gap + half - HEAD_RADIUS or head.position.y < p.gap - half + HEAD_RADIUS:
				if crash_sfx.stream != null:
					crash_sfx.play()   # the Pillars of Creation strike back
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
	if beer_sfx.stream != null:
		beer_sfx.play()
	score_label.text = str(score)
	_beer_pop(Vector3(p.x, p.gap, 0.2))
	p.beer.queue_free()
	p.beer = null

func _confetti() -> void:
	# a rain of little LEGO-colored plates for a new high score
	var colors := [
		Color(0.82, 0.12, 0.12), Color(1.0, 0.8, 0.1), Color(0.2, 0.4, 0.9),
		Color(0.2, 0.7, 0.3), Color(0.95, 0.95, 0.95), Color(0.95, 0.5, 0.1),
	]
	for i in range(44):
		var m := _add(_box(Vector3(0.18, 0.28, 0.02)), _mat(colors[i % colors.size()], 0.5),
			Vector3(randf_range(-4.5, 4.5), randf_range(8.5, 11.5), 6.0))
		m.rotation_degrees = Vector3(randf() * 360.0, randf() * 360.0, randf() * 360.0)
		var dur := randf_range(2.0, 3.4)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(m, "position:y", -8.5, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tw.tween_property(m, "position:x", m.position.x + randf_range(-1.6, 1.6), dur)
		tw.tween_property(m, "rotation", Vector3(randf() * 14.0, randf() * 14.0, randf() * 14.0), dur)
		tw.chain().tween_callback(m.queue_free)

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
	_refresh_scores_label(gameover_scores)
	hiscore_label.text = "HI-SCORE  0"
	_toast("HIGH SCORES CLEARED")

func _toast(msg: String) -> void:
	var t := _make_label(24, Color(1.0, 0.9, 0.4))
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
	var lines := ["- HIGH SCORES -", ""]
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
	# every UI label wears the title card's pixel font — one 16-bit look
	var l := Label.new()
	l.add_theme_font_override("font", retro_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	# live score (top center)
	score_label = _make_label(56)
	score_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_label.position.y = 40
	ui.add_child(score_label)

	# blinking tell-tale for the secret autopilot — no silent cheating
	pilot_label = _make_label(16, Color(1.0, 0.85, 0.3))
	pilot_label.text = "AUTOPILOT"
	pilot_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pilot_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pilot_label.position.y = 130
	pilot_label.visible = false
	ui.add_child(pilot_label)

	# (the menu is the 3D retro title card — no 2D title UI needed)

	# --- game over ---
	gameover_box = _panel()
	gameover_box.visible = false
	ui.add_child(gameover_box)
	var gv := VBoxContainer.new()
	gv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gv.alignment = BoxContainer.ALIGNMENT_CENTER
	gv.add_theme_constant_override("separation", 12)
	gameover_box.add_child(gv)
	gv.add_child(_center(_make_label(40, Color(1.0, 0.45, 0.38)), "GAME OVER"))
	final_label = _make_label(24)
	gv.add_child(_center(final_label, "SCORE 0"))
	gameover_scores = _make_label(16, Color(0.55, 0.76, 0.55))
	gv.add_child(_center(gameover_scores, ""))

	name_row = HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "YOUR NAME"
	name_edit.max_length = 10
	name_edit.custom_minimum_size = Vector2(280, 48)
	name_edit.add_theme_font_override("font", retro_font)
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.gui_input.connect(_on_name_gui_input)
	var save_btn := Button.new()
	save_btn.text = "SAVE"
	save_btn.add_theme_font_override("font", retro_font)
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.pressed.connect(_on_name_submitted)
	name_row.add_child(name_edit)
	name_row.add_child(save_btn)
	gv.add_child(_center_control(name_row))

	hint_label = _make_label(16, Color(0.8, 1.0, 0.85))
	gv.add_child(_center(hint_label, ""))

func _panel() -> Control:
	# just enough dark for the text to pop — space stays the backdrop
	var p := ColorRect.new()
	p.color = Color(0.02, 0.03, 0.08, 0.3)
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
