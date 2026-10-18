extends Node

# État de la session de jeu : qui joue et sur quel étage.
#
# L'identifiant du joueur est enregistré sur l'appareil (SESSION_FILE). Au
# premier lancement, un nouveau joueur est créé côté serveur. Pour reprendre
# un joueur existant pendant le développement, lancer le jeu avec
# --player=<id> (Godot : Projet > Paramètres > Éditeur > Run > Main Run Args).
# Quand l'authentification Firebase sera en place, son uid remplacera cet
# identifiant local.
#
# L'étage n'est pas stocké : il se déduit de la zone courante du joueur.

signal session_ready
signal session_failed(message: String)
signal player_changed(player: Dictionary)
signal floor_changed(floor_id: String)

const SESSION_FILE := "user://session.cfg"

var player_id := ""
var player: Dictionary = {}
var floor_id := ""
var is_ready := false


func _ready() -> void:
	start_session()


func start_session() -> void:
	is_ready = false
	player_id = _resolve_player_id()

	var player_res := await _load_or_create_player()

	if not player_res.ok:
		session_failed.emit(player_res.error)
		return

	_set_player(player_res.data)
	_save_player_id()

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
	player_changed.emit(player)


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


# État d'une quête pour le joueur courant : "", "active" ou "completed".
func quest_state(quest_id: String) -> String:
	return str(player.get("quests", {}).get(quest_id, {}).get("state", ""))


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


func _resolve_player_id() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--player="):
			return arg.trim_prefix("--player=")

	var config := ConfigFile.new()

	if config.load(SESSION_FILE) == OK:
		var saved_id: String = config.get_value("session", "player_id", "")

		if not saved_id.is_empty():
			return saved_id

	return "joueur_" + Crypto.new().generate_random_bytes(4).hex_encode()


func _save_player_id() -> void:
	var config := ConfigFile.new()
	config.load(SESSION_FILE)
	config.set_value("session", "player_id", player_id)
	config.save(SESSION_FILE)


func _load_or_create_player() -> Dictionary:
	var res := await ApiClient.get_player(player_id)

	if res.status == 404:
		print("Joueur ", player_id, " inconnu : création côté serveur")
		res = await ApiClient.create_player(player_id)

	return res


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
