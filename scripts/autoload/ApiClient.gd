extends Node

const BASE_URL := "http://127.0.0.1:8000"

var http: HTTPRequest
var current_request := ""


signal floor_received(data)


func _ready() -> void:
	http = HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(_on_request_completed)


func health_check() -> void:
	current_request = "health"

	var url := BASE_URL + "/health"

	print("GET ", url)

	var error := http.request(url)

	if error != OK:
		print("Erreur lors de la requête : ", error)


func get_floor(floor_id: String) -> void:
	current_request = "floor"

	var url := BASE_URL + "/content/floors/" + floor_id

	print("GET ", url)

	var error := http.request(url)

	if error != OK:
		print("Erreur lors de la requête : ", error)


func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	print("HTTP result : ", result)
	print("HTTP status : ", response_code)

	var response_text := body.get_string_from_utf8()

	print("Response : ", response_text)

	if current_request == "health":
		print("Health response reçue")

	elif current_request == "floor":
		var json := JSON.new()
		var parse_result := json.parse(response_text)

		if parse_result != OK:
			print("Erreur JSON : ", json.get_error_message())
			return

		var data = json.data

		if typeof(data) != TYPE_DICTIONARY:
			print("Erreur : la réponse du Floor n'est pas un objet JSON")
			return

		print("Floor reçu : ", data.get("name", "Sans nom"))

		floor_received.emit(data)
