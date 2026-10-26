extends SceneTree
## Renders every sound of the game into audio/*.wav (see sfx.gd). Run after changing a sound:
##   godot --headless --path . -s tools/render_audio.gd
## then open the editor (or run with --import) so the new files are imported.

func _init() -> void:
	var sfx = load("res://sfx.gd").new()
	var dir := ProjectSettings.globalize_path("res://audio/")
	DirAccess.make_dir_recursive_absolute(dir)
	var t := Time.get_ticks_msec()
	sfx.render_all(dir)
	print("rendered audio into %s in %.1f s" % [dir, (Time.get_ticks_msec() - t) / 1000.0])
	sfx.free()
	quit()
