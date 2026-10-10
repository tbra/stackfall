class_name UpnpBackend
extends RefCounted
## One router-port-mapping attempt (Bontago-1pi.164). The base class is the "unsupported" backend and
## the interface tests fake. Both methods run on UpnpRunner's worker thread and may block.


## Opens `port` (UDP) -> {"ok": bool, "address": String, "reason": String, "unsupported": bool}.
func open_port(_port: int, _config: UpnpConfig) -> Dictionary:
	return {"ok": false, "address": "", "reason": "UPnP is not available on this platform", "unsupported": true}


## Refreshes the lease of the mapping open_port() made. Returns success.
func renew_port(_port: int, _config: UpnpConfig) -> bool:
	return true


## Removes the mapping open_port() made; a no-op when nothing was mapped.
func close_port(_port: int) -> void:
	pass
