#!/usr/bin/env bash
# tests/lib.sh - shared primitives for dotfiles behavior tests.
#
# Source this from a test file:
#   # shellcheck source=tests/lib.sh
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# ROOT is exported as the repository root (this file lives in tests/).

if [ -n "${DOTFILES_TEST_LIB_SOURCED:-}" ]; then
  return 0
fi
DOTFILES_TEST_LIB_SOURCED=1

# shellcheck disable=SC2034
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

# --- self-cleaning temp root -------------------------------------------------

# Callers take dirs via command substitution, which runs in a subshell, so the
# cleanup trap must belong to the sourcing shell: set it here, once, and keep
# every dir under one root it removes.
DOTFILES_TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")
dotfiles_test_cleanup() { rm -rf "$DOTFILES_TEST_TMP"; }
trap dotfiles_test_cleanup EXIT

dotfiles_test_tmproot() {
  mktemp -d "$DOTFILES_TEST_TMP/${1:-dotfiles-test}.XXXXXX"
}

# --- assertions ---------------------------------------------------------------

assert_contains() {
  local haystack=$1 needle=$2 message=$3
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$message" ;;
  esac
}

assert_not_contains() {
  local haystack=$1 needle=$2 message=$3
  case "$haystack" in
    *"$needle"*) fail "$message" ;;
    *) : ;;
  esac
}

# --- deterministic git fixtures ------------------------------------------------

dotfiles_git_init_commit() {
  local dir=$1
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '# %s\n' "$(basename "$dir")" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" -c user.name=dotfiles-test -c user.email=dotfiles-test@example.invalid \
    commit -qm "fixture"
}
