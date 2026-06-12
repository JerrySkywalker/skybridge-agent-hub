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
  project_profile?: ProjectProfileReviewSummary;
  project_selection?: ProjectSelectionPreview;
  proposed_goal_summary?: ProposedGoalSafeSummary | ProposedGoalReviewSummary;
}

export interface ProjectValidationCommandSummary {
  id: string;
  command: string;
  known_fixture: boolean;
  executes: false;
}

export interface ProjectWorkerProfileSummary {
  default_worker_profile: string;
  allowed_worker_profiles: string[];
  can_claim_tasks: false;
  can_execute_tasks: false;
}

export interface ProjectGoalPackSummary {
  default_goal_pack_dir: string;
  allowed_goal_pack_dirs: string[];
  import_apply_enabled: false;
}

export interface ProjectPolicySummary {
  fixture_only: boolean;
  dry_run_default: boolean;
  selection_preview_only: true;
  forbid_arbitrary_shell: true;
  forbid_secret_fields: true;
  forbid_production_paths: true;
}

export interface ProjectProfileReviewSummary {
  schema: "skybridge.project_profile_review_summary.v1";
  project_id: string;
  display_name: string;
  validation_status: "valid" | "invalid" | "missing";
  validation_errors: string[];
  validation_warnings: string[];
  repo_identity: string;
  repo_path_display: string;
  default_branch: string;
  allowed_paths: string[];
  blocked_paths: string[];
  validation_commands: ProjectValidationCommandSummary[];
  worker_profile_summary: ProjectWorkerProfileSummary;
  goal_pack_summary: ProjectGoalPackSummary;
  policy_summary: ProjectPolicySummary;
  profile_hash: string;
  no_execution_controls: true;
  token_printed: false;
}

