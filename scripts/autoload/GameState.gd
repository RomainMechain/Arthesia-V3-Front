extends Node

# État de la session de jeu : qui joue et sur quel étage.
#
# Le joueur est celui connecté par Auth : son identifiant est son uid
# Firebase. La session démarre à chaque connexion ; un compte sans personnage
# (inscription interrompue, pseudo déjà pris) émet character_needed pour que
# l'écran de connexion demande un pseudo.
#
# L'étage n'est pas stocké : il se déduit de la zone courante du joueur.

signal session_ready
signal session_failed(message: String)
signal character_needed(message: String)
signal player_changed(player: Dictionary)
signal floor_changed(floor_id: String)

var player_id := ""
var player: Dictionary = {}
var floor_id := ""
var is_ready := false

# Pseudo choisi à l'inscription, utilisé pour créer le personnage.
var pending_display_name := ""

# Moment où player.health_view a été reçu : les PV remontent ensuite en
# continu (current_hp), sans redemander le joueur au serveur.
var health_received_ms := 0


func _ready() -> void:
	Auth.signed_in.connect(func(): start_session())
	Auth.signed_out.connect(reset)


func reset() -> void:
	is_ready = false
	player_id = ""
	player = {}
	floor_id = ""


func start_session() -> void:
	is_ready = false
	player_id = Auth.uid

	var player_res := await ApiClient.sync_player(player_id)

	if player_res.status == 404:
		if pending_display_name.is_empty():
			character_needed.emit("")
			return

		player_res = await ApiClient.create_player(player_id, pending_display_name)

		if not player_res.ok:
			# Pseudo pris ou invalide : le compte existe, il faut un autre pseudo.
			character_needed.emit(player_res.error)
			return

	if not player_res.ok:
		session_failed.emit(player_res.error)
		return

	pending_display_name = ""
	_set_player(player_res.data)

	var floor_res := await _resolve_floor_id()

	if not floor_res.ok:
		session_failed.emit(floor_res.error)
		return

	floor_id = floor_res.data
	is_ready = true
	print("Session prête : joueur ", player_id, " | étage ", floor_id)
	session_ready.emit()


# Déplace le joueur dans une zone (le serveur vérifie qu'elle est accessible).
# Change d'étage si la zone est sur un autre étage.
func travel(zone_id: String) -> Dictionary:
	var res := await perform_action("travel", {"zone_id": zone_id})

	if res.ok:
		var new_floor_id := str(res.data.get("floor_id", floor_id))

		if new_floor_id != floor_id:
			floor_id = new_floor_id
			floor_changed.emit(floor_id)

	return res


# Exécute une action pour le joueur courant puis recharge son état, ce qui
# met à jour tous les écrans abonnés à player_changed.
func perform_action(action: String, body: Dictionary = {}) -> Dictionary:
	var res := await ApiClient.post_action(player_id, action, body)

	if res.ok:
		await refresh_player()

	return res


func refresh_player() -> void:
	var res := await ApiClient.get_player(player_id)

	if res.ok:
		_set_player(res.data)


func _set_player(data: Dictionary) -> void:
	player = data
	health_received_ms = Time.get_ticks_msec()
	player_changed.emit(player)


# PV hors combat : ceux perdus aux combats précédents remontent avec le temps
# (plus vite en ville). Le serveur envoie l'état dans player.health_view.
func max_hp() -> float:
	return float(player.get("health_view", {}).get("max", 0))


func current_hp() -> float:
	var view: Dictionary = player.get("health_view", {})

	if view.is_empty():
		return 0.0

	var elapsed := (Time.get_ticks_msec() - health_received_ms) / 1000.0
	return minf(float(view.get("max", 0)), float(view.get("current", 0)) + float(view.get("regen_per_second", 0)) * elapsed)


# Ligne de résumé pour une entrée de quest_progress (combat, récolte).
func describe_quest_progress(update: Dictionary) -> String:
	var quest_name := str(update.get("quest_name", update.get("quest_id", "")))

	if update.get("quest_ready", false):
		return "✅ %s : prête à rendre !" % quest_name

	return "📜 %s : %d / %d" % [quest_name, int(update.get("current", 0)), int(update.get("count", 0))]


