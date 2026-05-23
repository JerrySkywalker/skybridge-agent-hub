[CmdletBinding()]
param(
  [string]$ImageTag = "dry-run"
)

$ErrorActionPreference = "Stop"

function Assert-PathExists {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Required path missing: $Path"
  }
  Write-Host "[release-dry-run] ok path $Path"
}

function Invoke-Checked {
  param(
    [string]$Label,
    [string]$FilePath,
    [string[]]$Arguments
  )
  Write-Host "[release-dry-run] running $Label"
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Label failed with exit code $LASTEXITCODE"
  }
}

$requiredPaths = @(
  ".github/workflows/pr-ci.yml",
  ".github/workflows/ai-branch-ci.yml",
  ".github/workflows/build-image.yml",
  ".github/workflows/deploy-staging.yml",
  ".github/workflows/release.yml",
  "deploy/docker-compose.dev.yml",
  "deploy/docker-compose.test.yml",
  "deploy/docker-compose.prod.yml",
  "deploy/dockerfiles/server.Dockerfile",
  "deploy/dockerfiles/web.Dockerfile",
  "deploy/scripts/staging-dry-run.sh",
  "deploy/scripts/backup.sh",
  "deploy/scripts/rollback.sh",
  "deploy/scripts/notify-deploy.sh",
  "docs/operations/CI_CD_RELEASE_PLAN.md",
  "docs/operations/DEPLOYMENT.md",
  "docs/operations/BACKUP_ROLLBACK.md",
  "docs/operations/RELEASE.md",
  "scripts/powershell/smoke-operator-console.ps1",
  "scripts/powershell/smoke-codex-hook-integration.ps1",
  "scripts/powershell/test-codex-hook-event.ps1"
)

foreach ($path in $requiredPaths) {
  Assert-PathExists -Path $path
}

Invoke-Checked -Label "PowerShell parse validation" -FilePath "pwsh" -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ".\scripts\powershell\validate-powershell.ps1")
Invoke-Checked -Label "docker compose dev config" -FilePath "docker" -Arguments @("compose", "-f", "deploy/docker-compose.dev.yml", "config")
Invoke-Checked -Label "docker compose test config" -FilePath "docker" -Arguments @("compose", "-f", "deploy/docker-compose.test.yml", "config")
Invoke-Checked -Label "docker compose prod config" -FilePath "docker" -Arguments @("compose", "-f", "deploy/docker-compose.prod.yml", "config")

if (Get-Command bash -ErrorAction SilentlyContinue) {
  bash -lc "command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1" *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[release-dry-run] bash is available but Docker Compose is unavailable from bash; skipped staging dry-run shell script"
    Write-Host "[release-dry-run] PowerShell docker compose config checks already passed"
    Write-Host "[release-dry-run] complete"
    exit 0
  }
  Invoke-Checked -Label "staging dry-run" -FilePath "bash" -Arguments @("deploy/scripts/staging-dry-run.sh", $ImageTag)
} else {
  Write-Host "[release-dry-run] bash unavailable; skipped staging dry-run shell script"
}

Write-Host "[release-dry-run] complete"
