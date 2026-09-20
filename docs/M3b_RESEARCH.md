# M3b research — GodotSteam / SteamMultiplayerPeer

Researched 2026-09-18 against Godot **4.7.2** (standard build, Windows). Findings
that cost a full research pass; read this before planning M3b.

> **GodotSteam moved to Codeberg.** The GitHub org was archived 2026-09-04 and is
> read-only. Use https://codeberg.org/godotsteam/godotsteam — docs at
> https://godotsteam.com.

## What to install

- **GodotSteam core, GDExtension package, v4.22.1** (released 2026-09-04,
  Steamworks SDK 1.65). GodotSteam's own blog names **Godot 4.7.2** as supported:
  https://godotsteam.com/blog/2026/08/22/godot-472-and-godotsteam-422--411/
- **Not** the precompiled editor build — it replaces the Godot binary, which
  conflicts with the pinned 4.7.2 shim in `CLAUDE.md` and with reproducibility
  for agents and CI.
- **`SteamMultiplayerPeer` is part of GodotSteam as of 4.17** — do *not* install
  the old standalone `codeberg.org/godotsteam/multiplayerpeer` repo (frozen at
  v4.16.2 / Godot 4.5.1).
- Steamworks SDK 1.65 is downloaded separately from Valve
  (partner.steamgames.com/downloads, free account). GodotSteam ships only its own
  binaries, not the SDK.

Layout per https://godotsteam.com/howto/gdextension/ — `res://addons/godotsteam/`
with `godotsteam.gdextension` and per-platform `win64/`, `linux64/`, `osx/`.

## Decisions already taken

- **Valve's redistributables (`steam_api64.dll`, `libsteam_api.so`, `.dylib`) stay
  out of git.** `tbra/stackfall` is public, and whether committing them there is
  covered by Valve's SDK Access Agreement — which grants redistribution "as part
  of your compiled game", not obviously as a cloneable repo file — could not be
  established. Each developer downloads the SDK and drops the file in locally;
  document it in `README.md`. GodotSteam's own MIT-licensed `libgodotsteam.*`
  binaries and the `.gdextension` file *are* committed.
- **Snapshots use sequence numbers, not channels.** `SteamMultiplayerPeer` has no
  real channel support (the parameter must stay 0). Spec §3.4 already specifies
  this fallback, and M3a's wire format carries a `u16 sequence` in every fragment
  header regardless of transport — so nothing changes in the format.
  `SnapshotSync.SNAPSHOT_CHANNEL` / `MatchNet.CURSOR_CHANNEL` simply become
  no-ops under Steam.
- **Use `Steam.steamInitEx()`, never `Steam.steamInit()`.** It returns
  `{"verbal", "status"}`; status 0 = ok, 2 = Steam client not running. The bare
  `steamInit()` is reported to crash in-editor. This is how §3.4's "hide online
  entries and fall back to LAN/direct IP" is implemented.
- **`server_relay = true`** on the peer routes client traffic through the host,
  matching the host-authoritative rule.

## The shape of the work

`autoload/Net.gd` was written so that `_make_host_peer()` and `_make_client_peer()`
are the only functions allowed to name a concrete peer class. `SteamMultiplayerPeer`
is a genuine `MultiplayerPeer` implementation handed to
`multiplayer.set_multiplayer_peer()` exactly like `ENetMultiplayerPeer`, and it
raises the same four signals. **M3b should be a peer swap, not a gameplay change.**

```gdscript
# host
var peer := SteamMultiplayerPeer.new()
peer.create_host(0)
peer.server_relay = true
# client
peer.create_client(Steam.getLobbyOwner(lobby_id), 0)
```

## App ID 480 (Spacewar)

- Lobbies, overlay invites and Steam's relay/NAT traversal all work under 480. A
  paid app ID ($100 Steam Direct, refundable) is **not** needed for M3b's
  acceptance test — only near release.
- **Everyone testing shares 480's lobby namespace.** Tag lobbies with
  `Steam.setLobbyData(id, "game", "stackfall")` plus a build-version string, and
  filter with `addRequestLobbyListStringFilter()` before `requestLobbyList()`.
- Store `MatchConfig` as **one JSON string under a single lobby-data key**, not a
  key per field. (Steamworks limits are believed to be key ≤ 255 chars, value
  ≤ 8192 bytes — *unverified*; check `isteammatchmaking.h` in the SDK.)
