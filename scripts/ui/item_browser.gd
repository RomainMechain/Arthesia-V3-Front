extends VBoxContainer

# Liste d'objets avec recherche, filtre de rang et catégories repliables.
#
#     var browser = ITEM_BROWSER.new()
#     body.add_child(browser)
#     browser.setup("sac", item_ids, item_templates, func(item_id): return make_card(item_id))
#
# Les objets sont rangés par catégorie (Équipement, Consommables, Matériaux),
# repliées au départ : les cartes d'une catégorie ne sont construites qu'à son
# ouverture. Une recherche ou un filtre de rang ouvre tout et ne garde que ce
# qui correspond. Taper ne reconstruit que la liste, jamais la barre : le
# clavier reste ouvert. L'état (texte, rang, catégories ouvertes) est gardé
# pour la session, par liste (clé de setup).

const CATEGORY_ORDER := ["equipment", "consumable", "material", "other"]
const CATEGORY_LABELS := {
	"equipment": "⚔ Équipement",
	"consumable": "🧪 Consommables",
	"material": "🧱 Matériaux",
	"other": "📦 Autres",
}
# En dessous de ce nombre d'objets, ni barre de recherche ni catégories repliées.
const FILTER_FROM := 6

static var states := {}

var item_ids: Array = []
var items: Dictionary = {}
var make_card: Callable
var state: Dictionary = {}
var list_box: VBoxContainer
var compact := false


func setup(key: String, ids: Array, item_templates: Dictionary, card_builder: Callable) -> void:
	item_ids = ids
	items = item_templates
	make_card = card_builder
	compact = ids.size() < FILTER_FROM
	state = states.get_or_add(key, {"text": "", "rarity": 0, "open": {}})
	add_theme_constant_override("separation", 8)

	if not compact:
		add_child(build_filter_bar())

	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 6)
	add_child(list_box)
	rebuild_list()


func build_filter_bar() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var search := LineEdit.new()
	search.placeholder_text = "🔍 Rechercher"
	search.text = state.text
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(0, 40)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(
		func(text):
			state.text = text
			rebuild_list()
	)
	row.add_child(search)

	# « Rare et + » : garde les objets de ce rang ou au-dessus.
	var rarity := OptionButton.new()
	rarity.custom_minimum_size = Vector2(0, 40)
	rarity.add_item("Tous les rangs")

	for rank in range(1, GameText.RARITY_NAMES.size()):
		rarity.add_item("%s et +" % GameText.RARITY_NAMES.values()[rank])

	rarity.selected = state.rarity
	rarity.item_selected.connect(
		func(index):
			state.rarity = index
			rebuild_list()
	)
	row.add_child(rarity)
	return row


func item_name(item_id: String) -> String:
	return str(items.get(item_id, {}).get("name", GameText.prettify_id(item_id)))


func rarity_rank(item_id: String) -> int:
	return GameText.RARITY_NAMES.keys().find(GameText.rarity_of(items.get(item_id, {})))


func matches(item_id: String) -> bool:
	var text := str(state.text).strip_edges().to_lower()
	return (text.is_empty() or item_name(item_id).to_lower().contains(text)) and rarity_rank(item_id) >= int(state.rarity)


func is_filtering() -> bool:
	return not str(state.text).strip_edges().is_empty() or int(state.rarity) > 0


func rebuild_list() -> void:
	for child in list_box.get_children():
		child.queue_free()

	var groups := {}

	for item_id in item_ids:
		if not matches(item_id):
			continue

		var category := str(items.get(item_id, {}).get("category", "other"))
		groups.get_or_add(category if CATEGORY_LABELS.has(category) else "other", []).append(item_id)

	if groups.is_empty():
		var empty := Label.new()
		empty.text = "Aucun objet ne correspond."
		empty.add_theme_color_override("font_color", UiStyle.COLOR_MUTED)
		list_box.add_child(empty)
		return

	for category in CATEGORY_ORDER:
		if groups.has(category):
			add_group(category, groups[category], groups.size() == 1)


# Les plus rares d'abord, puis par nom.
func sorted(ids: Array) -> Array:
	ids.sort_custom(
		func(a, b):
			if rarity_rank(a) != rarity_rank(b):
				return rarity_rank(a) > rarity_rank(b)
			return item_name(a).naturalnocasecmp_to(item_name(b)) < 0
	)
	return ids


func add_group(category: String, ids: Array, only_group: bool) -> void:
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)

	# Petite liste, recherche en cours ou seule catégorie : tout est ouvert.
	var forced_open := compact or is_filtering() or only_group

	if not forced_open:
		var header := Button.new()
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.custom_minimum_size = Vector2(0, 40)
		header.add_theme_font_size_override("font_size", 15)
		var refresh_header := func():
			header.text = "%s %s  (%d)" % ["▾" if state.open.get(category, false) else "▸", CATEGORY_LABELS[category], ids.size()]
		refresh_header.call()
		header.pressed.connect(
			func():
				state.open[category] = not state.open.get(category, false)
				refresh_header.call()
				show_cards(cards, ids, category)
		)
		list_box.add_child(header)
	else:
		var title := Label.new()
		title.text = "%s  (%d)" % [CATEGORY_LABELS[category], ids.size()]
		title.add_theme_font_size_override("font_size", 15)
		list_box.add_child(title)

	list_box.add_child(cards)

	if forced_open:
		fill_cards(cards, ids)
	else:
		show_cards(cards, ids, category)


# Une catégorie ne construit ses cartes qu'à sa première ouverture.
func show_cards(cards: VBoxContainer, ids: Array, category: String) -> void:
	cards.visible = state.open.get(category, false)

	if cards.visible and cards.get_child_count() == 0:
		fill_cards(cards, ids)


func fill_cards(cards: VBoxContainer, ids: Array) -> void:
	for item_id in sorted(ids):
		var card = make_card.call(item_id)

		if card is Control:
			cards.add_child(card)
