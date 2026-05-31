[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("pack-validate", "import-dry-run", "step-order", "dependency-check", "status-output", "advance-preview", "requires-apply", "json-clean", "advance-gate-clean", "advance-gate-active-task-block", "advance-gate-stale-lease-block", "advance-gate-missing-dependency", "advance-gate-human-approval", "hermes-gate-schema", "campaign-gate-final-decision-advance", "campaign-gate-final-decision-hard-veto", "campaign-gate-human-approval-required", "campaign-gate-warnings-do-not-block", "hermes-gate-parse", "hermes-gate-invalid-json", "hermes-gate-hard-veto", "hermes-gate-human-approval", "hermes-gate-warning-only", "advance-with-gate-dry-run", "advance-with-gate-requires-apply", "gate-json-clean", "gate-no-secrets")]
  [string]$Scenario,
  [int]$Port = 0,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$ProjectId = "skybridge-agent-hub"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) { return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}" }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 30)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 50; $attempt++) {
    try { Invoke-SkyBridgeJson "GET" "/v1/health" | Out-Null; return } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

function Invoke-CampaignJson {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 -ApiBase $ApiBase -ProjectId $ProjectId -Json @Arguments
  if ($LASTEXITCODE -ne 0) { throw "skybridge-campaign.ps1 failed for $Scenario." }
  return ($output | ConvertFrom-Json)
}

function Invoke-StatusJson {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase $ApiBase -ProjectId $ProjectId -Json @Arguments
  if ($LASTEXITCODE -ne 0) { throw "skybridge-status.ps1 failed for $Scenario." }
  return ($output | ConvertFrom-Json)
}

function Import-SmokeCampaign {
  Invoke-CampaignJson -Arguments @("import", "-GoalPackDir", "goals/bootstrap-mvp", "-Apply")
}

