# Embedding SkyBridge Status

SkyBridge ships a framework-neutral Web Component for compact local dashboards.

## Web Component

Build or import `@skybridge-agent-hub/web-components`, then add:

```html
<script type="module" src="./path/to/skybridge-web-components.js"></script>

<agent-status-card
  api-base="http://127.0.0.1:8787"
  compact
  refresh-ms="15000"
></agent-status-card>
```

Attributes:

- `api-base`: SkyBridge API base URL. Defaults to `http://127.0.0.1:8787`.
- `compact`: renders a narrow status card for Glance or small HTML panels.
- `mode="compact"`: equivalent to `compact`.
- `refresh-ms`: polling interval. Values below 5000 ms are ignored.

The component reads:

- `GET /v1/health`
- `GET /v1/events?limit=25`
- `GET /v1/runs?limit=25`

If the server is unavailable, the card stays rendered and switches to `offline` with a concise error.

## Web App Compact Route

The web app also exposes a compact route:

```text
http://127.0.0.1:5173/embed/compact
```

Hash fallback:

```text
http://127.0.0.1:5173/#/embed/compact
```

Use this when a host dashboard can embed an iframe but cannot load custom JavaScript modules directly.
