import { z } from "zod";

export const SKYBRIDGE_EVENT_SCHEMA_VERSION = "skybridge.agent_event.v1" as const;

export const SkyBridgeEventTypeSchema = z.enum([
  "session.started",
  "session.completed",
  "run.started",
  "run.completed",
  "run.failed",
  "turn.started",
  "turn.completed",
  "plan.updated",
  "todo.updated",
  "tool.started",
  "tool.completed",
  "tool.failed",
  "file.edited",
  "diff.updated",
  "approval.requested",
  "approval.resolved",
  "approval.denied",
  "approval.expired",
  "message.delta",
  "message.completed",
  "agent.idle",
  "agent.error",
  "agent.stale",
  "node.connected",
  "node.heartbeat",
  "node.disconnected",
  "notification.requested",
  "notification.sent",
  "notification.skipped",
  "notification.failed"
]);

export const SkyBridgeSeveritySchema = z.enum(["debug", "info", "warning", "error", "critical"]);
export const SkyBridgeSourcePlatformSchema = z.enum(["codex", "opencode", "hermes", "skybridge", "custom"]);

export const SkyBridgeSourceSchema = z.object({
  platform: SkyBridgeSourcePlatformSchema,
  adapter: z.string().min(1),
  node_id: z.string().optional(),
  agent_id: z.string().optional(),
  cwd: z.string().optional()
});

export const SkyBridgeCorrelationSchema = z.object({
  session_id: z.string().optional(),
  run_id: z.string().optional(),
  turn_id: z.string().optional(),
  step_id: z.string().optional(),
  tool_call_id: z.string().optional()
});

export const SkyBridgeEventSchema = z.object({
  schema: z.literal(SKYBRIDGE_EVENT_SCHEMA_VERSION).default(SKYBRIDGE_EVENT_SCHEMA_VERSION),
  event_id: z.string().optional(),
  time: z.string().datetime(),
  type: SkyBridgeEventTypeSchema,
  severity: SkyBridgeSeveritySchema.default("info"),
  source: SkyBridgeSourceSchema,
  correlation: SkyBridgeCorrelationSchema.optional(),
  payload: z.record(z.unknown()).default({})
});

export type SkyBridgeEventType = z.infer<typeof SkyBridgeEventTypeSchema>;
export type SkyBridgeSeverity = z.infer<typeof SkyBridgeSeveritySchema>;
export type SkyBridgeSourcePlatform = z.infer<typeof SkyBridgeSourcePlatformSchema>;
export type SkyBridgeSource = z.infer<typeof SkyBridgeSourceSchema>;
export type SkyBridgeCorrelation = z.infer<typeof SkyBridgeCorrelationSchema>;
export type SkyBridgeEvent = z.infer<typeof SkyBridgeEventSchema>;
export type SkyBridgeEventInput = {
  event_id?: string;
  time?: string;
  type: SkyBridgeEventType;
  severity?: SkyBridgeSeverity;
  source: SkyBridgeSource;
  correlation?: SkyBridgeCorrelation;
  payload?: Record<string, unknown>;
};

export interface RunSummary {
  run_id: string;
  session_id?: string;
  source_platform: SkyBridgeSourcePlatform;
  source_adapter: string;
  source_agent_id?: string;
  source_node_id?: string;
  status: "running" | "completed" | "failed" | "unknown";
  event_count: number;
  tool_call_count: number;
  active_tool_count: number;
  failed_tool_count: number;
  notification_count: number;
  first_seen_at: string;
  last_seen_at: string;
  last_event_type: SkyBridgeEventType;
  title?: string;
  lifecycle?: string;
  branch?: string;
  cwd?: string;
  goal?: string;
  goal_id?: string;
  latest_message_summary?: string;
}

export interface RunDetail {
  summary: RunSummary;
  events: SkyBridgeEvent[];
}

export interface SourceCapability {
  platform: SkyBridgeSourcePlatform;
  label: string;
  adapters: string[];
  event_families: string[];
  supports_remote_control: boolean;
  default_safe: boolean;
  notes: string;
}

export const SOURCE_CAPABILITIES: SourceCapability[] = [
  {
    platform: "codex",
    label: "Codex",
    adapters: ["codex-hook", "codex-exec-json", "codex-appserver"],
    event_families: ["session", "run", "turn", "tool", "file", "diff", "approval", "message", "agent", "notification"],
    supports_remote_control: false,
    default_safe: true,
    notes: "Local hook and exec telemetry with command, prompt and output redaction by default."
  },
  {
    platform: "opencode",
    label: "OpenCode",
    adapters: ["opencode-plugin"],
    event_families: ["session", "run", "tool", "file", "approval", "todo", "message", "agent"],
    supports_remote_control: false,
    default_safe: true,
    notes: "Plugin event telemetry normalized from status, tool, file, permission and todo events."
  },
  {
    platform: "hermes",
    label: "Hermes Agent",
    adapters: ["hermes-api"],
    event_families: ["run", "tool", "message", "agent"],
    supports_remote_control: false,
    default_safe: true,
    notes: "API and stream event telemetry normalized from run status and event stream samples."
  },
  {
    platform: "skybridge",
    label: "SkyBridge",
    adapters: ["yolo-runner", "self-observation-smoke", "demo-dataset", "sidecar"],
    event_families: ["run", "tool", "notification", "agent", "node", "approval"],
    supports_remote_control: false,
    default_safe: true,
    notes: "First-party runner, smoke, node and dogfooding telemetry."
  },
  {
    platform: "custom",
    label: "Custom Agent",
    adapters: ["custom"],
    event_families: ["session", "run", "turn", "tool", "file", "diff", "approval", "message", "agent", "notification"],
    supports_remote_control: false,
    default_safe: false,
    notes: "Bring-your-own adapter; events must be normalized and redacted before ingestion."
  }
];

export function createEvent(input: SkyBridgeEventInput): SkyBridgeEvent {
  return SkyBridgeEventSchema.parse({
    schema: SKYBRIDGE_EVENT_SCHEMA_VERSION,
    time: input.time ?? new Date().toISOString(),
    ...input
  });
}

export function parseEvent(input: unknown): SkyBridgeEvent {
  return SkyBridgeEventSchema.parse(input);
}

export function isNotificationTrigger(event: Pick<SkyBridgeEvent, "type">): boolean {
  return event.type === "run.failed" || event.type === "approval.requested" || event.type === "notification.requested";
}
