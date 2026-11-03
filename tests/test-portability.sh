#!/bin/sh
# tests/test-portability.sh -- the scripts must run under the BSD tools of
# every target (FreeBSD, NetBSD, OpenBSD, DragonFly, illumos), not only GNU.
#
# Covers every shell file: *.sh and any file starting with a #!/bin/sh line
# (Xsetup_0, xinitrc, the session helper). Flags bash-only constructs and
# options that GNU accepts and a BSD grep, sed, awk or find rejects or reads
# differently, parses each file with every POSIX shell found (dash, busybox
# sh), and, when shellcheck is installed, wants none of its POSIX-sh
# warnings (SC3xxx). Run the other suites with busybox grep/sed/awk first on
# PATH as well (see README) for a second, non-GNU opinion.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$(dirname -- "$HERE")" && pwd)

FAILURES=0
PASSES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { printf 'ok: %s\n' "$1"; PASSES=$((PASSES + 1)); }

# Every shell file in the repository, one per line.
FILES=$(find "$ROOT" \( -name .git -o -name out -o -name dist -o -name docs \) -prune -o -type f -print |
	while IFS= read -r _f; do
		case $_f in
		*.sh) printf '%s\n' "$_f" ;;
		*) head -n 1 "$_f" 2>/dev/null | grep -Eq '^#![[:space:]]*(/bin/sh|/usr/bin/env[[:space:]]+sh)([[:space:]]|$)' &&
			printf '%s\n' "$_f" ;;
		esac
	done | sort)
[ -n "$FILES" ] || { printf 'test-portability.sh: no shell files found\n' >&2; exit 1; }
for _want in scripts/render.sh dm/xenodm/Xsetup_0 xinit/xinitrc.example 'xfce/session/@NAME_LOWER@-wallpaper.sh'; do
	printf '%s\n' "$FILES" | grep -qxF "$ROOT/$_want" && ok "checks $_want" || fail "does not check $_want"
done

# lint DESCRIPTION ERE : no script line (comments aside) may match ERE
lint() {
	_hits=$(printf '%s\n' "$FILES" | grep -v '/tests/test-portability\.sh$' | while IFS= read -r _f; do
		grep -nE -- "$2" "$_f" 2>/dev/null | sed "s|^|$_f:|"
	done | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
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
# Bash and ksh constructs a POSIX sh (dash, ash, illumos ksh in sh mode) lacks.
lint 'no function keyword, source, declare, typeset or let' '(^[[:space:]]*|[;&|][[:space:]]*|(then|do|else)[[:space:]]+)(function[[:space:]]+[A-Za-z_]|source[[:space:]]|declare[[:space:]]|typeset[[:space:]]|let[[:space:]])'
lint 'no == inside [ ]' '(^|[[:space:]])\[ [^]]*[[:space:]]==[[:space:]]'
lint 'no arrays' '(^|[[:space:]])[A-Za-z_][A-Za-z0-9_]*=\(|\$\{[A-Za-z_][A-Za-z0-9_]*\[|\$\{#[A-Za-z_][A-Za-z0-9_]*\['
lint 'no ${var/...}, ${var:N} or ${!var}' '\$\{[A-Za-z_][A-Za-z0-9_]*(/|:[0-9])|\$\{!'
lint "no \$'...' strings, <<< or &>" "\\\$'[^' ]*\\\\[abefnrtvx0]|<<<|[^>&0-9]&>"
lint 'no pushd, popd, $RANDOM or $(<file)' '(^|[[:space:]])(pushd|popd)([[:space:]]|$)|\$RANDOM|\$\(<'
# GNU-only options and tools that are missing on some of the five systems.
lint 'no grep -P, sed -r, xargs -r, sort -V or find -printf' 'grep[[:space:]]+-[A-Za-z]*P|sed[[:space:]]+-[A-Za-z]*r[A-Za-z]*[[:space:]]|xargs[[:space:]]+-[A-Za-z]*r|sort[[:space:]]+-[A-Za-z]*V|-printf[[:space:]]'
lint 'no seq or tac' '(^|[[:space:];|(`])(seq|tac)[[:space:]]'

# Every file parses in every POSIX shell found here.
for _sh in dash 'busybox sh'; do
	command -v "${_sh%% *}" >/dev/null 2>&1 || { printf 'skip: %s not installed\n' "$_sh"; continue; }
	_bad=$(printf '%s\n' "$FILES" | while IFS= read -r _f; do
		$_sh -n "$_f" > /dev/null 2>&1 || printf ' %s' "${_f#"$ROOT/"}"
	done)
	if [ -z "$_bad" ]; then ok "every shell file parses with $_sh"; else fail "$_sh -n fails on:$_bad"; fi
done

# shellcheck's POSIX-sh warnings (SC3xxx: "In POSIX sh, ... is undefined").
if command -v shellcheck >/dev/null 2>&1; then
	_hits=$(printf '%s\n' "$FILES" | while IFS= read -r _f; do
		shellcheck -s sh -f gcc "$_f" 2>/dev/null || true
	done | grep -E 'SC3[0-9]{3}' || true)
	if [ -z "$_hits" ]; then ok 'shellcheck: no POSIX-sh warnings'; else
		fail 'shellcheck POSIX-sh warnings:'
		printf '%s\n' "$_hits" | sed 's/^/    /' >&2
	fi
else
	printf 'skip: shellcheck not installed\n'
fi

printf 'test-portability.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
