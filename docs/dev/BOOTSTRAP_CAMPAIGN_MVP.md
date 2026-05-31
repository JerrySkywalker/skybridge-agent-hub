# Bootstrap Campaign MVP

Super 187 hardens the bootstrap campaign sequencer into a restartable MVP. The campaign layer stays metadata-only: importing a Goal Pack, marking a step ready, retrying a step, skipping a step or exporting an audit report must not run imported Super Goal markdown or start a worker by itself.

## MVP Invariants

- Dry-run is the default for every campaign mutation.
- `-Apply` is required for import, start, pause, hold, resume, retry, skip, complete, fail, evidence attach and advance.
- One active campaign per project is allowed by default.
- Campaign locks are separate from task leases and local repo locks.
- Campaign advance marks metadata only; execution still goes through proposal review, task conversion and worker lease gates.
- A campaign step result is auditable from events plus linked PR, task and validation evidence.

## Restart And Resume Semantics

A campaign can be resumed after an interrupted operator session only after reading authoritative server state. Resume must not trust local terminal history.

Resume preflight:

1. Read campaign, current step and recent campaign events.
2. Read project control, active tasks, active or stale leases, worker status and queue hygiene.
3. Check whether the last step has terminal evidence: `completed`, `recovered`, `failed`, `held`, `skipped` or `needs_human`.
4. Check whether a campaign lock exists and whether it is active or stale.
5. Produce a preview result that says `resume_allowed`, `hold_required`, `retry_allowed` or `operator_review_required`.

Resume apply may refresh or replace a stale campaign lock only when the stale lock belongs to the same campaign and the operator supplies a reason. It must not re-run a step automatically. If the previous session already created a child PR, resume should link the PR and require CI/evidence review before retrying.

## Campaign Locks

Campaign locks protect campaign metadata decisions. They do not replace task leases, worker repo locks or Git branch collision checks.

Recommended lock fields:

- `schema`: `skybridge.campaign_lock.v1`
- `campaign_id`
- `project_id`
- `step_id`
- `goal_id`
- `owner_worker_id` or `operator_id`
- `operation`: `import`, `advance`, `complete`, `fail`, `retry`, `skip`, `hold`, `resume` or `export`
- `created_at`
- `updated_at`
- `expires_at`
- `reason`
- `last_event_id`

Lock rules:

- A campaign mutation checks the campaign lock before writing campaign or step state.
- A stale lock blocks by default and is recoverable only through explicit preview and `-Apply`.
- Lock recovery writes a `campaign.lock.recovered` event with the stale lock summary and recovery reason.
- Lock payloads must not include tokens, raw command output, full logs or raw markdown bodies.

## One Active Campaign Per Project

The project should have at most one campaign in an active execution state:

```text
ready / running / paused / held
```

Creating or starting another active campaign should return a deterministic hold unless an operator passes an explicit override. The override must record:

- the existing active campaign id;
- the new campaign id;
- the reason;
- the operator or worker id;
- whether the campaigns have overlapping expected files.

The override is for emergency migration only. Normal bootstrap work should finish, hold, fail or abort the current campaign before starting another.

## Step Retry, Skip And Hold

Step retry is for an already attempted step. It should preserve original evidence and add a new attempt record. Retrying a step must require:

- current step status is `failed`, `held`, `needs_human` or `recovered`;
- no active tasks or stale leases are present for the project;
- no active child PR already covers the same step unless the retry is explicitly linked to that PR;
- a retry reason and expected validation command;
- a maximum retry count or operator override.

Step skip is for a consciously omitted step. It must require evidence explaining why the step is safe to skip. Skip evidence should include either a replacement PR/task, a superseding campaign step or a human decision reason. Skipped steps can satisfy dependencies only when their skip evidence is present.

Step hold is for temporary pause. It must require a reason, owner and next review condition. Holds should be used for CI pending, human approval, unresolved evidence, stale locks, stale leases or high-risk follow-up. Hold is preferable to retry when the current state is ambiguous.

## Step Event Log

Campaign events should be append-only and derived into status views. Minimum event families:

```text
campaign.imported
campaign.started
campaign.paused
campaign.resumed
campaign.held
campaign.completed
campaign.failed
campaign.aborted
campaign.lock.acquired
campaign.lock.recovered
campaign.lock.released
campaign.step.ready
campaign.step.started
campaign.step.completed
campaign.step.recovered
campaign.step.failed
campaign.step.retry_requested
campaign.step.retry_started
campaign.step.skipped
campaign.step.held
campaign.step.needs_human
campaign.step.evidence_attached
campaign.step.advance_previewed
campaign.step.advance_blocked
campaign.step.advanced
campaign.report.exported
```

Event payloads should contain bounded summaries: ids, status, reasons, linked PRs, linked tasks, validation status, CI status, retry count, gate decisions and hygiene counts. They must not contain raw Codex JSONL, full command output, tokens or secrets.

## Audit And Export Reports

Campaign export should produce a reviewable report that can be attached to a parent or child PR. It should include:

- campaign id, title, source pack hash and current status;
- step table with status, attempts, linked PRs, linked tasks, validation and CI;
- deterministic and Hermes gate decisions when present;
- campaign lock history and recovered stale locks;
- active task and stale lease counts at each gate;
- retry, skip and hold reasons;
- required human approvals;
- residual risks and follow-up tasks.

Export is read-only by default. If an export command writes a file, it should require an explicit output path and avoid local runtime directories that are excluded from Git unless the report is intended to remain local.

## Validation Target

For docs-only campaign hardening, validation is:

```powershell
corepack pnpm check
```

If `just` is available, `just check` remains the final preferred command. A failed or unavailable check must be recorded in the campaign step result rather than hidden.

## Super 187 Pilot Result

Super 187 proved the next bootstrap capability: a campaign step can be turned into one approved task, executed through the lease-backed worker flow, attached back to the campaign step as evidence, and advanced through deterministic plus Hermes gate evaluation.

Pilot result:

- campaign id: `bootstrap-mvp`
- executed step: `bootstrap-mvp:super-187-bootstrap-campaign-mvp-hardening`
- derived task: `campaign-step-super-187-bootstrap-campaign-mvp-hardening-20260531100053`
- lease id: `lease_chdDfMPI1SEIgonHR-hzv`
- child PR: `https://github.com/JerrySkywalker/skybridge-agent-hub/pull/92`
- CI: passed
- merge: PR #92 merged
- evidence: recovered after the initial draft/pending CI guardian stop
- gate result: final decision `advance`
- current campaign step after pilot: `bootstrap-mvp:super-184b-operator-console-dashboard`

The pilot did not execute Super 184B and did not change production deployment, server root configuration, secrets, GitHub settings or branch protection.
