$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

function Invoke-LocalAuthGate([string]$Payload) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-auth.ps1") -Command validate-request -Payload $Payload -Json
  if ($LASTEXITCODE -ne 0) { throw "Local auth validation failed." }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "Local auth validation emitted unsafe text." }
  $text | ConvertFrom-Json
}

$cases = @(
  "shell=echo fixture",
  "command=pwsh fixture",
  "powershell=fixture",
  "bash=fixture",
  "execute=true",
  "queue_apply=true",
  "start_all=true",
  "claim_task=true"
)

foreach ($payload in $cases) {
  $result = Invoke-LocalAuthGate $payload
  if ($result.accepted -ne $false) { throw "Red-team command payload was accepted." }
  if (@($result.reasons).Count -lt 1) { throw "Red-team command payload had no rejection reason." }
  Assert-False $result.execution_enabled "execution_enabled"
  Assert-False $result.queue_apply_enabled "queue_apply_enabled"
  Assert-False $result.remote_execution_enabled "remote_execution_enabled"
  Assert-False $result.arbitrary_command_enabled "arbitrary_command_enabled"
}

Write-Host "[smoke-redteam-command-injection-rejected] ok"
