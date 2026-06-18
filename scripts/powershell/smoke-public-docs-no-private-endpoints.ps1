[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot

$excludedPathPattern = '(^|[\\/])(\.git|\.agent|node_modules|dist|build|coverage|\.turbo)([\\/]|$)'
$excludedFilePattern = '(?i)(^|[\\/])(\.env|.*\.env(\..*)?|.*\.local(\..*)?|.*secret.*|.*token.*)([\\/]|$)'
$rootDocNames = @(
  "README.md",
  "ARCHITECTURE.md",
  "DEVELOPMENT.md",
  "SECURITY.md",
  "CONTRIBUTING.md",
  "ROADMAP.md",
  "AGENTS.md"
)

$privatePatterns = @(
  @{ id = "jerryskywalker_domain"; pattern = '(?i)jerryskywalker\.space' },
  @{ id = "private_ip_prefix"; pattern = '43\.138\.' },
  @{ id = "private_deploy_host_alias"; pattern = '(?i)\bbeijing\b' },
  @{ id = "private_provider_name"; pattern = '(?i)\btencent\b|TENCENT_' },
  @{ id = "private_region_or_host_alias"; pattern = '(?i)\b(lax|novix)\b' },
  @{ id = "private_hermes_placeholder_misuse"; pattern = '(?i)api\.hermes\.jerryskywalker\.space' },
  @{ id = "private_skybridge_placeholder_misuse"; pattern = '(?i)skybridge\.jerryskywalker\.space' },
  @{ id = "private_ssh_placeholder_misuse"; pattern = '(?i)ssh\.jerryskywalker\.space' },
  @{ id = "private_dashboard_placeholder_misuse"; pattern = '(?i)dashboard\.jerryskywalker\.space' },
  @{ id = "private_auth_placeholder_misuse"; pattern = '(?i)auth\.jerryskywalker\.space' },
  @{ id = "private_ntfy_placeholder_misuse"; pattern = '(?i)ntfy\.jerryskywalker\.space' }
)

function Test-PublicDocsOrExample {
  param([string]$Path)
  $normalized = $Path -replace '\\', '/'
  $name = Split-Path -Leaf $Path
  if ($rootDocNames -contains $normalized) { return $true }
  if ($normalized -match '^(docs|examples|fixtures|config|deploy)/') { return $true }
  if ($name -match '(?i)(^|[._-])example([._-]|$)' -or $name -match '(?i)\.example\.') { return $true }
  return $false
}

$files = @(
  git ls-files |
    Where-Object { $_ -and ($_ -notmatch $excludedPathPattern) -and ($_ -notmatch $excludedFilePattern) } |
    Where-Object { Test-PublicDocsOrExample -Path $_ }
)

$findings = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
  foreach ($rule in $privatePatterns) {
    if ($file -match $rule.pattern) {
      $findings.Add([pscustomobject]@{
        file = $file
        line = 0
        rule = $rule.id
        text = "[path]"
      }) | Out-Null
    }
  }

  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
  $lineNumber = 0
  foreach ($line in Get-Content -LiteralPath $file) {
    $lineNumber++
    foreach ($rule in $privatePatterns) {
      if ($line -match $rule.pattern) {
        $snippet = $line.Trim()
        if ($snippet.Length -gt 180) { $snippet = $snippet.Substring(0, 180) }
        $findings.Add([pscustomobject]@{
          file = $file
          line = $lineNumber
          rule = $rule.id
          text = $snippet
        }) | Out-Null
      }
    }
  }
}

$result = [pscustomobject]@{
  ok = ($findings.Count -eq 0)
  schema = "skybridge.public_docs_private_endpoint_smoke.v1"
  scanned_files = $files.Count
  finding_count = $findings.Count
  findings = @($findings.ToArray())
  allowed_placeholders = @(
    "https://api.hermes.example.com",
    "https://skybridge.example.com",
    "<PRIVATE_HERMES_API_BASE>",
    "<PRIVATE_SKYBRIDGE_API_BASE>",
    "<PRIVATE_DEPLOY_HOST>"
  )
  skipped = @(".agent", ".git", "node_modules", "dist", "build", "coverage", "local env/secret/token files")
  token_printed = $false
}

if ($Json) {
  $result | ConvertTo-Json -Depth 8
} else {
  if ($result.ok) {
    "PASS public docs private endpoint smoke"
    "scanned_files=$($result.scanned_files)"
    "finding_count=0"
    "token_printed=false"
  } else {
    "FAIL public docs private endpoint smoke"
    "scanned_files=$($result.scanned_files)"
    "finding_count=$($result.finding_count)"
    foreach ($finding in $result.findings) {
      "$($finding.file):$($finding.line) [$($finding.rule)] $($finding.text)"
    }
  }
}

if (-not $result.ok) { exit 1 }
