# Bootstrap Alpha Roadmap

This roadmap defines the next Mega Goals after MG324. Each item should stay
focused on the Bootstrap Alpha product flow and avoid new policy-layer drift.

## MG325 Desktop Installer + Worker Service Manager

- Objective: make Desktop install, repair, and report local worker service
  status through reviewed UI.
- Likely touched: `apps/desktop`, `scripts/powershell/skybridge-worker-service.ps1`,
  Desktop worker status docs and smokes.
- Acceptance criteria: Desktop shows install/repair/status states; repair is
  previewed or explicitly confirmed; worker service status is read safely; no
  task claim or execution starts.
- Implementation note: MG325 adds
  `skybridge.local_worker_service_status.v1`, read-only status/doctor scripts,
  preview-only install/repair scripts, Desktop Worker Setup panel, and
  [Windows Worker Install Bootstrap Alpha](WINDOWS_WORKER_INSTALL_BOOTSTRAP_ALPHA.md).
- Forbidden scope: arbitrary shell controls, daemon expansion, production infra,
  worker loop start.
- Live deployment expected: no.

## MG326 Chat-to-Task Draft Planner

- Objective: add chat-to-draft flow that turns operator input into structured
  task or campaign drafts.
- Likely touched: `apps/desktop`, planner adapter packages, manual task/Hermes
  preview scripts, draft docs and smokes.
- Acceptance criteria: chat input produces a previewable draft; missing fields
  trigger clarifying questions; drafts include template id, paths, validation,
  and evidence schema; no execution occurs.
- Implementation note: MG326 adds a deterministic local draft planner,
  `skybridge.task_draft_preview.v1`, Desktop Chat-to-Task panel, MATLAB and
  docs/report examples, blocked-request classification, and focused smokes.
- Forbidden scope: direct execution, raw prompt persistence, arbitrary shell,
  automatic task creation without operator confirmation.
- Live deployment expected: no server runtime change; if the existing cloud
  auto-deploy runs after merge, verify parity through the existing path only.

## MG327 Task Template Registry

- Objective: add a template registry contract for Bootstrap Alpha templates.
- Likely touched: `apps/desktop`, `packages/event-schema`, `packages/client`,
  template docs, schema tests, registry smoke scripts.
- Acceptance criteria: planned templates are represented with ids, input schema,
  required capabilities, path bounds, risk class, validation, runner id, and
  evidence schema; registry is queryable or fixture-backed for drafts.
- Implementation note: MG327 adds `skybridge.task_template_registry.v1`, five
  Bootstrap Alpha templates, a read-only PowerShell registry script,
  registry-backed Chat-to-Task draft metadata, a Desktop Task Templates panel,
  and focused smokes. No server endpoint is required for this goal.
- Forbidden scope: full runner execution, MATLAB execution, unbounded task
  generation.
- Live deployment expected: no server runtime change; if the existing cloud
  auto-deploy runs after merge, verify parity through the existing path only.

## MG328 Draft Review + Submit To Server

- Objective: let the operator review planner drafts and submit confirmed tasks
  or campaigns to the server.
- Likely touched: `apps/desktop`, `apps/server`, client package, draft review
  scripts and smokes.
- Acceptance criteria: preview clearly shows allowed/blocked paths and no-shell
  boundary; confirmation creates server-side records; rejection creates no task;
  evidence remains safe.
- Implementation note: MG328 adds reviewed submit contracts,
  `POST /v1/drafts/submit-preview`, `POST /v1/drafts/submit`, the
  `skybridge-draft-submit.ps1` helper, Desktop Draft Review + Submit card, and
  focused submit smokes. Submit preview creates nothing. Confirmed submit
  creates queued task or non-running draft campaign records only.
- Forbidden scope: worker claim, runner execution, automatic merge, hidden
  Desktop execution controls.
- Live deployment expected: maybe, if server task/campaign APIs change.

## MG329 Worker Template Runner v1

- Objective: implement the first worker template runner for low-risk software
  docs/report or safe local smoke tasks.
- Likely touched: worker PowerShell scripts, runner docs, task claim smokes,
  evidence reporting, server task state tests.
- Acceptance criteria: worker pulls and claims one compatible template task;
  runner enforces template bounds; evidence returns safely; operator review
  remains required.
- Implementation note: MG329 adds
  `skybridge.worker_template_runner_preview.v1`,
  `skybridge.worker_template_runner_result.v1`,
  `skybridge.template_runner_evidence.v1`, the
  `skybridge-worker-template-runner.ps1` helper, fixture/local smokes, and a
  Desktop Worker Runner Preview panel. Apply is exact-confirmed and limited to
  one `safe-local-smoke.v1` fixture task.
