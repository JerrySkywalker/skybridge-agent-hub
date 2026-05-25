# Adapter Taxonomy

SkyBridge Core is agent-agnostic. Concrete agent systems and services connect through the adapter ring.

| Adapter              | Role                               | Status         | Dogfooding | Notes                                                                        |
| -------------------- | ---------------------------------- | -------------- | ---------- | ---------------------------------------------------------------------------- |
| Hermes               | PlannerAdapter / supervisor        | dogfooding     | yes        | Optional planner/supervisor path used during SkyBridge development.          |
| Rule-based planner   | PlannerAdapter                     | fixture-backed | no         | Minimal docs-only planner proof that does not require Hermes.                |
| Codex                | ExecutorAdapter / telemetry source | dogfooding     | yes        | Optional executor and hook telemetry path used during SkyBridge development. |
| Manual executor      | ExecutorAdapter                    | fixture-backed | no         | Manual completion proof that does not require Codex.                         |
| OpenCode             | ExecutorAdapter / telemetry source | fixture-backed | no         | Fixture-backed plugin event adapter.                                         |
| GitHub               | SCMProvider / CI provider          | dogfooding     | yes        | Optional PR/CI policy provider; settings remain operator-owned.              |
| Generic SCM          | SCMProvider / CI provider          | experimental   | no         | Placeholder provider contract for non-GitHub systems.                        |
| ntfy                 | NotificationProvider               | stable         | yes        | First notification provider and bootstrap fallback.                          |
| Generic notification | NotificationProvider               | experimental   | no         | Placeholder provider contract for alternative notification systems.          |
| Local sidecar        | RuntimeProvider                    | experimental   | no         | Future worker/node runtime boundary.                                         |

Adapter status vocabulary:

- `stable`: implemented and expected to keep a compatible contract.
- `experimental`: contract exists but may change.
- `fixture-backed`: tested with local fixtures or smoke data, not real runtime contract tests.
- `dogfooding`: used to develop SkyBridge but still optional product surface.

See [../architecture/AGENT_AGNOSTIC_CORE.md](../architecture/AGENT_AGNOSTIC_CORE.md).
