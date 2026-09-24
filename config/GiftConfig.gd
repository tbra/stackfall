class_name GiftConfig
extends Resource
## Tunables for gift-crate spawning (spec 2.6).
##
## DECISION (config/GiftConfig.gd, M4 P1a): the 2026-09-20/22 evidence audit
## (docs/M4_PLAN.md header amendment; SPEC.md 2.6 "Gift spawning [ORIGINAL
## target]") retired the earlier reconstructed 20 -> 45 s / 100 -> 6 s spawn
## interval with jitter. Nothing here implements that mapping. Instead a
## single Bernoulli roll runs once per placement window for the whole match
## (core/gifts/GiftSpawner.should_spawn()); the lobby's special_frequency
## (0..100) linearly scales that roll's chance up to frequency_to_chance_max.
##
## Loaded once as config/gift_config.tres.
##
## M4 P1b review fix (Bontago-4fa): "once per placement window for the whole
## match" is enforced by the caller, not by should_spawn() itself --
## autoload/match/MatchGifts.gd rolls only for the lowest-indexed slot still
## alive on any given feed-issue event, so an N-player concurrent match still
## gets exactly one roll per window rather than N.


## MatchConfig.special_frequency (0..100) maps linearly to a spawn chance of
## 0..this. 100 -> frequency_to_chance_max, 0 -> 0.0, monotonic in between.
@export var frequency_to_chance_max: float = 0.5

## No new crate spawns while this many are already live and unclaimed.
@export var max_live_crates: int = 1

## Seconds a crate lives before it expires unclaimed (spec 2.6, "Crate life"
## owner decision: stationary pickups, 60 s is a prototype starting value).
@export var life_s: float = 60.0

## How many random points GiftSpawner.pick_spawn_point() tries before giving
## up and returning its sentinel.
@export var spawn_max_attempts: int = 32

## Keeps a spawn point this far from the disk's rim, in meters.
##
## DECISION (config/GiftConfig.gd): 2.0 m, a couple of cube widths (see
## TerritoryTuning.goal_zone_radius's own "couple of cube widths" precedent) --
## enough that a crate never lands somewhere a 1 m cube's footprint would
## already clip the rim, small enough to leave nearly the whole disk eligible
## even on the smallest map size.
@export var spawn_edge_margin_m: float = 2.0

## Caps each slot's FIFO of drawn-but-unspent specials (Orchestrator
## amendment 1, M4 P2b/Bontago-csc, 2026-09-23 — supersedes the earlier
## single-slot "latest wins" scalar). A claim landing while a slot's queue is
## already at this many leaves the crate alive for someone else instead of
## consuming it (amendment 3) — nothing a slot claims is ever silently
## discarded.
@export var max_pending_specials: int = 3

## -- Claim feedback (Bontago-d04, owner report "I grabbed a yellow cube but
## nothing seemed to happen"): spec 2.6's claim rule was never actually
## broken (a crate claims only when it lands inside the claiming slot's own
## territory — see MatchGifts.claim_or_expire_gifts()'s own doc), but a
## successful claim had *no visible feedback at all*: _free_crate_visual()
## just queue_free()s the crate node the instant it is claimed, and the HUD
## only silently refreshed a small text counter. This section's tunables
## drive game/GiftCrate.gd's claim-pop effect and ui/HUD.gd's claim toast.
##
## DECISION (config/GiftConfig.gd, Bontago-d04): these live here rather than
## in GhostTuning's own "-- HUD --" section, which is that resource's
## documented home for HUD tunables (ui/HUD.gd's own class doc references it)
## and where hud_reject_message_duration/hud_reject_fade_duration already
## live. GhostTuning is one of the six resources ui/TuningPanel.gd reflects
## onto the F4 panel (tests/unit/test_tuning_panel.gd's fixed roster of
## camera_tuning/ghost_tuning/physics_tuning/territory_tuning/
## territory_visuals/block_feed_config); any new @export field there needs a
## config/tuning_panel_hints.tres description or
## test_every_shown_field_has_a_non_empty_description fails, and a slider
## range too if the default is outside [0, 4x default] (AGENT_WORKFLOW.md).
## GiftConfig is not on that roster (grep confirms no "GiftConfig." key
## exists in tuning_panel_hints.tres) and is already the documented
## destination for exactly this kind of value — game/GiftCrate.gd's own
## older DECISION says as much: "move [CRATE_SIZE/UNCLAIMED_COLOR] into
## GiftConfig if a later package needs them configurable." Keeping every new
## field here is one fewer widely-shared file this package needs to touch,
## with no loss of CLAUDE.md's "every tunable lives in some res://config/
## resource" rule — GiftConfig is exactly that resource, just not wired to F4.

## Scale multiplier the claim-pop effect grows to before shrinking away (1.0
## is unscaled, matching the claimed crate's own real size at the peak).
@export var claim_pop_scale_factor: float = 1.4
## Seconds the claim-pop effect takes to grow from 1.0 to claim_pop_scale_factor.
@export var claim_pop_grow_duration_s: float = 0.12
## Seconds the claim-pop effect then takes to shrink from
## claim_pop_scale_factor down to nothing, right before it frees itself.
@export var claim_pop_shrink_duration_s: float = 0.28

## Seconds ui/HUD.gd's "Special queued: <name>" toast stays fully visible
## before it starts fading — mirrors GhostTuning.hud_reject_message_duration's
## own shape (show_reject()'s own tween_interval then tween_property), for the
## same reason the pop tunables above live here instead of there.
@export var claim_toast_visible_duration_s: float = 1.5
## Seconds the toast then takes to fade to invisible.
@export var claim_toast_fade_duration_s: float = 0.5

## -- Not-claimable hint (spec 2.6's claim rule is territory-only [ORIGINAL]:
## walking a held block/ghost over a crate that is not inside the local
## player's own territory does nothing by design, and used to look identical
## to a crate the player really could walk into and claim) -------------------
## How close (meters, disk-local XZ distance) the local player's held ghost
## must be to a live, unclaimable crate before its hint pulse starts.
@export var hint_pulse_radius_m: float = 1.5
## Radians/second the hint's colour blend oscillates at.
@export var hint_pulse_speed: float = 5.0
## The pulse blends UNCLAIMED_COLOR toward this and back (game/GiftCrate.gd's
## _update_hint()), so an unclaimable crate visibly shimmers instead of
## sitting static and reading exactly like a claimable one.
@export var hint_pulse_color: Color = Color(1.0, 1.0, 1.0, 1.0)
