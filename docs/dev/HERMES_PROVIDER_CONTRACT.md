# Hermes Provider Contract

SkyBridge talks to Hermes, not to a backend model provider.

The server-side Hermes adapter has one narrow contract:

```text
GET  /v1/capabilities
POST /v1/responses
```

## Capabilities

`GET /v1/capabilities` is used as a health and capability check before a manual task response call.

SkyBridge stores no raw capabilities response. It may summarize a status or model label into `provider_status`.

## Responses

`POST /v1/responses` receives a bounded, sanitized manual task prompt. The request states:

- output execution is disabled;
- command execution is forbidden;
- secrets must not be requested or revealed;
- the response is advisory for a human operator.

SkyBridge extracts a safe text preview from common response fields such as `output_text`, `text`, `content`, or text parts under `output[].content[]`.

## Defaults

- timeout: `60000` ms
- max response preview: `2000` characters
- raw request persistence: `false`
- raw response persistence: `false`
- token printed: `false`

Errors return safe summaries such as `timeout`, `hermes_http_401`, or a bounded exception class/message. Headers, request bodies, response bodies and credential values are not reported.
