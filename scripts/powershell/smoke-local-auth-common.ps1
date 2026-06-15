$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

function Invoke-LocalAuthJson([string]$Command, [string[]]$ExtraArgs = @()) {
  Invoke-SmokeJson "skybridge-local-auth.ps1" @("-Command", $Command) @($ExtraArgs)
}

function Assert-LocalAuthDisabled($Value) {
  Assert-False $Value.execution_enabled "execution_enabled"
  Assert-False $Value.queue_apply_enabled "queue_apply_enabled"
  Assert-False $Value.remote_execution_enabled "remote_execution_enabled"
  Assert-False $Value.arbitrary_command_enabled "arbitrary_command_enabled"
}

function Assert-NoTokenPrintedTrueInFile([string]$Path) {
  $text = Get-Content -Raw -LiteralPath $Path
  if (Test-UnsafeText $text) { throw "Unsafe text in $Path" }
}
