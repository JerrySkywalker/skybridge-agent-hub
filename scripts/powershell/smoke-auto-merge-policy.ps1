[CmdletBinding()]
param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "auto-merge-policy.ps1")

$policy = Read-SkyBridgeAutoMergePolicy
$greenChecks = @($policy.required_checks | ForEach-Object {
  [pscustomobject]@{
    name = $_
    status = "COMPLETED"
    conclusion = "SUCCESS"
  }
})

function Assert-Eligibility {
  param(
    [string]$Name,
    [object]$PrInfo,
    [string[]]$ChangedFiles,
    [bool]$ExpectedEligible,
    [string[]]$ExpectedReasons = @()
  )

  $result = Test-SkyBridgeAutoMergeEligibility -PrInfo $PrInfo -ChangedFiles $ChangedFiles -Checks $greenChecks -Policy $policy
  if ([bool]$result.eligible -ne $ExpectedEligible) {
    throw "$Name eligibility expected $ExpectedEligible but got $($result.eligible): $($result.reasons -join ', ')"
  }

  foreach ($reason in $ExpectedReasons) {
    if ($result.reasons -notcontains $reason) {
      throw "$Name expected reason '$reason' but got: $($result.reasons -join ', ')"
    }
  }

  Write-Host "[auto-merge-policy-smoke] $Name eligible=$($result.eligible) risk=$($result.file_risk.risk)"
}

$normalPr = [pscustomobject]@{
  headRefName = "ai/docs-only"
  isDraft = $false
}

Assert-Eligibility `
  -Name "docs-only allowed" `
  -PrInfo $normalPr `
  -ChangedFiles @("docs/automation/example.md", "goals/ready/example.md") `
  -ExpectedEligible $true

Assert-Eligibility `
  -Name "workflow changes blocked" `
  -PrInfo $normalPr `
  -ChangedFiles @(".github/workflows/pr.yml") `
  -ExpectedEligible $false `
  -ExpectedReasons @("blocked_path")

Assert-Eligibility `
  -Name "deploy changes blocked" `
  -PrInfo $normalPr `
  -ChangedFiles @("deploy/docker-compose.prod.yml") `
  -ExpectedEligible $false `
  -ExpectedReasons @("blocked_path")

Assert-Eligibility `
  -Name "secret-like file blocked" `
  -PrInfo $normalPr `
  -ChangedFiles @("docs/examples/api-secret-notes.md") `
  -ExpectedEligible $false `
  -ExpectedReasons @("blocked_path")

$draftPr = [pscustomobject]@{
  headRefName = "ai/draft-docs"
  isDraft = $true
}

Assert-Eligibility `
  -Name "draft PR blocked" `
  -PrInfo $draftPr `
  -ChangedFiles @("docs/automation/example.md") `
  -ExpectedEligible $false `
  -ExpectedReasons @("draft_pr")

Write-Host "[auto-merge-policy-smoke] ok"
