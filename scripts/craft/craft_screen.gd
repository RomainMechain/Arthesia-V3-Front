extends Control

# Écran Artisanat, ouvert depuis la carte : on crafte partout, sans aller à
# un atelier. Deux pages construites en code dans Body :
#
# * la liste des ateliers, avec le niveau du joueur dans chaque métier ;
# * un atelier : réglage, ingrédients du sac, bouton Fabriquer et résultat.
#
# Une combinaison inédite est inventée par l'IA côté serveur, puis devient la
# recette de tout le monde. Le bouton retour ramène de l'atelier à la liste.

signal back_requested

const TOUCH_SCROLL := preload("res://scripts/ui/touch_scroll.gd")
const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_HIGHLIGHT := UiStyle.COLOR_HIGHLIGHT
const COLOR_ERROR := UiStyle.COLOR_ERROR

# Même limite que MAX_CRAFT_ITEMS côté serveur : objets d'un craft, quantités comprises.
const MAX_INPUTS := 4
# Fabrications d'affilée d'une recette connue (CraftRequest.times côté serveur).
const MAX_TIMES := 20
# Un niveau de métier couvre deux niveaux d'objet (balance.ITEM_LEVELS_PER_PROFESSION_LEVEL côté serveur).
const ITEM_LEVELS_PER_PROFESSION_LEVEL := 2
# Un objet de cette génération ne sert plus d'ingrédient (craft_rules.MAX_CRAFT_GENERATION côté serveur).
const MAX_CRAFT_GENERATION := 2

const STAT_LABELS := {"hp": "PV", "atk": "ATK", "def": "DEF", "agi": "AGI", "int": "INT", "sag": "SAG"}

@onready var back_button: Button = $Layout/Header/BackButton
@onready var title_label: Label = $Layout/Header/Title
@onready var scroll: ScrollContainer = $Layout/Scroll
@onready var body: VBoxContainer = $Layout/Scroll/Body

var workshops: Array = []
var items: Dictionary = {}

var workshop: Dictionary = {}
var parameters: Dictionary = {}
# item_id -> quantité choisie, dans l'ordre d'ajout.
var selection: Dictionary = {}
var is_crafting := false
# Type d'objet choisi dans l'atelier (orientation de la rune pour l'enchantement).
var item_type := ""
# Nombre de fabrications d'affilée demandé (recette connue seulement).
var times := 1
var last_result: Dictionary = {}
var last_error := ""
# Fenêtre du carnet de recettes, ouverte par-dessus l'atelier (null sinon).
var book_overlay: Control


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	show_workshops()


# --- Outils d'affichage -------------------------------------------------------

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


func add_card_box(color := UiStyle.COLOR_CARD) -> VBoxContainer:
	var card := UiStyle.make_card(color)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	body.add_child(card)
	return box


func item_name(item_id: String) -> String:
	return items.get(item_id, {}).get("name", GameText.prettify_id(item_id))


func item_level(item_id: String) -> int:
	return int(items.get(item_id, {}).get("level", 1))


func profession_id() -> String:
	return str(workshop.get("profession_required", {}).get("profession_id", ""))


func max_item_level(level: int) -> int:
	return level * ITEM_LEVELS_PER_PROFESSION_LEVEL


func profession_level(id: String) -> int:
	# Un métier jamais pratiqué commence au niveau 1 (règle du serveur).
	return int(GameState.player.get("professions", {}).get(id, {}).get("level", 1))


func load_items(item_ids: Array) -> void:
	for item_id in item_ids:
		if items.has(item_id):
			continue

		var res := await ApiClient.get_template("item", item_id)
		items[item_id] = res.data if res.ok else {}


# --- Page : liste des ateliers ----------------------------------------------

func show_workshops() -> void:
	workshop = {}
	title_label.text = "Artisanat"
	clear_body()

	if workshops.is_empty():
		add_label("Chargement des ateliers...", 14, COLOR_MUTED)
		var res := await ApiClient.get_content("/content/templates/workshop")

		if not res.ok:
			clear_body()
			add_label("Impossible de charger les ateliers : " + res.error, 14, COLOR_ERROR)
			return

		for summary in res.data:
			var detail := await ApiClient.get_template("workshop", str(summary.get("id", "")))

			if detail.ok:
				workshops.append(detail.data)

		clear_body()

	add_label("Assemble des objets de ton sac. Une combinaison jamais tentée donne naissance à un objet inédit, qui devient la recette de tous les joueurs.", 13, COLOR_MUTED)

	for entry in workshops:
		body.add_child(build_workshop_card(entry))


