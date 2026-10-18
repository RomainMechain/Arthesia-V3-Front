extends Control

# Marqueur d'une zone sur la carte : pastille ronde avec l'icône du type de
# zone, nom en dessous, et badges (position du joueur, quête à rendre).
# Le nœud racine ignore la souris : seule la pastille reçoit le clic, pour
# ne pas masquer les zones voisines.

signal zone_selected(zone_data: Dictionary)

const TYPE_ICONS := {
	"town": "🏘",
	"wilderness": "🌲",
	"water": "🌊",
	"camp": "⛺",
	"ruins": "🏛",
	"danger": "☠",
	"boss": "👑",
	"passage": "🌀",
	"lair": "🐉",
}

const RING_OPEN := Color(0.4, 0.75, 0.7)
const RING_CURRENT := Color(1.0, 0.82, 0.35)
const RING_BOSS := Color(0.9, 0.35, 0.3)
const RING_LOCKED := Color(0.4, 0.4, 0.42)

@onready var zone_button: Button = $ZoneButton
@onready var zone_name: Label = $ZoneName
@onready var badge: Label = $Badge

var zone_data: Dictionary = {}
var is_selected := false


func _ready() -> void:
	zone_button.pressed.connect(func(): zone_selected.emit(zone_data))


static func icon_for(zone_type: String) -> String:
	return TYPE_ICONS.get(zone_type, "📍")


# state : "open" ou "locked" ; is_current : le joueur s'y trouve ;
# quest_ready : une quête peut y être rendue.
func setup(data: Dictionary, state: String, is_current: bool, quest_ready: bool) -> void:
	zone_data = data

	var zone_type: String = data.get("type", "")
	var open := state == "open"

	zone_button.text = icon_for(zone_type) if open else "🔒"
	zone_name.text = data.get("name", "Zone")

	var ring := RING_LOCKED

	if open:
		ring = RING_BOSS if zone_type == "boss" else RING_OPEN

	if is_current:
		ring = RING_CURRENT

	var fill := Color(0.13, 0.14, 0.17) if open else Color(0.1, 0.1, 0.11)

	for style_name in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = fill.lightened(0.08) if style_name in ["hover", "pressed"] else fill
		style.set_corner_radius_all(28)
		style.set_border_width_all(4 if is_current else 3)
		style.border_color = ring
		style.shadow_color = Color(ring, 0.35) if open else Color(0, 0, 0, 0)
		style.shadow_size = 8 if is_current else (4 if open else 0)
		zone_button.add_theme_stylebox_override(style_name, style)

	zone_button.add_theme_font_size_override("font_size", 22)
	zone_name.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88) if open else Color(0.6, 0.6, 0.62))

	if is_current:
		badge.text = "📍"
	elif quest_ready:
		badge.text = "❗"
	else:
		badge.text = ""


func set_selected(selected: bool) -> void:
	is_selected = selected
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(zone_button, "scale", Vector2(1.15, 1.15) if selected else Vector2.ONE, 0.18)
