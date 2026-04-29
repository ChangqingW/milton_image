#!/usr/bin/env bash
# Run a command inside the Milton-compatible Apptainer sandbox with controlled
# file access. HPC library paths (R/FlexiBLAS stack) are always bind-mounted
# read-only. Pass additional paths and the command to run as arguments.
#
# Usage:
#   ./run.sh [-v] [--home ro|rw|no] [--bind /src[:/dst][:ro|rw]] ... COMMAND [args...]
#
# Examples:
#   # Verify R works
#   ./run.sh Rscript -e 'sessionInfo()'
#
#   # Interactive shell with module support
#   ./run.sh bash
#   # then: module load quarto && quarto render doc.qmd
#
#   # Read-only data, writable scratch output
#   ./run.sh \
#     --bind /stornext/projects/bioinf/data:/data:ro \
#     --bind /vast/scratch/users/$USER/output:/output:rw \
#     Rscript /project/analysis.R

set -euo pipefail

VERBOSE=0
HOME_MODE=no

# First pass: extract script-level flags before bind arrays are built
_REMAINING=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v) VERBOSE=1; shift ;;
        --home)
            HOME_MODE="${2:-}"
            [[ "$HOME_MODE" =~ ^(ro|rw|no)$ ]] || { echo "ERROR: --home must be ro, rw, or no" >&2; exit 1; }
            shift 2 ;;
        *) _REMAINING+=("$1"); shift ;;
    esac
done
set -- "${_REMAINING[@]+"${_REMAINING[@]}"}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
IMAGE=$SCRIPT_DIR/milton.sif

if [[ ! -f $IMAGE ]]; then
    echo "ERROR: $IMAGE not found."
    echo "Pull it from GHCR or build with build.sh on a machine with root."
    exit 1
fi

# ── HPC bind mount ────────────────────────────────────────────────────────────
# /stornext/System covers all module-managed software and modulefiles
HPC_BINDS=(
    "/stornext/System:/stornext/System:ro"
    "/lib:/lib:ro"
    "/lib64:/lib64:ro"
    "/etc/localtime:/etc/localtime:ro"
    "/etc/fonts:/etc/fonts:ro"
    "/usr/local/share:/usr/local/share:ro"
    "/usr/share:/usr/share:ro"
)

# ── Home directory bind mount ─────────────────────────────────────────────────
# Mounts $HOME as a base before .claude is overlaid; mode set by --home flag.
HOME_BINDS=()
[[ "$HOME_MODE" != "no" ]] && HOME_BINDS+=("$HOME:$HOME:$HOME_MODE")

# Individual home-dir entries track the home mode; ro unless explicitly rw.
[[ "$HOME_MODE" == "rw" ]] && FILE_MODE=rw || FILE_MODE=ro

# ── Application bind mounts ───────────────────────────────────────────────────
# Use $HOME (the symlinked path) for bind mount destinations — Apptainer sets
# HOME inside the container from /etc/passwd, which gives the symlinked path.

# Auto-detect current Claude Code binary (survives 'claude update')
CLAUDE_BIN=$(readlink -f "$HOME/.local/bin/claude" 2>/dev/null) || CLAUDE_BIN=""

# ── Isolated Claude config ────────────────────────────────────────────────────
# The sandbox gets its own ~/.claude and ~/.claude.json so permissions and
# settings are independent from the host Claude installation.
SANDBOX_HOME=$SCRIPT_DIR/sandbox-home
mkdir -p "$SANDBOX_HOME/.claude"
[[ -f "$SANDBOX_HOME/.claude.json" ]] || touch "$SANDBOX_HOME/.claude.json"

