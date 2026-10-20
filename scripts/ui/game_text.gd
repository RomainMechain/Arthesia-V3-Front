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
