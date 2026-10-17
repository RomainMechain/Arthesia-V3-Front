extends Control

# Écran Personnage : onglets Stats (niveau, XP, or, répartition des points)
# et Inventaire (objets groupés par catégorie, fiche détail).
#
# Le contenu des onglets est construit en code dans Content. Il est
# reconstruit à chaque changement du joueur (GameState.player_changed).

signal back_requested

const STAT_ORDER := ["hp", "atk", "def", "agi", "int", "sag"]

const STAT_LABELS := {
	"hp": "PV",
	"atk": "ATK",
	"def": "DEF",
	"agi": "AGI",
	"int": "INT",
	"sag": "SAG",
}

const ITEM_CATEGORY_ORDER := ["equipment", "consumable", "material", "other"]

const ITEM_CATEGORY_LABELS := {
	"equipment": "⚔ Équipement",
	"consumable": "🧪 Consommables",
	"material": "🪵 Matériaux",
	"other": "❔ Divers",
}

const ITEM_CATEGORY_NAMES := {
	"equipment": "Équipement",
	"consumable": "Consommable",
	"material": "Matériau",
}

const SLOT_LABELS := {
	"weapon": "Arme",
	"head": "Tête",
	"chest": "Torse",
	"gloves": "Gants",
	"boots": "Bottes",
	"ring": "Anneau",
	"amulet": "Amulette",
	"tool": "Outil",
}

const COLOR_MUTED := Color(0.65, 0.65, 0.65)
const COLOR_BONUS := Color(0.45, 0.85, 0.45)
const COLOR_HIGHLIGHT := Color(1.0, 0.82, 0.35)
const COLOR_ERROR := Color(1.0, 0.45, 0.45)

@onready var back_button: Button = $Layout/Header/BackButton
@onready var stats_tab: Button = $Layout/Tabs/StatsTab
@onready var inventory_tab: Button = $Layout/Tabs/InventoryTab
@onready var scroll: ScrollContainer = $Layout/Scroll
@onready var content: VBoxContainer = $Layout/Scroll/Content

var current_tab := "stats"

# Réponse de GET /players/{id}/stats : stats finales, seuil d'XP, gain par point.
var stats_data: Dictionary = {}

# Points choisis mais pas encore envoyés au serveur : stat -> nombre.
var pending_points: Dictionary = {}
var is_submitting := false
var error_message := ""

var item_templates: Dictionary = {}

# Incrémenté à chaque rendu : un chargement encore en cours pour un ancien
# rendu (autre onglet, joueur rechargé) ne doit pas écraser l'affichage.
var render_id := 0


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	stats_tab.pressed.connect(func(): show_tab("stats"))
	inventory_tab.pressed.connect(func(): show_tab("inventory"))
	GameState.player_changed.connect(_on_player_changed)

	show_tab("stats")


func _on_player_changed(_player: Dictionary) -> void:
	refresh()


func show_tab(tab: String) -> void:
	current_tab = tab
	stats_tab.button_pressed = tab == "stats"
	inventory_tab.button_pressed = tab == "inventory"
	error_message = ""
	scroll.scroll_vertical = 0
	refresh()


func refresh() -> void:
	render_id += 1
	var id := render_id

	if current_tab == "stats":
		await refresh_stats(id)
	else:
		await refresh_inventory(id)


# --- Outils d'affichage ---------------------------------------------------

func clear_content() -> void:
	for child in content.get_children():
		child.queue_free()


func make_label(text: String, font_size := 0, color = null) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)

	if color != null:
		label.add_theme_color_override("font_color", color)

	return label


func add_label(text: String, font_size := 0, color = null) -> Label:
	var label := make_label(text, font_size, color)
	content.add_child(label)
	return label


func add_section_title(text: String) -> void:
	content.add_child(HSeparator.new())
	add_label(text, 20)


func format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))

	return "%.1f" % value


# --- Onglet Stats -----------------------------------------------------------

func refresh_stats(id: int) -> void:
	var res := await ApiClient.get_player_stats(GameState.player_id)

	if id != render_id:
		return

	if not res.ok:
		clear_content()
		add_label("Impossible de charger les stats : " + res.error, 0, COLOR_ERROR)
		return

	stats_data = res.data
	render_stats()


func points_available() -> int:
	return int(GameState.player.get("stat_points", {}).get("available", 0))


func pending_total() -> int:
	var total := 0

	for stat in pending_points:
		total += int(pending_points[stat])

	return total


