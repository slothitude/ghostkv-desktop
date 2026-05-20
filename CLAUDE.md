# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GhostKV Desktop is a Godot 4.6 AI agent client with a ReAct (Think → Act → Observe) loop that calls an OpenAI-compatible LLM API and dispatches tools. Runs on Windows Desktop and Android. Package name: `com.slothitude.ghostkv`.

## Export Commands

```bash
# Windows export
"C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64_console.exe" --headless --path "C:/Users/aaron/Desktop/dev/ghostkv-desktop" --export-release "Windows Desktop"

# Android export (Gradle build — requires JDK 17)
"C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64_console.exe" --headless --path "C:/Users/aaron/Desktop/dev/ghostkv-desktop" --export-release "Android"
```

Output goes to `export/` (ghostkv-desktop.exe or ghostkv-desktop.apk).

### Android Build Requirements
- **JDK 17** at `C:/Users/aaron/jdk-17/jdk-17.0.19+10` — configured in `AppData/Roaming/Godot/editor_settings-4.6.tres` (`export/android/java_sdk_path`). JDK 25 causes "Unsupported class file major version 69".
- **Android SDK** at `C:/Android/SDK`
- **Debug keystore** at `C:/Android/debug.keystore`
- Gradle build template at `res://android/build/` (extracted from Godot export templates). The `gradle_build_directory` in `export_presets.cfg` is `"res://android"` — Godot appends `/build` internally.
- `.build_version` file at `res://android/.build_version` must contain `4.6.1.stable`

### Android Plugin (GhostKVPlugin)
- Source: `android_plugin/GhostKVPlugin.java` — extends `GodotPlugin`, uses `@UsedByGodot` annotations
- Background service: `android_plugin/GhostKVBgService.java` — foreground service with WakeLock to keep Telegram bot polling when app is backgrounded
- Plugin AAR: `android/plugins/GhostKVPlugin.aar` — contains `AndroidManifest.xml` (with `<meta-data>` for v2 plugin discovery), `classes.jar`, `assets/godot_plugin.xml`
- Plugin config: `android/plugins/GhostKVPlugin.gdap` — INI format `[config]` section with name/binary_type/binary
- Must be enabled: `export_presets.cfg` needs `plugins/GhostKVPlugin=true`
- Plugin discovery: GodotPluginRegistry reads `<meta-data android:name="org.godotengine.plugin.v2.GhostKVPlugin">` from merged AndroidManifest

### Plugin Compilation (Windows)
```bash
# Extract godot-lib classes from AAR (first time only, or after Godot version change)
cd "C:/Users/aaron/Desktop/dev/ghostkv-desktop"
mkdir -p build/compile
cp android/build/libs/release/godot-lib.template_release.aar build/compile/godot-lib.aar
cd build/compile && unzip -o godot-lib.aar classes.jar

# Compile plugin (use ; separator on Windows)
javac --release 11 \
  -classpath "C:/Android/SDK/platforms/android-35/android.jar;build/compile/classes.jar;C:/Users/aaron/.gradle/caches/8.14/transforms/4dc608de929bcf6e83a1d1bc31818fce/transformed/core-1.13.1-runtime.jar" \
  -d build/compile \
  android_plugin/GhostKVPlugin.java

# Package into AAR
cd build/compile
"C:/Users/aaron/jdk-17/jdk-17.0.19+10/bin/jar.exe" cf plugin_classes.jar -C . com/
mkdir -p aar_staging && cp plugin_classes.jar aar_staging/classes.jar
# Add AndroidManifest.xml with meta-data and assets/godot_plugin.xml
cd aar_staging && "C:/Users/aaron/jdk-17/jdk-17.0.19+10/bin/jar.exe" cf ../GhostKVPlugin.aar .
cp build/compile/GhostKVPlugin.aar android/plugins/
```

### ADB / Phone Testing
```bash
MSYS_NO_PATHCONV=1 adb connect 192.168.0.106:34953
MSYS_NO_PATHCONV=1 adb -s 192.168.0.106:34953 install -r export/ghostkv-desktop.apk
MSYS_NO_PATHCONV=1 adb -s 192.168.0.106:34953 shell am start -n com.slothitude.ghostkv/com.godot.game.GodotAppLauncher
```
Phone ADB port changes — check the current port on the device (Wireless debugging settings).

