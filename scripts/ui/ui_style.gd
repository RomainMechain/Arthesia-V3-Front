class_name UiStyle

# Identité visuelle d'Arthesia : un grimoire enluminé. Cuirs et parchemins
# sombres, filets dorés, ornements runiques aux coins, titres gravés (Cinzel).
#
# build_theme() habille tous les contrôles (boutons, champs, menus, panneaux) ;
# il est posé sur la fenêtre au démarrage (GameState). Les écrans construits en
# code utilisent les cartes ornées (card_style, make_card, make_card_button) et
# la variation de thème « Titre » pour leurs titres (make_title).

const TITLE_FONT := preload("res://fonts/Cinzel.ttf")

# Palette : encres et dorures sur cuir sombre.
const COLOR_BG := Color(0.075, 0.06, 0.047)
const COLOR_TEXT := Color(0.93, 0.88, 0.78)
const COLOR_GOLD := Color(0.86, 0.69, 0.38)
const COLOR_GOLD_DIM := Color(0.52, 0.4, 0.22)
const COLOR_CARD := Color(0.135, 0.105, 0.078)
const COLOR_CARD_HIGHLIGHT := Color(0.24, 0.17, 0.08)
const COLOR_PANEL := Color(0.095, 0.075, 0.055, 0.96)
const COLOR_MUTED := Color(0.7, 0.64, 0.54)
const COLOR_BONUS := Color(0.55, 0.82, 0.45)
const COLOR_MALUS := Color(0.95, 0.5, 0.42)
const COLOR_HIGHLIGHT := Color(0.96, 0.8, 0.45)
const COLOR_ERROR := Color(1.0, 0.47, 0.42)
const COLOR_XP := Color(0.5, 0.62, 0.95)
const COLOR_HP := Color(0.45, 0.76, 0.4)
const COLOR_ENEMY_HP := Color(0.84, 0.3, 0.26)
const COLOR_MANA := Color(0.4, 0.58, 0.96)

