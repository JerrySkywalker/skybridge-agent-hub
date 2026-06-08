import type {
  AdapterCapability,
  AdapterRole,
  EvidenceSummary,
  IterationRun,
  MasterGoal,
  Project,
  RunDetail,
  RunSummary,
  SkyBridgeEvent,
  SkyBridgeEventType,
  SkyBridgeSeverity,
  SkyBridgeSourcePlatform,
  SourceCapability,
  Task,
  TaskEvent,
  PlannerAdapterMetadata,
  GoalPriority,
  GoalRisk,
  ProjectControlState,
  TaskRisk,
  TaskSource,
  TaskStatus,
  Worker,
  WorkerCapability,
} from "@skybridge-agent-hub/event-schema";

export interface NotificationRequest {
  title: string;
  body: string;
  priority?: "low" | "default" | "high" | "urgent";
  url?: string;
}

export interface SkyBridgeHealth {
  ok: boolean;
  service: string;
  persistence: "memory" | "sqlite";
  dbFile?: string;
  jsonMigrationFile?: string;
  time: string;
}

export interface StoredNotification {
  id: string;
  category?: string;
  severity?: string;
  source_event_id?: string;
  target?: string;
  provider:
    | "ntfy"
    | "apprise"
    | "gotify"
    | "bark"
    | "wecom"
    | "fcm"
    | "xiaomi-push"
    | "placeholder";
  dedupe_key?: string;
  status: "pending" | "sent" | "skipped" | "failed";
  retry_count?: number;
  message: NotificationRequest;
  createdAt: string;
  updatedAt?: string;
  error?: string;
}

export interface SummaryResponse {
  health: SkyBridgeHealth;
  totals: {
    events: number;
    runs: number;
    active_runs: number;
    failed_runs: number;
    open_prs?: number;
    ci_failed?: number;
    notifications: number;
    notification_failed?: number;
    notification_skipped?: number;
    nodes?: number;
    node_stale?: number;
    workers?: number;
    workers_online?: number;
    workers_stale?: number;
    workers_offline?: number;
    tasks?: number;
    tasks_queued?: number;
    tasks_running?: number;
    tasks_completed?: number;
    tasks_failed?: number;
    tasks_blocked?: number;
    active_goals?: number;
    automerge_blocked?: number;
    attention_items: number;
  };
  latest?: {
    ci_state?: string;
    automerge_sweep?: AutoMergeSummary["latest_sweep"];
    iteration?: IterationRun;
    hermes_status?: string;
    notification?: StoredNotification;
    failure?: RunSummary;
    active_goal?: MasterGoal;
    latest_task_event?: TaskEvent;
    next_recommended_action?: string;
  };
  recent_failures?: RunSummary[];
  sources: Array<{
    platform: string;
    adapter: string;
    event_count: number;
    latest_event_at: string;
  }>;
}

export interface ProjectSummary {
  project_id: string;
  name?: string;
  repo?: string;
  description?: string;
  status?: string;
  control_state?: ProjectControlState;
  run_count: number;
  active_runs: number;
  failed_runs: number;
  iteration_count: number;
  goal_count?: number;
  latest_activity_at?: string;
}

export type WorkerRecord = Worker;
export type ProjectRecord = Project;
export type ProjectControlRecord = ProjectControlState;
export interface GoalTaskSummary {
  total: number;
  queued: number;
  claimed: number;
  running: number;
  completed: number;
  failed: number;
  blocked: number;
  cancelled: number;
  stale: number;
  evidence_count: number;
  latest_evidence?: EvidenceSummary;
}

export type GoalRecord = MasterGoal & { task_summary?: GoalTaskSummary };
export type TaskRecord = Task & {
  events?: TaskEvent[];
  last_event?: TaskEvent;
};

export interface WorkerSummary {
  total: number;
  online: number;
  stale: number;
  offline: number;
  disabled: number;
  workers: WorkerRecord[];
}

export interface TaskSummary {
  total: number;
  queued: number;
  claimed: number;
  running: number;
  completed: number;
  failed: number;
  blocked: number;
  cancelled: number;
  stale: number;
  latest_event?: TaskEvent;
}

export interface IterationsSummary {
  total: number;
  active: number;
  blocked: number;
  failed: number;
  repair_attempts: number;
  latest?: IterationRun;
  recent: Array<
    IterationRun & {
      blocked_reason?: string;
      repair_attempts: number;
      raw_logs_included: false;
    }
  >;
}

export interface PrSummaryItem {
  pr_number: number;
  branch?: string;
  repo?: string;
  state: "open" | "merged" | "blocked" | "unknown";
  ci_state: string;
  required_checks: Array<{ name: string; status: string; summary?: string }>;
  eligibility: "eligible" | "blocked" | "pending" | "unknown";
  risk: "low" | "needs_review" | "blocked" | "unknown";
  reasons: string[];
  updated_at: string;
}

export interface PrsSummary {
  total: number;
  open: number;
  merged: number;
  blocked: number;
  eligible: number;
  ci_failed: number;
  latest_ci_state: string;
  prs: PrSummaryItem[];
}

export interface NotificationsSummary {
  total: number;
  sent: number;
  skipped: number;
  failed: number;
  pending: number;
  by_severity: Record<string, number>;
  providers: Array<{
    provider: string;
    configured: boolean;
    status: string;
    required_env: string;
    credential_values_exposed: boolean;
  }>;
  bootstrap_fallback: {
    status: string;
    script: string;
    real_send_requires_explicit_send: boolean;
  };
  latest?: StoredNotification;
  recent: StoredNotification[];
}

export interface HermesSummary {
  status: "available" | "degraded" | "placeholder";
  tunnel: { status: string; public_exposure: false };
  api: { health: string; base_publicly_exposed: false };
  capabilities: string[];
  last_safe_run?: { event_id: string; run_id?: string; time: string };
  nightly_report?: { event_id: string; time: string; summary: string };
  sweep_dry_run?: { event_id: string; time: string; summary: string };
  degraded_reason?: string;
  related_iterations: IterationRun[];
}

export interface AutoMergeSummary {
  enabled_by_default: false;
  dry_run_default: true;
  total_prs: number;
  eligible: number;
  blocked: number;
  pending: number;
  merged_history: AuditEntry[];
  latest_sweep?: {
    event_id: string;
    time: string;
    mode: string;
    dry_run: boolean;
    summary?: string;
    eligible?: number;
    blocked?: number;
  };
  decisions: Array<{
    pr_number: number;
    eligibility: PrSummaryItem["eligibility"];
    risk: PrSummaryItem["risk"];
    reasons: string[];
    required_checks: PrSummaryItem["required_checks"];
  }>;
}

export interface NodeSummary {
  node_id: string;
  host?: string;
  labels: string[];
  capabilities: string[];
  sidecar_version?: string;
  last_seen: string;
  status: "connected" | "stale" | "disconnected";
  event_count: number;
}

export interface ApprovalSummary {
  approval_id: string;
  run_id?: string;
  session_id?: string;
  status: "pending" | "accepted" | "denied" | "expired";
  title?: string;
  requested_at: string;
  resolved_at?: string;
  source: string;
}

export interface MetricsResponse {
  total_events: number;
  runs_by_status: Record<string, number>;
  runs_by_source: Record<string, number>;
  notifications_by_status: Record<string, number>;
  notifications_by_severity: Record<string, number>;
  node_status_counts: Record<string, number>;
  recent_failures: RunSummary[];
}

export interface AuditEntry {
  audit_id: string;
  time: string;
  action: string;
  actor: string;
  source_adapter: string;
  run_id?: string;
  session_id?: string;
  safety_decision: string;
  immutable_event_id: string;
  redaction_policy_version: string;
  raw_payload_included: false;
}

export interface StreamEventsOptions {
  onEvent: (event: SkyBridgeEvent) => void;
  onOpen?: () => void;
  onError?: (error: Event) => void;
}

export class SkyBridgeClient {
  constructor(private readonly apiBase: string) {}

  async getHealth(): Promise<SkyBridgeHealth> {
    return this.getJson<SkyBridgeHealth>("/v1/health");
  }

  async sendEvent(event: SkyBridgeEvent): Promise<{ ok: boolean; id: string }> {
    const response = await fetch(this.url("/v1/events"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(event),
    });
    await assertOk(response, "event ingest");
    return response.json() as Promise<{ ok: boolean; id: string }>;
  }

  async listEvents(query: EventListQuery = {}): Promise<SkyBridgeEvent[]> {
    const json = await this.getJson<{ events: SkyBridgeEvent[] }>(
      `/v1/events${queryString(query)}`,
    );
    return json.events;
  }

  async listRuns(query: RunListQuery = {}): Promise<RunSummary[]> {
    const json = await this.getJson<{ runs: RunSummary[] }>(
      `/v1/runs${queryString(query)}`,
    );
    return json.runs;
  }

  async getRun(
    runId: string,
    query: { limit?: number } = {},
  ): Promise<RunDetail> {
    return this.getJson<RunDetail>(
      `/v1/runs/${encodeURIComponent(runId)}${queryString(query)}`,
    );
  }

  async listNotifications(
    query: NotificationListQuery = {},
  ): Promise<StoredNotification[]> {
    const json = await this.getJson<{ notifications: StoredNotification[] }>(
      `/v1/notifications${queryString(query)}`,
    );
    return json.notifications;
  }

  async getSummary(): Promise<SummaryResponse> {
    return this.getJson<SummaryResponse>("/v1/summary");
  }

  async registerWorker(input: {
    worker_id?: string;
    name: string;
    provider?: string;
    capabilities?: WorkerCapability[];
    labels?: string[];
    enabled?: boolean;
  }): Promise<WorkerRecord> {
    const response = await fetch(this.url("/v1/workers/register"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(input),
    });
    await assertOk(response, "worker register");
    return ((await response.json()) as { worker: WorkerRecord }).worker;
  }

