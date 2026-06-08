$ErrorActionPreference = "Stop"
$tmpDir = Join-Path ".agent\tmp" "project-profile-smokes"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$tmp = Join-Path $tmpDir "secret-profile.json"
$profile = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\config\project-profiles\skybridge-agent-hub.json") | ConvertFrom-Json
$profile | Add-Member -NotePropertyName api_key -NotePropertyValue "sk-testsecretvaluethatmustberejected123456" -Force
$profile | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $tmp -Encoding UTF8
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-validate -ProfileFile $tmp -Json | ConvertFrom-Json
if ($result.ok -ne $false) { throw "Secret-looking profile must be rejected." }
if (-not (@($result.errors) -match "secret_looking")) { throw "Expected secret_looking error." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-secret-rejection"; token_printed = $false } | ConvertTo-Json -Compress
