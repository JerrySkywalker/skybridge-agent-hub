# Progress Log

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
