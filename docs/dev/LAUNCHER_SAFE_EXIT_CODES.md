# Launcher Safe Exit Codes

Exit codes:

- `0`: command completed and returned safe metadata
- `2`: validation or internal safe failure
- `64`: unknown, unsafe or blocked command rejected before routing

The launcher never treats a rejected command as an invitation to run shell text. Use `.\skybridge.ps1 status` or `.\skybridge.ps1 start-preview` as the next safe action.
