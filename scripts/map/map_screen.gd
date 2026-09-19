extends Control


@onready var floor_title: Label = $FloorTitle
@onready var map_viewport: Control = $MapViewport
@onready var map_container: Control = $MapViewport/MapContainer

const ZONE_NODE_SCENE := preload("res://scene/map/ZoneNode.tscn")
var zone_positions: Dictionary = {}

var is_dragging := false
var last_pointer_position := Vector2.ZERO
var map_bounds := Rect2()

const MAP_SCALE := 20.0
const MAP_PADDING := 250.0

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

	map_bounds = calculate_map_bounds(zones)
	map_container.size = map_bounds.size + Vector2(
		MAP_PADDING * 2.0,
		MAP_PADDING * 2.0
	)

	print("Bornes de la map : ", map_bounds)
	print("Taille de la map : ", map_container.size)

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

	var world_position := Vector2(
		raw_x * MAP_SCALE,
		raw_y * MAP_SCALE
	)

	var map_position := (
		world_position
		- map_bounds.position
		+ Vector2(MAP_PADDING, MAP_PADDING)
	)

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
		clamp_map_position()

		last_pointer_position = event.position

	# --- Écran tactile ---
	elif event is InputEventScreenTouch:
		is_dragging = event.pressed
		last_pointer_position = event.position

	elif event is InputEventScreenDrag:
		map_container.position += event.relative
		clamp_map_position()
		
func center_on_zone(zone_id: String) -> void:
	if not zone_positions.has(zone_id):
		print("Impossible de centrer la carte : zone introuvable ", zone_id)
		return

	var zone_position: Vector2 = zone_positions[zone_id]
	var screen_center: Vector2 = map_viewport.size / 2.0

	map_container.position = screen_center - zone_position
	clamp_map_position()

	print("Carte centrée sur : ", zone_id)
	print("Position zone : ", zone_position)
	print("Position map : ", map_container.position)

func calculate_map_bounds(zones: Array) -> Rect2:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF

	for zone in zones:
		var position_data: Dictionary = zone.get("position", {})

		var x := float(position_data.get("x", 0)) * MAP_SCALE
		var y := float(position_data.get("y", 0)) * MAP_SCALE

		min_x = min(min_x, x)
		min_y = min(min_y, y)
		max_x = max(max_x, x)
		max_y = max(max_y, y)

	return Rect2(
		Vector2(min_x, min_y),
		Vector2(max_x - min_x, max_y - min_y)
	)

func clamp_map_position() -> void:
	var viewport_size: Vector2 = map_viewport.size
	var map_size: Vector2 = map_container.size

	var min_x := viewport_size.x - map_size.x
	var min_y := viewport_size.y - map_size.y

	var max_x := 0.0
	var max_y := 0.0

	map_container.position.x = clamp(
		map_container.position.x,
		min_x,
		max_x
	)

	map_container.position.y = clamp(
		map_container.position.y,
		min_y,
		max_y
	)
