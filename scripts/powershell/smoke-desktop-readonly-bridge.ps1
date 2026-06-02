$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$source = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")
foreach ($expected in @("skybridge-status.ps1", "skybridge-campaign.ps1", "skybridge-worker-status.ps1", "-ActiveOnly", "register-heartbeat", "token_printed: false")) {
  if ($source -notmatch [regex]::Escape($expected)) { throw "Desktop bridge missing expected contract: $expected" }
}
foreach ($forbidden in @("start-one", "start-all", "execute-step", "run-until-complete", "run-until-hold", "run-next", "skybridge-edge-worker.ps1")) {
  if ($source -match [regex]::Escape($forbidden)) { throw "Desktop bridge contains forbidden execution command: $forbidden" }
}
if ($source -notmatch '\.agent"\)\.join\("desktop-client"') { throw "Expected desktop client metadata path under .agent/desktop-client." }
[pscustomobject]@{ ok = $true; scenario = "desktop-readonly-bridge"; token_printed = $false } | ConvertTo-Json -Compress
