. "$PSScriptRoot\smoke-productization-common.ps1"

$fixtureRoot = Join-Path $RepoRoot ".agent/tmp/desktop-installer-staging-fixture"
$sourceRoot = Join-Path $fixtureRoot "source"
$outputRoot = ".agent/tmp/desktop-installer-staging-fixture/output"
New-Item -ItemType Directory -Force -Path $sourceRoot | Out-Null
$fixtureArtifact = Join-Path $sourceRoot "SkyBridge Desktop_0.1.0_x64-setup.exe"
Set-Content -LiteralPath $fixtureArtifact -Value "desktop installer staging fixture" -Encoding UTF8

$result = Invoke-JsonScript "skybridge-desktop-installer-staging.ps1" @(
  "-Command", "checksum",
  "-FixtureArtifactDir", ".agent/tmp/desktop-installer-staging-fixture/source",
  "-OutputDir", $outputRoot,
  "-WriteReport"
)

Assert-True $result.ok "desktop_installer_staging_checksum_ok"
Assert-True $result.artifacts_found "artifacts_found"
if (@($result.staged_artifacts).Count -ne 1) { throw "Expected one staged fixture artifact." }
if (@($result.checksums).Count -ne 1) { throw "Expected one checksum." }
Assert-FileExists $result.checksum_path
Assert-FileExists $result.manifest_path
Assert-FileExists $result.report_path
Assert-False $result.installer_uploaded "installer_uploaded"
Assert-False $result.binary_uploaded "binary_uploaded"
Assert-False $result.github_release_updated "github_release_updated"
Assert-False $result.tag_created "tag_created"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-staging-checksum"
