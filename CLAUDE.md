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

### Android Build Notes
- **JDK 17** at `C:/Users/aaron/jdk-17/jdk-17.0.19+10` — configured in `AppData/Roaming/Godot/editor_settings-4.6.tres` (`export/android/java_sdk_path`). JDK 25 causes "Unsupported class file major version 69".
- **Android SDK** at `C:/Android/SDK`
- **Debug keystore** at `C:/Android/debug.keystore`
- Gradle build template at `res://android/build/` (extracted from Godot export templates). The `gradle_build_directory` in `export_presets.cfg` is `"res://android"` — Godot appends `/build` internally.
- `.build_version` file at `res://android/.build_version` must contain `4.6.1.stable`
- **Gradle hang**: Godot often hangs after Gradle finishes. The APK is at `android/build/build/outputs/apk/standard/release/android_release.apk` — if Godot hangs, kill it and install from there directly.

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
# Via Tailscale (works from anywhere)
MSYS_NO_PATHCONV=1 adb connect 100.107.255.34:<port>
# Via LAN (faster, same network only)
MSYS_NO_PATHCONV=1 adb connect 192.168.0.106:<port>

MSYS_NO_PATHCONV=1 adb -s 100.107.255.34:<port> install -r export/ghostkv-desktop.apk
MSYS_NO_PATHCONV=1 adb -s 100.107.255.34:<port> shell am start -n com.slothitude.ghostkv/com.godot.game.GodotAppLauncher
```
Phone ADB port changes — check the current port on the device (Wireless debugging settings).

### Checking Logs
```bash
# GhostCallAgent + telephony logs (push_warning shows in logcat)
MSYS_NO_PATHCONV=1 adb -s 192.168.0.106:<port> logcat -d | grep -i "GhostCallAgent\|GhostInCall\|TelephonyManager\|VoiceManager" | tail -40

# Broader app logs
MSYS_NO_PATHCONV=1 adb -s 192.168.0.106:<port> logcat -d | grep -i "godot\|ghostkv\|Ghost" | grep -v "Finsky\|MotoExtend\|BLASTBuffer\|AppOps" | tail -40
```

**ADB port instability**: Phone wireless debugging port changes frequently (screen off/on, app install). Always need fresh `adb connect 192.168.0.106:<port>` before operations.

### Remote API Testing
```bash
# Send a message to the running app (port 9797)
MSYS_NO_PATHCONV=1 adb -s 192.168.0.106:<port> shell "curl -s -X POST http://127.0.0.1:9797/send -H 'Content-Type: application/json' -d '{\"message\": \"hello\"}'"
```

## Architecture

### Entry Point
`main.gd` — creates all singletons and UI in `_ready()`, registers them with `Engine.register_singleton()`. No scene tree autoloads — everything is wired programmatically.

### Singleton Chain (registered in order)
1. **AppState** (`core/state.gd`) — global state (token count, step counter)
2. **SessionManager** (`core/session.gd`) — session persistence to `user://` JSON, settings load/save
3. **ApiClient** (`core/api_client.gd`) — OpenAI-compatible HTTP API. Has non-streaming (`generate`/`generate_with_retry` via HTTPRequest) and streaming (`generate_stream` via HTTPClient) paths. **Streaming has a body truncation bug on Android** — use non-streaming. Signals: `response_received(text, usage)`, `error_occurred(msg)`.
4. **ToolDispatch** (`core/tool_dispatch.gd`) — routes `Action: tool_name("args")` from LLM output to registered tool handlers. Uses regex `"([^"]*)"` for arg parsing. **Critical**: `_args_to_dict()` returns `{"input": value}` when there's exactly 1 arg (not `arg0`). Tool functions must check `args.get("input", args.get("named_param", args.get("arg0", "")))`.
5. **ToolSelector** (`core/tool_selector.gd`) — smart tool filtering. Categorizes tools into core/communication/system/media/files/device/mcp groups, builds keyword index, scores tools per query. Returns ~15-25 relevant tools instead of 410+. Core tools (memory + calculator + web) always included (score 1000). Scoring: exact name token match (+80), prefix match for >=4 char tokens (+40), description match (+15/capped at +45), category keyword match (+20×relevance). Stop words filtered ("what", "is", "my", "level", etc.). Minimum score threshold of 30 excludes weak matches. Falls back to all tools if disabled. `strip_punctuation()` does not exist in GDScript — use manual char filtering.
6. **MemoryStore** (`core/memory_store.gd`) — graph memory store. JSON persistence at `user://memory.db.json`. 8 tools: remember, recall, relate, search_memory, list_entities, forget, forget_fact, export_memory. `auto_recall()` injects relevant memory into ReactLoop system prompt.
7. **ReactLoop** (`core/react_loop.gd`) — ReAct loop. Detects `Action: tool_name(args)` in LLM response via regex. If found, dispatches tool, appends observation, loops. If not, emits `answer_ready`. Uses ToolSelector to inject only relevant tool descriptions.
8. **Markdown** (`core/markdown.gd`) — Markdown → BBCode converter
9. **BuiltinTools** (`core/builtin_tools.gd`) — 57 built-in tools (58 with ghost_call + auto_answer_call). Includes 8 memory tools (via MemoryStore registration), 2 web tools (web_search via SearXNG, web_read), telephony tools, plus ~45 Android-bridged tools. On Android, bridges to `GhostKVPlugin` Java singleton; has `OS.execute()` shell fallbacks. Trust system: `add_trusted_contact()` stores phone→trust level; SMS/calls to non-trusted contacts require confirmation dialog.
9. **VoiceManager** (`core/voice_manager.gd`) — Voice pipeline orchestrator. Dictation mode (mic tap → STT → fills input), voice chat mode (continuous STT→LLM→TTS loop), auto-TTS, barge-in detection. Has `set_call_mode(agent)` to route STT to GhostCallAgent during calls, and `speak(text)` for direct TTS.
10. **TelephonyManager** (`core/telephony_manager.gd`) — Android telephony bridge via GhostKVPlugin. Signals: `incoming_call(number)`, `call_started(number)`, `call_ended(duration)`. Methods: `answer_call()`, `end_call()`, `make_call()`, `set_speaker()`, `set_mute()`. `set_speaker()` uses `InCallService.setAudioRoute()` (NOT `AudioManager.setSpeakerphoneOn()` which gets overridden by Telecom).
11. **GhostCallAgent** (`core/ghost_call_agent.gd`) — Autonomous call agent. `initialise()` called after all other singletons ready (after App loaded). Connects TelephonyManager signals + plugin's `on_call_state_changed` for connection detection. Uses VoiceManager for STT/TTS routing, ApiClient for LLM calls. Logs use `push_warning()` (visible in Android logcat — `print()` is invisible).

