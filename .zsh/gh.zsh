# gh is installed by the tools phase — skip completion on fresh shells before that.
command -v gh >/dev/null 2>&1 && eval "$(gh completion -s zsh)"

# Reuse gh CLI auth for the GitHub MCP server (opencode reads this env var).
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)"
fi