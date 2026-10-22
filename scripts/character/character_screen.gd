extends Control

# Écran Personnage, en quatre onglets :
#
# * Stats : niveau, XP, or et répartition des points de statistiques ;
# * Sac : inventaire groupé par catégorie, fiche détail, équiper un objet ;
# * Équipement : les 8 emplacements, équiper, changer ou retirer ;
# * Compétences : titres, puis compétences actives et passives équipées ou
#   disponibles.
#
# Le contenu des onglets est construit en code dans Content. Il est
# reconstruit à chaque changement du joueur (GameState.player_changed).

signal back_requested

const ITEM_BROWSER := preload("res://scripts/ui/item_browser.gd")
const STAT_ORDER := ["hp", "atk", "def", "agi", "int", "sag"]

const STAT_LABELS := {
	"hp": "PV",
	"atk": "ATK",
	"def": "DEF",
	"agi": "AGI",
	"int": "INT",
	"sag": "SAG",
}

const STAT_NAMES := {
	"hp": "Points de vie",
	"atk": "Attaque",
	"def": "Défense",
	"agi": "Agilité",
	"int": "Intelligence",
	"sag": "Sagesse",
}

# Rôle de chaque stat en combat, d'après les formules de combat_engine.py.
const STAT_HINTS := {
	"hp": "Encaisser plus de coups",
	"atk": "Dégâts physiques",
	"def": "Réduit les dégâts subis",
	"agi": "Vitesse, critiques et esquive",
	"int": "Dégâts magiques et mana max",
	"sag": "Soins, boucliers et régénération de mana",
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

const SLOT_ORDER := ["weapon", "head", "chest", "gloves", "boots", "ring", "amulet", "tool"]

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

# Mêmes limites que MAX_ACTIVE_SKILL_SLOTS / MAX_PASSIVE_SKILL_SLOTS côté serveur.
const MAX_ACTIVE_SKILLS := 4
const MAX_PASSIVE_SKILLS := 4

const COLOR_CARD := UiStyle.COLOR_CARD
const COLOR_CARD_HIGHLIGHT := UiStyle.COLOR_CARD_HIGHLIGHT
const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_MALUS := UiStyle.COLOR_MALUS
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR
const COLOR_XP := UiStyle.COLOR_XP

@onready var back_button: Button = $Layout/Header/BackButton
@onready var stats_tab: Button = $Layout/Tabs/StatsTab
@onready var inventory_tab: Button = $Layout/Tabs/InventoryTab
@onready var equipment_tab: Button = $Layout/Tabs/EquipmentTab
@onready var skills_tab: Button = $Layout/Tabs/SkillsTab
@onready var scroll: ScrollContainer = $Layout/Scroll
@onready var content: VBoxContainer = $Layout/Scroll/Content
@onready var footer: HBoxContainer = $Layout/Footer
@onready var cancel_button: Button = $Layout/Footer/CancelButton
@onready var confirm_button: Button = $Layout/Footer/ConfirmButton

var current_tab := "stats"

# Réponse de GET /players/{id}/stats : stats finales, seuil d'XP, gain par point.
var stats_data: Dictionary = {}

# Points choisis mais pas encore envoyés au serveur : stat -> nombre.
var pending_points: Dictionary = {}

# Widgets de l'onglet Stats mis à jour sans reconstruire l'écran (sinon un
# bouton maintenu enfoncé serait détruit pendant l'appui).
var stat_widgets: Dictionary = {}
var points_label: Label
var stats_error_label: Label

var is_submitting := false
# Réinitialisation des points : premier appui = demande de confirmation.
var confirm_respec := false

var item_templates: Dictionary = {}
var skill_templates: Dictionary = {}
var title_templates: Dictionary = {}
var equipped_title_name := ""

# Incrémenté à chaque rendu : un chargement encore en cours pour un ancien
# rendu (autre onglet, joueur rechargé) ne doit pas écraser l'affichage.
var render_id := 0


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	stats_tab.pressed.connect(func(): show_tab("stats"))
	inventory_tab.pressed.connect(func(): show_tab("inventory"))
	equipment_tab.pressed.connect(func(): show_tab("equipment"))
	skills_tab.pressed.connect(func(): show_tab("skills"))
	cancel_button.pressed.connect(cancel_allocation)
	confirm_button.pressed.connect(submit_allocation)
	GameState.player_changed.connect(_on_player_changed)

	# 13 px : les quatre onglets tiennent sur la largeur d'un téléphone.
	for tab in [stats_tab, inventory_tab, equipment_tab, skills_tab]:
		tab.add_theme_font_size_override("font_size", 13)

	show_tab("stats")


func _on_player_changed(_player: Dictionary) -> void:
	refresh()


func show_tab(tab: String) -> void:
	current_tab = tab
	stats_tab.button_pressed = tab == "stats"
	inventory_tab.button_pressed = tab == "inventory"
	equipment_tab.button_pressed = tab == "equipment"
	skills_tab.button_pressed = tab == "skills"
	scroll.scroll_vertical = 0
	refresh()


func refresh() -> void:
	render_id += 1
	var id := render_id

	footer.visible = false

	match current_tab:
		"stats":
			await refresh_stats(id)
		"inventory":
			await refresh_inventory(id)
		"equipment":
			await refresh_equipment(id)
		"skills":
			await refresh_skills(id)


# --- Outils d'affichage ---------------------------------------------------

func clear_content() -> void:
	stat_widgets.clear()

	for child in content.get_children():
		child.queue_free()


func make_label(text: String, font_size := 0, color = null, wrap := true) -> Label:
	var label := Label.new()
	label.text = text

	# Un label qui passe à la ligne dans une HBox peut être écrasé à une
	# largeur nulle : on ne l'active que s'il a toute la largeur disponible.
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)

	if color != null:
		label.add_theme_color_override("font_color", color)

	return label


