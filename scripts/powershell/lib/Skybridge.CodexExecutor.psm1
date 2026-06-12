Import-Module (Join-Path $PSScriptRoot "Skybridge.Core.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Skybridge.SafetyScanner.psm1") -Force

function Resolve-SkybridgeCodexCommand {
  param([string[]]$FixtureCommands = @())
  $commands = if ($FixtureCommands.Count -gt 0) {
    $FixtureCommands | ForEach-Object { [pscustomobject]@{ Source = $_; Name = [System.IO.Path]::GetFileName($_) } }
  } else {
    @(Get-Command "codex" -All -ErrorAction SilentlyContinue)
  }
  if (@($commands).Count -eq 0) {
    return [pscustomobject]@{ found = $false; launcher_kind = "missing"; token_printed = $false }
  }
  $preferred = @(
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".exe" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".cmd" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".bat" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".ps1" } | Select-Object -First 1
    $commands | Select-Object -First 1
  ) | Where-Object { $null -ne $_ } | Select-Object -First 1
  $source = [string]$preferred.Source
  $ext = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
  $kind = switch ($ext) {
    ".exe" { "exe" }
    ".cmd" { "cmd" }
    ".bat" { "bat" }
    ".ps1" { "ps1" }
    default { "extensionless" }
  }
  [pscustomobject]@{
    found = $true
    source = $source
    host_executable_name = [System.IO.Path]::GetFileName($source)
    launcher_kind = $kind
    token_printed = $false
  }
}

function New-SkybridgeCodexInvocationProfile {
  param([ValidateSet("profile_workspace_write_workdir", "profile_ephemeral_cd")][string]$ProfileId = "profile_workspace_write_workdir")
  [pscustomobject]@{
    profile_id = $ProfileId
    enabled = ($ProfileId -eq "profile_workspace_write_workdir")
    disabled_reason = if ($ProfileId -eq "profile_ephemeral_cd") { "modeled_but_disabled_until_compatible" } else { $null }
    arguments = @("exec", "--sandbox", "workspace-write", "-")
    stdin_prompt_supported = $true
    stdout_persisted = $false
    stderr_persisted = $false
    prompt_persisted = $false
    transcript_persisted = $false
    token_printed = $false
  }
}

function New-SkybridgeCodexExecutionPlan {
  param([string]$Prompt = "", [string[]]$FixtureCommands = @())
  if (Test-SkybridgeUnsafeText $Prompt) { throw "Unsafe prompt text detected." }
  $resolved = Resolve-SkybridgeCodexCommand -FixtureCommands $FixtureCommands
  $profile = New-SkybridgeCodexInvocationProfile
  [pscustomobject]@{
    schema = "skybridge.codex_execution_plan.v1"
    resolved = $resolved
    profile = $profile
    prompt_character_count = ($Prompt ?? "").Length
    stdout_character_count = 0
    stderr_character_count = 0
    execution_invoked = $false
    fixture_mode = ($FixtureCommands.Count -gt 0)
    token_printed = $false
  }
}

function Invoke-SkybridgeCodexFixture {
  param([string]$Prompt = "", [string[]]$FixtureCommands = @("C:/tools/codex.exe"))
  New-SkybridgeCodexExecutionPlan -Prompt $Prompt -FixtureCommands $FixtureCommands
}

Export-ModuleMember -Function Resolve-SkybridgeCodexCommand, New-SkybridgeCodexInvocationProfile, New-SkybridgeCodexExecutionPlan, Invoke-SkybridgeCodexFixture
