extends Node

## Graph memory store for GhostKV.
## Persists entities, facts, and relations as JSON in user://memory.db.json.
## Registers 8 tools with ToolDispatch and provides auto_recall() for ReactLoop.

const DB_PATH := "user://memory.db.json"
const VAULT_DIR := "user://vault"

var _db: Dictionary = {}

func _ready() -> void:
	_load_db()
	_register_tools()

# ── Persistence ──────────────────────────────────────────────────────────────

func _load_db() -> void:
	if FileAccess.file_exists(DB_PATH):
		var f := FileAccess.open(DB_PATH, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				_db = json.data
				return
	_db = {"entities": {}}

func _save_db() -> void:
	var f := FileAccess.open(DB_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_db, "\t"))

func _entity_key(name: String) -> String:
	return name.to_lower().strip_edges()

func _now() -> String:
	return Time.get_datetime_string_from_system()

# ── Tool Registration ────────────────────────────────────────────────────────

func _register_tools() -> void:
	var td := Engine.get_singleton("ToolDispatch") as Node
	if not td:
		return
	td.register_tool("remember", "memory", self)
	td.register_tool("recall", "memory", self)
	td.register_tool("relate", "memory", self)
	td.register_tool("search_memory", "memory", self)
	td.register_tool("list_entities", "memory", self)
	td.register_tool("forget", "memory", self)
	td.register_tool("forget_fact", "memory", self)
	td.register_tool("export_memory", "memory", self)

func get_tool_description(tool_name: String) -> String:
	match tool_name:
		"remember":
			return "Save a fact about an entity. Args: \"entity\", \"key\", \"value\""
		"recall":
			return "Get all facts about an entity. Args: \"entity\""
		"relate":
			return "Create a relationship from entity_a to entity_b. Args: \"entity_a\", \"relation\", \"entity_b\""
		"search_memory":
			return "Search entities and facts by keyword. Args: \"query\""
		"list_entities":
			return "List all entities, optionally filtered by type. Args: \"type\" (optional)"
		"forget":
			return "Delete an entity and all its data. Args: \"entity\""
		"forget_fact":
			return "Delete a specific fact from an entity. Args: \"entity\", \"key\""
		"export_memory":
			return "Export all memory as Obsidian-flavored markdown files. Args: none"
		_:
			return ""

func call_tool(tool_name: String, args: Dictionary) -> String:
	var input: String = args.get("input", "")
	var a0: String = args.get("arg0", "")
	var a1: String = args.get("arg1", "")
	var a2: String = args.get("arg2", "")

	# Also accept named params
	var entity: String = args.get("entity", a0 if a0 else input)
	var key: String = args.get("key", a1)
	var value: String = args.get("value", a2)
	var relation: String = args.get("relation", a1)
	var target: String = args.get("entity_b", args.get("target", a2))
	var query: String = args.get("query", a0 if a0 else input)
	var type_filter: String = args.get("type", a0 if a0 else input)

	match tool_name:
		"remember":
			return _tool_remember(entity, key, value)
		"recall":
			return _tool_recall(entity)
		"relate":
			return _tool_relate(entity, relation, target)
		"search_memory":
			return _tool_search(query)
		"list_entities":
			return _tool_list_entities(type_filter)
		"forget":
			return _tool_forget(entity)
		"forget_fact":
			return _tool_forget_fact(entity, key)
		"export_memory":
			return _tool_export()
	return "Error: Unknown memory tool '%s'" % tool_name

# ── Tool Implementations ─────────────────────────────────────────────────────

func _tool_remember(entity_name: String, key: String, value: String) -> String:
	if entity_name.is_empty() or key.is_empty() or value.is_empty():
		return "Error: remember requires entity, key, and value"

	var ek := _entity_key(entity_name)
	if not _db["entities"].has(ek):
		_db["entities"][ek] = {
			"name": entity_name.strip_edges(),
			"type": "thing",
			"created": _now(),
			"facts": {},
			"relations": []
		}

	var entity: Dictionary = _db["entities"][ek]
	entity["facts"][key.to_lower().strip_edges()] = {
		"key": key.strip_edges(),
		"value": value,
		"created": _now()
	}
	_save_db()
	return "Remembered: %s %s = %s" % [entity["name"], key.strip_edges(), value]

