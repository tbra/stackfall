class_name SoakConfig
extends Resource
## Every number the end-to-end soak gate uses: the monitor, the tick-budget curve, the intent
## fuzzer, the launcher and the offline report.
##
## Loaded as config/soak/soak_config.tres, which lists every field explicitly because tools/
## reads it as text. Tolerances are starting points until calibration pins them to a measured
## noise floor. Debug-only: nothing here reaches a shipped match rule.

# --- Run ---------------------------------------------------------------------

## Seconds a run lasts, counted from the client's first PLAYING state.
@export_range(1.0, 7200.0, 1.0, "or_greater") var duration_s: float = 900.0
## Seconds after the match starts during which no invariant is checked.
@export_range(0.0, 600.0, 1.0, "or_greater") var warmup_s: float = 30.0
## Seconds between samples. Samples sit on wall-aligned epochs, epoch = floor(unix_s / interval),
## so a host sample and a client sample can be matched offline.
@export_range(0.5, 60.0, 0.5, "or_greater") var sample_interval_s: float = 5.0
## A full per-body dump (SOAK_BODY lines) is written on every Nth sample.
@export_range(1, 1000, 1, "or_greater") var body_dump_every_samples: int = 6
## Seed passed to the host as --match-seed=.
@export var match_seed: int = 20261020
## One-way latency the client link simulates, in milliseconds (--sim-lag=).
@export_range(0.0, 1000.0, 1.0, "or_greater") var client_sim_lag_ms: float = 100.0
## Packet loss fraction the client link simulates (--sim-loss=).
@export_range(0.0, 1.0, 0.005) var client_sim_loss: float = 0.02
## Seconds the launcher waits for the host's first bot-match line before the run is invalid.
@export_range(1.0, 600.0, 1.0, "or_greater") var host_ready_timeout_s: float = 60.0
## Seconds past the run end before the launcher kills the process tree.
@export_range(1.0, 600.0, 1.0, "or_greater") var shutdown_grace_s: float = 120.0

# --- Agreement (host against client, evaluated offline by the report) -----------

## A client sample at epoch e matches any host sample in epochs e - k .. e, where k is this many
## seconds worth of epochs.
@export_range(0.0, 30.0, 0.1, "or_greater") var agree_window_s: float = 1.5
## A body missing from (or extra on) one side for less than this long is not a violation.
@export_range(0.0, 30.0, 0.1, "or_greater") var spawn_grace_s: float = 3.0
## Position difference, in metres, below which a settled body counts as converged
## (about 2 mm wire quantisation plus the 5 mm resend epsilon).
@export_range(0.0, 1.0, 0.001, "or_greater") var converge_pos_tol_m: float = 0.01
## Rotation difference, in degrees, below which a settled body counts as converged.
@export_range(0.0, 45.0, 0.1, "or_greater") var converge_angle_tol_deg: float = 1.0
## A body is at rest on the host when it sits at the same pose in this many consecutive dumps.
@export_range(1, 20, 1, "or_greater") var at_rest_min_dumps: int = 2
## How far the client's body count may stray from the host's min..max over the window.
@export_range(0, 1000, 1, "or_greater") var body_count_slack: int = 8
## Largest per-team territory share difference between host and client.
@export_range(0.0, 1.0, 0.001) var share_tol: float = 0.005
## Largest match-timer difference between host and client, in seconds.
@export_range(0.0, 60.0, 0.1, "or_greater") var timer_tol_s: float = 2.0
## Largest per-slot placed-block count difference between host and client.
@export_range(0, 100, 1, "or_greater") var score_tol: int = 0

# --- Authority (the client's intent fuzzer) -----------------------------------

## Seed of the fuzz plan, so a run replays the same intent sequence.
@export var fuzz_seed: int = 8331
## Seconds between fuzz batches.
@export_range(0.05, 60.0, 0.05, "or_greater") var fuzz_interval_s: float = 0.5
## A flood burst is this many times NetConfig.flood_place_burst intents in one tick.
@export_range(1.0, 100.0, 0.5, "or_greater") var fuzz_flood_factor: float = 3.0
## Seconds after the run starts before the fuzzer sends anything.
@export_range(0.0, 600.0, 1.0, "or_greater") var fuzz_start_after_s: float = 20.0

