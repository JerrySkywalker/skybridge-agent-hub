import { describe, expect, it } from "vitest";
import { send } from "./index.js";

describe("xiaomi push provider", () => {
  it("returns structured skipped status without credentials", async () => {
    await expect(send({ title: "SkyBridge", body: "test" })).resolves.toMatchObject({
      provider: "xiaomi-push",
      status: "skipped"
    });
  });
});
