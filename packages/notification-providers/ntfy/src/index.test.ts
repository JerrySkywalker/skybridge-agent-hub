import { afterEach, describe, expect, it, vi } from "vitest";
import { send } from "./index.js";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("ntfy provider", () => {
  it("returns structured skipped status when topic is missing", async () => {
    const result = await send({ title: "SkyBridge", body: "test" }, {});
    expect(result).toEqual({ provider: "ntfy", status: "skipped", error: "NTFY_TOPIC_URL is not configured." });
  });

  it("returns sent status for successful requests", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("", { status: 200 })));
    const result = await send({ title: "SkyBridge", body: "test" }, { topicUrl: "https://ntfy.sh/topic" });
    expect(result).toEqual({ provider: "ntfy", status: "sent" });
  });
});
