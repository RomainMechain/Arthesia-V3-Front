extends Control

# Carte d'un étage : zones et chemins, position du joueur, navigation entre
# étages, fiche de zone (entrer, monter à l'étage suivant, conditions de
# déblocage) et barre du personnage avec accès aux écrans.
#
# Les écrans plein cadre (zone, personnage, quêtes, artisanat) s'ouvrent
# par-dessus avec open_overlay().

const ZONE_NODE_SCENE := preload("res://scene/map/ZoneNode.tscn")
const ZONE_SCREEN_SCENE := preload("res://scene/zone/ZoneScreen.tscn")
const CHARACTER_SCREEN_SCENE := preload("res://scene/character/CharacterScreen.tscn")
const QUEST_JOURNAL_SCENE := preload("res://scene/quests/QuestJournal.tscn")
const CRAFT_SCREEN_SCENE := preload("res://scene/craft/CraftScreen.tscn")
const ZONE_NODE_SCRIPT := preload("res://scripts/map/zone_node.gd")
const LOGIN_SCREEN_SCENE := preload("res://scene/auth/LoginScreen.tscn")

# Les positions des zones (0 à 100) sont multipliées par MAP_SCALE pixels.
const MAP_SCALE := 8.0
const MAP_PADDING := 150.0
# Hauteur approximative de la fiche de zone, pour centrer la zone choisie
# dans la partie de la carte qui reste visible au-dessus.
const SHEET_CLEARANCE := 170.0
const NODE_SIZE := Vector2(120, 104)
# Centre de la pastille dans un marqueur de zone.
const NODE_ANCHOR := Vector2(60, 28)
# Au-delà de cette distance, un appui sur la carte est un glissement.
const DRAG_THRESHOLD := 8.0

const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR

const TYPE_LABELS := {
	"town": "Village",
	"wilderness": "Étendue sauvage",
	"water": "Rives",
	"camp": "Campement",
	"ruins": "Ruines",
	"danger": "Zone dangereuse",
	"boss": "Repaire du gardien",
	"passage": "Passage vers l'étage suivant",
	"lair": "Antre",
}

@onready var map_viewport: Control = $MapViewport
# Script map_canvas.gd : non typé pour pouvoir appeler set_paths().
@onready var map_container = $MapViewport/MapContainer
@onready var top_bar: PanelContainer = $TopBar
@onready var prev_floor_button: Button = $TopBar/Row/PrevFloor
@onready var next_floor_button: Button = $TopBar/Row/NextFloor
@onready var floor_title: Label = $TopBar/Row/Titles/FloorTitle
@onready var floor_subtitle: Label = $TopBar/Row/Titles/FloorSubtitle
@onready var recenter_button: Button = $RecenterButton
@onready var zone_sheet: PanelContainer = $ZoneSheet
@onready var sheet_box: VBoxContainer = $ZoneSheet/SheetBox
@onready var bottom_bar: PanelContainer = $BottomBar
@onready var player_level: Label = $BottomBar/Row/PlayerBox/PlayerLevel
@onready var player_title: Label = $BottomBar/Row/PlayerBox/PlayerTitle
@onready var xp_bar: ProgressBar = $BottomBar/Row/PlayerBox/XpBar
@onready var player_gold: Label = $BottomBar/Row/PlayerBox/PlayerGold
@onready var craft_button: Button = $BottomBar/Row/CraftButton
@onready var quest_button: Button = $BottomBar/Row/QuestButton
@onready var character_button: Button = $BottomBar/Row/CharacterButton

# Étages du jeu ([{id, name}]) et ceux que le joueur peut visiter.
var floors: Array = []
var reachable: Array = []
var viewed_floor_id := ""
var floor_data: Dictionary = {}

var zone_nodes: Dictionary = {}
var zone_positions: Dictionary = {}
var map_bounds := Rect2()

# Zones où une quête peut être rendue : zone_id -> [noms de quêtes].
var ready_quest_zones: Dictionary = {}
var ready_quest_count := 0
var xp_to_next_level := 0
var equipped_title_name := ""

var selected_zone: Dictionary = {}
var sheet_id := 0

# Nombre d'écrans ouverts par-dessus la carte : tant qu'il y en a, la carte
# ne doit pas défiler sous les gestes destinés à ces écrans.
var open_overlays := 0

var is_pressing := false
var is_dragging := false
var press_position := Vector2.ZERO
var last_pointer_position := Vector2.ZERO
var center_tween: Tween

