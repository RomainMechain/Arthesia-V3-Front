extends Control

# Carnet d'aventure, ouvert depuis la carte : ce que le joueur a découvert de
# chaque étage (GET /players/{id}/carnet). Trois onglets : les créatures
# vaincues, les ressources récoltées et les habitants rencontrés. Ce qui reste
# à découvrir n'est que compté, jamais décrit.

signal back_requested

const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR
const COLOR_TEXT := Color(0.85, 0.82, 0.75)

const ROLE_LABELS := {"normal": "", "elite": "Élite", "boss": "Boss"}
const ROLE_COLORS := {"elite": Color(1.0, 0.62, 0.25), "boss": Color(0.95, 0.35, 0.3)}

@onready var back_button: Button = $Layout/Header/BackButton
@onready var bestiary_tab: Button = $Layout/Tabs/BestiaryTab
@onready var harvest_tab: Button = $Layout/Tabs/HarvestTab
@onready var inhabitant_tab: Button = $Layout/Tabs/InhabitantTab
@onready var scroll: ScrollContainer = $Layout/Scroll
@onready var body: VBoxContainer = $Layout/Scroll/Body

# Réponse de GET /players/{id}/carnet : une page par étage découvert.
var floors: Array = []
var current_tab := "bestiary"
var loaded := false


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	bestiary_tab.pressed.connect(func(): show_tab("bestiary"))
	harvest_tab.pressed.connect(func(): show_tab("harvests"))
	inhabitant_tab.pressed.connect(func(): show_tab("inhabitants"))

	for tab in [bestiary_tab, harvest_tab, inhabitant_tab]:
		tab.add_theme_font_size_override("font_size", 13)

	show_tab("bestiary")
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()


func refresh() -> void:
	var res := await ApiClient.get_player_carnet(GameState.player_id)

	if not is_inside_tree():
		return

	if not res.ok:
		clear_body()
		add_label("Impossible de charger le carnet : " + res.error, 14, COLOR_ERROR)
		return

	floors = res.data.get("floors", [])
	loaded = true
	show_tab(current_tab)


func show_tab(tab: String) -> void:
	current_tab = tab
	bestiary_tab.button_pressed = tab == "bestiary"
	harvest_tab.button_pressed = tab == "harvests"
	inhabitant_tab.button_pressed = tab == "inhabitants"
	scroll.scroll_vertical = 0
	clear_body()

	if not loaded:
		add_label("Ouverture du carnet...", 14, COLOR_MUTED)
		return

	if floors.is_empty():
		add_label("Ton carnet est encore vierge. Bats-toi, récolte, parle aux habitants : chaque découverte s'y inscrira.", 13, COLOR_MUTED)
		return

	for floor in floors:
		# Le nom de l'étage ne sert de séparateur que s'il y en a plusieurs.
		if floors.size() > 1:
			add_label(str(floor.get("name", "Étage")), 17, COLOR_HIGHLIGHT)

		match tab:
			"bestiary":
				show_bestiary(floor)
			"harvests":
				show_harvests(floor)
			"inhabitants":
				show_inhabitants(floor)


# --- Onglets ------------------------------------------------------------------

func show_bestiary(floor: Dictionary) -> void:
	for monster in floor.get("bestiary", []):
		var card := add_card()
		var role := str(monster.get("role", "normal"))
		var heading := "%s  ·  Niv. %d" % [monster.get("name", "?"), int(monster.get("level", 1))]

		if not str(ROLE_LABELS.get(role, "")).is_empty():
			heading += "  ·  " + str(ROLE_LABELS[role])

		card.add_child(make_label(heading, 15, ROLE_COLORS.get(role, null)))
		var kills := int(monster.get("kills", 0))
		card.add_child(make_label("⚔ %d victoire%s" % [kills, "s" if kills > 1 else ""], 12, COLOR_HIGHLIGHT))
		card.add_child(make_label(str(monster.get("description", "")), 13, COLOR_TEXT))
		add_list_line(card, "Butin", monster.get("loot", []))

	add_unknown(int(floor.get("unknown_monsters", 0)), "créature encore inconnue", "créatures encore inconnues")


func show_harvests(floor: Dictionary) -> void:
	for resource in floor.get("harvests", []):
		var card := add_card()
		card.add_child(make_label("%s  ·  Niv. %d" % [resource.get("name", "?"), int(resource.get("level", 1))], 15))
		var count := int(resource.get("gathers", 0))
		var profession := GameText.profession_label(str(resource.get("profession_id", "")))
		card.add_child(make_label("%s  ·  %d récolte%s" % [profession, count, "s" if count > 1 else ""], 12, COLOR_HIGHLIGHT))
		card.add_child(make_label(str(resource.get("description", "")), 13, COLOR_TEXT))
		add_list_line(card, "Donne", resource.get("yields", []))

	add_unknown(int(floor.get("unknown_resources", 0)), "ressource encore inconnue", "ressources encore inconnues")


func show_inhabitants(floor: Dictionary) -> void:
	for npc in floor.get("inhabitants", []):
		var card := add_card()
		var heading := str(npc.get("name", "?"))

		if not str(npc.get("role", "")).is_empty():
			heading += "  ·  " + str(npc.role)

		card.add_child(make_label(heading, 15))
		card.add_child(make_label("📍 " + str(npc.get("zone_name", "")), 12, COLOR_HIGHLIGHT))
		card.add_child(make_label(str(npc.get("description", "")), 13, COLOR_TEXT))

		for line in npc.get("dialogues", []):
			card.add_child(make_label("« %s »" % line, 13, COLOR_MUTED))

	add_unknown(int(floor.get("unknown_inhabitants", 0)), "habitant encore jamais rencontré", "habitants encore jamais rencontrés")


# --- Construction ----------------------------------------------------------------

func clear_body() -> void:
	for child in body.get_children():
		child.queue_free()


func make_label(text: String, font_size := 0, color = null) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)

	if color != null:
		label.add_theme_color_override("font_color", color)

	return label


func add_label(text: String, font_size := 0, color = null) -> Label:
	var label := make_label(text, font_size, color)
	body.add_child(label)
	return label


# Carte d'une découverte ; renvoie la colonne où ajouter ses lignes.
func add_card() -> VBoxContainer:
	var card := UiStyle.make_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	body.add_child(card)
	return box


func add_list_line(card: VBoxContainer, heading: String, names: Array) -> void:
	if not names.is_empty():
		card.add_child(make_label("%s : %s" % [heading, ", ".join(names)], 12, COLOR_MUTED))


func add_unknown(count: int, singular: String, plural: String) -> void:
	if count > 0:
		add_label("🔒 %d %s…" % [count, singular if count == 1 else plural], 13, COLOR_MUTED)
