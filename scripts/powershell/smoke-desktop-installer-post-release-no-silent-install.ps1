. "$PSScriptRoot\smoke-productization-common.ps1"

$scriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-desktop-installer-post-release-smoke.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath
if ($source -match "(?i)(/quiet|/qn|/silent|--silent|ArgumentList\s+.*quiet|ArgumentList\s+.*silent)") {
  throw "Silent installer flag surface detected."
}
if ($source -notmatch [regex]::Escape("I_UNDERSTAND_OPEN_UNSIGNED_INSTALLER_UI_MANUAL_STEPS_REQUIRED")) {
  throw "Installer UI exact confirmation missing."
}
if ($source -notmatch [regex]::Escape("Start-Process -FilePath $installerPath")) {
  throw "Installer launch must use direct UI Start-Process without silent arguments."
}

$result = Invoke-JsonScript "skybridge-desktop-installer-post-release-smoke.ps1" @("-Command", "safe-summary")
Assert-True $result.ok "desktop_installer_post_release_no_silent_ok"
Assert-False $result.silent_install_used "silent_install_used"
Assert-False $result.windows_security_bypass "windows_security_bypass"
Assert-False $result.installer_opened "installer_opened"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-post-release-no-silent-install"
