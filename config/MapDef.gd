class_name MapDef
extends Resource
## One map's size and shape (spec 2.1). M1 only needs the round field and its
## radius; the S/M/L constants document the values every map size must use so
## later map variants (oval, ring, twin, cross) share the same scale.

const RADIUS_SMALL: float = 30.0
const RADIUS_MEDIUM: float = 45.0
const RADIUS_LARGE: float = 60.0

@export var id: StringName = &"round_medium"
@export var field_radius: float = RADIUS_MEDIUM