# Label d'une colonne extensible : raccourci (…) quand la place manque, au
# lieu d'élargir l'écran au-delà de celui du téléphone. À ne pas utiliser sur
# un label sans place réservée, qui disparaîtrait.
func make_shrinkable_label(text: String, font_size := 0, color = null) -> Label:
	var label := make_label(text, font_size, color, false)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func add_label(text: String, font_size := 0, color = null) -> Label:
	var label := make_label(text, font_size, color)
	content.add_child(label)
	return label


func add_section_title(text: String) -> void:
	var label := add_label(text, 18)
	label.add_theme_constant_override("line_spacing", 0)


func make_card(color := COLOR_CARD) -> PanelContainer:
	return UiStyle.make_card(color)


func make_button(text: String, width := 0.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 40)
	return button


func make_rich_label(bbcode: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 13)
	label.text = bbcode
	return label


func color_tag(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]


func format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))

	return "%.1f" % value


func show_error(message: String) -> void:
	var label := make_label("⚠ " + message, 0, COLOR_ERROR)
	content.add_child(label)
	content.move_child(label, 0)
	scroll.scroll_vertical = 0


# Exécute une action de jeu. En cas de succès, GameState recharge le joueur et
# l'onglet courant se reconstruit via player_changed.
func run_action(action: String, body: Dictionary) -> bool:
	if is_submitting:
		return false

	is_submitting = true
	var res := await GameState.perform_action(action, body)
	is_submitting = false

	if not res.ok:
		show_error(res.error)

	return res.ok


# --- Onglet Stats -----------------------------------------------------------

func refresh_stats(id: int) -> void:
	var res := await ApiClient.get_player_stats(GameState.player_id)
	equipped_title_name = await GameState.equipped_title_name()

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

	content.add_child(build_level_card())
	content.add_child(build_points_banner())

	var stats: Dictionary = stats_data.get("stats", {})
	var point_value: Dictionary = stats_data.get("point_value", {})
	var spent: Dictionary = GameState.player.get("stat_points", {}).get("spent", {})

	for stat in STAT_ORDER:
		content.add_child(
			build_stat_card(
				stat,
				float(stats.get(stat, 0)),
				float(point_value.get(stat, 0)),
				int(spent.get(stat, 0))
			)
		)

	stats_error_label = add_label("", 0, COLOR_ERROR)
	stats_error_label.visible = false

	add_respec_section()
	add_professions_section()
	add_account_section()
	update_stats_display()


# Rend tous les points dépensés, en ville : gratuit la première fois, puis
# payant (prix donné par le serveur dans stats_data.respec).
func add_respec_section() -> void:
	var spent: Dictionary = GameState.player.get("stat_points", {}).get("spent", {})
	var total := 0

	for stat in spent:
		total += int(spent[stat])

	if total <= 0:
		return

	var respec: Dictionary = stats_data.get("respec", {})
	var cost := int(respec.get("cost", 0))
	var gold := int(GameState.player.get("currency", {}).get("or", 0))

	add_section_title("🔄 Réinitialiser mes points")
	add_label(
		"Récupère tes %d points pour les répartir autrement. %s" % [
			total,
			"La première fois est gratuite." if cost == 0 else "Coût : %d or." % cost,
		],
		12,
		COLOR_MUTED
	)

	var price := "gratuit" if cost == 0 else "%d or" % cost
	var button := make_button("Réinitialiser (%s)" % price)

	if not bool(respec.get("in_town", false)):
		button.text = "Disponible seulement en ville"
		button.disabled = true
	elif gold < cost:
		button.text = "Il te faut %d or" % cost
		button.disabled = true
	elif confirm_respec:
		button.text = "Confirmer : tout réinitialiser (%s)" % price

	button.disabled = button.disabled or is_submitting
	button.pressed.connect(_on_respec_pressed)
	content.add_child(button)


func _on_respec_pressed() -> void:
	if not confirm_respec:
		confirm_respec = true
		render_stats()
		return

	confirm_respec = false
	is_submitting = true
	pending_points.clear()
	var res := await GameState.perform_action("reset_stat_points", {})
	is_submitting = false

	if current_tab != "stats":
		return

	if not res.ok:
		render_stats()
		show_error(res.error)
		return

	# Le rechargement du joueur a redessiné l'onglet pendant l'action : on
	# relit les stats (prix suivant compris) maintenant qu'elle est terminée.
	refresh()


