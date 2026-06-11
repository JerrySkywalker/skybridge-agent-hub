. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$path = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path "managed-mode-run-disallowed-fixture.tmp"
try {
  "fixture" | Set-Content -LiteralPath $path -Encoding UTF8
  $preview = Invoke-ManagedModeRunJson "changed-files-preview"
  if ($preview.changed_files -notcontains "managed-mode-run-disallowed-fixture.tmp") { throw "Expected untracked disallowed file detection." }
  if ($preview.allowed -ne $false) { throw "Disallowed fixture should be rejected." }
  if ($preview.disallowed_files -notcontains "managed-mode-run-disallowed-fixture.tmp") { throw "Expected disallowed file in output." }
  Write-ManagedModeRunSmokeResult "managed-mode-run-changed-files-rejects-untracked-disallowed"
} finally {
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}
