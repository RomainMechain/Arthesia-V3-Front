extends Control

# Vignette illustrée d'une zone, peinte en code comme une enluminure : un ciel
# d'aube, un paysage selon le type de zone (village, forêt, eaux, camp, ruines,
# lieu dangereux, antre du boss, passage), un cadre doré, le nom de la zone en
# lettres gravées et quelques grains de lumière. Le tirage des détails dépend
# de l'id de la zone : une zone garde toujours la même vignette.
#
#     var banner = ZONE_BANNER.new()
#     banner.setup(zone)        # zone : {id, name, type}
#     parent.add_child(banner)

const HEIGHT := 150.0
const FRAME := UiStyle.COLOR_GOLD

# Ciel de chaque type : [haut, milieu, horizon].
const SKIES := {
	"default": [Color(0.24, 0.15, 0.26), Color(0.62, 0.36, 0.38), Color(0.98, 0.76, 0.46)],
	"danger": [Color(0.1, 0.08, 0.12), Color(0.25, 0.18, 0.24), Color(0.48, 0.4, 0.32)],
	"boss": [Color(0.16, 0.06, 0.06), Color(0.42, 0.14, 0.1), Color(0.9, 0.42, 0.22)],
	"passage": [Color(0.1, 0.07, 0.2), Color(0.3, 0.2, 0.45), Color(0.72, 0.58, 0.85)],
}

var zone_type := "wilderness"
var zone_name := ""
var rng := RandomNumberGenerator.new()
var base_seed := 0
var title_label: Label
var motes: CPUParticles2D


func setup(zone: Dictionary, show_name := true) -> void:
	zone_type = str(zone.get("type", "wilderness"))
	zone_name = str(zone.get("name", "")) if show_name else ""
	base_seed = hash(str(zone.get("id", zone_name)))
	custom_minimum_size = Vector2(0, HEIGHT)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_motes()
	resized.connect(_on_resized)

	if not zone_name.is_empty():
		title_label = Label.new()
		title_label.text = zone_name
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		title_label.offset_top = -40
		title_label.offset_bottom = -8
		title_label.add_theme_font_size_override("font_size", 19)
		title_label.add_theme_constant_override("outline_size", 6)
		title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		UiStyle.make_title(title_label)
		add_child(title_label)


func add_motes() -> void:
	motes = CPUParticles2D.new()
	motes.amount = 14
	motes.lifetime = 6.0
	motes.preprocess = 6.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(180, 70)
	motes.position = Vector2(170, 80)
	motes.direction = Vector2(0.2, -1)
	motes.spread = 30.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 3.0
	motes.initial_velocity_max = 9.0
	motes.scale_amount_min = 1.2
	motes.scale_amount_max = 2.4
	var glow := Color(0.85, 0.75, 1.0) if zone_type == "passage" else (Color(1.0, 0.55, 0.35) if zone_type == "boss" else Color(1.0, 0.86, 0.55))
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.3, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(glow, 0.0), Color(glow, 0.7), Color(glow, 0.45), Color(glow, 0.0)])
	motes.color_ramp = fade
	add_child(motes)


func _on_resized() -> void:
	motes.position = size / 2.0
	motes.emission_rect_extents = size / 2.0


func _draw() -> void:
	var w := size.x
	var h := size.y
	var horizon := h * 0.6
	rng.seed = base_seed  # même tirage à chaque redessin : la vignette ne change pas

	draw_sky(w, horizon)

	match zone_type:
		"town":
			draw_hills(horizon + 6, 18.0, Color(0.32, 0.22, 0.2))
			draw_houses(horizon + 16, w)
			draw_ground(horizon + 34, Color(0.16, 0.11, 0.09))
		"water":
			draw_hills(horizon - 6, 14.0, Color(0.28, 0.22, 0.28))
			draw_water(horizon, w, h)
			draw_reeds(w, h)
		"camp":
			draw_hills(horizon - 4, 16.0, Color(0.3, 0.22, 0.25))
			draw_water(horizon + 8, w, h)
			draw_tents(horizon + 26, w)
		"ruins":
			draw_hills(horizon + 4, 22.0, Color(0.3, 0.22, 0.24))
			draw_ruins(horizon + 22, w)
			draw_ground(horizon + 36, Color(0.15, 0.11, 0.1))
		"danger":
			draw_hills(horizon - 2, 26.0, Color(0.14, 0.12, 0.15))
			draw_dead_trees(horizon + 30, w)
			draw_fog(horizon + 10, w)
			draw_ground(horizon + 40, Color(0.07, 0.06, 0.07))
		"boss":
			draw_hills(horizon + 6, 20.0, Color(0.2, 0.08, 0.07))
			draw_gate(Vector2(w / 2, horizon + 30))
			draw_ground(horizon + 34, Color(0.1, 0.05, 0.04))
		"passage":
			draw_hills(horizon + 8, 18.0, Color(0.16, 0.12, 0.25))
			draw_portal(Vector2(w / 2, horizon - 6))
			draw_ground(horizon + 34, Color(0.08, 0.06, 0.12))
		_:
			draw_forest(horizon, w)

	# Voile sombre en bas, pour la lisibilité du nom.
	var veil := PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55)])
	draw_polygon(PackedVector2Array([Vector2(0, h * 0.55), Vector2(w, h * 0.55), Vector2(w, h), Vector2(0, h)]), veil)
	draw_frame(w, h)


