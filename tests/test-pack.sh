#!/bin/sh
# tests/test-pack.sh -- scripts/pack.sh writes one pre-rendered tarball per
# variant, named <slug>-<commit>-<variant>.tar.xz, with a sha256 file that
# verifies, holding out/, branding/spots.tsv, the identity scripts and the
# palettes, so a template can install without rendering on its build host.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$(dirname -- "$HERE")" && pwd)

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/pack-test.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 1' INT TERM

FAILURES=0
PASSES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { printf 'ok: %s\n' "$1"; PASSES=$((PASSES + 1)); }

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
	else sha256 -q "$1"; fi
}

SLUG=$(sed -nE 's/^[[:space:]]*NAME_LOWER="?([^"]*)"?[[:space:]]*$/\1/p' "$ROOT/palette.env")
if [ ! -f "$ROOT/scripts/pack.sh" ]; then
	fail 'scripts/pack.sh missing'
else
	if sh "$ROOT/scripts/pack.sh" --commit 0123456789ab "$TMPD/dist" > "$TMPD/pack.log" 2>&1; then
		ok 'pack.sh --commit'
	else
		fail 'pack.sh exited non-zero'
		sed 's/^/    /' "$TMPD/pack.log" >&2
	fi
	for v in default cyberpunk; do
		T="$TMPD/dist/$SLUG-0123456789ab-$v.tar.xz"
		if [ ! -f "$T" ]; then fail "missing $(basename "$T")"; continue; fi
		ok "$(basename "$T")"
		if [ -f "$T.sha256" ] && [ "$(cut -d ' ' -f 1 "$T.sha256")" = "$(sha256_of "$T")" ] &&
			grep -q " $(basename "$T")\$" "$T.sha256"; then
			ok "$(basename "$T").sha256 verifies"
		else
			fail "$(basename "$T").sha256 missing or wrong"
		fi
		X="$TMPD/x-$v"
		mkdir -p "$X"
		if xz -dc "$T" | (cd "$X" && tar -xf -); then ok "$v unpacks"; else fail "$v does not unpack"; continue; fi
		P="$X/$SLUG-0123456789ab-$v"
		for f in out/variant out/lightdm/greeter-1920x1080.png out/dm/xenodm/Xresources "out/dm/pixmaps/$SLUG-color.xpm" \
			out/loader/splash.png branding/spots.tsv BRANDING-SPOTS.md palette.env "variants/$v/palette.env" \
			scripts/identity-stamp.sh scripts/identity-file.sh scripts/lib-identity.sh PACK; do
			if [ -e "$P/$f" ]; then ok "$v pack has $f"; else fail "$v pack lacks $f"; fi
		done
		[ "$(cat "$P/out/variant" 2>/dev/null)" = "$v" ] && ok "$v pack is the $v render" || fail "$v pack holds the wrong variant"
		grep -q '^commit=0123456789ab$' "$P/PACK" 2>/dev/null && grep -q "^variant=$v\$" "$P/PACK" &&
			ok "$v PACK manifest" || fail "$v PACK manifest wrong"
		# The identity line can be stamped from the unpacked pack alone.
		sh "$P/scripts/identity-file.sh" --product ExampleBSD --version 1.0 --base 'NetBSD 11.0' --variant X --arch amd64 > "$TMPD/id"
		if sh "$P/scripts/identity-stamp.sh" --variant "$v" "$TMPD/id" "$P/out/lightdm/greeter-1920x1080.png" "$TMPD/s.png" > /dev/null 2>&1; then
			ok "$v pack stamps the identity line on its own"
		else
			fail "$v pack cannot stamp the identity line on its own"
		fi
	done
	# Bad commit strings are refused.
	if sh "$ROOT/scripts/pack.sh" --commit '../x' "$TMPD/bad" > /dev/null 2>&1; then
		fail 'pack.sh accepted a bad commit string'
	else
		ok 'pack.sh refuses a bad commit string'
	fi
fi

printf 'test-pack.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
