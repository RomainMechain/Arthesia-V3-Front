extends Control

# Écran d'une zone, en deux pages construites en code dans Body :
#
# * la liste : description, filtres par catégorie, une carte par entry
#   (nom, sous-titre selon le type, disponibilité) ;
# * la fiche d'une entry : contenu propre à chaque type (monstre, ressource,
#   habitant, quête, commerce).
#
# Le bouton retour du haut ramène de la fiche à la liste, puis à la carte.

signal back_requested
signal _load_finished

const COMBAT_SCREEN_SCENE := preload("res://scene/combat/CombatScreen.tscn")
const RESOURCE_PANEL_SCRIPT := preload("res://scripts/zone/resource_panel.gd")
const QUEST_PANEL_SCRIPT := preload("res://scripts/quests/quest_panel.gd")
const SHOP_PANEL_SCRIPT := preload("res://scripts/commerce/shop_panel.gd")
const MARKET_PANEL_SCRIPT := preload("res://scripts/commerce/market_panel.gd")

const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR
const COLOR_DANGER := Color(0.95, 0.55, 0.45)

# Ordre d'affichage des catégories. Plusieurs template_type peuvent partager
# une catégorie (boutique PNJ et Autel des Ventes sont tous deux du commerce).
const CATEGORY_ORDER := ["combat", "resources", "npcs", "quests", "commerce", "exploration"]

const CATEGORY_NAMES := {
	"combat": "Combat",
	"resources": "Ressources",
	"npcs": "Habitants",
	"quests": "Quêtes",
	"commerce": "Commerce",
	"exploration": "Exploration",
}

const CATEGORY_ICONS := {
	"combat": "⚔",
	"resources": "🌿",
	"npcs": "👤",
	"quests": "📜",
	"commerce": "🛒",
	"exploration": "🔎",
}

const ROLE_LABELS := {
	"elite": "⭐ Élite",
	"boss": "👑 Boss",
}

const STAT_ORDER := ["hp", "atk", "def", "agi", "int", "sag"]
const STAT_LABELS := {"hp": "PV", "atk": "ATK", "def": "DEF", "agi": "AGI", "int": "INT", "sag": "SAG"}

@onready var back_button: Button = $Layout/Header/BackButton
@onready var title_label: Label = $Layout/Header/Title
@onready var scroll: ScrollContainer = $Layout/Scroll
@onready var body: VBoxContainer = $Layout/Scroll/Body

var zone_data: Dictionary = {}
var loaded_templates: Dictionary = {}
var item_names: Dictionary = {}

# Disponibilité des entries partagées (GET /zones/{id}/state), et instant de
# réception pour faire défiler les comptes à rebours.
var entry_states: Dictionary = {}
var states_received_msec := 0

var current_filter := "all"
var current_entry: Dictionary = {}
var list_scroll := 0

# Sous-titres des cartes de la liste à rafraîchir pendant les comptes à rebours.
var status_labels: Dictionary = {}
var status_timer := 0.0
var is_refreshing_state := false

# Incrémenté à chaque changement de page : un chargement terminé après coup
# ne doit pas reconstruire une page qui n'est plus affichée.
var page_id := 0


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	GameState.player_changed.connect(_on_player_changed)


# Une quête acceptée ou rendue peut changer les sous-titres et déverrouiller
# des entries : la liste est reconstruite (les fiches se mettent à jour seules).
func _on_player_changed(_player: Dictionary) -> void:
	if zone_data.get("entries", []).is_empty() or not current_entry.is_empty():
		return

	await refresh_states()

	if current_entry.is_empty():
		show_list(false)


