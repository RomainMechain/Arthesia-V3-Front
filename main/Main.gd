extends Control


func _ready() -> void:
	ApiClient.floor_received.connect(_on_floor_received)

	ApiClient.get_floor("floor_3")


func _on_floor_received(floor_data: Dictionary) -> void:
	print("================================")
	print("FLOOR REÇU PAR MAIN")
	print("Nom : ", floor_data.get("name"))
	print("Nombre de zones : ", floor_data.get("zones", []).size())
	print("Nombre de connexions : ", floor_data.get("connections", []).size())
	print("================================")
