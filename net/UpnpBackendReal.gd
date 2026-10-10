class_name UpnpBackendReal
extends UpnpBackend
## Godot's built-in UPNP behind the UpnpBackend interface. Tests never construct it (they would
## touch the real router); Net only builds it for the real autoload on a windowed, non-agent run.

var _upnp: UPNP = null
var _mapped: bool = false


func open_port(port: int, config: UpnpConfig) -> Dictionary:
	_upnp = UPNP.new()
	var found: int = _upnp.discover(config.discover_timeout_ms, config.discover_ttl)
	if found != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "address": "", "reason": "no UPnP router answered (code %d)" % found, "unsupported": false}
	var gateway: UPNPDevice = _upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {"ok": false, "address": "", "reason": "no usable UPnP gateway", "unsupported": false}
	var mapped: int = _upnp.add_port_mapping(port, port, config.mapping_description, "UDP", config.lease_seconds)
	if mapped != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "address": "", "reason": "router refused the port mapping (code %d)" % mapped, "unsupported": false}
	_mapped = true
	return {"ok": true, "address": _upnp.query_external_address(), "reason": "", "unsupported": false}


func renew_port(port: int, config: UpnpConfig) -> bool:
	if _upnp == null or not _mapped:
		return false
	return _upnp.add_port_mapping(port, port, config.mapping_description, "UDP", config.lease_seconds) == UPNP.UPNP_RESULT_SUCCESS


func close_port(port: int) -> void:
	if _upnp == null or not _mapped:
		return
	_upnp.delete_port_mapping(port, "UDP")
	_mapped = false
