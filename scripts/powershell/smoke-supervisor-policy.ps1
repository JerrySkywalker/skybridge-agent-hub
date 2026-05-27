$ErrorActionPreference = "Stop"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-supervisor-policy-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
  $base = @{
    control = @{ state = "paused"; stop_requested = $false }
    workers = @(@{ worker_id = "policy-worker"; status = "online" })
    proposals = @(
      @{ proposal_id = "policy-docs"; dedupe_key = "policy-docs"; risk = "low"; task_type = "docs"; status = "proposed"; required_capabilities = @("codex") },
      @{ proposal_id = "policy-smoke"; dedupe_key = "policy-smoke"; risk = "medium"; task_type = "test"; status = "proposed"; required_capabilities = @("codex") }
    )
  }
  $baseFile = Join-Path $tempDir "base.json"
  $base | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $baseFile -Encoding UTF8
  $baseResult = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-supervisor-policy.ps1 -FixtureFile $baseFile -Json | ConvertFrom-Json

  $highOnly = @{
    control = @{ state = "paused"; stop_requested = $false }
    workers = @(@{ worker_id = "policy-worker"; status = "online" })
    proposals = @(@{ proposal_id = "policy-high"; dedupe_key = "policy-high"; risk = "high"; task_type = "docs"; status = "proposed"; required_capabilities = @("codex") })
  }
  $highFile = Join-Path $tempDir "high.json"
  $highOnly | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $highFile -Encoding UTF8
  $highResult = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-supervisor-policy.ps1 -FixtureFile $highFile -Json | ConvertFrom-Json

  $recovered = @{
    control = @{ state = "paused"; stop_requested = $false }
    workers = @(@{ worker_id = "policy-worker"; status = "online" })
    proposals = @(@{ proposal_id = "policy-next"; dedupe_key = "policy-next"; risk = "low"; task_type = "docs"; status = "proposed"; required_capabilities = @("codex") })
    latest_task = @{ status = "failed"; evidence_summary = @{ recovered = $true; ci_status = "passed_after_rerun" } }
  }
  $recoveredFile = Join-Path $tempDir "recovered.json"
  $recovered | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $recoveredFile -Encoding UTF8
  $recoveredResult = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-supervisor-policy.ps1 -FixtureFile $recoveredFile -Json | ConvertFrom-Json

  if ($baseResult.selected_proposal_id -ne "policy-docs" -or $baseResult.decision.decision -ne "continue") { throw "Expected low-risk docs proposal selection." }
  if ($highResult.decision.decision -ne "ask_human" -or $highResult.decision.stop_reason -ne "high_risk_requires_review") { throw "Expected high-risk proposal to require human review." }
  if ($recoveredResult.latest_task_display_status -ne "recovered" -or $recoveredResult.decision.decision -ne "continue") { throw "Expected recovered task evidence to continue." }
  if ($baseResult.token_printed -ne $false -or $highResult.token_printed -ne $false -or $recoveredResult.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    SelectLowRisk = "passed"
    HighRiskBlocked = "passed"
    RecoveredEvidence = "passed"
    TokenPrinted = $false
  } | Format-List
} finally {
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
