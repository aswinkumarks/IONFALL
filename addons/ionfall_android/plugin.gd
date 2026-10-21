@tool
extends EditorPlugin
## Android export additions that Godot's export presets can't express.

var _export_plugin: ExportPlugin


func _enter_tree() -> void:
	_export_plugin = ExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class ExportPlugin:
	extends EditorExportPlugin

	func _get_name() -> String:
		return "IonfallAndroid"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	## Join links: ionfall://join?host=…&port=… open the game (PLAN §3.6).
	## Platform.take_join_link() reads the intent's data.
	func _get_android_manifest_activity_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return """
			<intent-filter>
				<action android:name="android.intent.action.VIEW" />
				<category android:name="android.intent.category.DEFAULT" />
				<category android:name="android.intent.category.BROWSABLE" />
				<data android:scheme="ionfall" android:host="join" />
			</intent-filter>
"""

	# --- Epic Online Services (decision 0005) ---
	# EOSG's manual steps for Android, done at export time so the generated
	# build template (android/, not committed) never needs hand edits.

	const EOS_AAR := "res://addons/epic-online-services-godot/bin/android/eossdk-StaticSTDC-release.aar"
	const EOS_CREDENTIALS := "res://eos_credentials.cfg"
	const MARK := "IONFALL-EOS"

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		# Relative to res://addons/ (EditorExportPlugin docs).
		return PackedStringArray([EOS_AAR.trim_prefix("res://addons/")]) if FileAccess.file_exists(EOS_AAR) else PackedStringArray()

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if not FileAccess.file_exists(EOS_AAR):
			return PackedStringArray()
		return PackedStringArray(["androidx.appcompat:appcompat:1.5.1",
				"androidx.constraintlayout:constraintlayout:2.1.4", "androidx.security:security-crypto:1.0.0",
				"androidx.browser:browser:1.4.0", "androidx.webkit:webkit:1.7.0"])

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if not FileAccess.file_exists(EOS_AAR):
			return
		# The EOS SDK's manifest needs its login redirect scheme.
		var cfg := ConfigFile.new()
		var client_id := ""
		if cfg.load(EOS_CREDENTIALS) == OK:
			client_id = str(cfg.get_value("eos", "client_id", "")).to_lower()
		_patch("res://android/build/build.gradle", "        missingDimensionStrategy 'products', 'template'\n",
				"        missingDimensionStrategy 'products', 'template'\n        // %s\n        resValue('string', 'eos_login_protocol_scheme', 'eos.%s')\n" % [MARK, client_id])
		# The EOS SDK AAR requires core library desugaring.
		_patch("res://android/build/build.gradle", "        targetCompatibility versions.javaVersion\n",
				"        targetCompatibility versions.javaVersion\n        coreLibraryDesugaringEnabled true // %s\n" % MARK)
		_patch("res://android/build/build.gradle", "dependencies {\n",
				"dependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4' // %s\n" % MARK)
		# The EOS SDK loads its native library and needs the activity first.
		var java := "res://android/build/src/main/java/com/godot/game/GodotApp.java"
		_patch(java, "import android.os.Bundle;\n",
				"import android.os.Bundle;\nimport com.epicgames.mobile.eossdk.EOSSDK; // %s\n" % MARK)
		_patch(java, "public class GodotApp extends GodotActivity {\n",
				"public class GodotApp extends GodotActivity {\n\tstatic { System.loadLibrary(\"EOSSDK\"); } // %s\n" % MARK)
		_patch(java, "\t\tEdgeToEdge.enable(this);\n",
				"\t\tEdgeToEdge.enable(this);\n\t\tEOSSDK.init(this); // %s\n" % MARK)

	## Inserts `replacement` in place of `anchor` once (idempotent via the
	## marker on the inserted line).
	func _patch(path: String, anchor: String, replacement: String) -> void:
		var text := FileAccess.get_file_as_string(path)
		var marked_line := replacement.trim_prefix(anchor).strip_edges()
		if text.is_empty() or text.contains(marked_line):
			return
		if not text.contains(anchor):
			push_error("IonfallAndroid: can't patch %s for EOS (anchor not found)" % path)
			return
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text.replace(anchor, replacement))