func setup(data: Dictionary) -> void:
	zone_data = data
	title_label.text = data.get("name", "Zone")

	clear_body()
	add_label(data.get("description", ""), 13, COLOR_MUTED)
	add_label("Chargement de la zone...", 14, COLOR_MUTED)

	var zone_id: String = data.get("id", "")
	var res := await ApiClient.get_zone(zone_id)

	if not res.ok:
		clear_body()
		add_label(data.get("description", ""), 13, COLOR_MUTED)

		if res.status == 404:
			add_label("Cette zone n'a pas encore de contenu.", 15, COLOR_MUTED)
		else:
			add_label("Impossible de charger la zone : " + res.error, 14, COLOR_ERROR)
		return

	zone_data = res.data
	title_label.text = zone_data.get("name", "Zone")

	# Templates et disponibilité sont chargés en parallèle.
	var counter := {"pending": 1}
	_refresh_states_counted(counter)
	await load_templates(zone_data.get("entries", []), counter)

	show_list()


# --- Chargements --------------------------------------------------------------

# Lance toutes les requêtes de templates en même temps et attend la dernière.
# counter peut déjà compter d'autres requêtes lancées en parallèle.
func load_templates(entries: Array, counter := {"pending": 0}) -> void:
	var requested := {}

	for entry in entries:
		var template_id: String = entry.get("template_id", "")

		if template_id.is_empty() or loaded_templates.has(template_id) or requested.has(template_id):
			continue

		requested[template_id] = true
		counter.pending += 1
		_load_template(entry, counter)

	while counter.pending > 0:
		await _load_finished


func _load_template(entry: Dictionary, counter: Dictionary) -> void:
	var res := await ApiClient.get_template(ApiClient.template_kind_for_entry(entry), entry.get("template_id", ""))

	if res.ok:
		loaded_templates[entry.get("template_id", "")] = res.data

	counter.pending -= 1
	_load_finished.emit()


func _refresh_states_counted(counter: Dictionary) -> void:
	await refresh_states()
	counter.pending -= 1
	_load_finished.emit()


func load_item_names(item_ids: Array) -> void:
	var missing: Array = item_ids.filter(func(item_id): return not item_names.has(item_id))
	var found := await ApiClient.get_templates("item", missing)

	for item_id in missing:
		item_names[item_id] = found.get(item_id, {}).get("name", GameText.prettify_id(item_id))


func refresh_states() -> void:
	is_refreshing_state = true
	var res := await ApiClient.get_zone_state(zone_data.get("id", ""), GameState.player_id)
	is_refreshing_state = false

	if res.ok:
		entry_states = res.data.get("entries", {})
		states_received_msec = Time.get_ticks_msec()


func template_of(entry: Dictionary) -> Dictionary:
	return loaded_templates.get(entry.get("template_id", ""), {})


# --- Outils d'affichage -------------------------------------------------------

func clear_body() -> void:
	status_labels.clear()

	for child in body.get_children():
		child.queue_free()


func make_label(text: String, font_size := 0, color = null, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)

	if color != null:
		label.add_theme_color_override("font_color", color)

	return label


func add_label(text: String, font_size := 0, color = null) -> Label:
	var label := make_label(text, font_size, color)
	body.add_child(label)
	return label


func add_section_title(text: String) -> void:
	add_label(text, 17)


func add_card(lines: Array) -> PanelContainer:
	var card := UiStyle.make_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	for line in lines:
		box.add_child(line)

	body.add_child(card)
	return card


# Fondu et léger glissement à l'arrivée d'une page.
func animate_page(from_right: bool) -> void:
	body.modulate.a = 0.0
	body.position.x = 24.0 if from_right else -24.0

	var tween := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(body, "modulate:a", 1.0, 0.18)
	tween.tween_property(body, "position:x", 0.0, 0.18)


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


func category_label(category: String) -> String:
	return "%s %s" % [CATEGORY_ICONS.get(category, "•"), CATEGORY_NAMES.get(category, category)]


# --- Disponibilité ------------------------------------------------------------

# Secondes restantes avant réapparition, d'après le dernier état reçu.
func seconds_left(entry_id: String) -> float:
	var state: Dictionary = entry_states.get(entry_id, {})
	var elapsed := (Time.get_ticks_msec() - states_received_msec) / 1000.0
	return max(0.0, float(state.get("seconds_until_available", 0)) - elapsed)


