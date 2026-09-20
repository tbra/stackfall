# M3b — Steam integration (GodotSteam): parallel build plan

Spec: §3.4 (this milestone), §2.8, §3.7, Part 4 M3. Research: `docs/M3b_RESEARCH.md`
(2026-09-18). Base: `main` @ `c377e9f`. **Bontago-mv0.2.1 (GodotSteam GDExtension spike) is
closed**: the addon installs cleanly in Godot 4.7.2 following README's "Steam setup
(development)" section, verified by `tools/check_steam_setup.ps1`. The **whole**
`addons/godotsteam/` directory is gitignored (`.gitignore`: `/addons/godotsteam/`), not just
the Valve redistributable inside it, so a fresh clone or worktree has **no `.gdextension`
file at all** — nothing loads, and the project-open gate is trivially clean without it. Each
developer installs the addon locally; every automated worktree/CI run that hasn't done so
exercises only the fallback path, which is why the `FakeSteam`-driven GUT tests below are this
milestone's only automated Steam coverage. **M3b is a peer swap in `autoload/Net.gd`, not a
gameplay change** (research: "`_make_host_peer()`/`_make_client_peer()` are the only functions
allowed to name a concrete peer class"; `net/MatchNet.gd`, `net/SnapshotSync.gd`,
`autoload/Match.gd`, `core/**` are out of scope). Two packages: P1 defines the new
Steam-facing interface on `Net`/`Events`/`NetConfig` and must land before P3 touches the UI
that consumes it.

## Questions for the owner

> **Answered 2026-09-19:** (1) friends-only. `NetConfig.steam_lobby_type` defaults to
> FriendsOnly; nothing else changes.

1. **Steam lobby visibility.** Spec §3.4 calls this "a friends-only game" (re: anti-cheat
   scope), but doesn't say whether "Join friend"'s lobby list should be **(a) friends-only**
   — `ELobbyType` FriendsOnly, so only lobbies your own Steam friends host are listed or
   joinable without a direct invite link — or **(b) public** — visible to any Stackfall
   tester worldwide sharing app id 480, easier for two testers who aren't already Steam
   friends but exposed to app 480's shared namespace (mitigated only by the `game`+`version`
   string filter research already recommends). The plan builds **(a)** as
   `NetConfig.steam_lobby_type`'s default — a single field a config edit flips — because it
   matches spec wording and because overlay invites and `+connect_lobby` work identically
   either way, so nothing else changes if the owner picks (b). Say the word; nothing else
   moves.

No M3b work changes a rule tagged **[ORIGINAL]** — this milestone touches transport only.

### P1 — Steam transport, session & lobby data — **sonnet** (`stackfall-netcode`; normal netcode work — the one genuinely subtle piece, extension-optional static typing, is resolved below by extending a pattern `Net.gd` already uses, not a new architecture problem, so no Opus escalation)

