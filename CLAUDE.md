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
MSYS_NO_PATHCONV=1 adb connect 192.168.0.106:38827
MSYS_NO_PATHCONV=1 adb -s 192.168.0.106:38827 install -r export/ghostkv-desktop.apk
MSYS_NO_PATHCONV=1 adb -s 192.168.0.106:38827 shell am start -n com.slothitude.ghostkv/com.godot.game.GodotAppLauncher
```

## Architecture

### Entry Point
`main.gd` — creates all singletons and UI in `_ready()`, registers them with `Engine.register_singleton()`. No scene tree autoloads — everything is wired programmatically.

### Singleton Chain (registered in order)
1. **AppState** (`core/state.gd`) — global state (token count, step counter)
2. **SessionManager** (`core/session.gd`) — session persistence to `user://` JSON, settings load/save
3. **ApiClient** (`core/api_client.gd`) — OpenAI-compatible HTTP API. Has non-streaming (`generate`/`generate_with_retry` via HTTPRequest) and streaming (`generate_stream` via HTTPClient) paths. **Streaming has a body truncation bug on Android** — use non-streaming.
4. **ToolDispatch** (`core/tool_dispatch.gd`) — routes `Action: tool_name("args")` from LLM output to registered tool handlers. Uses regex `"([^"]*)"` for arg parsing, creates `{"arg0":..., "arg1":...}` dicts.
5. **ReactLoop** (`core/react_loop.gd`) — ReAct loop. Detects `Action: tool_name(args)` in LLM response via regex. If found, dispatches tool, appends observation, loops. If not, emits `answer_ready`.
6. **Markdown** (`core/markdown.gd`) — Markdown → BBCode converter
7. **BuiltinTools** (`core/builtin_tools.gd`) — 19 built-in tools. On Android, bridges to `GhostKVPlugin` Java singleton; has `OS.execute()` shell fallbacks when plugin is null. Tools: open_url, run_command, file_read, calculator, send_sms, open_camera, open_app, list_apps, run_python, toast, vibrate, get_contacts, get_location, read_sms, set_alarm, set_timer, speak, start_listening.

### UI (all built programmatically, no .tscn editor layouts)
- **App** (`ui/app.gd`) — root `Control`, HBoxContainer with sidebar + chat. Detects mobile breakpoint at 720px.
- **Sidebar** (`ui/sidebar.tscn`) — sessions list, MCP panel, settings panel
- **ChatView** (`ui/chat_view.tscn`) — scrollable message list
- **MessageBubble** (`ui/message_bubble.tscn`) — user (purple) / assistant (dark) / error styling
- **ToolCard** (`ui/tool_card.tscn`) — expandable card with accent border for tool calls
- **InputBar** (`ui/input_bar.tscn`) — text input + send/stop button
- **StatusBar** (`ui/status_bar.tscn`) — model name, step counter, token count, elapsed time

### Remote API
`core/remote_api.gd` — TCPServer on port 9797. Endpoints: `GET /ping`, `POST /send {"message": "..."}`. Injects messages into App's `_on_message_sent()`.

### MCP Integration
`core/mcp_client.gd` — SSE client for MCP tool servers. Connects, discovers tools, calls them via HTTP POST. Auto-reconnect with backoff. Tools registered with ToolDispatch via `register_tool()`.

## Key Gotchas
- **Android streaming bug**: `HTTPClient` sends truncated request body on Android. Use `generate_with_retry()` (non-streaming, uses HTTPRequest node) instead of `generate_stream()`.
- **Tool arg parsing**: LLM returns `Action: send_sms("0488200725", "message")` → `_parse_args` extracts quoted strings → `_args_to_dict` creates `{"arg0": "0488200725", "arg1": "message"}`. Tool functions must check `arg0`/`arg1` in addition to named params.
- **Singleton access**: Use `Engine.get_singleton("Name")` — returns `Variant`, cast to `Node`. All singletons registered in `main.gd`.
- **Node tree**: App node is named "App" (from `app.tscn`). Remote API finds it via `_find_node(get_tree().root, "App")`.
- **Windows paths in GDScript**: `\t` in string paths becomes TAB. Use forward slashes or raw strings.
