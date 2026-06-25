[CmdletBinding()]
param(
  [ValidateSet("status", "local", "cloud", "tag", "audit", "stop-hook-diagnose", "safe-summary")]
  [string]$Command = "status",
  [string]$ExpectedTag = "v0.1.0-bootstrap-alpha-rc1",
  [string]$ExpectedCommit = "4473257548bd0fc26e05002d968f8525b37bac8b",
  [string]$ExpectedImageRef = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-4473257548bd0fc26e05002d968f8525b37bac8b",
  [string]$ExpectedCloudCommit = "",
  [string]$ExpectedCloudImageRef = "",
  [string]$ApiBase = "",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$ReportDir = ".agent/tmp/bootstrap-alpha-rc"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

$Schema = "skybridge.bootstrap_alpha_rc1_handoff.v1"
$ResolvedExpectedCloudCommit = if ([string]::IsNullOrWhiteSpace($ExpectedCloudCommit)) { $ExpectedCommit } else { $ExpectedCloudCommit }
$ResolvedExpectedCloudImageRef = if ([string]::IsNullOrWhiteSpace($ExpectedCloudImageRef)) { $ExpectedImageRef } else { $ExpectedCloudImageRef }
$PostTagAuditMarkdown = ".agent/tmp/bootstrap-alpha-rc/bootstrap-alpha-rc1-post-tag-audit.md"
$PostTagAuditJson = ".agent/tmp/bootstrap-alpha-rc/bootstrap-alpha-rc1-post-tag-audit.json"

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Get-Bool {
  param($Object, [string]$Name, [bool]$Default = $false)
  $value = Get-Prop -Object $Object -Name $Name -Default $Default
  if ($null -eq $value) { return $Default }
  return [bool]$value
}

function ConvertTo-SafeText {
  param([AllowNull()][string]$Text, [int]$MaxLength = 260)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = [string]$Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+\S+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{12,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{12,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe -replace "(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", "[redacted-private-key]"
  $safe = $safe.Trim()
  if ($safe.Length -gt $MaxLength) { return ($safe.Substring(0, $MaxLength) + "...[truncated]") }
  return $safe
}

function Test-UnsafeText {
  param([AllowNull()][string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed\s*[:=]\s*true|token_printed"\s*:\s*true'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer\s+\S+|bearer\s+[A-Za-z0-9._-]{20,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|cookie\s*[:=]\s*\S+|password\s*[:=]\s*\S+|api[_-]?key\s*[:=]\s*\S+|raw_stdout(?!_included)|raw_stderr(?!_included)|raw_prompt(?!_included)|process environment dump|env_dump|$tokenTrue"
}

function Test-RelativeFile {
  param([string]$Path)
  Test-Path -LiteralPath (Join-Path $RepoRoot $Path) -PathType Leaf
}

function Test-ApiConfigured {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  if ($Value -match "(?i)example\.com|^<.*>$") { return $false }
  try {
    $uri = [System.Uri]::new($Value)
    return ($uri.IsAbsoluteUri -and $uri.Scheme -in @("http", "https"))
  } catch {
    return $false
  }
}

function Invoke-ChildJson {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowNonZero
  )
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | Out-String).Trim())
  $parsed = $null
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    try { $parsed = $text | ConvertFrom-Json } catch {}
  }
  if ($exitCode -eq 0 -and $null -ne $parsed) { return $parsed }
  if ($AllowNonZero -and $null -ne $parsed) { return $parsed }
  return [pscustomobject]@{
    ok = $false
    unavailable = $true
    error_summary = ConvertTo-SafeText -Text $text
    token_printed = $false
  }
}

function Get-PackageScripts {
  $packagePath = Join-Path $RepoRoot "package.json"
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return @{} }
  (Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json).scripts
}

