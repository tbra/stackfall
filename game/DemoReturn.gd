class_name DemoReturn
extends CanvasLayer
## Bontago-1pi.34: back-to-menu glue for the dev demo scenes the main menu's
## Debug page opens (ui/MainMenu.gd's debug_scene_requested, handled by
## game/Main.gd's open_debug_scene()).
##
## The demos are separate scenes (the baked res://visual_demo/VisualDemo.tscn
## is script-free and gitignored, tools/gift_demo.tscn nests its own Main), so
## opening one is a plain scene change and nothing in them knows the menu
## exists. launch() therefore parks one of these nodes under the tree root --
## it survives the scene change -- and its only job is Esc / gamepad B
## (ui_cancel) -> change back to Main.tscn, then free itself.
##
## DECISION: the gift demo is listed in SELF_RETURNING_SCENES instead. It owns
## a real sandbox with its own pause menu (Esc = pause), so a second Esc
## handler would fight it; its own "Leave match" button calls return_to_menu()
## from tools/gift_demo.gd.
##
## DECISION: this lives in game/, not tools/: export_presets.cfg excludes
## tools/*, and game/Main.gd must still compile in an exported build (where the
## Debug entry never shows and launch() is never reached).

## Emitted when the player asks to leave the demo (before the scene change).
signal return_requested

const MAIN_SCENE: String = "res://game/Main.tscn"
## Demos that bring their own way back to the menu.
const SELF_RETURNING_SCENES: Array[String] = ["res://tools/gift_demo.tscn"]
const HINT_TEXT: String = "Esc / B: back to menu"
const HINT_LAYER: int = 90
const HINT_MARGIN_PX: float = 12.0
const HINT_ALPHA: float = 0.75

## Set by return_to_menu(), consumed once by game/Main.gd so coming back from a
## demo does not replay the splash screen.
static var _returning: bool = false

## Test seam: false skips the real scene change so a test can observe the signal.
var auto_return: bool = true


## Opens [param scene_path] as the running scene. ERR_FILE_NOT_FOUND (and no
## scene change) when it does not exist, e.g. the visual demo was never baked.
static func launch(tree: SceneTree, scene_path: String) -> Error:
	if not ResourceLoader.exists(scene_path):
		return ERR_FILE_NOT_FOUND
	if needs_glue(scene_path):
		tree.root.add_child(DemoReturn.new())
	return tree.change_scene_to_file(scene_path)


## True when [param scene_path] relies on this node for its way back.
static func needs_glue(scene_path: String) -> bool:
	return not SELF_RETURNING_SCENES.has(scene_path)


static func return_to_menu(tree: SceneTree) -> Error:
	_returning = true
	var err: Error = tree.change_scene_to_file(MAIN_SCENE)
	if err != OK:
		_returning = false
	return err


## True exactly once after return_to_menu() (then false again).
static func consume_returning() -> bool:
	var was_returning: bool = _returning
	_returning = false
	return was_returning


func _ready() -> void:
	layer = HINT_LAYER
	var hint: Label = Label.new()
	hint.text = HINT_TEXT
	hint.position = Vector2(HINT_MARGIN_PX, HINT_MARGIN_PX)
	hint.modulate.a = HINT_ALPHA
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	return_requested.emit()
	if auto_return:
		return_to_menu(get_tree())
	queue_free()