func _tool_recall(entity_name: String) -> String:
	if entity_name.is_empty():
		return "Error: recall requires an entity name"

	var ek := _entity_key(entity_name)
	if not _db["entities"].has(ek):
		return "No memory found for '%s'" % entity_name

	var entity: Dictionary = _db["entities"][ek]
	var lines: PackedStringArray = []
	lines.append("== %s (%s) ==" % [entity["name"], entity.get("type", "thing")])

	var facts: Dictionary = entity.get("facts", {})
	if facts.is_empty():
		lines.append("No facts recorded.")
	else:
		for fk in facts:
			var fact: Dictionary = facts[fk]
			lines.append("  %s: %s" % [fact["key"], fact["value"]])

	var relations: Array = entity.get("relations", [])
	if relations.size() > 0:
		lines.append("Relations:")
		for rel in relations:
			lines.append("  - %s %s" % [rel["relation"], rel["target"]])

	return "\n".join(lines)

func _tool_relate(entity_a: String, relation: String, entity_b: String) -> String:
	if entity_a.is_empty() or relation.is_empty() or entity_b.is_empty():
		return "Error: relate requires entity_a, relation, and entity_b"

	var ek_a := _entity_key(entity_a)
	var ek_b := _entity_key(entity_b)

	# Ensure both entities exist
	for ename in [entity_a, entity_b]:
		var ek := _entity_key(ename)
		if not _db["entities"].has(ek):
			_db["entities"][ek] = {
				"name": ename.strip_edges(),
				"type": "thing",
				"created": _now(),
				"facts": {},
				"relations": []
			}

	var entity: Dictionary = _db["entities"][ek_a]
	var relations: Array = entity.get("relations", [])

	# Check for duplicate
	for rel in relations:
		if rel["relation"] == relation and _entity_key(rel["target"]) == ek_b:
			return "Relation already exists: %s %s %s" % [entity_a, relation, entity_b]

	relations.append({
		"relation": relation,
		"target": entity_b.strip_edges(),
		"created": _now()
	})
	entity["relations"] = relations
	_save_db()
	return "Related: %s --%s--> %s" % [entity_a, relation, entity_b]

func _tool_search(query: String) -> String:
	if query.is_empty():
		return "Error: search_memory requires a query string"

	var q := query.to_lower()
	var results: PackedStringArray = []
	var entities: Dictionary = _db["entities"]

	for ek in entities:
		var entity: Dictionary = entities[ek]
		var matched := false
		var match_reasons: PackedStringArray = []

		# Check entity name
		if ek.find(q) >= 0:
			matched = true
			match_reasons.append("name match")

		# Check facts
		for fk in entity.get("facts", {}):
			var fact: Dictionary = entity["facts"][fk]
			if fk.find(q) >= 0 or fact["value"].to_lower().find(q) >= 0:
				matched = true
				match_reasons.append("fact: %s=%s" % [fact["key"], fact["value"]])

		# Check relations
		for rel in entity.get("relations", []):
			if rel["relation"].to_lower().find(q) >= 0 or _entity_key(rel["target"]).find(q) >= 0:
				matched = true
				match_reasons.append("relation: %s %s" % [rel["relation"], rel["target"]])

		if matched:
			results.append("- %s: %s" % [entity["name"], ", ".join(match_reasons)])

	if results.is_empty():
		return "No results for '%s'" % query
	return "Found %d result(s):\n%s" % [results.size(), "\n".join(results)]

func _tool_list_entities(type_filter: String) -> String:
	var entities: Dictionary = _db["entities"]
	if entities.is_empty():
		return "No entities in memory."

	var lines: PackedStringArray = []
	var filter := type_filter.to_lower().strip_edges()

	for ek in entities:
		var entity: Dictionary = entities[ek]
		var etype: String = entity.get("type", "thing")
		if filter != "" and etype != filter:
			continue
		var fact_count: int = entity.get("facts", {}).size()
		var rel_count: int = entity.get("relations", []).size()
		lines.append("- %s [%s] (%d facts, %d relations)" % [entity["name"], etype, fact_count, rel_count])

	if lines.is_empty():
		if filter != "":
			return "No entities of type '%s'" % filter
		return "No entities in memory."
	return "\n".join(lines)

