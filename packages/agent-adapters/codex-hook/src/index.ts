import { createEvent, type SkyBridgeEvent, type SkyBridgeEventType } from "@skybridge-agent-hub/event-schema";

type CodexHook = Record<string, unknown>;

const hookEventTypes: Record<string, SkyBridgeEventType> = {
  SessionStart: "session.started",
  UserPromptSubmit: "run.started",
  PreToolUse: "tool.started",
  PostToolUse: "tool.completed",
  PermissionRequest: "approval.requested",
  Stop: "turn.completed"
};

function stringValue(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 ? input : undefined;
}

function toolName(input: CodexHook): string | undefined {
  const toolInput = input.tool_input;
  if (toolInput && typeof toolInput === "object" && "name" in toolInput) {
    return stringValue((toolInput as Record<string, unknown>).name);
  }
  return stringValue(input.tool_name) ?? stringValue(input.tool);
}

export function summarizeToolInput(input: unknown): Record<string, unknown> | undefined {
  if (!input || typeof input !== "object") return undefined;
  const value = input as Record<string, unknown>;
  const command = stringValue(value.command);
  const filePath = stringValue(value.file_path) ?? stringValue(value.path);
  return {
    name: stringValue(value.name),
    command_present: Boolean(command),
    command_length: command?.length,
    file_path: filePath,
    keys: Object.keys(value).sort()
  };
}

export function normalize(input: unknown): SkyBridgeEvent[] {
  if (!input || typeof input !== "object") return [];
  const event = input as CodexHook;
  const hookEventName = stringValue(event.hook_event_name) ?? stringValue(event.event) ?? "Unknown";
  const type = hookEventTypes[hookEventName] ?? "agent.idle";
  const runId = stringValue(event.run_id) ?? stringValue(event.conversation_id) ?? stringValue(event.session_id);

  return [
    createEvent({
      type,
      severity: type === "approval.requested" ? "warning" : "info",
      source: {
        platform: "codex",
        adapter: "codex-hook",
        node_id: stringValue(event.node_id) ?? process.env.SKYBRIDGE_NODE_ID,
        agent_id: "codex-cli",
        cwd: stringValue(event.cwd)
      },
      correlation: {
        session_id: stringValue(event.session_id),
        run_id: runId,
        turn_id: stringValue(event.turn_id),
        tool_call_id: stringValue(event.tool_use_id) ?? stringValue(event.tool_call_id)
      },
      payload: {
        hook_event_name: hookEventName,
        tool_name: toolName(event),
        permission_mode: stringValue(event.permission_mode),
        tool_input_summary: summarizeToolInput(event.tool_input),
        redaction: "command/stdout/stderr omitted by default"
      }
    })
  ];
}
