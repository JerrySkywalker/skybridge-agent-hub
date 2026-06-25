# Progress Log

## 2026-06-26 Mega Goal 341 Bootstrap Alpha RC Tag Authorization

- Updated the Bootstrap Alpha tag plan for MG341 operator authorization to
  create the real annotated `v0.1.0-bootstrap-alpha-rc1` tag.
- Recorded that the final tag target must be the final merged MG341
  documentation commit after PR CI, Deploy Cloud, `/v1/version`, cloud parity,
  and RC gate audit pass.
- Kept GitHub Release creation, release asset creation, task creation, task
  claim, task execution, Codex execution, MATLAB execution, worker loops,
  project-control unpause, deployment infrastructure changes, raw
  logs/prompts/process streams, credentials, and token printing disabled.

## 2026-06-26 Mega Goal 340 Bootstrap Alpha RC Release Gate

- Added Bootstrap Alpha RC release notes, runbook, disabled-features inventory,
  and preview-only tag plan for `v0.1.0-bootstrap-alpha-rc1`.
- Added `skybridge-bootstrap-alpha-rc-gate.ps1` with read-only `status`,
  `local`, `cloud`, `live-evidence`, `audit`, `tag-preview`, and
  `safe-summary` commands.
- RC gate checks local artifacts, package scripts, cloud version/parity,
  operator report, review gate, self-bootstrap convergence, worker identity and
  heartbeat support, and read-only live evidence for MG332, MG336, and MG339.
- RC reports write only safe Markdown/JSON under
  `.agent/tmp/bootstrap-alpha-rc/` when explicitly requested.
- Added RC gate, local, report, disabled-features, and tag-preview smokes.
- Updated Bootstrap Alpha acceptance and README to include MG340 RC artifacts.
- Kept task creation, task claim, task execution, Codex execution, MATLAB
  execution, worker loops, notification sends, project-control unpause, deploy
  mutation, tag creation, GitHub release creation, raw logs/prompts/process
  streams, credentials, and token printing disabled.

## 2026-06-26 Mega Goal 339 Codex Native Report Validation Success

- Hardened `skybridge-codex-analysis-report-runner.ps1` so native Codex
  reports must include Markdown shape, the synthetic MATLAB runner-validation
  statement, expected/completed/failed count metrics, and no process stream or
  secret-like markers.
- Added native evidence fields:
  `native_report_attempted`, `native_report_valid`,
  `native_report_validation_failure_category`,
  `native_report_validation_checks`, and `final_report_source`.
- Tightened the fixed prompt to request exactly one Markdown report, no wrapper,
  no commands, no external facts, no raw logs, no secrets, and no PR
  instructions.
- Added safe persistence for usable native Markdown captured from Codex output,
  while keeping raw Codex logs and process streams out of final evidence.
- Added `skybridge-live-codex-analysis-report-native-success.ps1` for the exact
  live task `live-codex-analysis-report-task-339-001`, refusing the MG337 and
  MG338 task ids.
- Added native validation, native fixture, fallback-not-used, unsafe rejection,
  orchestrator preview, and Desktop native report smokes.
- Updated Desktop Bootstrap Alpha native report fields, Bootstrap Alpha
  acceptance, README, and product/release docs.
- Kept arbitrary prompt text, arbitrary shell, MATLAB execution, worker loops,
  PR creation, project-control unpause, old task requeue, raw Codex logs,
  process stream exposure, and token printing disabled.

## 2026-06-25 Mega Goal 338 Codex Artifact Persistence Recovery

- Hardened `skybridge-codex-analysis-report-runner.ps1` so the report output is
  deterministically `.agent/tmp/codex-analysis-report/<task-id>/report.md`,
  with outside-path and truncated-path rejection before Codex starts.
- Added deterministic fallback report writing for the case where Codex exits
  successfully without `report.md`; failed Codex runs still fail closed and do
  not fake success.
- Hardened sanitizer-failed Codex output to use the same deterministic fallback
  report with `codex_failure_category=report_validation_failed_after_codex`.
- Added `skybridge-live-codex-analysis-report-recovery.ps1` for the exact
  recovery task `live-codex-analysis-report-task-338-001`, with create/run exact
  confirmations and no reuse of the MG337 task.
- Updated shared evidence schema, client fixtures, Desktop Bootstrap Alpha
  recovery fields, Bootstrap Alpha acceptance, README, and product/release docs.
- Added artifact path, fallback writer, evidence validation, recovery preview,
  recovery fixture, unsafe rejection, and Desktop artifact recovery smokes.
- Repaired server-side task evidence persistence so
  `skybridge.codex_analysis_report_evidence.v1` keeps bounded artifact fields
  such as `output_report_path`, `report_exists`, `report_size_bytes`,
  `fallback_report_used`, Codex invocation metadata, and disabled-action flags
  instead of collapsing the record to generic task evidence only.
- Kept arbitrary prompt text, arbitrary shell, MATLAB execution, worker loops,
  PR creation, project-control unpause, old task requeue, raw Codex logs,
  stdout/stderr/prompt exposure, and token printing disabled.

## 2026-06-24 Mega Goal 336 MATLAB Golden Recovery Live Success

- Added `skybridge-live-matlab-golden-success.ps1` for the exact
  `live-matlab-golden-task-336-001` path, with doctor-gated create/run
  previews, exact confirmations, MG333/MG334 task-id reuse rejection, optional
  heartbeat-only refresh, and one-task claim/start/complete/fail semantics.
- Hardened MATLAB sweep evidence with expected combination count and
  manifest/summary/metrics existence booleans, plus stricter output validation
  for manifest schema, summary counts, and metrics row count.
- Added Desktop MG336 success fixture visibility and CI-safe smokes for preview,
  fixture output, unsafe rejection, evidence validation, and Desktop contract.
- Documented the repaired success path in
  `docs/product/MATLAB_GOLDEN_RECOVERY_SUCCESS.md` and linked it from Bootstrap
  Alpha scope, roadmap, flow, MATLAB diagnostic, runtime repair, and README
  docs.
- Kept the boundary to one exact live MATLAB task only; no Codex, no arbitrary
  MATLAB command text, no arbitrary shell, no worker loop, no PR creation, no
  project-control unpause, no old task requeue, and `token_printed=false`.

## 2026-06-24 Mega Goal 335 MATLAB Local Runtime Repair And Successful Doctor

- Hardened `skybridge-matlab-doctor.ps1` with safe MATLAB executable
  resolution, user-level MATLAB config loading, fallback invocation reporting,
  and precise sanitized classifications for executable, batch, license,
  startup, working-directory, output-write, fixed-script, and unknown failures.
- Added `skybridge-matlab-local-config.ps1` for preview and exact-confirmed
  user-level MATLAB executable/run-mode config under `$HOME\.skybridge`, without
  writing tokens, license keys, system `PATH`, registry entries, or MATLAB
  installation files.
- Tightened `scripts/matlab/skybridge_matlab_startup_doctor.m` so a successful
  fixed doctor requires the no-toolbox compute and both doctor output files.
- Updated shared schemas, client fixtures, Desktop Worker Runner Preview, and
  Bootstrap Alpha acceptance with MATLAB runtime repair fields and disabled
  Desktop apply controls.
- Added local config, doctor classification, fallback fixture, and Desktop
  runtime repair smokes. MG335 creates no recovery tasks, claims no tasks, runs
  no Codex, starts no worker loop, exposes no arbitrary MATLAB command text, and
  keeps `token_printed=false`.

## 2026-06-24 Mega Goal 334 MATLAB Startup Diagnostics And Golden Trial Recovery

- Added `skybridge-matlab-doctor.ps1` and
  `scripts/matlab/skybridge_matlab_startup_doctor.m` for fixed MATLAB startup,
  batch/fallback, license/status, output-write, and tiny no-toolbox diagnostics.
- Hardened `skybridge-matlab-parameter-sweep-runner.ps1` with doctor preflight,
  timeout-bounded fixed invocation, fallback support, and failed evidence that
  separates actual `existing_outputs` from `expected_outputs_missing`.
- Added `skybridge-live-matlab-golden-recovery.ps1` for the exact recovery task
  `live-matlab-golden-task-334-001` and explicit non-reuse of
  `live-matlab-golden-task-333-001`.
- Updated shared schemas, client fixtures, and Desktop Worker Runner Preview
  with MATLAB doctor/recovery status and disabled live apply controls.
- Added doctor, recovery, failed-evidence accuracy, and Desktop recovery smokes
  plus Bootstrap Alpha acceptance coverage.
- Kept arbitrary MATLAB command text, Codex execution, arbitrary shell, worker
  loop start, PR creation, project-control unpause, old task requeue, raw
  stdout/stderr reporting, and token printing disabled.

## 2026-06-24 Mega Goal 333 MATLAB Experiment Golden Trial v1

- Added shared MATLAB golden-trial contracts:
  `skybridge.matlab_parameter_sweep_runner.v1`,
  `skybridge.matlab_sweep_manifest.v1`,
  `skybridge.matlab_sweep_summary.v1`, and
  `skybridge.matlab_sweep_evidence.v1`.
- Added the fixed `skybridge-matlab-parameter-sweep-runner.ps1` and
  toolbox-free `scripts/matlab/skybridge_run_parameter_sweep.m` synthetic
  runner for the tiny grid `eta=[2,3]`, `h_km=[500]`, `P=[6]`.
- Added `skybridge-live-matlab-golden-trial.ps1` for preview/create and
  preview/run of the exact live task `live-matlab-golden-task-333-001`, with
  exact confirmations for task creation and one fixed MATLAB run.
- Updated Desktop Worker Runner Preview with MG333 MATLAB Golden Trial status,
  target task id, parameter grid, output paths, evidence summary, and disabled
  live apply labels.
- Added MATLAB runner preview/fixture, live trial preview/rejection, Desktop
  fixture smokes, Bootstrap Alpha acceptance coverage, README link, and product
  docs.
- Kept arbitrary MATLAB command text, Codex execution, arbitrary shell, worker
  loop start, PR creation, project-control unpause, old task requeue, raw
  stdout/stderr reporting, and token printing disabled.

## 2026-06-24 Mega Goal 332 Live Worker One Safe Template Task

- Added `skybridge-live-safe-task-pilot.ps1` to preview/create, preview/run,
  apply-run, and report the deterministic live pilot task
  `live-safe-template-task-332-001`.
- Hardened `skybridge-worker-template-runner.ps1` with MG332 live-only modes,
  exact task id checks, low-risk/template/runner validation, old-residue
  rejection, MaxTasks=1 enforcement, and sanitized
  `skybridge.live_safe_template_task_evidence.v1` output.
- Updated Desktop Worker Runner Preview with MG332 live pilot status, target
  task id, cloud worker status, evidence schema, final state, and disabled
  PowerShell-only apply labels.
- Added live pilot preview, fixture apply, unsafe rejection, and Desktop fixture
  smokes plus Bootstrap Alpha acceptance coverage.
- Kept Codex execution, MATLAB execution, arbitrary shell, worker loop start,
  PR creation, project-control unpause, old task requeue, arbitrary task claim,
  and token printing disabled.

## 2026-06-24 Mega Goal 331 Local Worker Identity Activation And Live Heartbeat

- Added `skybridge-worker-identity.ps1` for exact-confirmed safe local worker
  identity config with `worker_id=jerry-win-local-01`.
- Added `skybridge-worker-live-heartbeat.ps1` for preview and exact-confirmed
  register/heartbeat-only pairing through worker APIs.
- Hardened worker service status with identity status, worker name/provider,
  identity apply availability, live heartbeat availability, and last live
  heartbeat result fields.
- Updated Desktop Bootstrap Alpha Worker Setup to show identity, live heartbeat,
  cloud worker status, blockers, and disabled execution flags. Desktop live
  apply remains PowerShell-only.
- Added identity preview/apply, live heartbeat preview/fixture, and Desktop
  identity/heartbeat smokes plus Bootstrap Alpha acceptance coverage.
- Kept live task claim, task execution, worker template runner live apply,
  Codex execution, MATLAB execution, arbitrary shell, worker loop start,
  notification send, project-control unpause, and token printing disabled.

## 2026-06-24 Mega Goal 330 Local Worker Install Apply And Heartbeat Pairing

- Added exact-confirmed local worker install and repair scripts:
  `skybridge-worker-service-install.ps1` and
  `skybridge-worker-service-repair.ps1`.
- Added `skybridge-worker-heartbeat-pairing-drill.ps1` for register and
  heartbeat-only pairing through `/v1/workers/register` and
  `/v1/workers/:workerId/heartbeat`.
- Hardened `skybridge.local_worker_service_status.v1` with local config paths,
  install apply availability, repair apply availability, heartbeat pairing
  availability, local state metadata, last heartbeat, and cloud worker status.
- Updated Desktop Bootstrap Alpha Worker Setup to show install/repair apply
  availability, heartbeat pairing state, cloud registration status, and disabled
  execution flags. Desktop live apply remains unavailable.
- Added fixture smokes for install preview, install apply, repair preview,
  heartbeat pairing, Desktop install flow, and Bootstrap Alpha acceptance.
- Kept live task claim, worker template runner live apply, Codex execution,
  MATLAB execution, arbitrary shell, worker loop start, PR creation,
  project-control unpause, notification send, and token printing disabled.

## 2026-06-23 Mega Goal 328 Draft Review And Submit To Server

- Added shared reviewed submit contracts: `skybridge.draft_review.v1`,
  `skybridge.draft_submit_preview.v1`, and
  `skybridge.draft_submit_result.v1`.
- Added server `POST /v1/drafts/submit-preview` and `POST /v1/drafts/submit`.
  Preview creates nothing; confirmed submit requires exact confirmation and
  creates queued task or non-running draft campaign records only.
- Added `skybridge-draft-submit.ps1` plus focused submit smokes for preview,
  server task submit, MATLAB campaign submit, and Desktop fixture coverage.
- Updated Desktop Chat-to-Task with a Draft Review + Submit card, submit
  preview state, exact confirmation, result ids, and MG329 worker-runner hold.
- Kept task claim, Codex execution, MATLAB execution, worker loop start,
  arbitrary shell, project-control unpause, raw prompt persistence, raw
  response persistence, and token printing disabled.

## 2026-06-23 Mega Goal 327 Task Template Registry

- Added the shared Bootstrap Alpha task template registry contract:
  `skybridge.task_template_registry.v1`, `skybridge.task_template.v1`,
  `skybridge.task_template_validation.v1`, and
  `skybridge.task_template_evidence_schema.v1`.
- Added five preview-only templates: `software-docs-task.v1`,
  `codex-analysis-report.v1`, `safe-local-smoke.v1`,
  `matlab-parameter-sweep.v1`, and `matlab-result-analysis.v1`.
- Added the read-only `skybridge-task-template-registry.ps1` script and
  registry smokes for general, MATLAB, and Desktop fixture coverage.
- Updated Chat-to-Task so known MATLAB and docs/report drafts pull runner id,
  path policy, validation rules, risk class, and evidence schema from the
  registry.
- Added the Desktop Bootstrap Alpha Task Templates panel with execution, task
  creation, campaign creation, claim, Codex, MATLAB, arbitrary shell, and token
  output disabled.
- Added registry docs and Bootstrap Alpha doc updates. MG327 remains
  no-execution and creates no server tasks or campaigns.

## 2026-06-23 Mega Goal 326 Chat-to-Task Draft Planner

- Added shared Chat-to-Task draft contracts for session, task draft, campaign
  draft, clarifying question, and preview output.
- Added deterministic local PowerShell planner
  `skybridge-chat-to-task-draft.ps1` with MATLAB parameter sweep, software
  docs/report, clarifying-question, blocked-request, command-text detection,
  status, and safe-summary modes.
- Added Desktop Bootstrap Alpha Chat-to-Task panel with natural-language input,
  structured draft preview fields, clarifying questions, and disabled MG328
  submit placeholder.
- Added Chat-to-Task product docs, README link, Bootstrap Alpha doc updates,
  package smoke scripts, and bootstrap-alpha acceptance coverage.
- Kept raw prompt persistence, raw response persistence, task creation,
  campaign creation, claim creation, Codex execution, MATLAB execution,
  arbitrary shell, worker loop start, and token printing disabled.

## 2026-06-23 Mega Goal 325 Desktop Installer And Worker Service Manager

- Added `skybridge.local_worker_service_status.v1` for local Windows worker
  service install/readiness status with safe service, config, tool capability,
  blocker, warning and recommended-action fields.
- Added read-only status/doctor scripts plus preview-only install/repair scripts
  for Bootstrap Alpha worker service management.
- Added a Desktop Bootstrap Alpha Worker Setup panel with install/repair state,
  tool capability matrix, blockers, warnings and explicit disabled execution
  flags.
- Added Windows worker install Bootstrap Alpha docs and focused smokes for
  status, doctor, Desktop contract, and bootstrap-alpha acceptance.
- Kept task claim, Codex execution, MATLAB execution, worker loop start,
  notification send, arbitrary shell, apply install/repair and token printing
  disabled.

## 2026-06-08 Goal 200 Controlled Goal Draft Review And Import

