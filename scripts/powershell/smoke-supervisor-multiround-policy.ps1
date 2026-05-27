[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-supervisor-multiround-policy-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
  $fixture = @{
    control = @{ state = "paused"; stop_requested = $false }
    workers = @(@{ worker_id = "policy-worker"; status = "online" })
    proposals = @(
      @{ proposal_id = "safe-docs"; dedupe_key = "safe-docs"; risk = "low"; task_type = "docs"; status = "proposed"; required_capabilities = @("codex"); expected_files = @("docs/dev/example.md"); policy_decision = "accepted_for_execution" },
      @{ proposal_id = "unsafe-deploy"; dedupe_key = "unsafe-deploy"; risk = "high"; task_type = "deploy"; status = "proposed"; required_capabilities = @("codex"); expected_files = @("deploy/docker-compose.prod.yml"); policy_decision = "rejected_high_risk" }
    )
  }
  $file = Join-Path $tempDir "policy.json"
  $fixture | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $file -Encoding UTF8
  $result = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-supervisor-policy.ps1 -FixtureFile $file -Json | ConvertFrom-Json
  if ($result.selected_proposal_id -ne "safe-docs") { throw "Expected safe docs proposal selection." }
  if ($result.decision.decision -ne "continue") { throw "Expected continue decision." }
  $summary = @{ ok = $true; selected = $result.selected_proposal_id; decision = $result.decision.decision; token_printed = $false }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 } else { $summary | Format-List }
} finally {
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
