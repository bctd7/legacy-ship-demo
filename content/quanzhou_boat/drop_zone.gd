extends Control
## Screen-space presentation only; the existing drag contract owns acceptance.
var centers: Array[Vector2] = []
var radii: Array[float] = []
var near := false

func show_regions(points: Array[Vector2], sizes: Array[float], valid: bool) -> void:
	centers = points
	radii = sizes
	near = valid
	queue_redraw()

func _draw() -> void:
	var color := Color("527b50") if near else Color("ae874b")
	for index in centers.size():
		draw_circle(centers[index],radii[index],Color(color,0.035))
		draw_arc(centers[index],radii[index],0,TAU,64,Color(color,0.6),1.2,true)