- Forbidden scope: MATLAB execution, arbitrary shell, unbounded run, daemon
  auto-expansion, project-control unpause, Codex execution, PR creation, live
  cloud task claim during post-deploy smoke.
- Live deployment expected: maybe, for server compatibility only.

## MG330 Local Worker Install Apply + Heartbeat Pairing

- Objective: move local worker setup from preview-only to exact-confirmed local
  install/repair apply and heartbeat-only cloud pairing.
- Likely touched: worker service PowerShell scripts, Desktop Worker Setup
  panel, install docs, heartbeat fixture smokes, Bootstrap Alpha acceptance.
- Acceptance criteria: preview creates no local mutation; install/repair apply
  reject missing confirmation; confirmed fixture apply writes only local temp
  metadata; heartbeat fixture registers/heartbeats only; Desktop shows install
  and heartbeat state; no task claim or execution starts.
- Implementation note: MG330 adds `skybridge-worker-service-install.ps1`,
  `skybridge-worker-service-repair.ps1`, and
  `skybridge-worker-heartbeat-pairing-drill.ps1`. The default strategy is a
  non-admin user-level heartbeat-only wrapper with safe state under
  `$HOME\.skybridge\state`.
- Forbidden scope: live task claim, worker template runner live apply, Codex
  execution, MATLAB execution, arbitrary shell, worker loop start, unbounded
  run, PR creation, project-control unpause, deploy infrastructure mutation.
- Live deployment expected: no server runtime change; if the existing cloud
  auto-deploy runs after merge, verify parity through the existing path only.

## MG331 Local Worker Identity Activation + Live Heartbeat

- Objective: configure a real local Bootstrap Alpha worker identity and prove
  live heartbeat-only registration against the deployed server.
- Likely touched: worker identity PowerShell scripts, Desktop Worker Setup
  panel, install docs, heartbeat fixture smokes, Bootstrap Alpha acceptance.
- Acceptance criteria: missing worker id fails closed; exact-confirmed identity
  apply writes only safe local metadata; live heartbeat preview creates no
  server mutation; exact-confirmed live heartbeat registers and heartbeats the
  worker only; Desktop shows identity and cloud worker status.
- Implementation note: MG331 adds `skybridge-worker-identity.ps1`,
  `skybridge-worker-live-heartbeat.ps1`, identity/live heartbeat smokes, and
  Desktop identity/heartbeat status fields. Baseline worker id is
  `jerry-win-local-01`.
- Forbidden scope: live task claim, task execution, worker template runner live
  apply, Codex execution, MATLAB execution, arbitrary shell, worker loop start,
  unbounded run, PR creation, project-control unpause, deploy infrastructure
  mutation.
- Live deployment expected: no server runtime change; if the existing cloud
  auto-deploy runs after merge, verify parity through the existing path only.

## MG332 Live Worker One Safe Template Task

- Objective: prove one live task lifecycle from server queued task through
  local worker claim/start/complete with sanitized safe-local-smoke evidence.
- Likely touched: worker template runner, live pilot PowerShell helper,
  Desktop Worker Runner preview, Bootstrap Alpha acceptance, live task docs.
- Acceptance criteria: exactly one task id,
  `live-safe-template-task-332-001`, is created by the pilot, previewed,
  exact-confirmed, claimed, started, and completed or failed by
  `worker_id=jerry-win-local-01`; evidence summary is present; operator report,
  review gate, and self-bootstrap convergence remain safe.
- Implementation note: MG332 adds
  [Live Worker One Safe Template Task](../product/LIVE_WORKER_ONE_SAFE_TEMPLATE_TASK.md),
  `skybridge-live-safe-task-pilot.ps1`, live runner modes on
  `skybridge-worker-template-runner.ps1`, fixture/rejection smokes, and Desktop
  live pilot status fields.
- Forbidden scope: any old or arbitrary task claim, worker loop start, Codex
  execution, MATLAB execution, arbitrary shell, PR creation, project-control
  unpause, old task requeue, or production infrastructure mutation.
- Live deployment expected: no server runtime change; post-deploy checks may
  run read-only pilot previews. The one live apply may run only if the exact
  target task preconditions still hold.

## MG333 MATLAB Experiment Golden Trial

- Objective: run a reviewed MATLAB parameter sweep golden path through the
  template model after the one-safe-task live lifecycle has been proven.
- Implementation note: MG333 adds
  [MATLAB Experiment Golden Trial](../product/MATLAB_EXPERIMENT_GOLDEN_TRIAL.md),
  the fixed `skybridge-matlab-parameter-sweep-runner.ps1`, the deterministic
  `scripts/matlab/skybridge_run_parameter_sweep.m` fixture, the
  `skybridge-live-matlab-golden-trial.ps1` live orchestrator, Desktop preview
  fields, shared MATLAB runner/evidence schemas, and fixture/rejection smokes.
