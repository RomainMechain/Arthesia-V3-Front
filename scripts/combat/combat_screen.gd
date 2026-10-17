extends Control

# Écran de combat temps réel contre un monstre d'une zone.
#
# Le serveur décide de tout (dégâts, mana, recharges) et envoie des événements
# via CombatClient. Le client se contente d'afficher, d'animer la
# régénération de mana entre deux événements et de bloquer les boutons
# pendant les recharges indiquées par le serveur.

signal back_requested

const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR
const COLOR_DAMAGE_DEALT := Color(1.0, 0.85, 0.4)
const COLOR_DAMAGE_TAKEN := Color(1.0, 0.45, 0.4)

const ROLE_LABELS := {
	"elite": "⭐ Élite",
	"boss": "👑 Boss",
}

const MAX_LOG_LINES := 60

@onready var flee_button: Button = $Layout/Header/FleeButton
@onready var status_label: Label = $Layout/Header/StatusLabel
@onready var monster_card: PanelContainer = $Layout/MonsterCard
@onready var monster_name: Label = $Layout/MonsterCard/Box/MonsterName
@onready var monster_level: Label = $Layout/MonsterCard/Box/MonsterLevel
@onready var monster_hp: ProgressBar = $Layout/MonsterCard/Box/MonsterHP
@onready var monster_hp_label: Label = $Layout/MonsterCard/Box/MonsterHPLabel
@onready var player_card: PanelContainer = $Layout/PlayerCard
@onready var player_name: Label = $Layout/PlayerCard/Box/PlayerName
@onready var player_hp: ProgressBar = $Layout/PlayerCard/Box/PlayerHP
@onready var player_hp_label: Label = $Layout/PlayerCard/Box/PlayerHPLabel
@onready var player_mana: ProgressBar = $Layout/PlayerCard/Box/PlayerMana
@onready var player_mana_label: Label = $Layout/PlayerCard/Box/PlayerManaLabel
@onready var log_card: PanelContainer = $Layout/LogCard
@onready var combat_log: RichTextLabel = $Layout/LogCard/CombatLog
@onready var attack_button: Button = $Layout/AttackButton
@onready var attack_cooldown: ProgressBar = $Layout/AttackCooldown
@onready var skills_grid: GridContainer = $Layout/SkillsGrid
@onready var result_overlay: ColorRect = $ResultOverlay
@onready var result_panel: PanelContainer = $ResultOverlay/Center/ResultPanel
@onready var result_title: Label = $ResultOverlay/Center/ResultPanel/Box/ResultTitle
@onready var result_details: VBoxContainer = $ResultOverlay/Center/ResultPanel/Box/ResultDetails
@onready var leave_button: Button = $ResultOverlay/Center/ResultPanel/Box/Buttons/LeaveButton
@onready var retry_button: Button = $ResultOverlay/Center/ResultPanel/Box/Buttons/RetryButton

var selected_zone_id := ""
var selected_entry: Dictionary = {}
var monster_template: Dictionary = {}

var in_combat := false
var combat_finished := false

# Valeur affichée du mana : animée localement par la régénération, puis
# recalée sur la valeur exacte à chaque événement du serveur.
var mana_current := 0.0
var mana_regen := 0.0

# Recharges en millisecondes (Time.get_ticks_msec).
var attack_ready_at := 0
var attack_cooldown_ms := 1
var skill_ready_at: Dictionary = {}

# skill_id -> {button, template}, dans l'ordre des compétences équipées.
var skill_slots: Dictionary = {}
var log_lines := 0


