Objective: bots test placement legality at the same point the host uses. The host judges the centre of the rotated footprint (see core/rules and the Placement legality section of docs/SPEC.md); the bot code still passes the piece's pivot to the rule check in its candidate generation, strategy and think code.

Goal: every bot legality check uses the host's point, so bots stop proposing tilted or rolled placements the host refuses and stop skipping legal ones. Upright and yaw-only pieces must behave as before.

Acceptance: a unit test with a tilted or rolled piece near a territory edge, where pivot and centre disagree, shows the bot verdict equals the host verdict. Affected bot tests pass (python tools/affected_tests.py --path <checkout>). lint_all is clean; no magic numbers.

Owned scope: core/ai and tests/unit/bots. Not owned: core/rules, autoload/match.
Budget: 40 min. Targeted tests only (tools/run_gut.ps1 with -Path <checkout>); no bot matches.
Interface: bots must judge the same point the host does; BotStatics.OrientationInfo.center_shift already exists.
