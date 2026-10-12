# Player chat design contract (Bontago-1pi.192)

**OWNER DECISION (2026-10-12): gamepad users do not type. Chat input is keyboard only; pad users still see the chat log. Opening and sending chat is a keyboard/mouse action only, no gamepad binding exists for it, and a pad player must never be trapped in a focused chat input (section 4). No gamepad text-entry work (Steam keyboard, on-screen keyboard, quick-chat) is planned.**

Base: main `2b2f3be6`. Owner request (playtest 2026-10-12): "Player chat; lobby (bottom of the right panel) and in-game (above held/next preview)". SPEC section 3.4 already lists chat as a reliable RPC and the original game had pre-game chat (SPEC lines 55, 87, 471), so this is not an [ORIGINAL] rule change. Beads owns status; this file is design only.

## 1. Findings that shape the design (code anchors)

- Net pattern to copy: `autoload/Net.gd` `request_seat_pref` (l.2145) -> `@rpc("any_peer","call_remote","reliable") _rpc_request_seat_pref(Variant, Variant)` (l.2162) -> `_handle_seat_pref(sender, ...)` (l.2184): untyped `Variant` args so the host refuses wrong types, sender from `multiplayer.get_remote_sender_id()`, roster/slot check via `_peers.has` + `slot_of_peer`, per-peer token bucket (`_seat_pref_take_token`, `NetConfig.seat_pref_burst/_refill_per_s`, `_seat_pref_buckets` cleared at session start/end l.2032), result handed to the UI over `Events` (`net_seat_pref_requested`, `autoload/Events.gd:91`). Chat follows it exactly; Net stays transport-only.
- Host-to-all fan-out: `_broadcast_targets()` (Net.gd l.1862) + `_can_send()` (l.1830); late-join hook: `Events.net_peer_joined(peer_id, slot_id, name)` emitted at Net.gd l.1787 after the roster is broadcast.
- Names: `PlayerNames.clean/sanitize` (`core/rules/PlayerNames.gd`) already strips C0/C1 controls, bidi and zero-width characters with a `SCAN_FACTOR` bounded scan (anti-DoS on any_peer string). Chat reuses its stripped ranges (expose a public `PlayerNames.strip_invisible(text, scan_limit)` or copy via ChatRules; C0 decides, prefer exposing).
- The roster (`_peers[peer_id]`, `LobbySeats.FIELD_NAME/_SLOT_ID/_COLOR`, `core/rules/LobbySeats.gd:34-45`) is the identity source: the host stamps name, slot and colour on each line from the sender's peer id; the payload names no sender. Bots are never in `_peers` as peers (only a slot), so no code path lets a bot chat; a test pins it.
- Offline / Vs-bots: `Net.is_private_local_host()` (Net.gd ~l.800) is the private loopback host; nobody can join. Chat UI hides itself there and offline.
- Game input: `PlayerController.input_enabled` (game/PlayerController.gd l.204) is set false by `Events.pause_menu_opened` (l.358-375); `CameraRig.is_input_blocked()` (game/CameraRig.gd l.248). Typing must reuse this: a focused LineEdit eats key events in the GUI phase, but `Input.is_action_pressed` polling (W/A/S/D pitch/yaw, Space camera_modifier, Ctrl lock) still fires, so gating by signal is mandatory.
- Pause: `ui/PauseMenu.gd:183` handles `pause_menu` (Esc / Start) and `ui_cancel` in `_unhandled_input`. GUI input (LineEdit) runs before `_unhandled_input`, so chat's own Esc handler (mark handled) wins naturally; Start while typing still opens pause, which must close chat (listen to `Events.pause_menu_opened`).
- Lobby: `ui/Lobby.gd:1086` `_input` treats Enter (`lobby_confirm`, bootstrap l.516) as Start but already skips when a LineEdit has focus; so a focused chat field is safe there. The right panel is `ui/lobby/LobbyPlayersPanel.tscn` (title row, action row, `PlayerScroll` list); the Lobby owns the focus loop (`Lobby.gd` ~l.761-806, `focus_entries()` hook).
- HUD: `ui/HUD.tscn` `HeldNextPanel` is anchored bottom-left, offsets x 24..264, y -172..-24; the top-left cluster ends near y 220 and ToastStack starts at y 240. Chat sits directly above HeldNextPanel (bottom offset -184, height up to ~`log_lines` rows), clear of Minimap (bottom-right).
- Input Map: only through `tools/bootstrap_project.gd` `_actions()` (l.245+). Enter is `lobby_confirm`/`ui_accept` (menus only), `T` is free. `chat_open` is keyboard-only (owner decision), so it lives in the keyboard-only exceptions list the way `rotate_yaw_ccw` does (bootstrap l.~290, `DEVICE_EXCEPTIONS`; the Options pad page needs no stand-in row).

