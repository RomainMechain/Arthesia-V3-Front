extends VBoxContainer

# Fiche d'une ressource dans l'écran de zone : métier requis, rendement,
# disponibilité (stock partagé, réapparition) et bouton Récolter.
#
# Créé par zone_screen.gd (preload du script puis .new()), puis setup() une
# fois ajouté à l'arbre.

const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR

const MAX_RESULTS := 3

var zone_id := ""
var entry: Dictionary = {}
var template: Dictionary = {}

# État de l'entry côté serveur (vide si l'entry n'est pas partagée).
var entry_state: Dictionary = {}
var available_at_msec := 0
var is_gathering := false
var is_refreshing := false

var profession_id := ""
var min_level := 0
var profession_xp_to_next := 0

var profession_label: Label
var profession_bar: ProgressBar
var requirement_label: Label
var yields_box: VBoxContainer
var status_label: Label
var gather_button: Button
var gather_bar: ProgressBar
var results_box: VBoxContainer


func setup(p_zone_id: String, p_entry: Dictionary, p_template: Dictionary) -> void:
	zone_id = p_zone_id
	entry = p_entry
	template = p_template

	var requirement: Dictionary = template.get("profession_required", {}) if template.get("profession_required") else {}
	profession_id = requirement.get("profession_id", "")
	min_level = int(requirement.get("min_level", 0))

	add_theme_constant_override("separation", 10)
	build()

	await load_profession_threshold()
	update_profession_display()
	await load_yields()
	await refresh_state()


# --- Construction -------------------------------------------------------------

func make_label(text: String, font_size := 0, color = null, wrap := true) -> Label:
	var label := Label.new()
	label.text = text

	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)

	if color != null:
		label.add_theme_color_override("font_color", color)

	return label


func build() -> void:
	add_child(make_label(template.get("name", entry.get("template_id", "Ressource")), 22))
	add_child(
		make_label(
			"Ressource · Niveau %d · Récolte en %s s" % [
				int(template.get("level", 1)),
				GameText.format_number(float(template.get("gather_time_seconds", 0)))
			],
			13,
			COLOR_MUTED
		)
	)

	var description: String = template.get("description", "")

	if not description.is_empty():
		add_child(make_label(description, 13, COLOR_MUTED))

	if not profession_id.is_empty():
		var card := UiStyle.make_card()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)

		profession_label = make_label("", 15, null, false)
		box.add_child(profession_label)

		profession_bar = ProgressBar.new()
		profession_bar.show_percentage = false
		profession_bar.custom_minimum_size = Vector2(0, 8)
		UiStyle.style_bar(profession_bar, COLOR_BONUS)
		box.add_child(profession_bar)

		requirement_label = make_label("", 12, COLOR_MUTED, false)
		box.add_child(requirement_label)
		add_child(card)

	var yields_card := UiStyle.make_card()
	yields_box = VBoxContainer.new()
	yields_box.add_theme_constant_override("separation", 2)
	yields_box.add_child(make_label("Rendement", 15, null, false))
	yields_card.add_child(yields_box)
	add_child(yields_card)

	status_label = make_label("Vérification de la disponibilité...", 14, COLOR_MUTED)
	add_child(status_label)

	gather_button = Button.new()
	gather_button.text = "🌿 Récolter"
	gather_button.custom_minimum_size = Vector2(0, 54)
	gather_button.add_theme_font_size_override("font_size", 18)
	gather_button.disabled = true
	gather_button.pressed.connect(gather)
	add_child(gather_button)

	gather_bar = ProgressBar.new()
	gather_bar.show_percentage = false
	gather_bar.custom_minimum_size = Vector2(0, 8)
	gather_bar.max_value = 1.0
	gather_bar.visible = false
	UiStyle.style_bar(gather_bar, COLOR_HIGHLIGHT)
	add_child(gather_bar)

	results_box = VBoxContainer.new()
	results_box.add_theme_constant_override("separation", 6)
	add_child(results_box)


# --- Métier -------------------------------------------------------------------

func player_profession() -> Dictionary:
	# Un métier jamais pratiqué commence au niveau 1 (règle du serveur).
	return GameState.player.get("professions", {}).get(profession_id, {"level": 1, "xp": 0})


