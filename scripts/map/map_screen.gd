extends Control


@onready var floor_title: Label = $FloorTitle
@onready var map_container: Control = $MapContainer

var zone_positions: Dictionary = {}


func _ready() -> void:
	ApiClient.floor_received.connect(_on_floor_received)

	ApiClient.get_floor("floor_3")


func _on_floor_received(floor_data: Dictionary) -> void:
	print("MapScreen a reçu : ", floor_data.get("name"))

	floor_title.text = floor_data.get("name", "Étage")

	build_map(floor_data)


func build_map(floor_data: Dictionary) -> void:
	var zones: Array = floor_data.get("zones", [])
	
	zone_positions.clear()

	if zones.is_empty():
		print("Aucune zone à afficher")
		return

	# Cherche les limites des coordonnées générées par le backend.
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF

	for zone in zones:
		var position_data: Dictionary = zone.get("position", {})

		var x := float(position_data.get("x", 50))
		var y := float(position_data.get("y", 50))

		min_x = min(min_x, x)
		max_x = max(max_x, x)
		min_y = min(min_y, y)
		max_y = max(max_y, y)

	print("Limites X : ", min_x, " -> ", max_x)
	print("Limites Y : ", min_y, " -> ", max_y)

	for zone in zones:
		create_zone(zone, min_x, max_x, min_y, max_y)
		
	var connections: Array = floor_data.get("connections", [])
	create_connections(connections)
		
func create_zone(
	zone: Dictionary,
	min_x: float,
	max_x: float,
	min_y: float,
	max_y: float
) -> void:

	var position_data: Dictionary = zone.get("position", {})

	var raw_x := float(position_data.get("x", 50))
	var raw_y := float(position_data.get("y", 50))

	# Transforme les coordonnées du backend en valeurs entre 0 et 1.
	var normalized_x := 0.5
	var normalized_y := 0.5

	if max_x != min_x:
		normalized_x = (raw_x - min_x) / (max_x - min_x)

	if max_y != min_y:
		normalized_y = (raw_y - min_y) / (max_y - min_y)

	# Espace réellement utilisable par la carte.
	var margin_x := 55.0
	var margin_top := 150.0
	var margin_bottom := 100.0

	var usable_width := map_container.size.x - (margin_x * 2.0)
	var usable_height := map_container.size.y - margin_top - margin_bottom

	var x := margin_x + normalized_x * usable_width
	var y := margin_top + normalized_y * usable_height
	
	var zone_id: String = zone.get("id", "")
	zone_positions[zone_id] = Vector2(x, y)

	create_zone_visual(zone, Vector2(x, y))
	

func create_zone_visual(zone: Dictionary, map_position: Vector2) -> void:
	var zone_control := Control.new()

	zone_control.size = Vector2(100, 55)
	zone_control.position = map_position - Vector2(50, 16)

	map_container.add_child(zone_control)

	# Point de la zone
	var zone_button := Button.new()

	zone_button.text = "●"
	zone_button.size = Vector2(32, 32)
	zone_button.position = Vector2(34, 0)

	zone_control.add_child(zone_button)

	# Nom de la zone
	var zone_label := Label.new()

	zone_label.text = zone.get("name", "Zone")
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_label.position = Vector2(-25, 32)
	zone_label.size = Vector2(150, 40)

	zone_control.add_child(zone_label)
	
func create_connections(connections: Array) -> void:
	for connection in connections:
		if connection.size() < 2:
			continue

		var from_id: String = connection[0]
		var to_id: String = connection[1]

		if not zone_positions.has(from_id):
			continue

		if not zone_positions.has(to_id):
			continue

		var from_position: Vector2 = zone_positions[from_id]
		var to_position: Vector2 = zone_positions[to_id]

		var line := Line2D.new()

		line.width = 3.0
		line.add_point(from_position)
		line.add_point(to_position)

		map_container.add_child(line)

		# Les lignes doivent être derrière les zones.
		map_container.move_child(line, 0)
