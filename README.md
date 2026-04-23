# milton-sandbox

Image with ABI compatibility with Milton (RHEL 9.3).
Allows running any command in a Rocky Linux 9 container with controlled file access
enforced via Apptainer bind mounts.


## How it works

- Minimal Rocky Linux 9 base image, binary-compatible with RHEL 9.3
- Milton libraries (R, FlexiBLAS, PCRE2, curl, libjpeg) are bind-mounted read-only
- `--no-home` + `--cleanenv` make everything outside explicit bind mounts invisible
- Pass additional paths per invocation with `--bind`

## Build the image

Convert the Docker image from GHCR to an Apptainer image:

```bash
apptainer build sandbox.sif \
  docker://ghcr.io/changqingw/milton_image:latest
```

## Run

```bash
# Verify R works
./run.sh Rscript -e 'sessionInfo()'

# Read-only input data, writable output
./run.sh \
  --bind /stornext/projects/bioinf/data:/data:ro \
  --bind /vast/scratch/users/wang.ch/output:/output:rw \
  Rscript /data/analysis.R
```

Any `--bind` flags are consumed by `run.sh`; everything else is the command to execute.
