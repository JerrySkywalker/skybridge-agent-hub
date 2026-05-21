import Fastify, { type FastifyInstance } from "fastify";
import { createEvent, parseEvent } from "@skybridge-agent-hub/event-schema";

export interface SidecarOptions {
  cloudUrl?: string;
  nodeId?: string;
  host?: string;
  labels?: string[];
  capabilities?: string[];
  version?: string;
  logger?: boolean;
}

export interface NodeIdentity {
  node_id: string;
  host: string;
  labels: string[];
  capabilities: string[];
  last_seen: string;
  sidecar_version: string;
}

export function resolveNodeIdentity(options: SidecarOptions = {}): NodeIdentity {
  return {
    node_id: options.nodeId ?? process.env.SKYBRIDGE_NODE_ID ?? `local-${safeHost(options.host ?? process.env.COMPUTERNAME ?? process.env.HOSTNAME ?? "node")}`,
    host: options.host ?? process.env.SKYBRIDGE_NODE_HOST ?? process.env.COMPUTERNAME ?? process.env.HOSTNAME ?? "localhost",
    labels: options.labels ?? splitCsv(process.env.SKYBRIDGE_NODE_LABELS) ?? ["local", "sidecar"],
    capabilities: options.capabilities ?? splitCsv(process.env.SKYBRIDGE_NODE_CAPABILITIES) ?? ["event-forwarding", "heartbeat", "spool"],
    last_seen: new Date().toISOString(),
    sidecar_version: options.version ?? process.env.npm_package_version ?? "0.1.0"
  };
}

export async function createSidecar(options: SidecarOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({ logger: options.logger ?? true });
  const cloudUrl = options.cloudUrl ?? process.env.SKYBRIDGE_CLOUD_URL ?? "http://127.0.0.1:8787";
  const spool: unknown[] = [];
  const identity = () => ({ ...resolveNodeIdentity(options), last_seen: new Date().toISOString() });

  app.get("/health", async () => ({
    ok: true,
    service: "skybridge-sidecar",
    cloudUrl,
    node: identity(),
    spool: { queued: spool.length },
    remote_control: { enabled: false, reason: "Remote command execution is not implemented in the sidecar foundation." },
    time: new Date().toISOString()
  }));

  app.get("/v1/local/status", async () => ({
    ok: true,
    node: identity(),
    spool: { queued: spool.length },
    capabilities: identity().capabilities
  }));

  app.post("/v1/local/heartbeat", async (_request, reply) => {
    const node = identity();
    const event = createEvent({
      type: "node.heartbeat",
      source: { platform: "skybridge", adapter: "sidecar", node_id: node.node_id },
      correlation: { session_id: node.node_id },
      payload: node
    });
    try {
      const response = await fetch(`${cloudUrl}/v1/events`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(event)
      });
      return reply.code(response.ok ? 202 : 502).send({ ok: response.ok, node });
    } catch (error) {
      spool.push(event);
      _request.log.warn({ error }, "failed to forward heartbeat");
      return reply.code(202).send({ ok: false, spooled: true, node });
    }
  });

  app.post("/v1/local/events", async (request, reply) => {
    const event = parseEvent(request.body);
    try {
      const response = await fetch(`${cloudUrl}/v1/events`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(event)
      });
      if (!response.ok) {
        spool.push(event);
        return reply.code(202).send({ ok: false, spooled: true });
      }
      return reply.code(202).send({ ok: true, spooled: false });
    } catch (error) {
      spool.push(event);
      request.log.warn({ error }, "failed to forward event");
      return reply.code(202).send({ ok: false, spooled: true });
    }
  });

  return app;
}

function splitCsv(value: string | undefined): string[] | undefined {
  const items = value?.split(",").map((item) => item.trim()).filter(Boolean);
  return items && items.length > 0 ? items : undefined;
}

function safeHost(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-|-$/g, "") || "node";
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, "/"))) {
  const app = await createSidecar();
  await app.listen({ host: "127.0.0.1", port: Number(process.env.SIDECAR_PORT || 8789) });
}
