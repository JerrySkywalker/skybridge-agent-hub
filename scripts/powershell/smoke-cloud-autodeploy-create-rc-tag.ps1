[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$commit = (& git rev-parse HEAD).Trim()
$tagName = "v999.305.0-smoke-rc"
$result = Invoke-JsonScript "skybridge-create-rc-tag.ps1" @(
  "-TagName", $tagName,
  "-Commit", $commit,
  "-SkipVerify",
  "-FixtureCleanWorkingTree",
  "-FixtureTagAbsent",
  "-WhatIfTag"
)
Assert-True $result.ok "tag preflight ok"
Assert-True $result.dry_run "dry_run"
Assert-False $result.github_release_created "github_release_created"
Assert-TokenPrintedFalse $result
if ($result.tag_name -ne $tagName) { throw "tag name mismatch." }

if ($Json) { $result | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "cloud-autodeploy-create-rc-tag" }