func is_entry_available(entry: Dictionary) -> bool:
	var state: Dictionary = entry_states.get(entry.get("id", ""), {})
	return state.get("status", "available") == "available"


# [texte, couleur] de disponibilité, texte vide pour une entry toujours présente.
func availability(entry: Dictionary) -> Array:
	var entry_id: String = entry.get("id", "")
	var state: Dictionary = entry_states.get(entry_id, {})
	var status: String = state.get("status", "available")

	match status:
		"available":
			if state.has("max_stock"):
				return ["stock %d/%d" % [int(state.get("current_stock", 0)), int(state["max_stock"])], COLOR_BONUS]
			return ["", null]
		"defeated":
			if state.get("echo_available", false):
				return ["💀 Vaincu · écho disponible", COLOR_HIGHLIGHT]
			return ["💀 Vaincu", COLOR_MUTED]
		"depleted":
			var left := seconds_left(entry_id)
			if left <= 0:
				return ["revient...", COLOR_HIGHLIGHT]
			return ["⏳ %d s" % ceili(left), COLOR_HIGHLIGHT]
		_:
			return ["Indisponible", COLOR_MUTED]


func _process(delta: float) -> void:
	if status_labels.is_empty():
		return

	status_timer += delta

	if status_timer < 0.5:
		return

	status_timer = 0.0
	var needs_refresh := false

	for entry_id in status_labels:
		var label: Label = status_labels[entry_id].label
		var info := availability(status_labels[entry_id].entry)
		label.text = info[0]

		if info[1] != null:
			label.add_theme_color_override("font_color", info[1])

		var state: Dictionary = entry_states.get(entry_id, {})

		if state.get("status", "") == "depleted" and seconds_left(entry_id) <= 0:
			needs_refresh = true

	# Une entry vient de réapparaître : on redemande l'état exact.
	if needs_refresh and not is_refreshing_state:
		await refresh_states()

		if current_entry.is_empty():
			show_list(false)


# --- Page liste ---------------------------------------------------------------

func show_list(animate := true) -> void:
	page_id += 1
	current_entry = {}
	clear_body()

	add_label(zone_data.get("description", ""), 13, COLOR_MUTED)

	var entries: Array = zone_data.get("entries", [])

	if entries.is_empty():
		add_label("Rien à faire ici pour l'instant.", 14, COLOR_MUTED)
		return

	var groups: Dictionary = {}

	for entry in entries:
		if entry_states.get(entry.get("id", ""), {}).get("hidden", false):
			continue

		var category := get_category(entry.get("template_type", ""))

		if not groups.has(category):
			groups[category] = []

		groups[category].append(entry)

	var ordered: Array = []

	for category in CATEGORY_ORDER:
		if groups.has(category):
			ordered.append(category)

	for category in groups:
		if not ordered.has(category):
			ordered.append(category)

	body.add_child(build_filters(ordered, groups))

	for category in ordered:
		if current_filter != "all" and current_filter != category:
			continue

		if current_filter == "all":
			add_section_title(category_label(category))

		for entry in groups[category]:
			if entry_states.get(entry.get("id", ""), {}).get("locked", false):
				body.add_child(build_locked_card(entry))
			else:
				body.add_child(build_entry_card(entry, category))

	if animate:
		animate_page(false)

	# Revient à la position de défilement de la liste après une fiche.
	await get_tree().process_frame
	scroll.scroll_vertical = list_scroll


