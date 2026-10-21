extends "res://scripts/commerce/commerce_panel.gd"

# Autel des Ventes : marché entre joueurs. Tous les autels partagent les mêmes
# annonces, un objet déposé ici s'achète depuis n'importe quel autre.
#
# Une annonce vend un lot entier (quantité) pour un prix total.

# Annonces actives (GET /market/listings), rechargées à chaque rendu.
var listings: Array = []
var sell_prices: Dictionary = {}
var search_text := ""

# Objet choisi dans l'onglet Vendre (vide : liste du sac).
var selected_item_id := ""


func _init() -> void:
	tabs = [["buy", "Acheter"], ["sell", "Vendre"], ["mine", "Mes annonces"]]


func subtitle() -> String:
	return "🛒 Autel des Ventes · relié à tous les autels"


func show_tab(tab: String) -> void:
	selected_item_id = ""
	super.show_tab(tab)


func render_tab(tab: String, id: int) -> void:
	match tab:
		"buy":
			await render_buy(id)
		"sell":
			await render_sell(id)
		"mine":
			await render_mine(id)


func load_listings() -> bool:
	var res := await ApiClient.get_json("/market/listings")

	if res.ok:
		listings = res.data.get("listings", [])

	return res.ok


func is_mine(listing: Dictionary) -> bool:
	return str(listing.get("seller_player_id", "")) == GameState.player_id


# --- Acheter ------------------------------------------------------------------

func render_buy(id: int) -> void:
	if not await load_listings():
		clear_content()
		add_content_label("Impossible de charger les annonces.", 13, COLOR_ERROR)
		return

	var others: Array = listings.filter(func(listing): return not is_mine(listing))
	var item_ids: Array = []

	for listing in others:
		item_ids.append(str(listing.get("item_id", "")))

	await load_items(item_ids)

	if id != render_id:
		return

	clear_content()

	if others.is_empty():
		add_content_label("Aucune annonce pour l'instant. Reviens plus tard, ou mets tes objets en vente !", 13, COLOR_MUTED)
		return

	var search := LineEdit.new()
	search.placeholder_text = "🔎 Rechercher un objet"
	search.text = search_text
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(0, 40)
	content.add_child(search)

	var results := VBoxContainer.new()
	results.add_theme_constant_override("separation", 8)
	content.add_child(results)

	var fill_results := func():
		for child in results.get_children():
			child.queue_free()

		var shown := 0

		for listing in others:
			if search_text.is_empty() or item_name(str(listing.get("item_id", ""))).to_lower().contains(search_text.to_lower()):
				results.add_child(build_listing_card(listing))
				shown += 1

		if shown == 0:
			results.add_child(make_label("Aucune annonce ne correspond.", 13, COLOR_MUTED))

	search.text_changed.connect(
		func(text: String):
			search_text = text
			fill_results.call()
	)
	fill_results.call()


func build_listing_card(listing: Dictionary) -> PanelContainer:
	var item_id := str(listing.get("item_id", ""))
	var quantity := int(listing.get("quantity", 1))
	var price := int(listing.get("price", 0))

	var card := UiStyle.make_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	box.add_child(make_row("%s  ×%d" % [item_name(item_id), quantity], "💰 %d" % price))

	var unit := "%s or / u" % GameText.format_number(float(price) / max(quantity, 1)) if quantity > 1 else ""
	var origin := "Vendu par %s · %s" % [listing.get("seller_name", listing.get("seller_player_id", "?")), listing.get("market_name", "un autel")]
	box.add_child(make_label(origin + ("  ·  " + unit if not unit.is_empty() else ""), 12, COLOR_MUTED))

	var buy_button := make_action_button("Acheter · %d or" % price)
	buy_button.disabled = price > gold() or is_submitting
	box.add_child(buy_button)

	buy_button.pressed.connect(
		func():
			run_action(
				"market_buy",
				{"listing_id": listing.get("listing_id", "")},
				"✅ Acheté : %d × %s (−%d or)" % [quantity, item_name(item_id), price]
			)
	)

	return card


# --- Vendre -------------------------------------------------------------------

func render_sell(id: int) -> void:
	var res := await ApiClient.get_json("/shops/sell_prices?player_id=" + GameState.player_id.uri_encode())
	await load_items(inventory().keys())

	if id != render_id:
		return

	if res.ok:
		sell_prices = res.data.get("prices", {})

	clear_content()

	if not selected_item_id.is_empty() and inventory().has(selected_item_id):
		build_sell_form(selected_item_id)
		return

	selected_item_id = ""

	if inventory().is_empty():
		add_content_label("Ton sac est vide.", 13, COLOR_MUTED)
		return

	add_content_label("Choisis un objet à mettre en vente. Il quitte ton sac jusqu'à la vente ou au retrait de l'annonce.", 12, COLOR_MUTED)

	for item_id in sorted_inventory_ids():
		var button := UiStyle.make_card_button(48)
		button.text = "  %s  ×%d" % [item_name(item_id), int(inventory()[item_id])]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(
			func():
				selected_item_id = item_id
				refresh()
		)
		content.add_child(button)