# Intercept compinit before any plugin can call it without -u, then hand off
# to the real dotfiles by unsetting ZDOTDIR.
cat > "$SANDBOX_HOME/.zshenv" <<'EOF'
unset ZDOTDIR
[[ -f "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
if [[ -o interactive ]]; then
    autoload -Uz compinit
    compinit -u
    compinit() {
        unfunction compinit
        autoload -Uz compinit
        compinit -u "$@"
    }
fi
EOF

APP_BINDS=(
    "$HOME/R:$HOME/R:$FILE_MODE"
    "$HOME/.local:$HOME/.local:$FILE_MODE"
    "$SANDBOX_HOME/.claude:$HOME/.claude:rw"
    "$SANDBOX_HOME/.claude.json:$HOME/.claude.json:rw"
)

# RC files — bind only if they exist; missing file sources cause silent failures
for rc in .bashrc .bash_profile .zshrc .zshenv .profile .Renviron; do
    [[ -f "$HOME/$rc" ]] && APP_BINDS+=("$HOME/$rc:$HOME/$rc:$FILE_MODE")
done

[[ -d "$HOME/.config" ]] && APP_BINDS+=("$HOME/.config:$HOME/.config:$FILE_MODE")
[[ -n "$CLAUDE_BIN" ]] && APP_BINDS+=("$CLAUDE_BIN:/usr/local/bin/claude:ro")

# ── Current working directory ─────────────────────────────────────────────────
# Mount CWD read-write so the sandbox can edit project files; overlay .git
# read-only on top to protect history. The parent bind must come first so the
# more-specific .git mount takes precedence.
# should not matter with v1.2.4+: shortest path is always mounted first
if [[ "$PWD" != "$HOME" ]]; then
    APP_BINDS+=("$PWD:$PWD:rw")
    [[ -d "$PWD/.git" ]] && APP_BINDS+=("$PWD/.git:$PWD/.git:ro")
fi

# ── Build --bind argument list ────────────────────────────────────────────────
BIND_ARGS=()
for b in "${HPC_BINDS[@]}" "${HOME_BINDS[@]}" "${APP_BINDS[@]}"; do
    BIND_ARGS+=(--bind "$b")
done

# ── Parse caller-supplied --bind flags; collect remaining args as the command ─
EXTRA_BINDS=()
CMD=()
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--bind" && $# -gt 1 ]]; then
        EXTRA_BINDS+=(--bind "$2")
        shift 2
    else
        CMD+=("$1")
        shift
    fi
done

if [[ ${#CMD[@]} -eq 0 ]]; then
    echo "Usage: $0 [-v] [--home ro|rw|no] [--bind /src[:/dst][:ro|rw]] ... COMMAND [args...]"
    exit 1
fi

ENV_ARGS=(
    --env "USER=$USER"
    --env "TERM=${TERM:-xterm-256color}"
    --env "LANG=${LANG:-en_US.UTF-8}"
    --env "TZ=${TZ:-$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')}"
    --env "ZDOTDIR=$SANDBOX_HOME"
    --env "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}"
    --env "PATH=/usr/local/bin:/usr/bin:/bin${PATH:+:$PATH}"
)
# Only pass these if set on host; an empty value is worse than absent
[[ -n "${R_HOME:-}" ]]     && ENV_ARGS+=(--env "R_HOME=$R_HOME")
[[ -n "${MODULEPATH:-}" ]] && ENV_ARGS+=(--env "MODULEPATH=$MODULEPATH")

# ── User-local overrides ──────────────────────────────────────────────────────
# run.local.sh (git-ignored) can append to USER_BINDS and USER_ENVS, e.g.:
#   USER_BINDS+=(--bind "/data:/data:ro")
#   USER_ENVS+=(--env "MY_VAR=value")
USER_BINDS=()
USER_ENVS=()
[[ -f "$SCRIPT_DIR/run.local.sh" ]] && source "$SCRIPT_DIR/run.local.sh"

if [[ $VERBOSE -eq 1 ]]; then
    echo "==> home mode: $HOME_MODE" >&2
    echo "==> Apptainer bind arguments:" >&2
    for b in "${HPC_BINDS[@]}" "${HOME_BINDS[@]}" "${APP_BINDS[@]}" "${EXTRA_BINDS[@]}" "${USER_BINDS[@]}"; do
        echo "    --bind $b \\" >&2
    done
    echo "    ${CMD[*]}" >&2
fi

exec apptainer exec \
    --no-home \
    --cleanenv \
    --writable-tmpfs \
    "${BIND_ARGS[@]}" \
    "${EXTRA_BINDS[@]}" \
    "${USER_BINDS[@]}" \
    "${ENV_ARGS[@]}" \
    "${USER_ENVS[@]}" \
    "$IMAGE" \
    "${CMD[@]}"
