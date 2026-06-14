# Local Config and First-run RC

The RC config wizard uses `fixtures/productization/local-config.example.json` as the safe profile example.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-config.ps1 -Command report
```

Reports:
- `.agent/tmp/product-readiness/local-config-validation-report.json`
- `.agent/tmp/product-readiness/local-config-redaction-report.json`

Do not add secrets, tokens, Authorization headers, cookies, private keys, raw pairing codes, approval secrets, or secret-bearing local paths.
