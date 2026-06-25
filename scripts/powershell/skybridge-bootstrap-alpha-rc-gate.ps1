[CmdletBinding()]
param(
  [ValidateSet("status", "local", "cloud", "live-evidence", "audit", "tag-preview", "safe-summary")]
  [string]$Command = "status",
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$ExpectedCommit = "8499ccba39894fdfccb7b29ddfe72db142ddb711",
  [string]$ExpectedImageRef = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-8499ccba39894fdfccb7b29ddfe72db142ddb711",
  [switch]$WriteReport,
  [string]$ReportDir = ".agent/tmp/bootstrap-alpha-rc",
  [switch]$Json,
  [switch]$FixtureMissingRequiredDoc,
  [switch]$FixtureMissingRequiredDocBlock
)

$ErrorActionPreference = "Stop"

$BootstrapAlphaBaselineCommit = "8499ccba39894fdfccb7b29ddfe72db142ddb711"
$BootstrapAlphaBaselineImageRef = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-8499ccba39894fdfccb7b29ddfe72db142ddb711"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

$Schema = "skybridge.bootstrap_alpha_rc_gate.v1"
$TagNamePreview = "v0.1.0-bootstrap-alpha-rc1"
$WorkerId = "jerry-win-local-01"
$ApiBaseParameterWasBound = $PSBoundParameters.ContainsKey("ApiBase")
$TokenFileParameterWasBound = $PSBoundParameters.ContainsKey("TokenFile")
$LiveTaskIds = @(
  "live-safe-template-task-332-001",
  "live-matlab-golden-task-336-001",
  "live-codex-analysis-report-task-339-001"
)

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

function Test-UnsafeSecretText {
  param([AllowNull()][string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed\s*[:=]\s*true|token_printed"\s*:\s*true'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer\s+\S+|bearer\s+[A-Za-z0-9._-]{20,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|cookie\s*[:=]\s*\S+|password\s*[:=]\s*\S+|api[_-]?key\s*[:=]\s*\S+|$tokenTrue"
}

function Resolve-ConfigValueFromFile {
  param([string]$Path, [string]$Name)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
  $text = Get-Content -Raw -LiteralPath $Path
  $pattern = "(?m)^\s*\`$env:$([regex]::Escape($Name))\s*=\s*['""]?([^'""\r\n]+)['""]?"
  $match = [regex]::Match($text, $pattern)
  if ($match.Success) { return $match.Groups[1].Value.Trim() }
  ""
}

function Resolve-HomePathValue {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $profileHome = [Environment]::GetFolderPath("UserProfile")
  $Value.Replace('$HOME', $profileHome).Replace('~', $profileHome)
}

function Resolve-GateApiBase {
  if ($ApiBaseParameterWasBound) { return $ApiBase.Trim() }
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_API_BASE)) { return $env:SKYBRIDGE_API_BASE.Trim() }
  $profileHome = [Environment]::GetFolderPath("UserProfile")
  Resolve-ConfigValueFromFile -Path (Join-Path $profileHome ".skybridge\skybridge.env.ps1") -Name "SKYBRIDGE_API_BASE"
}

function Resolve-GateTokenFile {
  if ($TokenFileParameterWasBound) { return (Resolve-HomePathValue $TokenFile) }
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_TOKEN_FILE)) { return (Resolve-HomePathValue $env:SKYBRIDGE_WORKER_TOKEN_FILE) }
  $profileHome = [Environment]::GetFolderPath("UserProfile")
  $fromConfig = Resolve-ConfigValueFromFile -Path (Join-Path $profileHome ".skybridge\worker.env.ps1") -Name "SKYBRIDGE_WORKER_TOKEN_FILE"
  if (-not [string]::IsNullOrWhiteSpace($fromConfig)) { return (Resolve-HomePathValue $fromConfig) }
  Join-Path $profileHome ".skybridge\worker-token.txt"
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

function Get-AuthHeaders {
  param([string]$Path)
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $token = (Get-Content -Raw -LiteralPath $Path).Trim()
    if (-not [string]::IsNullOrWhiteSpace($token)) { $headers["Authorization"] = "Bearer $token" }
  }
  $headers
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

