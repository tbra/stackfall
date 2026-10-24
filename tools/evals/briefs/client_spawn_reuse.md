Role: stackfall-netcode. Area: net client block mirror (bug). Budget: 40 min, targeted tests only (no ENet harness, no bot match, no screenshots).

Symptom: a client finishes one match and joins the next on the same session. During the second match the client refuses block spawns for net ids that the earlier match also used. Those ids were never despawned by an RPC: the earlier match's world was simply cleared when it ended, and the host's block registry restarts its ids for the new match. The client's blocks for the new match are missing or stale, so the host and the client disagree about what is on the table.

Objective: reproduce the fault through the public client mirror API (spawn a block with a net id, clear the world without a despawn, then spawn the same net id again as the new match would), fix the root cause once in the shared client code, and leave a test that fails when the behaviour breaks. A spawn for an id that is genuinely still alive must still be handled as before (a duplicate spawn for a live block is not a second block).

Read first: the spec sections on multiplayer authority and the client mirror; `net/` client block mirror and its spawn and despawn handlers; the existing client mirror tests under `tests/unit/net/`.

Owned scope: `net/` and `tests/unit/net/`.

Interface: `ClientBlockMirror.has_spawned(net_id)` already exists; this is a behaviour fix only, no new API is required.

Acceptance:
- A new test in `tests/unit/net/test_net_client_mirror.gd` that fails on the current code and passes after the fix.
- `tests/unit/net` (whole folder) passes via `tools/run_gut.ps1`.
- `python tools/lint_dead.py` reports nothing new; `python tools/lint_all.py` is GREEN.
