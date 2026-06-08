[CmdletBinding()]
param(
  [ValidateSet("project-profile-validate", "project-profile-preview", "project-profile-list", "project-profile-hash", "project-select-preview")]
  [string]$Command = "project-profile-validate",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$ProfileFile,
  [string]$ProfileDir = "config/project-profiles",
  [string]$ExpectedDefaultBranch = "main",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path

function ConvertTo-SafeSlash {
  param([string]$Value)
  return ([string]$Value) -replace "\\", "/"
}

function Get-ProfileFiles {
  if (-not (Test-Path -LiteralPath $ProfileDir -PathType Container)) { return @() }
  @(Get-ChildItem -LiteralPath $ProfileDir -Filter "*.json" -File | Sort-Object Name)
}

function Resolve-ProfilePath {
  if (-not [string]::IsNullOrWhiteSpace($ProfileFile)) {
    $path = if ([System.IO.Path]::IsPathRooted($ProfileFile)) { $ProfileFile } else { Join-Path $RepoRoot $ProfileFile }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Profile file not found: $ProfileFile" }
    return (Resolve-Path -LiteralPath $path).Path
  }
  $match = @(Get-ProfileFiles | Where-Object { $_.BaseName -eq $ProjectId -or $_.BaseName -eq "$ProjectId.fixture" } | Select-Object -First 1)
  if (-not $match) {
    foreach ($file in Get-ProfileFiles) {
      try {
        $read = Read-Profile -Path $file.FullName
        if ([string]$read.profile.project_id -eq $ProjectId) { return $file.FullName }
      } catch {
      }
    }
    return $null
  }
  return $match[0].FullName
}

function Read-Profile {
  param([string]$Path)
  $raw = Get-Content -Raw -LiteralPath $Path
  try {
    $profile = $raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "Invalid project profile JSON: $Path"
  }
  return [pscustomobject]@{ raw = $raw; profile = $profile; path = $Path }
}

function Get-StableProfileHash {
  param([object]$Profile)
  $copy = $Profile | ConvertTo-Json -Depth 80 | ConvertFrom-Json
  if ($copy.PSObject.Properties["profile_hash"]) { $copy.PSObject.Properties.Remove("profile_hash") }
  if ($copy.PSObject.Properties["token_printed"]) { $copy.PSObject.Properties.Remove("token_printed") }
  $json = $copy | ConvertTo-Json -Depth 80 -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Test-SecretLookingText {
  param([string]$Text)
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|private[_-]?key|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|cookie'
}

function Test-SecretLookingKey {
  param([string]$Key)
  if ($Key -in @("token_printed", "forbid_secret_fields")) { return $false }
  return $Key -match '(?i)(secret|token|authorization|api[_-]?key|private[_-]?key|password|cookie|credential)'
}

function Add-ProfileFieldFindings {
  param([object]$Value, [string]$Path, [System.Collections.Generic.List[string]]$Errors)
  if ($null -eq $Value) { return }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    foreach ($prop in $Value.PSObject.Properties) {
      $childPath = if ($Path) { "$Path.$($prop.Name)" } else { $prop.Name }
      if (Test-SecretLookingKey -Key $prop.Name) { $Errors.Add("secret_looking_field:$childPath") | Out-Null }
      Add-ProfileFieldFindings -Value $prop.Value -Path $childPath -Errors $Errors
    }
  } elseif ($Value -is [array]) {
    for ($i = 0; $i -lt $Value.Count; $i++) {
      Add-ProfileFieldFindings -Value $Value[$i] -Path "$Path[$i]" -Errors $Errors
    }
  } elseif ($Value -is [string]) {
    if (Test-SecretLookingText -Text $Value) { $Errors.Add("secret_looking_value:$Path") | Out-Null }
  }
}

function Resolve-RepoScopedPath {
  param([string]$RepoPath, [string]$PathValue)
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
  if ([System.IO.Path]::IsPathRooted($PathValue)) { return [System.IO.Path]::GetFullPath($PathValue) }
  return [System.IO.Path]::GetFullPath((Join-Path $RepoPath $PathValue))
}

function Test-PathInsideRoot {
  param([string]$Root, [string]$Candidate)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  return $candidateFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or $candidateFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or $candidateFull.StartsWith($rootFull + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-BlockedOperationalPath {
  param([string]$Value, [bool]$FixtureOnly)
  if ($FixtureOnly) { return $false }
  return (ConvertTo-SafeSlash $Value) -match '(?i)(^|/)(production|server-root|dns|openresty|authelia|1panel|hermes)(/|$)|docker-daemon|/opt/skybridge-agent-hub'
}

function Test-CommandShape {
  param([string]$CommandText, [bool]$KnownFixture)
  if ([string]::IsNullOrWhiteSpace($CommandText)) { return "validation_command_empty" }
  if ($KnownFixture) {
    if ($CommandText -notmatch '^fixture:[a-z0-9][a-z0-9:-]*$') { return "invalid_fixture_command_shape" }
    return $null
  }
  if ($CommandText -match '[;&|<>`]' -or $CommandText -match '(?i)\b(invoke-expression|iex|start-process|cmd\s*/c|powershell\s+-command|pwsh\s+-command|bash\s+-c|sh\s+-c|curl|wget|ssh|scp)\b') {
    return "arbitrary_shell_command_shape"
  }
  if ($CommandText -notmatch '^(corepack pnpm( -C [A-Za-z0-9_./-]+)? [A-Za-z0-9:_./-]+|pwsh -ExecutionPolicy Bypass -File scripts/powershell/[A-Za-z0-9_.-]+\.ps1( -[A-Za-z0-9_.-]+)*)$') {
    return "unapproved_validation_command_shape"
  }
  return $null
}

function Test-ProjectProfile {
  param([object]$Profile, [string]$Path)
  $errors = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]
  Add-ProfileFieldFindings -Value $Profile -Path "" -Errors $errors

  foreach ($field in @("project_id", "display_name", "repo_path", "repo_identity", "default_branch", "allowed_paths", "blocked_paths", "validation_commands", "worker_profile", "goal_pack", "ci_policy", "project_policy")) {
    if (-not $Profile.PSObject.Properties[$field]) { $errors.Add("missing_field:$field") | Out-Null }
  }
  if ([string]::IsNullOrWhiteSpace([string]$Profile.repo_path)) { $errors.Add("missing_repo_path") | Out-Null }
  if ([string]::IsNullOrWhiteSpace([string]$Profile.default_branch)) { $errors.Add("missing_default_branch") | Out-Null }
  if (@($Profile.allowed_paths).Count -eq 0) { $errors.Add("missing_allowed_paths") | Out-Null }

  $fixtureOnly = [bool]$Profile.project_policy.fixture_only
  $repoPathText = [string]$Profile.repo_path
  $repoPath = if ([System.IO.Path]::IsPathRooted($repoPathText)) { [System.IO.Path]::GetFullPath($repoPathText) } else { [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $repoPathText)) }
  $approvedRoots = @($Profile.project_policy.approved_repo_roots)
  if ($approvedRoots.Count -eq 0) { $errors.Add("missing_approved_repo_roots") | Out-Null }
  $approved = $false
  foreach ($root in $approvedRoots) {
    $rootPath = if ([System.IO.Path]::IsPathRooted([string]$root)) { [System.IO.Path]::GetFullPath([string]$root) } else { [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ([string]$root))) }
    if ($repoPath.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) { $approved = $true }
  }
  if (-not $approved) { $errors.Add("unapproved_repo_path") | Out-Null }
  if (-not $fixtureOnly -and -not (Test-Path -LiteralPath $repoPath -PathType Container)) { $errors.Add("project_repo_path_invalid") | Out-Null }
  if ($fixtureOnly -and -not (Test-Path -LiteralPath $repoPath -PathType Container)) { $warnings.Add("fixture_repo_path_missing") | Out-Null }
  if (-not [bool]$Profile.project_policy.allow_absolute_repo_path -and [System.IO.Path]::IsPathRooted($repoPathText)) { $errors.Add("absolute_repo_path_not_allowed") | Out-Null }
  if (Test-BlockedOperationalPath -Value $repoPathText -FixtureOnly:$fixtureOnly) { $errors.Add("blocked_operational_repo_path") | Out-Null }

  foreach ($allowed in @($Profile.allowed_paths)) {
    $item = [string]$allowed
    if (Test-BlockedOperationalPath -Value $item -FixtureOnly:$fixtureOnly) { $errors.Add("blocked_operational_allowed_path:$item") | Out-Null }
    $resolved = Resolve-RepoScopedPath -RepoPath $repoPath -PathValue $item
    if (-not (Test-PathInsideRoot -Root $repoPath -Candidate $resolved)) { $errors.Add("allowed_path_outside_repo:$item") | Out-Null }
  }
  foreach ($blocked in @($Profile.blocked_paths)) {
    $item = [string]$blocked
    $resolved = Resolve-RepoScopedPath -RepoPath $repoPath -PathValue $item
    if (-not (Test-PathInsideRoot -Root $repoPath -Candidate $resolved)) { $errors.Add("blocked_path_outside_repo:$item") | Out-Null }
  }

  foreach ($entry in @($Profile.validation_commands)) {
    $reason = Test-CommandShape -CommandText ([string]$entry.command) -KnownFixture ([bool]$entry.known_fixture)
    if ($reason) { $errors.Add("$reason`:$($entry.id)") | Out-Null }
  }

  $goalPackDirs = @($Profile.goal_pack.allowed_goal_pack_dirs)
  if ([string]::IsNullOrWhiteSpace([string]$Profile.goal_pack.default_goal_pack_dir)) { $errors.Add("invalid_goal_pack_path") | Out-Null }
  if ($goalPackDirs.Count -eq 0 -or @($goalPackDirs) -notcontains [string]$Profile.goal_pack.default_goal_pack_dir) { $errors.Add("invalid_goal_pack_path") | Out-Null }
  foreach ($goalPack in @($goalPackDirs)) {
    $resolvedGoalPack = Resolve-RepoScopedPath -RepoPath $repoPath -PathValue ([string]$goalPack)
    if (-not (Test-PathInsideRoot -Root $repoPath -Candidate $resolvedGoalPack)) { $errors.Add("goal_pack_path_outside_repo:$goalPack") | Out-Null }
    if (-not $fixtureOnly -and -not (Test-Path -LiteralPath $resolvedGoalPack -PathType Container)) { $errors.Add("invalid_goal_pack_path:$goalPack") | Out-Null }
  }

  if ([string]$Profile.default_branch -ne $ExpectedDefaultBranch) { $warnings.Add("project_default_branch_mismatch") | Out-Null }
  if ([bool]$Profile.worker_profile.can_claim_tasks -or [bool]$Profile.worker_profile.can_execute_tasks) { $errors.Add("worker_profile_execution_enabled") | Out-Null }
  if ([bool]$Profile.goal_pack.import_apply_enabled) { $errors.Add("goal_pack_import_apply_enabled") | Out-Null }
  if ([bool]$Profile.ci_policy.auto_merge_enabled) { $warnings.Add("ci_auto_merge_enabled_not_used_by_goal_198") | Out-Null }

  $hash = Get-StableProfileHash -Profile $Profile
  $status = if ($errors.Count -eq 0) { "valid" } else { "invalid" }
  [pscustomobject]@{
    schema = "skybridge.project_profile_validation.v1"
    ok = ($errors.Count -eq 0)
    validation_status = $status
    project_id = [string]$Profile.project_id
    display_name = [string]$Profile.display_name
    repo_identity = [string]$Profile.repo_identity
    repo_path = ConvertTo-SafeSlash $repoPath
    repo_path_display = if ($fixtureOnly) { ConvertTo-SafeSlash $Profile.repo_path } else { "V:/src/skybridge-agent-hub" }
    default_branch = [string]$Profile.default_branch
    allowed_path_count = @($Profile.allowed_paths).Count
    blocked_path_count = @($Profile.blocked_paths).Count
    validation_command_count = @($Profile.validation_commands).Count
    worker_profile_summary = [pscustomobject]@{
      default_worker_profile = [string]$Profile.worker_profile.default_worker_profile
      allowed_worker_profiles = @($Profile.worker_profile.allowed_worker_profiles)
      can_claim_tasks = $false
      can_execute_tasks = $false
    }
    goal_pack_summary = [pscustomobject]@{
      default_goal_pack_dir = [string]$Profile.goal_pack.default_goal_pack_dir
      allowed_goal_pack_dirs = @($Profile.goal_pack.allowed_goal_pack_dirs)
      import_apply_enabled = $false
    }
    ci_policy_summary = [pscustomobject]@{
      required_checks = @($Profile.ci_policy.required_checks)
      auto_merge_enabled = [bool]$Profile.ci_policy.auto_merge_enabled
      dry_run_default = [bool]$Profile.ci_policy.dry_run_default
    }
    policy_summary = [pscustomobject]@{
      fixture_only = $fixtureOnly
      dry_run_default = [bool]$Profile.project_policy.dry_run_default
      selection_preview_only = [bool]$Profile.project_policy.selection_preview_only
      forbid_arbitrary_shell = [bool]$Profile.project_policy.forbid_arbitrary_shell
      forbid_secret_fields = [bool]$Profile.project_policy.forbid_secret_fields
      forbid_production_paths = [bool]$Profile.project_policy.forbid_production_paths
    }
    validation_commands = @($Profile.validation_commands | ForEach-Object { [pscustomobject]@{ id = [string]$_.id; command = [string]$_.command; known_fixture = [bool]$_.known_fixture; executes = $false } })
    errors = @($errors | Select-Object -Unique)
    warnings = @($warnings | Select-Object -Unique)
    profile_hash = $hash
    token_printed = $false
  }
}

