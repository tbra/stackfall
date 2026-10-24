Role: stackfall-implementer. Area: tooling (bug). Budget: 40 min, python tests only (no Godot).

Observed deadlock: two `run_enet_set` invocations run at once. The first holds one Godot slot for a multi-process harness and still needs more slots for that harness's peers. The second queued an exclusive request (a bench that needs every slot), and the exclusive gate refuses new slot holders until the current holders drain. Neither can progress: the first waits for slots the gate will not grant, the gate waits for the first to finish.

Objective: two concurrent `run_enet_set` invocations always finish (one may wait for the other). Make the smallest correct fix. Keep: the Godot slot cap, writer preference for real exclusive benches, stale-PID reclaim, and that nothing is ever killed.

Read first: the `tools/godot_slots.py` docstring and code (slots, the exclusive gate with writer preference, the re-entrant token); `tools/run_enet_set.py` (how a harness declares and acquires its process count, and how a harness asks for exclusive); `tools/test_godot_slots.py`.

Owned scope: `tools/` (`godot_slots.py`, `run_enet_set.py`, their tests; a new `tools/test_run_enet_set.py` if needed).

Interface the acceptance tests call:
- `godot_slots.acquire_many(label, count, pid=None, wait_s=None) -> list`
- context manager `godot_slots(label, count, wait_s=None)`

Acceptance:
- `python -m unittest` for the touched tool tests passes, including a new test that reproduces the deadlock shape with fake processes and pids (two sets, one multi-slot holder, one exclusive request) and finishes.
- `python tools/lint_all.py` is GREEN.