function Get-LocalChecks {
  $requiredDocs = @(
    "docs/release/BOOTSTRAP_ALPHA_RC1_HANDOFF.md",
    "docs/dev/CODEX_STOP_HOOK_HYGIENE.md",
    "docs/release/BOOTSTRAP_ALPHA_RC_RELEASE_NOTES.md",
    "docs/release/BOOTSTRAP_ALPHA_RC_RUNBOOK.md",
    "docs/release/BOOTSTRAP_ALPHA_DISABLED_FEATURES.md",
    "docs/release/BOOTSTRAP_ALPHA_TAG_PLAN.md"
  )
  $requiredScripts = @(
    "scripts/powershell/skybridge-bootstrap-alpha-rc1-handoff.ps1",
    "scripts/powershell/skybridge-bootstrap-alpha-rc-gate.ps1",
    "scripts/powershell/skybridge-stop-hook-diagnostics.ps1",
    "scripts/powershell/smoke-bootstrap-alpha-rc1-handoff.ps1",
    "scripts/powershell/smoke-codex-stop-hook-hygiene.ps1",
    "scripts/powershell/smoke-bootstrap-alpha-rc1-tag-check.ps1"
  )
  $requiredPackageScripts = @(
    "smoke:bootstrap-alpha-rc1-handoff",
    "smoke:bootstrap-alpha-rc1-handoff-local",
    "smoke:bootstrap-alpha-rc1-handoff-report",
    "smoke:codex-stop-hook-hygiene",
    "smoke:bootstrap-alpha-rc1-tag-check"
  )

  $docResults = foreach ($doc in $requiredDocs) {
    [pscustomobject]@{ path = $doc; exists = Test-RelativeFile $doc }
  }
  $scriptResults = foreach ($script in $requiredScripts) {
    [pscustomobject]@{ path = $script; exists = Test-RelativeFile $script }
  }
  $scripts = Get-PackageScripts
  $packageScriptResults = foreach ($scriptName in $requiredPackageScripts) {
    [pscustomobject]@{ name = $scriptName; exists = [bool]($scripts.PSObject.Properties.Name -contains $scriptName) }
  }

  $docSecretFindings = @()
  foreach ($doc in $requiredDocs) {
    $path = Join-Path $RepoRoot $doc
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $text = Get-Content -Raw -LiteralPath $path
      if (Test-UnsafeText -Text $text) { $docSecretFindings += [pscustomobject]@{ path = $doc; issue = "unsafe_secret_like_text" } }
    }
  }

  $handoffDocPresent = Test-RelativeFile "docs/release/BOOTSTRAP_ALPHA_RC1_HANDOFF.md"
  $disabledFeaturesPresent = Test-RelativeFile "docs/release/BOOTSTRAP_ALPHA_DISABLED_FEATURES.md"
  $postTagAuditPresent = ((Test-RelativeFile $PostTagAuditMarkdown) -and (Test-RelativeFile $PostTagAuditJson))
  $rcGateLocal = Invoke-ChildJson -Arguments @("-File", (Join-Path $PSScriptRoot "skybridge-bootstrap-alpha-rc-gate.ps1"), "-Command", "local", "-Json") -AllowNonZero

  $missingDocs = @($docResults | Where-Object { -not $_.exists } | ForEach-Object { $_.path })
  $missingScripts = @($scriptResults | Where-Object { -not $_.exists } | ForEach-Object { $_.path })
  $missingPackageScripts = @($packageScriptResults | Where-Object { -not $_.exists } | ForEach-Object { $_.name })
  $blockers = @()
  $warnings = @()
  if ($missingDocs.Count -gt 0) { $blockers += "missing_required_docs" }
  if ($missingScripts.Count -gt 0) { $blockers += "missing_required_scripts" }
  if ($missingPackageScripts.Count -gt 0) { $blockers += "missing_required_package_scripts" }
  if ($docSecretFindings.Count -gt 0) { $blockers += "unsafe_secret_like_text_in_handoff_docs" }
  if (-not $postTagAuditPresent) { $warnings += "post_tag_audit_report_not_present_in_local_workspace" }
  if (-not [bool](Get-Bool -Object $rcGateLocal -Name "ok")) { $blockers += "rc_gate_local_not_ok" }

  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    status = if ($blockers.Count -eq 0 -and $warnings.Count -eq 0) { "pass" } elseif ($blockers.Count -eq 0) { "warning" } else { "blocked" }
    required_docs = $docResults
    required_scripts = $scriptResults
    required_package_scripts = $packageScriptResults
    missing_docs = @($missingDocs)
    missing_scripts = @($missingScripts)
    missing_package_scripts = @($missingPackageScripts)
    doc_secret_findings = @($docSecretFindings)
    handoff_doc_present = $handoffDocPresent
    disabled_features_present = $disabledFeaturesPresent
    post_tag_audit_present = $postTagAuditPresent
    rc_gate_local_ok = [bool](Get-Bool -Object $rcGateLocal -Name "ok")
    blockers = @($blockers)
    warnings = @($warnings)
    token_printed = $false
  }
}

