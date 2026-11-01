#!/bin/sh
# scripts/render.sh -- substitute branding tokens and render the asset tree.
#
# Usage: sh scripts/render.sh [--variant NAME] [--identity FILE]
#                             [--share-dir PATH] [palette.env] [outdir]
#
#   --variant NAME    a directory under variants/ (default: $ARTWORK_VARIANT,
#                     else "default"). Its palette.env overrides palette.env
#                     key by key; any other file in it replaces the base file
#                     at the same path (e.g. variants/cyberpunk/src/logo.svg).
#   --identity FILE   an identity file (see scripts/identity-file.sh): stamp
#                     the identity line on the greeter, slim and wallpaper
#                     backgrounds, write it into the display-manager configs,
#                     and copy the file to outdir/identity.
#   --share-dir PATH  where the artwork is installed on the target
#                     (default /usr/local/share/<NAME_LOWER>).
#
# Requires rsvg-convert (librsvg), inkscape or cairosvg, and ImageMagick
# (magick or convert) for the XPM logos, the loader splash and favicon.ico.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_DIR")" && pwd)
. "$SCRIPT_DIR/lib-identity.sh"

usage() {
	sed -n '3,19s/^# \{0,1\}//p' "$0"
}

die() {
	printf 'render.sh: error: %s\n' "$*" >&2
	exit 1
}

warn() {
	printf 'render.sh: warning: %s\n' "$*" >&2
}

# ----------------------------------------------------------------- arguments
VARIANT=${ARTWORK_VARIANT:-default}
IDENTITY_FILE=''
SHARE_DIR=''
while [ $# -gt 0 ]; do
	case $1 in
	-h|--help) usage; exit 0 ;;
	--variant) [ $# -ge 2 ] || die "--variant needs a name"; VARIANT=$2; shift 2 ;;
	--identity) [ $# -ge 2 ] || die "--identity needs a file"; IDENTITY_FILE=$2; shift 2 ;;
	--share-dir) [ $# -ge 2 ] || die "--share-dir needs a path"; SHARE_DIR=$2; shift 2 ;;
	--) shift; break ;;
	-*) usage >&2; die "unknown option: $1" ;;
	*) break ;;
	esac
done
case "${1:-}" in
"") PALETTE="$ROOT_DIR/palette.env" ;;
*) PALETTE=$1 ;;
esac
case "${2:-}" in
"") OUTDIR="$ROOT_DIR/out" ;;
*) OUTDIR=$2 ;;
esac

