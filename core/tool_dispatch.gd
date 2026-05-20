extends Node

signal tool_executed(name: String, result: String)

var _mcp_clients: Dictionary = {}  # server_name -> mcp_client node
var _tool_map: Dictionary = {}     # tool_name -> {"server": str, "client": Node}

func register_mcp_client(server_name: String, client: Node) -> void:
	_mcp_clients[server_name] = client

func unregister_mcp_client(server_name: String) -> void:
	_mcp_clients.erase(server_name)
	# Remove all tools from this server
	var to_remove: Array = []
	for tool_name in _tool_map:
		if _tool_map[tool_name]["server"] == server_name:
			to_remove.append(tool_name)
	for t in to_remove:
		_tool_map.erase(t)

func register_tool(tool_name: String, server_name: String, client: Node) -> void:
	_tool_map[tool_name] = {"server": server_name, "client": client}

func get_registered_tools() -> Dictionary:
	return _tool_map

func dispatch(tool_name: String, args_str: String) -> String:
	# Parse args: "arg1", "arg2" -> PackedStringArray
	var args := _parse_args(args_str)

	if _tool_map.has(tool_name):
		var entry: Dictionary = _tool_map[tool_name]
		var client: Node = entry["client"]
		var server: String = entry["server"]

		# Built-in tools (server == "builtin")
		if server == "builtin" and client and client.has_method("call_tool"):
			var args_dict := _args_to_dict(args)
			var result: String = await client.call_tool(tool_name, args_dict)
			tool_executed.emit(tool_name, result)
			return result

		# MCP tools
		if client and client.has_method("call_tool"):
			var args_dict := _args_to_dict(args)
			var result: String = await client.call_tool(tool_name, args_dict)
			tool_executed.emit(tool_name, result)
			return result
		return "Error: MCP client for '%s' not available" % tool_name

	return "Error: Unknown tool '%s'. Available tools: %s" % [tool_name, ", ".join(_tool_map.keys())]

func _args_to_dict(args: PackedStringArray) -> Dictionary:
	var args_dict := {}
	if args.size() > 0:
		if args.size() == 1:
			args_dict = {"input": args[0]}
		else:
			for i in args.size():
				args_dict["arg%d" % i] = args[i]
	return args_dict

func _parse_args(args_str: String) -> PackedStringArray:
	var result := PackedStringArray()
	if args_str.strip_edges().is_empty():
		return result

	# Try quoted args first: "arg1", "arg2"
	var regex := RegEx.new()
	regex.compile('"([^"]*)"')
	var matches = regex.search_all(args_str)
	if matches.size() > 0:
		for m in matches:
			result.append(m.get_string(1))
		return result

	# Fallback: unquoted comma-separated args
	for part in args_str.split(","):
		var trimmed: String = part.strip_edges()
		if not trimmed.is_empty():
			result.append(trimmed)
	return result

func build_tool_descriptions() -> String:
	var lines: PackedStringArray = []
	for tool_name in _tool_map:
		var entry: Dictionary = _tool_map[tool_name]
		var client: Node = entry["client"]
		var desc := ""
		if client and client.has_method("get_tool_description"):
			desc = client.get_tool_description(tool_name)
		if desc.is_empty():
			desc = "No description available"
		lines.append("- %s: %s" % [tool_name, desc])
	return "\n".join(lines)

func get_tool_schema(tool_name: String) -> Dictionary:
	if _tool_map.has(tool_name):
		var entry: Dictionary = _tool_map[tool_name]
		var client: Node = entry["client"]
		if client and client.has_method("get_tool_schema"):
			return client.get_tool_schema(tool_name)
	return {}

func get_tool_description(tool_name: String) -> String:
	if _tool_map.has(tool_name):
		var entry: Dictionary = _tool_map[tool_name]
		var client: Node = entry["client"]
		if client and client.has_method("get_tool_description"):
			return client.get_tool_description(tool_name)
	return ""

func build_openai_tools() -> Array:
	var tools: Array = []
	for tool_name in _tool_map:
		var entry: Dictionary = _tool_map[tool_name]
		var client: Node = entry["client"]
		var desc: String = ""
		if client and client.has_method("get_tool_description"):
			desc = client.get_tool_description(tool_name)
		if desc.is_empty():
			desc = "No description available"

		var description_only: String = desc.split("Args:")[0].strip_edges()
		var params := _parse_params_from_desc(desc)
		tools.append({
			"type": "function",
			"function": {
				"name": tool_name,
				"description": description_only,
				"parameters": params
			}
		})
	return tools

func _parse_params_from_desc(desc: String) -> Dictionary:
	var params := {"type": "object", "properties": {}}
	var required: Array = []
	var args_pos := desc.find("Args:")
	if args_pos < 0:
		return params

	var args_str: String = desc.substr(args_pos + 5).strip_edges()
	if args_str == "none":
		return params

	var regex := RegEx.new()
	regex.compile('"([^"]*)"')
	for m in regex.search_all(args_str):
		var param_name: String = m.get_string(1)
		params["properties"][param_name] = {"type": "string", "description": param_name}
		required.append(param_name)

	if required.size() > 0:
		params["required"] = required
	return params
