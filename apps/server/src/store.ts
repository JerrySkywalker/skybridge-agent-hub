import { existsSync, mkdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname } from "node:path";
import type {
  IterationRun,
  MasterGoal,
  PlanningMasterGoal,
  PlanningSession,
  Project,
  SkyBridgeEvent,
  Task,
  TaskEvent,
  TaskProposal,
  Worker,
  WorkerHeartbeat,
} from "@skybridge-agent-hub/event-schema";
import type { NotificationMessage } from "@skybridge-agent-hub/notification-ntfy";

export type StoredEvent = SkyBridgeEvent & { id: string; receivedAt: string };

export interface StoredNotification {
  id: string;
  category?: string;
  severity?: string;
  source_event_id?: string;
  target?: string;
  provider: "ntfy" | "apprise" | "gotify" | "bark" | "wecom" | "fcm" | "xiaomi-push" | "placeholder";
  dedupe_key?: string;
  status: "pending" | "sent" | "skipped" | "failed";
  retry_count?: number;
  message: NotificationMessage;
  createdAt: string;
  updatedAt?: string;
  error?: string;
}

export interface StoredAuditRecord {
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

export interface StoredIterationEvent {
  iteration_id: string;
  type: string;
  time: string;
  payload: Record<string, unknown>;
}

export type StoredIterationRun = IterationRun & { events: StoredIterationEvent[] };
export type StoredProject = Project;
export type StoredMasterGoal = MasterGoal;
export type StoredPlanningMasterGoal = PlanningMasterGoal;
export type StoredPlanningSession = PlanningSession;
export type StoredTaskProposal = TaskProposal;
export type StoredWorker = Omit<Worker, "status" | "current_task_id" | "last_seen_at">;
export type StoredWorkerHeartbeat = WorkerHeartbeat;
export type StoredTask = Task;
export type StoredTaskEvent = TaskEvent;

interface LocalStoreData {
  events: StoredEvent[];
  notifications: StoredNotification[];
  audit: StoredAuditRecord[];
  iterations?: StoredIterationRun[];
  projects?: StoredProject[];
  masterGoals?: StoredMasterGoal[];
  planningMasterGoals?: StoredPlanningMasterGoal[];
  planningSessions?: StoredPlanningSession[];
  taskProposals?: StoredTaskProposal[];
  workers?: StoredWorker[];
  workerHeartbeats?: StoredWorkerHeartbeat[];
  tasks?: StoredTask[];
  taskEvents?: StoredTaskEvent[];
}

export interface EventStore {
  kind: "memory" | "sqlite";
  load(): Promise<void>;
  close(): Promise<void>;
  listEvents(limit?: number): StoredEvent[];
  listNotifications(limit?: number): StoredNotification[];
  listAuditRecords(limit?: number): StoredAuditRecord[];
  listIterations(limit?: number): StoredIterationRun[];
  getIteration(iterationId: string): StoredIterationRun | undefined;
  addEvent(event: StoredEvent): Promise<void>;
  addNotification(notification: StoredNotification): Promise<void>;
  addAuditRecord(record: StoredAuditRecord): Promise<void>;
  upsertIteration(iteration: StoredIterationRun): Promise<void>;
  addIterationEvent(event: StoredIterationEvent): Promise<void>;
  listProjects(): StoredProject[];
  getProject(projectId: string): StoredProject | undefined;
  upsertProject(project: StoredProject): Promise<void>;
  listGoals(projectId?: string): StoredMasterGoal[];
  getGoal(goalId: string): StoredMasterGoal | undefined;
  upsertGoal(goal: StoredMasterGoal): Promise<void>;
  listPlanningMasterGoals(projectId?: string): StoredPlanningMasterGoal[];
  getPlanningMasterGoal(masterGoalId: string): StoredPlanningMasterGoal | undefined;
  upsertPlanningMasterGoal(masterGoal: StoredPlanningMasterGoal): Promise<void>;
  listPlanningSessions(masterGoalId?: string): StoredPlanningSession[];
  getPlanningSession(planningSessionId: string): StoredPlanningSession | undefined;
  upsertPlanningSession(session: StoredPlanningSession): Promise<void>;
  listTaskProposals(filters?: { projectId?: string; masterGoalId?: string; status?: string }): StoredTaskProposal[];
  getTaskProposal(proposalId: string): StoredTaskProposal | undefined;
  upsertTaskProposal(proposal: StoredTaskProposal): Promise<void>;
  listWorkers(): StoredWorker[];
  getWorker(workerId: string): StoredWorker | undefined;
  upsertWorker(worker: StoredWorker): Promise<void>;
  listWorkerHeartbeats(workerId?: string): StoredWorkerHeartbeat[];
  addWorkerHeartbeat(heartbeat: StoredWorkerHeartbeat): Promise<void>;
  listTasks(filters?: { projectId?: string; goalId?: string; status?: string }): StoredTask[];
  getTask(taskId: string): StoredTask | undefined;
  upsertTask(task: StoredTask): Promise<void>;
  listTaskEvents(taskId?: string): StoredTaskEvent[];
  addTaskEvent(event: StoredTaskEvent): Promise<void>;
}

export class MemoryStore implements EventStore {
  kind = "memory" as const;
  private data: Required<LocalStoreData> = {
    events: [],
    notifications: [],
    audit: [],
    iterations: [],
    projects: [],
    masterGoals: [],
    planningMasterGoals: [],
    planningSessions: [],
    taskProposals: [],
    workers: [],
    workerHeartbeats: [],
    tasks: [],
    taskEvents: [],
  };

  async load(): Promise<void> {}

  async close(): Promise<void> {}