var quest_badge: Label
var character_badge: Label
var hp_bar: ProgressBar
var login_screen: Control


func _ready() -> void:
	var bar_style := UiStyle.card_style(Color(0.1, 0.11, 0.14, 0.92))
	top_bar.add_theme_stylebox_override("panel", bar_style)
	bottom_bar.add_theme_stylebox_override("panel", bar_style)
	zone_sheet.add_theme_stylebox_override("panel", UiStyle.card_style(Color(0.12, 0.13, 0.16, 0.97)))

	# Le bouton de recentrage prend le style des barres pour ne pas être
	# confondu avec le badge de position d'une zone.
	for style_name in ["normal", "hover", "pressed"]:
		var style := UiStyle.card_style(Color(0.1, 0.11, 0.14, 0.92) if style_name == "normal" else Color(0.18, 0.19, 0.23, 0.95))
		style.set_corner_radius_all(24)
		recenter_button.add_theme_stylebox_override(style_name, style)
	UiStyle.style_bar(xp_bar, UiStyle.COLOR_XP)

	# Barre de PV au-dessus de la barre d'XP : elle remonte en continu.
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 6)
	hp_bar.show_percentage = false
	UiStyle.style_bar(hp_bar, UiStyle.COLOR_HP)
	xp_bar.get_parent().add_child(hp_bar)
	xp_bar.get_parent().move_child(hp_bar, xp_bar.get_index())

	quest_badge = make_badge(quest_button)
	character_badge = make_badge(character_button)

	prev_floor_button.pressed.connect(func(): change_viewed_floor(-1))
	next_floor_button.pressed.connect(func(): change_viewed_floor(1))
	recenter_button.pressed.connect(center_on_player)
	craft_button.pressed.connect(_on_craft_button_pressed)
	quest_button.pressed.connect(_on_quest_button_pressed)
	character_button.pressed.connect(_on_character_button_pressed)

	GameState.session_failed.connect(_on_session_failed)
	GameState.player_changed.connect(_on_player_changed)
	GameState.floor_changed.connect(_on_floor_changed)

	# Sans session, l'écran de connexion couvre la carte. Se déconnecter
	# recharge la scène pour repartir d'une carte vide.
	Auth.needs_login.connect(func(): show_login())
	GameState.character_needed.connect(func(error): show_login("character", error))
	Auth.signed_out.connect(func(): get_tree().reload_current_scene())

	if not Auth.is_signed_in() and not GameState.is_ready:
		floor_title.text = "Arthesia"
		floor_subtitle.text = ""

		# Après une déconnexion, la scène est rechargée alors qu'Auth a déjà
		# fini de démarrer : needs_login ne sera plus émis.
		if not Auth.is_restoring:
			show_login.call_deferred()

	if GameState.is_ready:
		_on_session_ready()
	else:
		GameState.session_ready.connect(_on_session_ready)


# --- Session et données ---------------------------------------------------------

func _on_session_ready() -> void:
	update_hud()
	await refresh_meta()
	await load_floor(GameState.floor_id, true)


func _on_session_failed(message: String) -> void:
	floor_title.text = "Erreur"
	floor_subtitle.text = message


# Le joueur a changé (combat, quête, déblocage...) : barre, badges et état des
# zones sont recalculés sans recentrer la carte.
func _on_player_changed(_player: Dictionary) -> void:
	update_hud()

	if floor_data.is_empty():
		return

	await refresh_meta()
	build_map()

	if not selected_zone.is_empty():
		show_zone_sheet(selected_zone)


func _on_floor_changed(floor_id: String) -> void:
	await refresh_meta()
	await load_floor(floor_id, true)


# Étages atteignables, quêtes prêtes à rendre et seuil d'XP.
func refresh_meta() -> void:
	var floors_res := await ApiClient.get_player_floors(GameState.player_id)

	if floors_res.ok:
		floors = floors_res.data.get("floors", [])
		reachable = floors_res.data.get("reachable", [])

	var quests_res := await ApiClient.get_player_quests(GameState.player_id)

	if quests_res.ok:
		ready_quest_zones.clear()
		ready_quest_count = 0

		for entry in quests_res.data.get("quests", []):
			if not entry.get("ready", false):
				continue

			ready_quest_count += 1

			for giver in entry.get("givers", []):
				var zone_id := str(giver.get("zone_id", ""))

				if not ready_quest_zones.has(zone_id):
					ready_quest_zones[zone_id] = []

				ready_quest_zones[zone_id].append(str(entry.get("quest", {}).get("name", "")))

	var stats_res := await ApiClient.get_player_stats(GameState.player_id)

	if stats_res.ok:
		xp_to_next_level = int(stats_res.data.get("xp_to_next_level", 0))

	equipped_title_name = await GameState.equipped_title_name()

	update_hud()
	update_floor_header()