func add_account_section() -> void:
	add_section_title("👤 Compte")
	add_label("%s · %s" % [GameState.player.get("display_name", ""), Auth.email], 13, COLOR_MUTED)

	var sign_out := make_button("Se déconnecter")
	sign_out.pressed.connect(func(): Auth.sign_out())
	content.add_child(sign_out)


func add_professions_section() -> void:
	add_section_title("🛠 Métiers")

	var professions: Dictionary = GameState.player.get("professions", {})

	if professions.is_empty():
		add_label("Aucun métier pratiqué. Récolte des ressources dans les zones pour progresser.", 13, COLOR_MUTED)
		return

	var thresholds: Dictionary = stats_data.get("profession_xp_to_next_level", {})
	var profession_ids: Array = professions.keys()
	profession_ids.sort_custom(
		func(a, b): return GameText.profession_name(a).naturalnocasecmp_to(GameText.profession_name(b)) < 0
	)

	for profession_id in profession_ids:
		var profession: Dictionary = professions[profession_id]
		var xp := int(profession.get("xp", 0))
		var xp_needed := int(thresholds.get(profession_id, 0))

		var card := make_card()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)

		var row := HBoxContainer.new()
		var name_label := make_label(GameText.profession_label(profession_id), 15, null, false)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(make_label("Niveau %d" % int(profession.get("level", 1)), 15, COLOR_HIGHLIGHT, false))
		box.add_child(row)

		if xp_needed > 0:
			var bar := ProgressBar.new()
			bar.max_value = xp_needed
			bar.value = xp
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 8)
			UiStyle.style_bar(bar, COLOR_BONUS)
			box.add_child(bar)
			box.add_child(make_label("%d / %d XP" % [xp, xp_needed], 11, COLOR_MUTED, false))

		content.add_child(card)


func build_level_card() -> PanelContainer:
	var player: Dictionary = GameState.player
	var level := int(player.get("level", 1))
	var xp := int(player.get("xp", 0))
	var xp_needed := int(stats_data.get("xp_to_next_level", 1))

	var card := make_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var top := HBoxContainer.new()
	var level_label := make_label("Niveau %d" % level, 22, null, false)
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(level_label)
	top.add_child(make_label("💰 %d or" % int(player.get("currency", {}).get("or", 0)), 16, COLOR_HIGHLIGHT, false))
	box.add_child(top)

	if not equipped_title_name.is_empty():
		box.add_child(make_label("🏅 " + equipped_title_name, 14, COLOR_HIGHLIGHT, false))

	var hp := GameState.current_hp()
	var max_hp := GameState.max_hp()
	var hp_text := "❤ %d / %d PV" % [int(hp), int(max_hp)]

	if hp < max_hp:
		hp_text += " · pleins dans %s" % format_duration(int(player.get("health_view", {}).get("full_in_seconds", 0)))

	box.add_child(make_label(hp_text, 13, UiStyle.COLOR_HP if hp >= max_hp else COLOR_MALUS, false))

	var xp_bar := ProgressBar.new()
	xp_bar.max_value = max(xp_needed, 1)
	xp_bar.value = xp
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0, 12)
	UiStyle.style_bar(xp_bar, COLOR_XP)
	box.add_child(xp_bar)

	box.add_child(make_label("%d / %d XP avant le niveau %d" % [xp, xp_needed, level + 1], 12, COLOR_MUTED, false))

	return card


func format_duration(seconds: int) -> String:
	if seconds < 60:
		return "%d s" % seconds

	return "%d min" % ceili(seconds / 60.0)


func build_points_banner() -> PanelContainer:
	var card := make_card(COLOR_CARD_HIGHLIGHT)
	var row := HBoxContainer.new()
	card.add_child(row)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_child(make_shrinkable_label("Points à répartir", 16))
	text_box.add_child(make_shrinkable_label("Maintiens + pour en ajouter plusieurs", 12, COLOR_MUTED))
	row.add_child(text_box)

	points_label = make_label("0", 28, COLOR_HIGHLIGHT, false)
	points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(points_label)

	return card


