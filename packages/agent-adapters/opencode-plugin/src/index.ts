import { createEvent, type SkyBridgeEvent, type SkyBridgeEventType } from "@skybridge-agent-hub/event-schema";

const typeMap: Record<string, SkyBridgeEventType> = {
  "session:start": "session.started",
  "session:end": "session.completed",
  "session:idle": "agent.idle",
  "run:start": "run.started",
  "run:status": "run.started",
  "run:done": "run.completed",
  "run:error": "run.failed",
  "tool:start": "tool.started",
  "tool:end": "tool.completed",
  "tool:error": "tool.failed",
  "file:edited": "file.edited",
  "approval:request": "approval.requested",
  "approval:reply": "approval.resolved",
  "todo:update": "todo.updated",
  "message": "message.completed",
  "error": "agent.error"
};

export function normalize(input: unknown): SkyBridgeEvent[] {
  if (!input || typeof input !== "object") return [];
  const event = input as Record<string, unknown>;
  const rawType = firstString(event.type, event.event, event.name) ?? "message";
  const status = firstString(event.status, event.state);
  const normalizedType = normalizeType(rawType, status);
  const severity = normalizedType === "run.failed" || normalizedType === "tool.failed" || normalizedType === "agent.error"
    ? "error"
    : normalizedType === "approval.requested"
      ? "warning"
      : "info";
  return [
    createEvent({
      type: normalizedType,
      severity,
      source: {
        platform: "opencode",
        adapter: "opencode-plugin",
        agent_id: firstString(event.agent, event.agentId) ?? "opencode",
        node_id: firstString(event.nodeId, event.node_id),
        cwd: safePath(firstString(event.cwd, event.workspace))
      },
      correlation: {
        session_id: firstString(event.sessionId, event.session_id),
        run_id: firstString(event.runId, event.run_id, event.id),
        tool_call_id: firstString(event.toolCallId, event.tool_call_id, event.toolId)
      },
      payload: {
        raw_type: rawType,
        status,
        title: boundedString(firstString(event.title, event.name), 120),
        summary: boundedString(firstString(event.summary, event.message), 180),
        tool_name: boundedString(firstString(event.tool, event.toolName, event.tool_name), 80),
        file_path: safePath(firstString(event.path, event.file, event.filePath)),
        permission: boundedString(firstString(event.permission, event.action), 80),
        decision: boundedString(firstString(event.decision, event.reply), 40),
        todo_counts: todoCounts(event.todos),
        redaction: "adapter omits raw prompts, command output and file contents"
      }
    })
  ];
}

function normalizeType(rawType: string, status: string | undefined): SkyBridgeEventType {
  if (rawType === "run:status") {
    if (status === "idle") return "agent.idle";
    if (status === "error" || status === "failed") return "run.failed";
    if (status === "done" || status === "completed") return "run.completed";
  }
  return typeMap[rawType] ?? "message.completed";
}

function firstString(...values: unknown[]): string | undefined {
  return values.find((value): value is string => typeof value === "string" && value.length > 0);
}

function boundedString(value: string | undefined, max: number): string | undefined {
  if (!value) return undefined;
  return value.length > max ? `${value.slice(0, max)}...` : redactSecrets(value);
}

function safePath(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const redacted = redactSecrets(value);
  return redacted.replace(/[A-Za-z]:\\Users\\[^\\]+/g, "[USER_HOME]").slice(0, 180);
}

function redactSecrets(value: string): string {
  return value
    .replace(/(sk-[A-Za-z0-9_-]{12,})/g, "[REDACTED]")
    .replace(/(Bearer\s+)[A-Za-z0-9._-]+/gi, "$1[REDACTED]")
    .replace(/(token|password|secret|cookie)=\S+/gi, "$1=[REDACTED]");
}

function todoCounts(value: unknown): { total: number; completed: number } | undefined {
  if (!Array.isArray(value)) return undefined;
  return {
    total: value.length,
    completed: value.filter((item) => item && typeof item === "object" && (item as Record<string, unknown>).done === true).length
  };
}