func _ready() -> void:
	for card in [monster_card, player_card, log_card]:
		card.add_theme_stylebox_override("panel", UiStyle.card_style())

	result_panel.add_theme_stylebox_override("panel", UiStyle.card_style(Color(0.13, 0.13, 0.15)))

	UiStyle.style_bar(monster_hp, UiStyle.COLOR_ENEMY_HP)
	UiStyle.style_bar(player_hp, UiStyle.COLOR_HP)
	UiStyle.style_bar(player_mana, UiStyle.COLOR_MANA)
	UiStyle.style_bar(attack_cooldown, COLOR_HIGHLIGHT)

	monster_level.add_theme_color_override("font_color", COLOR_MUTED)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)

	flee_button.pressed.connect(_on_flee_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	retry_button.pressed.connect(_on_retry_pressed)

	CombatClient.connected.connect(_on_combat_connected)
	CombatClient.disconnected.connect(_on_combat_disconnected)
	CombatClient.message_received.connect(_on_combat_message)


# Appelé par l'écran de zone. monster_data est le template du monstre s'il
# est déjà chargé ; sinon il est demandé au serveur.
func prepare_combat(zone_id: String, entry: Dictionary, monster_data: Dictionary = {}) -> void:
	selected_zone_id = zone_id
	selected_entry = entry
	monster_template = monster_data

	player_name.text = "Toi · Niveau %d" % int(GameState.player.get("level", 1))

	if monster_template.is_empty():
		var res := await ApiClient.get_template("monster", entry.get("template_id", ""))

		if res.ok:
			monster_template = res.data

	show_monster_header()
	await build_skill_buttons()

	CombatClient.connect_to_combat()


func show_monster_header() -> void:
	monster_name.text = monster_template.get("name", selected_entry.get("template_id", "Monstre"))

	var level_text := "Niv. %d" % int(monster_template.get("level", 1))
	var role: String = monster_template.get("role", "normal")

	if ROLE_LABELS.has(role):
		level_text = ROLE_LABELS[role] + " · " + level_text

	monster_level.text = level_text


# --- Compétences ----------------------------------------------------------

func build_skill_buttons() -> void:
	for child in skills_grid.get_children():
		child.queue_free()

	skill_slots.clear()

	var equipped: Array = GameState.player.get("skills", {}).get("equipped_active", [])

	for skill_id in equipped:
		var res := await ApiClient.get_template("skill", skill_id)
		var template: Dictionary = res.data if res.ok else {}

		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 13)
		button.disabled = true
		button.pressed.connect(func(): _on_skill_pressed(skill_id))
		skills_grid.add_child(button)

		skill_slots[skill_id] = {"button": button, "template": template}


func skill_display_name(skill_id: String) -> String:
	return skill_slots.get(skill_id, {}).get("template", {}).get("name", prettify_id(skill_id))


func skill_mana_cost(skill_id: String) -> float:
	return float(skill_slots[skill_id].template.get("mana_cost", 0))


func prettify_id(value: String) -> String:
	var text := value.replace("_", " ")
	return text.substr(0, 1).to_upper() + text.substr(1)


# --- Mise à jour continue --------------------------------------------------

func _process(delta: float) -> void:
	if not in_combat:
		return

	if mana_current < player_mana.max_value:
		mana_current = min(player_mana.max_value, mana_current + mana_regen * delta)
		set_mana(mana_current)

	var now := Time.get_ticks_msec()

	var attack_left: int = max(0, attack_ready_at - now)
	attack_button.disabled = attack_left > 0
	attack_cooldown.value = 1.0 - float(attack_left) / float(attack_cooldown_ms)

	if attack_left > 0:
		attack_button.text = "⚔ Attaque  ·  %.1f s" % (attack_left / 1000.0)
	else:
		attack_button.text = "⚔ Attaque"

	for skill_id in skill_slots:
		update_skill_button(skill_id, now)


func update_skill_button(skill_id: String, now: int) -> void:
	var button: Button = skill_slots[skill_id].button
	var cost := skill_mana_cost(skill_id)
	var left: int = max(0, int(skill_ready_at.get(skill_id, 0)) - now)
	var skill_name := skill_display_name(skill_id)

	if left > 0:
		button.text = "%s\n⏳ %.1f s" % [skill_name, left / 1000.0]
	else:
		button.text = "%s\n💧 %s mana" % [skill_name, format_number(cost)]

	button.disabled = left > 0 or mana_current < cost


func set_monster_hp(current: float, maximum: float) -> void:
	monster_hp.max_value = max(maximum, 1.0)
	monster_hp.value = current
	monster_hp_label.text = "%s / %s PV" % [format_number(current), format_number(maximum)]


func set_player_hp(current: float, maximum: float) -> void:
	player_hp.max_value = max(maximum, 1.0)
	player_hp.value = current
	player_hp_label.text = "%s / %s PV" % [format_number(current), format_number(maximum)]


func set_mana(current: float) -> void:
	mana_current = current
	player_mana.value = current
	player_mana_label.text = "%d / %d Mana" % [int(current), int(player_mana.max_value)]


func format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))

	return "%.1f" % value


# --- Journal et animations --------------------------------------------------

