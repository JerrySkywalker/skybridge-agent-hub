# Dogfooding Boundaries

SkyBridge is developed using Hermes, Codex, GitHub Actions and ntfy. That is intentional dogfooding, not a product dependency.

## Current Dogfooding Roles

- Hermes: planner/supervisor adapter for health checks, nightly reports and safe supervision decisions.
- Codex: executor adapter for local implementation work and redacted hook/exec telemetry.
- GitHub: SCM/CI provider for PR checks, branch policy visibility and dry-run auto-merge decisions.
- ntfy: notification provider and bootstrap phone-notification fallback.

## Product Boundary

SkyBridge Core must remain useful without those systems. A basic demo path should work with:

- rule-based planner output;
- manual executor completion records;
- generic SCM/CI provider placeholders;
- generic notification provider placeholders;
- local fixture events.

## Adding A New Adapter

1. Put source-specific logic in an adapter package, script or provider package.
2. Normalize emitted events to `skybridge.agent_event.v1`.
3. Register capabilities through the neutral adapter registry.
4. Document status as `stable`, `experimental`, `fixture-backed` or `dogfooding`.
5. Add focused fixtures or smoke tests.
6. Keep credentials in local env files or operator-managed secret stores, never in Git.

## Preventing Adapter Leakage

Do not place these in core:

- provider credentials or env-file paths;
- provider-specific CLI flags or hook config paths;
- raw prompts, command output, patches, stdout/stderr or tool results;
- GitHub-only or ntfy-only assumptions in neutral policy names;
- Hermes-only scheduling language in project/goal/task APIs;
- Codex-only worker language in executor-neutral surfaces.

Use neutral terms in core and product docs: Planner, Executor, SCM/CI provider, Notification provider and Runtime worker.
