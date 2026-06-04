$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$libPath = Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs"
$uiPath = Join-Path $repoRoot "apps\desktop\src\main.tsx"
$lib = Get-Content -Raw -LiteralPath $libPath
$ui = Get-Content -Raw -LiteralPath $uiPath

foreach ($expected in @(
  "mode_banner",
  "mutation_scope",
  "execution_disabled",
  "pre190_readiness",
  "goal_190_linked_task_ids_count",
  "goal_190_linked_pr_urls_count",
  "status_age_seconds",
  "warnings",
  "STANDBY / READ ONLY",
  "HEARTBEAT ONLY MUTATION",
  "EXECUTION DISABLED",
  "token_printed"
)) {
  if (($lib + "`n" + $ui) -notmatch [regex]::Escape($expected)) {
    throw "Desktop readiness contract missing expected field/text: $expected"
  }
}

foreach ($expected in @("PASS", "WARN", "BLOCK", "active_tasks=unknown", "stale_leases=unknown")) {
  if ($lib -notmatch [regex]::Escape($expected)) {
    throw "Desktop readiness evaluator missing expected state: $expected"
  }
}

foreach ($forbidden in @("#[tauri::command]`r`nfn run", "fn run_shell", "fn shell", "Command::new(command", "invoke_handler(tauri::generate_handler![run")) {
  if ($lib -match [regex]::Escape($forbidden)) {
    throw "Desktop bridge appears to expose a generic shell bridge: $forbidden"
  }
}

[pscustomobject]@{ ok = $true; scenario = "desktop-readiness-contract"; token_printed = $false } | ConvertTo-Json -Compress