func render_stats() -> void:
	clear_content()

	# Le pool a pu baisser depuis le dernier choix : on repart de zéro.
	if pending_total() > points_available():
		pending_points.clear()

	var player: Dictionary = GameState.player
	var level := int(player.get("level", 1))
	var xp := int(player.get("xp", 0))
	var xp_needed := int(stats_data.get("xp_to_next_level", 1))

	add_label("Niveau %d" % level, 24)

	var xp_bar := ProgressBar.new()
	xp_bar.max_value = max(xp_needed, 1)
	xp_bar.value = xp
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0, 14)
	content.add_child(xp_bar)

	add_label("%d / %d XP" % [xp, xp_needed], 0, COLOR_MUTED)
	add_label("💰 %d or" % int(player.get("currency", {}).get("or", 0)))

	add_section_title("Statistiques")

	var remaining := points_available() - pending_total()

	add_label(
		"Points à répartir : %d" % remaining,
		0,
		COLOR_HIGHLIGHT if remaining > 0 else COLOR_MUTED
	)

	var stats: Dictionary = stats_data.get("stats", {})
	var point_value: Dictionary = stats_data.get("point_value", {})
	var spent: Dictionary = player.get("stat_points", {}).get("spent", {})

	for stat in STAT_ORDER:
		content.add_child(
			build_stat_row(
				stat,
				float(stats.get(stat, 0)),
				float(point_value.get(stat, 0)),
				int(spent.get(stat, 0)),
				remaining
			)
		)

	var gains := PackedStringArray()

	for stat in STAT_ORDER:
		gains.append("%s +%s" % [STAT_LABELS[stat], format_number(float(point_value.get(stat, 0)))])

	add_label("Un point donne : " + ", ".join(gains), 12, COLOR_MUTED)

	if not error_message.is_empty():
		add_label("⚠ " + error_message, 0, COLOR_ERROR)

	if pending_total() > 0:
		add_label("Les points répartis sont définitifs.", 12, COLOR_MUTED)
		content.add_child(build_allocation_buttons())


func build_stat_row(
	stat: String,
	value: float,
	value_per_point: float,
	spent_points: int,
	remaining: int
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := make_label(STAT_LABELS[stat])
	name_label.custom_minimum_size = Vector2(44, 0)
	row.add_child(name_label)

	var pending := int(pending_points.get(stat, 0))
	var value_text := format_number(value)

	if pending > 0:
		value_text += "  → " + format_number(value + pending * value_per_point)

	var value_label := make_label(value_text, 0, COLOR_BONUS if pending > 0 else null)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)

	var spent_text := "%d pts" % spent_points

	if pending > 0:
		spent_text += " +%d" % pending

	row.add_child(make_label(spent_text, 12, COLOR_MUTED))

	var minus_button := Button.new()
	minus_button.text = "−"
	minus_button.custom_minimum_size = Vector2(40, 40)
	minus_button.disabled = pending <= 0 or is_submitting
	minus_button.pressed.connect(func(): change_pending(stat, -1))
	row.add_child(minus_button)

	var plus_button := Button.new()
	plus_button.text = "+"
	plus_button.custom_minimum_size = Vector2(40, 40)
	plus_button.disabled = remaining <= 0 or is_submitting
	plus_button.pressed.connect(func(): change_pending(stat, 1))
	row.add_child(plus_button)

	return row


func build_allocation_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()

	var cancel_button := Button.new()
	cancel_button.text = "Annuler"
	cancel_button.custom_minimum_size = Vector2(0, 48)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.disabled = is_submitting
	cancel_button.pressed.connect(
		func():
			pending_points.clear()
			error_message = ""
			render_stats()
	)
	row.add_child(cancel_button)

	var confirm_button := Button.new()
	confirm_button.text = "Envoi..." if is_submitting else "Valider (%d)" % pending_total()
	confirm_button.custom_minimum_size = Vector2(0, 48)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.disabled = is_submitting
	confirm_button.pressed.connect(submit_allocation)
	row.add_child(confirm_button)

	return row


func change_pending(stat: String, delta: int) -> void:
	var next := int(pending_points.get(stat, 0)) + delta

	if next <= 0:
		pending_points.erase(stat)
	elif delta < 0 or pending_total() < points_available():
		pending_points[stat] = next

	error_message = ""
	render_stats()


func submit_allocation() -> void:
	if is_submitting or pending_total() <= 0:
		return

	var allocations := pending_points.duplicate()

	is_submitting = true
	error_message = ""
	render_stats()

	# Les points en attente sont vidés avant l'envoi : le rechargement du
	# joueur qui suit le succès doit afficher l'état sans prévisualisation.
	pending_points.clear()

	var res := await GameState.perform_action(
		"allocate_stat_points",
		{"allocations": allocations}
	)

	is_submitting = false

	if not res.ok:
		pending_points = allocations
		error_message = res.error
		render_stats()


# --- Onglet Inventaire ----------------------------------------------------