  async sendWorkerHeartbeat(
    workerId: string,
    input: { status_note?: string; load?: number } = {},
  ): Promise<WorkerRecord> {
    const response = await fetch(
      this.url(`/v1/workers/${encodeURIComponent(workerId)}/heartbeat`),
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(input),
      },
    );
    await assertOk(response, "worker heartbeat");
    return ((await response.json()) as { worker: WorkerRecord }).worker;
  }

  async listWorkers(): Promise<WorkerRecord[]> {
    const json = await this.getJson<{ workers: WorkerRecord[] }>("/v1/workers");
    return json.workers;
  }

  async getWorker(workerId: string): Promise<WorkerRecord> {
    const json = await this.getJson<{ worker: WorkerRecord }>(
      `/v1/workers/${encodeURIComponent(workerId)}`,
    );
    return json.worker;
  }

  async updateWorker(
    workerId: string,
    input: {
      name?: string;
      enabled?: boolean;
      labels?: string[];
      capabilities?: WorkerCapability[];
    },
  ): Promise<WorkerRecord> {
    const response = await fetch(
      this.url(`/v1/workers/${encodeURIComponent(workerId)}`),
      {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(input),
      },
    );
    await assertOk(response, "worker update");
    return ((await response.json()) as { worker: WorkerRecord }).worker;
  }

  async getWorkersSummary(): Promise<WorkerSummary> {
    return this.getJson<WorkerSummary>("/v1/workers/summary");
  }

  async listProjects(): Promise<ProjectSummary[]> {
    const json = await this.getJson<{ projects: ProjectSummary[] }>(
      "/v1/projects",
    );
    return json.projects;
  }

  async createProject(input: {
    project_id?: string;
    name: string;
    repo?: string;
    description?: string;
    status?: Project["status"];
  }): Promise<ProjectRecord> {
    const response = await fetch(this.url("/v1/projects"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(input),
    });
    await assertOk(response, "project create");
    return ((await response.json()) as { project: ProjectRecord }).project;
  }

  async getProject(projectId: string): Promise<ProjectRecord> {
    const json = await this.getJson<{ project: ProjectRecord }>(
      `/v1/projects/${encodeURIComponent(projectId)}`,
    );
    return json.project;
  }

  async getProjectControl(projectId: string): Promise<ProjectControlRecord> {
    const json = await this.getJson<{ control_state: ProjectControlRecord }>(
      `/v1/projects/${encodeURIComponent(projectId)}/control`,
    );
    return json.control_state;
  }

  async updateProjectControl(
    projectId: string,
    input: Partial<ProjectControlRecord>,
  ): Promise<ProjectControlRecord> {
    const response = await fetch(
      this.url(`/v1/projects/${encodeURIComponent(projectId)}/control`),
      {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(input),
      },
    );
    await assertOk(response, "project control update");
    return ((await response.json()) as { control_state: ProjectControlRecord })
      .control_state;
  }

  async createGoal(
    projectId: string,
    input: {
      goal_id?: string;
      title: string;
      summary?: string;
      status?: MasterGoal["status"];
      source?: string;
      priority?: GoalPriority;
      risk?: GoalRisk;
      lifecycle?: string;
      acceptance_criteria?: string[];
      evidence_requirements?: string[];
      dedupe_key?: string;
      supersedes?: string[];
      superseded_by?: string;
      stale_reason?: string;
      blocked_reason?: string;
      planner_metadata?: PlannerAdapterMetadata;
      completion_note?: string;
      evidence_summary?: EvidenceSummary;
    },
  ): Promise<GoalRecord> {
    const response = await fetch(
      this.url(`/v1/projects/${encodeURIComponent(projectId)}/goals`),
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(input),
      },
    );
    await assertOk(response, "goal create");
    return ((await response.json()) as { goal: GoalRecord }).goal;
  }

  async listGoals(projectId: string): Promise<GoalRecord[]> {
    const json = await this.getJson<{ goals: GoalRecord[] }>(
      `/v1/projects/${encodeURIComponent(projectId)}/goals`,
    );
    return json.goals;
  }

  async getGoal(goalId: string): Promise<GoalRecord> {
    const json = await this.getJson<{ goal: GoalRecord }>(
      `/v1/goals/${encodeURIComponent(goalId)}`,
    );
    return json.goal;
  }

  async updateGoal(
    goalId: string,
    input: {
      title?: string;
      summary?: string;
      status?: MasterGoal["status"];
      source?: string;
      priority?: GoalPriority;
      risk?: GoalRisk;
      lifecycle?: string;
      acceptance_criteria?: string[];
      evidence_requirements?: string[];
      dedupe_key?: string;
      supersedes?: string[];
      superseded_by?: string;
      stale_reason?: string;
      blocked_reason?: string;
      planner_metadata?: PlannerAdapterMetadata;
      completion_note?: string;
      evidence_summary?: EvidenceSummary;
    },
  ): Promise<GoalRecord> {
    const response = await fetch(
      this.url(`/v1/goals/${encodeURIComponent(goalId)}`),
      {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(input),
      },
    );
    await assertOk(response, "goal update");
    return ((await response.json()) as { goal: GoalRecord }).goal;
  }

  async createTask(input: {
    task_id?: string;
    project_id: string;
    goal_id?: string;
    title: string;
    body?: string;
    prompt_summary?: string;
    risk?: TaskRisk;
    source?: TaskSource;
    task_type?: string;
    planner_metadata?: PlannerAdapterMetadata;
    allowed_paths?: string[];
    blocked_paths?: string[];
    validation?: string[];
    required_capabilities?: WorkerCapability[];
  }): Promise<TaskRecord> {
    const response = await fetch(this.url("/v1/tasks"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(input),
    });
    await assertOk(response, "task create");
    return ((await response.json()) as { task: TaskRecord }).task;
  }

  async listTasks(query: TaskListQuery = {}): Promise<TaskRecord[]> {
    const json = await this.getJson<{ tasks: TaskRecord[] }>(
      `/v1/tasks${queryString(query)}`,
    );
    return json.tasks;
  }

  async listProjectTasks(projectId: string): Promise<TaskRecord[]> {
    const json = await this.getJson<{ tasks: TaskRecord[] }>(
      `/v1/projects/${encodeURIComponent(projectId)}/tasks`,
    );
    return json.tasks;
  }

  async getTask(taskId: string): Promise<TaskRecord> {
    const json = await this.getJson<{ task: TaskRecord }>(
      `/v1/tasks/${encodeURIComponent(taskId)}`,
    );
    return json.task;
  }

  async claimTask(taskId: string, workerId: string): Promise<TaskRecord> {
    return this.postTaskAction(taskId, "claim", { worker_id: workerId });
  }

  async startTask(taskId: string, workerId?: string): Promise<TaskRecord> {
    return this.postTaskAction(taskId, "start", { worker_id: workerId });
  }

  async completeTask(
    taskId: string,
    input: {
      worker_id?: string;
      summary?: string;
      result_url?: string;
      pr_url?: string;
      evidence_summary?: EvidenceSummary;
    } = {},
  ): Promise<TaskRecord> {
    return this.postTaskAction(taskId, "complete", input);
  }

  async failTask(
    taskId: string,
    input: { worker_id?: string; error_summary?: string; result_url?: string } = {},
  ): Promise<TaskRecord> {
    return this.postTaskAction(taskId, "fail", input);
  }

  async requeueTask(taskId: string): Promise<TaskRecord> {
    return this.postTaskAction(taskId, "requeue", {});
  }

  async getTasksSummary(): Promise<TaskSummary> {
    return this.getJson<TaskSummary>("/v1/tasks/summary");
  }

  async getIterationsSummary(): Promise<IterationsSummary> {
    return this.getJson<IterationsSummary>("/v1/iterations/summary");
  }

  async getPrsSummary(): Promise<PrsSummary> {
    return this.getJson<PrsSummary>("/v1/prs/summary");
  }

  async getNotificationsSummary(): Promise<NotificationsSummary> {
    return this.getJson<NotificationsSummary>("/v1/notifications/summary");
  }

  async getHermesSummary(): Promise<HermesSummary> {
    return this.getJson<HermesSummary>("/v1/hermes/summary");
  }

  async getAutoMergeSummary(): Promise<AutoMergeSummary> {
    return this.getJson<AutoMergeSummary>("/v1/automerge/summary");
  }

  async listSources(): Promise<SourceCapability[]> {
    const json = await this.getJson<{ sources: SourceCapability[] }>(
      "/v1/sources",
    );
    return json.sources;
  }

  async listAdapters(role?: AdapterRole): Promise<AdapterCapability[]> {
    const json = await this.getJson<{ adapters: AdapterCapability[] }>(
      `/v1/adapters${queryString({ role })}`,
    );
    return json.adapters;
  }

  async listNodes(): Promise<NodeSummary[]> {
    const json = await this.getJson<{ nodes: NodeSummary[] }>("/v1/nodes");
    return json.nodes;
  }

  async listNotificationProviders(): Promise<
    Array<{
      provider: string;
      configured: boolean;
      status: string;
      required_env: string;
      credential_values_exposed: boolean;
    }>
  > {
    const json = await this.getJson<{
      providers: Array<{
        provider: string;
        configured: boolean;
        status: string;
        required_env: string;
        credential_values_exposed: boolean;
      }>;
    }>("/v1/notifications/providers");
    return json.providers;
  }

  async getMetrics(): Promise<MetricsResponse> {
    return this.getJson<MetricsResponse>("/v1/metrics");
  }

  async listAuditEntries(query: AuditListQuery = {}): Promise<AuditEntry[]> {
    const json = await this.getJson<{ audit: AuditEntry[] }>(
      `/v1/audit${queryString(query)}`,
    );
    return json.audit;
  }

  async listIterations(): Promise<IterationRun[]> {
    const json = await this.getJson<{ iterations: IterationRun[] }>(
      "/v1/iterations",
    );
    return json.iterations;
  }

  async getIteration(
    iterationId: string,
  ): Promise<
    IterationRun & {
      events?: Array<{
        type: string;
        time: string;
        payload: Record<string, unknown>;
      }>;
    }
  > {
    const json = await this.getJson<{
      iteration: IterationRun & {
        events?: Array<{
          type: string;
          time: string;
          payload: Record<string, unknown>;
        }>;
      };
    }>(`/v1/iterations/${encodeURIComponent(iterationId)}`);
    return json.iteration;
  }

  async getSupervisorStatus(): Promise<SupervisorStatus> {
    return this.getJson<SupervisorStatus>("/v1/supervisor/status");
  }

  async getSupervisorNextAction(): Promise<SupervisorNextAction> {
    return this.getJson<SupervisorNextAction>("/v1/supervisor/next-action");
  }

  async listApprovals(): Promise<ApprovalSummary[]> {
    const json = await this.getJson<{ approvals: ApprovalSummary[] }>(
      "/v1/approvals",
    );
    return json.approvals;
  }

  async sendNotification(
    message: NotificationRequest,
  ): Promise<{ ok: boolean; provider: string }> {
    const response = await fetch(this.url("/v1/notifications/send"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(message),
    });
    await assertOk(response, "notification request");
    return response.json() as Promise<{ ok: boolean; provider: string }>;
  }

  streamEvents(
    optionsOrHandler: StreamEventsOptions | ((event: SkyBridgeEvent) => void),
  ): EventSource {
    const options =
      typeof optionsOrHandler === "function"
        ? { onEvent: optionsOrHandler }
        : optionsOrHandler;
    const source = new EventSource(this.url("/v1/stream"));
    if (options.onOpen) source.addEventListener("open", options.onOpen);
    if (options.onError) source.addEventListener("error", options.onError);
    source.addEventListener("skybridge.event", (message) => {
      options.onEvent(
        JSON.parse((message as MessageEvent).data) as SkyBridgeEvent,
      );
    });
    return source;
  }

  private async getJson<T>(path: string): Promise<T> {
    const response = await fetch(this.url(path));
    await assertOk(response, "request");
    return response.json() as Promise<T>;
  }

  private url(path: string): string {
    return `${this.apiBase.replace(/\/$/, "")}${path}`;
  }

  private async postTaskAction(
    taskId: string,
    action: "claim" | "start" | "complete" | "fail" | "requeue",
    input: Record<string, unknown>,
  ): Promise<TaskRecord> {
    const response = await fetch(
      this.url(`/v1/tasks/${encodeURIComponent(taskId)}/${action}`),
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(input),
      },
    );
    await assertOk(response, `task ${action}`);
    return ((await response.json()) as { task: TaskRecord }).task;
  }
}

export interface EventListQuery {
  run_id?: string;
  session_id?: string;
  platform?: SkyBridgeSourcePlatform;
  adapter?: string;
  source_platform?: SkyBridgeSourcePlatform;
  source_adapter?: string;
  type?: SkyBridgeEventType;
  severity?: SkyBridgeSeverity;
  from?: string;
  to?: string;
  limit?: number;
  offset?: number;
}

export interface RunListQuery {
  platform?: SkyBridgeSourcePlatform;
  adapter?: string;
  source_platform?: SkyBridgeSourcePlatform;
  source_adapter?: string;
  status?: RunSummary["status"];
  lifecycle?: string;
  branch?: string;
  goal?: string;
  from?: string;
  to?: string;
  limit?: number;
}

export interface NotificationListQuery {
  status?: StoredNotification["status"];
  provider?: StoredNotification["provider"];
  severity?: SkyBridgeSeverity;
  limit?: number;
}

export interface TaskListQuery {
  project_id?: string;
  goal_id?: string;
  status?: TaskStatus;
}

export interface AuditListQuery {
  action?: string;
  actor?: string;
  run_id?: string;
  from?: string;
  to?: string;
  limit?: number;
}

export interface SupervisorStatus {
  ok: boolean;
  raw_prompts_included: false;
  raw_logs_included: false;
  notification_path?: {
    primary_for_skybridge_development: string;
    skybridge_notification_center_required: boolean;
    migration_stage: string;
  };
  iterations: {
    total: number;
    active: number;
    blocked: number;
    latest?: IterationRun;
  };
  recent_iteration_events: SkyBridgeEvent[];
}

export interface SupervisorNextAction {
  action: string;
  reason?: string;
  iteration_id?: string;
  pr_number?: number;
  state?: string;
}

