#!/usr/bin/env bash
# The daily launchd agent runs update.sh at 5am and Homebrew upgrades on switch.
set -euo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cfg=$(nix eval --json "path:$ROOT#darwinConfigurations.mac.config" --apply 'c: {
  agent = (builtins.head (builtins.attrValues c.home-manager.users)).launchd.agents.dotfiles-update.config;
  upgrade = c.homebrew.onActivation.upgrade;
}')
assert_contains "$cfg" '/.dotfiles/update.sh"' "agent runs update.sh"
assert_contains "$cfg" '"Hour":5' "agent runs at 5am"
assert_contains "$cfg" '"upgrade":true' "Homebrew upgrades on rebuild"
pass "daily update agent and Homebrew upgrades are declared"
