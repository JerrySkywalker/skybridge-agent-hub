$ErrorActionPreference = "Stop"

$requiredFiles = @(
  "README.md",
  "SECURITY.md",
  "ROADMAP.md",
  "CHANGELOG.md",
  "docs\release\V0_9_RELEASE_CANDIDATE.md",
  "docs\security\THREAT_MODEL.md",
  "docs\operations\SELF_HOSTING.md",
  "docs\approval\APPROVAL_MODEL.md",
  "docs\observability\METRICS_AND_AUDIT.md",
  "scripts\powershell\generate-demo-dataset.ps1",
  "scripts\powershell\smoke-dogfooding-loop.ps1"
)

foreach ($path in $requiredFiles) {
  if (-not (Test-Path $path)) {
    throw "Missing release candidate file: $path"
  }
}

pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\generate-demo-dataset.ps1 -OutputPath .\docs\demo\skybridge-demo-events.json | Out-Host

$demo = Get-Content .\docs\demo\skybridge-demo-events.json -Raw | ConvertFrom-Json
if ($demo.Count -lt 8) {
  throw "Demo dataset is unexpectedly small"
}

Write-Host "Release candidate smoke passed with $($demo.Count) demo events."
