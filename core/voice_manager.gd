extends Node

signal listening_changed(active: bool)
signal voice_mode_changed(active: bool)
signal speech_partial(text: String)
signal speaking_changed(active: bool)

var _voice_mode: bool = false
var _auto_tts: bool = false
var _is_listening: bool = false
var _is_speaking: bool = false
var _plugin: Object = null
var _state: Node = null
var _react_loop: Node = null
var _input_bar: Node = null
var _tts_utterance_id: String = ""
var _pending_restart: bool = false

func _ready() -> void:
	_state = Engine.get_singleton("AppState")
	_react_loop = Engine.get_singleton("ReactLoop")

	# Try to get Android plugin (null on desktop)
	if Engine.has_singleton("GhostKVPlugin"):
		_plugin = Engine.get_singleton("GhostKVPlugin")

	# Connect react loop for auto-TTS
	if _react_loop:
		_react_loop.answer_ready.connect(_on_answer_ready)

func set_input_bar(bar: Node) -> void:
	_input_bar = bar

func set_auto_tts(val: bool) -> void:
	_auto_tts = val

func is_voice_mode() -> bool:
	return _voice_mode

func is_listening() -> bool:
	return _is_listening

func is_speaking() -> bool:
	if _plugin:
		return _plugin.isSpeaking()
	return false

# ── Dictation mode (mic tap) ────────────────────────────────────

func start_listening() -> void:
	if not _plugin:
		return
	_connect_plugin_signals()
	_plugin.startContinuousListening()
	_is_listening = true
	listening_changed.emit(true)

# ── Voice chat mode ─────────────────────────────────────────────

func toggle_voice_mode() -> void:
	if _voice_mode:
		_deactivate_voice_mode()
	else:
		_activate_voice_mode()

func _activate_voice_mode() -> void:
	if not _plugin:
		return
	_voice_mode = true
	voice_mode_changed.emit(true)
	_connect_plugin_signals()
	_start_voice_listening()

func _deactivate_voice_mode() -> void:
	_voice_mode = false
	voice_mode_changed.emit(false)
	_stop_voice_listening()
	if _plugin and _plugin.isSpeaking():
		_plugin.stopSpeaking()
	_is_speaking = false
	speaking_changed.emit(false)

func barge_in() -> void:
	if not _voice_mode or not _plugin:
		return
	if _plugin.isSpeaking():
		_plugin.stopSpeaking()
	_is_speaking = false
	speaking_changed.emit(false)
	_pending_restart = false
	_start_voice_listening()

func _start_voice_listening() -> void:
	if not _plugin or not _voice_mode:
		return
	_plugin.startContinuousListening()
	_is_listening = true
	listening_changed.emit(true)

func _stop_voice_listening() -> void:
	if _plugin and _is_listening:
		_plugin.stopListening()
	_is_listening = false
	listening_changed.emit(false)

# ── Plugin signal handlers ──────────────────────────────────────

var _signals_connected: bool = false

func _connect_plugin_signals() -> void:
	if not _plugin or _signals_connected:
		return
	var signals := ["speech_result", "speech_error", "speech_partial", "listening_state", "tts_completed"]
	var handlers := [_on_speech_result, _on_speech_error, _on_speech_partial, _on_listening_state, _on_tts_completed]
	for i in range(signals.size()):
		var sig_name: String = signals[i]
		var handler: Callable = handlers[i]
		if _plugin.has_signal(sig_name) and not _plugin.is_connected(sig_name, handler):
			_plugin.connect(sig_name, handler)
	_signals_connected = true

func _on_speech_result(text: String) -> void:
	_is_listening = false
	listening_changed.emit(false)

	if _voice_mode:
		if _is_speaking:
			# Barge-in: stop TTS and treat this as new input
			if _plugin:
				_plugin.stopSpeaking()
			_is_speaking = false
			_send_voice_message(text)
			# Don't restart mic here — tts_completed won't fire since we stopped TTS
			_pending_restart = true
			get_tree().create_timer(0.3).timeout.connect(_on_restart_timer)
		else:
			_send_voice_message(text)
			# Don't restart mic — wait for tts_completed to restart
	else:
		if _input_bar and _input_bar.has_method("set_dictated_text"):
			_input_bar.set_dictated_text(text)

func _on_speech_error(msg: String) -> void:
	_is_listening = false
	listening_changed.emit(false)

	if _voice_mode:
		if msg == "NO_MATCH":
			# Silence detected (VAD) — restart listening after brief pause
			_pending_restart = true
			get_tree().create_timer(0.5).timeout.connect(_on_restart_timer)
		else:
			# Real error — restart listening after longer pause
			_pending_restart = true
			get_tree().create_timer(1.0).timeout.connect(_on_restart_timer)

func _on_restart_timer() -> void:
	if _pending_restart and _voice_mode and not _is_listening:
		_start_voice_listening()
	_pending_restart = false

func _on_speech_partial(text: String) -> void:
	speech_partial.emit(text)

func _on_listening_state(active: bool) -> void:
	_is_listening = active
	listening_changed.emit(active)

func _on_tts_completed(utterance_id: String) -> void:
	if utterance_id == _tts_utterance_id:
		_is_speaking = false
		speaking_changed.emit(false)
		# Restart listening after TTS finishes
		if _voice_mode:
			_pending_restart = true
			get_tree().create_timer(0.3).timeout.connect(_on_restart_timer)

# ── Send voice message ──────────────────────────────────────────

func _send_voice_message(text: String) -> void:
	if text.strip_edges().is_empty():
		if _voice_mode:
			_start_voice_listening()
		return

	# Find the App node to send the message through
	var app := _find_node(get_tree().root, "App")
	if app and app.has_method("send_voice_message"):
		app.send_voice_message(text)
	elif app and app.has_method("_on_message_sent"):
		app._on_message_sent(text)

func _find_node(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var found := _find_node(child, name)
		if found:
			return found
	return null

# ── Auto-TTS ────────────────────────────────────────────────────

func _on_answer_ready(text: String) -> void:
	if not (_auto_tts or _voice_mode) or not _plugin:
		return

	# Strip markdown for speech
	var spoken := _strip_markdown(text)
	if spoken.is_empty():
		return

	_tts_utterance_id = "voice_chat_%d" % Time.get_ticks_msec()
	_is_speaking = true
	speaking_changed.emit(true)
	_plugin.speakWithId(spoken, _tts_utterance_id)

func _strip_markdown(text: String) -> String:
	var result := text
	# Remove code blocks
	var code_regex := RegEx.new()
	code_regex.compile("```[\\s\\S]*?```")
	result = code_regex.sub(result, "", true)
	# Remove inline code
	var inline_regex := RegEx.new()
	inline_regex.compile("`[^`]+`")
	result = inline_regex.sub(result, "", true)
	# Remove links [text](url)
	var link_regex := RegEx.new()
	link_regex.compile("\\[([^\\]]+)\\]\\([^)]+\\)")
	result = link_regex.sub(result, "$1", true)
	# Remove images ![alt](url)
	var img_regex := RegEx.new()
	img_regex.compile("!\\[[^\\]]*\\]\\([^)]+\\)")
	result = img_regex.sub(result, "", true)
	# Remove bold/italic markers
	result = result.replace("**", "").replace("__", "").replace("*", "").replace("_", " ")
	# Remove headers
	var header_regex := RegEx.new()
	header_regex.compile("(?m)^#+\\s*")
	result = header_regex.sub(result, "", true)
	# Collapse whitespace
	var ws_regex := RegEx.new()
	ws_regex.compile("\\s+")
	result = ws_regex.sub(result, " ", true)
	return result.strip_edges()
