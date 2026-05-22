[CmdletBinding()]
param(
  [string]$ConfigFile = ".\config\iteration-controller.example.json",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Test-CommandAvailable {
  param([string]$Name)
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Add-Check {
  param([string]$Name, [bool]$Ok, [string]$Detail)
  $script:checks += @{
    name = $Name
    ok = $Ok
    detail = $Detail
  }
}

$script:checks = @()

Add-Check -Name "git" -Ok (Test-CommandAvailable "git") -Detail "Git CLI available"
Add-Check -Name "gh" -Ok (Test-CommandAvailable "gh") -Detail "GitHub CLI available"
Add-Check -Name "codex" -Ok (Test-CommandAvailable "codex") -Detail "Codex CLI available"
Add-Check -Name "corepack" -Ok (Test-CommandAvailable "corepack") -Detail "Corepack available"
Add-Check -Name "config" -Ok (Test-Path -LiteralPath $ConfigFile) -Detail $ConfigFile
Add-Check -Name "workflows" -Ok (Test-Path -LiteralPath ".\.github\workflows\pr-ci.yml") -Detail "PR CI workflow present"
Add-Check -Name "ai_branch_workflow" -Ok (Test-Path -LiteralPath ".\.github\workflows\ai-branch-ci.yml") -Detail "AI branch workflow present"

$repo = $null
try {
  $repo = git config --get remote.origin.url
  Add-Check -Name "git_remote" -Ok (-not [string]::IsNullOrWhiteSpace($repo)) -Detail ($repo ?? "missing")
} catch {
  Add-Check -Name "git_remote" -Ok $false -Detail $_.Exception.Message
}

if (Test-CommandAvailable "gh") {
  try {
    $auth = gh auth status 2>&1
    Add-Check -Name "gh_auth" -Ok ($LASTEXITCODE -eq 0) -Detail (($auth | Select-Object -First 1) -join "")
  } catch {
    Add-Check -Name "gh_auth" -Ok $false -Detail $_.Exception.Message
  }

  try {
    $prs = gh pr list --limit 10 --json number,title,state,isDraft 2>$null
    Add-Check -Name "open_prs_visible" -Ok ($LASTEXITCODE -eq 0) -Detail "gh pr list returned"
  } catch {
    Add-Check -Name "open_prs_visible" -Ok $false -Detail $_.Exception.Message
  }
}

$requiredCommands = @(
  "corepack pnpm check",
  "pwsh -ExecutionPolicy Bypass -File ./scripts/powershell/validate-powershell.ps1"
)

$summary = @{
  ok = -not ($checks | Where-Object { -not $_.ok })
  modified_remote_settings = $false
  branch_protection_mutated = $false
  required_local_commands = $requiredCommands
  auto_merge_default = $false
  notes = @(
    "Enable GitHub auto-merge manually after branch protection is configured.",
    "Do not use privileged self-hosted runners for public PRs.",
    "Production deployment remains out of scope."
  )
  checks = $checks
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8
} else {
  foreach ($check in $checks) {
    $state = if ($check.ok) { "ok" } else { "warn" }
    Write-Host "[github-readiness] $state $($check.name): $($check.detail)"
  }
  Write-Host "[github-readiness] branch protection was not modified"
}

if (-not $summary.ok) {
  exit 1
}
