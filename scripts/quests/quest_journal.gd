extends Control

# Journal de quêtes, ouvert depuis la carte : quêtes en cours (progression,
# où les rendre) et quêtes terminées. Une quête s'ouvre dans un QuestPanel.
#
# Le bouton retour du haut ramène de la fiche à la liste, puis à la carte.

signal back_requested

const QUEST_PANEL_SCRIPT := preload("res://scripts/quests/quest_panel.gd")

const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR

@onready var back_button: Button = $Layout/Header/BackButton
@onready var title_label: Label = $Layout/Header/Title
@onready var scroll: ScrollContainer = $Layout/Scroll
@onready var body: VBoxContainer = $Layout/Scroll/Body

# Réponse de GET /players/{id}/quests.
var quests: Array = []
var open_quest_id := ""
var render_id := 0


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	GameState.player_changed.connect(_on_player_changed)
	refresh()


func _on_player_changed(_player: Dictionary) -> void:
	# Une fiche ouverte se met à jour seule ; la liste est rechargée.
	if open_quest_id.is_empty():
		refresh()


func refresh() -> void:
	render_id += 1
	var id := render_id

	if quests.is_empty():
		clear_body()
		add_label("Chargement du journal...", 14, COLOR_MUTED)

	var res := await ApiClient.get_player_quests(GameState.player_id)

	if id != render_id:
		return

	if not res.ok:
		clear_body()
		add_label("Impossible de charger le journal : " + res.error, 14, COLOR_ERROR)
		return

	quests = res.data.get("quests", [])
	show_list()


# --- Affichage --------------------------------------------------------------

func clear_body() -> void:
	for child in body.get_children():
		child.queue_free()


func make_label(text: String, font_size := 0, color = null, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)

	if color != null:
		label.add_theme_color_override("font_color", color)

	return label


func add_label(text: String, font_size := 0, color = null) -> Label:
	var label := make_label(text, font_size, color)
	body.add_child(label)
	return label


func show_list() -> void:
	open_quest_id = ""
	title_label.text = "Journal de quêtes"
	clear_body()

	var active: Array = []
	var completed: Array = []

	for entry in quests:
		if entry.get("state", "") == "active":
			active.append(entry)
		else:
			completed.append(entry)

	# Les quêtes prêtes à rendre d'abord.
	active.sort_custom(func(a, b): return a.get("ready", false) and not b.get("ready", false))

	add_label("📜 En cours  (%d)" % active.size(), 17)

	if active.is_empty():
		add_label("Aucune quête en cours. Parle aux habitants des zones pour en trouver.", 13, COLOR_MUTED)

	for entry in active:
		body.add_child(build_quest_card(entry))

	if not completed.is_empty():
		add_label("✅ Terminées  (%d)" % completed.size(), 17)

		for entry in completed:
			body.add_child(build_quest_card(entry))


func build_quest_card(entry: Dictionary) -> Button:
	var quest: Dictionary = entry.get("quest", {})
	var objectives: Array = entry.get("objectives", [])
	var is_active: bool = entry.get("state", "") == "active"
	var is_ready: bool = entry.get("ready", false)

	var button := UiStyle.make_card_button(70)
	button.pressed.connect(func(): open_quest(entry))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 8
	box.offset_bottom = -8
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	button.add_child(box)

	var name_label := make_label(quest.get("name", "Quête"), 15, null if is_active else COLOR_MUTED, false)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)

	var zone_names := PackedStringArray()

	for giver in entry.get("givers", []):
		zone_names.append(str(giver.get("zone_name", "")))

	var subtitle := ""
	var color = COLOR_MUTED

	if not is_active:
		subtitle = "Terminée"
	elif is_ready:
		subtitle = "✅ Prête à rendre · 📍 " + ", ".join(zone_names)
		color = COLOR_HIGHLIGHT
	else:
		var done := 0

		for objective in objectives:
			if objective.get("done", false):
				done += 1

		subtitle = "%d / %d objectif%s · 📍 %s" % [done, objectives.size(), "s" if objectives.size() > 1 else "", ", ".join(zone_names)]

	var subtitle_label := make_label(subtitle, 12, color, false)
	subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(subtitle_label)

	# Barre de progression globale pour une quête en cours.
	if is_active and not objectives.is_empty():
		var total := 0.0
		var current := 0.0

		for objective in objectives:
			total += float(objective.get("count", 1))
			current += float(objective.get("current", 0))

		var bar := ProgressBar.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.max_value = max(total, 1.0)
		bar.value = current
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		UiStyle.style_bar(bar, COLOR_BONUS if is_ready else COLOR_HIGHLIGHT)
		box.add_child(bar)

	return button


func open_quest(entry: Dictionary) -> void:
	var quest: Dictionary = entry.get("quest", {})
	open_quest_id = str(quest.get("id", ""))
	render_id += 1
	clear_body()
	scroll.scroll_vertical = 0

	# Depuis le journal on suit la quête ; on la rend chez le donneur.
	var panel = QUEST_PANEL_SCRIPT.new()
	body.add_child(panel)
	panel.setup(quest, false, entry.get("givers", []))


func _on_back_pressed() -> void:
	if open_quest_id.is_empty():
		back_requested.emit()
	else:
		open_quest_id = ""
		await refresh()
