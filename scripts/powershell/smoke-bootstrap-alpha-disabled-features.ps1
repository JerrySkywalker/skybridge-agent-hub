$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$doc = "docs/release/BOOTSTRAP_ALPHA_DISABLED_FEATURES.md"
Assert-FileExists $doc
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $doc)

$required = @(
  "general remote shell",
  "unbounded run",
  "daemon auto-expansion",
  "arbitrary task execution",
  "arbitrary prompt execution",
  "MATLAB arbitrary command",
  "Codex arbitrary prompt",
  "production deployment automation for other projects",
  "PR creation by worker runner",
  "auto-merge",
  "multi-user permissions",
  "mobile/watch client",
  "notification center productization",
  "multi-project production support",
  "long-running real research sweeps",
  "background autonomous queue processing"
)

foreach ($feature in $required) {
  if ($text -notmatch [regex]::Escape($feature)) { throw "Missing disabled feature: $feature" }
}
foreach ($flag in @("task_claimed=false", "execution_started=false", "deploy_mutation_performed=false", "tag_created=false", "token_printed=false")) {
  if ($text -notmatch [regex]::Escape($flag)) { throw "Missing RC safety flag: $flag" }
}
Assert-NoUnsafeText $text

[pscustomobject]@{
  ok = $true
  smoke = "bootstrap-alpha-disabled-features"
  disabled_feature_count = $required.Count
  token_printed = $false
} | ConvertTo-Json
