# Managed Mode v1 Pilot

Managed Mode v1 is the BOINC-like direction for SkyBridge Agent Hub, but Goal 208 keeps it in pilot-only form. General bounded queue apply remains disabled. The only authorized apply shape is one explicitly bounded pilot workunit under `managed-mode-pilot-208`.

## Distinction

General managed mode means the queue could select and execute multiple workunits over time. That is still disabled because locking, conflict handling, retry policy and operator review boundaries are not complete enough for unattended queue continuation.

Pilot mode is a narrow readiness and apply contract for one low-risk docs/local-smoke workunit. It proves the queue, scheduler and sanitized executor boundary can be joined without exposing broad execution controls.

## Pilot Limits

- `pilot_id=managed-mode-pilot-208`
- `mode=managed_mode_v1_pilot`
- `max_workunits=1`
- `max_tasks=1`
- `max_claims=1`
- `max_codex_executions=1`
- `max_prs=1`
- `max_runtime_minutes<=30`
- `max_parallel_per_repo=1`
- `stop_on_pr_created=true`
- `stop_on_ci_failure=true`
- `stop_on_warning=true`
- `require_human_review=true`
- allowed task types: `docs`, `local-smoke`, `docs/local-smoke`
- allowed paths: `README.md`, `docs/**`

Blocked surfaces include production deploy, secret rotation, server-root config, DNS, OpenResty config, Hermes config, GitHub settings, branch protection, arbitrary shell execution, auto execution and auto merge.

## Operator Review Boundary

The pilot may create at most one task PR. That PR must remain open for human review. The pilot must stop immediately after PR creation or controlled failure and must not continue to another workunit.

Goal 208C finalization is separate and may complete only after the human operator manually merges the task PR.

## Finalizer

The finalizer is infrastructure-only until the pilot task PR exists and is manually merged. It must not create work, rerun the pilot, merge the task PR, or continue the queue.

Read-only finalizer commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command finalizer-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command finalizer-evidence -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command finalizer-report -Json
```

`finalizer-apply` is the only finalizer command that can write files, and it writes only ignored safe evidence under `.agent/tmp/managed-mode-pilot-208/`. It refuses unless all of these are true:

- pilot executor evidence exists and is safe;
- the pilot task PR is merged;
- changed files exist on `main` and stay within `README.md` or `docs/**`;
- exactly one workunit, task, claim, Codex execution and PR were recorded;
- no second workunit or task PR is present;
- `active_tasks=0`, `stale_leases=0` and `runner_lock=none`;
- no raw prompt, transcript, stdout, stderr, worker log, CI log or secret-bearing value is persisted;
- no previous finalizer evidence already completed the pilot.

If the task PR is missing or still open, finalizer preview and apply report `held_waiting_human_pr_review` and do not complete the pilot.

## Renewed Apply After Launcher Repair

Goal 208D authorizes one renewed `pilot-apply` only because the first apply attempt failed before Codex execution when the Windows Codex launcher shim was not hosted correctly. The renewed path is not a general retry mechanism.

The renewed apply must pass the normal one-workunit pilot gate and must also classify the prior attempt as `prior_attempt_failed_before_execution`. It fails closed if any pilot task PR, executor evidence, finalizer evidence, ambiguous partial result, unknown artifact, raw prompt, transcript, stdout, stderr, worker log, CI log or secret-looking content exists.

The renewed apply must be invoked with an explicit reason:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command pilot-apply -RenewedAuthorization -RequireRenewedAuthorization -RenewedAuthorizationReason "Renewed operator authorization after prior launcher failure before execution; launcher repair merged; no prior task PR or executor evidence exists." -Json
```

The resulting safe evidence distinguishes the prior failed-before-execution state from the renewed authorized attempt and keeps `token_printed=false`.

## Timeout Recovery and Single Retry

Goal 208E adds timeout classification for the renewed pilot attempt. A timeout is retryable only when it is classified as `prior_attempt_timed_out_no_mutation`.

That classification requires all of these facts to be true:

- `pilot-result.json` exists and records `timed_out=true`;
- no pilot task PR was created or left open;
- `changed_files` is empty;
- pilot executor evidence is absent;
- finalizer evidence is absent;
- the pilot state directory contains no raw prompt, transcript, stdout, stderr, worker log, CI log or secret-looking artifact;
- `token_printed=false`;
- the normal pilot gate still reports one workunit, one worker, no active tasks, no stale leases and no runner lock.

The retry policy is intentionally one-shot:

- `max_retries=1`;
- `retry_reason_required=true`;
- retry is allowed only after timeout-without-mutation;
- retry is refused after any PR, executor evidence, finalizer evidence, partial changes, raw artifacts or ambiguous result;
- a second timeout or controlled retry failure marks the retry budget exhausted.

Read-only timeout and retry commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command timeout-state -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command retry-readiness -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command retry-preview -Json
```

`retry-apply` is mutating and is authorized only by a future operator goal after the timeout recovery infrastructure is merged:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command retry-apply -RetryAuthorization -RetryAuthorizationReason "Operator-authorized one-time retry after prior Codex timeout without mutation; timeout recovery policy merged; prompt narrowed; no prior PR or executor evidence exists." -Json
```

The retry prompt is narrowed to one tiny documentation-only change, currently `docs/managed-mode-pilot-orientation.md`. It forbids broad exploration, broad validation, interactive actions, user input waits, code changes and paths outside `docs/**`.

## Validation

Preview and readiness commands are read-only:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command schema -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command readiness -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command plan-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command apply-gate -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command pilot-preview -Json
```

Focused smokes:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-readiness-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-general-apply-disabled.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-policy-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-preview-no-mutation.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-one-workunit-only.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-docs-only.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-rejects-production.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-rejects-secrets.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-rejects-auto-merge.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-no-start-all.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-no-unbounded-queue.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-token-printed-false.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-finalizer-preview.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-finalizer-requires-merged-pr.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-finalizer-evidence-safe.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-finalizer-refuses-rerun.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-finalizer-no-second-workunit.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-finalizer-token-printed-false.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-renewed-authorization-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-prior-failed-before-execution-resumable.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-prior-success-refuses-renewal.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-prior-ambiguous-refuses-renewal.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-renewed-apply-one-shot-only.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-renewed-apply-no-raw-artifacts.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-renewed-apply-token-printed-false.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-timeout-state-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-classifies-timeout-no-mutation.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-timeout-ambiguous-refused.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-timeout-with-changes-refused.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-timeout-with-pr-refused.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-timeout-with-raw-artifacts-refused.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-policy-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-readiness.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-preview-no-mutation.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-exhaustion.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-token-printed-false.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-apply-one-shot.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-creates-one-pr.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-refuses-second-retry.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-timeout-exhausts-budget.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-no-auto-merge.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-no-raw-artifacts.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-pilot-retry-clean-worktree.ps1
```

Every JSON result must keep `token_printed=false` and must not persist raw prompts, transcripts, stdout, stderr, raw worker logs or secrets.
