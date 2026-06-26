# Bootstrap Alpha RC Release Notes

RC name: Bootstrap Alpha RC

Baseline commit: `8499ccba39894fdfccb7b29ddfe72db142ddb711`

Current image:
`ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-8499ccba39894fdfccb7b29ddfe72db142ddb711`

Bootstrap Alpha RC is a release-candidate freeze and audit package for the
current SkyBridge Agent Hub Bootstrap Alpha state. It does not add runtime
capability. It documents the bounded cloud/server, Desktop, local worker,
template runner, MATLAB golden task, Codex native report, and evidence chain
that was proven through MG324-MG339.

## MG324-MG339 Chain

- MG324 product flow freeze: froze the Bootstrap Alpha product path, scope, and
  roadmap around cloud server, Desktop, local worker, chat-to-task, template
  registry, reviewed submit, and template-bound runners.
- MG325 Desktop worker service manager: added local worker service status,
  doctor, install-preview, and repair-preview visibility with execution disabled.
- MG326 Chat-to-Task draft planner: added preview-only natural-language draft
  generation with no server task creation, prompt persistence, Codex run, or
  MATLAB run.
- MG327 Task template registry: added the read-only Bootstrap Alpha template
  registry and Desktop visibility for fixed templates.
- MG328 Draft review and submit: added reviewed submit preview and exact
  confirmation for queued records without task claim or execution.
- MG329 Worker template runner v1: added exact-confirmed one-task runner
  contracts for safe fixture tasks with Codex, MATLAB, shell, worker loop, PR,
  and project-control mutations disabled.
- MG330 Local worker install/heartbeat: added local worker config scaffolding,
  heartbeat-only wrapper, and heartbeat pairing with exact confirmation.
- MG331 Worker identity live heartbeat: activated
  `worker_id=jerry-win-local-01` and proved heartbeat-only cloud pairing.
- MG332 live safe template task: proved one exact live safe template task,
  `live-safe-template-task-332-001`.
- MG333 MATLAB golden trial fail-closed: first MATLAB golden task failed safely
  with bounded evidence.
- MG334 MATLAB diagnostics/recovery: added fixed startup diagnostics and
  recovery classification for MATLAB availability.
- MG335 MATLAB local runtime repair: repaired local MATLAB runtime discovery and
  doctor classification.
- MG336 MATLAB golden recovery success: proved
  `live-matlab-golden-task-336-001` with two completed combinations and
  manifest, summary, and metrics artifacts.
- MG337 Codex report trial failure: first Codex analysis report task failed
  safely; the report path was truncated and the artifact did not exist.
- MG338 Codex artifact persistence fix: repaired deterministic `report.md`
  persistence and fallback writer behavior through
  `live-codex-analysis-report-task-338-001`.
- MG339 Codex native report validation success: proved
  `live-codex-analysis-report-task-339-001` with
  `final_report_source=codex_native`, `fallback_report_used=false`,
  `native_report_valid=true`, and `validation_status=passed`.

## Live Proof Tasks

- `live-safe-template-task-332-001`: safe template runner cloud task completed.
- `live-matlab-golden-task-336-001`: MATLAB golden recovery task completed with
  `completed_count=2`, `failed_count=0`, and `expected_combination_count=2`.
- `live-codex-analysis-report-task-339-001`: Codex-native report task completed
  with the native report artifact validated.

## Known Failed Or Recovery Tasks

- `live-matlab-golden-task-333-001`: failed closed during the first MATLAB
  golden trial.
- `live-matlab-golden-task-334-001`: recovery task path used during MATLAB
  diagnostics and recovery work; superseded by MG336 success.
- `live-codex-analysis-report-task-337-001`: failed safely because the report
  artifact path was malformed/truncated and `report.md` did not exist.
- `live-codex-analysis-report-task-338-001`: completed through deterministic
  fallback after native report validation failed; superseded by MG339 native
  success.

## Included

- Cloud server version and route parity verification.
- Local Desktop Bootstrap Alpha panels for worker setup, task drafting,
  template registry, draft submit, safe task pilot, MATLAB golden success, and
  Codex native report status.
- Local Windows worker identity and heartbeat-only pairing.
- Template-bound worker runner contracts.
- One live safe template task proof.
- One live MATLAB golden recovery success proof.
- One live Codex-native report proof over the MATLAB outputs.
- Sanitized evidence summaries and read-only RC gate reports.

## Post-RC1 Desktop Packaging Track

MG344 starts Desktop packaging readiness after the Bootstrap Alpha RC1 GitHub
Release. It documents the Tauri package inventory, unsigned Windows packaging
status, CI-safe preview smokes, and future installer RC plan without publishing
or attaching installer assets. See
[../desktop/DESKTOP_PACKAGING_READINESS.md](../desktop/DESKTOP_PACKAGING_READINESS.md)
and
[../desktop/DESKTOP_INSTALLER_RC_PLAN.md](../desktop/DESKTOP_INSTALLER_RC_PLAN.md).

The existing RC1 tag and GitHub Release remain unchanged.

## Still Disabled

- General remote shell.
- Arbitrary task execution.
- Arbitrary prompt execution.
- Unbounded run.
- Worker loops and background autonomous queue processing.
- Project control unpause.
- Worker PR auto-creation and auto-merge.
- Production infrastructure mutation.
- Raw prompt, log, stdout, stderr, token, credential, environment, cookie,
  provider header, or proxy profile inclusion in evidence.

## Safety Invariants

- `arbitrary_shell_enabled=false`
- `unbounded_run_enabled=false`
- `worker_loop_started=false`
- `project_control_unpaused=false`
- `pr_created=false`
- `deploy_mutation_performed=false`
- `raw_prompt_included=false`
- `raw_codex_log_included=false`
- `raw_stdout_included=false`
- `raw_stderr_included=false`
- `token_printed=false`

## RC Readiness

Bootstrap Alpha RC is ready for operator review when
`skybridge-bootstrap-alpha-rc-gate.ps1 -Command audit` returns
`status=pass`, `release_candidate_ready=true`, and `tag_created=false`.

MG341 created and pushed the annotated tag `v0.1.0-bootstrap-alpha-rc1` after
operator authorization. MG342 adds the RC1 handoff package and classifies the
post-MG341 stop-hook timeout as non-blocking when tag, deploy, audit, and local
checks remain green.

See [BOOTSTRAP_ALPHA_RC1_HANDOFF.md](BOOTSTRAP_ALPHA_RC1_HANDOFF.md) for the
current handoff facts and verification commands.
