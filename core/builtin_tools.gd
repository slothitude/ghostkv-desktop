extends Node

## Built-in tools that bridge to Android plugin (mobile) or OS APIs (desktop).
## Registered with ToolDispatch so the ReAct loop can call them via Action: syntax.

var _plugin: RefCounted = null  # GhostKVPlugin singleton on Android
var _confirm_dialog: Node = null  # Confirmation dialog overlay
var _trusted_contacts: Dictionary = {}  # phone -> {"name": "...", "trust": "full"|"temp"}
var _telegram_http: HTTPRequest  # For Telegram Bot API calls

func _ready() -> void:
	# On Android, the plugin is registered as a singleton by Godot's plugin loader
	if OS.has_feature("android"):
		_plugin = Engine.get_singleton("GhostKVPlugin")
		if _plugin:
			print("BuiltinTools: plugin loaded OK")
		else:
			push_error("BuiltinTools: FAILED to load GhostKVPlugin singleton")
	# HTTPRequest node for Telegram Bot API
	_telegram_http = HTTPRequest.new()
	add_child(_telegram_http)
	_register_tools()
	_load_trusted_contacts()

func set_confirm_dialog(dialog: Node) -> void:
	_confirm_dialog = dialog

func _load_trusted_contacts() -> void:
	var session := Engine.get_singleton("SessionManager") as Node
	if not session:
		return
	var settings: Dictionary = session.load_settings()
	var contacts: Dictionary = settings.get("trusted_contacts", {})
	_trusted_contacts = contacts

func _save_trusted_contacts() -> void:
	var session := Engine.get_singleton("SessionManager") as Node
	if not session:
		return
	var settings: Dictionary = session.load_settings()
	settings["trusted_contacts"] = _trusted_contacts
	session.save_settings(settings)

func add_trusted_contact(phone: String, name: String, trust: String) -> void:
	# Normalize phone: strip spaces/dashes
	var clean := phone.replace(" ", "").replace("-", "")
	_trusted_contacts[clean] = {"name": name, "trust": trust}
	_save_trusted_contacts()

func get_trust_level(phone: String) -> Dictionary:
	var clean := phone.replace(" ", "").replace("-", "")
	if _trusted_contacts.has(clean):
		return _trusted_contacts[clean]
	return {"name": "", "trust": "unknown"}

func _lookup_contact_name(phone: String) -> String:
	var trust := get_trust_level(phone)
	if trust.get("name", "") != "":
		return trust["name"]
	# Try to find via contacts tool
	if _plugin and _plugin.has_method("getContacts"):
		var result: String = _plugin.getContacts(phone)
		if result != "[]" and result != "":
			var json := JSON.new()
			if json.parse(result) == OK and json.data is Array and json.data.size() > 0:
				var first: Dictionary = json.data[0]
				return first.get("name", "")
	return ""

## Check if a phone number is trusted (full trust = auto-send, temp/unknown = confirm)
func _is_full_trusted(phone: String) -> bool:
	var trust := get_trust_level(phone)
	return trust.get("trust", "") == "full"

## Show confirmation dialog and await user response. Returns true if confirmed.
func _await_confirmation(action: String, phone: String, message: String = "") -> bool:
	if not _confirm_dialog:
		# No dialog available — block the action for safety
		return false
	var contact_name: String = _lookup_contact_name(phone)
	_confirm_dialog.show_confirm(action, phone, contact_name, message)
	var result: bool = await _confirm_dialog.confirmed
	return result

func _register_tools() -> void:
	var td := Engine.get_singleton("ToolDispatch") as Node
	if not td:
		return

	# Tools available on all platforms
	td.register_tool("open_url", "builtin", self)
	td.register_tool("run_command", "builtin", self)
	td.register_tool("file_read", "builtin", self)
	td.register_tool("calculator", "builtin", self)

	# Android-only tools (registered always, but return error on non-Android)
	td.register_tool("send_sms", "builtin", self)
	td.register_tool("open_camera", "builtin", self)
	td.register_tool("open_app", "builtin", self)
	td.register_tool("list_apps", "builtin", self)
	td.register_tool("run_python", "builtin", self)
	td.register_tool("toast", "builtin", self)
	td.register_tool("vibrate", "builtin", self)
	td.register_tool("get_contacts", "builtin", self)
	td.register_tool("get_location", "builtin", self)
	td.register_tool("read_sms", "builtin", self)
	td.register_tool("set_alarm", "builtin", self)
	td.register_tool("set_timer", "builtin", self)
	td.register_tool("speak", "builtin", self)
	td.register_tool("start_listening", "builtin", self)
	td.register_tool("make_call", "builtin", self)
	td.register_tool("get_call_log", "builtin", self)
	td.register_tool("answer_call", "builtin", self)
	td.register_tool("end_call", "builtin", self)
	td.register_tool("get_call_state", "builtin", self)
	td.register_tool("set_call_mute", "builtin", self)
	td.register_tool("set_call_speaker", "builtin", self)
	td.register_tool("start_call_monitor", "builtin", self)
	td.register_tool("stop_call_monitor", "builtin", self)
	td.register_tool("get_calendar_events", "builtin", self)
	td.register_tool("create_calendar_event", "builtin", self)
	td.register_tool("read_clipboard", "builtin", self)
	td.register_tool("write_clipboard", "builtin", self)
	td.register_tool("toggle_flashlight", "builtin", self)
	td.register_tool("get_notifications", "builtin", self)
	td.register_tool("add_trusted_contact", "builtin", self)
	td.register_tool("list_trusted_contacts", "builtin", self)
	td.register_tool("media_control", "builtin", self)
	td.register_tool("get_volume", "builtin", self)
	td.register_tool("set_volume", "builtin", self)
	td.register_tool("get_brightness", "builtin", self)
	td.register_tool("set_brightness", "builtin", self)
	td.register_tool("web_search", "builtin", self)
	td.register_tool("web_read", "builtin", self)
	td.register_tool("get_battery", "builtin", self)
	td.register_tool("get_wifi_info", "builtin", self)
	td.register_tool("wake_screen", "builtin", self)
	td.register_tool("set_screen_timeout", "builtin", self)
	td.register_tool("get_screen_timeout", "builtin", self)
	td.register_tool("share_text", "builtin", self)
	td.register_tool("write_file", "builtin", self)
	td.register_tool("list_directory", "builtin", self)
	td.register_tool("add_contact", "builtin", self)
	td.register_tool("get_bluetooth_devices", "builtin", self)
	td.register_tool("get_nfc_status", "builtin", self)
	td.register_tool("send_whatsapp", "builtin", self)
	td.register_tool("send_telegram", "builtin", self)