function New-GateFixtureFile {
  param(
    [string]$CampaignId,
    [string]$CurrentStepId,
    [string]$CurrentGoalId,
    [string]$NextStepId,
    [string]$NextGoalId,
    [string]$Decision = "advance",
    [string[]]$Warnings = @("worker_offline")
  )
  $path = Join-Path $tempDir ("gate-" + [Guid]::NewGuid().ToString("n") + ".json")
  $gate = [pscustomobject]@{
    schema = "skybridge.campaign_gate.v1"
    decision = $Decision
    confidence = if ($Decision -eq "advance") { 0.86 } else { 0.62 }
    campaign_id = $CampaignId
    current_step_id = $CurrentStepId
    current_goal_id = $CurrentGoalId
    next_step_id = $NextStepId
    next_goal_id = $NextGoalId
    reasons = @("Fixture Hermes gate reviewed campaign state.")
    blockers = @()
    warnings = @($Warnings)
    required_human_actions = @()
    evidence_reviewed = [pscustomobject]@{
      active_tasks = 0
      stale_leases = 0
      failed_unrecovered = 0
      blocked_tasks = 0
      approved_unconverted_proposals = 0
      current_step_status = "ready"
      linked_prs = @()
      linked_tasks = @()
      validation_summary = @{ ok = $true }
      hygiene_summary = @{ active_tasks = 0; stale_leases = 0 }
    }
    safety_assessment = [pscustomobject]@{
      safe_to_advance = ($Decision -eq "advance")
      safe_to_execute_next_step = $false
      requires_human_approval = $true
      deterministic_veto_expected = $false
    }
    recommended_next_action = if ($Decision -eq "advance") { "advance_campaign_metadata_only" } else { "hold_campaign" }
    raw_notes = "Fixture output; no worker execution."
  }
  $gate | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-campaign-fixture-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$dbFile = Join-Path $tempDir "skybridge-campaign.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  if ($Scenario -in @("pack-validate", "import-dry-run", "dependency-check", "requires-apply", "json-clean")) {
    switch ($Scenario) {
      "pack-validate" {
        $result = Invoke-CampaignJson -Arguments @("validate-pack", "-GoalPackDir", "goals/bootstrap-mvp")
        if (-not $result.ok -or -not $result.validation.ok) { throw "Expected valid seed goal pack." }
      }
      "import-dry-run" {
        $result = Invoke-CampaignJson -Arguments @("import", "-GoalPackDir", "goals/bootstrap-mvp", "-DryRun")
        if ($result.mode -ne "dry-run" -or -not $result.would_import) { throw "Expected import dry-run result." }
      }
      "dependency-check" {
        $badDir = Join-Path $tempDir "bad-pack"
        New-Item -ItemType Directory -Path $badDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path "goals/bootstrap-mvp" "campaign.skybridge.json") -Destination (Join-Path $badDir "campaign.skybridge.json")
        Copy-Item -LiteralPath (Join-Path "goals/bootstrap-mvp" "super-186-hermes-gate-evaluator-auto-advance.md") -Destination (Join-Path $badDir "super-186-hermes-gate-evaluator-auto-advance.md")
        Copy-Item -LiteralPath (Join-Path "goals/bootstrap-mvp" "super-187-bootstrap-campaign-mvp-hardening.md") -Destination (Join-Path $badDir "super-187-bootstrap-campaign-mvp-hardening.md")
        Copy-Item -LiteralPath (Join-Path "goals/bootstrap-mvp" "super-184b-operator-console-dashboard.md") -Destination (Join-Path $badDir "super-184b-operator-console-dashboard.md")
        $badStep = Join-Path $badDir "super-187-bootstrap-campaign-mvp-hardening.md"
        (Get-Content -Raw -LiteralPath $badStep) -replace '"super-186-hermes-gate-evaluator-auto-advance"', '"missing-goal-dependency"' | Set-Content -LiteralPath $badStep -Encoding UTF8
        $failed = $false
        try {
          $badResult = Invoke-CampaignJson -Arguments @("validate-pack", "-GoalPackDir", $badDir)
          if (-not $badResult.ok -or -not $badResult.validation.ok) { $failed = $true }
        } catch { $failed = $true }
        if (-not $failed) { throw "Expected dependency validation to fail." }
        $result = [pscustomobject]@{ ok = $true; scenario = $Scenario }
      }
      "requires-apply" {
        $result = Invoke-CampaignJson -Arguments @("import", "-GoalPackDir", "goals/bootstrap-mvp")
        if ($result.mode -ne "dry-run") { throw "Expected import without -Apply to dry-run." }
      }
      "json-clean" {
        $text = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 validate-pack -GoalPackDir goals/bootstrap-mvp -Json) -join "`n"
        if ($text -match "`e\[[0-9;]*m") { throw "Campaign JSON output contains ANSI codes." }
        $result = ($text | ConvertFrom-Json)
      }
    }
    if ($Json) { $result | ConvertTo-Json -Depth 60 -Compress } else { $result | Format-List }
    exit 0
  }

  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = $ProjectId; name = "Campaign Smoke Project" } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/$ProjectId/control" @{ state = "paused"; stop_requested = $false } | Out-Null

  $import = Import-SmokeCampaign
  $campaignId = $import.campaign.campaign_id
  $stepsForGate = @($import.steps | Sort-Object order)
  $currentForGate = @($stepsForGate | Select-Object -First 1)[0]
  $nextForGate = @($stepsForGate | Select-Object -Skip 1 -First 1)[0]

  switch ($Scenario) {
    "step-order" {
      $steps = Invoke-CampaignJson -Arguments @("steps", "-CampaignId", $campaignId)
      $orders = @($steps.steps | Sort-Object order | ForEach-Object { [int]$_.order })
      if (($orders -join ",") -ne "1,2,3") { throw "Expected step order 1,2,3, got $($orders -join ',')." }
      $result = $steps
    }
    "status-output" {
      $status = Invoke-StatusJson -Arguments @("-ShowCampaigns", "-CampaignId", $campaignId)
      if (-not $status.campaign_summary -or @($status.campaigns).Count -ne 1) { throw "Expected campaign status output." }
      $result = $status
    }
    "advance-preview" {
      $preview = Invoke-CampaignJson -Arguments @("advance-preview", "-CampaignId", $campaignId, "-HumanApproved")
      if ($preview.gate.decision -ne "advance") { throw "Expected advance decision, got $($preview.gate.decision)." }
      $result = $preview
    }
    "advance-gate-clean" {
      $preview = Invoke-CampaignJson -Arguments @("advance-preview", "-CampaignId", $campaignId, "-HumanApproved")
      if ($preview.gate.decision -ne "advance" -or @($preview.gate.blockers).Count -ne 0) { throw "Expected clean advance gate." }
      $result = $preview
    }
    "advance-gate-human-approval" {
      $preview = Invoke-CampaignJson -Arguments @("advance-preview", "-CampaignId", $campaignId)
      if ($preview.gate.decision -ne "ask_human") { throw "Expected ask_human decision, got $($preview.gate.decision)." }
      $result = $preview
    }
    "advance-gate-active-task-block" {
      Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "campaign-smoke-active"; project_id = $ProjectId; title = "Active task"; risk = "low"; source = "manual" } | Out-Null
      $preview = Invoke-CampaignJson -Arguments @("advance-preview", "-CampaignId", $campaignId, "-HumanApproved")
      if ($preview.gate.decision -ne "hold" -or @($preview.gate.blockers) -notcontains "active_tasks_present") { throw "Expected active task blocker." }
      $result = $preview
    }
    "advance-gate-stale-lease-block" {
      Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "campaign-smoke-worker"; name = "Campaign Smoke Worker" } | Out-Null
      Invoke-SkyBridgeJson "POST" "/v1/workers/campaign-smoke-worker/heartbeat" @{ status_note = "ready" } | Out-Null
      Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "campaign-smoke-stale"; project_id = $ProjectId; title = "Stale lease"; risk = "low"; source = "manual" } | Out-Null
      Invoke-SkyBridgeJson "POST" "/v1/tasks/campaign-smoke-stale/claim" @{ worker_id = "campaign-smoke-worker" } | Out-Null
      $mutateScript = Join-Path $tempDir "mutate-campaign-stale.mjs"
      Set-Content -LiteralPath $mutateScript -Encoding UTF8 -Value @"
