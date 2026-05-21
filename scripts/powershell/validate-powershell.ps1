[CmdletBinding()]
param(
  [string]$Path = "scripts/powershell"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Path)) {
  throw "PowerShell script path not found: $Path"
}

$failed = $false
$scripts = Get-ChildItem -LiteralPath $Path -Filter *.ps1 -File | Sort-Object FullName

foreach ($script in $scripts) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    $failed = $true
    Write-Error "$($script.FullName) failed PowerShell parse validation."
    $errors | Format-List
  } else {
    Write-Host "[powershell-parse] ok $($script.FullName)"
  }
}

if ($failed) {
  exit 1
}

Write-Host "[powershell-parse] validated $($scripts.Count) script(s)"
