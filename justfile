set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

bootstrap profile="auto" *args:
    ./provisioning/arch/bootstrap.sh --profile {{ quote(profile) }} {{ args }}

dry-run profile="auto" *args:
    ./provisioning/arch/bootstrap.sh --profile {{ quote(profile) }} --dry-run {{ args }}

check profile="auto" *args:
    ./provisioning/arch/bootstrap.sh --profile {{ quote(profile) }} --check {{ args }}

audit profile="auto" *args:
    ./provisioning/arch/audit.sh --profile {{ quote(profile) }} {{ args }}

audit-check profile="auto" *args:
    ./provisioning/arch/audit.sh --profile {{ quote(profile) }} --check {{ args }}

completions *args:
    ./provisioning/arch/tools/completions.sh {{ args }}

fonts *args:
    ./provisioning/arch/tools/fonts.sh {{ args }}

auth *args:
    ./provisioning/arch/auth.sh --generate-key {{ args }}

auth-check *args:
    ./provisioning/arch/auth.sh --check {{ args }}

wsl-init *args:
    sudo ./provisioning/arch/wsl-init.sh {{ args }}

diff:
    chezmoi diff

apply:
    chezmoi apply

apply-dry-run:
    chezmoi apply --dry-run --verbose

update:
    chezmoi update

lint:
    ./scripts/lint.sh

fmt:
    ./scripts/fmt.sh

test:
    ./scripts/test.sh

doctor:
    ./scripts/doctor.sh

render:
    ./tests/render-templates.sh
