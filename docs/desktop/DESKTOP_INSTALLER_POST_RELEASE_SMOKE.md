# Desktop Installer Post-Release Smoke

MG347 verifies the published Bootstrap Alpha Desktop RC1 installer assets after
release. It is an install smoke and audit goal, not a new release goal.

## Release

- Release URL:
  `https://github.com/JerrySkywalker/skybridge-agent-hub/releases/tag/v0.1.0-bootstrap-alpha-desktop-rc1`
- Release tag: `v0.1.0-bootstrap-alpha-desktop-rc1`
- Release title: `Bootstrap Alpha Desktop RC1`
- Source commit: `6bdf1545ef5420d16fa9e0990eaff94ee81ccd03`

## Assets

- `SkyBridge.Desktop_0.1.0_x64_en-US.msi`
  - SHA256: `2a19f5b93c104bce508560c6c888287c1df6c8204fd6b47b8d43cc4efcb98352`
- `SkyBridge.Desktop_0.1.0_x64-setup.exe`
  - SHA256: `35cbd415e621828d8263546e4b69f5691c7fb542e5e0064785239cbbebb9fc71`
- `SHA256SUMS.txt`
- `manifest.json`

## Unsigned Installer Warning

The Windows installers are unsigned. Windows SmartScreen, Defender, or UAC may
show warnings because no code signing certificate is configured yet.

Do not bypass Windows security prompts. The operator should review and approve
or cancel the normal Windows prompts manually.

## Commands

Download and verify assets:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-installer-post-release-smoke.ps1 -Command download -WriteReport -Json
```

Open the selected unsigned installer UI only after exact confirmation:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-installer-post-release-smoke.ps1 -Command launch-installer -InstallerType nsis -Confirm I_UNDERSTAND_OPEN_UNSIGNED_INSTALLER_UI_MANUAL_STEPS_REQUIRED -Json
```

Launch the installed Desktop app only after exact confirmation:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-installer-post-release-smoke.ps1 -Command launch-app -Confirm I_UNDERSTAND_LAUNCH_DESKTOP_APP_FOR_MANUAL_SMOKE_ONLY -Json
```

Generate an uninstall checklist only:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-installer-post-release-smoke.ps1 -Command uninstall-checklist -Confirm I_UNDERSTAND_MANUAL_UNINSTALL_CHECKLIST_ONLY -Json
```

## Manual Install Checklist

- Download assets into `.agent/tmp/desktop-installer-post-release-smoke/downloads/`.
- Verify both installer hashes against `SHA256SUMS.txt`.
- Prefer `SkyBridge.Desktop_0.1.0_x64-setup.exe` for an interactive user install
  smoke unless the operator chooses MSI.
- Review any Windows SmartScreen, Defender, or UAC prompt manually.
- Complete the installer wizard manually.
- Report only summarized results:
  - SmartScreen shown: yes / no / not observed
  - UAC shown: yes / no / not observed
  - install completed: yes / no
  - app launched automatically: yes / no
  - visible error summary: short sanitized text only

## First-Run Checklist

- App window opens.
- App name/title is visible.
- Worker setup or worker status surface is visible.
- Identity and heartbeat fields are visible where expected.
- RC1 or handoff status fields are visible where expected.
- Live apply controls remain disabled or PowerShell exact-confirmation only.
- No automatic task claim occurs.
- No automatic Codex or MATLAB execution occurs.

## Desktop Safety Checklist

The packaged app must not expose:

- arbitrary shell
- arbitrary prompt runner
- queue runner
- worker loop button
- MATLAB arbitrary command
- Codex arbitrary prompt
- PR creation action
- auto-merge action
- background autonomous execution

## Uninstall Or Keep-Installed Decision

Record one of:

- keep installed
- uninstall manually later
- uninstall smoke performed manually

MG347 does not uninstall automatically. Use only the normal Windows uninstall UI
if uninstall is tested.

## Known Limitations

- Installer is unsigned.
- Desktop safety checks include static scan and manual visual smoke.
- The installer smoke does not create tasks or execute worker jobs.
- Post-install file and shortcut discovery may be warning-only when the install
  path is not discoverable.

## Report Hygiene

Reports must not include:

- tokens
- full environment listings
- raw logs
- unredacted prompt text
- credentials
- cookies
- provider auth headers
- proxy profiles

The install smoke report is written under:

- `.agent/tmp/desktop-installer-post-release-smoke/post-release-install-smoke.md`
- `.agent/tmp/desktop-installer-post-release-smoke/post-release-install-smoke.json`

`token_printed=false`
