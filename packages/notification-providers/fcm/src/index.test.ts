import { describe, expect, it } from "vitest";
import { send } from "./index.js";

describe("fcm provider", () => {
  it("returns structured skipped status without credentials", async () => {
    await expect(send({ title: "SkyBridge", body: "test" })).resolves.toMatchObject({
      provider: "fcm",
      status: "skipped"
    });
  });
});
