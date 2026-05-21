# OpenCode Adapter

SkyBridge normalizes OpenCode plugin events with `@skybridge-agent-hub/adapter-opencode-plugin`.

## Contract

The adapter emits `skybridge.agent_event.v1` before events are sent to the server. The MVP accepts common plugin-style payloads with:

- `type`: `session:start`, `session:idle`, `run:status`, `run:error`, `tool:start`, `tool:end`, `tool:error`, `file:edited`, `approval:request`, `approval:reply`, `todo:update` or `message`;
- `sessionId`, `runId`, `toolCallId`;
- optional `agent`, `nodeId`, `cwd`, `summary`, `toolName`, `path`, `permission`, `decision` and `todos`.

Unknown payloads become `message.completed`; malformed non-object input emits no event.

## Safety Defaults

The adapter does not preserve raw prompts, full commands, stdout, stderr, file contents or patch bodies. Secret-like strings and user-home paths are redacted or bounded before they enter normalized payloads.

## Example

```ts
import { normalize } from "@skybridge-agent-hub/adapter-opencode-plugin";

const events = normalize({
  type: "tool:end",
  sessionId: "opencode-session-1",
  runId: "opencode-run-1",
  toolCallId: "tool-1",
  toolName: "bash",
  summary: "completed"
});
```
