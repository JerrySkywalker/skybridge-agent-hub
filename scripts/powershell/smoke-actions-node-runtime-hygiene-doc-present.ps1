. "$PSScriptRoot\smoke-productization-common.ps1"

Assert-FileExists "docs/dev/ACTIONS_NODE_RUNTIME_HYGIENE.md"
Assert-FileExists "scripts/powershell/skybridge-actions-node-runtime-hygiene.ps1"

$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs/dev/ACTIONS_NODE_RUNTIME_HYGIENE.md")
Assert-NoUnsafeText $text

foreach ($required in @(
  "docker/metadata-action@v6",
  "docker/login-action@v4",
  "docker/setup-buildx-action@v4",
  "docker/build-push-action@v7",
  "Do not suppress warnings",
  "Do not weaken CI",
  "Do not expand workflow permissions",
  "token_printed=false"
)) {
  if ($text -notmatch [regex]::Escape($required)) {
    throw "ACTIONS_NODE_RUNTIME_HYGIENE.md missing required text: $required"
  }
}

Complete-Smoke "actions-node-runtime-hygiene-doc-present"
