. "$PSScriptRoot\smoke-productization-common.ps1"

$fixtureRoot = Join-Path $RepoRoot ".agent/tmp/desktop-installer-post-release-fixture"
if (Test-Path -LiteralPath $fixtureRoot) {
  Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null

$files = @{
  "SkyBridge.Desktop_0.1.0_x64_en-US.msi" = "msi fixture"
  "SkyBridge.Desktop_0.1.0_x64-setup.exe" = "nsis fixture"
  "manifest.json" = '{"schema":"skybridge.desktop_installer_rc_release_manifest.v1","artifacts":[],"token_printed":false}'
}
foreach ($name in $files.Keys) {
  Set-Content -LiteralPath (Join-Path $fixtureRoot $name) -Value $files[$name] -Encoding UTF8
}

$sumLines = @()
foreach ($name in @("SkyBridge.Desktop_0.1.0_x64_en-US.msi", "SkyBridge.Desktop_0.1.0_x64-setup.exe")) {
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $fixtureRoot $name)).Hash.ToLowerInvariant()
  $sumLines += "$hash  $name"
}
$sumLines | Set-Content -LiteralPath (Join-Path $fixtureRoot "SHA256SUMS.txt") -Encoding UTF8

$result = Invoke-JsonScript "skybridge-desktop-installer-post-release-smoke.ps1" @(
  "-Command", "verify-checksum",
  "-DownloadDir", ".agent/tmp/desktop-installer-post-release-fixture",
  "-FixtureMode",
  "-WriteReport"
)

Assert-True $result.ok "desktop_installer_post_release_checksum_fixture_ok"
Assert-True $result.checksums_verified "checksums_verified"
Assert-FileExists $result.report_json_path
Assert-FileExists $result.report_markdown_path
Assert-False $result.release_updated "release_updated"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.silent_install_used "silent_install_used"
Assert-False $result.windows_security_bypass "windows_security_bypass"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-post-release-checksum-fixture"
