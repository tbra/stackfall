class_name GlueDropTuning
extends Resource
## Host physics settings for blocks placed while Glue charges are active.

@export_range(1.0, 10000.0, 1.0) var break_force: float = 40.0
@export_range(1, 64, 1) var max_contacts_reported: int = 16