# Cadre orné (48 × 48, découpé en neuf) : fond en dégradé, double filet doré et
# losanges aux coins. {fill_top}/{fill_bottom}/{border} sont remplacés.
const ORNATE_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="{fill_top}"/><stop offset="1" stop-color="{fill_bottom}"/></linearGradient></defs>
<rect x="1" y="1" width="46" height="46" rx="5" fill="url(#g)" stroke="{border}" stroke-width="1.3"/>
<rect x="4" y="4" width="40" height="40" rx="3" fill="none" stroke="{border}" stroke-opacity="0.4" stroke-width="0.8"/>
<path d="M4 1.6 L6.4 4 L4 6.4 L1.6 4 Z M44 1.6 L46.4 4 L44 6.4 L41.6 4 Z M4 41.6 L6.4 44 L4 46.4 L1.6 44 Z M44 41.6 L46.4 44 L44 46.4 L41.6 44 Z" fill="{border}"/>
</svg>"""
const ORNATE_MARGIN := 12

static var _box_cache := {}


static func _hex(color: Color) -> String:
	return "#" + color.to_html(false)


# Cadre orné d'une couleur de fond donnée (mis en cache par couleur et dorure).
static func ornate_box(fill: Color, border := COLOR_GOLD_DIM) -> StyleBoxTexture:
	var key := fill.to_html() + border.to_html()

	if not _box_cache.has(key):
		var svg := ORNATE_SVG.format({
			"fill_top": _hex(fill.lightened(0.06)),
			"fill_bottom": _hex(fill.darkened(0.12)),
			"border": _hex(border),
		})
		var image := Image.new()
		image.load_svg_from_string(svg, 1.0)
		var box := StyleBoxTexture.new()
		box.texture = ImageTexture.create_from_image(image)
		box.set_texture_margin_all(ORNATE_MARGIN)
		box.modulate_color = Color(1, 1, 1, fill.a)
		_box_cache[key] = box

	var style: StyleBoxTexture = _box_cache[key].duplicate()
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


# Carte ornée (anciennement un rectangle uni : le nom est gardé pour les écrans).
static func card_style(color := COLOR_CARD) -> StyleBox:
	return ornate_box(color)


# Fond uni arrondi, pour ce qui ne doit pas porter d'ornements (pastilles, barres).
static func flat_style(color: Color, radius := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func make_card(color := COLOR_CARD) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", card_style(color))
	return card


# Bouton au look de carte : son contenu (labels, icônes) est ajouté en enfant
# et doit ignorer la souris pour laisser le clic au bouton.
static func make_card_button(min_height := 64.0) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, min_height)
	button.add_theme_stylebox_override("normal", card_style())
	button.add_theme_stylebox_override("hover", ornate_box(COLOR_CARD.lightened(0.06), COLOR_GOLD))
	button.add_theme_stylebox_override("pressed", ornate_box(COLOR_CARD.lightened(0.1), COLOR_GOLD))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", ornate_box(COLOR_CARD.darkened(0.25), COLOR_GOLD_DIM.darkened(0.35)))
	return button


# Titre gravé (police Cinzel, dorée) pour un label construit en code.
static func make_title(label: Label) -> Label:
	label.theme_type_variation = &"Titre"
	return label


# Donne à une ProgressBar un fond sombre et un remplissage coloré arrondis.
static func style_bar(bar: ProgressBar, fill_color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.05, 0.04, 0.03)
	background.set_corner_radius_all(5)
	background.set_border_width_all(1)
	background.border_color = COLOR_GOLD_DIM.darkened(0.3)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(5)

	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)


# Thème de toute l'application.
static func build_theme() -> Theme:
	var theme := Theme.new()

	# Textes
	theme.set_color("font_color", "Label", COLOR_TEXT)
	var title_font := FontVariation.new()
	title_font.base_font = TITLE_FONT
	title_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	theme.set_type_variation("Titre", "Label")
	theme.set_font("font", "Titre", title_font)
	theme.set_color("font_color", "Titre", COLOR_HIGHLIGHT)
	theme.set_color("font_outline_color", "Titre", Color(0, 0, 0, 0.6))
	theme.set_constant("outline_size", "Titre", 2)

	# Boutons (et puces à bascule : la puce choisie prend la dorure)
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, ornate_box(Color(0.17, 0.13, 0.09)))
		theme.set_stylebox("hover", type, ornate_box(Color(0.21, 0.16, 0.1), COLOR_GOLD))
		theme.set_stylebox("pressed", type, ornate_box(Color(0.3, 0.21, 0.09), COLOR_GOLD))
		theme.set_stylebox("hover_pressed", type, ornate_box(Color(0.32, 0.23, 0.1), COLOR_GOLD))
		theme.set_stylebox("disabled", type, ornate_box(Color(0.1, 0.08, 0.06), COLOR_GOLD_DIM.darkened(0.4)))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		theme.set_color("font_color", type, COLOR_TEXT)
		theme.set_color("font_hover_color", type, COLOR_HIGHLIGHT)
		theme.set_color("font_pressed_color", type, COLOR_HIGHLIGHT)
		theme.set_color("font_hover_pressed_color", type, COLOR_HIGHLIGHT)
		theme.set_color("font_focus_color", type, COLOR_TEXT)
		theme.set_color("font_disabled_color", type, Color(0.52, 0.47, 0.4))

	for style_name in ["normal", "focus", "read_only"]:
		var field := flat_style(Color(0.055, 0.045, 0.035), 4)
		field.set_border_width_all(1)
		field.border_color = COLOR_GOLD if style_name == "focus" else COLOR_GOLD_DIM
		field.content_margin_top = 6
		field.content_margin_bottom = 6
		theme.set_stylebox(style_name, "LineEdit", field)

	theme.set_color("font_color", "LineEdit", COLOR_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", COLOR_MUTED.darkened(0.2))
	theme.set_color("caret_color", "LineEdit", COLOR_GOLD)

	# Panneaux et menus
	theme.set_stylebox("panel", "PanelContainer", card_style())
	theme.set_stylebox("panel", "PopupMenu", ornate_box(Color(0.1, 0.08, 0.06)))
	theme.set_color("font_color", "PopupMenu", COLOR_TEXT)
	theme.set_color("font_hover_color", "PopupMenu", COLOR_HIGHLIGHT)
	theme.set_stylebox("hover", "PopupMenu", flat_style(Color(0.26, 0.19, 0.09), 4))

	var separator := StyleBoxLine.new()
	separator.color = Color(COLOR_GOLD_DIM, 0.45)
	theme.set_stylebox("separator", "HSeparator", separator)

	# Barre de défilement : un fin filet doré
	var grabber := flat_style(Color(COLOR_GOLD_DIM, 0.7), 3)
	grabber.set_content_margin_all(0)
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	var track := StyleBoxEmpty.new()
	track.content_margin_left = 3
	track.content_margin_right = 3
	theme.set_stylebox("scroll", "VScrollBar", track)
	return theme
