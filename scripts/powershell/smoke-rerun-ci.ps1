$ErrorActionPreference = "Stop"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-rerun-ci-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$runsPath = Join-Path $tempDir "runs.json"
$logPath = Join-Path $tempDir "failed.log"
try {
  @(
    @{ databaseId = 123; conclusion = "failure"; status = "completed"; displayTitle = "PR CI"; workflowName = "PR CI"; url = "https://example.invalid/run/123" },
    @{ databaseId = 124; conclusion = "success"; status = "completed"; displayTitle = "Docs"; workflowName = "Docs"; url = "https://example.invalid/run/124" }
  ) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runsPath -Encoding UTF8
  "actions/checkout failed with HTTP 403 expected 'packfile'" | Set-Content -LiteralPath $logPath -Encoding UTF8
  $output = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-rerun-ci.ps1 -PrNumber 57 -FixtureRunsFile $runsPath -FixtureLogFile $logPath -Json
  $parsed = $output | ConvertFrom-Json
  if (-not $parsed.dry_run) { throw "Expected dry-run by default." }
  if (@($parsed.failed_runs).Count -ne 1) { throw "Expected one failed fixture run." }
  if ($parsed.classification -ne "ci_blocked_checkout_403") { throw "Unexpected classification $($parsed.classification)." }
  [pscustomobject]@{
    DryRun = $parsed.dry_run
    FailedRuns = @($parsed.failed_runs).Count
    Classification = $parsed.classification
    RealGitHubApiCalled = $false
  } | Format-List
} finally {
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