- Invites arrive two ways and both must be handled: `join_requested` callback if
  the game is already running, or Steam launching it with
  `+connect_lobby <lobby_id>` on the command line, read via `OS.get_cmdline_args()`.

## Risks to spike before committing to the plan

1. **Does the GDExtension actually load in this project's 4.7.2?** The zip is
   labelled "4.4+" rather than built per patch release; compatibility rests on
   GodotSteam's announcement, not a version-pinned artifact. Treat the first load
   as a spike, not a given.
2. **Headless open-project check.** Godot loads GDExtensions at project boot
   regardless of display server, and GodotSteam's docs say a *missing* shared
   library crashes the editor. Since the Valve binary is deliberately not in git,
   a fresh clone or agent worktree may fail `godot --headless --editor --path .
   --quit` — which is the Definition of Done gate for every step. Resolve this
   explicitly (document the local setup step, or gate the addon) before merging
   M3b. Note this is a *file-presence* problem, distinct from "Steam isn't
   running"; don't conflate them in the fallback logic or its tests.
3. **Transport error parity** beyond the four standard signals is undocumented —
   test by killing Steam mid-match.
4. **Two PCs over 480 across different home networks** is well attested by
   community practice but has no citable Valve guarantee. Prove it with an early
   two-machine test rather than building on the assumption.

Not a risk: GodotSteam crashes with double-precision builds, but this project uses
Godot's default single precision (checked `project.godot`).

## Spike results (2026-09-19)

Spike for Bontago-mv0.2.1, run in `M:/Bontago` on `main`@`c377e9f` (clean), Windows,
Godot 4.7.2. Full logs and the downloaded zip are in the worker's scratch directory
(outside the repo, not committed): `.../scratchpad/godotsteam/`.

### What was actually downloaded

Codeberg splits GodotSteam's releases into a per-Godot-version precompiled editor
(tag `v4.22.1`, assets like `win64-g472-s165-gs4221-editor.tar.xz` — `g472` = Godot
4.7.2 exactly, but this is the *replace-the-editor-binary* build CLAUDE.md says not to
use) and the GDExtension package (tag **`v4.22.1-gde`**, one universal asset). Verified
against the Codeberg API (`GET /repos/godotsteam/godotsteam/releases/tags/v4.22.1-gde`),
not guessed:

- URL: `https://codeberg.org/godotsteam/godotsteam/releases/download/v4.22.1-gde/godotsteam-4.22.1-gdextension-plugin-4.4.zip`
- File name: `godotsteam-4.22.1-gdextension-plugin-4.4.zip`
- Size: 27,290,405 bytes (matches the Codeberg API's `assets[0].size`)
- SHA-256: `2b12b3499434c50da16104a0d22b725aee15cc5cd41223c1cea825bae59bfa8f`
- Published: 2026-09-04

### Correction to "What to install" above: the zip bundles Valve's redistributable

The zip's listing (46 files, ~97 MB uncompressed) contains, per platform, **both**
GodotSteam's own `libgodotsteam.*` build **and** Valve's `steam_api*` file:
`win64/steam_api64.dll` (319,128 bytes), `win32/steam_api.dll`, `linux64/libsteam_api.so`
(and 32-bit/arm64 variants), `osx/libsteam_api.dylib`. This contradicts the "GodotSteam
ships only its own binaries, not the SDK" line above — for this v4.22.1-gde package it
is not true. **No separate partner.steamgames.com download was needed** to get a working
Windows install for this spike. (Whether GodotSteam is licensed to redistribute Valve's
file this way is between GodotSteam and Valve; it doesn't change our own decision below
about what *stackfall* commits.)

`addons/godotsteam/license.md` in the zip is GodotSteam's own MIT license (GP Garcia,
Chris Ridenour, and contributors) for "the Software" — i.e. GodotSteam's own source and
its compiled `libgodotsteam.*` outputs. It does not purport to relicense Valve's bundled
`steam_api64.dll`; that file is still Valve's redistributable under the Steamworks SDK
terms, just conveniently sitting in the same zip.

### Gate A — addon present (clean)

Installed the Windows-only subset into `res://addons/godotsteam/`:
`godotsteam.gdextension`, `license.md`, `win64/libgodotsteam.windows.template_debug.x86_64.dll`,
`win64/libgodotsteam.windows.template_release.x86_64.dll`, `win64/steam_api64.dll`. Godot
auto-generated `godotsteam.gdextension.uid` on first scan (same UID-sidecar mechanism as
`.gd.uid` files).

