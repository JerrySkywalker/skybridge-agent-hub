[CmdletBinding()]
param(
  [ValidateSet("status", "preview", "generate-one", "validate-generated", "classify", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/generated-goals",
  [string]$GeneratedGoalDir = "",
  [string]$GoalId = "",
  [string]$Title = "",
  [string]$Objective = "",
  [string]$CampaignId = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [int]$GoalBudgetRemaining = 1,
  [string]$Template = "generated-proposed-goal",
  [string[]]$AllowedTaskTypes = @("docs-validation", "local-smoke"),
  [string[]]$BlockedTaskTypes = @("task-execution", "worker-loop", "production-deploy", "secret-rotation", "release-mutation"),
  [string]$Provider = "direct",
  [switch]$Fixture,
  [switch]$UseCodex,
  [string]$Confirm = "",
  [switch]$NoCodex
)

$ErrorActionPreference = "Stop"

if ($NoCodex) {
  $UseCodex = $false
}
if ($UseCodex) {
  $Fixture = $false
} elseif (-not $Fixture) {
  $Fixture = $true
}

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.local_goal_generator.v1"
$EvidenceSchema = "skybridge.local_goal_generator_evidence.v1"
$MetadataSchema = "skybridge.generated_goal_metadata.v1"
$GenerateConfirmation = "I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION"
$FixtureGoalId = "generated-docs-validation-goal-354-fixture"
$FixtureCampaignId = "local-goal-generator-fixture-354"
$FixtureObjective = "Create a safe documentation validation goal for a future campaign."
$FixtureTitle = "Generated Docs Validation Goal 354 Fixture"

function Add-Finding([ref]$List, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not ($List.Value -contains $Value)) {
    $List.Value = @($List.Value) + $Value
  }
}

function ConvertTo-SafeJson($Value) {
  $Value | ConvertTo-Json -Depth 80
}

function Convert-ToSafePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $value = $Path.Replace("\", "/")
  $repo = $RepoRoot.Replace("\", "/").TrimEnd("/")
  if ($value.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $value.Substring($repo.Length).TrimStart("/")
  }
  if ($value -match "^[A-Za-z]:/") {
    return "%PATH%/" + (Split-Path -Leaf $value)
  }
  $value
}

function Resolve-OutputRoot {
  $targetRoot = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $RepoRoot $OutputDir }
  $fullTarget = [IO.Path]::GetFullPath($targetRoot)
  $agentGenerated = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/generated-goals"))
  if (-not $fullTarget.StartsWith($agentGenerated, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/generated-goals."
  }
  $fullTarget
}

function Resolve-GeneratedRoot([ref]$Blockers) {
  $outputRoot = Resolve-OutputRoot
  if ([string]::IsNullOrWhiteSpace($GeneratedGoalDir)) {
    $folder = if ($UseCodex) { "local-codex" } else { "fixture" }
    return [IO.Path]::GetFullPath((Join-Path $outputRoot $folder))
  }

  $candidate = if ([IO.Path]::IsPathRooted($GeneratedGoalDir)) { $GeneratedGoalDir } else { Join-Path $RepoRoot $GeneratedGoalDir }
  $fullCandidate = [IO.Path]::GetFullPath($candidate)
  $agentGenerated = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/generated-goals"))
  $goalsProposed = [IO.Path]::GetFullPath((Join-Path $RepoRoot "goals/proposed"))
  if ($fullCandidate.StartsWith($goalsProposed, [System.StringComparison]::OrdinalIgnoreCase)) {
    Add-Finding $Blockers "goals_proposed_write_deferred_to_mg355"
    return $fullCandidate
  }
  if (-not $fullCandidate.StartsWith($agentGenerated, [System.StringComparison]::OrdinalIgnoreCase)) {
    Add-Finding $Blockers "output_dir_outside_allowed_root"
  }
  $fullCandidate
}

function New-SafetyFlags {
  [pscustomobject]@{
    import_performed = $false
    approval_performed = $false
    append_performed = $false
    task_created = $false
    task_claimed = $false
    execution_started = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    raw_prompt_persisted = $false
    raw_response_persisted = $false
    raw_stdout_persisted = $false
    raw_stderr_persisted = $false
    token_printed = $false
  }
}

function Test-SafeGoalId([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  if ($Value -match "[\\/]" -or $Value.Contains("..")) { return $false }
  $Value -match "^[a-z0-9][a-z0-9._-]{2,160}$"
}

function Test-UnsafeOperatorText([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  $Value -match "(?i)(authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|token\s*[:=]|password\s*[:=]|cookie\s*[:=]|env\s+dump|environment dump|raw stdout|raw stderr|raw prompt|rm\s+-rf|docker\s+system\s+prune|production deploy|secret rotation|server root|github settings|branch protection|auto[- ]?approve|auto[- ]?import|auto[- ]?execute|worker loop|arbitrary shell|matlab command|hermes planner|mcp execution)"
}

function Get-GeneratorIds {
  $mode = if ($UseCodex) { "local_codex" } else { "fixture" }
  $goalIdValue = if (-not [string]::IsNullOrWhiteSpace($GoalId)) { $GoalId } elseif ($Fixture) { $FixtureGoalId } else { "generated-goal-354-local-codex" }
  $titleValue = if (-not [string]::IsNullOrWhiteSpace($Title)) { $Title } elseif ($Fixture) { $FixtureTitle } else { "Generated Local Codex Goal 354" }
  $campaignValue = if (-not [string]::IsNullOrWhiteSpace($CampaignId)) { $CampaignId } elseif ($Fixture) { $FixtureCampaignId } else { "local-codex-goal-generator-354-001" }
  $objectiveValue = if (-not [string]::IsNullOrWhiteSpace($Objective)) { $Objective } elseif ($Fixture) { $FixtureObjective } else { "Generate one safe follow-up goal for validating goal append review only." }
  [pscustomobject]@{
    mode = $mode
    goal_id = $goalIdValue
    title = $titleValue
    campaign_id = $campaignValue
    objective = $objectiveValue
  }
}

function Invoke-ProviderInventory {
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $PSScriptRoot "skybridge-tool-provider.ps1"),
    "-Command",
    "inventory",
    "-NoVersionProbe",
    "-Json"
  )
  if ($Fixture) { $args += "-Fixture" }
  $raw = & pwsh @args
  if ($LASTEXITCODE -ne 0) { throw "tool provider inventory failed." }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Test-DirectProviderAvailable($Inventory) {
  $direct = @($Inventory.providers | Where-Object { $_.provider_id -eq "direct-local" } | Select-Object -First 1)
  ($direct.Count -gt 0 -and [string]$direct[0].status -in @("available", "warning"))
}

function Test-CodexDetected($Inventory) {
  if ($Fixture -or $NoCodex) { return $false }
  $tool = @($Inventory.tools | Where-Object { $_.tool_id -eq "codex" } | Select-Object -First 1)
  ($tool.Count -gt 0 -and [string]$tool[0].status -eq "detected")
}

function Get-CodexCommand {
  foreach ($name in @("codex.cmd", "codex.exe", "codex")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd }
  }
  $null
}

function Quote-CmdArgument([string]$Value) {
  '"' + ($Value -replace '"', '\"') + '"'
}

function Get-CodexProcessInvocation($CodexCommand, [string[]]$CodexArguments) {
  if (-not $CodexCommand) { return $null }
  $source = [string]$CodexCommand.Source
  if ($source.EndsWith(".cmd", [System.StringComparison]::OrdinalIgnoreCase) -or $source.EndsWith(".bat", [System.StringComparison]::OrdinalIgnoreCase)) {
    $comspec = if ([string]::IsNullOrWhiteSpace($env:ComSpec)) { "cmd.exe" } else { $env:ComSpec }
    $quoted = @((Quote-CmdArgument $source)) + @($CodexArguments | ForEach-Object { Quote-CmdArgument ([string]$_) })
    return [pscustomobject]@{
      file_name = $comspec
      arguments_string = "/d /c call " + ($quoted -join " ")
      arguments = @()
    }
  }
  [pscustomobject]@{
    file_name = $source
    arguments_string = ""
    arguments = @($CodexArguments)
  }
}

function New-GeneratedGoalMetadata($Ids) {
  [ordered]@{
    schema = $MetadataSchema
    goal_id = $Ids.goal_id
    title = $Ids.title
    order = 1
    risk = "low"
    task_type = "docs-validation"
    allowed_task_types = @($AllowedTaskTypes)
    blocked_task_types = @($BlockedTaskTypes)
    requires = @("human review", "MG355 review/import gate before any campaign mutation")
    expected_outputs = @("one markdown goal proposal", "sanitized validation evidence")
    advance_gate = [ordered]@{
      human_review_required = $true
      import_allowed = $false
      execution_allowed = $false
      review_milestone = "MG355"
    }
    generated_by = "skybridge-local-goal-generator"
    generation_provider = if ($UseCodex) { "local_codex" } else { "fixture" }
    source_campaign_id = $Ids.campaign_id
    source_project_id = $ProjectId
    goal_budget_remaining = $GoalBudgetRemaining
    human_review_required = $true
    import_allowed = $false
    execution_allowed = $false
    token_printed = $false
  }
}

function New-GeneratedGoalMarkdown($Ids) {
  $metadataJson = (New-GeneratedGoalMetadata $Ids | ConvertTo-Json -Depth 20)
  $fence = '```'
  @(
    "$fence" + "json",
    $metadataJson,
    $fence,
    "",
    "# $($Ids.title)",
    "",
    "## Context",
    "This proposed goal was produced by MG354 for project $ProjectId and source campaign $($Ids.campaign_id).",
    "",
    "## Mission",
    $Ids.objective,
    "",
    "## Hard Safety Boundaries",
    "- Do not import this generated goal into a campaign.",
    "- Do not approve this generated goal.",
    "- Do not append this generated goal to any campaign.",
    "- Do not execute any generated instructions.",
    "- Do not create or claim tasks.",
    "- Do not start a worker loop or queue runner.",
    "- Do not call MATLAB, Hermes planner, MCP, or arbitrary shell execution.",
    "- Do not mutate releases, tags, assets, production infrastructure, secrets, GitHub settings, or project_control.",
    "- Keep token_printed=false.",
    "",
    "## Allowed Scope",
    "- Review this markdown proposal.",
    "- Validate metadata and required safety sections.",
    "- Record sanitized evidence under ignored .agent/tmp paths.",
    "",
    "## Forbidden Scope",
    "- No generated goal import.",
    "- No generated goal approval.",
    "- No generated goal append.",
    "- No generated goal execution.",
    "- No task creation or task claim.",
    "- No raw prompt, raw response, stdout, stderr, token, credential, cookie, provider auth header, proxy profile, or environment dump persistence.",
    "",
    "## Implementation Requirements",
    "- Keep this goal as a reviewed markdown candidate only.",
    "- Require a later human-reviewed MG355 import gate before campaign mutation.",
    "- Preserve provider inventory and execution-plane safety boundaries.",
    "",
    "## Validation Requirements",
    "- Validate the fenced JSON metadata block.",
    "- Confirm human_review_required=true.",
    "- Confirm import_allowed=false.",
    "- Confirm execution_allowed=false.",
    "- Confirm token_printed=false.",
    "",
    "## CI/CD Requirements",
    "- Run only read-only validation and fixture smokes.",
    "- Do not deploy, release, tag, upload assets, auto-merge, or mutate infrastructure from this generated proposal.",
    "",
    "## Manual Milestone Script Requirement",
    "- Add or run only a future manual review script that previews the proposal and stops before import.",
    "",
    "## Evidence Requirements",
    "- Report the generated goal path and SHA256 hash.",
    "- Report metadata validation and safety validation results.",
    "- Exclude raw prompts, raw responses, raw logs, stdout, stderr, tokens, credentials, cookies, provider auth headers, proxy profiles, and environment dumps.",
    "",
    "## Final Report Requirements",
    "- Include the generated goal id, path, hash, validation status, safety flags, blockers, warnings, and token_printed=false.",
    "",
    "## No-Execution Statement",
    "This generated markdown is a candidate for human review only. It is not approved, imported, appended, or executed."
  ) -join [Environment]::NewLine
}

function Get-MetadataFromMarkdown([string]$Markdown) {
  $match = [regex]::Match($Markdown, '(?s)```json\s*(\{.*?\})\s*```')
  if (-not $match.Success) { return $null }
  try {
    return ($match.Groups[1].Value | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Test-GeneratedMarkdown {
  param([string]$Markdown, [string]$ExpectedGoalId)
  $errors = @()
  $metadata = Get-MetadataFromMarkdown $Markdown
  if ($null -eq $metadata) {
    $errors += "metadata_missing_or_invalid"
  } else {
    if ([string]$metadata.schema -ne $MetadataSchema) { $errors += "metadata_schema_invalid" }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedGoalId) -and [string]$metadata.goal_id -ne $ExpectedGoalId) { $errors += "goal_id_mismatch" }
    if ($metadata.human_review_required -ne $true) { $errors += "human_review_required_not_true" }
    if ($metadata.import_allowed -ne $false) { $errors += "import_allowed_not_false" }
    if ($metadata.execution_allowed -ne $false) { $errors += "execution_allowed_not_false" }
    if ($metadata.token_printed -ne $false) { $errors += "token_printed_not_false" }
  }
  foreach ($section in @(
      "## Context",
      "## Mission",
      "## Hard Safety Boundaries",
      "## Allowed Scope",
      "## Forbidden Scope",
      "## Implementation Requirements",
      "## Validation Requirements",
      "## CI/CD Requirements",
      "## Manual Milestone Script Requirement",
      "## Evidence Requirements",
      "## Final Report Requirements",
      "## No-Execution Statement"
    )) {
    if ($Markdown -notmatch [regex]::Escape($section)) { $errors += "missing_section:$section" }
  }
  if ($Markdown -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|cookie\s*[:=]') {
    $errors += "unsafe_secret_like_text"
  }
  [pscustomobject]@{
    valid = ($errors.Count -eq 0)
    errors = @($errors)
    metadata = $metadata
  }
}

function Invoke-LocalCodexGeneration {
  param($Ids, [string]$GeneratedRoot, [string]$TargetPath)
  $codex = Get-CodexCommand
  if (-not $codex) {
    return [pscustomobject]@{ ok = $false; reason = "codex_not_found"; markdown = "" }
  }
  $prompt = @"
You are writing exactly one SkyBridge generated goal markdown candidate.

Return markdown only. Do not include commentary outside the markdown.
Use the fenced JSON metadata block and section names requested below.
Do not include secrets, raw prompts, raw logs, stdout, stderr, tokens, credentials, cookies, auth headers, proxy profiles, environment dumps, arbitrary shell commands, production infrastructure mutation, release/tag/asset mutation, self-approval, self-import, or self-execution.

Goal id: $($Ids.goal_id)
Title: $($Ids.title)
Project id: $ProjectId
Campaign id: $($Ids.campaign_id)
Goal budget remaining: $GoalBudgetRemaining
Objective: $($Ids.objective)

Required metadata schema: $MetadataSchema
Required booleans: human_review_required=true, import_allowed=false, execution_allowed=false, token_printed=false.
Required sections: Context, Mission, Hard Safety Boundaries, Allowed Scope, Forbidden Scope, Implementation Requirements, Validation Requirements, CI/CD Requirements, Manual Milestone Script Requirement, Evidence Requirements, Final Report Requirements, No-Execution Statement.
"@
  $codexArgs = @(
    "--ask-for-approval", "never",
    "exec",
    "--sandbox", "read-only",
    "--ephemeral",
    "--ignore-rules",
    "--skip-git-repo-check",
    "-C", $GeneratedRoot,
    "-"
  )
  $invocation = Get-CodexProcessInvocation -CodexCommand $codex -CodexArguments $codexArgs
  if (-not $invocation) {
    return [pscustomobject]@{ ok = $false; reason = "codex_start_failed"; markdown = "" }
  }

  $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = $invocation.file_name
  if ($invocation.PSObject.Properties["arguments_string"] -and -not [string]::IsNullOrWhiteSpace([string]$invocation.arguments_string)) {
    $processInfo.Arguments = [string]$invocation.arguments_string
  } else {
    foreach ($argument in @($invocation.arguments)) {
      [void]$processInfo.ArgumentList.Add($argument)
    }
  }
  $processInfo.WorkingDirectory = $GeneratedRoot
  $processInfo.UseShellExecute = $false
  $processInfo.RedirectStandardInput = $true
  $processInfo.RedirectStandardOutput = $true
  $processInfo.RedirectStandardError = $true
  $processInfo.CreateNoWindow = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $processInfo
  try {
    [void]$process.Start()
    $process.StandardInput.Write($prompt)
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit(120000)
    if (-not $completed) {
      try { $process.Kill($true) } catch { try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {} }
      return [pscustomobject]@{ ok = $false; reason = "codex_timeout"; markdown = "" }
    }
    $process.WaitForExit()
    $stdout = [string]$stdoutTask.GetAwaiter().GetResult()
    [void]$stderrTask.GetAwaiter().GetResult()
    if ([int]$process.ExitCode -ne 0) {
      return [pscustomobject]@{ ok = $false; reason = "codex_nonzero_exit"; markdown = "" }
    }
    return [pscustomobject]@{ ok = $true; reason = "codex_completed"; markdown = $stdout }
  } catch {
    try {
      if ($process -and -not $process.HasExited) { $process.Kill($true) }
    } catch {
      try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    [pscustomobject]@{ ok = $false; reason = "codex_start_failed"; markdown = "" }
  }
}

function Get-TargetPath([string]$GeneratedRoot, $Ids) {
  if ($Fixture) {
    return (Join-Path $GeneratedRoot "generated-goal-354-fixture.md")
  }
  Join-Path $GeneratedRoot ($Ids.goal_id + ".md")
}

function Get-HashOrEmpty([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-Evidence {
  param($Context, [bool]$GoalValid)
  $flags = New-SafetyFlags
  $record = [ordered]@{
    schema = $EvidenceSchema
    generated_at = $Context.generated_at
    provider_inventory_checked = $Context.provider_inventory_checked
    direct_provider_available = $Context.direct_provider_available
    codex_detected = $Context.codex_detected
    codex_generation_called = $Context.codex_generation_called
    generated_goal_path_safe = $Context.generated_goal_path_safe
    generated_goal_hash = $Context.generated_goal_hash
    generated_goal_valid = $GoalValid
  }
  foreach ($property in $flags.PSObject.Properties) { $record[$property.Name] = $property.Value }
  [pscustomobject]$record
}

function New-GeneratorResult {
  param(
    [string]$GeneratedAt,
    $Ids,
    [bool]$ProviderInventoryChecked,
    [bool]$DirectProviderAvailable,
    [bool]$CodexDetected,
    [bool]$CodexGenerationRequested,
    [bool]$CodexGenerationCalled,
    [bool]$CodexGenerationSucceeded,
    [string]$GoalPathSafe,
    [string]$GoalHash,
    [bool]$SchemaValid,
    [bool]$SafetyValid,
    [bool]$GoalWritten,
    [string[]]$Blockers,
    [string[]]$Warnings
  )
  $flags = New-SafetyFlags
  $context = [pscustomobject]@{
    generated_at = $GeneratedAt
    provider_inventory_checked = $ProviderInventoryChecked
    direct_provider_available = $DirectProviderAvailable
    codex_detected = $CodexDetected
    codex_generation_called = $CodexGenerationCalled
    generated_goal_path_safe = $GoalPathSafe
    generated_goal_hash = $GoalHash
  }
  $record = [ordered]@{
    schema = $Schema
    generated_at = $GeneratedAt
    mode = $Ids.mode
    project_id = $ProjectId
    campaign_id = $Ids.campaign_id
    goal_budget_remaining = $GoalBudgetRemaining
    provider_inventory_checked = $ProviderInventoryChecked
    direct_provider_available = $DirectProviderAvailable
    codex_detected = $CodexDetected
    codex_generation_requested = $CodexGenerationRequested
    codex_generation_called = $CodexGenerationCalled
    codex_generation_succeeded = $CodexGenerationSucceeded
    generated_goal_id = $Ids.goal_id
    generated_goal_title = $Ids.title
    generated_goal_path_safe = $GoalPathSafe
    generated_goal_hash = $GoalHash
    generated_goal_schema_valid = $SchemaValid
    generated_goal_safety_valid = $SafetyValid
    proposed_goal_written = $GoalWritten
    blockers = @($Blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    warnings = @($Warnings | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    safety_flags = $flags
    evidence = (New-Evidence -Context $context -GoalValid:($SchemaValid -and $SafetyValid))
  }
  foreach ($property in $flags.PSObject.Properties) { $record[$property.Name] = $property.Value }
  [pscustomobject]$record
}

function Write-Reports($Result) {
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "local-goal-generator.json"
  $mdPath = Join-Path $root "local-goal-generator.md"
  $Result | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Result | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $lines = @(
    "# Local Goal Generator Report",
    "",
    "- schema: $($Result.schema)",
    "- mode: $($Result.mode)",
    "- campaign_id: $($Result.campaign_id)",
    "- generated_goal_id: $($Result.generated_goal_id)",
    "- generated_goal_path_safe: $($Result.generated_goal_path_safe)",
    "- generated_goal_hash: $($Result.generated_goal_hash)",
    "- generated_goal_schema_valid: $($Result.generated_goal_schema_valid)",
    "- generated_goal_safety_valid: $($Result.generated_goal_safety_valid)",
    "- import_performed: false",
    "- approval_performed: false",
    "- append_performed: false",
    "- task_created: false",
    "- task_claimed: false",
    "- execution_started: false",
    "- worker_loop_started: false",
    "- token_printed: false",
    "- blockers: $(@($Result.blockers) -join ', ')",
    "- warnings: $(@($Result.warnings) -join ', ')"
  )
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
}

$ids = Get-GeneratorIds
$blockers = @()
$warnings = @()
if ($Fixture) { Add-Finding ([ref]$warnings) "fixture_mode_no_codex_invocation" }
if ($UseCodex -and $Provider -ne "direct") { Add-Finding ([ref]$blockers) "unsupported_provider:$Provider" }
if (-not (Test-SafeGoalId $ids.goal_id)) { Add-Finding ([ref]$blockers) "unsafe_goal_id" }
if (Test-UnsafeOperatorText $ids.title) { Add-Finding ([ref]$blockers) "unsafe_title" }
if (Test-UnsafeOperatorText $ids.objective) { Add-Finding ([ref]$blockers) "unsafe_objective" }
if ($GoalBudgetRemaining -lt 0) { Add-Finding ([ref]$blockers) "goal_budget_remaining_invalid" }

$generatedRoot = Resolve-GeneratedRoot ([ref]$blockers)
$targetPath = Get-TargetPath -GeneratedRoot $generatedRoot -Ids $ids
$targetSafe = Convert-ToSafePath $targetPath
$generatedAt = (Get-Date).ToUniversalTime().ToString("o")

$inventory = Invoke-ProviderInventory
$directAvailable = Test-DirectProviderAvailable $inventory
$codexDetected = Test-CodexDetected $inventory
if (-not $directAvailable) { Add-Finding ([ref]$blockers) "direct_provider_unavailable" }
if ($UseCodex -and -not $codexDetected) { Add-Finding ([ref]$blockers) "codex_not_detected" }

$codexRequested = ($UseCodex -and $Command -eq "generate-one")
$codexCalled = $false
$codexSucceeded = $false
$goalWritten = $false
$schemaValid = $false
$safetyValid = $false
$goalHash = ""

if ($Command -eq "generate-one") {
  if ($Confirm -ne $GenerateConfirmation) {
    Add-Finding ([ref]$blockers) "missing_exact_confirmation"
  }
  if ($blockers.Count -eq 0) {
    New-Item -ItemType Directory -Force -Path $generatedRoot | Out-Null
    if ($UseCodex) {
      $codexCalled = $true
      $codexResult = Invoke-LocalCodexGeneration -Ids $ids -GeneratedRoot $generatedRoot -TargetPath $targetPath
      if ($codexResult.ok) {
        $validation = Test-GeneratedMarkdown -Markdown ([string]$codexResult.markdown) -ExpectedGoalId $ids.goal_id
        if ($validation.valid) {
          Set-Content -LiteralPath $targetPath -Value ([string]$codexResult.markdown) -Encoding UTF8
          $goalWritten = $true
          $codexSucceeded = $true
        } else {
          Add-Finding ([ref]$blockers) "codex_output_validation_failed"
          foreach ($errorName in @($validation.errors)) { Add-Finding ([ref]$warnings) $errorName }
        }
      } else {
        Add-Finding ([ref]$blockers) $codexResult.reason
      }
    } else {
      $markdown = New-GeneratedGoalMarkdown $ids
      $validation = Test-GeneratedMarkdown -Markdown $markdown -ExpectedGoalId $ids.goal_id
      if ($validation.valid) {
        Set-Content -LiteralPath $targetPath -Value $markdown -Encoding UTF8
        $goalWritten = $true
      } else {
        Add-Finding ([ref]$blockers) "fixture_markdown_validation_failed"
        foreach ($errorName in @($validation.errors)) { Add-Finding ([ref]$warnings) $errorName }
      }
    }
  }
} elseif ($Command -in @("validate-generated", "classify")) {
  if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
    $markdown = Get-Content -Raw -LiteralPath $targetPath
    $validation = Test-GeneratedMarkdown -Markdown $markdown -ExpectedGoalId $ids.goal_id
    foreach ($errorName in @($validation.errors)) { Add-Finding ([ref]$warnings) $errorName }
  } else {
    Add-Finding ([ref]$blockers) "generated_goal_missing"
  }
}

if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
  $goalHash = Get-HashOrEmpty $targetPath
  $markdown = Get-Content -Raw -LiteralPath $targetPath
  $validation = Test-GeneratedMarkdown -Markdown $markdown -ExpectedGoalId $ids.goal_id
  $schemaValid = $validation.valid
  $safetyValid = $validation.valid
  $goalWritten = $true
} elseif ($Command -eq "preview") {
  $previewMarkdown = New-GeneratedGoalMarkdown $ids
  $validation = Test-GeneratedMarkdown -Markdown $previewMarkdown -ExpectedGoalId $ids.goal_id
  $schemaValid = $validation.valid
  $safetyValid = $validation.valid
} elseif ($Command -in @("status", "report", "safe-summary")) {
  $schemaValid = ($blockers.Count -eq 0)
  $safetyValid = ($blockers.Count -eq 0)
}

$result = New-GeneratorResult `
  -GeneratedAt $generatedAt `
  -Ids $ids `
  -ProviderInventoryChecked:$true `
  -DirectProviderAvailable:$directAvailable `
  -CodexDetected:$codexDetected `
  -CodexGenerationRequested:$codexRequested `
  -CodexGenerationCalled:$codexCalled `
  -CodexGenerationSucceeded:$codexSucceeded `
  -GoalPathSafe:$targetSafe `
  -GoalHash:$goalHash `
  -SchemaValid:$schemaValid `
  -SafetyValid:$safetyValid `
  -GoalWritten:$goalWritten `
  -Blockers:$blockers `
  -Warnings:$warnings

if ($WriteReport -or $Command -eq "report") {
  Write-Reports $result
}

if ($Json) {
  ConvertTo-SafeJson $result
} elseif ($Command -eq "safe-summary") {
  Write-Host "mode=$($result.mode) generated_goal_id=$($result.generated_goal_id) written=$($result.proposed_goal_written) valid=$($result.generated_goal_schema_valid) blockers=$(@($result.blockers).Count) token_printed=false"
} else {
  Write-Host "SkyBridge local goal generator $($result.mode): written=$($result.proposed_goal_written) valid=$($result.generated_goal_schema_valid) token_printed=false"
}
