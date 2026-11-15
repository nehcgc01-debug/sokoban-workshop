extends SceneTree
const Progress = preload("res://progress_store.gd")
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, message):
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS ", message)
func write(text: String):
	var f = FileAccess.open(Progress.PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()
func run():
	var broken = "1=3\n[builtin]\n"
	check(not Progress._looks_healthy(broken.to_utf8_buffer()), "key before builtin header is rejected")
	check(not Progress._looks_healthy(" \n 1 = 3 \n [builtin] \n".to_utf8_buffer()), "whitespace does not hide misplaced record")
	write(broken)
	check(Progress.record(2, 10) == ERR_FILE_CORRUPT, "record refuses malformed existing progress")
	check(FileAccess.get_file_as_string(Progress.PATH) == broken, "refused write preserves exact original bytes")
	var note = Progress.check_integrity()
	check(note.contains("另存"), "integrity check gives player a recovery notice")
	check(not FileAccess.file_exists(Progress.PATH) and FileAccess.get_file_as_string(Progress.PATH + ".corrupt") == broken, "malformed progress moved aside without altering bytes")
	var old = "[builtin]\n\n1=3\n2=10\n6=14\n7=19\n"
	write(old)
	check(Progress.check_integrity().is_empty(), "valid old seven-level progress needs no recovery")
	check(Progress.best_moves(1) == 3 and Progress.best_moves(6) == 14 and Progress.best_moves(7) == 19, "old stable IDs and best moves stay intact")
	check(Progress.record(11, 31) == OK and Progress.best_moves(11) == 31 and Progress.best_moves(6) == 14, "new level can be added without losing old records")
	check(Progress._looks_healthy(FileAccess.get_file_as_bytes(Progress.PATH)), "normal ConfigFile serialization remains healthy")
	check(Progress._looks_healthy("[builtin]\r\n1=3\r\n".to_utf8_buffer()), "Windows CRLF progress stays compatible")
	check(Progress._looks_healthy(PackedByteArray()) and Progress._looks_healthy("[builtin]\n".to_utf8_buffer()), "existing empty-file and empty-section behavior preserved")
	print("PROGRESS ORDER TESTS: %d/12" % checks)
	quit(1 if failures else 0)