## 2. Message flow (transport-agnostic, host-authoritative)

```
sender UI --Events.chat_send_requested(text)--> Net.send_chat(text)
  client:  _rpc_chat_submit.rpc_id(HOST, text)          (reliable, any_peer, text: Variant)
  host:    _handle_chat(sender = local_peer_id(), text) (same checks, remote = false)
host _handle_chat(sender, payload, remote, now):
  1. refuse unless Mode.HOST; remote sender must be in _peers and not is_peer_disconnecting (spectators allowed)
  2. chat enabled (ChatConfig.enabled) and session is not the private local bot host
  3. flood bucket (every attempt from a known peer drains it): ChatConfig.burst=3, refill_per_s=0.5
     (3 quick lines then 1 per 2 s); on empty -> notice(CODE_RATE) to sender only, at most 1 per 1.5 s
  4. typeof(payload) == TYPE_STRING else drop (and drain); bounded scan: substr(0, max_len*SCAN_FACTOR)
  5. ChatRules.clean: strip C0/C1/bidi/zero-width (PlayerNames ranges), turn tab/newline into one space,
     collapse spaces, trim, cut to ChatConfig.max_chars (140 code points); empty -> drop silently
  6. duplicate guard: same text as sender's previous line inside 3 s -> notice(CODE_DUPLICATE)
  7. build line {seq, peer, slot, name (roster, sanitized at join), color (roster FIELD_COLOR), text, kind}
  8. append to host ring (ChatConfig.history_lines = 30); emit Events.chat_line_received locally;
     _rpc_chat_line.rpc_id(p, line) for every _broadcast_targets() peer except self
client _rpc_chat_line(line: Dictionary): accept only from sender 1 (host), re-validate shape and
  caps (keys, types, text <= max_chars, name <= max_player_name_length, seq monotonic), then emit
  Events.chat_line_received. Never trust, never BBCode (rendered as plain text, section 3).
late join: on Events.net_peer_joined (host) -> _rpc_chat_history.rpc_id(peer, last N lines, bounded
  to history_lines); client replaces its local log, marks lines as history (no fade-in toast).
leave / session end: _chat_buckets, last-line map and ring cleared next to _seat_pref_buckets.clear().
```

BBCode: the log control is a `RichTextLabel` with `bbcode_enabled = false` and the name drawn in the sender colour through `push_color`/`add_text`, never by concatenating user text into a BBCode string. Square brackets are therefore harmless and kept ("[GG]" must work). ChatRules carries a test that `[b]x[/b]`, `[url]`, `[img]` render as literal text. This satisfies "strip BBCode" by making it unparseable (DECISION, minor).

Sender colour: the name is tinted with `MatchConfig.player_colors[color]` (design system: player is shown by diamond + colour; names stay `cream` with a small diamond marker in the colour, so colour-assist and contrast on `disc-900` hold).

## 3. UI: one reusable component

`UiChatPanel` (ui/components/UiChatPanel.gd, built in code like `UiField`/`UiPanel`; follows `docs/ui_reskin/components.md`: `disc-900` well for the log with `shadow-well`, `radius-panel` 12, body 16/500 text, `caption` timestamps off, Rubik, `cream` text, 4px grid, focus = 3px cream outline offset 3). Two skins via `mode`:
- `Mode.LOBBY`: opaque `disc-800` panel, always visible, log scrolls (`FocusScrollContainer`-style), input line below, bottom of the right panel, grows with space; the title row says CHAT.
- `Mode.HUD`: `hud-plate` background, no scroll, last `hud_lines` (6) lines, compact (caption/body-sm size, never below 15px at 1080p per the design rules).

Contract: `log` (RichTextLabel, no bbcode), `edit` (LineEdit, `max_length = ChatConfig.max_chars`, placeholder "Press Enter to chat"/"Type a message"), `append_line(line: Dictionary)`, `replace_history(lines: Array)`, `open_input()`, `close_input(send: bool)`, signals `submit_requested(text)` and `input_opened` / `input_closed`. The panel never touches Net; screens connect it to `Events.chat_send_requested` / `chat_line_received` (so UI packages build and unit-test without Net).

