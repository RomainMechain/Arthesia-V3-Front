extends Node

# Connexion du joueur à Firebase Authentication (e-mail et mot de passe), via
# l'API REST de Firebase : pas de plugin natif.
#
# Le jeton d'identité (1 h) accompagne chaque requête au serveur de jeu, qui
# en déduit l'uid du joueur. Le jeton de rafraîchissement est enregistré sur
# l'appareil (AUTH_FILE) pour rester connecté entre deux lancements.
#
# Au démarrage : session restaurée -> signed_in, sinon -> needs_login.
# En développement, --email=... --password=... connecte automatiquement.

signal signed_in
signal needs_login
signal signed_out

const CONFIG_FILE := "res://config/firebase.cfg"
const AUTH_FILE := "user://auth.cfg"
const IDENTITY_URL := "https://identitytoolkit.googleapis.com/v1/accounts:%s?key=%s"
const TOKEN_URL := "https://securetoken.googleapis.com/v1/token?key=%s"

# Le jeton est renouvelé un peu avant son expiration.
const REFRESH_MARGIN_SECONDS := 120
# Délai d'une requête à Firebase avant d'abandonner.
const REQUEST_TIMEOUT_SECONDS := 20.0

const ERROR_MESSAGES := {
	"EMAIL_EXISTS": "Un compte existe déjà avec cet e-mail.",
	"INVALID_EMAIL": "Adresse e-mail invalide.",
	"WEAK_PASSWORD": "Mot de passe trop faible : 6 caractères minimum.",
	"MISSING_PASSWORD": "Saisis un mot de passe.",
	"INVALID_LOGIN_CREDENTIALS": "E-mail ou mot de passe incorrect.",
	"EMAIL_NOT_FOUND": "E-mail ou mot de passe incorrect.",
	"INVALID_PASSWORD": "E-mail ou mot de passe incorrect.",
	"USER_DISABLED": "Ce compte a été désactivé.",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "Trop de tentatives : réessaie dans quelques minutes.",
	"OPERATION_NOT_ALLOWED": "La connexion par e-mail n'est pas activée sur le projet Firebase.",
	"TOKEN_EXPIRED": "Session expirée : reconnecte-toi.",
	"INVALID_REFRESH_TOKEN": "Session expirée : reconnecte-toi.",
}

var api_key := ""
var uid := ""
var email := ""
var id_token := ""
var refresh_token := ""
# Expiration du jeton d'identité (secondes Unix).
var expires_at := 0.0
var is_refreshing := false
# Vrai tant que la session enregistrée n'a pas été restaurée au démarrage.
var is_restoring := true

signal _refresh_finished


func _ready() -> void:
	var config := ConfigFile.new()

	if config.load(CONFIG_FILE) == OK:
		api_key = str(config.get_value("firebase", "api_key", ""))

	# Attendre une image : les écrans doivent pouvoir écouter les signaux.
	await get_tree().process_frame
	await restore_session()
	is_restoring = false


func is_configured() -> bool:
	return not api_key.is_empty()


func is_signed_in() -> bool:
	return not uid.is_empty() and not refresh_token.is_empty()


func restore_session() -> void:
	var dev_email := ""
	var dev_password := ""

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--email="):
			dev_email = arg.trim_prefix("--email=")
		elif arg.begins_with("--password="):
			dev_password = arg.trim_prefix("--password=")

	if not dev_email.is_empty():
		var res := await sign_in(dev_email, dev_password)

		if not res.ok:
			push_warning("Connexion de développement impossible : " + res.error)
			needs_login.emit()
		return

	var saved := ConfigFile.new()

	if saved.load(AUTH_FILE) == OK:
		refresh_token = str(saved.get_value("auth", "refresh_token", ""))
		uid = str(saved.get_value("auth", "uid", ""))
		email = str(saved.get_value("auth", "email", ""))

	if not is_signed_in() or not is_configured():
		needs_login.emit()
		return

	var res := await refresh()

	if res.ok:
		signed_in.emit()
	else:
		sign_out(false)
		needs_login.emit()


# --- Connexion -----------------------------------------------------------------

func sign_up(new_email: String, password: String) -> Dictionary:
	return await _identity_request("signUp", {"email": new_email, "password": password, "returnSecureToken": true})


func sign_in(existing_email: String, password: String) -> Dictionary:
	return await _identity_request("signInWithPassword", {"email": existing_email, "password": password, "returnSecureToken": true})


func send_password_reset(target_email: String) -> Dictionary:
	if not is_configured():
		return _failure("Clé Firebase manquante : renseigne config/firebase.cfg.")

	return await _post_json(IDENTITY_URL % ["sendOobCode", api_key], {"requestType": "PASSWORD_RESET", "email": target_email})


