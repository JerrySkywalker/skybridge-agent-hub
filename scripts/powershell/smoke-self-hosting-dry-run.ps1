$ErrorActionPreference = "Stop"

$required = @(
  "deploy/docker-compose.prod.yml",
  "docs/operations/SELF_HOSTING.md",
  "docs/operations/OPENRESTY_AUTHELIA_EXAMPLE.md",
  ".env.example"
)

foreach ($path in $required) {
  if (-not (Test-Path $path)) {
    throw "Missing self-hosting file: $path"
  }
}

$envExample = Get-Content .\.env.example -Raw
foreach ($name in @("SKYBRIDGE_DB_FILE", "NTFY_TOPIC_URL", "SKYBRIDGE_NODE_ID", "SKYBRIDGE_REMOTE_CONTROL_ENABLED")) {
  if ($envExample -notmatch [regex]::Escape($name)) {
    throw ".env.example is missing $name"
  }
}

$compose = docker compose -f deploy/docker-compose.prod.yml config
if ($LASTEXITCODE -ne 0) {
  throw "prod compose config failed"
}

if ($compose -match "NTFY_TOKEN=|FCM_SERVER_KEY=|XIAOMI_PUSH_SECRET=") {
  throw "compose config printed secret-like env values"
}

Write-Host "Self-hosting dry-run smoke passed; no containers were started."