func load_profession_threshold() -> void:
	if profession_id.is_empty():
		return

	var res := await ApiClient.get_player_stats(GameState.player_id)

	if res.ok:
		profession_xp_to_next = int(res.data.get("profession_xp_to_next_level", {}).get(profession_id, 0))


func level_ok() -> bool:
	return profession_id.is_empty() or int(player_profession().get("level", 1)) >= min_level


func update_profession_display() -> void:
	if profession_id.is_empty():
		return

	var profession := player_profession()
	var level := int(profession.get("level", 1))
	var xp := int(profession.get("xp", 0))

	profession_label.text = "%s · niveau %d" % [GameText.profession_label(profession_id), level]

	# Seuil inconnu pour un métier jamais pratiqué : la barre s'affiche après
	# la première récolte, qui renvoie le seuil.
	profession_bar.visible = profession_xp_to_next > 0
	profession_bar.max_value = max(profession_xp_to_next, 1)
	profession_bar.value = xp

	var requirement := "Niveau %d requis" % min_level

	if profession_xp_to_next > 0:
		requirement = "%d / %d XP · %s" % [xp, profession_xp_to_next, requirement]

	requirement_label.text = requirement
	requirement_label.add_theme_color_override("font_color", COLOR_MUTED if level_ok() else COLOR_ERROR)


# --- Rendement ----------------------------------------------------------------

func load_yields() -> void:
	var yields: Array = template.get("yields", [])
	var total_weight := 0.0

	for y in yields:
		total_weight += float(y.get("weight", 1))

	var yield_items := await ApiClient.get_templates("item", yields.map(func(y): return str(y.get("item_id", ""))))

	for y in yields:
		var item_id: String = y.get("item_id", "")
		var item_name: String = yield_items.get(item_id, {}).get("name", GameText.prettify_id(item_id))

		var quantity_min := int(y.get("quantity_min", 1))
		var quantity_max := int(y.get("quantity_max", quantity_min))
		var quantity := "×%d" % quantity_min if quantity_min == quantity_max else "×%d–%d" % [quantity_min, quantity_max]
		var text := "%s %s" % [item_name, quantity]

		if yields.size() > 1 and total_weight > 0:
			text += "  (%d %%)" % roundi(float(y.get("weight", 1)) / total_weight * 100.0)

		yields_box.add_child(make_label(text, 13, COLOR_BONUS))


# --- Disponibilité ------------------------------------------------------------

func refresh_state() -> void:
	if entry.get("state_scope", "") != "shared":
		apply_state({})
		return

	is_refreshing = true
	var res := await ApiClient.get_json("/zones/%s/state" % zone_id)
	is_refreshing = false

	if not res.ok:
		status_label.text = "Disponibilité inconnue : " + res.error
		status_label.add_theme_color_override("font_color", COLOR_ERROR)
		return

	apply_state(res.data.get("entries", {}).get(entry.get("id", ""), {}))


func apply_state(state) -> void:
	entry_state = state if state is Dictionary else {}
	available_at_msec = 0

	if entry_state.get("status", "available") != "available":
		var seconds := float(entry_state.get("seconds_until_available", 0))
		available_at_msec = Time.get_ticks_msec() + int(seconds * 1000)

	update_status()


func is_available() -> bool:
	return entry_state.get("status", "available") == "available"


func update_status() -> void:
	if is_available():
		var text := "✅ Disponible"

		if entry_state.has("max_stock"):
			text += " · stock %d / %d" % [int(entry_state.get("current_stock", 0)), int(entry_state["max_stock"])]

		status_label.text = text
		status_label.add_theme_color_override("font_color", COLOR_BONUS)
	elif available_at_msec > 0:
		var left: float = max(0.0, (available_at_msec - Time.get_ticks_msec()) / 1000.0)
		status_label.text = "⏳ Épuisée · revient dans %d s" % ceili(left)
		status_label.add_theme_color_override("font_color", COLOR_HIGHLIGHT)
	else:
		status_label.text = "Indisponible"
		status_label.add_theme_color_override("font_color", COLOR_MUTED)

	gather_button.disabled = is_gathering or not is_available() or not level_ok()

	if not level_ok():
		gather_button.text = "🔒 %s niveau %d requis" % [GameText.profession_name(profession_id), min_level]
	elif not is_gathering:
		gather_button.text = "🌿 Récolter"