import { DatabaseSync } from 'node:sqlite';
const db = new DatabaseSync(process.argv[2]);
const old = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
const row = db.prepare('SELECT task_json FROM tasks WHERE task_id = ?').get('campaign-smoke-stale');
const task = JSON.parse(row.task_json);
task.lease.lease_expires_at = old;
task.lease.heartbeat_at = old;
db.prepare('UPDATE tasks SET task_json = ?, updated_at = ? WHERE task_id = ?').run(JSON.stringify(task), old, 'campaign-smoke-stale');
"@
      node $mutateScript $dbFile
      $preview = Invoke-CampaignJson -Arguments @("advance-preview", "-CampaignId", $campaignId, "-HumanApproved")
      if ($preview.gate.decision -ne "hold" -or @($preview.gate.blockers) -notcontains "active_tasks_present" -or @($preview.gate.blockers) -notcontains "stale_leases_present") { throw "Expected stale lease blockers." }
      $result = $preview
    }
    "advance-gate-missing-dependency" {
      $mutateScript = Join-Path $tempDir "mutate-campaign-dependency.mjs"
      Set-Content -LiteralPath $mutateScript -Encoding UTF8 -Value @"
import { DatabaseSync } from 'node:sqlite';
const db = new DatabaseSync(process.argv[2]);
const row = db.prepare('SELECT step_json FROM campaign_steps WHERE goal_id = ?').get('super-186-hermes-gate-evaluator-auto-advance');
const step = JSON.parse(row.step_json);
step.dependencies = ['missing-step'];
db.prepare('UPDATE campaign_steps SET step_json = ? WHERE campaign_step_id = ?').run(JSON.stringify(step), step.campaign_step_id);
"@
      node $mutateScript $dbFile
      $preview = Invoke-CampaignJson -Arguments @("advance-preview", "-CampaignId", $campaignId, "-HumanApproved")
      if ($preview.gate.decision -ne "hold" -or -not (@($preview.gate.blockers) -match "dependency_not_complete:missing-step")) { throw "Expected missing dependency blocker." }
      $result = $preview
    }
    "hermes-gate-schema" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $preview = Invoke-CampaignJson -Arguments @("hermes-gate-preview", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.hermes_gate.schema -ne "skybridge.campaign_gate.v1") { throw "Expected campaign gate schema." }
      $result = $preview
    }
    "hermes-gate-parse" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $preview = Invoke-CampaignJson -Arguments @("hermes-gate-preview", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.gate.hermes_decision -ne "advance") { throw "Expected parsed Hermes advance decision." }
      $result = $preview
    }
    "hermes-gate-invalid-json" {
      $badFixture = Join-Path $tempDir "bad-gate.json"
      Set-Content -LiteralPath $badFixture -Encoding UTF8 -Value '```json{"schema":"skybridge.campaign_gate.v1"}```'
      $failed = $false
      try { Invoke-CampaignJson -Arguments @("hermes-gate-preview", "-CampaignId", $campaignId, "-HermesGateFixtureFile", $badFixture) | Out-Null } catch { $failed = $true }
      if (-not $failed) { throw "Expected invalid Hermes JSON to be rejected." }
      $result = [pscustomobject]@{ ok = $true; scenario = $Scenario }
    }
    "campaign-gate-final-decision-advance" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $preview = Invoke-CampaignJson -Arguments @("advance-with-gate", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.gate.final_decision -ne "advance" -or -not $preview.would_advance) { throw "Expected final advance decision." }
      $result = $preview
    }
    "campaign-gate-final-decision-hard-veto" {
      Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "campaign-smoke-active"; project_id = $ProjectId; title = "Active task"; risk = "low"; source = "manual" } | Out-Null
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $preview = Invoke-CampaignJson -Arguments @("advance-with-gate", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.gate.final_decision -ne "hold" -or @($preview.gate.hard_blockers) -notcontains "active_tasks_present") { throw "Expected deterministic hard veto." }
      $result = $preview
    }
    "campaign-gate-human-approval-required" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $preview = Invoke-CampaignJson -Arguments @("advance-with-gate", "-CampaignId", $campaignId, "-HermesGateFixtureFile", $fixture)
      if ($preview.gate.final_decision -ne "ask_human" -or -not $preview.gate.human_approval_required) { throw "Expected human approval requirement." }
      $result = $preview
    }
    "campaign-gate-warnings-do-not-block" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id -Warnings @("worker_offline", "blocked_tasks_present")
      $preview = Invoke-CampaignJson -Arguments @("advance-with-gate", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.gate.final_decision -ne "advance" -or @($preview.gate.warnings).Count -eq 0) { throw "Expected warnings to remain non-blocking." }
      $result = $preview
    }
    "hermes-gate-hard-veto" {
      Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "campaign-smoke-active"; project_id = $ProjectId; title = "Active task"; risk = "low"; source = "manual" } | Out-Null
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $preview = Invoke-CampaignJson -Arguments @("hermes-gate-preview", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.gate.final_decision -ne "hold") { throw "Expected hard veto to hold Hermes advance." }
      $result = $preview
    }
    "hermes-gate-human-approval" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $preview = Invoke-CampaignJson -Arguments @("hermes-gate-preview", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.gate.final_decision -ne "advance" -or -not $preview.gate.human_approval_present) { throw "Expected human-approved Hermes gate advance." }
      $result = $preview
    }
    "hermes-gate-warning-only" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id -Warnings @("worker_offline")
      $preview = Invoke-CampaignJson -Arguments @("hermes-gate-preview", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.gate.final_decision -ne "advance" -or @($preview.gate.warnings).Count -eq 0) { throw "Expected warning-only gate to advance." }
      $result = $preview
    }
    "advance-with-gate-dry-run" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $preview = Invoke-CampaignJson -Arguments @("advance-with-gate", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.mode -ne "dry-run" -or -not $preview.would_advance) { throw "Expected advance-with-gate dry-run." }
      $after = Invoke-CampaignJson -Arguments @("show", "-CampaignId", $campaignId)
      if ($after.campaign.current_step_id -ne $currentForGate.campaign_step_id) { throw "Dry-run changed campaign current step." }
      $result = $preview
    }
    "advance-with-gate-requires-apply" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $preview = Invoke-CampaignJson -Arguments @("advance-with-gate", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture)
      if ($preview.mode -ne "dry-run") { throw "Expected -Apply to be required for advance-with-gate." }
      $result = $preview
    }
    "gate-json-clean" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $text = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 -ApiBase $ApiBase -ProjectId $ProjectId -Json advance-with-gate -CampaignId $campaignId -HumanApproved -HumanApprovalReason "smoke approval" -HermesGateFixtureFile $fixture) -join "`n"
      if ($LASTEXITCODE -ne 0) { throw "advance-with-gate JSON command failed." }
      if ($text -match "`e\[[0-9;]*m") { throw "Gate JSON output contains ANSI codes." }
      $result = ($text | ConvertFrom-Json)
    }
    "gate-no-secrets" {
      $fixture = New-GateFixtureFile -CampaignId $campaignId -CurrentStepId $currentForGate.campaign_step_id -CurrentGoalId $currentForGate.goal_id -NextStepId $nextForGate.campaign_step_id -NextGoalId $nextForGate.goal_id
      $inputFile = Join-Path $tempDir "gate-input.json"
      $outputFile = Join-Path $tempDir "gate-output.json"
      $preview = Invoke-CampaignJson -Arguments @("hermes-gate-preview", "-CampaignId", $campaignId, "-HumanApproved", "-HumanApprovalReason", "smoke approval", "-HermesGateFixtureFile", $fixture, "-SaveGateInput", $inputFile, "-SaveGateOutput", $outputFile)
      $saved = (Get-Content -Raw -LiteralPath $inputFile) + "`n" + (Get-Content -Raw -LiteralPath $outputFile)
      if ($saved -match "(?i)(HERMES_API_KEY|SKYBRIDGE_WORKER_TOKEN|sk-[A-Za-z0-9_-]{20,}|-----BEGIN .*PRIVATE KEY-----)") { throw "Saved gate artifacts contain secret-looking text." }
      $result = $preview
    }
  }

  if ($Json) { $result | ConvertTo-Json -Depth 80 -Compress } else { $result | Format-List }
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  if (Test-Path -LiteralPath $tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