func build_filters(ordered: Array, groups: Dictionary) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)

	var filters: Array = [["all", "Tout"]]

	for category in ordered:
		filters.append([category, "%s %d" % [CATEGORY_ICONS.get(category, "•"), groups[category].size()]])

	for filter in filters:
		var chip := Button.new()
		chip.text = filter[1]
		chip.toggle_mode = true
		chip.button_pressed = current_filter == filter[0]
		chip.custom_minimum_size = Vector2(52, 36)
		chip.add_theme_font_size_override("font_size", 14)
		chip.tooltip_text = CATEGORY_NAMES.get(filter[0], "Tout")
		chip.pressed.connect(
			func():
				current_filter = filter[0]
				list_scroll = 0
				show_list(false)
		)
		flow.add_child(chip)

	return flow


func build_entry_card(entry: Dictionary, category: String) -> Button:
	var template := template_of(entry)
	var button := UiStyle.make_card_button()
	button.pressed.connect(func(): open_entry_detail(entry))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.add_theme_constant_override("separation", 12)
	button.add_child(row)

	var icon := make_label(CATEGORY_ICONS.get(category, "•"), 22, null, false)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.custom_minimum_size = Vector2(28, 0)
	row.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 1)

	var name_label := make_label(template.get("name", GameText.prettify_id(entry.get("template_id", ""))), 15, null, false)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(name_label)

	var subtitle := entry_subtitle(entry, template)

	if not subtitle.is_empty():
		var subtitle_label := make_label(subtitle, 12, COLOR_MUTED, false)
		subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text_box.add_child(subtitle_label)

	row.add_child(text_box)

	# Disponibilité à droite (stock, compte à rebours), mise à jour en continu.
	var info := availability(entry)
	var status_label := make_label(info[0], 12, info[1], false)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(status_label)
	status_labels[entry.get("id", "")] = {"label": status_label, "entry": entry}

	var chevron := make_label("›", 22, COLOR_MUTED, false)
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chevron)

	return button