`godot --headless --editor --path . --quit`, run twice (import pass, then clean pass):
both exit 0, **no errors or warnings**.

`res://tools/steam_probe.gd` (headless `SceneTree` script; see that file) reported:

```
ClassDB.class_exists("Steam") = true
ClassDB.class_exists("SteamMultiplayerPeer") = true
Steam.steamInitEx(480, false) = { "status": 0, "verbal": "" }
```

The dev machine had `steam.exe` already running and logged in, so app ID 480 initialized
fully (status 0 = success) with **no `steam_appid.txt`** — the app ID was passed directly
as `steamInitEx`'s first argument, per godotsteam.com's initialization tutorial
(`Steam.steamInitEx(app_id: int = 0, embed_callbacks: bool = false) -> Dictionary`,
returning `{"verbal": String, "status": int}`; 0 = ok, 1 = other failure, 2 = client not
running, 3 = client out of date). `steamInitEx` — never bare `steamInit()` — matches the
decision already taken above. Status 2 (client not running) was not observed on this
machine but is documented as an equally fine spike outcome per the assignment; not
independently verified here.

### Gate B — Valve redistributable missing (reproduces risk 2)

Moved `win64/steam_api64.dll` out (kept elsewhere) and reran the open-project check.
**Exit code stayed 0**, but stdout/stderr gained, every run:

```
ERROR: Can't open dynamic library: .../win64/libgodotsteam.windows.template_debug.x86_64.dll. Error: Error 126: The specified module could not be found..
   at: open_dynamic_library (platform/windows/os_windows.cpp:544)
ERROR: Can't open GDExtension dynamic library: 'res://addons/godotsteam/godotsteam.gdextension'.
   at: open_library (core/extension/gdextension.cpp:811)
ERROR: Error loading extension: 'res://addons/godotsteam/godotsteam.gdextension'.
   at: load_extensions (core/extension/gdextension_manager.cpp:333)
```

Restored the file and re-verified clean. This is risk 2 from above, confirmed exactly:
**a missing Valve binary does not crash the editor, but it does print ERROR lines that
fail the "no errors or warnings" Definition-of-Done gate**, even though the process exits
0. A log-triage or CI gate that treats any ERROR line as a failure (as this project's does)
would flag it.

### Whole-addon-absent test, and why the naive version of it was misleading

First attempt — moving `addons/godotsteam/` aside entirely and rerunning — *still* printed
the same ERROR lines, which looked like Godot remembers a stale extension path. Root cause
tracked down: this repo's `.godot/` cache (gitignored, not evaluated fresh) still held state
from the previous "addon present" runs. Clearing `.godot/` (safe: it's wholly gitignored and
regenerates automatically) and rerunning with the addon folder genuinely absent gave a
**completely clean** result — no output at all beyond the normal init/layout steps. Godot's
GDExtensionManager only attempts to load a `.gdextension` file that it discovers in a fresh
filesystem scan; if none exists, nothing Steam-related happens. `.godot/` was restored to its
original snapshot afterward.

This matters because it changes the fresh-clone diagnosis: the failure mode isn't "the addon
folder is missing" (that's silently fine), it's specifically "**the `.gdextension` file is
present but the platform library or Valve dependency it names is not**" — i.e. a *partial*
install.

To make sure this generalizes to what a real fresh clone would see under the *current*
`.gitignore` (unedited by this spike — see the negation-rule discussion below), a further
test left only `godotsteam.gdextension` and `license.md` in place (the two files that
`.gitignore` does **not** currently exclude) with every `.dll` removed. Result: the same
`ERROR: GDExtension dynamic library not found` / `ERR_FILE_NOT_FOUND` output as Gate B,
plus two `WARNING: Canceling suspended execution of "..." due to a script reload` lines
triggered by the failed load. **This means committing just the `.gdextension` file (the
current `.gitignore`'s effective behavior, since it lets `.gdextension`/`.md` through but
blocks every `.dll`) already fails the DoD gate on a fresh clone, with zero further edits
needed to reproduce it.**

### `.gitignore` — exact files git would track today, and what changing that would need

`git status --short` after installing showed `addons/godotsteam/` as untracked (`??`).
Checked with `git check-ignore -v` per file:

| File | Tracked under current `.gitignore`? |
|---|---|
| `godotsteam.gdextension` | Yes (would be tracked) |
| `license.md` | Yes (would be tracked) |
| `win64/libgodotsteam.windows.template_debug.x86_64.dll` | No — caught by both the global `*.dll` rule (line 12) and `addons/godotsteam/**/*.dll` (line 20) |
| `win64/libgodotsteam.windows.template_release.x86_64.dll` | No — same two rules |
| `win64/steam_api64.dll` | No — same two rules |

So today, GodotSteam's own MIT-licensed DLL is caught by the same blanket rule meant only
for Valve's file — the earlier "Decisions already taken" bullet above (commit
`.gdextension` + `libgodotsteam.*`, keep `steam_api64.dll` local) is not actually possible
without a `.gitignore` change. The exact negation needed, if that decision were kept, would
be two lines added after the existing exclusions (order matters — a later `!` pattern wins
over an earlier `*` exclusion as long as no parent directory is itself excluded, which is
true here):

