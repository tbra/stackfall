#!/bin/sh
# Bontago-1pi.11.17 variant matrix, one factor at a time, on the real PHYSICAL_BALANCE scenario.
cd "$(dirname "$0")/.." || exit 1
B="--balance=1 --x=1 --run=50"
S=tools/probe_creep_sweep.sh
$S "" "$B" base
$S "" "$B --bounce=0" bounce0
$S "" "$B --rebound=1" rebound1
$S "" "$B --bf=2.0" bf2.0
$S "" "$B --bf=0.4" bf0.4
$S "" "$B --df=2.0" df2.0
$S "" "$B --df=0.4" df0.4
$S "" "$B --ldamp=1.0 --adamp=1.0" damp1
$S "" "$B --gscale=1.0" g1.0
$S "velocity_steps=384" "$B" vsteps384
$S "velocity_steps=64" "$B" vsteps64
$S "position_steps=16" "$B" psteps16
$S "body_pair_contact_cache_distance_threshold=0.001" "$B" cache1mm
$S "body_pair_contact_cache_distance_threshold=0.0" "$B" cache0
$S "penetration_slop=0.0001" "$B" slop0.1mm
