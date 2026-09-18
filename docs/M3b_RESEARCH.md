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
