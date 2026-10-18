extends VBoxContainer

# Fiche d'une quête : objectifs avec progression, récompenses et actions
# (accepter, rendre, abandonner) selon l'état de la quête pour le joueur.
#
# Utilisée dans l'écran de zone (can_turn_in = true : on est chez le
# donneur de quête) et dans le journal (can_turn_in = false : on indique où
# la rendre). Créée avec preload(...).new(), puis setup() une fois ajoutée à
# l'arbre. Se reconstruit à chaque changement du joueur.

const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR

var quest: Dictionary = {}
var can_turn_in := false
var givers: Array = []

# Noms des cibles (monstres, ressources, objets), chargés une fois.
var names: Dictionary = {}
var is_submitting := false
var confirm_abandon := false
var message_lines: Array = []
var message_color := COLOR_BONUS


func setup(p_quest: Dictionary, p_can_turn_in: bool, p_givers: Array = []) -> void:
	quest = p_quest
	can_turn_in = p_can_turn_in
	givers = p_givers

	add_theme_constant_override("separation", 10)
	GameState.player_changed.connect(_on_player_changed)

	render()
	await load_names()
	render()


func _on_player_changed(_player: Dictionary) -> void:
	render()


# --- Données ----------------------------------------------------------------

func load_names() -> void:
	var targets: Array = []

	for objective in quest.get("objectives", []):
		match objective.get("type", ""):
			"kill_count":
				targets.append(["monster", str(objective.get("monster_id", ""))])
			"gather_count":
				targets.append(["resource", str(objective.get("resource_id", ""))])
			"deliver_item":
				targets.append(["item", str(objective.get("item_id", ""))])
			"zone":
				var zone_id := str(objective.get("zone_id", ""))
				var zone_res := await ApiClient.get_zone(zone_id)
				names[zone_id] = zone_res.data.get("name", zone_id) if zone_res.ok else GameText.prettify_id(zone_id)

	for reward in quest.get("rewards", {}).get("items", []):
		targets.append(["item", str(reward.get("item_id", ""))])

	for target in targets:
		var res := await ApiClient.get_template(target[0], target[1])
		names[target[1]] = res.data.get("name", target[1]) if res.ok else GameText.prettify_id(target[1])


func display_name(template_id: String) -> String:
	return names.get(template_id, GameText.prettify_id(template_id))


func quest_id() -> String:
	return str(quest.get("id", ""))


func state() -> String:
	return GameState.quest_state(quest_id())


# Progression actuelle de chaque objectif : [actuel, requis].
func objective_progress() -> Array:
	var result: Array = []
	var objectives: Array = quest.get("objectives", [])

	for index in objectives.size():
		result.append(GameState.quest_objective_progress(quest_id(), objectives[index], index))

	return result


func is_ready() -> bool:
	if state() != "active":
		return false

	for progress in objective_progress():
		if progress[0] < progress[1]:
			return false

	return true


func describe_objective(objective: Dictionary) -> String:
	match objective.get("type", ""):
		"kill_count":
			return "Vaincre " + display_name(str(objective.get("monster_id", "")))
		"gather_count":
			return "Récolter " + display_name(str(objective.get("resource_id", "")))
		"deliver_item":
			return "Apporter " + display_name(str(objective.get("item_id", "")))
		"level":
			return "Atteindre le niveau %d" % int(objective.get("min", 1))
		"zone":
			return "Découvrir " + display_name(str(objective.get("zone_id", "")))
		_:
			return GameText.prettify_id(str(objective.get("type", "")))


# --- Affichage --------------------------------------------------------------

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


func make_card_box(color := UiStyle.COLOR_CARD) -> VBoxContainer:
	var card := UiStyle.make_card(color)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	add_child(card)
	return box


func render() -> void:
	for child in get_children():
		child.queue_free()

	var current_state := state()
	var quest_ready := is_ready()

	add_child(make_label(quest.get("name", "Quête"), 22))

	var meta := "📜 Quête"

	if quest.get("repeatable", false):
		meta += " · répétable"

	match current_state:
		"active":
			meta += " · ✅ Prête à rendre" if quest_ready else " · En cours"
		"completed":
			meta += " · Terminée"

	add_child(make_label(meta, 13, COLOR_HIGHLIGHT if quest_ready else COLOR_MUTED))

	var description: String = quest.get("description", "")

	if not description.is_empty():
		add_child(make_label(description, 13, COLOR_MUTED))

	add_objectives()
	add_rewards()

	if not givers.is_empty():
		var zone_names := PackedStringArray()

		for giver in givers:
			zone_names.append(str(giver.get("zone_name", giver.get("zone_id", ""))))

		add_child(make_label("📍 À rendre à : " + ", ".join(zone_names), 13, COLOR_MUTED))

	if not message_lines.is_empty():
		var box := make_card_box(Color(0.17, 0.2, 0.15) if message_color == COLOR_BONUS else UiStyle.COLOR_CARD)

		for i in message_lines.size():
			box.add_child(make_label(str(message_lines[i]), 15 if i == 0 else 13, message_color if i == 0 else null))

	add_actions(current_state, quest_ready)


