class_name GameText

# Libellés affichés pour les identifiants du jeu.

const PROFESSION_NAMES := {
	"bucheronnage": "Bûcheronnage",
	"minage": "Minage",
	"peche": "Pêche",
	"herboristerie": "Herboristerie",
	"chasse": "Chasse",
	"runographie": "Runographie",
	"sourcellerie": "Sourcellerie",
	"archeologie": "Archéologie",
	"forgeron": "Forge",
	"alchimiste": "Alchimie",
	"couturier": "Couture",
	"enchanteur": "Enchantement",
	"sculpteur": "Sculpture",
	"cuisinier": "Cuisine",
}

const PROFESSION_ICONS := {
	"bucheronnage": "🪓",
	"minage": "⛏",
	"peche": "🎣",
	"herboristerie": "🌿",
	"chasse": "🏹",
	"runographie": "🔮",
	"sourcellerie": "💧",
	"archeologie": "🏺",
	"forgeron": "🔨",
	"alchimiste": "⚗",
	"couturier": "🧵",
	"enchanteur": "✨",
	"sculpteur": "🗿",
	"cuisinier": "🍲",
}

# Rangs de rareté d'un objet (balance.RARITIES côté serveur), du plus courant au
# plus rare. Le nom d'un objet prend la couleur de son rang partout.
const RARITY_NAMES := {
	"commun": "Commun",
	"peu_commun": "Peu commun",
	"rare": "Rare",
	"epique": "Épique",
	"legendaire": "Légendaire",
}

const RARITY_COLORS := {
	"commun": Color(0.92, 0.92, 0.92),
	"peu_commun": Color(0.45, 0.85, 0.45),
	"rare": Color(0.42, 0.66, 1.0),
	"epique": Color(0.76, 0.52, 1.0),
	"legendaire": Color(1.0, 0.66, 0.22),
}


static func rarity_of(item: Dictionary) -> String:
	var rarity := str(item.get("rarity", "commun"))
	return rarity if RARITY_NAMES.has(rarity) else "commun"


static func rarity_color(item: Dictionary) -> Color:
	return RARITY_COLORS[rarity_of(item)]


static func rarity_name(item: Dictionary) -> String:
	return RARITY_NAMES[rarity_of(item)]


static func is_above_common(item: Dictionary) -> bool:
	return rarity_of(item) != "commun"


# Colore le texte d'un bouton (carte d'objet) selon le rang de l'objet.
static func color_button(button: Button, item: Dictionary) -> void:
	var color := rarity_color(item)

	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, color)


static func profession_name(profession_id: String) -> String:
	return PROFESSION_NAMES.get(profession_id, prettify_id(profession_id))


static func profession_label(profession_id: String) -> String:
	return "%s %s" % [PROFESSION_ICONS.get(profession_id, "🛠"), profession_name(profession_id)]


static func prettify_id(value: String) -> String:
	var text := value.replace("_", " ")
	return text.substr(0, 1).to_upper() + text.substr(1)


# Nombre lisible : entier avec espaces de milliers (« 12 480 »), sinon une décimale.
static func format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		var digits := str(absi(int(roundf(value))))
		var grouped := ""

		while digits.length() > 3:
			grouped = "\u00a0" + digits.substr(digits.length() - 3) + grouped
			digits = digits.substr(0, digits.length() - 3)

		return ("-" if value < 0 else "") + digits + grouped

	return "%.1f" % value
