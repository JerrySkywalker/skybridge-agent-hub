$ErrorActionPreference = "Stop"
foreach ($command in @("status", "alpha-preview", "alpha-apply-gate", "alpha-safe-summary", "blocked-state", "workunit-a-finalizer-preview", "workunit-a-finalizer-evidence", "workunit-a-finalizer-report", "workunit-b-apply-gate", "workunit-b-hold-report", "workunit-b-finalizer-preview", "workunit-b-finalizer-evidence", "workunit-b-finalizer-report", "alpha-completion-readiness", "v1-alpha-release-report")) {
  $json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command $command -Json | Out-String).Trim()
  if ($json -match 'token_printed"\s*:\s*true') { throw "token_printed=true in $command" }
}
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-token-printed-false"; token_printed = $false } | ConvertTo-Json -Compress
