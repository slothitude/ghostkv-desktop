extends Node

## Built-in tools that bridge to Android plugin (mobile) or OS APIs (desktop).
## Registered with ToolDispatch so the ReAct loop can call them via Action: syntax.

var _plugin: RefCounted = null  # GhostKVPlugin singleton on Android

func _ready() -> void:
	# On Android, the plugin is registered as a singleton by Godot's plugin loader
	if OS.has_feature("android"):
		_plugin = Engine.get_singleton("GhostKVPlugin")
	_register_tools()

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
			return "Send an SMS message (Android only). Args: \"phone\", \"message\""
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
			return _tool_send_sms(args)
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
		return "SMS intent launched to %s" % phone
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