- Acceptance criteria: exactly one task id,
  `live-matlab-golden-task-333-001`, may be created and run by
  `worker_id=jerry-win-local-01`; MATLAB is invoked only by the fixed runner
  after exact confirmation; manifest, summary, metrics, and sanitized evidence
  are present; raw stdout/stderr are not reported.
- Forbidden scope: arbitrary MATLAB command text, Codex execution, production
  automation, unrelated project deployment, worker loops, run-until-hold,
  multiple task execution, background daemon expansion, PR creation, automatic
  merge, project-control unpause, and old task requeue.
- Live deployment expected: no server runtime change; post-deploy checks may
  run read-only MATLAB golden previews. The one live MATLAB apply may run only
  if exact target preconditions hold.

## MG334 MATLAB Startup Diagnostics And Golden Recovery

- Objective: diagnose MATLAB startup/license/batch availability and recover
  the MG333 failed golden trial with a new exact task id,
  `live-matlab-golden-task-334-001`.
- Implementation note: MG334 adds
  [MATLAB Startup Diagnostics And Recovery](../product/MATLAB_STARTUP_DIAGNOSTICS_AND_RECOVERY.md),
  `skybridge-matlab-doctor.ps1`,
  `scripts/matlab/skybridge_matlab_startup_doctor.m`,
  `skybridge-live-matlab-golden-recovery.ps1`, recovery Desktop fixture fields,
  and failed-evidence accuracy smokes.
- Acceptance criteria: doctor preview is read-only; doctor apply requires exact
  confirmation; recovery create/run require exact confirmations; the recovery
  path does not reuse `live-matlab-golden-task-333-001`; failed evidence lists
  only actual files in `changed_files`.
- Forbidden scope: arbitrary MATLAB command text, Codex execution, arbitrary
  shell, worker loop, PR creation, old task requeue, project-control unpause,
  and production infrastructure mutation.
- Live deployment expected: no server runtime change; post-deploy checks may
  run read-only doctor/recovery previews. The one live recovery apply may run
  only if doctor apply passes and exact target preconditions hold.

## MG335 MATLAB Local Runtime Repair

- Objective: make the fixed MATLAB doctor precise enough to prove local runtime
  readiness or classify the blocker before any recovery task is created.
- Implementation note: MG335 adds
  [MATLAB Local Runtime Repair](../product/MATLAB_LOCAL_RUNTIME_REPAIR.md),
  `skybridge-matlab-local-config.ps1`, expanded
  `skybridge.matlab_doctor.v1` fields, precise fixture classifications,
  stricter fixed diagnostic output checks, and Desktop runtime repair fields.
- Acceptance criteria: config preview is read-only; config apply requires exact
  confirmation and writes only user-level MATLAB executable/run-mode config;
  doctor classification covers executable, batch, license, startup, working
  directory, output write, fixed script, fallback, and unknown failures; raw
  stdout/stderr and tokens are not reported.
- Forbidden scope: task claim, recovery task creation, Codex execution, worker
  loop, PR creation, project-control unpause, arbitrary MATLAB command text,
  arbitrary shell, MATLAB installation mutation, license mutation, registry
  mutation, and system PATH mutation.
- Live deployment expected: no server runtime change; post-deploy checks may
  run read-only smokes and an optional fixed doctor only, with no task claim.

## MG336 MATLAB Golden Recovery Success

- Objective: prove the repaired MATLAB runtime can complete the fixed tiny
  sweep through one live SkyBridge task lifecycle.
- Implementation note: MG336 adds
  [MATLAB Golden Recovery Success](../product/MATLAB_GOLDEN_RECOVERY_SUCCESS.md),
  `skybridge-live-matlab-golden-success.ps1`, explicit output existence fields
  in MATLAB sweep evidence, Desktop success fixture fields, and success
  preview/fixture/rejection/evidence smokes.
- Acceptance criteria: only `live-matlab-golden-task-336-001` may be created
  and claimed; doctor apply must pass first; the runner writes manifest,
  summary, and metrics for exactly two combinations; evidence lists only actual
  output files and keeps raw stdout/stderr excluded.
- Forbidden scope: requeue or reclaim of `live-matlab-golden-task-333-001` or
  `live-matlab-golden-task-334-001`, arbitrary MATLAB command text, Codex
  execution, arbitrary shell, worker loop, PR creation, project-control unpause,
  old task requeue, generic MATLAB queue execution, and production
  infrastructure mutation.