func build_stat_card(stat: String, value: float, value_per_point: float, spent_points: int) -> PanelContainer:
	var card := make_card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	# Nom, rôle et points déjà investis.
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	info.add_child(make_shrinkable_label(STAT_NAMES[stat], 16))
	info.add_child(make_shrinkable_label(STAT_HINTS[stat], 11, COLOR_MUTED))
	info.add_child(
		make_shrinkable_label(
			"%d pts · +%s %s/pt" % [spent_points, format_number(value_per_point), STAT_LABELS[stat]],
			11,
			COLOR_MUTED
		)
	)
	row.add_child(info)

	# Valeur actuelle et aperçu après validation.
	var values := VBoxContainer.new()
	values.alignment = BoxContainer.ALIGNMENT_CENTER
	values.custom_minimum_size = Vector2(52, 0)
	values.add_theme_constant_override("separation", 0)

	var value_label := make_label(format_number(value), 20, null, false)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	values.add_child(value_label)

	var preview_label := make_label("", 13, COLOR_BONUS, false)
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	values.add_child(preview_label)
	row.add_child(values)

	# Sélecteur − / nombre en attente / +.
	var stepper := HBoxContainer.new()
	stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	stepper.add_theme_constant_override("separation", 2)

	var minus_button := make_repeat_button("−", func(): return change_pending(stat, -1))
	stepper.add_child(minus_button)

	var pending_label := make_label("", 14, COLOR_BONUS, false)
	pending_label.custom_minimum_size = Vector2(30, 0)
	pending_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pending_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stepper.add_child(pending_label)

	var plus_button := make_repeat_button("+", func(): return change_pending(stat, 1))
	stepper.add_child(plus_button)
	row.add_child(stepper)

	stat_widgets[stat] = {
		"value": value,
		"value_per_point": value_per_point,
		"preview": preview_label,
		"pending": pending_label,
		"minus": minus_button,
		"plus": plus_button,
	}

	return card


# Bouton qui répète son action tant qu'il est maintenu enfoncé. L'action
# renvoie false quand elle ne peut plus s'appliquer, ce qui arrête la répétition.
func make_repeat_button(text: String, step: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(40, 40)

	var timer := Timer.new()
	button.add_child(timer)

	button.button_down.connect(
		func():
			if step.call():
				timer.start(0.4)
	)
	button.button_up.connect(timer.stop)
	timer.timeout.connect(
		func():
			if button.disabled or not step.call():
				timer.stop()
			else:
				timer.start(0.07)
	)

	return button


func change_pending(stat: String, delta: int) -> bool:
	if is_submitting:
		return false

	var current := int(pending_points.get(stat, 0))

	if delta < 0 and current <= 0:
		return false

	if delta > 0 and pending_total() >= points_available():
		return false

	if current + delta <= 0:
		pending_points.erase(stat)
	else:
		pending_points[stat] = current + delta

	stats_error_label.visible = false
	update_stats_display()
	return true


func update_stats_display() -> void:
	var remaining := points_available() - pending_total()

	points_label.text = str(remaining)

	for stat in stat_widgets:
		var widgets: Dictionary = stat_widgets[stat]
		var pending := int(pending_points.get(stat, 0))
		var preview_value: float = widgets.value + pending * widgets.value_per_point

		widgets.preview.text = "→ " + format_number(preview_value) if pending > 0 else ""
		widgets.pending.text = "+%d" % pending if pending > 0 else ""
		widgets.minus.disabled = pending <= 0 or is_submitting
		widgets.plus.disabled = remaining <= 0 or is_submitting

	footer.visible = pending_total() > 0
	cancel_button.disabled = is_submitting
	confirm_button.disabled = is_submitting
	confirm_button.text = "Envoi..." if is_submitting else "Valider %d point%s" % [
		pending_total(),
		"s" if pending_total() > 1 else ""
	]


func cancel_allocation() -> void:
	pending_points.clear()
	stats_error_label.visible = false
	update_stats_display()


func submit_allocation() -> void:
	if is_submitting or pending_total() <= 0:
		return

	var allocations := pending_points.duplicate()

	is_submitting = true
	update_stats_display()

	# Les points en attente sont vidés avant l'envoi : le rechargement du
	# joueur qui suit le succès doit afficher l'état sans prévisualisation.
	pending_points.clear()

	var res := await GameState.perform_action(
		"allocate_stat_points",
		{"allocations": allocations}
	)

	is_submitting = false

	if current_tab != "stats" or not is_instance_valid(stats_error_label):
		return

	if not res.ok:
		pending_points = allocations
		stats_error_label.text = "⚠ " + res.error
		stats_error_label.visible = true

	# Le rechargement du joueur a redessiné l'onglet pendant l'envoi, boutons
	# désactivés : on les réactive maintenant que l'envoi est terminé.
	update_stats_display()


# --- Chargement des templates ---------------------------------------------

# Charge les templates manquants d'une liste d'objets. Renvoie false si un
# rendu plus récent a pris la main pendant le chargement.
func ensure_item_templates(item_ids: Array, id: int) -> bool:
	var missing: Array = item_ids.filter(func(item_id): return not item_templates.has(item_id))

	if missing.is_empty():
		return true

	# Une seule requête ; un template introuvable reste affiché avec son identifiant.
	var found := await ApiClient.get_templates("item", missing)

	if id != render_id:
		return false

	item_templates.merge(found, true)
	return true


func ensure_skill_templates(skill_ids: Array, id: int) -> bool:
	for skill_id in skill_ids:
		if skill_templates.has(skill_id):
			continue

		var res := await ApiClient.get_template("skill", skill_id)

		if id != render_id:
			return false

		skill_templates[skill_id] = res.data if res.ok else {}

	return true


func item_name(item_id: String) -> String:
	return item_templates.get(item_id, {}).get("name", item_id)


func item_slot(item_id: String) -> String:
	return item_templates.get(item_id, {}).get("equipment", {}).get("slot", "")


func item_bonuses(item_id) -> Dictionary:
	if item_id == null:
		return {}

	return item_templates.get(item_id, {}).get("equipment", {}).get("stat_bonuses", {})


func equipped_item_ids() -> Array:
	var ids: Array = []

	for item_id in GameState.player.get("equipment", {}).values():
		if item_id:
			ids.append(item_id)

	return ids


func format_bonuses(bonuses: Dictionary) -> String:
	var parts := PackedStringArray()

	for stat in STAT_ORDER:
		if bonuses.has(stat):
			parts.append("%s +%s" % [STAT_LABELS[stat], format_number(float(bonuses[stat]))])

	return " · ".join(parts)


# --- Onglet Sac -----------------------------------------------------------

func refresh_inventory(id: int) -> void:
	var inventory: Dictionary = GameState.player.get("inventory", {})

	clear_content()

	if inventory.is_empty():
		add_label("Ton sac est vide.", 0, COLOR_MUTED)
		return

	add_label("Chargement du sac...", 0, COLOR_MUTED)

	if not await ensure_item_templates(inventory.keys() + equipped_item_ids(), id):
		return

	render_inventory()


func render_inventory() -> void:
	clear_content()

	var inventory: Dictionary = GameState.player.get("inventory", {})
	# Recherche, filtre de rang et catégories repliées (cartes construites à l'ouverture).
	var browser = ITEM_BROWSER.new()
	content.add_child(browser)
	browser.setup("sac", inventory.keys(), item_templates,
		func(item_id):
			var button := Button.new()
			button.text = "%s  ×%d" % [item_name(item_id), int(inventory[item_id])]
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			GameText.color_button(button, item_templates.get(item_id, {}))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 46)
			button.pressed.connect(func(): show_item_detail(item_id))
			return button
	)