# --- Physics ------------------------------------------------------------------

## A tracked block lower than PhysicsTuning.kill_plane_y minus this margin, in metres (this far
## below the plane), is a violation (the field frees such a body, so a tracked one means it never did).
@export_range(0.0, 10.0, 0.1, "or_greater") var kill_plane_margin_m: float = 1.0
## A client body below the kill plane for less than this many seconds is not a violation: the
## client holds a falling body at its last snapshot until the host's despawn arrives. A host
## body below the plane is always one.
@export_range(0.0, 60.0, 0.5, "or_greater") var client_kill_grace_s: float = 6.0
## A client body that is not at rest and first appeared in a client dump less than this many
## seconds ago is not "client only": the host may have despawned it already. Host never graced.
@export_range(0.0, 60.0, 0.5, "or_greater") var client_despawn_grace_s: float = 6.0
## Largest awake / total block fraction once enough blocks exist.
@export_range(0.0, 1.0, 0.01) var awake_fraction_max: float = 0.6
## Block count from which the awake fraction is checked.
@export_range(1, 5000, 1, "or_greater") var awake_check_min_bodies: int = 200

# --- Territory ------------------------------------------------------------------

## Slack on "shares sum to at most 1" and on the owned-cell recount (unowned cells exist).
@export_range(0.0, 0.1, 0.0005) var share_sum_eps: float = 0.002
## Seconds a living home flag's cell may belong to another team before it is a violation.
@export_range(0.0, 60.0, 0.1, "or_greater") var home_foreign_grace_s: float = 1.0
## The uncached re-solve comparison runs on every Nth sample (host, clean board only).
@export_range(1, 1000, 1, "or_greater") var fresh_solve_every_samples: int = 12

# --- Budget ---------------------------------------------------------------------

## Tick budget as a fraction of 1000 / Engine.physics_ticks_per_second milliseconds.
@export_range(0.1, 4.0, 0.05) var tick_budget_fraction: float = 1.0
## Body-count centres of the tick-cost curve.
@export var curve_bands: PackedInt32Array = PackedInt32Array([250, 500, 1000, 1500])
## A band holds ticks whose body count is within this fraction of its centre.
@export_range(0.01, 0.5, 0.01) var curve_band_half_width_fraction: float = 0.15
## A band with fewer ticks than this is "not reached" and never a verdict.
@export_range(1, 100000, 1, "or_greater") var curve_min_ticks: int = 600
## Width of one histogram bucket of the tick-cost curve, in milliseconds.
@export_range(0.01, 10.0, 0.01, "or_greater") var curve_bucket_ms: float = 0.1
## Tick costs at or above this many milliseconds all land in the last bucket.
@export_range(1.0, 1000.0, 1.0, "or_greater") var curve_max_ms: float = 100.0
## Lowest physics frames per wall second, as a fraction of the physics tick rate.
@export_range(0.1, 1.0, 0.01) var sim_rate_min: float = 0.99
## Most snapshot bytes per second the host may send. DECISION: placeholder until calibration
## measures the baseline (no product bandwidth cap exists).
@export_range(0.0, 1.0e9, 1000.0, "or_greater") var snapshot_bps_max: float = 5.0e6
## Most megabytes of static memory one extra body may cost over a run.
@export_range(0.0, 10.0, 0.01, "or_greater") var mem_per_body_max_mb: float = 0.25
## Most orphan nodes allowed at the end of a run.
@export_range(0, 1000, 1, "or_greater") var orphan_nodes_max: int = 0
## Base of the monitor's own sample budget, in microseconds, before the per-body allowance.
@export_range(1, 1000000, 1, "or_greater") var monitor_overhead_us_max: int = 2000
## Microseconds the monitor's sample may take per tracked body (the sample walks every body).
@export_range(0, 10000, 1, "or_greater") var monitor_overhead_us_per_body: int = 15

# --- Launcher health ----------------------------------------------------------------

## Idle CPU load, in percent, above which the run is INVALID rather than failed.
@export_range(0.0, 100.0, 1.0) var idle_cpu_max_pct: float = 25.0
