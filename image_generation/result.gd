extends RefCounted
var ok := false
var image: Image
var error: Dictionary = {}

static func failure(code: String, message: String, status: int = 0, unknown: bool = false):
	var value = load("res://image_generation/result.gd").new()
	value.error = {"code": code, "message": message, "http_status": status,
		"outcome_unknown": unknown, "automatic_retry": false}
	return value

static func success(output: Image):
	var value = load("res://image_generation/result.gd").new()
	value.ok = true
	value.image = output
	return value
