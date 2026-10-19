extends RefCounted
## Protocol: encode(snapshot) -> {wire} or {failure}; decode(status, body) -> Result.
## snapshot contains png: PackedByteArray, prompt: String. Never mutate it.
const Result = preload("res://image_generation/result.gd")

func encode(_snapshot: Dictionary) -> Dictionary:
	return {"failure": Result.failure("configuration", "A generation provider is required.")}

func decode(_status: int, _body: PackedByteArray):
	return Result.failure("configuration", "Provider decoder is not implemented.")
