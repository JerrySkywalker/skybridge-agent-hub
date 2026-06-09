# Campaign Report And Evidence Ledger

Goal 190 adds a read-only campaign run report for `dev-queue-189-200`. The report is designed as the stable data source for later Desktop and Web queue controls. It summarizes campaign state, step evidence, recovered evidence, missing evidence, hygiene and queue-control readiness without requiring operators to inspect local runtime logs.

Generate the JSON and Markdown artifacts:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 `
  runner-report `
  -CampaignId dev-queue-189-200 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -Json
```

The default artifacts are ignored local files:

```text
.agent/tmp/campaign-reports/dev-queue-189-200-campaign-report.json
.agent/tmp/campaign-reports/dev-queue-189-200-campaign-report.md
```

`skybridge-dev-queue-control.ps1 -Command report -Json` remains compatible and returns the same `report` object plus the control wrapper hygiene counters.

## JSON Contract

The report schema is `skybridge.campaign_run_report.v1`.

Top-level sections:

- `schema`, `generated_at`, `project_id`, `campaign_id`, `campaign_status`.
- `current_step_id`, `current_goal_id`, `current_goal_status`, `current_goal_unexecuted`.
- `campaign_summary`, `current_step_summary`, `previous_step_summary`.
- `step_ledger`.
- `evidence_ledger`.
- `recovery_ledger`.
- `hygiene_summary`.
- `runner_state_summary`.
- `lock_summary`.
- `blocker_summary`, `warning_summary`, `blockers`, `warnings`.
- `queue_control_readiness`.
- `acceptance_summary`.
- `artifact_summary`, `artifact_paths`.
- `token_printed=false`.

The report intentionally omits runtime transcripts, prompt bodies, command output streams, patches, Authorization headers, credentials and token-bearing local paths.

## Markdown Contract

The Markdown artifact is safe to paste into PRs after a quick token-pattern check. It includes Campaign Summary, Current Step, Previous Step, Step Ledger, Evidence Ledger, PR/CI Summary, Finalizer Summary, Recovery Summary, Hygiene Summary, Queue Control Readiness, Blockers And Warnings, Acceptance Summary and `Token printed: false`.

Local-only material stays out of the Markdown report: worker runtime logs, Codex runtime logs, command output streams, prompt transcripts and token files.

## Evidence Ledger Fields

Each evidence entry includes:

- `kind`: `step`, `task`, `pr`, `ci`, `finalizer` or `gate`.
- `campaign_step_id` and `goal_id`.
- `evidence_id`: safe id or URL summary, or `none` when evidence is missing or not applicable.
- `status`: `present`, `recovered`, `missing`, `skipped`, `not_applicable`, `passed` or another bounded status summary.
- `classification`: `present_evidence`, `recovered_evidence`, `missing_evidence`, `skipped_evidence` or `not_applicable_evidence`.
- `recovered`, `missing`, `skipped`, `not_applicable`.
- `operator_action_required`.
- `summary`: short safe text only.

Missing evidence is explicit. A ready current step with no linked task or PR has `missing_evidence` entries for task, PR, CI and finalizer evidence. Pending future steps use `not_applicable_evidence`, not missing evidence.

Recovered evidence is explicit. Goal 189 is represented as completed with recovered step, task, PR, CI and finalizer evidence. Its PR URL is present, and CI is summarized as passed.

## Queue Control Readiness

`queue_control_readiness` is the field Desktop and Web queue controls should consume before enabling any button.

Fields:

- `can_start_one`.
- `can_start_queue`.
- `can_pause`.
- `can_stop`.
- `can_emergency_stop`.
- `can_resume`.
- `blockers[]`.
- `warnings[]`.
- `required_human_action[]`.
- `next_safe_action`.
- `worker_required`.
- `worker_status`.
- `run_budget_required`.
- `reason_required`.

Desktop/Web controls must treat `blockers[]` as disabling. Historical warnings can be displayed without becoming current blockers. A control surface must still require a human reason for mutating actions and must never infer permission from `can_start_one` alone.

Start controls must also require worker readiness. When `worker_required=true`, Desktop/Web controls must keep `start-one`, `start-queue` and apply-mode resume disabled unless `worker_status` is `online` or `ready`. Values such as `unknown`, `offline`, `stale` or `missing` are execution blockers and should surface `verify_worker_online_before_execution` before any start action. `can_stop` and `can_emergency_stop` can remain enabled because they are conservative no-regret controls.

Goal 191D adds the first shared dashboard consumer for this contract. Web and Desktop use the same typed model, evidence count helper and safe summary builder from `@skybridge-agent-hub/client`. Dashboard rendering is read-only: `queue_control_readiness` may be displayed, but active queue mutations are deferred to Goal 192A/192B.

## Current Dev Queue State

The historical Goal 190 implementation state was `ready` and unexecuted while the report feature was being introduced. The current checked-in `dev-queue-189-200` state has advanced through the full reviewed queue:

- current step: `dev-queue-189-200:super-200-controlled-goal-draft-review-import`;
- current goal: `super-200-controlled-goal-draft-review-import`;
- current goal status: `completed`;
- current goal unexecuted: `false`;
- linked task ids: empty;
- linked PR URLs: the Goal 200 PR evidence URL.

This remains a read-only report state. Generating the report does not create campaign-step-derived tasks, run `start-one`, run `start-all`, run `resume -Apply` or start a worker loop.

After the Goal 190 PR merges, the next recommended operator action is to generate the report again from clean latest `main`, review the artifacts, then separately decide whether to attach the Goal 190 PR/report evidence and complete the Goal 190 campaign step. Goal 191 must not start as a side effect of report generation.

## Safe Sharing

Safe to paste after checking `token_printed=false`:

- generated Markdown report;
- generated JSON report;
- PR URL, task ids, CI status summaries and recovered evidence summaries from the report.

Local-only:

- worker runtime logs;
- Codex runtime logs;
- command output streams;
- prompt transcripts;
- token files or worker profile secret locations;
- any manually captured terminal output that has not been redacted.
