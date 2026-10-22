extends "res://scripts/commerce/commerce_panel.gd"

# Boutique d'un PNJ : acheter ses offres, lui revendre les objets du sac au
# prix de rachat global (calculé par le serveur).

const MAX_QUANTITY := 99

# Prix de rachat unitaire des objets du sac (GET /shops/sell_prices).
var sell_prices: Dictionary = {}


func _init() -> void:
	tabs = [["buy", "Acheter"], ["sell", "Vendre"]]


func subtitle() -> String:
	return "🛒 Boutique · rachète aussi tous tes objets"


func render_tab(tab: String, id: int) -> void:
	match tab:
		"buy":
			await render_buy(id)
		"sell":
			await render_sell(id)


# --- Acheter ------------------------------------------------------------------

func render_buy(id: int) -> void:
	var offers: Array = template.get("sell_offers", [])
	var item_ids: Array = []

	for offer in offers:
		item_ids.append(str(offer.get("item_id", "")))

	await load_items(item_ids)

	if id != render_id:
		return

	clear_content()

	if offers.is_empty():
		add_content_label("Cette boutique n'a rien à vendre pour l'instant.", 13, COLOR_MUTED)
		return

	for offer in offers:
		build_offer_card(offer)


func build_offer_card(offer: Dictionary) -> void:
	var item_id := str(offer.get("item_id", ""))
	var price := int(offer.get("price", 0))
	var owned := int(inventory().get(item_id, 0))

	var box := make_card_box()
	box.add_child(make_row(item_name(item_id), "💰 %d" % price, COLOR_HIGHLIGHT, item_color(item_id)))

	var detail = items.get(item_id, {}).get("description", "")

	if not str(detail).is_empty():
		box.add_child(make_label(str(detail), 12, COLOR_MUTED))

	if owned > 0:
		box.add_child(make_label("Tu en as %d" % owned, 12, COLOR_MUTED))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var state := {"value": 1}
	var buy_button := make_action_button("")

	var update := func():
		var total: int = price * state.value
		buy_button.text = "Acheter · %d or" % total
		buy_button.disabled = total > gold() or is_submitting

	row.add_child(make_stepper(state, 1, MAX_QUANTITY, update))
	row.add_child(buy_button)
	box.add_child(row)
	update.call()

	buy_button.pressed.connect(
		func():
			var quantity: int = state.value
			run_action(
				"shop_buy",
				{"zone_id": zone_id, "entry_id": entry.get("id", ""), "item_id": item_id, "quantity": quantity},
				"✅ Acheté : %d × %s (−%d or)" % [quantity, item_name(item_id), price * quantity]
			)
	)


# --- Vendre -------------------------------------------------------------------

func render_sell(id: int) -> void:
	var res := await ApiClient.get_json("/shops/sell_prices?player_id=" + GameState.player_id.uri_encode())
	await load_items(inventory().keys())

	if id != render_id:
		return

	clear_content()

	if not res.ok:
		add_content_label("Impossible de connaître les prix de rachat : " + res.error, 13, COLOR_ERROR)
		return

	sell_prices = res.data.get("prices", {})

	if inventory().is_empty():
		add_content_label("Ton sac est vide.", 13, COLOR_MUTED)
		return

	add_content_label("Le marchand rachète tout, à un prix inférieur à la valeur des objets.", 12, COLOR_MUTED)

	var browser = ITEM_BROWSER.new()
	content.add_child(browser)
	browser.setup("boutique_vente", sorted_inventory_ids().filter(func(item_id): return sell_prices.has(item_id)), items,
		func(item_id):
			var holder := VBoxContainer.new()
			build_sell_card(item_id, holder)
			return holder
	)


func build_sell_card(item_id: String, parent: Node = null) -> void:
	var owned := int(inventory().get(item_id, 0))
	var unit_price := int(sell_prices.get(item_id, 0))

	var box := make_card_box(parent)
	box.add_child(make_row("%s  ×%d" % [item_name(item_id), owned], "%d or / u" % unit_price, COLOR_MUTED, item_color(item_id)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var state := {"value": 1}
	var sell_button := make_action_button("")

	var update := func():
		sell_button.text = "Vendre · %d or" % (unit_price * state.value)
		sell_button.disabled = unit_price <= 0 or is_submitting

	row.add_child(make_stepper(state, 1, owned, update))
	row.add_child(sell_button)
	box.add_child(row)
	update.call()

	if unit_price <= 0:
		box.add_child(make_label("Sans valeur pour le marchand.", 12, COLOR_MUTED))

	sell_button.pressed.connect(
		func():
			var quantity: int = state.value
			run_action(
				"shop_sell",
				{"zone_id": zone_id, "entry_id": entry.get("id", ""), "item_id": item_id, "quantity": quantity},
				"✅ Vendu : %d × %s (+%d or)" % [quantity, item_name(item_id), unit_price * quantity]
			)
	)