### GhostCallAgent Call Flow
```
Incoming call → TelephonyManager.incoming_call → _on_incoming_call()
  → LLM decides answer/reject (or auto_answer timer)
  → answer → set_speaker(true) → VoiceManager.set_call_mode(self)
  → greeting via TTS → STT listening starts
  → caller speaks → VoiceManager._on_speech_result() → call_mode → _on_caller_speech()
  → ApiClient.generate() → LLM response → VoiceManager.speak() → repeat

Outgoing → ghost_call tool → TelephonyManager.make_call()
  → InCallService on_call_state_changed "active" (NOT call_started — that fires on OFFHOOK/dialing)
  → set_speaker(true) via InCallService.setAudioRoute()
  → wait 2s → start STT
  → long speech = voicemail greeting → listen silently → silence = beep → leave message → auto-hangup 8s
  → short speech (≤4 words) = person → greet them → normal conversation loop

Call ends → call_ended signal → set_call_mode(null) → set_speaker(false) → transcript emitted
```

### Default Dialer Requirement
GhostKV **must be set as the default Phone app** on Android for the InCallService to bind. Without it:
- Telecom skips binding `GhostInCallService` (`"Skipping binding to ... isRequestedtype:false"`)
- `setAudioRoute()` returns `"error:service_not_bound"`, falls back to `AudioManager.setSpeakerphoneOn()` which gets overridden
- Call state callbacks don't fire
The app declares `ACTION_DIAL` intent filters via an `activity-alias` in `android_plugin/AndroidManifest.xml` targeting `com.godot.game.GodotApp`, making it appear as a dialer option in system settings.

