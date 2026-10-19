extends "res://content/quanzhou_boat/boat_play.gd"
func _ready() -> void:
	super._ready()
	_audit.call_deferred()

func _audit() -> void:
	var report: Array = []
	for group in groups:
		var id: String = group.id
		var g := _group(id)
		var part_names: Array[String] = []
		for mesh in _part_meshes(id): part_names.append(str(mesh.name))
		var records: Array = []
		for root in group_nodes[id]:
			for mesh in _meshes(root):
				var materials: Array = []
				for surface in mesh.mesh.get_surface_count():
					var source := mesh.mesh.surface_get_material(surface)
					var restored := mesh.get_active_material(surface)
					materials.append({"source_name":source.resource_name if source else "","source_class":source.get_class() if source else "","source_albedo_texture":source.albedo_texture!=null if source is StandardMaterial3D else false,"active_class":restored.get_class() if restored else "","active_shader":restored.shader.resource_path if restored is ShaderMaterial else ""})
				records.append({"root":str(root.name),"mesh":str(mesh.name),"source_path":str(boat.get_path_to(mesh)),"world_aabb":str(mesh.global_transform*mesh.get_aabb()),"in_preview":str(mesh.name) in part_names,"materials":materials})
		report.append({"id":id,"card_label":g.label,"roots":g.roots,"canonical_meshes":part_names,"connection_meshes":g.connection_meshes,"install_mesh_count":records.size(),"preview_count":part_names.size(),"meshes":records,"asset":"res://content/quanzhou_boat/assets/quanzhou_complete.glb"})
	var f := FileAccess.open("res://content/quanzhou_boat/evidence/tolerance_zoom/all_group_mapping_after.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	for entry in report: print(entry.id," preview=",entry.preview_count," installed=",entry.install_mesh_count," roots=",entry.roots)
	get_tree().quit()