export type CampaignEvidenceClassification =
  | "present_evidence"
  | "recovered_evidence"
  | "missing_evidence"
  | "skipped_evidence"
  | "not_applicable_evidence";

export interface CampaignStepSummary {
  campaign_step_id: string;
  goal_id: string;
  order: number;
  title: string;
  status: string;
  is_current: boolean;
  dependencies: string[];
  linked_task_ids: string[];
  linked_pr_urls: string[];
  linked_task_count: number;
  linked_pr_count: number;
  evidence_status: string;
  recovered: boolean;
  missing_evidence: boolean;
  skipped_evidence: boolean;
  not_applicable_evidence: boolean;
  operator_action_required: boolean;
}

export interface CampaignEvidenceEntry {
  kind: "step" | "task" | "pr" | "ci" | "finalizer" | "gate" | string;
  campaign_step_id: string;
  goal_id: string;
  evidence_id: string;
  status: string;
  classification: CampaignEvidenceClassification | string;
  recovered: boolean;
  missing: boolean;
  skipped: boolean;
  not_applicable: boolean;
  operator_action_required: boolean;
  summary: string;
}

export interface CampaignQueueControlReadiness {
  can_start_one: boolean;
  can_start_queue: boolean;
  can_pause: boolean;
  can_stop: boolean;
  can_emergency_stop: boolean;
  can_resume: boolean;
  blockers: string[];
  warnings: string[];
  required_human_action: string[];
  next_safe_action: string;
  worker_required: boolean;
  worker_status: string;
  run_budget_required: boolean;
  reason_required: boolean;
  worker_service_state?: WorkerServiceState;
  execution_disabled_until_goal?: string;
  campaign_lock?: CampaignLock;
  repo_exclusive_lock?: RepoExclusiveLock;
  priority_queue?: CampaignPriorityQueue;
  routing_readiness?: WorkerRoutingReadinessDetail;
}

export type WorkerOs = "windows" | "linux" | "macos" | "unknown";
export type WorkerTool = "codex" | "git" | "node" | "pnpm" | "rust" | "docker" | "powershell" | "bash";
export type WorkerReadinessState = "online" | "offline" | "stale" | "disabled" | "busy" | "unknown";

export interface WorkerCapabilityMatrixEntry {
  schema: "skybridge.worker_capability_matrix_entry.v1";
  worker_id: string;
  worker_label: string;
  worker_profile: string;
  os: WorkerOs;
  tools: WorkerTool[];
  task_type_capabilities: string[];
  project_access: string[];
  repo_access: string[];
  can_run_local_smokes: boolean;
  can_run_frontend: boolean;
  can_run_backend: boolean;
  can_run_docs: boolean;
  can_run_worker_service: boolean;
  can_claim_tasks: false;
  can_execute_tasks: false;
  token_printed: false;
}

export interface WorkerReadinessEntry {
  schema: "skybridge.worker_readiness_entry.v1";
  worker_id: string;
  worker_label: string;
  readiness_state: WorkerReadinessState;
  heartbeat_age_seconds: number | null;
  current_task_id: string | null;
  service_mode: string;
  readiness_score: number;
  readiness_blockers: string[];
  readiness_warnings: string[];
  recommended_action: string;
  capability_matrix: WorkerCapabilityMatrixEntry;
  token_printed: false;
}

export interface WorkerRouteTaskPreview {
  task_id: string;
  task_type: string;
  project_id: string;
  repo_id: string;
  required_os: WorkerOs | null;
  required_tools: WorkerTool[];
  required_capabilities: string[];
  token_printed: false;
}

export interface WorkerRouteDecision {
  worker_id: string;
  worker_label: string;
  accepted: boolean;
  readiness_score: number;
  rejection_reasons: string[];
  warnings: string[];
  token_printed: false;
}

export interface WorkerRoutingPolicy {
  schema: "skybridge.worker_routing_policy.v1";
  default_mode: "preview";
  max_parallel_per_repo: 1;
  reject_offline_workers: true;
  reject_stale_workers: true;
  reject_disabled_workers: true;
  reject_busy_workers: true;
  require_capability_match: true;
  require_project_access: true;
  require_repo_access: true;
  require_os_tool_match: true;
  repo_lock_blocks_preview: true;
  stale_repo_lock_requires_recovery_first: true;
  can_claim_tasks: false;
  can_execute_tasks: false;
  token_printed: false;
}

export interface WorkerRoutePreview {
  schema: "skybridge.worker_route_preview.v1";
  mode: "preview";
  task: WorkerRouteTaskPreview;
  selected_worker: WorkerRouteDecision | null;
  rejected_workers: WorkerRouteDecision[];
  decisions: WorkerRouteDecision[];
  policy: WorkerRoutingPolicy;
  repo_parallelism_guard: {
    repo_id: string;
    max_parallel_per_repo: 1;
    active_mutating_workers: number;
    repo_lock_status: LockStatus | "none";
    blocked: boolean;
    blocker: string | null;
    token_printed: false;
  };
  task_created: false;
  task_claimed: false;
  task_executed: false;
  worker_loop_started: false;
  queue_execution_enabled: false;
  token_printed: false;
}

export interface WorkerRoutingReadinessDetail {
  schema: "skybridge.worker_routing_readiness_detail.v1";
  worker_pool_counts: {
    total: number;
    online: number;
    stale: number;
    offline: number;
    disabled: number;
    busy: number;
    preview_candidates: number;
  };
  worker_capability_matrix: WorkerCapabilityMatrixEntry[];
  worker_readiness: WorkerReadinessEntry[];
  route_preview: WorkerRoutePreview;
  selected_worker_ready_for_preview_only: boolean;
  execution_enabled: false;
  can_start_one: false;
  can_start_queue: false;
  token_printed: false;
}

export type WorkerServiceMode = "offline" | "standby" | "ready" | "paused" | "stopping" | "error";

export interface WorkerServiceCapabilityMatrix {
  heartbeat: boolean;
  status: boolean;
  stop: boolean;
  pause: boolean;
  task_claim: false;
  task_execute: false;
  codex_execute: false;
  pr_create: false;
  arbitrary_shell: false;
  token_printed: false;
}

export interface WorkerServiceState {
  schema: "skybridge.worker_service_state.v1";
  worker_service_state: true;
  worker_id: string;
  worker_profile: string;
  mode: WorkerServiceMode;
  heartbeat_at: string | null;
  service_started_at: string | null;
  current_task_id: string | null;
  can_claim_tasks: false;
  can_execute_tasks: false;
  stop_requested: boolean;
  pause_requested: boolean;
  capability_matrix: WorkerServiceCapabilityMatrix;
  readiness_blockers: string[];
  token_available: boolean;
  token_printed: false;
}

export interface WorkerServiceReadiness {
  schema: "skybridge.worker_service_readiness.v1";
  worker_id: string;
  mode: WorkerServiceMode;
  heartbeat_age_seconds: number | null;
  ready_for_start_one_gate: false;
  can_claim_tasks: false;
  can_execute_tasks: false;
  blockers: string[];
  warnings: string[];
  recommended_action: string;
  token_printed: false;
}

export type LockStatus = "active" | "stale" | "released" | "cancelled" | "aborted" | "held";

export interface LockOwner {
  owner_id: string;
  owner_kind: "campaign" | "runner" | "worker" | "operator" | "unknown";
  display_name: string;
  process_id?: string | null;
  host?: string | null;
  token_printed: false;
}

export interface CampaignLock {
  schema: "skybridge.campaign_lock.v1";
  lock_id: string;
  campaign_id: string;
  project_id: string;
  lock_owner: LockOwner;
  heartbeat_at: string | null;
  expires_at: string | null;
  lock_status: LockStatus;
  release_reason: string | null;
  operator_reason: string | null;
  age_seconds: number;
  stale: boolean;
  token_printed: false;
}

export interface RepoExclusiveLock {
  schema: "skybridge.repo_exclusive_lock.v1";
  lock_id: string;
  campaign_id: string;
  project_id: string;
  repo_id: string;
  worktree_identity: string;
  lock_owner: LockOwner;
  heartbeat_at: string | null;
  expires_at: string | null;
  lock_status: LockStatus;
  release_reason: string | null;
  operator_reason: string | null;
  age_seconds: number;
  stale: boolean;
  blocks_execution_preview: boolean;
  force_release_allowed: false;
  token_printed: false;
}

export type CampaignQueueStatus = "ready" | "paused" | "held" | "completed" | "archived";

export interface CampaignPriorityQueueItem {
  campaign_id: string;
  project_id: string;
  priority: number;
  status: CampaignQueueStatus;
  current_goal_id: string;
  current_step_id: string;
  blocked_reason: string | null;
  selected: boolean;
  token_printed: false;
}

export interface CampaignPriorityQueue {
  schema: "skybridge.campaign_priority_queue.v1";
  project_id: string;
  active_campaign_id: string | null;
  current_campaign_id: string | null;
  one_active_campaign_per_project: true;
  deterministic_order: true;
  filter_statuses: CampaignQueueStatus[];
  items: CampaignPriorityQueueItem[];
  selection: {
    selected_campaign_id: string | null;
    decision: "select" | "blocked" | "none";
    blocked_campaign_reason: string | null;
    queue_decision_summary: string;
    execution_side_effects: false;
    token_printed: false;
  };
  token_printed: false;
}

export interface LockRecoveryDecision {
  schema: "skybridge.lock_recovery_decision.v1";
  action:
    | "campaign_lock_preview"
    | "repo_lock_preview"
    | "unlock_stale_campaign_lock"
    | "cancel_campaign"
    | "abort_campaign"
    | "hold_campaign";
  mode: "dry-run" | "apply";
  allowed: boolean;
  lock_status?: LockStatus;
  requires_reason: boolean;
  reason_recorded: boolean;
  blockers: string[];
  warnings: string[];
  audit_event_id: string | null;
  task_created: false;
  worker_loop_started: false;
  queue_execution_enabled: false;
  token_printed: false;
}

export type QueueControlAction =
  | "refresh_status"
  | "report"
  | "preflight"
  | "heartbeat"
  | "safe_pause"
  | "stop_queue"
  | "emergency_stop"
  | "resume_preview"
  | "start_one_preview"
  | "start_queue_preview"
  | "campaign_lock_status"
  | "campaign_lock_preview"
  | "repo_lock_status"
  | "repo_lock_preview"
  | "unlock_stale_campaign_lock"
  | "cancel_campaign_preview"
  | "abort_campaign_preview"
  | "campaign_priority_queue"
  | "campaign_select_next_preview"
  | "start_one_apply"
  | "start_queue_apply"
  | "start_all"
  | "arbitrary_shell";

export type QueueControlMode = "read" | "preview" | "apply";
export type QueueControlActionClass =
  | "read_only"
  | "preview"
  | "heartbeat_only"
  | "safe_stop_pause"
  | "armed_execution"
  | "forbidden";

export interface QueueControlActionMatrixEntry {
  action: QueueControlAction;
  class: QueueControlActionClass;
  allowed_modes: QueueControlMode[];
  apply_allowed: boolean;
  reason_required: boolean;
  human_approval_required: boolean;
  requires_arm_lease: boolean;
  blockers: string[];
  warnings: string[];
  summary: string;
  token_printed: false;
}

export interface QueueControlState {
  schema: "skybridge.queue_control_state.v1";
  project_id: string;
  campaign_id: string;
  current_step_id: string;
  current_goal_id: string;
  worker_status: string;
  active_tasks: number;
  stale_leases: number;
  can_start_one: boolean;
  can_start_queue: boolean;
  can_resume: boolean;
  state_hash: string;
  revision: string;
  action_matrix: QueueControlActionMatrixEntry[];
  blockers: string[];
  warnings: string[];
  token_printed: false;
}

export interface QueueControlIntent {
  schema: "skybridge.queue_control_intent.v1";
  action: QueueControlAction;
  mode: QueueControlMode;
  source: "cli" | "web" | "desktop" | "server";
  actor?: string;
  campaign_id: string;
  current_step_id?: string;
  target_revision: string;
  reason?: string;
  run_budget?: QueueControlRunBudget;
  arm_lease?: QueueControlArmLease;
  token_printed: false;
}