# ── Tool descriptions (used by ToolDispatch.build_tool_descriptions) ───────

func get_tool_description(tool_name: String) -> String:
	match tool_name:
		"open_url":
			return "Open a URL in the default browser. Args: \"url\""
		"run_command":
			return "Execute a shell command and return output. Args: \"command\""
		"file_read":
			return "Read a file's contents. Args: \"path\""
		"calculator":
			return "Evaluate a math expression. Args: \"expression\""
		"send_sms":
			return "Send an SMS message (Android only). Requires confirmation unless contact has full trust. Args: \"phone\", \"message\""
		"open_camera":
			return "Open the device camera (Android only). Args: none"
		"open_app":
			return "Open an installed app by package name (Android only). Args: \"package_name\""
		"list_apps":
			return "List all installed apps as JSON (Android only). Args: none"
		"run_python":
			return "Execute a Python script. Args: \"script_path\" or \"command\""
		"toast":
			return "Show a toast notification (Android only). Args: \"message\""
		"vibrate":
			return "Vibrate the device (Android only). Args: \"milliseconds\""
		"get_contacts":
			return "Search contacts by name. Returns JSON array of {name, phone}. Args: \"query\" (empty = all)"
		"get_location":
			return "Get the device GPS location. Returns JSON {lat, lon, accuracy}. Args: none"
		"read_sms":
			return "Read recent SMS messages from inbox. Returns JSON array of {sender, body, date}. Args: \"limit\" (default 20)"
		"set_alarm":
			return "Set an alarm. Args: \"hour\" (0-23), \"minutes\" (0-59), \"message\" (optional label)"
		"set_timer":
			return "Start a countdown timer. Args: \"seconds\", \"message\" (optional label)"
		"speak":
			return "Read text aloud using text-to-speech. Args: \"text\""
		"start_listening":
			return "Start speech recognition (voice input). Args: none"
		"make_call":
			return "Make a phone call (Android only). Requires confirmation unless contact has full trust. Args: \"phone\""
		"get_call_log":
			return "Read recent call history. Returns JSON array of {number, name, date, duration, type}. Args: \"limit\" (default 20)"
		"answer_call":
			return "Answer an incoming ringing call (Android 8+). Args: none"
		"end_call":
			return "End or reject the current call (Android 9+). Args: none"
		"get_call_state":
			return "Get current call state: idle, ringing, or offhook. Args: none"
		"set_call_mute":
			return "Mute or unmute the microphone during a call. Args: \"mute\" (\"true\" or \"false\")"
		"set_call_speaker":
			return "Switch call audio to speaker or earpiece. Args: \"on\" (\"true\" or \"false\")"
		"start_call_monitor":
			return "Start monitoring call state changes. Fires incoming_call, call_started, call_ended events. Args: none"
		"stop_call_monitor":
			return "Stop monitoring call state. Args: none"
		"get_calendar_events":
			return "Read calendar events. Returns JSON array of {title, start, end, location, description}. Args: \"limit\" (default 20)"
		"create_calendar_event":
			return "Create a calendar event. Args: \"title\", \"description\", \"start_ms\" (epoch ms), \"end_ms\" (epoch ms)"
		"read_clipboard":
			return "Read text from clipboard. Args: none"
		"write_clipboard":
			return "Write text to clipboard. Args: \"text\""
		"toggle_flashlight":
			return "Toggle flashlight on/off. Args: \"on\" (\"true\" or \"false\")"
		"get_notifications":
			return "Read active notifications. Returns JSON array of {app, title, text}. Requires notification access permission."
		"add_trusted_contact":
			return "Add a contact to the trusted list so SMS/calls to them skip confirmation. Args: \"phone\", \"name\", \"trust\" (\"full\" or \"temp\")"
		"list_trusted_contacts":
			return "List all trusted contacts and their trust levels (full=temp=needs confirm, full=auto-send)"
		"media_control":
			return "Control media playback. Args: \"action\" (\"play\", \"pause\", \"next\", \"previous\")"
		"get_volume":
			return "Get current volume level. Args: \"stream\" (\"music\", \"ring\", \"alarm\", \"notification\", \"system\", \"voice_call\")"
		"set_volume":
			return "Set volume level. Args: \"stream\", \"volume\" (integer)"
		"get_brightness":
			return "Get screen brightness (0-255)"
		"set_brightness":
			return "Set screen brightness. Args: \"brightness\" (0-255)"
		"web_search":
			return "Search the web using SearXNG. Args: \"query\""
		"web_read":
			return "Read a web page and return its text content. Args: \"url\""
		"get_battery":
			return "Get battery status: level, charging state, health, power source"
		"get_wifi_info":
			return "Get WiFi info: SSID, IP, signal strength"
		"wake_screen":
			return "Wake up the screen if it's off"
		"set_screen_timeout":
			return "Set screen timeout. Args: \"seconds\" (0 = never)"
		"get_screen_timeout":
			return "Get current screen timeout in seconds"
		"share_text":
			return "Share text via Android share sheet. Args: \"text\""
		"write_file":
			return "Save text content to a file in Downloads. Args: \"filename\", \"content\""
		"list_directory":
			return "List files in a directory. Args: \"path\" (e.g. \"downloads\", \"dcim\", \"documents\", or full path)"
		"add_contact":
			return "Add a new contact. Args: \"name\", \"phone\""
		"get_bluetooth_devices":
			return "List paired Bluetooth devices"
		"get_nfc_status":
			return "Check if NFC is available and enabled"
		"send_whatsapp":
			return "Send a WhatsApp message (Android only). Opens WhatsApp with pre-filled text — user must tap Send. Args: \"phone\", \"message\""
		"send_telegram":
			return "Send a Telegram message via bot. Requires telegram_bot_token and telegram_chat_id in settings. Args: \"message\""
		_:
			return ""

