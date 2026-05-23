$ErrorActionPreference = "Stop"

function Get-SkyBridgeDefaultAutoMergePolicy {
  [CmdletBinding()]
  param()

  return [ordered]@{
    enabled = $false
    allowed_branch_prefixes = @("ai/")
    allowed_paths = @(
      "docs/**",
      "goals/ready/**",
      "goals/backlog/**",
      "goals/done/**",
      "README.md",
      "CHANGELOG.md",
      "ROADMAP.md",
      "CONTRIBUTING.md"
    )
    blocked_paths = @(
      ".env",
      ".env.*",
      "**/.env",
      "**/.env.*",
      "**/*secret*",
      "**/*secrets*",
      "**/*credential*",
      "**/*credentials*",
      "**/*token*",
      ".github/workflows/**",
      "deploy/**",
      "production/**",
      "**/production/**",
      "**/*prod*",
      "**/openresty/**",
      "**/authelia/**",
      "**/1panel/**",
      "**/docker-daemon/**",
      "**/daemon.json"
    )
    required_checks = @(
      "AI branch validation",
      "Project check",
      "Docker build (server)",
      "Docker build (web)"
    )
    max_repair_attempts = 3
    notifications = [ordered]@{
      bootstrap_on_blocked = $true
      bootstrap_on_high_risk = $true
      bootstrap_on_dry_run = $false
    }
  }
}

function Read-SkyBridgeAutoMergePolicy {
  [CmdletBinding()]
  param([string]$PolicyFile)

  $policy = Get-SkyBridgeDefaultAutoMergePolicy
  if ([string]::IsNullOrWhiteSpace($PolicyFile)) {
    return [pscustomobject]$policy
  }
  if (-not (Test-Path -LiteralPath $PolicyFile -PathType Leaf)) {
    throw "auto-merge policy file not found: $PolicyFile"
  }

  $loaded = Get-Content -LiteralPath $PolicyFile -Raw | ConvertFrom-Json
  foreach ($property in $loaded.PSObject.Properties) {
    $policy[$property.Name] = $property.Value
  }
  return [pscustomobject]$policy
}

function ConvertTo-SkyBridgePolicyPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return ($Path -replace "\\", "/").TrimStart("./")
}

function Test-SkyBridgePathPattern {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern
  )

  $normalizedPath = ConvertTo-SkyBridgePolicyPath -Path $Path
  $normalizedPattern = ConvertTo-SkyBridgePolicyPath -Path $Pattern
  $wildcardPattern = $normalizedPattern -replace "\*\*/", "*"
  return ($normalizedPath -like $normalizedPattern -or $normalizedPath -like $wildcardPattern)
}

function Test-SkyBridgeChangedFileRisk {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string[]]$ChangedFiles,
    [object]$Policy = (Get-SkyBridgeDefaultAutoMergePolicy)
  )

  $blocked = New-Object System.Collections.Generic.List[string]
  $outsideAllowed = New-Object System.Collections.Generic.List[string]
  $allowed = New-Object System.Collections.Generic.List[string]
  $blockedPatterns = @($Policy.blocked_paths)
  $allowedPatterns = @($Policy.allowed_paths)

  foreach ($file in $ChangedFiles) {
    $path = ConvertTo-SkyBridgePolicyPath -Path $file
    $isBlocked = $false
    foreach ($pattern in $blockedPatterns) {
      if (Test-SkyBridgePathPattern -Path $path -Pattern $pattern) {
        $blocked.Add($path) | Out-Null
        $isBlocked = $true
        break
      }
    }
    if ($isBlocked) { continue }

    $isAllowed = $false
    foreach ($pattern in $allowedPatterns) {
      if (Test-SkyBridgePathPattern -Path $path -Pattern $pattern) {
        $allowed.Add($path) | Out-Null
        $isAllowed = $true
        break
      }
    }
    if (-not $isAllowed) {
      $outsideAllowed.Add($path) | Out-Null
    }
  }

  $reasons = New-Object System.Collections.Generic.List[string]
  if ($blocked.Count -gt 0) { $reasons.Add("blocked_path") | Out-Null }
  if ($outsideAllowed.Count -gt 0) { $reasons.Add("outside_allowed_paths") | Out-Null }

  return [pscustomobject]@{
    allowed = ($blocked.Count -eq 0 -and $outsideAllowed.Count -eq 0)
    risk = $(if ($blocked.Count -gt 0) { "blocked" } elseif ($outsideAllowed.Count -gt 0) { "needs_review" } else { "low" })
    changed_files = @($ChangedFiles | ForEach-Object { ConvertTo-SkyBridgePolicyPath -Path $_ })
    allowed_files = @($allowed)
    blocked_files = @($blocked)
    outside_allowed_files = @($outsideAllowed)
    reasons = @($reasons)
  }
}