func show_item_detail(item_id: String) -> void:
	# Invalide un éventuel chargement encore en cours.
	render_id += 1
	clear_content()
	scroll.scroll_vertical = 0

	var back_to_list := make_button("← Sac")
	back_to_list.pressed.connect(func(): refresh())
	content.add_child(back_to_list)

	var template: Dictionary = item_templates.get(item_id, {})
	var quantity := int(GameState.player.get("inventory", {}).get(item_id, 0))

	add_label(item_name(item_id), 22, GameText.rarity_color(template))

	if GameText.is_above_common(template):
		add_label("◆ " + GameText.rarity_name(template), 13, GameText.rarity_color(template))

	if template.is_empty():
		add_label("Quantité : %d" % quantity)
		add_label("Détails indisponibles pour cet objet.", 0, COLOR_MUTED)
		return

	var category: String = template.get("category", "")
	add_label(
		"%s · Niveau %d · Quantité %d" % [
			ITEM_CATEGORY_NAMES.get(category, "Objet"),
			int(template.get("level", 1)),
			quantity
		],
		13,
		COLOR_MUTED
	)
	add_label(template.get("description", ""))

	if category == "equipment":
		content.add_child(build_equip_candidate_card(item_id))
	elif category == "consumable":
		add_consumable_details(template.get("consumable", {}))

		# Hors combat, seuls les soins s'utilisent : ils rendent les PV perdus.
		if template.get("consumable", {}).get("effect_type", "") == "heal":
			var use_button := make_button("Utiliser")
			use_button.disabled = GameState.current_hp() >= GameState.max_hp()

			if use_button.disabled:
				use_button.text = "Utiliser (PV déjà au maximum)"

			use_button.pressed.connect(func(): use_item(item_id))
			content.add_child(use_button)

	add_label("💰 Valeur : %d or" % int(template.get("base_value", 0)), 13, COLOR_MUTED)


func use_item(item_id: String) -> void:
	if await run_action("use_item", {"item_id": item_id}):
		# player_changed a reconstruit le sac : on revient sur l'objet s'il en reste.
		if int(GameState.player.get("inventory", {}).get(item_id, 0)) > 0:
			show_item_detail(item_id)


func add_consumable_details(consumable: Dictionary) -> void:
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

	var card := make_card()
	card.add_child(make_label("Effet : " + text, 0, COLOR_BONUS))
	content.add_child(card)


# Carte d'un équipement du sac : emplacement, niveau requis, bonus comparés à
# l'objet actuellement équipé dans le même emplacement, et bouton Équiper.
func build_equip_candidate_card(item_id: String) -> PanelContainer:
	var equipment_info: Dictionary = item_templates.get(item_id, {}).get("equipment", {})
	var slot: String = equipment_info.get("slot", "")
	var current_item_id = GameState.player.get("equipment", {}).get(slot)
	var level_required := int(equipment_info.get("level_required", 1))
	var level_ok := int(GameState.player.get("level", 1)) >= level_required

	var card := make_card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	info.add_child(make_label(item_name(item_id), 16, GameText.rarity_color(item_templates.get(item_id, {}))))
	info.add_child(
		make_label(
			"%s · Niveau requis %d" % [SLOT_LABELS.get(slot, slot), level_required],
			12,
			COLOR_MUTED if level_ok else COLOR_ERROR
		)
	)
	info.add_child(make_rich_label(format_bonus_comparison(item_bonuses(item_id), item_bonuses(current_item_id))))

	if current_item_id:
		info.add_child(make_label("Remplace : " + item_name(current_item_id), 12, COLOR_MUTED))

	row.add_child(info)

	var equip_button := make_button("Équiper", 84)
	equip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	equip_button.disabled = not level_ok

	if not level_ok:
		equip_button.tooltip_text = "Niveau %d requis" % level_required

	equip_button.pressed.connect(
		func():
			if await run_action("equip_item", {"item_id": item_id}):
				show_tab("equipment")
	)
	row.add_child(equip_button)

	return card


