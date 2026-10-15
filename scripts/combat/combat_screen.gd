extends Control

signal back_requested

@onready var back_button: Button = $BackButton
@onready var monster_name: Label = $MonsterName
@onready var monster_hp: ProgressBar = $MonsterHP
@onready var monster_hp_label: Label = $MonsterHPLabel
@onready var player_hp: ProgressBar = $PlayerHP
@onready var player_hp_label: Label = $PlayerHPLabel
@onready var player_mana: ProgressBar = $PlayerMana
@onready var player_mana_label: Label = $PlayerManaLabel
@onready var attack_button: Button = $AttackButton
@onready var combat_log: RichTextLabel = $CombatLog
@onready var attack_cooldown_timer: Timer = $AttackCooldownTimer
@onready var skill_button: Button = $SkillButton
@onready var skills_container: HBoxContainer = $SkillsContainer

var selected_entry: Dictionary = {}
var selected_zone_id := ""
var combat_finished := false
var equipped_skills: Array = []

func setup_combat(data: Dictionary) -> void:
	monster_name.text = data.get("monster_name", "Monstre")

	var monster_max_hp: float = float(data.get("monster_hp", 1))
	var player_max_hp: float = float(data.get("player_hp", 1))
	var player_max_mana: float = float(data.get("player_mana", 1))

	monster_hp.max_value = monster_max_hp
	monster_hp.value = monster_max_hp
	monster_hp_label.text = "%d / %d PV" % [
		int(monster_max_hp),
		int(monster_max_hp)
	]

	player_hp.max_value = player_max_hp
	player_hp.value = player_max_hp
	player_hp_label.text = "%d / %d PV" % [
		int(player_max_hp),
		int(player_max_hp)
	]

	player_mana.max_value = player_max_mana
	player_mana.value = player_max_mana
	player_mana_label.text = "%d / %d Mana" % [
		int(player_max_mana),
		int(player_max_mana)
	]

	combat_log.clear()
	combat_log.add_text("Le combat commence !\n")

func prepare_combat(
	zone_id: String,
	entry: Dictionary,
	player: Dictionary
) -> void:
	selected_zone_id = zone_id
	selected_entry = entry

	equipped_skills = player.get("skills", {}).get("equipped_active", []).duplicate()
	
	build_skill_buttons()

	print("Combat préparé :")
	print("Zone : ", selected_zone_id)
	print("Entry : ", selected_entry.get("id", ""))
	print("Compétences équipées en combat : ", equipped_skills)

	CombatClient.connect_to_combat()

func _on_combat_connected() -> void:
	CombatClient.start_combat(
		"Newsimi",
		selected_zone_id,
		selected_entry.get("id", "")
	)


func _on_combat_message(data: Dictionary) -> void:
	var event_type: String = data.get("type", "")

	print("CombatScreen reçoit : ", event_type)

	if event_type == "combat_started":
		setup_combat(data)
		attack_button.disabled = false
		for button in skills_container.get_children():
			button.disabled = false
		
	elif event_type == "player_basic_attack":
		var current_hp: float = float(data.get("monster_hp", 0))
		var max_hp: float = float(data.get("monster_max_hp", 1))
		var damage: float = float(data.get("final_damage", 0))

		monster_hp.max_value = max_hp
		monster_hp.value = current_hp

		monster_hp_label.text = "%.1f / %.1f PV" % [
			current_hp,
			max_hp
		]

		combat_log.add_text(
			"Tu attaques le monstre : -%.1f PV\n" % damage
		)
		
		var cooldown: float = float(data.get("next_ready_in", 0.0))

		if cooldown > 0.0:
			attack_button.disabled = true
			attack_button.text = "Attaque en recharge..."
			attack_cooldown_timer.start(cooldown)

	elif event_type == "player_skill_used":
		var current_monster_hp: float = float(
			data.get("monster_hp", monster_hp.value)
		)
		var max_monster_hp: float = float(
			data.get("monster_max_hp", monster_hp.max_value)
		)

		monster_hp.max_value = max_monster_hp
		monster_hp.value = current_monster_hp

		monster_hp_label.text = "%.1f / %.1f PV" % [
			current_monster_hp,
			max_monster_hp
		]
		
		# Mettre à jour les PV du joueur, notamment après un soin.
		if data.has("player_hp"):
			var current_hp: float = float(data["player_hp"])

			player_hp.value = current_hp
			player_hp_label.text = "%.1f / %.1f PV" % [
				current_hp,
				player_hp.max_value
			]

		# Afficher les effets réellement appliqués par le serveur.
		var results: Array = data.get("results", [])

		for result in results:
			var effect_type: String = str(result.get("effect", ""))

			match effect_type:
				"heal":
					var amount: float = float(result.get("amount", 0))
					combat_log.add_text(
						"💚 Soin : +%.1f PV\n" % amount
					)

				"damage":
					var damage: float = float(result.get("final_damage", 0))
					combat_log.add_text(
						"⚔ Dégâts : %.1f\n" % damage
					)

		if data.has("player_mana"):
			var current_mana: float = float(data["player_mana"])

			player_mana.value = current_mana
			player_mana_label.text = "%.1f / %.1f Mana" % [
				current_mana,
				player_mana.max_value
			]

	elif event_type == "monster_attack":
		var current_hp: float = float(data.get("player_hp", 0))
		var max_hp: float = float(data.get("player_max_hp", 1))
		var damage: float = float(data.get("final_damage", 0))
		var skill_id: String = data.get("skill_id", "")

		update_player_hp(current_hp, max_hp)

		combat_log.add_text(
			"Le monstre utilise %s : -%.1f PV\n" % [
				skill_id,
				damage
			]
		)

	elif event_type == "combat_won":
		finish_combat(true)
		show_victory_rewards(data)
		ApiClient.get_player("Newsimi")

	elif event_type == "combat_won_no_reward":
		print("Victoire sans récompense : ", data)
		finish_combat(true)

	elif event_type == "combat_lost":
		finish_combat(false)

	elif event_type == "error":
		print("Erreur complète du backend : ", data)

		combat_log.add_text(
			"⚠ %s\n" % str(data.get("message", "Erreur inconnue"))
		)


