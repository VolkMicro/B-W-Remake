extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	if f == null:
		quit(1)
		return
	f.store_string("Godot Engine\n\n" + Engine.get_license_text())
	f.store_string("\n\nBundled third-party copyright notices\n\n" + JSON.stringify(Engine.get_copyright_info(), "  "))
	f.store_string("\n\nThird-party licenses\n\n" + JSON.stringify(Engine.get_license_info(), "  "))
	f.close()
	quit()