  listEvents(limit?: number): StoredEvent[] {
    return sliceTail(this.data.events, limit);
  }

  listNotifications(limit?: number): StoredNotification[] {
    return sliceTail(this.data.notifications, limit);
  }

  listAuditRecords(limit?: number): StoredAuditRecord[] {
    return sliceTail(this.data.audit, limit);
  }

  listIterations(limit?: number): StoredIterationRun[] {
    return sliceTail(
      [...this.data.iterations].sort((a, b) => a.updated_at.localeCompare(b.updated_at)),
      limit
    );
  }

  getIteration(iterationId: string): StoredIterationRun | undefined {
    return this.data.iterations.find((iteration) => iteration.iteration_id === iterationId);
  }

  async addEvent(event: StoredEvent): Promise<void> {
    this.data.events.push(event);
  }

  async addNotification(notification: StoredNotification): Promise<void> {
    this.data.notifications.push(notification);
  }

  async addAuditRecord(record: StoredAuditRecord): Promise<void> {
    if (this.data.audit.some((existing) => existing.audit_id === record.audit_id)) return;
    this.data.audit.push(record);
  }

  async upsertIteration(iteration: StoredIterationRun): Promise<void> {
    const index = this.data.iterations.findIndex((existing) => existing.iteration_id === iteration.iteration_id);
    if (index >= 0) this.data.iterations[index] = iteration;
    else this.data.iterations.push(iteration);
  }

  async addIterationEvent(event: StoredIterationEvent): Promise<void> {
    const existing = this.getIteration(event.iteration_id);
    if (!existing) return;
    existing.events.push(event);
    existing.updated_at = event.time;
  }

  listProjects(): StoredProject[] {
    return [...this.data.projects].sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  }

  getProject(projectId: string): StoredProject | undefined {
    return this.data.projects.find((project) => project.project_id === projectId);
  }

  async upsertProject(project: StoredProject): Promise<void> {
    upsertBy(this.data.projects, project, (item) => item.project_id);
  }

  listGoals(projectId?: string): StoredMasterGoal[] {
    return this.data.masterGoals
      .filter((goal) => !projectId || goal.project_id === projectId)
      .sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  }

  getGoal(goalId: string): StoredMasterGoal | undefined {
    return this.data.masterGoals.find((goal) => goal.goal_id === goalId);
  }

  async upsertGoal(goal: StoredMasterGoal): Promise<void> {
    upsertBy(this.data.masterGoals, goal, (item) => item.goal_id);
  }

  listPlanningMasterGoals(projectId?: string): StoredPlanningMasterGoal[] {
    return this.data.planningMasterGoals
      .filter((goal) => !projectId || goal.project_id === projectId)
      .sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  }

  getPlanningMasterGoal(masterGoalId: string): StoredPlanningMasterGoal | undefined {
    return this.data.planningMasterGoals.find((goal) => goal.master_goal_id === masterGoalId);
  }

  async upsertPlanningMasterGoal(masterGoal: StoredPlanningMasterGoal): Promise<void> {
    upsertBy(this.data.planningMasterGoals, masterGoal, (item) => item.master_goal_id);
  }

  listPlanningSessions(masterGoalId?: string): StoredPlanningSession[] {
    return this.data.planningSessions
      .filter((session) => !masterGoalId || session.master_goal_id === masterGoalId)
      .sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  }

  getPlanningSession(planningSessionId: string): StoredPlanningSession | undefined {
    return this.data.planningSessions.find((session) => session.planning_session_id === planningSessionId);
  }

  async upsertPlanningSession(session: StoredPlanningSession): Promise<void> {
    upsertBy(this.data.planningSessions, session, (item) => item.planning_session_id);
  }

  listTaskProposals(filters: { projectId?: string; masterGoalId?: string; status?: string } = {}): StoredTaskProposal[] {
    return this.data.taskProposals
      .filter((proposal) => !filters.projectId || proposal.project_id === filters.projectId)
      .filter((proposal) => !filters.masterGoalId || proposal.master_goal_id === filters.masterGoalId)
      .filter((proposal) => !filters.status || proposal.status === filters.status)
      .sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  }

  getTaskProposal(proposalId: string): StoredTaskProposal | undefined {
    return this.data.taskProposals.find((proposal) => proposal.proposal_id === proposalId);
  }

  async upsertTaskProposal(proposal: StoredTaskProposal): Promise<void> {
    upsertBy(this.data.taskProposals, proposal, (item) => item.proposal_id);
  }

  listWorkers(): StoredWorker[] {
    return [...this.data.workers].sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  }

  getWorker(workerId: string): StoredWorker | undefined {
    return this.data.workers.find((worker) => worker.worker_id === workerId);
  }

  async upsertWorker(worker: StoredWorker): Promise<void> {
    upsertBy(this.data.workers, worker, (item) => item.worker_id);
  }

  listWorkerHeartbeats(workerId?: string): StoredWorkerHeartbeat[] {
    return this.data.workerHeartbeats
      .filter((heartbeat) => !workerId || heartbeat.worker_id === workerId)
      .sort((a, b) => b.seen_at.localeCompare(a.seen_at));
  }

  async addWorkerHeartbeat(heartbeat: StoredWorkerHeartbeat): Promise<void> {
    this.data.workerHeartbeats.push(heartbeat);
  }

  listTasks(filters: { projectId?: string; goalId?: string; status?: string } = {}): StoredTask[] {
    return this.data.tasks
      .filter((task) => !filters.projectId || task.project_id === filters.projectId)
      .filter((task) => !filters.goalId || task.goal_id === filters.goalId)
      .filter((task) => !filters.status || task.status === filters.status)
      .sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  }