### Voicemail vs Person Detection (Outgoing Calls)
1. Call connects → wait 2s → start STT
2. STT silence with no speech yet → restart listening (don't greet)
3. Short speech (≤4 words, e.g. "Hello?") → person → greet them → normal conversation
4. Long speech (>4 words, e.g. "Hi, you've reached...") → voicemail greeting → keep listening silently
5. Silence after long speech → voicemail beep done → leave message → auto-hangup after 8s
6. Safety timeout: 30s after call connects, leave message regardless

### Tool Registration Flow
1. `BuiltinTools._ready()` → registers 57 tools with `ToolDispatch.register_tool(name, "builtin", self)`
2. `MemoryStore._ready()` → registers 8 memory tools with `ToolDispatch.register_tool(name, "memory", self)`
3. `McpPanel._load_servers()` → connects MCP servers, discovers tools via `MCPClient`, registers with `ToolDispatch`
4. `ToolDispatch.register_tool()` → notifies `ToolSelector.on_tool_registered()` (caches name tokens, description, category)
5. `ReactLoop.run()` → calls `ToolSelector.select_tools(query)` → `ToolDispatch.build_tool_descriptions_filtered()` → injects ~30-50 relevant tool descriptions into system prompt

### MCP Client (SSE Transport)
`core/mcp_client.gd` — uses low-level `HTTPClient` (not `HTTPRequest`) for SSE handshake because `HTTPRequest` hangs on streaming responses. Flow:
1. Connect to `/sse` endpoint via `HTTPClient`, read initial SSE data for message endpoint
2. Keep `HTTPClient` alive as `_sse_client` for reading SSE responses
3. `_poll_sse()` loop reads chunks, buffers complete SSE events (`\n\n` delimited)
4. `_send_jsonrpc()` creates a separate `HTTPClient` for POSTing (POST returns 202, actual response arrives via SSE)
5. `_discover_tools()` sends `tools/list`, response arrives via SSE → emits `tools_discovered`

**MCP Panel** (`ui/mcp_panel.gd`) — auto-connects default servers from `_default_settings()`. Merges defaults into saved server list. Calls `_load_servers()` directly in `_ready()` (settings already loaded before UI created).

### Web Tools (Builtin, no MCP dependency)
- `web_search` — hits SearXNG at `http://100.119.172.102:8888/search?q=...&format=json` (Oracle Tailscale), returns top 5 results
- `web_read` — fetches page via web-reader at `http://100.84.161.63:8003/read?url=...` (Lappy Tailscale), truncates to 4000 chars

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
- **No parenthesized string concatenation** — `var s = ("line1\n" "line2\n")` is a parse error. Use `+` or write as a single string literal.
- **`await` in `_ready()`** — cooperative async works in GDScript. Multiple coroutines interleave via `await get_tree().process_frame`. An infinite `while/await` loop blocks the function from returning but doesn't block other coroutines.
- **Android streaming bug**: `HTTPClient` sends truncated request body on Android. Use `generate_with_retry()` (non-streaming HTTPRequest).
- **Tool arg parsing — the `input` key**: When ToolDispatch extracts exactly 1 quoted arg from `Action: tool("value")`, `_args_to_dict()` returns `{"input": "value"}` (NOT `{"arg0": "value"}`). With 2+ args it uses `arg0`, `arg1`, etc. Tool functions must check `args.get("input", args.get("named_param", args.get("arg0", "")))` to handle both cases.
- **Singleton access**: `Engine.get_singleton("Name")` returns `Variant` — cast to `Node`. All singletons registered in `main.gd`.
- **Windows paths**: `\t` in GDScript strings becomes TAB. Always use forward slashes.
- **SpeechRecognizer threading**: Must run on Android main thread. Plugin uses `Handler(Looper.getMainLooper()).post()`.
- **TTS init race**: First `speakWithId()` may arrive before TTS ready. Plugin queues and flushes.
- **Thinking bubble race**: `queue_free()` is deferred. `chat_view._on_answer()` must `await get_tree().process_frame` before adding assistant bubble.
- **AAR rebuild**: `jar cf` must use absolute output path on Windows. Never extract from + write to same AAR file.
- **Settings merge**: `SessionManager.load_settings()` only adds missing keys from defaults — it does NOT overwrite existing keys. To change a default for an already-installed app, the code must actively merge (as done in `mcp_panel.gd:_load_servers()`).
- **`has_signal()` for dynamic connections** — when connecting signals from singletons that may or may not exist, always check `node.has_signal("signal_name")` before connecting (see GhostCallAgent.initialise()).
- **`SceneTreeTimer` assignment** — `get_tree().create_timer()` returns `SceneTreeTimer`. Don't store it in a `Timer` var — use `SceneTreeTimer` or `Variant`.
- **`print()` invisible in Android logcat** — use `push_warning()` instead. It writes to logcat at warn level and is grep-able.
- **InCallService audio routing** — `AudioManager.setSpeakerphoneOn()` gets overridden by Telecom framework within milliseconds. Always use `InCallService.setAudioRoute(ROUTE_SPEAKER)` via the plugin's `setAudioRoute("SPEAKER")` method. Only works when app is default dialer.
- **Outgoing call OFFHOOK vs ACTIVE** — `TelephonyManager.on_call_started` fires immediately on OFFHOOK (when dialing starts). For outgoing calls, wait for `on_call_state_changed` with state "active" (InCallService) to know when the callee actually picks up.
- **Phone number format normalization** — Australian numbers need +61↔0 prefix matching. Trust store may have `+61439720202` but LLM sends `0439720262`. `get_trust_level()` must try both formats.

## Default Settings

Key defaults from `session.gd:_default_settings()`:
- API: `https://api.z.ai/api/coding/paas/v4/chat/completions`, model `glm-5.1`
- MCP servers: `[{"name": "web-reader", "url": "http://100.84.161.63:8003/sse"}, {"name": "alphabetty", "url": "https://alphabetty.ddns.net/mcp/sse"}]`
- SearXNG: `http://100.119.172.102:8888` (Oracle Tailscale, hardcoded in builtin_tools web_search)
- STT: `http://100.84.161.63:5000/v1/audio/transcriptions` (Lappy Tailscale)
- Memory auto-recall: `true`
- Remote API port: `9797`
- Tool selection: `tool_selection_enabled: true`, `tool_selection_max: 50`

### Tailscale IPs
| Device | Tailscale IP | Services |
|--------|-------------|----------|
| Oracle | `100.119.172.102` | SearXNG (:8888), Alphabetty (HTTPS via DDNS) |
| Lappy | `100.84.161.63` | web-reader (:8003), STT (:5000), Ollama (:11434) |
| Phone | `100.107.255.34` | ADB (port changes) |