func load_floor(floor_id: String, center: bool) -> void:
	var res := await ApiClient.get_floor(floor_id)

	if not res.ok:
		floor_title.text = "Étage introuvable"
		floor_subtitle.text = res.error
		return

	viewed_floor_id = floor_id
	floor_data = res.data
	close_zone_sheet()
	build_map()
	update_floor_header()

	if center:
		center_on_player(false)


# --- Barre du personnage et badges ------------------------------------------------

func make_badge(button: Button) -> Label:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.25, 0.25)
	style.set_corner_radius_all(9)
	style.content_margin_left = 5
	style.content_margin_right = 5

	var badge := Label.new()
	badge.add_theme_stylebox_override("normal", style)
	badge.add_theme_font_size_override("font_size", 11)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(34, -6)
	badge.visible = false
	button.add_child(badge)
	return badge


func set_badge(badge: Label, count: int) -> void:
	badge.visible = count > 0
	badge.text = str(count)


func update_hud() -> void:
	var player: Dictionary = GameState.player
	var level := int(player.get("level", 1))
	var xp := int(player.get("xp", 0))

	player_level.text = "Niveau %d" % level
	player_title.text = "🏅 " + equipped_title_name
	player_title.visible = not equipped_title_name.is_empty()
	xp_bar.max_value = max(xp_to_next_level, 1)
	xp_bar.value = xp
	xp_bar.tooltip_text = "%d / %d XP" % [xp, xp_to_next_level]
	player_gold.text = "💰 %d or" % int(player.get("currency", {}).get("or", 0))
	update_hp_bar()

	set_badge(character_badge, int(player.get("stat_points", {}).get("available", 0)))
	set_badge(quest_badge, ready_quest_count)


func update_hp_bar() -> void:
	var max_hp := GameState.max_hp()
	var hp := GameState.current_hp()
	hp_bar.max_value = max(max_hp, 1)
	hp_bar.value = hp
	hp_bar.tooltip_text = "❤ %d / %d PV" % [int(hp), int(max_hp)]


func _process(_delta: float) -> void:
	# Les PV remontent avec le temps : la barre suit tant qu'ils ne sont pas pleins.
	if GameState.is_ready and hp_bar.value < hp_bar.max_value:
		update_hp_bar()


# --- Navigation entre étages --------------------------------------------------------

func floor_index(floor_id: String) -> int:
	for i in floors.size():
		if floors[i].get("id", "") == floor_id:
			return i

	return -1


func update_floor_header() -> void:
	if floor_data.is_empty():
		return

	var index := floor_index(viewed_floor_id)
	floor_title.text = floor_data.get("name", "Étage")

	var zones: Array = floor_data.get("zones", [])
	var open_count := 0

	for zone in zones:
		if zone_state(zone) == "open":
			open_count += 1

	var subtitle := "Étage %d" % (index + 1) if index >= 0 else "Étage"
	subtitle += " · %d / %d zones ouvertes" % [open_count, zones.size()]

	if not current_zone_on_floor():
		subtitle += " · tu n'es pas ici"

	floor_subtitle.text = subtitle

	prev_floor_button.disabled = index <= 0
	var next_id := str(floors[index + 1].get("id", "")) if index >= 0 and index + 1 < floors.size() else ""
	next_floor_button.disabled = next_id.is_empty() or not reachable.has(next_id)
	next_floor_button.tooltip_text = "Étage suivant" if not next_floor_button.disabled else "Franchis le passage de cet étage pour monter"


func change_viewed_floor(direction: int) -> void:
	var index := floor_index(viewed_floor_id) + direction

	if index < 0 or index >= floors.size():
		return

	var floor_id := str(floors[index].get("id", ""))

	if not reachable.has(floor_id):
		return

	await load_floor(floor_id, true)


# --- Construction de la carte ---------------------------------------------------------

func current_zone_on_floor() -> bool:
	var current := str(GameState.player.get("current_zone_id", ""))

	for zone in floor_data.get("zones", []):
		if zone.get("id", "") == current:
			return true

	return false


