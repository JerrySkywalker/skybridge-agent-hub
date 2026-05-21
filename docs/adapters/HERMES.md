# Hermes Adapter

SkyBridge normalizes Hermes Agent API and stream samples with `@skybridge-agent-hub/adapter-hermes-api`.

## Contract

The adapter emits `skybridge.agent_event.v1` from run status and stream-like records:

- run lifecycle: `created`, `queued`, `running`, `completed`, `succeeded`, `failed`, `error`;
- approval lifecycle: `waiting_for_approval`;
- tool stream events: `tool_started`, `tool_completed`, `tool_failed`;
- correlation: `id`, `runId`, `sessionId`, `toolCallId`;
- metadata: `agentId`, `nodeId`, `title`, `detail`, `queue`, `toolName`, `exitCode`.

Unknown object payloads are treated as safe run/status messages. Non-object payloads emit no event.

## Safety Defaults

The adapter summarizes status and tool metadata only. It omits raw prompts, stdout, stderr and tool result bodies, and redacts obvious bearer tokens, passwords, cookies and API keys from bounded text fields.

## Example

```ts
import { normalize } from "@skybridge-agent-hub/adapter-hermes-api";

const events = normalize({
  id: "hermes-run-1",
  status: "queued",
  queue: "default"
});
```
