class_name BlockShape
extends Resource
## One placeable block shape: a set of unit-cube offsets plus feed weight
## (spec 3.6, 2.4). The block factory (game/BlockFactory.gd) turns this data
## into a RigidBody3D with one BoxShape3D per cell.

## Unique identifier, e.g. &"cube", &"bar3".
@export var id: StringName = &""

## Integer cube offsets from the shape's local origin. No two cells may repeat.
@export var cells: Array[Vector3i] = []

## Feed weight for the weighted bag (M2). Must stay positive so the M1 plain
## random pick can still use it as a relative likelihood.
@export var weight: float = 1.0

## Cells (must also appear in `cells`) whose collision and mesh should be a
## 45-degree wedge instead of a full cube. Spec 2.4: "the wedge needs a sloped
## collision shape". Empty for every shape except the wedge.
@export var sloped_cells: Array[Vector3i] = []

## Optional custom mesh; when null the factory generates one from `cells` and
## `sloped_cells`.
@export var mesh: Mesh = null
