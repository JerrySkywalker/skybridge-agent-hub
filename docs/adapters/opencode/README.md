# OpenCode Adapter

Status: `fixture-backed`

Role: `ExecutorAdapter` and telemetry adapter.

OpenCode support currently normalizes fixture-backed plugin events such as session status, tool events, file edits, permission events and todo updates.

Core boundary:

- OpenCode plugin internals stay in the adapter package.
- Events must normalize to `skybridge.agent_event.v1`.
- Real runtime contract tests are a follow-up before marking the adapter stable.

Related docs:

- [../OPENCODE.md](../OPENCODE.md)
