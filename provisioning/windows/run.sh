#!/usr/bin/env bash
#
# Run the Windows provisioning scripts from WSL.
#
# The PowerShell scripts are the source of truth and also run natively on
# Windows. This wrapper only locates a Windows PowerShell host and translates
# the repository path with wslpath; it does not contain provisioning logic.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/provisioning/windows"

usage() {
    cat <<'EOF'
Usage: provisioning/windows/run.sh <command> [options]

Commands:
  audit [options]       Run the read-only Windows host audit
  bootstrap [options]   Install missing Windows packages
  settings [options]    Apply managed .wslconfig and Terminal settings

Options:
  -h, --help        Show this help

Environment:
  WINDOWS_POWERSHELL  Explicit path to pwsh.exe or powershell.exe

The wrapper must run inside WSL with interop enabled. On Windows, run the
PowerShell script directly instead.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[[ $# -gt 0 ]] || {
    usage >&2
    exit 1
}

subcommand="$1"
shift

case "$subcommand" in
audit)
    script="audit.ps1"
    ;;
bootstrap)
    script="bootstrap.ps1"
    ;;
settings)
    script="settings.ps1"
    ;;
-h | --help)
    usage
    exit 0
    ;;
*)
    die "unknown command: $subcommand (try --help)"
    ;;
esac

if ! grep -qi microsoft /proc/version 2>/dev/null; then
    die "this wrapper must run inside WSL; run the PowerShell script directly on Windows"
fi

find_powershell() {
    if [[ -n "${WINDOWS_POWERSHELL:-}" ]]; then
        [[ -x "$WINDOWS_POWERSHELL" ]] || return 1
        printf '%s\n' "$WINDOWS_POWERSHELL"
        return 0
    fi

    if command -v pwsh.exe >/dev/null 2>&1; then
        command -v pwsh.exe
        return 0
    fi

    if command -v powershell.exe >/dev/null 2>&1; then
        command -v powershell.exe
        return 0
    fi

    for candidate in \
        /mnt/c/Users/*/AppData/Local/Microsoft/WindowsApps/Microsoft.PowerShell_*/pwsh.exe \
        /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

powershell="$(find_powershell)" ||
    die "Windows PowerShell not found or not executable; enable WSL interop or set WINDOWS_POWERSHELL"

command -v wslpath >/dev/null 2>&1 || die "wslpath not found; run this inside WSL"

# PowerShell sees stdin as redirected when it runs through WSL interop, so its
# Read-Host prompt cannot be used here. Ask in the WSL terminal instead, then
# pass -Yes to the script. --help, -Check, -DryRun, and -Yes skip this.
if [[ ("$subcommand" == "bootstrap" || "$subcommand" == "settings") && -t 0 ]]; then
    has_yes=0
    has_noninteractive=0
    for arg in "$@"; do
        case "${arg,,}" in
        -yes | --yes) has_yes=1 ;;
        -check | --check | -dryrun | --dryrun | -dry-run | --dry-run) has_noninteractive=1 ;;
        esac
    done
    if ((has_yes == 0 && has_noninteractive == 0)); then
        if [[ "$subcommand" == "settings" ]]; then
            prompt="Apply Windows settings? [y/N] "
        else
            prompt="Install missing Windows packages? [y/N] "
        fi
        read -r -p "$prompt" answer
        [[ "$answer" =~ ^[Yy]$ ]] || {
            printf '%s\n' "Aborted."
            exit 1
        }
        set -- "$@" -Yes
    fi
fi

win_script="$(wslpath -w "$SCRIPT_DIR/$script")" ||
    die "could not translate $SCRIPT_DIR/$script to a Windows path"

exec "$powershell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$win_script" "$@"
