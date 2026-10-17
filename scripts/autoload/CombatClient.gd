extends Node

signal connected
signal disconnected
signal message_received(data: Dictionary)

var socket := WebSocketPeer.new()
var is_connected := false


func connect_to_combat() -> void:
	socket = WebSocketPeer.new()
	is_connected = false
	
	# Même serveur que l'API HTTP : http:// devient ws://, https:// devient wss://.
	var url := ApiClient.BASE_URL.replace("http", "ws") + "/ws/combat"

	print("Connexion WebSocket : ", url)

	var error := socket.connect_to_url(url)

	if error != OK:
		print("Erreur de connexion WebSocket : ", error)


func _process(_delta: float) -> void:
	socket.poll()

	var state := socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			print("WebSocket connecté !")
			connected.emit()

		while socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()
			var text_data := packet.get_string_from_utf8()

			var data = JSON.parse_string(text_data)

			if typeof(data) == TYPE_DICTIONARY:
				message_received.emit(data)

	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			print("WebSocket déconnecté")
			disconnected.emit()

func start_combat(
	player_id: String,
	zone_id: String,
	entry_id: String
) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("Impossible de démarrer : WebSocket non connecté")
		return

	var message := {
		"action": "start_combat",
		"player_id": player_id,
		"zone_id": zone_id,
		"entry_id": entry_id
	}

	socket.send_text(JSON.stringify(message))

	print("Commande start_combat envoyée : ", message)

func disconnect_from_combat() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.close(1000, "Combat terminé")

func basic_attack() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("Impossible d'attaquer : WebSocket non connecté")
		return

	var message := {
		"action": "basic_attack"
	}

	socket.send_text(JSON.stringify(message))
	print("Attaque basique envoyée")

func use_skill(skill_id: String) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("Impossible d'utiliser la compétence : WebSocket non connecté")
		return

	var message := {
		"action": "use_skill",
		"skill_id": skill_id
	}

	socket.send_text(JSON.stringify(message))
	print("Compétence envoyée : ", skill_id)
