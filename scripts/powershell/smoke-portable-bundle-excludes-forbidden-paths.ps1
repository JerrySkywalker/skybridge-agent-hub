. "$PSScriptRoot\smoke-productization-common.ps1"
$manifest = Invoke-JsonScript "skybridge-portable-bundle.ps1" @("-Command", "manifest")
Assert-TokenPrintedFalse $manifest
$required = @("node_modules", "target", "raw logs", "raw prompts", "raw transcripts", "env dumps", "secrets", "tokens")
foreach ($item in $required) {
  if ($manifest.excluded_paths -notcontains $item) { throw "Missing excluded path: $item" }
}
Complete-Smoke "portable-bundle-excludes-forbidden-paths"
