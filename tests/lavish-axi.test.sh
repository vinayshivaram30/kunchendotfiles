#!/usr/bin/env bash
# Build the declared package without activating Home Manager.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export LAVISH_DOTFILES_ROOT="$ROOT"
PACKAGE=$(nix build --impure --no-link --print-out-paths --expr '
  let
    f = builtins.getFlake ("path:" + builtins.getEnv "LAVISH_DOTFILES_ROOT");
    system = f.darwinConfigurations.mac;
    users = system.config.home-manager.users;
    packages = (builtins.head (builtins.attrValues users)).home.packages;
    matches = builtins.filter (p: system.pkgs.lib.getName p == "lavish-axi") packages;
  in if builtins.length matches == 1 then builtins.head matches
     else throw "Expected one declared lavish-axi package"
')
"$PACKAGE/bin/lavish-axi" --version | grep -F '0.1.77'
"$PACKAGE/bin/lavish-axi" --help >/dev/null
printf 'ok - declared Lavish package builds and CLI starts: %s\n' "$PACKAGE"
