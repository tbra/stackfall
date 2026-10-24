Role: stackfall-implementer. Area: UI and config. Budget: 40 min, targeted tests only (at most one off-screen capture of the longest message).

Objective: a placement rejection currently shows the raw reason id as an uppercase phrase, for example "REJECTED: OUTSIDE TERRITORY" (the HUD builds it from the reason id). Show a plain sentence instead. Put the reason-to-message table in a config Resource so no message strings are hard-coded in the HUD. It must cover every refusal reason: the `REASON_*` constants in `core/rules/PlacementRules.gd` plus any other reason id the host sends to the HUD (search the placement and throw paths and the Events signals, and list what you find). The HUD shows the table's sentence; an unknown reason id falls back to a generic sentence (and a `push_warning` in debug builds).

Text: one short, plain sentence per reason that tells the player what to do, with no em dashes. Example tone: "You can only build inside your territory." List all sentences in your handback. Whether the HUD keeps uppercase is your call (add a `# DECISION:` comment). The message must fit the HUD reject label at 1280x720.

Read first: the spec sections on the HUD and placement rules; `ui/hud/HUD.gd` (the reject feedback part); `core/rules/PlacementRules.gd`; the existing HUD tests under `tests/unit/ui/`; the layer lint baseline notes if the new resource is reachable from an autoload.

Owned scope: `ui/hud/` (reject message part only), `config/ui/`, `tests/unit/ui/`.

Interface the acceptance tests call:
- `class_name RejectMessageTable` in `config/ui/RejectMessageTable.gd`, with the resource at `config/ui/reject_message_table.tres`
- `has_message(reason: StringName) -> bool`
- `message_for(reason: StringName) -> String`
- `fallback_message: String`

Acceptance:
- A unit test that every `REASON_*` constant has a table entry and that an unknown id returns the fallback.
- HUD tests that touch reject feedback pass (`python tools/affected_tests.py`).
- `godot --headless --editor --path . --quit` prints no errors; `python tools/lint_all.py` is GREEN.
