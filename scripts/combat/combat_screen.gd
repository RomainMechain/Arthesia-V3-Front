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

var selected_entry: Dictionary = {}
var selected_zone_id := ""

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

func prepare_combat(zone_id: String, entry: Dictionary) -> void:
	selected_zone_id = zone_id
	selected_entry = entry

	print("Combat préparé :")
	print("Zone : ", selected_zone_id)
	print("Entry : ", selected_entry.get("id", ""))

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

	elif event_type == "combat_lost":
		combat_log.add_text("Défaite !\n")

	elif event_type == "error":
		print("Erreur combat : ", data.get("message", ""))


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
	CombatClient.basic_attack()
	
func _on_attack_cooldown_finished() -> void:
	attack_button.disabled = false
	attack_button.text = "⚔ Attaque basique"

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)

	CombatClient.connected.connect(_on_combat_connected)
	CombatClient.message_received.connect(_on_combat_message)
	attack_button.pressed.connect(_on_attack_pressed)
	attack_cooldown_timer.timeout.connect(_on_attack_cooldown_finished)
	attack_button.disabled = true
