$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$web = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$bridge = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")

foreach ($label in @("Start One disabled", "Start Queue disabled", "Resume disabled")) {
  if ($web -notmatch [regex]::Escape($label)) {
    throw "Web missing disabled placeholder: $label"
  }
}

if ($web -match '<button[^>]*(Start One|Start Queue|Resume)[\s\S]*?onClick=') {
  throw "Web contains an active start/resume placeholder button."
}

if ($desktop -match '<button[^>]*(Start One|Start Queue|Resume|Stop|Emergency Stop)') {
  throw "Desktop must not add execution-control buttons in Goal 191D."
}

foreach ($forbidden in @("start-one", "start-all", "resume -Apply", "execute-step", "skybridge-edge-worker.ps1")) {
  if ($web -match [regex]::Escape($forbidden)) {
    throw "Web queue dashboard contains forbidden execution text: $forbidden"
  }
  if ($desktop -match [regex]::Escape($forbidden)) {
    throw "Desktop queue dashboard contains forbidden execution text: $forbidden"
  }
}

foreach ($allowedLegacy in @("register-heartbeat")) {
  if ($bridge -notmatch [regex]::Escape($allowedLegacy)) {
    throw "Existing heartbeat-only bridge command disappeared unexpectedly."
  }
}

foreach ($forbidden in @("start-one", "start-all", "execute-step", "run-until-complete", "run-until-hold", "run-next", "skybridge-edge-worker.ps1")) {
  if ($bridge -match [regex]::Escape($forbidden)) {
    throw "Desktop bridge contains forbidden execution command: $forbidden"
  }
}

[pscustomobject]@{
  ok = $true
  scenario = "queue-dashboard-no-mutation-buttons"
  token_printed = $false
} | ConvertTo-Json -Compress
