extends Node
## Windowed evidence probe for Bontago-d04 (owner report: "I grabbed a yellow
## cube but nothing seemed to happen"). Confirms game/GiftCrate.gd's claim-pop
## effect and ui/HUD.gd's "Special queued" toast actually render together, in
## a real running sandbox match (not a synthetic node in isolation). Same
## shape as tools/screenshot_hud_status.gd; not part of the running game
## (CLAUDE.md: manual-QA scripts live in tools/).
##
##   godot --path . --position 10000,10000 \
##       --scene res://tools/screenshot_gift_claim_feedback.tscn -- sandbox --players=2
##
## Spawns a real crate (Match._gifts._spawn_crate_at(), the same call
## MatchGifts._try_spawn() makes on a real roll) on slot 0's own home flag --
## ground it already owns, uncontested -- so the very next territory tick
## claims it exactly the way a real match would. Saves one screenshot a
## couple of seconds after the claim, while both the crate's pop effect and
## the HUD toast are still visible (GiftConfig's default durations are ~0.4s
## and ~2s respectively).

const OUTPUT_PATH: String = "res://feedback/gift-claim-feedback.png"
const SPAWN_SETTLE_FRAMES: int = 10
## Short on purpose: GiftConfig's default claim_pop_grow_duration_s (0.12s) +
## claim_pop_shrink_duration_s (0.28s) is a fast animation, so the screenshot
## needs to land close to the claim to still show the pop mid-flight; the HUD
## toast's own default hold (1.5s) comfortably outlasts this either way.
const CLAIM_SETTLE_FRAMES: int = 8


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	# Same 3.5s settle tools/screenshot_hud_status.gd's own precedent uses --
	# HUD._active_slot stays -1 (Events.turn_changed not fired yet) for a
	# beat after start_match(), and _on_gift_claimed()/_process() both no-op
	# while it does.
	await _wait(int(3.5 * Engine.physics_ticks_per_second))

	var home: Vector2 = Match.slot(0).home_position
	Match._gifts._spawn_crate_at(home)
	await _wait(SPAWN_SETTLE_FRAMES)

	# The real per-frame territory tick should already claim this on its own
	# next solve pass; one explicit call keeps the timing deterministic for a
	# screenshot instead of depending on exactly when that tick next lands.
	Match._gifts.claim_or_expire_gifts(0.0)
	await _wait(CLAIM_SETTLE_FRAMES)

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null and not dir.dir_exists("feedback"):
		dir.make_dir("feedback")
	image.save_png(OUTPUT_PATH)
	print("SCREENSHOT saved=%s size=%dx%d" % [
		ProjectSettings.globalize_path(OUTPUT_PATH), image.get_width(), image.get_height(),
	])
	get_tree().quit()


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
