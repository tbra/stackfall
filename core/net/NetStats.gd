class_name NetStats
extends RefCounted
## One reading of the network data path for the F3 panel. Data only.

enum Role { OFFLINE, HOST, CLIENT }  # same order as Net.Mode


class PeerRow extends RefCounted:
	var peer_id: int = 0
	var slot_id: int = 0
	var name: String = ""
	var rtt_ms: float = 0.0
	var rtt_jitter_ms: float = 0.0


class IntentRow extends RefCounted:
	var slot_id: int = 0
	var sent: int = 0
	var accepted: int = 0
	var refused: int = 0
	var cursors_refused: int = 0


var role: Role = Role.OFFLINE
var local_slot: int = 0
var peers: Array[PeerRow] = []  # host: every remote peer; client/offline: empty
var local_rtt_ms: float = 0.0  # client: RTT to the host as the host reports it
var snapshot_bytes_per_s: float = 0.0  # host: sent; client: applied
var snapshots_per_s: float = 0.0
var last_snapshot_bytes: int = 0
var last_snapshot_bodies: int = 0  # host only
var last_snapshot_fragments: int = 0  # host only
var interp_delay_ms: float = 0.0  # client only from here
var arrival_jitter_ms: float = 0.0
var loss_fraction: float = 0.0
var dropped_unknown: int = 0
var intents: Array[IntentRow] = []  # host: slots with a non-zero counter; client: own slot (sent only)
var sim_lag_ms: float = 0.0  # the live NetSim values
var sim_loss: float = 0.0
