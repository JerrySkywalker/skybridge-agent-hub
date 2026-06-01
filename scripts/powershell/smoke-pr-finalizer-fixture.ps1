[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Scenario
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-pr-finalizer-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

function Write-Fixture {
  param($Value)
  $path = Join-Path $tempDir "pr.json"
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Invoke-Finalizer {
  param([string]$Fixture, [string[]]$Extra = @())
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-pr-finalize.ps1 -FixtureFile $Fixture -ExpectedFiles "docs/dev/example.md" -DryRun -Json @Extra
  if ($LASTEXITCODE -ne 0) { throw "finalizer failed: $output" }
  return ($output | ConvertFrom-Json)
}

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

try {
  switch ($Scenario) {
    "pending-wait" {
      $fixture = Write-Fixture @{ number = 10; url = "https://github.com/example/repo/pull/10"; state = "OPEN"; isDraft = $false; merged = $false; files = @(@{ path = "docs/dev/example.md" }); statusCheckRollup = @(@{ name = "Project check"; status = "IN_PROGRESS"; conclusion = $null }) }
      $result = Invoke-Finalizer -Fixture $fixture
      Assert-True ($result.decision -eq "wait_pending") "Expected wait_pending."
    }
    "safe-merge" {
      $fixture = Write-Fixture @{ number = 11; url = "https://github.com/example/repo/pull/11"; state = "OPEN"; isDraft = $false; merged = $false; files = @(@{ path = "docs/dev/example.md" }); statusCheckRollup = @(@{ name = "Project check"; status = "COMPLETED"; conclusion = "SUCCESS" }) }
      $result = Invoke-Finalizer -Fixture $fixture -Extra @("-AllowAutoMerge")
      Assert-True ($result.decision -eq "would_auto_merge") "Expected would_auto_merge."
      Assert-True ($result.safe_to_merge -eq $true) "Expected safe_to_merge."
    }
    "draft-ready" {
      $fixture = Write-Fixture @{ number = 14; url = "https://github.com/example/repo/pull/14"; state = "OPEN"; isDraft = $true; merged = $false; files = @(@{ path = "docs/dev/example.md" }); statusCheckRollup = @(@{ name = "Project check"; status = "IN_PROGRESS"; conclusion = $null }) }
      $result = Invoke-Finalizer -Fixture $fixture -Extra @("-RiskLevel", "low")
      Assert-True ($result.decision -eq "would_mark_ready") "Expected would_mark_ready."
      Assert-True ($result.safe_to_mark_ready -eq $true) "Expected safe_to_mark_ready."
    }
    "transient-retry" {
      $fixture = Write-Fixture @{ number = 15; url = "https://github.com/example/repo/pull/15"; state = "OPEN"; isDraft = $false; merged = $false; files = @(@{ path = "docs/dev/example.md" }); statusCheckRollup = @(@{ name = "checkout dependencies"; status = "COMPLETED"; conclusion = "FAILURE" }) }
      $result = Invoke-Finalizer -Fixture $fixture
      Assert-True ($result.decision -eq "rerun_transient_once") "Expected rerun_transient_once."
      Assert-True ($result.retry.allowed -eq $true) "Expected transient retry to be allowed."
    }
    "transient-retry-blocked" {
      $fixture = Write-Fixture @{ number = 16; url = "https://github.com/example/repo/pull/16"; state = "OPEN"; isDraft = $false; merged = $false; files = @(@{ path = "docs/dev/example.md" }); statusCheckRollup = @(@{ name = "checkout dependencies"; status = "COMPLETED"; conclusion = "FAILURE" }) }
      $stateFile = Join-Path $tempDir "retry-state.json"
      @{ attempts = 1; reasons = @("transient_check_failure") } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
      $result = Invoke-Finalizer -Fixture $fixture -Extra @("-RetryStateFile", $stateFile)
      Assert-True ($result.decision -eq "blocked_transient_ci_after_retry") "Expected transient retry block."
      Assert-True ($result.ok -eq $false) "Expected blocked retry to fail finalizer."
    }
    "blocks-unsafe-files" {
      $fixture = Write-Fixture @{ number = 12; url = "https://github.com/example/repo/pull/12"; state = "OPEN"; isDraft = $false; merged = $false; files = @(@{ path = ".env" }); statusCheckRollup = @(@{ name = "Project check"; status = "COMPLETED"; conclusion = "SUCCESS" }) }
      $result = Invoke-Finalizer -Fixture $fixture -Extra @("-AllowAutoMerge")
      Assert-True ($result.decision -eq "blocked_unsafe_files") "Expected unsafe file block."
    }
    "blocks-high-risk-draft" {
      $fixture = Write-Fixture @{ number = 17; url = "https://github.com/example/repo/pull/17"; state = "OPEN"; isDraft = $true; merged = $false; files = @(@{ path = "docs/dev/example.md" }); statusCheckRollup = @(@{ name = "Project check"; status = "COMPLETED"; conclusion = "SUCCESS" }) }
      $result = Invoke-Finalizer -Fixture $fixture -Extra @("-RiskLevel", "high")
      Assert-True ($result.decision -eq "safe_no_auto_merge") "Expected high-risk draft to remain manual."
      Assert-True ($result.safe_to_mark_ready -eq $false) "Expected high-risk draft ready block."
    }
    "evidence-repair" {
      $fixture = Write-Fixture @{ number = 13; url = "https://github.com/example/repo/pull/13"; state = "MERGED"; isDraft = $false; merged = $true; mergeCommit = @{ oid = "abc123" }; files = @(@{ path = "docs/dev/example.md" }); statusCheckRollup = @(@{ name = "Project check"; status = "COMPLETED"; conclusion = "SUCCESS" }) }
      $result = Invoke-Finalizer -Fixture $fixture -Extra @("-AllowEvidenceRepair")
      Assert-True ($result.ci_status -eq "passed") "Expected passed CI."
      Assert-True ($result.decision -eq "safe_no_auto_merge") "Expected safe no auto merge."
    }
    default { throw "Unknown PR finalizer scenario: $Scenario" }
  }
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
} finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}
