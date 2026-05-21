import Fastify from "fastify";
import { parseEvent } from "@skybridge-agent-hub/event-schema";

const app = Fastify({ logger: true });
const cloudUrl = process.env.SKYBRIDGE_CLOUD_URL || "http://127.0.0.1:8787";

app.get("/health", async () => ({
  ok: true,
  service: "skybridge-sidecar",
  cloudUrl,
  time: new Date().toISOString()
}));

app.post("/v1/local/events", async (request, reply) => {
  const event = parseEvent(request.body);
  try {
    const response = await fetch(`${cloudUrl}/v1/events`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(event)
    });
    return reply.code(response.ok ? 202 : 502).send({ ok: response.ok });
  } catch (error) {
    // Later: spool to local JSONL/SQLite.
    request.log.warn({ error }, "failed to forward event");
    return reply.code(202).send({ ok: false, spooled: false });
  }
});

await app.listen({ host: "127.0.0.1", port: Number(process.env.SIDECAR_PORT || 8789) });
