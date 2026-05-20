extends Node

## Telegram bot singleton — receives messages via Java background thread polling,
## processes through ReactLoop, sends responses back via Java HTTP.
## Works even when app is backgrounded (like WhatsApp).
## Maintains conversation history for chat awareness.

var _bot_token: String = ""
var _chat_id: String = ""
var _plugin: Object = null  # GhostKVPlugin (Android)
var _telegram_pending: bool = false
var _history: Array = []  # conversation history [{role, content}, ...]
const MAX_HISTORY := 20  # keep last N messages (10 exchanges)

func _ready() -> void:
	# Get Android plugin
	if Engine.has_singleton("GhostKVPlugin"):
		_plugin = Engine.get_singleton("GhostKVPlugin")

	# Connect ReactLoop signals
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if react_loop:
		react_loop.answer_ready.connect(_on_answer_ready)
		react_loop.loop_error.connect(_on_loop_error)
		react_loop.tool_called.connect(_on_tool_called)

	# Connect plugin signal for incoming Telegram messages
	if _plugin:
		_plugin.connect("telegram_message", _on_telegram_message)

	_load_and_start()

func _load_and_start() -> void:
	var session := Engine.get_singleton("SessionManager") as Node
	if not session:
		return
	var settings: Dictionary = session.load_settings()
	_bot_token = settings.get("telegram_bot_token", "")
	_chat_id = str(settings.get("telegram_chat_id", ""))
	var enabled: bool = settings.get("telegram_enabled", true)
	if _bot_token.is_empty() or _chat_id.is_empty():
		print("TelegramBot: not configured (token or chat_id missing)")
		return
	if not enabled:
		print("TelegramBot: disabled in settings")
		return
	if not _plugin:
		print("TelegramBot: no Android plugin — Telegram not available")
		return
	start()

func start() -> void:
	if _bot_token.is_empty() or _chat_id.is_empty() or not _plugin:
		return
	_plugin.call("startTelegramPolling", _bot_token, _chat_id)
	print("TelegramBot: Java background polling started")

func stop() -> void:
	if _plugin:
		_plugin.call("stopTelegramPolling")
	print("TelegramBot: stopped")

# ── Incoming message from Java thread ──────────────────────────────

func _on_telegram_message(text: String) -> void:
	print("TelegramBot: received: %s" % text.left(80))

	# Handle /clear command to reset conversation
	if text.strip_edges().to_lower() == "/clear":
		_history.clear()
		_send("Conversation cleared.")
		return

	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if not react_loop:
		_send("Error: ReactLoop not available")
		return
	if react_loop.is_running():
		_send("Busy processing another request. Try again in a moment.")
		return

	_telegram_pending = true
	react_loop.run(text, _history)

# ── ReactLoop signal handlers ─────────────────────────────────────

func _on_answer_ready(text: String) -> void:
	print("TelegramBot: answer_ready fired, pending=%s text_len=%d" % [_telegram_pending, text.length()])
	if not _telegram_pending:
		return
	_telegram_pending = false

	# Save to conversation history
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if react_loop:
		var msgs = react_loop.get_messages()
		# Extract only user/assistant pairs (skip system and Observation entries)
		_history.clear()
		for m in msgs:
			var role: String = m.get("role", "")
			if role == "user" and not str(m.get("content", "")).begins_with("Observation:"):
				_history.append({"role": "user", "content": m["content"]})
			elif role == "assistant":
				_history.append({"role": "assistant", "content": m["content"]})
		# Trim to max history
		while _history.size() > MAX_HISTORY:
			_history.pop_front()

	_send(text)
	# Speak via TTS on phone
	if _plugin:
		var spoken := text.replace("```", "").replace("**", "").replace("__", "")
		spoken = spoken.replace("*", "").replace("_", " ")
		if spoken.length() > 1000:
			spoken = spoken.left(1000) + "..."
		if not spoken.strip_edges().is_empty():
			_plugin.call("speakWithId", spoken, "tg_%d" % Time.get_ticks_msec())

func _on_loop_error(msg: String) -> void:
	if not _telegram_pending:
		return
	_telegram_pending = false
	_send("Error: %s" % msg)

func _on_tool_called(name: String, _args: String) -> void:
	if not _telegram_pending:
		return
	_send("Using: %s" % name)

# ── Send response via Java ────────────────────────────────────────

func _send(text: String) -> void:
	print("TelegramBot: _send called, plugin=%s token_empty=%s text_len=%d" % [_plugin != null, _bot_token.is_empty(), text.length()])
	if not _plugin or _bot_token.is_empty():
		push_warning("TelegramBot: cannot send — plugin=%s token_empty=%s" % [_plugin != null, _bot_token.is_empty()])
		return
	_plugin.call("tgSend", _bot_token, _chat_id, text)

# ── Public: send message from GDScript ────────────────────────────

func send_message(text: String) -> void:
	_send(text)
