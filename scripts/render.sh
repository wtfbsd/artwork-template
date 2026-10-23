#!/bin/sh
# scripts/render.sh -- substitute branding tokens and render the asset tree.
#
# Usage: sh scripts/render.sh [palette.env] [outdir]
#
# Sources the palette, validates it, substitutes the @TOKEN@ markers in src/
# and the config templates into a temporary directory, then renders the
# assets into outdir. Requires rsvg-convert (librsvg) or inkscape.
# Optional: ImageMagick (flatten for loader splash, favicon.ico), icoutools
# (favicon.ico).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_DIR")" && pwd)

usage() {
	printf 'usage: sh scripts/render.sh [palette.env] [outdir]\n'
}

die() {
	printf 'render.sh: error: %s\n' "$*" >&2
	exit 1
}

warn() {
	printf 'render.sh: warning: %s\n' "$*" >&2
}

# ----------------------------------------------------------------- arguments
case "${1:-}" in
-h|--help) usage; exit 0 ;;
"") PALETTE="$ROOT_DIR/palette.env" ;;
*) PALETTE=$1 ;;
esac
case "${2:-}" in
"") OUTDIR="$ROOT_DIR/out" ;;
*) OUTDIR=$2 ;;
esac

[ -f "$PALETTE" ] || die "palette file not found: $PALETTE"
PALETTE=$(CDPATH= cd -- "$(dirname -- "$PALETTE")" && pwd)/$(basename -- "$PALETTE")

# ------------------------------------------------------------------ palette
HEX_RE='^[0-9A-Fa-f]{6}$'
# Restricted charsets so values stay safe inside shell and sed contexts:
# no quotes, backslashes, '#' (comments), '&' or '|' (sed specials),
# '*' (globs), '@' (tokens) or control characters. Values are unquoted
# shell KEY=VALUE assignments, so they must also be assignment-safe.
NAME_RE='^[A-Za-z][A-Za-z0-9 ._%:,!?+-]{0,63}$'
NAME_LOWER_RE='^[a-z0-9][a-z0-9-]{0,63}$'
TAGLINE_RE='^[A-Za-z0-9 _%:,!?+-]{0,127}$'
LINE_RE='^[A-Z][A-Z0-9_]*=[A-Za-z0-9 ._%:,!?+-]*$'