func add_log(text: String, color = null) -> void:
	if log_lines >= MAX_LOG_LINES:
		combat_log.remove_paragraph(0)
	else:
		log_lines += 1

	if color != null:
		text = "[color=#%s]%s[/color]" % [color.to_html(false), text]

	combat_log.append_text(text + "\n")


# Fait monter et disparaître un nombre au-dessus d'une carte.
func spawn_floating_text(text: String, color: Color, target: Control) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)

	var start := target.global_position - global_position + Vector2(
		target.size.x * 0.5 - 30 + randf_range(-40, 40),
		target.size.y * 0.3
	)
	label.position = start

	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", start.y - 45, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


func flash(card: Control, color: Color) -> void:
	card.modulate = color
	create_tween().tween_property(card, "modulate", Color.WHITE, 0.25)


# --- Connexion et messages --------------------------------------------------

func _on_combat_connected() -> void:
	start_combat()


func start_combat() -> void:
	status_label.text = "Début du combat..."
	CombatClient.start_combat(GameState.player_id, selected_zone_id, selected_entry.get("id", ""))


func _on_combat_disconnected() -> void:
	if combat_finished:
		return

	in_combat = false
	status_label.text = "Connexion perdue"
	show_result("Connexion perdue", COLOR_ERROR, ["Le serveur de combat ne répond plus."])


func _on_combat_message(data: Dictionary) -> void:
	match str(data.get("type", "")):
		"combat_started":
			on_combat_started(data)
		"player_basic_attack":
			on_player_basic_attack(data)
		"player_skill_used":
			on_player_skill_used(data)
		"monster_attack":
			on_monster_attack(data)
		"combat_won":
			finish_combat()
			await show_victory(data)
		"combat_won_no_reward":
			finish_combat()
			show_result(
				"Victoire",
				COLOR_HIGHLIGHT,
				["Ce monstre venait d'être vaincu : pas de récompense cette fois.", str(data.get("reason", ""))]
			)
		"combat_lost":
			finish_combat()
			add_log("💀 Tu es à terre.", COLOR_ERROR)
			show_result("Défaite", COLOR_ERROR, ["Tu t'es fait terrasser. Renforce-toi et reviens !"])
		"error":
			add_log("⚠ " + str(data.get("message", "Erreur inconnue")), COLOR_HIGHLIGHT)


func on_combat_started(data: Dictionary) -> void:
	in_combat = true
	combat_finished = false
	result_overlay.visible = false
	status_label.text = "En combat"

	monster_name.text = str(data.get("monster_name", monster_name.text))

	var monster_max := float(data.get("monster_hp", 1))
	set_monster_hp(monster_max, monster_max)

	var player_max := float(data.get("player_hp", 1))
	set_player_hp(player_max, player_max)

	player_mana.max_value = max(float(data.get("player_mana", 1)), 1.0)
	set_mana(float(data.get("player_mana", 0)))
	mana_regen = float(data.get("player_mana_regen", 0))

	attack_ready_at = 0
	attack_cooldown_ms = int(float(data.get("basic_attack_cooldown", 1)) * 1000)
	skill_ready_at.clear()

	combat_log.clear()
	log_lines = 0
	add_log("Le combat contre %s commence !" % monster_name.text, COLOR_MUTED)


func on_player_basic_attack(data: Dictionary) -> void:
	var damage := float(data.get("final_damage", 0))

	set_monster_hp(float(data.get("monster_hp", 0)), float(data.get("monster_max_hp", monster_hp.max_value)))
	add_log("⚔ Tu frappes : %s dégâts" % format_number(damage))
	spawn_floating_text("-" + format_number(damage), COLOR_DAMAGE_DEALT, monster_card)
	flash(monster_card, Color(1.4, 0.8, 0.8))

	var cooldown := float(data.get("next_ready_in", 0))
	attack_cooldown_ms = max(int(cooldown * 1000), 1)
	attack_ready_at = Time.get_ticks_msec() + attack_cooldown_ms