# Bonus d'un objet, avec l'écart par rapport à l'objet équipé (▲ / ▼).
func format_bonus_comparison(bonuses: Dictionary, current: Dictionary) -> String:
	var parts := PackedStringArray()

	for stat in STAT_ORDER:
		if not bonuses.has(stat) and not current.has(stat):
			continue

		var value := float(bonuses.get(stat, 0))
		var delta := value - float(current.get(stat, 0))
		var text := "%s +%s" % [STAT_LABELS[stat], format_number(value)]

		if delta > 0:
			text += " " + color_tag("▲%s" % format_number(delta), COLOR_BONUS)
		elif delta < 0:
			text += " " + color_tag("▼%s" % format_number(-delta), COLOR_MALUS)

		parts.append(text)

	if parts.is_empty():
		return color_tag("Aucun bonus de stat", COLOR_MUTED)

	return " · ".join(parts)


# --- Onglet Équipement ----------------------------------------------------

func refresh_equipment(id: int) -> void:
	clear_content()
	add_label("Chargement de l'équipement...", 0, COLOR_MUTED)

	var inventory: Dictionary = GameState.player.get("inventory", {})

	if not await ensure_item_templates(inventory.keys() + equipped_item_ids(), id):
		return

	render_equipment()


func candidates_for_slot(slot: String) -> Array:
	var candidates: Array = []

	for item_id in GameState.player.get("inventory", {}):
		if item_templates.get(item_id, {}).get("category", "") == "equipment" and item_slot(item_id) == slot:
			candidates.append(item_id)

	candidates.sort_custom(func(a, b): return item_name(a).naturalnocasecmp_to(item_name(b)) < 0)
	return candidates


func render_equipment() -> void:
	clear_content()

	var equipment: Dictionary = GameState.player.get("equipment", {})
	var total: Dictionary = {}

	for item_id in equipped_item_ids():
		var bonuses := item_bonuses(item_id)

		for stat in bonuses:
			total[stat] = float(total.get(stat, 0)) + float(bonuses[stat])

	var summary := make_card(COLOR_CARD_HIGHLIGHT)
	var summary_box := VBoxContainer.new()
	summary_box.add_child(make_label("Bonus de l'équipement", 16))
	summary_box.add_child(
		make_label(
			format_bonuses(total) if not total.is_empty() else "Aucun objet équipé",
			13,
			COLOR_BONUS if not total.is_empty() else COLOR_MUTED
		)
	)
	summary.add_child(summary_box)
	content.add_child(summary)

	for slot in SLOT_ORDER:
		content.add_child(build_slot_card(slot, equipment.get(slot), candidates_for_slot(slot)))


func build_slot_card(slot: String, item_id, candidates: Array) -> PanelContainer:
	var card := make_card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	info.add_child(make_label(SLOT_LABELS[slot], 12, COLOR_MUTED, false))

	if item_id:
		info.add_child(make_label(item_name(item_id), 16, GameText.rarity_color(item_templates.get(item_id, {}))))
		var bonuses := format_bonuses(item_bonuses(item_id))
		if not bonuses.is_empty():
			info.add_child(make_label(bonuses, 12, COLOR_BONUS))
	else:
		info.add_child(make_label("Vide", 16, COLOR_MUTED, false))

	if not candidates.is_empty():
		info.add_child(
			make_label(
				"%d objet%s disponible%s" % [
					candidates.size(),
					"s" if candidates.size() > 1 else "",
					"s" if candidates.size() > 1 else ""
				],
				11,
				COLOR_HIGHLIGHT,
				false
			)
		)

	row.add_child(info)

	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER

	if not candidates.is_empty():
		var choose_button := make_button("Changer" if item_id else "Équiper", 84)
		choose_button.pressed.connect(func(): show_slot_picker(slot))
		buttons.add_child(choose_button)

	if item_id:
		var remove_button := make_button("Retirer", 84)
		remove_button.pressed.connect(func(): run_action("unequip_item", {"slot": slot}))
		buttons.add_child(remove_button)

	row.add_child(buttons)
	return card


func show_slot_picker(slot: String) -> void:
	render_id += 1
	clear_content()
	scroll.scroll_vertical = 0

	var back_to_slots := make_button("← Équipement")
	back_to_slots.pressed.connect(func(): refresh())
	content.add_child(back_to_slots)

	add_label(SLOT_LABELS[slot], 22)

	var current_item_id = GameState.player.get("equipment", {}).get(slot)

	if current_item_id:
		add_label("Équipé : %s (%s)" % [item_name(current_item_id), format_bonuses(item_bonuses(current_item_id))], 13, COLOR_MUTED)
	else:
		add_label("Rien d'équipé pour l'instant.", 13, COLOR_MUTED)

	for item_id in candidates_for_slot(slot):
		content.add_child(build_equip_candidate_card(item_id))


