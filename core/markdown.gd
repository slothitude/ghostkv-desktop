extends Node

# Syntax highlighting colors
const COLOR_KEYWORD := "#c678dd"
const COLOR_STRING := "#98c379"
const COLOR_COMMENT := "#5c6370"
const COLOR_NUMBER := "#d19a66"
const COLOR_FUNCTION := "#61afef"
const COLOR_TYPE := "#e5c07b"
const COLOR_OPERATOR := "#56b6c2"
const COLOR_PLAIN := "#abb2bf"
const COLOR_BG := "#0d0d1a"
const COLOR_LANG_LABEL := "#555570"

# Language keyword sets
var _lang_keywords: Dictionary = {
	"python": ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "as", "async", "await", "yield", "lambda", "pass", "break", "continue", "raise", "del", "global", "nonlocal", "assert", "in", "not", "and", "or", "is", "None", "True", "False", "print", "self", "super"],
	"gdscript": ["func", "class", "extends", "var", "const", "enum", "signal", "await", "return", "if", "elif", "else", "for", "while", "match", "break", "continue", "pass", "self", "super", "true", "false", "null", "void", "int", "float", "bool", "String", "Vector2", "Vector3", "Array", "Dictionary", "Node", "preload", "load", "export", "onready", "static", "class_name"],
	"javascript": ["function", "class", "const", "let", "var", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "try", "catch", "finally", "throw", "new", "this", "async", "await", "yield", "import", "export", "from", "default", "typeof", "instanceof", "in", "of", "null", "undefined", "true", "false", "console"],
	"typescript": ["function", "class", "const", "let", "var", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "try", "catch", "finally", "throw", "new", "this", "async", "await", "yield", "import", "export", "from", "default", "typeof", "instanceof", "in", "of", "null", "undefined", "true", "false", "interface", "type", "enum", "implements", "extends", "public", "private", "protected", "readonly", "abstract", "as", "is", "keyof", "never", "unknown", "any", "void", "string", "number", "boolean"],
	"rust": ["fn", "let", "mut", "const", "struct", "enum", "impl", "trait", "pub", "use", "mod", "crate", "self", "super", "return", "if", "else", "for", "while", "loop", "match", "break", "continue", "where", "as", "in", "ref", "move", "async", "await", "unsafe", "extern", "type", "static", "dyn", "true", "false", "Some", "None", "Ok", "Err", "Vec", "String", "Box", "Option", "Result"],
	"bash": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "return", "exit", "echo", "export", "source", "alias", "local", "readonly", "set", "unset", "shift", "true", "false"],
	"json": [],
	"sql": ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AND", "OR", "NOT", "NULL", "IS", "IN", "BETWEEN", "LIKE", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "AS", "DISTINCT", "COUNT", "SUM", "AVG", "MAX", "MIN", "UNION", "ALL", "EXISTS", "CASE", "WHEN", "THEN", "ELSE", "END", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "AUTO_INCREMENT"],
	"gd": ["func", "class", "extends", "var", "const", "enum", "signal", "await", "return", "if", "elif", "else", "for", "while", "match", "break", "continue", "pass", "self", "super", "true", "false", "null", "void", "int", "float", "bool", "String", "Vector2", "Vector3", "Array", "Dictionary", "Node"],
}

func to_bbcode(text: String) -> String:
	return _convert(text)

func _convert(text: String) -> String:
	var result := text

	# Protect code blocks first — extract and replace with placeholders
	var code_blocks: Array = []  # Array of {lang, code, placeholder}
	var placeholder_idx := 0
	result = _extract_code_blocks(result, code_blocks, placeholder_idx)

	# Process inline markdown (no code blocks to accidentally match)
	result = _process_inline(result)

	# Restore code blocks with rendered BBCode
	for block in code_blocks:
		var rendered := _render_code_block(block.lang, block.code)
		result = result.replace(block.placeholder, rendered)

	return result

func _extract_code_blocks(text: String, blocks: Array, idx: int) -> String:
	var result := text
	var regex := RegEx.new()
	regex.compile("```(\\w*)\\n([\\s\\S]*?)```")
	var matches := regex.search_all(result)
	# Process in reverse to keep positions valid
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var lang: String = m.get_string(1).to_lower()
		var code: String = m.get_string(2)
		# Trim trailing newline from code content
		if code.ends_with("\n"):
			code = code.substr(0, code.length() - 1)
		var placeholder := "[CODEBLOCK_%d]" % idx
		idx += 1
		blocks.append({"lang": lang, "code": code, "placeholder": placeholder})
		result = result.replace(m.get_string(0), placeholder)
	return result

func _render_code_block(lang: String, code: String) -> String:
	# Escape BBCode special characters in code
	var escaped := _escape_bbcode(code)

	# Apply syntax highlighting if we know the language
	var highlighted: String
	if lang != "" and _lang_keywords.has(lang):
		highlighted = _highlight_syntax(escaped, lang)
	else:
		highlighted = "[color=%s]%s[/color]" % [COLOR_PLAIN, escaped]

	# Build the block
	var parts: PackedStringArray = []

	# Language label
	if lang != "":
		var display_lang := _display_name(lang)
		parts.append("[color=%s][font_size=10]%s[/font_size][/color]" % [COLOR_LANG_LABEL, display_lang])

	# Code content with monospace and background
	parts.append("[bgcolor=%s][font_size=12][color=%s]%s[/color][/font_size][/bgcolor]" % [COLOR_BG, COLOR_PLAIN, highlighted])

	return "\n".join(parts)

