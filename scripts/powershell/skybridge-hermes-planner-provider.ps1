[CmdletBinding()]
param(
  [ValidateSet("status", "preview", "fixture-plan", "live-status", "live-plan", "validate-candidate", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/hermes-planner-provider",
  [string]$Objective = "",
  [string]$CandidatePath = "",
  [string]$ExpectedHash = "",
  [string]$HermesBaseUrl = "",
  [string]$TokenFile = "",
  [string]$Confirm = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.hermes_planner_provider.v1"
$EvidenceSchema = "skybridge.hermes_planner_evidence.v1"
$MetadataSchema = "skybridge.generated_goal_metadata.v1"
$FixtureGoalId = "hermes-fixture-goal-366c"
$LiveStatusConfirmation = "I_UNDERSTAND_CHECK_HERMES_PLANNER_PROVIDER_STATUS_ONLY"
$LivePlanConfirmation = "I_UNDERSTAND_CALL_HERMES_PLANNER_READ_ONLY_TO_GENERATE_UNAPPROVED_CANDIDATE"

function Add-Finding([ref]$List, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not ($List.Value -contains $Value)) {
    $List.Value = @($List.Value) + $Value
  }
}

function Resolve-RepoPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Convert-ToSafePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $value = $Path.Replace("\", "/")
  $repo = $RepoRoot.Replace("\", "/").TrimEnd("/")
  if ($value.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $value.Substring($repo.Length).TrimStart("/")
  }
  if ($value -match "^[A-Za-z]:/") { return "%PATH%/" + (Split-Path -Leaf $value) }
  $value
}

function Resolve-OutputRoot {
  $fullTarget = Resolve-RepoPath $OutputDir
  $agentRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/hermes-planner-provider"))
  if (-not $fullTarget.StartsWith($agentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/hermes-planner-provider."
  }
  $fullTarget
}

function Resolve-CandidatePath([ref]$Blockers) {
  if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
    return [IO.Path]::GetFullPath((Join-Path (Resolve-OutputRoot) "candidates/$FixtureGoalId.md"))
  }
  $fullPath = Resolve-RepoPath $CandidatePath
  $allowedRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/hermes-planner-provider"))
  if (-not $fullPath.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Add-Finding $Blockers "candidate_path_outside_allowed_root"
  }
  $fullPath
}

function Get-CurrentCommit {
  $value = (& git -C $RepoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
  if (-not [string]::IsNullOrWhiteSpace($value)) { return [string]$value }
  "unknown"
}

function Get-HermesBaseUrl {
  if (-not [string]::IsNullOrWhiteSpace($HermesBaseUrl)) { return $HermesBaseUrl }
  if (-not [string]::IsNullOrWhiteSpace($env:HERMES_BASE_URL)) { return [string]$env:HERMES_BASE_URL }
  if (-not [string]::IsNullOrWhiteSpace($env:HERMES_API_BASE)) { return [string]$env:HERMES_API_BASE }
  ""
}

function Test-AuthConfigured {
  if (-not [string]::IsNullOrWhiteSpace($TokenFile)) {
    $path = Resolve-RepoPath $TokenFile
    return (Test-Path -LiteralPath $path -PathType Leaf)
  }
  -not [string]::IsNullOrWhiteSpace($env:HERMES_API_KEY)
}

function Test-UnsafeText([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  $Value -match "(?i)(authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|token\s*[:=]|password\s*[:=]|cookie\s*[:=]|env\s+dump|environment dump|raw stdout|raw stderr|raw prompt|deploy|docker|git\s+push|gh\s+pr|auto[- ]?merge|worker loop|queue runner|task claim|task create|matlab|mcp|codex generation|project_control)"
}

function Get-Objective {
  if (-not [string]::IsNullOrWhiteSpace($Objective)) { return $Objective }
  "Draft an unapproved MG367A Vite chunk remediation candidate goal."
}

function Get-ShortObjective([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $clean = ($Value -replace "\s+", " ").Trim()
  if ($clean.Length -gt 180) { return $clean.Substring(0, 180) }
  $clean
}

function Get-Hash([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-SafetyFlags {
  [pscustomobject]@{
    candidate_approved = $false
    candidate_appended = $false
    task_created = $false
    task_claimed = $false
    execution_started = $false
    branch_created = $false
    pr_created = $false
    merge_performed = $false
    deploy_triggered = $false
    raw_prompt_persisted = $false
    raw_response_persisted = $false
    raw_stdout_persisted = $false
    raw_stderr_persisted = $false
    secrets_persisted = $false
    token_printed = $false
  }
}

function New-CandidateMarkdown([string]$ObjectiveText) {
  $metadata = [ordered]@{
    schema = $MetadataSchema
    goal_id = $FixtureGoalId
    title = "MG367A Vite Chunk Remediation Plan Candidate"
    order = 1
    risk = "low"
    task_type = "docs-analysis"
    allowed_task_types = @("docs-analysis", "local-smoke")
    blocked_task_types = @("task-execution", "worker-loop", "production-deploy", "release-mutation", "secret-rotation")
    requires = @("human review", "MG355 review/import gate before any campaign mutation")
    expected_outputs = @("one reviewed remediation plan", "sanitized validation evidence")
    advance_gate = [ordered]@{
      human_review_required = $true
      import_allowed = $false
      execution_allowed = $false
    }
    generated_by = "skybridge-hermes-planner-provider fixture"
    generation_provider = "hermes-fixture"
    source_campaign_id = "hermes-planner-provider-366c"
    source_project_id = "skybridge-agent-hub"
    goal_budget_remaining = 1
    human_review_required = $true
    import_allowed = $false
    execution_allowed = $false
    token_printed = $false
  }
  $json = $metadata | ConvertTo-Json -Depth 20
  @(
    "# MG367A Vite Chunk Remediation Plan Candidate",
    "",
    '```json',
    $json,
    '```',
    "",
    "## Objective",
    "",
    $ObjectiveText,
    "",
    "## Allowed Paths",
    "",
    "- docs/dev/",
    "- docs/release/",
    "- scripts/powershell/",
    "- package.json only for fixture smoke entries",
    "",
    "## Forbidden Paths",
    "",
    "- .github/workflows/",
    "- deployment infrastructure",
    "- Dockerfiles and Docker deployment files",
    "- OpenResty, Authelia, DNS, TLS, or firewall configuration",
    "- secrets, config, env, proxy, token, cookie, or credential files",
    "- generated release assets",
    "",
    "## Validation Plan",
    "",
    "- Run Vite chunk warning analysis smokes.",
    "- Run Bootstrap Alpha acceptance.",
    "- Run PowerShell validation and repository checks.",
    "",
    "## Safety Boundary",
    "",
    "- Human review is required before append or import.",
    "- This candidate is not approved.",
    "- This candidate is not appended.",
    "- This candidate must not execute in the same invocation.",
    "- No auto-merge.",
    "- No release, tag, or asset mutation.",
    "- No worker loop.",
    "- token_printed=false",
    "",
    "## Context",
    "",
    "This fixture candidate exists only for MG368C operator-console review and append validation.",
    "",
    "## Mission",
    "",
    "Review and append one candidate as non-executed campaign metadata.",
    "",
    "## Hard Safety Boundaries",
    "",
    "- Do not execute the appended step.",
    "- Do not create or claim tasks.",
    "- Do not start a worker loop or queue runner.",
    "- Do not call Hermes live planning or MCP.",
    "- Keep token_printed=false.",
    "",
    "## Allowed Scope",
    "",
    "- Validate this fixture candidate.",
    "- Record review state after exact human confirmation.",
    "- Append one pending campaign step after exact append confirmation.",
    "",
    "## Forbidden Scope",
    "",
    "- No task creation.",
    "- No task claim.",
    "- No step execution.",
    "- No worker loop.",
    "- No release, tag, asset, branch, PR, merge, deploy or production infrastructure mutation.",
    "",
    "## Implementation Requirements",
    "",
    "- Append exactly one reviewed metadata step and leave it pending for a future goal.",
    "- Preserve import_allowed=false until the append gate receives exact human confirmation.",
    "- Preserve execution_allowed=false.",
    "",
    "## Validation Requirements",
    "",
    "- Validate metadata, hash, allowed paths, forbidden paths and no-execution safety text.",
    "",
    "## CI/CD Requirements",
    "",
    "- Run fixture smokes only; do not deploy from this generated candidate.",
    "",
    "## Manual Milestone Script Requirement",
    "",
    "- Use the MG368C operator console gate for review, append preview and fixture-safe append.",
    "",
    "## Evidence Requirements",
    "",
    "- Report candidate hash, review status, appended step id and safety flags.",
    "",
    "## Final Report Requirements",
    "",
    "- Report changed files, chunk findings, validation status, safety flags, and token_printed=false.",
    "",
    "## No-Execution Statement",
    "",
    "This generated goal is appended for future review only and is not executed by MG368C."
  ) -join [Environment]::NewLine
}

function Write-FixtureCandidate([string]$Path, [string]$ObjectiveText) {
  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  New-CandidateMarkdown $ObjectiveText | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-CandidateMarkdown([string]$Path, [ref]$Warnings, [ref]$Blockers) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Add-Finding $Blockers "candidate_missing"
    return $false
  }
  $content = Get-Content -Raw -LiteralPath $Path
  if ($content -match '(?is)```json\s*(.*?)\s*```') {
    try {
      $metadata = $Matches[1] | ConvertFrom-Json
      if ([string]$metadata.schema -ne $MetadataSchema) { Add-Finding $Blockers "candidate_metadata_schema_invalid" }
      if ($metadata.human_review_required -ne $true) { Add-Finding $Blockers "candidate_human_review_not_required" }
      if ($metadata.import_allowed -ne $false) { Add-Finding $Blockers "candidate_import_allowed_not_false" }
      if ($metadata.execution_allowed -ne $false) { Add-Finding $Blockers "candidate_execution_allowed_not_false" }
      if ($metadata.token_printed -ne $false) { Add-Finding $Blockers "candidate_token_printed_not_false" }
    } catch {
      Add-Finding $Blockers "candidate_metadata_json_invalid"
    }
  } else {
    Add-Finding $Blockers "candidate_metadata_missing"
  }
  foreach ($required in @("## Objective", "## Allowed Paths", "## Forbidden Paths", "## Validation Plan", "## Safety Boundary", "Human review is required", "No auto-merge", "No release, tag, or asset mutation", "No worker loop", "token_printed=false")) {
    if ($content -notmatch [regex]::Escape($required)) {
      Add-Finding $Blockers ("candidate_missing_" + ($required -replace "[^A-Za-z0-9]+", "_").Trim("_").ToLowerInvariant())
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedHash)) {
    $actual = Get-Hash $Path
    if ($actual -ne $ExpectedHash.ToLowerInvariant()) { Add-Finding $Blockers "candidate_hash_mismatch" }
  }
  if ($content -match "(?i)(authorization\s*[:=]\s*bearer|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|password\s*[:=]|cookie\s*[:=]|environment dump|raw stdout|raw stderr)") {
    Add-Finding $Blockers "candidate_contains_unsafe_text"
  }
  if (@($Blockers.Value).Count -eq 0) { return $true }
  Add-Finding $Warnings "candidate_requires_human_review"
  $false
}

function New-Evidence([string]$Mode, [string]$ObjectiveText, [string]$CandidateSafePath, [string]$CandidateHash, [bool]$FixtureUsed, [bool]$LiveAttempted) {
  [pscustomobject]@{
    schema = $EvidenceSchema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    objective_summary = Get-ShortObjective $ObjectiveText
    candidate_goal_hash = $CandidateHash
    candidate_goal_path_safe = $CandidateSafePath
    provider_mode = $Mode
    fixture_response_used = $FixtureUsed
    live_call_attempted = $LiveAttempted
    candidate_approved = $false
    candidate_appended = $false
    task_created = $false
    execution_started = $false
    raw_logs_persisted = $false
    token_printed = $false
  }
}

function Invoke-HermesLiveStatus([string]$BaseUrl, [ref]$Warnings, [ref]$Blockers) {
  if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    Add-Finding $Blockers "hermes_endpoint_not_configured"
    return $false
  }
  $uri = $BaseUrl.TrimEnd("/") + "/health"
  try {
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($TokenFile)) {
      $tokenPath = Resolve-RepoPath $TokenFile
      if (Test-Path -LiteralPath $tokenPath -PathType Leaf) {
        $token = (Get-Content -Raw -LiteralPath $tokenPath).Trim()
        if (-not [string]::IsNullOrWhiteSpace($token)) { $headers["Authorization"] = "Bearer $token" }
      }
    } elseif (-not [string]::IsNullOrWhiteSpace($env:HERMES_API_KEY)) {
      $headers["Authorization"] = "Bearer $($env:HERMES_API_KEY)"
    }
    $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers -TimeoutSec 10 -UseBasicParsing
    return ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 500)
  } catch {
    Add-Finding $Warnings "hermes_live_status_unavailable"
    return $false
  }
}

function New-Report {
  $warnings = @()
  $blockers = @()
  $warningsRef = [ref]$warnings
  $blockersRef = [ref]$blockers
  $objectiveText = Get-Objective
  $objectiveSafe = -not (Test-UnsafeText $objectiveText)
  if (-not $objectiveSafe) { Add-Finding $blockersRef "unsafe_objective" }

  $baseUrl = Get-HermesBaseUrl
  $endpointConfigured = -not [string]::IsNullOrWhiteSpace($baseUrl)
  $authConfigured = Test-AuthConfigured
  $candidatePathFull = Resolve-CandidatePath $blockersRef
  $candidateSafePath = Convert-ToSafePath $candidatePathFull

  $mode = switch ($Command) {
    "live-status" { "live_status" }
    "live-plan" { "live_plan" }
    "preview" { "preview" }
    default { "fixture" }
  }

  $requestPreviewGenerated = $Command -in @("preview", "fixture-plan", "live-plan")
  $fixtureUsed = $Command -eq "fixture-plan"
  $liveAttempted = $false
  $liveSucceeded = $false
  $candidateGenerated = $false
  $candidateValidated = $false
  $candidateHash = ""
  $providerAvailable = $false

  if ($Command -eq "status" -or $Command -eq "safe-summary" -or $Command -eq "report") {
    if (-not $endpointConfigured) { Add-Finding $warningsRef "hermes_endpoint_not_configured" }
  } elseif ($Command -eq "preview") {
    if (-not $endpointConfigured) { Add-Finding $warningsRef "hermes_endpoint_not_configured_preview_only" }
  } elseif ($Command -eq "fixture-plan") {
    if ($objectiveSafe) {
      Write-FixtureCandidate -Path $candidatePathFull -ObjectiveText $objectiveText
      $candidateGenerated = $true
      $candidateValidated = Test-CandidateMarkdown -Path $candidatePathFull -Warnings $warningsRef -Blockers $blockersRef
      $candidateHash = Get-Hash $candidatePathFull
      $providerAvailable = $true
    }
  } elseif ($Command -eq "validate-candidate") {
    $candidateValidated = Test-CandidateMarkdown -Path $candidatePathFull -Warnings $warningsRef -Blockers $blockersRef
    $candidateGenerated = Test-Path -LiteralPath $candidatePathFull -PathType Leaf
    $candidateHash = Get-Hash $candidatePathFull
  } elseif ($Command -eq "live-status") {
    if ($Confirm -ne $LiveStatusConfirmation) {
      Add-Finding $blockersRef "live_status_confirmation_required"
    } else {
      $liveAttempted = $true
      $providerAvailable = Invoke-HermesLiveStatus -BaseUrl $baseUrl -Warnings $warningsRef -Blockers $blockersRef
      $liveSucceeded = $providerAvailable
    }
  } elseif ($Command -eq "live-plan") {
    if ($Confirm -ne $LivePlanConfirmation) {
      Add-Finding $blockersRef "live_plan_confirmation_required"
    } else {
      Add-Finding $blockersRef "live_plan_call_deferred_until_hermes_contract_is_configured"
      Add-Finding $warningsRef "fixture_plan_remains_available"
    }
  }

  if ($Command -eq "validate-candidate" -and -not [string]::IsNullOrWhiteSpace($ExpectedHash)) {
    $candidateHash = Get-Hash $candidatePathFull
  }

  $safety = New-SafetyFlags
  $evidence = New-Evidence `
    -Mode $mode `
    -ObjectiveText $objectiveText `
    -CandidateSafePath $candidateSafePath `
    -CandidateHash $candidateHash `
    -FixtureUsed $fixtureUsed `
    -LiveAttempted $liveAttempted

  [pscustomobject]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    current_commit = Get-CurrentCommit
    mode = $mode
    provider_name = "hermes"
    provider_role = "planner"
    provider_available = [bool]$providerAvailable
    provider_endpoint_configured = [bool]$endpointConfigured
    provider_auth_configured = [bool]$authConfigured
    objective_safe = [bool]$objectiveSafe
    request_preview_generated = [bool]$requestPreviewGenerated
    live_call_attempted = [bool]$liveAttempted
    live_call_succeeded = [bool]$liveSucceeded
    fixture_response_used = [bool]$fixtureUsed
    candidate_goal_generated = [bool]$candidateGenerated
    candidate_goal_path_safe = $candidateSafePath
    candidate_goal_hash = $candidateHash
    candidate_validated = [bool]$candidateValidated
    candidate_approved = $safety.candidate_approved
    candidate_appended = $safety.candidate_appended
    task_created = $safety.task_created
    task_claimed = $safety.task_claimed
    execution_started = $safety.execution_started
    branch_created = $safety.branch_created
    pr_created = $safety.pr_created
    merge_performed = $safety.merge_performed
    deploy_triggered = $safety.deploy_triggered
    raw_prompt_persisted = $safety.raw_prompt_persisted
    raw_response_persisted = $safety.raw_response_persisted
    raw_stdout_persisted = $safety.raw_stdout_persisted
    raw_stderr_persisted = $safety.raw_stderr_persisted
    secrets_persisted = $safety.secrets_persisted
    evidence = $evidence
    blockers = @($blockers)
    warnings = @($warnings)
    token_printed = $false
  }
}

function Write-Reports($Report) {
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "hermes-planner-provider.json"
  $mdPath = Join-Path $root "hermes-planner-provider.md"
  $Report | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Report | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Report | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  @(
    "# Hermes Planner Provider Report",
    "",
    "- schema: $($Report.schema)",
    "- mode: $($Report.mode)",
    "- provider_name: hermes",
    "- provider_role: planner",
    "- provider_available: $($Report.provider_available)",
    "- request_preview_generated: $($Report.request_preview_generated)",
    "- live_call_attempted: $($Report.live_call_attempted)",
    "- live_call_succeeded: $($Report.live_call_succeeded)",
    "- fixture_response_used: $($Report.fixture_response_used)",
    "- candidate_goal_generated: $($Report.candidate_goal_generated)",
    "- candidate_goal_path_safe: $($Report.candidate_goal_path_safe)",
    "- candidate_goal_hash: $($Report.candidate_goal_hash)",
    "- candidate_validated: $($Report.candidate_validated)",
    "- candidate_approved=false",
    "- candidate_appended=false",
    "- task_created=false",
    "- task_claimed=false",
    "- execution_started=false",
    "- branch_created=false",
    "- pr_created=false",
    "- merge_performed=false",
    "- deploy_triggered=false",
    "- raw_prompt_persisted=false",
    "- raw_response_persisted=false",
    "- secrets_persisted=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath $mdPath -Encoding UTF8
}

$report = New-Report
if ($Command -eq "safe-summary") {
  $report = [pscustomobject]@{
    schema = $Schema
    provider_name = "hermes"
    provider_role = "planner"
    provider_available = $report.provider_available
    provider_endpoint_configured = $report.provider_endpoint_configured
    candidate_goal_generated = $report.candidate_goal_generated
    candidate_validated = $report.candidate_validated
    candidate_approved = $false
    candidate_appended = $false
    task_created = $false
    execution_started = $false
    token_printed = $false
  }
}

if ($WriteReport -or $Command -eq "report") {
  Write-Reports $report
}

if ($Json) {
  $report | ConvertTo-Json -Depth 80
} elseif ($Command -eq "safe-summary") {
  Write-Host "Hermes planner provider: available=$($report.provider_available) candidate_validated=$($report.candidate_validated) token_printed=false"
} else {
  Write-Host "Hermes planner provider"
  Write-Host "- mode: $($report.mode)"
  Write-Host "- provider_role: planner"
  Write-Host "- live_call_attempted: $($report.live_call_attempted)"
  Write-Host "- candidate_goal_generated: $($report.candidate_goal_generated)"
  Write-Host "- candidate_validated: $($report.candidate_validated)"
  Write-Host "- candidate_approved=false"
  Write-Host "- candidate_appended=false"
  Write-Host "- task_created=false"
  Write-Host "- execution_started=false"
  Write-Host "- token_printed=false"
}
