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

  it("throws useful errors for non-2xx responses", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValueOnce(jsonResponse({ error: "invalid_query" }, 400));
    const client = new SkyBridgeClient("http://localhost:8787");

    await expect(client.listEvents({ limit: 1 })).rejects.toThrow("HTTP 400");
  });
});
