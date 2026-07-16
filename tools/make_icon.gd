extends SceneTree
# Renders the app icon from the in-game pixel-Jonk sprite:
#
#   godot --headless -s tools/make_icon.gd
#
# icon_ios.png     1024x1024, OPAQUE, square — App Store validation rejects
#                  alpha in the marketing icon, and iOS rounds the corners
#                  itself (baked corners double-round into dark artifacts).
# FlappyJonk.icns  macOS icon — same art inset with margin and rounded
#                  corners, the Big Sur convention.
#
# The scene: Jonk stands on the martian plain under a starfield, bäär
# raised. Same art language as the splash and the game itself.

const SIZE := 1024
const GROUND_H := 176

func _initialize() -> void:
	var m: Object = (load("res://Main.gd") as GDScript).new()
	var jonk: Image = m._jonk_image()
	m.free()

	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	# night-space gradient, subtly lighter up top
	for y in range(SIZE):
		var t := float(y) / SIZE
		var c := Color(0.05, 0.07, 0.16).lerp(Color(0.015, 0.02, 0.06), t)
		for x in range(SIZE):
			img.set_pixel(x, y, c)

	# deterministic starfield, denser along a loose diagonal band
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in range(240):
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - GROUND_H - 8)
		var band: float = clampf(1.4 - absf((y - (SIZE * 0.62 - x * 0.25))) / 260.0, 0.25, 1.0)
		if rng.randf() > band:
			continue
		var s := 2 + (rng.randi() % 3) * 2   # 2/4/6 px — chunky pixel stars
		var a := rng.randf_range(0.35, 1.0) * band
		var col := Color(1, 1, 1, a) if rng.randf() > 0.2 else Color(0.85, 0.9, 1.0, a)
		for dy in range(s):
			for dx in range(s):
				if x + dx < SIZE and y + dy < SIZE:
					var base := img.get_pixel(x + dx, y + dy)
					img.set_pixel(x + dx, y + dy, base.lerp(Color(col.r, col.g, col.b, 1.0), col.a))

	# the martian plain: rust bands, brightest at the horizon line
	for y in range(SIZE - GROUND_H, SIZE):
		var t := float(y - (SIZE - GROUND_H)) / GROUND_H
		var c := Color(0.62, 0.33, 0.20).lerp(Color(0.38, 0.18, 0.11), t)
		if y == SIZE - GROUND_H:
			c = Color(0.72, 0.42, 0.28)   # sunlit horizon edge
		for x in range(SIZE):
			img.set_pixel(x, y, c)

	# Jonk, feet planted on the plain (6x nearest = crisp pixels)
	var s6 := jonk.duplicate() as Image
	s6.resize(jonk.get_width() * 6, jonk.get_height() * 6, Image.INTERPOLATE_NEAREST)
	var jx := (SIZE - s6.get_width()) / 2
	var jy := SIZE - GROUND_H - s6.get_height() + 30   # feet sink slightly in
	img.blend_rect(s6, Rect2i(0, 0, s6.get_width(), s6.get_height()), Vector2i(jx, jy))

	# --- iOS: opaque square ---
	var ios := img.duplicate() as Image
	ios.convert(Image.FORMAT_RGB8)
	ios.save_png("res://icon_ios.png")
	print("wrote res://icon_ios.png (opaque: ", not ios.detect_alpha(), ")")

	# --- macOS: inset + rounded corners (Big Sur style), then .icns ---
	var mac := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	mac.fill(Color(0, 0, 0, 0))
	var margin := 100
	var box := SIZE - margin * 2
	var scaled := img.duplicate() as Image
	scaled.resize(box, box, Image.INTERPOLATE_LANCZOS)
	var r := 186.0   # Apple's squircle radius at this content size, near enough
	for y in range(box):
		for x in range(box):
			var nx: float = clampf(x, r, box - r)
			var ny: float = clampf(y, r, box - r)
			var d := Vector2(x - nx, y - ny).length()
			var a: float = clampf(r - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				var p := scaled.get_pixel(x, y)
				p.a = a
				mac.set_pixel(x + margin, y + margin, p)

	var iconset := "res://build/mac.iconset"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(iconset))
	for sz in [16, 32, 128, 256, 512]:
		for mult in [1, 2]:
			var px: int = sz * mult
			var out := mac.duplicate() as Image
			out.resize(px, px, Image.INTERPOLATE_LANCZOS)
			var suffix := "@2x" if mult == 2 else ""
			out.save_png("%s/icon_%dx%d%s.png" % [iconset, sz, sz, suffix])
	print("iconset written — run iconutil to produce FlappyJonk.icns")
	quit()