### Checking Logs
```bash
# Get the GhostKV PID from latest godot log
adb logcat -d | grep "I godot" | tail -5

# Filter by PID (replace with actual PID)
adb logcat -d | grep "PID" | grep -v "Finsky\|MotoExtend\|AudioSystem" | tail -20
```

## Architecture

### Entry Point
`main.gd` — creates all singletons and UI in `_ready()`, registers them with `Engine.register_singleton()`. No scene tree autoloads — everything is wired programmatically.

### Singleton Chain (registered in order)
1. **AppState** (`core/state.gd`) — global state (token count, step counter)
2. **SessionManager** (`core/session.gd`) — session persistence to `user://` JSON, settings load/save
3. **ApiClient** (`core/api_client.gd`) — OpenAI-compatible HTTP API. Has non-streaming (`generate`/`generate_with_retry` via HTTPRequest) and streaming (`generate_stream` via HTTPClient) paths. **Streaming has a body truncation bug on Android** — use non-streaming.
4. **ToolDispatch** (`core/tool_dispatch.gd`) — routes `Action: tool_name("args")` from LLM output to registered tool handlers. Uses regex `"([^"]*)"` for arg parsing, creates `{"arg0":..., "arg1":...}` dicts.
5. **MemoryStore** (`core/memory_store.gd`) — graph memory store. JSON persistence at `user://memory.db.json`. 8 tools: remember, recall, relate, search_memory, list_entities, forget, forget_fact, export_memory. `auto_recall()` injects relevant memory into ReactLoop system prompt.
6. **ReactLoop** (`core/react_loop.gd`) — ReAct loop. Detects `Action: tool_name(args)` in LLM response via regex. If found, dispatches tool, appends observation, loops. If not, emits `answer_ready`.
7. **Markdown** (`core/markdown.gd`) — Markdown → BBCode converter
8. **BuiltinTools** (`core/builtin_tools.gd`) — 56 built-in tools including 8 memory tools (via MemoryStore registration), 2 web tools (web_search via SearXNG, web_read), plus ~46 Android-bridged tools (SMS, contacts, camera, etc). On Android, bridges to `GhostKVPlugin` Java singleton; has `OS.execute()` shell fallbacks.
9. **VoiceManager** (`core/voice_manager.gd`) — Voice pipeline orchestrator. Dictation mode (mic tap → STT → fills input), voice chat mode (continuous STT→LLM→TTS loop), auto-TTS, barge-in detection.

### Tool Registration Flow
1. `BuiltinTools._ready()` → registers 56 tools with `ToolDispatch.register_tool(name, "builtin", self)`
2. `MemoryStore._ready()` → registers 8 memory tools with `ToolDispatch.register_tool(name, "memory", self)`
3. `McpPanel._load_servers()` → connects MCP servers, discovers tools via `MCPClient`, registers with `ToolDispatch`
4. `ReactLoop.run()` → calls `ToolDispatch.build_tool_descriptions()` → injects all tool descriptions into system prompt

### MCP Client (SSE Transport)
`core/mcp_client.gd` — uses low-level `HTTPClient` (not `HTTPRequest`) for SSE handshake because `HTTPRequest` hangs on streaming responses. Flow:
1. Connect to `/sse` endpoint via `HTTPClient`, read initial SSE data for message endpoint
2. Keep `HTTPClient` alive as `_sse_client` for reading SSE responses
3. `_poll_sse()` loop reads chunks, buffers complete SSE events (`\n\n` delimited)
4. `_send_jsonrpc()` creates a separate `HTTPClient` for POSTing (POST returns 202, actual response arrives via SSE)
5. `_discover_tools()` sends `tools/list`, response arrives via SSE → emits `tools_discovered`

**MCP Panel** (`ui/mcp_panel.gd`) — auto-connects default servers from `_default_settings()`. Merges defaults into saved server list. Calls `_load_servers()` directly in `_ready()` (settings already loaded before UI created).

### Web Tools (Builtin, no MCP dependency)
- `web_search` — hits SearXNG at `http://192.168.0.33:8888/search?q=...&format=json`, returns top 5 results
- `web_read` — fetches page via web-reader at `http://192.168.0.33:8003/read?url=...`, truncates to 4000 chars

### Memory Store (Graph Memory)
- **Storage**: `user://memory.db.json` — entity name (lowercased) as dict key for O(1) lookup
- **Schema**: `{entities: {key: {name, type, created, facts: {key: {key, value, created}}, relations: [{relation, target, created}]}}}`
- **Auto-recall**: `auto_recall(query)` matches entities by name/words/fact values, returns formatted context
- **Export**: `export_memory()` writes Obsidian-flavored markdown to `user://vault/` with `[[wikilinks]]`

