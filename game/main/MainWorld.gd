class_name MainWorld
extends RefCounted
## STUB (P7 plan section 2.1): null-object bodies, nothing wired; the filler package P7-Isbx implements it.
## The typed context the flows get instead of `Node3D main` and `as Main`.

## Where flows add_child (Main).
var parent: Node3D = null
var field: Field = null
var registry: BlockRegistry = null
var blocks_container: Node3D = null
var camera_rig: CameraRig = null
var world_environment: WorldEnvironment = null
var skybox: Skybox = null
var loader: AppLoader = null
var graphics: GraphicsApplier = null