func get_tool_schema(tool_name: String) -> Dictionary:
	match tool_name:
		"open_url":
			return {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}
		"run_command":
			return {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}
		"file_read":
			return {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}
		"calculator":
			return {"type": "object", "properties": {"expression": {"type": "string"}}, "required": ["expression"]}
		"send_sms":
			return {"type": "object", "properties": {"phone": {"type": "string"}, "message": {"type": "string"}}, "required": ["phone", "message"]}
		"open_camera":
			return {"type": "object", "properties": {}}
		"open_app":
			return {"type": "object", "properties": {"package_name": {"type": "string"}}, "required": ["package_name"]}
		"list_apps":
			return {"type": "object", "properties": {}}
		"run_python":
			return {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}
		"toast":
			return {"type": "object", "properties": {"message": {"type": "string"}}, "required": ["message"]}
		"vibrate":
			return {"type": "object", "properties": {"milliseconds": {"type": "string"}}, "required": ["milliseconds"]}
		"get_contacts":
			return {"type": "object", "properties": {"query": {"type": "string"}}, "required": []}
		"get_location":
			return {"type": "object", "properties": {}}
		"read_sms":
			return {"type": "object", "properties": {"limit": {"type": "string"}}, "required": []}
		"set_alarm":
			return {"type": "object", "properties": {"hour": {"type": "string"}, "minutes": {"type": "string"}, "message": {"type": "string"}}, "required": ["hour", "minutes"]}
		"set_timer":
			return {"type": "object", "properties": {"seconds": {"type": "string"}, "message": {"type": "string"}}, "required": ["seconds"]}
		"speak":
			return {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}
		"start_listening":
			return {"type": "object", "properties": {}}
		"make_call":
			return {"type": "object", "properties": {"phone": {"type": "string"}}, "required": ["phone"]}
		"get_call_log":
			return {"type": "object", "properties": {"limit": {"type": "string"}}, "required": []}
		"answer_call":
			return {"type": "object", "properties": {}}
		"end_call":
			return {"type": "object", "properties": {}}
		"get_call_state":
			return {"type": "object", "properties": {}}
		"set_call_mute":
			return {"type": "object", "properties": {"mute": {"type": "string"}}, "required": ["mute"]}
		"set_call_speaker":
			return {"type": "object", "properties": {"on": {"type": "string"}}, "required": ["on"]}
		"start_call_monitor":
			return {"type": "object", "properties": {}}
		"stop_call_monitor":
			return {"type": "object", "properties": {}}
		"get_calendar_events":
			return {"type": "object", "properties": {"limit": {"type": "string"}}, "required": []}
		"create_calendar_event":
			return {"type": "object", "properties": {"title": {"type": "string"}, "description": {"type": "string"}, "start_ms": {"type": "string"}, "end_ms": {"type": "string"}}, "required": ["title", "start_ms", "end_ms"]}
		"read_clipboard":
			return {"type": "object", "properties": {}}
		"write_clipboard":
			return {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}
		"toggle_flashlight":
			return {"type": "object", "properties": {"on": {"type": "string"}}, "required": ["on"]}
		"get_notifications":
			return {"type": "object", "properties": {}}
		"add_trusted_contact":
			return {"type": "object", "properties": {"phone": {"type": "string"}, "name": {"type": "string"}, "trust": {"type": "string"}}, "required": ["phone", "name", "trust"]}
		"list_trusted_contacts":
			return {"type": "object", "properties": {}}
		"media_control":
			return {"type": "object", "properties": {"action": {"type": "string"}}, "required": ["action"]}
		"get_volume":
			return {"type": "object", "properties": {"stream": {"type": "string"}}, "required": ["stream"]}
		"set_volume":
			return {"type": "object", "properties": {"stream": {"type": "string"}, "volume": {"type": "string"}}, "required": ["stream", "volume"]}
		"get_brightness":
			return {"type": "object", "properties": {}}
		"set_brightness":
			return {"type": "object", "properties": {"brightness": {"type": "string"}}, "required": ["brightness"]}
		"get_battery":
			return {"type": "object", "properties": {}}
		"get_wifi_info":
			return {"type": "object", "properties": {}}
		"wake_screen":
			return {"type": "object", "properties": {}}
		"set_screen_timeout":
			return {"type": "object", "properties": {"seconds": {"type": "string"}}, "required": ["seconds"]}
		"get_screen_timeout":
			return {"type": "object", "properties": {}}
		"share_text":
			return {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}
		"write_file":
			return {"type": "object", "properties": {"filename": {"type": "string"}, "content": {"type": "string"}}, "required": ["filename", "content"]}
		"list_directory":
			return {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}
		"add_contact":
			return {"type": "object", "properties": {"name": {"type": "string"}, "phone": {"type": "string"}}, "required": ["name", "phone"]}
		"get_bluetooth_devices":
			return {"type": "object", "properties": {}}
		"get_nfc_status":
			return {"type": "object", "properties": {}}
		"send_whatsapp":
			return {"type": "object", "properties": {"phone": {"type": "string"}, "message": {"type": "string"}}, "required": ["phone", "message"]}
		"send_telegram":
			return {"type": "object", "properties": {"message": {"type": "string"}}, "required": ["message"]}
		_:
			return {}

# ── Tool execution ──────────────────────────────────────────────────────────