[ -f "$PALETTE" ] || die "palette file not found: $PALETTE"
PALETTE=$(CDPATH= cd -- "$(dirname -- "$PALETTE")" && pwd)/$(basename -- "$PALETTE")
printf '%s' "$VARIANT" | grep -Eq '^[a-z0-9][a-z0-9-]{0,31}$' || die "bad variant name: $VARIANT"
VARIANT_DIR="$ROOT_DIR/variants/$VARIANT"
[ -d "$VARIANT_DIR" ] || die "no such variant: $VARIANT (looked in $VARIANT_DIR)"
case $SHARE_DIR in ''|/*) ;; *) die "--share-dir must be an absolute path" ;; esac
[ -z "$SHARE_DIR" ] || printf '%s' "$SHARE_DIR" | grep -Eq '^[A-Za-z0-9/._-]+$' || die "--share-dir has unsafe characters: $SHARE_DIR"

# ------------------------------------------------------------------ palette
HEX_RE='^[0-9A-Fa-f]{6}$'
# Restricted charsets so values stay safe inside shell and sed contexts:
# no quotes, backslashes, '#' (comments), '&' or '|' (sed specials),
# '*' (globs), '@' (tokens) or control characters. Values are unquoted
# shell KEY=VALUE assignments, so they must also be assignment-safe.
NAME_RE='^[A-Za-z][A-Za-z0-9 ._%:,!?+-]{0,63}$'
NAME_LOWER_RE='^[a-z0-9][a-z0-9-]{0,63}$'
TAGLINE_RE='^[A-Za-z0-9 _%:,!?+-]{0,127}$'
FONT_RE='^[A-Za-z][A-Za-z0-9 -]{0,63}$'
LABEL_RE='^[A-Za-z0-9][A-Za-z0-9 ._+-]{0,31}$'
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

# The variant's palette is appended, so its keys win when sourced.
{
	tr -d '\r' < "$PALETTE"
	printf '\n'
	[ -f "$VARIANT_DIR/palette.env" ] && tr -d '\r' < "$VARIANT_DIR/palette.env"
} > "$TMP_ROOT/palette.src"
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
grep -vE '^[[:space:]]*(#.*)?$' "$TMP_ROOT/palette.env" > "$TMP_ROOT/palette.lines" || true
if [ -s "$TMP_ROOT/palette.lines" ]; then
	if grep -Ev -- "$LINE_RE" "$TMP_ROOT/palette.lines" > "$TMP_ROOT/palette.bad"; then
		while IFS= read -r _bad; do
			die "malformed palette line: $_bad"
		done < "$TMP_ROOT/palette.bad"
	fi
fi

# Sourcing the uniformly-quoted file is safe: after the checks above the
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
# Keys added with the variants; older palettes fall back to sensible values.
HIGHLIGHT=${HIGHLIGHT:-$ACCENT}
IDENTITY_FG=${IDENTITY_FG:-$MUTED}
FONT=${FONT:-DejaVu Sans}
if [ -z "${VARIANT_LABEL:-}" ]; then
	VARIANT_LABEL=$(printf '%s' "$VARIANT" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')
fi

matched "$NAME" "$NAME_RE" || die "NAME must match $NAME_RE (got: \"$NAME\")"
matched "$NAME_LOWER" "$NAME_LOWER_RE" || die "NAME_LOWER must match $NAME_LOWER_RE (got: \"$NAME_LOWER\")"
matched "$TAGLINE" "$TAGLINE_RE" || die "TAGLINE must match $TAGLINE_RE (got: \"$TAGLINE\")"
matched "$FONT" "$FONT_RE" || die "FONT must match $FONT_RE (got: \"$FONT\")"
matched "$VARIANT_LABEL" "$LABEL_RE" || die "VARIANT_LABEL must match $LABEL_RE (got: \"$VARIANT_LABEL\")"
for _hex in PRIMARY ACCENT HIGHLIGHT DARK DARK2 LIGHT MUTED IDENTITY_FG; do
	eval "_val=\$$_hex"
	matched "$_val" "$HEX_RE" || die "$_hex must be a 6-digit hex color (got: \"$_val\")"
done
[ -n "$SHARE_DIR" ] || SHARE_DIR="/usr/local/share/$NAME_LOWER"

# ----------------------------------------------------------------- identity
if [ -n "$IDENTITY_FILE" ]; then
	identity_read "$IDENTITY_FILE" || die "bad identity file: $IDENTITY_FILE"
	IDENTITY_LINE=$(identity_line "$IDENTITY_SEP")
	IDENTITY_ASCII=$(identity_line "$IDENTITY_SEP_ASCII")
else
	# No build identity yet: name and variant only. A product build renders
	# again with --identity once version, base and arch are known.
	IDENTITY_LINE="$NAME$IDENTITY_SEP$VARIANT_LABEL"
	IDENTITY_ASCII="$NAME$IDENTITY_SEP_ASCII$VARIANT_LABEL"
fi

# ------------------------------------------------------------ substitution
apply_tokens() {
	# apply_tokens SRC DST : substitute every palette token into DST.
	sed \
		-e "s|@NAME@|$NAME|g" \
		-e "s|@NAME_LOWER@|$NAME_LOWER|g" \
		-e "s|@TAGLINE@|$TAGLINE|g" \
		-e "s|@PRIMARY@|$PRIMARY|g" \
		-e "s|@ACCENT@|$ACCENT|g" \
		-e "s|@HIGHLIGHT@|$HIGHLIGHT|g" \
		-e "s|@DARK@|$DARK|g" \
		-e "s|@DARK2@|$DARK2|g" \
		-e "s|@LIGHT@|$LIGHT|g" \
		-e "s|@MUTED@|$MUTED|g" \
		-e "s|@IDENTITY_FG@|$IDENTITY_FG|g" \
		-e "s|@FONT@|$FONT|g" \
		-e "s|@VARIANT@|$VARIANT|g" \
		-e "s|@VARIANT_LABEL@|$VARIANT_LABEL|g" \
		-e "s|@SHARE_DIR@|$SHARE_DIR|g" \
		-e "s#@IDENTITY_LINE@#$IDENTITY_LINE#g" \
		-e "s#@IDENTITY_ASCII@#$IDENTITY_ASCII#g" \
		"$1" > "$2"
}

# ---------------------------------------------------------- template tree
# The base tree, then the variant's files on top of it.
TEMPLATE_DIRS='src xfce lightdm xinit dm console boot'
TPL="$TMP_ROOT/tpl"
mkdir -p "$TPL"
[ -d "$ROOT_DIR/src" ] || die "src/ not found in $ROOT_DIR"
for _d in $TEMPLATE_DIRS; do
	[ -d "$ROOT_DIR/$_d" ] && cp -R "$ROOT_DIR/$_d" "$TPL/"
done
for _d in $TEMPLATE_DIRS; do
	if [ -d "$VARIANT_DIR/$_d" ]; then
		(cd "$VARIANT_DIR" && find "$_d" -type f) | while IFS= read -r _f; do
			[ -f "$ROOT_DIR/$_f" ] || die "variant $VARIANT overrides a file the base does not have: $_f"
			cp "$VARIANT_DIR/$_f" "$TPL/$_f"
		done
	fi
done

# SVG sources are substituted in place under $TPL/src.
find "$TPL/src" -type f | while IFS= read -r _f; do
	apply_tokens "$_f" "$_f.part"
	mv "$_f.part" "$_f"
done

# -------------------------------------------------------------- config tree
# Every non-SVG template is substituted into outdir at the same path, with
# @NAME_LOWER@ in a path replaced by the slug. Files named *.in drop the
# suffix; executables keep their mode.
mkdir -p "$OUTDIR"
for _d in $TEMPLATE_DIRS; do
	[ "$_d" = src ] && continue
	[ -d "$TPL/$_d" ] || continue
	(cd "$TPL" && find "$_d" -type f) | while IFS= read -r _rel; do
		_dst=$(printf '%s' "$_rel" | sed -e "s|@NAME_LOWER@|$NAME_LOWER|g" -e 's|\.in$||')
		mkdir -p "$OUTDIR/$(dirname "$_dst")"
		apply_tokens "$TPL/$_rel" "$OUTDIR/$_dst"
		[ -x "$TPL/$_rel" ] && chmod 755 "$OUTDIR/$_dst"
		:
	done
done
printf '%s\n' "$VARIANT" > "$OUTDIR/variant"

# xrdb runs the xdm/xenodm Xresources through cpp, which would replace any
# word of the greeting that happens to be a predefined macro (unix, i386,
# ...). Undefine every word of the greeting just before it.
_undefs=$(printf '%s\n' "$IDENTITY_ASCII" | tr -c 'A-Za-z0-9_' '\n' | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u)
for _x in "$OUTDIR/dm/xenodm/Xresources" "$OUTDIR/dm/xdm/Xresources"; do
	[ -f "$_x" ] || continue
	awk -v words="$_undefs" '
		/^xlogin\*greeting:/ { n = split(words, w, "\n"); for (i = 1; i <= n; i++) if (w[i] != "") print "#undef " w[i] }
		{ print }' "$_x" > "$_x.part"
	mv "$_x.part" "$_x"
done

# ----------------------------------------------------------------- renderer
if command -v rsvg-convert >/dev/null 2>&1; then
	RENDERER=rsvg
elif command -v inkscape >/dev/null 2>&1; then
	RENDERER=inkscape
elif command -v cairosvg >/dev/null 2>&1; then
	RENDERER=cairosvg
else
	die "no renderer found: install rsvg-convert (librsvg), inkscape or cairosvg"
fi

IM=""
command -v magick >/dev/null 2>&1 && IM=magick
if [ -z "$IM" ]; then
	command -v convert >/dev/null 2>&1 && IM=convert
fi
[ -n "$IM" ] || die "ImageMagick (magick or convert) is required for the XPM logos"

render_png() {
	# render_png SVG WIDTH HEIGHT OUTFILE
	_svg=$1
	_w=$2
	_h=$3
	_out=$4
	case $RENDERER in
	rsvg)
		rsvg-convert -w "$_w" -h "$_h" -o "$_out" "$_svg" || die "rsvg-convert failed on $_out"
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
	cairosvg)
		cairosvg "$_svg" -o "$_out" --output-width "$_w" --output-height "$_h" ||
			die "cairosvg failed on $_out"
		;;
	esac
}

S="$TPL/src"

# ------------------------------------------------------------------- logos
mkdir -p "$OUTDIR/logo"
for _s in 64 128 256 512; do
	render_png "$S/logo.svg" "$_s" "$_s" "$OUTDIR/logo/logo-$_s.png"
done
render_png "$S/wordmark.svg" 1200 300 "$OUTDIR/logo/wordmark.png"
render_png "$S/wordmark-light.svg" 1200 300 "$OUTDIR/logo/wordmark-light.png"

# ------------------------------------------------------------------ splash
mkdir -p "$OUTDIR/splash"
for _s in 640x480 1024x768 1920x1080; do
	_w=${_s%%x*}
	_h=${_s##*x}
	render_png "$S/splash-$_s.svg" "$_w" "$_h" "$OUTDIR/splash/splash-$_s.png"
done

# ------------------------------------------------------------------- loader
mkdir -p "$OUTDIR/loader"
render_png "$S/loader-logo.svg" 480 200 "$OUTDIR/loader/loader-logo.png"
# Framebuffer brand (drawn 7 text rows high) and logo (15 rows) for the
# FreeBSD and illumos loader menus, and the vt(4) boot splash. All three
# are written as 8-bit RGBA, non-interlaced PNG: vt(4) draws only RGBA
# (splash(4)) and the loader's PNG reader rejects indexed colour.
rgba_png() {
	# rgba_png SVG W H OUT
	render_png "$1" "$2" "$3" "$TMP_ROOT/rgba.png"
	"$IM" "$TMP_ROOT/rgba.png" -alpha set -depth 8 -interlace none PNG32:"$4"
}
rgba_png "$S/loader-brand.svg" 400 100 "$OUTDIR/loader/$NAME_LOWER-brand.png"
rgba_png "$S/loader-mark.svg" 240 200 "$OUTDIR/loader/$NAME_LOWER-logo.png"
rgba_png "$S/splash-1024x768.svg" 1024 768 "$OUTDIR/loader/splash.png"

# ---------------------------------------------------------------- installer
mkdir -p "$OUTDIR/installer"
render_png "$S/installer-header.svg" 800 96 "$OUTDIR/installer/header.png"
render_png "$S/installer-sidebar.svg" 200 600 "$OUTDIR/installer/sidebar.png"

# ------------------------------------------------------------------ lightdm
mkdir -p "$OUTDIR/lightdm"
render_png "$S/greeter.svg" 1920 1080 "$OUTDIR/lightdm/greeter-1920x1080.png"

# --------------------------------------------------------------- wallpapers
mkdir -p "$OUTDIR/wallpapers"
for _n in 1 2 3; do
	render_png "$S/wallpaper-$_n.svg" 1920 1080 "$OUTDIR/wallpapers/wallpaper-$_n-1920x1080.png"
	render_png "$S/wallpaper-$_n.svg" 3840 2160 "$OUTDIR/wallpapers/wallpaper-$_n-3840x2160.png"
done

# ------------------------------------------------------------------- icons
for _s in 16 22 24 32 48 64 128 256; do
	_d="$OUTDIR/icons/hicolor/${_s}x${_s}/apps"
	mkdir -p "$_d"
	render_png "$S/icons/distributor-logo.svg" "$_s" "$_s" "$_d/$NAME_LOWER-logo.png"
	render_png "$S/icons/system-installer.svg" "$_s" "$_s" "$_d/$NAME_LOWER-installer.png"
	render_png "$S/icons/panel-menu.svg" "$_s" "$_s" "$_d/$NAME_LOWER-menu.png"
done
mkdir -p "$OUTDIR/icons/hicolor/scalable/apps"
cp "$S/icons/distributor-logo.svg" "$OUTDIR/icons/hicolor/scalable/apps/$NAME_LOWER-logo.svg"
cp "$S/icons/system-installer.svg" "$OUTDIR/icons/hicolor/scalable/apps/$NAME_LOWER-installer.svg"
cp "$S/icons/panel-menu.svg" "$OUTDIR/icons/hicolor/scalable/apps/$NAME_LOWER-menu.svg"

# ----------------------------------------------------------------- favicon
mkdir -p "$OUTDIR/favicon"
for _s in 16 32 48 180 192 512; do
	render_png "$S/favicon.svg" "$_s" "$_s" "$OUTDIR/favicon/favicon-$_s.png"
done
cp "$S/favicon.svg" "$OUTDIR/favicon/favicon.svg"
if command -v icotool >/dev/null 2>&1; then
	icotool -c -o "$OUTDIR/favicon/favicon.ico" \
		"$OUTDIR/favicon/favicon-16.png" \
		"$OUTDIR/favicon/favicon-32.png" \
		"$OUTDIR/favicon/favicon-48.png" ||
		warn "icotool could not build favicon.ico"
else
	"$IM" "$OUTDIR/favicon/favicon-16.png" "$OUTDIR/favicon/favicon-32.png" "$OUTDIR/favicon/favicon-48.png" \
		"$OUTDIR/favicon/favicon.ico" ||
		warn "ImageMagick could not build favicon.ico"
fi

# ------------------------------------------------- display-manager pixmaps
# xenodm and xdm draw an XPM logo in the login box (xlogin*logoFileName).
# It is flattened onto the login box colour (DARK2) so the edges stay clean
# without alpha: a full-colour, a 16-colour and a 2-colour version, chosen
# by display depth in the Xresources (#if PLANES ...).
mkdir -p "$OUTDIR/dm/pixmaps"
render_png "$S/logo.svg" 112 112 "$TMP_ROOT/dm-logo.png"
"$IM" "$TMP_ROOT/dm-logo.png" -background "#$DARK2" -alpha remove -alpha off -colors 64 \
	"$OUTDIR/dm/pixmaps/$NAME_LOWER-color.xpm"
"$IM" "$TMP_ROOT/dm-logo.png" -background "#$DARK2" -alpha remove -alpha off -colors 16 \
	"$OUTDIR/dm/pixmaps/$NAME_LOWER-8bpp.xpm"
# 1 bpp: the login box is black there; threshold grey at 50% so the light
# bars stay white and the tile goes black.
"$IM" "$TMP_ROOT/dm-logo.png" -background black -alpha remove -alpha off -colorspace Gray -threshold 50% -type Bilevel \
	"$OUTDIR/dm/pixmaps/$NAME_LOWER-1bpp.xpm"

# ---------------------------------------------------------------- slim
mkdir -p "$OUTDIR/dm/slim/$NAME_LOWER"
cp "$OUTDIR/lightdm/greeter-1920x1080.png" "$OUTDIR/dm/slim/$NAME_LOWER/background.png"
render_png "$S/slim-panel.svg" 600 280 "$OUTDIR/dm/slim/$NAME_LOWER/panel.png"

# ------------------------------------------------------------- identity
if [ -n "$IDENTITY_FILE" ]; then
	STAMP="$SCRIPT_DIR/identity-stamp.sh"
	stamp() {
		# stamp PNG [BOTTOM_PX] : stamp the identity line onto PNG in place
		sh "$STAMP" --palette "$PALETTE" --variant "$VARIANT" --fg "$IDENTITY_FG" \
			--plate "$DARK" --font "$FONT" --bottom "${2:-0}" \
			"$IDENTITY_FILE" "$1" "$1.stamped" > /dev/null || die "identity stamp failed on $1"
		mv "$1.stamped" "$1"
	}
	stamp "$OUTDIR/lightdm/greeter-1920x1080.png"
	stamp "$OUTDIR/dm/slim/$NAME_LOWER/background.png"
	# Wallpapers keep the bottom panel (30 px at 1080p) clear.
	for _n in 1 2 3; do
		stamp "$OUTDIR/wallpapers/wallpaper-$_n-1920x1080.png" 30
		stamp "$OUTDIR/wallpapers/wallpaper-$_n-3840x2160.png" 60
	done
	tr -d '\r' < "$IDENTITY_FILE" > "$OUTDIR/identity"
fi

# ------------------------------------------------------------------ summary
_count=$(find "$OUTDIR" -type f | wc -l)
printf 'render.sh: wrote %s files to %s (variant %s, via %s)\n' "$_count" "$OUTDIR" "$VARIANT" "$RENDERER"
