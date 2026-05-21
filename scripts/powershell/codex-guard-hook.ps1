# Hard-deny dangerous Codex tool calls. This script is intended for PreToolUse.
$ErrorActionPreference = "Stop"

try {
  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

  $event = $raw | ConvertFrom-Json -AsHashtable
  $toolInput = $event["tool_input"]
  $command = ""

  if ($toolInput -is [hashtable] -and $toolInput.ContainsKey("command")) {
    $command = [string]$toolInput["command"]
  }

  $denyPatterns = @(
    "(^|;|\s)rm\s+-rf\s+/",
    "(^|;|\s)rm\s+-rf\s+~",
    "docker\s+system\s+prune\s+-a\s+--volumes",
    "docker\s+volume\s+prune",
    "docker\s+builder\s+prune\s+-a",
    "git\s+push\s+.*--force.*\s(main|master)\b",
    "git\s+reset\s+--hard\s+origin/main",
    "git\s+checkout\s+.*\s--\s\.",
    "Remove-Item\s+.*-Recurse.*\$HOME",
    "Remove-Item\s+.*-Recurse.*C:\\Users",
    "Remove-Item\s+.*-Recurse.*V:\\",
    "id_rsa",
    "id_ed25519",
    "\.env",
    "GITHUB_TOKEN",
    "OPENAI_API_KEY",
    "NTFY_TOKEN",
    "BEGIN OPENSSH PRIVATE KEY",
    "BEGIN RSA PRIVATE KEY"
  )

  foreach ($pattern in $denyPatterns) {
    if ($command -match $pattern) {
      $response = @{
        decision = "deny"
        reason = "Blocked by SkyBridge Agent Hub guard hook: $pattern"
      } | ConvertTo-Json -Compress
      [Console]::Error.WriteLine($response)
      exit 2
    }
  }
} catch {
  # Do not block on parser errors.
}

exit 0