# "open" : accessible ; "locked" : visible mais verrouillée ; "hidden" : cachée
# tant que sa condition n'est pas remplie.
func zone_state(zone: Dictionary) -> String:
	var unlocked: Array = GameState.player.get("unlocks", {}).get("zones", [])

	if zone.get("unlock_condition") == null or unlocked.has(zone.get("id", "")):
		return "open"

	if zone.get("visibility", "visible") == "hidden":
		return "hidden"

	return "locked"


func build_map() -> void:
	var zones: Array = floor_data.get("zones", [])

	for child in map_container.get_children():
		child.queue_free()

	zone_nodes.clear()
	zone_positions.clear()

	map_bounds = calculate_map_bounds(zones)
	map_container.size = map_bounds.size + Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)

	var current := str(GameState.player.get("current_zone_id", ""))

	for zone in zones:
		var state := zone_state(zone)

		if state == "hidden":
			continue

		var zone_id: String = zone.get("id", "")
		var position_data: Dictionary = zone.get("position", {})
		var map_position := (
			Vector2(float(position_data.get("x", 0)), float(position_data.get("y", 0))) * MAP_SCALE
			- map_bounds.position
			+ Vector2(MAP_PADDING, MAP_PADDING)
		)
		zone_positions[zone_id] = map_position

		var node = ZONE_NODE_SCENE.instantiate()
		map_container.add_child(node)
		node.position = map_position - NODE_ANCHOR
		node.setup(zone, state, zone_id == current, ready_quest_zones.has(zone_id))
		node.zone_selected.connect(_on_zone_selected)
		zone_nodes[zone_id] = node

		if selected_zone.get("id", "") == zone_id:
			node.set_selected(true)

	var paths: Array = []

	for connection in floor_data.get("connections", []):
		if connection.size() < 2 or not zone_positions.has(connection[0]) or not zone_positions.has(connection[1]):
			continue

		var both_open := (
			zone_state(zone_by_id(connection[0])) == "open"
			and zone_state(zone_by_id(connection[1])) == "open"
		)
		paths.append([zone_positions[connection[0]], zone_positions[connection[1]], both_open])

	map_container.set_paths(paths)
	clamp_map_position()


func zone_by_id(zone_id: String) -> Dictionary:
	for zone in floor_data.get("zones", []):
		if zone.get("id", "") == zone_id:
			return zone

	return {}


func calculate_map_bounds(zones: Array) -> Rect2:
	if zones.is_empty():
		return Rect2()

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)

	for zone in zones:
		var position_data: Dictionary = zone.get("position", {})
		var point := Vector2(float(position_data.get("x", 0)), float(position_data.get("y", 0))) * MAP_SCALE
		min_point = min_point.min(point)
		max_point = max_point.max(point)

	return Rect2(min_point, max_point - min_point)


# --- Déplacement de la carte ----------------------------------------------------------

# Zone de la carte réellement visible entre les deux barres.
func visible_center() -> Vector2:
	var top := top_bar.position.y + top_bar.size.y
	var bottom := bottom_bar.position.y
	return Vector2(map_viewport.size.x / 2.0, (top + bottom) / 2.0)


func clamp_map_position() -> void:
	var viewport_size: Vector2 = map_viewport.size
	var map_size: Vector2 = map_container.size
	var target: Vector2 = map_container.position

	for axis in [0, 1]:
		if map_size[axis] <= viewport_size[axis]:
			# Carte plus petite que l'écran : elle reste centrée.
			target[axis] = (viewport_size[axis] - map_size[axis]) / 2.0
		else:
			target[axis] = clamp(target[axis], viewport_size[axis] - map_size[axis], 0.0)

	map_container.position = target


func center_on(map_point: Vector2, animate := true, above_sheet := false) -> void:
	if center_tween != null and center_tween.is_valid():
		center_tween.kill()

	var start: Vector2 = map_container.position
	var screen_point := visible_center()

	if above_sheet:
		screen_point.y -= SHEET_CLEARANCE / 2.0

	map_container.position = screen_point - map_point
	clamp_map_position()
	var target: Vector2 = map_container.position

	if not animate:
		return

	map_container.position = start
	center_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	center_tween.tween_property(map_container, "position", target, 0.35)


