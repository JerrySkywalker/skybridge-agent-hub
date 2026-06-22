# Campaign Compiler Pilot 001

This deterministic docs-only pilot file is reserved for Mega Goal 322 live validation.

Allowed task:

- `campaign-policy-compiler-pilot-docs-001`

Safety boundary:

- docs-only update;
- no deployment;
- no credentials or private configuration;
- no server-root or external infrastructure changes;
- no repository settings changes;
- selected worker `jerry-win-local-01`;
- `token_printed=false`.

## Operator Note

Scope: SkyBridge Mega Goal 322 campaign compiler pilot.

This pilot is documentation-only. It records the intended operator boundary for
campaign compiler work without authorizing code, script, credential, deployment,
repository setting, or infrastructure changes.

Operators may use this note to evaluate whether a future campaign compiler run is
ready for execution. Treat the compiler as a planning and packaging aid until a
separate goal explicitly authorizes implementation or runtime changes.

## Pilot Rules

- Keep all pilot work inside reviewable documentation artifacts.
- Do not run compiler output against live agent queues, production services, or
  remote infrastructure from this pilot.
- Do not introduce or modify secrets, `.env` files, deployment manifests, CI
  settings, service configuration, or repository protection settings.
- Require normalized SkyBridge terminology in any proposed campaign artifacts:
  goals, subtasks, gates, checks, evidence, risks, and follow-ups.
- Preserve the one-goal-at-a-time operating model unless a later approved goal
  adds explicit locking and conflict handling.

## Readiness Checklist

- Campaign intent is stated in operator-readable language.
- Generated subtasks are independently reviewable and docs-first.
- Safety boundaries are explicit and visible before execution.
- Required checks and stop conditions are listed before any implementation goal
  is opened.
- Residual risks and follow-up goals are documented instead of handled
  opportunistically.
