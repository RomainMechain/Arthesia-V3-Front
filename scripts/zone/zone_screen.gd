extends Control


signal back_requested

@onready var back_button: Button = $BackButton
@onready var zone_title: Label = $ZoneTitle
@onready var zone_description: Label = $ZoneDescription
@onready var categories_container: VBoxContainer = $CategoriesContainer
@onready var entries_container: VBoxContainer = $EntriesContainer
@onready var entry_detail_container: VBoxContainer = $EntryDetailContainer

const COMBAT_SCREEN_SCENE := preload("res://scene/combat/CombatScreen.tscn")

# Ordre d'affichage des catégories. Plusieurs template_type peuvent partager
# une catégorie (boutique PNJ et Autel des Ventes sont tous deux du commerce).
const CATEGORY_ORDER := ["combat", "resources", "npcs", "quests", "commerce", "exploration"]

var zone_data: Dictionary = {}
var loaded_templates: Dictionary = {}

# Incrémenté à chaque ouverture de catégorie : un chargement de templates
# encore en cours pour une ancienne catégorie ne doit pas écraser la liste.
var category_request_id := 0


func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)


func setup(data: Dictionary) -> void:
	zone_data = data

	zone_title.text = data.get("name", "Zone")
	zone_description.text = data.get(
		"description",
		"Aucune description disponible."
	)

	var zone_id: String = data.get("id", "")

	if zone_id.is_empty():
		return

	var res := await ApiClient.get_zone(zone_id)

	if not res.ok:
		if res.status == 404:
			show_message("Cette zone n'a pas encore de contenu.")
		else:
			show_message("Impossible de charger la zone : " + res.error)
		return

	zone_data = res.data
	zone_title.text = zone_data.get("name", "Zone")
	zone_description.text = zone_data.get(
		"description",
		"Aucune description disponible."
	)

	build_categories(zone_data.get("entries", []))


func _on_back_button_pressed() -> void:
	back_requested.emit()


