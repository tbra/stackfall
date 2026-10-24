# Agent-setup evals

A small fixed set of past work packages that measures whether a change to the agent setup
(`CLAUDE.md`, `.claude/`, `tools/`) helps or hurts. Each eval is a reconstructed brief, a base commit, an
accepted commit and hidden checks that already exist in Git history.

Files:
- `manifest.json`: eval name to `{area, base, accepted, brief, hidden[], regression[], interface_lines[], runner, lint_floor}`.
  `runner` is `gut` (script names for `tools/run_gut.ps1 -Path`) or `unittest` (paths for `python -m unittest`).
- `briefs/<name>.md`: the reconstructed brief, with the interface lines the hidden checks call.
- `review_brief.md`: the reviewer brief template used for every run.

Hidden checks are not copied into the repo: after a worker is done, the runner does
`git checkout <accepted> -- <hidden paths>` in the candidate worktree, so the worker never sees them. History
reachable from main must never be rewritten, or the manifest revisions stop resolving.

The worktree for a run carries the setup under test: it is made at the eval's base, then `CLAUDE.md`, `.claude/`
and `tools/` (excluding baseline state files) are overlaid from the setup revision and committed as the eval
base commit. All scoring diffs run against that commit.

## A/B procedure

1. **Baseline.** On the unchanged setup (setup revision S0) run every eval N=2 times (3 where the two runs
   disagree on hidden_pass), score each, render the scorecard. Keep it as `_evals/S0`. The spread between
   repeats of the same eval is the noise floor for every column.
2. **Change one thing.** Make a single process change (one rule, one skill edit, one tool) on a branch; its
   commit is S1. Overlay source is S1; the evals, models, routing, budgets and machine state stay identical.
3. **Rerun** the same evals and repeats; score; render `_evals/S1`.
4. **Compare** per eval and overall: hidden_pass and regression_pass must not drop; review H count must not
   rise; guard entries added stay 0. Then the metric the change claims to move (tokens, turns, lines added,
   first-try handback denials, review M/L, mutate score) must improve by more than the baseline repeat spread.
   Inside the spread: no evidence, treat as neutral.
5. **Decide.** Adopt if a claimed metric improved beyond noise and no gate above regressed; revert if any gate
   regressed or nothing moved (a rule that moves no metric is a pruning candidate for the prune pass); rerun
   once before reverting on a single-eval regression. Record the decision in the debrief with both scorecard
   paths and the one-line deltas.
6. **Hygiene.** The overlay never includes baseline state files; an eval run with a denied handback is scored,
   not discarded; evals are rebuilt (new base/accepted) only by a package that re-runs `verify`.

Two repeats cannot support significance tests; the procedure uses a spread rule, and says so.
