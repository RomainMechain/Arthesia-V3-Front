extends Control


@onready var floor_title: Label = $FloorTitle
@onready var map_viewport: Control = $MapViewport
@onready var map_container: Control = $MapViewport/MapContainer

const ZONE_NODE_SCENE := preload("res://scene/map/ZoneNode.tscn")
var zone_positions: Dictionary = {}

var is_dragging := false
var last_pointer_position := Vector2.ZERO


func _ready() -> void:
	ApiClient.floor_received.connect(_on_floor_received)

	ApiClient.get_floor("floor_3")


func _on_floor_received(floor_data: Dictionary) -> void:
	print("MapScreen a reçu : ", floor_data.get("name"))

	floor_title.text = floor_data.get("name", "Étage")

	build_map(floor_data)


func build_map(floor_data: Dictionary) -> void:
	var zones: Array = floor_data.get("zones", [])
	var connections: Array = floor_data.get("connections", [])

	zone_positions.clear()

	map_container.size = Vector2(2200, 1800)

	if zones.is_empty():
		print("Aucune zone à afficher")
		return

	for zone in zones:
		create_zone(zone)

	create_connections(connections)
	
	var start_zone_id: String = floor_data.get("start_zone_id", "")
	center_on_zone(start_zone_id)
		
func create_zone(zone: Dictionary) -> void:
	var position_data: Dictionary = zone.get("position", {})

	var raw_x := float(position_data.get("x", 0))
	var raw_y := float(position_data.get("y", 0))

	var map_scale := 20.0

	var x := raw_x * map_scale
	var y := raw_y * map_scale

	var map_position := Vector2(x, y)

	var zone_id: String = zone.get("id", "")

	zone_positions[zone_id] = map_position

	create_zone_visual(zone, map_position)
	

func create_zone_visual(zone: Dictionary, map_position: Vector2) -> void:
	var zone_node = ZONE_NODE_SCENE.instantiate()

	map_container.add_child(zone_node)

	zone_node.setup(zone)

	# Notre ZoneNode fait 160 × 80.
	# On décale de 80 px pour que son centre horizontal
	# corresponde exactement à la coordonnée de la map.
	zone_node.position = map_position - Vector2(80, 16)
	
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

func _input(event: InputEvent) -> void:
	# --- Souris ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			last_pointer_position = event.position

	elif event is InputEventMouseMotion and is_dragging:
		var delta: Vector2 = event.position - last_pointer_position

		map_container.position += delta
		last_pointer_position = event.position


	# --- Écran tactile ---
	elif event is InputEventScreenTouch:
		is_dragging = event.pressed
		last_pointer_position = event.position

	elif event is InputEventScreenDrag:
		map_container.position += event.relative
		
func center_on_zone(zone_id: String) -> void:
	if not zone_positions.has(zone_id):
		print("Impossible de centrer la carte : zone introuvable ", zone_id)
		return

	var zone_position: Vector2 = zone_positions[zone_id]
	var screen_center: Vector2 = map_viewport.size / 2.0

	map_container.position = screen_center - zone_position

	print("Carte centrée sur : ", zone_id)
	print("Position zone : ", zone_position)
	print("Position map : ", map_container.position)
