class_name PortBoundNode
extends Node
## Base for the weather replication nodes (WeatherNet, SnowNet, BreezeNet): holds
## the session port and the Match authority port they read. A subclass names the
## methods it calls by overriding _session_methods() / _authority_methods(), so a
## narrow test double stays a valid port. Unbound, the ports are built over the Net
## and Match autoloads on first use, which is what every shipped build uses.


var _session_port: SessionPort = null
var _authority_port: MatchHostPort = null


## Binds the ports. Returns false (and binds nothing) when either is null or invalid.
func bind(session: SessionPort, authority: MatchHostPort) -> bool:
	if session == null or authority == null or not session.is_valid() or not authority.is_valid():
		return false
	_session_port = session
	_authority_port = authority
	return true


## The session methods this node calls (empty = the whole port); override in the subclass.
func _session_methods() -> PackedStringArray:
	return PackedStringArray()


## The Match reads this node calls (empty = the whole port); override in the subclass.
func _authority_methods() -> PackedStringArray:
	return PackedStringArray()


## The bound session port, or one over the real Net autoload when none was bound.
func _session() -> SessionPort:
	if _session_port == null:
		_session_port = SessionPort.new(Net, _session_methods())
	return _session_port


## The bound Match authority port, or one over the real Match autoload when none was bound.
func _authority() -> MatchHostPort:
	if _authority_port == null:
		_authority_port = MatchHostPort.new(Match, _authority_methods())
	return _authority_port