func build_sell_form(item_id: String) -> void:
	var owned := int(inventory().get(item_id, 0))
	var reference := int(items.get(item_id, {}).get("base_value", 0))
	var shop_price := int(sell_prices.get(item_id, 0))

	var back := Button.new()
	back.text = "← Choisir un autre objet"
	back.flat = true
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.pressed.connect(
		func():
			selected_item_id = ""
			refresh()
	)
	content.add_child(back)

	var box := make_card_box()
	box.add_child(make_label(item_name(item_id), 18))
	box.add_child(make_label("Tu en as %d · valeur de référence %d or / u · rachat en boutique %d or / u" % [owned, reference, shop_price], 12, COLOR_MUTED))

	var quantity_row := HBoxContainer.new()
	var quantity_label := make_label("Quantité", 14)
	quantity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quantity_row.add_child(quantity_label)
	box.add_child(quantity_row)

	var price_row := HBoxContainer.new()
	var price_label := make_label("Prix du lot (or)", 14)
	price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_row.add_child(price_label)

	var price_input := SpinBox.new()
	price_input.min_value = 0
	price_input.max_value = 999999
	price_input.step = 1
	price_input.custom_minimum_size = Vector2(120, 40)
	price_row.add_child(price_input)
	box.add_child(price_row)

	var list_button := make_action_button("")
	box.add_child(list_button)

	var state := {"value": 1}
	var price_edited := {"value": false}

	var update := func():
		# Tant que le joueur n'a pas saisi de prix, on propose la valeur de
		# référence du lot.
		if not price_edited.value:
			price_input.set_value_no_signal(max(reference, 1) * state.value)
		list_button.text = "Mettre en vente · %d or" % int(price_input.value)
		list_button.disabled = is_submitting

	quantity_row.add_child(make_stepper(state, 1, owned, update))

	price_input.value_changed.connect(
		func(_value: float):
			price_edited.value = true
			update.call()
	)
	update.call()

	list_button.pressed.connect(
		func():
			var quantity: int = state.value
			var price := int(price_input.value)
			if await run_action(
				"market_list_item",
				{"zone_id": zone_id, "entry_id": entry.get("id", ""), "item_id": item_id, "quantity": quantity, "price": price},
				"✅ Mis en vente : %d × %s pour %d or" % [quantity, item_name(item_id), price]
			):
				selected_item_id = ""
				refresh()
	)


# --- Mes annonces ---------------------------------------------------------------

func render_mine(id: int) -> void:
	if not await load_listings():
		clear_content()
		add_content_label("Impossible de charger les annonces.", 13, COLOR_ERROR)
		return

	var mine: Array = listings.filter(is_mine)
	var sales: Array = GameState.player.get("market_sales", [])
	var item_ids: Array = []

	for listing in mine:
		item_ids.append(str(listing.get("item_id", "")))

	for sale in sales:
		item_ids.append(str(sale.get("item_id", "")))

	await load_items(item_ids)

	if id != render_id:
		return

	clear_content()
	add_content_label("📦 En vente  (%d)" % mine.size(), 17)

	if mine.is_empty():
		add_content_label("Tu n'as aucune annonce en cours.", 13, COLOR_MUTED)

	for listing in mine:
		var item_id := str(listing.get("item_id", ""))
		var quantity := int(listing.get("quantity", 1))
		var box := make_card_box()
		box.add_child(make_row("%s  ×%d" % [item_name(item_id), quantity], "💰 %d" % int(listing.get("price", 0))))
		box.add_child(make_label("Déposé %s · %s" % [time_ago(str(listing.get("listed_at", ""))), listing.get("market_name", "")], 12, COLOR_MUTED))

		var cancel := make_action_button("Retirer l'annonce")
		cancel.disabled = is_submitting
		cancel.pressed.connect(
			func():
				run_action(
					"market_cancel_listing",
					{"listing_id": listing.get("listing_id", "")},
					"Annonce retirée : %d × %s revient dans ton sac." % [quantity, item_name(item_id)]
				)
		)
		box.add_child(cancel)

	add_content_label("💰 Ventes récentes", 17)

	if sales.is_empty():
		add_content_label("Aucune vente pour l'instant.", 13, COLOR_MUTED)

	for sale in sales:
		var box := make_card_box()
		box.add_child(make_row(
			"%s  ×%d" % [item_name(str(sale.get("item_id", ""))), int(sale.get("quantity", 1))],
			"+%d or" % int(sale.get("price", 0)),
			COLOR_BONUS
		))
		box.add_child(make_label("Vendu " + time_ago(str(sale.get("sold_at", ""))), 12, COLOR_MUTED))


# « il y a 5 min » à partir d'une date ISO 8601 en UTC.
func time_ago(iso_date: String) -> String:
	if iso_date.length() < 19:
		return ""

	var then := Time.get_unix_time_from_datetime_string(iso_date.substr(0, 19))
	var seconds := int(Time.get_unix_time_from_system() - then)

	if seconds < 60:
		return "à l'instant"
	if seconds < 3600:
		return "il y a %d min" % (seconds / 60)
	if seconds < 86400:
		return "il y a %d h" % (seconds / 3600)

	return "il y a %d j" % (seconds / 86400)