function Test-RelativeFile {
  param([string]$Path)
  Test-Path -LiteralPath (Join-Path $RepoRoot $Path) -PathType Leaf
}

function Get-PackageScripts {
  $packagePath = Join-Path $RepoRoot "package.json"
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return @{} }
  (Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json).scripts
}

function Get-LocalChecks {
  $requiredDocs = @(
    "docs/release/BOOTSTRAP_ALPHA_RC_RELEASE_NOTES.md",
    "docs/release/BOOTSTRAP_ALPHA_RC_RUNBOOK.md",
    "docs/release/BOOTSTRAP_ALPHA_DISABLED_FEATURES.md",
    "docs/release/BOOTSTRAP_ALPHA_TAG_PLAN.md",
    "docs/product/BOOTSTRAP_ALPHA_PRODUCT_FLOW.md",
    "docs/product/CODEX_NATIVE_REPORT_VALIDATION_SUCCESS.md",
    "docs/product/MATLAB_GOLDEN_RECOVERY_SUCCESS.md",
    "docs/product/LIVE_WORKER_ONE_SAFE_TEMPLATE_TASK.md",
    "docs/release/BOOTSTRAP_ALPHA_SCOPE.md",
    "docs/release/BOOTSTRAP_ALPHA_ROADMAP.md",
    "docs/dev/PROGRESS.md"
  )
  if ($FixtureMissingRequiredDoc) { $requiredDocs += "docs/release/__missing_bootstrap_alpha_rc_fixture__.md" }

  $requiredScripts = @(
    "scripts/powershell/skybridge-bootstrap-alpha-rc-gate.ps1",
    "scripts/powershell/skybridge-bootstrap-alpha-acceptance.ps1",
    "scripts/powershell/skybridge-worker-identity.ps1",
    "scripts/powershell/skybridge-worker-live-heartbeat.ps1",
    "scripts/powershell/skybridge-live-safe-task-pilot.ps1",
    "scripts/powershell/skybridge-live-matlab-golden-success.ps1",
    "scripts/powershell/skybridge-live-codex-analysis-report-native-success.ps1",
    "scripts/powershell/smoke-bootstrap-alpha-rc-report.ps1",
    "scripts/powershell/smoke-bootstrap-alpha-tag-preview.ps1"
  )

  $requiredPackageScripts = @(
    "smoke:bootstrap-alpha-rc-gate",
    "smoke:bootstrap-alpha-rc-gate-local",
    "smoke:bootstrap-alpha-rc-report",
    "smoke:bootstrap-alpha-disabled-features",
    "smoke:bootstrap-alpha-tag-preview",
    "smoke:bootstrap-alpha-acceptance",
    "smoke:operator-report",
    "smoke:review-gate",
    "smoke:self-bootstrap-converge"
  )

  $requiredDocBlocks = @(
    [pscustomobject]@{ path = "docs/release/BOOTSTRAP_ALPHA_RC_RELEASE_NOTES.md"; markers = @("Bootstrap Alpha RC", $BootstrapAlphaBaselineCommit, $BootstrapAlphaBaselineImageRef, "live-codex-analysis-report-task-339-001", "token_printed=false") },
    [pscustomobject]@{ path = "docs/release/BOOTSTRAP_ALPHA_RC_RUNBOOK.md"; markers = @("cloud deploy verification", "worker identity", "Codex native report", "forbidden actions") },
    [pscustomobject]@{ path = "docs/release/BOOTSTRAP_ALPHA_DISABLED_FEATURES.md"; markers = @("general remote shell", "unbounded run", "Codex arbitrary prompt", "background autonomous queue processing") },
    [pscustomobject]@{ path = "docs/release/BOOTSTRAP_ALPHA_TAG_PLAN.md"; markers = @($TagNamePreview, $BootstrapAlphaBaselineCommit, $BootstrapAlphaBaselineImageRef, "tag_created=false", "operator authorization") }
  )
  if ($FixtureMissingRequiredDocBlock) {
    $requiredDocBlocks += [pscustomobject]@{ path = "docs/release/BOOTSTRAP_ALPHA_RC_RELEASE_NOTES.md"; markers = @("__missing_bootstrap_alpha_rc_block_fixture__") }
  }

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
      if (Test-UnsafeSecretText -Text $text) {
        $docSecretFindings += [pscustomobject]@{ path = $doc; issue = "unsafe_secret_like_text" }
      }
    }
  }

  $missingDocBlocks = @()
  foreach ($block in $requiredDocBlocks) {
    $path = Join-Path $RepoRoot ([string]$block.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = Get-Content -Raw -LiteralPath $path
    foreach ($marker in @($block.markers)) {
      if ($text -notmatch [regex]::Escape([string]$marker)) {
        $missingDocBlocks += [pscustomobject]@{ path = [string]$block.path; marker = [string]$marker }
      }
    }
  }

  $acceptanceCallable = [bool](Test-RelativeFile "scripts/powershell/skybridge-bootstrap-alpha-acceptance.ps1")
  $acceptanceOk = $acceptanceCallable

  $missingDocs = @($docResults | Where-Object { -not $_.exists } | ForEach-Object { $_.path })
  $missingScripts = @($scriptResults | Where-Object { -not $_.exists } | ForEach-Object { $_.path })
  $missingPackageScripts = @($packageScriptResults | Where-Object { -not $_.exists } | ForEach-Object { $_.name })
  $blockers = @()
  if ($missingDocs.Count -gt 0) { $blockers += "missing_required_docs" }
  if ($missingScripts.Count -gt 0) { $blockers += "missing_required_scripts" }
  if ($missingPackageScripts.Count -gt 0) { $blockers += "missing_required_package_scripts" }
  if ($docSecretFindings.Count -gt 0) { $blockers += "unsafe_secret_like_text_in_rc_docs" }
  if ($missingDocBlocks.Count -gt 0) { $blockers += "missing_required_doc_blocks" }
  if (-not $acceptanceCallable) { $blockers += "bootstrap_alpha_acceptance_not_callable" }

  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    status = if ($blockers.Count -eq 0) { "pass" } else { "blocked" }
    required_docs = $docResults
    required_scripts = $scriptResults
    required_package_scripts = $packageScriptResults
    missing_docs = @($missingDocs)
    missing_scripts = @($missingScripts)
    missing_package_scripts = @($missingPackageScripts)
    missing_doc_blocks = @($missingDocBlocks)
    doc_secret_findings = @($docSecretFindings)
    bootstrap_alpha_acceptance_callable = $acceptanceCallable
    bootstrap_alpha_acceptance_ok = $acceptanceOk
    bootstrap_alpha_acceptance_check_mode = "callable"
    blockers = @($blockers)
    warnings = @()
    token_printed = $false
  }
}

