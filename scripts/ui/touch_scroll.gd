extends ScrollContainer

# Liste qui défile en glissant le doigt (ou la souris) n'importe où dessus,
# cartes et boutons compris, avec un peu d'inertie au lâcher.
#
# Le défilement tactile intégré de Godot est neutralisé : il ne marche qu'en
# tactile réel, s'arrête sur les cartes (qui gardent le doigt pour elles) et
# laisse passer le clic de la carte relâchée après un glissement. Ici, les
# cartes laissent passer les glissements jusqu'à la liste, et le bouton appuyé
# est annulé dès que le doigt a glissé.

const DRAG_THRESHOLD := 10.0
# Décroissance de l'inertie (par seconde) et vitesse sous laquelle elle s'arrête.
const FRICTION := 5.0
const MIN_SPEED := 30.0
const MAX_SPEED := 2500.0

var pressing := false
var dragging := false
var press_y := 0.0
var press_scroll := 0
var velocity := 0.0
var last_motion_ms := 0
var last_y := 0.0
# Fraction de pixel restante de l'inertie, pour ne pas caler à faible vitesse.
var fling_remainder := 0.0
# Bouton sous le doigt au moment de l'appui, annulé si l'on glisse.
var pressed_button: BaseButton = null


func _ready() -> void:
	scroll_deadzone = 100000
	get_tree().node_added.connect(_on_node_added)

	for node in find_children("*", "Control", true, false):
		prepare(node)


func _on_node_added(node: Node) -> void:
	if node is Control and is_ancestor_of(node):
		prepare(node)


# Les éléments d'une liste laissent passer les glissements jusqu'à elle (ils
# restent cliquables). Les champs de saisie et les curseurs gardent les leurs.
func prepare(node: Control) -> void:
	if node is ScrollBar or node is LineEdit or node is TextEdit or node is Range:
		return

	if node.mouse_filter == Control.MOUSE_FILTER_STOP:
		node.mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressing = true
		dragging = false
		velocity = 0.0
		press_y = event.global_position.y
		press_scroll = scroll_vertical
		last_y = press_y
		last_motion_ms = Time.get_ticks_msec()
		pressed_button = button_under(get_viewport().gui_get_hovered_control())


# Le glissement et le lâcher sont suivis au niveau global : le doigt peut sortir
# de la liste, et la carte appuyée peut être reconstruite pendant le geste.
func _input(event: InputEvent) -> void:
	if not pressing:
		return

	if event is InputEventMouseMotion:
		var offset: float = event.global_position.y - press_y

		if not dragging and absf(offset) > DRAG_THRESHOLD:
			dragging = true
			cancel_pressed_button()

		if dragging:
			# Vitesse du doigt, lissée et plafonnée, pour l'inertie au lâcher.
			var now := Time.get_ticks_msec()
			var elapsed := maxf((now - last_motion_ms) / 1000.0, 0.016)
			var speed: float = (last_y - event.global_position.y) / elapsed
			velocity = clampf(lerpf(velocity, speed, 0.5), -MAX_SPEED, MAX_SPEED)
			last_motion_ms = now
			last_y = event.global_position.y
			scroll_vertical = press_scroll - int(offset)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		pressing = false

		# Pas d'élan si le doigt s'était arrêté avant d'être levé.
		if not dragging or Time.get_ticks_msec() - last_motion_ms > 100:
			velocity = 0.0

		dragging = false
		# Le bouton annulé redevient actif une fois ce lâcher traité.
		restore_pressed_button.call_deferred()


func _process(delta: float) -> void:
	if pressing or velocity == 0.0:
		return

	if absf(velocity) < MIN_SPEED:
		velocity = 0.0
		fling_remainder = 0.0
		return

	fling_remainder += velocity * delta
	var step := int(fling_remainder)
	fling_remainder -= step
	scroll_vertical += step
	velocity *= exp(-FRICTION * delta)


func button_under(control: Control) -> BaseButton:
	while control != null and control != self:
		if control is BaseButton:
			return control

		control = control.get_parent() as Control

	return null


# Désactiver le bouton efface son appui en cours : le lâcher ne le déclenchera pas.
func cancel_pressed_button() -> void:
	if is_instance_valid(pressed_button) and not pressed_button.disabled:
		pressed_button.disabled = true
		pressed_button.set_meta("scroll_cancelled", true)
	else:
		pressed_button = null


func restore_pressed_button() -> void:
	if is_instance_valid(pressed_button) and pressed_button.has_meta("scroll_cancelled"):
		pressed_button.remove_meta("scroll_cancelled")
		pressed_button.disabled = false

	pressed_button = null
