default:
    @just --list

bootstrap profile="native":
    ./arch/bootstrap.sh --profile {{profile}}

dry-run profile="native":
    ./arch/bootstrap.sh --profile {{profile}} --dry-run

audit profile="native":
    ./arch/audit.sh --profile {{profile}}

completions:
    ./arch/completions.sh

auth:
    ./arch/auth.sh --generate-key

diff:
    chezmoi diff

apply:
    chezmoi apply

update:
    chezmoi update
