$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$reportDir = ".agent/tmp/bootstrap-alpha-rc"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-bootstrap-alpha-rc-gate.ps1") -Command audit -ApiBase "" -TokenFile "" -WriteReport -ReportDir $reportDir -Json
if ($LASTEXITCODE -ne 0) { throw "RC gate audit report failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

if ([string]$result.schema -ne "skybridge.bootstrap_alpha_rc_gate.v1") { throw "Unexpected RC report schema." }
if ([string]::IsNullOrWhiteSpace([string]$result.report_json_path)) { throw "Missing JSON report path." }
if ([string]::IsNullOrWhiteSpace([string]$result.report_markdown_path)) { throw "Missing Markdown report path." }
Assert-FileExists ([string]$result.report_json_path)
Assert-FileExists ([string]$result.report_markdown_path)
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.deploy_mutation_performed "deploy_mutation_performed"
Assert-False $result.tag_created "tag_created"
Assert-False $result.token_printed "token_printed"

$jsonText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$result.report_json_path))
$markdownText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$result.report_markdown_path))
Assert-NoUnsafeText $jsonText
Assert-NoUnsafeText $markdownText
if ($jsonText -match "(?i)authorization\s*[:=]\s*bearer|environment dump|provider auth|proxy profile") { throw "Unsafe report JSON text detected." }
if ($markdownText -match "(?i)authorization\s*[:=]\s*bearer|environment dump|provider auth|proxy profile") { throw "Unsafe report Markdown text detected." }

[pscustomobject]@{
  ok = $true
  smoke = "bootstrap-alpha-rc-report"
  report_json_path = [string]$result.report_json_path
  report_markdown_path = [string]$result.report_markdown_path
  token_printed = $false
} | ConvertTo-Json
