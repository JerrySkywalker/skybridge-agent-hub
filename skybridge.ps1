[CmdletBinding()]
param(
  [string]$Command = "status"
)

$ErrorActionPreference = "Stop"
$Script = Join-Path $PSScriptRoot "scripts\powershell\skybridge-launcher.ps1"
& pwsh -NoProfile -ExecutionPolicy Bypass -File $Script -Command $Command
