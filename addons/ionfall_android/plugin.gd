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
