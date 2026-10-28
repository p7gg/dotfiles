set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes.
default:
    @just --list

# Provision packages, dotfiles, shell, and services (profile auto-detects).
bootstrap profile="auto" *args:
    ./provisioning/arch/bootstrap.sh --profile {{ quote(profile) }} {{ args }}

# Preview bootstrap actions without changing anything.
dry-run profile="auto" *args:
    ./provisioning/arch/bootstrap.sh --profile {{ quote(profile) }} --dry-run {{ args }}

# Validate bootstrap prerequisites without changing anything.
check profile="auto" *args:
    ./provisioning/arch/bootstrap.sh --profile {{ quote(profile) }} --check {{ args }}

# Report installed-versus-tracked package drift.
audit profile="auto" *args:
    ./provisioning/arch/audit.sh --profile {{ quote(profile) }} {{ args }}

# Fail when tracked packages are missing (--strict also checks untracked).
audit-check profile="auto" *args:
    ./provisioning/arch/audit.sh --profile {{ quote(profile) }} --check {{ args }}

# Run the read-only Windows host audit from WSL.
windows-audit *args:
    ./provisioning/windows/run.sh audit {{ args }}

# Generate fish completions for mise and user-installed tools.
completions *args:
    ./provisioning/arch/tools/completions.sh {{ args }}

# Browse or install optional Nerd Fonts.
fonts *args:
    ./provisioning/arch/tools/fonts.sh {{ args }}

# Run interactive authentication setup (generates the SSH key if needed).
auth *args:
    ./provisioning/arch/auth.sh --generate-key {{ args }}

# Report missing authentication without changing anything.
auth-check *args:
    ./provisioning/arch/auth.sh --check {{ args }}

# Run the one-time WSL root initialization.
wsl-init *args:
    sudo ./provisioning/arch/wsl-init.sh {{ args }}

# Show pending chezmoi changes.
diff:
    chezmoi diff

# Apply managed dotfiles.
apply:
    chezmoi apply

# Preview dotfile changes verbosely.
apply-dry-run:
    chezmoi apply --dry-run --verbose

# Pull and apply chezmoi updates.
update:
    chezmoi update

# Run shell, fish, workflow, and secret lint checks.
lint:
    ./scripts/lint.sh

# Format shell, fish, and Just files in place.
fmt:
    ./scripts/fmt.sh

# Run docs, template, and bats tests.
test:
    ./scripts/test.sh

# Run the full local validation suite (lint and tests).
verify: lint test

# Print the state of repository tools and auth.
doctor:
    ./scripts/doctor.sh

# Render every chezmoi template with test data.
render:
    ./tests/render-templates.sh
