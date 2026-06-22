[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\campaign-policy-report-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

$tasks = @(
  [pscustomobject]@{
    task_id = "campaign-policy-compiler-pilot-docs-001"
    project_id = "skybridge-agent-hub"
    campaign_id = "campaign-policy-compiler-pilot-001"
    title = "Campaign compiler pilot 001"
    status = "queued"
    risk = "low"
    task_type = "docs"
    allowed_paths = @("docs/operations/CAMPAIGN_COMPILER_PILOT_001.md")
    hygiene_metadata = [pscustomobject]@{ campaign_id = "campaign-policy-compiler-pilot-001"; campaign_task_compiler_pilot = $true }
    token_printed = $false
  },
  [pscustomobject]@{
    task_id = "campaign-policy-compiler-pilot-docs-002"
    project_id = "skybridge-agent-hub"
    campaign_id = "campaign-policy-compiler-pilot-001"
    title = "Campaign compiler pilot 002"
    status = "completed"
    risk = "low"
    task_type = "docs"
    allowed_paths = @("docs/operations/CAMPAIGN_COMPILER_PILOT_002.md")
    hygiene_metadata = [pscustomobject]@{ campaign_id = "campaign-policy-compiler-pilot-001"; campaign_task_compiler_pilot = $true }
    token_printed = $false
  },
  [pscustomobject]@{ task_id = "old-failed-001"; status = "failed"; risk = "low"; task_type = "docs"; token_printed = $false }
)

$compiler = [pscustomobject]@{
  schema = "skybridge.campaign_task_compiler.v1"
  ok = $true
  campaign_id = "campaign-policy-compiler-pilot-001"
  generated_tasks = @($tasks[0], $tasks[1])
  rejected_items = @([pscustomobject]@{ item_index = 9; task_id = $null; reasons = @("unsafe_requested_surface"); token_printed = $false })
  dependency_order = @("campaign-policy-compiler-pilot-docs-001", "campaign-policy-compiler-pilot-docs-002")
  token_printed = $false
}

$bounded = [pscustomobject]@{
  schema = "skybridge.run_until_hold_bounded.v1"
  ok = $true
  evidence_summary = [pscustomobject]@{ evidence_present = $true; attempted_task_count = 2; token_printed = $false }
  token_printed = $false
}

$tasksPath = Write-Fixture "tasks.json" ([pscustomobject]@{ tasks = $tasks })
$compilerPath = Write-Fixture "compiler.json" $compiler
$boundedPath = Write-Fixture "bounded.json" $bounded

$raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-campaign-policy-report.ps1 `
  -FixtureTasksFile $tasksPath `
  -FixtureCompilerFile $compilerPath `
  -FixtureBoundedRunFile $boundedPath `
  -Json
if ($LASTEXITCODE -ne 0) { throw "campaign policy report failed." }
$text = (($raw | Out-String).Trim())
Assert-NoUnsafeText $text
$report = $text | ConvertFrom-Json
if ($report.schema -ne "skybridge.campaign_policy_report.v1") { throw "Unexpected campaign policy report schema." }
Assert-True $report.ok "policy report ok"
if ($report.safe_task_count -ne 2) { throw "Policy report should count two safe tasks." }
if ($report.generated_task_count -ne 2) { throw "Policy report should count two generated tasks." }
if ($report.rejected_task_count -ne 1) { throw "Policy report should count rejected fixture item." }
if (@($report.unsafe_surface_rejections).Count -lt 8) { throw "Unsafe surface rejection proof missing." }
Assert-False $report.old_residue_selected "old residue selected"
Assert-False $report.token_printed "report token_printed"

$summary = [pscustomobject]@{
  ok = $true
  smoke = "campaign-policy-report"
  scenarios = @(
    "campaign_policy_report_schema",
    "safe_generated_tasks_included",
    "rejected_unsafe_requests_included",
    "dependency_order_included",
    "evidence_state_included",
    "old_residue_selected_false",
    "token_printed_false"
  )
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "campaign-policy-report" }