func build_workshop_card(entry: Dictionary) -> Button:
	var prof := str(entry.get("profession_required", {}).get("profession_id", ""))
	var button := UiStyle.make_card_button(72)
	button.pressed.connect(func(): open_workshop(entry))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.add_theme_constant_override("separation", 12)
	button.add_child(row)

	var icon := make_label(GameText.PROFESSION_ICONS.get(prof, "🔨"), 24, null, false)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.custom_minimum_size = Vector2(30, 0)
	row.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_child(make_label(str(entry.get("name", "Atelier")), 16, null, false))

	var subtitle := make_label("%s · niveau %d" % [GameText.profession_name(prof), profession_level(prof)], 12, COLOR_MUTED, false)
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(subtitle)
	row.add_child(text_box)

	var chevron := make_label("›", 22, COLOR_MUTED, false)
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chevron)

	return button


# --- Page : atelier -------------------------------------------------------------

func open_workshop(entry: Dictionary) -> void:
	workshop = entry
	parameters = {}
	selection = {}
	item_type = ""
	last_result = {}
	last_error = ""
	title_label.text = str(entry.get("name", "Atelier"))
	scroll.scroll_vertical = 0

	clear_body()
	add_label("Chargement du sac...", 14, COLOR_MUTED)

	# Les objets du sac et ceux du carnet de cet atelier (ingrédients et résultats).
	var ids: Array = GameState.player.get("inventory", {}).keys()

	for recipe in workshop_recipes():
		ids.append(str(recipe.get("output_item_id", "")))

		for input in recipe.get("inputs", []):
			ids.append(str(input.get("item_id", "")))

	await load_items(ids)
	render_workshop()


func render_workshop() -> void:
	clear_body()

	var prof := profession_id()
	var level := profession_level(prof)

	add_label(str(workshop.get("description", "")), 13, COLOR_MUTED)
	add_label(
		"%s · niveau %d — ingrédients jusqu'au niveau %d" % [GameText.profession_label(prof), level, max_item_level(level)],
		13,
		COLOR_HIGHLIGHT
	)

	if not last_result.is_empty():
		add_result_card()
	elif not last_error.is_empty():
		var box := add_card_box()
		box.add_child(make_label("⚠ " + last_error, 14, COLOR_ERROR))

	add_item_types()
	add_parameters()
	add_selection()
	add_craft_button()
	add_craft_book()
	add_inventory_picker(level)


# --- Type d'objet, générations, enchantement (craft_rules côté serveur) ------

func is_enchanting() -> bool:
	return workshop.get("mode", "") == "enchant"


func item_generation(item_id: String) -> int:
	return int(items.get(item_id, {}).get("generation", 0))


# Un ingrédient déjà travaillé interdit de fabriquer un matériau.
func selection_reworked() -> bool:
	for item_id in selection:
		if item_generation(item_id) >= 1:
			return true

	return false


func available_types() -> Array:
	var reworked := selection_reworked()
	return workshop.get("item_types", []).filter(func(t): return not (reworked and t.get("category", "") == "material"))


# Pourquoi un objet du sac ne peut pas entrer dans ce craft ("" s'il le peut).
func unusable_reason(item_id: String) -> String:
	var item: Dictionary = items.get(item_id, {})

	if item.get("enchanted", false):
		return "enchanté"
	if item_generation(item_id) >= MAX_CRAFT_GENERATION:
		return "trop travaillé"
	if is_enchanting():
		var category := str(item.get("category", ""))

		if category != "equipment" and category != "material":
			return "ni équipement ni matériau"
		if category == "equipment" and selection.keys().any(func(id): return items.get(id, {}).get("category", "") == "equipment"):
			return "un seul équipement"

	return ""


