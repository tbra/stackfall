#!/bin/sh
# Bontago-1pi.11.17: run probe_creep variants; Jolt settings go through a temporary override.cfg
# (restored afterwards). usage: tools/probe_creep_sweep.sh "<jolt k=v;k=v>" "<probe args>" label
cd "$(dirname "$0")/.." || exit 1
cp override.cfg override.cfg.bak
J=physics/jolt_physics_3d/simulation
if [ -n "$1" ]; then
  printf '\n[physics]\n\n' >> override.cfg
  echo "$1" | tr ';' '\n' | sed "s#^#jolt_physics_3d/simulation/#" >> override.cfg
fi
timeout 400 godot --headless --log-file "${TMPDIR:-/tmp}/probe_creep_godot.log" --path . res://tools/probe_creep.tscn -- $2 --label=$3 2>&1 | grep -E "PROBE|SCRIPT|ERROR|TRACE"
cp override.cfg.bak override.cfg; rm override.cfg.bak