function Get-CloudChecks {
  param([string]$ResolvedApiBase)
  $warnings = @()
  $blockers = @()
  if (-not (Test-ApiConfigured -Value $ResolvedApiBase)) {
    return [pscustomobject]@{
      ok = $false
      status = "skipped"
      skipped = $true
      skip_reason = "api_base_not_configured"
      version_reachable = $false
      commit_matches_expected = $false
      image_matches_expected = $false
      parity_ok = $false
      operator_report_ok = $false
      review_gate_ok = $false
      self_bootstrap_convergence_ok = $false
      blockers = @()
      warnings = @("cloud_checks_skipped_api_base_not_configured")
      token_printed = $false
    }
  }

  $version = $null
  try {
    $version = Invoke-RestMethod -Method GET -Uri "$($ResolvedApiBase.TrimEnd('/'))/v1/version" -TimeoutSec 30
  } catch {
    $blockers += "cloud_version_unreachable"
  }
  $versionReachable = ($null -ne $version)
  $commitMatches = ($versionReachable -and [string](Get-Prop -Object $version -Name "commit_sha") -eq $ExpectedCommit)
  $imageMatches = ($versionReachable -and [string](Get-Prop -Object $version -Name "image_ref") -eq $ExpectedImageRef)
  if ($versionReachable -and -not $commitMatches) { $blockers += "cloud_commit_mismatch" }
  if ($versionReachable -and -not $imageMatches) { $blockers += "cloud_image_ref_mismatch" }

  $parity = Invoke-ChildJson -Arguments @("-File", (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1"), "-ApiBase", $ResolvedApiBase, "-Json") -AllowNonZero
  $parityOk = [bool](Get-Bool -Object $parity -Name "ok" -Default $false)
  if (-not $parityOk) { $blockers += "cloud_parity_not_ok" }

  $operatorOk = Test-RelativeFile "scripts/powershell/skybridge-operator-report.ps1"
  $reviewOk = Test-RelativeFile "scripts/powershell/skybridge-review-gate.ps1"
  $convergeOk = Test-RelativeFile "scripts/powershell/skybridge-self-bootstrap-converge.ps1"
  if (-not $operatorOk) { $warnings += "operator_report_not_callable" }
  if (-not $reviewOk) { $warnings += "review_gate_not_callable" }
  if (-not $convergeOk) { $warnings += "self_bootstrap_convergence_not_callable" }

  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    status = if ($blockers.Count -eq 0 -and $warnings.Count -eq 0) { "pass" } elseif ($blockers.Count -eq 0) { "warning" } else { "blocked" }
    skipped = $false
    api_base_configured = $true
    api_base_host = ([uri]$ResolvedApiBase).Host
    version_reachable = $versionReachable
    commit_sha = if ($versionReachable) { [string](Get-Prop -Object $version -Name "commit_sha") } else { "" }
    image_ref = if ($versionReachable) { [string](Get-Prop -Object $version -Name "image_ref") } else { "" }
    commit_matches_expected = $commitMatches
    image_matches_expected = $imageMatches
    parity_ok = $parityOk
    parity_status = [string](Get-Prop -Object $parity -Name "status" -Default (Get-Prop -Object $parity -Name "deployment_parity_status" -Default "unknown"))
    parity_missing_routes = @((Get-Prop -Object $parity -Name "missing_routes" -Default @()) | ForEach-Object { [string]$_ })
    operator_report_ok = $operatorOk
    operator_report_check_mode = "callable"
    review_gate_ok = $reviewOk
    review_gate_check_mode = "callable"
    self_bootstrap_convergence_ok = $convergeOk
    self_bootstrap_convergence_check_mode = "callable"
    blockers = @($blockers)
    warnings = @($warnings)
    token_printed = $false
  }
}

function Get-WorkerChecks {
  param([string]$ResolvedApiBase, [string]$ResolvedTokenFile)
  $workerIdentityExists = Test-RelativeFile "scripts/powershell/skybridge-worker-identity.ps1"
  $workerHeartbeatExists = Test-RelativeFile "scripts/powershell/skybridge-worker-live-heartbeat.ps1"
  $workerDocExists = Test-RelativeFile "docs/release/WINDOWS_WORKER_INSTALL_BOOTSTRAP_ALPHA.md"
  $workerLookupAvailable = $false
  $cloudWorkerStatus = "skipped"
  if (Test-ApiConfigured -Value $ResolvedApiBase) {
    try {
      $headers = Get-AuthHeaders -Path $ResolvedTokenFile
      $response = Invoke-RestMethod -Method GET -Uri "$($ResolvedApiBase.TrimEnd('/'))/v1/workers/$([uri]::EscapeDataString($WorkerId))" -Headers $headers -TimeoutSec 30
      $workerLookupAvailable = $true
      $cloudWorkerStatus = [string](Get-Prop -Object (Get-Prop -Object $response -Name "worker") -Name "status" -Default "unknown")
    } catch {
      $cloudWorkerStatus = "unavailable"
    }
  }
  $blockers = @()
  if (-not $workerIdentityExists) { $blockers += "worker_identity_script_missing" }
  if (-not $workerHeartbeatExists) { $blockers += "worker_heartbeat_script_missing" }
  if (-not $workerDocExists) { $blockers += "worker_baseline_doc_missing" }
  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    status = if ($blockers.Count -eq 0) { "pass" } else { "blocked" }
    worker_id = $WorkerId
    worker_identity_script_exists = $workerIdentityExists
    worker_heartbeat_script_exists = $workerHeartbeatExists
    worker_id_baseline_documented = $workerDocExists
    cloud_worker_lookup_available = $workerLookupAvailable
    cloud_worker_status = $cloudWorkerStatus
    claim_check_performed = $false
    blockers = @($blockers)
    warnings = @()
    token_printed = $false
  }
}