export interface QueueControlRunBudget {
  max_steps?: number;
  max_tasks?: number;
  max_runtime_minutes?: number;
  token_printed: false;
}

export interface QueueControlArmLease {
  lease_id: string;
  campaign_id: string;
  allowed_actions: QueueControlAction[];
  expires_at: string;
  created_by: string;
  reason: string;
  consumed_at?: string | null;
  token_printed: false;
}

export interface QueueControlAuditEvent {
  schema: "skybridge.queue_control_audit_event.v1";
  audit_event_id: string;
  action: QueueControlAction;
  source: QueueControlIntent["source"];
  mode: QueueControlMode;
  actor?: string;
  campaign_id: string;
  current_step_id: string;
  target_revision: string;
  reason: string;
  blockers: string[];
  warnings: string[];
  created_at: string;
  token_printed: false;
}

export interface QueueControlActionResponse {
  schema: "skybridge.queue_control_action_response.v1";
  ok: boolean;
  mode: QueueControlMode;
  action: QueueControlAction;
  allowed: boolean;
  blockers: string[];
  warnings: string[];
  audit_event_id?: string;
  state_hash: string;
  token_printed: false;
}

export type AttentionLevel = "info" | "warning" | "blocker" | "action_required" | "critical";
export type AttentionSource =
  | "campaign"
  | "worker"
  | "queue_control"
  | "pr"
  | "ci"
  | "notification"
  | "desktop"
  | "web";
export type AttentionEventType =
  | "worker_offline"
  | "queue_blocked"
  | "human_approval_required"
  | "goal_ready"
  | "goal_completed"
  | "pr_created"
  | "ci_failed"
  | "stale_lease"
  | "active_repo_lock_blocks_queue"
  | "stale_lock_requires_review"
  | "campaign_cancelled"
  | "campaign_aborted"
  | "campaign_held"
  | "multi_campaign_conflict"
  | "repo_lock_owner_unknown"
  | "unlock_requires_reason"
  | "safe_action_applied"
  | "emergency_stop_requested"
  | "notification_delivery_skipped"
  | "notification_delivery_fixture"
  | "no_ready_worker"
  | "all_workers_offline"
  | "worker_stale"
  | "worker_disabled"
  | "capability_mismatch"
  | "repo_parallelism_blocked"
  | "selected_worker_ready_for_preview_only";

export interface AttentionEvent {
  schema: "skybridge.attention_event.v1";
  attention_event: true;
  attention_event_id: string;
  attention_level: AttentionLevel;
  source: AttentionSource;
  campaign_id: string;
  current_step_id: string;
  goal_id: string;
  event_type: AttentionEventType;
  message: string;
  recommended_action: string;
  created_at: string;
  acknowledged_at: string | null;
  token_printed: false;
}

export type NotificationRouteKind =
  | "desktop_only"
  | "web_banner"
  | "local_fixture_notification"
  | "ntfy_placeholder"
  | "disabled";

export type NotificationRouteStatus =
  | "enabled"
  | "fixture_only"
  | "not_configured"
  | "disabled";

export interface NotificationRoutingRule {
  route: NotificationRouteKind;
  status: NotificationRouteStatus;
  levels: AttentionLevel[];
  event_types: AttentionEventType[];
  real_external_send: false;
  fixture_ledger_dir?: string;
  summary: string;
  token_printed: false;
}

export interface NotificationRoutingDecision {
  schema: "skybridge.notification_routing_decision.v1";
  attention_event_id: string;
  event_type: AttentionEventType;
  routes: NotificationRoutingRule[];
  external_notification_sent: false;
  fixture_ledger_enabled: boolean;
  token_printed: false;
}

export interface AttentionModel {
  schema: "skybridge.attention_model.v1";
  campaign_id: string;
  current_step_id: string;
  goal_id: string;
  attention_events: AttentionEvent[];
  routing_matrix: NotificationRoutingRule[];
  top_blocker: AttentionEvent | null;
  recommended_next_action: string;
  token_printed: false;
}

export const queueControlActionMatrix: QueueControlActionMatrixEntry[] = [
  {
    action: "refresh_status",
    class: "read_only",
    allowed_modes: ["read"],
    apply_allowed: false,
    reason_required: false,
    human_approval_required: false,
    requires_arm_lease: false,
    blockers: [],
    warnings: [],
    summary: "Read current queue status.",
    token_printed: false,
  },
  {
    action: "report",
    class: "read_only",
    allowed_modes: ["read"],
    apply_allowed: false,
    reason_required: false,
    human_approval_required: false,
    requires_arm_lease: false,
    blockers: [],
    warnings: [],
    summary: "Read the safe campaign report.",
    token_printed: false,
  },
  {
    action: "preflight",
    class: "read_only",
    allowed_modes: ["read"],
    apply_allowed: false,
    reason_required: false,
    human_approval_required: false,
    requires_arm_lease: false,
    blockers: [],
    warnings: [],
    summary: "Read preflight readiness.",
    token_printed: false,
  },
  {
    action: "heartbeat",
    class: "heartbeat_only",
    allowed_modes: ["apply"],
    apply_allowed: true,
    reason_required: false,
    human_approval_required: false,
    requires_arm_lease: false,
    blockers: [],
    warnings: ["heartbeat_only_no_task_claim"],
    summary: "Refresh worker heartbeat only.",
    token_printed: false,
  },
  ...(["safe_pause", "stop_queue", "emergency_stop"] as const).map(
    (action) =>
      ({
        action,
        class: "safe_stop_pause",
        allowed_modes: ["preview", "apply"],
        apply_allowed: true,
        reason_required: true,
        human_approval_required: false,
        requires_arm_lease: false,
        blockers: [],
        warnings: ["audit_required", "does_not_start_worker"],
        summary: "Low-risk queue stop or pause action.",
        token_printed: false,
      }) satisfies QueueControlActionMatrixEntry,
  ),
  ...([
    "resume_preview",
    "start_one_preview",
    "start_queue_preview",
    "campaign_lock_status",
    "campaign_lock_preview",
    "repo_lock_status",
    "repo_lock_preview",
    "cancel_campaign_preview",
    "abort_campaign_preview",
    "campaign_priority_queue",
    "campaign_select_next_preview",
  ] as const).map(
    (action) =>
      ({
        action,
        class: "preview",
        allowed_modes: ["preview"],
        apply_allowed: false,
        reason_required: false,
        human_approval_required: false,
        requires_arm_lease: false,
        blockers: action === "start_one_preview" || action === "start_queue_preview" ? ["active_repo_lock_blocks_execution_preview"] : [],
        warnings: ["preview_only_no_mutation"],
        summary: "Preview only; no campaign mutation or task creation.",
        token_printed: false,
      }) satisfies QueueControlActionMatrixEntry,
  ),
  {
    action: "unlock_stale_campaign_lock",
    class: "safe_stop_pause",
    allowed_modes: ["preview", "apply"],
    apply_allowed: true,
    reason_required: true,
    human_approval_required: false,
    requires_arm_lease: false,
    blockers: [],
    warnings: ["stale_only", "audit_required", "does_not_start_worker"],
    summary: "Release an inspected stale campaign lock only when a reason is supplied.",
    token_printed: false,
  },
  ...(["start_one_apply", "start_queue_apply"] as const).map(
    (action) =>
      ({
        action,
        class: "armed_execution",
        allowed_modes: [],
        apply_allowed: false,
        reason_required: true,
        human_approval_required: true,
        requires_arm_lease: true,
        blockers: ["execution_apply_deferred_until_goal_197"],
        warnings: [],
        summary: "Armed execution is modeled but forbidden until a later reviewed multi-worker readiness gate.",
        token_printed: false,
      }) satisfies QueueControlActionMatrixEntry,
  ),
  ...(["start_all", "arbitrary_shell"] as const).map(
    (action) =>
      ({
        action,
        class: "forbidden",
        allowed_modes: [],
        apply_allowed: false,
        reason_required: true,
        human_approval_required: true,
        requires_arm_lease: false,
        blockers: ["forbidden_action"],
        warnings: [],
        summary: "Forbidden queue-control action.",
        token_printed: false,
      }) satisfies QueueControlActionMatrixEntry,
  ),
];

export const workerRoutingPolicy: WorkerRoutingPolicy = {
  schema: "skybridge.worker_routing_policy.v1",
  default_mode: "preview",
  max_parallel_per_repo: 1,
  reject_offline_workers: true,
  reject_stale_workers: true,
  reject_disabled_workers: true,
  reject_busy_workers: true,
  require_capability_match: true,
  require_project_access: true,
  require_repo_access: true,
  require_os_tool_match: true,
  repo_lock_blocks_preview: true,
  stale_repo_lock_requires_recovery_first: true,
  can_claim_tasks: false,
  can_execute_tasks: false,
  token_printed: false,
};

export const fixtureWorkerCapabilityMatrix: WorkerCapabilityMatrixEntry[] = [
  {
    schema: "skybridge.worker_capability_matrix_entry.v1",
    worker_id: "laptop-zenbookduo",
    worker_label: "Jerry Windows standby",
    worker_profile: "laptop-zenbookduo-standby",
    os: "windows",
    tools: ["codex", "git", "node", "pnpm", "powershell"],
    task_type_capabilities: ["docs", "local-smoke", "frontend", "backend", "worker-service"],
    project_access: ["skybridge-agent-hub"],
    repo_access: ["skybridge-agent-hub"],
    can_run_local_smokes: true,
    can_run_frontend: true,
    can_run_backend: true,
    can_run_docs: true,
    can_run_worker_service: true,
    can_claim_tasks: false,
    can_execute_tasks: false,
    token_printed: false,
  },
  {
    schema: "skybridge.worker_capability_matrix_entry.v1",
    worker_id: "linux-ci-preview",
    worker_label: "Linux CI preview",
    worker_profile: "linux-ci-preview",
    os: "linux",
    tools: ["git", "node", "pnpm", "bash", "docker"],
    task_type_capabilities: ["docs", "local-smoke", "frontend", "backend"],
    project_access: ["skybridge-agent-hub"],
    repo_access: ["skybridge-agent-hub"],
    can_run_local_smokes: true,
    can_run_frontend: true,
    can_run_backend: true,
    can_run_docs: true,
    can_run_worker_service: false,
    can_claim_tasks: false,
    can_execute_tasks: false,
    token_printed: false,
  },
  {
    schema: "skybridge.worker_capability_matrix_entry.v1",
    worker_id: "docs-disabled",
    worker_label: "Docs disabled fixture",
    worker_profile: "docs-disabled",
    os: "unknown",
    tools: ["git"],
    task_type_capabilities: ["docs"],
    project_access: ["skybridge-agent-hub"],
    repo_access: ["skybridge-agent-hub"],
    can_run_local_smokes: false,
    can_run_frontend: false,
    can_run_backend: false,
    can_run_docs: true,
    can_run_worker_service: false,
    can_claim_tasks: false,
    can_execute_tasks: false,
    token_printed: false,
  },
  {
    schema: "skybridge.worker_capability_matrix_entry.v1",
    worker_id: "foreign-repo-worker",
    worker_label: "Foreign repo worker",
    worker_profile: "foreign-repo-worker",
    os: "windows",
    tools: ["git", "node", "pnpm", "powershell"],
    task_type_capabilities: ["docs", "local-smoke"],
    project_access: ["other-project"],
    repo_access: ["other-repo"],
    can_run_local_smokes: true,
    can_run_frontend: false,
    can_run_backend: false,
    can_run_docs: true,
    can_run_worker_service: false,
    can_claim_tasks: false,
    can_execute_tasks: false,
    token_printed: false,
  },
];

