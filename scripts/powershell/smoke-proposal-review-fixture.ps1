[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("list", "approve", "reject", "defer", "convert-approved-only", "approval-policy-docs", "approval-policy-local-smoke", "approval-policy-high-risk", "approval-dependency-block")]
  [string]$Scenario,
  [int]$Port = 0,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) { return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}" }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 24)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { Invoke-SkyBridgeJson "GET" "/v1/health" | Out-Null; return } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

function Invoke-ProposalJson {
  param([string[]]$Arguments, [switch]$ExpectFailure)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 -ApiBase $ApiBase -ProjectId "proposal-review-project" -Json @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if ($ExpectFailure) {
    if ($exitCode -eq 0) { throw "Expected skybridge-proposal.ps1 to fail for $Scenario." }
    return [pscustomobject]@{ failed = $true; output = ($output -join "`n") }
  }
  if ($exitCode -ne 0) { throw "skybridge-proposal.ps1 failed for $Scenario`: $($output -join "`n")" }
  return ($output | ConvertFrom-Json)
}

function Add-ProposalSession {
  Invoke-SkyBridgeJson "POST" "/v1/master-goals" @{
    master_goal_id = "proposal-review-master"
    project_id = "proposal-review-project"
    title = "Proposal Review Master"
    source = "fixture"
    priority = "normal"
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/planning-sessions" @{
    planning_session_id = "proposal-review-session"
    master_goal_id = "proposal-review-master"
    project_id = "proposal-review-project"
    planner_adapter = @{
      provider = "fixture"
      planner_mode = "fixture"
      prompt_version = "v1"
      input_state_hash = "fixture"
      raw_response_included = $false
      secrets_included = $false
    }
    proposals = @(
      @{
        proposal_id = "prop_docs_safe"
        title = "Docs safe proposal"
        body = "Update docs only."
        dedupe_key = "prop-docs-safe"
        risk = "low"
        task_type = "docs"
        status = "proposed"
        review_status = "proposed"
        policy_decision = "accepted_for_preview"
        expected_files = @("docs/dev/PROPOSAL_REVIEW_QUEUE.md")
        acceptance_criteria = @("docs updated")
        evidence_requirements = @("status smoke")
        required_capabilities = @("docs")
        original_required_capabilities = @("docs")
        normalized_required_capabilities = @("codex", "git", "gh")
        rationale = "Fixture docs proposal."
      },
      @{
        proposal_id = "prop_smoke_safe"
        title = "Safe local smoke proposal"
        body = "Add a safe local smoke script."
        dedupe_key = "prop-smoke-safe"
        risk = "low"
        task_type = "local-smoke"
        status = "proposed"
        review_status = "proposed"
        policy_decision = "accepted_for_preview"
        expected_files = @("scripts/powershell/smoke-proposal-review-fixture-output.ps1")
        acceptance_criteria = @("smoke added")
        evidence_requirements = @("validate powershell")
        required_capabilities = @("codex", "powershell", "windows")
        normalized_required_capabilities = @("codex", "powershell", "windows")
        rationale = "Fixture local-smoke proposal."
      },
      @{
        proposal_id = "prop_high_risk"
        title = "Production deploy proposal"
        body = "Production deploy and secret changes."
        dedupe_key = "prop-high-risk"
        risk = "high"
        task_type = "deploy"
        status = "proposed"
        review_status = "proposed"
        policy_decision = "rejected_high_risk"
        expected_files = @("deploy/unsafe.md")
        acceptance_criteria = @("blocked")
        evidence_requirements = @("blocked")
        required_capabilities = @("codex")
        rationale = "Fixture unsafe proposal."
      },
      @{
        proposal_id = "prop_dependency_blocked"
        title = "Dependency blocked docs proposal"
        body = "Depends on another proposal."
        dedupe_key = "prop-dependency-blocked"
        risk = "low"
        task_type = "docs"
        status = "proposed"
        review_status = "proposed"
        policy_decision = "dependency_blocked"
        expected_files = @("docs/dev/PROGRESS.md")
        acceptance_criteria = @("docs updated")
        evidence_requirements = @("status smoke")
        required_capabilities = @("codex", "git", "gh")
        normalized_required_capabilities = @("codex", "git", "gh")
        dependencies = @("prop_docs_safe")
        depends_on = @("prop_docs_safe")
        rationale = "Fixture dependency blocked proposal."
      }
    )
  } | Out-Null
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-proposal-review-fixture-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$dbFile = Join-Path $tempDir "skybridge-proposal.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 28001 -Maximum 38000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "proposal-review-project"; name = "Proposal Review Project" } | Out-Null
  Add-ProposalSession

  switch ($Scenario) {
    "list" {
      $result = Invoke-ProposalJson -Arguments @("-Command", "list", "-ShowAll")
      if (@($result.proposals).Count -lt 4) { throw "Expected proposal list." }
    }
    "approve" {
      $result = Invoke-ProposalJson -Arguments @("-Command", "approve", "-ProposalId", "prop_docs_safe", "-Apply", "-Reason", "fixture approval")
      if ($result.proposal.status -ne "approved" -or $result.proposal.review_status -ne "approved") { throw "Expected approved proposal." }
    }
    "reject" {
      $result = Invoke-ProposalJson -Arguments @("-Command", "reject", "-ProposalId", "prop_high_risk", "-Apply", "-Reason", "unsafe fixture")
      if ($result.proposal.status -ne "rejected") { throw "Expected rejected proposal." }
    }
    "defer" {
      $result = Invoke-ProposalJson -Arguments @("-Command", "defer", "-ProposalId", "prop_smoke_safe", "-Apply", "-Reason", "operator review needed")
      if ($result.proposal.status -ne "deferred") { throw "Expected deferred proposal." }
    }
    "convert-approved-only" {
      Invoke-ProposalJson -Arguments @("-Command", "convert", "-ProposalId", "prop_docs_safe", "-Apply") -ExpectFailure | Out-Null
      Invoke-ProposalJson -Arguments @("-Command", "approve", "-ProposalId", "prop_docs_safe", "-Apply", "-Reason", "fixture approval") | Out-Null
      $result = Invoke-ProposalJson -Arguments @("-Command", "convert", "-ProposalId", "prop_docs_safe", "-Apply", "-TaskId", "task_prop_docs_safe")
      if ($result.task.task_id -ne "task_prop_docs_safe" -or $result.proposal.status -ne "converted") { throw "Expected approved proposal conversion." }
    }
    "approval-policy-docs" {
      $result = Invoke-ProposalJson -Arguments @("-Command", "approve", "-ProposalId", "prop_docs_safe", "-Apply", "-Reason", "docs ok")
      if ($result.validation.decision -notin @("accepted_for_execution", "accepted_for_preview", "ask_human")) { throw "Expected docs proposal approval policy to pass." }
    }
    "approval-policy-local-smoke" {
      $result = Invoke-ProposalJson -Arguments @("-Command", "approve", "-ProposalId", "prop_smoke_safe", "-Apply", "-Reason", "explicit safe local smoke")
      if ($result.proposal.status -ne "approved") { throw "Expected local-smoke explicit approval." }
    }
    "approval-policy-high-risk" {
      $failure = Invoke-ProposalJson -Arguments @("-Command", "approve", "-ProposalId", "prop_high_risk", "-Apply", "-Reason", "should fail") -ExpectFailure
      if ($failure.output -notmatch "rejected_high_risk") { throw "Expected high-risk approval rejection." }
    }
    "approval-dependency-block" {
      $failure = Invoke-ProposalJson -Arguments @("-Command", "approve", "-ProposalId", "prop_dependency_blocked", "-Apply", "-Reason", "should fail") -ExpectFailure
      if ($failure.output -notmatch "dependency_blocked") { throw "Expected dependency block." }
    }
  }

  $global:LASTEXITCODE = 0
  $summary = [pscustomobject]@{ ok = $true; scenario = $Scenario; api_base = $ApiBase; token_printed = $false }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
