# Network options (Bontago-1pi.161)

**Summary.** Today: ENet for LAN, direct IP and tests; GodotSteam (lobbies + SteamMultiplayerPeer, which already
rides Valve's relay network) for online. One host runs Jolt physics and sends snapshots; clients send intents.
Steam already fixes NAT, invites and hiding IPs. The real gaps are: direct-IP play over the internet (needs port
forwarding), host leaving ends the match, a host can cheat, and no non-Steam players.
Nothing below fixes "host leaves" or "host cheats" except a dedicated server running our headless host.

**Near term: change nothing in transport.** Ship Steam (SteamMultiplayerPeer) + ENet. Spend effort on
real-AppID testing and a clear "port forward / use Steam" message for direct IP. Optional small add: noray
for direct-IP NAT punching (needs owner OK for an addon, plus a free small relay box).
**Later: if players ask for non-Steam builds or cheat-proof ranked play, run our headless host on a hosted
server (own VPS first, Edgegap/Hathora if we need regions).** Transport code stays; only who runs the host changes.

| Option | What it gives us | Cost / work | Catch |
|---|---|---|---|
| Current: ENet + GodotSteam | LAN, direct IP, tests; Steam invites, lobbies, NAT traversal, relay hides IPs. Already built | Done. Real AppID needs the Steam Direct fee (~$100) before release | Direct IP over internet needs port forwarding. Host leaves = match over. Host-trusted |
| Steam Sockets/Messages / Datagram Relay (inside GodotSteam) | Same relay and NAT help we already use; lower-level control (channels, priorities) | No new addon. Moderate work to bypass the Godot peer | Little gain: the peer already uses it. Only worth it for custom packet tuning |
| Epic Online Services (P2P + lobbies) | Crossplay with Epic/other stores, free | New addon (needs owner approval), second lobby/invite path, an EOS peer to maintain | Weeks of work; Godot EOS addons are community-run. Only useful off-Steam |
| WebRTC (built in) | No addon; NAT punching between peers | Needs our own signalling server plus a TURN relay for strict NATs; ~1-2 weeks | We would rebuild what Steam gives free. Fits a web build only |
| noray / NAT-punch relay | Direct IP without port forwarding for non-Steam ENet play | Small addon (netfox noray) + a free-tier or $5 VPS; days of work | Addon approval; some NATs still fail and fall back to relay |
| Own VPS headless host | Fixes host-leaves and cheating; fair latency for all; no IP exposure | ~$5-20/month; headless host exists (bot mode) but physics CPU per match is large (8 players, Jolt) | Ops work (deploy, restarts, matchmaking). Needs a spare player-less server slot in the lobby flow |
| Edgegap / Hathora (managed servers) | Servers started on demand near players, billed by use | Pay-per-use; container build of the headless host; a few days | Vendor lock-in; cost scales with matches; still needs a lobby/matchmaker (Steam lobby can serve) |
| Nakama / Photon | Accounts, matchmaking, relay | Nakama: self-host. Photon: no official Godot 4 support; paid | Bigger than we need; Photon relays do not run our physics anyway |
| Rollback / lockstep | Would remove the host | Large rewrite | Jolt is not deterministic across machines; rejected |

Notes: "Host leaves" can be softened without servers by host migration (hard with one physics owner; not advised).
The headless host and snapshot path already assume one authority, so a dedicated server is a deployment change,
not a rewrite. Facts are from the repo (SPEC §3.4 transports/model, net/SteamClient.gd, addons/godotsteam) and
general knowledge of these services; no web lookups, prices approximate and unverified.