func call_tool(tool_name: String, args: Dictionary) -> String:
	match tool_name:
		"open_url":
			return _tool_open_url(args)
		"run_command":
			return _tool_run_command(args)
		"file_read":
			return _tool_file_read(args)
		"calculator":
			return _tool_calculator(args)
		"send_sms":
			return await _tool_send_sms(args)
		"open_camera":
			return _tool_open_camera()
		"open_app":
			return _tool_open_app(args)
		"list_apps":
			return _tool_list_apps()
		"run_python":
			return _tool_run_python(args)
		"toast":
			return _tool_toast(args)
		"vibrate":
			return _tool_vibrate(args)
		"get_contacts":
			return _tool_get_contacts(args)
		"get_location":
			return _tool_get_location()
		"read_sms":
			return _tool_read_sms(args)
		"set_alarm":
			return _tool_set_alarm(args)
		"set_timer":
			return _tool_set_timer(args)
		"speak":
			return _tool_speak(args)
		"start_listening":
			return _tool_start_listening()
		"make_call":
			return await _tool_make_call(args)
		"get_call_log":
			return _tool_get_call_log(args)
		"answer_call":
			return _tool_answer_call()
		"end_call":
			return _tool_end_call()
		"get_call_state":
			return _tool_get_call_state()
		"set_call_mute":
			return _tool_set_call_mute(args)
		"set_call_speaker":
			return _tool_set_call_speaker(args)
		"start_call_monitor":
			return _tool_start_call_monitor()
		"stop_call_monitor":
			return _tool_stop_call_monitor()
		"get_calendar_events":
			return _tool_get_calendar_events(args)
		"create_calendar_event":
			return _tool_create_calendar_event(args)
		"read_clipboard":
			return _tool_read_clipboard()
		"write_clipboard":
			return _tool_write_clipboard(args)
		"toggle_flashlight":
			return _tool_toggle_flashlight(args)
		"get_notifications":
			return _tool_get_notifications()
		"add_trusted_contact":
			return _tool_add_trusted_contact(args)
		"list_trusted_contacts":
			return _tool_list_trusted_contacts()
		"media_control":
			return _tool_media_control(args)
		"get_volume":
			return _tool_get_volume(args)
		"set_volume":
			return _tool_set_volume(args)
		"get_brightness":
			return _tool_get_brightness()
		"set_brightness":
			return _tool_set_brightness(args)
		"web_search":
			return await _tool_web_search(args)
		"web_read":
			return await _tool_web_read(args)
		"get_battery":
			return _tool_get_battery()
		"get_wifi_info":
			return _tool_get_wifi_info()
		"wake_screen":
			return _tool_wake_screen()
		"set_screen_timeout":
			return _tool_set_screen_timeout(args)
		"get_screen_timeout":
			return _tool_get_screen_timeout()
		"share_text":
			return _tool_share_text(args)
		"write_file":
			return _tool_write_file(args)
		"list_directory":
			return _tool_list_directory(args)
		"add_contact":
			return _tool_add_contact(args)
		"get_bluetooth_devices":
			return _tool_get_bluetooth_devices()
		"get_nfc_status":
			return _tool_get_nfc_status()
		"send_whatsapp":
			return _tool_send_whatsapp(args)
		"send_telegram":
			return await _tool_send_telegram(args)
		_:
			return "Error: Unknown built-in tool '%s'" % tool_name

# ── Platform-agnostic tools ────────────────────────────────────────────────

func _tool_open_url(args: Dictionary) -> String:
	var url: String = args.get("input", args.get("url", ""))
	if url.is_empty():
		return "Error: No URL provided"
	if OS.has_feature("android") and _plugin:
		_plugin.openUrl(url)
	else:
		OS.shell_open(url)
	return "Opened: %s" % url

func _tool_run_command(args: Dictionary) -> String:
	var command: String = args.get("input", args.get("command", ""))
	if command.is_empty():
		return "Error: No command provided"

	if OS.has_feature("android") and _plugin:
		# Use async command on Android — wait for signal
		_plugin.execCommand(command)
		# Synchronous fallback for simple cases
		var output: String = _plugin.execCommandSync(command)
		return output
	elif OS.has_feature("android"):
		# Shell fallback without plugin
		var output: Array = []
		var parts := command.split(" ", false, 1)
		var cmd := parts[0]
		var cmd_args: PackedStringArray = []
		if parts.size() > 1:
			cmd_args = parts[1].split(" ")
		OS.execute(cmd, cmd_args, output)
		if output.size() > 0:
			return output[0].strip_edges()
		return "Command executed"
	else:
		# Desktop: use OS.execute
		var parts := command.split(" ", false, 1)
		var cmd := parts[0]
		var cmd_args: PackedStringArray = []
		if parts.size() > 1:
			cmd_args = parts[1].split(" ")
		var output: Array = []
		var exit_code: int = OS.execute(cmd, cmd_args, output)
		if output.size() > 0:
			return output[0].strip_edges()
		return "Exit code: %d" % exit_code

func _tool_file_read(args: Dictionary) -> String:
	var path: String = args.get("input", args.get("path", ""))
	if path.is_empty():
		return "Error: No file path provided"

	if not FileAccess.file_exists(path):
		return "Error: File not found: %s" % path

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Error: Cannot open file: %s" % path
	var content: String = file.get_as_text()
	file.close()
	# Truncate very large files
	if content.length() > 10000:
		content = content.substr(0, 10000) + "\n... [truncated]"
	return content

func _tool_calculator(args: Dictionary) -> String:
	var expr: String = args.get("input", args.get("expression", ""))
	if expr.is_empty():
		return "Error: No expression provided"
	# Validate: only allow numbers, operators, parentheses, spaces, dots
	var sanitized := expr.strip_edges()
	var valid_chars := RegEx.new()
	valid_chars.compile("^[0-9+\\-*/().%\\s]+$")
	if not valid_chars.search(sanitized):
		return "Error: Invalid expression (only numbers and +-*/().%% allowed)"
	var expr_node := Expression.new()
	var err := expr_node.parse(sanitized)
	if err != OK:
		return "Error: Cannot parse expression: %s" % sanitized
	var result: Variant = expr_node.execute()
	if expr_node.has_execute_failed():
		return "Error: Execution failed for: %s" % sanitized
	return str(result)

# ── Android-only tools ─────────────────────────────────────────────────────

func _tool_send_sms(args: Dictionary) -> String:
	var phone: String = args.get("phone", args.get("arg0", args.get("input", "")))
	var message: String = args.get("message", args.get("arg1", ""))
	if phone.is_empty() or message.is_empty():
		return "Error: Both phone and message are required. Got: phone='%s' message='%s' args=%s" % [phone, message, str(args)]
	# Check trust level — require confirmation for non-full-trust contacts
	if not _is_full_trusted(phone):
		var confirmed: bool = await _await_confirmation("Send SMS", phone, message)
		if not confirmed:
			return "SMS cancelled by user"
	if _plugin:
		_plugin.sendSMS(phone, message)
		return "SMS sent to %s" % phone
	if OS.has_feature("android"):
		# Shell fallback: use am command to send SMS via intent
		var output: Array = []
		print("BuiltinTools: sending SMS via am intent to %s" % phone)
		OS.execute("am", ["start", "-a", "android.intent.action.SENDTO",
			"-d", "sms:%s" % phone, "--es", "sms_body", message], output)
		print("BuiltinTools: am output: %s" % str(output))
		return "SMS compose screen opened to %s — user must tap Send manually (plugin not loaded)" % phone
	return "Error: SMS only available on Android"

func _tool_open_camera() -> String:
	if _plugin:
		_plugin.openCamera()
		return "Camera opened"
	if OS.has_feature("android"):
		OS.execute("am", ["start", "-a", "android.media.action.IMAGE_CAPTURE"], [])
		return "Camera opened"
	return "Error: Camera only available on Android"