func show_message(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	categories_container.add_child(label)


func get_category(template_type: String) -> String:
	match template_type:
		"monster":
			return "combat"
		"resource":
			return "resources"
		"npc":
			return "npcs"
		"quest_giver":
			return "quests"
		"shop", "player_market":
			return "commerce"
		"discovery":
			return "exploration"
		_:
			return template_type


func get_category_name(category: String) -> String:
	match category:
		"combat":
			return "⚔ Combat"
		"resources":
			return "🌿 Ressources"
		"npcs":
			return "👤 Habitants"
		"quests":
			return "📜 Quêtes"
		"commerce":
			return "🛒 Commerce"
		"exploration":
			return "🔎 Exploration"
		_:
			return category


func build_categories(entries: Array) -> void:
	var category_counts: Dictionary = {}

	for entry in entries:
		var template_type: String = entry.get("template_type", "")
		if template_type.is_empty():
			continue
		var category := get_category(template_type)
		category_counts[category] = category_counts.get(category, 0) + 1

	# Catégories connues dans l'ordre prévu, puis les éventuelles inconnues.
	var ordered: Array = []

	for category in CATEGORY_ORDER:
		if category_counts.has(category):
			ordered.append(category)

	for category in category_counts:
		if not ordered.has(category):
			ordered.append(category)

	for category in ordered:
		var count: int = category_counts[category]
		var button := Button.new()
		button.text = "%s  (%d)" % [
			get_category_name(category),
			count
		]
		button.custom_minimum_size = Vector2(0, 55)
		button.pressed.connect(
			func():
				open_category(category)
		)
		categories_container.add_child(button)


func open_category(category: String) -> void:
	var entries: Array = zone_data.get("entries", [])
	var filtered_entries: Array = []

	for entry in entries:
		if get_category(entry.get("template_type", "")) == category:
			filtered_entries.append(entry)

	category_request_id += 1
	var request_id := category_request_id

	# Affiche tout de suite la liste (avec les identifiants), puis la
	# réaffiche une fois les vrais noms chargés.
	show_category_entries(filtered_entries)

	for entry in filtered_entries:
		await load_entry_template(entry)

		if request_id != category_request_id:
			return

	show_category_entries(filtered_entries)


# Charge le template d'une entry dans loaded_templates. Les templates sont
# mis en cache par ApiClient : rouvrir une catégorie ne refait pas d'appel.
func load_entry_template(entry: Dictionary) -> void:
	var template_id: String = entry.get("template_id", "")

	if template_id.is_empty() or loaded_templates.has(template_id):
		return

	var res := await ApiClient.get_template(
		ApiClient.template_kind_for_entry(entry),
		template_id
	)

	if res.ok:
		loaded_templates[template_id] = res.data


func show_category_entries(entries: Array) -> void:
	categories_container.visible = false
	entry_detail_container.visible = false
	entries_container.visible = true

	# Nettoie l'ancien contenu.
	for child in entries_container.get_children():
		child.queue_free()

	var back_categories_button := Button.new()
	back_categories_button.text = "← Catégories"
	back_categories_button.custom_minimum_size = Vector2(0, 45)

	back_categories_button.pressed.connect(
		func():
			show_categories()
	)

	entries_container.add_child(back_categories_button)

	for entry in entries:
		var button := Button.new()

		var template_id: String = entry.get("template_id", "")
		var template: Dictionary = loaded_templates.get(template_id, {})

		button.text = template.get("name", template_id)
		button.custom_minimum_size = Vector2(0, 50)

		button.pressed.connect(
			func():
				open_entry_detail(entry)
		)

		entries_container.add_child(button)


func show_categories() -> void:
	# Invalide un éventuel chargement de catégorie en cours.
	category_request_id += 1
	entries_container.visible = false
	categories_container.visible = true


func open_entry_detail(entry: Dictionary) -> void:
	entries_container.visible = false
	entry_detail_container.visible = true

	for child in entry_detail_container.get_children():
		child.queue_free()

	var template_id: String = entry.get("template_id", "")
	var template: Dictionary = loaded_templates.get(template_id, {})

	var back_button_detail := Button.new()
	back_button_detail.text = "← Liste"
	back_button_detail.custom_minimum_size = Vector2(0, 45)
	back_button_detail.pressed.connect(
		func():
			entry_detail_container.visible = false
			entries_container.visible = true
	)
	entry_detail_container.add_child(back_button_detail)

	var name_label := Label.new()
	name_label.text = template.get("name", template_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry_detail_container.add_child(name_label)

	# ============ MONSTER =============
	if entry.get("template_type", "") == "monster":
		var level_label := Label.new()
		level_label.text = "Niveau %d" % int(template.get("level", 1))
		entry_detail_container.add_child(level_label)

		var stats: Dictionary = template.get("stats", {})

		var stats_label := Label.new()
		stats_label.text = (
			"PV : %d\n" +
			"ATK : %d | DEF : %d\n" +
			"AGI : %d | INT : %d | SAG : %d"
		) % [
			int(stats.get("hp", 0)),
			int(stats.get("atk", 0)),
			int(stats.get("def", 0)),
			int(stats.get("agi", 0)),
			int(stats.get("int", 0)),
			int(stats.get("sag", 0))
		]

		entry_detail_container.add_child(stats_label)

	var description_label := Label.new()
	description_label.text = template.get(
		"description",
		"Aucune description disponible."
	)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry_detail_container.add_child(description_label)

	if entry.get("template_type", "") == "monster":
		var fight_button := Button.new()
		fight_button.text = "⚔ Combattre"
		fight_button.custom_minimum_size = Vector2(0, 50)

		fight_button.pressed.connect(
			func():
				open_combat(entry)
		)

		entry_detail_container.add_child(fight_button)

	print("Fiche ouverte : ", entry.get("id", ""))


func open_combat(entry: Dictionary) -> void:
	var combat_screen = COMBAT_SCREEN_SCENE.instantiate()

	add_child(combat_screen)
	combat_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	combat_screen.prepare_combat(
		zone_data.get("id", ""),
		entry,
		loaded_templates.get(entry.get("template_id", ""), {})
	)

	combat_screen.back_requested.connect(
		func():
			combat_screen.queue_free()
	)