# Entry dont la condition d'apparition n'est pas remplie : seul l'indice est
# montré, sans le nom (il fait partie de la découverte).
func build_locked_card(entry: Dictionary) -> PanelContainer:
	var card := UiStyle.make_card(Color(0.13, 0.13, 0.14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var icon := make_label("🔒", 20, null, false)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.custom_minimum_size = Vector2(28, 0)
	row.add_child(icon)

	var hint: String = str(entry_states.get(entry.get("id", ""), {}).get("hint", ""))

	if hint.is_empty() or hint == "<null>":
		hint = "Quelque chose se cache ici..."

	var text := make_label(hint, 12, COLOR_MUTED)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)

	return card


func entry_subtitle(entry: Dictionary, template: Dictionary) -> String:
	match entry.get("template_type", ""):
		"monster":
			var text := "Niveau %d" % int(template.get("level", 1))
			var role: String = template.get("role", "normal")
			if ROLE_LABELS.has(role):
				text += " · " + ROLE_LABELS[role]
			return text
		"resource":
			var requirement = template.get("profession_required")
			if requirement is Dictionary:
				return "%s niv. %d" % [GameText.profession_label(requirement.get("profession_id", "")), int(requirement.get("min_level", 1))]
			return "Ressource"
		"npc":
			return str(template.get("role", "Habitant"))
		"quest_giver":
			return quest_subtitle(template)
		"shop":
			var offers: int = template.get("sell_offers", []).size()
			return "Boutique · %d article%s" % [offers, "s" if offers > 1 else ""]
		"player_market":
			return "Autel des Ventes · entre joueurs"
		_:
			return ""


func quest_subtitle(template: Dictionary) -> String:
	var objectives: Array = template.get("objectives", [])
	var quest_id: String = template.get("id", "")

	match GameState.quest_state(quest_id):
		"completed":
			return "Terminée" + (" · répétable" if template.get("repeatable", false) else "")
		"active":
			var done := 0

			for index in objectives.size():
				var progress := GameState.quest_objective_progress(quest_id, objectives[index], index)

				if progress[0] >= progress[1]:
					done += 1

			if done == objectives.size():
				return "✅ Prête à rendre"

			return "En cours · %d / %d objectif%s" % [done, objectives.size(), "s" if objectives.size() > 1 else ""]
		_:
			return "Nouvelle quête · %d objectif%s" % [objectives.size(), "s" if objectives.size() > 1 else ""]


# --- Page fiche -----------------------------------------------------------

func open_entry_detail(entry: Dictionary) -> void:
	if current_entry.is_empty():
		list_scroll = scroll.scroll_vertical

	page_id += 1
	current_entry = entry
	clear_body()
	scroll.scroll_vertical = 0

	var template := template_of(entry)

	match entry.get("template_type", ""):
		"resource":
			var panel = RESOURCE_PANEL_SCRIPT.new()
			body.add_child(panel)
			panel.setup(zone_data.get("id", ""), entry, template)
		"monster":
			show_monster_detail(entry, template)
		"npc":
			show_npc_detail(template)
		"quest_giver":
			var quest_panel = QUEST_PANEL_SCRIPT.new()
			body.add_child(quest_panel)
			quest_panel.setup(template, true)
		"shop":
			var shop_panel = SHOP_PANEL_SCRIPT.new()
			body.add_child(shop_panel)
			shop_panel.setup(zone_data.get("id", ""), entry, template)
		"player_market":
			var market_panel = MARKET_PANEL_SCRIPT.new()
			body.add_child(market_panel)
			market_panel.setup(zone_data.get("id", ""), entry, template)
		_:
			show_generic_detail(entry, template)

	animate_page(true)


func add_detail_header(entry_name: String, meta: String, meta_color = COLOR_MUTED) -> void:
	add_label(entry_name, 22)

	if not meta.is_empty():
		add_label(meta, 13, meta_color)


func add_description(template: Dictionary) -> void:
	var description: String = template.get("description", "")

	if not description.is_empty():
		add_label(description, 13, COLOR_MUTED)


# ----- Monstre -----

func show_monster_detail(entry: Dictionary, template: Dictionary) -> void:
	var role: String = template.get("role", "normal")
	var meta := "Niveau %d" % int(template.get("level", 1))

	if ROLE_LABELS.has(role):
		meta += " · " + ROLE_LABELS[role]

	add_detail_header(template.get("name", "Monstre"), meta, COLOR_HIGHLIGHT if ROLE_LABELS.has(role) else COLOR_MUTED)
	add_description(template)

	# Statistiques en grille 3 × 2.
	var stats: Dictionary = template.get("stats", {})
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)

	for stat in STAT_ORDER:
		var tile := UiStyle.make_card()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tile_box := VBoxContainer.new()
		tile_box.add_theme_constant_override("separation", 0)
		var value := make_label(GameText.format_number(float(stats.get(stat, 0))), 18, null, false)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var label := make_label(STAT_LABELS[stat], 11, COLOR_MUTED, false)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile_box.add_child(value)
		tile_box.add_child(label)
		tile.add_child(tile_box)
		grid.add_child(tile)

	body.add_child(grid)

	var moveset: Array = template.get("moveset", [])

	if not moveset.is_empty():
		var lines: Array = [make_label("Attaques", 15, null, false)]

		for move in moveset:
			lines.append(
				make_label(
					"%s · %s dégâts · toutes les %s s" % [
						GameText.prettify_id(str(move.get("id", ""))),
						GameText.format_number(float(move.get("damage", 0))),
						GameText.format_number(float(move.get("cooldown_seconds", 0)))
					],
					13,
					COLOR_DANGER
				)
			)

		add_card(lines)

	var loot_table: Array = template.get("loot_table", [])
	var loot_box: VBoxContainer = null

	if not loot_table.is_empty():
		var card := add_card([make_label("Butin possible", 15, null, false)])
		loot_box = card.get_child(0) as VBoxContainer

	var available := is_entry_available(entry)
	# Boss d'étage déjà vaincu : son écho s'affronte une fois, pour l'XP seulement.
	var echo: bool = entry_states.get(entry.get("id", ""), {}).get("echo_available", false)

	if echo:
		add_label("Ce gardien a déjà été vaincu, et son butin est parti avec le premier vainqueur. Son écho rôde encore : l'affronter ne rapporte que de l'expérience, une seule fois.", 13, COLOR_HIGHLIGHT)
	elif not available:
		add_label("Ce monstre n'est pas là pour l'instant (%s)." % availability(entry)[0], 13, COLOR_HIGHLIGHT)

	var fight_button := Button.new()
	fight_button.text = "👻 Affronter l'écho (XP seulement)" if echo else "⚔ Combattre"
	fight_button.custom_minimum_size = Vector2(0, 54)
	fight_button.add_theme_font_size_override("font_size", 18)
	fight_button.disabled = not available and not echo
	fight_button.pressed.connect(func(): open_combat(entry))
	body.add_child(fight_button)

	# Les noms du butin arrivent après coup sans bloquer l'affichage.
	if loot_box == null:
		return

	var id := page_id
	var item_ids: Array = []

	for loot in loot_table:
		item_ids.append(str(loot.get("item_id", "")))

	await load_item_names(item_ids)

	if id != page_id:
		return

	var total_weight := 0.0

	for loot in loot_table:
		total_weight += float(loot.get("weight", 1))

	for loot in loot_table:
		var quantity_min := int(loot.get("quantity_min", 1))
		var quantity_max := int(loot.get("quantity_max", quantity_min))
		var quantity := "×%d" % quantity_min if quantity_min == quantity_max else "×%d–%d" % [quantity_min, quantity_max]
		var chance: float = float(loot.get("weight", 1)) / maxf(total_weight, 1.0) * 100.0
		loot_box.add_child(
			make_label("%s %s  (%d %%)" % [item_names.get(str(loot.get("item_id", "")), ""), quantity, roundi(chance)], 13, COLOR_BONUS)
		)


