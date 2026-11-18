extends SceneTree
# Launcher-only environment diagnostic. Does not open, erase or reset saves.
func _initialize():
	print("HOSTCHECK_APPDATA=", OS.get_environment("APPDATA"))
	print("HOSTCHECK_LOCALAPPDATA=", OS.get_environment("LOCALAPPDATA"))
	print("HOSTCHECK_USER_DIR=", OS.get_user_data_dir())
	print("HOSTCHECK_GLOBAL_USER=", ProjectSettings.globalize_path("user://"))
	var expected = OS.get_environment("KURO_EXPECTED_USER_DIR").replace("\\", "/").simplify_path()
	var actual = OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if expected.is_empty() or actual.to_lower() != expected.to_lower():
		print("HOSTCHECK_MATCH=false")
		quit(2)
		return
	print("HOSTCHECK_MATCH=true")
	# Only inspect this verified private directory, never a default or fallback location.
	var config = ConfigFile.new()
	var count = 0
	if config.load("user://progress.cfg") == OK and config.has_section("builtin"):
		for key in config.get_section_keys("builtin"):
			if key.is_valid_int() and int(config.get_value("builtin", key, -1)) >= 0:
				count += 1
	print("HOSTCHECK_RECORDED_ENTRIES=", count)
	quit()
