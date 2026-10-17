class_name GiftConfig
extends Resource
## Tunables for gift-crate spawning (spec 1.6).
##
## DECISION: spawning is a single Bernoulli roll once per placement window for the
## whole match (core/gifts/GiftSpawner.should_spawn()), not a timed interval (SPEC.md
## 2.6 "Gift spawning"); the lobby's special_frequency (0..100) linearly scales the
## roll's chance up to frequency_to_chance_max.
##
## Loaded once as config/gifts/gift_config.tres.
##
## "Once per window for the whole match" is enforced by the caller, not by
## should_spawn(): autoload/match/MatchGifts.gd rolls only for the lowest-indexed slot
## still alive on any feed-issue event, so N players still get exactly one roll per window.


## MatchConfig.special_frequency (0..100) maps linearly to a spawn chance of
## 0..this. 100 -> frequency_to_chance_max, 0 -> 0.0, monotonic in between.
@export var frequency_to_chance_max: float = 0.5

## Start grace: no spawn roll runs until this many seconds of host play have elapsed
## (the roll is skipped, not queued). Counted on host physics ticks while the match is live.
@export var first_gift_delay_s: float = 10.0

## Hard ceiling on simultaneously live crates. No new crate spawns while this many are
## already live and unclaimed.
## DECISION: the effective cap scales with the match: ceil(players / players_per_crate),
## clamped to 1..max_live_crates (GiftSpawner.live_cap()). Crates accumulate at most one
## per window, so the cap alone bounds the count. GiftConfig is not on the F4 roster, so
## no tuning_panel_hints entry is required.
@export var max_live_crates: int = 4
## Players needed per allowed live crate (2 players -> 1, 4 -> 2, 8 -> 4).
@export var players_per_crate: int = 2
## A newly spawned crate keeps at least this far (disk-local metres) from
## every other live crate so simultaneous crates never stack.
@export var crate_min_separation_m: float = 3.0

## Seconds a crate lives before it expires unclaimed (spec 1.6, "Crate life": 25 s).
@export var life_s: float = 25.0

## Descent begins this many metres above the field and advances on host physics ticks.
@export var drop_height_m: float = 18.0
@export var fall_speed_m_s: float = 2.0
## Small deterministic sideways motion; its envelope vanishes at both ends
## so the crate reaches the exact landing point used for claims.
@export var sway_amplitude_m: float = 0.45
@export var sway_frequency_hz: float = 0.33
## Additional clearance around the held block and crate for in-flight touch.
@export var air_touch_margin_m: float = 0.08
## Ignore remote cursor poses older than this; a stale pose cannot collect a gift.
@export var cursor_max_age_s: float = 0.5

## How far (meters, disk-local XZ distance) an expired crate's immediate replacement must
## land from the crate it replaces. MatchGifts._pick_relocation_point() retries the same
## seeded GiftSpawner.pick_spawn_point() logic up to spawn_max_attempts times until a
## candidate clears this distance, so replays stay deterministic under a fixed rng_seed.
##
## DECISION: 5.0 m -- large enough that a relocated crate never reads as the same crate
## next to a 1 m cube, small enough to fit inside a 20 m disk's edge-margined radius
## alongside spawn_edge_margin_m. Exempt from the F4 hints (see the "Claim feedback"
## DECISION below).
@export var relocate_min_distance_m: float = 5.0

## How many random points GiftSpawner.pick_spawn_point() tries before giving
## up and returning its sentinel.
@export var spawn_max_attempts: int = 32

## Keeps a spawn point this far from the disk's rim, in meters.
##
## DECISION: 2.0 m, a couple of cube widths (as TerritoryTuning.goal_zone_radius) --
## enough that a crate never lands where a 1 m cube's footprint would clip the rim,
## small enough to leave nearly the whole disk eligible on the smallest map.
@export var spawn_edge_margin_m: float = 2.0

## Caps each slot's FIFO of drawn-but-unspent specials. A claim landing while a slot's
## queue is already at this many leaves the crate alive for someone else instead of
## consuming it, so nothing a slot claims is ever silently discarded.
@export var max_pending_specials: int = 3

## -- Claim feedback: the claim-pop effect (game/gifts/GiftCrate.gd) and the claim toast
## (ui/hud/HUD.gd) that show a successful claim.
##
## DECISION: these live here rather than in GhostTuning's "-- HUD --" section because
## GhostTuning is on the F4 panel roster, where every new field needs a
## config/ui/tuning_panel_hints.tres description (and possibly a slider range).
## GiftConfig is not on that roster, so none of its fields needs a hints entry; GiftCrate's
## own DECISION already names GiftConfig as the home for such values.

## Scale multiplier the claim-pop effect grows to before shrinking away (1.0
## is unscaled, matching the claimed crate's own real size at the peak).
@export var claim_pop_scale_factor: float = 1.4
## Seconds the claim-pop effect takes to grow from 1.0 to claim_pop_scale_factor.
@export var claim_pop_grow_duration_s: float = 0.12
## Seconds the claim-pop effect then takes to shrink from
## claim_pop_scale_factor down to nothing, right before it frees itself.
@export var claim_pop_shrink_duration_s: float = 0.28

