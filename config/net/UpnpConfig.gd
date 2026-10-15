class_name UpnpConfig
extends Resource
## Tunables for opening the host's UDP port on the home router (Bontago-1pi.164, net/UpnpRunner.gd).

## Milliseconds the discovery broadcast waits for a router (blocks the worker thread, never a frame).
@export var discover_timeout_ms: int = 2000
## Multicast TTL for the discovery packet; Godot's default is 2.
@export var discover_ttl: int = 2
## Name the router lists the mapping under.
@export var mapping_description: String = "Stackfall"
## Lease in seconds, so a crash or kill cannot leave a permanent mapping; the runner renews it at half
## the lease while hosting and removes it when hosting stops and at quit. 0 = until removed (no renewal).
@export var lease_seconds: int = 3600
## Master switch (a LAN party never needs it).
@export var enabled: bool = true
