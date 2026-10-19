extends "res://content/quanzhou_boat/boat_play.gd"
func _ready() -> void:
	super._ready()
	_audit.call_deferred()

func _audit() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/quanzhou_boat/reference/assembly_manifest.json"))
	var records: Array = []
	for entry in manifest.assemblies:
		var root := boat.find_child(entry.id,true,false)
		var meshes: Array = []
		var box := AABB()
		var first := true
		for mesh in _meshes(root):
			var world_box: AABB = mesh.global_transform*mesh.get_aabb()
			box = world_box if first else box.merge(world_box)
			first = false
			var p := world_box.get_center()
			meshes.append({"name":str(mesh.name),"center":[p.x,p.y,p.z],"min":[world_box.position.x,world_box.position.y,world_box.position.z],"size":[world_box.size.x,world_box.size.y,world_box.size.z]})
		var p := box.get_center()
		records.append({"root":entry.id,"label":entry.label,"count":meshes.size(),"center":[p.x,p.y,p.z],"min":[box.position.x,box.position.y,box.position.z],"size":[box.size.x,box.size.y,box.size.z],"meshes":meshes})
	var f := FileAccess.open("res://content/quanzhou_boat/evidence/connected_groups/source_geometry.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(records,"\t"))
	get_tree().quit()