# Nom du titre équipé par le joueur courant ("" sans titre).
func equipped_title_name() -> String:
	var title_id = player.get("titles", {}).get("equipped")

	if title_id == null or str(title_id).is_empty():
		return ""

	var res := await ApiClient.get_template("title", str(title_id))
	return str(res.data.get("name", title_id)) if res.ok else GameText.prettify_id(str(title_id))


# Danger d'une zone pour le joueur, d'après sa plage de niveaux : {} si la zone
# n'a pas de combat. Un monstre plus faible rapporte 20 % d'XP en moins par
# niveau d'écart (balance.level_gap_xp_multiplier côté serveur).
func zone_danger(zone: Dictionary) -> Dictionary:
	var level_range = zone.get("level_range")

	if typeof(level_range) != TYPE_ARRAY or level_range.size() < 2 or zone.get("type", "") in ["town", "passage"]:
		return {}

	var low := int(level_range[0])
	var high := int(level_range[1])
	var level := int(player.get("level", 1))
	var label := "Niv. %d" % low if low == high else "Niv. %d-%d" % [low, high]

	if level <= low - 3:
		return {"label": label, "text": "très dangereux pour toi", "color": Color(0.95, 0.35, 0.3)}
	if level < low:
		return {"label": label, "text": "dangereux pour toi", "color": Color(1.0, 0.62, 0.25)}
	if level <= high:
		return {"label": label, "text": "à ta mesure", "color": Color(0.45, 0.85, 0.5)}
	if level <= high + 2:
		return {"label": label, "text": "facile, moins d'XP", "color": Color(0.7, 0.72, 0.75)}
	return {"label": label, "text": "trop facile, peu d'XP", "color": Color(0.5, 0.5, 0.52)}


# État d'une quête pour le joueur courant : "", "active" ou "completed".
func quest_state(quest_id: String) -> String:
	return str(player.get("quests", {}).get(quest_id, {}).get("state", ""))


# Progression d'un objectif de quête active : [actuel, requis]. Même règle que
# game_rules.quest_progress_view côté serveur.
func quest_objective_progress(quest_id: String, objective: Dictionary, index: int) -> Array:
	var counters: Array = player.get("quests", {}).get(quest_id, {}).get("objectives_progress", [])
	var required := int(objective.get("count", 1))
	var current := 0

	match objective.get("type", ""):
		"deliver_item":
			current = int(player.get("inventory", {}).get(objective.get("item_id", ""), 0))
		"level":
			required = int(objective.get("min", 1))
			current = int(player.get("level", 1))
		"zone":
			required = 1
			current = 1 if player.get("unlocks", {}).get("zones", []).has(objective.get("zone_id", "")) else 0
		_:
			if index < counters.size():
				current = int(counters[index].get("current_count", 0))

	return [mini(current, required), required]


# Explique une condition de déblocage, ligne par ligne : [[texte, remplie], ...].
# Les groupes sont aplatis avec une ligne d'introduction (remplie = null).
func describe_condition(condition) -> Array:
	if typeof(condition) != TYPE_DICTIONARY:
		return []

	var lines: Array = []

	if condition.get("type", "") == "group":
		var any: bool = condition.get("mode", "all") == "any"
		lines.append(["Une de ces conditions :" if any else "Toutes ces conditions :", null])

		for child in condition.get("conditions", []):
			lines.append_array(await describe_condition(child))

		return lines

	return [await _describe_leaf_condition(condition)]


func _template_name(kind: String, template_id: String) -> String:
	var res := await ApiClient.get_template(kind, template_id)
	return str(res.data.get("name", template_id)) if res.ok else GameText.prettify_id(template_id)


func _zone_name(zone_id: String) -> String:
	var res := await ApiClient.list_zones()

	if res.ok:
		for zone in res.data:
			if zone.get("id", "") == zone_id:
				return str(zone.get("name", zone_id))

	return GameText.prettify_id(zone_id)


