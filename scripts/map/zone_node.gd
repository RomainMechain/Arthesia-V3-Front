extends Control

signal zone_selected(zone_data: Dictionary)

@onready var zone_button: Button = $ZoneButton
@onready var zone_name: Label = $ZoneName
@onready var zone_status: Label = $ZoneStatus

var zone_data: Dictionary = {}
var zone_state := ""


func _ready() -> void:
	zone_button.pressed.connect(_on_zone_button_pressed)


func setup(data: Dictionary, state: String) -> void:
	zone_data = data
	zone_state = state

	zone_name.text = data.get("name", "Zone")

	if state == "unlocked":
		zone_button.text = "●"
		zone_button.disabled = false
		zone_status.text = ""

	elif state == "locked":
		zone_button.text = "◉"
		zone_button.disabled = true
		zone_status.text = "Verrouillée"


func _on_zone_button_pressed() -> void:
	if zone_state != "unlocked":
		return

	print("Clic sur la zone : ", zone_data.get("id", ""))

	zone_selected.emit(zone_data)