```gitignore
!addons/godotsteam/win64/libgodotsteam.windows.template_debug.x86_64.dll
!addons/godotsteam/win64/libgodotsteam.windows.template_release.x86_64.dll
```

`libgodotsteam.windows.template_release.x86_64.dll` (and the debug variant) is
**licence-safe to commit** — it's GodotSteam's own compiled output, covered by its
bundled MIT `license.md`. `steam_api64.dll` should stay excluded regardless, unchanged
from the original decision.

**This spike does not recommend taking that path**, though — see the next section. No
`.gitignore` edit was made (out of ownership for this task); this table is the evidence
for whoever decides.

### Revised recommendation: keep `addons/godotsteam/` entirely untracked

Even with the negation rule above, a fresh clone still has `.gdextension` +
`libgodotsteam.*` present but `steam_api64.dll` absent (Valve's file, correctly never
committed) — which is exactly Gate B, which fails the "no errors/warnings" gate. Committing
part of the addon does not avoid the problem; it just narrows it to one missing file
instead of four, and that one file is unavoidably absent in every fresh clone by design.

The only state that is genuinely clean on a fresh clone, confirmed empirically above, is
**no `.gdextension` file present at all**. So: `res://addons/godotsteam/` stays wholly
untracked — none of `.gdextension`, `license.md`, or any `.dll` get committed. Each
developer runs a one-time local install (documented in `README.md`, "Steam setup
(development)") that drops in the whole zip's Windows subset at once, never partially.
`tools/check_steam_setup.ps1` (added by this spike) tells a developer which of the two
supported states — absent, or fully installed — they're in, and flags the one unsupported
state (partial install) with the exact missing files.

This supersedes the "Decisions already taken" bullet above about committing GodotSteam's
own binaries; it does not change the Valve-redistributable-stays-out-of-git decision, which
this spike's evidence reinforces rather than revisits.

`.gitignore` was not edited to formalize this (e.g. a single `/addons/godotsteam/` line
would make the intent explicit and guard against a future `git add -A` accidentally staging
`.gdextension`/`license.md`); that edit is outside this task's ownership and is recommended
as a small follow-up for whoever has `.gitignore` authority.

### Full GUT run with the addon installed

`godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`, addon
fully installed: **515 tests, 514 passing, 1 pending** (the known `test_field_cells.gd`
hole-radius limitation, unchanged from before this spike), 11,682 asserts, ~1114 s. No
`godotsteam`, `steam_api`, or `SteamMultiplayerPeer` string appears anywhere in the run's
output — GUT's `-gdir=res://tests` scope means it never touches `addons/godotsteam` — so
the addon's presence is a no-op for the existing test suite, as expected pre-M3b
implementation.

### Not verified in this spike

- Status 2 (Steam client not running) was not observed — this dev machine's Steam client
  was already running and logged in. Not a blocker; both status 0 and 2 are documented as
  acceptable spike outcomes.
- Linux/macOS installs and their `.so`/`.dylib` equivalents (Windows-only spike, per
  CLAUDE.md's Environment section and this task's scope).
- Transport error parity beyond the four standard signals (risk 3) and the two-PC/two-network
  claim (risk 4) — both explicitly out of scope for this spike; still open for the real M3b
  implementation.
