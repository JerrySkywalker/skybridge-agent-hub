[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$workflowRoot = Join-Path $repoRoot ".github\workflows"

if (-not (Test-Path -LiteralPath $workflowRoot -PathType Container)) {
  throw "Workflow directory not found."
}

$workflowFiles = @(
  Get-ChildItem -LiteralPath $workflowRoot -File |
    Where-Object { $_.Name -match '\.ya?ml$' } |
    Sort-Object FullName
)

$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
  param(
    [string]$Rule,
    [string]$File,
    [int]$Line
  )
  $relative = [System.IO.Path]::GetRelativePath($repoRoot, $File) -replace '\\', '/'
  $findings.Add([pscustomobject]@{
    rule = $Rule
    file = $relative
    line = $Line
  }) | Out-Null
}

function Test-Lines {
  param(
    [System.IO.FileInfo]$File,
    [string]$Rule,
    [regex]$Pattern
  )
  $lineNumber = 0
  foreach ($line in Get-Content -LiteralPath $File.FullName) {
    $lineNumber++
    if ($Pattern.IsMatch($line)) {
      Add-Finding -Rule $Rule -File $File.FullName -Line $lineNumber
    }
  }
}

$rules = @(
  @{ id = "checkout_v4_forbidden"; pattern = [regex]'(?i)\bactions/checkout@v4\b' },
  @{ id = "upload_artifact_v4_forbidden"; pattern = [regex]'(?i)\bactions/upload-artifact@v4\b' },
  @{ id = "setup_node_v4_forbidden"; pattern = [regex]'(?i)\bactions/setup-node@v4\b' },
  @{ id = "pnpm_action_setup_v4_forbidden"; pattern = [regex]'(?i)\bpnpm/action-setup@v4\b' },
  @{ id = "unsecure_node_escape_hatch_forbidden"; pattern = [regex]'(?i)\bACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION\b' },
  @{ id = "jerry_domain_forbidden"; pattern = [regex]'(?i)\bjerryskywalker\.space\b' },
  @{ id = "private_ip_prefix_forbidden"; pattern = [regex]'\b43\.138\.' },
  @{ id = "skybridge_private_endpoint_forbidden"; pattern = [regex]'(?i)\bskybridge\.jerryskywalker\.space\b' },
  @{ id = "hermes_private_endpoint_forbidden"; pattern = [regex]'(?i)\bapi\.hermes\.jerryskywalker\.space\b' },
  @{ id = "ssh_private_endpoint_forbidden"; pattern = [regex]'(?i)\bssh\.jerryskywalker\.space\b' },
  @{ id = "dashboard_private_endpoint_forbidden"; pattern = [regex]'(?i)\bdashboard\.jerryskywalker\.space\b' },
  @{ id = "auth_private_endpoint_forbidden"; pattern = [regex]'(?i)\bauth\.jerryskywalker\.space\b' },
  @{ id = "ntfy_private_endpoint_forbidden"; pattern = [regex]'(?i)\bntfy\.jerryskywalker\.space\b' }
)

foreach ($file in $workflowFiles) {
  foreach ($rule in $rules) {
    Test-Lines -File $file -Rule $rule.id -Pattern $rule.pattern
  }
}

$deployWorkflow = Join-Path $workflowRoot "deploy-cloud.yml"
if (-not (Test-Path -LiteralPath $deployWorkflow -PathType Leaf)) {
  Add-Finding -Rule "deploy_cloud_workflow_missing" -File $deployWorkflow -Line 0
} else {
  $deployText = Get-Content -Raw -LiteralPath $deployWorkflow
  $publicApiBasePattern = [regex]'(?m)^\s*PUBLIC_API_BASE:\s*\$\{\{\s*(vars|secrets)\.[A-Za-z_][A-Za-z0-9_]*\s*\}\}\s*$'
  if (-not $publicApiBasePattern.IsMatch($deployText)) {
    Add-Finding -Rule "public_api_base_must_use_vars_or_secrets" -File $deployWorkflow -Line 0
  }
}

$result = [pscustomobject]@{
  ok = ($findings.Count -eq 0)
  schema = "skybridge.github_actions_hygiene_smoke.v1"
  scanned_workflow_count = $workflowFiles.Count
  finding_count = $findings.Count
  findings = @($findings.ToArray())
  required_public_api_base_sources = @("vars.SKYBRIDGE_PUBLIC_API_BASE", "secrets.<name>")
  sanitized_findings = $true
  token_printed = $false
}

if ($Json) {
  $result | ConvertTo-Json -Depth 8
} else {
  if ($result.ok) {
    "PASS github actions hygiene smoke"
    "scanned_workflow_count=$($result.scanned_workflow_count)"
    "finding_count=0"
    "token_printed=false"
  } else {
    "FAIL github actions hygiene smoke"
    "scanned_workflow_count=$($result.scanned_workflow_count)"
    "finding_count=$($result.finding_count)"
    foreach ($finding in $result.findings) {
      "$($finding.file):$($finding.line) [$($finding.rule)] [redacted-finding]"
    }
    "token_printed=false"
  }
}

if (-not $result.ok) { exit 1 }