func add_item_types() -> void:
	var types := available_types()

	# Un type devenu impossible (matériau après un ingrédient travaillé) est oublié.
	if not types.any(func(t): return t.get("id", "") == item_type):
		item_type = ""

	var box := add_card_box()
	box.add_child(make_label("Orientation de la rune" if is_enchanting() else "Ce que tu fabriques", 15, null, false))

	if is_enchanting():
		box.add_child(make_label("Pose un équipement et 1 à 3 matériaux : la rune le renforce. Un objet ne s'enchante qu'une fois, puis ne sert plus dans aucun craft.", 12, COLOR_MUTED))
	elif selection_reworked():
		box.add_child(make_label("Avec un ingrédient déjà travaillé, seuls un équipement ou un consommable sont possibles.", 12, COLOR_MUTED))

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)

	for type in types:
		var chip := Button.new()
		chip.text = str(type.get("label", type.get("id", "")))
		chip.toggle_mode = true
		chip.button_pressed = type.get("id", "") == item_type
		chip.custom_minimum_size = Vector2(0, 38)
		chip.disabled = is_crafting
		chip.pressed.connect(
			func():
				item_type = str(type.get("id", ""))
				render_workshop()
		)
		flow.add_child(chip)

	box.add_child(flow)


func add_parameters() -> void:
	for parameter in workshop.get("parameters", []):
		var id := str(parameter.get("id", ""))
		var box := add_card_box()
		box.add_child(make_label(str(parameter.get("label", GameText.prettify_id(id))), 15, null, false))

		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)

		for option in parameter.get("options", []):
			var chip := Button.new()
			chip.text = str(option)
			chip.toggle_mode = true
			chip.button_pressed = parameters.get(id, "") == option
			chip.custom_minimum_size = Vector2(0, 38)
			chip.disabled = is_crafting
			chip.pressed.connect(
				func():
					parameters[id] = option
					render_workshop()
			)
			flow.add_child(chip)

		box.add_child(flow)


