extends Control


@onready var floor_title: Label = $FloorTitle
@onready var map_viewport: Control = $MapViewport
@onready var map_container: Control = $MapViewport/MapContainer
@onready var character_button: Button = $CharacterButton
@onready var quest_button: Button = $QuestButton

const ZONE_NODE_SCENE := preload("res://scene/map/ZoneNode.tscn")
const ZONE_SCREEN_SCENE := preload("res://scene/zone/ZoneScreen.tscn")
const CHARACTER_SCREEN_SCENE := preload("res://scene/character/CharacterScreen.tscn")
const QUEST_JOURNAL_SCENE := preload("res://scene/quests/QuestJournal.tscn")

# Nombre d'écrans ouverts par-dessus la carte : tant qu'il y en a, la carte
# ne doit pas défiler sous les gestes destinés à ces écrans.
var open_overlays := 0
var zone_positions: Dictionary = {}

var is_dragging := false
var last_pointer_position := Vector2.ZERO
var map_bounds := Rect2()

var floor_data: Dictionary = {}
var player_data: Dictionary = {}

const MAP_SCALE := 20.0
const MAP_PADDING := 250.0

var map_initialized := false

func _ready() -> void:
	character_button.pressed.connect(_on_character_button_pressed)
	quest_button.pressed.connect(_on_quest_button_pressed)
	GameState.session_failed.connect(_on_session_failed)
	GameState.player_changed.connect(_on_player_changed)

	floor_title.text = "Connexion..."

	if GameState.is_ready:
		_on_session_ready()
	else:
		GameState.session_ready.connect(_on_session_ready)


func _on_session_ready() -> void:
	var res := await ApiClient.get_floor(GameState.floor_id)

	if not res.ok:
		floor_title.text = "Erreur : " + res.error
		return

	floor_data = res.data
	player_data = GameState.player
	try_build_map()


func _on_session_failed(message: String) -> void:
	floor_title.text = "Erreur : " + message


# Rejoue la construction quand le joueur change, par exemple après une
# victoire qui débloque une nouvelle zone.
func _on_player_changed(data: Dictionary) -> void:
	player_data = data
	try_build_map()


func try_build_map() -> void:
	if floor_data.is_empty():
		print("En attente du Floor...")
		return

	if player_data.is_empty():
		print("En attente du Player...")
		return

	print("Floor + Player disponibles : construction de la map")

	floor_title.text = floor_data.get("name", "Étage")

	build_map(floor_data)

func build_map(floor_data: Dictionary) -> void:
	var zones: Array = floor_data.get("zones", [])
	var connections: Array = floor_data.get("connections", [])
	
	# Supprimer les anciens éléments générés de la carte.
	for child in map_container.get_children():
		child.queue_free()

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
		var zone_state := get_zone_state(zone)

		print(
			"Zone : ",
			zone.get("id", ""),
			" | état : ",
			zone_state
		)
		
		if zone_state == "hidden":
			continue
		
		create_zone(zone, zone_state)

	create_connections(connections)
	
	if not map_initialized:
		var start_zone_id: String = floor_data.get("start_zone_id", "")
		center_on_zone(start_zone_id)
		map_initialized = true


func create_zone(zone: Dictionary, zone_state: String) -> void:
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

	create_zone_visual(zone, map_position, zone_state)
	

func create_zone_visual(
	zone: Dictionary,
	map_position: Vector2,
	zone_state: String
) -> void:
	var zone_node = ZONE_NODE_SCENE.instantiate()

	map_container.add_child(zone_node)

	zone_node.position = map_position - Vector2(80, 16)
	zone_node.setup(zone, zone_state)

	zone_node.zone_selected.connect(_on_zone_selected)
	
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
	if open_overlays > 0:
		return

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

func get_zone_state(zone: Dictionary) -> String:
	var zone_id: String = zone.get("id", "")
	var visibility: String = zone.get("visibility", "visible")

	var unlocks: Dictionary = player_data.get("unlocks", {})
	var unlocked_zones: Array = unlocks.get("zones", [])

	if zone_id in unlocked_zones:
		return "unlocked"

	if visibility == "hidden":
		return "hidden"

	return "locked"

func _on_zone_selected(zone: Dictionary) -> void:
	print("Ouverture de la zone : ", zone.get("id", ""))

	var zone_screen = ZONE_SCREEN_SCENE.instantiate()

	open_overlay(zone_screen)
	zone_screen.setup(zone)


func _on_character_button_pressed() -> void:
	if not GameState.is_ready:
		return

	open_overlay(CHARACTER_SCREEN_SCENE.instantiate())


func _on_quest_button_pressed() -> void:
	if not GameState.is_ready:
		return

	open_overlay(QUEST_JOURNAL_SCENE.instantiate())


# Affiche un écran plein cadre par-dessus la carte. L'écran doit émettre
# back_requested pour se fermer.
func open_overlay(screen: Control) -> void:
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	open_overlays += 1
	is_dragging = false

	screen.back_requested.connect(
		func():
			open_overlays -= 1
			screen.queue_free()
	)
