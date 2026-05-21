import { describe, expect, it } from "vitest";
import { send } from "./index.js";

describe("wecom provider", () => {
  it("returns structured skipped status without credentials", async () => {
    await expect(send({ title: "SkyBridge", body: "test" })).resolves.toMatchObject({
      provider: "wecom",
      status: "skipped"
    });
  });
});
