Objective: placement legality is judged at the centre of the piece's rotated footprint, not at its pivot.

Background: the spec says legality uses one ray straight down from the ghost's middle. The host currently tests the piece's unrotated bottom-centre pivot (the ghost's global position) for placement, for throws and for the ghost validity preview. For upright pieces the two points coincide; for tilted or rolled pieces the pivot can sit 1-2 m from the piece's middle, so the verdict is wrong.

Goal: every legality test (placement, throw, the host and client ghost validity preview, and the closest-valid-point relocation) classifies the point under the horizontal centre of the rotated shape's bounds, projected straight down. The spawned body still uses its pivot as its origin.

Acceptance:
1. One pure helper computes the legality point from shape, basis and pivot, with unit tests: upright equals the pivot; a pillar lying along X or Z gives its middle; rolled and tilted pieces.
2. Placement, throw and preview use it. Relocation moves the piece so its centre lands on the valid point (pivot offset applied back); no double offset.
3. The host stays authoritative; the client ghost tint matches the host verdict for tilted pieces (test it).
4. Existing placement, refusal, throw, rule-scenario, match-flow and sandbox-placement tests still pass.
5. Do not edit the bots (game/bots, core/ai). If bots compute legality themselves and now disagree with the host for tilted pieces, list the spots in your handback.
6. Do not edit docs/SPEC.md.

Owned scope: autoload/match, core/rules, the ghost preview scripts under game/, and the matching tests under tests/unit.
Budget: 40 min. Targeted tests only (tools/run_gut.ps1 with -Path <checkout>); no bot matches, no ENet harness, no screenshots.
