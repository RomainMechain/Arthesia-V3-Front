extends VBoxContainer

# Base commune des fiches de commerce (boutique, Autel des Ventes) : en-tête
# avec l'or du joueur, onglets, sélecteur de quantité, message de résultat et
# exécution des actions. Les panneaux concrets implémentent render_tab().
#
# Créés avec preload(...).new(), puis setup() une fois ajoutés à l'arbre. Le
# contenu se reconstruit à chaque changement du joueur.

const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR

var zone_id := ""
var entry: Dictionary = {}
var template: Dictionary = {}

var tabs: Array = []
var current_tab := ""

var gold_label: Label
var tab_bar: HBoxContainer
var message_box: VBoxContainer
var content: VBoxContainer

# Templates d'objets déjà chargés (nom, catégorie, valeur...).
var items: Dictionary = {}
var is_submitting := false

# Incrémenté à chaque rendu d'onglet : un chargement terminé après coup ne
# doit pas écraser un onglet plus récent.
var render_id := 0


func setup(p_zone_id: String, p_entry: Dictionary, p_template: Dictionary) -> void:
	zone_id = p_zone_id
	entry = p_entry
	template = p_template

	add_theme_constant_override("separation", 10)
	build_header()
	GameState.player_changed.connect(_on_player_changed)
	show_tab(tabs[0][0])


# À redéfinir : sous-titre de l'en-tête et onglets [[id, libellé], ...].
func subtitle() -> String:
	return ""


# À redéfinir : remplit content pour l'onglet demandé.
func render_tab(_tab: String, _id: int) -> void:
	pass


func _on_player_changed(_player: Dictionary) -> void:
	update_gold()
	refresh()


# --- Structure ----------------------------------------------------------------

func build_header() -> void:
	add_child(make_label(template.get("name", "Commerce"), 22))

	var meta := subtitle()

	if not meta.is_empty():
		add_child(make_label(meta, 13, COLOR_MUTED))

	gold_label = make_label("", 15, COLOR_HIGHLIGHT, false)
	add_child(gold_label)
	update_gold()

	tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	add_child(tab_bar)

	for tab in tabs:
		var button := Button.new()
		button.text = tab[1]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(func(): show_tab(tab[0]))
		tab_bar.add_child(button)

	message_box = VBoxContainer.new()
	add_child(message_box)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	add_child(content)


func show_tab(tab: String) -> void:
	current_tab = tab

	for i in tabs.size():
		tab_bar.get_child(i).button_pressed = tabs[i][0] == tab

	clear_message()
	refresh()


func refresh() -> void:
	render_id += 1
	render_tab(current_tab, render_id)


func update_gold() -> void:
	gold_label.text = "💰 Tu as %d or" % gold()


func gold() -> int:
	return int(GameState.player.get("currency", {}).get("or", 0))


# --- Outils d'affichage -------------------------------------------------------

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


func clear_content() -> void:
	for child in content.get_children():
		child.queue_free()


func add_content_label(text: String, font_size := 0, color = null) -> Label:
	var label := make_label(text, font_size, color)
	content.add_child(label)
	return label


func make_card_box() -> VBoxContainer:
	var card := UiStyle.make_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	content.add_child(card)
	return box


# Ligne « nom à gauche, détail à droite ».
func make_row(left: String, right: String, right_color = COLOR_HIGHLIGHT) -> HBoxContainer:
	var row := HBoxContainer.new()
	var left_label := make_label(left, 15)
	left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_label)
	row.add_child(make_label(right, 14, right_color, false))
	return row


# Sélecteur − / quantité / + borné entre minimum et maximum. state.value
# porte la valeur courante ; on_change est appelé après chaque modification.
func make_stepper(state: Dictionary, minimum: int, maximum: int, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(40, 40)
	row.add_child(minus)

	var value_label := make_label(str(state.value), 15, null, false)
	value_label.custom_minimum_size = Vector2(36, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(40, 40)
	row.add_child(plus)

	var update := func():
		value_label.text = str(state.value)
		minus.disabled = state.value <= minimum
		plus.disabled = state.value >= maximum
		on_change.call()

	minus.pressed.connect(
		func():
			state.value = max(minimum, state.value - 1)
			update.call()
	)
	plus.pressed.connect(
		func():
			state.value = min(maximum, state.value + 1)
			update.call()
	)
	update.call()

	return row


func make_action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(110, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


# --- Données ------------------------------------------------------------------

func load_items(item_ids: Array) -> void:
	for item_id in item_ids:
		if items.has(item_id):
			continue

		var res := await ApiClient.get_template("item", item_id)
		items[item_id] = res.data if res.ok else {}


func item_name(item_id: String) -> String:
	return items.get(item_id, {}).get("name", GameText.prettify_id(item_id))


func inventory() -> Dictionary:
	return GameState.player.get("inventory", {})


# Objets du sac triés par nom.
func sorted_inventory_ids() -> Array:
	var ids: Array = inventory().keys()
	ids.sort_custom(func(a, b): return item_name(a).naturalnocasecmp_to(item_name(b)) < 0)
	return ids


# --- Messages et actions ------------------------------------------------------

func clear_message() -> void:
	for child in message_box.get_children():
		child.queue_free()


func show_message(text: String, color: Color) -> void:
	clear_message()

	var card := UiStyle.make_card(Color(0.17, 0.2, 0.15) if color == COLOR_BONUS else UiStyle.COLOR_CARD)
	card.add_child(make_label(text, 14, color))
	message_box.add_child(card)

	card.modulate.a = 0.0
	create_tween().tween_property(card, "modulate:a", 1.0, 0.2)


func run_action(action: String, body: Dictionary, success_text: String) -> bool:
	if is_submitting:
		return false

	is_submitting = true
	var res := await GameState.perform_action(action, body)
	is_submitting = false

	if res.ok:
		show_message(success_text, COLOR_BONUS)
	else:
		show_message("⚠ " + res.error, COLOR_ERROR)

	# Le rechargement du joueur a redessiné l'onglet pendant l'action, boutons
	# désactivés : on le redessine maintenant qu'elle est terminée.
	refresh()
	return res.ok