func sign_out(emit := true) -> void:
	uid = ""
	email = ""
	id_token = ""
	refresh_token = ""
	expires_at = 0.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AUTH_FILE))

	if emit:
		signed_out.emit()


func _identity_request(endpoint: String, body: Dictionary) -> Dictionary:
	if not is_configured():
		return _failure("Clé Firebase manquante : renseigne config/firebase.cfg.")

	var res := await _post_json(IDENTITY_URL % [endpoint, api_key], body)

	if not res.ok:
		return res

	uid = str(res.data.get("localId", ""))
	email = str(res.data.get("email", body.get("email", "")))
	id_token = str(res.data.get("idToken", ""))
	refresh_token = str(res.data.get("refreshToken", ""))
	expires_at = Time.get_unix_time_from_system() + float(res.data.get("expiresIn", 3600))
	_save()
	signed_in.emit()
	return res


# --- Jeton d'identité ----------------------------------------------------------

# Jeton valide pour le serveur de jeu, renouvelé s'il expire bientôt. Renvoie
# "" si la session est perdue.
func get_id_token() -> String:
	if not is_signed_in():
		return ""

	if Time.get_unix_time_from_system() < expires_at - REFRESH_MARGIN_SECONDS and not id_token.is_empty():
		return id_token

	# Plusieurs requêtes simultanées partagent le même renouvellement.
	if is_refreshing:
		await _refresh_finished
		return id_token

	var res := await refresh()
	return id_token if res.ok else ""


func refresh() -> Dictionary:
	is_refreshing = true
	var res := await _post_form(TOKEN_URL % api_key, "grant_type=refresh_token&refresh_token=" + refresh_token.uri_encode())
	is_refreshing = false

	if res.ok:
		id_token = str(res.data.get("id_token", ""))
		refresh_token = str(res.data.get("refresh_token", refresh_token))
		uid = str(res.data.get("user_id", uid))
		expires_at = Time.get_unix_time_from_system() + float(res.data.get("expires_in", 3600))
		_save()

	_refresh_finished.emit()
	return res


func _save() -> void:
	var saved := ConfigFile.new()
	saved.set_value("auth", "uid", uid)
	saved.set_value("auth", "email", email)
	saved.set_value("auth", "refresh_token", refresh_token)
	saved.save(AUTH_FILE)


# --- HTTP --------------------------------------------------------------------------

func _post_json(url: String, body: Dictionary) -> Dictionary:
	return await _post(url, PackedStringArray(["Content-Type: application/json"]), JSON.stringify(body))


func _post_form(url: String, body: String) -> Dictionary:
	return await _post(url, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), body)


func _post(url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	# Sans délai, une requête sans réponse bloquerait le démarrage pour toujours.
	http.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(http)

	# Godot se connecte à la première adresse du nom, souvent IPv6. Sur un
	# réseau où IPv6 est annoncé mais ne passe pas, la requête n'aboutit jamais.
	# On s'adresse donc à l'adresse IPv4 de Firebase, en gardant le nom pour
	# l'en-tête Host et pour le TLS (SNI et vérification du certificat).
	var host := url.get_slice("://", 1).get_slice("/", 0)
	var ipv4 := IP.resolve_hostname(host, IP.TYPE_IPV4)

	if not ipv4.is_empty():
		headers.append("Host: " + host)
		http.set_tls_options(TLSOptions.client(null, host))
		url = url.replace("://" + host, "://" + ipv4)

	if http.request(url, headers, HTTPClient.METHOD_POST, body) != OK:
		http.queue_free()
		return _failure("Impossible de joindre Firebase.")

	var response: Array = await http.request_completed
	http.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return _failure("Impossible de joindre Firebase : vérifie ta connexion.")

	var data = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())

	if int(response[1]) >= 200 and int(response[1]) < 300 and typeof(data) == TYPE_DICTIONARY:
		return {"ok": true, "data": data, "error": ""}

	var code := ""

	if typeof(data) == TYPE_DICTIONARY:
		var error = data.get("error", {})
		code = str(error.get("message", "")) if typeof(error) == TYPE_DICTIONARY else str(error)

	# Firebase ajoute parfois un détail après le code : "WEAK_PASSWORD : ...".
	var key := code.split(" ")[0] if not code.is_empty() else ""

	if code.begins_with("API key not valid"):
		return _failure("Clé Firebase invalide : vérifie config/firebase.cfg.")

	return _failure(ERROR_MESSAGES.get(key, "Erreur de connexion (%s)" % code))


func _failure(message: String) -> Dictionary:
	return {"ok": false, "data": null, "error": message}
