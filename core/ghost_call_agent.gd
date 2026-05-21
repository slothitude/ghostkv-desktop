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
	_log("Call active with %s" % number)
	_in_call = true
	_active_call_id = _get_active_call_id()

	# Enable speaker so STT mic picks up caller audio
	if _telephony:
		_telephony.set_speaker(true)

	# Route VoiceManager STT to us instead of App
	if _voice:
		_voice.set_call_mode(self)

	# Greet the caller
	var greeting: String = "Hello, I'm handling calls for the user right now. How can I help you?"
	_transcript.append({"role": "assistant", "content": greeting})
	_speak(greeting)

func _on_call_ended(duration_sec: int) -> void:
	_log("Call ended after %ds" % duration_sec)
	_in_call = false
	_active_call_id = ""
	_llm_pending = false
	_llm_last_response = ""

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
	if not _in_call or text.strip_edges().is_empty():
		return

	_log("Caller said: %s" % text)
	_transcript.append({"role": "user", "content": text})
	call_transcript_updated.emit(_transcript)

	# Ask LLM for response
	var reply: String = await _llm_respond(text)
	if reply.is_empty():
		reply = "Sorry, could you say that again?"

	_transcript.append({"role": "assistant", "content": reply})
	_speak(reply)

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