- Added `skybridge-goal-draft-review.ps1` with review queue, validate, approve/reject/edit/supersede, import-preview, import-apply, safe-summary and attention-event commands.
- Added risk gating for blocked/unsafe drafts, reason-gated approval/rejection, edit hash recompute, manifest/dependency validation and dry-run-first import staging.
- Added Desktop/Web controlled review/import panel state with approve/reject/edit/import preview summaries, manifest diff, import target and execution-review-required status.
- Added focused Goal 200 smokes covering reason requirements, risk gating, edit hashes, import preview/apply, no execution, manifest/dependency validation, attention, no secrets and clean worktree.
- Imports stage reviewed goals only; they do not execute, create tasks, claim tasks, start worker loops, start queues or advance campaigns.

## 2026-06-08 Goal 199 Hermes Goal Draft Generator

- Added a fixture-first proposed-goal draft generator with required safety sections, stable content hashes and `token_printed=false`.
- Added proposed goal review metadata and read-only Desktop/Web review panels.
- Added no-import/no-execution smokes and attention events that route operators to Goal 200 for controlled review/import.

## 2026-06-08 Goal 198 Multi-project Support

- Added safe `skybridge.project_profile.v1` sample profiles for SkyBridge and a repository-local fixture project.
- Added `skybridge-project-profile.ps1` for read-only profile list, validate, preview, hash and project selection preview flows.
- Added conservative project policy validation for secret-looking fields, token values, Authorization/private-key markers, unapproved repo roots, out-of-repo paths, production/server-root/DNS/OpenResty/Hermes paths, arbitrary shell command shapes, invalid goal pack paths and execution-enabled worker/goal-pack defaults.
- Integrated project selection preview into queue-control and worker routing preview metadata while keeping `task_created=false`, `task_claimed=false`, `task_executed=false`, `worker_loop_started=false`, `queue_execution_enabled=false` and `validation_commands_executed=false`.
- Added Desktop/Web read-only Project Profile Review panels and project-profile attention event types.
- Added focused Goal 198 project profile smokes. Goal 198 does not run `start-one`, `start-all`, `resume -Apply`, a worker loop, task claim, campaign-step task creation, Codex worker execution, live queue execution, other-repo mutation or real external notification sending.

## 2026-06-08 Goal 196 Campaign Locking and Multi-campaign Queue

- Added shared campaign lock, repo-exclusive lock, lock owner, stale recovery decision and deterministic multi-campaign priority queue contracts with `token_printed=false`.
- Extended queue-control previews so active repo locks block start-one/start-queue previews while execution apply remains disabled for a later reviewed gate.
- Added reason-gated fixture/local stale unlock, cancel, abort and hold semantics that record safe audit metadata only and do not create tasks or start workers.
- Added Desktop/Web lock review and priority queue panels with owner, heartbeat age, expiry, stale recovery guidance and no execution controls.
- Added lock-derived attention events for active repo lock blockers, stale lock review, campaign held/cancelled/aborted, multi-campaign conflicts, unknown owners and missing unlock reasons.
- Added focused campaign-lock and repo-exclusive-lock smokes. Goal 196 does not run `start-one`, `start-all`, `resume -Apply`, a worker loop, task claim, campaign-step task creation, Codex worker execution or live queue execution.

## 2026-06-08 Goal 195 Manual Goal Queue Management

- Added six reviewable goal templates under `goals/templates/` for super, patch, recovery, dashboard/control, worker/service and generated/proposed goals.
- Added `skybridge-goal-pack.ps1` for offline goal pack validation, manifest hash update previews, explicit-apply local hash writes, hash drift reporting, re-import previews, archive previews and safe summaries.
- Added Desktop/Web manual goal queue review surfaces backed by `GoalQueueReviewSummary`, plus safe summary fields for goal pack id, validation result, hash drift count, dependency/order status and proposed import/update action.
- Updated `goals/dev-queue-189-200/campaign.skybridge.json` with per-goal `markdown_hash` metadata. This is local authoring metadata only; it does not update live campaign state.
- Added focused Goal 195 smokes for templates, manifest preview, hash drift, duplicate validation, dependency validation, cycle validation, re-import preview, archive preview, no-execution, Desktop/Web review and no-secrets output.
- Goal 195 does not run `start-one`, `start-all`, `resume -Apply`, task claim, Codex worker execution, live campaign update, PR creation or real queue start.

## 2026-06-08 Goal 194 Worker Service Mode

- Added the shared `skybridge.worker_service_state.v1` contract and `skybridge.worker_service_readiness.v1` helper with heartbeat/status/stop capability and explicit `can_claim_tasks=false`, `can_execute_tasks=false` and `token_printed=false`.
- Added a bounded local worker service wrapper, `skybridge-worker-service.ps1`, that writes heartbeat-only standby metadata under ignored `.agent/tmp/worker-service/`.
- Integrated worker service readiness into the campaign report and queue-control readiness while keeping `can_start_one=false`, `can_start_queue=false`, `can_resume=false` and the execution-disabled gate active.
- Added Web Worker Readiness and Desktop Worker Service panels with capability matrix, heartbeat age, blockers and disabled execution controls.
- Added focused worker service smokes for contract, heartbeat, stop, readiness gates, no task claim, no arbitrary shell, no secrets, Desktop/Web rendering, queue integration and clean-tree hygiene.
- Goal 194 does not run `start-one`, `start-all`, `resume -Apply`, task claim, Codex worker execution, PR creation or real queue start.

## 2026-06-08 Goal 193 Notification and Attention Loop

- Added the shared `skybridge.attention_event.v1` contract with attention levels, sources, required event types, routing decisions and `token_printed=false`.
- Added attention derivation from campaign report, queue-control readiness, worker offline state, required human action, PR/CI evidence and queue-control audit events.
- Added fixture-safe notification routing: Desktop-only, Web banner, local fixture ledger, ntfy placeholder and disabled routes. All routes keep `real_external_send=false` by default.
- Added Web Campaign Queue attention banner/feed and notification routing status, plus a Desktop Attention Panel with worker offline, queue blocker, recommended action and safe notification status.
- Extended safe summaries with `attention_count`, `top_blocker` and `recommended_next_action`.
- Moved queue-control fixture audit output from `.agent/queue-control-audit/` to ignored `.agent/tmp/queue-control-audit/`.
- Added focused attention/notification smokes and clean-tree audit hygiene coverage.
- Goal 193 implementation does not run `start-one`, `start-all`, `resume -Apply`, a worker loop, task claim, campaign-step task creation or real external notification sending.

## 2026-06-08 Goal 192 Dashboard Safe Actions and Queue Control Contract

- Added the shared queue-control contract foundation for Desktop, Web, CLI and Server: control intents, queue-control state, action matrix, audit events, run budget, arm lease fixture, revision/state hash guard and `token_printed=false`.
- Added Goal 192 action classification: read-only status/report/preflight, heartbeat-only heartbeat, reason-gated safe pause/stop/emergency stop, preview-only resume/start-one/start-queue, and forbidden start apply/start queue apply/start-all/arbitrary shell.
- Added server `control/matrix`, `control/preview` and narrow `control/apply` endpoints; apply only accepts reason-gated safe stop/pause actions and records audit. Start-one/start-queue apply remain rejected.
- Hardened `skybridge-dev-queue-control.ps1` with `control-matrix`, `control-preview`, `safe-pause`, `stop-queue`, `emergency-stop`, `resume-preview`, `start-one-preview` and `start-queue-preview`; legacy `start-one -Apply`, `start-all -Apply` and `resume -Apply` are blocked for Goal 192.
- Updated Web and Desktop with Safe Actions / Queue Controls sections that show disabled execution controls, preview controls, reason requirements, worker-offline blocker, audit result location and no token contents.
- Added focused queue-control, Desktop and Web smokes. Goal 192 implementation does not run `start-one`, `start-all`, `resume -Apply`, a worker loop, task claim or campaign-step task creation.

## 2026-06-05 Goal 191E Desktop Async Refresh and Nonblocking Bridge Hardening

- Moved Desktop status refresh into an async Tauri command and made tray refresh fire the bridge work on a background task.
- Split status, campaign, worker and report bridge outcomes into structured warning records with bounded timeouts.
- Preserved cached report snapshots when fresh report generation fails, including cached age and safe summary generation from the cached snapshot.
- Updated Desktop UI refresh generation tracking so overlapping refreshes ignore stale responses and the last known report remains visible while refresh is pending.
- Replaced the post-Goal-190 primary banner with Queue Readiness / Operator Readiness and hid Goal 190-specific link counters unless Goal 190 is current.
- Hardened Open report to only open ignored `.agent/tmp/campaign-reports/` artifacts without a blocking refresh, and kept Copy safe summary snapshot-only with secret-pattern guarding.
- Added focused async refresh, timeout, open-report, no-Pre-190 and cached-summary smokes plus fixture visual QA timeout-warning coverage.
- Goal 191E does not run `start-one`, `start-all`, `resume -Apply`, a worker loop, task claim, campaign-step task creation or campaign state mutation.

## 2026-06-05 Goal 191D Unified Queue Dashboard Foundation

- Added a shared typed `skybridge.campaign_run_report.v1` consumer in `@skybridge-agent-hub/client`, including evidence counts and a safe summary payload.
- Added a read-only Web Campaign Queue route that displays campaign state, Goal 190/191 state, evidence counts, worker readiness, blockers, warnings, `next_safe_action` and disabled future-control placeholders.
- Upgraded SkyBridge Desktop with a read-only Queue Dashboard section, report artifact opening and copy-safe-summary support while keeping execution controls out of scope.
- Added fixture-only Web/Desktop visual QA coverage and focused no-mutation/safe-summary smokes.
- Goal 191D does not run `start-one`, `start-all`, `resume -Apply`, a worker loop, task claim, campaign-step task creation or campaign state mutation.

## 2026-06-05 Goal 190 Campaign Run Report and Evidence Ledger

- Added a read-only `skybridge.campaign_run_report.v1` report contract to `skybridge-campaign.ps1 runner-report`, with JSON and Markdown artifacts under ignored `.agent/tmp/campaign-reports/`.
- Added step, task, PR, CI, finalizer, gate, recovery, hygiene, runner, lock, blocker, warning, queue-control readiness and acceptance summaries.
- Kept `skybridge-dev-queue-control.ps1 -Command report -Json` compatible while returning the richer report object.
- Added focused campaign report smokes for schema, Markdown headings, evidence ledger, recovered Goal 189 evidence, current Goal 190 state, queue-control readiness and no-secret output.
- Patched queue-control readiness so unknown, offline, stale or missing worker state disables start controls and apply-mode resume until worker readiness is verified.
- Goal 190 remains current/ready/unexecuted; this implementation does not run `start-one`, `start-all`, `resume -Apply`, a worker loop, task claim, campaign-step task creation or Goal 191.

## 2026-06-04 Goal 188I Desktop Readiness Gate

- Hardened the desktop standby status contract with explicit `STANDBY / READ ONLY`, `HEARTBEAT ONLY MUTATION` and `EXECUTION DISABLED` mode fields.
- Added structured Pre-190 readiness output with PASS/WARN/BLOCK semantics for active tasks, stale leases, `token_printed`, current Goal 190 state and Goal 190 linked task/PR counts.
- Kept Heartbeat Now as the only mutation and documented it as heartbeat-only.
- Added desktop readiness documentation and a manual operator drill.
- Added focused desktop smokes for readiness contract, safe metadata, Pre-190 gate fixtures and heartbeat-only behavior.
- Fixed Tauri bundle icon configuration and validated that Windows MSI and NSIS bundle generation passes locally.
- Fixed the desktop dev-command recursion found during manual GUI drill: `pnpm dev` now starts Vite only, while `pnpm tauri:dev` or `pnpm tauri dev` starts the full Tauri app.
- Added fixture-only desktop visual QA support with local screenshot/manifest artifacts under `.agent/tmp/desktop-visual-qa/`.
- Goal 190 remains unexecuted; this goal does not run `start-one`, `start-all`, a worker loop or campaign-step task creation.

## 2026-06-02 Goal 188H Tauri Desktop Client MVP

- Added `apps/desktop`, a Tauri v2, React, TypeScript and Vite desktop app named `@skybridge/desktop` with identifier `space.jerryskywalker.skybridge.desktop`.
- Implemented a tray menu with Open SkyBridge, Refresh Status, Open Logs and Quit. Tray actions do not claim tasks or execute campaign steps.
- Added a read-only status panel for `laptop-zenbookduo`, `skybridge-agent-hub`, `dev-queue-189-200`, Goal 190 current state, Goal 189 completed state, active tasks, stale leases, last refresh and `token_printed=false`.
- Added a safe Rust bridge to existing PowerShell status commands and an explicitly labeled Heartbeat Now action that only runs worker register-heartbeat.
- Added ignored local metadata paths under `.agent/desktop-client/` for `status.json` and logs.
- Added desktop package, Tauri config, read-only bridge and no-task-execution smokes.
- Goal 190 remains unexecuted; this goal does not run `start-one`, `start-all`, a worker loop or campaign-step task creation.

## 2026-06-02 Goal 188G Operator Control Drill

- Hardened `skybridge-dev-queue-control.ps1` preflight for the post-188F state: Goal 189 completed/recovered with PR #99 and Goal 190 ready/current but unexecuted is now a healthy control-plane state.
- Changed `resume` without `-Apply` into a dry-run preview that reports the current step, emergency-stop recovery action, Goal 190 execution block and next safe action.
- Hardened safe-pause, emergency-stop and stale-runner unlock output so dry-runs are explicit, emergency-stop reports Ctrl+C instructions and no task creation, and no-lock unlock is a no-op.
- Fixed runner stop/hold state updates for older/minimal local runner state files that lack optional fields.
- Added 188G smokes for safe-pause, emergency-stop, resume dry-run, Goal 190 report display, unlock reason/apply requirements and active lock refusal.
- Updated operator docs with the two-window workflow, safe-pause vs emergency-stop semantics, resume recovery, runner-report inspection and the Pre-190 Acceptance Gate warning.
- Goal 190 remains unexecuted; this goal does not run `start-one`, `start-all`, a worker loop or campaign-step task creation.

## 2026-06-02 Goal 188E Runner Resume, Residue And Lease Hardening

- Hardened campaign runner resume/idempotency so existing linked tasks, linked PRs, merged-PR evidence gaps, completed steps and already-advanced campaigns are handled without duplicate task or PR creation.
- Added runner status/report classification for old failed runner state: a Goal 189 runner failure is `historical_warning` once the campaign current step is Goal 190.
- Improved hygiene findings with concrete object ids, classifications and action hints for task residue, stale leases, PR evidence gaps, historical blocked tasks and approved-unconverted proposals.
- Added worker active-task keepalive behavior: pre-task heartbeat, periodic heartbeat job during active task processing, post-task heartbeat and terminal lease release verification.
- Added focused 188E smokes for runner resume cases, residue action hints, stale lease action hints, historical runner state and heartbeat lease renewal.
- Goal 190 remains unexecuted; this goal is metadata/control-plane hardening only.

## 2026-06-01 Goal 188C Watch CLI and Dev Queue Control

- Added `skybridge-campaign-watch.ps1`, a read-only Docker BuildKit-style watch CLI with spinner frames, colorized status output, `-Once`, `-NoClear`, `-Compact`, `-ShowEvents`, JSON output and demo frames.
- Added `skybridge-dev-queue-control.ps1` with `preflight`, `watch`, `start-one`, `start-all`, `safe-pause`, `emergency-stop`, `resume`, `report` and `unlock-stale-runner` commands.
- Added dry-run/local smokes for watch output, demo output, JSON cleanliness, color suppression, control preflight, dry-run starts, pause/stop previews and reports.
- Recommended launch workflow is now two windows: watch in Window A, control commands in Window B, with `start-one` before `start-all`.
- No Goal 189-200 execution is part of Goal 188C; mutating control paths require `-Apply` and the queue remains paused before launch.

## 2026-06-01 Goal 188A Dev Queue Expansion and Launch UX

- Started from clean latest `main` after Super 188 merged and created branch `ai/goal-188a-expand-dev-queue-goals-launch-ux`.
- Preflight against the cloud control plane confirmed project control `paused`, active queued/claimed/running tasks `0`, stale leases `0`, campaign `dev-queue-189-200` present as `draft`, no runner lock active, `laptop-zenbookduo` heartbeat online after refresh, Hermes direct HTTPS healthy, and `token_printed=false`.
- Expanded all 12 files under `goals/dev-queue-189-200` from thin notes into full Super Goal style documents with context, mission, safety boundaries, phased implementation, validation, final status, PR package, success criteria, stop/hold conditions and evidence requirements.
- Preserved the Goal 189-200 dependency chain and kept Goal 199 as proposed-goal generation only and Goal 200 as controlled review/import only.
- Updated `start-dev-queue-189-200.ps1` with `-GoalPackDir`, `-CampaignId`, `-MaxSteps`, `-MaxTasks`, `-OutputFile`, `-OutputDir` and `-DryRun`. `-Apply` remains required for execution and still requires clean latest `main`.
- Added `.agent/campaign-runners/` to `.gitignore`; dry-run reports remain under ignored `.agent/tmp`, and the clean-tree smoke proved dry-run runner state does not dirty `git status`.
- Added focused dry-run/local smokes for expanded goal files, pack validation, import dry-run, launch parameters, output-file resolution and dry-run clean-tree behavior.
- Validation so far: `validate-pack` passed with 12 goals and updated markdown hashes; `import -DryRun` passed; `start-dev-queue-189-200.ps1` dry-run returned resolved parameters, active tasks `0`, stale leases `0`, planned all 12 steps in dry-run state and left `git status` clean.
- No `-Apply` launch was run, no Goal 189-200 execution occurred, no campaign-step-derived tasks were created, no worker loop was started, and no GitHub settings, branch protection, production, server-root, DNS, OpenResty or Hermes server mutation occurred.