- Live deployment expected: no server runtime change; post-deploy checks may
  include exactly one live MG336 success apply if the doctor, worker, API, token,
  task id, and output-path preconditions hold.

## MG337 Codex Analysis Report Golden Trial

- Objective: prove the first controlled Codex execution path by generating one
  bounded Markdown report from the MG336 MATLAB manifest, summary, and metrics.
- Implementation note: MG337 adds
  [Codex Analysis Report Golden Trial](../product/CODEX_ANALYSIS_REPORT_GOLDEN_TRIAL.md),
  `skybridge-codex-analysis-report-runner.ps1`,
  `skybridge-live-codex-analysis-report-trial.ps1`, a fixed prompt template,
  Codex report schemas, Desktop preview fields, and preview/fixture/rejection
  evidence smokes.
- Acceptance criteria: only `live-codex-analysis-report-task-337-001` may be
  created and claimed; Codex is invoked only by the fixed runner; report
  evidence lists the actual Markdown output and excludes raw Codex logs,
  prompt text, stdout, stderr, MATLAB execution, PR creation, and token
  printing.
- Forbidden scope: arbitrary prompts, MATLAB execution, arbitrary shell,
  source edits, PR creation, auto-merge, worker loops, project-control unpause,
  old task requeue, generic Codex queue execution, and production
  infrastructure mutation.
- Live deployment expected: no server runtime change; post-deploy checks may
  include exactly one live MG337 report apply if Codex, worker, API, token,
  task id, input-file, and output-path preconditions hold.

## MG338 Codex Artifact Persistence Recovery

- Objective: repair the MG337 Codex report artifact contract so the live
  recovery task produces a validated `report.md` or fails closed with accurate
  evidence.
- Implementation note: MG338 adds
  [Codex Artifact Persistence Recovery](../product/CODEX_ARTIFACT_PERSISTENCE_RECOVERY.md),
  `skybridge-live-codex-analysis-report-recovery.ps1`, deterministic output
  path validation in `skybridge-codex-analysis-report-runner.ps1`, a fallback
  report writer, evidence fields for report size/fallback/category, Desktop
  recovery visibility, and CI-safe recovery smokes.
- Acceptance criteria: only `live-codex-analysis-report-task-338-001` may be
  created and claimed; `report.md` must be under
  `.agent/tmp/codex-analysis-report/live-codex-analysis-report-task-338-001/`,
  non-empty, validated, and listed only when it exists; evidence must keep raw
  Codex logs, raw prompts, stdout, stderr, MATLAB execution, PR creation, worker
  loops, project-control unpause, and token printing disabled.
- Forbidden scope: requeue or reclaim of
  `live-codex-analysis-report-task-337-001`, arbitrary prompts, MATLAB
  execution, arbitrary shell, PR creation, auto-merge, worker loops,
  project-control unpause, old task requeue, generic Codex queue execution,
  notification send, and production infrastructure mutation.
- Live deployment expected: no new deploy path; post-deploy checks may include
  exactly one live MG338 report recovery apply if Codex, worker, API, token,
  exact task id, input-file, no-lease, no-residue, and output-path preconditions
  hold.

## MG339 Codex Native Report Validation Success

- Objective: make the fixed Codex report runner complete with a valid
  Codex-native Markdown report instead of the deterministic fallback writer.
- Implementation note: MG339 adds
  [Codex Native Report Validation Success](../product/CODEX_NATIVE_REPORT_VALIDATION_SUCCESS.md),
  `skybridge-live-codex-analysis-report-native-success.ps1`, stricter native
  report validation fields, native stdout persistence when safe, Desktop native
  report visibility, and CI-safe native validation smokes.
- Acceptance criteria: only `live-codex-analysis-report-task-339-001` may be
  created and claimed; Codex exits 0 through
  `codex-analysis-report-runner.v1`; `report.md` exists, is non-empty, and
  validates with `final_report_source=codex_native`,
  `fallback_report_used=false`, `native_report_valid=true`,
  `validation_status=passed`, and `codex_failure_category=none`.
- Forbidden scope: requeue or reclaim of MG337/MG338 tasks, arbitrary prompts,
  MATLAB execution, arbitrary shell, PR creation, auto-merge, worker loops,
  project-control unpause, old task requeue, generic Codex queue execution,
  notification send, raw Codex logs, raw prompts, process streams, credentials,
  tokens, runtime environment details, and production infrastructure mutation.
- Live deployment expected: no new deploy path; post-deploy checks may include
  exactly one live MG339 native report apply if Codex, worker, API, token,
  exact task id, input-file, no-lease, no-residue, and output-path preconditions
  hold.

token_printed=false
