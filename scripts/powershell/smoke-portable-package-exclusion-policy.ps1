. "$PSScriptRoot\smoke-productization-common.ps1"
$manifest = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "manifest")
Assert-TokenPrintedFalse $manifest
foreach ($pattern in @(".git/**", "node_modules/**", "**/node_modules/**", "target/**", "**/target/**", ".env*", "**/*.log", ".agent/tmp/**")) {
  if ($manifest.excluded_paths -notcontains $pattern) { throw "Missing excluded pattern: $pattern" }
}
$allIncluded = @($manifest.included_entrypoints + $manifest.included_docs + $manifest.included_scripts + $manifest.included_fixtures)
foreach ($path in $allIncluded) {
  if ($path -match "(^|/)(\.git|node_modules|target|dist|build|\.next|coverage)(/|$)|(^|/)\.env|\.log$|secret|token|cookie|(^|/)raw(/|$)|^\.agent/tmp/") {
    throw "Forbidden included path: $path"
  }
}
Complete-Smoke "portable-package-exclusion-policy"
