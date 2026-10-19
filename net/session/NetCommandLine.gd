class_name NetCommandLine
extends RefCounted
## Turns the user arguments after Godot's "--" into a typed Options object, and
## scans the full command line for Steam's "+connect_lobby <id>" launch
## convention. Pure parsing: no scene tree, no Net, no side effects. The Net
## autoload calls parse() once and applies the result (spec 2.6 "Testing").
##
## Recognised: --host, --headless-host, --host-online, --advertise,
## --steam-public-lobby (bare flags); --port=<n>, --player-name=<s>,
## --join=<ip[:port]>, --sim-lag=<ms>, --sim-loss=<fraction>,
## --match-config=<path> (key=value). Any number of leading "-" is accepted.
## Unknown tokens are ignored. Bad numbers read as 0 (String.to_int/to_float
## semantics) and a later duplicate overwrites an earlier one; the consumer
## treats port <= 0 as "use the default".

const KEY_PORT: String = "port"
const KEY_PLAYER_NAME: String = "player-name"
const KEY_JOIN: String = "join"
const KEY_SIM_LAG: String = "sim-lag"
const KEY_SIM_LOSS: String = "sim-loss"
const KEY_MATCH_CONFIG: String = "match-config"
const FLAG_HOST: String = "host"
const FLAG_HEADLESS_HOST: String = "headless-host"
const FLAG_HOST_ONLINE: String = "host-online"
const FLAG_ADVERTISE: String = "advertise"
const FLAG_STEAM_PUBLIC_LOBBY: String = "steam-public-lobby"
const CONNECT_LOBBY_TOKEN: String = "+connect_lobby"
const JOIN_PORT_SEPARATOR: String = ":"


## What the command line asked for. Defaults mean "flag absent".
class Options extends RefCounted:
	## --sim-lag=/--sim-loss= appeared (either one); the missing one reads 0.
	var has_simulation: bool = false
	var sim_lag_ms: float = 0.0
	var sim_loss: float = 0.0
	var steam_public_lobby: bool = false
	## --port=<n>; 0 when absent or unparsable.
	var port: int = 0
	## --player-name=<s>; "" when absent.
	var player_name: String = ""
	var host: bool = false
	var headless_host: bool = false
	var host_online: bool = false
	var advertise: bool = false
	## --match-config=<path> appeared (the path may be empty).
	var has_match_config: bool = false
	var match_config_path: String = ""
	## --join=<spec> appeared.
	var has_join: bool = false
	## The address part of --join (before the last ":"), or the whole spec.
	var join_address: String = ""
	## The port part of --join=<ip>:<port>, else --port=, else 0.
	var join_port: int = 0

	## --host or --headless-host: this instance starts a listen server.
	func wants_host() -> bool:
		return host or headless_host

	## A --headless-host stays off the LAN browser unless --advertise opts back in.
	func lan_visible() -> bool:
		return not headless_host or advertise


## Parses `args` (normally OS.get_cmdline_user_args()).
static func parse(args: PackedStringArray) -> Options:
	var values: Dictionary = {}
	var flags: Dictionary = {}
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		var eq: int = text.find("=")
		if eq >= 0:
			values[text.substr(0, eq)] = text.substr(eq + 1)
		else:
			flags[text] = true

	var options: Options = Options.new()
	options.has_simulation = values.has(KEY_SIM_LAG) or values.has(KEY_SIM_LOSS)
	options.sim_lag_ms = String(values.get(KEY_SIM_LAG, "")).to_float()
	options.sim_loss = String(values.get(KEY_SIM_LOSS, "")).to_float()
	options.steam_public_lobby = flags.has(FLAG_STEAM_PUBLIC_LOBBY)
	options.port = String(values.get(KEY_PORT, "")).to_int()
	options.player_name = String(values.get(KEY_PLAYER_NAME, ""))
	options.host = flags.has(FLAG_HOST)
	options.headless_host = flags.has(FLAG_HEADLESS_HOST)
	options.host_online = flags.has(FLAG_HOST_ONLINE)
	options.advertise = flags.has(FLAG_ADVERTISE)
	options.has_match_config = values.has(KEY_MATCH_CONFIG)
	options.match_config_path = String(values.get(KEY_MATCH_CONFIG, ""))
	options.has_join = values.has(KEY_JOIN)
	if options.has_join:
		var spec: String = String(values[KEY_JOIN])
		options.join_address = spec
		options.join_port = options.port
		var colon: int = spec.rfind(JOIN_PORT_SEPARATOR)
		if colon >= 0:
			options.join_address = spec.substr(0, colon)
			options.join_port = spec.substr(colon + 1).to_int()
	return options


## The lobby id after the first "+connect_lobby" token in `args` (the full
## command line: the token has no "-" prefix, so OS.get_cmdline_user_args()
## never carries it), or 0 when absent, last without a value, non-numeric or
## not positive. Only the first occurrence counts.
static func connect_lobby_id(args: PackedStringArray) -> int:
	for i: int in range(args.size() - 1):
		if args[i] != CONNECT_LOBBY_TOKEN:
			continue
		var text: String = args[i + 1]
		if not text.is_valid_int():
			return 0
		return maxi(text.to_int(), 0)
	return 0