function Get-TagChecks {
  $localTag = ((git tag --list $ExpectedTag 2>$null | Out-String).Trim())
  $tagExists = -not [string]::IsNullOrWhiteSpace($localTag)
  $tagType = ""
  $tagCommit = ""
  $tagObject = ""
  $tagSubject = ""
  if ($tagExists) {
    try { $tagType = ((git cat-file -t $ExpectedTag 2>$null | Out-String).Trim()) } catch {}
    try { $tagCommit = ((git rev-list -n 1 $ExpectedTag 2>$null | Out-String).Trim()) } catch {}
    try {
      $ref = ((git for-each-ref "refs/tags/$ExpectedTag" --format="%(objectname)|%(subject)" 2>$null | Out-String).Trim())
      if ($ref -match "^(?<object>[^|]+)\|(?<subject>.*)$") {
        $tagObject = $Matches.object
        $tagSubject = $Matches.subject
      }
    } catch {}
  }

  $originAvailable = $false
  $originTagVerified = $false
  $originTagObject = ""
  $originPeeledCommit = ""
  $originWarning = @()
  try {
    $remote = @(& git ls-remote --tags origin "refs/tags/$ExpectedTag*" 2>$null)
    if ($LASTEXITCODE -eq 0) {
      $originAvailable = $true
      foreach ($line in $remote) {
        if ($line -match "^([0-9a-f]{40})\s+refs/tags/$([regex]::Escape($ExpectedTag))$") { $originTagObject = $Matches[1] }
        if ($line -match "^([0-9a-f]{40})\s+refs/tags/$([regex]::Escape($ExpectedTag))\^\{\}$") { $originPeeledCommit = $Matches[1] }
      }
      $originTagVerified = ($originPeeledCommit -eq $ExpectedCommit)
    }
  } catch {
    $originWarning += "origin_tag_lookup_unavailable"
  }
  if ($originAvailable -and -not $originTagVerified) { $originWarning += "origin_tag_not_verified" }
  if (-not $originAvailable) { $originWarning += "origin_tag_lookup_unavailable" }

  $blockers = @()
  if (-not $tagExists) { $blockers += "expected_tag_missing_local" }
  if ($tagExists -and $tagType -ne "tag") { $blockers += "expected_tag_not_annotated" }
  if ($tagExists -and $tagCommit -ne $ExpectedCommit) { $blockers += "expected_tag_commit_mismatch" }

  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    status = if ($blockers.Count -eq 0 -and $originWarning.Count -eq 0) { "pass" } elseif ($blockers.Count -eq 0) { "warning" } else { "blocked" }
    tag_name = $ExpectedTag
    tag_exists_local = $tagExists
    tag_type = $tagType
    tag_annotated = ($tagType -eq "tag")
    tag_target_commit = $tagCommit
    tag_object_id = $tagObject
    tag_subject = $tagSubject
    tag_verified_local = ($tagExists -and $tagType -eq "tag" -and $tagCommit -eq $ExpectedCommit)
    origin_lookup_available = $originAvailable
    tag_verified_origin_if_available = $originTagVerified
    origin_tag_object_id = $originTagObject
    origin_peeled_commit = $originPeeledCommit
    blockers = @($blockers)
    warnings = @($originWarning)
    token_printed = $false
  }
}

