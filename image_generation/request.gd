extends RefCounted
## One PNG + prompt; intentionally no provider, key, level, or filesystem path.
var image: Image
var prompt := ""
var timeout_seconds := 60.0

func _init(source: Image = null, instruction: String = "") -> void:
	image = source
	prompt = instruction
