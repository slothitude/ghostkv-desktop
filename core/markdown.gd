extends Node

static func to_bbcode(text: String) -> String:
	var result := text

	# Code blocks (```...```) — must process before inline code
	var code_block_regex := RegEx.new()
	code_block_regex.compile("```(\\w*)\\n([\\s\\S]*?)```")
	result = code_block_regex.sub(result, "[code][color=#6c63ff]$2[/color][/code]", true)

	# Inline code (`...`)
	var inline_code_regex := RegEx.new()
	inline_code_regex.compile("`([^`]+)`")
	result = inline_code_regex.sub(result, "[color=#6c63ff]$1[/color]", true)

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
	result = list_regex.sub(result, "  • $1", true)

	# Numbered lists (1. item)
	var nlist_regex := RegEx.new()
	nlist_regex.compile("^\\d+\\. (.+)$", 2)
	result = nlist_regex.sub(result, "  • $1", true)

	# Links [text](url)
	var link_regex := RegEx.new()
	link_regex.compile("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	result = link_regex.sub(result, "[color=#6c63ff][url=$2]$1[/url][/color]", true)

	return result
