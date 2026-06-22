# Bounded Run-Until-Hold

Mega Goal 321 adds a bounded, supervised run-until-hold pilot path for deterministic low-risk docs/test tasks only.

The loop is not a daemon and does not enable generic queue apply. It previews by default, caps selected work at `MaxTasks` with an absolute maximum of 3, keeps `project_control` paused, writes sanitized evidence for every attempted task, and stops on exhaustion, no safe candidate, first failure, missing evidence, unsafe path changes, worker unavailability, stale claim/lease, validation failure, or runtime limit.

Seed preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-seed-run-until-hold-pilot-tasks.ps1 -Json
```

Seed apply requires:

```text
I_UNDERSTAND_SEED_BOUNDED_RUN_UNTIL_HOLD_PILOT_TASKS
```

Bounded run preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-until-hold-bounded.ps1 -Json
```

Bounded apply requires:

```text
I_UNDERSTAND_BOUNDED_RUN_UNTIL_HOLD_MAX_2_SAFE_TASKS
```

The report command returns `skybridge.run_until_hold_report.v1` and summarizes stop reason, hold reason, evidence presence, old-residue exclusion, paused project control, and bounded/non-recursive proof.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-until-hold-report.ps1 -Json
```

Validation:

```powershell
corepack pnpm smoke:run-until-hold-pilot-seed
corepack pnpm smoke:run-until-hold-bounded
```

Safety invariants:

- only `run-until-hold-pilot-docs-001` through `run-until-hold-pilot-docs-003` can be selected;
- each selected task must be queued, low risk, docs/test typed, marked `bounded_loop_pilot`, and limited to one matching `docs/operations/RUN_UNTIL_HOLD_PILOT_00N.md` path;
- old failed, blocked, completed, unsafe-to-requeue, active non-pilot, stale-claim, active-lease, deploy, secret, server-root, OpenResty, Authelia, DNS, Cloudflare, and GitHub-settings surfaces are rejected;
- no raw prompts, raw logs, raw stdout/stderr, credentials, cookies, tokens, or environment dumps are reported;
- operator reports may summarize selected/executed counts, stop reasons, hold reasons and evidence presence, but never raw task prompts or Codex output;
- review gate status must keep unbounded run and daemon mode disabled;
- `token_printed=false`.
