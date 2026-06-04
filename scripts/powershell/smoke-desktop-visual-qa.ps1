[CmdletBinding()]
param(
  [switch]$SkipWhenUnavailable,
  [switch]$RequirePlaywright,
  [string]$WebBase = "http://127.0.0.1:1420"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$origin = [uri]$WebBase
if ($origin.Host -notin @("localhost", "127.0.0.1", "::1", "[::1]")) {
  throw "Refusing non-loopback desktop visual QA base: $WebBase"
}

$args = @("--web-base=$WebBase")
if ($SkipWhenUnavailable) { $args += "--skip-when-unavailable" }
if ($RequirePlaywright) { $args += "--require-playwright" }

node (Join-Path $repoRoot "scripts\desktop-visual-qa.mjs") @args