In-game visibility rules (DECISION, minor, tunable in ChatConfig):
- A new line is fully visible for `line_visible_s` (8), then the whole panel fades over `fade_s` (1.0) to hidden; any new line or open input restores it. Opening input shows the last `hud_lines`. Holding `show_scores` shows the panel at full opacity. Own lines count as new lines. Hidden = not drawn and `mouse_filter = IGNORE`.
- The panel never takes mouse input in game (mouse is for placing). Chat is keyboard/pad driven.
- Muted-while-typing is not needed; incoming lines still arrive while typing.

Focus and gameplay-input rules (HUD mode):
- Open: action `chat_open` (keyboard Enter, KP Enter and T). Opening: `edit.grab_focus()`, emit `Events.chat_input_opened`; `PlayerController`, `CameraRig` and the other pollers set blocked exactly like `pause_menu_opened` (reuse that code path via a shared `Events` listener, not a copy of state). Close emits `Events.chat_input_closed` and `release_focus()`.
- Enter in the field: non-empty -> `submit_requested` then close; empty -> just close. Esc / `ui_cancel` (gui_input, `set_input_as_handled`) cancels and discards the text; the first Esc never reaches PauseMenu. Opening Pause or the match ending closes chat. Focus returning to the game restores `input_enabled` only if the pause menu is not open.
- While typing every key is the LineEdit's (W, A, S, D, Space, Tab, digits do not move the camera or rotate blocks); mouse placement is blocked too (`input_enabled`); mouse position still shows the ghost.
- Auto-closes on `LoadingScreen`, results screen, disconnect.

Lobby keyboard flow: the chat field is NOT in the pad focus loop (`FOCUS_CLICK`); keyboard users reach it by click or `chat_open` (T, ignored while another text field has focus) and type; Enter sends (Lobby `_input` already ignores `lobby_confirm` while a LineEdit has focus, `Lobby.gd:1090`); Esc / `ui_cancel` blurs the field and returns focus to the previous loop stop; Enter outside the field still means Start.

Pad flow: none by design (section 4).

## 4. Gamepad users (owner decision: read-only)

