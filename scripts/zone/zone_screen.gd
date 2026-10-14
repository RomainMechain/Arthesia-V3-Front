extends Control


signal back_requested

@onready var back_button: Button = $BackButton
@onready var zone_title: Label = $ZoneTitle
@onready var zone_description: Label = $ZoneDescription
@onready var categories_container: VBoxContainer = $CategoriesContainer
@onready var entries_container: VBoxContainer = $EntriesContainer
@onready var entry_detail_container: VBoxContainer = $EntryDetailContainer

const COMBAT_SCREEN_SCENE := preload("res://scene/combat/CombatScreen.tscn")

var zone_data: Dictionary = {}
var loaded_templates: Dictionary = {}
var expected_template_count := 0
var current_category_entries: Array = []

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	ApiClient.zone_received.connect(_on_zone_received)
	ApiClient.template_received.connect(_on_template_received)
	
func _on_zone_received(data: Dictionary) -> void:
	print("ZoneScreen a reçu la zone complète : ", data.get("id", ""))

	zone_data = data

	zone_title.text = data.get("name", "Zone")
	zone_description.text = data.get(
		"description",
		"Aucune description disponible."
	)

	var entries: Array = data.get("entries", [])

	build_categories(entries)


func setup(data: Dictionary) -> void:
	zone_data = data

	zone_title.text = data.get("name", "Zone")
	zone_description.text = data.get(
		"description",
		"Aucune description disponible."
	)

	var zone_id: String = data.get("id", "")

	if not zone_id.is_empty():
		ApiClient.get_zone(zone_id)


func _on_back_button_pressed() -> void:
	back_requested.emit()
	
func build_categories(entries: Array) -> void:
	var category_counts: Dictionary = {}

	for entry in entries:
		var template_type: String = entry.get("template_type", "")
		if template_type.is_empty():
			continue
		if not category_counts.has(template_type):
			category_counts[template_type] = 0
		category_counts[template_type] += 1

	for template_type in category_counts:
		var count: int = category_counts[template_type]
		var button := Button.new()
		button.text = "%s  (%d)" % [
			get_category_name(template_type),
			count
		]
		button.custom_minimum_size = Vector2(0, 55)
		button.pressed.connect(
			func():
				open_category(template_type)
		)
		categories_container.add_child(button)
	
	
func get_category_name(template_type: String) -> String:
	match template_type:
		"monster":
			return "⚔ Combat"
		"resource":
			return "🌿 Ressources"
		"npc":
			return "👤 Habitants"
		"quest_giver":
			return "📜 Quêtes"
		"shop", "player_market":
			return "🛒 Commerce"
		"discovery":
			return "🔎 Exploration"
		_:
			return template_type


func open_category(template_type: String) -> void:
	var entries: Array = zone_data.get("entries", [])
	var filtered_entries: Array = []

	for entry in entries:
		if entry.get("template_type", "") == template_type:
			filtered_entries.append(entry)

	current_category_entries = filtered_entries

	loaded_templates.clear()
	expected_template_count = filtered_entries.size()

	for entry in filtered_entries:
		var template_id: String = entry.get("template_id", "")

		if template_id.is_empty():
			continue

		ApiClient.get_template(
			template_type,
			template_id
		)

	show_category_entries(
		template_type,
		filtered_entries
	)

func show_category_entries(
	template_type: String,
	entries: Array
) -> void:
	categories_container.visible = false
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
		var display_name := template_id

		if loaded_templates.has(template_id):
			var template: Dictionary = loaded_templates[template_id]

			display_name = template.get(
				"name",
				template_id
			)

		button.text = display_name
		button.custom_minimum_size = Vector2(0, 50)
		
		button.pressed.connect(
			func():
				open_entry_detail(entry)
		)

		entries_container.add_child(button)
		
func show_categories() -> void:
	entries_container.visible = false
	categories_container.visible = true

func _on_template_received(
	kind: String,
	template_id: String,
	data: Dictionary
) -> void:
	loaded_templates[template_id] = data

	print(
		"Template stocké : ",
		template_id,
		" | ",
		data.get("name", "Sans nom")
	)

	print(
		"Templates chargés : ",
		loaded_templates.size(),
		" / ",
		expected_template_count
	)

	if loaded_templates.size() == expected_template_count:
		print("Tous les templates de la catégorie sont chargés !")

		show_category_entries(
			kind,
			current_category_entries
		)

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
		entry
	)

	combat_screen.back_requested.connect(
		func():
			combat_screen.queue_free()
	)