export interface ProjectSelectionPreview {
  schema: "skybridge.project_selection_preview.v1";
  mode: "preview";
  selected_project_id: string;
  profile_hash: string;
  repo_identity: string;
  repo_path_display: string;
  default_branch: string;
  allowed_path_summary: string;
  worker_profile_summary: ProjectWorkerProfileSummary;
  goal_pack_summary: ProjectGoalPackSummary;
  blocked_reason: string | null;
  project_selection_preview_only: true;
  task_created: false;
  task_claimed: false;
  task_executed: false;
  worker_loop_started: false;
  queue_execution_enabled: false;
  validation_commands_executed: false;
  token_printed: false;
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
  project_profile_required?: boolean;
  project_profile_hash?: string;
  project_selection_preview_only?: boolean;
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

export interface WorkerProfile {
  schema: "skybridge.worker_profile.v1";
  worker_id: string;
  display_name: string;
  host_label: string;
  os: WorkerOs;
  arch: string;
  location_label: string;
  worker_group: string;
  supported_task_types: string[];
  supported_projects: string[];
  supported_repos: string[];
  tools_available: WorkerTool[];
  can_claim_tasks: false;
  can_execute_tasks: false;
  max_concurrent_workunits: number;
  heartbeat_at: string | null;
  stale_after_seconds: number;
  resource_policy_summary: string;
  trust_level: "local_operator" | "ci_fixture" | "untrusted_fixture";
  token_printed: false;
}

export interface WorkerPool {
  schema: "skybridge.worker_pool.v1";
  workers: WorkerProfile[];
  groups: string[];
  preview_only: true;
  token_printed: false;
}

export interface WorkerAvailability {
  schema: "skybridge.worker_availability.v1";
  worker_id: string;
  state: "online" | "offline" | "stale" | "disabled" | "busy" | "ready_preview_only";
  heartbeat_age_seconds: number | null;
  busy_workunit_id: string | null;
  readiness_blockers: string[];
  score: number;
  token_printed: false;
}

export interface WorkerCapabilityMatch {
  schema: "skybridge.worker_capability_match.v1";
  worker_id: string;
  workunit_id: string;
  accepted: boolean;
  score: number;
  rejected_reasons: string[];
  token_printed: false;
}

export interface WorkerScore {
  schema: "skybridge.worker_score.v1";
  worker_id: string;
  score: number;
  factors: string[];
  blockers: string[];
  token_printed: false;
}

export interface RepoParallelismPolicy {
  schema: "skybridge.repo_parallelism_policy.v1";
  repo_id: string;
  max_parallel_per_repo: 1;
  mutating_work_serialized: true;
  read_only_parallel_allowed_when_explicit: boolean;
  uncertain_counts_as_mutating: true;
  token_printed: false;
}

export interface WorkunitRoutePlan {
  schema: "skybridge.workunit_route_plan.v1";
  plan_id: string;
  mode: "preview";
  selected_routes: Array<{
    workunit_id: string;
    selected_worker_id: string | null;
    queue_order: number;
    serialized_by_repo_policy: boolean;
    token_printed: false;
  }>;
  rejected_workers: WorkerCapabilityMatch[];
  policy_blockers: string[];
  task_claimed: false;
  lease_created: false;
  task_executed: false;
  pr_created: false;
  token_printed: false;
}

export interface SchedulingPreview {
  schema: "skybridge.scheduling_preview.v1";
  preview_id: string;
  worker_pool: WorkerPool;
  availability: WorkerAvailability[];
  scores: WorkerScore[];
  repo_parallelism_policy: RepoParallelismPolicy;
  route_plan: WorkunitRoutePlan;
  apply_available: false;
  task_claimed: false;
  lease_created: false;
  task_executed: false;
  pr_created: false;
  token_printed: false;
}

export interface MultiWorkerReadiness {
  schema: "skybridge.multi_worker_readiness.v1";
  worker_pool_count: number;
  ready_preview_only_count: number;
  stale_count: number;
  disabled_count: number;
  apply_available: false;
  blockers: string[];
  attention_events: string[];
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

export interface DesktopResidentState {
  schema: "skybridge.desktop_resident_state.v1";
  tray_available: boolean;
  window_visible: boolean;
  close_to_tray_supported: boolean;
  autostart_supported: boolean;
  autostart_enabled: boolean;
  resident_mode: "disabled" | "tray_resident_preview" | "resident_standby";
  last_refresh_at: string;
  token_printed: false;
}

export interface LocalWorkerSupervisorState {
  schema: "skybridge.local_worker_supervisor_state.v1";
  worker_id: string;
  worker_service_mode: WorkerServiceMode;
  heartbeat_age_seconds: number | null;
  current_task_id: string | null;
  can_claim_tasks: false;
  can_execute_tasks: false;
  readiness_blockers: string[];
  pause_requested: boolean;
  stop_requested: boolean;
  last_local_evidence_at: string | null;
  token_printed: false;
}

export interface LocalResourcePolicy {
  schema: "skybridge.local_resource_policy.v1";
  require_ac_power: boolean;
  pause_on_battery: boolean;
  pause_below_battery_percent: number;
  require_idle: boolean;
  max_cpu_percent: number;
  max_memory_percent: number;
  network_required: boolean;
  allowed_hours: string;
  lid_sleep_note?: string;
  sleep_lid_behavior_note: string;
  policy_source: "fixture" | "local_script" | "desktop_metadata";
  enforcement_status: "preview_only" | "metadata_only" | "enforced";
  observation_source?: string;
  battery_state: "unknown" | "ac_power" | "battery" | "no_battery";
  battery_percent: number | null;
  ac_power?: boolean | null;
  memory_used_percent: number | null;
  cpu_summary: string;
  blockers?: string[];
  warnings?: string[];
  can_run_one_at_a_time?: boolean;
  token_printed: false;
}

export interface LocalResourceObservation {
  schema: "skybridge.local_resource_observation.v1";
  observation_source: string;
  battery_state: "unknown" | "ac_power" | "battery" | "no_battery";
  battery_percent: number | null;
  ac_power: boolean | null;
  memory_used_percent: number | null;
  cpu_percent: number | null;
  network_available: boolean | null;
  current_local_time: string;
  token_printed: false;
}

export interface LocalResourceBlocker {
  schema: "skybridge.local_resource_blocker.v1";
  blocker_id: string;
  severity: "blocker" | "warning";
  summary: string;
  token_printed: false;
}

export interface LocalResourcePolicyEnforcement {
  schema: "skybridge.local_resource_policy_enforcement.v1";
  policy: LocalResourcePolicy;
  observation: LocalResourceObservation;
  blockers: LocalResourceBlocker[];
  warnings: string[];
  can_run_one_at_a_time: boolean;
  task_claimed: false;
  task_executed: false;
  no_powercfg_mutation: true;
  admin_required: false;
  token_printed: false;
}

export interface LocalRunAllowance {
  schema: "skybridge.local_run_allowance.v1";
  run_id: string;
  explicit_authorization_required: true;
  resource_gate_required: true;
  can_run_one_at_a_time: boolean;
  blockers: string[];
  token_printed: false;
}

export interface LocalExecutionGuard {
  schema: "skybridge.local_execution_guard.v1";
  execution_disabled: true;
  start_one_enabled: false;
  start_queue_enabled: false;
  start_all_present: false;
  resume_execution_enabled: false;
  arbitrary_shell_available: false;
  bounded_queue_execution_enabled: false;
  reason: string;
  next_safe_action: string;
  token_printed: false;
}

export type WorkunitState =
  | "proposed"
  | "ready"
  | "claimed"
  | "running"
  | "succeeded"
  | "failed"
  | "expired"
  | "cancelled"
  | "held_for_review"
  | "completed";

export interface WorkunitLease {
  schema: "skybridge.workunit_lease.v1";
  lease_id: string | null;
  lease_owner: string | null;
  lease_expires_at: string | null;
  token_printed: false;
}

export interface WorkunitResult {
  schema: "skybridge.workunit_result.v1";
  result_artifact: string | null;
  evidence_artifact: string | null;
  pr_url: string | null;
  ci_status: "not_applicable" | "not_started" | "pending" | "passing" | "failing" | "unknown";
  token_printed: false;
}

export interface Workunit {
  schema: "skybridge.workunit.v1";
  workunit_id: string;
  project_id: string;
  campaign_id: string;
  goal_id: string;
  task_id: string;
  task_type: string;
  required_capabilities: string[];
  allowed_paths: string[];
  risk: GoalRisk;
  state: WorkunitState;
  lease_id: string | null;
  lease_owner: string | null;
  lease_expires_at: string | null;
  retry_count: number;
  max_retries: number;
  deadline: string | null;
  result_artifact: string | null;
  evidence_artifact: string | null;
  pr_url: string | null;
  ci_status: WorkunitResult["ci_status"];
  token_printed: false;
}

export interface WorkunitStateEnvelope {
  schema: "skybridge.workunit_state.v1";
  workunit_id: string;
  state: WorkunitState;
  terminal: boolean;
  requires_human_review: boolean;
  token_printed: false;
}

export type WorkunitCandidateConversionStatus =
  | "proposed"
  | "reviewed"
  | "candidate_ready"
  | "blocked"
  | "imported_preview_only"
  | "rejected";

export interface ProposedGoalWorkunitCandidate {
  schema: "skybridge.proposed_goal_workunit_candidate.v1";
  candidate_id: string;
  source_proposed_goal_id: string;
  source_goal_path: string;
  reviewed_goal_path: string | null;
  project_id: string;
  campaign_id: string | null;
  candidate_pack_id: string;
  suggested_workunit_id: string;
  suggested_task_type: string;
  risk: GoalRisk | "blocked";
  allowed_paths: string[];
  blocked_paths: string[];
  required_capabilities: string[];
  estimated_runtime_minutes: number;
  max_prs: number;
  requires_human_review: boolean;
  conversion_status: WorkunitCandidateConversionStatus;
  blockers: string[];
  warnings: string[];
  content_hash: string;
  manifest_hash: string;
  token_printed: false;
}

export interface GoalToWorkunitConversion {
  schema: "skybridge.goal_to_workunit_conversion.v1";
  conversion_id: string;
  mode: "preview" | "fixture";
  candidate_count: number;
  candidate_ready_count: number;
  blocked_count: number;
  execution_review_required: true;
  task_created: false;
  task_claimed: false;
  task_executed: false;
  pr_created: false;
  token_printed: false;
}

export interface WorkunitCandidateRiskGate {
  schema: "skybridge.workunit_candidate_risk_gate.v1";
  candidate_id: string;
  decision: "allow_candidate_ready" | "review_required" | "blocked";
  reasons: string[];
  blocked_terms: string[];
  generated_goal_self_approved: false;
  token_printed: false;
}

export interface WorkunitCandidateReview {
  schema: "skybridge.workunit_candidate_review.v1";
  candidate_id: string;
  review_status: "preview_only" | "requires_human_review" | "blocked" | "rejected";
  reviewer: "operator_required";
  execution_review_required: true;
  token_printed: false;
}

export interface WorkunitCandidateManifest {
  schema: "skybridge.workunit_candidate_manifest.v1";
  manifest_id: string;
  candidate_pack_id: string;
  manifest_path: string;
  manifest_hash: string;
  candidates: ProposedGoalWorkunitCandidate[];
  execution_review_required: true;
  apply_available: false;
  task_created: false;
  task_claimed: false;
  task_executed: false;
  token_printed: false;
}

export interface WorkunitCandidatePack {
  schema: "skybridge.workunit_candidate_pack.v1";
  candidate_pack_id: string;
  project_id: string;
  campaign_id: string | null;
  candidates: ProposedGoalWorkunitCandidate[];
  risk_gates: WorkunitCandidateRiskGate[];
  candidate_ready_count: number;
  blocked_count: number;
  requires_review_count: number;
  bounded_queue_preview_only: true;
  apply_available: false;
  execution_disabled: true;
  next_safe_action: string;
  token_printed: false;
}

export interface BoundedQueuePolicy {
  schema: "skybridge.bounded_queue_policy.v1";
  max_steps: number;
  max_tasks: number;
  max_prs: number;
  max_runtime_minutes: number;
  max_parallel_per_repo: number;
  stop_on_pr_created: boolean;
  stop_on_ci_failure: boolean;
  stop_on_warning: boolean;
  drain_after_current: boolean;
  pause_after_current: boolean;
  require_human_review: boolean;
  allow_task_types: string[];
  block_task_types: string[];
  token_printed: false;
}

export interface BoundedQueuePlan {
  schema: "skybridge.bounded_queue_plan.v1";
  plan_id: string;
  mode: "preview";
  campaign_id: string;
  project_id: string;
  policy: BoundedQueuePolicy;
  workunits: Workunit[];
  workunit_candidate_pack?: WorkunitCandidatePack;
  candidate_preview_count?: number;
  would_create_tasks: false;
  would_claim_tasks: false;
  would_execute_tasks: false;
  would_create_prs: false;
  would_start_runner: false;
  no_mutation: true;
  token_printed: false;
}

export interface BoundedQueueReadiness {
  schema: "skybridge.bounded_queue_readiness.v1";
  campaign_id: string;
  project_id: string;
  can_start_bounded_queue: false;
  start_bounded_queue_apply_available: false;
  bounded_queue_execution_enabled: false;
  blockers: string[];
  warnings: string[];
  next_safe_action: string;
  token_printed: false;
}

export interface ManagedModePilotPolicy {
  schema: "skybridge.managed_mode_pilot_policy.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  max_workunits: 1;
  max_tasks: 1;
  max_claims: 1;
  max_codex_executions: 1;
  max_prs: 1;
  max_runtime_minutes: number;
  max_parallel_per_repo: 1;
  stop_on_pr_created: true;
  stop_on_ci_failure: true;
  stop_on_warning: true;
  require_human_review: true;
  allow_task_types: string[];
  block_task_types: string[];
  allowed_paths: string[];
  selected_worker_id: string;
  can_start_managed_mode: false;
  general_bounded_queue_apply_enabled: false;
  pilot_bounded_queue_apply_enabled: boolean;
  token_printed: false;
}

export interface BoundedQueueApplyRequest {
  schema: "skybridge.bounded_queue_apply_request.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  plan_id: string;
  policy: ManagedModePilotPolicy;
  workunits: Workunit[];
  selected_routes: Array<{
    workunit_id: string;
    selected_worker_id: string;
    queue_order: number;
    token_printed: false;
  }>;
  selected_worker_count: number;
  selected_workunit_count: number;
  would_create_tasks: boolean;
  would_claim_tasks: boolean;
  would_execute_tasks: boolean;
  would_create_prs: boolean;
  would_start_runner: false;
  no_mutation: true;
  token_printed: false;
}

export interface BoundedQueueApplyGate {
  schema: "skybridge.bounded_queue_apply_gate.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  can_run_pilot: boolean;
  can_start_managed_mode: false;
  general_bounded_queue_apply_enabled: false;
  pilot_bounded_queue_apply_enabled: boolean;
  active_tasks: number;
  stale_leases: number;
  runner_lock: string;
  open_pilot_pr_count: number;
  selected_workunit_count: number;
  selected_worker_count: number;
  blockers: string[];
  token_printed: false;
}

export interface BoundedQueueApplyResult {
  schema: "skybridge.bounded_queue_apply_result.v1";
  pilot_id: string;
  mode: string;
  final_state: string;
  renewed_authorization?: boolean;
  renewed_authorization_reason?: string | null;
  prior_attempt_state?: string;
  prior_attempt_had_task_pr?: boolean;
  prior_attempt_had_executor_evidence?: boolean;
  prior_attempt_had_raw_artifacts?: boolean;
  renewed_attempt_count?: number;
  task_created: boolean;
  task_claimed: boolean;
  codex_execution_started: boolean;
  pr_created: boolean;
  blockers: string[];
  token_printed: false;
}

export interface ManagedModeV1Readiness {
  schema: "skybridge.managed_mode_v1_readiness.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  managed_mode_v1: "pilot only";
  can_start_managed_mode: false;
  can_run_pilot: boolean;
  general_bounded_queue_apply_enabled: false;
  pilot_bounded_queue_apply_enabled: boolean;
  active_tasks: number;
  stale_leases: number;
  runner_lock: string;
  blockers: string[];
  token_printed: false;
}

export interface ManagedModePilotState {
  schema: "skybridge.managed_mode_pilot_state.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  state: "ready_for_one_workunit_pilot" | "pilot_gate_blocked" | "held_waiting_human_pr_review" | "managed_mode_pilot_completed";
  workunits_executed: number;
  task_count: number;
  claim_count: number;
  codex_execution_count: number;
  pr_count: number;
  evidence_path: string | null;
  token_printed: false;
}

export interface ManagedModePilotRenewedAuthorizationState {
  schema: "skybridge.managed_mode_pilot_renewed_authorization_state.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  renewed_authorization: boolean;
  renewed_authorization_reason: string | null;
  prior_attempt_state:
    | "prior_attempt_failed_before_execution"
    | "prior_attempt_produced_task_pr_or_evidence"
    | "prior_attempt_ambiguous"
    | "prior_attempt_unsafe_raw_artifacts";
  prior_attempt_had_task_pr: boolean;
  prior_attempt_open_task_pr_count: number;
  prior_attempt_had_executor_evidence: boolean;
  prior_attempt_had_result_artifact: boolean;
  prior_attempt_had_finalizer_evidence: boolean;
  prior_attempt_had_raw_artifacts: boolean;
  prior_attempt_artifact_count: number;
  prior_attempt_unknown_artifacts: string[];
  renewed_attempt_count: 0 | 1;
  can_run_renewed_apply: boolean;
  blockers: string[];
  token_printed: false;
}

export type ManagedModePilotPriorAttemptState =
  | "no_prior_attempt"
  | "prior_attempt_failed_before_execution"
  | "prior_attempt_timed_out_no_mutation"
  | "prior_attempt_failed_with_no_mutation"
  | "prior_attempt_partial_worktree_dirty"
  | "prior_attempt_created_pr"
  | "prior_attempt_executor_evidence_exists"
  | "prior_attempt_finalizer_evidence_exists"
  | "prior_attempt_ambiguous"
  | "prior_attempt_unsafe_raw_artifacts"
  | "retry_exhausted";

export interface ManagedModePilotTimeoutDiagnostics {
  timeout: boolean;
  retry_timeout: boolean;
  elapsed_seconds: number | null;
  timeout_minutes: number | null;
  launcher_kind: string | null;
  host_executable_name: string | null;
  stdout_chars_discarded: number | null;
  stderr_chars_discarded: number | null;
  changed_file_count: number;
  open_pr_count: number;
  executor_evidence_exists: boolean;
  finalizer_evidence_exists: boolean;
  retry_count: number;
  token_printed: false;
}

export interface ManagedModePilotTimeoutState {
  schema: "skybridge.managed_mode_pilot_timeout_state.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  prior_state: ManagedModePilotPriorAttemptState;
  result_path: string | null;
  retry_result_path: string | null;
  timed_out: boolean;
  changed_files: string[];
  open_pilot_pr_count: number;
  executor_evidence_exists: boolean;
  finalizer_evidence_exists: boolean;
  raw_or_secret_artifacts_present: boolean;
  retry_count: number;
  max_retries: 1;
  retry_exhausted: boolean;
  diagnostics: ManagedModePilotTimeoutDiagnostics;
  blockers: string[];
  token_printed: false;
}

export interface ManagedModePilotRetryPolicy {
  schema: "skybridge.managed_mode_pilot_retry_policy.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  max_retries: 1;
  retry_count: number;
  retry_reason_required: true;
  retry_allowed_only_after_timeout_no_mutation: true;
  retry_disallowed_after_pr: true;
  retry_disallowed_after_executor_evidence: true;
  retry_disallowed_after_partial_changes: true;
  retry_disallowed_after_unsafe_artifacts: true;
  token_printed: false;
}

export interface ManagedModePilotRetryReadiness {
  schema: "skybridge.managed_mode_pilot_retry_readiness.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  can_retry: boolean;
  prior_state: ManagedModePilotPriorAttemptState;
  retry_count: number;
  remaining_retry_count: 0 | 1;
  max_retries: 1;
  policy: ManagedModePilotRetryPolicy;
  gate: BoundedQueueApplyGate;
  timeout_state: ManagedModePilotTimeoutState;
  blockers: string[];
  token_printed: false;
}

export interface ManagedModePilotRetryPreview {
  schema: "skybridge.managed_mode_pilot_retry_preview.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  can_retry: boolean;
  retry_target_path: string;
  readiness: ManagedModePilotRetryReadiness;
  request: BoundedQueueApplyRequest;
  no_mutation: true;
  token_printed: false;
}

export interface ManagedModePilotRetryResult {
  schema: "skybridge.managed_mode_pilot_retry_result.v1";
  pilot_id: string;
  mode: string;
  final_state: "held_waiting_human_pr_review" | "pilot_failed_timeout_retry_exhausted" | "pilot_failed_retry_exhausted";
  retry_authorization: boolean;
  retry_authorization_reason: string;
  retry_attempt_count: 1;
  max_retries: 1;
  task_created: boolean;
  task_claimed: boolean;
  codex_execution_started: boolean;
  timed_out: boolean;
  pr_created: boolean;
  pr_url: string | null;
  changed_files: string[];
  elapsed_seconds?: number | null;
  timeout_minutes?: number | null;
  stdout_chars_discarded?: number | null;
  stderr_chars_discarded?: number | null;
  blockers: string[];
  token_printed: false;
}

export interface ManagedModePilotFinalizerPrSnapshot {
  exists: boolean;
  number: number | null;
  url: string | null;
  title: string | null;
  state: string;
  merged: boolean;
  base_ref: string | null;
  head_ref: string | null;
  changed_files: string[];
  token_printed: false;
}

export interface ManagedModePilotFinalizerState {
  schema: "skybridge.managed_mode_pilot_finalizer_state.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  state: "held_waiting_human_pr_review" | "ready_to_finalize" | "managed_mode_pilot_completed";
  final_state: "held_waiting_human_pr_review" | "managed_mode_pilot_completed";
  executor_evidence_path: string | null;
  finalizer_evidence_path: string | null;
  task_pr: ManagedModePilotFinalizerPrSnapshot;
  changed_files: string[];
  workunits_executed: number;
  task_count: number;
  claim_count: number;
  codex_execution_count: number;
  pr_count: number;
  no_second_workunit: boolean;
  no_second_task_pr: boolean;
  active_tasks: number;
  stale_leases: number;
  runner_lock: string;
  no_raw_artifacts: boolean;
  blockers: string[];
  token_printed: false;
}

export interface ManagedModePilotFinalizerEvidence {
  schema: "skybridge.managed_mode_pilot_finalizer_evidence.v1";
  pilot_id: string;
  mode: "managed_mode_v1_pilot";
  final_state: "managed_mode_pilot_completed";
  workunit_id: "managed-mode-pilot-208-workunit-001";
  task_id: "managed-mode-pilot-208-task-001";
  worker_id: "laptop-zenbookduo";
  task_pr: ManagedModePilotFinalizerPrSnapshot;
  changed_files: string[];
  workunits_executed: 1;
  task_count: 1;
  claim_count: 1;
  codex_execution_count: 1;
  pr_count: 1;
  no_second_workunit: true;
  no_second_task_pr: true;
  active_tasks: 0;
  stale_leases: 0;
  runner_lock: "none";
  no_raw_artifacts: true;
  executor_evidence_path: string;
  prompt_persisted: false;
  transcript_persisted: false;
  stdout_persisted: false;
  stderr_persisted: false;
  raw_logs_persisted: false;
  token_printed: false;
}

export interface ManagedModePilotFinalizerReport {
  schema: "skybridge.managed_mode_pilot_finalizer_report.v1";
  pilot_id: string;
  final_state: "managed_mode_pilot_completed";
  dashboard: {
    managed_mode_pilot_completed: true;
    no_next_execution_authorized: true;
    require_human_review: true;
    token_printed: false;
  };
  evidence_path: string;
  token_printed: false;
}

export interface ManagedModePilotFinalizerResult {
  schema: "skybridge.managed_mode_pilot_finalizer_result.v1";
  pilot_id: string;
  mode: "finalizer_preview" | "finalizer_apply" | "finalizer_apply_blocked";
  final_state: "held_waiting_human_pr_review" | "managed_mode_pilot_completed";
  state?: ManagedModePilotFinalizerState;
  evidence?: ManagedModePilotFinalizerEvidence;
  report?: ManagedModePilotFinalizerReport;
  evidence_path?: string | null;
  blockers?: string[];
  no_mutation?: boolean;
  token_printed: false;
}

export interface ManagedModeSequencePolicy {
  schema: "skybridge.managed_mode_sequence_policy.v1";
  max_open_runs: 1;
  max_workunits_per_run: 1;
  max_tasks_per_run: 1;
  max_claims_per_run: 1;
  max_codex_executions_per_run: 1;
  max_prs_per_run: 1;
  require_human_review: true;
  stop_on_pr_created: true;
  stop_on_ci_failure: true;
  stop_on_warning: true;
  general_bounded_queue_apply_enabled: false;
  one_at_a_time_run_apply_enabled: false;
  token_printed: false;
}

export interface ManagedModeRunRecord {
  schema:
    | "skybridge.managed_mode_run_record.v1"
    | "skybridge.managed_mode_completed_workunit_archive.v1";
  run_id: string;
  pilot_id?: string;
  managed_mode_run_id: string;
  sequence_number: number;
  source_workunit_id: string;
  task_id: string;
  worker_id: string;
  task_type: string;
  risk: "low" | "medium" | "high";
  allowed_paths: string[];
  state: "completed" | "held_waiting_human_pr_review" | "failed" | "blocked" | "ready";
  pr_url: string | null;
  pr_state: string;
  finalizer_evidence_path: string | null;
  evidence_hash: string | null;
  created_at: string | null;
  completed_at: string | null;
  token_printed: false;
}

export interface ManagedModeRunRegistry {
  schema: "skybridge.managed_mode_run_registry.v1";
  project_id: string;
  registry_id: string;
  sequence_policy: ManagedModeSequencePolicy;
  records: ManagedModeRunRecord[];
  completed_runs: ManagedModeRunRecord[];
  open_runs: ManagedModeRunRecord[];
  general_bounded_queue_apply_enabled: false;
  max_workunits: 1;
  token_printed: false;
}

export interface CoreEngineStatus {
  schema: "skybridge.core_engine_status.v1";
  module_status: {
    modules_added: string[];
    preferred_implementation_path: boolean;
    wrappers_compatible: boolean;
    token_printed: false;
  };
  completed_run_registry: {
    completed_run_ids: string[];
    active_tasks: number;
    stale_leases: number;
    runner_lock: string;
    open_managed_mode_pr_count: number;
    token_printed: false;
  };
  resource_gate_status: {
    resource_gate_required: boolean;
    can_run_one_at_a_time: boolean;
    blockers: string[];
    token_printed: false;
  };
  two_workunit_preview_status: {
    preview_workunit_count: number;
    apply_enabled: false;
    workunit_b_waits_for_a_finalized: boolean;
    token_printed: false;
  };
  drain_pause_preview_status: {
    drain_after_current: boolean;
    pause_after_current: boolean;
    pause_new_claims: boolean;
    token_printed: false;
  };
  apply_disabled_status: {
    general_bounded_queue_apply_enabled: false;
    multi_workunit_apply_enabled: false;
    reason: string;
    token_printed: false;
  };
  no_next_execution_authorized: true;
  token_printed: false;
}

export interface OneAtATimeManagedModeGate {
  schema: "skybridge.one_at_a_time_managed_mode_gate.v1";
  run_id: string;
  managed_mode_run_id: string;
  sequence_number: number;
  can_run_one_at_a_time?: boolean;
  explicit_209b_authorization_present?: boolean;
  run_apply_enabled?: false;
  apply_disabled_reason?: string;
  previous_run_208_completed?: boolean;
  completed_run_ids?: string[];
  open_run_count?: number;
  open_managed_mode_pr_count?: number;
  active_tasks?: number;
  stale_leases?: number;
  runner_lock?: string;
  general_bounded_queue_apply_enabled?: false;
  max_workunits?: number;
  blockers?: string[];
  source_workunit_id?: string;
  task_id?: string;
  worker_id?: string;
  task_type?: string;
  risk?: "low" | "medium" | "high";
  allowed_paths?: string[];
  target_path?: string;
  selected_workunit_count?: number;
  selected_worker_count?: 1;
  selected_worker_id?: string;
  would_create_task?: boolean;
  would_create_claim?: boolean;
  would_execute_codex?: boolean;
  would_create_pr?: boolean;
  no_mutation?: true;
  token_printed: false;
}

export interface ManagedModeRepeatabilitySummary {
  schema: "skybridge.managed_mode_repeatability_summary.v1";
  managed_mode_pilot_208: "completed";
  next_mode: "repeatable one-at-a-time preview";
  next_run_id: string;
  next_sequence_number: number;
  general_bounded_queue: "disabled";
  general_bounded_queue_apply_enabled: false;
  one_at_a_time_run_apply_enabled: false;
  can_run_one_at_a_time: boolean;
  apply_disabled_reason: string;
  completed_run_count: number;
  open_run_count: number;
  open_managed_mode_pr_count: number;
  active_tasks: number;
  stale_leases: number;
  runner_lock: string;
  next_safe_action: string;
  token_printed: false;
}

export interface ManagedModeV0CompletedRuns {
  schema: "skybridge.managed_mode_v0_completed_runs.v1";
  completed_run_count: number;
  completed_run_ids: string[];
  runs: ManagedModeRunRecord[];
  docs_local_smoke_runs_after_pilot?: string[];
  docs_local_smoke_run_count_after_pilot?: number;
  changed_files: string[];
  token_printed: false;
}

export interface ManagedModeV0ReleaseReadiness {
  schema: "skybridge.managed_mode_v0_release_readiness.v1";
  readiness_id?: string;
  self_bootstrap_v0_complete: true;
  managed_mode_pilot_complete: true;
  repeatable_one_at_a_time_run_complete: true;
  managed_mode_run_210_completed?: true;
  managed_mode_run_211_completed?: true;
  completed_runs: string[];
  docs_local_smoke_runs_after_pilot?: string[];
  docs_local_smoke_run_count_after_pilot?: number;
  active_tasks: number;
  stale_leases: number;
  runner_lock: string;
  open_managed_mode_pr_count: number;
  general_bounded_queue_apply_enabled: false;
  multi_workunit_queue_enabled: false;
  resource_gate_integrated?: true;
  resource_gate_required_for_next_run: true;
  next_run_requires_explicit_future_goal: true;
  no_next_execution_authorized: true;
  next_safe_action?: string;
  release_ready: boolean;
  blockers: string[];
  token_printed: false;
}

export interface ManagedModeV0OperatorGuidance {
  schema: "skybridge.managed_mode_v0_operator_guidance.v1";
  current_state: string;
  next_safe_action: string;
  banners: string[];
  disabled_actions: string[];
  token_printed: false;
}

export interface ManagedModeV0ReleaseReport {
  schema: "skybridge.managed_mode_v0_release_report.v1";
  status: ManagedModeV0Status;
  generated_at: string;
  report_path?: string;
  token_printed: false;
}

export interface ManagedModeV0Status {
  schema: "skybridge.managed_mode_v0_status.v1";
  product: "SkyBridge Agent Hub";
  status: "ready" | "blocked";
  completed_runs: ManagedModeV0CompletedRuns;
  release_readiness: ManagedModeV0ReleaseReadiness;
  operator_guidance: ManagedModeV0OperatorGuidance;
  token_printed: false;
}

export type BoincModeId =
  | "standby"
  | "armed_preview"
  | "start_one_review"
  | "bounded_queue_preview"
  | "bounded_queue_apply_disabled"
  | "managed_mode_disabled"
  | "emergency_stop"
  | "completed_bootstrap_trial";

export interface BoincMode {
  schema: "skybridge.boinc_mode.v1";
  mode_id: BoincModeId;
  display_name: string;
  description: string;
  enabled: boolean;
  reason_disabled: string | null;
  required_human_action: string[];
  allowed_actions: string[];
  blocked_actions: string[];
  next_safe_action: string;
  token_printed: false;
}

export interface BoincOperatorAction {
  action: string;
  display_name: string;
  enabled: boolean;
  reason_disabled: string | null;
  category: "allowed" | "disabled";
  token_printed: false;
}

export interface BoincOperatorActionMatrix {
  schema: "skybridge.boinc_operator_action_matrix.v1";
  allowed: BoincOperatorAction[];
  disabled: BoincOperatorAction[];
  task_created: false;
  task_claimed: false;
  task_executed: false;
  pr_created: false;
  token_printed: false;
}

export interface BoincReviewHold {
  schema: "skybridge.boinc_review_hold.v1";
  hold_id: string;
  hold_type: "human_review" | "execution_disabled" | "bootstrap_completed";
  title: string;
  status: "active" | "completed";
  reason: string;
  next_safe_action: string;
  token_printed: false;
}

export interface BoincControlSurface {
  schema: "skybridge.boinc_control_surface.v1";
  project_id: string;
  current_mode: BoincMode;
  modes: BoincMode[];
  action_matrix: BoincOperatorActionMatrix;
  review_holds: BoincReviewHold[];
  bounded_queue_readiness: BoundedQueueReadiness;
  workunit_preview_plan: BoundedQueuePlan;
  completed_bootstrap_trial: {
    campaign_id: "bootstrap-trial-201";
    final_state: "bootstrap_trial_completed";
    task_pr_url: string;
    finalizer_report: string;
    token_printed: false;
  };
  token_printed: false;
}

export interface BoincManagerState {
  schema: "skybridge.boinc_manager_state.v1";
  project_id: string;
  product_name: "SkyBridge Agent Hub";
  control_surface: BoincControlSurface;
  local_resident_state: DesktopResidentState;
  local_worker_supervisor_state: LocalWorkerSupervisorState;
  local_resource_policy: LocalResourcePolicy;
  workunit_preview_plan: BoundedQueuePlan;
  bounded_queue_readiness: BoundedQueueReadiness;
  active_holds: BoincReviewHold[];
  workunit_candidate_count?: number;
  next_safe_action: string;
  token_printed: false;
}

export interface BoincManagerSafeSummary {
  schema: "skybridge.boinc_manager_safe_summary.v1";
  project_id: string;
  mode_id: BoincModeId;
  mode_display_name: string;
  managed_mode_v1?: "pilot only";
  managed_mode_v1_summary?: string;
  managed_mode_pilot_state?: string;
  managed_mode_pilot_208?: string;
  next_mode?: string;
  next_run_id?: string | null;
  general_apply?: "disabled";
  general_bounded_queue?: "disabled";
  general_bounded_queue_apply_enabled?: false;
  one_at_a_time_run_apply_enabled?: false;
  apply_disabled_reason?: string;
  pilot_bounded_queue_apply_enabled?: boolean;
  one_workunit_pilot_possible_only_after_gate?: true;
  enabled: boolean;
  bounded_queue_apply_available: false;
  can_start_bounded_queue: false;
  active_hold_count: number;
  completed_bootstrap_trial: true;
  disabled_execution_actions: string[];
  allowed_operator_actions: string[];
  task_created: false;
  task_claimed: false;
  task_executed: false;
  pr_created: false;
  token_printed: false;
}

export interface BoincV1PreviewPolicy {
  schema: "skybridge.boinc_v1_preview_policy.v1";
  max_workunits_preview: 2;
  max_apply_workunits: 0;
  apply_enabled: false;
  run_apply_enabled: false;
  multi_workunit_apply_enabled: false;
  require_resource_gate: true;
  require_human_review: true;
  stop_on_pr_created: true;
  stop_on_ci_failure: true;
  stop_on_warning: true;
  token_printed: false;
}

export interface BoincV1PreviewWorkunit {
  schema: "skybridge.boinc_v1_preview_workunit.v1";
  workunit_id: string;
  task_id: null;
  project_id: "skybridge-agent-hub";
  task_type: "docs/local-smoke";
  risk: "low";
  queue_order: 1 | 2;
  target_path: string;
  allowed_paths: string[];
  requires_human_review: true;
  repo_mutating: true;
  serialization_group: "repo:skybridge-agent-hub";
  waits_for_workunit_id: string;
  state: "preview_only_not_created";
  task_created: false;
  task_claimed: false;
  codex_executed: false;
  pr_created: false;
  token_printed: false;
}

export interface BoincV1TwoWorkunitPreview {
  schema: "skybridge.boinc_v1_two_workunit_preview.v1";
  preview_id: "boinc-like-v1-two-workunit-preview";
  mode: "preview";
  policy: BoincV1PreviewPolicy;
  workunits: BoincV1PreviewWorkunit[];
  preview_workunit_count: 2;
  max_workunits_preview: 2;
  max_apply_workunits: 0;
  serializes_repo_mutating_work: true;
  no_parallel_mutation_in_one_repo: true;
  workunit_b_waits_for_a_finalized: true;
  open_review_count: number;
  blocked_by_open_review: boolean;
  blocked_reason: "none" | "blocked_by_open_review";
  apply_enabled: false;
  task_created: false;
  task_claimed: false;
  codex_executed: false;
  pr_created: false;
  no_mutation: true;
  token_printed: false;
}

export interface BoincV1ApplyGate {
  schema: "skybridge.boinc_v1_apply_gate.v1";
  can_apply: false;
  apply_enabled: false;
  run_apply_enabled: false;
  multi_workunit_apply_enabled: false;
  max_apply_workunits: 0;
  require_resource_gate: true;
  resource_gate: Record<string, unknown>;
  active_tasks: number;
  stale_leases: number;
  runner_lock: string;
  open_review_count: number;
  blockers: string[];
  task_created: false;
  task_claimed: false;
  codex_executed: false;
  pr_created: false;
  token_printed: false;
}

export interface BoincV1DrainPausePolicy {
  schema: "skybridge.boinc_v1_drain_pause_policy.v1";
  drain_after_current: true;
  pause_after_current: true;
  pause_new_claims: true;
  stop_on_pr_created: true;
  stop_on_ci_failure: true;
  stop_on_warning: true;
  emergency_stop: "preview_only";
  operator_hold: "preview_only";
  resource_gate_hold: "preview_only";
  review_hold: "preview_only";
  worker_started: false;
  worker_stopped: false;
  task_created: false;
  task_claimed: false;
  queue_apply_enabled: false;
  token_printed: false;
}

export interface BoincV1Action {
  action: "preview" | "pause" | "drain" | "resume_preview_only" | "emergency_stop_preview" | "apply_disabled";
  kind: string;
  enabled: false;
  preview_only: true;
  apply_enabled: false;
  reason_disabled: "boinc_v1_preview_only_no_execution_authorized";
  task_created: false;
  task_claimed: false;
  worker_started: false;
  worker_stopped: false;
  token_printed: false;
}

export interface BoincV1ActionMatrix {
  schema: "skybridge.boinc_v1_action_matrix.v1";
  actions: BoincV1Action[];
  all_actions_preview_only: true;
  apply_enabled: false;
  worker_started: false;
  worker_stopped: false;
  task_created: false;
  task_claimed: false;
  token_printed: false;
}

export interface BoincV1ReadinessReport {
  schema: "skybridge.boinc_v1_readiness_report.v1";
  readiness_id: "boinc_like_v1_readiness_preview";
  completed_managed_mode_runs: string[];
  resource_gate_state: Record<string, unknown>;
  worker_readiness_summary: {
    worker_id: "laptop-zenbookduo";
    can_claim_tasks: false;
    can_execute_tasks: false;
    mode: "preview_only";
    token_printed: false;
  };
  scheduler_preview: {
    selected_workunit_count: 2;
    max_parallel_per_repo: 1;
    serializes_repo_mutating_work: true;
    no_task_claim: true;
    no_execution: true;
    token_printed: false;
  };
  two_workunit_preview: BoincV1TwoWorkunitPreview;
  drain_pause_policy: BoincV1DrainPausePolicy;
  apply_disabled: true;
  no_next_execution_authorized: true;
  readiness_gaps_before_v1_apply: string[];
  next_safe_action: string;
  token_printed: false;
}

export interface BoincV1Status {
  schema: "skybridge.boinc_v1_status.v1";
  status: "preview_ready_apply_disabled";
  preview: BoincV1TwoWorkunitPreview;
  apply_gate: BoincV1ApplyGate;
  drain_pause_policy: BoincV1DrainPausePolicy;
  action_matrix: BoincV1ActionMatrix;
  readiness: BoincV1ReadinessReport;
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
  | "project_profile_validate"
  | "project_profile_preview"
  | "project_profile_list"
  | "project_profile_hash"
  | "project_select_preview"
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
  project_selection?: ProjectSelectionPreview;
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
  | "bootstrap_trial_completed"
  | "bounded_queue_preview_available"
  | "bounded_queue_apply_disabled"
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
  | "selected_worker_ready_for_preview_only"
  | "multi_worker_preview_available"
  | "worker_capability_mismatch"
  | "repo_parallelism_blocks_concurrent_work"
  | "scheduling_apply_disabled"
  | "project_profile_invalid"
  | "project_profile_missing"
  | "project_repo_path_invalid"
  | "project_default_branch_mismatch"
  | "project_policy_blocked_path"
  | "project_selection_preview_only"
  | "proposed_goal_created"
  | "proposed_goal_needs_review"
  | "proposed_goal_approved"
  | "proposed_goal_blocked"
  | "proposed_goal_rejected"
  | "proposed_goal_import_preview_ready"
  | "proposed_goal_imported"
  | "workunit_candidates_available"
  | "workunit_candidate_blocked"
  | "workunit_candidate_requires_review"
  | "candidate_execution_disabled"
  | "imported_goal_requires_execution_review"
  | "unsafe_import_blocked"
  | "unsafe_goal_draft_detected"
  | "import_requires_goal_200";

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
    "project_profile_validate",
    "project_profile_preview",
    "project_profile_list",
    "project_profile_hash",
    "project_select_preview",
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
        blockers: ["execution_apply_deferred_until_goal_199"],
        warnings: [],
        summary: "Armed execution is modeled but forbidden until a later reviewed project bootstrap gate.",
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

export const fixtureProjectProfileReviewSummary: ProjectProfileReviewSummary = {
  schema: "skybridge.project_profile_review_summary.v1",
  project_id: "skybridge-agent-hub",
  display_name: "SkyBridge Agent Hub",
  validation_status: "valid",
  validation_errors: [],
  validation_warnings: [],
  repo_identity: "JerrySkywalker/skybridge-agent-hub",
  repo_path_display: "V:/src/skybridge-agent-hub",
  default_branch: "main",
  allowed_paths: [
    ".",
    "apps/desktop",
    "apps/web",
    "config/project-profiles",
    "docs/dev",
    "goals/dev-queue-189-200",
    "packages/client",
    "scripts/powershell",
  ],
  blocked_paths: [
    ".env",
    ".env.local",
    ".agent/runs",
    ".data",
    "deploy/production",
    "docs/operations/openresty-hermes-api.example.conf",
  ],
  validation_commands: [
    {
      id: "pnpm-check",
      command: "corepack pnpm check",
      known_fixture: false,
      executes: false,
    },
    {
      id: "powershell-parse",
      command: "pwsh -ExecutionPolicy Bypass -File scripts/powershell/validate-powershell.ps1",
      known_fixture: false,
      executes: false,
    },
  ],
  worker_profile_summary: {
    default_worker_profile: "laptop-zenbookduo-standby",
    allowed_worker_profiles: ["laptop-zenbookduo-standby", "linux-ci-preview"],
    can_claim_tasks: false,
    can_execute_tasks: false,
  },
  goal_pack_summary: {
    default_goal_pack_dir: "goals/dev-queue-189-200",
    allowed_goal_pack_dirs: ["goals/dev-queue-189-200"],
    import_apply_enabled: false,
  },
  policy_summary: {
    fixture_only: false,
    dry_run_default: true,
    selection_preview_only: true,
    forbid_arbitrary_shell: true,
    forbid_secret_fields: true,
    forbid_production_paths: true,
  },
  profile_hash: "258fbacefb78c8d8bd42900c90fbc04ff6d7dd020204cb4bdd9c67d1a2e24d7a",
  no_execution_controls: true,
  token_printed: false,
};

export const fixtureProjectSelectionPreview: ProjectSelectionPreview = {
  schema: "skybridge.project_selection_preview.v1",
  mode: "preview",
  selected_project_id: fixtureProjectProfileReviewSummary.project_id,
  profile_hash: fixtureProjectProfileReviewSummary.profile_hash,
  repo_identity: fixtureProjectProfileReviewSummary.repo_identity,
  repo_path_display: fixtureProjectProfileReviewSummary.repo_path_display,
  default_branch: fixtureProjectProfileReviewSummary.default_branch,
  allowed_path_summary: `${fixtureProjectProfileReviewSummary.allowed_paths.length} allowed paths; ${fixtureProjectProfileReviewSummary.blocked_paths.length} blocked paths`,
  worker_profile_summary: fixtureProjectProfileReviewSummary.worker_profile_summary,
  goal_pack_summary: fixtureProjectProfileReviewSummary.goal_pack_summary,
  blocked_reason: null,
  project_selection_preview_only: true,
  task_created: false,
  task_claimed: false,
  task_executed: false,
  worker_loop_started: false,
  queue_execution_enabled: false,
  validation_commands_executed: false,
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
  task_id: "preview-super-198-local-smoke",
  task_type: "local-smoke",
  project_id: "skybridge-agent-hub",
  repo_id: "skybridge-agent-hub",
  project_profile_required: true,
  project_profile_hash: fixtureProjectProfileReviewSummary.profile_hash,
  project_selection_preview_only: true,
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

export const fixtureWorkerProfiles: WorkerProfile[] = fixtureWorkerCapabilityMatrix.map((entry, index) => ({
  schema: "skybridge.worker_profile.v1",
  worker_id: entry.worker_id,
  display_name: entry.worker_label,
  host_label: index === 1 ? "linux-ci-preview" : "laptop-zenbookduo",
  os: entry.os,
  arch: "x64",
  location_label: index === 1 ? "ci-preview" : "local-desktop",
  worker_group: index === 1 ? "ci-preview" : "local-preview",
  supported_task_types: entry.task_type_capabilities,
  supported_projects: entry.project_access,
  supported_repos: entry.repo_access,
  tools_available: entry.tools,
  can_claim_tasks: false,
  can_execute_tasks: false,
  max_concurrent_workunits: 1,
  heartbeat_at: index === 1 ? "2026-06-08T23:45:00.000Z" : "2026-06-09T00:00:00.000Z",
  stale_after_seconds: 300,
  resource_policy_summary: "preview only; local resource policy gates execution",
  trust_level: index === 3 ? "untrusted_fixture" : index === 1 ? "ci_fixture" : "local_operator",
  token_printed: false,
}));

export const fixtureWorkerPool: WorkerPool = {
  schema: "skybridge.worker_pool.v1",
  workers: fixtureWorkerProfiles,
  groups: Array.from(new Set(fixtureWorkerProfiles.map((worker) => worker.worker_group))),
  preview_only: true,
  token_printed: false,
};

export const fixtureWorkerAvailability: WorkerAvailability[] = fixtureWorkerReadiness.map((entry) => ({
  schema: "skybridge.worker_availability.v1",
  worker_id: entry.worker_id,
  state: entry.readiness_state === "online" && entry.readiness_blockers.length === 0
    ? "ready_preview_only"
    : entry.readiness_state === "unknown"
      ? "offline"
      : entry.readiness_state,
  heartbeat_age_seconds: entry.heartbeat_age_seconds,
  busy_workunit_id: entry.current_task_id,
  readiness_blockers: entry.readiness_blockers,
  score: entry.readiness_score,
  token_printed: false,
}));

export const fixtureWorkerScores: WorkerScore[] = fixtureWorkerRoutingReadiness.route_preview.decisions.map((decision) => ({
  schema: "skybridge.worker_score.v1",
  worker_id: decision.worker_id,
  score: decision.accepted ? decision.readiness_score : 0,
  factors: decision.accepted ? ["task_type", "project_repo", "tools", "heartbeat", "trust_level"] : [],
  blockers: decision.rejection_reasons,
  token_printed: false,
}));

export const fixtureRepoParallelismPolicy: RepoParallelismPolicy = {
  schema: "skybridge.repo_parallelism_policy.v1",
  repo_id: "skybridge-agent-hub",
  max_parallel_per_repo: 1,
  mutating_work_serialized: true,
  read_only_parallel_allowed_when_explicit: true,
  uncertain_counts_as_mutating: true,
  token_printed: false,
};

const fixtureSchedulingWorkunitId = "workunit-bootstrap-trial-201-task-001";

export const fixtureWorkunitRoutePlan: WorkunitRoutePlan = {
  schema: "skybridge.workunit_route_plan.v1",
  plan_id: "route-plan-preview-bootstrap-trial-201",
  mode: "preview",
  selected_routes: [
    {
      workunit_id: fixtureSchedulingWorkunitId,
      selected_worker_id: fixtureWorkerRoutingReadiness.route_preview.selected_worker?.worker_id ?? null,
      queue_order: 1,
      serialized_by_repo_policy: true,
      token_printed: false,
    },
  ],
  rejected_workers: fixtureWorkerRoutingReadiness.route_preview.rejected_workers.map((decision) => ({
    schema: "skybridge.worker_capability_match.v1",
    worker_id: decision.worker_id,
    workunit_id: fixtureSchedulingWorkunitId,
    accepted: false,
    score: decision.readiness_score,
    rejected_reasons: decision.rejection_reasons,
    token_printed: false,
  })),
  policy_blockers: ["scheduling_apply_disabled"],
  task_claimed: false,
  lease_created: false,
  task_executed: false,
  pr_created: false,
  token_printed: false,
};

export const fixtureSchedulingPreview: SchedulingPreview = {
  schema: "skybridge.scheduling_preview.v1",
  preview_id: "multi-worker-scheduling-preview-bootstrap-trial-201",
  worker_pool: fixtureWorkerPool,
  availability: fixtureWorkerAvailability,
  scores: fixtureWorkerScores,
  repo_parallelism_policy: fixtureRepoParallelismPolicy,
  route_plan: fixtureWorkunitRoutePlan,
  apply_available: false,
  task_claimed: false,
  lease_created: false,
  task_executed: false,
  pr_created: false,
  token_printed: false,
};

export const fixtureMultiWorkerReadiness: MultiWorkerReadiness = {
  schema: "skybridge.multi_worker_readiness.v1",
  worker_pool_count: fixtureWorkerPool.workers.length,
  ready_preview_only_count: fixtureWorkerAvailability.filter((worker) => worker.state === "ready_preview_only").length,
  stale_count: fixtureWorkerAvailability.filter((worker) => worker.state === "stale").length,
  disabled_count: fixtureWorkerAvailability.filter((worker) => worker.state === "disabled").length,
  apply_available: false,
  blockers: ["scheduling_apply_disabled", "preview_only_no_claim_no_lease_no_execution"],
  attention_events: [
    "multi_worker_preview_available",
    "worker_stale",
    "worker_capability_mismatch",
    "repo_parallelism_blocks_concurrent_work",
    "scheduling_apply_disabled",
  ],
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
    "execution_disabled_until_goal_199",
  ],
  token_available: false,
  token_printed: false,
};

export const fixtureDesktopResidentState: DesktopResidentState = {
  schema: "skybridge.desktop_resident_state.v1",
  tray_available: true,
  window_visible: true,
  close_to_tray_supported: false,
  autostart_supported: false,
  autostart_enabled: false,
  resident_mode: "tray_resident_preview",
  last_refresh_at: "2026-06-09T00:00:00.000Z",
  token_printed: false,
};

export const fixtureLocalWorkerSupervisorState: LocalWorkerSupervisorState = {
  schema: "skybridge.local_worker_supervisor_state.v1",
  worker_id: "laptop-zenbookduo",
  worker_service_mode: "offline",
  heartbeat_age_seconds: null,
  current_task_id: null,
  can_claim_tasks: false,
  can_execute_tasks: false,
  readiness_blockers: [
    "standby_metadata_only",
    "task_claim_disabled",
    "execution_disabled_until_bounded_queue_authorization",
  ],
  pause_requested: false,
  stop_requested: false,
  last_local_evidence_at: null,
  token_printed: false,
};

export const fixtureLocalResourcePolicy: LocalResourcePolicy = {
  schema: "skybridge.local_resource_policy.v1",
  require_ac_power: true,
  pause_on_battery: true,
  pause_below_battery_percent: 30,
  require_idle: false,
  max_cpu_percent: 65,
  max_memory_percent: 90,
  network_required: true,
  allowed_hours: "00:00-23:59 local",
  lid_sleep_note: "No powercfg mutation; operator-managed Windows sleep/lid behavior.",
  sleep_lid_behavior_note: "No powercfg mutation; operator-managed Windows sleep/lid behavior.",
  policy_source: "fixture",
  enforcement_status: "enforced",
  observation_source: "fixture",
  battery_state: "unknown",
  battery_percent: null,
  ac_power: null,
  memory_used_percent: null,
  cpu_summary: "preview only",
  blockers: [],
  warnings: ["cpu usage is advisory in fixture mode"],
  can_run_one_at_a_time: true,
  token_printed: false,
};

export const fixtureLocalResourceObservation: LocalResourceObservation = {
  schema: "skybridge.local_resource_observation.v1",
  observation_source: "fixture",
  battery_state: "ac_power",
  battery_percent: 95,
  ac_power: true,
  memory_used_percent: 42,
  cpu_percent: null,
  network_available: true,
  current_local_time: "12:00",
  token_printed: false,
};

export const fixtureLocalResourcePolicyEnforcement: LocalResourcePolicyEnforcement = {
  schema: "skybridge.local_resource_policy_enforcement.v1",
  policy: fixtureLocalResourcePolicy,
  observation: fixtureLocalResourceObservation,
  blockers: [],
  warnings: ["cpu usage is advisory"],
  can_run_one_at_a_time: true,
  task_claimed: false,
  task_executed: false,
  no_powercfg_mutation: true,
  admin_required: false,
  token_printed: false,
};

export const fixtureLocalRunAllowance: LocalRunAllowance = {
  schema: "skybridge.local_run_allowance.v1",
  run_id: "managed-mode-run-210",
  explicit_authorization_required: true,
  resource_gate_required: true,
  can_run_one_at_a_time: false,
  blockers: ["explicit_future_goal_required"],
  token_printed: false,
};

export const fixtureLocalExecutionGuard: LocalExecutionGuard = {
  schema: "skybridge.local_execution_guard.v1",
  execution_disabled: true,
  start_one_enabled: false,
  start_queue_enabled: false,
  start_all_present: false,
  resume_execution_enabled: false,
  arbitrary_shell_available: false,
  bounded_queue_execution_enabled: false,
  reason: "Goal 203A is resident supervisor and policy visibility only.",
  next_safe_action: "Standby worker may be observed or heartbeated; execution remains disabled until bounded queue/workunit goals authorize it.",
  token_printed: false,
};

export const fixtureBoundedQueuePolicy: BoundedQueuePolicy = {
  schema: "skybridge.bounded_queue_policy.v1",
  max_steps: 1,
  max_tasks: 1,
  max_prs: 0,
  max_runtime_minutes: 30,
  max_parallel_per_repo: 1,
  stop_on_pr_created: true,
  stop_on_ci_failure: true,
  stop_on_warning: true,
  drain_after_current: true,
  pause_after_current: true,
  require_human_review: true,
  allow_task_types: ["docs_refresh", "infrastructure_preview"],
  block_task_types: ["production_change", "server_root_change", "secret_mutation", "unbounded_worker_loop"],
  token_printed: false,
};

export const fixtureBootstrapTrialWorkunit: Workunit = {
  schema: "skybridge.workunit.v1",
  workunit_id: "workunit-bootstrap-trial-201-task-001",
  project_id: "skybridge-agent-hub",
  campaign_id: "bootstrap-trial-201",
  goal_id: "goal-201-controlled-start-one-bootstrap-trial",
  task_id: "bootstrap-trial-201-task-001",
  task_type: "docs_refresh",
  required_capabilities: ["codex_exec_adapter", "repo_local_docs"],
  allowed_paths: ["docs/local-smoke-orientation.md"],
  risk: "low",
  state: "completed",
  lease_id: null,
  lease_owner: null,
  lease_expires_at: null,
  retry_count: 0,
  max_retries: 0,
  deadline: null,
  result_artifact: ".agent/tmp/bootstrap-trial-201-one-shot/trial-report.json",
  evidence_artifact: ".agent/tmp/bootstrap-trial-201-one-shot/finalizer-evidence.json",
  pr_url: "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/124",
  ci_status: "not_applicable",
  token_printed: false,
};

export const fixtureBootstrapTrialWorkunitLease: WorkunitLease = {
  schema: "skybridge.workunit_lease.v1",
  lease_id: null,
  lease_owner: null,
  lease_expires_at: null,
  token_printed: false,
};

export const fixtureBootstrapTrialWorkunitResult: WorkunitResult = {
  schema: "skybridge.workunit_result.v1",
  result_artifact: fixtureBootstrapTrialWorkunit.result_artifact,
  evidence_artifact: fixtureBootstrapTrialWorkunit.evidence_artifact,
  pr_url: fixtureBootstrapTrialWorkunit.pr_url,
  ci_status: fixtureBootstrapTrialWorkunit.ci_status,
  token_printed: false,
};

export const fixtureBootstrapTrialWorkunitState: WorkunitStateEnvelope = {
  schema: "skybridge.workunit_state.v1",
  workunit_id: fixtureBootstrapTrialWorkunit.workunit_id,
  state: fixtureBootstrapTrialWorkunit.state,
  terminal: true,
  requires_human_review: false,
  token_printed: false,
};

export const fixtureProposedGoalWorkunitCandidate: ProposedGoalWorkunitCandidate = {
  schema: "skybridge.proposed_goal_workunit_candidate.v1",
  candidate_id: "candidate-proposed-goal-201-local-readme-refresh",
  source_proposed_goal_id: "proposed-goal-201-local-readme-refresh",
  source_goal_path: "goals/proposed/proposed-goal-201-local-readme-refresh.md",
  reviewed_goal_path: "goals/reviewed/proposed-goal-201-local-readme-refresh.md",
  project_id: "skybridge-agent-hub",
  campaign_id: "bootstrap-trial-201",
  candidate_pack_id: "candidate-pack-proposed-goals-preview",
  suggested_workunit_id: "workunit-candidate-proposed-goal-201-local-readme-refresh",
  suggested_task_type: "docs",
  risk: "low",
  allowed_paths: ["docs/**", "scripts/powershell/smoke-*.ps1"],
  blocked_paths: [".env*", "deploy/**", "docs/operations/openresty-*", "config/hermes*", ".github/**"],
  required_capabilities: ["codex", "repo_local_docs"],
  estimated_runtime_minutes: 20,
  max_prs: 0,
  requires_human_review: true,
  conversion_status: "candidate_ready",
  blockers: [],
  warnings: ["preview_only_execution_disabled", "bounded_queue_apply_disabled", "execution_review_required"],
  content_hash: "a80296ad3f06fd009c1c82a8caa68e337821bc538040fb01141eff47ae6785fb",
  manifest_hash: "manifest-preview-201-local-readme-refresh",
  token_printed: false,
};

export const fixtureBlockedWorkunitCandidate: ProposedGoalWorkunitCandidate = {
  schema: "skybridge.proposed_goal_workunit_candidate.v1",
  candidate_id: "candidate-proposed-unsafe-production-deploy",
  source_proposed_goal_id: "proposed-unsafe-production-deploy",
  source_goal_path: "goals/proposed/proposed-unsafe-production-deploy.md",
  reviewed_goal_path: null,
  project_id: "skybridge-agent-hub",
  campaign_id: null,
  candidate_pack_id: "candidate-pack-proposed-goals-preview",
  suggested_workunit_id: "blocked-workunit-proposed-unsafe-production-deploy",
  suggested_task_type: "production_deploy",
  risk: "blocked",
  allowed_paths: [],
  blocked_paths: ["deploy/**", ".env*", ".github/**", "docs/operations/**", "config/hermes*"],
  required_capabilities: [],
  estimated_runtime_minutes: 0,
  max_prs: 0,
  requires_human_review: true,
  conversion_status: "blocked",
  blockers: ["production_deploy", "secret_rotation", "github_settings", "branch_protection", "auto_execution"],
  warnings: ["blocked_high_risk_surface"],
  content_hash: "5314ffd66b9f4013ff44822c2fced00ddfc4784b98210903c65efd60d4a09111",
  manifest_hash: "manifest-blocked-production-deploy",
  token_printed: false,
};

export const fixtureWorkunitCandidateRiskGate: WorkunitCandidateRiskGate = {
  schema: "skybridge.workunit_candidate_risk_gate.v1",
  candidate_id: fixtureProposedGoalWorkunitCandidate.candidate_id,
  decision: "allow_candidate_ready",
  reasons: ["low_risk_docs_or_local_smoke", "reviewed_goal_preview_ready", "execution_disabled"],
  blocked_terms: [],
  generated_goal_self_approved: false,
  token_printed: false,
};

export const fixtureBlockedWorkunitCandidateRiskGate: WorkunitCandidateRiskGate = {
  schema: "skybridge.workunit_candidate_risk_gate.v1",
  candidate_id: fixtureBlockedWorkunitCandidate.candidate_id,
  decision: "blocked",
  reasons: fixtureBlockedWorkunitCandidate.blockers,
  blocked_terms: ["production deploy", "secret rotation", "GitHub settings", "branch protection", "auto-execution"],
  generated_goal_self_approved: false,
  token_printed: false,
};

export const fixtureGoalToWorkunitConversion: GoalToWorkunitConversion = {
  schema: "skybridge.goal_to_workunit_conversion.v1",
  conversion_id: "conversion-proposed-goals-to-workunit-candidates-preview",
  mode: "preview",
  candidate_count: 2,
  candidate_ready_count: 1,
  blocked_count: 1,
  execution_review_required: true,
  task_created: false,
  task_claimed: false,
  task_executed: false,
  pr_created: false,
  token_printed: false,
};

export const fixtureWorkunitCandidateReview: WorkunitCandidateReview = {
  schema: "skybridge.workunit_candidate_review.v1",
  candidate_id: fixtureProposedGoalWorkunitCandidate.candidate_id,
  review_status: "requires_human_review",
  reviewer: "operator_required",
  execution_review_required: true,
  token_printed: false,
};

export const fixtureWorkunitCandidateManifest: WorkunitCandidateManifest = {
  schema: "skybridge.workunit_candidate_manifest.v1",
  manifest_id: "manifest-proposed-goal-workunit-candidates-preview",
  candidate_pack_id: "candidate-pack-proposed-goals-preview",
  manifest_path: ".agent/tmp/workunit-candidates/candidate-pack-proposed-goals-preview.json",
  manifest_hash: "manifest-preview-proposed-goal-workunit-candidates",
  candidates: [fixtureProposedGoalWorkunitCandidate, fixtureBlockedWorkunitCandidate],
  execution_review_required: true,
  apply_available: false,
  task_created: false,
  task_claimed: false,
  task_executed: false,
  token_printed: false,
};

export const fixtureWorkunitCandidatePack: WorkunitCandidatePack = {
  schema: "skybridge.workunit_candidate_pack.v1",
  candidate_pack_id: "candidate-pack-proposed-goals-preview",
  project_id: "skybridge-agent-hub",
  campaign_id: "bootstrap-trial-201",
  candidates: [fixtureProposedGoalWorkunitCandidate, fixtureBlockedWorkunitCandidate],
  risk_gates: [fixtureWorkunitCandidateRiskGate, fixtureBlockedWorkunitCandidateRiskGate],
  candidate_ready_count: 1,
  blocked_count: 1,
  requires_review_count: 1,
  bounded_queue_preview_only: true,
  apply_available: false,
  execution_disabled: true,
  next_safe_action: "Review candidate pack and keep execution disabled until a future explicit bounded-queue apply goal authorizes it.",
  token_printed: false,
};

export const fixtureBoundedQueuePlan: BoundedQueuePlan = {
  schema: "skybridge.bounded_queue_plan.v1",
  plan_id: "bounded-queue-preview-bootstrap-trial-201",
  mode: "preview",
  campaign_id: "bootstrap-trial-201",
  project_id: "skybridge-agent-hub",
  policy: fixtureBoundedQueuePolicy,
  workunits: [fixtureBootstrapTrialWorkunit],
  workunit_candidate_pack: fixtureWorkunitCandidatePack,
  candidate_preview_count: fixtureWorkunitCandidatePack.candidates.length,
  would_create_tasks: false,
  would_claim_tasks: false,
  would_execute_tasks: false,
  would_create_prs: false,
  would_start_runner: false,
  no_mutation: true,
  token_printed: false,
};

export const fixtureBoundedQueueReadiness: BoundedQueueReadiness = {
  schema: "skybridge.bounded_queue_readiness.v1",
  campaign_id: "bootstrap-trial-201",
  project_id: "skybridge-agent-hub",
  can_start_bounded_queue: false,
  start_bounded_queue_apply_available: false,
  bounded_queue_execution_enabled: false,
  blockers: [
    "bounded_queue_apply_not_yet_enabled",
    "requires_future_goal_authorization",
  ],
  warnings: ["preview_only_no_task_creation_no_claim_no_execution_no_pr"],
  next_safe_action: "Review the workunit preview and keep bounded queue apply disabled until a future explicit goal authorizes execution.",
  token_printed: false,
};

export const fixtureBoincModes: BoincMode[] = [
  {
    schema: "skybridge.boinc_mode.v1",
    mode_id: "standby",
    display_name: "Standby",
    description: "Read-only operator view with local resident worker visibility.",
    enabled: true,
    reason_disabled: null,
    required_human_action: [],
    allowed_actions: ["refresh", "open_logs", "view_worker", "view_workunits"],
    blocked_actions: ["start_all", "worker_claim", "task_execution"],
    next_safe_action: "Refresh status or inspect the completed bootstrap trial evidence.",
    token_printed: false,
  },
  {
    schema: "skybridge.boinc_mode.v1",
    mode_id: "armed_preview",
    display_name: "Armed Preview",
    description: "Preview-only planning state; no claims, tasks, runners or execution are created.",
    enabled: true,
    reason_disabled: null,
    required_human_action: ["review_action_matrix"],
    allowed_actions: ["refresh", "view_workunits", "view_finalizer_report"],
    blocked_actions: ["start_one_apply", "start_queue_apply", "bounded_queue_apply"],
    next_safe_action: "Review the action matrix and keep apply paths disabled.",
    token_printed: false,
  },
  {
    schema: "skybridge.boinc_mode.v1",
    mode_id: "start_one_review",
    display_name: "Start-One Review",
    description: "Historical review of the completed one-shot bootstrap task.",
    enabled: false,
    reason_disabled: "bootstrap_trial_completed_no_second_task_authorized",
    required_human_action: ["review_pr_124_and_finalizer_report"],
    allowed_actions: ["view_task_pr", "view_finalizer_report"],
    blocked_actions: ["create_task_pr", "auto_merge", "task_execution"],
    next_safe_action: "Use the finalizer evidence as read-only history.",
    token_printed: false,
  },
  {
    schema: "skybridge.boinc_mode.v1",
    mode_id: "bounded_queue_preview",
    display_name: "Bounded Queue Preview",
    description: "Shows the workunit queue plan while apply remains unavailable.",
    enabled: true,
    reason_disabled: null,
    required_human_action: ["review_bounded_queue_readiness"],
    allowed_actions: ["view_workunits", "refresh"],
    blocked_actions: ["bounded_queue_apply", "worker_claim", "task_execution"],
    next_safe_action: fixtureBoundedQueueReadiness.next_safe_action,
    token_printed: false,
  },
  {
    schema: "skybridge.boinc_mode.v1",
    mode_id: "bounded_queue_apply_disabled",
    display_name: "Bounded Queue Apply Disabled",
    description: "The apply path is intentionally absent for Goal 205A.",
    enabled: false,
    reason_disabled: "bounded_queue_apply_not_yet_enabled",
    required_human_action: ["future_goal_must_authorize_apply"],
    allowed_actions: ["view_workunits"],
    blocked_actions: ["start_queue_apply", "bounded_queue_apply", "resume_execution"],
    next_safe_action: "Keep using preview-only queue state.",
    token_printed: false,
  },
  {
    schema: "skybridge.boinc_mode.v1",
    mode_id: "managed_mode_disabled",
    display_name: "Managed Mode Disabled",
    description: "BOINC-like managed execution is not yet authorized.",
    enabled: false,
    reason_disabled: "managed_execution_requires_future_explicit_goal",
    required_human_action: ["authorize_future_managed_mode_goal"],
    allowed_actions: ["refresh", "view_worker"],
    blocked_actions: ["worker_claim", "task_execution", "start_all"],
    next_safe_action: "Use the manager as a read-only control plane.",
    token_printed: false,
  },
  {
    schema: "skybridge.boinc_mode.v1",
    mode_id: "emergency_stop",
    display_name: "Emergency Stop",
    description: "Metadata-only stop state for already-supported safe stop surfaces.",
    enabled: false,
    reason_disabled: "no_active_execution_to_stop",
    required_human_action: ["use_existing_queue_control_if_a_future_run_is_active"],
    allowed_actions: ["safe_stop_metadata"],
    blocked_actions: ["start_all", "resume_execution"],
    next_safe_action: "No active task is running; remain in Standby.",
    token_printed: false,
  },
  {
    schema: "skybridge.boinc_mode.v1",
    mode_id: "completed_bootstrap_trial",
    display_name: "Completed Bootstrap Trial",
    description: "Goal 201/202B finalizer evidence shows bootstrap-trial-201 is complete.",
    enabled: true,
    reason_disabled: null,
    required_human_action: [],
    allowed_actions: ["view_task_pr", "view_finalizer_report"],
    blocked_actions: ["create_task_pr", "auto_merge", "second_task"],
    next_safe_action: "Use the completed trial as the reference workunit history.",
    token_printed: false,
  },
];

export const fixtureBoincOperatorActionMatrix: BoincOperatorActionMatrix = {
  schema: "skybridge.boinc_operator_action_matrix.v1",
  allowed: [
    "refresh",
    "open_logs",
    "view_worker",
    "view_workunits",
    "view_task_pr",
    "view_finalizer_report",
    "safe_pause_metadata",
    "safe_stop_metadata",
  ].map((action) => ({
    action,
    display_name: action.replaceAll("_", " "),
    enabled: true,
    reason_disabled: null,
    category: "allowed",
    token_printed: false,
  })),
  disabled: [
    "start_one_apply",
    "start_queue_apply",
    "bounded_queue_apply",
    "start_all",
    "resume_execution",
    "worker_claim",
    "task_execution",
    "auto_merge",
  ].map((action) => ({
    action,
    display_name: action.replaceAll("_", " "),
    enabled: false,
    reason_disabled: "execution_disabled_in_goal_205a_preview_only",
    category: "disabled",
    token_printed: false,
  })),
  task_created: false,
  task_claimed: false,
  task_executed: false,
  pr_created: false,
  token_printed: false,
};

export const fixtureBoincReviewHolds: BoincReviewHold[] = [
  {
    schema: "skybridge.boinc_review_hold.v1",
    hold_id: "bounded-queue-apply-disabled",
    hold_type: "execution_disabled",
    title: "Bounded queue apply disabled",
    status: "active",
    reason: "Goal 205A exposes manager controls but does not authorize apply.",
    next_safe_action: fixtureBoundedQueueReadiness.next_safe_action,
    token_printed: false,
  },
  {
    schema: "skybridge.boinc_review_hold.v1",
    hold_id: "bootstrap-trial-201-completed",
    hold_type: "bootstrap_completed",
    title: "bootstrap-trial-201 completed",
    status: "completed",
    reason: "Goal 202B finalizer recorded bootstrap_trial_completed after PR #124 merged.",
    next_safe_action: "Reference the finalizer report; do not create another task.",
    token_printed: false,
  },
];

export const fixtureBoincControlSurface: BoincControlSurface = {
  schema: "skybridge.boinc_control_surface.v1",
  project_id: "skybridge-agent-hub",
  current_mode: fixtureBoincModes[0],
  modes: fixtureBoincModes,
  action_matrix: fixtureBoincOperatorActionMatrix,
  review_holds: fixtureBoincReviewHolds,
  bounded_queue_readiness: fixtureBoundedQueueReadiness,
  workunit_preview_plan: fixtureBoundedQueuePlan,
  completed_bootstrap_trial: {
    campaign_id: "bootstrap-trial-201",
    final_state: "bootstrap_trial_completed",
    task_pr_url: "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/124",
    finalizer_report: ".agent/tmp/bootstrap-trial-201-one-shot/finalizer-evidence.json",
    token_printed: false,
  },
  token_printed: false,
};

export const fixtureBoincManagerState: BoincManagerState = {
  schema: "skybridge.boinc_manager_state.v1",
  project_id: "skybridge-agent-hub",
  product_name: "SkyBridge Agent Hub",
  control_surface: fixtureBoincControlSurface,
  local_resident_state: fixtureDesktopResidentState,
  local_worker_supervisor_state: fixtureLocalWorkerSupervisorState,
  local_resource_policy: fixtureLocalResourcePolicy,
  workunit_preview_plan: fixtureBoundedQueuePlan,
  bounded_queue_readiness: fixtureBoundedQueueReadiness,
  active_holds: fixtureBoincReviewHolds.filter((hold) => hold.status === "active"),
  next_safe_action: fixtureBoincModes[0].next_safe_action,
  workunit_candidate_count: fixtureWorkunitCandidatePack.candidates.length,
  token_printed: false,
};

export const fixtureBoincManagerSafeSummary: BoincManagerSafeSummary = {
  schema: "skybridge.boinc_manager_safe_summary.v1",
  project_id: "skybridge-agent-hub",
  mode_id: fixtureBoincManagerState.control_surface.current_mode.mode_id,
  mode_display_name: fixtureBoincManagerState.control_surface.current_mode.display_name,
  enabled: fixtureBoincManagerState.control_surface.current_mode.enabled,
  bounded_queue_apply_available: false,
  can_start_bounded_queue: false,
  active_hold_count: fixtureBoincManagerState.active_holds.length,
  completed_bootstrap_trial: true,
  disabled_execution_actions: fixtureBoincOperatorActionMatrix.disabled.map((item) => item.action),
  allowed_operator_actions: fixtureBoincOperatorActionMatrix.allowed.map((item) => item.action),
  task_created: false,
  task_claimed: false,
  task_executed: false,
  pr_created: false,
  token_printed: false,
};

export const fixtureManagedModeSequencePolicy: ManagedModeSequencePolicy = {
  schema: "skybridge.managed_mode_sequence_policy.v1",
  max_open_runs: 1,
  max_workunits_per_run: 1,
  max_tasks_per_run: 1,
  max_claims_per_run: 1,
  max_codex_executions_per_run: 1,
  max_prs_per_run: 1,
  require_human_review: true,
  stop_on_pr_created: true,
  stop_on_ci_failure: true,
  stop_on_warning: true,
  general_bounded_queue_apply_enabled: false,
  one_at_a_time_run_apply_enabled: false,
  token_printed: false,
};

export const fixtureManagedModeCompleted208Archive: ManagedModeRunRecord = {
  schema: "skybridge.managed_mode_completed_workunit_archive.v1",
  run_id: "managed-mode-pilot-208",
  pilot_id: "managed-mode-pilot-208",
  managed_mode_run_id: "managed-mode-pilot-208",
  sequence_number: 1,
  source_workunit_id: "managed-mode-pilot-208-workunit-001",
  task_id: "managed-mode-pilot-208-task-001",
  worker_id: "laptop-zenbookduo",
  task_type: "docs/local-smoke",
  risk: "low",
  allowed_paths: ["docs/managed-mode-pilot-orientation.md"],
  state: "completed",
  pr_url: "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/140",
  pr_state: "merged",
  finalizer_evidence_path: ".agent/tmp/managed-mode-pilot-208/finalizer-evidence.json",
  evidence_hash: "fixture-managed-mode-pilot-208-finalizer-hash",
  created_at: "2026-06-10T00:00:00.000Z",
  completed_at: "2026-06-10T00:00:00.000Z",
  token_printed: false,
};

export const fixtureManagedModeCompleted209Archive: ManagedModeRunRecord = {
  schema: "skybridge.managed_mode_run_record.v1",
  run_id: "managed-mode-run-209",
  managed_mode_run_id: "managed-mode-run-209",
  sequence_number: 2,
  source_workunit_id: "managed-mode-run-209-workunit-001",
  task_id: "managed-mode-run-209-task-001",
  worker_id: "laptop-zenbookduo",
  task_type: "docs/local-smoke",
  risk: "low",
  allowed_paths: ["docs/managed-mode-repeatability-orientation.md"],
  state: "completed",
  pr_url: "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/144",
  pr_state: "merged",
  finalizer_evidence_path: ".agent/tmp/managed-mode-run-209/finalizer-evidence.json",
  evidence_hash: "fixture-managed-mode-run-209-finalizer-hash",
  created_at: "2026-06-12T00:00:00.000Z",
  completed_at: "2026-06-12T00:30:11.5283244Z",
  token_printed: false,
};

export const fixtureManagedModeCompleted210Archive: ManagedModeRunRecord = {
  schema: "skybridge.managed_mode_run_record.v1",
  run_id: "managed-mode-run-210",
  managed_mode_run_id: "managed-mode-run-210",
  sequence_number: 3,
  source_workunit_id: "managed-mode-run-210-workunit-001",
  task_id: "managed-mode-run-210-task-001",
  worker_id: "laptop-zenbookduo",
  task_type: "docs/local-smoke",
  risk: "low",
  allowed_paths: ["docs/managed-mode-v0-operator-checklist.md"],
  state: "completed",
  pr_url: "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/148",
  pr_state: "merged",
  finalizer_evidence_path: ".agent/tmp/managed-mode-run-210/finalizer-evidence.json",
  evidence_hash: "fixture-managed-mode-run-210-finalizer-hash",
  created_at: "2026-06-12T01:08:07.000Z",
  completed_at: "2026-06-12T01:23:28.6095154Z",
  token_printed: false,
};

export const fixtureManagedModeCompleted211Archive: ManagedModeRunRecord = {
  schema: "skybridge.managed_mode_run_record.v1",
  run_id: "managed-mode-run-211",
  managed_mode_run_id: "managed-mode-run-211",
  sequence_number: 4,
  source_workunit_id: "managed-mode-run-211-workunit-001",
  task_id: "managed-mode-run-211-task-001",
  worker_id: "laptop-zenbookduo",
  task_type: "docs/local-smoke",
  risk: "low",
  allowed_paths: ["docs/managed-mode-v0-repeatability-check.md"],
  state: "completed",
  pr_url: "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/151",
  pr_state: "merged",
  finalizer_evidence_path: ".agent/tmp/managed-mode-run-211/finalizer-evidence.json",
  evidence_hash: "fixture-managed-mode-run-211-finalizer-hash",
  created_at: "2026-06-12T03:18:09.0677048Z",
  completed_at: "2026-06-12T03:22:27.000Z",
  token_printed: false,
};

export const fixtureManagedModeRunRegistry: ManagedModeRunRegistry = {
  schema: "skybridge.managed_mode_run_registry.v1",
  project_id: "skybridge-agent-hub",
  registry_id: "skybridge-managed-mode-run-registry",
  sequence_policy: fixtureManagedModeSequencePolicy,
  records: [fixtureManagedModeCompleted208Archive, fixtureManagedModeCompleted209Archive, fixtureManagedModeCompleted210Archive, fixtureManagedModeCompleted211Archive],
  completed_runs: [fixtureManagedModeCompleted208Archive, fixtureManagedModeCompleted209Archive, fixtureManagedModeCompleted210Archive, fixtureManagedModeCompleted211Archive],
  open_runs: [],
  general_bounded_queue_apply_enabled: false,
  max_workunits: 1,
  token_printed: false,
};

export const fixtureCoreEngineStatus: CoreEngineStatus = {
  schema: "skybridge.core_engine_status.v1",
  module_status: {
    modules_added: [
      "Skybridge.Core",
      "Skybridge.CodexExecutor",
      "Skybridge.ResourceGate",
      "Skybridge.WorkunitRegistry",
      "Skybridge.EvidenceStore",
      "Skybridge.PrPackager",
      "Skybridge.Finalizer",
      "Skybridge.QueuePolicy",
      "Skybridge.SafetyScanner",
      "Skybridge.SmokeHarness",
    ],
    preferred_implementation_path: true,
    wrappers_compatible: true,
    token_printed: false,
  },
  completed_run_registry: {
    completed_run_ids: ["managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211"],
    active_tasks: 0,
    stale_leases: 0,
    runner_lock: "none",
    open_managed_mode_pr_count: 0,
    token_printed: false,
  },
  resource_gate_status: {
    resource_gate_required: true,
    can_run_one_at_a_time: true,
    blockers: [],
    token_printed: false,
  },
  two_workunit_preview_status: {
    preview_workunit_count: 2,
    apply_enabled: false,
    workunit_b_waits_for_a_finalized: true,
    token_printed: false,
  },
  drain_pause_preview_status: {
    drain_after_current: true,
    pause_after_current: true,
    pause_new_claims: true,
    token_printed: false,
  },
  apply_disabled_status: {
    general_bounded_queue_apply_enabled: false,
    multi_workunit_apply_enabled: false,
    reason: "core_engine_consolidation_no_execution_boundary",
    token_printed: false,
  },
  no_next_execution_authorized: true,
  token_printed: false,
};

export const fixtureOneAtATimeManagedModeGate: OneAtATimeManagedModeGate = {
  schema: "skybridge.one_at_a_time_managed_mode_gate.v1",
  run_id: "managed-mode-run-212",
  managed_mode_run_id: "managed-mode-run-212",
  sequence_number: 5,
  can_run_one_at_a_time: false,
  explicit_209b_authorization_present: false,
  run_apply_enabled: false,
  apply_disabled_reason: "one_at_a_time_run_apply_disabled_by_default",
  previous_run_208_completed: true,
  completed_run_ids: ["managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211"],
  open_run_count: 0,
  open_managed_mode_pr_count: 0,
  active_tasks: 0,
  stale_leases: 0,
  runner_lock: "none",
  general_bounded_queue_apply_enabled: false,
  max_workunits: 1,
  blockers: ["no_next_execution_authorized"],
  source_workunit_id: "managed-mode-run-212-workunit-preview-001",
  task_id: "managed-mode-run-212-task-preview-001",
  worker_id: "laptop-zenbookduo",
  task_type: "docs/local-smoke",
  risk: "low",
  allowed_paths: ["README.md", "docs/**"],
  target_path: "docs/managed-mode-v0-9-two-workunit-preview.md",
  selected_workunit_count: 2,
  selected_worker_count: 1,
  selected_worker_id: "laptop-zenbookduo",
  would_create_task: false,
  would_create_claim: false,
  would_execute_codex: false,
  would_create_pr: false,
  no_mutation: true,
  token_printed: false,
};

export const fixtureManagedModeRepeatabilitySummary: ManagedModeRepeatabilitySummary = {
  schema: "skybridge.managed_mode_repeatability_summary.v1",
  managed_mode_pilot_208: "completed",
  next_mode: "repeatable one-at-a-time preview",
  next_run_id: "managed-mode-run-212",
  next_sequence_number: 5,
  general_bounded_queue: "disabled",
  general_bounded_queue_apply_enabled: false,
  one_at_a_time_run_apply_enabled: false,
  can_run_one_at_a_time: false,
  apply_disabled_reason: "one_at_a_time_run_apply_disabled_by_default",
  completed_run_count: 4,
  open_run_count: 0,
  open_managed_mode_pr_count: 0,
  active_tasks: 0,
  stale_leases: 0,
  runner_lock: "none",
  next_safe_action: "plan two-workunit preview only",
  token_printed: false,
};

export const fixtureManagedModeV0CompletedRuns: ManagedModeV0CompletedRuns = {
  schema: "skybridge.managed_mode_v0_completed_runs.v1",
  completed_run_count: 4,
  completed_run_ids: ["managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211"],
  runs: [fixtureManagedModeCompleted208Archive, fixtureManagedModeCompleted209Archive, fixtureManagedModeCompleted210Archive, fixtureManagedModeCompleted211Archive],
  docs_local_smoke_runs_after_pilot: ["managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211"],
  docs_local_smoke_run_count_after_pilot: 3,
  changed_files: ["docs/managed-mode-pilot-orientation.md", "docs/managed-mode-repeatability-orientation.md", "docs/managed-mode-v0-operator-checklist.md", "docs/managed-mode-v0-repeatability-check.md"],
  token_printed: false,
};

export const fixtureManagedModeV0ReleaseReadiness: ManagedModeV0ReleaseReadiness = {
  schema: "skybridge.managed_mode_v0_release_readiness.v1",
  readiness_id: "managed_mode_v0_9_readiness",
  self_bootstrap_v0_complete: true,
  managed_mode_pilot_complete: true,
  repeatable_one_at_a_time_run_complete: true,
  managed_mode_run_210_completed: true,
  managed_mode_run_211_completed: true,
  completed_runs: ["managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211"],
  docs_local_smoke_runs_after_pilot: ["managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211"],
  docs_local_smoke_run_count_after_pilot: 3,
  active_tasks: 0,
  stale_leases: 0,
  runner_lock: "none",
  open_managed_mode_pr_count: 0,
  general_bounded_queue_apply_enabled: false,
  multi_workunit_queue_enabled: false,
  resource_gate_integrated: true,
  resource_gate_required_for_next_run: true,
  next_run_requires_explicit_future_goal: true,
  no_next_execution_authorized: true,
  next_safe_action: "plan two-workunit preview only",
  release_ready: true,
  blockers: [],
  token_printed: false,
};

export const fixtureManagedModeV0OperatorGuidance: ManagedModeV0OperatorGuidance = {
  schema: "skybridge.managed_mode_v0_operator_guidance.v1",
  current_state: "managed_mode_v0_9_readiness",
  next_safe_action: "plan two-workunit preview only",
  banners: ["Managed Mode v0.9 readiness", "Resource gate required before next run", "No next execution authorized", "General bounded queue apply disabled"],
  disabled_actions: ["start-all", "start-queue apply", "bounded queue apply", "multi-workunit apply", "resume -Apply", "unbounded worker loop"],
  token_printed: false,
};

export const fixtureManagedModeV0Status: ManagedModeV0Status = {
  schema: "skybridge.managed_mode_v0_status.v1",
  product: "SkyBridge Agent Hub",
  status: "ready",
  completed_runs: fixtureManagedModeV0CompletedRuns,
  release_readiness: fixtureManagedModeV0ReleaseReadiness,
  operator_guidance: fixtureManagedModeV0OperatorGuidance,
  token_printed: false,
};

export const fixtureBoincV1PreviewPolicy: BoincV1PreviewPolicy = {
  schema: "skybridge.boinc_v1_preview_policy.v1",
  max_workunits_preview: 2,
  max_apply_workunits: 0,
  apply_enabled: false,
  run_apply_enabled: false,
  multi_workunit_apply_enabled: false,
  require_resource_gate: true,
  require_human_review: true,
  stop_on_pr_created: true,
  stop_on_ci_failure: true,
  stop_on_warning: true,
  token_printed: false,
};

export const fixtureBoincV1PreviewWorkunitA: BoincV1PreviewWorkunit = {
  schema: "skybridge.boinc_v1_preview_workunit.v1",
  workunit_id: "boinc-v1-preview-workunit-a",
  task_id: null,
  project_id: "skybridge-agent-hub",
  task_type: "docs/local-smoke",
  risk: "low",
  queue_order: 1,
  target_path: "docs/boinc-v1-preview-workunit-a.md",
  allowed_paths: ["docs/boinc-v1-preview-workunit-a.md"],
  requires_human_review: true,
  repo_mutating: true,
  serialization_group: "repo:skybridge-agent-hub",
  waits_for_workunit_id: "",
  state: "preview_only_not_created",
  task_created: false,
  task_claimed: false,
  codex_executed: false,
  pr_created: false,
  token_printed: false,
};

export const fixtureBoincV1PreviewWorkunitB: BoincV1PreviewWorkunit = {
  schema: "skybridge.boinc_v1_preview_workunit.v1",
  workunit_id: "boinc-v1-preview-workunit-b",
  task_id: null,
  project_id: "skybridge-agent-hub",
  task_type: "docs/local-smoke",
  risk: "low",
  queue_order: 2,
  target_path: "docs/boinc-v1-preview-workunit-b.md",
  allowed_paths: ["docs/boinc-v1-preview-workunit-b.md"],
  requires_human_review: true,
  repo_mutating: true,
  serialization_group: "repo:skybridge-agent-hub",
  waits_for_workunit_id: "boinc-v1-preview-workunit-a",
  state: "preview_only_not_created",
  task_created: false,
  task_claimed: false,
  codex_executed: false,
  pr_created: false,
  token_printed: false,
};

export const fixtureBoincV1TwoWorkunitPreview: BoincV1TwoWorkunitPreview = {
  schema: "skybridge.boinc_v1_two_workunit_preview.v1",
  preview_id: "boinc-like-v1-two-workunit-preview",
  mode: "preview",
  policy: fixtureBoincV1PreviewPolicy,
  workunits: [fixtureBoincV1PreviewWorkunitA, fixtureBoincV1PreviewWorkunitB],
  preview_workunit_count: 2,
  max_workunits_preview: 2,
  max_apply_workunits: 0,
  serializes_repo_mutating_work: true,
  no_parallel_mutation_in_one_repo: true,
  workunit_b_waits_for_a_finalized: true,
  open_review_count: 0,
  blocked_by_open_review: false,
  blocked_reason: "none",
  apply_enabled: false,
  task_created: false,
  task_claimed: false,
  codex_executed: false,
  pr_created: false,
  no_mutation: true,
  token_printed: false,
};

export const fixtureBoincV1ApplyGate: BoincV1ApplyGate = {
  schema: "skybridge.boinc_v1_apply_gate.v1",
  can_apply: false,
  apply_enabled: false,
  run_apply_enabled: false,
  multi_workunit_apply_enabled: false,
  max_apply_workunits: 0,
  require_resource_gate: true,
  resource_gate: {
    schema: "skybridge.local_run_allowance.v1",
    can_run_one_at_a_time: true,
    blockers: [],
    token_printed: false,
  },
  active_tasks: 0,
  stale_leases: 0,
  runner_lock: "none",
  open_review_count: 0,
  blockers: ["apply_disabled", "multi_workunit_apply_disabled"],
  task_created: false,
  task_claimed: false,
  codex_executed: false,
  pr_created: false,
  token_printed: false,
};

export const fixtureBoincV1DrainPausePolicy: BoincV1DrainPausePolicy = {
  schema: "skybridge.boinc_v1_drain_pause_policy.v1",
  drain_after_current: true,
  pause_after_current: true,
  pause_new_claims: true,
  stop_on_pr_created: true,
  stop_on_ci_failure: true,
  stop_on_warning: true,
  emergency_stop: "preview_only",
  operator_hold: "preview_only",
  resource_gate_hold: "preview_only",
  review_hold: "preview_only",
  worker_started: false,
  worker_stopped: false,
  task_created: false,
  task_claimed: false,
  queue_apply_enabled: false,
  token_printed: false,
};

export const fixtureBoincV1ActionMatrix: BoincV1ActionMatrix = {
  schema: "skybridge.boinc_v1_action_matrix.v1",
  actions: [
    "preview",
    "pause",
    "drain",
    "resume_preview_only",
    "emergency_stop_preview",
    "apply_disabled",
  ].map((action) => ({
    action: action as BoincV1Action["action"],
    kind: action === "apply_disabled" ? "disabled_apply" : `${action}_preview`,
    enabled: false,
    preview_only: true,
    apply_enabled: false,
    reason_disabled: "boinc_v1_preview_only_no_execution_authorized",
    task_created: false,
    task_claimed: false,
    worker_started: false,
    worker_stopped: false,
    token_printed: false,
  })),
  all_actions_preview_only: true,
  apply_enabled: false,
  worker_started: false,
  worker_stopped: false,
  task_created: false,
  task_claimed: false,
  token_printed: false,
};

export const fixtureBoincV1ReadinessReport: BoincV1ReadinessReport = {
  schema: "skybridge.boinc_v1_readiness_report.v1",
  readiness_id: "boinc_like_v1_readiness_preview",
  completed_managed_mode_runs: fixtureManagedModeV0CompletedRuns.completed_run_ids,
  resource_gate_state: fixtureBoincV1ApplyGate.resource_gate,
  worker_readiness_summary: {
    worker_id: "laptop-zenbookduo",
    can_claim_tasks: false,
    can_execute_tasks: false,
    mode: "preview_only",
    token_printed: false,
  },
  scheduler_preview: {
    selected_workunit_count: 2,
    max_parallel_per_repo: 1,
    serializes_repo_mutating_work: true,
    no_task_claim: true,
    no_execution: true,
    token_printed: false,
  },
  two_workunit_preview: fixtureBoincV1TwoWorkunitPreview,
  drain_pause_policy: fixtureBoincV1DrainPausePolicy,
  apply_disabled: true,
  no_next_execution_authorized: true,
  readiness_gaps_before_v1_apply: [
    "reliable two-workunit finalizer",
    "desktop resident enforcement",
    "failure budget policy",
    "queue drain implementation",
    "operator approval flow",
    "release/audit docs",
    "long-run evidence retention model",
    "explicit v1 authorization goal",
  ],
  next_safe_action: "review two-workunit preview and drain policy; keep apply disabled",
  token_printed: false,
};

export const fixtureBoincV1Status: BoincV1Status = {
  schema: "skybridge.boinc_v1_status.v1",
  status: "preview_ready_apply_disabled",
  preview: fixtureBoincV1TwoWorkunitPreview,
  apply_gate: fixtureBoincV1ApplyGate,
  drain_pause_policy: fixtureBoincV1DrainPausePolicy,
  action_matrix: fixtureBoincV1ActionMatrix,
  readiness: fixtureBoincV1ReadinessReport,
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
  operator_reason: "Goal 198 fixture: campaign remains held for project policy review before execution.",
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
      current_goal_id: "super-198-multi-project-support",
      current_step_id: "dev-queue-189-200:super-198-multi-project-support",
      blocked_reason: "project_selection_preview_only",
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
    blocked_campaign_reason: "project_selection_preview_only",
    queue_decision_summary: "dev-queue-189-200 is highest priority; project selection is preview-only and cannot claim or execute tasks.",
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
  if (state.mode === "ready") warnings.add("ready_mode_still_execution_disabled_until_goal_199");
  if (state.pause_requested) blockers.add("pause_requested");
  if (state.stop_requested) blockers.add("stop_requested");
  if (state.current_task_id) blockers.add("current_task_present");
  blockers.add("execution_disabled_until_goal_199");

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
  desktop_resident_state?: DesktopResidentState;
  local_worker_supervisor_state?: LocalWorkerSupervisorState;
  local_resource_policy?: LocalResourcePolicy;
  local_execution_guard?: LocalExecutionGuard;
  workunit_preview_plan?: BoundedQueuePlan;
  bounded_queue_readiness?: BoundedQueueReadiness;
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
  selected_project_id?: string;
  project_profile_hash?: string;
  project_validation_status?: "valid" | "invalid" | "missing";
  project_selection_preview_only?: boolean;
  proposed_goal_count?: number;
  pending_proposed_goal_review_count?: number;
  blocked_proposed_goal_count?: number;
  proposed_goal_next_action?: string;
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

export type ProposedGoalSource = "fixture" | "hermes" | "manual";
export type ProposedGoalSafetyClassification = "low" | "medium" | "high" | "blocked";
export type ProposedGoalReviewStatus =
  | "proposed"
  | "needs_review"
  | "approved"
  | "rejected"
  | "edited"
  | "imported"
  | "superseded"
  | "approved_for_import";

export interface ProposedGoalDraft {
  draft_id?: string;
  proposed_goal_id: string;
  title: string;
  source: ProposedGoalSource;
  proposed_markdown_path: string;
  content_hash: string;
  original_hash?: string;
  edited_hash?: string | null;
  safety_classification: ProposedGoalSafetyClassification;
  risk_level?: ProposedGoalSafetyClassification;
  review_status: ProposedGoalReviewStatus;
  reviewer?: string;
  decision?: string | null;
  decision_reason?: string | null;
  import_status?: "not_imported" | "preview_ready" | "imported" | "blocked";
  import_target?: string | null;
  import_preview?: {
    import_target: string;
    manifest_path: string;
    manifest_diff: string[];
    dependency_order_changes: string[];
    validation_blockers: string[];
    execution_review_required: true;
  } | null;
  suggested_order: number;
  suggested_dependencies: string[];
  allowed_task_types: string[];
  blocked_task_types: string[];
  expected_outputs: string[];
  review_notes: string[];
  blocked_reasons: string[];
  generated_at: string;
  reviewed_at?: string | null;
  token_printed: false;
}

export interface ProposedGoalSafeSummary {
  schema: "skybridge.proposed_goal_safe_summary.v1";
  proposed_goal_count: number;
  pending_review_count: number;
  approved_count?: number;
  rejected_count?: number;
  imported_count?: number;
  blocked_draft_count: number;
  import_target?: string | null;
  blocked_reason?: string | null;
  next_action: "review proposed goals in Goal 200";
  import_requires_goal_200: true;
  imported: false;
  executed: false;
  task_created: false;
  worker_loop_started: false;
  token_printed: false;
}

export interface ProposedGoalReviewSummary {
  schema: "skybridge.proposed_goal_review_summary.v1";
  proposed_goal_count: number;
  pending_review_count: number;
  approved_count: number;
  rejected_count: number;
  imported_count: number;
  blocked_draft_count: number;
  import_target: string;
  blocked_reason: string | null;
  next_action: "review proposed goals in Goal 200";
  import_requires_goal_200: true;
  imported: false;
  executed: false;
  task_created: false;
  worker_loop_started: false;
  proposed_goals: ProposedGoalDraft[];
  review_controls: {
    approve_preview: "reason-gated";
    reject_preview: "reason-gated";
    edit_staged: "hash-recompute";
    import_preview: "dry-run";
    import_apply: "disabled-until-approved-and-confirmed";
    execute_imported_goal: "not_available";
  };
  import_preview_summary: {
    target_path: string;
    manifest_diff: string[];
    dependency_order_changes: string[];
    hash_changes: string[];
    validation_blockers: string[];
    dry_run_first: true;
    execution_review_required: true;
  };
  no_import_button: true;
  no_execute_button: true;
  no_execution_controls: true;
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
    selected_project_id: readiness.project_selection?.selected_project_id ?? readiness.project_profile?.project_id,
    project_profile_hash: readiness.project_selection?.profile_hash ?? readiness.project_profile?.profile_hash,
    project_validation_status: readiness.project_profile?.validation_status,
    project_selection_preview_only: readiness.project_selection?.project_selection_preview_only ?? false,
    proposed_goal_count: readiness.proposed_goal_summary?.proposed_goal_count ?? 0,
    pending_proposed_goal_review_count: readiness.proposed_goal_summary?.pending_review_count ?? 0,
    blocked_proposed_goal_count: readiness.proposed_goal_summary?.blocked_draft_count ?? 0,
    proposed_goal_next_action: readiness.proposed_goal_summary?.next_action,
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
      "bootstrap_trial_completed",
      "bounded_queue_preview_available",
      "bounded_queue_apply_disabled",
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
      "project_profile_invalid",
      "project_profile_missing",
      "project_repo_path_invalid",
      "project_default_branch_mismatch",
      "project_policy_blocked_path",
      "project_selection_preview_only",
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
      "bounded_queue_apply_disabled",
      "proposed_goal_created",
      "proposed_goal_needs_review",
      "proposed_goal_blocked",
      "proposed_goal_rejected",
      "unsafe_goal_draft_detected",
      "import_requires_goal_200",
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
      "proposed_goal_blocked",
      "unsafe_goal_draft_detected",
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
    event_types: ["ci_failed", "emergency_stop_requested", "unsafe_goal_draft_detected"],
    real_external_send: false,
    summary: "Real ntfy delivery is disabled by default and represented as not configured.",
    token_printed: false,
  },
  {
    route: "disabled",
    status: "disabled",
    levels: ["info"],
    event_types: ["goal_ready", "goal_completed", "bootstrap_trial_completed", "pr_created", "safe_action_applied", "notification_delivery_skipped", "notification_delivery_fixture", "proposed_goal_created", "proposed_goal_needs_review", "proposed_goal_rejected", "import_requires_goal_200"],
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
  const boundedQueueReadiness = report.bounded_queue_readiness;

  if (report.workunit_preview_plan) {
    events.push(
      makeAttentionEvent(
        report,
        "bounded_queue_preview_available",
        "info",
        "queue_control",
        "Bounded queue preview is available without mutation.",
        "Inspect workunit mapping and keep bounded queue apply disabled.",
        "bounded_queue_preview",
      ),
    );
  }

  if (boundedQueueReadiness && !boundedQueueReadiness.start_bounded_queue_apply_available) {
    events.push(
      makeAttentionEvent(
        report,
        "bounded_queue_apply_disabled",
        "blocker",
        "queue_control",
        "Bounded queue apply is disabled by policy.",
        boundedQueueReadiness.next_safe_action,
        "bounded_queue_apply",
      ),
    );
  }

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

  const projectProfile = readiness.project_profile;
  const projectSelection = readiness.project_selection;
  if (!projectProfile) {
    events.push(
      makeAttentionEvent(
        report,
        "project_profile_missing",
        "blocker",
        "queue_control",
        "Selected project profile is missing.",
        "Add a safe project profile and validate it before any future project onboarding.",
        "project_profile_missing",
      ),
    );
  } else {
    if (projectProfile.validation_status !== "valid") {
      events.push(
        makeAttentionEvent(
          report,
          "project_profile_invalid",
          "blocker",
          "queue_control",
          `Project profile ${projectProfile.project_id} is invalid.`,
          "Review profile validation errors before any future queue execution gate.",
          projectProfile.project_id,
        ),
      );
    }
    if (projectProfile.validation_errors.some((error) => error.includes("repo_path"))) {
      events.push(
        makeAttentionEvent(
          report,
          "project_repo_path_invalid",
          "blocker",
          "queue_control",
          `Project repo path is invalid for ${projectProfile.project_id}.`,
          "Keep project selection preview-only until the repo path is approved and inside the declared root.",
          "repo_path",
        ),
      );
    }
    if (projectProfile.validation_warnings.includes("project_default_branch_mismatch")) {
      events.push(
        makeAttentionEvent(
          report,
          "project_default_branch_mismatch",
          "warning",
          "queue_control",
          `Project default branch mismatch for ${projectProfile.project_id}.`,
          "Confirm the expected default branch before onboarding or importing goals.",
          "default_branch",
        ),
      );
    }
    if (projectProfile.validation_errors.some((error) => error.includes("blocked_operational") || error.includes("blocked_path"))) {
      events.push(
        makeAttentionEvent(
          report,
          "project_policy_blocked_path",
          "blocker",
          "queue_control",
          `Project policy blocked a path for ${projectProfile.project_id}.`,
          "Remove production/server-root/DNS/OpenResty/Hermes or out-of-repo paths from the profile.",
          "blocked_path",
        ),
      );
    }
  }
  if (projectSelection?.project_selection_preview_only) {
    events.push(
      makeAttentionEvent(
        report,
        "project_selection_preview_only",
        "info",
        "queue_control",
        `Project ${projectSelection.selected_project_id} is selected for preview only.`,
        "Do not claim tasks or mutate another repository from project selection.",
        "project_selection",
      ),
    );
  }

  const proposedSummary = readiness.proposed_goal_summary;
  if (proposedSummary) {
    if (proposedSummary.proposed_goal_count > 0) {
      events.push(
        makeAttentionEvent(
          report,
          "proposed_goal_created",
          "info",
          "campaign",
          `${proposedSummary.proposed_goal_count} proposed goal draft(s) are available for human review.`,
          proposedSummary.next_action,
          "proposed_goals",
        ),
      );
    }
    if (proposedSummary.pending_review_count > 0) {
      events.push(
        makeAttentionEvent(
          report,
          "proposed_goal_needs_review",
          "action_required",
          "campaign",
          `${proposedSummary.pending_review_count} proposed goal draft(s) need review.`,
          proposedSummary.next_action,
          "proposed_goals_pending_review",
        ),
      );
    }
    if ((proposedSummary.approved_count ?? 0) > 0) {
      events.push(
        makeAttentionEvent(
          report,
          "proposed_goal_approved",
          "info",
          "campaign",
          `${proposedSummary.approved_count} proposed goal draft(s) are approved for controlled import preview.`,
          "Run import-preview first; do not execute imported goals.",
          "proposed_goals_approved",
        ),
      );
      events.push(
        makeAttentionEvent(
          report,
          "proposed_goal_import_preview_ready",
          "info",
          "campaign",
          "A controlled import preview can be generated for approved proposed goals.",
          "Review manifest diff, dependencies, hash changes and blockers before any import apply.",
          "import_preview_ready",
        ),
      );
    }
    if ((proposedSummary.rejected_count ?? 0) > 0) {
      events.push(
        makeAttentionEvent(
          report,
          "proposed_goal_rejected",
          "info",
          "campaign",
          `${proposedSummary.rejected_count} proposed goal draft(s) have been rejected.`,
          "Keep rejected drafts out of import staging.",
          "proposed_goals_rejected",
        ),
      );
    }
    if ((proposedSummary.imported_count ?? 0) > 0) {
      events.push(
        makeAttentionEvent(
          report,
          "proposed_goal_imported",
          "info",
          "campaign",
          `${proposedSummary.imported_count} proposed goal draft(s) are staged as reviewed imports.`,
          "Imported goals remain pending execution review in a later goal.",
          "proposed_goals_imported",
        ),
      );
      events.push(
        makeAttentionEvent(
          report,
          "imported_goal_requires_execution_review",
          "action_required",
          "campaign",
          "Imported proposed goals require separate future execution approval.",
          "Do not create tasks, claim work, or start queue execution from import state.",
          "imported_goal_execution_review",
        ),
      );
    }
    if (proposedSummary.blocked_draft_count > 0) {
      events.push(
        makeAttentionEvent(
          report,
          "proposed_goal_blocked",
          "blocker",
          "campaign",
          `${proposedSummary.blocked_draft_count} proposed goal draft(s) are blocked by the safety filter.`,
          "Reject or rewrite blocked proposed drafts during Goal 200 review.",
          "proposed_goals_blocked",
        ),
      );
      events.push(
        makeAttentionEvent(
          report,
          "unsafe_import_blocked",
          "blocker",
          "campaign",
          "Unsafe proposed goal import is blocked by risk gating.",
          "Reject or rewrite the unsafe draft; import remains disabled.",
          "unsafe_import_blocked",
        ),
      );
      events.push(
        makeAttentionEvent(
          report,
          "unsafe_goal_draft_detected",
          "critical",
          "campaign",
          "Unsafe proposed goal draft content was detected by the fixture safety filter.",
          "Do not import or execute blocked drafts; review them in Goal 200.",
          "unsafe_goal_draft",
        ),
      );
    }
    if (proposedSummary.import_requires_goal_200) {
      events.push(
        makeAttentionEvent(
          report,
          "import_requires_goal_200",
          "info",
          "campaign",
          "Proposed goal import is deferred to Goal 200.",
          proposedSummary.next_action,
          "goal_200_import_gate",
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

export const fixtureProposedGoalReviewSummary: ProposedGoalReviewSummary = {
  schema: "skybridge.proposed_goal_review_summary.v1",
  proposed_goal_count: 2,
  pending_review_count: 1,
  approved_count: 1,
  rejected_count: 1,
  imported_count: 0,
  blocked_draft_count: 1,
  import_target: "goals/reviewed",
  blocked_reason: "unsafe_import_blocked",
  next_action: "review proposed goals in Goal 200",
  import_requires_goal_200: true,
  imported: false,
  executed: false,
  task_created: false,
  worker_loop_started: false,
  proposed_goals: [
    {
      draft_id: "proposed-goal-201-local-readme-refresh",
      proposed_goal_id: "proposed-goal-201-local-readme-refresh",
      title: "Goal 201 Local README Refresh",
      source: "fixture",
      proposed_markdown_path: "goals/proposed/proposed-goal-201-local-readme-refresh.md",
      content_hash: "a80296ad3f06fd009c1c82a8caa68e337821bc538040fb01141eff47ae6785fb",
      original_hash: "a80296ad3f06fd009c1c82a8caa68e337821bc538040fb01141eff47ae6785fb",
      edited_hash: null,
      safety_classification: "low",
      risk_level: "low",
      review_status: "approved",
      reviewer: "local-operator",
      decision: "approved",
      decision_reason: "low-risk docs fixture approved for dry-run-first import preview",
      import_status: "preview_ready",
      import_target: "goals/reviewed/proposed-goal-201-local-readme-refresh.md",
      import_preview: {
        import_target: "goals/reviewed/proposed-goal-201-local-readme-refresh.md",
        manifest_path: "goals/reviewed/manifest.skybridge-goal-import.json",
        manifest_diff: ["add proposed-goal-201-local-readme-refresh to reviewed import manifest"],
        dependency_order_changes: ["order=201", "depends_on=super-200-controlled-goal-draft-review-import"],
        validation_blockers: [],
        execution_review_required: true,
      },
      suggested_order: 201,
      suggested_dependencies: ["super-200-controlled-goal-draft-review-import"],
      allowed_task_types: ["docs", "local-smoke"],
      blocked_task_types: ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection", "auto_execution"],
      expected_outputs: ["reviewed_docs", "fixture_smoke"],
      review_notes: ["Fixture-generated proposed goal for human review only."],
      blocked_reasons: [],
      generated_at: "2026-06-08T00:00:00.000Z",
      reviewed_at: "2026-06-08T00:00:00.000Z",
      token_printed: false,
    },
    {
      draft_id: "proposed-unsafe-production-deploy",
      proposed_goal_id: "proposed-unsafe-production-deploy",
      title: "Unsafe Production Deployment",
      source: "fixture",
      proposed_markdown_path: "goals/proposed/proposed-unsafe-production-deploy.md",
      content_hash: "5314ffd66b9f4013ff44822c2fced00ddfc4784b98210903c65efd60d4a09111",
      original_hash: "5314ffd66b9f4013ff44822c2fced00ddfc4784b98210903c65efd60d4a09111",
      edited_hash: null,
      safety_classification: "blocked",
      risk_level: "blocked",
      review_status: "rejected",
      reviewer: "local-operator",
      decision: "rejected",
      decision_reason: "blocked safety fixture cannot be imported",
      import_status: "blocked",
      import_target: null,
      import_preview: null,
      suggested_order: 201,
      suggested_dependencies: ["super-200-controlled-goal-draft-review-import"],
      allowed_task_types: ["docs"],
      blocked_task_types: ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection", "auto_execution"],
      expected_outputs: ["blocked_draft_record"],
      review_notes: ["Safety fixture: blocked and review-only."],
      blocked_reasons: ["production_deploy", "secret_rotation", "github_settings", "branch_protection", "auto_import", "auto_execution", "self_approval"],
      generated_at: "2026-06-08T00:00:00.000Z",
      reviewed_at: "2026-06-08T00:00:00.000Z",
      token_printed: false,
    },
  ],
  review_controls: {
    approve_preview: "reason-gated",
    reject_preview: "reason-gated",
    edit_staged: "hash-recompute",
    import_preview: "dry-run",
    import_apply: "disabled-until-approved-and-confirmed",
    execute_imported_goal: "not_available",
  },
  import_preview_summary: {
    target_path: "goals/reviewed/proposed-goal-201-local-readme-refresh.md",
    manifest_diff: ["add reviewed import manifest entry", "token_printed=false"],
    dependency_order_changes: ["order=201", "dependency super-200-controlled-goal-draft-review-import stays external/completed"],
    hash_changes: ["original=a80296ad3f06", "edited=none", "target=a80296ad3f06"],
    validation_blockers: ["unsafe_import_blocked for blocked fixture only"],
    dry_run_first: true,
    execution_review_required: true,
  },
  no_import_button: true,
  no_execute_button: true,
  no_execution_controls: true,
  token_printed: false,
};

export const fixtureCampaignRunReport: CampaignRunReport = {
  schema: "skybridge.campaign_run_report.v1",
  generated_at: "2026-06-08T00:00:00.000Z",
  project_id: "skybridge-agent-hub",
  campaign_id: "dev-queue-189-200",
  campaign_status: "paused",
  current_step_id: "dev-queue-189-200:super-199-hermes-goal-draft-generator",
  current_goal_id: "super-199-hermes-goal-draft-generator",
  current_goal_status: "ready",
  current_goal_unexecuted: true,
  campaign_summary: {
    campaign_id: "dev-queue-189-200",
    project_id: "skybridge-agent-hub",
    title: "Dev Queue 189-200",
    status: "paused",
    current_step_id: "dev-queue-189-200:super-199-hermes-goal-draft-generator",
    step_count: 12,
    source: "fixture",
    goal_pack_hash: "fixture-dev-queue-189-200-local-pack-hash",
  },
  current_step_summary: {
    campaign_step_id: "dev-queue-189-200:super-199-hermes-goal-draft-generator",
    goal_id: "super-199-hermes-goal-draft-generator",
    order: 11,
    title: "Hermes Goal Draft Generator",
    status: "ready",
    is_current: true,
    dependencies: ["super-198-multi-project-support"],
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
    campaign_step_id: "dev-queue-189-200:super-198-multi-project-support",
    goal_id: "super-198-multi-project-support",
    order: 10,
    title: "Multi-project Support",
    status: "completed",
    is_current: false,
    dependencies: ["super-197-multi-worker-readiness"],
    linked_task_ids: [],
    linked_pr_urls: ["https://github.com/JerrySkywalker/skybridge-agent-hub/pull/115"],
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
        status: "present",
        classification: "present_evidence",
        recovered: false,
        missing: false,
        skipped: false,
        not_applicable: false,
        operator_action_required: false,
        summary: "Goal 196 locking foundation evidence is represented by completed campaign state.",
      },
    ],
  },
  blockers: [],
  warnings: ["proposed_goals_need_review", "multi_campaign_conflict_review_required"],
  queue_control_readiness: {
    can_start_one: false,
    can_start_queue: false,
    can_pause: false,
    can_stop: true,
    can_emergency_stop: true,
    can_resume: false,
    blockers: ["worker_service_offline", "active_repo_lock_blocks_execution_preview", "execution_disabled_until_goal_200"],
    warnings: ["proposed_goals_need_review", "standby_worker_can_only_heartbeat", "multiple_campaigns_require_selection_review", "project_selection_preview_only"],
    required_human_action: ["review_proposed_goals_in_goal_200", "unlock_stale_locks_only_after_inspection_with_reason"],
    next_safe_action: "Review proposed goals in Goal 200; keep import and execution disabled.",
    worker_required: true,
    worker_status: "offline",
    run_budget_required: true,
    reason_required: true,
    worker_service_state: fixtureWorkerServiceState,
    execution_disabled_until_goal: "super-200-controlled-goal-draft-review-import",
    campaign_lock: fixtureCampaignLock,
    repo_exclusive_lock: fixtureRepoExclusiveLock,
    priority_queue: fixtureCampaignPriorityQueue,
    routing_readiness: fixtureWorkerRoutingReadiness,
    project_profile: fixtureProjectProfileReviewSummary,
    project_selection: fixtureProjectSelectionPreview,
    proposed_goal_summary: fixtureProposedGoalReviewSummary,
  },
  worker_service_state: fixtureWorkerServiceState,
  desktop_resident_state: fixtureDesktopResidentState,
  local_worker_supervisor_state: fixtureLocalWorkerSupervisorState,
  local_resource_policy: fixtureLocalResourcePolicy,
  local_execution_guard: fixtureLocalExecutionGuard,
  workunit_preview_plan: fixtureBoundedQueuePlan,
  bounded_queue_readiness: fixtureBoundedQueueReadiness,
  token_printed: false,
};

export const fixtureQueueControlState: QueueControlState = {
  schema: "skybridge.queue_control_state.v1",
  project_id: fixtureCampaignRunReport.project_id,
  campaign_id: fixtureCampaignRunReport.campaign_id,
  current_step_id: "dev-queue-189-200:super-199-hermes-goal-draft-generator",
  current_goal_id: "super-199-hermes-goal-draft-generator",
  worker_status: "offline",
  active_tasks: 0,
  stale_leases: 0,
  can_start_one: false,
  can_start_queue: false,
  can_resume: false,
  state_hash: "fixture-goal-199-proposed-goals-active0-stale0",
  revision: "fixture-goal-199-revision",
  action_matrix: queueControlActionMatrix,
  blockers: ["worker_service_offline", "active_repo_lock_blocks_execution_preview", "execution_disabled_until_goal_200"],
  warnings: ["standby_worker_can_only_heartbeat", "multiple_campaigns_require_selection_review", "project_selection_preview_only", "proposed_goals_need_review"],
  project_selection: fixtureProjectSelectionPreview,
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
    ["super-200-controlled-goal-draft-review-import", "Controlled Goal Draft Review and Import"],
  ].map(([goalId, title], index) => ({
    campaign_step_id: `dev-queue-189-200:${goalId}`,
    goal_id: goalId,
    order: index + 12,
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