# Centre sur la position du joueur, ou sur la zone de départ de l'étage affiché.
func center_on_player(animate := true) -> void:
	var current := str(GameState.player.get("current_zone_id", ""))

	if not zone_positions.has(current) and GameState.floor_id != viewed_floor_id:
		await load_floor(GameState.floor_id, false)

		current = current if zone_positions.has(current) else str(floor_data.get("start_zone_id", ""))

	if zone_positions.has(current):
		center_on(zone_positions[current], animate)


# Les clics sur le fond de la carte arrivent au nœud racine : le fond, la
# vue et le conteneur ignorent la souris, et les barres comme les pastilles
# de zone gardent leurs propres clics. Tant que le bouton reste enfoncé, Godot
# continue d'envoyer les mouvements ici, même hors du point de départ.
func _gui_input(event: InputEvent) -> void:
	if open_overlays > 0:
		return

	# Le toucher est converti en souris par Godot (emulate_mouse_from_touch) :
	# seuls les événements souris sont traités pour ne pas bouger deux fois.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_pressing = true
			is_dragging = false
			press_position = event.position
			last_pointer_position = event.position
		else:
			# Un appui bref sur le fond de la carte ferme la fiche de zone.
			if is_pressing and not is_dragging:
				close_zone_sheet()

			is_pressing = false
			is_dragging = false

	elif event is InputEventMouseMotion and is_pressing:
		if not is_dragging and event.position.distance_to(press_position) > DRAG_THRESHOLD:
			is_dragging = true

			if center_tween != null and center_tween.is_valid():
				center_tween.kill()

		if is_dragging:
			map_container.position += event.position - last_pointer_position
			clamp_map_position()

		last_pointer_position = event.position


# --- Fiche de zone --------------------------------------------------------------------

func _on_zone_selected(zone: Dictionary) -> void:
	if selected_zone.get("id", "") == zone.get("id", "") and zone_sheet.visible:
		close_zone_sheet()
		return

	select_zone(zone)

	if zone_positions.has(zone.get("id", "")):
		center_on(zone_positions[zone.get("id", "")], true, true)

	show_zone_sheet(zone)


func select_zone(zone: Dictionary) -> void:
	for zone_id in zone_nodes:
		zone_nodes[zone_id].set_selected(zone_id == zone.get("id", ""))

	selected_zone = zone


func close_zone_sheet() -> void:
	sheet_id += 1
	selected_zone = {}
	zone_sheet.visible = false

	for zone_id in zone_nodes:
		if zone_nodes[zone_id].is_selected:
			zone_nodes[zone_id].set_selected(false)


func make_label(text: String, font_size := 0, color = null, wrap := true) -> Label:
	var label := Label.new()
	label.text = text

	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)

	if color != null:
		label.add_theme_color_override("font_color", color)

	return label


func show_zone_sheet(zone: Dictionary) -> void:
	sheet_id += 1
	var id := sheet_id
	var was_visible := zone_sheet.visible

	for child in sheet_box.get_children():
		child.queue_free()

	var state := zone_state(zone)
	var zone_type := str(zone.get("type", ""))
	var zone_id := str(zone.get("id", ""))
	var is_current := zone_id == str(GameState.player.get("current_zone_id", ""))

	# En-tête : icône, nom, fermeture.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(make_label(ZONE_NODE_SCRIPT.icon_for(zone_type) if state == "open" else "🔒", 22, null, false))

	var name_label := make_label(str(zone.get("name", "Zone")), 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.custom_minimum_size = Vector2(36, 36)
	close.pressed.connect(close_zone_sheet)
	header.add_child(close)
	sheet_box.add_child(header)

	var meta := str(TYPE_LABELS.get(zone_type, GameText.prettify_id(zone_type)))

	if is_current:
		meta += " · 📍 Tu es ici"

	sheet_box.add_child(make_label(meta, 12, COLOR_HIGHLIGHT if is_current else COLOR_MUTED))

	if state == "open":
		await fill_open_sheet(zone, id)
	else:
		await fill_locked_sheet(zone, id)

	if id != sheet_id:
		return

	zone_sheet.visible = true

	# Petite apparition depuis le bas à l'ouverture.
	if not was_visible:
		zone_sheet.modulate.a = 0.0
		var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(zone_sheet, "modulate:a", 1.0, 0.18)


func fill_open_sheet(zone: Dictionary, _id: int) -> void:
	var zone_id := str(zone.get("id", ""))
	var description := str(zone.get("description", ""))

	if not description.is_empty():
		sheet_box.add_child(make_label(description, 13, COLOR_MUTED))

	for quest_name in ready_quest_zones.get(zone_id, []):
		sheet_box.add_child(make_label("❗ Quête à rendre : " + str(quest_name), 13, COLOR_HIGHLIGHT))

	if zone.get("type", "") == "passage":
		add_passage_action()
		return

	var enter := make_sheet_button("Entrer  ›")
	enter.pressed.connect(func(): enter_zone(zone, enter))


func make_sheet_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 17)
	sheet_box.add_child(button)
	return button