func _process(_delta: float) -> void:
	if is_available() or available_at_msec == 0:
		return

	update_status()

	# À la fin du délai, on redemande l'état exact au serveur.
	if Time.get_ticks_msec() >= available_at_msec and not is_refreshing:
		available_at_msec = 0
		refresh_state()


# --- Récolte ------------------------------------------------------------------

func gather() -> void:
	if is_gathering or not is_available() or not level_ok():
		return

	is_gathering = true
	gather_button.text = "Récolte en cours..."
	update_status()

	# Le serveur note le début : il refusera la récolte avant la fin du délai.
	var start := await ApiClient.post_action(
		GameState.player_id,
		"gather_start",
		{"zone_id": zone_id, "entry_id": entry.get("id", "")}
	)

	if not start.ok:
		is_gathering = false
		add_result([start.error], COLOR_ERROR)
		update_status()
		return

	# Le temps de récolte du template : le joueur est occupé pendant ce délai.
	var duration: float = max(float(start.data.get("gather_time_seconds", template.get("gather_time_seconds", 0))), 0.1)
	gather_bar.value = 0
	gather_bar.visible = true
	var tween := create_tween()
	tween.tween_property(gather_bar, "value", 1.0, duration)
	await tween.finished

	var res := await GameState.perform_action(
		"resource_gather",
		{"zone_id": zone_id, "entry_id": entry.get("id", "")}
	)

	is_gathering = false
	gather_bar.visible = false

	if not res.ok:
		add_result([res.error], COLOR_ERROR)
		await refresh_state()
		return

	var data: Dictionary = res.data

	if data.get("entry_state") is Dictionary:
		apply_state(data["entry_state"])
	else:
		update_status()

	await show_gather_result(data)


func show_gather_result(data: Dictionary) -> void:
	var lines: Array = []
	var yields = data.get("yields")

	if yields is Array and yields.size() >= 2:
		var item_id := str(yields[0])
		var res := await ApiClient.get_template("item", item_id)
		var item_name: String = res.data.get("name", item_id) if res.ok else GameText.prettify_id(item_id)
		lines.append("🎁 +%d %s" % [int(yields[1]), item_name])
	else:
		lines.append("Rien trouvé cette fois.")

	var profession = data.get("profession")

	if profession is Dictionary:
		profession_xp_to_next = int(profession.get("xp_to_next_level", profession_xp_to_next))
		lines.append("✨ +%d XP %s" % [int(profession.get("xp_gained", 0)), GameText.profession_name(profession_id)])

		if int(profession.get("levels_gained", 0)) > 0:
			lines.append("🌟 %s niveau %d !" % [GameText.profession_name(profession_id), int(profession.get("level", 1))])

	for update in data.get("quest_progress", []):
		lines.append(GameState.describe_quest_progress(update))

	for unlock in data.get("newly_unlocked", []):
		lines.append(await GameState.describe_unlock(str(unlock)))

	update_profession_display()
	add_result(lines, COLOR_BONUS)


# Ajoute une carte de résultat en haut de la liste (les plus récents d'abord).
func add_result(lines: Array, color: Color) -> void:
	var card := UiStyle.make_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	for i in lines.size():
		box.add_child(make_label(str(lines[i]), 14 if i == 0 else 13, color if i == 0 else null))

	results_box.add_child(card)
	results_box.move_child(card, 0)

	card.modulate.a = 0.0
	create_tween().tween_property(card, "modulate:a", 1.0, 0.25)

	while results_box.get_child_count() > MAX_RESULTS:
		var oldest := results_box.get_child(results_box.get_child_count() - 1)
		results_box.remove_child(oldest)
		oldest.queue_free()

	# Fait défiler l'écran parent jusqu'au résultat, une fois sa taille connue.
	var scroll := find_parent_scroll()

	if scroll != null:
		await get_tree().process_frame
		scroll.ensure_control_visible(card)


func find_parent_scroll() -> ScrollContainer:
	var node := get_parent()

	while node != null:
		if node is ScrollContainer:
			return node

		node = node.get_parent()

	return null