### UI (all built programmatically, no .tscn editor layouts)
- **App** (`ui/app.gd`) — root `Control`, HBoxContainer with sidebar + chat. Detects mobile breakpoint at 720px. Voice mode toggle in status row, floating 64x64 mic overlay when active.
- **Sidebar** (`ui/sidebar.tscn`) — sessions list, MCP panel, settings panel
- **ChatView** (`ui/chat_view.tscn`) — scrollable message list, thinking bubble with animated dots
- **MessageBubble** (`ui/message_bubble.tscn`) — user (purple) / assistant (dark) / error styling
- **ToolCard** (`ui/tool_card.tscn`) — expandable card with accent border for tool calls
- **InputBar** (`ui/input_bar.tscn`) — text input + mic button (Android) + send/stop button
- **StatusBar** (`ui/status_bar.tscn`) — model name, step counter, token count, elapsed time

### Remote API
`core/remote_api.gd` — TCPServer on port 9797. Endpoints: `GET /ping`, `POST /send {"message": "..."}`. Injects messages into App's `_on_message_sent()`. Used for testing via `adb shell curl`. Note: added as child node but NOT registered as an Engine singleton.

### Telegram Bot
`core/telegram_bot.gd` — background thread long-polling. Emits messages into App. Requires `telegram_bot_token` and `telegram_chat_id` in settings.

## GDScript Gotchas for This Codebase

- **`HTTPRequest` can't handle SSE** — it buffers the entire response body before firing `request_completed`. SSE streams never "complete", so the callback never fires. Use low-level `HTTPClient` for SSE/streaming HTTP.
- **`HTTPClient.connect_to_host()` takes `TLSOptions`** not `bool` for the TLS parameter in Godot 4.6. Use `TLSOptions.client()` or `null`.
- **Type inference fails on dict access** — `var host := dict["host"]` fails. Use explicit types: `var host: String = dict["host"]`. Same for `var x := some_dict.size()`.
- **`PackedStringArray` has no `.join()`** — use `separator.join(array)` (String method), not `array.join(separator)`.
- **`match` requires `_` for default** — bare `return` at the end of a `match` block causes parse error. Use `_:` branch.
- **No Python-style docstrings** — `"""text"""` is not valid GDScript.
- **`await` in `_ready()`** — cooperative async works in GDScript. Multiple coroutines interleave via `await get_tree().process_frame`. An infinite `while/await` loop blocks the function from returning but doesn't block other coroutines.
- **Android streaming bug**: `HTTPClient` sends truncated request body on Android. Use `generate_with_retry()` (non-streaming HTTPRequest).
- **Tool arg parsing**: LLM returns `Action: tool("arg1", "arg2")` → regex extracts quoted strings → `{"arg0": "arg1", "arg1": "arg2"}`. Tool functions must check both positional (`arg0`/`arg1`) and named params.
- **Singleton access**: `Engine.get_singleton("Name")` returns `Variant` — cast to `Node`. All singletons registered in `main.gd`.
- **Windows paths**: `\t` in GDScript strings becomes TAB. Always use forward slashes.
- **SpeechRecognizer threading**: Must run on Android main thread. Plugin uses `Handler(Looper.getMainLooper()).post()`.
- **TTS init race**: First `speakWithId()` may arrive before TTS ready. Plugin queues and flushes.
- **Thinking bubble race**: `queue_free()` is deferred. `chat_view._on_answer()` must `await get_tree().process_frame` before adding assistant bubble.
- **AAR rebuild**: `jar cf` must use absolute output path on Windows. Never extract from + write to same AAR file.
- **Settings merge**: `SessionManager.load_settings()` only adds missing keys from defaults — it does NOT overwrite existing keys. To change a default for an already-installed app, the code must actively merge (as done in `mcp_panel.gd:_load_servers()`).

## Default Settings

Key defaults from `session.gd:_default_settings()`:
- API: `https://api.z.ai/api/coding/paas/v4/chat/completions`, model `glm-5.1`
- MCP servers: `[{"name": "web-reader", "url": "http://192.168.0.33:8003/sse"}]`
- SearXNG: `http://192.168.0.33:8888` (hardcoded in builtin_tools web_search)
- Memory auto-recall: `true`
- Remote API port: `9797`
