extends Control


signal back_requested


@onready var back_button: Button = $BackButton
@onready var zone_title: Label = $ZoneTitle
@onready var zone_description: Label = $ZoneDescription
@onready var categories_container: VBoxContainer = $CategoriesContainer


var zone_data: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	ApiClient.zone_received.connect(_on_zone_received)
	
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