  getTask(taskId: string): StoredTask | undefined {
    return this.data.tasks.find((task) => task.task_id === taskId);
  }

  async upsertTask(task: StoredTask): Promise<void> {
    upsertBy(this.data.tasks, task, (item) => item.task_id);
  }

  listTaskEvents(taskId?: string): StoredTaskEvent[] {
    return this.data.taskEvents
      .filter((event) => !taskId || event.task_id === taskId)
      .sort((a, b) => a.time.localeCompare(b.time));
  }

  async addTaskEvent(event: StoredTaskEvent): Promise<void> {
    this.data.taskEvents.push(event);
  }
}

export interface SqliteStoreOptions {
  dbFile: string;
  legacyJsonFile?: string;
}

export class SqliteStore implements EventStore {
  kind = "sqlite" as const;
  private db: SqliteDatabase | undefined;

  constructor(private readonly options: SqliteStoreOptions) {}

  async load(): Promise<void> {
    mkdirSync(dirname(this.options.dbFile), { recursive: true });
    const { DatabaseSync } = await loadNodeSqlite();
    this.db = new DatabaseSync(this.options.dbFile);
    this.db.exec("PRAGMA journal_mode = WAL");
    this.db.exec("PRAGMA foreign_keys = ON");
    this.createSchema();
    await this.migrateJsonIfNeeded();
  }

  async close(): Promise<void> {
    this.db?.close();
    this.db = undefined;
  }

  listEvents(limit?: number): StoredEvent[] {
    const db = this.requireDb();
    const rows = db.prepare(`
      SELECT event_json
      FROM events
      ORDER BY received_at DESC, rowid DESC
      ${limit ? "LIMIT ?" : ""}
    `).all(...(limit ? [limit] : [])) as Array<{ event_json: string }>;
    return rows.reverse().map((row) => JSON.parse(row.event_json) as StoredEvent);
  }

  listNotifications(limit?: number): StoredNotification[] {
    const db = this.requireDb();
    const rows = db.prepare(`
      SELECT notification_json
      FROM notifications
      ORDER BY created_at DESC, rowid DESC
      ${limit ? "LIMIT ?" : ""}
    `).all(...(limit ? [limit] : [])) as Array<{ notification_json: string }>;
    return rows.reverse().map((row) => JSON.parse(row.notification_json) as StoredNotification);
  }

  listAuditRecords(limit?: number): StoredAuditRecord[] {
    const db = this.requireDb();
    const rows = db.prepare(`
      SELECT audit_json
      FROM audit_records
      ORDER BY time DESC, rowid DESC
      ${limit ? "LIMIT ?" : ""}
    `).all(...(limit ? [limit] : [])) as Array<{ audit_json: string }>;
    return rows.map((row) => JSON.parse(row.audit_json) as StoredAuditRecord);
  }

  listIterations(limit?: number): StoredIterationRun[] {
    const db = this.requireDb();
    const rows = db.prepare(`
      SELECT iteration_json
      FROM iterations
      ORDER BY updated_at DESC, rowid DESC
      ${limit ? "LIMIT ?" : ""}
    `).all(...(limit ? [limit] : [])) as Array<{ iteration_json: string }>;
    return rows.map((row) => JSON.parse(row.iteration_json) as StoredIterationRun);
  }

  getIteration(iterationId: string): StoredIterationRun | undefined {
    const db = this.requireDb();
    const row = db.prepare(`
      SELECT iteration_json
      FROM iterations
      WHERE iteration_id = ?
    `).get(iterationId) as { iteration_json: string } | undefined;
    return row ? JSON.parse(row.iteration_json) as StoredIterationRun : undefined;
  }

  async addEvent(event: StoredEvent): Promise<void> {
    const db = this.requireDb();
    db.prepare(`
      INSERT OR REPLACE INTO events (
        id, schema_version, event_id, type, severity, source_platform, source_adapter,
        session_id, run_id, tool_call_id, event_time, received_at, event_json
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      )
    `).run(...toEventParams(event));
  }

  async addNotification(notification: StoredNotification): Promise<void> {
    const db = this.requireDb();
    db.prepare(`
      INSERT OR REPLACE INTO notifications (
        id, provider, status, title, created_at, error, notification_json
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?
      )
    `).run(...toNotificationParams(notification));
  }

  async addAuditRecord(record: StoredAuditRecord): Promise<void> {
    const db = this.requireDb();
    db.prepare(`
      INSERT OR IGNORE INTO audit_records (
        audit_id, time, action, actor, source_adapter, run_id, session_id,
        safety_decision, immutable_event_id, redaction_policy_version, audit_json
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      )
    `).run(...toAuditParams(record));
  }

  async upsertIteration(iteration: StoredIterationRun): Promise<void> {
    const db = this.requireDb();
    db.prepare(`
      INSERT OR REPLACE INTO iterations (
        iteration_id, project_id, repo, branch, base_branch, pr_number, state,
        attempts, max_attempts, created_at, updated_at, iteration_json
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      )
    `).run(...toIterationParams(iteration));
  }

  async addIterationEvent(event: StoredIterationEvent): Promise<void> {
    const db = this.requireDb();
    const existing = this.getIteration(event.iteration_id);
    if (!existing) return;
    const updated: StoredIterationRun = {
      ...existing,
      events: [...existing.events, event],
      updated_at: event.time
    };
    const addEvent = transaction(db, () => {
      db.prepare(`
        INSERT INTO iteration_events (
          iteration_id, type, time, event_json
        ) VALUES (
          ?, ?, ?, ?
        )
      `).run(...toIterationEventParams(event));
      db.prepare(`
        UPDATE iterations
        SET updated_at = ?, iteration_json = ?
        WHERE iteration_id = ?
      `).run(updated.updated_at, JSON.stringify(updated), updated.iteration_id);
    });
    addEvent();
  }

