# Portable Package Reproducibility Preview

The reproducibility preview rebuilds the package candidate under `.agent/tmp` and compares safe metadata.

It compares:

- manifest identity fields;
- included file lists;
- package checksum when stable.

Zip archive checksums may differ because archive tools can include timestamps. That does not fail the preview when the manifest and file list match. In that case the report uses `reproducible_manifest=true`, `reproducible_file_list=true`, and `reproducible_archive=false` with a timestamp reason.

No package is uploaded, installed, or released. `token_printed=false`.