## Seconds ui/hud/HUD.gd's "Special queued: <name>" toast stays fully visible
## before it starts fading.
@export var claim_toast_visible_duration_s: float = 1.5
## Seconds the toast then takes to fade to invisible.
@export var claim_toast_fade_duration_s: float = 0.5

## -- Not-claimable hint: spec 1.6's claim rule is territory-only, so a held ghost over a
## crate outside the local player's territory does nothing by design; the pulse tells it
## apart from a claimable crate.
## How close (meters, disk-local XZ distance) the local player's held ghost
## must be to a live, unclaimable crate before its hint pulse starts.
@export var hint_pulse_radius_m: float = 1.5
## Radians/second the hint's colour blend oscillates at.
@export var hint_pulse_speed: float = 5.0
## The pulse blends UNCLAIMED_COLOR toward this and back (GiftCrate._update_hint()).
@export var hint_pulse_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## -- Spawn glow: a brief flash settles into a soft idle light
## around the pickup. GiftConfig is not on the F4 roster, so no hints entry.
## Seconds the flash takes to settle (and the halo to expand and fade).
@export var spawn_glow_duration_s: float = 0.7
@export var spawn_glow_start_energy: float = 2.4
## Persistent light energy once settled; GraphicsPreset.gift_idle_glow_enabled
## = false (Low) drops this to zero and hides the light.
@export var spawn_glow_idle_energy: float = 0.55
@export var glow_light_height_m: float = 0.45
@export var glow_light_range_m: float = 3.0
@export var spawn_halo_inner_radius_m: float = 0.53
@export var spawn_halo_outer_radius_m: float = 0.6
@export var spawn_halo_height_m: float = -0.2
@export var spawn_halo_alpha: float = 0.65
@export var spawn_halo_start_scale: float = 0.75
@export var spawn_halo_end_scale: float = 2.0

## -- Parachute: the visual canopy a crate wears while it descends. Purely cosmetic and
## client-side: it follows the replicated falling/landed state (GiftCrate.set_falling)
## and changes no descent speed, landing time, claim rule or network message.
## The model is built by game/gifts/ParachuteMesh.gd, animated by
## core/gifts/ParachuteAnim.gd and shown by game/gifts/GiftParachute.gd.

## Canopy rim radius in metres.
@export var chute_radius_m: float = 0.85
## Height of the dome above its rim, in metres.
@export var chute_dome_height_m: float = 0.55
## Height of the canopy rim above the riser point (where the lines converge).
@export var chute_rim_height_m: float = 0.95
## Height of the riser point above the crate's top face; four short harness
## lines run from it to the crate's top corners.
@export var chute_riser_height_m: float = 0.45
## Inset of the harness attachment points from the crate's edge, as the
## half-width of the square they sit on (metres from the crate's centre line).
@export var chute_attach_half_extent_m: float = 0.24
## Number of panels (gores); even so the two colours alternate all round.
@export var chute_gore_count: int = 12
## Rows of panels between the vent and the rim.
@export var chute_ring_count: int = 4
## Polar angle (radians from the top) at which the open vent ends.
@export var chute_vent_angle_rad: float = 0.22
## How far the middle of each panel's rim edge is lifted (the scallop), metres.
@export var chute_scallop_depth_m: float = 0.07
## Outward bulge of each panel's middle, as a fraction of the canopy radius.
@export var chute_billow: float = 0.06
@export var chute_color_a: Color = Color(1.0, 0.7, 0.19)
@export var chute_color_b: Color = Color(0.96, 0.93, 0.85)
@export var chute_line_color: Color = Color(0.92, 0.9, 0.82)
## Edge length of the thin prism each suspension line is drawn as, in metres.
@export var chute_line_thickness_m: float = 0.016

## Deploy: the canopy inflates from a narrow stream over this many seconds.
@export var chute_deploy_s: float = 0.9
@export var chute_deploy_start_radius_scale: float = 0.12
@export var chute_deploy_start_height_scale: float = 0.75
## Opening-shock overshoot (0 = none; ~1.7 is the classic 10% back-ease overshoot).
@export var chute_deploy_overshoot: float = 1.2

## Descent: a gentle pendulum lean about the riser, plus a slow breathing.
@export var chute_sway_hz: float = 0.4
## Peak lean in radians.
@export var chute_sway_tilt_rad: float = 0.09
## The second lean axis swings at this multiple of chute_sway_hz.
@export var chute_sway_axis_ratio: float = 1.31
@export var chute_breath_hz: float = 0.8
## Radius swells and height shrinks by this fraction at the peak of a breath.
@export var chute_breath_amount: float = 0.025

## Landing: the canopy deflates, sinks and fades over this many seconds.
@export var chute_collapse_s: float = 1.1
@export var chute_collapse_end_radius_scale: float = 0.9
@export var chute_collapse_end_height_scale: float = 0.08
@export var chute_collapse_drop_m: float = 0.55
## Fraction of the collapse after which the fade-out starts.
@export var chute_collapse_fade_start: float = 0.35
