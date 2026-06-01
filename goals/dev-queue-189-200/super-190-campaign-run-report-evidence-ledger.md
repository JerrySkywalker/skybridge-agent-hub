```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-190-campaign-run-report-evidence-ledger","title":"Campaign Run Report and Evidence Ledger","order":2,"risk":"medium","task_type":"super-goal","allowed_task_types":["docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-189-ci-guardian-pr-finalizer-hardening"],"expected_outputs":["campaign_report_markdown","campaign_report_json","evidence_ledger"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 190: Campaign Run Report and Evidence Ledger

## Context

- Goal 188 added runner commands and local runner state, but unattended review needs a compact report that is more useful than raw logs.
- Operators need to understand what happened in each campaign step without reading tokens, prompts, command output, or raw worker logs.

## Mission

Produce Markdown and JSON campaign reports with a durable step ledger, PR/CI/evidence ledger, Hermes gate history, runner state, locks, stop reasons, and final acceptance summary.

## Global Safety Boundaries

- Do not print tokens, secrets, credentials, cookies, private keys, raw authorization headers, or secret-bearing local paths.
- Do not mutate GitHub repository settings, branch protection, Actions secrets, environments, or organization settings.
- Do not modify production, server-root, DNS, OpenResty, Authelia, 1Panel, Docker daemon, or Hermes server configuration unless a later goal explicitly allows a bounded change.
- Do not deploy to production, rotate secrets, weaken authentication or authorization, or upload raw command output by default.
- Keep dry-run as the default where an operation can mutate external state.
- Do not run an unbounded worker loop; use bounded, local, fixture, or dry-run validation unless the goal explicitly authorizes apply-mode execution.

## Phase A: Preflight

- Run `git status --short` and confirm the working tree is clean before implementation.
- Confirm the current branch is the goal branch for this work, not `main`.
- Run or review the smallest relevant project-control status command and confirm active tasks are zero before any apply-gated operation.
- Run or review hygiene status and confirm stale leases are zero before any apply-gated operation.
- Check for local runner or campaign locks that could indicate another active runner.
- If active tasks, stale leases, active runner locks, or unexpected project-control running state are present, stop and report instead of continuing.

## Phase B: Ledger Schema

- Define a stable report schema for campaign, step, task, PR, CI, gate, lock, stop, and evidence summaries.
- Use safe metadata only and omit raw logs, prompts, patches, stdout, stderr, and secret-bearing paths.

## Phase C: Report Generator

- Improve or add runner-report output for both Markdown and JSON.
- Include step ordering, dependency status, current runner status, stop reason, and validation summary.
- Make report paths deterministic and write reports under ignored output locations by default.

## Phase D: Evidence Collection

- Collect linked task ids, PR URLs, CI conclusions, finalizer decisions, gate decisions, and evidence repair status.
- Represent missing evidence explicitly instead of implying success.
- Ensure token_printed=false is present in JSON results.

## Phase E: Operator Docs

- Document how to read the final campaign report.
- Document which fields are safe to paste into PRs or issue comments.
- Document which raw local logs remain local-only.

## Validation Phase

- Prove JSON output is parseable and contains all required ledger sections.
- Prove Markdown output contains campaign summary, step ledger, evidence ledger, gate history, stop reason, and acceptance summary.
- Run token-looking text checks against generated reports.

## Final Status Phase

- Record changed files and commits.
- Record validation commands and results.
- Record final `git status --short`.
- Record project-control state when available: paused/running, active tasks, stale leases, and token_printed=false.
- Record any residual risk or follow-up goal needed for incomplete non-blocking work.

## PR Package Phase

- Keep commits coherent and reviewable.
- Push the branch after validation passes or after failures are clearly documented.
- Open or update the parent PR as draft/manual unless the active goal explicitly authorizes auto-merge.
- Include summary, validation, evidence, risks, rollback notes, and confirmation that no secrets were introduced.

## Success Criteria

- Minimum success: campaign_report_markdown is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
- Qualified success: all expected outputs are implemented with local or dry-run smokes, docs are updated, and evidence is sufficient for campaign review.
- Ideal success: all expected outputs are implemented, existing relevant checks pass, UX/docs are clear enough for unattended follow-on execution, and residual risk is limited to explicitly documented follow-up work.

## Stop And Hold Conditions

- Active tasks are present.
- Stale leases, active runner locks, or ambiguous lock ownership are present.
- A required validation command fails in a way that would make unattended execution unsafe.
- The implementation would require production/server-root/DNS/OpenResty/Authelia/1Panel/Docker daemon/Hermes mutation outside the explicit scope.
- The implementation would require GitHub settings or branch protection mutation.
- A token, credential, private key, raw prompt, raw command output, or secret-looking value appears in generated output.
- The work would execute a later campaign step or create campaign-step-derived tasks without explicit authorization.

## Evidence Requirements

- generated report paths
- step count
- gate decisions
- PR links
- CI states
- token_printed=false
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- campaign_report_markdown
- campaign_report_json
- evidence_ledger

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
