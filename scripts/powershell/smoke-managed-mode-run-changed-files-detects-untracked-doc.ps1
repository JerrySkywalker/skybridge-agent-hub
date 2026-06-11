. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$path = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path "docs/managed-mode-run-untracked-fixture.md"
try {
  "fixture" | Set-Content -LiteralPath $path -Encoding UTF8
  $preview = Invoke-ManagedModeRunJson "changed-files-preview"
  if ($preview.changed_files -notcontains "docs/managed-mode-run-untracked-fixture.md") { throw "Expected untracked docs file detection." }
  if ($preview.disallowed_files -contains "docs/managed-mode-run-untracked-fixture.md") { throw "Docs fixture should be allowed." }
  Write-ManagedModeRunSmokeResult "managed-mode-run-changed-files-detects-untracked-doc"
} finally {
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}