func add_selection() -> void:
	var box := add_card_box()
	box.add_child(make_label("Ingrédients  (%d / %d objets)" % [selected_count(), MAX_INPUTS], 15, null, false))

	if selection.is_empty():
		box.add_child(make_label("Ajoute des objets de ton sac ci-dessous.", 12, COLOR_MUTED))
		return

	for item_id in selection:
		var owned := int(GameState.player.get("inventory", {}).get(item_id, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_label := make_label(item_name(item_id), 14, GameText.rarity_color(items.get(item_id, {})))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(38, 38)
		minus.disabled = is_crafting or selection[item_id] <= 1
		minus.pressed.connect(
			func():
				selection[item_id] -= 1
				render_workshop()
		)
		row.add_child(minus)

		var quantity := make_label("%d / %d" % [selection[item_id], owned], 13, null, false)
		quantity.custom_minimum_size = Vector2(48, 0)
		quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quantity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(quantity)

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(38, 38)
		plus.disabled = is_crafting or selection[item_id] >= owned or selected_count() >= MAX_INPUTS
		plus.pressed.connect(
			func():
				selection[item_id] += 1
				render_workshop()
		)
		row.add_child(plus)

		var remove := Button.new()
		remove.text = "✕"
		remove.flat = true
		remove.custom_minimum_size = Vector2(32, 38)
		remove.disabled = is_crafting
		remove.pressed.connect(
			func():
				selection.erase(item_id)
				render_workshop()
		)
		row.add_child(remove)

		box.add_child(row)


func add_craft_button() -> void:
	# Une série ne vaut que pour une recette du carnet, dans la limite du sac.
	times = clampi(times, 1, maxi(max_times(), 1)) if known_recipe() else 1
	var missing := PackedStringArray()

	if item_type.is_empty():
		missing.append("l'orientation" if is_enchanting() else "ce que tu fabriques")

	for parameter in workshop.get("parameters", []):
		if not parameters.has(str(parameter.get("id", ""))):
			missing.append(str(parameter.get("label", "")).to_lower())

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(craft)

	if is_crafting:
		button.text = "⏳ Fabrication en cours..."
		button.disabled = true
	elif selection.is_empty():
		button.text = "🔨 Fabriquer"
		button.disabled = true
	elif not missing.is_empty():
		button.text = "Choisis : " + ", ".join(missing)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = true
	else:
		button.text = "🔨 Fabriquer" if times <= 1 else "🔨 Fabriquer ×%d" % times

	# Une recette déjà dans le carnet peut se refaire plusieurs fois d'un coup.
	if not is_crafting and missing.is_empty() and known_recipe() and max_times() > 1:
		add_times_row()

	body.add_child(button)

	if is_crafting:
		add_label("Une combinaison inédite peut prendre quelques secondes : l'objet est en train d'être inventé.", 12, COLOR_MUTED)


# --- Carnet de recettes -------------------------------------------------------

# Recettes de cet atelier dans le carnet privé du joueur, la plus récente d'abord.
func workshop_recipes() -> Array:
	var book: Array = GameState.player.get("craft_book", [])
	return book.filter(func(recipe): return str(recipe.get("workshop_id", "")) == str(workshop.get("id", "")))


# Bouton du carnet dans l'atelier : la liste s'ouvre dans une fenêtre.
func add_craft_book() -> void:
	var recipes := workshop_recipes()

	if recipes.is_empty():
		return

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 44)
	button.text = "📖 Mon carnet  (%d recette%s)" % [recipes.size(), "s" if recipes.size() > 1 else ""]
	button.disabled = is_crafting
	button.pressed.connect(open_craft_book)
	body.add_child(button)


func open_craft_book() -> void:
	close_craft_book()

	book_overlay = ColorRect.new()
	book_overlay.color = Color(0, 0, 0, 0.65)
	book_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	book_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(book_overlay)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)

	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)

	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)

	book_overlay.add_child(margin)

	var panel := UiStyle.make_card(Color(0.12, 0.12, 0.14))
	margin.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)

	var title := make_label("📖 Mon carnet · %s" % str(workshop.get("name", "Atelier")), 17, null, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(40, 40)
	close.pressed.connect(close_craft_book)
	header.add_child(close)

	layout.add_child(make_label("Tes recettes restent secrètes : à toi de choisir avec qui les partager.", 12, COLOR_MUTED))

	var list_scroll: ScrollContainer = TOUCH_SCROLL.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(list_scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	list_scroll.add_child(list)

	for recipe in workshop_recipes():
		add_recipe_card(recipe, list)


func close_craft_book() -> void:
	if book_overlay != null:
		book_overlay.queue_free()
		book_overlay = null


func add_recipe_card(recipe: Dictionary, list: VBoxContainer) -> void:
	var card := UiStyle.make_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	list.add_child(card)
	var output_id := str(recipe.get("output_item_id", ""))
	var times := int(recipe.get("times", 1))
	box.add_child(make_label("→ %s" % item_name(output_id), 15, COLOR_HIGHLIGHT))

	var inputs := PackedStringArray()
	var missing := PackedStringArray()
	var inventory: Dictionary = GameState.player.get("inventory", {})

	for input in recipe.get("inputs", []):
		var item_id := str(input.get("item_id", ""))
		var quantity := int(input.get("quantity", 1))
		inputs.append("%d %s" % [quantity, item_name(item_id)])

		if int(inventory.get(item_id, 0)) < quantity:
			missing.append(item_name(item_id))

	box.add_child(make_label(" + ".join(inputs), 13))

	var details := PackedStringArray()
	var recipe_parameters: Dictionary = recipe.get("parameters", {})

	for type in workshop.get("item_types", []):
		if type.get("id", "") == recipe.get("item_type", ""):
			details.append(str(type.get("label", "")).to_lower())

	for parameter in workshop.get("parameters", []):
		var id := str(parameter.get("id", ""))

		if recipe_parameters.has(id):
			details.append("%s : %s" % [str(parameter.get("label", GameText.prettify_id(id))).to_lower(), recipe_parameters[id]])

	details.append("faite %d fois" % times if times > 1 else "faite une fois")
	box.add_child(make_label(" · ".join(details), 12, COLOR_MUTED))

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 38)
	button.disabled = is_crafting or not missing.is_empty()
	button.text = "Reprendre cette recette" if missing.is_empty() else "Il te manque : " + ", ".join(missing)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(func(): use_recipe(recipe))
	box.add_child(button)


# Remet les ingrédients et les paramètres de la recette : il ne reste qu'à fabriquer.
func use_recipe(recipe: Dictionary) -> void:
	close_craft_book()
	selection = {}

	for input in recipe.get("inputs", []):
		selection[str(input.get("item_id", ""))] = int(input.get("quantity", 1))

	parameters = recipe.get("parameters", {}).duplicate()
	item_type = str(recipe.get("item_type", ""))
	last_result = {}
	last_error = ""
	render_workshop()
	scroll.scroll_vertical = 0


func add_inventory_picker(level: int) -> void:
	add_label("🎒 Ton sac", 17)

	var inventory: Dictionary = GameState.player.get("inventory", {})
	var ids: Array = inventory.keys().filter(func(item_id): return not selection.has(item_id))
	ids.sort_custom(func(a, b): return item_name(a).naturalnocasecmp_to(item_name(b)) < 0)

	if ids.is_empty():
		add_label("Rien d'autre à ajouter." if not inventory.is_empty() else "Ton sac est vide.", 13, COLOR_MUTED)
		return

	for item_id in ids:
		var too_high := item_level(item_id) > max_item_level(level)
		var reason := unusable_reason(item_id)
		var button := UiStyle.make_card_button(46)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "  %s  ×%d   ·   niv. %d" % [item_name(item_id), int(inventory[item_id]), item_level(item_id)]

		if not reason.is_empty():
			button.text += "   ·   " + reason
		elif item_generation(item_id) >= 1:
			button.text += "   ·   ⚒ travaillé"

		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		GameText.color_button(button, items.get(item_id, {}))
		button.disabled = too_high or is_crafting or selected_count() >= MAX_INPUTS or not reason.is_empty()

		if too_high:
			button.tooltip_text = "Niveau %d requis dans ce métier" % ceili(item_level(item_id) / float(ITEM_LEVELS_PER_PROFESSION_LEVEL))

		button.pressed.connect(
			func():
				selection[item_id] = 1
				render_workshop()
		)
		body.add_child(button)


# --- Fabrication --------------------------------------------------------------

# Objets choisis, quantités comprises.
func selected_count() -> int:
	var count := 0

	for item_id in selection:
		count += int(selection[item_id])

	return count


# La sélection et les paramètres actuels sont-ils une recette du carnet ?
func known_recipe() -> bool:
	for recipe in workshop_recipes():
		var inputs := {}

		for input in recipe.get("inputs", []):
			inputs[str(input.get("item_id", ""))] = int(input.get("quantity", 1))

		if inputs == selection and recipe.get("parameters", {}) == parameters and str(recipe.get("item_type", "")) == item_type:
			return true

	return false


# Nombre de fois que le sac permet de refaire la sélection.
func max_times() -> int:
	var inventory: Dictionary = GameState.player.get("inventory", {})
	var count := MAX_TIMES

	for item_id in selection:
		count = mini(count, int(inventory.get(item_id, 0)) / maxi(int(selection[item_id]), 1))

	return count


func add_times_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(make_label("Nombre :", 14, null, false))

	for step in [[-1, "−"], [1, "+"]]:
		var button := Button.new()
		button.text = step[1]
		button.custom_minimum_size = Vector2(44, 40)
		button.disabled = times + step[0] < 1 or times + step[0] > max_times()
		button.pressed.connect(
			func():
				times += step[0]
				render_workshop()
		)
		row.add_child(button)

		if step[0] < 0:
			var count := make_label("×%d" % times, 16, null, false)
			count.custom_minimum_size = Vector2(44, 0)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(count)

	var all := Button.new()
	all.text = "Max (%d)" % max_times()
	all.custom_minimum_size = Vector2(0, 40)
	all.disabled = times == max_times()
	all.pressed.connect(
		func():
			times = max_times()
			render_workshop()
	)
	row.add_child(all)
	body.add_child(row)


func craft() -> void:
	if is_crafting or selection.is_empty():
		return

	var inputs: Array = []

	for item_id in selection:
		inputs.append({"item_id": item_id, "quantity": selection[item_id]})

	is_crafting = true
	last_result = {}
	last_error = ""
	render_workshop()

	var res := await GameState.perform_action(
		"craft",
		{"workshop_id": workshop.get("id", ""), "inputs": inputs, "parameters": parameters, "item_type": item_type,
			"times": times if known_recipe() else 1}
	)

	is_crafting = false

	if res.ok:
		last_result = res.data
		var output_id := str(res.data.get("output_item_id", ""))
		items[output_id] = res.data.get("output_item", {})
		items.merge(res.data.get("output_items", {}), true)
	else:
		last_error = res.error

	# On garde la même sélection pour refaire la recette, dans la limite de
	# ce qu'il reste dans le sac.
	var inventory: Dictionary = GameState.player.get("inventory", {})

	for item_id in selection.keys():
		var owned := int(inventory.get(item_id, 0))

		if owned <= 0:
			selection.erase(item_id)
		else:
			selection[item_id] = mini(selection[item_id], owned)

	render_workshop()
	scroll.scroll_vertical = 0


func add_result_card() -> void:
	var item: Dictionary = last_result.get("output_item", {})
	var is_new: bool = not last_result.get("from_cache", true)
	var box := add_card_box(Color(0.2, 0.18, 0.12) if is_new else Color(0.17, 0.2, 0.15))

	box.add_child(make_label("✨ Création inédite !" if is_new else "📜 Recette connue", 15, COLOR_HIGHLIGHT if is_new else COLOR_BONUS, false))
	var made := int(last_result.get("times", 1))
	box.add_child(make_label("🎁 " + str(item.get("name", last_result.get("output_item_id", ""))), 18, GameText.rarity_color(item)))

	if made > 1:
		box.add_child(make_label(produced_summary(made), 13, null))
	elif GameText.is_above_common(item):
		box.add_child(make_label("◆ " + GameText.rarity_name(item), 14, GameText.rarity_color(item), false))

	var category: String = {"equipment": "Équipement", "consumable": "Consommable", "material": "Matériau"}.get(str(item.get("category", "")), "Objet")
	box.add_child(make_label("%s · niveau %d" % [category, int(item.get("level", 1))], 12, COLOR_MUTED))

	var description := str(item.get("description", ""))

	if not description.is_empty():
		box.add_child(make_label(description, 13, COLOR_MUTED))

	var equipment: Dictionary = item.get("equipment", {}) if item.get("equipment") is Dictionary else {}
	var bonuses := PackedStringArray()

	for stat in STAT_LABELS:
		if equipment.get("stat_bonuses", {}).has(stat):
			bonuses.append("%s +%s" % [STAT_LABELS[stat], GameText.format_number(float(equipment["stat_bonuses"][stat]))])

	if not bonuses.is_empty():
		box.add_child(make_label(" · ".join(bonuses), 13, COLOR_BONUS))

	var profession: Dictionary = last_result.get("profession", {})

	if not profession.is_empty():
		box.add_child(make_label("✨ +%d XP %s" % [int(profession.get("xp_gained", 0)), GameText.profession_name(profession_id())], 13, COLOR_BONUS))

		if int(profession.get("levels_gained", 0)) > 0:
			box.add_child(make_label("🌟 %s niveau %d !" % [GameText.profession_name(profession_id()), int(profession.get("level", 1))], 13, COLOR_HIGHLIGHT))


# Série : combien de chaque rang (« ×5 : 3 Commun · 1 Peu commun · 1 Rare »).
func produced_summary(made: int) -> String:
	var counts := {}

	for item_id in last_result.get("produced", {}):
		var rarity := GameText.rarity_of(items.get(item_id, {}))
		counts[rarity] = int(counts.get(rarity, 0)) + int(last_result["produced"][item_id])

	var parts := PackedStringArray()

	for rarity in GameText.RARITY_NAMES:
		if counts.has(rarity):
			parts.append("%d %s" % [counts[rarity], GameText.RARITY_NAMES[rarity]])

	return "×%d : %s  (le meilleur est affiché)" % [made, " · ".join(parts)]


# --- Navigation ---------------------------------------------------------------

func _on_back_pressed() -> void:
	if is_crafting:
		return

	# Le retour ferme d'abord le carnet s'il est ouvert.
	if book_overlay != null:
		close_craft_book()
		return

	if workshop.is_empty():
		back_requested.emit()
	else:
		close_craft_book()
		show_workshops()
