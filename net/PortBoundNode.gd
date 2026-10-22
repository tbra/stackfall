class_name PortBoundNode
extends Node
## Base for the weather replication nodes (WeatherNet, SnowNet, BreezeNet): holds
## the session port and the Match authority port they read. A subclass names the
## methods it calls by overriding _session_methods() / _authority_methods(), so a
## narrow test double stays a valid port.
##
## STUB: signatures only. The bodies push_error and answer a safe default until
## the fill replaces them.


## Binds the ports. Returns false (and binds nothing) when either is null or invalid.
func bind(_session_port: SessionPort, _authority_port: MatchHostPort) -> bool:
	push_error("PortBoundNode.bind is a stub")
	return false


## The session methods this node calls; override in the subclass.
func _session_methods() -> PackedStringArray:
	push_error("PortBoundNode._session_methods is a stub")
	return PackedStringArray()


## The Match reads this node calls; override in the subclass.
func _authority_methods() -> PackedStringArray:
	push_error("PortBoundNode._authority_methods is a stub")
	return PackedStringArray()


## The bound session port, or one over the real Net autoload when none was bound.
func _session() -> SessionPort:
	push_error("PortBoundNode._session is a stub")
	return null


## The bound Match authority port, or one over the real Match autoload when none was bound.
func _authority() -> MatchHostPort:
	push_error("PortBoundNode._authority is a stub")
	return null
