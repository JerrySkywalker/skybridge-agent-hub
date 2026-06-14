$ErrorActionPreference = "Stop"

function Get-SkyBridgeRoot {
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Invoke-ScopedTrustedDocsJson([string[]]$Arguments) {
  $script = Join-Path (Get-SkyBridgeRoot) "scripts\powershell\skybridge-trusted-docs-auto-merge.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Arguments
  if ($LASTEXITCODE -ne 0) { throw "trusted-docs scoped command failed: $($Arguments -join ' ')" }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Assert-ScopedTrustedDocsNoUnsafeText {
  $root = Get-SkyBridgeRoot
  $paths = @(
    "scripts/powershell/skybridge-trusted-docs-auto-merge.ps1",
    "scripts/powershell/smoke-trusted-docs-scoped-common.ps1"
  )
  foreach ($path in $paths) {
    $full = Join-Path $root $path
    $text = Get-Content -Raw -LiteralPath $full
    if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|authorization\s*[:=]\s*bearer|Bearer\s+[A-Za-z0-9_.-]{12,}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----') {
      throw "Unsafe marker found in $path"
    }
  }
}

function Invoke-ScopedTrustedDocsSmoke([string]$Scenario) {
  Assert-ScopedTrustedDocsNoUnsafeText
  switch ($Scenario) {
    "contract" {
      $policy = Invoke-ScopedTrustedDocsJson @("-Command", "scoped-policy", "-ScopedPrNumber", "9101")
      if ($policy.schema -ne "skybridge.trusted_docs_scoped_apply_policy.v1") { throw "Wrong scoped policy schema." }
      if ($policy.trusted_docs_auto_merge_enabled -ne $false -or $policy.auto_merge_apply_enabled -ne $false -or $policy.generic_auto_merge_enabled -ne $false) { throw "Global auto-merge policy enabled." }
      if ($policy.trusted_docs_scoped_apply_enabled -ne $true -or $policy.max_files -ne 1 -or $policy.max_additions -ne 25 -or $policy.max_deletions -ne 0) { throw "Scoped policy limits mismatch." }
    }
    "exact-pr" {
      $decision = Invoke-ScopedTrustedDocsJson @("-Command", "scoped-decision", "-Fixture", "scoped-wrong-pr", "-ScopedPrNumber", "9101")
      if (@($decision.blockers) -notcontains "blocked_by_pr_scope_mismatch" -or $decision.auto_merge_allowed -ne $false) { throw "Scope mismatch was not blocked." }
    }
    "blocks-non-docs" {
      $decision = Invoke-ScopedTrustedDocsJson @("-Command", "scoped-decision", "-Fixture", "scoped-non-docs", "-ScopedPrNumber", "9101")
      if (@($decision.blockers) -notcontains "blocked_by_disallowed_path") { throw "Non-doc path was not blocked." }
    }
    "blocks-multiple-files" {
      $decision = Invoke-ScopedTrustedDocsJson @("-Command", "scoped-decision", "-Fixture", "scoped-multiple-files", "-ScopedPrNumber", "9101")
      if (@($decision.blockers) -notcontains "blocked_by_multiple_files") { throw "Multiple files were not blocked." }
    }
    "blocks-deletions" {
      $decision = Invoke-ScopedTrustedDocsJson @("-Command", "scoped-decision", "-Fixture", "scoped-deletion", "-ScopedPrNumber", "9101")
      if (@($decision.blockers) -notcontains "blocked_by_deletions") { throw "Deletion was not blocked." }
    }
    "blocks-failing-ci" {
      $decision = Invoke-ScopedTrustedDocsJson @("-Command", "scoped-decision", "-Fixture", "scoped-failing-ci", "-ScopedPrNumber", "9101")
      if (@($decision.blockers) -notcontains "blocked_by_failing_or_missing_ci") { throw "Failing CI was not blocked." }
    }
    "blocks-secret-content" {
      $decision = Invoke-ScopedTrustedDocsJson @("-Command", "scoped-decision", "-Fixture", "scoped-secret-content", "-ScopedPrNumber", "9101")
      if (@($decision.blockers) -notcontains "blocked_by_redaction_scan" -and @($decision.blockers) -notcontains "blocked_by_secret_scan") { throw "Secret content was not blocked." }
    }
    "audit-event" {
      $gate = Invoke-ScopedTrustedDocsJson @("-Command", "scoped-gate", "-Fixture", "scoped-eligible", "-ScopedPrNumber", "9101")
      if ($gate.action -ne "trusted_docs_scoped_merge" -or @($gate.audit.events) -notcontains "trusted_docs_scoped_merge_allowed") { throw "Scoped merge audit event missing." }
    }
    "token-printed-false" {
      foreach ($command in @("scoped-policy", "scoped-decision", "scoped-gate", "scoped-audit")) {
        $raw = Invoke-ScopedTrustedDocsJson @("-Command", $command, "-Fixture", "scoped-eligible", "-ScopedPrNumber", "9101") | ConvertTo-Json -Depth 20
        if ($raw -match '"token_printed"\s*:\s*true') { throw "token_printed true in $command" }
      }
    }
    default { throw "Unknown scoped trusted-docs smoke scenario: $Scenario" }
  }
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
}