## 2026-05-31 Super Goal 187 Campaign Step Executor and Bootstrap MVP Pilot

- Started from latest `main` after PR #91 and created branch `ai/super-187-campaign-step-executor-bootstrap-mvp`.
- Preflight confirmed cloud project control `paused`, `stop_requested=false`, active queued/claimed/running tasks `0`, stale leases `0`, campaign `bootstrap-mvp` present, current step `bootstrap-mvp:super-187-bootstrap-campaign-mvp-hardening` ready, Super 186 completed, `laptop-zenbookduo` heartbeat online after refresh, and Hermes `direct_https=true`.
- Added campaign step executor support in `skybridge-campaign.ps1` and the server: `execute-preview`, `execute-step`, `link-task`, `attach-execution-evidence`, and `step-report`. Mutating commands require `-Apply`; execution creates a queued task only and does not run a worker unless a future explicit run mode is implemented.
- Added execution safety gates for active tasks, stale leases, running project control, non-current or already-completed steps, incomplete dependencies, duplicate linked tasks, linked open PRs, markdown hash mismatch, unsafe paths, blocked task types, dirty worktree markers, and missing worker capabilities.
- Real cloud `execute-preview` for Super 187 produced exactly one docs-scoped task payload. `execute-step -Apply` created `campaign-step-super-187-bootstrap-campaign-mvp-hardening-20260531100053` and linked it to the campaign step.
- Ran a bounded `MaxTasks=1` lease-backed worker loop on `laptop-zenbookduo`. The task received lease `lease_chdDfMPI1SEIgonHR-hzv`, passed workspace guards, created child PR #92, and changed only the expected docs files.
- PR #92 checks passed and the child PR merged. The task remains raw `failed` because the worker CI guardian initially stopped on draft/pending checks, but evidence was repaired to recovered after merge.
- Attached task/PR/evidence summary to Super 187, marked the step completed, and ran `advance-with-gate -Apply` with human approval. Deterministic plus Hermes gate returned final decision `advance`, moving `bootstrap-mvp` to `bootstrap-mvp:super-184b-operator-console-dashboard` ready. No worker execution for Super 184B occurred.

## 2026-05-31 Super Goal 186 Hermes Gate Evaluator and Auto-Advance Pilot

- Started from latest `main` after Super 185 and created branch `ai/super-186-hermes-gate-evaluator-auto-advance`.
- Preflight confirmed cloud project control `paused`, `stop_requested=false`, active queued/claimed/running tasks `0`, stale leases `0`, campaign `bootstrap-mvp` present, current step `bootstrap-mvp:super-186-hermes-gate-evaluator-auto-advance` ready, deterministic `advance-preview` returning `ask_human` without human approval, `laptop-zenbookduo` heartbeat online after refresh, and Hermes `direct_https=true`.
- Added strict Hermes campaign gate output schema `skybridge.campaign_gate.v1` with decision, confidence, campaign/step ids, reasons, blockers, warnings, required human actions, evidence reviewed, safety assessment, recommended next action, prompt version, and input state hash.
- Added campaign gate input building in `skybridge-campaign.ps1`, including campaign state, current/next step summaries, deterministic gate result, hygiene/task/proposal summaries, worker and Hermes health summaries, linked evidence, git branch/commit, dirty marker, and operator human approval marker.
- Added `gate-preview`, `hermes-gate-preview`, `advance-with-gate`, and `attach-gate-evidence` commands. `advance-with-gate` remains dry-run by default, requires `-Apply` to mutate campaign metadata, and never starts a worker.
- Hardened the final decision algorithm so deterministic hard blockers and missing human approval override Hermes, while warning-only conditions such as blocked historical tasks, recovered tasks, approved-unconverted proposals, and offline workers do not block by themselves.
- Added campaign gate event types and status display fields for deterministic decision, Hermes decision, final decision, human approval, blockers, warnings, prompt version, timestamp, and input state hash.
- Added local fixture smokes for strict JSON parsing, invalid JSON rejection, hard-veto precedence, human approval, warning-only advance, dry-run behavior, apply requirement, JSON cleanliness, and saved-artifact secret checks.
- Real cloud gate preview without `-HumanApproved` returned final decision `ask_human`, as expected because the current Super 186 step requires explicit human approval.
- Real cloud gate preview with `-HumanApproved` and reason `Operator approved Super 186 gate pilot; this advance only prepares Super 187 and does not execute it.` returned final decision `advance` with no hard blockers. Hermes kept historical failed/blocked tasks, approved-unconverted proposals, and worker offline state as warnings for later execution gates.
- Attached Super 186 gate evidence, marked the current step completed with metadata-only evidence, and ran `advance-with-gate -Apply`. Campaign `bootstrap-mvp` advanced current step metadata to `bootstrap-mvp:super-187-bootstrap-campaign-mvp-hardening`, which is now ready. No worker loop, task creation, proposal conversion, Super 187 execution, or Super 184B execution occurred.

## 2026-05-31 Super Goal 185 Goal Pack and Campaign Sequencer

- Started from latest `main` after Super 184 and created branch `ai/super-185-goal-pack-campaign-sequencer`.
- Preflight confirmed cloud project control `paused`, `stop_requested=false`, no active queued/claimed/running tasks, stale leases `0`, `laptop-zenbookduo` heartbeat online, Hermes `direct_https=true`, and historical `task_proposal-59a0236fb69800cd` still blocked.
- Added campaign and campaign step domain types, SQLite/memory persistence, and campaign event types for import, start, pause, hold, complete/fail, advance blocked, and evidence attachment.
- Added campaign API endpoints for listing, importing goal packs, inspecting steps, state transitions, advance preview, explicit advance, step completion/failure, and evidence attachment.
- Added `skybridge-campaign.ps1` with offline `validate-pack`, dry-run-first `import`, list/show/steps/status, advance-preview, advance, complete/fail, attach-evidence, and export-report commands. Mutating commands require `-Apply`.
- Added campaign visibility to `skybridge-status.ps1` through `-ShowCampaigns`, `-CampaignId`, `-ShowCampaignSteps`, and `-CampaignLimit`, with JSON fields `campaign_summary`, `campaigns`, `campaign_steps`, and `campaign_gate_summary`.
- Implemented deterministic advance gates with hard holds for active tasks, stale leases, running project control, missing dependencies, missing human approval, dirty worktree markers, missing required parent PR merge, and failed/aborted campaigns. Hermes advisory gate remains disabled for Super 185.
- Created the seed goal pack under `goals/bootstrap-mvp/` for Super 186 Hermes Gate Evaluator, Super 187 Campaign MVP Hardening, and Super 184B Operator Console Dashboard.
- Added local fixture smokes for pack validation, import dry-run, step order, dependency validation, status output, JSON cleanliness, apply requirement, and advance gate blockers.
- Real cloud import was not applied because this branch contains unmerged campaign API code; no deployment or worker execution occurred in Super 185.

## 2026-05-30 Super Goal 182 Cloud Proposal Review Pilot and Task Lease Safety

- Started from latest `main` at Super 181 merge commit `5ff8838` and created branch `ai/super-182-cloud-proposal-review-task-lease-safety`.
- Preflight confirmed cloud project control `paused`, `stop_requested=false`, active queued/claimed/running tasks `0`, `laptop-zenbookduo` heartbeat online, Hermes `direct_https=true`, and cloud API accepted `status=approved` proposal filtering.
- Added task lease metadata to tasks. Claim creates an active lease while preserving legacy `claim`; start refreshes the lease; complete/fail/block releases it; worker heartbeat can refresh the active lease; stale leases block silent duplicate execution.
- Added local worker guards: active lease required before Codex, dirty worktree guard, active PR guard, branch collision guard, repo lock under `.agent/locks`, stale lock recovery and finally cleanup.
- Added status lease visibility with `-ShowLeases` and `-ShowLocks` filter metadata.
- Real Hermes preview/apply persisted two low-risk docs proposals for Super 182: `proposal-0da654fd64115472` and `proposal-76496878cf3a15a2`.
- Approved exactly those two Super 182 docs proposals. Deferred older local-smoke `proposal-7a0c9c5d4ce0612c` because it was outside the docs-only pilot and needs separate safe-local-smoke approval.
- Verified unapproved `proposal-82cd1023bd7ae368` and deferred `proposal-7a0c9c5d4ce0612c` cannot be converted.
- Attempted approved conversion for `proposal-0da654fd64115472`; deployed cloud server rejected it with `proposal_not_convertible` because the live server still matches the safety phrase `No production configuration` as a high-risk surface. The local CLI policy was fixed to ignore negated high-risk phrases.
- No worker task was executed because server-side lease support is not deployed to cloud yet and the worker now requires an active lease before starting Codex. Final cloud active task count stayed `0`; historical `task_proposal-59a0236fb69800cd` remained blocked.
- Result: cloud proposal review queue is proven through persistence, approval, defer and non-approved conversion refusal. Cloud task execution with lease safety is intentionally not proven until the server lease changes are merged and deployed.

## 2026-05-29 Super Goal 180 Capability Alignment and Status Query Hardening

