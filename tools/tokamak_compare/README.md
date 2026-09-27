# Tokamak controlled reference

This runs the locally supplied Tokamak source, not Bontago. No Bontago-specific material, solver or sleep settings are known. Source defaults have explicit provenance:

- `feedback/tokamak_release/tokamaksrc/src/simulator.cpp:73–74`: friction `0.5`, restitution `0.4`; the runner queries `GetMaterial(0)` rather than replacing them.
- `tokamaksrc/src/rigidbody.cpp:150–154`: angular damping `0`, linear damping `0`, sleeping parameter `0.2`. Native `IsIdle()` is reported as `all_asleep`/`first_asleep_s`, but is not interchangeable with Godot sleep or visible stillness.
- Dimensions, mass, gravity and inertia are fixture inputs: a `0.98 m` box, `1 kg`, `9.8 m/s²` down, analytic uniform-box inertia, a fixed level 30 m square floor with top at zero. Both floor and cube use material zero.
- Fixed 60 Hz, ten simulated seconds; two-edge drop, or sequential three-box stack at 2 s intervals and a 0.3-edge release gap. Bottom starts resting for stack. Stack sleep/drift timing starts on third release.

The runner uses centre positions offset by half an edge to obtain the same bottom-relative heights as Stackfall's cell-origin bodies. Contact is first impulse/callback collision tick (enabled with `RESPONSE_IMPULSE_CALLBACK`); it is discrete, not continuous time of impact. Rebound is the maximum centre height after first contact minus resting centre height, divided by edge. CSV traces contain top-box positions on every tick. Stack drift only measures the top box after its release. Engine solver/contact conventions differ; this is configured behavior, not proof that either engine is intrinsically more bouncy.

## Build and run (PowerShell)

Extract Zig 0.13.0 into `feedback/tokamak-comparison/zig-windows-x86_64-0.13.0/`, then:

```powershell
pwsh -NoProfile -File tools/tokamak_compare/build.ps1
pwsh -NoProfile -File tools/tokamak_compare/run.ps1
```

Portable toolchain archive: https://ziglang.org/download/0.13.0/zig-windows-x86_64-0.13.0.zip

## Cube-on-cube impact probe

The `impact` mode starts a resting cube and drops a second cube from a gap of the specified height above it. An optional last argument offsets the falling cube horizontally in cube edges. This probes the owner's reported sideways/tumbling response without engine patches:

```powershell
feedback/tokamak-comparison/tokamak_compare.exe impact 1 2 0.3 feedback/tokamak-comparison/impact-1-0.csv 0
feedback/tokamak-comparison/tokamak_compare.exe impact 2 2 0.3 feedback/tokamak-comparison/impact-2-0.2.csv 0.2
```

Contact is filtered to the measured falling cube, drift is relative to its release position, and peak angular speed is reported in rad/s. The resting cube is dynamic, not artificially anchored. The original game still has not been measured.

SHA256: `d859994725ef9402381e557c60bb57497215682e355204d754ee3df75ee3c158`

Source, compiler, caches, executable, logs, records and traces stay under ignored `feedback/`; no third-party code is vendored. Compiler target is 32-bit Windows GNU (`x86-windows-gnu`) because this 2007 source uses 32-bit pointer assumptions; optimization is `-O2`. Floating-point behavior may differ from the original game's build. Engine source is compiled as supplied; portability fixes, if needed, must be listed here explicitly.