export const fixtureWorkerReadiness: WorkerReadinessEntry[] = [
  {
    schema: "skybridge.worker_readiness_entry.v1",
    worker_id: "laptop-zenbookduo",
    worker_label: "Jerry Windows standby",
    readiness_state: "online",
    heartbeat_age_seconds: 12,
    current_task_id: null,
    service_mode: "standby",
    readiness_score: 92,
    readiness_blockers: [],
    readiness_warnings: ["preview_only_execution_gate_disabled"],
    recommended_action: "Worker can be selected for preview only; execution remains disabled.",
    capability_matrix: fixtureWorkerCapabilityMatrix[0],
    token_printed: false,
  },
  {
    schema: "skybridge.worker_readiness_entry.v1",
    worker_id: "linux-ci-preview",
    worker_label: "Linux CI preview",
    readiness_state: "stale",
    heartbeat_age_seconds: 900,
    current_task_id: null,
    service_mode: "standby",
    readiness_score: 30,
    readiness_blockers: ["worker_stale"],
    readiness_warnings: [],
    recommended_action: "Refresh heartbeat before route preview can select this worker.",
    capability_matrix: fixtureWorkerCapabilityMatrix[1],
    token_printed: false,
  },
  {
    schema: "skybridge.worker_readiness_entry.v1",
    worker_id: "docs-disabled",
    worker_label: "Docs disabled fixture",
    readiness_state: "disabled",
    heartbeat_age_seconds: null,
    current_task_id: null,
    service_mode: "disabled",
    readiness_score: 0,
    readiness_blockers: ["worker_disabled"],
    readiness_warnings: [],
    recommended_action: "Enable the worker outside this goal before it can be considered.",
    capability_matrix: fixtureWorkerCapabilityMatrix[2],
    token_printed: false,
  },
  {
    schema: "skybridge.worker_readiness_entry.v1",
    worker_id: "foreign-repo-worker",
    worker_label: "Foreign repo worker",
    readiness_state: "online",
    heartbeat_age_seconds: 6,
    current_task_id: null,
    service_mode: "standby",
    readiness_score: 90,
    readiness_blockers: [],
    readiness_warnings: ["preview_only_execution_gate_disabled"],
    recommended_action: "Worker can be selected for preview only; execution remains disabled.",
    capability_matrix: fixtureWorkerCapabilityMatrix[3],
    token_printed: false,
  },
];

export const fixtureRouteTaskPreview: WorkerRouteTaskPreview = {
  task_id: "preview-super-197-local-smoke",
  task_type: "local-smoke",
  project_id: "skybridge-agent-hub",
  repo_id: "skybridge-agent-hub",
  required_os: "windows",
  required_tools: ["git", "node", "pnpm", "powershell"],
  required_capabilities: ["local-smoke"],
  token_printed: false,
};

export function createWorkerRoutePreview(
  task: WorkerRouteTaskPreview = fixtureRouteTaskPreview,
  workers: WorkerReadinessEntry[] = fixtureWorkerReadiness,
  options: {
    repoLock?: RepoExclusiveLock | null;
    activeMutatingWorkers?: number;
  } = {},
): WorkerRoutePreview {
  const repoLock = options.repoLock === undefined ? null : options.repoLock;
  const activeMutatingWorkers = options.activeMutatingWorkers ?? 0;
  const repoBlocked = activeMutatingWorkers >= workerRoutingPolicy.max_parallel_per_repo || !!repoLock?.blocks_execution_preview || !!repoLock?.stale;
  const repoBlocker = activeMutatingWorkers >= workerRoutingPolicy.max_parallel_per_repo
    ? "max_parallel_per_repo_exceeded"
    : repoLock?.stale
      ? "stale_repo_lock_requires_recovery_first"
      : repoLock?.blocks_execution_preview
        ? "active_repo_lock_blocks_routing_preview"
        : null;
  const decisions = workers.map((worker): WorkerRouteDecision => {
    const reasons = new Set<string>();
    if (worker.readiness_state === "offline") reasons.add("worker_offline");
    if (worker.readiness_state === "stale") reasons.add("worker_stale");
    if (worker.readiness_state === "disabled") reasons.add("worker_disabled");
    if (worker.readiness_state === "busy" || worker.current_task_id) reasons.add("worker_busy_current_task");
    if (!worker.capability_matrix.task_type_capabilities.includes(task.task_type)) reasons.add("capability_mismatch");
    if (!worker.capability_matrix.project_access.includes(task.project_id)) reasons.add("project_access_mismatch");
    if (!worker.capability_matrix.repo_access.includes(task.repo_id)) reasons.add("repo_access_mismatch");
    if (task.required_os && worker.capability_matrix.os !== task.required_os) reasons.add("os_mismatch");
    for (const tool of task.required_tools) {
      if (!worker.capability_matrix.tools.includes(tool)) reasons.add(`tool_mismatch_${tool}`);
    }
    for (const capability of task.required_capabilities) {
      if (!worker.capability_matrix.task_type_capabilities.includes(capability)) reasons.add(`capability_mismatch_${capability}`);
    }
    if (repoBlocked && repoBlocker) reasons.add(repoBlocker);
    return {
      worker_id: worker.worker_id,
      worker_label: worker.worker_label,
      accepted: reasons.size === 0,
      readiness_score: worker.readiness_score,
      rejection_reasons: Array.from(reasons),
      warnings: [...worker.readiness_warnings, "preview_only_no_task_claim"],
      token_printed: false,
    };
  });
  const selected = decisions.filter((decision) => decision.accepted).sort((a, b) => b.readiness_score - a.readiness_score)[0] ?? null;
  return {
    schema: "skybridge.worker_route_preview.v1",
    mode: "preview",
    task,
    selected_worker: selected,
    rejected_workers: decisions.filter((decision) => !decision.accepted),
    decisions,
    policy: workerRoutingPolicy,
    repo_parallelism_guard: {
      repo_id: task.repo_id,
      max_parallel_per_repo: 1,
      active_mutating_workers: activeMutatingWorkers,
      repo_lock_status: repoLock?.lock_status ?? "none",
      blocked: repoBlocked,
      blocker: repoBlocker,
      token_printed: false,
    },
    task_created: false,
    task_claimed: false,
    task_executed: false,
    worker_loop_started: false,
    queue_execution_enabled: false,
    token_printed: false,
  };
}

export const fixtureWorkerRoutingReadiness: WorkerRoutingReadinessDetail = {
  schema: "skybridge.worker_routing_readiness_detail.v1",
  worker_pool_counts: {
    total: fixtureWorkerReadiness.length,
    online: fixtureWorkerReadiness.filter((worker) => worker.readiness_state === "online").length,
    stale: fixtureWorkerReadiness.filter((worker) => worker.readiness_state === "stale").length,
    offline: fixtureWorkerReadiness.filter((worker) => worker.readiness_state === "offline").length,
    disabled: fixtureWorkerReadiness.filter((worker) => worker.readiness_state === "disabled").length,
    busy: fixtureWorkerReadiness.filter((worker) => worker.readiness_state === "busy").length,
    preview_candidates: createWorkerRoutePreview(fixtureRouteTaskPreview, fixtureWorkerReadiness).decisions.filter((decision) => decision.accepted).length,
  },
  worker_capability_matrix: fixtureWorkerCapabilityMatrix,
  worker_readiness: fixtureWorkerReadiness,
  route_preview: createWorkerRoutePreview(fixtureRouteTaskPreview, fixtureWorkerReadiness),
  selected_worker_ready_for_preview_only: createWorkerRoutePreview(fixtureRouteTaskPreview, fixtureWorkerReadiness).selected_worker !== null,
  execution_enabled: false,
  can_start_one: false,
  can_start_queue: false,
  token_printed: false,
};

export const workerServiceCapabilityMatrix: WorkerServiceCapabilityMatrix = {
  heartbeat: true,
  status: true,
  stop: true,
  pause: true,
  task_claim: false,
  task_execute: false,
  codex_execute: false,
  pr_create: false,
  arbitrary_shell: false,
  token_printed: false,
};

export const fixtureWorkerServiceState: WorkerServiceState = {
  schema: "skybridge.worker_service_state.v1",
  worker_service_state: true,
  worker_id: "laptop-zenbookduo",
  worker_profile: "laptop-zenbookduo-standby",
  mode: "offline",
  heartbeat_at: null,
  service_started_at: null,
  current_task_id: null,
  can_claim_tasks: false,
  can_execute_tasks: false,
  stop_requested: false,
  pause_requested: false,
  capability_matrix: workerServiceCapabilityMatrix,
  readiness_blockers: [
    "worker_service_offline",
    "standby_heartbeat_required",
    "execution_disabled_until_goal_197",
  ],
  token_available: false,
  token_printed: false,
};

export const fixtureLockOwner: LockOwner = {
  owner_id: "runner-dev-queue-189-200",
  owner_kind: "campaign",
  display_name: "dev queue campaign runner",
  process_id: null,
  host: "laptop-zenbookduo",
  token_printed: false,
};

export const fixtureCampaignLock: CampaignLock = {
  schema: "skybridge.campaign_lock.v1",
  lock_id: "campaign_lock_dev_queue_189_200",
  campaign_id: "dev-queue-189-200",
  project_id: "skybridge-agent-hub",
  lock_owner: fixtureLockOwner,
  heartbeat_at: "2026-06-08T00:00:00.000Z",
  expires_at: "2026-06-08T00:30:00.000Z",
  lock_status: "held",
  release_reason: null,
  operator_reason: "Goal 196 fixture: campaign is held for lock review before execution.",
  age_seconds: 0,
  stale: false,
  token_printed: false,
};

export const fixtureRepoExclusiveLock: RepoExclusiveLock = {
  schema: "skybridge.repo_exclusive_lock.v1",
  lock_id: "repo_lock_skybridge_agent_hub",
  campaign_id: "dev-queue-189-200",
  project_id: "skybridge-agent-hub",
  repo_id: "skybridge-agent-hub",
  worktree_identity: "V:/src/skybridge-agent-hub",
  lock_owner: fixtureLockOwner,
  heartbeat_at: "2026-06-08T00:00:00.000Z",
  expires_at: "2026-06-08T00:30:00.000Z",
  lock_status: "active",
  release_reason: null,
  operator_reason: null,
  age_seconds: 0,
  stale: false,
  blocks_execution_preview: true,
  force_release_allowed: false,
  token_printed: false,
};

export const fixtureStaleCampaignLock: CampaignLock = {
  ...fixtureCampaignLock,
  lock_id: "campaign_lock_dev_queue_189_200_stale",
  heartbeat_at: "2026-06-07T22:00:00.000Z",
  expires_at: "2026-06-07T22:30:00.000Z",
  lock_status: "stale",
  age_seconds: 7200,
  stale: true,
};

export const fixtureCampaignPriorityQueue: CampaignPriorityQueue = {
  schema: "skybridge.campaign_priority_queue.v1",
  project_id: "skybridge-agent-hub",
  active_campaign_id: "dev-queue-189-200",
  current_campaign_id: "dev-queue-189-200",
  one_active_campaign_per_project: true,
  deterministic_order: true,
  filter_statuses: ["ready", "paused", "held", "completed", "archived"],
  items: [
    {
      campaign_id: "dev-queue-189-200",
      project_id: "skybridge-agent-hub",
      priority: 10,
      status: "ready",
      current_goal_id: "super-197-multi-worker-readiness",
      current_step_id: "dev-queue-189-200:super-197-multi-worker-readiness",
      blocked_reason: "execution_gate_disabled_until_controlled_start_one_trial",
      selected: true,
      token_printed: false,
    },
    {
      campaign_id: "bootstrap-mvp",
      project_id: "skybridge-agent-hub",
      priority: 20,
      status: "held",
      current_goal_id: "super-184b-operator-console-dashboard",
      current_step_id: "bootstrap-mvp:super-184b-operator-console-dashboard",
      blocked_reason: "lower_priority_campaign_held_while_dev_queue_is_current",
      selected: false,
      token_printed: false,
    },
  ],
  selection: {
    selected_campaign_id: "dev-queue-189-200",
    decision: "blocked",
    blocked_campaign_reason: "execution_gate_disabled_until_controlled_start_one_trial",
    queue_decision_summary: "dev-queue-189-200 is highest priority; routing can preview a worker but cannot claim or execute tasks.",
    execution_side_effects: false,
    token_printed: false,
  },
  token_printed: false,
};

