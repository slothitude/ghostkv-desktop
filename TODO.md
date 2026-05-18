# GhostKV Desktop — Master TODO

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

## TODO

### Polish
- [ ] Loading spinner — animated indicator while awaiting API response
- [ ] Error display — API errors shown as clear error cards in chat
- [ ] Keyboard shortcuts — Ctrl+N new session, Ctrl+S save, Escape stop
- [ ] Window persistence — remember size/position across restarts
- [ ] Sound effects — play Kenney click/tap sounds on send and receive
- [ ] Copy message — right-click context menu or button to copy text
- [ ] Clear chat — button to clear current session messages
- [ ] Delete session — remove session from list and disk

### UX Improvements
- [ ] Auto-scroll — guarantee chat scrolls to bottom on new messages
- [ ] Code block rendering — proper monospace blocks with syntax hints
- [ ] System prompt editor — multiline edit in settings panel
- [ ] Response streaming — show tokens as they arrive (SSE/chunked)
- [ ] Token counter — live count in status bar during generation
- [ ] Stop button — cancel ongoing API request mid-generation
- [ ] Retry button — retry failed messages

### MCP & Tools
- [ ] MCP auto-reconnect — reconnect saved servers on startup
- [ ] Tool argument schema — show input schema for each tool
- [ ] Tool call history — show full tool history in sidebar
- [ ] Built-in tools — add basic tools (web search, file read, calculator)

### Mobile / Android
- [ ] Responsive layout — sidebar collapse for narrow windows
- [ ] Sidebar drawer — slide-out drawer on mobile
- [ ] Touch-friendly sizing — larger tap targets (48dp minimum)
- [ ] Virtual keyboard handling — resize layout when keyboard appears
- [ ] Android export — build and test .apk on phone

### Export & Distribution
- [ ] Windows .exe export — build standalone executable
- [ ] Android .apk export — build and install on device
- [ ] App icon — proper .ico for Windows, adaptive icon for Android
- [ ] Auto-update — check for new versions on launch
