extends SceneTree
# Renders the in-game pixel-Jonk sprite to the boot-splash PNGs:
#
#   godot --headless -s tools/make_splash.gd
#
# splash.png    (4x) — Godot boot splash + iOS launch storyboard @2x
# splash_3x.png (6x) — iOS launch storyboard @3x
# Integer scales only: anything else smears the pixel art.

func _initialize() -> void:
	var m: Object = (load("res://Main.gd") as GDScript).new()
	var img: Image = m._jonk_image()
	m.free()
	for out in [["res://splash.png", 4], ["res://splash_3x.png", 6]]:
		var s: Image = img.duplicate()
		s.resize(img.get_width() * out[1], img.get_height() * out[1], Image.INTERPOLATE_NEAREST)
		s.save_png(out[0])
		print("wrote %s (%dx%d)" % [out[0], s.get_width(), s.get_height()])
	quit()