func _tool_open_app(args: Dictionary) -> String:
	var pkg: String = args.get("input", args.get("package_name", ""))
	if pkg.is_empty():
		return "Error: No package name provided"
	if _plugin:
		_plugin.openApp(pkg)
		return "Opened: %s" % pkg
	if OS.has_feature("android"):
		OS.execute("am", ["start", "-n", "%s/.MainActivity" % pkg], [])
		# Try monkey as fallback
		OS.execute("monkey", ["-p", pkg, "-c", "android.intent.category.LAUNCHER", "1"], [])
		return "Launched: %s" % pkg
	return "Error: open_app only available on Android"

func _tool_list_apps() -> String:
	if _plugin:
		return _plugin.listApps()
	if OS.has_feature("android"):
		var output: Array = []
		OS.execute("pm", ["list", "packages", "-3"], output)
		if output.size() > 0:
			return output[0].strip_edges()
		return "Error: could not list apps"
	return "Error: list_apps only available on Android"

func _tool_run_python(args: Dictionary) -> String:
	var command: String = args.get("input", args.get("command", ""))
	if command.is_empty():
		return "Error: No Python command provided"

	if OS.has_feature("android") and _plugin:
		# Find Python path (Termux or bundled)
		var python_path: String = _plugin.getPythonPath()
		if python_path.is_empty():
			return "Error: Python not found. Install Termux or bundle Python."
		var full_cmd: String = "%s %s" % [python_path, command]
		return _plugin.execCommandSync(full_cmd)
	else:
		# Desktop: try python3, then python
		var python_path := "python3"
		if OS.execute("python3", ["--version"], []) != 0:
			if OS.execute("python", ["--version"], []) == 0:
				python_path = "python"
			else:
				return "Error: Python not found on this system"
		var output: Array = []
		var parts := command.split(" ", false)
		var exit_code: int = OS.execute(python_path, parts, output)
		if output.size() > 0:
			return output[0].strip_edges()
		return "Exit code: %d" % exit_code

func _tool_toast(args: Dictionary) -> String:
	var msg: String = args.get("input", args.get("message", ""))
	if _plugin:
		_plugin.showToast(msg)
		return "Toast shown"
	if OS.has_feature("android"):
		OS.execute("toast", [msg], [])
		return "Toast shown (shell)"
	return "Toast only available on Android"

func _tool_vibrate(args: Dictionary) -> String:
	if _plugin:
		var ms: String = args.get("input", args.get("milliseconds", "200"))
		_plugin.vibrate(int(ms))
		return "Vibrated for %s ms" % ms
	if OS.has_feature("android"):
		var ms: String = args.get("input", args.get("milliseconds", "200"))
		OS.execute("cmd", ["vibrator", "vibrate", ms], [])
		return "Vibrated for %s ms (shell)" % ms
	return "Vibrate only available on Android"

func _tool_get_contacts(args: Dictionary) -> String:
	if _plugin:
		var query: String = args.get("input", args.get("query", args.get("arg0", "")))
		return _plugin.getContacts(query)
	if OS.has_feature("android"):
		var output: Array = []
		var query: String = args.get("input", args.get("query", ""))
		OS.execute("content", ["query", "--uri", "content://com.android.contacts/contacts", "--projection", "display_name"], output)
		if output.size() > 0:
			return output[0].strip_edges()
		return "Error: could not read contacts"
	return "Error: contacts only available on Android"

func _tool_get_location() -> String:
	if _plugin:
		return _plugin.getLocation()
	return "Error: location only available on Android with plugin"

func _tool_read_sms(args: Dictionary) -> String:
	if _plugin:
		var limit: String = args.get("input", args.get("limit", args.get("arg0", "20")))
		return _plugin.readSmsInbox(int(limit))
	if OS.has_feature("android"):
		var output: Array = []
		OS.execute("content", ["query", "--uri", "content://sms/inbox", "--projection", "address:body:date", "--sort-order", "date DESC", "--limit", "20"], output)
		if output.size() > 0:
			return output[0].strip_edges()
		return "Error: could not read SMS"
	return "Error: read_sms only available on Android"

func _tool_set_alarm(args: Dictionary) -> String:
	var hour_str: String = args.get("hour", args.get("arg0", ""))
	var min_str: String = args.get("minutes", args.get("minute", args.get("arg1", "0")))
	var message: String = args.get("message", args.get("arg2", "GhostKV Alarm"))
	if hour_str.is_empty():
		return "Error: hour is required (0-23)"
	if _plugin:
		_plugin.setAlarm(int(hour_str), int(min_str), message)
		return "Alarm set for %s:%s" % [hour_str, min_str]
	if OS.has_feature("android"):
		var output: Array = []
		OS.execute("am", ["start", "-a", "android.intent.action.SET_ALARM",
			"--ei", "android.intent.extra.alarm.HOUR", hour_str,
			"--ei", "android.intent.extra.alarm.MINUTES", min_str,
			"--es", "android.intent.extra.alarm.MESSAGE", message], output)
		return "Alarm intent launched for %s:%s" % [hour_str, min_str]
	return "Error: set_alarm only available on Android"

func _tool_set_timer(args: Dictionary) -> String:
	var seconds_str: String = args.get("seconds", args.get("arg0", "60"))
	var message: String = args.get("message", args.get("arg1", "GhostKV Timer"))
	if _plugin:
		_plugin.setTimer(int(seconds_str), message)
		return "Timer set for %s seconds" % seconds_str
	return "Error: set_timer only available on Android with plugin"

func _tool_speak(args: Dictionary) -> String:
	var text: String = args.get("input", args.get("text", args.get("arg0", "")))
	if text.is_empty():
		return "Error: no text provided"
	if _plugin:
		_plugin.speak(text)
		return "Speaking: %s" % text.left(50)
	return "Error: TTS only available on Android with plugin"

func _tool_start_listening() -> String:
	if _plugin:
		_plugin.startSpeechRecognition()
		return "Listening... result will appear in chat"
	return "Error: speech recognition only available on Android with plugin"

# ── Phone, Calendar, Clipboard, Flashlight, Notifications ──────────────────