func _describe_leaf_condition(condition: Dictionary) -> Array:
	var counters: Dictionary = player.get("lifetime_counters", {})

	match condition.get("type", ""):
		"level":
			var level := int(player.get("level", 1))
			return ["Atteindre le niveau %d (tu es niveau %d)" % [int(condition.get("min", 1)), level], level >= int(condition.get("min", 1))]
		"quest":
			var quest_id := str(condition.get("quest_id", ""))
			var wanted := str(condition.get("state", "completed"))
			var verb := "Terminer" if wanted == "completed" else "Commencer"
			var state := quest_state(quest_id)
			var met := state == wanted or (wanted == "active" and state == "completed")
			return ["%s la quête « %s »" % [verb, await _template_name("quest", quest_id)], met]
		"item":
			var item_id := str(condition.get("item_id", ""))
			return ["Posséder « %s »" % await _template_name("item", item_id), int(player.get("inventory", {}).get(item_id, 0)) > 0]
		"zone":
			var zone_id := str(condition.get("zone_id", ""))
			return ["Débloquer « %s »" % await _zone_name(zone_id), player.get("unlocks", {}).get("zones", []).has(zone_id)]
		"boss":
			var zone_id := str(condition.get("zone_id", ""))
			var met := false

			# Boss d'étage : vaincu pour tout le serveur (état de la zone).
			var state_res := await ApiClient.get_zone_state(zone_id)

			if state_res.ok:
				for entry_state in state_res.data.get("entries", {}).values():
					if entry_state.get("status", "") == "defeated":
						met = true

			# Autre boss : vaincu par ce joueur (son profil).
			for key in player.get("defeated_entries", []):
				if str(key).begins_with(zone_id + "/"):
					met = true

			return ["Vaincre le gardien de « %s »" % await _zone_name(zone_id), met]
		"kill_count":
			var monster_id := str(condition.get("monster_id", ""))
			var count := int(condition.get("count", 1))
			var done := int(counters.get("kills", {}).get(monster_id, 0))
			return ["Vaincre %d × %s (%d / %d)" % [count, await _template_name("monster", monster_id), mini(done, count), count], done >= count]
		"gather_count":
			var resource_id := str(condition.get("resource_id", ""))
			var count := int(condition.get("count", 1))
			var done := int(counters.get("gathers", {}).get(resource_id, 0))
			return ["Récolter %d × %s (%d / %d)" % [count, await _template_name("resource", resource_id), mini(done, count), count], done >= count]
		"deliver_item":
			var item_id := str(condition.get("item_id", ""))
			var count := int(condition.get("count", 1))
			var done := int(counters.get("deliveries", {}).get(item_id, 0))
			return ["Livrer %d × %s (%d / %d)" % [count, await _template_name("item", item_id), mini(done, count), count], done >= count]
		_:
			return [GameText.prettify_id(str(condition.get("type", "condition"))), false]


# Les déblocages arrivent sous la forme "zone:<id>", "skill:<id>", "title:<id>".
func describe_unlock(unlock: String) -> String:
	var parts := unlock.split(":", true, 1)

	if parts.size() < 2:
		return "🔓 " + unlock

	var kind := parts[0]
	var id := parts[1]

	match kind:
		"zone":
			var res := await ApiClient.list_zones()

			if res.ok:
				for zone in res.data:
					if zone.get("id", "") == id:
						return "🗺 Nouvelle zone : " + str(zone.get("name", id))

			return "🗺 Nouvelle zone : " + GameText.prettify_id(id)
		"skill", "title":
			var res := await ApiClient.get_template(kind, id)
			var label := "📖 Nouvelle compétence : " if kind == "skill" else "🏅 Nouveau titre : "
			return label + (str(res.data.get("name", id)) if res.ok else GameText.prettify_id(id))
		_:
			return "🔓 " + unlock


# Renvoie un résultat au format ApiClient dont data est l'id de l'étage.
func _resolve_floor_id() -> Dictionary:
	var current_zone_id: String = str(player.get("current_zone_id", ""))

	if not current_zone_id.is_empty():
		var zones_res := await ApiClient.list_zones()

		if not zones_res.ok:
			return zones_res

		for zone in zones_res.data:
			if zone.get("id", "") == current_zone_id:
				return {"ok": true, "data": zone.get("floor_id", ""), "error": ""}

		push_warning("Zone courante introuvable dans les étages : " + current_zone_id)

	# Sans zone courante valide, on retombe sur le premier étage.
	var floors_res := await ApiClient.list_floors()

	if not floors_res.ok:
		return floors_res

	if floors_res.data.is_empty():
		return {"ok": false, "data": null, "error": "Aucun étage disponible"}

	return {"ok": true, "data": floors_res.data[0].get("id", ""), "error": ""}