- Chat input is keyboard only. No pad button, chord, on-screen keyboard, Steam text input or preset list is built. `chat_open` has no gamepad event, `SteamClient` is untouched.
- Pad players see the chat log in both places (HUD fade rules apply, `show_scores` shows it; lobby panel is always visible).
- No-trap rules (each has a test):
  1. The input line takes focus only from a keyboard/mouse action: `chat_open` (keyboard), a mouse click on the field, or, in the lobby, arriving at it by focus navigation is **prevented**: the lobby edit has `focus_mode = FOCUS_CLICK` so the pad focus loop and `ui_up/ui_down` skip it (`focus_entries()` does not list it) and the log scroller is the only chat stop a pad can reach.
  2. If the field is focused and any pad event arrives (`InputEventJoypadButton` pressed or `InputEventJoypadMotion` beyond deadzone, including B, Start, A, d-pad), chat closes and focus returns to the previous owner (HUD: gameplay with `input_enabled` restored; lobby: the focus loop's last stop). The panel tracks `last device`; `ui_cancel` (B or Esc) always closes.
  3. A pad player cannot get stuck typing even if a keyboard user hands over the controller mid-line: the pad-event close above discards nothing but keeps the draft (restored on next open).
  4. Pad Start while typing opens Pause and closes chat; the match end, loading, results and disconnect close chat.
- A pad-only player therefore never needs the chat; a keyboard player on the same machine can still chat.

## 5. Work packages (disjoint owned files)

Dependency order: C0 -> {C1, C2} in parallel -> {C3, C4} (both need C1, C2) -> C5 (optional mute, after Q3).

### C0 interface stubs + pure rules (implementation worker, Sonnet, first; others wait for its commit on their base)
Owned: `core/rules/ChatRules.gd`, `config/ChatConfig.gd` (+ `config/chat_config.tres`), `autoload/Events.gd` (new signals only), `tools/bootstrap_project.gd` (+ regenerated `project.godot`), `tests/unit/test_chat_rules.gd` (+ `.uid`s). Optional tiny edit `core/rules/PlayerNames.gd` to expose the stripping helper (state in brief).
Interfaces (typed):
```gdscript
class_name ChatRules extends RefCounted
const KIND_TEXT: int = 0
const KIND_SYSTEM: int = 1
const NOTICE_RATE: int = 0
const NOTICE_DUPLICATE: int = 1
static func clean(text: Variant, max_chars: int) -> String          # "" when not a String or empty after cleaning
static func make_line(seq: int, peer: int, slot: int, player_name: String, color_index: int, text: String, kind: int = KIND_TEXT) -> Dictionary
static func validate_line(line: Variant, cfg: ChatConfig, max_name_len: int) -> bool   # client-side shape/caps check
class Bucket extends RefCounted: func take(now: float, burst: int, refill_per_s: float) -> bool
class History extends RefCounted: func push(line: Dictionary) -> void; func lines() -> Array[Dictionary]; func clear() -> void  # ring of cfg.history_lines
class_name ChatConfig extends Resource   # enabled, max_chars=140, burst=3, refill_per_s=0.5, duplicate_window_s=3.0, notice_min_interval_s=1.5, history_lines=30, hud_lines=6, line_visible_s=8.0, fade_s=1.0, sanitize()
```
Events signals: `chat_send_requested(text: String)`, `chat_line_received(line: Dictionary)`, `chat_history_received(lines: Array)`, `chat_notice(code: int)`, `chat_input_opened`, `chat_input_closed`.
Input Map: `chat_open` = Enter, KP Enter, T, keyboard only (no pad event; listed in the keyboard-only exceptions). 
Tests: clean (controls, bidi, zero-width, newline->space, trimming, length cap in code points, non-string, 10 MB input cost bounded, BBCode text kept literally), Bucket math, History ring, validate_line rejects wrong types/oversize/extra weird keys.

### C2 Net relay (netcode worker, Sonnet)
Owned: `autoload/Net.gd` (chat section + `_chat_*` state clears at l.2032 and session teardown), `config/NetConfig.gd` only if a chat knob belongs there (otherwise none), `tests/unit/test_net_chat.gd`.
Interfaces: `Net.send_chat(text: String) -> void`, internal `_rpc_chat_submit(Variant)`, `_rpc_chat_line(Dictionary)`, `_rpc_chat_history(Array)`, `_rpc_chat_notice(int)`, `_handle_chat(sender: int, payload: Variant, remote: bool, now: float = -1.0) -> bool`. Net subscribes to `Events.chat_send_requested`. Host history re-sent on `net_peer_joined`. Bots: no path.
Checks: see section 6.

### C1 UiChatPanel (implementation worker, Sonnet; parallel with C2)
Owned: `ui/components/UiChatPanel.gd` (+uid), `ui/components/ComponentGallery.gd/.tscn` (gallery entry only), `tests/unit/test_ui_chat_panel.gd`. Reads `docs/ui_reskin/tokens.json` through the existing `MenuStyleFactory`/`ArcadeVisualTuning`, no hard-coded colours.
Interface: as section 3 (`Mode`, `append_line`, `replace_history`, `open_input`, `close_input`, `submit_requested`, `input_opened`, `input_closed`, `apply_fade(delta)`, `is_typing() -> bool`).

### C3 Lobby integration (implementation worker)
Owned: `ui/lobby/LobbyChat.gd` (small adapter: connects the panel to Events, hides in private local host / offline), `ui/lobby/LobbyPlayersPanel.tscn` (adds the panel node under `PlayerScroll`) , `ui/lobby/LobbyPlayersPanel.gd` (`focus_entries()` deliberately does NOT list the chat edit (pad no-trap rule, section 4); nothing else), `ui/Lobby.gd` only if the Enter/Esc handling needs a line (state it), `tests/unit/test_lobby_chat.gd`. If `Lobby.gd` and `LobbyPlayersPanel.gd` cannot both be avoided by another package, C3 owns them exclusively; no other package touches them.

### C4 HUD integration + input gating (implementation worker)
Owned: `ui/HudChat.gd` (adapter + fade + open/close handling), `ui/HUD.tscn` (one node above HeldNextPanel), `game/PlayerController.gd` and `game/CameraRig.gd` (listen to `Events.chat_input_opened/closed` beside the pause hooks), `ui/PauseMenu.gd` (close chat when pause opens, no Esc theft), `ui/OptionsMenu.gd` + `ui/KeyRebindRow.gd` (list `chat_open` on the keyboard page only), `tests/unit/test_hud_chat.gd`. Over the 10-file soft cap only if tests are counted; split off `OptionsMenu/KeyRebindRow` into C4b if the worker runs long.

### C5 Mute and filter (after Q3)
Owned: `core/rules/ChatMute.gd`, scoreboard/lobby row hooks, `user://` settings key via existing settings store; defaults in section 7.

Integration order for the orchestrator: merge C0 first, verify C1/C2 bases contain it, merge C1+C2, then C3+C4 (each verified in a fresh `godot --headless --editor --path . --quit`), then C5. Full GUT once per batch via `integrate_batch.py`.

## 6. Acceptance checks

Unit (`powershell -File tools/run_gut.ps1 test_chat_rules,test_ui_chat_panel,...`):
- ChatRules: see C0. UiChatPanel: append respects `hud_lines`, fade timeline (visible, fading, hidden, restored by new line/open), `bbcode_enabled == false` and bracket text rendered literally, Enter submits trimmed text, Esc discards and emits `input_closed`, empty submit sends nothing, `max_length` enforced.
- Net (`test_net_chat`, pattern of `test_net_session.gd`: real ENet host + 2 clients, deadline by wall time): a client line reaches host and the other client with the roster name/slot/colour and monotonic `seq`; sender spoof attempt (payload dictionary claiming another peer/name) is ignored since only a string is accepted; wrong types (int, float, Array, Dictionary, null, huge string) dropped without relay; control chars and bidi stripped; 140-char cap; flood of 50 messages in a frame relays at most `burst` and sends a rate notice to the sender only; duplicate guard; late joiner receives history (<= 30 lines, order kept) and a joiner's history is not re-broadcast to others; a peer in the handshake / spectator / unknown id / disconnecting peer cannot chat as configured; `_rpc_chat_line` from a non-host sender is refused on clients; host's own `send_chat` relays; offline and private local host `send_chat` is a no-op; no peer id in `_peers` is a bot (assert bots produce no lines); buckets and ring clear on leave.
- Lobby/HUD with synthetic input: Enter (keyboard) opens HUD chat and `PlayerController.input_enabled == false` with W/A/S/D events injected via `Input.parse_input_event` not rotating the held block; Esc closes without pausing; Start (synthetic `InputEventJoypadButton`) while typing opens pause and closes chat; lobby Enter in the field sends and does not start the match; no pad event opens chat (synthetic `InputEventJoypadButton` A/B/X/Y/Start/Back/d-pad do not focus the field in lobby or HUD); a synthetic pad button while the field is focused closes it and restores the previous focus/`input_enabled`; the lobby pad focus loop never lands on the chat edit; the log is readable (scrollable by stick) in the lobby.
- Gate: `godot --headless --editor --path . --quit` clean; no untyped declarations; `tools/probe_lint.py`.
- Manual owner steps: two instances (Debug -> Customize Run Instances) type in lobby and match; gamepad pass: pad player sees lines, cannot open chat, and keeps full control while a keyboard player types.

## 7. OPEN QUESTIONS for the owner (all with defaults so work is not blocked)

- Q1 Profanity filter and mute. Options: none (friends-only game, host can kick), per-player mute toggle in the scoreboard/lobby row, word filter. Default: **no word filter; per-player mute (client-side, per session) as C5, shown as a small button on each non-local lobby seat row and in the held scoreboard**. Muting only hides lines locally; the host still relays.
- Q2 Rate limit: 3-line burst then 1 line per 2 s, 140 characters. Default as stated.
- Q3 Spectators and late joiners may chat (labelled with their roster name, neutral colour) and receive the last 30 lines. Default yes.
- Q4 In-game fade: 8 s visible then 1 s fade; hold `show_scores` (Tab/R3) to show it. Default as stated.
- Q5 Chat persists across lobby <-> match <-> results in one session (history kept); results screen shows the lobby-style panel? Default: no chat on results/loading, history kept for the lobby.
- Q6 System lines ("X joined", "X left") in the log. Default: yes in the lobby, no in match (toasts already exist).
- Q7 Team-only chat (teams mode). Default: **all-chat only**; team channel deferred.
- Q8 Players can see `[...]` text literally and no emoji support beyond what Rubik renders. Default as stated (design rule: no emoji in UI copy applies to our copy only).

## 8. Risks

- Net.gd is 2400 lines and shared; only C2 may touch it (serialize against any other Net package). Fallback: if conflicts appear, move chat RPCs to a `net/ChatNet.gd` child node (needs the same node path on all peers; test fixtures instantiate Net twice, so this is riskier than inline).
- Enter in game is not otherwise bound but `chat_open` shares Enter with menu `ui_accept`; acceptable because menus and the match never run together, but the pause menu being open must win (C4 test).
- Pad-event close rule (section 4) must not eat gameplay pad events on the frame chat closes: the closing event is consumed, later events pass.