function Test-EvidenceSafety {
  param($Evidence)
  if ($null -eq $Evidence) { return $false }
  $unsafe = @(
    (Get-Bool -Object $Evidence -Name "raw_codex_log_included"),
    (Get-Bool -Object $Evidence -Name "raw_prompt_included"),
    (Get-Bool -Object $Evidence -Name "raw_stdout_included"),
    (Get-Bool -Object $Evidence -Name "raw_stderr_included"),
    (Get-Bool -Object $Evidence -Name "raw_logs_included"),
    (Get-Bool -Object $Evidence -Name "project_control_unpaused"),
    (Get-Bool -Object $Evidence -Name "token_printed"),
    (Get-Bool -Object $Evidence -Name "pr_created"),
    (Get-Bool -Object $Evidence -Name "worker_loop_started")
  ) | Where-Object { $_ -eq $true }
  return (@($unsafe).Count -eq 0)
}

function New-LiveEvidenceSummary {
  param([string]$Name, [string]$TaskId, $Report, [scriptblock]$ExtraCheck)
  $evidence = Get-Prop -Object $Report -Name "evidence_summary"
  $finalState = [string](Get-Prop -Object $Report -Name "final_task_state" -Default "missing")
  $evidencePresent = [bool](Get-Bool -Object $Report -Name "evidence_summary_present" -Default $false)
  $safetyOk = Test-EvidenceSafety -Evidence $evidence
  $extraOk = & $ExtraCheck $Report $evidence
  [pscustomobject]@{
    name = $Name
    task_id = $TaskId
    ok = ($finalState -eq "completed" -and $evidencePresent -and $safetyOk -and $extraOk)
    final_task_state = $finalState
    evidence_present = $evidencePresent
    safety_flags_ok = $safetyOk
    extra_checks_ok = $extraOk
    token_printed = $false
  }
}