function Test-SkyBridgeRequiredChecks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][object[]]$Checks,
    [Parameter(Mandatory = $true)][string[]]$RequiredChecks,
    [switch]$AllowPending
  )

  $missing = New-Object System.Collections.Generic.List[string]
  $notGreen = New-Object System.Collections.Generic.List[string]
  $pending = New-Object System.Collections.Generic.List[string]

  foreach ($required in $RequiredChecks) {
    $check = @($Checks | Where-Object { $_.name -eq $required } | Select-Object -First 1)
    if ($check.Count -eq 0) {
      $missing.Add($required) | Out-Null
      continue
    }

    $status = [string]$check[0].status
    $conclusion = [string]$check[0].conclusion
    if ($status -ne "COMPLETED") {
      $pending.Add($required) | Out-Null
      if (-not $AllowPending) { $notGreen.Add($required) | Out-Null }
      continue
    }
    if ($conclusion -ne "SUCCESS") {
      $notGreen.Add($required) | Out-Null
    }
  }

  return [pscustomobject]@{
    allowed = ($missing.Count -eq 0 -and $notGreen.Count -eq 0)
    missing_checks = @($missing)
    pending_checks = @($pending)
    not_green_checks = @($notGreen)
  }
}

function Test-SkyBridgeAutoMergeEligibility {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][object]$PrInfo,
    [Parameter(Mandatory = $true)][string[]]$ChangedFiles,
    [Parameter(Mandatory = $true)][object[]]$Checks,
    [object]$Policy = (Get-SkyBridgeDefaultAutoMergePolicy),
    [switch]$AllowPendingChecks
  )

  $reasons = New-Object System.Collections.Generic.List[string]
  $branch = [string]$PrInfo.headRefName
  $branchAllowed = $false
  foreach ($prefix in @($Policy.allowed_branch_prefixes)) {
    if ($branch.StartsWith([string]$prefix, [System.StringComparison]::Ordinal)) {
      $branchAllowed = $true
      break
    }
  }
  if (-not $branchAllowed) { $reasons.Add("branch_prefix_not_allowed") | Out-Null }
  if ([bool]$PrInfo.isDraft) { $reasons.Add("draft_pr") | Out-Null }

  $fileRisk = Test-SkyBridgeChangedFileRisk -ChangedFiles $ChangedFiles -Policy $Policy
  if (-not $fileRisk.allowed) {
    foreach ($reason in @($fileRisk.reasons)) { $reasons.Add($reason) | Out-Null }
  }

  $checkResult = Test-SkyBridgeRequiredChecks -Checks $Checks -RequiredChecks @($Policy.required_checks) -AllowPending:$AllowPendingChecks
  if ($checkResult.missing_checks.Count -gt 0) { $reasons.Add("required_checks_missing") | Out-Null }
  if ($checkResult.not_green_checks.Count -gt 0) { $reasons.Add("required_checks_not_green") | Out-Null }

  return [pscustomobject]@{
    eligible = ($reasons.Count -eq 0)
    reasons = @($reasons | Select-Object -Unique)
    branch = $branch
    draft = [bool]$PrInfo.isDraft
    file_risk = $fileRisk
    checks = $checkResult
  }
}
