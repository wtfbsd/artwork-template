#!/bin/sh
# tests/test-portability.sh -- the scripts must run under the BSD tools of
# every target (FreeBSD, NetBSD, OpenBSD, DragonFly, illumos), not only GNU.
#
# Flags constructs that GNU accepts and a BSD grep, sed or awk rejects or
# reads differently. Run the other suites with busybox grep/sed/awk first on
# PATH as well (see README) for a second, non-GNU opinion.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$(dirname -- "$HERE")" && pwd)

FAILURES=0
PASSES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { printf 'ok: %s\n' "$1"; PASSES=$((PASSES + 1)); }

# lint DESCRIPTION ERE : no script line (comments aside) may match ERE
lint() {
	_hits=$(find "$ROOT/scripts" "$ROOT/tests" -name '*.sh' ! -name test-portability.sh -exec grep -nE -- "$2" {} + 2>/dev/null |
		grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
	if [ -z "$_hits" ]; then
		ok "$1"
	else
		fail "$1:"
		printf '%s\n' "$_hits" | sed 's/^/    /' >&2
	fi
}

# An empty alternative, "(a|)" or "(|a)": BSD regcomp says "empty (sub)expression".
lint 'no empty alternative in a regex' '\(\||\|\)'
# GNU-only options and escapes.
lint 'no sed -i (differs between GNU and BSD)' 'sed[[:space:]]+(-[A-Za-z]*[[:space:]]+)*-i'
lint 'no \U / \L case escapes in sed' 'sed .*\\[UL]'
lint 'no grep --exclude/--include (not in every grep)' 'grep .*--(ex|in)clude'
lint 'no readlink -f / realpath' 'readlink -f|realpath '
lint 'no stat -c / date -d (GNU forms)' 'stat -c|date -d '
lint 'no echo -e / echo -n' 'echo -[en] '
lint 'no bash-only [[ ]] or local' '\[\[ |^[[:space:]]*local '

printf 'test-portability.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
