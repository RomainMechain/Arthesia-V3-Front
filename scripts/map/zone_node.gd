extends Control


@onready var zone_button: Button = $ZoneButton
@onready var zone_name: Label = $ZoneName


var zone_data: Dictionary = {}


func setup(data: Dictionary) -> void:
	zone_data = data

	zone_name.text = data.get("name", "Zone")