func _tool_make_call(args: Dictionary) -> String:
	var phone: String = args.get("input", args.get("phone", args.get("arg0", "")))
	if phone.is_empty():
		return "Error: no phone number provided"
	# Check trust level — require confirmation for non-full-trust contacts
	if not _is_full_trusted(phone):
		var confirmed: bool = await _await_confirmation("Call", phone)
		if not confirmed:
			return "Call cancelled by user"
	if _plugin:
		_plugin.makeCall(phone)
		return "Calling %s" % phone
	if OS.has_feature("android"):
		var output: Array = []
		OS.execute("am", ["start", "-a", "android.intent.action.DIAL", "-d", "tel:%s" % phone], output)
		return "Dialing %s" % phone
	return "Error: calling only available on Android"

func _tool_get_call_log(args: Dictionary) -> String:
	var limit: String = args.get("input", args.get("limit", args.get("arg0", "20")))
	if _plugin:
		return _plugin.getCallLog(int(limit))
	return "Error: call log only available on Android with plugin"

func _tool_answer_call() -> String:
	var tel := Engine.get_singleton("TelephonyManager") as Node
	if tel and tel.has_method("answer_call"):
		return tel.answer_call()
	if _plugin and _plugin.has_method("answerCall"):
		return _plugin.answerCall()
	return "Error: answering calls requires Android 8+ with telephony plugin"

func _tool_end_call() -> String:
	var tel := Engine.get_singleton("TelephonyManager") as Node
	if tel and tel.has_method("end_call"):
		return tel.end_call()
	if _plugin and _plugin.has_method("endCall"):
		return _plugin.endCall()
	return "Error: ending calls requires Android 9+ with telephony plugin"

func _tool_get_call_state() -> String:
	var tel := Engine.get_singleton("TelephonyManager") as Node
	if tel and tel.has_method("get_raw_state"):
		return tel.get_raw_state()
	if _plugin and _plugin.has_method("getCallState"):
		return _plugin.getCallState()
	return "idle"

func _tool_set_call_mute(args: Dictionary) -> String:
	var mute_str: String = args.get("mute", args.get("arg0", "true"))
	var mute: bool = mute_str == "true"
	var tel := Engine.get_singleton("TelephonyManager") as Node
	if tel and tel.has_method("set_mute"):
		return tel.set_mute(mute)
	if _plugin and _plugin.has_method("setMicMute"):
		return _plugin.setMicMute(mute)
	return "Error: call mute only available on Android with telephony plugin"

func _tool_set_call_speaker(args: Dictionary) -> String:
	var on_str: String = args.get("on", args.get("arg0", "true"))
	var on: bool = on_str == "true"
	var tel := Engine.get_singleton("TelephonyManager") as Node
	if tel and tel.has_method("set_speaker"):
		return tel.set_speaker(on)
	if _plugin and _plugin.has_method("setSpeakerphone"):
		return _plugin.setSpeakerphone(on)
	return "Error: speaker control only available on Android with telephony plugin"

func _tool_start_call_monitor() -> String:
	var tel := Engine.get_singleton("TelephonyManager") as Node
	if tel and tel.has_method("start_monitor"):
		return tel.start_monitor()
	if _plugin and _plugin.has_method("startCallMonitor"):
		return _plugin.startCallMonitor()
	return "Error: call monitoring only available on Android with telephony plugin"

func _tool_stop_call_monitor() -> String:
	var tel := Engine.get_singleton("TelephonyManager") as Node
	if tel and tel.has_method("stop_monitor"):
		return tel.stop_monitor()
	if _plugin and _plugin.has_method("stopCallMonitor"):
		return _plugin.stopCallMonitor()
	return "Error: call monitoring only available on Android with telephony plugin"

func _tool_get_calendar_events(args: Dictionary) -> String:
	var limit: String = args.get("input", args.get("limit", args.get("arg0", "20")))
	if _plugin:
		return _plugin.getCalendarEvents(int(limit))
	return "Error: calendar only available on Android with plugin"

func _tool_create_calendar_event(args: Dictionary) -> String:
	var title: String = args.get("title", args.get("arg0", ""))
	var desc: String = args.get("description", args.get("arg1", ""))
	var start_ms: String = args.get("start_ms", args.get("arg2", ""))
	var end_ms: String = args.get("end_ms", args.get("arg3", ""))
	if title.is_empty() or start_ms.is_empty() or end_ms.is_empty():
		return "Error: title, start_ms, and end_ms are required"
	if _plugin:
		return _plugin.createCalendarEvent(title, desc, int(start_ms), int(end_ms))
	return "Error: calendar only available on Android with plugin"

func _tool_read_clipboard() -> String:
	if _plugin:
		var text: String = _plugin.readClipboard()
		if text.is_empty():
			return "Clipboard is empty"
		return text
	return "Error: clipboard only available on Android with plugin"

func _tool_write_clipboard(args: Dictionary) -> String:
	var text: String = args.get("input", args.get("text", args.get("arg0", "")))
	if text.is_empty():
		return "Error: no text provided"
	if _plugin:
		_plugin.writeClipboard(text)
		return "Copied to clipboard"
	return "Error: clipboard only available on Android with plugin"

func _tool_toggle_flashlight(args: Dictionary) -> String:
	var on_str: String = args.get("input", args.get("on", args.get("arg0", "true")))
	var on: bool = on_str == "true" or on_str == "1"
	if _plugin:
		_plugin.setFlashlight(on)
		return "Flashlight %s" % ("on" if on else "off")
	return "Error: flashlight only available on Android with plugin"

func _tool_get_notifications() -> String:
	if _plugin:
		return _plugin.getNotifications()
	return "Error: notifications only available on Android with plugin"

func _tool_add_trusted_contact(args: Dictionary) -> String:
	var phone: String = args.get("phone", args.get("arg0", ""))
	var name: String = args.get("name", args.get("arg1", ""))
	var trust: String = args.get("trust", args.get("arg2", "temp"))
	if phone.is_empty() or name.is_empty():
		return "Error: phone and name are required. Args: \"phone\", \"name\", \"trust\" (full or temp)"
	if trust != "full" and trust != "temp":
		trust = "temp"
	add_trusted_contact(phone, name, trust)
	return "Added %s (%s) as %s trust contact" % [name, phone, trust]

func _tool_list_trusted_contacts() -> String:
	if _trusted_contacts.is_empty():
		return "No trusted contacts configured. Use add_trusted_contact to add contacts."
	var lines: PackedStringArray = []
	for phone in _trusted_contacts:
		var entry: Dictionary = _trusted_contacts[phone]
		lines.append("- %s (%s): %s" % [entry.get("name", "?"), phone, entry.get("trust", "temp")])
	return "Trusted contacts:\n" + "\n".join(lines)

