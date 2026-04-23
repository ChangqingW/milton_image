# milton-sandbox

Apptainer sandbox with ABI compatibility with Milton (RHEL 9.3).
Runs any command in a Rocky Linux 9 container with controlled file access
enforced via Apptainer bind mounts.


## How it works

- Minimal Rocky Linux 9 base image, binary-compatible with RHEL 9.3
- HPC libraries (R, FlexiBLAS, PCRE2, curl, libjpeg) are bind-mounted read-only
- `--no-home` + `--cleanenv` make everything outside explicit bind mounts invisible
- Pass additional paths per invocation with `--bind`

