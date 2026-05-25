# Hermes Adapter

Status: `dogfooding`

Role: `PlannerAdapter` and supervision adapter.

Hermes is used during SkyBridge development to supervise autonomous iterations, inspect health, produce nightly summaries and exercise the operator dashboard. Hermes is not required by SkyBridge Core.

Core boundary:

- Hermes-specific API keys, tunnels, prompts and endpoint shape stay in adapter scripts and Hermes docs.
- Hermes events must normalize to `skybridge.agent_event.v1`.
- Product APIs should describe planner/supervisor capability, not require Hermes.

Related docs:

- [../../hermes/SUPERVISOR.md](../../hermes/SUPERVISOR.md)
- [../../hermes/CLOUD_SUPERVISOR_RUNBOOK.md](../../hermes/CLOUD_SUPERVISOR_RUNBOOK.md)