export function createWorkerServiceReadiness(
  state: WorkerServiceState = fixtureWorkerServiceState,
  options: {
    cleanWorktree?: boolean;
    activeTasks?: number;
    staleLeases?: number;
    runnerLockStatus?: string;
    knownCampaign?: boolean;
    tokenAvailable?: boolean;
    workerProfileValid?: boolean;
    now?: string;
  } = {},
): WorkerServiceReadiness {
  const blockers = new Set<string>(state.readiness_blockers);
  const warnings = new Set<string>();
  const activeTasks = options.activeTasks ?? 0;
  const staleLeases = options.staleLeases ?? 0;
  const runnerLockStatus = options.runnerLockStatus ?? "none";
  const cleanWorktree = options.cleanWorktree ?? true;
  const knownCampaign = options.knownCampaign ?? true;
  const tokenAvailable = options.tokenAvailable ?? state.token_available;
  const workerProfileValid = options.workerProfileValid ?? true;

  if (!cleanWorktree) blockers.add("worktree_dirty");
  if (!knownCampaign) blockers.add("unknown_campaign");
  if (activeTasks > 0) blockers.add("active_tasks_present");
  if (staleLeases > 0) blockers.add("stale_leases_present");
  if (runnerLockStatus !== "none" && runnerLockStatus !== "released") blockers.add("runner_lock_present");
  if (!tokenAvailable) blockers.add("worker_token_unavailable");
  if (!workerProfileValid) blockers.add("worker_profile_invalid");
  if (state.mode === "offline") blockers.add("worker_service_offline");
  if (state.mode === "standby") warnings.add("standby_heartbeat_only_no_execution");
  if (state.mode === "ready") warnings.add("ready_mode_still_execution_disabled_until_goal_197");
  if (state.pause_requested) blockers.add("pause_requested");
  if (state.stop_requested) blockers.add("stop_requested");
  if (state.current_task_id) blockers.add("current_task_present");
  blockers.add("execution_disabled_until_goal_197");

  const heartbeatAge = state.heartbeat_at
    ? Math.max(
        0,
        Math.floor(
          (Date.parse(options.now ?? "2026-06-08T00:00:00.000Z") - Date.parse(state.heartbeat_at)) / 1000,
        ),
      )
    : null;

  return {
    schema: "skybridge.worker_service_readiness.v1",
    worker_id: state.worker_id,
    mode: state.mode,
    heartbeat_age_seconds: Number.isFinite(heartbeatAge as number) ? heartbeatAge : null,
    ready_for_start_one_gate: false,
    can_claim_tasks: false,
    can_execute_tasks: false,
    blockers: Array.from(blockers),
    warnings: Array.from(warnings),
    recommended_action:
      state.mode === "offline"
        ? "Start or refresh a bounded standby heartbeat, then keep Start One disabled until a later reviewed gate."
        : "Monitor standby heartbeat and keep execution disabled until a later reviewed multi-worker readiness gate.",
    token_printed: false,
  };
}

export interface CampaignRunReport {
  schema: "skybridge.campaign_run_report.v1";
  generated_at: string;
  project_id: string;
  campaign_id: string;
  campaign_status: string;
  current_step_id: string;
  current_goal_id: string;
  current_goal_status: string;
  current_goal_unexecuted: boolean;
  campaign_summary: {
    campaign_id: string;
    project_id: string;
    title: string;
    status: string;
    current_step_id: string;
    step_count: number;
    source?: string;
    goal_pack_hash?: string;
  };
  current_step_summary: CampaignStepSummary;
  previous_step_summary?: CampaignStepSummary;
  step_ledger: CampaignStepSummary[];
  evidence_ledger: {
    all: CampaignEvidenceEntry[];
    present?: CampaignEvidenceEntry[];
    recovered?: CampaignEvidenceEntry[];
    missing?: CampaignEvidenceEntry[];
    skipped?: CampaignEvidenceEntry[];
    not_applicable?: CampaignEvidenceEntry[];
  };
  blockers: string[];
  warnings: string[];
  queue_control_readiness: CampaignQueueControlReadiness;
  worker_service_state: WorkerServiceState;
  token_printed: false;
}

export interface CampaignEvidenceCounts {
  total: number;
  present: number;
  recovered: number;
  missing: number;
  skipped: number;
  not_applicable: number;
}

export interface CampaignSafeSummary {
  schema: "skybridge.campaign_safe_summary.v1";
  campaign_id: string;
  current_step: string;
  current_goal_id: string;
  current_goal_status: string;
  goal_pack_id?: string;
  validation_result?: "pass" | "fail" | "unknown";
  hash_drift_count?: number;
  dependency_order_status?: "valid" | "invalid" | "unknown";
  proposed_import_update_action?: string;
  queue_readiness: Pick<
    CampaignQueueControlReadiness,
    | "can_start_one"
    | "can_start_queue"
    | "can_resume"
    | "can_stop"
    | "can_emergency_stop"
    | "next_safe_action"
    | "worker_required"
    | "worker_status"
  >;
  blockers: string[];
  warnings: string[];
  worker_status: string;
  worker_service_mode: WorkerServiceMode;
  worker_service_blockers: string[];
  attention_count: number;
  top_blocker: string | null;
  recommended_next_action: string;
  token_printed: false;
}

export interface GoalQueueReviewSummary {
  schema: "skybridge.goal_queue_review_summary.v1";
  goal_pack_id: string;
  current_campaign_pack_hash: string;
  validation_result: "pass" | "fail" | "unknown";
  validation_errors: string[];
  validation_warnings: string[];
  hash_drift_count: number;
  hash_drift_summary: string;
  dependency_order_status: "valid" | "invalid" | "unknown";
  proposed_import_update_action: string;
  reimport_preview_summary: {
    added_goals: number;
    removed_goals: number;
    changed_goals: number;
    dependency_changes: number;
    order_changes: number;
    safety_policy_changes: number;
    update_safe: boolean;
  };
  archive_preview_summary: {
    archive_target: string;
    would_archive: boolean;
    excludes_raw_logs_and_secrets: boolean;
  };
  no_execution_controls: true;
  task_created: false;
  worker_loop_started: false;
  queue_execution_enabled: false;
  token_printed: false;
}

export function summarizeCampaignEvidence(
  report: Pick<CampaignRunReport, "evidence_ledger">,
): CampaignEvidenceCounts {
  const entries = report.evidence_ledger.all ?? [];
  return {
    total: entries.length,
    present: entries.filter((entry) => entry.classification === "present_evidence").length,
    recovered: entries.filter((entry) => entry.recovered || entry.classification === "recovered_evidence").length,
    missing: entries.filter((entry) => entry.missing || entry.classification === "missing_evidence").length,
    skipped: entries.filter((entry) => entry.skipped || entry.classification === "skipped_evidence").length,
    not_applicable: entries.filter((entry) => entry.not_applicable || entry.classification === "not_applicable_evidence").length,
  };
}

export function createCampaignSafeSummary(report: CampaignRunReport): CampaignSafeSummary {
  const readiness = report.queue_control_readiness;
  const attention = deriveAttentionEvents(report);
  const topBlocker = attention.find((event) => event.attention_level === "critical" || event.attention_level === "blocker") ?? null;
  return {
    schema: "skybridge.campaign_safe_summary.v1",
    campaign_id: report.campaign_id,
    current_step: report.current_step_id,
    current_goal_id: report.current_goal_id,
    current_goal_status: report.current_goal_status,
    goal_pack_id: report.campaign_id,
    validation_result: "unknown",
    hash_drift_count: 0,
    dependency_order_status: "unknown",
    proposed_import_update_action: "review_goal_pack_offline",
    queue_readiness: {
      can_start_one: readiness.can_start_one,
      can_start_queue: readiness.can_start_queue,
      can_resume: readiness.can_resume,
      can_stop: readiness.can_stop,
      can_emergency_stop: readiness.can_emergency_stop,
      next_safe_action: readiness.next_safe_action,
      worker_required: readiness.worker_required,
      worker_status: readiness.worker_status,
    },
    blockers: [...readiness.blockers],
    warnings: [...readiness.warnings],
    worker_status: readiness.worker_status,
    worker_service_mode: report.worker_service_state.mode,
    worker_service_blockers: [...report.worker_service_state.readiness_blockers],
    attention_count: attention.length,
    top_blocker: topBlocker?.message ?? null,
    recommended_next_action: topBlocker?.recommended_action ?? readiness.next_safe_action,
    token_printed: false,
  };
}

const attentionCreatedAt = "2026-06-08T00:00:00.000Z";

function attentionId(report: CampaignRunReport, eventType: AttentionEventType, suffix = "current") {
  return `attention_${report.campaign_id}_${report.current_goal_id}_${eventType}_${suffix}`.replace(/[^A-Za-z0-9_:-]/g, "_");
}

function makeAttentionEvent(
  report: CampaignRunReport,
  event_type: AttentionEventType,
  attention_level: AttentionLevel,
  source: AttentionSource,
  message: string,
  recommended_action: string,
  suffix?: string,
): AttentionEvent {
  return {
    schema: "skybridge.attention_event.v1",
    attention_event: true,
    attention_event_id: attentionId(report, event_type, suffix),
    attention_level,
    source,
    campaign_id: report.campaign_id,
    current_step_id: report.current_step_id,
    goal_id: report.current_goal_id,
    event_type,
    message,
    recommended_action,
    created_at: attentionCreatedAt,
    acknowledged_at: null,
    token_printed: false,
  };
}

export const notificationRoutingMatrix: NotificationRoutingRule[] = [
  {
    route: "desktop_only",
    status: "enabled",
    levels: ["info", "warning", "blocker", "action_required", "critical"],
    event_types: [
      "worker_offline",
      "queue_blocked",
      "human_approval_required",
      "goal_ready",
      "goal_completed",
      "pr_created",
      "ci_failed",
      "stale_lease",
      "safe_action_applied",
      "emergency_stop_requested",
      "notification_delivery_skipped",
      "notification_delivery_fixture",
      "active_repo_lock_blocks_queue",
      "stale_lock_requires_review",
      "campaign_cancelled",
      "campaign_aborted",
      "campaign_held",
      "multi_campaign_conflict",
      "repo_lock_owner_unknown",
      "unlock_requires_reason",
      "no_ready_worker",
      "all_workers_offline",
      "worker_stale",
      "worker_disabled",
      "capability_mismatch",
      "repo_parallelism_blocked",
      "selected_worker_ready_for_preview_only",
    ],
    real_external_send: false,
    summary: "Render in SkyBridge Desktop only.",
    token_printed: false,
  },
  {
    route: "web_banner",
    status: "enabled",
    levels: ["warning", "blocker", "action_required", "critical"],
    event_types: [
      "worker_offline",
      "queue_blocked",
      "human_approval_required",
      "ci_failed",
      "stale_lease",
      "emergency_stop_requested",
      "active_repo_lock_blocks_queue",
      "stale_lock_requires_review",
      "campaign_cancelled",
      "campaign_aborted",
      "campaign_held",
      "multi_campaign_conflict",
      "repo_lock_owner_unknown",
      "unlock_requires_reason",
      "no_ready_worker",
      "all_workers_offline",
      "worker_stale",
      "worker_disabled",
      "capability_mismatch",
      "repo_parallelism_blocked",
    ],
    real_external_send: false,
    summary: "Render in the Web attention banner/feed.",
    token_printed: false,
  },
  {
    route: "local_fixture_notification",
    status: "fixture_only",
    levels: ["blocker", "action_required", "critical"],
    event_types: [
      "worker_offline",
      "queue_blocked",
      "human_approval_required",
      "ci_failed",
      "stale_lease",
      "emergency_stop_requested",
      "active_repo_lock_blocks_queue",
      "stale_lock_requires_review",
      "campaign_cancelled",
      "campaign_aborted",
      "campaign_held",
      "multi_campaign_conflict",
      "repo_lock_owner_unknown",
      "unlock_requires_reason",
      "no_ready_worker",
      "all_workers_offline",
      "repo_parallelism_blocked",
    ],
    real_external_send: false,
    fixture_ledger_dir: ".agent/tmp/notifications",
    summary: "Write a local ignored fixture ledger entry when fixture dispatch is explicitly requested.",
    token_printed: false,
  },
  {
    route: "ntfy_placeholder",
    status: "not_configured",
    levels: ["critical"],
    event_types: ["ci_failed", "emergency_stop_requested"],
    real_external_send: false,
    summary: "Real ntfy delivery is disabled by default and represented as not configured.",
    token_printed: false,
  },
  {
    route: "disabled",
    status: "disabled",
    levels: ["info"],
    event_types: ["goal_ready", "goal_completed", "pr_created", "safe_action_applied", "notification_delivery_skipped", "notification_delivery_fixture"],
    real_external_send: false,
    summary: "Low-noise events are not sent externally by default.",
    token_printed: false,
  },
];

