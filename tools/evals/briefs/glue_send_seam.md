Role: stackfall-netcode. Area: net host authority sends. Budget: 40 min, targeted tests only (no ENet harness, no bot match, no screenshots).

Objective: the host-side glue tracking (which block ids are glued or were coated, the wire-id filter, the was-coated rule from the fused and charged-drop sets) and the three host handlers for blocks fused, fused member released and glue drop charged currently live in `MatchNet`. Move that tracking state and those handlers into `MatchEventMirror`, behind its existing broadcast seam, so the host glued, uncoat and charged-drop sends can be observed with a spy seam in a unit test. `MatchNet` keeps no glue state. Wire format, RPC names and send order stay unchanged; the handlers stay host-only as before.

Read first: the spec sections on multiplayer authority; the net rebuild plan section on the mirror owning the host Events subscribers; `net/match/MatchEventMirror.gd` (its broadcast seam and how its other host subscribers live there); `net/MatchNet.gd` (how it builds the mirror's seam); the existing glue replication tests under `tests/unit/gifts/`.

Owned scope: `net/`. Do not edit tests; name in your handback the public seam (method and arguments) a tester would spy on.

Interface the acceptance tests call on `MatchEventMirror`:
- `on_blocks_fused(carrier: Node, members: Array)`
- `on_fused_member_released(member: Node)`
- `on_glue_drop_charged(body: Node)`
- `forget_glued(net_id: int)`
- `glued_ids() -> Array`
- `reset_glue()`

Acceptance:
- `tests/unit/net` (whole folder), the glue tests under `tests/unit/gifts` and the RPC contract test pass via `tools/run_gut.ps1`.
- The host sends are unchanged in format and order.
- `python tools/lint_dead.py` reports nothing new; `python tools/lint_all.py` is GREEN.