matched() {
	# matched VALUE REGEX : true if VALUE matches EREGEX
	printf '%s' "$1" | grep -Eq -- "$2"
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/render.XXXXXX")
cleanup() {
	rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

tr -d '\r' < "$PALETTE" > "$TMP_ROOT/palette.src"
# Normalize every assignment to the quoted form KEY="value" (so values with
# spaces source cleanly whatever way the palette was written), and strip the
# quotes again for charset validation.
STRIP='s/^([A-Z][A-Z0-9_]*)="?([^"]*)"?[[:space:]]*$/\1=\2/'
sed -E 's/^([A-Z][A-Z0-9_]*)="?([^"]*)"?[[:space:]]*$/\1="\2"/' "$TMP_ROOT/palette.src" > "$TMP_ROOT/palette.quoted"
sed -E "$STRIP" "$TMP_ROOT/palette.quoted" > "$TMP_ROOT/palette.env"
sed -E "$STRIP" "$TMP_ROOT/palette.src" > "$TMP_ROOT/palette.stripped"
# If the two derivations disagree the file has stray quotes; refuse it.
cmp -s "$TMP_ROOT/palette.env" "$TMP_ROOT/palette.stripped" ||
	die "malformed palette line (unbalanced quotes?): $PALETTE"

# Every non-comment, non-blank line must be a simple KEY=VALUE assignment.
grep -vE '^[[:space:]]*(#.*|)$' "$TMP_ROOT/palette.env" > "$TMP_ROOT/palette.lines"
if [ -s "$TMP_ROOT/palette.lines" ]; then
	if grep -Ev -- "$LINE_RE" "$TMP_ROOT/palette.lines" > "$TMP_ROOT/palette.bad"; then
		while IFS= read -r _bad; do
			die "malformed palette line: $_bad"
		done < "$TMP_ROOT/palette.bad"
	fi
fi

# Sourcing the uniformly-quoted file is safe: after the checks below the
# file can only contain plain KEY="value" assignments, comments and blanks.
set -a
. "$TMP_ROOT/palette.quoted"
set +a

for _key in NAME NAME_LOWER TAGLINE PRIMARY ACCENT DARK DARK2 LIGHT MUTED; do
	if [ -n "$(eval "printf '%s' \"\${$_key+x}\"")" ]; then
		:
	else
		die "missing palette key: $_key"
	fi
done

matched "$NAME" "$NAME_RE" || die "NAME must match $NAME_RE (got: \"$NAME\")"
matched "$NAME_LOWER" "$NAME_LOWER_RE" || die "NAME_LOWER must match $NAME_LOWER_RE (got: \"$NAME_LOWER\")"
matched "$TAGLINE" "$TAGLINE_RE" || die "TAGLINE must match $TAGLINE_RE (got: \"$TAGLINE\")"
for _hex in PRIMARY ACCENT DARK DARK2 LIGHT MUTED; do
	eval "_val=\$$_hex"
	matched "$_val" "$HEX_RE" || die "$_hex must be a 6-digit hex color (got: \"$_val\")"
done

# ------------------------------------------------------------ substitution
apply_tokens() {
	# apply_tokens SRC DST : substitute every palette token into DST.
	sed \
		-e "s|@NAME@|$NAME|g" \
		-e "s|@NAME_LOWER@|$NAME_LOWER|g" \
		-e "s|@TAGLINE@|$TAGLINE|g" \
		-e "s|@PRIMARY@|$PRIMARY|g" \
		-e "s|@ACCENT@|$ACCENT|g" \
		-e "s|@DARK@|$DARK|g" \
		-e "s|@DARK2@|$DARK2|g" \
		-e "s|@LIGHT@|$LIGHT|g" \
		-e "s|@MUTED@|$MUTED|g" \
		"$1" > "$2"
}

# ------------------------------------------------------------ token sources
[ -d "$ROOT_DIR/src" ] || die "src/ not found in $ROOT_DIR"
cp -R "$ROOT_DIR/src" "$TMP_ROOT/src"
find "$TMP_ROOT/src" -type f | while IFS= read -r _f; do
	apply_tokens "$_f" "$_f.part"
	mv "$_f.part" "$_f"
done

# -------------------------------------------------------------- config tree
CONFIG_TEMPLATES='
xfce/gtk-colors.css
xfce/xfwm4-themerc
xfce/xfconf/xfce4-desktop.xml
xfce/xfconf/xfce4-panel.xml
xfce/xfconf/xsettings.xml
lightdm/lightdm-gtk-greeter.conf
xinit/xinitrc.example
'
for _rel in $CONFIG_TEMPLATES; do
	[ -f "$ROOT_DIR/$_rel" ] || die "missing template: $_rel"
done
for _rel in $CONFIG_TEMPLATES; do
	_d=$(dirname "$_rel")
	mkdir -p "$OUTDIR/$_d"
	apply_tokens "$ROOT_DIR/$_rel" "$OUTDIR/$_rel"
done

# ----------------------------------------------------------------- renderer
if command -v rsvg-convert >/dev/null 2>&1; then
	RENDERER=rsvg
elif command -v inkscape >/dev/null 2>&1; then
	RENDERER=inkscape
else
	die "no renderer found: install rsvg-convert (librsvg) or inkscape"
fi

render_png() {
	# render_png SVG WIDTH HEIGHT OUTFILE
	_svg=$1
	_w=$2
	_h=$3
	_out=$4
	case $RENDERER in
	rsvg)
		rsvg-convert -w "$_w" -h "$_h" -o "$_out" "$_svg" || die "rsvg-convert failed on $OUTDIR"
		;;
	inkscape)
		inkscape --export-type=png \
			--export-filename="$_out" \
			--export-width="$_w" \
			--export-height="$_h" \
			"$_svg" 2>/dev/null ||
			inkscape --export-type=png \
				--export-png="$_out" \
				--export-width="$_w" \
				--export-height="$_h" \
				"$_svg" ||
			die "inkscape failed on $_out"
		;;
	esac
}

# ------------------------------------------------------------------- logos
mkdir -p "$OUTDIR/logo"
for _s in 64 128 256 512; do
	render_png "$TMP_ROOT/src/logo.svg" "$_s" "$_s" "$OUTDIR/logo/logo-$_s.png"
done
render_png "$TMP_ROOT/src/wordmark.svg" 1200 300 "$OUTDIR/logo/wordmark.png"
render_png "$TMP_ROOT/src/wordmark-light.svg" 1200 300 "$OUTDIR/logo/wordmark-light.png"

