# Product Readiness Interpretation

`ready_for_local_preview` means the repository can display local productization surfaces and safe reports. It does not mean execution is enabled.

Interpretation:

- `product_state_layout=defined`: safe report directories are known.
- `launch_profiles=preview_only`: launch commands do not start workers by default.
- `diagnostics=safe_reports`: diagnostics avoid raw logs and environment dumps.
- `packaging_preview=metadata_only`: no artifact upload or install.
- `windows_launcher_preview=dry_run_only`: no host mutation.

token_printed=false
