## ghost_call_agent.gd
## Autonomous call agent — holds phone conversations via LLM.
##
## Flow:
##   Incoming call → TelephonyManager signal → LLM decides answer/reject
##   Call active   → VoiceManager routes STT to _on_caller_speech() → LLM → TTS
##   Outgoing call → ghost_call tool → place call → same STT/LLM/TTS loop
##
## Dependencies (resolved via singletons in initialise()):
##   - TelephonyManager  (call control)
##   - VoiceManager      (STT/TTS routing)
##   - ApiClient         (LLM calls)

class_name GhostCallAgent
extends Node

# ── Config ─────────────────────────────────────────────────────────────────────
var auto_answer: bool = false
var auto_answer_delay: float = 3.0
var llm_system_prompt: String = "You are a ghost phone agent running on the user's Android phone.\nYou speak concisely and naturally. You answer calls on behalf of the user.\nWhen someone calls, greet them, find out what they want, and either:\n  - Handle it yourself (take a message, answer questions)\n  - Tell them the user will call back\nKeep responses under 2 sentences for natural conversation flow."

# ── State ──────────────────────────────────────────────────────────────────────
var _active_call_id: String = ""
var _transcript: Array = []
var _in_call: bool = false
var _llm_pending: bool = false
var _llm_last_response: String = ""
var _answer_timer: SceneTreeTimer = null
var _is_outgoing: bool = false
var _call_connected: bool = false
var _voicemail_timer: SceneTreeTimer = null
var _caller_spoke: bool = false
var _outgoing_speech_count: int = 0
var _silence_after_speech: bool = false
var _listening_active: bool = false
var _hangup_pending: bool = false

# ── Singleton refs (set in initialise) ────────────────────────────────────────
var _telephony: Node = null
var _voice: Node = null
var _api: Node = null

# ── Signals ────────────────────────────────────────────────────────────────────
signal call_transcript_updated(transcript: Array)
signal agent_decision(action: String, reason: String)

# ════════════════════════════════════════════════════════════════════════════════
# INIT
# ════════════════════════════════════════════════════════════════════════════════

func initialise() -> void:
	_telephony = Engine.get_singleton("TelephonyManager")
	_voice = Engine.get_singleton("VoiceManager")
	_api = Engine.get_singleton("ApiClient")

	# Connect telephony signals
	if _telephony:
		if _telephony.has_signal("incoming_call"):
			_telephony.incoming_call.connect(_on_incoming_call)
		if _telephony.has_signal("call_started"):
			_telephony.call_started.connect(_on_call_started)
		if _telephony.has_signal("call_ended"):
			_telephony.call_ended.connect(_on_call_ended)
	# Connect plugin's detailed call state for detecting actual connection
	if _telephony and _telephony._plugin:
		_telephony._plugin.connect("on_call_state_changed", _on_call_state_changed)

	_log("initialised — telephony=%s voice=%s api=%s" % [
		_telephony != null, _voice != null, _api != null
	])

# ════════════════════════════════════════════════════════════════════════════════
# PUBLIC API (called from builtin_tools)
# ════════════════════════════════════════════════════════════════════════════════

## Answer a ringing call and start the agent conversation loop.
func auto_answer_call() -> String:
	if not _telephony:
		return "Error: TelephonyManager not available"
	if _telephony.state != 0:  # CallState.RINGING = 0? Check enum
		# Try regardless — state might not be synced
		pass
	_do_answer()
	return "Agent answering call"

## Place an outgoing call and run the agent conversation loop.
func ghost_call(phone: String) -> String:
	if not _telephony:
		return "Error: TelephonyManager not available"
	_transcript = []
	_is_outgoing = true
	_call_connected = false
	_caller_spoke = false
	_outgoing_speech_count = 0
	var result: String = _telephony.make_call(phone)
	_log("ghost_call(%s) → %s" % [phone, result])
	return "Agent calling %s: %s" % [phone, result]

# ════════════════════════════════════════════════════════════════════════════════
# TELEPHONY EVENT HANDLERS
# ════════════════════════════════════════════════════════════════════════════════