func add_passage_action() -> void:
	var index := floor_index(viewed_floor_id)

	if index < 0 or index + 1 >= floors.size():
		sheet_box.add_child(make_label("Au-delà, la Tour n'a pas encore été explorée.", 13, COLOR_MUTED))
		return

	var next_floor: Dictionary = floors[index + 1]
	var climb := make_sheet_button("🌀 Monter : %s" % next_floor.get("name", "étage suivant"))
	climb.pressed.connect(func(): climb_to(str(next_floor.get("id", "")), climb))


func fill_locked_sheet(zone: Dictionary, id: int) -> void:
	var hint := str(zone.get("hint", ""))

	if not hint.is_empty() and hint != "<null>":
		sheet_box.add_child(make_label("« %s »" % hint, 13, Color(0.85, 0.82, 0.75)))

	var lines := await GameState.describe_condition(zone.get("unlock_condition"))

	if id != sheet_id or lines.is_empty():
		return

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(make_label("Pour débloquer :", 13, null, false))

	for line in lines:
		if line[1] == null:
			box.add_child(make_label(str(line[0]), 12, COLOR_MUTED))
		else:
			box.add_child(make_label(("✓ " if line[1] else "✗ ") + str(line[0]), 12, COLOR_BONUS if line[1] else COLOR_MUTED))

	sheet_box.add_child(box)


# Se déplace dans la zone (le serveur vérifie l'accès) puis l'ouvre.
func enter_zone(zone: Dictionary, button: Button) -> void:
	var zone_id := str(zone.get("id", ""))

	if zone_id != str(GameState.player.get("current_zone_id", "")):
		button.disabled = true
		button.text = "En route..."
		var res := await GameState.travel(zone_id)

		if not res.ok:
			button.disabled = false
			button.text = "Entrer  ›"
			sheet_box.add_child(make_label("⚠ " + res.error, 13, COLOR_ERROR))
			return

	close_zone_sheet()
	var zone_screen = ZONE_SCREEN_SCENE.instantiate()
	open_overlay(zone_screen)
	zone_screen.setup(zone)


# Monte à l'étage suivant : déplacement vers sa zone de départ.
func climb_to(floor_id: String, button: Button) -> void:
	button.disabled = true
	button.text = "Ascension..."

	var res := await ApiClient.get_floor(floor_id)
	var travel_res := res

	if res.ok:
		travel_res = await GameState.travel(str(res.data.get("start_zone_id", "")))

	if not travel_res.ok:
		button.disabled = false
		button.text = "🌀 Réessayer"
		sheet_box.add_child(make_label("⚠ " + travel_res.error, 13, COLOR_ERROR))


# --- Écrans par-dessus la carte ---------------------------------------------------------

func _on_character_button_pressed() -> void:
	if GameState.is_ready:
		open_overlay(CHARACTER_SCREEN_SCENE.instantiate())


func _on_quest_button_pressed() -> void:
	if GameState.is_ready:
		open_overlay(QUEST_JOURNAL_SCENE.instantiate())


func _on_craft_button_pressed() -> void:
	if GameState.is_ready:
		open_overlay(CRAFT_SCREEN_SCENE.instantiate())


func show_login(mode := "sign_in", message := "") -> void:
	if login_screen == null:
		login_screen = LOGIN_SCREEN_SCENE.instantiate()
		add_child(login_screen)
		login_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		open_overlays += 1
		login_screen.closed.connect(
			func():
				open_overlays -= 1
				login_screen.queue_free()
				login_screen = null
		)

	if mode != "sign_in" or not message.is_empty():
		login_screen.show_mode(mode, message)


# Affiche un écran plein cadre par-dessus la carte. L'écran doit émettre
# back_requested pour se fermer.
func open_overlay(screen: Control) -> void:
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	open_overlays += 1
	is_pressing = false
	is_dragging = false

	screen.back_requested.connect(
		func():
			open_overlays -= 1
			screen.queue_free()
	)