func add_objectives() -> void:
	var objectives: Array = quest.get("objectives", [])

	if objectives.is_empty():
		return

	var box := make_card_box()
	box.add_child(make_label("Objectifs", 15, null, false))

	var active := state() == "active"
	var progress := objective_progress()

	for index in objectives.size():
		var current: int = progress[index][0]
		var required: int = progress[index][1]
		var done := active and current >= required

		var row := HBoxContainer.new()
		var text := make_label(("✓ " if done else "• ") + describe_objective(objectives[index]), 13, COLOR_BONUS if done else null)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)

		var count_text := "%d / %d" % [current, required] if active else "× %d" % required
		row.add_child(make_label(count_text, 13, COLOR_BONUS if done else COLOR_MUTED, false))
		box.add_child(row)

		if active:
			var bar := ProgressBar.new()
			bar.max_value = max(required, 1)
			bar.value = current
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 6)
			UiStyle.style_bar(bar, COLOR_BONUS if done else COLOR_HIGHLIGHT)
			box.add_child(bar)


func add_rewards() -> void:
	var rewards: Dictionary = quest.get("rewards", {})
	var lines: Array = []

	if int(rewards.get("xp", 0)) > 0:
		lines.append(["✨ %d XP" % int(rewards["xp"]), COLOR_BONUS])

	if int(rewards.get("gold", 0)) > 0:
		lines.append(["💰 %d or" % int(rewards["gold"]), COLOR_HIGHLIGHT])

	for reward in rewards.get("items", []):
		lines.append(["🎁 %s ×%d" % [display_name(str(reward.get("item_id", ""))), int(reward.get("quantity", 1))], COLOR_BONUS])

	if lines.is_empty():
		return

	var box := make_card_box()
	box.add_child(make_label("Récompenses", 15, null, false))

	for line in lines:
		box.add_child(make_label(line[0], 13, line[1]))


func make_action_button(text: String, enabled := true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.add_theme_font_size_override("font_size", 17)
	button.disabled = not enabled or is_submitting
	add_child(button)
	return button


func add_actions(current_state: String, quest_ready: bool) -> void:
	match current_state:
		"":
			var accept := make_action_button("📜 Accepter la quête", can_turn_in)
			accept.pressed.connect(func(): run_quest_action("start_quest"))

			if not can_turn_in:
				add_child(make_label("Rends-toi chez le donneur de quête pour l'accepter.", 12, COLOR_MUTED))
		"completed":
			if quest.get("repeatable", false) and can_turn_in:
				var again := make_action_button("🔁 Recommencer")
				again.pressed.connect(func(): run_quest_action("start_quest"))
			else:
				make_action_button("✅ Quête terminée", false)
		"active":
			if quest_ready and can_turn_in:
				var turn_in := make_action_button("🎁 Rendre la quête")
				turn_in.pressed.connect(func(): run_quest_action("turn_in_quest"))
			elif quest_ready:
				add_child(make_label("Retourne voir le donneur de quête pour la rendre.", 13, COLOR_HIGHLIGHT))
			else:
				make_action_button("En cours...", false)

			# L'abandon demande une confirmation : la progression est perdue.
			var abandon := Button.new()
			abandon.text = "Confirmer l'abandon ?" if confirm_abandon else "Abandonner"
			abandon.flat = not confirm_abandon
			abandon.disabled = is_submitting
			abandon.add_theme_color_override("font_color", COLOR_ERROR)
			abandon.pressed.connect(
				func():
					if confirm_abandon:
						run_quest_action("abandon_quest")
					else:
						confirm_abandon = true
						render()
			)
			add_child(abandon)


# --- Actions ----------------------------------------------------------------

func run_quest_action(action: String) -> void:
	if is_submitting:
		return

	is_submitting = true
	confirm_abandon = false
	message_lines = []
	render()

	var res := await GameState.perform_action(action, {"quest_id": quest_id()})
	is_submitting = false

	if not res.ok:
		message_lines = ["⚠ " + res.error]
		message_color = COLOR_ERROR
		render()
		return

	match action:
		"start_quest":
			message_lines = ["📜 Quête acceptée !", "Ta progression s'affiche ici et dans le journal de quêtes."]

			# Une quête active peut ouvrir une zone.
			for unlock in res.data.get("newly_unlocked", []):
				message_lines.append(await GameState.describe_unlock(str(unlock)))
		"abandon_quest":
			message_lines = ["Quête abandonnée."]
		"turn_in_quest":
			message_lines = await describe_turn_in(res.data)

	message_color = COLOR_BONUS
	render()


func describe_turn_in(data: Dictionary) -> Array:
	var lines: Array = ["🎉 Quête terminée !"]
	var rewards: Dictionary = data.get("rewards_given", {})

	if int(rewards.get("xp", 0)) > 0:
		lines.append("✨ +%d XP" % int(rewards["xp"]))

	if int(rewards.get("gold", 0)) > 0:
		lines.append("💰 +%d or" % int(rewards["gold"]))

	for reward in rewards.get("items", []):
		lines.append("🎁 %s ×%d" % [display_name(str(reward.get("item_id", ""))), int(reward.get("quantity", 1))])

	if int(data.get("levels_gained", 0)) > 0:
		lines.append("🌟 Niveau %d atteint !" % int(data.get("player_level", 1)))

	for unlock in data.get("newly_unlocked", []):
		lines.append(await GameState.describe_unlock(str(unlock)))

	return lines
