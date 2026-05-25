import { afterEach, describe, expect, it, vi } from "vitest";
import { SkyBridgeClient } from "./index.js";

const fetchMock = vi.fn();

afterEach(() => {
  fetchMock.mockReset();
  vi.unstubAllGlobals();
});

function jsonResponse(body: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body
  } as Response;
}

describe("SkyBridgeClient", () => {
  it("builds filtered event URLs", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValueOnce(jsonResponse({ events: [] }));
    const client = new SkyBridgeClient("http://127.0.0.1:8787/");

    await client.listEvents({
      platform: "codex",
      adapter: "codex-hook",
      severity: "warning",
      type: "approval.requested",
      limit: 25,
      offset: 10
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "http://127.0.0.1:8787/v1/events?platform=codex&adapter=codex-hook&severity=warning&type=approval.requested&limit=25&offset=10"
    );
  });

  it("builds run, detail and notification URLs", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ runs: [] }))
      .mockResolvedValueOnce(jsonResponse({ summary: { run_id: "run/1" }, events: [] }))
      .mockResolvedValueOnce(jsonResponse({ notifications: [] }));
    const client = new SkyBridgeClient("http://localhost:8787");

    await client.listRuns({ status: "failed", goal: "console", limit: 10 });
    await client.getRun("run/1", { limit: 50 });
    await client.listNotifications({ status: "skipped", provider: "placeholder" });

    expect(fetchMock).toHaveBeenNthCalledWith(1, "http://localhost:8787/v1/runs?status=failed&goal=console&limit=10");
    expect(fetchMock).toHaveBeenNthCalledWith(2, "http://localhost:8787/v1/runs/run%2F1?limit=50");
    expect(fetchMock).toHaveBeenNthCalledWith(3, "http://localhost:8787/v1/notifications?status=skipped&provider=placeholder");
  });

  it("returns health and summary responses", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ ok: true, service: "skybridge-server", persistence: "memory", time: "2026-05-21T00:00:00.000Z" }))
      .mockResolvedValueOnce(jsonResponse({ health: {}, totals: { events: 0 }, sources: [] }));
    const client = new SkyBridgeClient("http://localhost:8787");

    await expect(client.getHealth()).resolves.toMatchObject({ service: "skybridge-server" });
    await expect(client.getSummary()).resolves.toMatchObject({ sources: [] });
  });

  it("returns derived audit entries", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValueOnce(jsonResponse({
      audit: [{
        audit_id: "audit-1",
        action: "approval.denied",
        actor: "operator",
        source_adapter: "skybridge/approval-api",
        safety_decision: "operator_denied",
        immutable_event_id: "event-1",
        redaction_policy_version: "packages/event-schema/src/redaction-rules.json",
        raw_payload_included: false
      }]
    }));
    const client = new SkyBridgeClient("http://localhost:8787");

    await expect(client.listAuditEntries({ run_id: "run-1", action: "approval.denied", limit: 10 })).resolves.toEqual([
      expect.objectContaining({ audit_id: "audit-1", raw_payload_included: false })
    ]);
    expect(fetchMock).toHaveBeenCalledWith("http://localhost:8787/v1/audit?run_id=run-1&action=approval.denied&limit=10");
  });

  it("returns iteration and supervisor status helpers", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ iterations: [{ iteration_id: "iter-1", state: "ci_pending" }] }))
      .mockResolvedValueOnce(jsonResponse({ iteration: { iteration_id: "iter-1", state: "ci_pending", events: [] } }))
      .mockResolvedValueOnce(jsonResponse({ ok: true, raw_prompts_included: false, raw_logs_included: false, iterations: { total: 1, active: 1, blocked: 0 }, recent_iteration_events: [] }))
      .mockResolvedValueOnce(jsonResponse({ action: "repair_ci", iteration_id: "iter-1", pr_number: 12 }));
    const client = new SkyBridgeClient("http://localhost:8787");

    await expect(client.listIterations()).resolves.toEqual([expect.objectContaining({ iteration_id: "iter-1" })]);
    await expect(client.getIteration("iter-1")).resolves.toMatchObject({ iteration_id: "iter-1", events: [] });
    await expect(client.getSupervisorStatus()).resolves.toMatchObject({ raw_logs_included: false });
    await expect(client.getSupervisorNextAction()).resolves.toMatchObject({ action: "repair_ci", pr_number: 12 });
  });

  it("returns product dashboard summaries with stable URLs", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ projects: [{ project_id: "skybridge-agent-hub" }] }))
      .mockResolvedValueOnce(jsonResponse({ total: 1, active: 1, blocked: 0, failed: 0, repair_attempts: 0, recent: [] }))
      .mockResolvedValueOnce(jsonResponse({ total: 1, open: 1, merged: 0, blocked: 0, eligible: 1, ci_failed: 0, latest_ci_state: "ci_green", prs: [] }))
      .mockResolvedValueOnce(jsonResponse({ total: 1, sent: 1, skipped: 0, failed: 0, pending: 0, by_severity: {}, providers: [], bootstrap_fallback: { status: "available-manual", script: "notify-bootstrap.ps1", real_send_requires_explicit_send: true }, recent: [] }))
      .mockResolvedValueOnce(jsonResponse({ status: "placeholder", tunnel: { status: "unknown", public_exposure: false }, api: { health: "placeholder", base_publicly_exposed: false }, capabilities: [], related_iterations: [] }))
      .mockResolvedValueOnce(jsonResponse({ enabled_by_default: false, dry_run_default: true, total_prs: 1, eligible: 1, blocked: 0, pending: 0, merged_history: [], decisions: [] }));
    const client = new SkyBridgeClient("http://localhost:8787/");

    await expect(client.listProjects()).resolves.toEqual([expect.objectContaining({ project_id: "skybridge-agent-hub" })]);
    await expect(client.getIterationsSummary()).resolves.toMatchObject({ total: 1 });
    await expect(client.getPrsSummary()).resolves.toMatchObject({ latest_ci_state: "ci_green" });
    await expect(client.getNotificationsSummary()).resolves.toMatchObject({ sent: 1 });
    await expect(client.getHermesSummary()).resolves.toMatchObject({ status: "placeholder" });
    await expect(client.getAutoMergeSummary()).resolves.toMatchObject({ dry_run_default: true });

    expect(fetchMock).toHaveBeenNthCalledWith(1, "http://localhost:8787/v1/projects");
    expect(fetchMock).toHaveBeenNthCalledWith(2, "http://localhost:8787/v1/iterations/summary");
    expect(fetchMock).toHaveBeenNthCalledWith(3, "http://localhost:8787/v1/prs/summary");
    expect(fetchMock).toHaveBeenNthCalledWith(4, "http://localhost:8787/v1/notifications/summary");
    expect(fetchMock).toHaveBeenNthCalledWith(5, "http://localhost:8787/v1/hermes/summary");
    expect(fetchMock).toHaveBeenNthCalledWith(6, "http://localhost:8787/v1/automerge/summary");
  });

  it("throws useful errors for non-2xx responses", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValueOnce(jsonResponse({ error: "invalid_query" }, 400));
    const client = new SkyBridgeClient("http://localhost:8787");

    await expect(client.listEvents({ limit: 1 })).rejects.toThrow("HTTP 400");
  });
});
