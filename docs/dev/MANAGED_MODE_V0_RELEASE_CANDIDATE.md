# Managed Mode v0 Release Candidate

Managed Mode v0 is release-candidate ready after three one-at-a-time, human-reviewed docs/local-smoke runs.

## Completed Runs

| Run | Task PR | Merge commit | Changed files | Finalizer evidence |
| --- | --- | --- | --- | --- |
| managed-mode-pilot-208 | https://github.com/JerrySkywalker/skybridge-agent-hub/pull/140 | recorded in `.agent/tmp/managed-mode-pilot-208/finalizer-evidence.json` | `docs/managed-mode-pilot-orientation.md` | `.agent/tmp/managed-mode-pilot-208/finalizer-evidence.json` |
| managed-mode-run-209 | https://github.com/JerrySkywalker/skybridge-agent-hub/pull/144 | `d04edabebbb4255748bcad0e54aca63f74793587` | `docs/managed-mode-repeatability-orientation.md` | `.agent/tmp/managed-mode-run-209/finalizer-evidence.json` |
| managed-mode-run-210 | https://github.com/JerrySkywalker/skybridge-agent-hub/pull/148 | `cb0eec4d77234e740b747387afe96b1f9eadfaea` | `docs/managed-mode-v0-operator-checklist.md` | `.agent/tmp/managed-mode-run-210/finalizer-evidence.json` |

## RC State

- Final state: `managed_mode_run_210_completed`.
- Release state: `managed_mode_v0_release_candidate_ready`.
- Resource gate status: required for any future one-at-a-time run.
- Queue state: `active_tasks=0`, `stale_leases=0`, `runner_lock=none`.
- General bounded queue apply: disabled.
- Next execution authorization: `no_next_execution_authorized=true`.
- Token safety: `token_printed=false`.

## Smoke Hygiene

Historical dev-queue and Goal 199 fixture outputs are retained as historical evidence only. Parameterized queue-control harnesses such as `scripts/powershell/start-dev-queue-189-200.ps1` and `scripts/powershell/skybridge-dev-queue-control.ps1` should not be run standalone as release proof. Prefer focused managed-mode wrappers for RC checks.