function Get-LiveEvidenceChecks {
  param([string]$ResolvedApiBase, [string]$ResolvedTokenFile)
  if (-not (Test-ApiConfigured -Value $ResolvedApiBase)) {
    return [pscustomobject]@{
      ok = $false
      status = "skipped"
      skipped = $true
      skip_reason = "api_base_not_configured"
      task_summaries = @()
      blockers = @()
      warnings = @("live_evidence_checks_skipped_api_base_not_configured")
      token_printed = $false
    }
  }
  if ([string]::IsNullOrWhiteSpace($ResolvedTokenFile) -or -not (Test-Path -LiteralPath $ResolvedTokenFile -PathType Leaf)) {
    return [pscustomobject]@{
      ok = $false
      status = "skipped"
      skipped = $true
      skip_reason = "token_file_not_configured"
      task_summaries = @()
      blockers = @()
      warnings = @("live_evidence_checks_skipped_token_file_not_configured")
      token_printed = $false
    }
  }

  $commonArgs = @("-ApiBase", $ResolvedApiBase, "-TokenFile", $ResolvedTokenFile, "-Json")
  $safe = Invoke-ChildJson -Arguments (@("-File", (Join-Path $PSScriptRoot "skybridge-live-safe-task-pilot.ps1"), "-Command", "report") + $commonArgs) -AllowNonZero
  $matlab = Invoke-ChildJson -Arguments (@("-File", (Join-Path $PSScriptRoot "skybridge-live-matlab-golden-success.ps1"), "-Command", "report") + $commonArgs) -AllowNonZero
  $codex = Invoke-ChildJson -Arguments (@("-File", (Join-Path $PSScriptRoot "skybridge-live-codex-analysis-report-native-success.ps1"), "-Command", "report") + $commonArgs) -AllowNonZero

  $safeSummary = New-LiveEvidenceSummary -Name "live_safe_template" -TaskId "live-safe-template-task-332-001" -Report $safe -ExtraCheck {
    param($Report, $Evidence)
    return (
      [string](Get-Prop -Object $Report -Name "task_id") -eq "live-safe-template-task-332-001" -and
      -not (Get-Bool -Object $Report -Name "codex_run_called") -and
      -not (Get-Bool -Object $Report -Name "matlab_run_called") -and
      -not (Get-Bool -Object $Report -Name "arbitrary_shell_enabled") -and
      -not (Get-Bool -Object $Report -Name "worker_loop_started") -and
      -not (Get-Bool -Object $Report -Name "project_control_unpaused")
    )
  }
  $matlabSummary = New-LiveEvidenceSummary -Name "matlab_golden_success" -TaskId "live-matlab-golden-task-336-001" -Report $matlab -ExtraCheck {
    param($Report, $Evidence)
    $requiredChangedFiles = @(
      ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/manifest.json",
      ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json",
      ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/metrics.csv"
    )
    $changedFiles = @((Get-Prop -Object $Evidence -Name "changed_files" -Default @()) | ForEach-Object { [string]$_ })
    $changedFilesOk = $true
    foreach ($required in $requiredChangedFiles) {
      if ($changedFiles -notcontains $required) { $changedFilesOk = $false }
    }
    $summaryPath = Join-Path $RepoRoot ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json"
    $summaryOk = $false
    if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
      try {
        $summaryJson = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
        $expectedCount = [int](Get-Prop -Object $summaryJson -Name "expected_combination_count" -Default (Get-Prop -Object $summaryJson -Name "combination_count" -Default 0))
        $summaryOk = (
          [int](Get-Prop -Object $summaryJson -Name "completed_count" -Default 0) -eq 2 -and
          [int](Get-Prop -Object $summaryJson -Name "failed_count" -Default 0) -eq 0 -and
          $expectedCount -eq 2
        )
      } catch {
        $summaryOk = $false
      }
    }
    return (
      [string](Get-Prop -Object $Report -Name "task_id") -eq "live-matlab-golden-task-336-001" -and
      [string](Get-Prop -Object $Evidence -Name "validation_status" -Default "") -eq "passed" -and
      $changedFilesOk -and
      $summaryOk
    )
  }
  $codexSummary = New-LiveEvidenceSummary -Name "codex_native_report" -TaskId "live-codex-analysis-report-task-339-001" -Report $codex -ExtraCheck {
    param($Report, $Evidence)
    return (
      [string](Get-Prop -Object $Report -Name "task_id") -eq "live-codex-analysis-report-task-339-001" -and
      [string](Get-Prop -Object $Evidence -Name "final_report_source" -Default "") -eq "codex_native" -and
      -not (Get-Bool -Object $Evidence -Name "fallback_report_used") -and
      (Get-Bool -Object $Evidence -Name "native_report_valid") -and
      [string](Get-Prop -Object $Evidence -Name "validation_status" -Default "") -eq "passed" -and
      [int](Get-Prop -Object $Evidence -Name "codex_exit_code" -Default -1) -eq 0 -and
      [string](Get-Prop -Object $Evidence -Name "codex_failure_category" -Default "") -eq "none"
    )
  }

  $summaries = @($safeSummary, $matlabSummary, $codexSummary)
  $failed = @($summaries | Where-Object { -not $_.ok } | ForEach-Object { $_.task_id })
  [pscustomobject]@{
    ok = ($failed.Count -eq 0)
    status = if ($failed.Count -eq 0) { "pass" } else { "blocked" }
    skipped = $false
    task_summaries = @($summaries)
    live_safe_template_completed = [bool]$safeSummary.ok
    matlab_golden_success_completed = [bool]$matlabSummary.ok
    codex_native_report_completed = [bool]$codexSummary.ok
    failed_task_ids = @($failed)
    blockers = @(if ($failed.Count -gt 0) { "live_evidence_not_proven" })
    warnings = @()
    token_printed = $false
  }
}

