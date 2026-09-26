extends Node

const BASE_URL := "http://127.0.0.1:8000"

var http: HTTPRequest
var current_request := ""


signal floor_received(data)
signal player_received(data)
signal zone_received(data)
signal template_received(kind, template_id, data)

func _ready() -> void:
	pass


func health_check() -> void:
	current_request = "health"

	var url := BASE_URL + "/health"

	print("GET ", url)

	var error := http.request(url)

	if error != OK:
		print("Erreur lors de la requête : ", error)


func get_floor(floor_id: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(
		func(result, response_code, headers, body):
			_on_floor_request_completed(
				http,
				result,
				response_code,
				headers,
				body
			)
	)

	var url := BASE_URL + "/content/floors/" + floor_id
	print("GET ", url)

	var error := http.request(url)

	if error != OK:
		print("Erreur lors de la requête Floor : ", error)
		http.queue_free()
		
func get_player(player_id: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(
		func(result, response_code, headers, body):
			_on_player_request_completed(
				http,
				result,
				response_code,
				headers,
				body
			)
	)

	var url := BASE_URL + "/players/" + player_id
	print("GET ", url)

	var error := http.request(url)

	if error != OK:
		print("Erreur lors de la requête Player : ", error)
		http.queue_free()
		
func get_zone(zone_id: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(
		func(result, response_code, headers, body):
			_on_zone_request_completed(
				http,
				result,
				response_code,
				headers,
				body
			)
	)

	var url := BASE_URL + "/content/zones/" + zone_id
	print("GET ", url)

	var error := http.request(url)

	if error != OK:
		print("Erreur lors de la requête Zone : ", error)
		http.queue_free()
		
func get_template(kind: String, template_id: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(
		func(result, response_code, headers, body):
			_on_template_request_completed(
				http,
				kind,
				template_id,
				result,
				response_code,
				headers,
				body
			)
	)

	var url := (
		BASE_URL
		+ "/content/templates/"
		+ kind
		+ "/"
		+ template_id
	)

	print("GET ", url)

	var error := http.request(url)

	if error != OK:
		print("Erreur lors de la requête Template : ", error)
		http.queue_free()
		
func _on_floor_request_completed(
	http: HTTPRequest,
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	http.queue_free()

	print("Floor HTTP status : ", response_code)

	if response_code != 200:
		print("Erreur HTTP Floor : ", response_code)
		return

	var response_text := body.get_string_from_utf8()

	var json := JSON.new()
	var parse_result := json.parse(response_text)

	if parse_result != OK:
		print("Erreur JSON Floor : ", json.get_error_message())
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		print("Erreur : la réponse Floor n'est pas un objet JSON")
		return

	print("Floor reçu : ", data.get("name", "Sans nom"))

	floor_received.emit(data)
	
func _on_player_request_completed(
	http: HTTPRequest,
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	http.queue_free()

	print("Player HTTP status : ", response_code)

	if response_code != 200:
		print("Erreur HTTP Player : ", response_code)
		return

	var response_text := body.get_string_from_utf8()

	var json := JSON.new()
	var parse_result := json.parse(response_text)

	if parse_result != OK:
		print("Erreur JSON Player : ", json.get_error_message())
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		print("Erreur : la réponse Player n'est pas un objet JSON")
		return

	print("Player reçu : ", data.get("player_id", "Inconnu"))
	print(
		"Zones débloquées : ",
		data.get("unlocks", {}).get("zones", [])
	)

	player_received.emit(data)

func _on_zone_request_completed(
	http: HTTPRequest,
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	http.queue_free()

	print("Zone HTTP status : ", response_code)

	if response_code != 200:
		print("Erreur HTTP Zone : ", response_code)
		return

	var response_text := body.get_string_from_utf8()

	var json := JSON.new()
	var parse_result := json.parse(response_text)

	if parse_result != OK:
		print("Erreur JSON Zone : ", json.get_error_message())
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		print("Erreur : la réponse Zone n'est pas un objet JSON")
		return

	print("Zone reçue : ", data.get("name", "Sans nom"))
	print("Nombre d'entries : ", data.get("entries", []).size())

	zone_received.emit(data)

func _on_template_request_completed(
	http: HTTPRequest,
	kind: String,
	template_id: String,
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	http.queue_free()

	print("Template HTTP status : ", response_code)

	if response_code != 200:
		print("Erreur HTTP Template : ", response_code)
		return

	var response_text := body.get_string_from_utf8()

	var json := JSON.new()
	var parse_result := json.parse(response_text)

	if parse_result != OK:
		print(
			"Erreur JSON Template : ",
			json.get_error_message()
		)
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		print(
			"Erreur : la réponse Template n'est pas un objet JSON"
		)
		return

	print(
		"Template reçu : ",
		data.get("id", "Sans id")
	)

	template_received.emit(
		kind,
		template_id,
		data
	)