export function routeAttentionEvent(event: AttentionEvent): NotificationRoutingDecision {
  const routes = notificationRoutingMatrix.filter(
    (rule) => rule.levels.includes(event.attention_level) && rule.event_types.includes(event.event_type),
  );
  return {
    schema: "skybridge.notification_routing_decision.v1",
    attention_event_id: event.attention_event_id,
    event_type: event.event_type,
    routes,
    external_notification_sent: false,
    fixture_ledger_enabled: routes.some((route) => route.route === "local_fixture_notification" && route.status === "fixture_only"),
    token_printed: false,
  };
}

export function deriveAttentionEvents(report: CampaignRunReport, auditEvents: QueueControlAuditEvent[] = []): AttentionEvent[] {
  const events: AttentionEvent[] = [];
  const readiness = report.queue_control_readiness;

  if (["offline", "stale", "missing", "unknown"].includes(readiness.worker_status)) {
    events.push(
      makeAttentionEvent(
        report,
        "worker_offline",
        readiness.worker_status === "offline" ? "action_required" : "blocker",
        "worker",
        `Worker is ${readiness.worker_status}; queue execution remains disabled.`,
        readiness.next_safe_action,
      ),
    );
  }

  const routing = readiness.routing_readiness;
  if (routing) {
    const counts = routing.worker_pool_counts;
    if (counts.preview_candidates === 0) {
      events.push(
        makeAttentionEvent(
          report,
          "no_ready_worker",
          "blocker",
          "worker",
          "No worker is eligible for route preview.",
          "Review rejected worker reasons; execution remains disabled.",
        ),
      );
    }
    if (counts.total > 0 && counts.online === 0) {
      events.push(
        makeAttentionEvent(
          report,
          "all_workers_offline",
          "action_required",
          "worker",
          "All workers are offline, stale, disabled, or busy.",
          "Refresh standby heartbeat or register an eligible worker before any future execution gate.",
        ),
      );
    }
    if (counts.stale > 0) {
      events.push(makeAttentionEvent(report, "worker_stale", "warning", "worker", "One or more workers have stale heartbeats.", "Refresh stale worker heartbeats before route preview selection.", "stale"));
    }
    if (counts.disabled > 0) {
      events.push(makeAttentionEvent(report, "worker_disabled", "warning", "worker", "One or more workers are disabled.", "Disabled workers are rejected by routing policy.", "disabled"));
    }
    if (routing.route_preview.rejected_workers.some((worker) => worker.rejection_reasons.some((reason) => reason.includes("capability_mismatch") || reason.includes("os_mismatch") || reason.includes("tool_mismatch")))) {
      events.push(makeAttentionEvent(report, "capability_mismatch", "warning", "worker", "At least one worker was rejected for capability, OS, or tool mismatch.", "Review the worker capability matrix before future route selection.", "capability"));
    }
    if (routing.route_preview.repo_parallelism_guard.blocked) {
      events.push(
        makeAttentionEvent(
          report,
          "repo_parallelism_blocked",
          "blocker",
          "queue_control",
          `Repo parallelism guard blocked preview: ${routing.route_preview.repo_parallelism_guard.blocker ?? "unknown"}.`,
          "Recover stale locks or wait for the active repo owner before any future route selection.",
          "repo_parallelism",
        ),
      );
    }
    if (routing.selected_worker_ready_for_preview_only) {
      events.push(
        makeAttentionEvent(
          report,
          "selected_worker_ready_for_preview_only",
          "info",
          "worker",
          `Selected worker ${routing.route_preview.selected_worker?.worker_label ?? "unknown"} is ready for preview only.`,
          "Keep execution disabled until the controlled Start-One Bootstrap Trial.",
          "selected_preview_only",
        ),
      );
    }
  }

  if (readiness.blockers.length > 0 || report.blockers.length > 0) {
    events.push(
      makeAttentionEvent(
        report,
        "queue_blocked",
        "blocker",
        "queue_control",
        `Queue blocked by ${[...readiness.blockers, ...report.blockers].join(", ")}.`,
        readiness.next_safe_action,
      ),
    );
  }

  const repoLock = readiness.repo_exclusive_lock;
  if (repoLock?.blocks_execution_preview) {
    events.push(
      makeAttentionEvent(
        report,
        "active_repo_lock_blocks_queue",
        repoLock.stale ? "blocker" : "action_required",
        "queue_control",
        `Repo lock ${repoLock.lock_id} blocks queue start previews for ${repoLock.repo_id}.`,
        repoLock.stale ? "Inspect the stale repo lock and release only with an operator reason." : "Inspect the active repo lock owner before any queue start preview.",
        repoLock.lock_id,
      ),
    );
  }
  if (repoLock?.lock_owner.owner_kind === "unknown") {
    events.push(
      makeAttentionEvent(
        report,
        "repo_lock_owner_unknown",
        "blocker",
        "queue_control",
        `Repo lock ${repoLock.lock_id} has an unknown owner.`,
        "Inspect local lock evidence before releasing or starting any queue preview.",
        `${repoLock.lock_id}_unknown_owner`,
      ),
    );
  }

  const campaignLock = readiness.campaign_lock;
  if (campaignLock?.stale || repoLock?.stale) {
    events.push(
      makeAttentionEvent(
        report,
        "stale_lock_requires_review",
        "blocker",
        "campaign",
        "A stale campaign or repo lock requires inspection-first recovery.",
        "Run lock preview, confirm the owner/heartbeat/expiry, then apply stale unlock only with a reason.",
      ),
    );
  }
  if (campaignLock?.lock_status === "held") {
    events.push(
      makeAttentionEvent(
        report,
        "campaign_held",
        "warning",
        "campaign",
        `${campaignLock.campaign_id} is held for operator review.`,
        "Review lock status and priority queue selection before allowing later execution work.",
      ),
    );
  }

  const priorityQueue = readiness.priority_queue;
  if ((priorityQueue?.items.filter((item) => item.status === "ready").length ?? 0) > 1 || priorityQueue?.selection.decision === "blocked") {
    events.push(
      makeAttentionEvent(
        report,
        "multi_campaign_conflict",
        "warning",
        "campaign",
        priorityQueue?.selection.queue_decision_summary ?? "Multiple campaigns require deterministic selection review.",
        "Use campaign-select-next-preview and keep execution side effects disabled.",
      ),
    );
  }

  for (const action of readiness.required_human_action) {
    events.push(
      makeAttentionEvent(
        report,
        "human_approval_required",
        "action_required",
        "campaign",
        `Human action required: ${action}.`,
        readiness.next_safe_action,
        action,
      ),
    );
  }

  if (report.current_goal_status === "ready" && report.current_goal_unexecuted) {
    events.push(
      makeAttentionEvent(
        report,
        "goal_ready",
        "info",
        "campaign",
        `${report.current_goal_id} is ready but execution is not enabled.`,
        "Review attention blockers and keep queue execution disabled until the next authorized goal.",
      ),
    );
  }

  if (report.previous_step_summary?.status === "completed") {
    events.push(
      makeAttentionEvent(
        report,
        "goal_completed",
        "info",
        "campaign",
        `${report.previous_step_summary.goal_id} is completed.`,
        "Review PR/CI evidence before advancing execution policy.",
        report.previous_step_summary.goal_id,
      ),
    );
  }

  for (const entry of report.evidence_ledger.all ?? []) {
    if (entry.kind === "pr" && (entry.status === "present" || entry.classification === "present_evidence")) {
      events.push(
        makeAttentionEvent(report, "pr_created", "info", "pr", `PR evidence present for ${entry.goal_id}.`, "Review PR evidence and CI status.", entry.evidence_id),
      );
    }
    if (entry.kind === "ci" && (entry.status === "failed" || entry.classification === "missing_evidence")) {
      events.push(
        makeAttentionEvent(report, "ci_failed", "critical", "ci", `CI attention required for ${entry.goal_id}.`, "Inspect safe CI evidence before queue execution.", entry.evidence_id),
      );
    }
  }

  if (readiness.blockers.includes("stale_lease") || report.blockers.includes("stale_lease")) {
    events.push(
      makeAttentionEvent(report, "stale_lease", "blocker", "worker", "A stale lease blocks queue readiness.", "Inspect lease evidence and use the existing stale-lease recovery runbook.", "lease"),
    );
  }

  for (const audit of auditEvents) {
    events.push(
      makeAttentionEvent(
        report,
        audit.action === "emergency_stop" ? "emergency_stop_requested" : "safe_action_applied",
        audit.action === "emergency_stop" ? "critical" : "warning",
        "queue_control",
        `Queue-control audit recorded ${audit.action}.`,
        "Review the safe audit event before taking further action.",
        audit.audit_event_id,
      ),
    );
  }

  const notificationSkipped = events.some((event) => routeAttentionEvent(event).routes.some((route) => route.route === "ntfy_placeholder"));
  if (notificationSkipped) {
    events.push(
      makeAttentionEvent(
        report,
        "notification_delivery_skipped",
        "warning",
        "notification",
        "External notification delivery skipped because ntfy is not configured.",
        "Use Desktop/Web attention surfaces or explicit fixture dispatch for local validation.",
      ),
    );
  }

  return events;
}

export function createAttentionModel(report: CampaignRunReport, auditEvents: QueueControlAuditEvent[] = []): AttentionModel {
  const attentionEvents = deriveAttentionEvents(report, auditEvents);
  const topBlocker = attentionEvents.find((event) => event.attention_level === "critical" || event.attention_level === "blocker") ?? null;
  return {
    schema: "skybridge.attention_model.v1",
    campaign_id: report.campaign_id,
    current_step_id: report.current_step_id,
    goal_id: report.current_goal_id,
    attention_events: attentionEvents,
    routing_matrix: notificationRoutingMatrix,
    top_blocker: topBlocker,
    recommended_next_action: topBlocker?.recommended_action ?? report.queue_control_readiness.next_safe_action,
    token_printed: false,
  };
}

