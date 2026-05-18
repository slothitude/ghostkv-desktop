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

## Next Up

### Polish
- [ ] Loading spinner — animated indicator while awaiting API response
- [ ] Error display — API errors shown clearly in chat
- [ ] Keyboard shortcuts — Ctrl+N new session, Ctrl+S save, Escape stop
- [ ] Window persistence — remember size/position across restarts
- [ ] Sound effects — play Kenney click/tap on send/receive
- [ ] Copy message — right-click or button to copy text
- [ ] Clear chat — button to clear current session messages
- [ ] Delete session — remove from list and disk

### UX
- [ ] Streaming output — show tokens as they arrive
- [ ] Code block rendering — monospace blocks with syntax hints
- [ ] Stop button — cancel ongoing API request
- [ ] Retry button — retry failed messages

### MCP & Tools
- [ ] MCP auto-reconnect on startup
- [ ] Tool argument schema display
- [ ] Built-in tools — web search, file read, calculator

### Mobile
- [ ] Responsive sidebar collapse
- [ ] Slide-out drawer on mobile
- [ ] Touch-friendly sizing (48dp)
- [ ] Virtual keyboard handling

### Export
- [ ] Windows .exe build
- [ ] Android .apk build and test on phone
- [ ] App icons (.ico + adaptive)