func on_player_skill_used(data: Dictionary) -> void:
	var skill_id := str(data.get("skill_id", ""))

	set_monster_hp(float(data.get("monster_hp", monster_hp.value)), monster_hp.max_value)

	# Le serveur plafonne les soins aux PV max mais renvoie la valeur brute :
	# on affiche les PV réellement récupérés.
	var hp_before := player_hp.value

	if data.has("player_hp"):
		set_player_hp(float(data["player_hp"]), player_hp.max_value)

	if data.has("player_mana"):
		set_mana(float(data["player_mana"]))

	var details := PackedStringArray()

	for result in data.get("results", []):
		match str(result.get("effect", "")):
			"damage":
				var damage := float(result.get("final_damage", 0))
				details.append("%s dégâts" % format_number(damage))
				spawn_floating_text("-" + format_number(damage), COLOR_DAMAGE_DEALT, monster_card)
				flash(monster_card, Color(1.4, 0.8, 0.8))
			"heal":
				var healed: float = max(0.0, player_hp.value - hp_before)
				details.append("+%s PV" % format_number(healed) if healed > 0 else "PV déjà au maximum")

				if healed > 0:
					spawn_floating_text("+" + format_number(healed), COLOR_BONUS, player_card)

	var line := "✨ %s" % skill_display_name(skill_id)

	if not details.is_empty():
		line += " : " + ", ".join(details)

	add_log(line, Color(0.7, 0.8, 1.0))

	skill_ready_at[skill_id] = Time.get_ticks_msec() + int(float(data.get("next_ready_in", 0)) * 1000)


func on_monster_attack(data: Dictionary) -> void:
	var damage := float(data.get("final_damage", 0))

	set_player_hp(float(data.get("player_hp", 0)), float(data.get("player_max_hp", player_hp.max_value)))

	if data.has("player_mana"):
		set_mana(float(data["player_mana"]))

	add_log(
		"🩸 %s : %s dégâts subis" % [prettify_id(str(data.get("skill_id", "Attaque"))), format_number(damage)],
		COLOR_DAMAGE_TAKEN
	)
	spawn_floating_text("-" + format_number(damage), COLOR_DAMAGE_TAKEN, player_card)
	flash(player_card, Color(1.5, 0.7, 0.7))


func finish_combat() -> void:
	in_combat = false
	combat_finished = true
	status_label.text = "Combat terminé"
	attack_button.disabled = true
	attack_cooldown.value = 0

	for skill_id in skill_slots:
		skill_slots[skill_id].button.disabled = true


# --- Fin de combat ---------------------------------------------------------

func show_result(title: String, color: Color, lines: Array) -> void:
	result_title.text = title
	result_title.add_theme_color_override("font_color", color)

	for child in result_details.get_children():
		child.queue_free()

	for line in lines:
		if str(line).is_empty():
			continue

		var label := Label.new()
		label.text = str(line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		result_details.add_child(label)

	result_overlay.visible = true


func show_victory(data: Dictionary) -> void:
	add_log("🏆 Victoire !", COLOR_HIGHLIGHT)

	var lines: Array = ["✨ +%d XP" % int(data.get("xp_gagne", 0))]

	var loot = data.get("loot")

	if loot is Array and loot.size() >= 2:
		var res := await ApiClient.get_template("item", str(loot[0]))
		var loot_name: String = res.data.get("name", str(loot[0])) if res.ok else prettify_id(str(loot[0]))
		lines.append("🎁 %s ×%d" % [loot_name, int(loot[1])])
	else:
		lines.append("Pas de butin cette fois.")

	if int(data.get("levels_gained", 0)) > 0:
		lines.append("🌟 Niveau %d atteint !" % int(data.get("player_level", 1)))

	for unlock in data.get("newly_unlocked", []):
		lines.append(await GameState.describe_unlock(str(unlock)))

	show_result("Victoire !", COLOR_HIGHLIGHT, lines)

	# Recharge le joueur : la carte et l'écran Personnage se mettent à jour.
	GameState.refresh_player()


# --- Boutons -----------------------------------------------------------------

func _on_attack_pressed() -> void:
	if in_combat:
		CombatClient.basic_attack()


func _on_skill_pressed(skill_id: String) -> void:
	if in_combat:
		CombatClient.use_skill(skill_id)


func _on_flee_pressed() -> void:
	CombatClient.disconnect_from_combat()
	back_requested.emit()


func _on_leave_pressed() -> void:
	CombatClient.disconnect_from_combat()
	back_requested.emit()


func _on_retry_pressed() -> void:
	result_overlay.visible = false
	combat_finished = false
	status_label.text = "Connexion..."

	# Les compétences équipées ont pu changer depuis le début du combat.
	player_name.text = "Toi · Niveau %d" % int(GameState.player.get("level", 1))
	await build_skill_buttons()

	# La connexion reste ouverte après une victoire ou une défaite : on peut
	# relancer directement un combat dessus.
	if CombatClient.is_open():
		start_combat()
	else:
		CombatClient.connect_to_combat()
