extends Control

# Fond de la carte, façon carte ancienne d'un grimoire : sol de parchemin
# sombre, paysage dessiné autour de chaque zone selon son type (arbres, eaux,
# maisons, ruines…), chemins à l'encre dorée, cadre et rose des vents. Tout est
# tracé en code à partir des zones de l'étage : un nouvel étage a sa carte sans
# illustration à faire. Les marqueurs de zone sont des enfants dessinés par-dessus.

const GROUND := Color(0.115, 0.09, 0.066)
const INK := Color(0.86, 0.7, 0.42)
const PATH_OPEN := Color(0.88, 0.72, 0.43, 0.85)
const PATH_LOCKED := Color(0.75, 0.65, 0.5, 0.22)
# Marge de terrain dessinée au-delà de la carte (on peut la faire glisser un peu plus loin).
const BLEED := 420.0
# Rayon de la tache de couleur d'une zone, et zone dégagée autour de son marqueur.
const BIOME_RADIUS := 115.0
const CLEAR_RADIUS := 52.0

# Teinte et motifs de chaque type de zone.
const BIOMES := {
	"town": {"color": Color(0.58, 0.42, 0.2), "glyph": "maison"},
	"wilderness": {"color": Color(0.24, 0.34, 0.17), "glyph": "arbre"},
	"water": {"color": Color(0.16, 0.34, 0.4), "glyph": "vague"},
	"camp": {"color": Color(0.5, 0.36, 0.19), "glyph": "tente"},
	"ruins": {"color": Color(0.38, 0.35, 0.31), "glyph": "colonne"},
	"danger": {"color": Color(0.27, 0.19, 0.27), "glyph": "arbre_mort"},
	"boss": {"color": Color(0.55, 0.2, 0.12), "glyph": "rune"},
	"passage": {"color": Color(0.38, 0.27, 0.55), "glyph": "spirale"},
	"lair": {"color": Color(0.45, 0.16, 0.12), "glyph": "arbre_mort"},
}

# [[position_a, position_b, ouvert], ...] en coordonnées de la carte.
var paths: Array = []
# [{position, type, open, id}, ...] : le paysage se dessine autour des zones.
var zones: Array = []
var grain: NoiseTexture2D


func _ready() -> void:
	# Grain du parchemin : un bruit doux, en mosaïque sans raccord visible.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0, 0, 0, 0.22))
	ramp.set_color(1, Color(0.95, 0.8, 0.55, 0.07))
	grain = NoiseTexture2D.new()
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	grain.noise = noise
	grain.color_ramp = ramp
	grain.changed.connect(queue_redraw)


func set_paths(new_paths: Array) -> void:
	paths = new_paths
	queue_redraw()


func set_zones(new_zones: Array) -> void:
	zones = new_zones
	queue_redraw()


func _draw() -> void:
	var area := Rect2(-Vector2(BLEED, BLEED), size + Vector2(BLEED, BLEED) * 2.0)
	draw_rect(area, GROUND)

	if grain != null:
		draw_texture_rect(grain, area, true)

	for zone in zones:
		draw_biome_glow(zone)

	draw_frame()
	draw_compass(Vector2(size.x - 70.0, 70.0))

	for zone in zones:
		draw_biome_glyphs(zone)

	draw_paths()


# --- Paysage ---------------------------------------------------------------------

func biome_of(zone: Dictionary) -> Dictionary:
	return BIOMES.get(zone.type, BIOMES.wilderness)


# Tache de couleur douce : des cercles superposés très transparents.
func draw_biome_glow(zone: Dictionary) -> void:
	var color: Color = biome_of(zone).color
	var strength := 0.075 if zone.open else 0.035

	for step in range(8):
		var radius := BIOME_RADIUS * (1.0 - step * 0.11)
		draw_circle(zone.position, radius, Color(color, strength))


func draw_biome_glyphs(zone: Dictionary) -> void:
	var biome := biome_of(zone)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(zone.id)
	var alpha := 0.55 if zone.open else 0.22
	var tint: Color = biome.color.lightened(0.25)
	var placed := 0
	var tries := 0

	while placed < 11 and tries < 60:
		tries += 1
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(CLEAR_RADIUS, BIOME_RADIUS * 0.95)
		var offset := Vector2.from_angle(angle) * distance

		# On laisse dégagés le marqueur, son niveau au-dessus et son nom en dessous.
		if absf(offset.x) < 62.0 and offset.y > -50.0 and offset.y < 80.0:
			continue

		draw_glyph(biome.glyph, zone.position + offset, rng.randf_range(0.8, 1.25), Color(tint, alpha), rng)
		placed += 1


