import { existsSync, mkdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname } from "node:path";
import type { SkyBridgeEvent } from "@skybridge-agent-hub/event-schema";
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

interface LocalStoreData {
  events: StoredEvent[];
  notifications: StoredNotification[];
  audit: StoredAuditRecord[];
}

export interface EventStore {
  kind: "memory" | "sqlite";
  load(): Promise<void>;
  close(): Promise<void>;
  listEvents(limit?: number): StoredEvent[];
  listNotifications(limit?: number): StoredNotification[];
  listAuditRecords(limit?: number): StoredAuditRecord[];
  addEvent(event: StoredEvent): Promise<void>;
  addNotification(notification: StoredNotification): Promise<void>;
  addAuditRecord(record: StoredAuditRecord): Promise<void>;
}

export class MemoryStore implements EventStore {
  kind = "memory" as const;
  private data: LocalStoreData = { events: [], notifications: [], audit: [] };

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

      CREATE TABLE IF NOT EXISTS store_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
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

    insertEvents(events);
    insertNotifications(notifications);
    db.prepare("INSERT OR REPLACE INTO store_metadata (key, value) VALUES (?, ?)").run(
      migratedKey,
      JSON.stringify({ migratedAt: new Date().toISOString(), events: events.length, notifications: notifications.length })
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

function sliceTail<T>(items: T[], limit?: number): T[] {
  return limit ? items.slice(-limit) : [...items];
}
