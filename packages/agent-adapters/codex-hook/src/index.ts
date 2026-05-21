import { createEvent, type SkyBridgeEvent, type SkyBridgeEventInput, type SkyBridgeEventType } from "@skybridge-agent-hub/event-schema";

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

function numberValue(input: unknown): number | undefined {
  return typeof input === "number" && Number.isFinite(input) ? input : undefined;
}

function booleanValue(input: unknown): boolean | undefined {
  return typeof input === "boolean" ? input : undefined;
}

function toolName(input: CodexHook): string | undefined {
  const toolInput = input.tool_input;
  if (toolInput && typeof toolInput === "object" && "name" in toolInput) {
    return stringValue((toolInput as Record<string, unknown>).name);
  }
  return stringValue(input.tool_name) ?? stringValue(input.tool);
}

const secretKeyPattern = /authorization|api[_-]?key|token|password|passwd|secret|cookie|credential/i;
const bearerPattern = /\bBearer\s+[A-Za-z0-9._~+/=-]+/gi;
const assignmentSecretPattern = /\b([A-Za-z0-9_.-]*(?:token|password|passwd|secret|api[_-]?key)[A-Za-z0-9_.-]*)\s*[:=]\s*([^\s;&|]+)/gi;
const maxStringLength = 160;
const maxKeys = 24;
const maxDepth = 4;

export function redactString(input: string, maxLength = maxStringLength): string {
  let redacted = input
    .replace(bearerPattern, "Bearer [REDACTED]")
    .replace(assignmentSecretPattern, "$1=[REDACTED]");
  if (redacted.length > maxLength) redacted = `${redacted.slice(0, maxLength)}...[truncated ${redacted.length - maxLength} chars]`;
  return redacted;
}

export function redactUnknown(input: unknown, depth = 0): unknown {
  if (input === null || input === undefined) return input;
  if (typeof input === "string") return redactString(input);
  if (typeof input === "number" || typeof input === "boolean") return input;
  if (Array.isArray(input)) {
    if (depth >= maxDepth) return { bounded: true, type: "array", length: input.length };
    return input.slice(0, maxKeys).map((item) => redactUnknown(item, depth + 1));
  }
  if (typeof input === "object") {
    const entries = Object.entries(input as Record<string, unknown>).slice(0, maxKeys);
    const output: Record<string, unknown> = {};
    for (const [key, value] of entries) {
      output[key] = secretKeyPattern.test(key) ? "[REDACTED]" : depth >= maxDepth ? summarizeUnknown(value) : redactUnknown(value, depth + 1);
    }
    const keyCount = Object.keys(input as Record<string, unknown>).length;
    if (keyCount > maxKeys) output.__truncated_keys = keyCount - maxKeys;
    return output;
  }
  return String(input);
}

function summarizeUnknown(input: unknown): Record<string, unknown> {
  if (Array.isArray(input)) return { bounded: true, type: "array", length: input.length };
  if (input && typeof input === "object") return { bounded: true, type: "object", keys: Object.keys(input as Record<string, unknown>).slice(0, maxKeys) };
  if (typeof input === "string") return { bounded: true, type: "string", length: input.length, preview: redactString(input, 80) };
  return { bounded: true, type: typeof input };
}

export function summarizeToolInput(input: unknown): Record<string, unknown> | undefined {
  if (!input || typeof input !== "object") return undefined;
  const value = input as Record<string, unknown>;
  const command = stringValue(value.command);
  const filePath = stringValue(value.file_path) ?? stringValue(value.path);
  const content = stringValue(value.content) ?? stringValue(value.patch);
  return {
    name: stringValue(value.name),
    command_present: Boolean(command),
    command_length: command?.length,
    command_preview: command ? redactString(command, 120) : undefined,
    file_path: filePath ? redactString(filePath, 160) : undefined,
    content_present: Boolean(content),
    content_length: content?.length,
    keys: Object.keys(value).sort().slice(0, maxKeys),
    bounded_payload: redactToolObject(value)
  };
}

function redactToolObject(value: Record<string, unknown>): Record<string, unknown> {
  const output: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value).slice(0, maxKeys)) {
    if (/command|stdout|stderr|output|content|patch|prompt/i.test(key)) {
      output[key] = summarizeSensitiveValue(item);
    } else {
      output[key] = secretKeyPattern.test(key) ? "[REDACTED]" : redactUnknown(item, 1);
    }
  }
  const keyCount = Object.keys(value).length;
  if (keyCount > maxKeys) output.__truncated_keys = keyCount - maxKeys;
  return output;
}

