## ghost_call_agent.gd
## Autonomous call agent — the "ghost in the machine."
##
## Requires:
##   - GhostKV set as default phone app (InCallService bound)
##   - voice_manager.gd initialised and connected to plugin
##   - telephony_manager.gd initialised and connected to plugin
##   - An LLM callable (Anthropic API, local llama.cpp, etc.)
##
## What this does:
##   Incoming call → LLM decides answer/reject
##   Call active   → STT feeds LLM → TTS responds through earpiece
##   Outgoing call → agent places call on your behalf via Telegram command
##
## Telegram commands (via existing bot integration):
##   /call +61412345678          → agent places outgoing call
##   /answer                     → answer ringing call
##   /hangup                     → end current call
##   /speaker on|off             → toggle speakerphone
##   /calls                      → list active calls

class_name GhostCallAgent
extends Node

# ── Dependencies (assign in editor or via initialise()) ──────────────────────
@export var telephony : TelephonyManager
@export var voice     : Node            # voice_manager.gd instance

# ── Config ────────────────────────────────────────────────────────────────────
@export var auto_answer       : bool   = false   # answer all calls automatically
@export var auto_answer_delay : float  = 3.0     # seconds before auto-answer
@export var llm_system_prompt : String = """
You are a ghost phone agent running on the user's Android phone.
You speak concisely and naturally. You answer calls on behalf of the user.
When someone calls, greet them, find out what they want, and either:
  - Handle it yourself (take a message, answer questions)
  - Tell them the user will call back
Keep responses under 2 sentences for natural conversation flow.
""".strip_edges()

# ── State ─────────────────────────────────────────────────────────────────────
var _active_call_id   : String = ""
var _transcript       : Array  = []   # [{role, content}, ...]
var _answer_timer     : SceneTreeTimer = null
var _in_call          : bool   = false

# ── Signals ───────────────────────────────────────────────────────────────────
signal call_transcript_updated(transcript: Array)
signal agent_decision(action: String, reason: String)

# ════════════════════════════════════════════════════════════════════════════
# INIT
# ════════════════════════════════════════════════════════════════════════════

func initialise(tel: TelephonyManager, voice_mgr: Node) -> void:
	telephony = tel
	voice     = voice_mgr
	_connect_signals()

func _connect_signals() -> void:
	if telephony:
		telephony.incoming_call.connect(_on_incoming_call)
		telephony.call_started.connect(_on_call_started)
		telephony.call_ended.connect(_on_call_ended)

	if voice:
		# Fired when STT produces a final transcript segment
		if voice.has_signal("on_speech_result"):
			voice.connect("on_speech_result", _on_speech_result)

# ════════════════════════════════════════════════════════════════════════════
# TELEPHONY EVENT HANDLERS
# ════════════════════════════════════════════════════════════════════════════

func _on_incoming_call(number: String) -> void:
	_log("📞 Incoming call from %s" % number)
	_active_call_id = _get_active_call_id()
	_transcript     = []

	if auto_answer:
		_log("Auto-answer in %.1fs..." % auto_answer_delay)
		_answer_timer = get_tree().create_timer(auto_answer_delay)
		_answer_timer.timeout.connect(_do_answer)
	else:
		# Ask LLM whether to answer
		_llm_decide_answer(number)

func _on_call_started(number: String) -> void:
	_log("📞 Call active with %s" % number)
	_in_call = true
	_active_call_id = _get_active_call_id()

	# Route audio through earpiece for STT pipeline
	telephony.set_speaker(false)

	# Greet the caller via TTS
	var greeting = "Hello, I'm handling calls for the user right now. How can I help you?"
	_speak(greeting)
	_transcript.append({"role": "assistant", "content": greeting})

	# Start listening
	if voice:
		voice.call("start_listening")  # voice_manager.gd API

func _on_call_ended(duration_sec: int) -> void:
	_log("📞 Call ended after %ds" % duration_sec)
	_in_call        = false
	_active_call_id = ""
	_transcript     = []

	if voice:
		voice.call("stop_listening")

	# Cancel pending auto-answer timer if it exists
	if _answer_timer:
		_answer_timer = null

# ════════════════════════════════════════════════════════════════════════════
# STT → LLM → TTS  LOOP
# ════════════════════════════════════════════════════════════════════════════

