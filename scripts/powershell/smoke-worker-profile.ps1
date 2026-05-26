param(
  [string]$ProfilePath = ".\config\worker-profile.example.json"
)

$ErrorActionPreference = "Stop"

$loader = Join-Path $PSScriptRoot "load-worker-profile.ps1"
if (-not (Test-Path -LiteralPath $loader)) {
  throw "Missing worker profile loader at $loader."
}

function Load-ProfileJson([string]$Path, [switch]$AsEdgeWorkerConfig) {
  $args = @("-ExecutionPolicy", "Bypass", "-File", $loader, "-ConfigFile", $Path, "-Json")
  if ($AsEdgeWorkerConfig) {
    $args += @("-ProjectId", "skybridge-agent-hub", "-AsEdgeWorkerConfig")
  }
  $raw = & pwsh @args
  if ($LASTEXITCODE -ne 0) {
    throw "Profile loader failed for $Path."
  }
  return ($raw | ConvertFrom-Json)
}

$profile = Load-ProfileJson $ProfilePath
if ($profile.worker_id -ne "worker-dev-example") { throw "Unexpected example worker_id." }
if ($profile.allow_production_deploy -ne $false) { throw "Example profile must keep allow_production_deploy false." }
if ($profile.token_value_printed -ne $false) { throw "Loader must not print token values." }
if (-not $profile.skybridge_api_base) { throw "Expected skybridge_api_base." }
if (-not ($profile.project_ids -contains "skybridge-agent-hub")) { throw "Expected skybridge-agent-hub project." }

$edgeConfig = Load-ProfileJson $ProfilePath -AsEdgeWorkerConfig
if ($edgeConfig.project_id -ne "skybridge-agent-hub") { throw "Expected project-specific edge config." }
if (-not $edgeConfig.api_base) { throw "Expected edge worker api_base." }
if (-not $edgeConfig.codex_command) { throw "Expected edge worker codex_command." }

$cloudPath = ".\config\worker-profile.cloud.example.json"
if (Test-Path -LiteralPath $cloudPath) {
  $cloud = Load-ProfileJson $cloudPath
  if ($cloud.auth_mode -ne "worker-token") { throw "Cloud example should use worker-token auth mode." }
  if ($cloud.allow_auto_merge -ne $false) { throw "Cloud example should not allow auto-merge by default." }
  if ($cloud.allow_production_deploy -ne $false) { throw "Cloud example must keep production deploy disabled." }
}

& pwsh -ExecutionPolicy Bypass -File $loader -ConfigFile ".\config\missing-worker-profile.json" -Json 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
  throw "Expected missing profile to fail clearly."
}

[pscustomobject]@{
  ProfilePath = $ProfilePath
  WorkerId = $profile.worker_id
  ApiBase = $profile.skybridge_api_base
  ProjectCount = @($profile.project_ids).Count
  TokenValuePrinted = $profile.token_value_printed
  ProductionDeployAllowed = $profile.allow_production_deploy
  EdgeWorkerConfig = "passed"
} | Format-List
