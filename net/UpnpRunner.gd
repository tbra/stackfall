class_name UpnpRunner
extends RefCounted
## Runs UpnpBackend jobs on a worker thread so a ~2 s router discovery never stalls a frame
## (Bontago-1pi.164). Jobs run strictly one at a time and in order, so a new host's OPEN can never
## be undone by the previous host's late CLOSE. Net calls start()/stop() and polls poll() each frame;
## shutdown() is the blocking quit-time variant.

enum State { IDLE, PENDING, OPENED, FAILED, UNSUPPORTED }
enum Job { OPEN, CLOSE, RENEW }

## Renew at half the lease: lease_seconds * this many milliseconds.
const _RENEW_MSEC_PER_LEASE_SECOND: int = 500

var state: State = State.IDLE
## Public IPv4 reported by the router once OPENED.
var external_address: String = ""
## Human-readable cause once FAILED / UNSUPPORTED.
var reason: String = ""

var _config: UpnpConfig = null
var _generation: int = 0
var _backend: UpnpBackend = null
var _port: int = 0
var _jobs: Array[Dictionary] = []
var _thread: Thread = null
var _running: Dictionary = {}
var _last_refresh_msec: int = 0


## Begins opening `port`; returns immediately. Any previous session is closed first.
func start(backend: UpnpBackend, port: int, config: UpnpConfig) -> void:
	stop()
	_config = config
	_backend = backend
	_port = port
	state = State.PENDING
	_jobs.append({"kind": Job.OPEN, "backend": backend, "port": port, "gen": _generation})
	_pump()


## Schedules the mapping's removal (a no-op when idle) and returns immediately.
func stop() -> void:
	if _backend != null:
		_jobs.append({"kind": Job.CLOSE, "backend": _backend, "port": _port, "gen": _generation})
		_backend = null
	_generation += 1
	state = State.IDLE
	external_address = ""
	reason = ""
	_pump()


## Call every frame. Returns true when `state` changed because an open finished.
func poll() -> bool:
	var changed: bool = false
	if _thread != null and not _thread.is_alive():
		changed = _collect()
	_schedule_renew()
	_pump()
	return changed


## Blocking quit-time teardown: removes any mapping, skipping opens that never started.
func shutdown() -> void:
	stop()
	var skipped: Array[UpnpBackend] = []
	for job: Dictionary in _jobs:
		if int(job["kind"]) == Job.OPEN:
			skipped.append(job["backend"] as UpnpBackend)
	_jobs = _jobs.filter(func(job: Dictionary) -> bool:
		return int(job["kind"]) != Job.RENEW and not skipped.has(job["backend"]))
	while _thread != null or not _jobs.is_empty():
		if _thread != null:
			_collect()
		_pump()


func is_busy() -> bool:
	return _thread != null or not _jobs.is_empty()


## True when a lease renewal is due and nothing else is queued (checked every poll).
func renew_due() -> bool:
	if state != State.OPENED or _config == null or _config.lease_seconds <= 0 or is_busy():
		return false
	return Time.get_ticks_msec() - _last_refresh_msec >= _config.lease_seconds * _RENEW_MSEC_PER_LEASE_SECOND


func _schedule_renew() -> void:
	if renew_due():
		_jobs.append({"kind": Job.RENEW, "backend": _backend, "port": _port, "gen": _generation})


func _pump() -> void:
	if _thread != null or _jobs.is_empty():
		return
	_running = _jobs.pop_front()
	_thread = Thread.new()
	_thread.start(_run_job.bind(_running))


## Worker thread body: only touches the job's own backend.
func _run_job(job: Dictionary) -> Dictionary:
	var backend: UpnpBackend = job["backend"] as UpnpBackend
	if int(job["kind"]) == Job.OPEN:
		return backend.open_port(int(job["port"]), _config)
	if int(job["kind"]) == Job.RENEW:
		backend.renew_port(int(job["port"]), _config)
		return {}
	backend.close_port(int(job["port"]))
	return {}


func _collect() -> bool:
	var result: Variant = _thread.wait_to_finish()
	_thread = null
	var job: Dictionary = _running
	_running = {}
	_last_refresh_msec = Time.get_ticks_msec()
	if int(job["kind"]) != Job.OPEN or int(job["gen"]) != _generation:
		return false
	var data: Dictionary = result as Dictionary
	if bool(data.get("unsupported", false)):
		state = State.UNSUPPORTED
		reason = str(data.get("reason", ""))
	elif bool(data.get("ok", false)):
		var address: String = str(data.get("address", ""))
		if JoinCode.is_public_ipv4(address):
			state = State.OPENED
			external_address = address
		else:
			state = State.FAILED
			reason = "router reported a non-public address (%s); it is behind another NAT" % address
	else:
		state = State.FAILED
		reason = str(data.get("reason", "unknown"))
	return true