export const fixtureCampaignRunReport: CampaignRunReport = {
  schema: "skybridge.campaign_run_report.v1",
  generated_at: "2026-06-08T00:00:00.000Z",
  project_id: "skybridge-agent-hub",
  campaign_id: "dev-queue-189-200",
  campaign_status: "paused",
  current_step_id: "dev-queue-189-200:super-197-multi-worker-readiness",
  current_goal_id: "super-197-multi-worker-readiness",
  current_goal_status: "ready",
  current_goal_unexecuted: true,
  campaign_summary: {
    campaign_id: "dev-queue-189-200",
    project_id: "skybridge-agent-hub",
    title: "Dev Queue 189-200",
    status: "paused",
    current_step_id: "dev-queue-189-200:super-197-multi-worker-readiness",
    step_count: 12,
    source: "fixture",
    goal_pack_hash: "fixture-dev-queue-189-200-local-pack-hash",
  },
  current_step_summary: {
    campaign_step_id: "dev-queue-189-200:super-197-multi-worker-readiness",
    goal_id: "super-197-multi-worker-readiness",
    order: 9,
    title: "Multi-worker Readiness",
    status: "ready",
    is_current: true,
    dependencies: ["super-196-campaign-locking-multi-campaign-queue"],
    linked_task_ids: [],
    linked_pr_urls: [],
    linked_task_count: 0,
    linked_pr_count: 0,
    evidence_status: "missing",
    recovered: false,
    missing_evidence: true,
    skipped_evidence: false,
    not_applicable_evidence: false,
    operator_action_required: false,
  },
  previous_step_summary: {
    campaign_step_id: "dev-queue-189-200:super-196-campaign-locking-multi-campaign-queue",
    goal_id: "super-196-campaign-locking-multi-campaign-queue",
    order: 8,
    title: "Campaign Locking and Multi-campaign Queue",
    status: "completed",
    is_current: false,
    dependencies: ["super-195-manual-goal-queue-management"],
    linked_task_ids: [],
    linked_pr_urls: ["https://github.com/JerrySkywalker/skybridge-agent-hub/pull/114"],
    linked_task_count: 0,
    linked_pr_count: 1,
    evidence_status: "present",
    recovered: false,
    missing_evidence: false,
    skipped_evidence: false,
    not_applicable_evidence: false,
    operator_action_required: false,
  },
  step_ledger: [],
  evidence_ledger: {
    all: [
      {
        kind: "pr",
        campaign_step_id: "dev-queue-189-200:super-193-notification-attention-loop",
        goal_id: "super-193-notification-attention-loop",
        evidence_id: "goal-193-pr",
        status: "present",
        classification: "present_evidence",
        recovered: false,
        missing: false,
        skipped: false,
        not_applicable: false,
        operator_action_required: false,
        summary: "Goal 193 notification attention loop PR evidence is present.",
      },
      {
        kind: "step",
        campaign_step_id: "dev-queue-189-200:super-189-ci-guardian-pr-finalizer-hardening",
        goal_id: "super-189-ci-guardian-pr-finalizer-hardening",
        evidence_id: "goal-189-recovered",
        status: "recovered",
        classification: "recovered_evidence",
        recovered: true,
        missing: false,
        skipped: false,
        not_applicable: false,
        operator_action_required: false,
        summary: "Goal 189 recovered evidence is represented.",
      },
      {
        kind: "pr",
        campaign_step_id: "dev-queue-189-200:super-194-worker-service-mode",
        goal_id: "super-194-worker-service-mode",
        evidence_id: "none",
        status: "present",
        classification: "present_evidence",
        recovered: false,
        missing: false,
        skipped: false,
        not_applicable: false,
        operator_action_required: false,
        summary: "Goal 194 worker service PR evidence is present.",
      },
      {
        kind: "step",
        campaign_step_id: "dev-queue-189-200:super-196-campaign-locking-multi-campaign-queue",
        goal_id: "super-196-campaign-locking-multi-campaign-queue",
        evidence_id: "none",
        status: "missing",
        classification: "missing_evidence",
        recovered: false,
        missing: true,
        skipped: false,
        not_applicable: false,
        operator_action_required: false,
        summary: "Goal 196 evidence is missing until the locking foundation is completed.",
      },
    ],
  },
  blockers: [],
  warnings: ["approved_unconverted_proposals_present", "multi_campaign_conflict_review_required"],
  queue_control_readiness: {
    can_start_one: false,
    can_start_queue: false,
    can_pause: false,
    can_stop: true,
    can_emergency_stop: true,
    can_resume: false,
    blockers: ["worker_service_offline", "active_repo_lock_blocks_execution_preview", "execution_disabled_until_goal_197"],
    warnings: ["approved_unconverted_proposals_present", "standby_worker_can_only_heartbeat", "multiple_campaigns_require_selection_review"],
    required_human_action: ["review_campaign_and_repo_locks_before_any_start_preview", "unlock_stale_locks_only_after_inspection_with_reason"],
    next_safe_action: "Review campaign lock, repo lock and priority queue previews; keep Start One and Start Queue disabled.",
    worker_required: true,
    worker_status: "offline",
    run_budget_required: true,
    reason_required: true,
    worker_service_state: fixtureWorkerServiceState,
    execution_disabled_until_goal: "super-197-multi-worker-readiness",
    campaign_lock: fixtureCampaignLock,
    repo_exclusive_lock: fixtureRepoExclusiveLock,
    priority_queue: fixtureCampaignPriorityQueue,
    routing_readiness: fixtureWorkerRoutingReadiness,
  },
  worker_service_state: fixtureWorkerServiceState,
  token_printed: false,
};

export const fixtureQueueControlState: QueueControlState = {
  schema: "skybridge.queue_control_state.v1",
  project_id: fixtureCampaignRunReport.project_id,
  campaign_id: fixtureCampaignRunReport.campaign_id,
  current_step_id: "dev-queue-189-200:super-197-multi-worker-readiness",
  current_goal_id: "super-197-multi-worker-readiness",
  worker_status: "offline",
  active_tasks: 0,
  stale_leases: 0,
  can_start_one: false,
  can_start_queue: false,
  can_resume: false,
  state_hash: "fixture-goal-197-routing-preview-active0-stale0",
  revision: "fixture-goal-197-revision",
  action_matrix: queueControlActionMatrix,
  blockers: ["worker_service_offline", "active_repo_lock_blocks_execution_preview", "execution_disabled_until_goal_197"],
  warnings: ["standby_worker_can_only_heartbeat", "multiple_campaigns_require_selection_review"],
  token_printed: false,
};

fixtureCampaignRunReport.step_ledger = [
  {
    campaign_step_id: "dev-queue-189-200:super-189-ci-guardian-pr-finalizer-hardening",
    goal_id: "super-189-ci-guardian-pr-finalizer-hardening",
    order: 1,
    title: "CI Guardian and PR Finalizer Hardening",
    status: "completed",
    is_current: false,
    dependencies: [],
    linked_task_ids: ["campaign-step-super-189-ci-guardian-pr-finalizer-hardening-20260601102536"],
    linked_pr_urls: ["https://github.com/JerrySkywalker/skybridge-agent-hub/pull/99"],
    linked_task_count: 1,
    linked_pr_count: 1,
    evidence_status: "recovered",
    recovered: true,
    missing_evidence: false,
    skipped_evidence: false,
    not_applicable_evidence: false,
    operator_action_required: false,
  },
  {
    campaign_step_id: "dev-queue-189-200:super-190-campaign-run-report-evidence-ledger",
    goal_id: "super-190-campaign-run-report-evidence-ledger",
    order: 2,
    title: "Campaign Run Report and Evidence Ledger",
    status: "completed",
    is_current: false,
    dependencies: ["super-189-ci-guardian-pr-finalizer-hardening"],
    linked_task_ids: [],
    linked_pr_urls: ["https://github.com/JerrySkywalker/skybridge-agent-hub/pull/106"],
    linked_task_count: 0,
    linked_pr_count: 1,
    evidence_status: "present",
    recovered: false,
    missing_evidence: false,
    skipped_evidence: false,
    not_applicable_evidence: false,
    operator_action_required: false,
  },
  {
    campaign_step_id: "dev-queue-189-200:super-191-readonly-operator-dashboard",
    goal_id: "super-191-readonly-operator-dashboard",
    order: 3,
    title: "Read-only Operator Dashboard",
    status: "completed",
    is_current: false,
    dependencies: ["super-190-campaign-run-report-evidence-ledger"],
    linked_task_ids: [],
    linked_pr_urls: ["https://github.com/JerrySkywalker/skybridge-agent-hub/pull/107"],
    linked_task_count: 0,
    linked_pr_count: 1,
    evidence_status: "present",
    recovered: false,
    missing_evidence: false,
    skipped_evidence: false,
    not_applicable_evidence: false,
    operator_action_required: false,
  },
  {
    campaign_step_id: "dev-queue-189-200:super-192-dashboard-safe-actions",
    goal_id: "super-192-dashboard-safe-actions",
    order: 4,
    title: "Dashboard Safe Actions",
    status: "completed",
    is_current: false,
    dependencies: ["super-191-readonly-operator-dashboard"],
    linked_task_ids: [],
    linked_pr_urls: ["https://github.com/JerrySkywalker/skybridge-agent-hub/pull/108"],
    linked_task_count: 0,
    linked_pr_count: 1,
    evidence_status: "present",
    recovered: false,
    missing_evidence: false,
    skipped_evidence: false,
    not_applicable_evidence: false,
    operator_action_required: false,
  },
  {
    campaign_step_id: "dev-queue-189-200:super-193-notification-attention-loop",
    goal_id: "super-193-notification-attention-loop",
    order: 5,
    title: "Notification and Attention Loop",
    status: "completed",
    is_current: false,
    dependencies: ["super-192-dashboard-safe-actions"],
    linked_task_ids: [],
    linked_pr_urls: ["https://github.com/JerrySkywalker/skybridge-agent-hub/pull/111"],
    linked_task_count: 0,
    linked_pr_count: 1,
    evidence_status: "present",
    recovered: false,
    missing_evidence: false,
    skipped_evidence: false,
    not_applicable_evidence: false,
    operator_action_required: false,
  },
  {
    campaign_step_id: "dev-queue-189-200:super-194-worker-service-mode",
    goal_id: "super-194-worker-service-mode",
    order: 6,
    title: "Worker Service Mode",
    status: "completed",
    is_current: false,
    dependencies: ["super-193-notification-attention-loop"],
    linked_task_ids: [],
    linked_pr_urls: ["https://github.com/JerrySkywalker/skybridge-agent-hub/pull/112"],
    linked_task_count: 0,
    linked_pr_count: 1,
    evidence_status: "present",
    recovered: false,
    missing_evidence: false,
    skipped_evidence: false,
    not_applicable_evidence: false,
    operator_action_required: false,
  },
  fixtureCampaignRunReport.previous_step_summary!,
  fixtureCampaignRunReport.current_step_summary,
  ...[
    ["super-197-multi-worker-readiness", "Multi-worker Readiness"],
    ["super-198-multi-project-support", "Multi-project Support"],
    ["super-199-hermes-goal-draft-generator", "Hermes Goal Draft Generator"],
    ["super-200-controlled-goal-draft-review-import", "Controlled Goal Draft Review and Import"],
  ].map(([goalId, title], index) => ({
    campaign_step_id: `dev-queue-189-200:${goalId}`,
    goal_id: goalId,
    order: index + 9,
    title,
    status: "pending",
    is_current: false,
    dependencies: [],
    linked_task_ids: [],
    linked_pr_urls: [],
    linked_task_count: 0,
    linked_pr_count: 0,
    evidence_status: "not_applicable",
    recovered: false,
    missing_evidence: false,
    skipped_evidence: false,
    not_applicable_evidence: true,
    operator_action_required: false,
  })),
];

export const fixtureGoalQueueReviewSummary: GoalQueueReviewSummary = {
  schema: "skybridge.goal_queue_review_summary.v1",
  goal_pack_id: "dev-queue-189-200",
  current_campaign_pack_hash: "fixture-dev-queue-189-200-local-pack-hash",
  validation_result: "pass",
  validation_errors: [],
  validation_warnings: [],
  hash_drift_count: 0,
  hash_drift_summary: "No fixture hash drift. Run skybridge-goal-pack.ps1 manifest-preview for live local hashes.",
  dependency_order_status: "valid",
  proposed_import_update_action: "safe_to_preview_import",
  reimport_preview_summary: {
    added_goals: 0,
    removed_goals: 0,
    changed_goals: 0,
    dependency_changes: 0,
    order_changes: 0,
    safety_policy_changes: 0,
    update_safe: true,
  },
  archive_preview_summary: {
    archive_target: ".agent/tmp/campaign-archives/dev-queue-189-200",
    would_archive: true,
    excludes_raw_logs_and_secrets: true,
  },
  no_execution_controls: true,
  task_created: false,
  worker_loop_started: false,
  queue_execution_enabled: false,
  token_printed: false,
};

function queryString(query: object): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined) params.set(key, String(value));
  }
  const text = params.toString();
  return text ? `?${text}` : "";
}

async function assertOk(response: Response, label: string): Promise<void> {
  if (response.ok) return;
  let detail = "";
  try {
    detail = `: ${JSON.stringify(await response.json())}`;
  } catch {
    detail = "";
  }
  throw new Error(`${label} failed with HTTP ${response.status}${detail}`);
}
