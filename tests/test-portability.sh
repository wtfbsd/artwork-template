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

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/portability-test.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 1' INT TERM

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

# lint_hits PATTERN ERRORFILE : the lines of every shell file that match
# PATTERN, one per line, as FILE:LINE:TEXT. Binary files are never matched
# (grep -I). A file grep could not run the pattern in (exit status above 1:
# the pattern was rejected) is reported in ERRORFILE: that is an error, not
# "no match".
lint_hits() {
	printf '%s\n' "$FILES" | grep -v '/tests/test-portability\.sh$' | while IFS= read -r _f; do
		_st=0
		grep -IHnE -- "$1" "$_f" 2>/dev/null || _st=$?
		if [ "$_st" -gt 1 ]; then
			printf 'grep exited %s on %s (pattern rejected?)\n' "$_st" "$_f" >> "$2"
		fi
	done
}

# lint DESCRIPTION ERE SAMPLE : no script line (comments aside) may match
# ERE. SAMPLE is a line ERE has to match: a pattern that matches nothing
# (a typo in a bracket expression) would report "no match" on every file
# and pass this suite for ever.
lint() {
	_desc=$1
	_pat=$2
	_sample=$3
	if printf '%s\n' "$_sample" | grep -qE -- "$_pat"; then
		ok "lint pattern catches its known-bad sample: $_desc"
	else
		fail "lint pattern matches nothing (typo?): $_desc"
	fi
	_errf="$TMPD/lint-err"
	: > "$_errf"
	_hits=$(lint_hits "$_pat" "$_errf" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
	if [ -s "$_errf" ]; then
		fail "$_desc: grep could not run the pattern"
		sed 's/^/    /' "$_errf" >&2
	fi
	if [ -z "$_hits" ]; then
		ok "$_desc"
	else
		fail "$_desc:"
		printf '%s\n' "$_hits" | sed 's/^/    /' >&2
	fi
}

# An empty alternative, "(a|)" or "(|a)": BSD regcomp says "empty (sub)expression".
lint 'no empty alternative in a regex' '\(\||\|\)' "p='(|'"
# GNU-only options and escapes.
lint 'no sed -i (differs between GNU and BSD)' 'sed[[:space:]]+(-[A-Za-z]*[[:space:]]+)*-i' "sed -i 's/a/b/' f"
lint 'no \U / \L case escapes in sed' 'sed .*\\[UL]' "sed 's/a/\Ub/' f"
lint 'no grep --exclude/--include (not in every grep)' 'grep .*--(ex|in)clude' "grep --exclude='*.o' -r ."
lint 'no readlink -f / realpath' 'readlink -f|realpath ' 'p=$(readlink -f "$0")'
lint 'no stat -c / date -d (GNU forms)' 'stat -c|date -d ' "stat -c %s \"\$f\""
lint 'no echo -e / echo -n' 'echo -[en] ' 'echo -n "$x"'
lint 'no bash-only [[ ]] or local' '\[\[ |^[[:space:]]*local ' 'if [[ -n "$x" ]]; then'
# Bash and ksh constructs a POSIX sh (dash, ash, illumos ksh in sh mode) lacks.
lint 'no function keyword, source, declare, typeset or let' '(^[[:space:]]*|[;&|][[:space:]]*|(then|do|else)[[:space:]]+)(function[[:space:]]+[A-Za-z_]|source[[:space:]]|declare[[:space:]]|typeset[[:space:]]|let[[:space:]])' 'function greet {'
lint 'no == inside [ ]' '(^|[[:space:]])\[ [^]]*[[:space:]]==[[:space:]]' 'if [ "$a" == "$b" ]; then'
lint 'no arrays' '(^|[[:space:]])[A-Za-z_][A-Za-z0-9_]*=\(|\$\{[A-Za-z_][A-Za-z0-9_]*\[|\$\{#[A-Za-z_][A-Za-z0-9_]*\[' 'files=(a b c)'
lint 'no ${var/...}, ${var:N} or ${!var}' '\$\{[A-Za-z_][A-Za-z0-9_]*(/|:[0-9])|\$\{!' 'echo ${name/a/b}'
lint "no \$'...' strings, <<< or &>" "\\\$'[^' ]*\\\\[abefnrtvx0]|<<<|[^>&0-9]&>" "echo \$'a\\nb'"
lint 'no pushd, popd, $RANDOM or $(<file)' '(^|[[:space:]])(pushd|popd)([[:space:]]|$)|\$RANDOM|\$\(<' 'pushd /tmp'
# GNU-only options and tools that are missing on some of the five systems.
lint 'no grep -P' 'grep[[:space:]]+-[A-Za-z]*P' 'grep -P pattern file'
lint 'no sed -r' 'sed[[:space:]]+-[A-Za-z]*r[A-Za-z]*[[:space:]]' "sed -r 's/a/b/' f"
lint 'no xargs -r' 'xargs[[:space:]]+-[A-Za-z]*r' 'xargs -r ls'
lint 'no sort -V' 'sort[[:space:]]+-[A-Za-z]*V' 'sort -V'
lint 'no find -printf' '-printf[[:space:]]' "find . -printf '%p\\n'"
lint 'no seq or tac' '(^|[[:space:];|(`])(seq|tac)[[:space:]]' 'seq 1 10'

# A pattern grep rejects must fail the suite, not pass it as "no match".
: > "$TMPD/lint-broken-err"
lint_hits '[' "$TMPD/lint-broken-err" > /dev/null
if [ -s "$TMPD/lint-broken-err" ]; then
	ok 'a pattern grep rejects is reported as an error'
else
	fail 'a pattern grep rejects is silently taken for no match'
fi

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