# ── Medium value tools ──────────────────────────────────────────────────────

func _tool_media_control(args: Dictionary) -> String:
	var action: String = args.get("input", args.get("action", args.get("arg0", "")))
	if action.is_empty():
		return "Error: action required (play, pause, next, previous)"
	if action != "play" and action != "pause" and action != "next" and action != "previous":
		return "Error: invalid action '%s'. Use play, pause, next, or previous" % action
	if _plugin:
		_plugin.mediaControl(action)
		return "Media: %s" % action
	return "Error: media control only available on Android with plugin"

func _tool_get_volume(args: Dictionary) -> String:
	var stream: String = args.get("input", args.get("stream", args.get("arg0", "music")))
	if _plugin:
		var vol: int = _plugin.getVolume(stream)
		var max_vol: int = _plugin.getMaxVolume(stream)
		return "Volume (%s): %d / %d" % [stream, vol, max_vol]
	return "Error: volume only available on Android with plugin"

func _tool_set_volume(args: Dictionary) -> String:
	var stream: String = args.get("stream", args.get("arg0", "music"))
	var vol_str: String = args.get("volume", args.get("arg1", ""))
	if vol_str.is_empty():
		return "Error: volume value required"
	var vol: int = int(vol_str)
	if _plugin:
		_plugin.setVolume(stream, vol)
		return "Volume (%s) set to %d" % [stream, vol]
	return "Error: volume only available on Android with plugin"

func _tool_get_brightness() -> String:
	if _plugin:
		var b: float = _plugin.getBrightness()
		if b < 0:
			return "Error: could not read brightness"
		return "Brightness: %d / 255 (%.0f%%)" % [int(b), b / 255.0 * 100]
	return "Error: brightness only available on Android with plugin"

func _tool_set_brightness(args: Dictionary) -> String:
	var b_str: String = args.get("input", args.get("brightness", args.get("arg0", "")))
	if b_str.is_empty():
		return "Error: brightness value required (0-255)"
	var b: int = int(b_str)
	if _plugin:
		_plugin.setBrightness(b)
		return "Brightness set to %d / 255" % b
	return "Error: brightness only available on Android with plugin"

func _tool_get_battery() -> String:
	if _plugin:
		var result: String = _plugin.getBatteryStatus()
		if result == "{}":
			return "Error: could not read battery status"
		var json := JSON.new()
		if json.parse(result) == OK:
			var d: Dictionary = json.data
			return "Battery: %d%% | %s | plugged: %s | health: %s" % [d.get("level", 0), d.get("status", "?"), d.get("plugged", "?"), d.get("health", "?")]
		return "Battery: %s" % result
	return "Error: battery status only available on Android with plugin"

func _tool_get_wifi_info() -> String:
	if _plugin:
		var result: String = _plugin.getWifiInfo()
		if result == "{}":
			return "Error: could not read WiFi info"
		var json := JSON.new()
		if json.parse(result) == OK:
			var d: Dictionary = json.data
			if not d.get("enabled", false):
				return "WiFi is disabled"
			return "WiFi: %s | IP: %s | Signal: %d/4 (RSSI: %d)" % [d.get("ssid", "?"), d.get("ip", "?"), d.get("signal_level", 0), d.get("rssi", 0)]
		return "WiFi: %s" % result
	return "Error: WiFi info only available on Android with plugin"

func _tool_wake_screen() -> String:
	if _plugin:
		_plugin.wakeScreen()
		return "Screen woken"
	return "Error: screen control only available on Android with plugin"

func _tool_set_screen_timeout(args: Dictionary) -> String:
	var s_str: String = args.get("input", args.get("seconds", args.get("arg0", "30")))
	var seconds: int = int(s_str)
	if _plugin:
		_plugin.setScreenTimeout(seconds)
		return "Screen timeout set to %d seconds" % seconds
	return "Error: screen control only available on Android with plugin"

func _tool_get_screen_timeout() -> String:
	if _plugin:
		var t: int = _plugin.getScreenTimeout()
		if t < 0:
			return "Error: could not read screen timeout"
		return "Screen timeout: %d seconds" % t
	return "Error: screen control only available on Android with plugin"

func _tool_share_text(args: Dictionary) -> String:
	var text: String = args.get("input", args.get("text", args.get("arg0", "")))
	if text.is_empty():
		return "Error: text required"
	if _plugin:
		_plugin.shareText(text)
		return "Share sheet opened"
	return "Error: share only available on Android with plugin"

# ── Nice to have tools ──────────────────────────────────────────────────────

func _tool_write_file(args: Dictionary) -> String:
	var filename: String = args.get("filename", args.get("arg0", ""))
	var content: String = args.get("content", args.get("arg1", ""))
	if filename.is_empty() or content.is_empty():
		return "Error: filename and content required"
	if _plugin:
		var result: String = _plugin.writeFile(filename, content)
		return result
	return "Error: file write only available on Android with plugin"

func _tool_list_directory(args: Dictionary) -> String:
	var path: String = args.get("input", args.get("path", args.get("arg0", "")))
	if path.is_empty():
		path = "downloads"
	if _plugin:
		var result: String = _plugin.listDirectory(path)
		if result.begins_with("Error:"):
			return result
		var json := JSON.new()
		if json.parse(result) == OK and json.data is Array:
			var items: Array = json.data
			if items.is_empty():
				return "Directory is empty"
			var lines: PackedStringArray = []
			for item in items:
				var d: Dictionary = item
				var icon: String = "FILE"
				if d.get("is_dir", false):
					icon = "DIR "
				var size: int = d.get("size", 0)
				var name: String = d.get("name", "?")
				if size > 1048576:
					lines.append("  %s  %-40s  %.1f MB" % [icon, name, size / 1048576.0])
				elif size > 1024:
					lines.append("  %s  %-40s  %.1f KB" % [icon, name, size / 1024.0])
				else:
					lines.append("  %s  %-40s  %d B" % [icon, name, size])
			return "Listing (%d items):\n%s" % [items.size(), "\n".join(lines)]
		return "Directory: %s" % result
	return "Error: list directory only available on Android with plugin"

func _tool_add_contact(args: Dictionary) -> String:
	var name: String = args.get("name", args.get("arg0", ""))
	var phone: String = args.get("phone", args.get("arg1", ""))
	if name.is_empty() or phone.is_empty():
		return "Error: name and phone required"
	if _plugin:
		var result: String = _plugin.addContact(name, phone)
		return result
	return "Error: add contact only available on Android with plugin"