# ----- Habitant -----

func show_npc_detail(template: Dictionary) -> void:
	add_detail_header(template.get("name", "Habitant"), str(template.get("role", "")))
	add_description(template)

	var dialogues: Array = template.get("dialogues", [])

	if dialogues.is_empty():
		return

	var bubble := UiStyle.make_card(Color(0.2, 0.19, 0.16))
	var quote := make_label("« %s »" % dialogues[0], 14)
	bubble.add_child(quote)
	body.add_child(bubble)

	var talk_button := Button.new()
	talk_button.text = "💬 Parler"
	talk_button.custom_minimum_size = Vector2(0, 48)
	body.add_child(talk_button)

	var index := {"value": 0}
	talk_button.pressed.connect(
		func():
			index.value = (index.value + 1) % dialogues.size()
			quote.text = "« %s »" % dialogues[index.value]
			bubble.modulate.a = 0.0
			create_tween().tween_property(bubble, "modulate:a", 1.0, 0.2)
	)


func show_generic_detail(entry: Dictionary, template: Dictionary) -> void:
	add_detail_header(template.get("name", GameText.prettify_id(entry.get("template_id", ""))), "")
	add_description(template)


# --- Navigation ---------------------------------------------------------------

func _on_back_pressed() -> void:
	if current_entry.is_empty():
		back_requested.emit()
		return

	# Retour à la liste : la disponibilité a pu changer (récolte...).
	page_id += 1
	var id := page_id
	await refresh_states()

	if id == page_id:
		show_list()


func open_combat(entry: Dictionary) -> void:
	var combat_screen = COMBAT_SCREEN_SCENE.instantiate()

	add_child(combat_screen)
	combat_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	combat_screen.prepare_combat(
		zone_data.get("id", ""),
		entry,
		template_of(entry)
	)

	combat_screen.back_requested.connect(
		func():
			combat_screen.queue_free()
			# Le monstre vient peut-être d'être vaincu : on rafraîchit la fiche.
			await refresh_states()

			if current_entry == entry:
				open_entry_detail(entry)
	)