function Get-CloudChecks {
  if (-not (Test-ApiConfigured -Value $ApiBase)) {
    return [pscustomobject]@{
      ok = $false
      status = "skipped"
      skipped = $true
      skip_reason = "api_base_not_configured"
      cloud_version_ok = $false
      image_ref_ok = $false
      rc_gate_ok = $false
      blockers = @()
      warnings = @("cloud_checks_skipped_api_base_not_configured")
      token_printed = $false
    }
  }

  $blockers = @()
  $warnings = @()
  $version = $null
  try {
    $version = Invoke-RestMethod -Method GET -Uri "$($ApiBase.TrimEnd('/'))/v1/version" -TimeoutSec 30
  } catch {
    $blockers += "cloud_version_unreachable"
  }
  $versionReachable = ($null -ne $version)
  $commitOk = ($versionReachable -and [string](Get-Prop -Object $version -Name "commit_sha") -eq $ResolvedExpectedCloudCommit)
  $imageOk = ($versionReachable -and [string](Get-Prop -Object $version -Name "image_ref") -eq $ResolvedExpectedCloudImageRef)
  if ($versionReachable -and -not $commitOk) { $blockers += "cloud_commit_mismatch" }
  if ($versionReachable -and -not $imageOk) { $blockers += "cloud_image_ref_mismatch" }

  $parity = Invoke-ChildJson -Arguments @("-File", (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1"), "-ApiBase", $ApiBase, "-Json") -AllowNonZero
  $parityOk = [bool](Get-Bool -Object $parity -Name "ok")
  if (-not $parityOk) { $blockers += "cloud_parity_not_ok" }

  $rcGate = Invoke-ChildJson -Arguments @(
    "-File", (Join-Path $PSScriptRoot "skybridge-bootstrap-alpha-rc-gate.ps1"),
    "-Command", "audit",
    "-ApiBase", $ApiBase,
    "-ExpectedCommit", $ResolvedExpectedCloudCommit,
    "-ExpectedImageRef", $ResolvedExpectedCloudImageRef,
    "-ExpectedTagTargetCommit", $ExpectedCommit,
    "-Json"
  ) -AllowNonZero
  $rcGateOk = [bool](Get-Bool -Object $rcGate -Name "ok")
  if (-not $rcGateOk) { $blockers += "rc_gate_not_ok" }
  foreach ($warning in @((Get-Prop -Object $rcGate -Name "warnings" -Default @()))) {
    if (-not [string]::IsNullOrWhiteSpace([string]$warning)) { $warnings += [string]$warning }
  }

  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    status = if ($blockers.Count -eq 0 -and $warnings.Count -eq 0) { "pass" } elseif ($blockers.Count -eq 0) { "warning" } else { "blocked" }
    skipped = $false
    version_reachable = $versionReachable
    cloud_version_ok = ($commitOk -and $imageOk)
    commit_sha = if ($versionReachable) { [string](Get-Prop -Object $version -Name "commit_sha") } else { "" }
    image_ref = if ($versionReachable) { [string](Get-Prop -Object $version -Name "image_ref") } else { "" }
    image_ref_ok = $imageOk
    parity_ok = $parityOk
    parity_status = [string](Get-Prop -Object $parity -Name "status" -Default (Get-Prop -Object $parity -Name "deployment_parity_status" -Default "unknown"))
    parity_missing_routes = @((Get-Prop -Object $parity -Name "missing_routes" -Default @()) | ForEach-Object { [string]$_ })
    rc_gate_ok = $rcGateOk
    rc_gate_status = [string](Get-Prop -Object $rcGate -Name "status" -Default "unknown")
    rc_gate_release_candidate_ready = [bool](Get-Bool -Object $rcGate -Name "release_candidate_ready")
    live_evidence = Get-Prop -Object $rcGate -Name "live_evidence"
    blockers = @($blockers)
    warnings = @($warnings | Select-Object -Unique)
    token_printed = $false
  }
}

function Get-StopHookDiagnosis {
  $hooksExamplePath = Join-Path $RepoRoot "config/codex/hooks.example.json"
  $repoStopHookFound = $false
  $repoStopHookMaxTimeout = $null
  $repoStopHookCommands = @()
  $repoHookTimeoutRisk = $false
  $repoHookCloudRisk = $false

  if (Test-Path -LiteralPath $hooksExamplePath -PathType Leaf) {
    try {
      $hooks = Get-Content -Raw -LiteralPath $hooksExamplePath | ConvertFrom-Json
      $stopEntries = @($hooks.hooks.Stop)
      foreach ($entry in $stopEntries) {
        foreach ($hook in @($entry.hooks)) {
          $repoStopHookFound = $true
          $timeout = 0
          if ($hook.PSObject.Properties.Name -contains "timeout") { $timeout = [int]$hook.timeout }
          if ($null -eq $repoStopHookMaxTimeout -or $timeout -gt $repoStopHookMaxTimeout) { $repoStopHookMaxTimeout = $timeout }
          $command = [string]$hook.command
          if (-not [string]::IsNullOrWhiteSpace($command)) { $repoStopHookCommands += $command }
          if ($timeout -gt 30) { $repoHookTimeoutRisk = $true }
          if ($command -match "(?i)rc-gate|cloud|deploy|matlab|codex\s+exec|pnpm\s+check|just\s+check") { $repoHookCloudRisk = $true }
        }
      }
    } catch {
      $repoHookTimeoutRisk = $true
    }
  }

  $package = Get-PackageScripts
  $packageStopHookScripts = @(
    $package.PSObject.Properties |
      Where-Object {
        $_.Name -match "(?i)stop.*hook|hook.*stop" -and
        $_.Name -notmatch "^(?i)smoke:" -and
        [string]$_.Value -notmatch "(?i)smoke-"
      } |
      ForEach-Object { $_.Name }
  )
  $repoDiagnostics = Invoke-ChildJson -Arguments @("-File", (Join-Path $PSScriptRoot "skybridge-stop-hook-diagnostics.ps1"), "-Command", "analyze-timeout", "-Json") -AllowNonZero

  $status = "no_repo_hook_found"
  $summary = "No repository-controlled Stop hook was found; the observed 30 second timeout is not classified as a repository script failure."
  if ($repoStopHookFound -and (-not $repoHookTimeoutRisk) -and (-not $repoHookCloudRisk) -and $packageStopHookScripts.Count -eq 0) {
    $status = "local_codex_hook_not_repo_controlled"
    $summary = "Repository example Stop hook is bounded and does not explain the observed 30 second host timeout; local Codex hook configuration was not read or mutated."
  } elseif ($repoStopHookFound -and ($repoHookTimeoutRisk -or $repoHookCloudRisk)) {
    $status = "repo_hook_timeout_risk"
    $summary = "A repository-controlled Stop hook may exceed the safe hook budget or call heavy workflows."
  }

  [pscustomobject]@{
    ok = ($status -in @("no_repo_hook_found", "repo_hook_ok", "local_codex_hook_not_repo_controlled"))
    status = if ($status -eq "repo_hook_timeout_risk") { "warning" } else { "pass" }
    stop_hook_status = $status
    stop_hook_summary = $summary
    repo_stop_hook_found = $repoStopHookFound
    repo_stop_hook_timeout_seconds = $repoStopHookMaxTimeout
    repo_stop_hook_timeout_risk = $repoHookTimeoutRisk
    repo_stop_hook_cloud_or_full_suite_risk = $repoHookCloudRisk
    repo_stop_hook_command_count = @($repoStopHookCommands).Count
    package_stop_hook_script_count = @($packageStopHookScripts).Count
    raw_hook_logs_read = $false
    local_codex_config_read = $false
    local_codex_config_mutated = $false
    diagnostic_script_ok = [bool](Get-Bool -Object $repoDiagnostics -Name "token_printed") -eq $false
    blockers = @()
    warnings = @(if ($status -eq "repo_hook_timeout_risk") { "repo_hook_timeout_risk" })
    token_printed = $false
  }
}

function New-MarkdownReport {
  param($Report)
  $lines = @(
    "# Bootstrap Alpha RC1 Handoff",
    "",
    "- schema: $($Report.schema)",
    "- status: $($Report.status)",
    "- ok: $($Report.ok)",
    "- tag_name: $($Report.tag_name)",
    "- tag_target_commit: $($Report.tag_target_commit)",
    "- tag_verified_local: $($Report.tag_verified_local)",
    "- tag_verified_origin_if_available: $($Report.tag_verified_origin_if_available)",
    "- cloud_version_ok: $($Report.cloud_version_ok)",
    "- image_ref_ok: $($Report.image_ref_ok)",
    "- rc_gate_ok: $($Report.rc_gate_ok)",
    "- post_tag_audit_present: $($Report.post_tag_audit_present)",
    "- handoff_doc_present: $($Report.handoff_doc_present)",
    "- disabled_features_present: $($Report.disabled_features_present)",
    "- github_release_created: false",
    "- task_claimed: false",
    "- execution_started: false",
    "- codex_run_called: false",
    "- matlab_run_called: false",
    "- worker_loop_started: false",
    "- project_control_unpaused: false",
    "- stop_hook_status: $($Report.stop_hook_status)",
    "- stop_hook_summary: $(ConvertTo-SafeText -Text $Report.stop_hook_summary -MaxLength 320)",
    "- token_printed: false",
    "",
    "## Audit Notes",
    "",
    "- RC1 tag and deploy references are read-only handoff facts.",
    "- This report does not include raw logs, raw prompts, stdout/stderr dumps, token values, credentials, cookies, provider auth headers, proxy profiles, or process-environment snapshots."
  )
  ($lines -join [Environment]::NewLine)
}

function Write-HandoffReports {
  param($Report)
  $dir = Join-Path $RepoRoot $ReportDir
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $jsonPath = Join-Path $dir "bootstrap-alpha-rc1-handoff.json"
  $mdPath = Join-Path $dir "bootstrap-alpha-rc1-handoff.md"
  $json = $Report | ConvertTo-Json -Depth 24
  if (Test-UnsafeText -Text $json) { throw "Unsafe RC1 handoff JSON report content detected." }
  Set-Content -LiteralPath $jsonPath -Value $json -Encoding UTF8
  $markdown = New-MarkdownReport -Report $Report
  if (Test-UnsafeText -Text $markdown) { throw "Unsafe RC1 handoff Markdown report content detected." }
  Set-Content -LiteralPath $mdPath -Value $markdown -Encoding UTF8
  [pscustomobject]@{
    report_json_path = ($jsonPath.Substring($RepoRoot.Length + 1) -replace "\\", "/")
    report_markdown_path = ($mdPath.Substring($RepoRoot.Length + 1) -replace "\\", "/")
  }
}

function New-HandoffReport {
  $local = if ($Command -in @("status", "local", "audit")) { Get-LocalChecks } else { $null }
  $tag = if ($Command -in @("status", "tag", "audit")) { Get-TagChecks } else { $null }
  $cloud = if ($Command -in @("cloud", "audit")) { Get-CloudChecks } else { $null }
  $stopHook = if ($Command -in @("status", "stop-hook-diagnose", "audit")) { Get-StopHookDiagnosis } else { $null }

  $blockers = @()
  $warnings = @()
  foreach ($section in @($local, $tag, $cloud, $stopHook)) {
    if ($null -eq $section) { continue }
    $blockers += @($section.blockers)
    $warnings += @($section.warnings)
    if ([string](Get-Prop -Object $section -Name "status") -eq "skipped") { $warnings += [string](Get-Prop -Object $section -Name "skip_reason" -Default "section_skipped") }
  }

  $sectionOk = $true
  foreach ($section in @($local, $tag, $cloud, $stopHook)) {
    if ($null -eq $section) { continue }
    if ([string](Get-Prop -Object $section -Name "status") -eq "skipped") { continue }
    if (-not [bool](Get-Bool -Object $section -Name "ok")) { $sectionOk = $false }
  }
  $status = if ($blockers.Count -gt 0 -or -not $sectionOk) {
    "blocked"
  } elseif ($warnings.Count -gt 0) {
    "warning"
  } else {
    "pass"
  }

  $report = [pscustomobject]@{
    schema = $Schema
    ok = ($status -in @("pass", "warning"))
    status = $status
    command = $Command
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    tag_name = $ExpectedTag
    expected_commit = $ExpectedCommit
    expected_image_ref = $ExpectedImageRef
    expected_cloud_commit = $ResolvedExpectedCloudCommit
    expected_cloud_image_ref = $ResolvedExpectedCloudImageRef
    tag_target_commit = if ($tag) { [string](Get-Prop -Object $tag -Name "tag_target_commit" -Default "") } else { $ExpectedCommit }
    tag_verified_local = if ($tag) { [bool](Get-Bool -Object $tag -Name "tag_verified_local") } else { $false }
    tag_verified_origin_if_available = if ($tag) { [bool](Get-Bool -Object $tag -Name "tag_verified_origin_if_available") } else { $false }
    cloud_version_ok = if ($cloud) { [bool](Get-Bool -Object $cloud -Name "cloud_version_ok") } else { $false }
    image_ref_ok = if ($cloud) { [bool](Get-Bool -Object $cloud -Name "image_ref_ok") } else { $false }
    rc_gate_ok = if ($cloud) { [bool](Get-Bool -Object $cloud -Name "rc_gate_ok") } elseif ($local) { [bool](Get-Bool -Object $local -Name "rc_gate_local_ok") } else { $false }
    post_tag_audit_present = if ($local) { [bool](Get-Bool -Object $local -Name "post_tag_audit_present") } else { ((Test-RelativeFile $PostTagAuditMarkdown) -and (Test-RelativeFile $PostTagAuditJson)) }
    handoff_doc_present = if ($local) { [bool](Get-Bool -Object $local -Name "handoff_doc_present") } else { Test-RelativeFile "docs/release/BOOTSTRAP_ALPHA_RC1_HANDOFF.md" }
    disabled_features_present = if ($local) { [bool](Get-Bool -Object $local -Name "disabled_features_present") } else { Test-RelativeFile "docs/release/BOOTSTRAP_ALPHA_DISABLED_FEATURES.md" }
    local = $local
    tag = $tag
    cloud = $cloud
    stop_hook = $stopHook
    github_release_created = $false
    task_created = $false
    task_claimed = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    stop_hook_status = if ($stopHook) { [string](Get-Prop -Object $stopHook -Name "stop_hook_status" -Default "not_checked") } else { "not_checked" }
    stop_hook_summary = if ($stopHook) { [string](Get-Prop -Object $stopHook -Name "stop_hook_summary" -Default "") } else { "" }
    blockers = @($blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    warnings = @($warnings | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    report_json_path = ""
    report_markdown_path = ""
    token_printed = $false
  }

  if ($WriteReport) {
    $paths = Write-HandoffReports -Report $report
    $report.report_json_path = $paths.report_json_path
    $report.report_markdown_path = $paths.report_markdown_path
  }
  $report
}

if ($Command -eq "safe-summary") {
  $result = [pscustomobject]@{
    schema = "skybridge.bootstrap_alpha_rc1_handoff_safe_summary.v1"
    ok = $true
    tag_name = $ExpectedTag
    expected_commit = $ExpectedCommit
    expected_image_ref = $ExpectedImageRef
    expected_cloud_commit = $ResolvedExpectedCloudCommit
    expected_cloud_image_ref = $ResolvedExpectedCloudImageRef
    github_release_created = $false
    task_created = $false
    task_claimed = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  }
} else {
  $result = New-HandoffReport
}

if ($Json) {
  $result | ConvertTo-Json -Depth 24
} else {
  "Schema:       $($result.schema)"
  "Status:       $($result.status)"
  "OK:           $($result.ok)"
  "Tag:          $($result.tag_name)"
  "StopHook:     $($result.stop_hook_status)"
  "TokenPrinted: false"
}

if ($result.status -eq "blocked") {
  exit 1
}
