$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command workunit-a-finalizer-preview -SimulatePr157Merged -Json | Out-String).Trim()
if ($json -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|token_printed"\s*:\s*true') { throw "unsafe finalizer preview" }
$result = $json | ConvertFrom-Json
if ($result.token_printed -ne $false) { throw "token_printed=true" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-a-finalizer-evidence-safe"; token_printed = $false } | ConvertTo-Json -Compress