  listProjects(): StoredProject[] {
    const rows = this.requireDb().prepare(`
      SELECT project_json FROM projects ORDER BY updated_at DESC, rowid DESC
    `).all() as Array<{ project_json: string }>;
    return rows.map((row) => JSON.parse(row.project_json) as StoredProject);
  }

  getProject(projectId: string): StoredProject | undefined {
    const row = this.requireDb().prepare(`
      SELECT project_json FROM projects WHERE project_id = ?
    `).get(projectId) as { project_json: string } | undefined;
    return row ? JSON.parse(row.project_json) as StoredProject : undefined;
  }

  async upsertProject(project: StoredProject): Promise<void> {
    this.requireDb().prepare(`
      INSERT INTO projects (project_id, name, repo, status, created_at, updated_at, project_json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(project_id) DO UPDATE SET
        name = excluded.name,
        repo = excluded.repo,
        status = excluded.status,
        updated_at = excluded.updated_at,
        project_json = excluded.project_json
    `).run(...toProjectParams(project));
  }

  listGoals(projectId?: string): StoredMasterGoal[] {
    const rows = this.requireDb().prepare(`
      SELECT goal_json FROM master_goals
      ${projectId ? "WHERE project_id = ?" : ""}
      ORDER BY updated_at DESC, rowid DESC
    `).all(...(projectId ? [projectId] : [])) as Array<{ goal_json: string }>;
    return rows.map((row) => JSON.parse(row.goal_json) as StoredMasterGoal);
  }

  getGoal(goalId: string): StoredMasterGoal | undefined {
    const row = this.requireDb().prepare(`
      SELECT goal_json FROM master_goals WHERE goal_id = ?
    `).get(goalId) as { goal_json: string } | undefined;
    return row ? JSON.parse(row.goal_json) as StoredMasterGoal : undefined;
  }

  async upsertGoal(goal: StoredMasterGoal): Promise<void> {
    this.requireDb().prepare(`
      INSERT INTO master_goals (goal_id, project_id, title, status, created_at, updated_at, goal_json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(goal_id) DO UPDATE SET
        project_id = excluded.project_id,
        title = excluded.title,
        status = excluded.status,
        updated_at = excluded.updated_at,
        goal_json = excluded.goal_json
    `).run(...toGoalParams(goal));
  }

  listPlanningMasterGoals(projectId?: string): StoredPlanningMasterGoal[] {
    const rows = this.requireDb().prepare(`
      SELECT master_goal_json FROM planning_master_goals
      ${projectId ? "WHERE project_id = ?" : ""}
      ORDER BY updated_at DESC, rowid DESC
    `).all(...(projectId ? [projectId] : [])) as Array<{ master_goal_json: string }>;
    return rows.map((row) => JSON.parse(row.master_goal_json) as StoredPlanningMasterGoal);
  }

  getPlanningMasterGoal(masterGoalId: string): StoredPlanningMasterGoal | undefined {
    const row = this.requireDb().prepare(`
      SELECT master_goal_json FROM planning_master_goals WHERE master_goal_id = ?
    `).get(masterGoalId) as { master_goal_json: string } | undefined;
    return row ? JSON.parse(row.master_goal_json) as StoredPlanningMasterGoal : undefined;
  }

  async upsertPlanningMasterGoal(masterGoal: StoredPlanningMasterGoal): Promise<void> {
    this.requireDb().prepare(`
      INSERT INTO planning_master_goals (master_goal_id, project_id, title, source, priority, created_at, updated_at, master_goal_json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(master_goal_id) DO UPDATE SET
        project_id = excluded.project_id,
        title = excluded.title,
        source = excluded.source,
        priority = excluded.priority,
        updated_at = excluded.updated_at,
        master_goal_json = excluded.master_goal_json
    `).run(...toPlanningMasterGoalParams(masterGoal));
  }

  listPlanningSessions(masterGoalId?: string): StoredPlanningSession[] {
    const rows = this.requireDb().prepare(`
      SELECT session_json FROM planning_sessions
      ${masterGoalId ? "WHERE master_goal_id = ?" : ""}
      ORDER BY updated_at DESC, rowid DESC
    `).all(...(masterGoalId ? [masterGoalId] : [])) as Array<{ session_json: string }>;
    return rows.map((row) => JSON.parse(row.session_json) as StoredPlanningSession);
  }

  getPlanningSession(planningSessionId: string): StoredPlanningSession | undefined {
    const row = this.requireDb().prepare(`
      SELECT session_json FROM planning_sessions WHERE planning_session_id = ?
    `).get(planningSessionId) as { session_json: string } | undefined;
    return row ? JSON.parse(row.session_json) as StoredPlanningSession : undefined;
  }

  async upsertPlanningSession(session: StoredPlanningSession): Promise<void> {
    this.requireDb().prepare(`
      INSERT INTO planning_sessions (planning_session_id, master_goal_id, project_id, planner_mode, created_at, updated_at, session_json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(planning_session_id) DO UPDATE SET
        master_goal_id = excluded.master_goal_id,
        project_id = excluded.project_id,
        planner_mode = excluded.planner_mode,
        updated_at = excluded.updated_at,
        session_json = excluded.session_json
    `).run(...toPlanningSessionParams(session));
  }

