## telephony_manager.gd
## GDScript bridge for GhostTelephony Java class.
## Mirrors the pattern of voice_manager.gd — plugin signals → GDScript state machine.
##
## Usage:
##   var tel = TelephonyManager.new()
##   tel.initialise(ghost_kv_plugin_instance)
##   tel.make_call("+61412345678")
##
## Signals you can connect to:
##   incoming_call(number: String)
##   call_started(number: String)
##   call_ended(duration_sec: int)
##   call_missed(number: String)

class_name TelephonyManager
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────
signal incoming_call(number: String)
signal call_started(number: String)
signal call_ended(duration_sec: int)
signal permission_denied(permission: String)

# ── State ─────────────────────────────────────────────────────────────────────
enum CallState { IDLE, RINGING, ACTIVE }

var state        : CallState = CallState.IDLE
var active_number: String    = ""

var _plugin              = null
var _signals_connected   : bool = false
var _is_android          : bool = false

# ── Init ──────────────────────────────────────────────────────────────────────

func initialise(plugin) -> void:
	_is_android = OS.has_feature("android")
	if not _is_android:
		push_warning("TelephonyManager: not on Android — all calls are no-ops")
		return
	_plugin = plugin
	_connect_signals()
	start_monitor()

func _connect_signals() -> void:
	if _plugin == null or _signals_connected:
		return
	# These must be declared in GhostKVPlugin.getPluginSignals()
	_plugin.connect("on_incoming_call", _on_incoming_call)
	_plugin.connect("on_call_started",  _on_call_started)
	_plugin.connect("on_call_ended",    _on_call_ended)
	_plugin.connect("on_permission_denied", _on_permission_denied)
	_signals_connected = true

# ── Public API ────────────────────────────────────────────────────────────────

## Place an outgoing call. Returns result string from Java layer.
func make_call(number: String) -> String:
	if not _is_android or _plugin == null:
		push_warning("make_call: no plugin (desktop?)")
		return "error:no_plugin"
	var result = _plugin.makeCall(number)
	_log("make_call(%s) → %s" % [number, result])
	return result

## Answer a ringing call (Android 8+).
func answer_call() -> String:
	if not _is_android or _plugin == null:
		return "error:no_plugin"
	var result = _plugin.answerCall()
	_log("answer_call() → %s" % result)
	return result

## End or reject current call (Android 9+).
func end_call() -> String:
	if not _is_android or _plugin == null:
		return "error:no_plugin"
	var result = _plugin.endCall()
	_log("end_call() → %s" % result)
	return result

## Mute / unmute mic.
func set_mute(mute: bool) -> String:
	if not _is_android or _plugin == null:
		return "error:no_plugin"
	return _plugin.setMicMute(mute)

## Toggle speakerphone.
func set_speaker(on: bool) -> String:
	if not _is_android or _plugin == null:
		return "error:no_plugin"
	return _plugin.setSpeakerphone(on)

## Start listening for call state changes.
func start_monitor() -> String:
	if not _is_android or _plugin == null:
		return "error:no_plugin"
	return _plugin.startCallMonitor()

## Stop listening.
func stop_monitor() -> String:
	if not _is_android or _plugin == null:
		return "error:no_plugin"
	return _plugin.stopCallMonitor()

## Raw state string from Java: "idle" | "ringing" | "offhook"
func get_raw_state() -> String:
	if not _is_android or _plugin == null:
		return "idle"
	return _plugin.getCallState()

## Whether this app is the default dialer (needed for full InCallService control).
func is_default_dialer() -> bool:
	if not _is_android or _plugin == null:
		return false
	return _plugin.isDefaultDialer()

## Prompt user to set app as default dialer.
func request_default_dialer() -> void:
	if _is_android and _plugin != null:
		_plugin.requestDefaultDialer()

# ── Signal Handlers ───────────────────────────────────────────────────────────

func _on_incoming_call(number: String) -> void:
	state          = CallState.RINGING
	active_number  = number
	_log("← RINGING from %s" % number)
	emit_signal("incoming_call", number)

func _on_call_started(number: String) -> void:
	state          = CallState.ACTIVE
	active_number  = number
	_log("← ACTIVE with %s" % number)
	emit_signal("call_started", number)

func _on_call_ended(duration_str: String) -> void:
	var duration   = int(duration_str)
	_log("← ENDED  duration=%ds" % duration)
	state          = CallState.IDLE
	active_number  = ""
	emit_signal("call_ended", duration)

func _on_permission_denied(permission: String) -> void:
	push_warning("TelephonyManager: permission denied — %s" % permission)
	emit_signal("permission_denied", permission)

# ── Utility ───────────────────────────────────────────────────────────────────

func _log(msg: String) -> void:
	print("[TelephonyManager] %s" % msg)
