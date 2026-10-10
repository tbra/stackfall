# tools/

Build-time and developer scripts that are not part of the running game.

## `bootstrap_project.gd`

Regenerates `project.godot`'s settings and Input Map from the values checked
into this script. Run it after adding a new input action, instead of
hand-editing the `[input]` section:

```
godot --headless --path . -s tools/bootstrap_project.gd
```

## `route_model.py`

One bounded TypeSafe/Jev request helps dispatch a semantic package: Claude tier,
independent review, split recommendation, verification tier and whether a visual
probe is useful. The brief comes from stdin. The script enforces hard review and
specialized-gate floors in code, caps targeted runs at two and windowed probes at
two, and takes a deterministic fast path for mechanical/known-gate work. With no
API key or after an 8-second request timeout, it returns bounded rules instead.
The orchestrator still names the actual tests and time budget in the worker brief.

```powershell
Get-Content brief.txt | python tools/route_model.py --title "Fix lobby state" --files net/Session.gd --kind bugfix --json
python -m unittest tools.test_route_model
```

## `rank_context.py`

Ranks up to ten candidate Beads issues or memories against a task using one Jev
Choice judgment. The caller first retrieves a shortlist with `bd search` or
`bd memories`, then passes JSON on stdin with `query` and `candidates` (`id`,
`text`). The result is one ID or `no_match`; this is a relevance hint, never
evidence to close or merge issues. Without TypeSafe or after eight seconds it
uses keyword overlap. No Beads writes occur. Run
`python -m unittest tools.test_rank_context` for its local checks.

## `triage_log.py`

Turns a long headless Godot run log into a short, ranked summary, so nobody
has to read a multi-thousand-line log by hand after the GUT suite, a
`tests/bench/*.tscn` benchmark, the M3a multi-instance harness, or (from M5
on) a `--headless-host --bots=N` run or an M8 soak test.

It does the cheap, free part in plain Python first: pull every `ERROR:` /
`WARNING:` / `SCRIPT ERROR:` line and its GDScript backtrace out of the log,
normalise away timestamps/addresses/net or instance ids/coordinates, and
group identical signatures with a count. That grouping is most of the value
and costs nothing. Only the resulting handful of *distinct* signatures are
then optionally sent to [TypeSafe](https://docs.typesafe.ai) (the `jev`
model) to judge which subsystem each belongs to, how severe it looks
(likely-bug / benign-noise / known-limitation), and whether it looks novel.
It also reads `docs/archive/M2_PLAN.md`'s "Known limitations" section and scans
`tests/` for any GUT test marked `pending()`, so already-accepted issues get
labeled instead of re-reported as new bugs.

### Running it

```
python tools/triage_log.py path/to/log.txt
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit > run.log 2>&1
python tools/triage_log.py run.log

# or pipe directly:
godot --headless --path . res://tests/bench/bench_rain.tscn 2>&1 | python tools/triage_log.py

# machine-readable output, and to gate CI on it:
python tools/triage_log.py run.log --json
```

Exits non-zero if anything was classified `likely-bug`, so it can gate CI
once M5's bot-match harness lands.

### `TYPESAFE_API_KEY`

The classification pass needs `TYPESAFE_API_KEY` in the environment (get one
at <https://console.typesafe.ai/>). **Never commit this key** -- this repo is
public. It is read from the environment only; the tool never writes it to a
file or prints it.

Without the key (or if the TypeSafe API call fails for any reason -- no
network, bad key, rate limit, timeout) the tool still prints the full
deterministic grouped-and-counted summary; it just says classification was
skipped and falls back to a cheap keyword-based subsystem guess. It never
crashes and never blocks the deterministic half on the network.

Useful flags: `--no-classify` (skip TypeSafe even if a key is set),
`--max-classify N` (cap how many distinct signatures get sent, default 40),
`--chunk-size N` (groups batched per TypeSafe request, default 6).

## `contact_sheet.py` and `ContactSheet.gd`

One small labelled grid PNG instead of several full-size screenshots.
`python tools/contact_sheet.py a.png dir/ "shots/*.png" -o sheet.png [--max-width 1280] [--columns N]`
prints the output path and size; `--self-test` builds a sheet from generated
images. `ContactSheet.save_capture(image, path)` (GDScript) replaces
`image.save_png(path)` in screenshot scripts and, in agent-probe mode, also
writes `<scene>_sheet.png` next to the captures (unlabelled cells, row-major
capture order, names printed). Retrofitted: screenshot_fog, screenshot_rain,
screenshot_pt7_pause.

## `bot_dataset.py`, `bot_fit_weights.py`, `bot_h2h.py` (bot training, Bontago-1t5.12; P1b options 1t5.20)

Python-only (stdlib) tooling for the recorder output described in
`docs/BOT_TRAINING_SOAK_PLAN.md` section 1 (schema v1).

```
python -I tools/bot_dataset.py validate|summarise|size <dir|files>   # strict schema v1; exit 1 on errors
python -I tools/bot_fit_weights.py <dir|files> [--mode N] [--write-proposal out.txt]
python -I tools/bot_h2h.py --candidate out.txt --pairs 50 --godot-args "..."   # --parallel defaults to 1
python -I tools/bot_h2h.py --dry-run --battery E1|E2|E3|E4|E5|all               # section 2.5 command lines
python tools/test_bot_dataset.py
python tools/test_bot_h2h.py
```

`bot_fit_weights.py` is the T1 offline refit: listwise softmax over the recorded
candidate terms, outcome-weighted (`d_share_30s` advantage), L2 toward the shipped
weights read from `config/`. It prints held-out top-1 agreement and regret plus a
weight diff, and never edits `config/` (`--write-proposal` refuses paths there).
`bot_h2h.py` runs paired same-seed, swapped-seat matches against the owner's ship
gate (>= 75 % win share over >= 100 matches). It needs the per-slot weight override
and match seed seam (plan BT5 `--bot-weights`), supplied through `--godot-args`;
until then use `--dry-run`.
Bontago-1t5.20 options: `--candidate` is optional when the template has no `{weights_file}`/`{weights_json}`
(for example a passive or legacy baseline); `--players N` adds `--players=N`; `--mode M` adds `--mode=M`;
`--no-swap` runs only the A-seat half and prints one `H2H seed=` line per match (the gate verdict stays
INSUFFICIENT under 100 matches); the summary adds `candidate_win_time_s median= max=` in game seconds.
`--battery E1..E5|all` (dry-run only) prints the section 2.5 command lines; their `<v2>`-style placeholders
must be filled in by hand, and a real launch refuses a template that still has one.
Headless bot log clock (Bontago-1t5.16): `HEADLESS_BOTS t=`/`done t=` and `HEADLESS_MATCH duration=`
are game time (physics ticks, the clock `--seconds` uses; `wall=` is the wall-clock extra field), so
under `--fixed-fps 60` `done t=` equals the cap. A run that hits `--seconds` while still PLAYING prints
`HEADLESS_MATCH ... winner_team=-1 ... timeout=1`; `bot_h2h.py` counts it as a draw and shows it as
`draws=N (timeouts=M)`, separate from `failed` (no HEADLESS_MATCH line at all).