function summarizeSensitiveValue(input: unknown): Record<string, unknown> {
  if (typeof input === "string") return { bounded: true, type: "string", length: input.length };
  if (Array.isArray(input)) return { bounded: true, type: "array", length: input.length };
  if (input && typeof input === "object") return { bounded: true, type: "object", keys: Object.keys(input as Record<string, unknown>).slice(0, maxKeys) };
  return { bounded: true, type: typeof input };
}

function summarizeOutput(input: unknown): Record<string, unknown> | undefined {
  const text = stringValue(input);
  if (!text) return undefined;
  return {
    present: true,
    length: text.length,
    line_count: text.split(/\r?\n/).length,
    preview: redactString(text, 120)
  };
}

function exitCode(input: CodexHook): number | undefined {
  return numberValue(input.exit_code) ?? numberValue(input.status_code) ?? numberValue((input.tool_response as Record<string, unknown> | undefined)?.exit_code);
}

function toolFailed(input: CodexHook): boolean {
  const code = exitCode(input);
  return booleanValue(input.is_error) === true || booleanValue(input.error) === true || (typeof code === "number" && code !== 0);
}

function sourcePayload(event: CodexHook) {
  return {
    platform: "codex" as const,
    adapter: "codex-hook",
    node_id: stringValue(event.node_id) ?? process.env.SKYBRIDGE_NODE_ID,
    agent_id: "codex-cli",
    cwd: stringValue(event.cwd)
  };
}

function correlationPayload(event: CodexHook) {
  const runId = stringValue(event.run_id) ?? stringValue(event.conversation_id) ?? stringValue(event.session_id);
  return {
    session_id: stringValue(event.session_id),
    run_id: runId,
    turn_id: stringValue(event.turn_id) ?? stringValue(event.request_id),
    tool_call_id: stringValue(event.tool_use_id) ?? stringValue(event.tool_call_id)
  };
}

export function normalize(input: unknown): SkyBridgeEvent[] {
  if (!input || typeof input !== "object") return [];
  const event = input as CodexHook;
  const hookEventName = stringValue(event.hook_event_name) ?? stringValue(event.event) ?? "Unknown";
  const type = hookEventName === "PostToolUse" && toolFailed(event) ? "tool.failed" : hookEventTypes[hookEventName] ?? "agent.idle";
  const severity = type === "approval.requested" ? "warning" : type === "tool.failed" ? "error" : "info";
  const base: Pick<SkyBridgeEventInput, "source" | "correlation"> = {
    source: sourcePayload(event),
    correlation: correlationPayload(event)
  };
  const safePayload = {
    hook_event_name: hookEventName,
    session_start_type: stringValue(event.session_start_type) ?? stringValue(event.source),
    tool_name: toolName(event),
    permission_mode: stringValue(event.permission_mode),
    exit_code: exitCode(event),
    stdout_summary: summarizeOutput(event.stdout ?? (event.tool_response as Record<string, unknown> | undefined)?.stdout),
    stderr_summary: summarizeOutput(event.stderr ?? (event.tool_response as Record<string, unknown> | undefined)?.stderr),
    tool_input_summary: summarizeToolInput(event.tool_input),
    message_summary: summarizeOutput(event.prompt ?? event.message),
    redaction: "commands, prompts, stdout and stderr are redacted and bounded by default"
  };

  const events = [
    createEvent({
      type,
      severity,
      ...base,
      payload: safePayload
    })
  ];

  if (toolName(event)?.toLowerCase() === "apply_patch") {
    const patchPath = patchFilePath(event.tool_input);
    events.push(createEvent({
      type: "file.edited",
      severity: "info",
      ...base,
      payload: { hook_event_name: hookEventName, file_path: patchPath, redaction: "patch content omitted by default" }
    }));
    events.push(createEvent({
      type: "diff.updated",
      severity: "info",
      ...base,
      payload: { hook_event_name: hookEventName, file_path: patchPath, diff_present: true, redaction: "diff content omitted by default" }
    }));
  }

  return events;
}

function patchFilePath(input: unknown): string | undefined {
  if (!input || typeof input !== "object") return undefined;
  const value = input as Record<string, unknown>;
  return stringValue(value.file_path) ?? stringValue(value.path);
}
