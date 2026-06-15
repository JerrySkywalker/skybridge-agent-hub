[CmdletBinding()]
param(
  [ValidateSet("status", "scan-workflows", "classify-tag-triggers", "publish-side-effect-report", "tag-safety-gate", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$WorkflowRoot = Join-Path $RepoRoot ".github\workflows"
$ReportDir = Join-Path $RepoRoot ".agent\tmp\release-guard"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 60
  if (Test-UnsafeText $text) { throw "Refusing unsafe release guard JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe release guard markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Get-WorkflowFiles {
  if (-not (Test-Path -LiteralPath $WorkflowRoot)) { return @() }
  @(Get-ChildItem -LiteralPath $WorkflowRoot -Recurse -File -Include *.yml,*.yaml | Sort-Object FullName)
}

function Test-TagTrigger([string]$Text) {
  return $Text -match "(?m)^\s*tags\s*:" -or $Text -match "(?m)^\s*-\s*['""]?v\*['""]?\s*$" -or $Text -match "refs/tags|github\.ref_type\s*==\s*['""]tag"
}

function Test-ReleaseTrigger([string]$Text) {
  return $Text -match "(?m)^\s*release\s*:" -or $Text -match "github\.event_name\s*==\s*['""]release"
}

function Get-WorkflowEffect([System.IO.FileInfo]$File) {
  $text = Get-Content -Raw -LiteralPath $File.FullName
  $relative = [System.IO.Path]::GetRelativePath($RepoRoot, $File.FullName).Replace("\", "/")
  $effects = @()
  if ($text -match "docker/(build-push-action|login-action)|ghcr\.io|packages:\s*write|push:\s*\$\{\{") { $effects += "docker_publish_or_registry_write" }
  if ($text -match "actions/upload-artifact|upload-artifact@") { $effects += "artifact_upload" }
  if ($text -match "softprops/action-gh-release|gh\s+release|actions/create-release|repos/.*/releases|createRelease") { $effects += "github_release_creation" }
  if ($text -match "npm\s+publish|pnpm\s+publish|yarn\s+npm\s+publish|twine\s+upload|cargo\s+publish") { $effects += "package_publish" }
  if ($text -match "workflow_dispatch\s*:") { $effects += "workflow_dispatch" }
  if ($effects.Count -eq 0) { $effects += "validation_only" }
  $secretNames = @()
  foreach ($m in [regex]::Matches($text, "secrets\.([A-Za-z_][A-Za-z0-9_]*)")) {
    $secretNames += $m.Groups[1].Value
  }
  $permissionLines = @([regex]::Matches($text, "(?m)^\s{2,}[a-zA-Z_-]+\s*:\s*(read|write|none)\s*$") | ForEach-Object { $_.Value.Trim() })
  [pscustomobject]@{
    schema = "skybridge.workflow_side_effect.v1"
    workflow = $relative
    tag_triggered = Test-TagTrigger $text
    release_triggered = Test-ReleaseTrigger $text
    workflow_dispatch = ($text -match "workflow_dispatch\s*:")
    side_effects = @($effects | Select-Object -Unique)
    docker_publish = ($effects -contains "docker_publish_or_registry_write")
    artifact_upload = ($effects -contains "artifact_upload")
    github_release_creation = ($effects -contains "github_release_creation")
    package_publish = ($effects -contains "package_publish")
    secret_names_referenced = @($secretNames | Select-Object -Unique | Sort-Object)
    permissions = $permissionLines
    values_read = $false
    workflow_mutated = $false
    token_printed = $false
  }
}

function Get-Scan {
  $effects = @(Get-WorkflowFiles | ForEach-Object { Get-WorkflowEffect $_ })
  $unclassified = @($effects | Where-Object {
    ($_.tag_triggered -or $_.release_triggered) -and
    $_.side_effects.Count -eq 1 -and
    $_.side_effects[0] -eq "validation_only" -and
    $_.workflow_dispatch -eq $false
  })
  [pscustomobject]@{
    schema = "skybridge.release_workflow_guard.v1"
    status = $(if ($unclassified.Count -eq 0) { "classified" } else { "unknown" })
    workflow_count = $effects.Count
    effects = $effects
    unclassified_workflows = @($unclassified.workflow)
    manual_github_release_creation_allowed = $false
    manual_artifact_upload_allowed = $false
    workflow_values_read = $false
    workflow_mutated = $false
    token_printed = $false
  }
}

function Get-Policy {
  $scan = Get-Scan
  [pscustomobject]@{
    schema = "skybridge.tag_publish_policy.v1"
    status = $scan.status
    tags_may_trigger_existing_workflows = $true
    manual_github_release_creation_allowed = $false
    manual_artifact_upload_allowed = $false
    classified_tag_side_effects = @($scan.effects | Where-Object { $_.tag_triggered } | ForEach-Object {
      [pscustomobject]@{ workflow = $_.workflow; side_effects = $_.side_effects; token_printed = $false }
    })
    acceptable_existing_workflow_side_effects = @("release validation", "release artifacts uploaded by workflow", "GHCR image publish by workflow", "staging dry-run on main")
    token_printed = $false
  }
}

function Get-TagGate {
  $scan = Get-Scan
  $tagEffects = @($scan.effects | Where-Object { $_.tag_triggered })
  $releaseCreation = @($tagEffects | Where-Object { $_.github_release_creation })
  $unsafe = @()
  if ($scan.status -ne "classified") { $unsafe += "release_workflow_side_effects_unclassified" }
  if ($releaseCreation.Count -gt 0) { $unsafe += "tag_workflow_can_create_github_release" }
  [pscustomobject]@{
    schema = "skybridge.tag_safety_gate.v1"
    gate = $(if ($unsafe.Count -eq 0) { "passed" } else { "blocked" })
    tag_allowed_after_merge_smokes = ($unsafe.Count -eq 0)
    blockers = $unsafe
    existing_tag_workflow_side_effects = @($tagEffects | ForEach-Object { [pscustomobject]@{ workflow = $_.workflow; side_effects = $_.side_effects; token_printed = $false } })
    manual_github_release_creation_allowed = $false
    manual_artifact_upload_allowed = $false
    workflow_values_read = $false
    token_printed = $false
  }
}

function Publish-Report {
  $scan = Get-Scan
  $policy = Get-Policy
  $gate = Get-TagGate
  Write-SafeJson (Join-Path $ReportDir "workflow-side-effects.json") $scan
  Write-SafeJson (Join-Path $ReportDir "tag-safety-gate.json") $gate
  $lines = @(
    "# Release Workflow Side Effects",
    "",
    "- schema: skybridge.release_workflow_guard.v1",
    "- status: $($scan.status)",
    "- workflow_count: $($scan.workflow_count)",
    "- manual_github_release_creation_allowed=false",
    "- manual_artifact_upload_allowed=false",
    "- workflow_values_read=false",
    "- token_printed=false",
    "",
    "## Tag-triggered workflows"
  )
  foreach ($effect in @($scan.effects | Where-Object { $_.tag_triggered })) {
    $lines += "- $($effect.workflow): $(@($effect.side_effects) -join ', ')"
  }
  if (@($scan.effects | Where-Object { $_.tag_triggered }).Count -eq 0) { $lines += "- none" }
  Write-SafeMarkdown (Join-Path $ReportDir "workflow-side-effects.md") $lines
  [pscustomobject]@{
    schema = "skybridge.release_workflow_guard.v1"
    status = $scan.status
    policy = $policy
    gate = $gate
    report_paths = @(
      ".agent/tmp/release-guard/workflow-side-effects.json",
      ".agent/tmp/release-guard/workflow-side-effects.md",
      ".agent/tmp/release-guard/tag-safety-gate.json"
    )
    token_printed = $false
  }
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.release_workflow_guard.v1"; status = "ready"; workflow_root = ".github/workflows"; token_printed = $false } }
  "scan-workflows" { Get-Scan }
  "classify-tag-triggers" { Get-Policy }
  "publish-side-effect-report" { Publish-Report }
  "tag-safety-gate" { $g = Get-TagGate; Write-SafeJson (Join-Path $ReportDir "tag-safety-gate.json") $g; $g }
  "safe-summary" { $g = Get-TagGate; [pscustomobject]@{ ok = ($g.gate -eq "passed"); gate = $g.gate; manual_github_release_creation_allowed = $false; manual_artifact_upload_allowed = $false; token_printed = $false } }
  "report" { Publish-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 70 } else { $Result | Format-List | Out-String }