func _on_speech_result(text: String) -> void:
	if not _in_call or text.strip_edges().is_empty():
		return

	_log("👂 Caller said: %s" % text)
	_transcript.append({"role": "user", "content": text})
	emit_signal("call_transcript_updated", _transcript)

	# Stop listening while we think (barge-in handled by voice_manager)
	if voice:
		voice.call("stop_listening")

	# Ask LLM for response
	var reply = await _llm_respond(text)
	if reply.is_empty():
		reply = "Sorry, could you say that again?"

	_transcript.append({"role": "assistant", "content": reply})
	_speak(reply)

	# Resume listening after TTS
	await get_tree().create_timer(0.5).timeout
	if _in_call and voice:
		voice.call("start_listening")

# ════════════════════════════════════════════════════════════════════════════
# TELEGRAM COMMAND HANDLER
# Wire this into your Telegram bot command dispatcher
# ════════════════════════════════════════════════════════════════════════════

func handle_telegram_command(cmd: String, args: String) -> String:
	match cmd:
		"/call":
			if args.strip_edges().is_empty():
				return "Usage: /call +61412345678"
			var result = telephony.make_call(args.strip_edges())
			return "📞 Calling %s → %s" % [args.strip_edges(), result]

		"/answer":
			var result = telephony.answer_call()
			return "📞 Answer → %s" % result

		"/hangup":
			var result = telephony.end_call()
			return "📞 Hang up → %s" % result

		"/speaker":
			var on = args.strip_edges().to_lower() == "on"
			var result = telephony.set_speaker(on)
			return "🔊 Speaker %s → %s" % [("on" if on else "off"), result]

		"/mute":
			var mute = args.strip_edges().to_lower() != "off"
			var result = telephony.set_mute(mute)
			return "🎤 Mic %s → %s" % [("muted" if mute else "unmuted"), result]

		"/calls":
			var calls = telephony._plugin.listActiveCalls() if telephony._plugin else "[]"
			return "📋 Active calls: %s" % calls

		"/ghost":
			var bound = telephony.is_default_dialer()
			var svc   = telephony._plugin.isInCallServiceBound() if telephony._plugin else false
			return "👻 Default dialer: %s | InCallService: %s" % [bound, svc]

		_:
			return ""   # not a telephony command — let other handlers process

# ════════════════════════════════════════════════════════════════════════════
# LLM CALLS (async)
# ════════════════════════════════════════════════════════════════════════════

func _llm_decide_answer(number: String) -> void:
	# Quick decision: answer or reject?
	# Replace with your actual LLM call pattern
	var prompt = "Incoming call from %s. Should I answer? Reply YES or NO and one sentence reason." % number
	var decision = await _llm_call(prompt, [])

	var answer = decision.to_upper().begins_with("YES")
	emit_signal("agent_decision", ("answer" if answer else "reject"), decision)

	if answer:
		_do_answer()
	else:
		_log("LLM rejected call: %s" % decision)
		telephony.end_call()

func _llm_respond(caller_text: String) -> String:
	return await _llm_call(caller_text, _transcript)

func _llm_call(user_text: String, history: Array) -> String:
	# ── Replace this stub with your actual LLM integration ──────────────
	# For Anthropic API (via builtin_tools or HTTPClient):
	#
	#   var messages = history.duplicate()
	#   messages.append({"role": "user", "content": user_text})
	#   var response = await anthropic_client.complete(
	#       model    = "claude-sonnet-4-20250514",
	#       system   = llm_system_prompt,
	#       messages = messages,
	#       max_tokens = 150
	#   )
	#   return response
	#
	# For local llama.cpp via llama_manager (your existing integration):
	#
	#   return await llama_manager.generate(user_text, llm_system_prompt)
	#
	push_warning("GhostCallAgent: _llm_call stub — wire your LLM here")
	return ""

# ════════════════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════════════════

func _do_answer() -> void:
	var result = telephony.answer_call()
	_log("Answer result: %s" % result)

func _speak(text: String) -> void:
	if voice and voice.has_method("speak"):
		voice.speak(text)
	else:
		_log("TTS: %s" % text)

func _get_active_call_id() -> String:
	if not telephony or not telephony._plugin:
		return ""
	var calls_json = telephony._plugin.listActiveCalls()
	# Parse first call ID from JSON array
	# "[{\"id\":\"12345\",..." → "12345"
	var regex = RegEx.new()
	regex.compile('"id":"([^"]+)"')
	var match = regex.search(calls_json)
	return match.get_string(1) if match else ""

func _log(msg: String) -> void:
	print("[GhostCallAgent] %s" % msg)