func _tool_forget(entity_name: String) -> String:
	if entity_name.is_empty():
		return "Error: forget requires an entity name"

	var ek := _entity_key(entity_name)
	if not _db["entities"].has(ek):
		return "No entity '%s' found to forget" % entity_name

	var entity: Dictionary = _db["entities"][ek]
	_db["entities"].erase(ek)

	# Also remove relations pointing to this entity
	var name_lower := ek
	for other_ek in _db["entities"]:
		var other: Dictionary = _db["entities"][other_ek]
		var relations: Array = other.get("relations", [])
		var filtered: Array = []
		for rel in relations:
			if _entity_key(rel["target"]) != name_lower:
				filtered.append(rel)
		if filtered.size() != relations.size():
			other["relations"] = filtered

	_save_db()
	return "Forgot '%s' and all its data" % entity["name"]

func _tool_forget_fact(entity_name: String, key: String) -> String:
	if entity_name.is_empty() or key.is_empty():
		return "Error: forget_fact requires entity and key"

	var ek := _entity_key(entity_name)
	if not _db["entities"].has(ek):
		return "No entity '%s' found" % entity_name

	var entity: Dictionary = _db["entities"][ek]
	var fk := key.to_lower().strip_edges()
	var facts: Dictionary = entity.get("facts", {})
	if not facts.has(fk):
		return "No fact '%s' found for '%s'" % [key, entity["name"]]

	facts.erase(fk)
	_save_db()
	return "Forgot fact '%s' from '%s'" % [key, entity["name"]]

func _tool_export() -> String:
	var entities: Dictionary = _db["entities"]
	if entities.is_empty():
		return "Nothing to export — memory is empty."

	# Ensure vault directory exists
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("vault"):
		dir.make_dir("vault")

	var count := 0
	for ek in entities:
		var entity: Dictionary = entities[ek]
		var content := _entity_to_markdown(entity)
		var file_name: String = entity["name"].replace(" ", "_") + ".md"
		var path := VAULT_DIR.path_join(file_name)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(content)
			count += 1

	return "Exported %d entities to %s" % [count, VAULT_DIR]

func _entity_to_markdown(entity: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("# %s" % entity["name"])
	lines.append("")
	lines.append("**Type:** %s" % entity.get("type", "thing"))
	lines.append("**Created:** %s" % entity.get("created", "unknown"))
	lines.append("")

	# Facts table
	var facts: Dictionary = entity.get("facts", {})
	if not facts.is_empty():
		lines.append("## Facts")
		lines.append("| Key | Value |")
		lines.append("|-----|-------|")
		for fk in facts:
			var fact: Dictionary = facts[fk]
			lines.append("| %s | %s |" % [fact["key"], fact["value"]])
		lines.append("")

	# Relations with wikilinks
	var relations: Array = entity.get("relations", [])
	if not relations.is_empty():
		lines.append("## Relations")
		for rel in relations:
			lines.append("- %s [[%s]]" % [rel["relation"], rel["target"]])
		lines.append("")

	return "\n".join(lines)

# ── Auto-Recall (called by ReactLoop) ────────────────────────────────────────

func auto_recall(query: String) -> String:
	# Search memory for context relevant to the user's question.
	var settings := {}
	var session := Engine.get_singleton("SessionManager") as Node
	if session and session.has_method("load_settings"):
		var s: Dictionary = session.load_settings()
		if not s.get("memory_auto_recall", true):
			return ""

	if _db["entities"].is_empty():
		return ""

	var q := query.to_lower()
	var context_parts: PackedStringArray = []
	var entities: Dictionary = _db["entities"]

	# Extract potential entity names from the query
	var words := q.split(" ")
	for ek in entities:
		var entity: Dictionary = entities[ek]
		var matched := false

		# Check if entity name appears in query
		if q.find(ek) >= 0:
			matched = true

		# Check individual words against entity keys
		if not matched:
			for word in words:
				if word.length() >= 3 and ek.find(word) >= 0:
					matched = true
					break

		# Check if any fact values appear in query
		if not matched:
			for fk in entity.get("facts", {}):
				var fact: Dictionary = entity["facts"][fk]
				if q.find(fact["value"].to_lower()) >= 0:
					matched = true
					break

		if matched:
			var entry: String = _tool_recall(entity["name"])
			context_parts.append(entry)

	if context_parts.is_empty():
		return ""

	return "Relevant memory:\n" + "\n---\n".join(context_parts)
