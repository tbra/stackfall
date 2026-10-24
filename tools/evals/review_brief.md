# Eval review brief (template)

Role: stackfall-reviewer. Review the candidate for one eval run; do not edit files.

Inputs (filled in by the orchestrator):
- Checkout: <worktree path>. Eval base commit: <rev>. Candidate commit: <rev>.
- The worker's brief and handback: <paths>.

Review the diff `<eval base>..<candidate>` against the worker's brief. Check the brief's acceptance
criteria, host authority, static typing, tunables in `config/` Resources, one responsibility per class,
duplicated helpers, and whether the new logic has a test that fails when it breaks. Do not run the hidden
checks and do not run tests beyond what the brief names.

Severity: H = wrong behaviour, broken acceptance or a violated project rule that would block acceptance;
M = a defect that should be fixed before merging but does not break acceptance; L = style or minor note.

Handback: the `finding` field starts with `APPROVE` or `CHANGES`, then lists the counts in the form
`H1 M0 L2` (always all three), then one short reason. `CHANGES` is required when H or M is above 0.