function Get-TagPreview {
  $localTag = ((git tag --list $TagNamePreview 2>$null | Out-String).Trim())
  $tagExists = -not [string]::IsNullOrWhiteSpace($localTag)
  $tagCommit = ""
  if ($tagExists) {
    try { $tagCommit = ((git rev-list -n 1 $TagNamePreview 2>$null | Out-String).Trim()) } catch {}
  }
  [pscustomobject]@{
    ok = (-not $tagExists -or $tagCommit -eq $ExpectedCommit)
    status = if (-not $tagExists) { "pass" } elseif ($tagCommit -eq $ExpectedCommit) { "warning" } else { "blocked" }
    tag_name_preview = $TagNamePreview
    target_commit = $ExpectedCommit
    image_ref = $ExpectedImageRef
    tag_exists = $tagExists
    tag_commit = $tagCommit
    tag_recommended = (-not $tagExists)
    tag_created = $false
    command_preview = "git tag -a $TagNamePreview $ExpectedCommit -m `"Bootstrap Alpha RC`""
    blockers = @(if ($tagExists -and $tagCommit -ne $ExpectedCommit) { "tag_exists_on_different_commit" })
    warnings = @(if ($tagExists -and $tagCommit -eq $ExpectedCommit) { "tag_already_exists_on_target_commit" })
    token_printed = $false
  }
}

function New-MarkdownReport {
  param($Report)
  $lines = @(
    "# Bootstrap Alpha RC Gate Report",
    "",
    "- schema: $($Report.schema)",
    "- status: $($Report.status)",
    "- ok: $($Report.ok)",
    "- release_candidate_ready: $($Report.release_candidate_ready)",
    "- tag_name_preview: $($Report.tag_name_preview)",
    "- tag_created: $($Report.tag_created)",
    "- deploy_mutation_performed: $($Report.deploy_mutation_performed)",
    "- task_claimed: $($Report.task_claimed)",
    "- execution_started: $($Report.execution_started)",
    "- token_printed: false",
    "",
    "## Baseline",
    "",
    "- expected_commit: $ExpectedCommit",
    "- expected_image_ref: $ExpectedImageRef",
    "",
    "## Blockers",
    ""
  )
  $blockers = @($Report.blockers)
  if ($blockers.Count -eq 0) { $lines += "- none" } else { foreach ($blocker in $blockers) { $lines += "- $(ConvertTo-SafeText -Text ([string]$blocker))" } }
  $lines += @("", "## Warnings", "")
  $warnings = @($Report.warnings)
  if ($warnings.Count -eq 0) { $lines += "- none" } else { foreach ($warning in $warnings) { $lines += "- $(ConvertTo-SafeText -Text ([string]$warning))" } }
  $lines += @("", "## Live Evidence", "")
  foreach ($task in @($Report.live_evidence.task_summaries)) {
    $lines += "- $($task.task_id): state=$($task.final_task_state); evidence_present=$($task.evidence_present); ok=$($task.ok)"
  }
  $lines += @("", "## Safety", "")
  $lines += "- raw prompt/log/stdout/stderr/token values are not included"
  $lines += "- no task creation, claim, execution, deployment mutation, tag creation, or GitHub release creation was performed"
  $lines += "- token_printed=false"
  ($lines -join [Environment]::NewLine)
}

function Write-GateReports {
  param($Report)
  $dir = Join-Path $RepoRoot $ReportDir
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $jsonPath = Join-Path $dir "bootstrap-alpha-rc-report.json"
  $mdPath = Join-Path $dir "bootstrap-alpha-rc-report.md"
  $json = $Report | ConvertTo-Json -Depth 20
  if (Test-UnsafeSecretText -Text $json) { throw "Unsafe RC JSON report content detected." }
  Set-Content -LiteralPath $jsonPath -Value $json -Encoding UTF8
  $markdown = New-MarkdownReport -Report $Report
  if (Test-UnsafeSecretText -Text $markdown) { throw "Unsafe RC Markdown report content detected." }
  Set-Content -LiteralPath $mdPath -Value $markdown -Encoding UTF8
  [pscustomobject]@{
    report_json_path = ($jsonPath.Substring($RepoRoot.Length + 1) -replace "\\", "/")
    report_markdown_path = ($mdPath.Substring($RepoRoot.Length + 1) -replace "\\", "/")
  }
}

function New-RcGateReport {
  $resolvedApiBase = Resolve-GateApiBase
  $resolvedTokenFile = Resolve-GateTokenFile
  $local = if ($Command -in @("status", "local", "audit")) { Get-LocalChecks } else { $null }
  $cloud = if ($Command -in @("status", "cloud", "audit")) { Get-CloudChecks -ResolvedApiBase $resolvedApiBase } else { $null }
  $worker = if ($Command -in @("status", "cloud", "live-evidence", "audit")) { Get-WorkerChecks -ResolvedApiBase $resolvedApiBase -ResolvedTokenFile $resolvedTokenFile } else { $null }
  $live = if ($Command -in @("status", "live-evidence", "audit")) { Get-LiveEvidenceChecks -ResolvedApiBase $resolvedApiBase -ResolvedTokenFile $resolvedTokenFile } else { $null }
  $tag = if ($Command -in @("status", "tag-preview", "audit")) { Get-TagPreview } else { $null }

  $blockers = @()
  $warnings = @()
  foreach ($section in @($local, $cloud, $worker, $live, $tag)) {
    if ($null -eq $section) { continue }
    $blockers += @($section.blockers)
    $warnings += @($section.warnings)
  }

  $requiredSectionsOk = $true
  foreach ($section in @($local, $cloud, $worker, $live, $tag)) {
    if ($null -eq $section) { continue }
    if ([bool](Get-Bool -Object $section -Name "skipped")) { $requiredSectionsOk = $false; continue }
    if (-not [bool](Get-Bool -Object $section -Name "ok")) { $requiredSectionsOk = $false }
  }
  $hasSkipped = @($cloud, $live | Where-Object { $null -ne $_ -and [bool](Get-Bool -Object $_ -Name "skipped") }).Count -gt 0
  $status = if ($blockers.Count -gt 0) {
    "blocked"
  } elseif ($warnings.Count -gt 0 -or $hasSkipped) {
    "warning"
  } elseif ($requiredSectionsOk) {
    "pass"
  } else {
    "warning"
  }
  $releaseReady = (
    $Command -eq "audit" -and
    $status -eq "pass" -and
    [bool](Get-Bool -Object $local -Name "ok") -and
    [bool](Get-Bool -Object $cloud -Name "ok") -and
    [bool](Get-Bool -Object $worker -Name "ok") -and
    [bool](Get-Bool -Object $live -Name "ok") -and
    [bool](Get-Bool -Object $tag -Name "ok") -and
    -not [bool](Get-Bool -Object $tag -Name "tag_exists")
  )

  $report = [pscustomobject]@{
    schema = $Schema
    ok = ($status -in @("pass", "warning"))
    status = $status
    command = $Command
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    expected_commit = $ExpectedCommit
    expected_image_ref = $ExpectedImageRef
    api_base_configured = (Test-ApiConfigured -Value $resolvedApiBase)
    token_file_present = (-not [string]::IsNullOrWhiteSpace($resolvedTokenFile) -and (Test-Path -LiteralPath $resolvedTokenFile -PathType Leaf))
    worker_id = $WorkerId
    live_task_ids = @($LiveTaskIds)
    local = $local
    cloud = $cloud
    worker = $worker
    live_evidence = $live
    tag_preview = $tag
    blockers = @($blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    warnings = @($warnings | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    release_candidate_ready = $releaseReady
    tag_recommended = ($releaseReady -and [bool](Get-Bool -Object $tag -Name "tag_recommended"))
    tag_name_preview = $TagNamePreview
    tag_created = $false
    deploy_mutation_performed = $false
    task_created = $false
    task_claimed = $false
    execution_started = $false
    codex_execution_started = $false
    matlab_execution_started = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    github_release_created = $false
    raw_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    token_values_included = $false
    report_json_path = ""
    report_markdown_path = ""
    token_printed = $false
  }

  if ($WriteReport) {
    $paths = Write-GateReports -Report $report
    $report.report_json_path = $paths.report_json_path
    $report.report_markdown_path = $paths.report_markdown_path
  }
  $report
}

if ($Command -eq "safe-summary") {
  $result = [pscustomobject]@{
    schema = "skybridge.bootstrap_alpha_rc_gate_safe_summary.v1"
    ok = $true
    expected_commit = $ExpectedCommit
    expected_image_ref = $ExpectedImageRef
    tag_name_preview = $TagNamePreview
    tag_created = $false
    deploy_mutation_performed = $false
    task_created = $false
    task_claimed = $false
    execution_started = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  }
} else {
  $result = New-RcGateReport
}

if ($Json) {
  $result | ConvertTo-Json -Depth 24
} else {
  "Schema:       $($result.schema)"
  "Status:       $($result.status)"
  "OK:           $($result.ok)"
  "RC Ready:     $($result.release_candidate_ready)"
  "TagPreview:   $($result.tag_name_preview)"
  "TagCreated:   false"
  "TokenPrinted: false"
}

if ($result.status -eq "blocked") {
  exit 1
}
