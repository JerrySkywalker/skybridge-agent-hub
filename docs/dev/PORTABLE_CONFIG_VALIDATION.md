# Portable Config Validation

Portable config validation requires:

- no secrets or tokens
- no host absolute secret paths
- `execution_enabled=false`
- `queue_apply_enabled=false`
- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `token_printed=false`

The fixture validation block uses `skybridge.portable_config_validation.v1`.
