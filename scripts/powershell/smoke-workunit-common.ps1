function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Invoke-WorkunitQueue {
  param([Parameter(Mandatory = $true)][string]$Command)
  $script = Join-Path $PSScriptRoot "skybridge-workunit-queue.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command $Command -Json
  if ($LASTEXITCODE -ne 0) { throw "skybridge-workunit-queue $Command failed." }
  return ($raw | ConvertFrom-Json)
}

function Assert-TokenPrintedFalse {
  param([Parameter(Mandatory = $true)]$Value)
  $json = $Value | ConvertTo-Json -Depth 50 -Compress
  if ($json -match '"token_printed"\s*:\s*true') { throw "token_printed=true found." }
}

function Assert-CleanGitStatus {
  param([AllowEmptyString()][Parameter(Mandatory = $true)][string]$Before)
  $after = (git status --short | Out-String).Trim()
  if ($after -ne $Before) { throw "Command mutated git worktree. Before=[$Before] After=[$after]" }
}