- Started from latest `main` after v0.49.0 and created branch `ai/super-180-capability-alignment-status-query-hardening`.
- Preflight confirmed cloud project control `paused`, `stop_requested=false`, no queued/running tasks, direct Hermes health `ok=true`/`direct_https=true`, `laptop-zenbookduo` heartbeat online, and historical `task_proposal-59a0236fb69800cd` still blocked.
- Added proposal/task capability normalization semantics: `task_type` stays distinct from executable `required_capabilities`, `original_required_capabilities` is preserved, `normalized_required_capabilities` and `capability_normalization_reason` are emitted, docs tasks under `docs/` normalize to `codex`, `git`, `gh`, and safe local-smoke tasks under `scripts/powershell/smoke-*.ps1` normalize to `codex`, `powershell`, `windows`.
- Hardened worker matching so legacy `required_capabilities=["docs"]` no longer blocks low-risk docs tasks on `laptop-zenbookduo`, while production, deploy, secret, GitHub settings, branch protection, server config and server root config remain blocked.
- Refactored `skybridge-status.ps1` for growing task history with `-TaskLimit`, `-RecentTasks`, `-TaskStatus`, `-ActiveOnly`, `-WorkerId`, `-RecoveredOnly`, `-IncludeRecovered`, `-ExcludeRecovered`, `-TaskId`, `-EventLimit`, `-IncludeEvents`, `-Since`, `-Until`, `-SortBy`, `-Descending` and `-SummaryOnly`. Default output is now compact recent status; `-ShowAll` remains available.
- Added guide and Hermes CLI status aliases for active, recent, worker, task, failed and recovered views.
- Ran the Super 180 batch pilot with `MaxTasks=2`, `IdleTimeoutSeconds=120`, `PollIntervalSeconds=5`, `StopOnFailure=true` and only `laptop-zenbookduo`. The pilot executed only two low-risk docs tasks and no local-smoke, production, deployment, server config, GitHub settings, branch protection or secret work.
- Child PR [#81](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/81) completed `batch-worker-loop-pilot-docs-180b`, changed only `docs/orchestrator/WORKER_PROFILE_RUNBOOK.md`, passed AI branch validation, Project check and Docker build server/web, merged at `64fec501a08431d31442912d3820618f4882f0a5`, and cloud evidence recorded `ci_status=passed`.
- Child PR [#82](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/82) recovered `batch-worker-loop-pilot-docs-180a`, changed only `docs/dev/BATCH_WORKER_LOOP_PILOT.md`, passed AI branch validation, Project check and Docker build server/web, merged at `d7c2cd7ee7fe9eb703df0b9222472bf7c62348a1`, and evidence repair recorded `recovered=true`, `ci_status=passed_after_pending`.
- Final cloud control was restored to `paused`, `stop_requested=false`, `stop_reason=batch_pilot_completed_with_recovered_evidence`; active queued/claimed/running tasks were zero, historical `task_proposal-59a0236fb69800cd` remained blocked, and token output stayed redacted.
- Result: capability-aligned batch worker loop execution is proven for two low-risk docs tasks on `laptop-zenbookduo`, with the remaining follow-up that CI Guardian should wait on pending checks instead of initially failing an otherwise safe child PR.

## 2026-05-29 Super Goal 179 Always-on Worker Loop Pilot

- Started from latest `main` after v0.48.0 and created branch `ai/super-179-always-on-worker-loop-pilot`.
- Preflight confirmed cloud health OK, project control `paused`, `stop_requested=false`, no queued/running task residue, direct Hermes health `ok=true`/`direct_https=true`, and `laptop-zenbookduo` able to register heartbeat online.
- Added a worker-loop control hardening change: bounded `skybridge-edge-worker.ps1 -Loop` exits now finalize project control as `paused` instead of `stopped`, with `stop_requested=false`, final `loop_task_count` and `stop_reason` recorded.
- Added `smoke-worker-loop-control.ps1`, which runs a local empty-queue loop with `MaxTasks=1`, bounded idle timeout and non-dry-run control mutation, then asserts final control state is `paused`.
- Prepared a one-task docs-only pilot batch. The first queued task was blocked before execution because its required capabilities included `docs`, which `laptop-zenbookduo` does not advertise. The corrected task `always-on-worker-loop-pilot-docs-179b` required `codex` and `git`, had `allowed_paths=["docs/dev/ALWAYS_ON_WORKER_LOOP_PILOT.md"]`, and was the only queued/running task before the real loop.
- Ran the real bounded loop with `MaxTasks=1`, `IdleTimeoutSeconds=120`, `PollIntervalSeconds=5`, and `StopOnFailure`. The loop claimed exactly one task, Codex completed without transport retry, changed only `docs/dev/ALWAYS_ON_WORKER_LOOP_PILOT.md`, opened child PR [#79](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/79), then stopped on CI Guardian pending/blocked status as expected under `StopOnFailure`.
- Child PR #79 passed AI branch validation, Project check, Docker build server and Docker build web. It was marked ready and merged at `39e554b4c3fe704133bb0f3d0b0c46b442c43330`.
- Evidence repair recorded `recovered=true`, `ci_status=passed_after_pending`, `risk_status=low_docs_only`, changed file `docs/dev/ALWAYS_ON_WORKER_LOOP_PILOT.md`, and PR #79 for `always-on-worker-loop-pilot-docs-179b`.
- Final control stayed/restored `paused` with `stop_requested=false`; no production deployment, server config mutation, GitHub settings change, branch protection change, secret commit, local-smoke execution, unbounded loop or direct execution of historical `task_proposal-59a0236fb69800cd` occurred.
- Result: the bounded always-on worker loop pilot is proven for one low-risk docs task, with a follow-up needed to align task proposal capabilities with actual worker profiles before larger batches.

## 2026-05-29 Goal 178T Hermes Capability Normalization and Resume

- Started from latest `main` after PR #75 merged and created branch `ai/goal-178t-hermes-capability-normalization-resume`.
- Added Hermes proposal capability normalization: `original_required_capabilities` is preserved, `normalized_required_capabilities` is added, docs proposals under `docs/` and local-smoke proposals under `scripts/powershell/smoke-*.ps1` receive `codex` when Hermes omits it, and policy validation uses the normalized list without weakening blocked task-type or unsafe-file gates.
- Updated the Hermes prompt to ask executable proposals to include `codex`, and added/extended smokes for capability normalization and policy decisions.
- Real preview before this branch's normalization change: 7 proposals, 4 accepted, 2 ask-human, 1 rejected. Real preview after normalization: 8 proposals, 8 accepted, 0 ask-human, 0 rejected.
- `hermes-apply` persisted planning session `planning-session-a2e63e1b5456ef84` with 6 executable-policy proposals and created no executable tasks by itself.
- Selected two low-risk docs proposals with complete acceptance/evidence fields. Round 1 converted `proposal-331d222d4d38a3af` into `task_proposal-331d222d4d38a3af`; `laptop-zenbookduo` ran one targeted PollOnce; child PR [#76](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/76) changed only `docs/failed-task-patterns.md`, passed checks, merged at `fb4ffc41e4385cd3123e1010032ef50ebd7dd3d6`, and evidence repair recorded `recovered=true`, `ci_status=passed_after_pending`.
- Round 2 converted `proposal-ca9b20ca044e8119` into `task_proposal-ca9b20ca044e8119`; `laptop-zenbookduo` ran one targeted PollOnce; child PR [#77](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/77) changed only `docs/ci-recovery-runbook.md`, passed checks, merged at `a6bed1bab86abb45e245946a34e1c6d4f3659353`, and evidence repair recorded `recovered=true`, `ci_status=passed_after_pending`.
- Stopped after two completed rounds rather than converting weaker proposals with empty acceptance/evidence fields. No local-smoke proposal was executed, no long-running worker loop was started, no production/GitHub-settings/server-root mutation occurred, and historical `task_proposal-59a0236fb69800cd` was not run directly.
- Project control remained/restored `paused` after each PollOnce. Hermes-assisted multi-round reliability sprint is proven for two bounded low-risk docs rounds.

## 2026-05-29 Super Goal 178R Hermes Preview 504 Recovery

- Continued on `ai/super-178-hermes-assisted-multiround-reliability-sprint` after the prior Phase 178A stop. The branch started clean.
- Hermes direct HTTPS health succeeded at `https://api.hermes.example.com` with `ok=true`, `direct_https=true`, platform/model `hermes-agent`, runtime mode `server_agent`, tool execution mode `server`, and `token_printed=false`.
- A tiny direct HTTPS `/v1/responses` probe succeeded in 2.8 seconds, confirming bearer auth, DNS/TLS/proxy routing and basic responses handling.
- The real multi-round `hermes-preview` initially recovered once, producing 6 proposals with 4 accepted docs proposals and 2 local-smoke `ask_human` proposals. The hardening retry using compact state, `MaxHermesAttempts=3`, `RetryDelaySeconds=10` and `TimeoutSeconds=600` still ended in OpenResty `504 Gateway Time-out` during `/v1/responses`.
- Added bounded Hermes preview retry for transient proxy/transport failures only, default compact planner state, a configurable Hermes planner timeout, and smokes for retry and compact-state behavior.
- Hardened the Hermes direct API runbook and OpenResty example for 600 second planning/streaming timeouts and disabled request/response buffering, with a diagnosis path for capabilities OK but responses 504.
- No `hermes-apply`, proposal persistence, proposal conversion, worker `PollOnce`, project-control start, cloud task creation, production deployment, server config mutation or secret printing occurred in this recovery pass.
- Final cloud status remained safe: project control `paused`, no queued/running task residue, and historical `task_proposal-59a0236fb69800cd` still blocked. The multi-round reliability sprint is not proven yet; the next action is server-side verification of the live OpenResty/Hermes long-response route against the documented timeout and buffering settings.

## 2026-05-29 Super Goal 177 Hermes-assisted Single Apply Sprint

- Preflight passed on branch `ai/super-177-hermes-proposal-persistence-single-apply`: `main` was up to date at Super 176 merge commit `0252f37`, no open PRs were listed, SkyBridge cloud health was OK, project control was `paused`, and no queued/running task residue existed.
- Hermes health used direct HTTPS at `https://api.hermes.example.com` with `direct_https=true`, platform `hermes-agent`, runtime mode `server_agent`, tool execution mode `server`; SkyBridge planner metadata still records `tool_execution_mode=disabled` for safety.
- Real `hermes-preview` succeeded with planner mode `hermes-preview`, runtime mode `real-api`, 4 proposals, 3 accepted low-risk docs proposals, and 1 local-smoke `ask_human` proposal. Tokens were not printed.
- Real `hermes-apply` persisted master goal `master-goal-hermes-assisted-self-bootstrap-preview`, planning session `planning-session-36e4ecc246bc2996`, and 3 executable-policy docs proposals. It created no executable task and did not run a worker.
- Selected exactly one low-risk docs proposal: `proposal-4212a5e1447212c0`, `Update sprint progress after master goal doc merged`, dedupe key `proposal-progress-after-pr69-20260529`, expected file `docs/dev/PROGRESS.md`.
- Converted exactly one task: `task_proposal-4212a5e1447212c0`. Before execution it was the only queued/running task; historical `task_proposal-59a0236fb69800cd` remained blocked and was not run.
- Ran exactly one PollOnce through `laptop-zenbookduo`. Codex succeeded without transport retry (`retry_count=0`), changed only `docs/dev/PROGRESS.md`, and opened child PR [#73](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/73).
- Child PR #73 passed AI branch validation, Project check, Docker build server and Docker build web. It was marked ready, merged as low-risk docs-only with commit `c69aa6c209b61481cb8067bc58e4191faf76309d`, and its branch was deleted.
- CI Guardian had recorded the task as failed while checks were pending, so evidence repair was applied. `task_proposal-4212a5e1447212c0` now has `evidence_summary.recovered=true`, `ci_status=passed_after_pending`, `risk_status=low_docs_only`, PR #73 and the merge commit.
- Project control was restored to `paused` with `stop_requested=false`. No long-running worker loop, local-smoke proposal, production deployment, GitHub settings change, branch protection change, secret commit or extra task execution occurred. Hermes-assisted single apply is proven through proposal persistence -> selected docs proposal conversion -> targeted PollOnce -> child PR checks -> merge -> evidence repair.

## 2026-05-29 Sprint Pause After Master Goal Doc Merge

- Master goal doc PR [#69](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/69) merged after GitHub Actions passed and lifecycle policy approved the docs-only child task. The recovered task evidence now points at the merged master goal doc work.
- Recent merged sprint PRs are [#69](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/69), [#70](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/70) and [#71](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/71); no new code or cloud-control mutation is part of this progress update.
- The sprint is paused by operator. Project control should remain paused until the operator explicitly resumes the loop.
- `task_proposal-59a0236fb69800cd` remains blocked and should not be claimed by a worker until the operator either unblocks/requeues it with updated scope or closes it as historical retry fallout.
- `laptop-zenbookduo` is the sole active online worker recorded for the sprint. Do not start additional workers or raise worker parallelism until explicit locking and conflict handling are in place.
- Next unblock steps: confirm the project still has no queued/running residue, decide whether to retire or re-scope `task_proposal-59a0236fb69800cd`, verify `laptop-zenbookduo` can heartbeat through token-file auth, then resume with a bounded one-task run only after operator approval.

## 2026-05-28 Super Goal 176 Hermes Direct API and Preview Workflow Hardening

- Preflight on branch `ai/super-176-hermes-direct-api-preview-hardening` confirmed `main` was up to date at PR #71 merge commit `131f01c`, `gh pr list` returned no open PRs, and SkyBridge cloud status was read-only healthy.
- Cloud project `skybridge-agent-hub` remained `paused` with `stop_requested=false`; status showed one historical blocked task and no running task. No project-control mutation, task conversion, worker PollOnce or real cloud task creation was run.
- Current Hermes env still pointed at tunnel mode, `http://127.0.0.1:18642`, with a 64-character key. The tunnel capabilities check was refused in this session, so direct HTTPS is documented but not proven configured.
- Added direct HTTPS Hermes API runbook and OpenResty example for `https://api.hermes.example.com -> 127.0.0.1:8642`, preserving bearer auth, avoiding Dashboard exposure, and supporting long planning responses/streaming.
- Added `skybridge-hermes-health.ps1` and `skybridge-hermes-preview.ps1`. Preview wrapper defaults to `hermes-preview`, dry-run only, no proposal persistence, no task creation, no worker run, no project-control mutation, and `token_printed=false`.
- Hardened constraints with `-ConstraintsFile` and `-ConstraintsJson`; wrappers pass merged constraints as JSON to avoid PowerShell `pwsh -File` array-binding drift into acceptance criteria or stop conditions.
- Normalized Hermes proposal output so top-level `proposals` and `planning_session.proposals` contain the same policy-validated proposals during preview. The preview wrapper emits a compact proposal table and a quality summary/report.
- Normalized Hermes task types before policy validation: `smoke -> local-smoke`, `doc`/`documentation -> docs`, safe smoke-path `test -> local-smoke`; blocked surfaces such as deploy, production, secrets, GitHub settings, branch protection and server config remain human-gated or rejected.

## 2026-05-27 Super Goal 175 Hermes-assisted Multi-round Self-Bootstrap Sprint

- Implemented gated Hermes-assisted planning foundations on branch `ai/super-175-hermes-assisted-multiround-self-bootstrap`: `rule-based`, `hermes-preview`, and `hermes-apply` planner modes; strict Hermes proposal parsing; policy validation outputs; advisory evaluator records; default supervisor `MaxRounds=2`; active task residue checks; and fixture smokes.
- Preflight confirmed PR #70 was merged, tag `v0.43.0-first-dogfood-self-bootstrap-sprint` exists, cloud project `skybridge-agent-hub` was paused with no queued/running residue, `task_proposal-d90d09da925d2cf0` was recovered through PR #69, `task_proposal-59a0236fb69800cd` remained blocked, and `laptop-zenbookduo` could register-heartbeat online.
- Real `hermes-preview` attempted against the configured local Hermes profile, but the endpoint refused the connection. No proposals were faked, no task was converted, no worker PollOnce apply ran, and project control was restored to `paused`.
- Added sprint report: `docs/dev/HERMES_ASSISTED_SELF_BOOTSTRAP_SPRINT.md`.
- Verification passed for the requested supervisor/planner/guide/worker/Hermes smokes, `validate-powershell.ps1`, and `just check`.

## 2026-05-27 Super Goal 174 Dogfood Self-Bootstrap Sprint

- Preflight against `https://skybridge.example.com` succeeded: project control was paused, `laptop-zenbookduo` heartbeated online through token-file auth, no queued/running tasks were visible, and supervisor dry-run selected low-risk docs proposal `proposal-d90d09da925d2cf0`.
- The selected proposal was `Record master goal plan` for `master-goal-prepare-skybridge-dogfood-self-bootstrap-sprint`, with expected files limited to `docs/dev/MASTER_GOAL_PREPARE_SKYBRIDGE_DOGFOOD_SELF_BOOTSTRAP_SPRINT.md` and `docs/dev/PROGRESS.md`.
- Added supervisor UX polish so `skybridge-supervise.ps1` and guided supervisor modes can derive a deterministic `master-goal-*` id from `-GoalTitle` when `-MasterGoalId` is omitted.
- Real supervisor apply was attempted with `MaxRounds=1`. Structured run `supervisor-run-20260527045305-6522d2e0a752` failed with `stop_reason=supervisor_error` because the cloud server returned `404 Not Found` for `POST /v1/master-goals`. This indicates the deployed cloud server does not yet expose the planner persistence routes required for supervisor apply.
- No proposal was converted, no executable task was created, no worker `PollOnce` execution ran, and no child PR was opened. Project control was verified after the failed apply as `paused` with `stop_requested=false`.
- After the cloud server was updated and planner persistence succeeded, the retry exposed two local reliability gaps before the bounded apply: worker task compatibility ignored persisted `task_type=docs`, and run-once did not target or fail on the requested task id. The parent branch now fixes task-type preservation, target-task PollOnce, no-task failure reporting and docs/dev proposal preference.
- Retry preflight then selected the intended proposal `proposal-d90d09da925d2cf0` with converted task id `task_proposal-d90d09da925d2cf0`. A previously converted runbook task `task_proposal-59a0236fb69800cd` remains queued as historical retry fallout, but targeted PollOnce prevented it from being claimed.
- Bounded retry supervisor run `supervisor-run-20260527051547-c11fd86e34b0` converted and ran exactly one low-risk docs proposal. `laptop-zenbookduo` claimed and started `task_proposal-d90d09da925d2cf0`, edited `docs/dev/MASTER_GOAL_PREPARE_SKYBRIDGE_DOGFOOD_SELF_BOOTSTRAP_SPRINT.md`, then Codex exited nonzero after repeated ChatGPT Codex websocket TLS handshake EOF errors.
- Cloud task `task_proposal-d90d09da925d2cf0` final status is `failed` with no child PR, CI or evidence summary. Project control was restored to `paused` with `stop_requested=false`. The first dogfood self-bootstrap sprint is not yet proven; it is blocked on Codex execution transport reliability after successful cloud planning, proposal conversion, task claim and project-control rollback.
- Goal 174C added bounded Codex transport classification and retry: websocket/TLS/EOF/connection reset transport failures are classified as retriable Codex transport errors, retried at most once, and failed evidence records `execution_error_class`, `retry_count` and `recovered=false` without treating normal validation/build/CI failures as transport issues.
- Retry preflight confirmed project control was `paused`, no queued/running tasks existed, `task_proposal-59a0236fb69800cd` remained `blocked`, and `laptop-zenbookduo` could register-heartbeat online through token-file auth. Only `task_proposal-d90d09da925d2cf0` was requeued and targeted.
- The real retry ran `skybridge-run-once.ps1 -NoSubmit -Apply` for `task_proposal-d90d09da925d2cf0`. Codex succeeded on the first attempt of this run (`retry_count=0`), while the new local smoke proves the one-retry path with `execution_error_class=codex_transport_eof`.
- Worker-created child PR #69 changed only `docs/dev/MASTER_GOAL_PREPARE_SKYBRIDGE_DOGFOOD_SELF_BOOTSTRAP_SPRINT.md`. PR #69 was marked ready after docs-only review, all required GitHub Actions checks passed, and lifecycle policy merged it with commit `81399f6afff508b47f53ccaeeba4fbad8cfe6305`.
- Evidence repair for `task_proposal-d90d09da925d2cf0` succeeded. The task raw status remains `failed` to preserve the original transport-failure history, but `skybridge-status.ps1` now shows `display_status=failed/recovered`, `evidence_summary.recovered=true`, `ci_status=passed_after_pending`, and PR URL `https://github.com/JerrySkywalker/skybridge-agent-hub/pull/69`.
- Project control ended `paused` with `stop_requested=false`. The first dogfood self-bootstrap sprint is proven through recovered evidence: cloud planning -> proposal conversion -> targeted worker claim/start -> Codex docs edit -> child PR -> GitHub Actions green -> lifecycle merge -> evidence repair.

## 2026-05-27 Super Goal 173 Self-Bootstrap Supervisor Loop

- Added `skybridge-supervise.ps1`, a dry-run-first bounded supervisor that composes project status, rule-based planning, proposal selection, proposal conversion and optional one-shot worker execution.
- Added a lightweight supervisor run/round/decision output model with stop reasons, selected proposal/task, PR/CI/evidence fields and `token_printed=false`.
- Added deterministic supervisor policy coverage for low-risk docs selection, high-risk human review, worker availability and recovered evidence semantics.
- Extended `skybridge-guide.ps1` and `skybridge-hermes-cli.ps1 -Area operator` with supervisor preview/apply/status routing.
- Added local fixture smokes for supervisor dry-run, policy, apply-without-Codex conversion, guide supervisor flow and Hermes CLI supervisor facade. Real cloud mutation and long-running worker loops remain deferred.

## 2026-05-27 Super Goal 172 Master Goal Planner

- Added a lightweight planning model: `planning_master_goals`, `planning_sessions` and `task_proposals`. This keeps high-level planning separate from the existing executable Goal Registry while still allowing proposal conversion into normal queued tasks.
- Added `skybridge-plan.ps1`, a deterministic rule-based planner that builds compact project state and emits 1-5 reviewable task proposals with dedupe keys, expected files, acceptance criteria, evidence requirements, risk, required capabilities and rationale. Dry-run is default; `-Apply` creates planning records only.
- Added `skybridge-proposal.ps1` for proposal list/show/accept/reject/convert. Conversion previews are dry-run by default, high-risk proposals require `-AllowHighRisk`, and converted tasks carry expected files into allowed paths plus planner metadata.
- Added the disabled Hermes planner seam through planner adapter audit metadata: provider, model, planner mode, prompt version and input state hash. CI and smokes do not call Hermes.
- Extended `skybridge-guide.ps1` and `skybridge-hermes-cli.ps1 -Area operator` with plan/proposal modes. `inspect-task` now surfaces useful task detail, and run-once preview next commands preserve submit context when available.
- Added local planner/proposal smokes. No real cloud task creation, Codex execution or worker loop is required.

## 2026-05-27 Super Goal 171 Guided Goal Submission And Recovered Status Semantics

- Improved `skybridge-status.ps1` recovered-task presentation. Raw `task.status` remains unchanged for history, but failed tasks with `evidence_summary.recovered=true` and `ci_status=passed_after_rerun` now expose `display_status=recovered`; task detail shows `raw_status`, `display_status`, `recovered`, `ci_status`, `pr_url` and summary.
- Added `skybridge-guide.ps1`, a dry-run-first guided operator wrapper for status, submit preview/apply, run-once preview/apply, task inspection, worker inspection and project start/pause. It composes the existing operator scripts, prints next suggested commands and preserves `token_printed=false`.
- Extended `skybridge-hermes-cli.ps1` with an `operator` facade for guided status, submit, run-once, inspect, pause and start commands.
- Added local fixture smokes for recovered display semantics, guided operator flow and Hermes CLI facade routing. No real cloud mutation or long-running loop is required for these checks.
- Long-running remote worker loop remains deferred; guided apply modes still require explicit `-Apply` and use bounded `PollOnce` behavior.

## 2026-05-27 Super Goal 170 First Real Operator Submit-And-Run

- Polished the v0.37 operator UX: `skybridge-submit.ps1` now emits a copyable `skybridge-run-once.ps1` next command with API, project, goal, task and token-file/env context, and `skybridge-run-once.ps1` reports clearer submit-mode parameter errors.
- Fixed compact worker timestamp handling for PowerShell-converted JSON dates. Online and stale worker heartbeats now display fresh relative times instead of local-timezone-skewed values.
- Preflight against `https://skybridge.example.com` confirmed project control was `paused`, `laptop-zenbookduo` could register-heartbeat online through token-file auth, and no queued/claimed/running historical task would interfere.
- `skybridge-submit.ps1 -Apply` created real low-risk docs-only task `operator-real-docs-task-170` under goal `operator-real-goal-170`; token values were not printed.
- `skybridge-run-once.ps1 -NoSubmit -Apply` started control with `max_tasks=1`, heartbeat-registered `laptop-zenbookduo`, ran the edge worker with `-PollOnce`, and restored control to `paused`.
- Worker-created child PR #60 changed only `docs/dev/OPERATOR_SUBMIT_RUN_WORKFLOW.md`. GitHub Actions passed: AI branch validation, PR CI, Docker server and Docker web. Merge coordinator marked it ready, classified it low-risk/eligible, and enabled auto-merge; PR #60 merged with commit `536837c28870daeab84b5e438e1e3b3700879fda`.
- Cloud task `operator-real-docs-task-170` remains `failed` because CI Guardian recorded pending CI as blocked before checks completed. This failed status is preserved by design as task history.
- Follow-up recovery: after the cloud server was updated to the latest main image, `/v1/tasks/operator-real-docs-task-170/evidence-repair` accepted recovered evidence with `ok=true`. `skybridge-status.ps1` now shows the task as `status=failed` with `evidence=recovered`.
- Proof status: operator submit -> run-once -> local worker claim -> Codex docs edit -> worker-owned child PR -> GitHub Actions green -> policy merge -> recovered evidence is proven. This completes the Super 170 recovery story while preserving the original failed event history.

## 2026-05-26 Super Goal 169 Operator Goal Submission Workflow

- Added `skybridge-submit.ps1`, a dry-run-first operator command that can ensure a project/goal and create one task with default `required_capabilities=["codex"]`, token env/file support, JSON output and no token printing.
- Added `skybridge-run-once.ps1`, a one-shot operator workflow that records status snapshots, optionally submits a task, starts project control with `max_tasks=1`, register-heartbeats the worker, runs the edge worker with `-PollOnce`, and restores project control to `paused` in `finally`.
- Fixed compact worker status timestamps so an online worker no longer displays a stale relative time immediately after heartbeat. Remote status reads also use a longer timeout for cloud task lists.
- Extended `skybridge-hermes-cli.ps1` as a facade for goal submit/list, task create/list/show, project status/start/pause, worker status/heartbeat and run-once routing.
- Added local smokes for submit, run-once and the combined operator workflow. Real cloud checks were limited to status, heartbeat, submit dry-run and run-once dry-run; no remote task was created.
- Long-running remote `-Loop` remains deferred. The standard workflow is status -> submit -> run-once -> status -> inspect PR/evidence.

## 2026-05-26 Super Goal 168 Remote Worker Reliability

- Added CI failure classification for green, pending, real failures, checkout HTTP 403, account-suspended text, transient checkout/fetch failures and unknown outcomes. The classifier uses fixture logs in smokes and does not call GitHub with real secrets.
- Added `skybridge-rerun-ci.ps1`, a dry-run-first PR CI rerun helper that lists failed runs, reruns only when `-Apply` is explicit and stops after one batch.
- Added task evidence repair support through `/v1/tasks/:taskId/evidence-repair` and `Repair-TaskEvidence`. Repairs append `task.evidence_repaired`, keep the original failed event, and can mark EvidenceSummary as `recovered=true` with `ci_status=passed_after_rerun`.
- Improved `skybridge-status.ps1` with task/worker limits, active/problem-task default filtering, `-ShowCompleted`, `-ShowAll`, `-TaskId`, `-WorkerId`, PR and evidence columns, full-fidelity JSON output and `token_printed=false`.
- Added `skybridge-control.ps1` for project status/start/pause/stop/set-max-tasks and `skybridge-worker-status.ps1` for profile-aware register/heartbeat/status checks with token-file support.
- Server tests now isolate `SKYBRIDGE_WORKER_TOKEN`, `SKYBRIDGE_WORKER_TOKENS_FILE` and `SKYBRIDGE_REMOTE_API_BASE` so local no-auth tests are not polluted by a worker shell.
- Operator guidance now recommends token files, compact status, project-control helper commands, one-shot worker checks, CI rerun/recovered-evidence workflow and no long-running remote loop yet.

## 2026-05-26 Goal 167B First Remote Worker Execution Pilot

- Remote preflight used `$HOME\.skybridge\worker.laptop-zenbookduo.json` with `token_file_configured=true`; token values were not printed. `laptop-zenbookduo` registered and heartbeated through `https://skybridge.example.com` using direct bearer-token worker auth.
- Initial compact status showed project `skybridge-agent-hub` paused, `remote-claim-smoke-001` blocked, `remote-claim-smoke-002` completed and no queued stale smoke task. Snapshots were written under `.agent/tmp/remote-status-before-167b.json` and `.agent/tmp/remote-status-after-167b.json`.
- `remote-docs-exec-pilot-001` already existed from the first failed attempt, so the second run created docs-only task `remote-docs-exec-pilot-002` for goal `remote-worker-smoke-goal` with `required_capabilities=["codex"]`, then started project control with `state=running`, `stop_requested=false`, `max_tasks=1`.
- `-PollOnce` proved remote heartbeat, control read, task claim/start and Codex docs execution. Validation was skipped because no validation commands were configured, using the worker fix that ignores empty validation commands.
- The worker created draft child PR #57. After verifying it changed only `docs/dev/REMOTE_WORKER_EXECUTION_PILOT.md` and was classified low-risk child-task work, PR #57 was marked ready for review.
- CI Guardian blocked the task because GitHub Actions checkout failed with HTTP 403 and an account-suspended message. This was not retried as a dependency-download transient.
- Child PR: https://github.com/JerrySkywalker/skybridge-agent-hub/pull/57
- Child PR recovery: PR #57 checks later recovered and passed, and PR #57 merged at `2026-05-26T13:02:48Z` with merge commit `99c4c21b2fb1881596d48db43482beedbb0384a8`.
- Cloud task final status remained `failed`, with task result PR URL pointing to PR #57 and EvidenceSummary recorded with `ci_status=blocked_github_checkout_403`, because the original worker-owned task report captured the initial CI Guardian blocker.
- Project control was restored to `paused` with `stop_requested=false` and stop reason `operator_paused_after_167b_pilot`.
- Evidence summary: the cloud control plane -> local worker claim -> Codex docs edit -> worker-owned child PR packaging -> low-risk ready gate -> GitHub Actions green -> merge path is proven. Server-side evidence repair from failed task to completed task remains a follow-up need if the API rejects failed -> completed repair.

## 2026-05-26 Super Goal 167 Remote Worker Execution Pilot Prep

- Added `scripts/powershell/skybridge-status.ps1`, a compact cloud status command for narrow terminals. It queries `/v1/health`, project control, workers and project tasks, renders compact worker/task tables, and can write full JSON snapshots to `.agent/tmp` without printing worker tokens.
- Added `smoke-skybridge-status.ps1`, which starts a temporary local SkyBridge server, seeds paused project control, online/offline workers and queued/running/completed/failed/blocked tasks, then verifies compact and JSON status output.
- Remote preflight confirmed `$HOME\.skybridge\worker.laptop-zenbookduo.json` exists and loads as a bearer-token remote worker profile for `https://skybridge.example.com` without printing token values.
- Blocker: `SKYBRIDGE_WORKER_TOKEN` was not present in this Codex process, user environment or machine environment, and the profile has no configured token file. Because worker-sensitive routes require bearer auth, the real remote register/heartbeat, cloud docs task creation, `-PollOnce` execution, child PR packaging and EvidenceSummary reporting were not run.
- Safety state: project control was not changed by this run, so no start/resume operation needed rollback; the project was expected to remain paused from the prior safe state.

## 2026-05-26 Super Goal 166 Cloud Server Remote Worker Smoke

- Added safe cloud deployment wiring templates for `https://skybridge.example.com`: topology doc, server env example, SkyBridge compose template, OpenResty reverse proxy example and remote home PC worker profile example.
- Added `smoke-remote-skybridge-api.ps1` for dry-run request construction, remote `/v1/health`, optional worker register/heartbeat and optional missing/wrong token rejection checks without printing tokens.
- Added first remote worker registration runbook with DNS, HTTPS, token, profile, smoke command and 401/403/502/TLS troubleshooting.
- Real remote smoke was skipped in this session because `SKYBRIDGE_REMOTE_API_BASE` and `SKYBRIDGE_WORKER_TOKEN` were not present in the local environment.
- No production deployment, server config mutation, public Hermes exposure, real token commit, GitHub settings mutation or unattended auto-merge was performed.

## 2026-05-26 Super Goal 165 Direct Worker Connectivity

- Added direct worker connectivity architecture and a first bearer-token auth boundary for worker-sensitive routes. Local development remains no-auth when no worker token is configured; remote workers use `auth_mode=bearer_token`.
- Server-side worker auth supports `SKYBRIDGE_WORKER_TOKEN`, `SKYBRIDGE_WORKER_TOKENS_FILE` and structured 401/403 responses without logging token values.
- Worker profiles now include allowed project IDs, remote-server allow flag, HTTPS enforcement for non-localhost API bases, token env/file settings and redacted auth/API status in worker records.
- Added token auth success/failure smokes and a remote-profile dry-run smoke. No real worker token, env file, production deploy, GitHub settings mutation or public Hermes exposure was introduced.
- Added SkyBridge Server API deployment guidance. Remaining production gaps: real cloud deployment wiring, token issuing/rotation/revocation APIs, scoped worker tokens and first explicit remote worker registration smoke.

## 2026-05-26 Super Goal 164 Cloud Control Plane Foundations

- Added the cloud control plane architecture direction: SkyBridge Server is the authoritative state source, the Goal Registry is the durable objective registry, local workers are execution caches and direct SkyBridge API connectivity replaces SSH tunnel dependency for long-term worker operation.
- Added worker profile examples and a profile loader. Real profiles belong under `$HOME\.skybridge\worker.<hostname>.json`; repo examples use placeholders only. `SKYBRIDGE_API_BASE`, `SKYBRIDGE_WORKER_TOKEN` and `SKYBRIDGE_WORKER_TOKEN_FILE` establish the remote worker-token boundary without implementing production auth.
- Hardened Goal Registry metadata with source, priority, risk, lifecycle, acceptance criteria, evidence requirements, dedupe key, supersession fields, blocked/stale reasons, planner metadata, optional audit-only model backend metadata, completion note, progress summary and EvidenceSummary.
- Added governance checks for blocked/completed/superseded goals and executable-task rejection for archived or superseded goals.
- Added Markdown goal import/export scripts, worker profile smoke, goal registry smoke, goal import/export smoke and goal-task-evidence smoke.
- Updated typed client helpers and Operator Console Goals view to show goal registry state, evidence count and active-goal overview data.
- Production cloud deployment, worker token issuing/rotation/revocation and public remote auth remain deferred. Next recommended goal: Direct Cloud Server Connectivity and Worker Token Auth.

## 2026-05-26 Super Goal 162 Self-Bootstrap PR Lifecycle Rerun

- Created branch `ai/super-162-self-bootstrap-pr-lifecycle-rerun` from latest `main` after PR #43 was merged, then fixed the lifecycle coordinator gap where green low-risk draft child PRs could not be marked ready before auto-merge.
- Real Hermes used `/v1/responses` through `http://127.0.0.1:18642` with model `hermes-agent` and private server-agent runtime. Planner calls used real mode with compact state snapshots, no session continuity and no planner-side tool invocation requested.
- First real call against the existing self-bootstrap goal returned `stop` because compact state already satisfied prior acceptance, proving Hermes avoided duplicate PlannerAdapter work.
- Super 162 rerun used a local ignored master goal and `GoalId=super-162-self-bootstrap-pr-lifecycle-rerun`. Hermes planned one new low-risk docs task, worker `edge-worker-super-141` claimed it, Codex resolved from PATH, validation passed with `just check`, and draft child PR #44 was created.
- Merge coordinator dry-run classified PR #44 as low-risk child docs work with no duplicates, then `-Apply` marked it ready. A second coordinator pass classified it `auto_merge_eligible=true` and enabled GitHub auto-merge. PR #44 auto-merged at `2026-05-26T07:04:37Z`.
- A second real planner call read compact state with completed task `hermes-super-162-pr-20260526065837` in `do_not_repeat` and returned `stop` instead of repeating the task. No duplicate task was created.
- Sent exactly one final non-urgent ntfy summary; WeCom skipped because the notification was non-urgent.
- Follow-up blocker: the real Hermes evaluator returned invalid JSON missing `reason` after the completed child task, so the loop stopped safely after one execution round. Planner dedupe and PR lifecycle still completed, but evaluator schema repair should be hardened before unattended mode.

## 2026-05-26 Super Goal 161 PR Lifecycle And Planner Feedback

- Added PR lifecycle terminology, merge coordinator policy, PR classifier, dry-run merge coordinator, compact planner state builder, planner dedupe contract, and fixture smokes for lifecycle and planner dedupe behavior.
- Default future policy is child task PRs use auto PR plus auto-merge when eligible; parent/super-goal PRs use auto PR plus manual merge by default; high-risk PRs require human review and notification.
- CI Guardian and auto-merge sweep now route auto-merge attempts through the PR lifecycle classifier before enabling GitHub auto-merge.
- Live merge coordinator dry-run against the real repository returned zero open PRs, with no eligible, duplicate, stale, conflicting or high-risk PRs and no mutations applied.
- Updated Hermes runbooks and API docs with compact planner state, PR lifecycle defaults, classifier/coordinator scripts and required Hermes reporting metadata. Final validation passed: `smoke-pr-lifecycle-policy.ps1`, `smoke-hermes-planner-dedupe.ps1`, `smoke-self-bootstrap-loop.ps1 -DryRun`, `smoke-hermes-planner.ps1`, `smoke-auto-merge-policy.ps1`, `smoke-ci-guardian.ps1 -DryRun`, `smoke-worker-task-core.ps1`, `smoke-task-state-machine.ps1`, `validate-powershell.ps1` and `just check`.

## 2026-05-26 Super Goal 160B Real Hermes Self-Bootstrap Rerun

- Preflight confirmed PR #35 (`1c0ffa2`) and PR #38 (`a6708fc`) were merged to `main`, Hermes API base/key were present without printing secret values, `/v1/responses` was available, and Edge Worker Codex resolution used PATH rather than a temporary `.agent` shim.
- Preflight passed: Hermes cloud API smoke, Hermes cloud run smoke, Hermes planner dry-run smoke, self-bootstrap dry-run smoke, Edge Worker register/claim smokes and Codex task runner dry-run smoke.
- Ran `skybridge-self-bootstrap-loop.ps1 -MaxRounds 3 -Send -Json` against `goals/master/self-bootstrap-smoke.md` on the live local SkyBridge API. The loop attempted and completed 3 real Hermes-planned docs-only/low-risk rounds.
- Worker ID for all rounds: `edge-worker-super-141`. Codex resolved from PATH to the installed Windows PowerShell shim and each task validated with worker-owned `just check`; nested Codex did not own commit, push or PR creation.
- Round 1 Hermes planner decision: `continue`; task `hermes-clarify-hermes-planneradapter-runbook-20260526043833`; result completed; draft PR #39 created: https://github.com/JerrySkywalker/skybridge-agent-hub/pull/39; CI Guardian passed; auto-merge disabled.
- Round 2 Hermes planner decision: `continue`; task `hermes-clarify-hermes-planneradapter-runbook-20260526044205`; result completed; draft PR #40 created: https://github.com/JerrySkywalker/skybridge-agent-hub/pull/40; CI Guardian passed; auto-merge disabled.
- Round 3 Hermes planner decision: `continue`; task `hermes-hermes-task-20260526044512`; result completed; draft PR #41 created: https://github.com/JerrySkywalker/skybridge-agent-hub/pull/41; CI Guardian passed; auto-merge disabled.
- Child PR merge status: none were merged; all child PRs remained draft PRs because worker `auto_merge_enabled` stayed false.
- Notification status: sent exactly one final non-urgent bootstrap ntfy summary; WeCom skipped because the notification was `info`.
- Remaining blockers before unattended Hermes self-ordering: Planner state feedback is still too thin across rounds, so Hermes repeated the PlannerAdapter runbook task in rounds 1 and 2 and treated round 3 as a fresh first-round progress note. The loop should persist and pass compact completed-task/PR state into each subsequent planner prompt before unattended self-ordering. Auto-merge remains intentionally disabled for the worker until a separate policy-gated docs-only sweep enables it.

## 2026-05-26 Super Goal 142A Edge Worker Codex Invocation Hardening

- Root cause confirmed: local `config/edge-worker.json` still pointed `codex_command` at deleted `.agent/super-141-real-pilot/codex-worker.cmd`, so the worker depended on a temporary Super 141 shim that no longer existed.
- Hardened worker Codex resolution: explicit `codex_command` is still preferred when configured, but omitted config now resolves `codex` from `PATH` with `Get-Command`; missing explicit commands fail with a clear setup error.
- Hardened Windows invocation: PowerShell Codex shims such as `codex.ps1` run through `pwsh -File`, and task prompts are written to local `prompt.md` files and passed through stdin with the `-` prompt marker to avoid multi-word and long-prompt quoting bugs.
- Enforced ownership split in the nested Codex task prompt: Codex edits only; the edge worker owns safe file filtering, validation, commit, push, draft PR creation and CI Guardian.
- Added `.agent/workers/` to gitignore and updated edge worker/Codex adapter docs with command resolution, Windows shim behavior, prompt stdin handling and local worker artifact handling.
- Validation passed: `smoke-codex-task-runner.ps1 -DryRun`, `smoke-edge-worker-register.ps1`, `smoke-edge-worker-claim.ps1`, `smoke-worker-task-core.ps1`, `smoke-task-state-machine.ps1`, `validate-powershell.ps1` and `just check`.
- Real docs-only worker pilot passed. Task `super-142a-codex-invocation-pilot-20260526122339` was claimed by `edge-worker-super-141`, Codex resolved from `PATH` to `C:\Users\jerry\AppData\Roaming\npm\codex.ps1`, validation ran `just check`, the worker created draft PR #37 and completed the task. Auto-merge remained disabled.
- Child PR: https://github.com/JerrySkywalker/skybridge-agent-hub/pull/37
- Remaining blocker before Hermes planner dispatch: ensure each real worker host has either a working Codex CLI on `PATH` or a durable explicit `codex_command`; do not use task-specific `.agent` shims.

## 2026-05-26 Super Goal 142-160 Hermes Planner Bootstrap

- Added the neutral PlannerAdapter contract extensions for `continue`, `repair`, `wait`, `stop`, `blocked`, work-order/task metadata, validation commands, risk, allowed/blocked paths, task type and stop criteria. Hermes remains optional and records tasks as `source=hermes-planner`.
- Added `docs/hermes/prompts/self-bootstrap-planner.md`, `scripts/powershell/skybridge-hermes-planner.ps1`, `skybridge-hermes-evaluate-result.ps1`, `skybridge-self-bootstrap-loop.ps1`, `skybridge-hermes-cli.ps1` and dry-run smoke wrappers for planner, evaluation and loop validation.
- Added the self-bootstrap master goal at `goals/master/self-bootstrap-smoke.md` and runbooks for the Hermes PlannerAdapter and self-bootstrap loop.
- Updated the Operator Console Hermes and task views to show active master goal, planner decision, current Hermes-planned task, recent task result, worker assignment and self-bootstrap loop status.
- Dry-run validation completed three simulated docs-only rounds with no real Codex execution and no real notification send in the loop smoke.
- Real pilot status: Hermes env and worker config were present, and SkyBridge API was healthy, but the configured Hermes `/v1/responses` endpoint refused the connection before a real planner task could be generated. No real Hermes-planned task, worker execution, PR or auto-merge action occurred.
- Notification status: sent exactly one non-urgent bootstrap ntfy notification for the Hermes-unavailable blocker; WeCom skipped because the event was non-urgent.
- Blocker before unattended Hermes self-ordering: restore the private Hermes tunnel/API availability, then rerun one real planner task creation before allowing the edge worker to execute a round. The remaining two rounds should stay docs-only until the first real round has a task, PR and CI record.

## 2026-05-25 Super Goal 061-080 Productization Sprint

- Added the Operator Console product spec covering Overview, Runs, Iterations, PR/CI, Auto-merge, Notifications, Hermes, Sources/Adapters, Audit and Settings.
- Added safe local-derived product APIs: `/v1/projects`, `/v1/iterations/summary`, `/v1/prs/summary`, `/v1/notifications/summary`, `/v1/hermes/summary` and `/v1/automerge/summary`, and expanded `/v1/summary`.
- Added typed client helpers and tests for the new dashboard product APIs.
- Reworked the web Operator Console into hash-routed product surfaces for overview, runs, iterations, PR/CI, notifications, Hermes, sources/audit, settings and compact embed.
- Expanded demo seeding with Codex, OpenCode and Hermes runs, PR/CI records, auto-merge sweep dry-run, failed CI, notification sent/failed telemetry, audit records and a blocked high-risk PR.
- Added `smoke-product-console.ps1` and `corepack pnpm smoke:product-console` to validate seeded product state, summary APIs and web build without a browser by default.
- Improved the compact Web Component embed to show product status, PR/CI count, Hermes status, last notification and offline state.
- Updated optional browser visual QA to target overview, PR/CI, Hermes, notifications and embed routes, and to write a skip manifest when Playwright is unavailable.
- Added product quickstart, screenshot guide and API overview docs; updated README, CONTRIBUTING, Hermes and bootstrap notification runbooks.
- Real now: server persistence, summary APIs, typed client helpers, routed local UI, compact embed, demo smoke, audit-safe derived state.
- Demo/fixture-backed now: OpenCode runtime data, Hermes degraded/supervisor data, PR/CI and auto-merge decision rows when not produced by real local scripts.
- Deferred: public Hermes exposure remains forbidden, production deployment remains manual, real GitHub settings mutation is absent, always-on unattended auto-merge remains disabled, full browser screenshot capture depends on Playwright availability.

## 2026-05-25 Super Goal 049-060 Hermes Always-on Autonomy Pilot

- Added a Hermes tunnel lifecycle helper, check-only tunnel smoke and tunnel recovery guide. The validated local tunnel was listening on `127.0.0.1:18642`; no duplicate tunnel was started.
- Added the Hermes health watchdog and smoke. Validation checked the tunnel, `/health` and `/v1/capabilities` through the local tunnel with the Hermes API key present but not printed.
- Added the nightly supervisor report. It collects Hermes health, GitHub open PRs, latest workflow status, auto-merge sweep dry-run, local SkyBridge API status, bootstrap notification config and a progress tail summary.
- Hardened the Hermes-supervised sweep path with `NightlySweep`, `NightlyReport` and `SweepAndNotify` supervisor modes plus policy counts for eligible, blocked, draft, non-AI branch, high-risk file, missing-check and pending-check states.
- Added the Windows Task Scheduler-compatible nightly pilot wrapper. It writes local logs under `.agent/nightly/<timestamp>/`, verifies or starts the tunnel, checks Hermes health, runs the nightly report and runs a dry-run sweep by default.
- Added server-side supervisor option docs. Current mode remains local Windows execution with cloud Hermes supervision through the private tunnel; no server worker was deployed and no `/opt`, OpenResty, Authelia, 1Panel or Docker daemon config was touched.
- Phase 055 real phone summary test: sent one non-urgent nightly supervisor report notification through the new report command; ntfy reported sent and urgent notification was not used.
- Phase 056 candidate PR decision: skipped creating a new tiny docs-only candidate because GitHub reported zero open PRs and the new nightly sweep/report paths already exercised the real repository dry-run path safely. No real auto-merge occurred.
- Added operator docs alignment for the local Codex worker, GitHub CI/auto-merge gate, auto-merge sweep, Hermes cloud supervisor, bootstrap ntfy fallback and human-only controls.
- Added a safe failure drill covering simulated Hermes unavailable, no eligible PRs, blocked high-risk PR and phone-notification dry-run preview.
- Phase 059 validation passed: PowerShell parse validation, Hermes env loading, tunnel check-only smoke, health watchdog smoke, Hermes cloud API smoke, Hermes cloud run smoke, supervised sweep dry-run, nightly sweep dry-run, failure drill, bootstrap notification dry-run, Codex phone notification dry-run, auto-merge policy smoke and `just check`.
- Safety notes: no secrets, local env files, production deploy, server root config mutation, GitHub settings mutation, public Hermes exposure, WSS remote execution, urgent notification or real auto-merge were introduced.

## 2026-05-23 Super Goal 042-048 Hermes Cloud Supervisor Integration

- Added safe local Hermes env loading from `$HOME\.skybridge\hermes.env.ps1` or `HERMES_ENV_FILE`, with JSON presence reporting and no secret values included.
- Added Hermes cloud API and harmless run smokes for the local SSH tunnel path. Real validation connected through `http://127.0.0.1:18642`; `/health`, `/health/detailed`, `/v1/capabilities` and `/v1/models` responded, and the safe `/v1/responses` prompt matched the expected health sentence without printing the response text.
- Hardened `skybridge-hermes-supervisor.ps1` with `HermesHealth`, `HermesRunSmoke`, `AutoMergeSweepDryRun`, `NotifyTest`, `-UseHermesApi`, redacted Hermes key handling and explicit `-Send` gating for phone notification.
- Added the Hermes-supervised auto-merge sweep smoke. The validated path ran supervisor status, auto-merge sweep dry-run and bootstrap notification dry-run without enabling auto-merge.
- Sent exactly one real non-urgent bootstrap ntfy notification through `skybridge-hermes-supervisor.ps1 -Mode NotifyTest -UseHermesApi -Send`; ntfy reported `sent: ok` and WeCom skipped as expected for `info`.
- Added Hermes cloud run, environment, phone notification and cloud supervisor runbook docs.
- Safety notes: no Hermes API key, bootstrap credential, `.env`, local secret file, production deploy, GitHub settings mutation, branch-protection change, server root config edit, public API exposure or real auto-merge enablement was introduced.

## 2026-05-23 Super Goal 039-041 Auto-Merge Sweep Pilot

- Started controlled sweep pilot on `ai/super-039-041-auto-merge-sweep-pilot` after confirming `main` contains PR #21 via merge commit `098b4b2`.
- Preflight passed with no blockers and no remote mutation: `check-github-automation-readiness.ps1 -Json`, `smoke-auto-merge-policy.ps1`, dry-run `skybridge-auto-merge-sweep.ps1`, `smoke-bootstrap-notification.ps1 -DryRun` and `validate-powershell.ps1`.
- The readiness checker still reported manual setup required for branch-protection proof and repository auto-merge inspection, matching the known local checker limitation. It reported zero open PRs before candidate creation.
- Initial dry-run sweep used blocked-notification suppression to preserve the requirement for exactly one real non-urgent bootstrap phone notification after the pilot result.
- Created two safe candidate PRs from `origin/main`: PR #22 (`ai/039-sweep-pilot-docs-a`) added `goals/ready/039-auto-merge-sweep-pilot-candidate-a.md`, and PR #23 (`ai/040-sweep-pilot-docs-b`) added `goals/ready/040-auto-merge-sweep-pilot-candidate-b.md`.
- Both PRs were ready for review, not draft, and GitHub reported the required checks as present and green: `Project check`, `Docker build (server)` and `Docker build (web)`. `AI branch validation` also passed.
- Dry-run sweep selected exactly PR #23 and PR #22 as eligible, both with `file_risk=low`, empty reasons and `dry_run_eligible` actions.
- Real sweep with `-EnableAutoMerge` selected the same two PRs and enabled GitHub auto-merge for both. PR #23 merged first at `f700b8d`; PR #22 then needed a safe branch update after becoming behind `main`, reran checks, and GitHub auto-merged it at `3936f3a`.
- Pulled `main` and verified both docs-only goal files are present. No candidate PR was manually merged.
- Sent exactly one real non-urgent bootstrap phone notification summarizing the two merged PRs. ntfy reported `sent: ok`; WeCom skipped as expected for non-urgent severity.
- Final validation passed: auto-merge policy smoke, bootstrap notification dry-run smoke, Codex phone notification dry-run smoke, CI Guardian dry-run smoke, PowerShell parse validation, `just check`, `gh pr checks` for PR #22 and PR #23, and explicit merged-state verification for both candidate PRs.

## 2026-05-23 Super Goal 034 Auto-Merge Rerun

- Confirmed `origin/main` Docker Images workflow no longer has `pull_request` path filtering, so docs-only PRs now create the required `Docker build (server)` and `Docker build (web)` contexts.
- Confirmed `scripts/powershell/skybridge-iterate.ps1` and `scripts/powershell/skybridge-ci-guardian.ps1` no longer use the obsolete Codex CLI `--ask-for-approval` flag.
- `check-github-automation-readiness.ps1` completed with no blockers and no remote settings mutation. It still reported manual setup required for branch-protection proof because the local checker cannot fully inspect or mutate those GitHub settings.
- Created child goal `goals/ready/034-real-auto-merge-rerun-docs-smoke.md` and processed it with `skybridge-iterate.ps1`, producing branch `ai/034-real-auto-merge-rerun-docs-smoke` and PR #19: https://github.com/JerrySkywalker/skybridge-agent-hub/pull/19.
- Marked PR #19 ready for review after confirming it changed only Markdown files: `docs/dev/REAL_AUTO_MERGE_RERUN.md` and `goals/ready/034-real-auto-merge-rerun-docs-smoke.md`.
- GitHub reported the required checks as present and green: `Project check`, `Docker build (server)` and `Docker build (web)`. `AI branch validation` also passed.
- Ran `skybridge-ci-guardian.ps1 -CurrentBranch -EnableAutoMerge` only after the PR was verified as docs-only, on an `ai/` branch, green, and free of production/secrets/deploy/root config changes. The Guardian returned `state=ci_green` for PR #19.
- Did not manually merge the child PR. GitHub reported PR #19 merged, and pulling `main` fast-forwarded to the merged docs-only change.
- Sent exactly one real non-urgent bootstrap notification after merge. ntfy reported `sent: ok`; WeCom skipped as expected for non-urgent severity.
- Final validation passed: bootstrap notification dry-run smoke, Codex phone notification dry-run smoke, iteration controller dry-run smoke, CI Guardian dry-run smoke, PowerShell parse validation and `just check`.
- Remaining blocker before always-on AI auto-merge: the local readiness checker still cannot independently prove branch-protection and repository auto-merge settings, so those controls remain operator-reviewed even though this PR proved the end-to-end safe docs-only loop.

## 2026-05-23 Super Goal 032 Preflight

- Started the first real AI auto-merge trial on `ai/super-032-first-real-auto-merge` with a docs-only safety boundary: no production deployment, secrets, `.env`, deploy scripts, GitHub settings mutation, branch protection mutation, WSS remote execution or privileged runners.
- Preflight passed locally with a clean worktree before edits. `check-github-automation-readiness.ps1 -Json` reported no blockers, active local and remote workflows, authenticated `gh`, visible open PRs and no remote settings or branch protection mutation.
- Repository auto-merge was verified separately with `gh api repos/JerrySkywalker/skybridge-agent-hub --jq '{allow_auto_merge}'`, which returned `allow_auto_merge=true`. The readiness script could not inspect `autoMergeAllowed` through `gh repo view` because that JSON field is unavailable in this local GitHub CLI, so branch protection remains proven by the generated PR's GitHub checks rather than by local mutation or settings inspection.
- Dry-run validation passed for bootstrap phone notification, Codex phone notification, iteration controller, CI Guardian and PowerShell parse validation. Bootstrap ntfy reported configured in dry-run mode; WeCom remained skipped.
- Child goal `goals/ready/033-first-real-auto-merge-docs-smoke.md` was processed by the controller on `ai/033-first-real-auto-merge-docs-smoke`, producing PR #17: https://github.com/JerrySkywalker/skybridge-agent-hub/pull/17.
- The first controller attempt exposed a local Codex CLI compatibility issue: this installed `codex exec` no longer accepts `--ask-for-approval`. The controller and CI Guardian worker command shapes were updated to use the supported non-interactive flags, then PowerShell parse, iteration-controller dry-run and CI Guardian dry-run smokes passed.
- PR #17 changed only `docs/dev/FIRST_AUTO_MERGE_TRIAL.md`. GitHub checks passed for `Project check` and `AI branch validation`, and CI Guardian enabled GitHub auto-merge with squash merge.
- GitHub did not merge PR #17. `main` branch protection also requires `Docker build (server)` and `Docker build (web)`, but the Docker Images PR workflow is path-filtered and did not run for the docs-only PR, leaving `mergeStateStatus=BLOCKED` with auto-merge enabled.
- Sent one real bootstrap phone notification with warning severity for the blocked auto-merge state. ntfy reported `sent`; WeCom remained skipped because warning notifications are ntfy-only.
- Remaining blocker before always-on AI auto-merge: required branch-protection checks must align with workflows that run for every auto-merge-eligible PR, or docs-only PRs need a safe non-publishing required-check path that satisfies `Docker build (server)` and `Docker build (web)` without production deployment or package publishing.
- Follow-up parent-branch fix: removed the Docker Images pull-request path filter so the required `Docker build (server)` and `Docker build (web)` contexts are created for every PR. Pull-request Docker builds still do not push images because `push` remains disabled for `pull_request` events.

## 2026-05-23 Codex Phone Notification Smoke

- Added a Codex full-chain phone notification smoke wrapper that launches `codex exec`, instructs the nested Codex run to call `notify-bootstrap.ps1`, stores Codex JSONL/last-message artifacts under `.agent/codex-phone-smoke/<timestamp>/` and reports whether the output showed ntfy dry-run configured or real sent status.
- Documented the full chain `Codex exec -> notify-bootstrap.ps1 -> local bootstrap env -> ntfy -> phone`, including safe dry-run and manual `-Send` commands, CI warning and secret handling requirements.
- Added `smoke:codex-phone-notification` as a dry-run-only package script; real phone send remains manual and outside default checks.

## 2026-05-23 Super Goal 017-023

- Completed durable iteration persistence: `/v1/iterations` now uses the server store abstraction with SQLite-backed iteration runs and state events, bounded filters, restart coverage and redacted payload persistence.
- Added read-only GitHub automation readiness reporting with `ready`, `warning`, `blocker` and `manual_setup_required` findings plus a safe smoke wrapper. Latest local report had no blockers, one warning and manual setup still required for branch protection/auto-merge review.
- Hardened bootstrap notifications for direct local/server supervision: new `SKYBRIDGE_BOOTSTRAP_*` environment variables, Windows/server setup docs, phone setup notes and explicit `-Send` requirement for real delivery.
- Hardened Hermes supervisor dry-runs across `Status`, `StartNext`, `RepairPR`, `NightlyReport` and `NotifyTest`, including offline SkyBridge behavior and no-PR repair previews.
- Added `goals/backlog/030-controller-dry-run-validation.md` and documented the first controlled controller dry-run. The dry-run validated branch calculation, Codex command shape, local metadata/prompt paths, SkyBridge offline fail-open, auto-merge disabled and notification no-send behavior.
- Improved the Operator Console autonomous iteration panel to show latest iteration state, open PR, CI Guardian state, Hermes status, bootstrap notification path, blocked reason and next recommended action.
- Final validation passed: PowerShell parse validation; bootstrap notification smoke; iteration controller smoke; CI Guardian smoke; Hermes supervisor flow smoke; GitHub automation readiness smoke; Hermes operational smoke; release dry-run smoke; Operator Console smoke; Docker compose dev/test/prod config rendering; `corepack pnpm check`; and `just check`.
- Safety notes: no production deployment, real secrets, branch protection mutation, auto-merge enabling, WSS remote execution, privileged runner setup, force-push or merge was performed. Release dry-run skipped the optional bash staging script only when Docker Compose was unavailable from bash; PowerShell Docker compose config checks passed.

## 2026-05-22 Super Goal 015-016

- Follow-up PR prep: smoke validation wrappers now accept a `-DryRun` switch consistently while preserving their safe dry-run-only behavior, and the development docs record the convention for future `smoke-*` wrappers.
- Completed phases 015-A through 015-I: controller architecture, iteration event model, reusable config, server iteration/supervisor APIs, one-shot controller, CI Guardian, AI-only CI/CD docs, dashboard panels and dry-run smoke validation.
- Added bootstrap direct notifications after correcting the assumption that SkyBridge Notification Center is available for SkyBridge's own development alerts. `notify-bootstrap.ps1` supports direct ntfy and urgent WeCom/WeChat webhook delivery through environment variables, with dry-run smoke coverage.
- Completed phases 016-A through 016-F: Hermes supervisor design, prompt templates, bridge script, supervisor status refinement, escalation notification model and local Hermes flow smoke.
- Validation run so far: event-schema tests/typecheck, server tests/typecheck, client tests/typecheck, react-widgets tests/typecheck, web build, PowerShell parse validation, bootstrap notification smoke, iteration controller smoke, CI Guardian smoke and Hermes supervisor flow smoke.
- Completed phase 016-G: reusable project integration docs, SkyBridge/generic project config examples, README, roadmap and changelog updates.
- Final local validation passed: PowerShell parse validation; bootstrap notification smoke; iteration controller smoke; CI Guardian smoke; Hermes supervisor flow smoke; release dry-run smoke; Operator Console smoke; multi-agent platform smoke; dogfooding loop smoke; Docker compose dev/test/prod config rendering; `corepack pnpm check`; and `just check`.
- Safety notes: no production deployment, branch protection mutation, auto-merge enablement, real secrets, `.env`, `/opt`, OpenResty, Authelia, 1Panel or Docker daemon configuration changes were performed. SkyBridge event delivery remains fail-open, and bootstrap phone notification does not require the SkyBridge server.
- Remaining for this goal: push branch, create draft PR and update PR body.

## 2026-05-22

- Nightly CI/CD Guardian round 15: inspected draft PR #10 and confirmed latest GitHub checks were green, reran `corepack pnpm check`, then added manifest-gated browser visual QA artifact upload to PR and AI-branch CI. The default public-runner path still skips when Playwright is unavailable, while controlled runners that produce `.agent/tmp/browser-visual-qa/manifest.json` must pass a fixture-only, non-production, loopback-origin PowerShell guard before screenshots are uploaded for seven days.
- Nightly CI/CD Guardian round 14: inspected draft PR #10 and confirmed latest GitHub checks were green, reran `corepack pnpm check`, then wired the existing browser visual QA optional smoke into PR and AI-branch CI as a skip-safe logged step. The public-runner path still does not install Playwright or upload screenshots; it records a sanitized `.agent/ci/browser-visual-qa.log` and leaves screenshot artifact upload behind a later reviewed change. Validation passed with the browser visual QA skip-safe smoke and PowerShell parse validation.
- Nightly CI/CD Guardian round 13: inspected draft PR #10 and confirmed latest GitHub checks were green, reran `corepack pnpm check`, then hardened durable audit migration by importing existing safe JSON audit records into SQLite alongside events and notifications. Added a server migration fixture proving filtered `/v1/audit` returns the migrated safe record without raw prompt/stdout/token content, and documented the migration behavior. Validation passed with focused server tests, `corepack pnpm check` and `just check`.
- Nightly CI/CD Guardian round 12: inspected draft PR #10 and confirmed GitHub checks were green, reran `corepack pnpm check`, then expanded the shared PowerShell redaction parity smoke with a `ConvertFrom-Json` array fixture. The new fixture proves nested Authorization fields are replaced and raw `tool_result`/`stderr` content is bounded when PowerShell runner or hook telemetry receives JSON arrays. Validation passed with the focused shared redaction smoke and PowerShell parse validation.
- Nightly CI/CD Guardian round 11: inspected draft PR #10 and confirmed GitHub checks were green, reran `corepack pnpm check`, then added a bounded local audit JSONL export endpoint at `/v1/audit/export`. The export reuses durable safe audit records, accepts the same filters and bounded limit as `/v1/audit`, returns headers that state raw payloads are excluded, and is documented as local pull-only fixture-safe output. Validation passed with focused server tests, `corepack pnpm check` and `just check`.
- Nightly CI/CD Guardian round 10: inspected draft PR #10 and current local state, reran `corepack pnpm check`, then tightened durable audit trail coverage with SQLite restart fixtures for node heartbeat, notification routing and failed-run audit records. The server test now proves those audit records keep only safe metadata, retain source/action/actor/safety decision fields, and do not return private keys, notification bodies, tokens, stderr or prompts. Focused validation passed with `corepack pnpm --filter @skybridge-agent-hub/server test`.
- Nightly CI/CD Guardian round 9: inspected draft PR #10 and current local state, then hardened shared PowerShell redaction consumption for generic dictionaries and `ConvertFrom-Json` object values. The shared redaction parity smoke now proves `PSCustomObject` payloads redact token fields, bearer values and raw output fields before runner or hook telemetry can emit them. Validation passed with shared redaction parity smoke, PowerShell parse validation, runner dry-run smoke, `corepack pnpm check` and `just check`.
- Nightly CI/CD Guardian round 8: inspected draft PR #10 and confirmed latest GitHub checks were green, then added a fixture-only browser visual QA `manifest.json` for future screenshot artifact review. The browser visual QA runner now refuses non-loopback web bases, records the expected route/viewport/text matrix beside screenshots when Playwright is installed, and keeps the Playwright-unavailable skip-safe path. Validation passed with `node --check scripts/browser-visual-qa.mjs`, `corepack pnpm smoke:browser-visual-qa`, PowerShell parse validation, `corepack pnpm check` and `just check`.
- Nightly CI/CD Guardian round 7: inspected draft PR #10 and confirmed latest GitHub checks were green, reran `corepack pnpm check`, and tightened browser visual QA follow-up docs with the exact desktop/mobile/embed route and viewport matrix plus required visible panels. The browser visual QA backlog now marks viewport documentation complete and tracks the artifact manifest as the next safe CI upload prerequisite. Validation passed with `corepack pnpm check`, `corepack pnpm smoke:browser-visual-qa` on the Playwright-unavailable skip-safe path, and PowerShell parse validation.
- Nightly CI/CD Guardian round 6: expanded the shared TypeScript/PowerShell redaction parity smoke to cover secret keys, bearer values, API keys, private-key markers and raw prompt/patch/output fields; documented redaction policy versioning; and fixed the server SQLite persistence restart test so local `NTFY_TOPIC_URL` settings cannot make it perform a real provider send. Validation passed with shared redaction parity smoke, PowerShell parse validation, focused server tests and `corepack pnpm check`.
- Nightly CI/CD Guardian round 5: upgraded the browser visual QA scaffold into an optional executable Playwright path that starts fixture-backed temporary server/web processes, checks primary dashboard/embed rendering, and captures local screenshots when Playwright is installed while preserving the skip-safe default path for CI without browser dependencies.
- Nightly CI/CD Guardian round 4: extended shared PowerShell redaction consumption into runner telemetry, added policy metadata to runner payloads, added a loopback dry-run runner redaction smoke, and wired that smoke into nightly local validation. Validation passed with `corepack pnpm check`, runner dry-run redaction smoke, shared redaction parity smoke and PowerShell parse validation.
- Nightly CI/CD Guardian round 3: refactored Codex PowerShell hook redaction into `scripts/powershell/shared-redaction.ps1`, added a TypeScript/PowerShell shared-rule parity smoke, wired that smoke into nightly local validation, and updated release/security/backlog docs. Validation passed with `corepack pnpm check`, focused event-schema and Codex hook checks, PowerShell parse validation, hook fixture smoke, redaction parity smoke, and `nightly-local-validation.ps1 -SkipDockerBuilds`.
- Nightly CI/CD Guardian round 2: added a durable audit trail skeleton with SQLite-backed append-only audit rows for auditable events, `/v1/audit` filters, client query support, dogfooding smoke assertions for safe audit metadata, and refreshed release/audit docs. Validation passed with `corepack pnpm check`, focused server/client checks, PowerShell parse validation, multi-agent and dogfooding smokes, and `nightly-local-validation.ps1 -SkipDockerBuilds`.
- Super Goal 005-014 release train: completed the first platform release train pass across multi-agent adapters, sidecar/node foundation, notification routing/jobs, shared redaction/security docs, demo/dogfooding assets, approval API, metrics endpoint, self-hosting docs, roadmap and v0.9 release candidate notes.
- Commits created so far: `feat(adapters): add multi-agent adapter foundation`, `feat(sidecar): add safe node registry foundation`, `feat(notifications): add provider routing job foundation`, `security: add shared redaction rules`.
- Checks run so far: focused event-schema, adapter, sidecar, notification provider, server and client tests/typechecks passed for touched areas.
- Known gaps intentionally deferred to backlog goals: real WSS implementation, browser visual QA, mobile readiness, production deployment hardening, public docs site and external contributor onboarding.
- Continuation hardening: added physical OpenCode/Hermes fixture files, provider skip tests across the matrix, API examples, self-hosting dry-run smoke, release train audit notes, and a PowerShell shared-redaction follow-up goal.
- Second continuation hardening: added dashboard panels for metrics and notification provider status plus a multi-agent platform smoke covering sources, demo events, nodes, providers, approvals and metrics together.
- PR #9 audit hardening: repaired Linux PowerShell `Start-Process -WindowStyle` usage in smoke scripts, added Docker Buildx setup for image cache support, added `docs/release/PR9_GAP_AUDIT.md`, expanded PR-created backlog goals with background/tasks/completion/safety sections, and added a safe derived `/v1/audit` endpoint plus client/test coverage.
- PR #9 local validation passed: `corepack pnpm check`, Docker dev/test/prod compose config, PowerShell parse validation, Operator Console smoke, release dry-run smoke, self-hosting dry-run smoke, Codex hook integration smoke with temporary server/spool, multi-agent platform smoke, dogfooding smoke with temporary server, release candidate smoke, self-observation smoke against a temporary server, and local server/web Docker image builds.
- Mega Goal 004 Stages 1-15: completed the release, CI/CD, container, staging dry-run and operations foundation without deploying or touching production secrets.
- Commits created: `docs(ops): design CI/CD and release plan`, `ci: harden public PR checks`, `ci: harden AI branch validation`, `build(docker): harden production images`, `ci: publish images to GHCR`, `deploy: harden production compose template`, `deploy: add staging dry-run workflow`, `deploy: harden backup and rollback scripts`, `deploy: add notification hooks`, `ci: add release tag workflow`, `deploy: add staging dry-run workflow`, `test(ops): add release dry-run smoke`, `ci: publish smoke artifacts safely`, `security: document CI/CD threat model`.
- Final checks passed: `corepack pnpm check`, `just check`, Docker dev/test/prod compose config, PowerShell parse validation, release dry-run smoke, Operator Console smoke with temporary SQLite, Codex hook integration smoke with temporary server/spool, server Docker image build and web Docker image build.
- Staging dry-run result: missing `.env` was reported without printing secrets, compose rendered successfully and no containers were started or changed.
- Known gaps: release workflows are syntax-reviewed and locally smoke-validated but not executed on GitHub in this session; real staging or production deployment remains intentionally manual and outside this goal.

## 2026-05-21

- Mega Goal 003 Stages 1-12: productized the Operator Console across server APIs, demo data, typed client helpers, React widgets, web app layout, SSE-backed timeline behavior, compact Web Component embed, smoke validation, CI wiring and docs.
- Commits created: `docs(ui): design operator console`, `feat(server): add console query APIs`, `test(data): add demo event seeding`, `feat(client): add typed dashboard API helpers`, `feat(widgets): add operator console widgets`, `feat(web): build operator console overview`, `feat(embed): improve compact status component`, `test(smoke): add operator console smoke script`, `ci: harden dashboard validation`.
- Checks run so far: server test/typecheck, client test/typecheck, react-widgets test/typecheck, web build, web-components test/typecheck/build, Operator Console smoke with temporary SQLite, Docker dev/test compose config.
- Operator Console smoke result: temporary local server returned 12 demo events, 3 runs, 1 failed run, 3 notifications, 5 attention items and existing web build artifacts.
- Known gaps: no browser screenshot artifact was captured in this session; validation used build, static render tests and HTTP smoke scripts. Remote-control UI remains intentionally out of scope.
- Mega Goal 002 Stage 1: audited the Codex local integration path across hook and exec adapters, PowerShell hook scripts, server ingestion/query behavior, client query helpers, the self-observation panel and Codex docs. Added `docs/codex/CODEX_LOCAL_INTEGRATION.md` to define the production local path, supported Codex event families, hook mappings, spool/replay expectations and redaction defaults.
- Stage 1 check: documentation-only design change; no code check required before this commit.
- Mega Goal 002 Stages 2-3: added representative Codex hook stdin JSON fixtures for session startup/resume, prompt submit, Bash pre/post success/failure, apply_patch, permission request, stop and malformed/minimal payloads. Hardened Codex hook normalization for `tool.failed`, `file.edited`, `diff.updated`, bounded nested payloads, command/output summaries and secret-like redaction.
- Stages 2-3 checks: `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-hook test` and `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-hook typecheck` passed.
- Mega Goal 002 Stages 4-5: productionized Codex PowerShell hook operations with a bounded fail-open dashboard hook, local JSONL queue/audit spool, replay script, dry-run installer, restore script and fixture-driven hook tester. Installer dry-run preserves Codex hook array shape and writes only with explicit `-Apply`.
- Stages 4-5 checks: PowerShell parse checks passed for all scripts; `test-codex-hook-event.ps1 -RequireSpool` passed with 10 fixtures and 12 normalized queued events; `replay-codex-hook-spool.ps1 -WhatIfOnly` reported 12 queued events without mutation.
- Mega Goal 002 Stage 6: extended event queries with `from`/`to` time-window filters and expanded run summaries with active tool counts, cwd, goal and latest safe message summary derived only from normalized/redacted events.
- Stage 6 checks: `corepack pnpm --filter @skybridge-agent-hub/event-schema typecheck`, `corepack pnpm --filter @skybridge-agent-hub/client typecheck`, `corepack pnpm --filter @skybridge-agent-hub/server test` and `corepack pnpm --filter @skybridge-agent-hub/server typecheck` passed.
- Mega Goal 002 Stage 7: added `smoke-codex-hook-integration.ps1` for online hook delivery plus offline spool/replay. Fixed the PowerShell hook to drop null optional fields before delivery so server validation accepts generated events.
- Stage 7 checks: script parse passed; smoke passed on `http://127.0.0.1:8798` with 10 fixtures, 12 persisted Codex events, 4 Codex run summaries, 12 offline queued events and 12 replayed events.
- Mega Goal 002 Stage 8: added a Codex Integration dashboard panel that surfaces recent Codex runs, latest hook event, active/failed tool counts and spool count when available from events.
- Stage 8 checks: `corepack pnpm --filter @skybridge-agent-hub/react-widgets test`, `corepack pnpm --filter @skybridge-agent-hub/react-widgets typecheck` and `corepack pnpm --filter @skybridge-agent-hub/web build` passed.
- Mega Goal 002 Stage 9: updated README, DEVELOPMENT, SECURITY, `docs/codex/HOOKS.md` and `docs/codex/CODEX_LOCAL_INTEGRATION.md` with Codex hook install, smoke, replay, redaction, spool cleanup/privacy and troubleshooting guidance.
- Mega Goal 001 Stage 1: mapped the current self-observation loop in `docs/codex/SELF_OBSERVATION_LOOP.md`, including Codex hooks, Codex exec JSON, runner telemetry, manual smoke events, server ingestion/query/SSE, notification placeholders and dashboard consumption.
- Stage 1 check: documentation-only change; no code check required before this commit.
- Mega Goal 001 Stage 2: added scoped event filtering and a run detail API for self-observation drill-in; run summaries now include safe agent/node IDs, tool and notification counts, lifecycle, branch and goal metadata derived from redacted payloads.
- Stage 2 checks: `corepack pnpm --filter @skybridge-agent-hub/event-schema test`, `corepack pnpm --filter @skybridge-agent-hub/event-schema typecheck`, `corepack pnpm --filter @skybridge-agent-hub/client typecheck`, `corepack pnpm --filter @skybridge-agent-hub/server test` and `corepack pnpm --filter @skybridge-agent-hub/server typecheck` passed.
- Mega Goal 001 Stage 3: added `scripts/powershell/smoke-self-observation.ps1` to send representative local loop events, query the run detail API, verify scoped event lookup and report notification placeholder state without requiring secrets.
- Stage 3 checks: PowerShell parse check passed; local server smoke run passed on `http://127.0.0.1:8797` with a temporary SQLite file.
- Mega Goal 001 Stage 4: added a self-observation dashboard panel and summary helper that distinguish Codex, runner, smoke and notification events while surfacing active/failed run state.
- Stage 4 checks: `corepack pnpm --filter @skybridge-agent-hub/react-widgets test`, `corepack pnpm --filter @skybridge-agent-hub/react-widgets typecheck` and `corepack pnpm --filter @skybridge-agent-hub/web build` passed. The in-app Browser backend was unavailable (`iab` could not be acquired), so fallback local HTTP checks verified the dashboard returned HTTP 200, the API was healthy and the smoke run appeared in `/v1/runs`.
- Mega Goal 001 Stage 5: added focused adapter tests for Codex hook fallback correlation and Codex exec JSON redaction; tightened Codex exec normalization so free-form summaries are represented by presence/length metadata instead of being retained.
- Stage 5 checks: `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-exec-json test`, `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-exec-json typecheck`, `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-hook test` and `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-hook typecheck` passed.
- Mega Goal 001 Stage 6: updated README, architecture, development, self-observation loop docs and the active mega goal with the validated local smoke flow, new query APIs and deferred follow-up for deeper dashboard run drill-in.
- Stage 6 check: `just check` passed.
- Read the repository instructions, architecture docs and staged goals.
- Implemented a typed `skybridge.agent_event.v1` schema with validation and tests.
- Built the server MVP with health, event ingestion, event listing, run summaries, SSE stream, notification endpoints and local JSON persistence.
- Added ntfy provider behavior with safe placeholder recording when credentials are missing.
- Added Codex hook normalization and guard-hook redaction/safety updates.
- Added local sidecar event forwarding.
- Implemented React widgets, dashboard shell and a framework-neutral status Web Component.
- Updated development, hook and architecture docs for local operation.
- Validation: `corepack pnpm check` passed; Docker dev/test compose config passed; local server smoke test passed for health, event ingest, event list and run summaries.
- Environment note: `pnpm` and `just` are not directly on PATH here. Commands work through `corepack pnpm`; `just check` could not be run because `just` is not installed.
- Replaced MVP JSON-first persistence with SQLite-backed server persistence at `.data/skybridge.sqlite`; existing `.data/skybridge-store.json` or `SKYBRIDGE_DATA_FILE` data is imported once and left untouched.
- Added focused hardening tests for SQLite persistence/restart behavior, JSON migration, notification trigger placeholder recording, SSE replay, Codex hook parsing/redaction, and React widget static rendering.

## v0.2.0-sqlite-mvp verification

- `just check`: passed.
- Server health: passed.
- Persistence: sqlite.
- Local DB file observed at `apps/server/.data/skybridge.sqlite` when running server via pnpm filter.
- Git tag: `v0.2.0-sqlite-mvp`.

## Engineering discipline update

- Added repository line-ending policy with LF for source/config/docs/CI files and CRLF for Windows-first PowerShell scripts.
- Standardized server default SQLite and legacy JSON migration paths on repository-root `.data/`, while keeping `SKYBRIDGE_DB_FILE` and `SKYBRIDGE_DATA_FILE` overrides.
- Hardened `/v1/events` so invalid event payloads return HTTP 400 validation details instead of surfacing as server errors.
- Codified small-step autonomous Git workflow: split goals into logical commits, run the smallest relevant check before each commit, run `just check` before stopping, and push after completed passing goals.

## Open-source homepage and autonomous runner foundation

- Rewrote the top-level README as a public open-source project homepage with quick start, architecture, event model, API examples, development commands, roadmap, security stance and contributing guidance.
- Hardened `scripts/powershell/yolo-runner.ps1` into a single-worker queue runner MVP for `goals/ready/*.md`.
- Added runner claim metadata, per-run logs under `.agent/runs/<timestamp>-<goal-id>/`, Codex JSONL output, standard checks, limited repair rounds, branch push and optional PR creation.
- Added `config/runner.example.json` and `docs/codex/AUTONOMOUS_RUNNER.md`.
- Kept autonomous execution intentionally local, non-deploying and single-threaded with `MaxParallel = 1`.

## Codex TUI Master Goal workflow

- Added `goals/00_AUTONOMOUS_MASTER_GOAL.md` as the operating source of truth for long-horizon Codex TUI development.
- Added `docs/codex/TUI_MASTER_GOAL.md` and updated goal-mode docs to make Codex TUI the recommended primary development workflow.
- Added `goals/mega/` with five 6-10 hour mega goals:
  - `001-self-observable-skybridge-loop`
  - `002-codex-hook-productionization`
  - `003-dashboard-productization`
  - `004-ci-cd-staging-foundation`
  - `005-opencode-hermes-adapters`
- Repositioned `scripts/powershell/yolo-runner.ps1` as the fallback batch/background processor for bounded `goals/ready/*.md` child goals.

## Bootstrap notification verified

- Windows local bootstrap notification path verified.
- `notify-bootstrap.ps1 -Send` can deliver info and urgent messages to ntfy topics.
- Phone-side ntfy subscription and permissions confirmed.
- Bootstrap notification is currently the out-of-band fallback path for SkyBridge/Hermes/Codex development supervision.
## 2026-05-30

- Super 181 local implementation: added approval-gated proposal lifecycle states (`proposed`, `reviewed`, `approved`, `rejected`, `deferred`, `superseded`, `blocked_dependency`, `converted`, `executed`), proposal review metadata, approval policy checks and convert-only-approved enforcement.
- Polished `skybridge-status.ps1` human output with grouped SkyBridge header, grouped task summary and proposal queue visibility. The task summary now distinguishes `total`, `matching`, `shown` and `truncated`; `-ActiveOnly` with no matching tasks reports `matching=0`, `shown=0` and `Tasks: none`.
- Added `skybridge-proposal.ps1` review commands for list/show/review/approve/reject/defer/supersede/convert, with all mutations gated by `-Apply`. Guide and Hermes CLI operator aliases now expose proposal list/show/approve/reject/defer/convert/status-proposals flows.
- Local validation passed for the new status/proposal smokes, PowerShell parse validation and server typecheck.
- Super 181 cloud pilot blocker: the current cloud SkyBridge API is still on the old proposal enum and rejects `status=approved` with `invalid_proposal_status`. Because this goal explicitly forbids production deployment, no approval-gated real cloud proposal pilot was executed. Final cloud preconditions were otherwise safe: project control paused, `stop_requested=false`, no queued/claimed/running tasks, `laptop-zenbookduo` heartbeat online, Hermes direct HTTPS healthy and historical `task_proposal-59a0236fb69800cd` still blocked.

## 2026-05-31

- Super 183 deployed the latest merged SkyBridge Server image from `main` to the existing server container only. Health passed on localhost and `https://skybridge.example.com/v1/health`; no OpenResty, DNS, Authelia, ntfy, Halo, firewall, server root configuration, secret or GitHub settings changes were made.
- Hermes persisted a docs-only Super 183 proposal batch. Approved proposals `proposal-3ebb79b2b20a2d64` and `proposal-a3d7d8d55b54455e` converted to `task_proposal-3ebb79b2b20a2d64` and `task_proposal-a3d7d8d55b54455e`; deferred proposal `proposal-c6349c43ccbdcf98` and an unapproved proposal were refused conversion.
- The lease-backed worker loop ran on `laptop-zenbookduo` only. Task `task_proposal-a3d7d8d55b54455e` used lease `lease_xWVPzMr5ztjvHLKheYCJa` and created child PR #86; task `task_proposal-3ebb79b2b20a2d64` used lease `lease_B3Jh_y7YhYcqGPoEWtPhq` and created child PR #87.
- Both child PRs changed only their expected docs files, all checks passed, both PRs merged, both task leases were released, both local repo locks were cleaned up, and cloud evidence was repaired to recovered status after the CI guardian initially stopped on draft/pending checks.
- Final cloud state for the pilot: project control paused, `stop_requested=false`, active queued/claimed/running tasks `0`, recovered task count includes both Super 183 tasks, and historical `task_proposal-59a0236fb69800cd` remains blocked.

## 2026-05-31 Super 184

- Added colorized human output to `skybridge-status.ps1` with `-Color`, `-NoColor` and `-ColorMode Auto|Always|Never`. JSON and `-OutputFile` remain ANSI-free, and `NO_COLOR` is honored.
- Added `-Hygiene` status mode plus filters for stale, blocked, failed, review and reconciliation-focused views. JSON now exposes `hygiene_summary`, `hygiene_findings` and `recommended_actions`.
- Added derived lease display statuses (`active`, `released`, `expired`, `stale`, `abandoned`, `inconsistent`) and derived task hygiene statuses (`stale_claim`, `stale_running`, `lease_missing`, `lease_expired`, `pr_merged_needs_evidence`, `recovered_ok`, `blocked_historical`, `failed_unrecovered`).
- Added proposal/task reconciliation in status output. Converted proposals whose tasks completed or recovered now show derived execution state `executed`, while approved proposals without tasks show `approved_unconverted`.
- Added `skybridge-hygiene.ps1` for dry-run queue audit/report flows and explicit lease recovery commands. Mutations require `-Apply` and `-Reason`; the historical blocked `task_proposal-59a0236fb69800cd` is explicitly protected from automatic recovery.
- Read-only cloud audit found project control paused, `stop_requested=false`, active tasks `0`, active leases `0`, stale leases `0`, released leases `2`, blocked historical tasks `3`, failed unrecovered tasks `1`, recovered tasks `9`, completed tasks `3`, approved unconverted proposals `2`, converted unexecuted proposals `0` and derived executed proposals `6`.
- No safe reconciliation mutation was performed in Super 184 because there was no stale active lease or active task residue. `remote-docs-exec-pilot-001` remains an evidence-review item; historical blocked tasks remain blocked.

## 2026-05-31 Super 188

- Added the autonomous campaign runner command surface to `skybridge-campaign.ps1`: `run-next`, `run-until-hold`, `run-until-complete`, runner-aware `resume`, `runner-status`, `runner-report`, `runner-stop`, `runner-hold` and `runner-unlock`.
- Added local campaign runner state and campaign locks under `.agent/campaign-runners`, including bounded step/task/runtime limits, audit logs, stale lock handling and explicit apply-gated unlocks.
- Added delegated runner approval scope support so a bounded manually authored campaign can satisfy step-level human approval without overriding hard veto rules.
- Added the baseline PR finalizer at `scripts/powershell/skybridge-pr-finalize.ps1`, including fixture smokes for pending checks, safe merge, unsafe file blocking and evidence repair.
- Seeded `goals/dev-queue-189-200` with 12 manually authored Super Goal files and the `dev-queue-189-200` campaign manifest. The queue starts at Goal 189 and keeps Goal 190-200 dependency-gated.
- Added `scripts/powershell/start-dev-queue-189-200.ps1` as the post-merge launch wrapper. It validates the pack, checks cloud hygiene, requires `-Apply` and writes runner reports under `.agent/tmp`.
- Goal 189-200 were not executed from the unmerged feature branch. The queue was validated and imported only as campaign metadata.

## 2026-06-01 Goal 188D

- Hardened `skybridge-dev-queue-control.ps1` JSON parsing so mixed child output, including git prefix lines before the JSON payload, no longer breaks `start-one` or `start-all` JSON mode.
- Quieted `start-dev-queue-189-200.ps1` git fetch output and kept JSON output ANSI-free.
- Split `skybridge-campaign-watch.ps1` rendering from remote polling: `-RenderIntervalMilliseconds` controls spinner smoothness, while `-PollIntervalSeconds` controls bounded API polling. Recommended launch watch settings are 250 ms render and 5 second polling.
- Added focused smokes for mixed JSON extraction, JSON cleanliness, watch render/poll behavior, fast demo spinner and cached-frame poll failure handling.
- Goal 189-200 full queue execution remains held pending reviewed `start-one` verification.
## 2026-06-08 Goal 197 Multi-worker Readiness

- Added preview-only multi-worker capability matrix, readiness scoring, route preview, and routing policy fixtures.
- Added OS/tool/project/repo access checks and explicit `max_parallel_per_repo=1` guard.
- Integrated routing readiness into `queue_control_readiness`, Desktop/Web panels, and attention events.
- Execution remains disabled: no task claim, no task execution, no worker loop, and no queue start.

## 2026-06-23 Mega Goal 324 Bootstrap Alpha Product Flow Freeze

- Added Bootstrap Alpha product-flow, client/worker/server architecture, natural-language-to-task, task-template model, scope, and roadmap documents.
- Froze the next Mega Goal sequence from MG325 through MG331 around Desktop installer, chat planner, template registry, draft review, worker template runner, MATLAB golden trial, and end-to-end release.
- Added the read-only `skybridge-bootstrap-alpha-acceptance.ps1` smoke and `smoke:bootstrap-alpha-acceptance` package script.
- Kept the current safety boundary unchanged: no task claims, no Codex execution, no MATLAB execution, no worker loop start, no notification send, no unbounded run, no daemon path, and `token_printed=false`.

## 2026-06-23 Mega Goal 329 Worker Template Runner v1

- Added the first Worker Template Runner v1 contracts for preview, result, and sanitized evidence.
- Added `scripts/powershell/skybridge-worker-template-runner.ps1` with read-only preview and exact-confirmed `apply-one` limited to one `safe-local-smoke.v1` fixture task.
- Added fixture/local smokes for preview, apply-one, unsafe rejection, and Desktop runner preview contract.
- Added a Desktop Bootstrap Alpha Worker Runner Preview panel and the product doc `docs/product/WORKER_TEMPLATE_RUNNER_V1.md`.
- Kept Codex execution, MATLAB execution, arbitrary shell, worker loop, unbounded run, project-control unpause, PR creation, old task requeue, live cloud task claim, and `token_printed=false`.

## 2026-06-24 Mega Goal 337 Codex Analysis Report Golden Trial

- Added the first fixed Codex analysis report runner contract,
  `skybridge.codex_analysis_report_runner.v1`, and evidence contract,
  `skybridge.codex_analysis_report_evidence.v1`.
- Added `scripts/powershell/skybridge-codex-analysis-report-runner.ps1` and
  `scripts/powershell/skybridge-live-codex-analysis-report-trial.ps1` for one
  exact task, `live-codex-analysis-report-task-337-001`.
- Added the fixed prompt template at
  `docs/product/prompts/CODEX_ANALYSIS_REPORT_PROMPT_V1.md` and the product doc
  `docs/product/CODEX_ANALYSIS_REPORT_GOLDEN_TRIAL.md`.
- Added fixture, preview, rejection, evidence-validation, and Desktop contract
  smokes for the Codex report flow.
- Live task `live-codex-analysis-report-task-337-001` was created and claimed
  exactly once, then failed closed with sanitized evidence after the runner
  returned no usable report evidence. No second live retry was attempted.
- Hardened the fixed runner to prefer Windows `codex.cmd`, wrap PowerShell
  shims through `pwsh`, and classify process-start failures without exposing
  raw stdout, stderr, or Codex logs.
- Kept arbitrary prompt text, MATLAB execution, arbitrary shell, worker loops,
  source edits, PR creation, project-control unpause, raw Codex log exposure,
  old task requeue, and token printing disabled.

## 2026-06-26 Mega Goal 342 Bootstrap Alpha RC1 Handoff

- Added the Bootstrap Alpha RC1 handoff document for tag
  `v0.1.0-bootstrap-alpha-rc1`, target
  `4473257548bd0fc26e05002d968f8525b37bac8b`, and image
  `ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-4473257548bd0fc26e05002d968f8525b37bac8b`.
- Added the read-only RC1 handoff checker and smokes for local handoff, report
  safety, stop-hook hygiene, and tag verification.
- Documented the post-MG341 stop-hook timeout as non-blocking when git, tag,
  deploy, audit, and checks are clean; local Codex hook configuration is not
  read or mutated by the repo checker.
- Preserved the RC1 safety boundary: no tag movement, GitHub Release creation,
  task creation or claim, Codex or MATLAB execution, worker loop,
  project-control unpause, or token printing.