func _on_incoming_call(number: String) -> void:
	_log("Incoming call from %s" % number)
	_active_call_id = _get_active_call_id()
	_transcript = []

	if auto_answer:
		_log("Auto-answer in %.1fs..." % auto_answer_delay)
		_answer_timer = get_tree().create_timer(auto_answer_delay)
		_answer_timer.timeout.connect(_do_answer)
	else:
		_llm_decide_answer(number)

func _on_call_started(number: String) -> void:
	_log("Call started (may still be dialing) with %s" % number)
	_in_call = true
	_active_call_id = _get_active_call_id()

	# Enable speaker so STT mic picks up caller audio
	if _telephony:
		_telephony.set_speaker(true)

	# Route VoiceManager STT to us instead of App
	if _voice:
		_voice.set_call_mode(self)

	# For incoming calls, greet immediately (call is already connected)
	# For outgoing calls, wait for on_call_state_changed "active"
	if not _is_outgoing:
		_greet_caller()

func _on_call_state_changed(info: String) -> void:
	# info format: "callId:state" (e.g. "call_123:active", "call_123:dialing")
	_log("Call state changed: %s" % info)
	if _is_outgoing and not _call_connected:
		var parts := info.split(":")
		if parts.size() >= 2 and parts[1] == "active":
			_call_connected = true
			# Speaker ON via InCallService (only works after call is active)
			if _telephony:
				_telephony.set_speaker(true)
			_log("Outgoing call connected — listening for caller or voicemail")
			_caller_spoke = false
			_outgoing_speech_count = 0
			_listening_active = false
			# Wait 2s before starting STT (avoid silence from connection setup)
			get_tree().create_timer(2.0).timeout.connect(func():
				if not _in_call:
					return
				_listening_active = true
				if _voice:
					_voice.start_listening()
			)
			# Safety timeout: if still going after 30s, leave message anyway
			_voicemail_timer = get_tree().create_timer(30.0)
			_voicemail_timer.timeout.connect(_on_voicemail_timeout)

func _greet_caller() -> void:
	var greeting: String = "Hello, I'm the Ghost in Aaron's phone. If you're happy to talk to a Ghost in the machine, how can I help you?"
	_transcript.append({"role": "assistant", "content": greeting})
	_speak(greeting)

func _on_voicemail_timeout() -> void:
	if not _in_call or _caller_spoke:
		return
	_log("Voicemail safety timeout — leaving message")
	_leave_voicemail()

func _leave_voicemail() -> void:
	var msg: String = "Hi, this is Aaron's Ghost phone assistant. Aaron will call you back as soon as he can. Thanks, bye!"
	_transcript.append({"role": "assistant", "content": "[voicemail] " + msg})
	_speak(msg)
	# Hang up after TTS finishes (~8s)
	_hangup_pending = true
	get_tree().create_timer(8.0).timeout.connect(_do_hangup)

func _cancel_voicemail_timer() -> void:
	_voicemail_timer = null

func _do_hangup() -> void:
	if not _hangup_pending or not _in_call:
		return
	_hangup_pending = false
	_log("Auto-hanging up after voicemail")
	if _telephony:
		_telephony.end_call()

func _on_call_ended(duration_sec: int) -> void:
	_log("Call ended after %ds" % duration_sec)
	_in_call = false
	_active_call_id = ""
	_llm_pending = false
	_llm_last_response = ""
	_is_outgoing = false
	_call_connected = false
	_caller_spoke = false
	_voicemail_timer = null
	_outgoing_speech_count = 0
	_listening_active = false
	_hangup_pending = false

	# Restore voice routing to normal
	if _voice:
		_voice.set_call_mode(null)

	# Restore audio to earpiece
	if _telephony:
		_telephony.set_speaker(false)

	# Cancel pending auto-answer
	if _answer_timer:
		_answer_timer = null

	# Keep transcript for reference
	call_transcript_updated.emit(_transcript.duplicate())
	_transcript = []

# ════════════════════════════════════════════════════════════════════════════════
# STT → LLM → TTS LOOP
# ════════════════════════════════════════════════════════════════════════════════

