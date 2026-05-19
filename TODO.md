# GhostKV Desktop — TODO

Master roadmap: `C:\Users\aaron\Desktop\dev\ghostkv\ROADMAP.md` (v1.1.0 section)

## Done
- [x] Project skeleton (project.godot, main.gd, scene structure)
- [x] Dark theme builder (core/theme.gd)
- [x] App state singleton (core/state.gd)
- [x] Session persistence — JSON in user:// (core/session.gd)
- [x] API client — OpenAI-compatible HTTP with retry on 429 (core/api_client.gd)
- [x] ReAct loop — Think → Act → Observe (core/react_loop.gd)
- [x] Tool dispatch — Action: regex parser (core/tool_dispatch.gd)
- [x] MCP SSE client — discover + call tools (core/mcp_client.gd)
- [x] Markdown → BBCode converter (core/markdown.gd)
- [x] Main layout — sidebar + chat + input (ui/app.tscn)
- [x] Chat view — scrollable message list (ui/chat_view.tscn)
- [x] Message bubbles — user (purple) / assistant (dark) / error (ui/message_bubble.tscn)
- [x] Tool cards — expandable with accent border (ui/tool_card.tscn)
- [x] Input bar — text input + send button (ui/input_bar.tscn)
- [x] Status bar — model, step, tokens (ui/status_bar.tscn)
- [x] Sidebar — sessions, tools, MCP panel, settings (ui/sidebar.tscn)
- [x] Settings panel — API URL, key, model, temperature, max tokens/steps, system prompt
- [x] MCP panel — add/remove MCP SSE servers
- [x] Session list — new/switch/delete sessions
- [x] Kenney UI pack — fonts, icons, sounds integrated
- [x] API tested and working — Z.ai GLM-5.1 responding
- [x] Fix: invisible text (setup() after add_child())
- [x] Fix: Godot 4.6 parse errors (type inference, enum names)
- [x] Windows + Android export presets
- [x] Streaming output — HTTPClient-based SSE, tokens appear live, BBCode finalize on complete
- [x] Loading spinner — animated "thinking..." dots while awaiting first token
- [x] Stop button — replaces Send during generation, cancels stream + react loop
- [x] Retry button — error bubbles get Retry button that re-sends last user message
- [x] Copy message — Copy button on assistant + error bubbles, clipboard via DisplayServer
- [x] Keyboard shortcuts — Escape stop, Ctrl+N new session, Ctrl+S save, Ctrl+L focus input
- [x] Window persistence — save/restore position and size across restarts
- [x] Streaming placeholder — "GhostKV is responding..." during streaming vs "thinking..."
- [x] Code block rendering — syntax highlighting for 8+ languages, language label headers, dark bg, inline code styling
- [x] Clear chat — Clear button in status bar, clears messages + saves session
- [x] Delete session — X button in sidebar, removes from list and disk
- [x] Sound effects — tap.ogg on send, click.ogg on receive, switch.ogg on error
- [x] Live status bar — elapsed time counter during generation, step updates
- [x] MCP auto-reconnect — retry with backoff (2s/4s/6s, 3 attempts), live status in sidebar
- [x] Tool schema display — parameter names, types, required markers, descriptions in tool cards
- [x] Structured error display — error type detection, timestamps, actionable hints per error class
- [x] Responsive sidebar — hamburger menu on narrow screens, dark overlay, auto-collapse on mobile
- [x] Touch-friendly sizing — 48dp buttons, 36dp sidebar buttons, larger action targets
- [x] Android debug keystore — generated, export preset configured
- [x] Responsive resize detection — NOTIFICATION_RESIZED, auto-switches layout at 720px breakpoint
- [x] Android plugin — GhostKVPlugin.java (shell exec, SMS, camera, apps, toast, vibrate, permissions)
- [x] Built-in tools — core/builtin_tools.gd (run_command, file_read, calculator, open_url, run_python, send_sms, open_camera, open_app, list_apps, toast, vibrate)
- [x] Tool dispatch — handles builtin + MCP tools, schema + descriptions for all
- [x] Android permissions — SEND_SMS, CAMERA, VIBRATE in export_presets.cfg

## Next Up

### Android Plugin Build
- [ ] Compile GhostKVPlugin.java → .aar
- [ ] Configure plugin in project.godot (android_plugin)
- [ ] Test on Android device

### Export
- [ ] Windows .exe build
- [ ] Android .apk build and test on phone
- [ ] App icons (.ico + adaptive)
