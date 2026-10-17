extends Node

# Client HTTP du serveur Arthesia.
#
# Toutes les requêtes passent par request_json(), qui renvoie un dictionnaire
# de résultat à attendre avec await :
#
#     var res := await ApiClient.get_floor("floor_1")
#     if res.ok:
#         print(res.data)
#
# Clés du résultat : ok (bool), status (code HTTP, 0 si le serveur est
# injoignable), data (JSON décodé) et error (message lisible si ok est faux).

const BASE_URL := "http://127.0.0.1:8000"

# Le contenu statique (étages, zones, templates) ne change pas pendant une
# session : on le garde en mémoire pour ne pas le redemander à chaque écran.
var _content_cache: Dictionary = {}


func request_json(
	method: HTTPClient.Method,
	path: String,
	body = null
) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var headers := PackedStringArray()
	var body_text := ""

	if body != null:
		headers.append("Content-Type: application/json")
		body_text = JSON.stringify(body)

	var url := BASE_URL + path
	var error := http.request(url, headers, method, body_text)

	if error != OK:
		http.queue_free()
		return _failure(0, "Requête impossible vers %s (erreur %d)" % [path, error])

	var response: Array = await http.request_completed
	http.queue_free()

	var result: int = response[0]
	var status: int = response[1]
	var response_body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return _failure(0, "Serveur injoignable (%s)" % path)

	var data = JSON.parse_string(response_body.get_string_from_utf8())

	if status < 200 or status >= 300:
		# FastAPI renvoie ses erreurs sous la forme {"detail": "..."}.
		var message := "Erreur HTTP %d" % status

		if typeof(data) == TYPE_DICTIONARY and data.has("detail"):
			message = str(data["detail"])

		return _failure(status, message)

	return {"ok": true, "status": status, "data": data, "error": ""}


func get_json(path: String) -> Dictionary:
	return await request_json(HTTPClient.METHOD_GET, path)


func post_json(path: String, body: Dictionary) -> Dictionary:
	return await request_json(HTTPClient.METHOD_POST, path, body)


func get_content(path: String) -> Dictionary:
	if _content_cache.has(path):
		return _content_cache[path]

	var res := await get_json(path)

	if res.ok:
		_content_cache[path] = res

	return res


func _failure(status: int, message: String) -> Dictionary:
	push_warning("API : " + message)
	return {"ok": false, "status": status, "data": null, "error": message}


# --- Contenu statique ---------------------------------------------------------

func health_check() -> Dictionary:
	return await get_json("/health")


func get_floor(floor_id: String) -> Dictionary:
	return await get_content("/content/floors/" + floor_id)


func list_floors() -> Dictionary:
	return await get_content("/content/floors")


func list_zones() -> Dictionary:
	return await get_content("/content/zones")


func get_zone(zone_id: String) -> Dictionary:
	return await get_content("/content/zones/" + zone_id)


func get_template(kind: String, template_id: String) -> Dictionary:
	return await get_content("/content/templates/%s/%s" % [kind, template_id])


# Une entry de zone indique son template_type, qui ne correspond pas toujours
# au type de template côté serveur : un quest_giver référence une quête.
func template_kind_for_entry(entry: Dictionary) -> String:
	var template_type: String = entry.get("template_type", "")

	match template_type:
		"quest_giver":
			return "quest"
		_:
			return template_type


# --- Joueur ----------------------------------------------------------------

func get_player(player_id: String) -> Dictionary:
	return await get_json("/players/" + player_id)


func create_player(player_id: String) -> Dictionary:
	return await post_json("/players", {"player_id": player_id})


# Journal : quêtes démarrées avec définition, progression et zones où les rendre.
func get_player_quests(player_id: String) -> Dictionary:
	return await get_json("/players/%s/quests" % player_id)


# Disponibilité des entries d'une zone ; avec un joueur, les entries dont la
# condition d'apparition n'est pas remplie sont marquées locked.
func get_zone_state(zone_id: String, player_id := "") -> Dictionary:
	var path := "/zones/%s/state" % zone_id

	if not player_id.is_empty():
		path += "?player_id=" + player_id.uri_encode()

	return await get_json(path)


# Statistiques finales, seuil d'XP du niveau courant et gain par point de stat.
func get_player_stats(player_id: String) -> Dictionary:
	return await get_json("/players/%s/stats" % player_id)


# Envoie une action de jeu (POST /actions/<action>) au nom d'un joueur.
func post_action(player_id: String, action: String, body: Dictionary = {}) -> Dictionary:
	var payload := body.duplicate()
	payload["player_id"] = player_id
	return await post_json("/actions/" + action, payload)
