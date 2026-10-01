class_name BenchPort
extends RefCounted
## Bontago-fca.4: lets a bench that boots Main with `--headless-host` coexist
## with other hosts (tools/run_m3a_local.ps1, parallel benches). Unless the
## command line already carries --port=<n>, binds-probes random UDP ports and
## points Net.config.game_port at a free one for this process only (the shared
## resource is never saved). Call before instancing Main.

const PORT_MIN: int = 48000
const PORT_SPAN: int = 10000
const MAX_TRIES: int = 50


static func claim_free_port(net: Node) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			return int(arg.get_slice("=", 1))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for _try: int in MAX_TRIES:
		var port: int = PORT_MIN + rng.randi() % PORT_SPAN
		var probe: PacketPeerUDP = PacketPeerUDP.new()
		var err: Error = probe.bind(port)
		probe.close()
		if err == OK:
			(net.get(&"config") as NetConfig).game_port = port
			return port
	return 0