function New-SelectionPreview {
  param([object]$Validation)
  [pscustomobject]@{
    schema = "skybridge.project_selection_preview.v1"
    ok = [bool]$Validation.ok
    mode = "preview"
    selected_project_id = [string]$Validation.project_id
    profile_hash = [string]$Validation.profile_hash
    repo_identity = [string]$Validation.repo_identity
    repo_path_display = [string]$Validation.repo_path_display
    default_branch = [string]$Validation.default_branch
    allowed_path_summary = "$($Validation.allowed_path_count) allowed paths; $($Validation.blocked_path_count) blocked paths"
    worker_profile_summary = $Validation.worker_profile_summary
    goal_pack_summary = $Validation.goal_pack_summary
    blocked_reason = if ($Validation.ok) { $null } else { (@($Validation.errors) -join ";") }
    project_selection_preview_only = $true
    task_created = $false
    task_claimed = $false
    task_executed = $false
    worker_loop_started = $false
    queue_execution_enabled = $false
    validation_commands_executed = $false
    token_printed = $false
  }
}

$result = $null
if ($Command -eq "project-profile-list") {
  $profiles = foreach ($file in Get-ProfileFiles) {
    $read = Read-Profile -Path $file.FullName
    $validation = Test-ProjectProfile -Profile $read.profile -Path $read.path
    [pscustomobject]@{
      project_id = $validation.project_id
      display_name = $validation.display_name
      validation_status = $validation.validation_status
      repo_identity = $validation.repo_identity
      default_branch = $validation.default_branch
      profile_hash = $validation.profile_hash
      token_printed = $false
    }
  }
  $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; schema = "skybridge.project_profile_list.v1"; profiles = @($profiles); token_printed = $false }
} else {
  $path = Resolve-ProfilePath
  if ($null -eq $path) {
    $result = [pscustomobject]@{
      ok = $false
      command = $Command
      mode = "read"
      schema = "skybridge.project_profile_missing.v1"
      project_id = $ProjectId
      error = "project_profile_missing"
      attention_events = @("project_profile_missing")
      token_printed = $false
    }
  } else {
    $read = Read-Profile -Path $path
    $validation = Test-ProjectProfile -Profile $read.profile -Path $read.path
    switch ($Command) {
      "project-profile-hash" {
        $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $validation.project_id; profile_hash = $validation.profile_hash; token_printed = $false }
      }
      "project-select-preview" {
        $result = New-SelectionPreview -Validation $validation
      }
      "project-profile-preview" {
        $selection = New-SelectionPreview -Validation $validation
        $result = [pscustomobject]@{ ok = [bool]$validation.ok; command = $Command; mode = "preview"; validation = $validation; selection_preview = $selection; no_execution_controls = $true; token_printed = $false }
      }
      default {
        $result = $validation
        $result | Add-Member -NotePropertyName command -NotePropertyValue $Command -Force
        $result | Add-Member -NotePropertyName mode -NotePropertyValue "read" -Force
      }
    }
  }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if ($text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log') {
  throw "Secret-looking or raw-log field detected."
}
if ($Json) { $text } else { $result | Format-List }
