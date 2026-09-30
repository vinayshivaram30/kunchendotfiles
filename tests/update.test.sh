#!/usr/bin/env bash
# update.sh and rebuild.sh's daily update check, against a fixture repo with
# network and nix commands stubbed on PATH.
set -euo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(dotfiles_test_tmproot dotfiles-update)
STUBS="$TMP/stubs"
mkdir -p "$STUBS"

cat > "$STUBS/nix" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "flake update") echo bumped >> flake.lock ;;
  "store prefetch-file") echo '{"hash":"sha256-NEW"}' ;;
  "build "*) exit "${STUB_BUILD_EXIT:-0}" ;;
  *) echo "unexpected nix $*" >&2; exit 99 ;;
esac
EOF
cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"tag_name":"v9.9.9"}'
EOF
cat > "$STUBS/npm" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  view) echo 9.9.9 ;;
  install) echo '{"dependencies":{"tool":"9.9.9"}}' > package.json ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$STUBS"/*
export PATH="$STUBS:$PATH" DOTFILES_UPDATE_SHELL=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# Fixture: a fork with an upstream that has one new commit, and a dirty live
# config file that the updater must never touch or commit.
fixture() {
  local repo=$1
  dotfiles_git_init_commit "$TMP/upstream-$2"
  git clone -q "$TMP/upstream-$2" "$repo"
  git -C "$TMP/upstream-$2" commit -q --allow-empty -m "upstream change"
  git -C "$repo" remote rename origin upstream
  cp "$ROOT/update.sh" "$ROOT/rebuild.sh" "$repo/"
  mkdir -p "$repo/home/pkgs/tool" "$repo/home/.pi/agent" "$repo/tests"
  echo lock > "$repo/flake.lock"
  echo '{"tool":{"version":"1.0.0","hash":"sha256-OLD"}}' > "$repo/home/pkgs/releases.json"
  echo '{"dependencies":{"tool":"1.0.0"}}' > "$repo/home/pkgs/tool/package.json"
  echo '{"packages":["npm:@scope/pi-ext@1.0.0"]}' > "$repo/home/.pi/agent/settings.json"
  echo clean > "$repo/notes.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm fixture
  echo "user edit" > "$repo/notes.txt"
}

# --- success: pulls upstream, bumps every pin, commits only pin files --------
R="$TMP/ok"; fixture "$R" ok
export HOME="$TMP/home-ok"; mkdir -p "$HOME"
"$R/update.sh" >/dev/null 2>&1 || fail "update.sh succeeds when build and tests pass"
log=$(git -C "$R" log --format=%s)
assert_contains "$log" "upstream change" "upstream commits are merged"
assert_contains "$log" "chore: update pinned dependencies" "pin bumps are committed"
assert_contains "$(cat "$R/home/pkgs/releases.json")" '"9.9.9"' "release binary version bumped"
assert_contains "$(cat "$R/home/pkgs/releases.json")" 'sha256-NEW' "release binary hash refreshed"
assert_contains "$(cat "$R/home/pkgs/tool/package.json")" '9.9.9' "npm tool bumped"
assert_contains "$(cat "$R/home/.pi/agent/settings.json")" 'npm:@scope/pi-ext@9.9.9' "pi package bumped"
assert_contains "$(cat "$R/flake.lock")" bumped "flake inputs updated"
[ "$(git -C "$R" status --porcelain)" = " M notes.txt" ] || fail "user's dirty file stays uncommitted and untouched"
[ -f "$HOME/.local/state/dotfiles/last-update" ] || fail "success records the update time"
pass "update.sh merges upstream, bumps pins and commits only pin files"

# --- failure: build breaks, everything rolls back -----------------------------
R="$TMP/bad"; fixture "$R" bad
export HOME="$TMP/home-bad"; mkdir -p "$HOME"
start=$(git -C "$R" rev-parse HEAD)
if STUB_BUILD_EXIT=1 "$R/update.sh" >/dev/null 2>&1; then fail "update.sh fails when the build fails"; fi
[ "$(git -C "$R" rev-parse HEAD)" = "$start" ] || fail "failed update resets HEAD (upstream merge undone)"
[ "$(git -C "$R" status --porcelain)" = " M notes.txt" ] || fail "failed update restores pins and keeps user edits"
[ ! -e "$HOME/.local/state/dotfiles/last-update" ] || fail "failed update is retried next time"
pass "update.sh rolls back cleanly when the build fails"

# --- dirty pin file: refuse to run --------------------------------------------
R="$TMP/dirty"; fixture "$R" dirty
echo edit >> "$R/flake.lock"
start=$(git -C "$R" rev-parse HEAD)
if "$R/update.sh" >/dev/null 2>&1; then fail "update.sh refuses to run over uncommitted pin edits"; fi
[ "$(git -C "$R" rev-parse HEAD)" = "$start" ] || fail "refused update changes nothing"
assert_contains "$(cat "$R/flake.lock")" edit "refused update keeps the user's pin edit"
pass "update.sh leaves uncommitted pin edits alone"

# --- rebuild.sh: runs update when stale, skips when fresh, never blocks switch -
R="$TMP/rb"; mkdir -p "$R"
cp "$ROOT/rebuild.sh" "$R/"
cat > "$R/update.sh" <<'EOF'
#!/usr/bin/env bash
echo ran >> "$HOME/update-calls"
exit "${STUB_UPDATE_EXIT:-0}"
EOF
cat > "$STUBS/sudo" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$HOME/sudo-calls"
EOF
chmod +x "$R/update.sh" "$STUBS/sudo"
export HOME="$TMP/home-rb"; mkdir -p "$HOME/.local/state/dotfiles"

"$R/rebuild.sh" >/dev/null 2>&1
[ "$(wc -l < "$HOME/update-calls")" -eq 1 ] || fail "rebuild.sh updates when no update ever ran"
touch "$HOME/.local/state/dotfiles/last-update"
"$R/rebuild.sh" >/dev/null 2>&1
[ "$(wc -l < "$HOME/update-calls")" -eq 1 ] || fail "rebuild.sh skips the update within 24h"
touch -t 202001010000 "$HOME/.local/state/dotfiles/last-update"
out=$(STUB_UPDATE_EXIT=1 "$R/rebuild.sh" 2>&1)
[ "$(wc -l < "$HOME/update-calls")" -eq 2 ] || fail "rebuild.sh updates when the last update is stale"
assert_contains "$out" "update failed" "rebuild.sh reports a failed update"
[ "$(wc -l < "$HOME/sudo-calls")" -eq 3 ] || fail "rebuild.sh always switches, even after a failed update"
assert_contains "$(cat "$HOME/sudo-calls")" "darwin-rebuild switch" "rebuild.sh switches"
pass "rebuild.sh runs the update at most daily and always switches"
