extends Node

## Smart tool selector — categorizes tools, builds keyword index, scores per query.
## Sits between ReactLoop and ToolDispatch to reduce 410+ tool prompts to ~30-50.

# Category keyword maps: category -> trigger words
const _CATEGORY_KEYWORDS: Dictionary = {
	"communication": ["call", "sms", "message", "phone", "contact", "text", "whatsapp", "telegram", "dial"],
	"system": ["battery", "wifi", "location", "device", "bluetooth", "nfc", "screen", "brightness", "volume", "network"],
	"media": ["voice", "camera", "music", "photo", "speak", "listen", "tts", "stt", "audio", "media", "flashlight"],
	"files": ["file", "read", "write", "directory", "folder", "open", "url", "clipboard", "share"],
	"device": ["app", "alarm", "calendar", "notification", "timer", "wake", "command", "run", "python", "toast", "vibrate"]
}

# Tools that are ALWAYS included
const _CORE_TOOLS: PackedStringArray = [
	"remember", "recall", "relate", "search_memory", "list_entities",
	"forget", "forget_fact", "export_memory",
	"calculator", "web_search", "web_read"
]

# Tool -> category mapping for builtins
var _builtin_categories: Dictionary = {}
# MCP server -> set of tool names
var _mcp_server_tools: Dictionary = {}
# Tool name -> description (cached)
var _tool_descriptions: Dictionary = {}
# Tool name -> tokens (split by _)
var _tool_name_tokens: Dictionary = {}

var _max_tools: int = 50
var _enabled: bool = true


func _ready() -> void:
	# Build builtin category map
	_builtin_categories = {
		# Communication
		"send_sms": "communication", "make_call": "communication", "ghost_call": "communication",
		"get_contacts": "communication", "read_sms": "communication", "answer_call": "communication",
		"end_call": "communication", "get_call_log": "communication", "get_call_state": "communication",
		"set_call_mute": "communication", "set_call_speaker": "communication",
		"start_call_monitor": "communication", "stop_call_monitor": "communication",
		"auto_answer_call": "communication", "send_whatsapp": "communication",
		"send_telegram": "communication", "add_contact": "communication",
		"add_trusted_contact": "communication", "list_trusted_contacts": "communication",
		# System
		"get_battery": "system", "get_wifi_info": "system", "get_location": "system",
		"get_bluetooth_devices": "system", "get_nfc_status": "system",
		"get_screen_timeout": "system", "set_screen_timeout": "system",
		"get_brightness": "system", "set_brightness": "system",
		"get_volume": "system", "set_volume": "system",
		"wake_screen": "system",
		# Media
		"speak": "media", "start_listening": "media", "open_camera": "media",
		"media_control": "media", "toggle_flashlight": "media",
		# Files
		"file_read": "files", "write_file": "files", "list_directory": "files",
		"open_url": "files", "read_clipboard": "files", "write_clipboard": "files",
		"share_text": "files",
		# Device
		"open_app": "device", "list_apps": "device", "set_alarm": "device",
		"set_timer": "device", "get_calendar_events": "device",
		"create_calendar_event": "device", "get_notifications": "device",
		"run_command": "device", "run_python": "device",
		"toast": "device", "vibrate": "device",
	}

	# Load settings
	var session := Engine.get_singleton("SessionManager") as Node
	if session:
		var settings: Dictionary = session.load_settings()
		_max_tools = settings.get("tool_selection_max", 50)
		_enabled = settings.get("tool_selection_enabled", true)


## Called by ToolDispatch when a tool is registered
func on_tool_registered(tool_name: String, server_name: String, _client: Node) -> void:
	# Cache name tokens for scoring
	var tokens := tool_name.split("_")
	var lower_tokens: PackedStringArray = []
	for t in tokens:
		lower_tokens.append(t.to_lower())
	_tool_name_tokens[tool_name] = lower_tokens

	# Track MCP server grouping
	if server_name != "builtin" and server_name != "memory":
		if not _mcp_server_tools.has(server_name):
			_mcp_server_tools[server_name] = []
		_mcp_server_tools[server_name].append(tool_name)

	# Cache description
	var dispatch := Engine.get_singleton("ToolDispatch") as Node
	if dispatch and dispatch.has_method("get_tool_description"):
		_tool_descriptions[tool_name] = dispatch.get_tool_description(tool_name)


## Called by ToolDispatch when MCP tools are unregistered
func on_tools_unregistered(tool_names: Array) -> void:
	for t in tool_names:
		_builtin_categories.erase(t)
		_tool_descriptions.erase(t)
		_tool_name_tokens.erase(t)
	# Rebuild MCP server tracking
	for server in _mcp_server_tools:
		var remaining: Array = []
		for t in _mcp_server_tools[server]:
			if tool_names.has(t):
				remaining.append(t)
		_mcp_server_tools[server] = remaining


