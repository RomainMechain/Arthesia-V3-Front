class_name UiStyle

# Styles partagés par les écrans construits en code (cartes, barres).

const COLOR_CARD := Color(0.16, 0.16, 0.17)
const COLOR_CARD_HIGHLIGHT := Color(0.24, 0.2, 0.1)
const COLOR_MUTED := Color(0.65, 0.65, 0.65)
const COLOR_BONUS := Color(0.45, 0.85, 0.45)
const COLOR_MALUS := Color(0.95, 0.5, 0.45)
const COLOR_HIGHLIGHT := Color(1.0, 0.82, 0.35)
const COLOR_ERROR := Color(1.0, 0.45, 0.45)
const COLOR_XP := Color(0.42, 0.55, 0.95)
const COLOR_HP := Color(0.36, 0.78, 0.42)
const COLOR_ENEMY_HP := Color(0.86, 0.3, 0.3)
const COLOR_MANA := Color(0.36, 0.56, 0.98)


static func card_style(color := COLOR_CARD) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func make_card(color := COLOR_CARD) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", card_style(color))
	return card


# Donne à une ProgressBar un fond sombre et un remplissage coloré arrondis.
static func style_bar(bar: ProgressBar, fill_color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.08, 0.09)
	background.set_corner_radius_all(5)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(5)

	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
