#!/bin/sh
# tests/test-render.sh -- run scripts/render.sh into a temporary directory,
# verify every expected PNG exists with the right pixel size, verify no
# unsubstituted @TOKEN@ remains in out/ text files, and verify that
# scripts/rebrand.sh rewrites the name in a copy of the repo and leaves
# src/ untouched.
#
# Usage: sh tests/test-render.sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$(dirname -- "$HERE")" && pwd)

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/artwork-test.XXXXXX")
cleanup() {
	rm -rf "$TMPD"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

FAILURES=0

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	FAILURES=$((FAILURES + 1))
}

ok() {
	printf 'ok: %s\n' "$1"
}

# --------------------------------------------------------------- render run
RENDER_OUT="$TMPD/out"
RENDER_LOG="$TMPD/render.log"
printf '== running scripts/render.sh (log: %s)\n' "$RENDER_LOG"
if ! sh "$ROOT/scripts/render.sh" "$ROOT/palette.env" "$RENDER_OUT" > "$RENDER_LOG" 2>&1; then
	printf 'FAILED: render.sh exited non-zero:\n'
	cat "$RENDER_LOG"
	exit 1
fi

# ---------------------------------------------------------- png size checks
png_size() {
	# png_size FILE : reads WIDTH HEIGHT from the PNG IHDR with python3.
	python3 -c 'import struct, sys
with open(sys.argv[1], "rb") as fh:
    head = fh.read(24)
if head[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit(1)
w, h = struct.unpack(">II", head[16:24])
print(str(w) + " " + str(h))' "$1"
}

expect_png() {
	# expect_png PATH WIDTH HEIGHT
	_f=$1
	_w=$2
	_h=$3
	if [ ! -f "$_f" ]; then
		fail "missing: $_f"
		return
	fi
	if ! _got=$(png_size "$_f"); then
		fail "unreadable png: $_f"
		return
	fi
	if [ "x$_got" != "x$_w $_h" ]; then
		fail "wrong size for $_f: got \"$_got\", want \"$_w $_h\""
	else
		ok "$_f"
	fi
}

LOWER=$(sed -nE 's/^[[:space:]]*NAME_LOWER="?([^\"]*)"?[[:space:]]*$/\1/p' "$ROOT/palette.env")

# logos
for s in 64 128 256 512; do
	expect_png "$RENDER_OUT/logo/logo-$s.png" "$s" "$s"
done
expect_png "$RENDER_OUT/logo/wordmark.png" 1200 300
expect_png "$RENDER_OUT/logo/wordmark-light.png" 1200 300
# splashes
expect_png "$RENDER_OUT/splash/splash-640x480.png" 640 480
expect_png "$RENDER_OUT/splash/splash-1024x768.png" 1024 768
expect_png "$RENDER_OUT/splash/splash-1920x1080.png" 1920 1080
# loader
expect_png "$RENDER_OUT/loader/loader-logo.png" 480 200
expect_png "$RENDER_OUT/loader/splash.png" 1024 768
# installer
expect_png "$RENDER_OUT/installer/header.png" 800 96
expect_png "$RENDER_OUT/installer/sidebar.png" 200 600
# lightdm
expect_png "$RENDER_OUT/lightdm/greeter-1920x1080.png" 1920 1080
# wallpapers
for n in 1 2 3; do
	expect_png "$RENDER_OUT/wallpapers/wallpaper-$n-1920x1080.png" 1920 1080
	expect_png "$RENDER_OUT/wallpapers/wallpaper-$n-3840x2160.png" 3840 2160
done
# icons
for s in 16 22 24 32 48 64 128 256; do
	for name in logo installer menu; do
		expect_png "$RENDER_OUT/icons/hicolor/${s}x$s/apps/$LOWER-$name.png" "$s" "$s"
	done
done
# favicon
for s in 16 32 48 180 192 512; do
	expect_png "$RENDER_OUT/favicon/favicon-$s.png" "$s" "$s"
done
[ -f "$RENDER_OUT/favicon/favicon.svg" ] ||
	fail "missing: $RENDER_OUT/favicon/favicon.svg"

# ------------------------------------------------- config/xfconf artifacts
for f in xfce/gtk-colors.css xfce/xfwm4-themerc \
	xfce/xfconf/xfce4-desktop.xml xfce/xfconf/xfce4-panel.xml \
	xfce/xfconf/xsettings.xml lightdm/lightdm-gtk-greeter.conf \
	xinit/xinitrc.example; do
	if [ -f "$RENDER_OUT/$f" ]; then
		ok "config $f"
	else
		fail "missing config: $f"
	fi
done

# ----------------------------------------------------- token-substitution
# XPM pixel codes may contain any printable run, so XPMs are skipped.
if find "$RENDER_OUT" -type f ! -name '*.xpm' ! -name '*.png' ! -name '*.ico' -exec grep -nE '@[A-Z0-9_]+@' {} + > "$TMPD/tokens.out" 2>/dev/null; then
	fail 'unsubstituted @TOKEN@ left in out/ text files:'
	sed 's/^/    /' "$TMPD/tokens.out" >&2
else
	ok 'no @TOKEN@ markers left in out/'
fi

# -------------------------------------------------------------- rebrand run
CPY="$TMPD/copy"
mkdir -p "$CPY"
for _d in palette.env src scripts variants xfce lightdm xinit dm console boot; do
	[ -e "$ROOT/$_d" ] && cp -R "$ROOT/$_d" "$CPY/"
done
rm -rf "$CPY/out"

_BEFORE=$(find "$CPY/src" -type f -exec cksum {} + | sort)

if ! (cd "$CPY" && sh scripts/rebrand.sh 'TestBSD 2 NutX' '0becb4' '#221f57') >> "$TMPD/rebrand.log" 2>&1; then
	fail 'rebrand.sh exited non-zero:'
	sed 's/^/    /' "$TMPD/rebrand.log" >&2
fi

if [ "$(find "$CPY/src" -type f -exec cksum {} + | sort)" != "$_BEFORE" ]; then
	fail 'rebrand.sh modified src/'
else
	ok 'rebrand.sh left src/ untouched'
fi

_palette_out=$(sed -nE 's/^[[:space:]]*NAME="?([^\"]*)"?[[:space:]]*$/\1/p' "$CPY/palette.env")
if [ "$_palette_out" = 'TestBSD 2 NutX' ]; then
	ok 'palette.env carries the new NAME'
else
	fail "palette.env NAME is \"$_palette_out\", expected 'TestBSD 2 NutX'"
fi
_palette_lower=$(sed -nE 's/^[[:space:]]*NAME_LOWER="?([^\"]*)"?[[:space:]]*$/\1/p' "$CPY/palette.env")
if [ "$_palette_lower" = 'testbsd-2-nutx' ]; then
	ok 'palette.env carries the derived NAME_LOWER'
else
	fail "palette.env NAME_LOWER is \"$_palette_lower\", expected 'testbsd-2-nutx'"
fi
grep -q '^PRIMARY=0BECB4$' "$CPY/palette.env" ||
	fail 'rebrand.sh did not apply the new PRIMARY to palette.env'
grep -q '^ACCENT=221F57$' "$CPY/palette.env" ||
	fail 'rebrand.sh did not apply the new ACCENT to palette.env'
ok 'rebrand.sh accepted new colors'

for f in \
	"$CPY/out/xfce/xfconf/xfce4-panel.xml" \
	"$CPY/out/xfce/gtk-colors.css" \
	"$CPY/out/lightdm/lightdm-gtk-greeter.conf" \
	"$CPY/out/xfce/xfconf/xfce4-desktop.xml" \
	"$CPY/out/xinit/xinitrc.example"; do
	if [ -f "$f" ]; then
		ok "rendered config present: ${f#"$CPY/"}"
	else
		fail "missing rendered config: $f"
	fi
done

if grep -q 'TestBSD 2 NutX' "$CPY/out/xfce/xfconf/xfce4-panel.xml" \
	&& grep -q 'testbsd-2-nutx' "$CPY/out/lightdm/lightdm-gtk-greeter.conf"; then
	ok 'rebrand.sh re-rendered configs with the new name'
else
	fail 'rebrand.sh did not substitute the new name into out configs'
fi
if [ -f "$CPY/out/icons/hicolor/128x128/apps/testbsd-2-nutx-logo.png" ]; then
	ok 'rebrand.sh re-rendered icons under the new NAME_LOWER'
else
	fail 'rebrand.sh did not render icons under the new NAME_LOWER'
fi

# ---------------------------------------------------------------- summary
if [ "$FAILURES" -ne 0 ]; then
	printf 'test-render.sh: %s failure(s)\n' "$FAILURES"
	exit 1
fi
printf 'test-render.sh: all checks passed\n'