## Main selection method — returns top N tool names for a query
func select_tools(query: String) -> PackedStringArray:
	if not _enabled:
		# Return all tools if disabled
		var dispatch := Engine.get_singleton("ToolDispatch") as Node
		if dispatch:
			var all: Dictionary = dispatch.get_registered_tools()
			var names: PackedStringArray = []
			for n in all:
				names.append(n)
			return names
		return []

	var query_lower := query.to_lower()
	var query_words: PackedStringArray = []
	for w in query_lower.split(" "):
		if w.length() > 1:
			query_words.append(w)

	var scores: Dictionary = {}  # tool_name -> score
	var dispatch := Engine.get_singleton("ToolDispatch") as Node
	if not dispatch:
		return []

	var all_tools: Dictionary = dispatch.get_registered_tools()

	for tool_name in all_tools:
		var score: int = 0

		# Core tools always included
		if tool_name in _CORE_TOOLS:
			scores[tool_name] = 1000
			continue

		# Tool name token match (+50 per match)
		if _tool_name_tokens.has(tool_name):
			var tokens: PackedStringArray = _tool_name_tokens[tool_name]
			for qw in query_words:
				for t in tokens:
					if t == qw or t.begins_with(qw) or qw.begins_with(t):
						if t.length() >= 2 and qw.length() >= 2:
							score += 50

		# Description substring match (+20 per match)
		var desc: String = _tool_descriptions.get(tool_name, "").to_lower()
		if not desc.is_empty():
			for qw in query_words:
				if qw in desc:
					score += 20

		# Category keyword match (+30)
		var category: String = _get_category(tool_name)
		if not category.is_empty() and _CATEGORY_KEYWORDS.has(category):
			var keywords: Array = _CATEGORY_KEYWORDS[category]
			for qw in query_words:
				for kw in keywords:
					if qw == kw or qw.begins_with(kw) or kw.begins_with(qw):
						score += 30
						break

		if score > 0:
			scores[tool_name] = score

	# Sort by score descending, take top N
	var sorted := _sort_by_score(scores)

	# Always include core tools
	var result: PackedStringArray = []
	var core_added: Dictionary = {}
	for c in _CORE_TOOLS:
		if all_tools.has(c):
			result.append(c)
			core_added[c] = true

	# Add scored tools
	for entry in sorted:
		if result.size() >= _max_tools:
			break
		var name: String = entry["name"]
		if not core_added.has(name):
			result.append(name)

	# Minimum 5 tools — if too few, add from highest-scoring category
	if result.size() < 5:
		var best_category := _best_category(query_words)
		if not best_category.is_empty():
			for tool_name in all_tools:
				if result.size() >= 10:
					break
				if not result.has(tool_name) and _get_category(tool_name) == best_category:
					result.append(tool_name)

	push_warning("ToolSelector: selected %d/%d tools for query '%s'" % [result.size(), all_tools.size(), query_left(60, query)])
	return result


## Get category for a tool
func _get_category(tool_name: String) -> String:
	if _builtin_categories.has(tool_name):
		return _builtin_categories[tool_name]
	# MCP tools: category is "mcp:{server}"
	for server in _mcp_server_tools:
		if tool_name in _mcp_server_tools[server]:
			return "mcp:" + server
	return ""


## Find best matching category for degenerate queries
func _best_category(query_words: PackedStringArray) -> String:
	var best_cat: String = ""
	var best_score: int = 0
	for cat in _CATEGORY_KEYWORDS:
		var keywords: Array = _CATEGORY_KEYWORDS[cat]
		var cat_score: int = 0
		for qw in query_words:
			for kw in keywords:
				if qw == kw or qw.begins_with(kw) or kw.begins_with(qw):
					cat_score += 1
		if cat_score > best_score:
			best_score = cat_score
			best_cat = cat
	return best_cat


## Sort scores dict into array of {name, score} descending
func _sort_by_score(scores: Dictionary) -> Array:
	var entries: Array = []
	for name in scores:
		entries.append({"name": name, "score": scores[name]})
	entries.sort_custom(_compare_score)
	return entries


func _compare_score(a: Dictionary, b: Dictionary) -> bool:
	return a["score"] > b["score"]


## Truncate string for logging
func query_left(max_len: int, s: String) -> String:
	if s.length() <= max_len:
		return s
	return s.left(max_len) + "..."
