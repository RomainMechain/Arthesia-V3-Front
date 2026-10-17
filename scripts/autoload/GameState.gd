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
