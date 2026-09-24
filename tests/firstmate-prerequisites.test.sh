#!/usr/bin/env bash
# Build and exercise Firstmate's prerequisites without activating Home Manager.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export FIRSTMATE_DOTFILES_ROOT="$ROOT"
TOOLS=$(nix build --impure --no-link --print-out-paths --expr '
  let
    f = builtins.getFlake ("path:" + builtins.getEnv "FIRSTMATE_DOTFILES_ROOT");
    system = f.darwinConfigurations.mac;
    users = system.config.home-manager.users;
    packages = (builtins.head (builtins.attrValues users)).home.packages;
    names = [ "gh" "treehouse" "no-mistakes" "gh-axi" "tasks-axi" "quota-axi" "chrome-devtools-axi" ];
    selected = map (name:
      let matches = builtins.filter (p: system.pkgs.lib.getName p == name) packages;
      in if builtins.length matches == 1 then builtins.head matches
         else throw "Expected one declared Firstmate prerequisite: ${name}"
    ) names;
  in system.pkgs.buildEnv { name = "firstmate-prerequisites-check"; paths = selected; }
')
for tool in gh treehouse no-mistakes gh-axi tasks-axi quota-axi chrome-devtools-axi; do
  "$TOOLS/bin/$tool" --version
done
"$TOOLS/bin/treehouse" get --help | grep -- --lease >/dev/null
"$TOOLS/bin/tasks-axi" update --help | grep -- --archive-body >/dev/null
"$TOOLS/bin/tasks-axi" mv --help | grep -F '[<id>...]' >/dev/null
printf 'ok - Firstmate prerequisites build and required CLI features pass\n'