func _on_back_pressed() -> void:
	CombatClient.disconnect_from_combat()
	back_requested.emit()
	
func update_player_hp(current_hp: float, max_hp: float) -> void:
	player_hp.max_value = max_hp
	player_hp.value = current_hp

	player_hp_label.text = "%.1f / %.1f PV" % [
		current_hp,
		max_hp
	]

func _on_attack_pressed() -> void:
	if combat_finished:
		return

	CombatClient.basic_attack()
	
func _on_attack_cooldown_finished() -> void:
	if combat_finished:
		return

	attack_button.disabled = false
	attack_button.text = "⚔ Attaque basique"
	
func finish_combat(victory: bool) -> void:
	combat_finished = true
	for button in skills_container.get_children():
		button.disabled = true

	attack_cooldown_timer.stop()
	attack_button.disabled = true

	if victory:
		attack_button.text = "🏆 Combat terminé"
		combat_log.add_text("\n🏆 VICTOIRE !\n")
	else:
		attack_button.text = "💀 Combat terminé"
		combat_log.add_text("\n💀 DÉFAITE !\n")
		
func show_victory_rewards(data: Dictionary) -> void:
	var xp_gained: float = float(data.get("xp_gagne", 0))
	var levels_gained: int = int(data.get("levels_gained", 0))
	var player_level: int = int(data.get("player_level", 1))

	combat_log.add_text("✨ +%d XP\n" % int(xp_gained))

	var loot: Array = data.get("loot", [])

	if loot.size() >= 2:
		var item_id: String = str(loot[0])
		var quantity: int = int(loot[1])

		combat_log.add_text(
			"🎁 Butin : %s x%d\n" % [item_id.replace("_", " ").capitalize(), quantity]
		)

	if levels_gained > 0:
		combat_log.add_text(
			"🌟 Niveau supérieur ! Niveau %d\n" % player_level
		)
		
func _on_player_refreshed(data: Dictionary) -> void:
	equipped_skills = data.get("skills", {}).get("equipped_active", [])

	print("Compétences actives équipées : ", equipped_skills)

func _on_skill_pressed() -> void:
	if combat_finished:
		return

	CombatClient.use_skill("charge_du_sanglier")
	
func build_skill_buttons() -> void:
	for child in skills_container.get_children():
		child.queue_free()

	for skill_id in equipped_skills:
		var button := Button.new()

		button.text = str(skill_id).replace("_", " ").capitalize()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = true

		button.pressed.connect(
			func():
				if not combat_finished:
					CombatClient.use_skill(str(skill_id))
		)

		skills_container.add_child(button)

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)

	CombatClient.connected.connect(_on_combat_connected)
	CombatClient.message_received.connect(_on_combat_message)
	attack_button.pressed.connect(_on_attack_pressed)
	attack_cooldown_timer.timeout.connect(_on_attack_cooldown_finished)
	attack_button.disabled = true
	ApiClient.player_received.connect(_on_player_refreshed)