func _tool_get_bluetooth_devices() -> String:
	if _plugin:
		var result: String = _plugin.getBluetoothDevices()
		if result == "[]":
			return "Error: Bluetooth not available"
		var json := JSON.new()
		if json.parse(result) == OK:
			var d: Dictionary = json.data
			if not d.get("enabled", false):
				return "Bluetooth is disabled"
			var devices: Array = d.get("devices", [])
			if devices.is_empty():
				return "No paired Bluetooth devices"
			var lines: PackedStringArray = []
			for dev in devices:
				var dd: Dictionary = dev
				lines.append("- %s (%s)" % [dd.get("name", "?"), dd.get("address", "?")])
			return "Paired devices (%d):\n%s" % [devices.size(), "\n".join(lines)]
		return "Bluetooth: %s" % result
	return "Error: Bluetooth only available on Android with plugin"

func _tool_get_nfc_status() -> String:
	if _plugin:
		var result: String = _plugin.getNfcStatus()
		var json := JSON.new()
		if json.parse(result) == OK:
			var d: Dictionary = json.data
			if not d.get("available", false):
				return "NFC not available on this device"
			if d.get("enabled", false):
				return "NFC is enabled"
			return "NFC available but disabled"
		return "NFC: %s" % result
	return "Error: NFC only available on Android with plugin"

# ── WhatsApp & Telegram ──────────────────────────────────────────────────

func _tool_send_whatsapp(args: Dictionary) -> String:
	var phone: String = args.get("phone", args.get("arg0", ""))
	var message: String = args.get("message", args.get("arg1", ""))
	if phone.is_empty() or message.is_empty():
		return "Error: phone and message are required"
	if _plugin:
		var ok: bool = _plugin.sendWhatsApp(phone, message)
		if ok:
			return "WhatsApp opened for %s with message pre-filled. User must tap Send." % phone
		else:
			return "Error: WhatsApp is not installed on this device"
	if OS.has_feature("android"):
		# Shell fallback
		var output: Array = []
		OS.execute("am", ["start", "-a", "android.intent.action.SENDTO",
			"-d", "smsto:%s" % phone,
			"--es", "sms_body", message,
			"-p", "com.whatsapp"], output)
		return "WhatsApp intent launched for %s (shell fallback)" % phone
	return "Error: WhatsApp only available on Android"

func _tool_send_telegram(args: Dictionary) -> String:
	var message: String = args.get("message", args.get("arg0", ""))
	if message.is_empty():
		return "Error: message is required"
	# Read Telegram settings from session
	var session := Engine.get_singleton("SessionManager") as Node
	if not session:
		return "Error: SessionManager not available"
	var settings: Dictionary = session.load_settings()
	var bot_token: String = settings.get("telegram_bot_token", "")
	var chat_id: String = settings.get("telegram_chat_id", "")
	if bot_token.is_empty() or chat_id.is_empty():
		return "Error: Telegram not configured. Set telegram_bot_token and telegram_chat_id in settings."
	# Send via Telegram Bot API
	var url := "https://api.telegram.org/bot%s/sendMessage" % bot_token
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({"chat_id": chat_id, "text": message})
	var err := _telegram_http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		return "Error: Telegram request failed: %s" % error_string(err)
	# Wait for response
	var response: Array = await _telegram_http.request_completed
	var result: int = response[0]
	var code: int = response[1]
	var resp_body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return "Error: Telegram request failed (result=%d)" % result
	if code != 200:
		return "Error: Telegram API returned %d: %s" % [code, resp_body.get_string_from_utf8().left(200)]
	var json := JSON.new()
	var body_text := resp_body.get_string_from_utf8()
	if json.parse(body_text) == OK:
		var data: Dictionary = json.data
		if data.get("ok", false):
			var msg_data: Dictionary = data.get("result", {})
			return "Telegram message sent (msg_id: %d)" % msg_data.get("message_id", 0)
		else:
			return "Error: Telegram API error: %s" % data.get("description", "unknown")
	return "Telegram message sent"

# ── Web tools (SearXNG + web-reader) ────────────────────────────────────────

var _web_http: HTTPRequest

func _get_web_http() -> HTTPRequest:
	if not _web_http:
		_web_http = HTTPRequest.new()
		add_child(_web_http)
	return _web_http

func _tool_web_search(args: Dictionary) -> String:
	var query: String = args.get("query", args.get("input", args.get("arg0", "")))
	if query.is_empty():
		return "Error: web_search requires a query"

	var http := _get_web_http()
	var searx_url := "http://192.168.0.33:8888/search?q=%s&format=json&categories=general&language=en" % query.uri_encode()
	var err := http.request(searx_url, [], HTTPClient.METHOD_GET)
	if err != OK:
		return "Error: Failed to send search request"

	var response: Array = await http.request_completed
	var result: int = response[0]
	var code: int = response[1]
	var body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return "Error: Search request failed (%d)" % code

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return "Error: Invalid JSON response"

	var data: Dictionary = json.data
	var results: Array = data.get("results", [])
	if results.is_empty():
		return "No results found for '%s'" % query

	var lines: PackedStringArray = []
	var count := mini(results.size(), 5)
	for i in count:
		var r: Dictionary = results[i]
		lines.append("%d. %s\n   %s\n   URL: %s" % [i + 1, r.get("title", ""), r.get("content", "").left(200), r.get("url", "")])
	return "Search results for '%s':\n\n%s" % [query, "\n\n".join(lines)]

func _tool_web_read(args: Dictionary) -> String:
	var url: String = args.get("url", args.get("input", args.get("arg0", "")))
	if url.is_empty():
		return "Error: web_read requires a URL"

	var http := _get_web_http()
	# Use web-reader MCP server's reader endpoint directly
	var reader_url := "http://192.168.0.33:8003/read?url=%s" % url.uri_encode()
	var err := http.request(reader_url, [], HTTPClient.METHOD_GET)
	if err != OK:
		return "Error: Failed to send read request"

	var response: Array = await http.request_completed
	var result: int = response[0]
	var code: int = response[1]
	var body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return "Error: Read request failed (%d)" % code

	var text := body.get_string_from_utf8()
	# Truncate to ~4000 chars to avoid overwhelming the LLM context
	if text.length() > 4000:
		text = text.left(4000) + "\n\n[Content truncated at 4000 chars]"
	return text