# --- Ciel, relief, sol -------------------------------------------------------------

func draw_sky(w: float, horizon: float) -> void:
	var sky: Array = SKIES.get(zone_type, SKIES.default)
	var middle := horizon * 0.55
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, middle), Vector2(0, middle)]),
		PackedColorArray([sky[0], sky[0], sky[1], sky[1]]))
	draw_polygon(PackedVector2Array([Vector2(0, middle), Vector2(w, middle), Vector2(w, size.y), Vector2(0, size.y)]),
		PackedColorArray([sky[1], sky[1], sky[2], sky[2]]))

	# Le soleil de l'aube éternelle, à moitié levé, et son halo.
	var sun := Vector2(w * rng.randf_range(0.25, 0.75), horizon - 4)
	var glow: Color = sky[2]

	for step in 6:
		draw_circle(sun, 46.0 - step * 6.0, Color(glow.lightened(0.2), 0.08))

	if zone_type not in ["danger", "passage"]:
		draw_circle(sun, 15.0, Color(1.0, 0.92, 0.7, 0.9))


func ridge(base_y: float, amplitude: float, step: float = 12.0) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(0, size.y)])
	var phase := rng.randf() * TAU
	var x := 0.0

	while x <= size.x + step:
		var y := base_y - amplitude * (0.5 + 0.5 * sin(x * 0.018 + phase)) - rng.randf() * amplitude * 0.3
		points.append(Vector2(x, y))
		x += step

	points.append(Vector2(size.x, size.y))
	return points


func draw_hills(base_y: float, amplitude: float, color: Color) -> void:
	draw_colored_polygon(ridge(base_y, amplitude, 16.0), color)


func draw_ground(top: float, color: Color) -> void:
	draw_rect(Rect2(0, top, size.x, size.y - top), color)


func tree(base: Vector2, height: float, color: Color) -> void:
	var half := height * 0.32
	draw_colored_polygon(PackedVector2Array([base + Vector2(0, -height), base + Vector2(half, 0), base + Vector2(-half, 0)]), color)


func draw_forest(horizon: float, w: float) -> void:
	# Trois plans de sapins, du plus lointain (brumeux) au plus proche (sombre).
	var layers := [[horizon + 4, 26.0, Color(0.35, 0.27, 0.3)], [horizon + 22, 38.0, Color(0.18, 0.2, 0.15)], [horizon + 48, 54.0, Color(0.08, 0.1, 0.07)]]

	for layer in layers:
		var x := -10.0

		while x < w + 20:
			tree(Vector2(x, layer[0]), layer[1] * rng.randf_range(0.75, 1.2), layer[2])
			x += layer[1] * rng.randf_range(0.35, 0.6)

		draw_rect(Rect2(0, layer[0] - 1, w, size.y), layer[2])


func draw_houses(base_y: float, w: float) -> void:
	var x := rng.randf_range(10, 40)

	while x < w - 30:
		var house_w := rng.randf_range(22, 34)
		var house_h := rng.randf_range(16, 24)
		var color := Color(0.12, 0.08, 0.07)
		draw_rect(Rect2(x, base_y - house_h, house_w, house_h + 20), color)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 4, base_y - house_h), Vector2(x + house_w + 4, base_y - house_h), Vector2(x + house_w / 2, base_y - house_h - 14)]), color)
		# Fenêtre éclairée.
		draw_rect(Rect2(x + house_w / 2 - 3, base_y - house_h / 2 - 3, 6, 6), Color(1.0, 0.78, 0.4, 0.95))
		x += house_w + rng.randf_range(14, 34)


func draw_water(horizon: float, w: float, h: float) -> void:
	draw_polygon(PackedVector2Array([Vector2(0, horizon), Vector2(w, horizon), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(0.5, 0.42, 0.5), Color(0.5, 0.42, 0.5), Color(0.1, 0.14, 0.2), Color(0.1, 0.14, 0.2)]))

	# Reflets du soleil : traits clairs sur l'eau.
	for i in 14:
		var y := horizon + 4 + i * (h - horizon) / 14.0
		var length := rng.randf_range(10, 40) * (1.0 - i / 18.0)
		var x := w * rng.randf_range(0.3, 0.7)
		draw_line(Vector2(x - length, y), Vector2(x + length, y), Color(1.0, 0.85, 0.6, 0.35 - i * 0.02), 1.5)


