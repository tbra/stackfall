Objective: one elimination path. When several players lose their homes in the same step, the match judges them once as a batch instead of one at a time (today the later slot wins when two homes are lost in one step).

Rules:
- Non-Elimination modes: last team standing wins; if zero teams survive, the win goes to the largest territory share among the teams eliminated in that batch, lowest team id on a tie (the same rule as the sudden-death tiebreak).
- Elimination mode keeps its shared-win tolerance.
- Classic's results carry no mode fields.
- Host-only as today. Replicated elimination and win events keep their shape: player_eliminated per slot in id order, and the win event before the match results.
- All callers that eliminate players use the one batch path; remove any duplicate per-mode elimination paths that become unused.

Starting point: the base has typed stubs for the batch entry in MatchLifecycle (eliminate_slots), the territory-side objective accessor and the objective hooks, with nothing wired.

Acceptance: test_elimination, test_match_flow, test_sudden_death, test_turn_based, test_late_join and test_late_join_silence pass (tools/run_gut.ps1 with -Path <checkout>); python tools/affected_tests.py --path <checkout> and run what it lists; lint_all is green. Do not edit docs/SPEC.md.

Owned scope: core/rules and autoload/match.
Budget: 40 min. Targeted tests only; no ENet harness, no soak.
Interface: no new names; the stubs above already exist at the base.