func _display_name(lang: String) -> String:
	var names: Dictionary = {
		"py": "Python",
		"python": "Python",
		"gdscript": "GDScript",
		"gd": "GDScript",
		"javascript": "JavaScript",
		"js": "JavaScript",
		"typescript": "TypeScript",
		"ts": "TypeScript",
		"rust": "Rust",
		"rs": "Rust",
		"bash": "Bash",
		"sh": "Shell",
		"shell": "Shell",
		"json": "JSON",
		"sql": "SQL",
		"html": "HTML",
		"css": "CSS",
		"yaml": "YAML",
		"yml": "YAML",
		"toml": "TOML",
		"xml": "XML",
		"markdown": "Markdown",
		"md": "Markdown",
		"c": "C",
		"cpp": "C++",
		"java": "Java",
		"go": "Go",
		"ruby": "Ruby",
		"rb": "Ruby",
		"php": "PHP",
		"swift": "Swift",
		"kotlin": "Kotlin",
		"kt": "Kotlin",
	}
	return names.get(lang, lang.capitalize())

func _escape_bbcode(text: String) -> String:
	var result := text
	# Escape [ and ] that aren't our BBCode tags
	result = result.replace("[", "[lb]")
	result = result.replace("]", "[rb]")
	return result

func _highlight_syntax(code: String, lang: String) -> String:
	var result := code
	var keywords: Array = _lang_keywords.get(lang, [])

	# 1. Extract strings → protect from keyword matching inside them
	#    Use sub() with colored replacement in one pass
	var string_regex := RegEx.new()
	string_regex.compile("(\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"[^\"\\n]*\"|'[^'\\n]*')")
	result = string_regex.sub(result, "[color=%s]$1[/color]" % COLOR_STRING, true)

	# 2. Extract comments → protect from keyword matching
	var comment_pattern := "(#[^\\n]*)"  # default: hash comments
	if lang == "sql":
		comment_pattern = "(--[^\\n]*)"
	elif lang not in ["python", "py", "bash", "sh", "shell", "gdscript", "gd"]:
		comment_pattern = "(//[^\\n]*)"
	var comment_regex := RegEx.new()
	comment_regex.compile(comment_pattern)
	result = comment_regex.sub(result, "[color=%s]$1[/color]" % COLOR_COMMENT, true)

	# 3. Highlight keywords (whole word only)
	if keywords.size() > 0:
		var kw_pattern := "\\b(" + "|".join(keywords) + ")\\b"
		var kw_regex := RegEx.new()
		kw_regex.compile(kw_pattern)
		result = kw_regex.sub(result, "[color=%s]$1[/color]" % COLOR_KEYWORD, true)

	# 4. Highlight numbers
	var num_regex := RegEx.new()
	num_regex.compile("\\b(\\d+\\.?\\d*)\\b")
	result = num_regex.sub(result, "[color=%s]$1[/color]" % COLOR_NUMBER, true)

	# 5. Highlight function calls (word followed by parenthesis)
	var func_regex := RegEx.new()
	func_regex.compile("\\b([a-zA-Z_][a-zA-Z0-9_]*)\\(")
	result = func_regex.sub(result, "[color=%s]$1[/color](" % COLOR_FUNCTION, true)

	return result

func _process_inline(text: String) -> String:
	var result := text

	# Inline code (`...`) — must process before other inline patterns
	var inline_code_regex := RegEx.new()
	inline_code_regex.compile("`([^`]+)`")
	result = inline_code_regex.sub(result, "[bgcolor=%s][color=%s][font_size=12] $1 [/font_size][/color][/bgcolor]" % [COLOR_BG, "#c8d0e0"], true)

	# Bold (**...** or __...__)
	var bold_regex := RegEx.new()
	bold_regex.compile("\\*\\*(.+?)\\*\\*")
	result = bold_regex.sub(result, "[b]$1[/b]", true)

	var bold2_regex := RegEx.new()
	bold2_regex.compile("__(.+?)__")
	result = bold2_regex.sub(result, "[b]$1[/b]", true)

	# Italic (*...* or _..._) — but not inside bold
	var italic_regex := RegEx.new()
	italic_regex.compile("(?<!\\*)\\*(?<!\\*)(.+?)(?<!\\*)\\*(?!\\*)")
	result = italic_regex.sub(result, "[i]$1[/i]", true)

	# Headers (# ## ###)
	var h3_regex := RegEx.new()
	h3_regex.compile("^### (.+)$", 2)
	result = h3_regex.sub(result, "[b][font_size=16]$1[/font_size][/b]", true)

	var h2_regex := RegEx.new()
	h2_regex.compile("^## (.+)$", 2)
	result = h2_regex.sub(result, "[b][font_size=18]$1[/font_size][/b]", true)

	var h1_regex := RegEx.new()
	h1_regex.compile("^# (.+)$", 2)
	result = h1_regex.sub(result, "[b][font_size=22]$1[/font_size][/b]", true)

	# Unordered lists (- item or * item)
	var list_regex := RegEx.new()
	list_regex.compile("^[\\-\\*] (.+)$", 2)
	result = list_regex.sub(result, "  [color=#6c63ff]•[/color] $1", true)

	# Numbered lists (1. item)
	var nlist_regex := RegEx.new()
	nlist_regex.compile("^(\\d+)\\. (.+)$", 2)
	result = nlist_regex.sub(result, "  [color=#6c63ff]$1.[/color] $2", true)

	# Links [text](url)
	var link_regex := RegEx.new()
	link_regex.compile("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	result = link_regex.sub(result, "[color=#6c63ff][url=$2]$1[/url][/color]", true)

	return result
