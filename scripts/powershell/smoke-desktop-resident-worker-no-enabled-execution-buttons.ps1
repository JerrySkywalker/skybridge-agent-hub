$ErrorActionPreference = "Stop"
$desktop = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
$buttons = [regex]::Matches($desktop, '(?s)<button\b(?<attrs>[^>]*)>(?<body>.*?)</button>')
foreach ($button in $buttons) {
  $body = $button.Groups["body"].Value
  $attrs = $button.Groups["attrs"].Value
  if ($body -match '(?i)\b(start|run|apply|execute|claim)\b' -and $attrs -notmatch '\bdisabled\b') {
    throw "Execution-like button is not disabled: $body"
  }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-resident-worker-no-enabled-execution-buttons"; token_printed = $false } | ConvertTo-Json -Compress
