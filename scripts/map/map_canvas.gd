extends Control

# Fond de la carte : trame de points discrète et chemins entre les zones.
# Les marqueurs de zone sont des enfants dessinés par-dessus.

const DOT_SPACING := 40.0
const DOT_COLOR := Color(1, 1, 1, 0.05)
const PATH_OPEN := Color(0.93, 0.82, 0.55, 0.75)
const PATH_LOCKED := Color(1, 1, 1, 0.16)

# [[position_a, position_b, ouvert], ...] en coordonnées de la carte.
var paths: Array = []


func set_paths(new_paths: Array) -> void:
	paths = new_paths
	queue_redraw()


func _draw() -> void:
	var x := DOT_SPACING * 0.5

	while x < size.x:
		var y := DOT_SPACING * 0.5

		while y < size.y:
			draw_circle(Vector2(x, y), 1.5, DOT_COLOR)
			y += DOT_SPACING

		x += DOT_SPACING

	# Les chemins verrouillés en pointillés, les chemins ouverts par-dessus.
	for path in paths:
		if not path[2]:
			draw_dashed_line(path[0], path[1], PATH_LOCKED, 2.0, 8.0, true, true)

	for path in paths:
		if path[2]:
			draw_line(path[0], path[1], PATH_OPEN, 3.0, true)
