import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { SkyBridgeEventSchema } from "@skybridge-agent-hub/event-schema";
import { normalize } from "./index.js";

const fixtureNames = [
  "run-created",
  "run-queued",
  "run-running",
  "run-completed",
  "run-failed",
  "event-stream-tool",
  "event-stream-tool-completed",
  "event-stream-status"
];

const fixtures = fixtureNames.map((name) => JSON.parse(readFileSync(join("src", "fixtures", `${name}.json`), "utf8")) as unknown);

describe("hermes api adapter", () => {
  it("normalizes Hermes run and stream fixtures", () => {
    const events = fixtures.flatMap((fixture) => normalize(fixture));
    expect(events.map((event) => event.type)).toEqual([
      "run.started",
      "run.started",
      "run.started",
      "run.completed",
      "run.failed",
      "tool.started",
      "tool.completed",
      "message.completed"
    ]);
    for (const event of events) expect(() => SkyBridgeEventSchema.parse(event)).not.toThrow();
  });

  it("handles malformed/minimal payloads and redacts obvious secrets", () => {
    expect(normalize(undefined)).toEqual([]);
    const minimal = JSON.parse(readFileSync(join("src", "fixtures", "malformed-minimal.json"), "utf8")) as unknown;
    const [event] = normalize(minimal);
    expect(event?.type).toBe("run.failed");
    expect(JSON.stringify(event?.payload)).not.toContain("abc.def");
    expect(JSON.stringify(event?.payload)).not.toContain("abc123");
  });
});
