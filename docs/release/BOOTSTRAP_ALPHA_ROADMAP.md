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
- Forbidden scope: MATLAB execution, arbitrary shell, unbounded run, daemon
  auto-expansion, project-control unpause.
- Live deployment expected: maybe, for server compatibility only.

## MG330 MATLAB Experiment Golden Trial

- Objective: run a reviewed MATLAB parameter sweep golden path through the
  template model.
- Likely touched: MATLAB template docs, worker runner, fixture experiment
  assets, evidence schemas, Desktop/server reports.
- Acceptance criteria: operator confirms a MATLAB draft; worker runs only the
  MATLAB template runner; result summary and report are returned; no arbitrary
  shell is used.
- Forbidden scope: production automation, unrelated project deployment,
  background daemon expansion, automatic merge.
- Live deployment expected: maybe, if the server must store golden-path state.

## MG331 End-to-end Bootstrap Alpha Release

- Objective: release the complete Bootstrap Alpha golden path.
- Likely touched: release docs, server deploy scripts, Desktop package docs,
  acceptance scripts, operator runbooks, CI/release workflows.
- Acceptance criteria: cloud server parity passes; Desktop install target works;
  worker service target works; chat-to-task draft review works; template runner
  evidence returns; operator report and review gate are clean.
- Forbidden scope: general remote shell, multi-user permissions, mobile/watch
  client, automatic merge without operator review, production infrastructure
  changes outside the existing SkyBridge deploy contract.
- Live deployment expected: yes, using the existing SkyBridge server deploy
  workflow only.

token_printed=false