# --- Onglet Compétences -------------------------------------------------------

func refresh_skills(id: int) -> void:
	clear_content()
	add_label("Chargement des compétences...", 0, COLOR_MUTED)

	var skills: Dictionary = GameState.player.get("skills", {})

	if not await ensure_skill_templates(skills.get("unlocked", []), id):
		return

	if not await load_titles(id):
		return

	render_skills()


# Charge tous les titres du jeu. Leurs conditions restent secrètes : le serveur
# ne les envoie pas, et l'écran ne montre que les titres débloqués.
func load_titles(id: int) -> bool:
	var res := await ApiClient.get_content("/content/templates/title")

	if not res.ok:
		return id == render_id

	var unlocked: Array = GameState.player.get("titles", {}).get("unlocked", [])

	for summary in res.data:
		var title_id := str(summary.get("id", ""))

		if not title_templates.has(title_id):
			var detail := await ApiClient.get_template("title", title_id)
			title_templates[title_id] = detail.data if detail.ok else summary


		if id != render_id:
			return false

	return true


func render_skills() -> void:
	clear_content()

	add_titles_section()

	var skills: Dictionary = GameState.player.get("skills", {})
	var unlocked: Array = skills.get("unlocked", [])
	var equipped_active: Array = skills.get("equipped_active", [])
	var equipped_passive: Array = skills.get("equipped_passive", [])

	if unlocked.is_empty():
		add_section_title("⚔ Compétences")
		add_label(
			"Aucune compétence débloquée pour l'instant. Combats et explore pour en apprendre.",
			13,
			COLOR_MUTED
		)
		return

	add_section_title("⚔ Actives en combat  (%d/%d)" % [equipped_active.size(), MAX_ACTIVE_SKILLS])

	if equipped_active.is_empty():
		add_label("Aucune compétence active équipée.", 13, COLOR_MUTED)

	for skill_id in equipped_active:
		content.add_child(build_skill_card(skill_id, true))

	add_section_title("✨ Passives  (%d/%d)" % [equipped_passive.size(), MAX_PASSIVE_SKILLS])

	if equipped_passive.is_empty():
		add_label("Aucune compétence passive équipée.", 13, COLOR_MUTED)

	for skill_id in equipped_passive:
		content.add_child(build_skill_card(skill_id, true))

	var available: Array = []

	for skill_id in unlocked:
		if not equipped_active.has(skill_id) and not equipped_passive.has(skill_id):
			available.append(skill_id)

	add_section_title("📖 Disponibles  (%d)" % available.size())

	if available.is_empty():
		add_label("Toutes tes compétences sont équipées.", 13, COLOR_MUTED)

	for skill_id in available:
		content.add_child(build_skill_card(skill_id, false))


# --- Titres -----------------------------------------------------------------

func add_titles_section() -> void:
	var titles: Dictionary = GameState.player.get("titles", {})
	var unlocked: Array = titles.get("unlocked", [])
	var equipped = titles.get("equipped")

	add_section_title("🏅 Titres  (%d / %d)" % [unlocked.size(), title_templates.size()])
	add_label("Un seul titre peut être porté à la fois ; ses effets s'appliquent en permanence.", 12, COLOR_MUTED)

	# Seuls les titres débloqués apparaissent : les autres, et la façon de les
	# obtenir, restent à découvrir.
	var ids: Array = title_templates.keys().filter(func(title_id): return unlocked.has(title_id))
	# Le titre porté d'abord, puis les autres par nom.
	ids.sort_custom(
		func(a, b):
			if (a == equipped) != (b == equipped):
				return a == equipped
			return str(title_templates[a].get("name", a)).naturalnocasecmp_to(str(title_templates[b].get("name", b))) < 0
	)

	if ids.is_empty():
		add_label("Aucun titre pour l'instant.", 13, COLOR_MUTED)

	for title_id in ids:
		content.add_child(build_title_card(title_id, title_id == equipped))

	var hidden := title_templates.size() - ids.size()

	if hidden > 0:
		add_label("🔒 %d titre%s reste%s à découvrir…" % [hidden, "s" if hidden > 1 else "", "nt" if hidden > 1 else ""], 13, COLOR_MUTED)


