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
		if client and client.has_method("call_tool"):
			var args_dict := {}
			if args.size() > 0:
				# Single string arg -> "input" key
				if args.size() == 1:
					args_dict = {"input": args[0]}
				else:
					for i in args.size():
						args_dict["arg%d" % i] = args[i]
			var result: String = await client.call_tool(tool_name, args_dict)
			tool_executed.emit(tool_name, result)
			return result
		return "Error: MCP client for '%s' not available" % tool_name

	return "Error: Unknown tool '%s'. Available tools: %s" % [tool_name, ", ".join(_tool_map.keys())]

func _parse_args(args_str: String) -> PackedStringArray:
	var result := PackedStringArray()
	if args_str.strip_edges().is_empty():
		return result

	var regex := RegEx.new()
	regex.compile('"([^"]*)"')
	for m in regex.search_all(args_str):
		result.append(m.get_string(1))
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
