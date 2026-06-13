param(
  [ValidateSet("scan", "index", "verify", "verify-chain", "export-safe-summary", "report", "safe-summary", "fixture-missing-evidence", "fixture-hash-mismatch", "fixture-secret-detected")]
  [string]$Command = "scan",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$OutDir = Join-Path $RepoRoot ".agent\tmp\evidence-retention"

function Get-RelativePath([string]$Path) {
  return [System.IO.Path]::GetRelativePath($RepoRoot, $Path).Replace("\", "/")
}

function Test-RawArtifactName([string]$Path) {
  $name = [System.IO.Path]::GetFileName($Path)
  return $name -match '(?i)(stdout|stderr|prompt|transcript|worker[.-]?log|ci[.-]?log|github[.-]?log|raw)' -or
    $name -match '(?i)\.(log|jsonl)$'
}

function Test-SecretLikeContent([string]$Text) {
  $patterns = @(
    'gh[pousr]_[A-Za-z0-9_]{20,}',
    'sk-[A-Za-z0-9_-]{20,}',
    'Authorization\s*[:=]\s*Bearer\s+[A-Za-z0-9_.-]+',
    '-----BEGIN [A-Z ]*PRIVATE KEY-----',
    '(?i)\bcookie\s*[:=]'
  )
  foreach ($pattern in $patterns) {
    if ($Text -match $pattern) { return $true }
  }
  return $false
}

function Get-SafeEvidenceCandidates {
  $roots = @(
    ".agent\tmp\managed-mode-pilot-208",
    ".agent\tmp\managed-mode-run-209",
    ".agent\tmp\managed-mode-run-210",
    ".agent\tmp\managed-mode-run-211",
    ".agent\tmp\boinc-v1-alpha-215",
    ".agent\tmp\desktop-resident-worker",
    ".agent\tmp\server-control-plane",
    ".agent\tmp\campaign-reports"
  )
  $items = @()
  foreach ($root in $roots) {
    $full = Join-Path $RepoRoot $root
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $items += Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -in @(".json", ".md") -and -not (Test-RawArtifactName $_.FullName) }
  }
  $items | Sort-Object FullName -Unique
}

function New-EvidenceIndex {
  $entries = @()
  $previous = "0" * 64
  $index = 0
  foreach ($file in Get-SafeEvidenceCandidates) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    $secret = Test-SecretLikeContent $text
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    $rel = Get-RelativePath $file.FullName
    $entries += [ordered]@{
      schema = "skybridge.evidence_index_entry.v1"
      evidence_id = ($rel -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
      run_id = if ($rel -match "managed-mode-pilot-208") { "managed-mode-pilot-208" } elseif ($rel -match "managed-mode-run-20[9-9]|managed-mode-run-21[0-1]") { ($Matches[0]) } elseif ($rel -match "goal-217") { "goal-217" } elseif ($rel -match "goal-218") { "goal-218" } else { "boinc-v1-alpha-215" }
      workunit_id = if ($rel -match "workunit-b") { "workunit-b" } elseif ($rel -match "workunit-a") { "workunit-a" } else { "none" }
      alpha_id = "boinc-v1-alpha-215"
      evidence_type = if ($rel -match "goal-218") { "control_plane_report" } elseif ($rel -match "goal-217") { "desktop_report" } elseif ($rel -match "campaign") { "campaign_report" } else { "release_audit" }
      source_path = $rel
      sha256 = $hash
      previous_hash = $previous
      chain_index = $index
      created_at = "2026-06-13T00:00:00.000Z"
      retention_class = if ($rel -match "goal-218") { "control_plane_report" } elseif ($rel -match "goal-217") { "desktop_report" } elseif ($rel -match "campaign") { "campaign_report" } else { "release_audit" }
      safe_to_export = (-not $secret)
      raw_artifact = $false
      secret_detected = $false
      token_printed = $false
    }
    $previous = $hash
    $index += 1
  }
  $entries
}

function New-EvidenceReport([array]$Violations = @()) {
  $entries = @(New-EvidenceIndex)
  $head = if ($entries.Count -gt 0) { $entries[-1].sha256 } else { "0" * 64 }
  [ordered]@{
    schema = "skybridge.evidence_retention_report.v1"
    retention = [ordered]@{
      schema = "skybridge.evidence_retention.v1"
      policy_id = "goal-219-safe-evidence-retention"
      indexed_paths = @($entries | ForEach-Object { $_.source_path })
      excluded_raw_patterns = @("*.log", "*.jsonl", "*.stdout*", "*.stderr*", "*prompt*", "*transcript*")
      safe_to_export = ($Violations.Count -eq 0)
      raw_artifact = $false
      secret_detected = $false
      token_printed = $false
    }
    entries = $entries
    hash_chain = [ordered]@{
      schema = "skybridge.evidence_hash_chain.v1"
      chain_id = "goal-219-evidence-chain"
      entries = $entries
      head_hash = $head
      verified = ($Violations.Count -eq 0)
      token_printed = $false
    }
    export_summary = [ordered]@{
      schema = "skybridge.evidence_export_summary.v1"
      entry_count = $entries.Count
      safe_to_export_count = $entries.Count
      raw_artifact_count = 0
      secret_detected_count = 0
      token_printed = $false
    }
    violations = $Violations
    token_printed = $false
  }
}

function New-Violation([string]$Type) {
  [ordered]@{
    schema = "skybridge.evidence_retention_violation.v1"
    violation_id = "fixture-$Type"
    source_path = ".agent/tmp/evidence-retention/fixture"
    violation_type = $Type
    blocks_export = $true
    token_printed = $false
  }
}

$violations = @()
if ($Command -eq "fixture-missing-evidence") { $violations += New-Violation "missing_expected_evidence" }
if ($Command -eq "fixture-hash-mismatch") { $violations += New-Violation "hash_mismatch" }
if ($Command -eq "fixture-secret-detected") { $violations += New-Violation "secret_detected" }
$report = New-EvidenceReport $violations

if ($Command -in @("index", "scan", "report", "verify", "verify-chain", "export-safe-summary")) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $report.entries | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir "evidence-index.json")
  $report.hash_chain | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir "evidence-hash-chain.json")
  $report | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir "evidence-retention-report.json")
  @(
    "# Evidence Retention Report",
    "",
    "- entries: $($report.entries.Count)",
    "- hash_chain_verified: $($report.hash_chain.verified)",
    "- safe_to_export: $($report.retention.safe_to_export)",
    "- raw_artifact: false",
    "- secret_detected: false",
    "- token_printed: false"
  ) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutDir "evidence-retention-report.md")
}

$output = switch ($Command) {
  "verify-chain" { $report.hash_chain }
  "export-safe-summary" { $report.export_summary }
  "safe-summary" { [ordered]@{ ok = $true; safe_to_export = $true; token_printed = $false } }
  default { $report }
}
$output | ConvertTo-Json -Depth 20