func refresh_inventory(id: int) -> void:
	var inventory: Dictionary = GameState.player.get("inventory", {})

	clear_content()

	if inventory.is_empty():
		add_label("Ton inventaire est vide.", 0, COLOR_MUTED)
		return

	var missing: Array = []

	for item_id in inventory:
		if not item_templates.has(item_id):
			missing.append(item_id)

	if not missing.is_empty():
		add_label("Chargement de l'inventaire...", 0, COLOR_MUTED)

		for item_id in missing:
			var res := await ApiClient.get_template("item", item_id)

			if id != render_id:
				return

			# Un template introuvable reste affiché avec son identifiant.
			item_templates[item_id] = res.data if res.ok else {}

	render_inventory()


func item_name(item_id: String) -> String:
	return item_templates.get(item_id, {}).get("name", item_id)


func render_inventory() -> void:
	clear_content()

	var inventory: Dictionary = GameState.player.get("inventory", {})
	var groups: Dictionary = {}

	for item_id in inventory:
		var category: String = item_templates.get(item_id, {}).get("category", "other")

		if not ITEM_CATEGORY_LABELS.has(category):
			category = "other"

		if not groups.has(category):
			groups[category] = []

		groups[category].append(item_id)

	var first_group := true

	for category in ITEM_CATEGORY_ORDER:
		if not groups.has(category):
			continue

		var item_ids: Array = groups[category]
		item_ids.sort_custom(func(a, b): return item_name(a).naturalnocasecmp_to(item_name(b)) < 0)

		if first_group:
			add_label("%s  (%d)" % [ITEM_CATEGORY_LABELS[category], item_ids.size()], 20)
			first_group = false
		else:
			add_section_title("%s  (%d)" % [ITEM_CATEGORY_LABELS[category], item_ids.size()])

		for item_id in item_ids:
			var button := Button.new()
			button.text = "%s  ×%d" % [item_name(item_id), int(inventory[item_id])]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 46)
			button.pressed.connect(func(): show_item_detail(item_id))
			content.add_child(button)


func show_item_detail(item_id: String) -> void:
	# Invalide un éventuel chargement d'inventaire encore en cours.
	render_id += 1
	clear_content()
	scroll.scroll_vertical = 0

	var back_to_list := Button.new()
	back_to_list.text = "← Inventaire"
	back_to_list.custom_minimum_size = Vector2(0, 44)
	back_to_list.pressed.connect(func(): refresh())
	content.add_child(back_to_list)

	var template: Dictionary = item_templates.get(item_id, {})
	var quantity := int(GameState.player.get("inventory", {}).get(item_id, 0))

	add_label(item_name(item_id), 24)

	if template.is_empty():
		add_label("Quantité : %d" % quantity)
		add_label("Détails indisponibles pour cet objet.", 0, COLOR_MUTED)
		return

	var category: String = template.get("category", "")
	add_label(
		"%s · Niveau %d" % [
			ITEM_CATEGORY_NAMES.get(category, "Objet"),
			int(template.get("level", 1))
		],
		0,
		COLOR_MUTED
	)
	add_label("Quantité : %d" % quantity)
	add_label(template.get("description", ""))

	if category == "equipment":
		add_equipment_details(template.get("equipment", {}))
	elif category == "consumable":
		add_consumable_details(template.get("consumable", {}))

	add_label("💰 Valeur : %d or" % int(template.get("base_value", 0)), 0, COLOR_MUTED)


func add_equipment_details(equipment: Dictionary) -> void:
	add_section_title("Équipement")

	var slot: String = equipment.get("slot", "")
	add_label("Emplacement : " + SLOT_LABELS.get(slot, slot))

	var level_required := int(equipment.get("level_required", 1))
	var player_level := int(GameState.player.get("level", 1))
	add_label(
		"Niveau requis : %d" % level_required,
		0,
		COLOR_ERROR if player_level < level_required else null
	)

	var bonuses: Dictionary = equipment.get("stat_bonuses", {})

	for stat in STAT_ORDER:
		if bonuses.has(stat):
			add_label(
				"%s +%s" % [STAT_LABELS[stat], format_number(float(bonuses[stat]))],
				0,
				COLOR_BONUS
			)


func add_consumable_details(consumable: Dictionary) -> void:
	add_section_title("Effet")

	var amount := float(consumable.get("amount", 0))
	var duration := int(consumable.get("duration_seconds", 0))
	var effect_type: String = consumable.get("effect_type", "")
	var text := ""

	match effect_type:
		"heal":
			text = "Soigne %s PV" % format_number(amount)
		"restore_mana":
			text = "Rend %s mana" % format_number(amount)
		"buff_stat":
			var stat: String = consumable.get("stat", "")
			text = "%s +%s" % [STAT_LABELS.get(stat, stat), format_number(amount)]
		_:
			text = effect_type

	if duration > 0:
		text += " pendant %d s" % duration

	add_label(text, 0, COLOR_BONUS)
