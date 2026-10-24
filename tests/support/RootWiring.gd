class_name RootWiring
extends RefCounted
## The global wiring game/main/Main.gd performs for a real run, for an ENet scene that
## runs as its own root (no Main) and drives SnapshotSync: Net's chat/UPnP wiring plus
## the SnapshotSync session binding. Call it first in _ready.


static func attach() -> void:
	Net.attach_global_wiring()
	SnapshotSync.bind_session(SessionPort.new(Net))