func draw_glyph(kind: String, at: Vector2, scale_factor: float, color: Color, rng: RandomNumberGenerator) -> void:
	var s := 9.0 * scale_factor
	var dark := Color(color.darkened(0.45), color.a)

	match kind:
		"arbre":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 1.4), at + Vector2(s * 0.75, s * 0.35), at + Vector2(-s * 0.75, s * 0.35)]), color)
			draw_line(at + Vector2(0, s * 0.35), at + Vector2(0, s * 0.85), dark, 1.6)
		"arbre_mort":
			draw_line(at + Vector2(0, s), at + Vector2(0, -s), color, 1.6)
			draw_line(at + Vector2(0, -s * 0.2), at + Vector2(s * 0.6, -s * 0.8), color, 1.3)
			draw_line(at + Vector2(0, s * 0.2), at + Vector2(-s * 0.55, -s * 0.35), color, 1.3)
		"vague":
			for row in 2:
				var y := at.y + row * s * 0.7
				draw_arc(Vector2(at.x - s * 0.5, y), s * 0.5, PI, TAU, 8, color, 1.4)
				draw_arc(Vector2(at.x + s * 0.5, y), s * 0.5, PI, TAU, 8, color, 1.4)
		"maison":
			draw_rect(Rect2(at + Vector2(-s * 0.6, -s * 0.2), Vector2(s * 1.2, s * 0.9)), color)
			draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.85, -s * 0.2), at + Vector2(s * 0.85, -s * 0.2), at + Vector2(0, -s * 0.95)]), dark.lightened(0.2))
		"tente":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s), at + Vector2(s * 0.9, s * 0.6), at + Vector2(-s * 0.9, s * 0.6)]), color)
			draw_line(at + Vector2(0, -s), at + Vector2(0, s * 0.6), dark, 1.2)
		"colonne":
			var height := s * rng.randf_range(0.8, 1.6)
			draw_rect(Rect2(at + Vector2(-s * 0.3, -height), Vector2(s * 0.6, height)), color)
			draw_rect(Rect2(at + Vector2(-s * 0.5, 0), Vector2(s, s * 0.25)), color)
		"rune":
			draw_arc(at, s * 0.9, 0, TAU, 20, color, 1.2)
			draw_line(at + Vector2(0, -s * 0.6), at + Vector2(0, s * 0.6), color, 1.2)
			draw_line(at + Vector2(-s * 0.45, -s * 0.15), at + Vector2(s * 0.45, s * 0.15), color, 1.2)
		"spirale":
			var points := PackedVector2Array()
			for i in 24:
				points.append(at + Vector2.from_angle(i * 0.5) * (s * 0.08 * i))
			draw_polyline(points, color, 1.3, true)


# --- Chemins, cadre, rose des vents ---------------------------------------------

func draw_paths() -> void:
	# Les chemins fermés d'abord, en traits pâles ; les chemins ouverts en
	# pointillés d'encre par-dessus.
	for path in paths:
		if not path[2]:
			draw_dashed_line(path[0], path[1], PATH_LOCKED, 1.6, 7.0, true, true)

	for path in paths:
		if path[2]:
			var from: Vector2 = path[0]
			var to: Vector2 = path[1]
			var count := int(from.distance_to(to) / 11.0)

			for i in range(1, count):
				draw_circle(from.lerp(to, float(i) / count), 2.2, PATH_OPEN)


func draw_frame() -> void:
	var rect := Rect2(Vector2(24, 24), size - Vector2(48, 48))
	draw_rect(rect, Color(INK, 0.35), false, 1.5)
	draw_rect(rect.grow(-6), Color(INK, 0.18), false, 1.0)

	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -6), corner + Vector2(6, 0), corner + Vector2(0, 6), corner + Vector2(-6, 0)]), Color(INK, 0.5))


func draw_compass(center: Vector2) -> void:
	var color := Color(INK, 0.45)
	draw_arc(center, 26, 0, TAU, 32, color, 1.2)
	draw_arc(center, 20, 0, TAU, 32, Color(INK, 0.25), 1.0)

	for i in 4:
		var direction := Vector2.from_angle(i * PI / 2 - PI / 2)
		var side := direction.orthogonal() * 5.0
		draw_colored_polygon(PackedVector2Array([center + direction * 34, center + side, center - side]), color if i == 0 else Color(INK, 0.28))

	draw_string(ThemeDB.fallback_font, center + Vector2(-5, -38), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
