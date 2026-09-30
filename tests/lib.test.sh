#!/usr/bin/env bash
# dotfiles_test_tmproot dirs survive the test body and are removed at exit,
# even when taken via command substitution (how every caller uses it).
set -euo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
dir=$(bash -c '. "$1"; d=$(dotfiles_test_tmproot lib-test); [ -d "$d" ] || exit 1; echo "$d"' _ "$ROOT/tests/lib.sh") \
  || fail "tmproot dir exists while the test runs"
[ ! -e "$dir" ] || fail "tmproot dir is removed when the test exits: $dir"
pass "dotfiles_test_tmproot cleans up at exit"
