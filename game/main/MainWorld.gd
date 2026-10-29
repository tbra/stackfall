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
var skybox: Skybox = null
var loader: AppLoader = null
var graphics: GraphicsApplier = null
## The overlays the match flow drives, set by Main when it builds them (null until then).
var loading_screen: LoadingScreen = null
var pause_menu: PauseMenu = null

## State written by one flow and read by another (sandbox flow writes, match flow and Main read).
## Typed Node: Main must not name Sandbox/Tutorial (compile graph, MainFlowPort.gd).
var mode_extras: ModeExtras = null
var sandbox: Node = null
var tutorial: Node = null

## debug Watch bots: true from Main.start_watch_bots() until the session ends or returns to
## the menu; the match flow then builds a SpectatorController instead of a LocalPlayer.
var watch_bots_active: bool = false
