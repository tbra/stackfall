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