func draw_reeds(w: float, h: float) -> void:
	for i in 26:
		var x := rng.randf_range(0, w * 0.3) if i % 2 == 0 else rng.randf_range(w * 0.72, w)
		var height := rng.randf_range(16, 38)
		var lean := rng.randf_range(-5, 5)
		draw_line(Vector2(x, h), Vector2(x + lean, h - height), Color(0.08, 0.09, 0.06), 1.6)


func draw_tents(base_y: float, w: float) -> void:
	for i in 3:
		var x := w * (0.22 + i * 0.26) + rng.randf_range(-12, 12)
		var tent_h := rng.randf_range(22, 30)
		draw_colored_polygon(PackedVector2Array([Vector2(x, base_y - tent_h), Vector2(x + tent_h * 0.85, base_y), Vector2(x - tent_h * 0.85, base_y)]), Color(0.18, 0.12, 0.08))

	# Le feu de camp et sa lueur.
	var fire := Vector2(w * 0.5, base_y + 6)

	for step in 5:
		draw_circle(fire, 26.0 - step * 5.0, Color(1.0, 0.55, 0.2, 0.1))

	draw_colored_polygon(PackedVector2Array([fire + Vector2(-5, 0), fire + Vector2(0, -12), fire + Vector2(5, 0)]), Color(1.0, 0.75, 0.3))
	draw_rect(Rect2(0, base_y + 2, w, size.y), Color(0.12, 0.09, 0.07))


func draw_ruins(base_y: float, w: float) -> void:
	var color := Color(0.14, 0.11, 0.11)
	var x := rng.randf_range(8, 30)

	while x < w - 20:
		var column_h := rng.randf_range(20, 56)
		draw_rect(Rect2(x, base_y - column_h, 10, column_h + 20), color)
		draw_rect(Rect2(x - 3, base_y - column_h - 3, 16, 4), color)

		# Une arche entre deux colonnes, parfois.
		if rng.randf() < 0.35:
			draw_arc(Vector2(x + 26, base_y - column_h + 2), 21, PI, TAU, 16, color, 5.0)

		x += rng.randf_range(32, 58)


func draw_dead_trees(base_y: float, w: float) -> void:
	var color := Color(0.05, 0.045, 0.06)

	for i in 6:
		var x := w * (i + 0.5) / 6.0 + rng.randf_range(-14, 14)
		var height := rng.randf_range(40, 70)
		var top := Vector2(x, base_y - height)
		draw_line(Vector2(x, base_y), top, color, 3.0)

		for branch in 3:
			var at := Vector2(x, base_y - height * rng.randf_range(0.4, 0.9))
			var side := -1.0 if branch % 2 == 0 else 1.0
			draw_line(at, at + Vector2(side * rng.randf_range(10, 20), -rng.randf_range(8, 16)), color, 1.8)


func draw_fog(y: float, w: float) -> void:
	for i in 5:
		draw_circle(Vector2(w * rng.randf(), y + rng.randf_range(-6, 16)), rng.randf_range(30, 60), Color(0.55, 0.5, 0.6, 0.08))


func draw_gate(base: Vector2) -> void:
	var color := Color(0.09, 0.04, 0.03)
	draw_rect(Rect2(base.x - 46, base.y - 70, 18, 74), color)
	draw_rect(Rect2(base.x + 28, base.y - 70, 18, 74), color)
	draw_arc(Vector2(base.x, base.y - 70), 37, PI, TAU, 20, color, 18.0)

	# Cercle de runes rougeoyant dans l'ouverture.
	var center := Vector2(base.x, base.y - 40)

	for step in 5:
		draw_circle(center, 30.0 - step * 5.0, Color(1.0, 0.35, 0.15, 0.08))

	draw_arc(center, 18, 0, TAU, 28, Color(1.0, 0.55, 0.3, 0.85), 1.5)

	for i in 6:
		var direction := Vector2.from_angle(i * TAU / 6)
		draw_line(center + direction * 12, center + direction * 22, Color(1.0, 0.6, 0.35, 0.8), 1.4)


func draw_portal(center: Vector2) -> void:
	for step in 6:
		draw_circle(center, 44.0 - step * 7.0, Color(0.75, 0.6, 1.0, 0.07))

	var points := PackedVector2Array()

	for i in 60:
		points.append(center + Vector2.from_angle(i * 0.32) * (1.0 + i * 0.55))

	draw_polyline(points, Color(0.9, 0.82, 1.0, 0.85), 1.6, true)


func draw_frame(w: float, h: float) -> void:
	var rect := Rect2(Vector2(1, 1), Vector2(w - 2, h - 2))
	draw_rect(rect, FRAME, false, 2.0)
	draw_rect(rect.grow(-5), Color(FRAME, 0.45), false, 1.0)

	for corner in [Vector2(5, 5), Vector2(w - 5, 5), Vector2(w - 5, h - 5), Vector2(5, h - 5)]:
		draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -4), corner + Vector2(4, 0), corner + Vector2(0, 4), corner + Vector2(-4, 0)]), FRAME)
