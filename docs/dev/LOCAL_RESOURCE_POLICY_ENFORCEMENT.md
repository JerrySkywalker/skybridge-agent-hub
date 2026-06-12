# Local Resource Policy Enforcement

The local resource policy is an enforcement gate for future Managed Mode one-at-a-time run apply. It decides whether a future run is allowed to proceed. It does not start workers, claim tasks, execute Codex, or mutate Windows power settings.

## Enforced

- AC power is required when a battery device is present.
- Running on battery blocks one-at-a-time run allowance.
- Battery below `30%` blocks run allowance.
- Memory usage above `90%` blocks run allowance.
- Network availability is required when it can be safely observed.

## Advisory

- CPU usage is currently advisory because the script does not run a sampling loop.
- Idle detection is advisory unless using the `fixture-idle-required` smoke fixture.
- Allowed hours are represented in policy as `00:00-23:59 local` for v0.

## Not Mutated

The script never calls `powercfg`, never changes registry settings, never changes sleep/lid behavior, never dumps environment variables, and never requires admin privileges.

## Inspect Status

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-resource-policy.ps1 -Command status -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-resource-policy.ps1 -Command enforcement-gate -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-resource-policy.ps1 -Command run-allowance -Json
```

Fixture commands are available for deterministic smokes:

```powershell
fixture-ac-ok
fixture-battery-blocked
fixture-memory-blocked
fixture-idle-required
fixture-network-blocked
```

## Future Run Gate

Managed Mode v0 release readiness requires a resource gate before any future one-at-a-time run. A future run may proceed only when:

- an explicit future goal authorizes that run;
- `run-allowance.can_run_one_at_a_time=true`;
- blockers are empty;
- task scope remains within the explicit run limits;
- `token_printed=false`.