  listTaskProposals(filters: { projectId?: string; masterGoalId?: string; status?: string } = {}): StoredTaskProposal[] {
    const rows = this.requireDb().prepare(`
      SELECT proposal_json FROM task_proposals
      WHERE (? IS NULL OR project_id = ?)
        AND (? IS NULL OR master_goal_id = ?)
        AND (? IS NULL OR status = ?)
      ORDER BY updated_at DESC, rowid DESC
    `).all(
      filters.projectId ?? null,
      filters.projectId ?? null,
      filters.masterGoalId ?? null,
      filters.masterGoalId ?? null,
      filters.status ?? null,
      filters.status ?? null,
    ) as Array<{ proposal_json: string }>;
    return rows.map((row) => JSON.parse(row.proposal_json) as StoredTaskProposal);
  }

  getTaskProposal(proposalId: string): StoredTaskProposal | undefined {
    const row = this.requireDb().prepare(`
      SELECT proposal_json FROM task_proposals WHERE proposal_id = ?
    `).get(proposalId) as { proposal_json: string } | undefined;
    return row ? JSON.parse(row.proposal_json) as StoredTaskProposal : undefined;
  }

  async upsertTaskProposal(proposal: StoredTaskProposal): Promise<void> {
    this.requireDb().prepare(`
      INSERT INTO task_proposals (
        proposal_id, master_goal_id, planning_session_id, project_id, dedupe_key, status, risk, task_type, created_at, updated_at, proposal_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(proposal_id) DO UPDATE SET
        master_goal_id = excluded.master_goal_id,
        planning_session_id = excluded.planning_session_id,
        project_id = excluded.project_id,
        dedupe_key = excluded.dedupe_key,
        status = excluded.status,
        risk = excluded.risk,
        task_type = excluded.task_type,
        updated_at = excluded.updated_at,
        proposal_json = excluded.proposal_json
    `).run(...toTaskProposalParams(proposal));
  }

  listWorkers(): StoredWorker[] {
    const rows = this.requireDb().prepare(`
      SELECT worker_json FROM workers ORDER BY updated_at DESC, rowid DESC
    `).all() as Array<{ worker_json: string }>;
    return rows.map((row) => JSON.parse(row.worker_json) as StoredWorker);
  }

  getWorker(workerId: string): StoredWorker | undefined {
    const row = this.requireDb().prepare(`
      SELECT worker_json FROM workers WHERE worker_id = ?
    `).get(workerId) as { worker_json: string } | undefined;
    return row ? JSON.parse(row.worker_json) as StoredWorker : undefined;
  }

  async upsertWorker(worker: StoredWorker): Promise<void> {
    this.requireDb().prepare(`
      INSERT INTO workers (worker_id, name, provider, enabled, created_at, updated_at, worker_json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(worker_id) DO UPDATE SET
        name = excluded.name,
        provider = excluded.provider,
        enabled = excluded.enabled,
        updated_at = excluded.updated_at,
        worker_json = excluded.worker_json
    `).run(...toWorkerParams(worker));
  }

  listWorkerHeartbeats(workerId?: string): StoredWorkerHeartbeat[] {
    const rows = this.requireDb().prepare(`
      SELECT heartbeat_json FROM worker_heartbeats
      ${workerId ? "WHERE worker_id = ?" : ""}
      ORDER BY seen_at DESC, rowid DESC
    `).all(...(workerId ? [workerId] : [])) as Array<{ heartbeat_json: string }>;
    return rows.map((row) => JSON.parse(row.heartbeat_json) as StoredWorkerHeartbeat);
  }

  async addWorkerHeartbeat(heartbeat: StoredWorkerHeartbeat): Promise<void> {
    this.requireDb().prepare(`
      INSERT OR REPLACE INTO worker_heartbeats (heartbeat_id, worker_id, seen_at, heartbeat_json)
      VALUES (?, ?, ?, ?)
    `).run(heartbeat.heartbeat_id, heartbeat.worker_id, heartbeat.seen_at, JSON.stringify(heartbeat));
  }

  listTasks(filters: { projectId?: string; goalId?: string; status?: string } = {}): StoredTask[] {
    const rows = this.requireDb().prepare(`
      SELECT task_json FROM tasks
      WHERE (? IS NULL OR project_id = ?)
        AND (? IS NULL OR goal_id = ?)
        AND (? IS NULL OR status = ?)
      ORDER BY updated_at DESC, rowid DESC
    `).all(
      filters.projectId ?? null,
      filters.projectId ?? null,
      filters.goalId ?? null,
      filters.goalId ?? null,
      filters.status ?? null,
      filters.status ?? null,
    ) as Array<{ task_json: string }>;
    return rows.map((row) => JSON.parse(row.task_json) as StoredTask);
  }

  getTask(taskId: string): StoredTask | undefined {
    const row = this.requireDb().prepare(`
      SELECT task_json FROM tasks WHERE task_id = ?
    `).get(taskId) as { task_json: string } | undefined;
    return row ? JSON.parse(row.task_json) as StoredTask : undefined;
  }

  async upsertTask(task: StoredTask): Promise<void> {
    this.requireDb().prepare(`
      INSERT INTO tasks (task_id, project_id, goal_id, status, risk, source, assigned_worker_id, created_at, updated_at, task_json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(task_id) DO UPDATE SET
        project_id = excluded.project_id,
        goal_id = excluded.goal_id,
        status = excluded.status,
        risk = excluded.risk,
        source = excluded.source,
        assigned_worker_id = excluded.assigned_worker_id,
        updated_at = excluded.updated_at,
        task_json = excluded.task_json
    `).run(...toTaskParams(task));
  }

