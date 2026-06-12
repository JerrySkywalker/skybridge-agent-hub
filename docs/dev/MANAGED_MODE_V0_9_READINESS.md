# Managed Mode v0.9 Readiness

Managed Mode v0.9 readiness is reached after the pilot and three one-at-a-time docs/local-smoke runs have completed with human-reviewed PRs.

## Completed runs

- `managed-mode-pilot-208`
- `managed-mode-run-209`
- `managed-mode-run-210`
- `managed-mode-run-211`

Runs 209, 210 and 211 are the three post-pilot one-at-a-time managed-mode docs/local-smoke runs. Run 211 finalized PR #151 after human review and records `managed_mode_run_211_completed`.

## Readiness model

- Status surface id: `managed_mode_v0_9_readiness`
- Resource gate: integrated and required before future run execution.
- General bounded queue apply: disabled.
- Multi-workunit apply: disabled.
- Next safe action: plan two-workunit preview only.
- No next execution is authorized by this readiness state.
- `token_printed=false`

## No-execution boundary

This readiness state does not authorize `start-all`, generic `start-queue` apply, generic bounded queue apply, `run-apply`, replacement run apply, pilot apply, retry apply, `resume -Apply`, unbounded worker loops, Codex worker execution, new workunit creation, new task creation, task claims, task PR creation or auto-merge.

Desktop and Web status surfaces should show the four completed runs, resource gate integration, disabled bounded queue controls, `no_next_execution_authorized=true` and `token_printed=false`.
