extends Node
## NetworkManager: transport selection, host/join, LAN discovery, peer registry.
##
## Gameplay code only ever talks to MultiplayerAPI; this node decides whether the
## peer underneath is ENet (LAN, direct IP, tests) or Steam (spec 3.4).
## Implemented in M3a/M3b.