  listTaskEvents(taskId?: string): StoredTaskEvent[] {
    const rows = this.requireDb().prepare(`
      SELECT event_json FROM task_events
      ${taskId ? "WHERE task_id = ?" : ""}
      ORDER BY time ASC, rowid ASC
    `).all(...(taskId ? [taskId] : [])) as Array<{ event_json: string }>;
    return rows.map((row) => JSON.parse(row.event_json) as StoredTaskEvent);
  }

  async addTaskEvent(event: StoredTaskEvent): Promise<void> {
    this.requireDb().prepare(`
      INSERT OR REPLACE INTO task_events (task_event_id, task_id, type, worker_id, time, event_json)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(event.task_event_id, event.task_id, event.type, event.worker_id ?? null, event.time, JSON.stringify(event));
  }

  private createSchema() {
    const db = this.requireDb();
    db.exec(`
      CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY,
        schema_version TEXT NOT NULL,
        event_id TEXT,
        type TEXT NOT NULL,
        severity TEXT NOT NULL,
        source_platform TEXT NOT NULL,
        source_adapter TEXT NOT NULL,
        session_id TEXT,
        run_id TEXT,
        tool_call_id TEXT,
        event_time TEXT NOT NULL,
        received_at TEXT NOT NULL,
        event_json TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_events_received_at ON events(received_at);
      CREATE INDEX IF NOT EXISTS idx_events_run_id ON events(run_id);
      CREATE INDEX IF NOT EXISTS idx_events_session_id ON events(session_id);
      CREATE INDEX IF NOT EXISTS idx_events_type ON events(type);

      CREATE TABLE IF NOT EXISTS notifications (
        id TEXT PRIMARY KEY,
        provider TEXT NOT NULL,
        status TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        error TEXT,
        notification_json TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at);

      CREATE TABLE IF NOT EXISTS audit_records (
        audit_id TEXT PRIMARY KEY,
        time TEXT NOT NULL,
        action TEXT NOT NULL,
        actor TEXT NOT NULL,
        source_adapter TEXT NOT NULL,
        run_id TEXT,
        session_id TEXT,
        safety_decision TEXT NOT NULL,
        immutable_event_id TEXT NOT NULL,
        redaction_policy_version TEXT NOT NULL,
        audit_json TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_audit_records_time ON audit_records(time);
      CREATE INDEX IF NOT EXISTS idx_audit_records_action ON audit_records(action);
      CREATE INDEX IF NOT EXISTS idx_audit_records_actor ON audit_records(actor);
      CREATE INDEX IF NOT EXISTS idx_audit_records_run_id ON audit_records(run_id);

      CREATE TABLE IF NOT EXISTS iterations (
        iteration_id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        repo TEXT NOT NULL,
        branch TEXT NOT NULL,
        base_branch TEXT NOT NULL,
        pr_number INTEGER,
        state TEXT NOT NULL,
        attempts INTEGER NOT NULL,
        max_attempts INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        iteration_json TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_iterations_updated_at ON iterations(updated_at);
      CREATE INDEX IF NOT EXISTS idx_iterations_state ON iterations(state);
      CREATE INDEX IF NOT EXISTS idx_iterations_project_id ON iterations(project_id);
      CREATE INDEX IF NOT EXISTS idx_iterations_branch ON iterations(branch);
      CREATE INDEX IF NOT EXISTS idx_iterations_pr_number ON iterations(pr_number);

      CREATE TABLE IF NOT EXISTS iteration_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        iteration_id TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        event_json TEXT NOT NULL,
        FOREIGN KEY(iteration_id) REFERENCES iterations(iteration_id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_iteration_events_iteration_id ON iteration_events(iteration_id);
      CREATE INDEX IF NOT EXISTS idx_iteration_events_time ON iteration_events(time);

      CREATE TABLE IF NOT EXISTS store_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS projects (
        project_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        repo TEXT,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        project_json TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);

      CREATE TABLE IF NOT EXISTS master_goals (
        goal_id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        goal_json TEXT NOT NULL,
        FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_master_goals_project_id ON master_goals(project_id);
      CREATE INDEX IF NOT EXISTS idx_master_goals_status ON master_goals(status);

      CREATE TABLE IF NOT EXISTS planning_master_goals (
        master_goal_id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        title TEXT NOT NULL,
        source TEXT NOT NULL,
        priority TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        master_goal_json TEXT NOT NULL,
        FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_planning_master_goals_project_id ON planning_master_goals(project_id);

      CREATE TABLE IF NOT EXISTS planning_sessions (
        planning_session_id TEXT PRIMARY KEY,
        master_goal_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        planner_mode TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        session_json TEXT NOT NULL,
        FOREIGN KEY(master_goal_id) REFERENCES planning_master_goals(master_goal_id) ON DELETE CASCADE,
        FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_planning_sessions_master_goal_id ON planning_sessions(master_goal_id);
      CREATE INDEX IF NOT EXISTS idx_planning_sessions_project_id ON planning_sessions(project_id);

      CREATE TABLE IF NOT EXISTS task_proposals (
        proposal_id TEXT PRIMARY KEY,
        master_goal_id TEXT NOT NULL,
        planning_session_id TEXT,
        project_id TEXT NOT NULL,
        dedupe_key TEXT NOT NULL,
        status TEXT NOT NULL,
        risk TEXT NOT NULL,
        task_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        proposal_json TEXT NOT NULL,
        FOREIGN KEY(master_goal_id) REFERENCES planning_master_goals(master_goal_id) ON DELETE CASCADE,
        FOREIGN KEY(planning_session_id) REFERENCES planning_sessions(planning_session_id) ON DELETE SET NULL,
        FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_task_proposals_project_id ON task_proposals(project_id);
      CREATE INDEX IF NOT EXISTS idx_task_proposals_master_goal_id ON task_proposals(master_goal_id);
      CREATE INDEX IF NOT EXISTS idx_task_proposals_status ON task_proposals(status);
      CREATE UNIQUE INDEX IF NOT EXISTS idx_task_proposals_dedupe ON task_proposals(project_id, dedupe_key);

      CREATE TABLE IF NOT EXISTS workers (
        worker_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        provider TEXT NOT NULL,
        enabled INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        worker_json TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_workers_enabled ON workers(enabled);

      CREATE TABLE IF NOT EXISTS worker_heartbeats (
        heartbeat_id TEXT PRIMARY KEY,
        worker_id TEXT NOT NULL,
        seen_at TEXT NOT NULL,
        heartbeat_json TEXT NOT NULL,
        FOREIGN KEY(worker_id) REFERENCES workers(worker_id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_worker_heartbeats_worker_id ON worker_heartbeats(worker_id);
      CREATE INDEX IF NOT EXISTS idx_worker_heartbeats_seen_at ON worker_heartbeats(seen_at);

      CREATE TABLE IF NOT EXISTS tasks (
        task_id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        goal_id TEXT,
        status TEXT NOT NULL,
        risk TEXT NOT NULL,
        source TEXT NOT NULL,
        assigned_worker_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        task_json TEXT NOT NULL,
        FOREIGN KEY(project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
        FOREIGN KEY(goal_id) REFERENCES master_goals(goal_id) ON DELETE SET NULL,
        FOREIGN KEY(assigned_worker_id) REFERENCES workers(worker_id) ON DELETE SET NULL
      );
      CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks(project_id);
      CREATE INDEX IF NOT EXISTS idx_tasks_goal_id ON tasks(goal_id);
      CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
      CREATE INDEX IF NOT EXISTS idx_tasks_worker ON tasks(assigned_worker_id);

      CREATE TABLE IF NOT EXISTS task_events (
        task_event_id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        type TEXT NOT NULL,
        worker_id TEXT,
        time TEXT NOT NULL,
        event_json TEXT NOT NULL,
        FOREIGN KEY(task_id) REFERENCES tasks(task_id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_task_events_task_id ON task_events(task_id);
      CREATE INDEX IF NOT EXISTS idx_task_events_time ON task_events(time);
    `);
  }

  private async migrateJsonIfNeeded() {
    const legacyJsonFile = this.options.legacyJsonFile;
    if (!legacyJsonFile || !existsSync(legacyJsonFile)) return;

    const db = this.requireDb();
    const migratedKey = `json_migrated:${legacyJsonFile}`;
    const migrated = db.prepare("SELECT value FROM store_metadata WHERE key = ?").get(migratedKey);
    if (migrated) return;

    const content = await readFile(legacyJsonFile, "utf8");
    const parsed = JSON.parse(content) as Partial<LocalStoreData>;
    const events = parsed.events ?? [];
    const notifications = parsed.notifications ?? [];
    const audit = parsed.audit ?? [];
    const iterations = parsed.iterations ?? [];

    const insertEvents = transaction(db, (items: StoredEvent[]) => {
      for (const event of items) {
        this.addEventSync(event);
      }
    });
    const insertNotifications = transaction(db, (items: StoredNotification[]) => {
      for (const notification of items) {
        this.addNotificationSync(notification);
      }
    });
    const insertAudit = transaction(db, (items: StoredAuditRecord[]) => {
      for (const record of items) {
        this.addAuditRecordSync(record);
      }
    });
    const insertIterations = transaction(db, (items: StoredIterationRun[]) => {
      for (const iteration of items) {
        this.upsertIterationSync(iteration);
        for (const event of iteration.events ?? []) this.addIterationEventSync(event);
      }
    });

    insertEvents(events);
    insertNotifications(notifications);
    insertAudit(audit);
    insertIterations(iterations);
    db.prepare("INSERT OR REPLACE INTO store_metadata (key, value) VALUES (?, ?)").run(
      migratedKey,
      JSON.stringify({ migratedAt: new Date().toISOString(), events: events.length, notifications: notifications.length, audit: audit.length, iterations: iterations.length })
    );
  }

  private addEventSync(event: StoredEvent) {
    this.requireDb().prepare(`
      INSERT OR IGNORE INTO events (
        id, schema_version, event_id, type, severity, source_platform, source_adapter,
        session_id, run_id, tool_call_id, event_time, received_at, event_json
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      )
    `).run(...toEventParams(event));
  }

  private addNotificationSync(notification: StoredNotification) {
    this.requireDb().prepare(`
      INSERT OR IGNORE INTO notifications (
        id, provider, status, title, created_at, error, notification_json
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?
      )
    `).run(...toNotificationParams(notification));
  }

  private addAuditRecordSync(record: StoredAuditRecord) {
    this.requireDb().prepare(`
      INSERT OR IGNORE INTO audit_records (
        audit_id, time, action, actor, source_adapter, run_id, session_id,
        safety_decision, immutable_event_id, redaction_policy_version, audit_json
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      )
    `).run(...toAuditParams(record));
  }

  private upsertIterationSync(iteration: StoredIterationRun) {
    this.requireDb().prepare(`
      INSERT OR REPLACE INTO iterations (
        iteration_id, project_id, repo, branch, base_branch, pr_number, state,
        attempts, max_attempts, created_at, updated_at, iteration_json
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      )
    `).run(...toIterationParams(iteration));
  }

  private addIterationEventSync(event: StoredIterationEvent) {
    this.requireDb().prepare(`
      INSERT INTO iteration_events (
        iteration_id, type, time, event_json
      ) VALUES (
        ?, ?, ?, ?
      )
    `).run(...toIterationEventParams(event));
  }

  private requireDb(): SqliteDatabase {
    if (!this.db) throw new Error("SQLite store has not been loaded.");
    return this.db;
  }
}

interface SqliteDatabase {
  close(): void;
  exec(sql: string): void;
  prepare(sql: string): SqliteStatement;
  transaction?<T extends unknown[]>(fn: (...args: T) => void): (...args: T) => void;
}

interface SqliteStatement {
  all(...params: unknown[]): unknown[];
  get(...params: unknown[]): unknown;
  run(...params: unknown[]): unknown;
}

function transaction<T extends unknown[]>(db: SqliteDatabase, fn: (...args: T) => void): (...args: T) => void {
  if (db.transaction) return db.transaction(fn);
  return (...args: T) => {
    db.exec("BEGIN");
    try {
      fn(...args);
      db.exec("COMMIT");
    } catch (error) {
      db.exec("ROLLBACK");
      throw error;
    }
  };
}

async function loadNodeSqlite(): Promise<{ DatabaseSync: new (path: string) => SqliteDatabase }> {
  try {
    return await import("node:sqlite") as { DatabaseSync: new (path: string) => SqliteDatabase };
  } catch (error) {
    throw new Error(
      "SQLite persistence requires a Node.js runtime with node:sqlite support. Use Node 22.5+ or start the server with in-memory persistence for tests.",
      { cause: error }
    );
  }
}

function toEventParams(event: StoredEvent): unknown[] {
  return [
    event.id,
    event.schema,
    event.event_id ?? null,
    event.type,
    event.severity,
    event.source.platform,
    event.source.adapter,
    event.correlation?.session_id ?? null,
    event.correlation?.run_id ?? null,
    event.correlation?.tool_call_id ?? null,
    event.time,
    event.receivedAt,
    JSON.stringify(event)
  ];
}

function toNotificationParams(notification: StoredNotification): unknown[] {
  return [
    notification.id,
    notification.provider,
    notification.status,
    notification.message.title,
    notification.createdAt,
    notification.error ?? null,
    JSON.stringify(notification)
  ];
}

function toAuditParams(record: StoredAuditRecord): unknown[] {
  return [
    record.audit_id,
    record.time,
    record.action,
    record.actor,
    record.source_adapter,
    record.run_id ?? null,
    record.session_id ?? null,
    record.safety_decision,
    record.immutable_event_id,
    record.redaction_policy_version,
    JSON.stringify(record)
  ];
}

function toIterationParams(iteration: StoredIterationRun): unknown[] {
  return [
    iteration.iteration_id,
    iteration.project_id,
    iteration.repo,
    iteration.branch,
    iteration.base_branch,
    iteration.pr_number ?? null,
    iteration.state,
    iteration.attempts,
    iteration.max_attempts,
    iteration.created_at,
    iteration.updated_at,
    JSON.stringify(iteration)
  ];
}

function toIterationEventParams(event: StoredIterationEvent): unknown[] {
  return [
    event.iteration_id,
    event.type,
    event.time,
    JSON.stringify(event)
  ];
}

function toProjectParams(project: StoredProject): unknown[] {
  return [
    project.project_id,
    project.name,
    project.repo ?? null,
    project.status,
    project.created_at,
    project.updated_at,
    JSON.stringify(project),
  ];
}

function toGoalParams(goal: StoredMasterGoal): unknown[] {
  return [
    goal.goal_id,
    goal.project_id,
    goal.title,
    goal.status,
    goal.created_at,
    goal.updated_at,
    JSON.stringify(goal),
  ];
}

function toPlanningMasterGoalParams(masterGoal: StoredPlanningMasterGoal): unknown[] {
  return [
    masterGoal.master_goal_id,
    masterGoal.project_id,
    masterGoal.title,
    masterGoal.source,
    masterGoal.priority,
    masterGoal.created_at,
    masterGoal.updated_at,
    JSON.stringify(masterGoal),
  ];
}

function toPlanningSessionParams(session: StoredPlanningSession): unknown[] {
  return [
    session.planning_session_id,
    session.master_goal_id,
    session.project_id,
    session.planner_adapter.planner_mode,
    session.created_at,
    session.updated_at,
    JSON.stringify(session),
  ];
}

function toTaskProposalParams(proposal: StoredTaskProposal): unknown[] {
  return [
    proposal.proposal_id,
    proposal.master_goal_id,
    proposal.planning_session_id ?? null,
    proposal.project_id,
    proposal.dedupe_key,
    proposal.status,
    proposal.risk,
    proposal.task_type,
    proposal.created_at,
    proposal.updated_at,
    JSON.stringify(proposal),
  ];
}

function toWorkerParams(worker: StoredWorker): unknown[] {
  return [
    worker.worker_id,
    worker.name,
    worker.provider,
    worker.enabled ? 1 : 0,
    worker.created_at,
    worker.updated_at,
    JSON.stringify(worker),
  ];
}

function toTaskParams(task: StoredTask): unknown[] {
  return [
    task.task_id,
    task.project_id,
    task.goal_id ?? null,
    task.status,
    task.risk,
    task.source,
    task.assigned_worker_id ?? null,
    task.created_at,
    task.updated_at,
    JSON.stringify(task),
  ];
}

function sliceTail<T>(items: T[], limit?: number): T[] {
  return limit ? items.slice(-limit) : [...items];
}

function upsertBy<T>(items: T[], item: T, getKey: (item: T) => string): void {
  const index = items.findIndex((existing) => getKey(existing) === getKey(item));
  if (index >= 0) items[index] = item;
  else items.push(item);
}
