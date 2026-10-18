extends Control

# Écran de connexion, affiché par la carte tant qu'aucune session n'est prête.
#
# Trois modes :
# * connexion : e-mail et mot de passe (+ mot de passe oublié) ;
# * inscription : pseudo, e-mail et mot de passe ;
# * personnage : le compte existe sans personnage (pseudo déjà pris à
#   l'inscription, inscription interrompue) : on ne demande que le pseudo.
#
# Le formulaire est construit en code dans Form.

signal closed

const COLOR_MUTED := UiStyle.COLOR_MUTED
const COLOR_BONUS := UiStyle.COLOR_BONUS
const COLOR_ERROR := UiStyle.COLOR_ERROR

@onready var card: PanelContainer = $Center/Box/Card
@onready var form: VBoxContainer = $Center/Box/Card/Form

var mode := "sign_in"
var is_busy := false
var message := ""
var message_color := COLOR_ERROR

var pseudo_input: LineEdit
var email_input: LineEdit
var password_input: LineEdit
var submit_button: Button


func _ready() -> void:
	card.add_theme_stylebox_override("panel", UiStyle.card_style(Color(0.12, 0.13, 0.16)))

	GameState.character_needed.connect(_on_character_needed)
	GameState.session_failed.connect(_on_session_failed)
	GameState.session_ready.connect(func(): closed.emit())

	render()


func show_mode(new_mode: String, text := "", color := COLOR_ERROR) -> void:
	mode = new_mode
	message = text
	message_color = color
	is_busy = false
	render()


func _on_character_needed(error: String) -> void:
	show_mode("character", error)


func _on_session_failed(error: String) -> void:
	show_mode("sign_in", "Connexion au serveur de jeu impossible : " + error)


# --- Formulaire -------------------------------------------------------------------

func make_label(text: String, font_size := 0, color = null) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)

	if color != null:
		label.add_theme_color_override("font_color", color)

	return label


func make_input(placeholder: String, text := "", secret := false) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.text = text
	input.secret = secret
	input.custom_minimum_size = Vector2(0, 44)
	input.editable = not is_busy
	input.text_submitted.connect(func(_text): submit())
	form.add_child(input)
	return input


func render() -> void:
	# Les champs déjà saisis sont conservés d'un mode à l'autre.
	var previous_pseudo := pseudo_input.text if pseudo_input != null else ""
	var previous_email := email_input.text if email_input != null else Auth.email
	pseudo_input = null
	email_input = null
	password_input = null

	for child in form.get_children():
		child.queue_free()

	if not Auth.is_configured():
		form.add_child(make_label("Clé Firebase manquante : renseigne api_key dans config/firebase.cfg.", 14, COLOR_ERROR))
		return

	if mode == "character":
		render_character_form(previous_pseudo)
	else:
		render_account_form(previous_pseudo, previous_email)

	if not message.is_empty():
		form.add_child(make_label(message, 13, message_color))


func render_account_form(previous_pseudo: String, previous_email: String) -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)

	for tab in [["sign_in", "Connexion"], ["sign_up", "Inscription"]]:
		var button := Button.new()
		button.text = tab[1]
		button.toggle_mode = true
		button.button_pressed = mode == tab[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 40)
		button.disabled = is_busy
		button.pressed.connect(func(): show_mode(tab[0]))
		tabs.add_child(button)

	form.add_child(tabs)

	if mode == "sign_up":
		pseudo_input = make_input("Pseudo", previous_pseudo)
		form.add_child(make_label("Visible par les autres joueurs · 3 à 20 caractères", 11, COLOR_MUTED))

	email_input = make_input("E-mail", previous_email)
	email_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	password_input = make_input("Mot de passe (6 caractères min.)", "", true)
	password_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD

	submit_button = Button.new()
	submit_button.custom_minimum_size = Vector2(0, 50)
	submit_button.add_theme_font_size_override("font_size", 17)
	submit_button.disabled = is_busy

	if is_busy:
		submit_button.text = "Un instant..."
	else:
		submit_button.text = "Se connecter" if mode == "sign_in" else "Créer mon compte"

	submit_button.pressed.connect(submit)
	form.add_child(submit_button)

	if mode == "sign_in":
		var forgot := Button.new()
		forgot.text = "Mot de passe oublié ?"
		forgot.flat = true
		forgot.disabled = is_busy
		forgot.add_theme_color_override("font_color", COLOR_MUTED)
		forgot.pressed.connect(reset_password)
		form.add_child(forgot)


func render_character_form(previous_pseudo: String) -> void:
	form.add_child(make_label("Choisis ton pseudo", 18))
	form.add_child(make_label("Ton compte (%s) n'a pas encore de personnage. Ton pseudo sera visible par les autres joueurs." % Auth.email, 13, COLOR_MUTED))
	pseudo_input = make_input("Pseudo", previous_pseudo)

	submit_button = Button.new()
	submit_button.custom_minimum_size = Vector2(0, 50)
	submit_button.add_theme_font_size_override("font_size", 17)
	submit_button.text = "Un instant..." if is_busy else "Créer mon personnage"
	submit_button.disabled = is_busy
	submit_button.pressed.connect(submit)
	form.add_child(submit_button)

	var other := Button.new()
	other.text = "Utiliser un autre compte"
	other.flat = true
	other.disabled = is_busy
	other.add_theme_color_override("font_color", COLOR_MUTED)
	other.pressed.connect(
		func():
			Auth.sign_out(false)
			show_mode("sign_in")
	)
	form.add_child(other)


# --- Actions ----------------------------------------------------------------------

# Mêmes règles que le serveur : 3 à 20 caractères.
func validate_pseudo(pseudo: String) -> String:
	if pseudo.length() < 3 or pseudo.length() > 20:
		return "Ton pseudo doit faire entre 3 et 20 caractères."

	return ""


func submit() -> void:
	if is_busy:
		return

	var pseudo := pseudo_input.text.strip_edges() if pseudo_input != null else ""

	if pseudo_input != null:
		var error := validate_pseudo(pseudo)

		if not error.is_empty():
			show_mode(mode, error)
			return

	# Lire les champs avant render(), qui recrée le formulaire (le mot de passe
	# n'est pas conservé d'un rendu à l'autre).
	var entered_email := email_input.text.strip_edges() if email_input != null else ""
	var password := password_input.text if password_input != null else ""

	var previous_mode := mode
	is_busy = true
	message = ""
	render()

	if previous_mode == "character":
		GameState.pending_display_name = pseudo
		GameState.start_session()
		return

	var res: Dictionary

	if previous_mode == "sign_up":
		# Le personnage est créé avec ce pseudo dès que la session démarre.
		GameState.pending_display_name = pseudo
		res = await Auth.sign_up(entered_email, password)
	else:
		res = await Auth.sign_in(entered_email, password)

	# En cas de succès, Auth.signed_in lance la session : l'écran se ferme sur
	# session_ready, ou passe en mode personnage sur character_needed.
	if not res.ok:
		show_mode(previous_mode, res.error)


func reset_password() -> void:
	var entered_email := email_input.text.strip_edges()

	if entered_email.is_empty():
		show_mode("sign_in", "Saisis ton e-mail pour recevoir le lien de réinitialisation.")
		return

	is_busy = true
	render()
	var res := await Auth.send_password_reset(entered_email)

	if res.ok:
		show_mode("sign_in", "Un e-mail de réinitialisation a été envoyé à %s." % entered_email, COLOR_BONUS)
	else:
		show_mode("sign_in", res.error)