# ------------------------------------------------------------------ splash
mkdir -p "$OUTDIR/splash"
for _s in 640x480 1024x768 1920x1080; do
	_w=${_s%%x*}
	_h=${_s##*x}
	render_png "$TMP_ROOT/src/splash-$_s.svg" "$_w" "$_h" "$OUTDIR/splash/splash-$_s.png"
done

# ------------------------------------------------------------------- loader
mkdir -p "$OUTDIR/loader"
render_png "$TMP_ROOT/src/loader-logo.svg" 480 200 "$OUTDIR/loader/loader-logo.png"

IM=""
command -v magick >/dev/null 2>&1 && IM=magick
if [ -z "$IM" ]; then
	command -v convert >/dev/null 2>&1 && IM=convert
fi
if [ -n "$IM" ]; then
	render_png "$TMP_ROOT/src/splash-1024x768.svg" 1024 768 "$TMP_ROOT/loader-splash.png"
	# 8-bit RGB, no alpha: flatten and drop the alpha channel.
	"$IM" "$TMP_ROOT/loader-splash.png" -alpha remove -alpha off -type TrueColor -depth 8 \
		"$OUTDIR/loader/splash-flat.png"
	mv "$OUTDIR/loader/splash-flat.png" "$OUTDIR/loader/splash.png"
else
	warn "ImageMagick not found; loader splash.png keeps its alpha channel"
	render_png "$TMP_ROOT/src/splash-1024x768.svg" 1024 768 "$OUTDIR/loader/splash.png"
fi

# ---------------------------------------------------------------- installer
mkdir -p "$OUTDIR/installer"
render_png "$TMP_ROOT/src/installer-header.svg" 800 96 "$OUTDIR/installer/header.png"
render_png "$TMP_ROOT/src/installer-sidebar.svg" 200 600 "$OUTDIR/installer/sidebar.png"

# ------------------------------------------------------------------ lightdm
mkdir -p "$OUTDIR/lightdm"
render_png "$TMP_ROOT/src/greeter.svg" 1920 1080 "$OUTDIR/lightdm/greeter-1920x1080.png"

# --------------------------------------------------------------- wallpapers
mkdir -p "$OUTDIR/wallpapers"
for _n in 1 2 3; do
	render_png "$TMP_ROOT/src/wallpaper-$_n.svg" 1920 1080 "$OUTDIR/wallpapers/wallpaper-$_n-1920x1080.png"
	render_png "$TMP_ROOT/src/wallpaper-$_n.svg" 3840 2160 "$OUTDIR/wallpapers/wallpaper-$_n-3840x2160.png"
done

# ------------------------------------------------------------------- icons
for _s in 16 22 24 32 48 64 128 256; do
	_d="$OUTDIR/icons/hicolor/${_s}x${_s}/apps"
	mkdir -p "$_d"
	render_png "$TMP_ROOT/src/icons/distributor-logo.svg" "$_s" "$_s" "$_d/$NAME_LOWER-logo.png"
	render_png "$TMP_ROOT/src/icons/system-installer.svg" "$_s" "$_s" "$_d/$NAME_LOWER-installer.png"
	render_png "$TMP_ROOT/src/icons/panel-menu.svg" "$_s" "$_s" "$_d/$NAME_LOWER-menu.png"
done
mkdir -p "$OUTDIR/icons/hicolor/scalable/apps"
cp "$TMP_ROOT/src/icons/distributor-logo.svg" "$OUTDIR/icons/hicolor/scalable/apps/$NAME_LOWER-logo.svg"
cp "$TMP_ROOT/src/icons/system-installer.svg" "$OUTDIR/icons/hicolor/scalable/apps/$NAME_LOWER-installer.svg"
cp "$TMP_ROOT/src/icons/panel-menu.svg" "$OUTDIR/icons/hicolor/scalable/apps/$NAME_LOWER-menu.svg"

# ----------------------------------------------------------------- favicon
mkdir -p "$OUTDIR/favicon"
for _s in 16 32 48 180 192 512; do
	render_png "$TMP_ROOT/src/favicon.svg" "$_s" "$_s" "$OUTDIR/favicon/favicon-$_s.png"
done
cp "$TMP_ROOT/src/favicon.svg" "$OUTDIR/favicon/favicon.svg"
if command -v icotool >/dev/null 2>&1; then
	icotool -c -o "$OUTDIR/favicon/favicon.ico" \
		"$OUTDIR/favicon/favicon-16.png" \
		"$OUTDIR/favicon/favicon-32.png" \
		"$OUTDIR/favicon/favicon-48.png" ||
		warn "icotool could not build favicon.ico"
elif [ -n "$IM" ]; then
	"$IM" "$OUTDIR/favicon/favicon-16.png" "$OUTDIR/favicon/favicon-32.png" "$OUTDIR/favicon/favicon-48.png" \
		"$OUTDIR/favicon/favicon.ico" ||
		warn "ImageMagick could not build favicon.ico"
else
	warn "no icotool or ImageMagick; skipping favicon.ico"
fi

# ------------------------------------------------------------------ summary
_count=$(find "$OUTDIR" -type f | wc -l)
printf 'render.sh: wrote %s files to %s (via %s)\n' "$_count" "$OUTDIR" "$RENDERER"