**Owns:** `autoload/Net.gd` (edit), `net/SteamClient.gd` (new), `config/NetConfig.gd` (edit) +
`net_config.tres`, `autoload/Events.gd` (append only), `tests/unit/support/FakeSteam.gd` (new),
`tests/unit/support/FakeNet.gd` (edit — extend to mirror Net's new methods; P3 reads this file,
does not edit it, to avoid two writers), `tests/unit/test_net_session.gd` (edit, already P1's
from M3a), `tests/unit/test_steam_client.gd` (new).
**Reads only:** `config/MatchConfig.gd`, and — once installed locally per README's "Steam
setup (development)" section, as it already is on this machine — `addons/godotsteam/
godotsteam.gdextension` to confirm singleton/class names; do not edit it, and don't assume it
exists in every checkout (see above).
**Must NOT:** touch `net/MatchNet.gd`, `net/SnapshotSync.gd`, `autoload/Match.gd`, `core/**`,
`ui/**`, `game/Main.gd`; write `SteamMultiplayerPeer` as a static type anywhere (see below);
add a new `--flag=value` parser for `+connect_lobby` — it is Steam's own convention, not
this project's, and needs its own scan (see below).

**Interfaces it exposes** (typed; consumed by P3 and, at boot, by the integrator's
`game/Main.gd`):

```gdscript
# autoload/Net.gd — appended to the existing session API
func steam_available() -> bool
func init_steam() -> void                                  # idempotent; called once by Main
func is_steam_session() -> bool                             # true once host_online()/join_lobby() has an active peer
func host_online(player_name: String = "") -> Error         # same contract as host_game()
func join_lobby(lobby_id: int, player_name: String = "") -> Error  # same contract as join_game()
func discovered_lobbies() -> Array[Dictionary]               # {"lobby_id","name","players","max","map"}
func refresh_lobby_list() -> void
func invite_friends() -> void                                # opens the Steam overlay invite dialog; no-op off Steam
```

```gdscript
# net/SteamClient.gd — the only file besides Net's _make_*_peer() that may touch
# the Engine "Steam" singleton or lobby-list/lobby-data calls (peer instantiation
# itself stays inside Net, per the existing isolation rule)
class_name SteamClient
extends RefCounted
signal init_result(status: int, verbal: String)
signal lobby_created(result: int, lobby_id: int)
signal lobby_match_list(lobby_ids: Array)
signal lobby_data_updated(lobby_id: int)
signal lobby_joined(lobby_id: int, response: int)
signal lobby_join_requested(lobby_id: int, friend_id: int)   # overlay "Join Game" / invite accept

func is_available() -> bool                                  # ClassDB.class_exists(&"Steam")
func init() -> void                                          # calls Steam.steamInitEx(480), emits init_result
func local_steam_id() -> int
func local_persona_name() -> String
func create_lobby(lobby_type: int, max_members: int) -> void
func set_lobby_data(lobby_id: int, key: String, value: String) -> void
func get_lobby_data(lobby_id: int, key: String) -> String
func lobby_owner(lobby_id: int) -> int
func lobby_member_count(lobby_id: int) -> int
func join_lobby(lobby_id: int) -> void
func leave_lobby(lobby_id: int) -> void
func request_lobby_list(string_filters: Array[Dictionary]) -> void  # [{"key","value"}]
func activate_invite_overlay(lobby_id: int) -> void

static func encode_match_config(data: Dictionary) -> String   # JSON.stringify, split out for a pure test
static func decode_match_config(text: String) -> Dictionary   # malformed/oversized text -> {} without erroring
```

`Net` gains `var steam_provider: Variant = null` set to a real `SteamClient.new()` in
`_ready()`, exactly the `net_provider`/`match_provider` seam `ui/MainMenu.gd`,
`ui/Lobby.gd` and `ui/NetDebugOverlay.gd` already use — tests overwrite it with `FakeSteam`.

**Events additions** (append only, per M3a's "the one expected conflict; every side only
appends" convention at `autoload/Events.gd`):
```gdscript
signal net_steam_status_changed(available: bool, detail: String)
signal net_steam_lobbies_discovered(lobbies: Array[Dictionary])
```

**Tests first:**
- `test_steam_client.gd`: `encode_match_config`/`decode_match_config` round-trip a
  `MatchConfig.to_dict()`-shaped Dictionary; malformed/truncated/random text decodes to `{}`
  without erroring (parity with `net/LanDiscovery.gd`'s `encode_advert`/`decode_advert` split
  at lines 169–241, which this mirrors deliberately).
- `test_net_session.gd` (extend): `steam_available()` is false and `host_online()` returns a
  transport error without creating a peer when `steam_provider` (a `FakeSteam`) reports
  unavailable; `host_online()` calls `FakeSteam.create_lobby` with `config.steam_lobby_type`
  and, once the fake emits `lobby_created`, calls `set_lobby_data` with the JSON-encoded
  config under the one config key (not a key per field, per the research's "MatchConfig as
  one JSON string" decision); `discovered_lobbies()` only returns lobbies whose `FakeSteam`
  data has `game == "stackfall"` and `version == Net.build_version()`, exercised with one
  matching and one foreign-tagged lobby id; parsing `+connect_lobby 12345` from a full
  argument list (not just `get_cmdline_user_args()` — see below) calls `join_lobby(12345, ...)`.
**Acceptance:** the full GUT suite passes with no real Steam singleton present (the normal
state for any worktree that hasn't run README's per-developer Steam install, which is most of
them) — every P1 test must pass driven entirely by `FakeSteam`, proving the gating logic never
needs the real extension. Because the addon is already installed on this machine
(Bontago-mv0.2.1 verified it loads clean here), **P1 also runs the windowed single-PC Steam
smoke test described below itself**, as part of this package's own validation rather than
leaving it solely to the integrator: confirm `Steam.steamInitEx(480)` reports status 0 in the
boot log, `host_online()` produces a lobby visible in Steam's own overlay browser, and
`refresh_lobby_list()` finds it. `godot --headless --editor --path . --quit` prints no
errors/warnings both before and after this package lands (it must not newly reference
`SteamMultiplayerPeer` as a type anywhere — see "Design notes").

### P3 — Menu & Lobby UI — **sonnet** (`stackfall-implementer`)

**Owns:** `ui/MainMenu.gd` + `.tscn` (edit), `ui/Lobby.gd` + `.tscn` (edit),
`tests/unit/test_main_menu.gd` (edit), `tests/unit/test_lobby.gd` (edit).
**Reads only:** `autoload/Net.gd` (P1's committed interface), `tests/unit/support/FakeNet.gd`
(P1-authored — do not edit), `config/NetConfig.gd`, `autoload/Events.gd`.
**Depends on P1 being committed first** — `_make_menu()`/`_make_lobby()` in the test files
construct a `FakeNet` (`tests/unit/test_main_menu.gd:11`, `tests/unit/test_lobby.gd:13`) whose
new fields P1 must have already added; a fresh worktree started from `main` before P1 lands
will not see them (`docs/AGENT_WORKFLOW.md`: "a new worktree cannot see uncommitted files").

**Work:**
- `ui/MainMenu.gd`: new controls `%HostOnlineButton` ("Host online (Steam)"),
  `%SteamLobbyList` (an `ItemList`, same row-building pattern as `_rebuild_game_list()` at
  line 104), `%RefreshSteamButton`, `%SteamUnavailableLabel` (spec §3.4: "Hide the online
  menu entries and show a notice"). `_ready()` checks `net_provider.steam_available()` once
  (Steam init is synchronous by the time `Main._ready()` reaches `_show_main_menu()` — see
  Integration order) and toggles the Steam section vs. the notice label; also connects
  `Events.net_steam_lobbies_discovered` the same way `_on_games_discovered` already handles
  `Events.net_games_discovered`. `_on_host_online_pressed()` calls
  `net_provider.host_online(_player_name())`; `_on_steam_game_activated(index)` calls
  `net_provider.join_lobby(lobby_id, _player_name())` mirroring `_on_game_activated` at line
  74. No raw Steam call anywhere in this file — only `net_provider` methods, the same
  discipline `_on_host_pressed`/`_on_direct_join_pressed` already keep for ENet.
- `ui/Lobby.gd`: one new `%InviteFriendsButton`, visible only when
  `net_provider.is_host() and net_provider.is_steam_session()`, calling
  `net_provider.invite_friends()`. **No other change** — the roster's `name` field
  (`_apply_roster()` at line 254, reading `entry.get("name", "?")`) already renders whatever
  string `Net` recorded for that peer at accept time; once P1's `host_online()`/`join_lobby()`
  default an empty `player_name` to `SteamClient.local_persona_name()`, Steam names appear
  with zero Lobby-side code change. Confirm this with a test, don't just assert it.
**Input Map:** none. Every new control is a plain `Button`/`ItemList` inside an existing
`Control` scene, so it inherits Godot's built-in `ui_accept`/`ui_focus_next`/`ui_up`/`ui_down`
actions the same way `%HostButton`/`%RefreshButton` already do — those are pre-bound to
keyboard **and** gamepad D-pad/face buttons by the engine itself, which is exactly why M3a's
P4 never touched `tools/bootstrap_project.gd` for its own eight new buttons. Only a
non-focus-flow shortcut (there isn't one here) would need a new action.

**Tests first:**
- `test_main_menu.gd`: the Steam section is hidden and the notice shown when
  `net_provider.steam_available_value = false`; pressing `%HostOnlineButton` calls
  `host_online_calls`; `Events.net_steam_lobbies_discovered` populates `%SteamLobbyList` the
  same way `test_games_discovered_populates_the_list` (line 78) proves for the LAN list;
  activating a Steam list row calls `join_lobby_calls` with the right `lobby_id`.
- `test_lobby.gd`: `%InviteFriendsButton` is hidden when `is_steam_session_value = false` (the
  ENet-hosted case, matching the existing `_make_lobby(true)` fixture at line 9) and visible
  when a host's fake reports `is_steam_session_value = true`; pressing it calls
  `invite_friends_calls`; a roster entry whose `name` came from a Steam persona renders
  unchanged through `_apply_roster()` (no special-casing needed — the point of the test is to
  pin that down, since nothing else here proves it).
**Acceptance:** full GUT suite passes; `godot --headless --editor --path . --quit` stays
clean; the existing `test_main_menu.gd`/`test_lobby.gd` ENet-path assertions are untouched and
still pass (regression).

## Integration order

1. **Bontago-mv0.2.1 is closed** — it already proved the addon installs clean on this machine
   and that the fallback path is safe on every checkout that hasn't installed it. Nothing in
   P1 or P3 touches `addons/godotsteam/**`, `README.md`, or `tools/`, and P1's tests are built
   to pass with **no real Steam singleton present** (see P1 acceptance), so neither package
   waits on it further.
2. **P1 first**, alone or in the same checkout as P3 if a fresh worktree for P3 isn't ready
   yet (`docs/AGENT_WORKFLOW.md`'s serialize-or-wait rule) — it defines `Net`'s new methods,
   the two `Events` signals, `NetConfig`'s new fields, and `FakeNet`'s matching extension, all
   of which P3's tests construct against directly.
3. **P3 second**, once P1's interface is committed (or in the same serialized checkout).
   Each merge must pass `godot --headless --editor --path . --quit` (no errors, no new
   warnings) and the full GUT suite before the next lands, same gate M3a used.
4. **Integrator** adds the one line `game/Main.gd` needs — `Net.init_steam()` right before
   `_show_main_menu()` in `_ready()` (`game/Main.gd:94`), so Steam's synchronous
   `steamInitEx()` has already answered by the time `MainMenu._ready()` reads
   `steam_available()`. `game/Main.gd` and `project.godot` remain nobody's file but the
   integrator's, same as M3a. The integrator also extends `Net.apply_command_line()`'s
   contract note (`autoload/Net.gd:445`) once P1 lands, since it now also scans the **full**
   `OS.get_cmdline_args()` for `+connect_lobby`, not just `get_cmdline_user_args()` — see
   Design notes.
5. Run: the full GUT suite; `godot --headless --editor --path . --quit` **twice** — once from
   a checkout with the addon installed locally per README (verified by
   `tools/check_steam_setup.ps1`), once from one that has never run that step, so the whole
   `addons/godotsteam/` directory is absent, not just a DLL inside it — since P1's changes are
   exactly the code path this matters for; the existing `tools/run_m3a_local.ps1 -Peers 4` ENet
   regression; then the owner's two-PC steps below (P1 already ran the windowed single-PC
   smoke test itself, per its own acceptance).

## Where every tunable lives — no magic numbers (CLAUDE.md)

| Resource | Owner | Holds |
|---|---|---|
| `net_config.tres` | P1 | `steam_lobby_type` (default FriendsOnly — verify the exact `ELobbyType` ordinal or `Steam.LOBBY_TYPE_*` constant GodotSteam exposes once the addon is installed locally), `steam_lobby_data_max_bytes` 8192 (**unverified** — spec's estimate; confirm against Steamworks' `isteammatchmaking.h` or public documentation and record the real limit), `steam_lobby_list_refresh_s` (Steam's `request_lobby_list` is pull-based, unlike the LAN advert's push; pick a sane poll interval, e.g. 5 s, and record it here, not as a literal in `ui/MainMenu.gd`) |
| existing `net_config.tres` fields, unchanged | P1 reads, does not add | `connect_timeout`, `handshake_timeout` — reused as-is for the Steam join path; no new Steam-specific timeout field, since `SteamMultiplayerPeer.create_client` needing a deadline is the same shape as ENet's |
| script `const` | P1 | `SteamClient` (or `Net`) holds the lobby-data **key names** — `game`, `version`, `map`, `match_config` — as `const StringName`, not `NetConfig` fields: they are wire protocol, the same reasoning `docs/M3a_PLAN.md` gives for `SnapshotSync.SNAPSHOT_CHANNEL`/`Net.HOST_PEER_ID` being consts, not tunables. Likewise `Net.STEAM_APP_ID_EXPECTED := 480`, passed directly into `Steam.steamInitEx(480)` — Bontago-mv0.2.1 confirmed `steam_appid.txt` is unnecessary once the app id is passed as an argument, so this project carries no such file |

## Design notes — the parts that are easy to get wrong

**Extension-optional static typing is the load-bearing constraint.** CLAUDE.md makes an
untyped declaration a compile error project-wide, and the fresh-clone/agent-worktree gate
(`godot --headless --editor --path . --quit`) parses **every** script regardless of what it
does at runtime. Bontago-mv0.2.1 confirmed the **whole** `addons/godotsteam/` directory is
gitignored (`.gitignore`: `/addons/godotsteam/`), not merely the Valve redistributable inside
it, so **every** checkout that hasn't run README's per-developer install has no
`.gdextension` file at all. The GDExtension zip itself (v4.22.1-gde) bundles Valve's
`steam_api64.dll`, so installing it needs no Steamworks partner account — but the directory's
outright absence from every other checkout is still the fact that matters here: **any script
that writes `SteamMultiplayerPeer` (or `Steam`) as a static type would fail to parse there**,
breaking the Definition-of-Done gate for the entire project, not just Steam code. `Net.gd`
already has the fix pattern in hand: `_apply_peer_timeout()` (line 803–818) reaches
`ENetPacketPeer.set_timeout` through `_peer.call("get_peer", id)` / duck-typed `.call(...)`
rather than a static type, specifically to avoid naming a concrete peer type outside
`_make_*_peer()`. P1's Steam peer creation must do the same, one level further: never write
`SteamMultiplayerPeer` as a type anywhere. Bontago-mv0.2.1 verified in 4.7.2, with the addon
installed, that `ClassDB.class_exists(&"Steam")` and `ClassDB.class_exists(&"SteamMultiplayerPeer")`
are both true — the check to gate on — while a checkout without the addon sees both false and
never reaches any Steam-shaped code. Inside `_make_host_peer()`/`_make_client_peer()` only:
```gdscript
if not ClassDB.class_exists(&"SteamMultiplayerPeer"):
    return null   # addon not installed in this checkout, or steam_available() raced it
var obj: Object = ClassDB.instantiate(&"SteamMultiplayerPeer")
var peer: MultiplayerPeer = obj as MultiplayerPeer   # MultiplayerPeer is a built-in engine class, always safe to type
if peer == null:
    return null
peer.set("server_relay", true)
peer.call("create_host", 0)   # channel argument stays 0 -- see next note
```
`SteamClient.is_available()` uses the same `ClassDB.class_exists(&"Steam")` check — false
whenever the addon isn't installed in this checkout, distinct from `Steam.steamInitEx()`
returning a non-zero status once the addon **is** loaded. Bontago-mv0.2.1 verified the actual
signature: `steamInitEx(app_id: int = 0, embed_callbacks: bool = false) -> Dictionary
{verbal, status}`, status `0` ok, `1` other failure, `2` Steam client not running, `3` Steam
too out of date. Log the "addon not installed" and "status != 0" cases with different
messages — the assignment asks for this explicitly — but they collapse to the same
`Net.steam_available() == false` for every UI purpose. Pass the app id straight into the
call — `Steam.steamInitEx(480)` — rather than relying on a `steam_appid.txt` file:
Bontago-mv0.2.1 confirmed that file is unnecessary once the app id is passed as an argument,
so this project carries none.

**Channels are out of this package's hands.** `net/SnapshotSync.gd:65` (`SNAPSHOT_CHANNEL =
1`) and `net/MatchNet.gd:35,864,1026` (`CURSOR_CHANNEL = 2`) are compile-time `@rpc` arguments
in files this milestone does not own. Research's decision ("no channel support... the
parameter must stay 0... `SNAPSHOT_CHANNEL`/`CURSOR_CHANNEL` simply become no-ops") assumes
`SteamMultiplayerPeer.set_transfer_channel()` silently ignores a nonzero channel rather than
erroring or dropping the packet — plausible, but **unverified until an actual two-endpoint
Steam session runs a snapshot and a cursor update**, which needs the real extension and
cannot be faked. If the smoke test or the owner's two-PC run shows an engine error or dropped
traffic tied to a nonzero channel, the fix is changing those two constants to `0` — a
one-line, low-risk change, but in files P1/P3 don't own; report it to the orchestrator as a
scoped follow-up rather than editing across the ownership line.

**The version check needs no new code.** Spec §3.4: "Compare the version when joining a lobby
and during the ENet handshake." `_rpc_handshake` (`autoload/Net.gd:573`) is already
peer-agnostic — it reads `multiplayer.get_remote_sender_id()` and compares
`_host_build_version`, both `MultiplayerAPI`-level, with no ENet-specific call in the whole
function. Once a `SteamMultiplayerPeer` is handed to `multiplayer.multiplayer_peer` the exact
same handshake runs unmodified and refuses a mismatched build exactly as
`test_mismatched_build_version_is_refused_and_disconnected` already proves for ENet. The only
Steam-side addition is cosmetic: filtering `discovered_lobbies()` by the `version` lobby-data
tag so a stale build doesn't even show up in the list before a doomed join attempt. Verify
this by reading the diff, not by writing a redundant test — `_rpc_handshake` should show **no
new branch**.

**`+connect_lobby` is not this project's own command-line convention.** Everything
`Net._apply_command_line_args()` parses today (`--host`, `--join=...`, `--sim-lag=...`) comes
from `OS.get_cmdline_user_args()` — the arguments **after** Godot's own `--` separator
(`autoload/Net.gd:451`, `game/Main.gd:272` uses the same call for `--hot-seat`). Steam invites
a running or newly-launched game with `+connect_lobby <id>` as two bare tokens appended
directly to the process's own argv, with no `--` and no `=` — Valve's launch-option
convention, not this project's. `OS.get_cmdline_user_args()` would **not** see it. P1's
`apply_command_line()` must additionally scan the **unfiltered** `OS.get_cmdline_args()` for
a `+connect_lobby` token followed by an id, independent of the existing `--flag=value` parser,
and call `join_lobby(id, ...)` when found. This is exactly why `test_apply_command_line_*`
above drives a full synthetic argument list rather than reusing
`_apply_command_line_args(PackedStringArray)`'s existing signature untouched — extend that
function (or add a sibling it calls) rather than bolt Steam parsing onto the `-`-stripping
loop that assumes `--`/`-` prefixes.

**Lobby data is the Steam-side lobby-list preview, same job the LAN advert does.** The LAN
advert Dictionary (`net/LanDiscovery.gd`'s `{game, version, name, players, max, map, port}`)
exists so a browser can show a row **before** joining. Steam's lobby object already tracks
member count and the max passed to `create_lobby()` natively (`lobby_member_count()`,
`lobby_owner()`), so only `game`, `version`, and a short `map` label need their own lobby-data
keys for the list row; the **full** `MatchConfig` (everything `ui/Lobby.gd`'s round trip needs
once actually inside the lobby) rides under one more key as the JSON string research
specifies. `Net.host_online()`/`set_lobby_data()` should therefore write both: the three flat
keys once, and the JSON key every time `ui/Lobby.gd` calls `set_lobby_data(data)` — reusing the
exact same call site `set_lobby_data()` already has (`autoload/Net.gd:354`), just teeing the
Steam write in alongside the existing RPC broadcast so `ui/Lobby.gd` needs no changes at all
for this half either.

## Testing without Steam

A plain GUT run has the real Steam singleton only on a checkout where the addon has been
installed locally (Bontago-mv0.2.1 confirmed it loads and registers `ClassDB` entries clean
there) — the default checkout has none at all. Either way, **every** P1/P3 test above is
written against `FakeSteam`/`FakeNet`, never the real singleton, so the suite is correct in
both states — this is the entire point of the `steam_provider`/`net_provider` seams, mirroring
how `test_net_sim.gd` and M3a's `FakeNet` let P1–P4 test session/UI logic without two real
machines. What genuinely cannot be tested headlessly: `ClassDB.instantiate(&"SteamMultiplayerPeer")`
succeeding, an actual overlay invite, and NAT traversal across two networks. For those:

**Windowed single-PC smoke test** (addon already installed on this machine per
Bontago-mv0.2.1; P1 runs this itself, per its own acceptance above, not just the integrator):
run `godot --path .` normally, confirm the boot log shows `Steam.steamInitEx(480)` returning
status 0 rather than the "not available" fallback message, press "Host online (Steam)",
confirm a lobby appears in the Steam overlay's own lobby browser (an independent check that
`create_lobby`/`set_lobby_data` actually reached Valve's servers, not just this game's own
code), and confirm this instance's own game sees itself in `%SteamLobbyList` after
`refresh_lobby_list()`.

**Owner's two-PC steps** (spec Part 4 M3 / Bontago-mv0.2's acceptance: "Two PCs on different
home networks play a full match over Steam"): both machines install the GodotSteam addon
locally per README's "Steam setup (development)" section (Bontago-mv0.2.1, verified there by
`tools/check_steam_setup.ps1`) — no Steamworks partner account needed, since the GDExtension
zip bundles Valve's `steam_api64.dll` itself; PC A hosts online, invites PC B through the
Steam overlay (or PC B activates PC A's `+connect_lobby` link); confirm the lobby round-trips
settings exactly as the ENet path does (`ui/Lobby.gd`'s existing round trip, spec §2.8);
confirm player names show each account's Steam persona; play a full match to a win condition;
then kill Steam on one PC mid-match and record what actually happens (research risk 3) against
the disconnect/grace-period behaviour `docs/M3a_PLAN.md`'s question 2 already answers — this is
observation, not a new decision, since `Match.on_peer_left`/`disconnect_grace` react to any
`Events.net_peer_left` regardless of why the peer vanished.

## Known limitations (planned, M3b)

- **`ClassDB.instantiate(&"SteamMultiplayerPeer")` is unverified by GUT** — P1 runs the
  windowed smoke test itself (addon installed on this machine) in addition to `FakeSteam` GUT
  coverage, but only the owner's two-PC run exercises two real peers over the internet.
- **Channel behaviour under `SteamMultiplayerPeer` is unverified** until a real session sends
  a snapshot and a cursor update; see "Design notes" for the one-line fix if it's wrong, which
  needs its own follow-up package since it touches files P1/P3 don't own.
- **Steamworks' lobby-data byte limits are a documented estimate**, not yet checked against
  Valve's own `isteammatchmaking.h` or public documentation — a reading task, not a download,
  now that Bontago-mv0.2.1 confirmed the addon itself needs no separate SDK install.
- **No Steam Rich Presence "Join Game" from the friends list itself** — only the in-game
  tagged-lobby list and the overlay's own invite dialog. A `setRichPresence("connect", ...)`
  call would add that later cheaply; out of scope here.
- **Public matchmaking across strangers on app 480 is out of scope** regardless of how
  Question 1 is answered — both options here mean "people who already know each other socially
  or via a shared link," not open matchmaking.
- **Late join / reconnect stays M8**, exactly as `docs/M3a_PLAN.md` already states; a Steam
  lobby refuses a joiner the same way once the match leaves LOBBY (`Net.accepting_joins()`
  is transport-agnostic, so this needs no new code either).
