. "$PSScriptRoot\smoke-productization-common.ps1"

$doc = "docs/desktop/DESKTOP_INSTALLER_RC_PLAN.md"
Assert-FileExists $doc
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $doc)

foreach ($required in @(
  "v0.1.0-bootstrap-alpha-desktop-rc1",
  "Why Not Attach To Existing RC1",
  "unsigned Windows installer",
  "checksum file",
  "no auto-update unless already present",
  "no code signing unless separately authorized",
  "no arbitrary execution features",
  "token_printed=false"
)) {
  if ($text -notlike "*$required*") {
    throw "Missing installer RC plan text: $required"
  }
}

Assert-NoUnsafeText $text
Complete-Smoke "desktop-installer-rc-plan"
