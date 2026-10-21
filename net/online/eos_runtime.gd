extends Node
## Stand-in for EOSG's runtime autoload, registered as `EOSGRuntime`: the
## plugin's option classes read `EOSGRuntime.local_product_user_id`, and EOS
## needs ticking every frame. Unlike the plugin's own runtime.gd it never
## names the IEOS singleton directly, so builds without the extension (web)
## load it cleanly.

var local_product_user_id: String = ""
var local_epic_account_id: String = ""

var _ieos: Object = null


func _ready() -> void:
	if Engine.has_singleton("IEOS"):
		_ieos = Engine.get_singleton("IEOS")
	set_process(_ieos != null)


func _process(_delta: float) -> void:
	_ieos.call("tick")