## Called by VoiceManager when call_mode is active.
func _on_caller_speech(text: String) -> void:
	if not _in_call or not _listening_active or text.strip_edges().is_empty():
		return

	# Outgoing call: first speech could be voicemail greeting or person saying hello
	# Short text (1-3 words like "hello") = likely a person. Greet them.
	# Longer text = voicemail greeting. Keep listening.
	if _is_outgoing and not _caller_spoke:
		_outgoing_speech_count += 1
		var word_count: int = text.split(" ").size()
		_log("Outgoing speech #%d (%d words): %s" % [_outgoing_speech_count, word_count, text])
		if word_count <= 4:
			# Short greeting — it's a person
			_log("Short greeting detected — greeting caller")
			_caller_spoke = true
			_cancel_voicemail_timer()
			_greet_caller()
		else:
			# Voicemail greeting — keep listening silently
			if _voice:
				_voice.start_listening()
		return

	# Person is talking (after initial greeting exchange) — normal conversation
	_cancel_voicemail_timer()

	_log("Caller said: %s" % text)
	_transcript.append({"role": "user", "content": text})
	call_transcript_updated.emit(_transcript)

	# Ask LLM for response
	var reply: String = await _llm_respond(text)
	if reply.is_empty():
		reply = "Sorry, could you say that again?"

	_transcript.append({"role": "assistant", "content": reply})
	_speak(reply)

## Called by VoiceManager when STT detects silence (NO_MATCH) or error during call.
func _on_caller_silence() -> void:
	if not _in_call or not _listening_active:
		return

	if _is_outgoing and not _caller_spoke:
		# Silence after voicemail greeting — this is the moment after the beep
		if _outgoing_speech_count > 0:
			_log("Silence after %d speech segments — leaving voicemail" % _outgoing_speech_count)
			_cancel_voicemail_timer()
			_leave_voicemail()
		else:
			# No speech yet — keep listening, don't greet
			_log("Silence before any speech — restarting listener")
			if _voice:
				_voice.start_listening()
		return

	# Normal conversation — restart listening
	if _voice:
		_voice.start_listening()

# ════════════════════════════════════════════════════════════════════════════════
# LLM CALLS (async via ApiClient signals)
# ════════════════════════════════════════════════════════════════════════════════

func _llm_decide_answer(number: String) -> void:
	var prompt: String = "Incoming call from %s. Should I answer? Reply YES or NO and one sentence reason." % number
	var decision: String = await _llm_call(prompt, [])

	var answer: bool = decision.to_upper().begins_with("YES")
	agent_decision.emit("answer" if answer else "reject", decision)

	if answer:
		_do_answer()
	else:
		_log("LLM rejected call: %s" % decision)
		if _telephony:
			_telephony.end_call()

func _llm_respond(caller_text: String) -> String:
	return await _llm_call(caller_text, _transcript)

func _llm_call(user_text: String, history: Array) -> String:
	if not _api:
		push_warning("GhostCallAgent: no ApiClient")
		return ""

	var messages: Array = [{"role": "system", "content": llm_system_prompt}]
	for msg in history:
		messages.append(msg)
	messages.append({"role": "user", "content": user_text})

	# Connect one-shot handlers
	_api.response_received.connect(_on_llm_response, CONNECT_ONE_SHOT)
	_api.error_occurred.connect(_on_llm_error, CONNECT_ONE_SHOT)

	_llm_pending = true
	_llm_last_response = ""
	_api.generate(messages, 0.7, 150)

	# Wait for response
	while _llm_pending:
		await get_tree().process_frame

	return _llm_last_response

func _on_llm_response(text: String, _usage: Dictionary) -> void:
	_llm_last_response = text.strip_edges()
	_llm_pending = false

func _on_llm_error(msg: String) -> void:
	push_warning("GhostCallAgent LLM error: %s" % msg)
	_llm_last_response = ""
	_llm_pending = false

# ════════════════════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════════════════════

func _do_answer() -> void:
	if _telephony:
		var result: String = _telephony.answer_call()
		_log("Answer result: %s" % result)

func _speak(text: String) -> void:
	if _voice and _voice.has_method("speak"):
		_voice.speak(text)
	else:
		_log("TTS: %s" % text)

func _get_active_call_id() -> String:
	if not _telephony or not _telephony._plugin:
		return ""
	var calls_json: String = _telephony._plugin.listActiveCalls()
	var regex := RegEx.new()
	regex.compile('"id":"([^"]+)"')
	var match := regex.search(calls_json)
	return match.get_string(1) if match else ""

func _log(msg: String) -> void:
	print("[GhostCallAgent] %s" % msg)
