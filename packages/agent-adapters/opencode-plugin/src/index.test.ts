import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { SkyBridgeEventSchema } from "@skybridge-agent-hub/event-schema";
import { normalize } from "./index.js";

const fixtureNames = [
  "session-created",
  "session-status-idle",
  "session-error",
  "tool-before",
  "tool-after",
  "file-edited",
  "permission-asked",
  "permission-replied",
  "todo-updated"
];

const fixtures = fixtureNames.map((name) => JSON.parse(readFileSync(join("src", "fixtures", `${name}.json`), "utf8")) as unknown);

describe("opencode plugin adapter", () => {
  it("normalizes representative OpenCode fixtures", () => {
    const events = fixtures.flatMap((fixture) => normalize(fixture));
    expect(events.map((event) => event.type)).toEqual([
      "session.started",
      "agent.idle",
      "run.failed",
      "tool.started",
      "tool.completed",
      "file.edited",
      "approval.requested",
      "approval.resolved",
      "todo.updated"
    ]);
    for (const event of events) expect(() => SkyBridgeEventSchema.parse(event)).not.toThrow();
  });

  it("handles malformed/minimal payloads and redacts obvious secrets", () => {
    expect(normalize(null)).toEqual([]);
    const minimal = JSON.parse(readFileSync(join("src", "fixtures", "malformed-minimal.json"), "utf8")) as unknown;
    const [event] = normalize(minimal);
    expect(event?.type).toBe("message.completed");
    expect(JSON.stringify(event?.payload)).not.toContain("abc.def.ghi");
    expect(JSON.stringify(event?.payload)).not.toContain("abc123");
  });
});