func build_title_card(title_id: String, is_equipped: bool) -> PanelContainer:
	var title: Dictionary = title_templates.get(title_id, {})
	var card := make_card(COLOR_CARD_HIGHLIGHT if is_equipped else COLOR_CARD)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	info.add_child(make_label(str(title.get("name", title_id)), 16))
	info.add_child(make_label("Porté" if is_equipped else "Débloqué", 12, COLOR_HIGHLIGHT if is_equipped else COLOR_MUTED))
	row.add_child(info)

	var button := make_button("Retirer" if is_equipped else "Porter", 84)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if is_equipped:
		button.pressed.connect(func(): run_action("unequip_title", {}))
	else:
		button.pressed.connect(func(): run_action("equip_title", {"title_id": title_id}))

	row.add_child(button)

	var effects := describe_skill_effects(title)

	if not effects.is_empty():
		box.add_child(make_label(effects, 13, COLOR_BONUS))

	var description: String = title.get("description", "")

	if not description.is_empty():
		box.add_child(make_label(description, 12, COLOR_MUTED))

	return card


func build_skill_card(skill_id: String, is_equipped: bool) -> PanelContainer:
	var skill: Dictionary = skill_templates.get(skill_id, {})
	var is_active: bool = skill.get("kind", "active") == "active"

	var card := make_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	info.add_child(make_label(skill.get("name", skill_id), 16))
	info.add_child(make_label(skill_summary(skill), 12, COLOR_MUTED))
	row.add_child(info)

	var button := make_button("Retirer" if is_equipped else "Équiper", 84)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if is_equipped:
		button.pressed.connect(func(): run_action("unequip_skill", {"skill_id": skill_id}))
	else:
		var skills: Dictionary = GameState.player.get("skills", {})
		var used: int = skills.get("equipped_active" if is_active else "equipped_passive", []).size()
		var max_slots := MAX_ACTIVE_SKILLS if is_active else MAX_PASSIVE_SKILLS

		if used >= max_slots:
			button.disabled = true
			button.text = "Complet"

		button.pressed.connect(func(): run_action("equip_skill", {"skill_id": skill_id}))

	row.add_child(button)

	var effects := describe_skill_effects(skill)

	if not effects.is_empty():
		box.add_child(make_label(effects, 13, COLOR_BONUS))

	var description: String = skill.get("description", "")

	if not description.is_empty():
		box.add_child(make_label(description, 12, COLOR_MUTED))

	return card


func skill_summary(skill: Dictionary) -> String:
	if skill.get("kind", "") == "passive":
		if skill.get("trigger", "always") == "conditional":
			return "Passive · " + describe_condition(skill.get("condition", {}))

		return "Passive · toujours active"

	return "Active · %s mana · recharge %s s" % [
		format_number(float(skill.get("mana_cost", 0))),
		format_number(float(skill.get("cooldown_seconds", 0)))
	]


func describe_condition(condition) -> String:
	if typeof(condition) != TYPE_DICTIONARY:
		return "sous condition"

	match condition.get("type", ""):
		"hp_below_percent":
			return "si PV < %s %%" % format_number(float(condition.get("value", 0)))
		_:
			return "sous condition"


# Effet d'une compétence : part fixe + coefficient de la stat (voir
# combat_engine.apply_skill_effects), par exemple « 10 + 0,48 × ATK ».
func scaling_text(effect: Dictionary, power_key: String, stat: String) -> String:
	var base := float(effect.get("base", 0))
	var power := format_number(float(effect.get(power_key, 0))) + " × " + stat

	if base > 0:
		return "%s + %s" % [format_number(base), power]

	return power


func describe_skill_effects(skill: Dictionary) -> String:
	var parts := PackedStringArray()

	# Même règle que le combat : magique → INT, sinon ATK.
	var damage_stat := "INT" if skill.get("damage_type", "") == "magical" else "ATK"

	for effect in skill.get("effects", []):
		var stat_label: String = STAT_LABELS.get(effect.get("stat", ""), str(effect.get("stat", "")))
		var duration := int(effect.get("duration_seconds", 0))
		var duration_text := " pendant %d s" % duration if duration > 0 else ""

		match effect.get("type", ""):
			"damage":
				if skill.get("damage_type", "") == "hybrid":
					# Même règle que combat_engine.skill_damage_stat : 2 × la plus faible.
					var doubled: Dictionary = effect.duplicate()
					doubled["power"] = float(effect.get("power", 0)) * 2
					parts.append("Dégâts : " + scaling_text(doubled, "power", "la plus faible d'ATK et d'INT"))
				else:
					parts.append("Dégâts : " + scaling_text(effect, "power", damage_stat))
			"heal":
				parts.append("Soin : " + scaling_text(effect, "power", "SAG"))
			"shield":
				var shield_stat := "ATK" if skill.get("damage_type", "") == "physical" else "SAG"
				parts.append("Bouclier : " + scaling_text(effect, "amount_power", shield_stat) + duration_text)
			"stat_bonus":
				parts.append("%s +%s" % [stat_label, format_number(float(effect.get("amount", 0)))])
			"stat_bonus_percent":
				parts.append("%s +%s %%" % [stat_label, format_number(float(effect.get("amount_percent", 0)))])
			"debuff":
				parts.append("Ennemi %s −%s %%%s" % [stat_label, format_number(float(effect.get("amount_percent", 0))), duration_text])
			"buff":
				parts.append("%s +%s %%%s" % [stat_label, format_number(float(effect.get("amount_percent", 0))), duration_text])
			_:
				parts.append(str(effect.get("type", "")))

	return " · ".join(parts)
