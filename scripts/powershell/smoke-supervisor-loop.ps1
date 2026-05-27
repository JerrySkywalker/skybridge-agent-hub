param([int]$Port = 0)

$ErrorActionPreference = "Stop"

& pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-supervisor-dry-run.ps1 -Port $Port
