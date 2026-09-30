#!/usr/bin/env bash
# Pull upstream dotfiles and bump every pinned input to its latest release,
# then build and test. Commits on success; on any failure rolls back and exits
# non-zero, leaving the current pins in place. Never touches files outside the
# pin set, so live-edited config under home/ stays as you left it.
# Runs daily via the dotfiles-update launchd agent and from rebuild.sh.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$DIR"

# Pull node/jq/curl from the flake-locked nixpkgs so this also runs under
# launchd's bare PATH.
if [ -z "${DOTFILES_UPDATE_SHELL:-}" ]; then
  export DOTFILES_UPDATE_SHELL=1
  exec nix shell --inputs-from . nixpkgs#nodejs nixpkgs#jq nixpkgs#curl -c "$0" "$@"
fi

echo "update: $(date)"
PINS=(flake.lock home/pkgs home/.pi/agent/settings.json)
if [ -n "$(git status --porcelain -- "${PINS[@]}")" ]; then
  echo "update: uncommitted changes in ${PINS[*]}; commit or discard them first" >&2
  exit 1
fi
START=$(git rev-parse HEAD)
rollback() {
  echo "update: failed; rolling back to $START" >&2
  git checkout -q -- "${PINS[@]}"
  git reset -q --keep "$START"
}
trap rollback ERR

# jq can't edit in place.
jq_edit() { local f=$1; shift; jq "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }

if git remote get-url upstream >/dev/null 2>&1; then
  git fetch -q upstream
  git remote set-head upstream --auto >/dev/null
  git merge -q --no-edit upstream/HEAD || {
    git merge --abort
    echo "update: upstream merge conflicts; merge it by hand" >&2
  }
fi

nix flake update

# kunchenguid single-binary CLIs, fetched by releaseBin in home.nix.
R=home/pkgs/releases.json
for name in $(jq -r 'keys[]' "$R"); do
  v=$(curl -fsSL "https://api.github.com/repos/kunchenguid/$name/releases/latest" | jq -r .tag_name)
  v=${v#v}
  [ "$v" = "$(jq -r --arg n "$name" '.[$n].version' "$R")" ] && continue
  h=$(nix store prefetch-file --json \
    "https://github.com/kunchenguid/$name/releases/download/v$v/$name-v$v-darwin-arm64.tar.gz" | jq -r .hash)
  jq_edit "$R" --arg n "$name" --arg v "$v" --arg h "$h" '.[$n] = {version: $v, hash: $h}'
done

# npm CLIs: one lockfile per tool under home/pkgs/<tool>/.
for pkg in home/pkgs/*/package.json; do
  d=$(dirname "$pkg")
  # shellcheck disable=SC2046
  (cd "$d" && npm install --package-lock-only --ignore-scripts --save-exact --no-audit --no-fund \
    $(jq -r '.dependencies | keys | map(. + "@latest") | join(" ")' package.json))
done

# pi packages are installed by pi itself from these pins.
S=home/.pi/agent/settings.json
for spec in $(jq -r '.packages[] | select(startswith("npm:"))' "$S"); do
  name=${spec#npm:}
  name=${name%@*}
  jq_edit "$S" --arg old "$spec" --arg new "npm:$name@$(npm view "$name" version)" \
    '.packages |= map(if . == $old then $new else . end)'
done

nix build .#darwinConfigurations.mac.system --no-link
shopt -s nullglob
for t in tests/*.test.sh; do bash "$t"; done

git add -- "${PINS[@]}"
git diff --cached --quiet || git commit -q -m "chore: update pinned dependencies" -- "${PINS[@]}"
trap - ERR
STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/last-update"
mkdir -p "$(dirname "$STAMP")" && touch "$STAMP"
echo "update: done at $(git rev-parse --short HEAD)"
