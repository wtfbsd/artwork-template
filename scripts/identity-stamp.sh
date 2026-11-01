#!/bin/sh
# scripts/identity-stamp.sh -- draw the identity line in the lower-left
# corner of a background PNG (greeter, wallpaper, installer backdrop).
#
# Usage: sh scripts/identity-stamp.sh [options] IDENTITY IN.png OUT.png
#
#   --palette FILE  palette to take colours and font from (default palette.env)
#   --variant NAME  apply variants/NAME/palette.env on top (default: default)
#   --fg HEX        text colour (default: the palette's IDENTITY_FG)
#   --plate HEX     backing plate colour if needed (default: DARK)
#   --font NAME     fontconfig family (default: the palette's FONT)
#   --bottom PX     extra space to keep clear at the bottom (e.g. a panel)
#   --no-plate      never add a plate; fail if contrast is below 4.5:1
#
# Layout: text height is 1/60 of the image height (min 11 px), the margin
# 1/45 of it; the text shrinks (down to 11 px) until it fits on one line.
# Contrast is measured against every background pixel under the text box
# (worst case); below 4.5:1 an opaque plate in --plate goes behind the text.
#
# Prints one line: bbox=WxH+X+Y fg=HEX plate=0|1 size=PX contrast=RATIO
# Requires ImageMagick (magick or convert) and, preferably, fc-match.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_DIR")" && pwd)
. "$SCRIPT_DIR/lib-identity.sh"

die() { printf 'identity-stamp.sh: error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '3,24s/^# \{0,1\}//p' "$0"; }

PALETTE="$ROOT_DIR/palette.env"
VARIANT=${ARTWORK_VARIANT:-default}
FG='' PLATE_HEX='' FONT='' BOTTOM=0 ALLOW_PLATE=1
while [ $# -gt 0 ]; do
	case $1 in
	--palette) PALETTE=${2-}; shift 2 ;;
	--variant) VARIANT=${2-}; shift 2 ;;
	--fg) FG=${2#\#}; shift 2 ;;
	--plate) PLATE_HEX=${2#\#}; shift 2 ;;
	--font) FONT=${2-}; shift 2 ;;
	--bottom) BOTTOM=${2-}; shift 2 ;;
	--no-plate) ALLOW_PLATE=0; shift ;;
	-h|--help) usage; exit 0 ;;
	--) shift; break ;;
	-*) usage >&2; die "unknown option: $1" ;;
	*) break ;;
	esac
done
[ $# -eq 3 ] || { usage >&2; exit 1; }
IDENTITY=$1 IN=$2 OUT=$3

IM=""
command -v magick >/dev/null 2>&1 && IM=magick
[ -n "$IM" ] || { command -v convert >/dev/null 2>&1 && IM=convert; } || true
[ -n "$IM" ] || die "ImageMagick (magick or convert) is required"
[ -f "$IN" ] || die "no such image: $IN"
case $BOTTOM in ''|*[!0-9]*) die "--bottom must be a whole number of pixels" ;; esac
printf '%s' "$VARIANT" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || die "bad variant name: $VARIANT"

VPAL="$ROOT_DIR/variants/$VARIANT/palette.env"
[ -n "$FG" ] || FG=$(palette_value IDENTITY_FG "$PALETTE" "$VPAL")
[ -n "$FG" ] || FG=$(palette_value MUTED "$PALETTE" "$VPAL")
[ -n "$PLATE_HEX" ] || PLATE_HEX=$(palette_value DARK "$PALETTE" "$VPAL")
LIGHT_HEX=$(palette_value LIGHT "$PALETTE" "$VPAL")
[ -n "$FONT" ] || FONT=$(palette_value FONT "$PALETTE" "$VPAL")
[ -n "$FONT" ] || FONT='DejaVu Sans'
for _h in "$FG" "$PLATE_HEX"; do
	printf '%s' "$_h" | grep -Eq '^[0-9A-Fa-f]{6}$' || die "not a 6-digit hex colour: $_h"
done

identity_read "$IDENTITY" || die "bad identity file: $IDENTITY"
TEXT=$(identity_line "$IDENTITY_SEP")

FONT_ARG=$FONT
if command -v fc-match >/dev/null 2>&1; then
	_ff=$(fc-match -f '%{file}' "$FONT" 2>/dev/null || true)
	[ -n "$_ff" ] && [ -f "$_ff" ] && FONT_ARG=$_ff
fi

# ------------------------------------------------------------- geometry
set -- $("$IM" "$IN" -format '%w %h' info:)
W=$1 H=$2
SIZE=$(( (H + 30) / 60 ))
[ "$SIZE" -ge 11 ] || SIZE=11
MARGIN=$(( (H + 22) / 45 ))
[ "$MARGIN" -ge 8 ] || MARGIN=8

measure() {
	# measure SIZE : print "WIDTH HEIGHT" of TEXT at SIZE px
	"$IM" -density 72 -font "$FONT_ARG" -pointsize "$1" label:"$TEXT" -format '%w %h' info:
}
while :; do
	set -- $(measure "$SIZE")
	TW=$1 TH=$2
	[ $((TW + 2 * MARGIN)) -le "$W" ] && break
	[ "$SIZE" -gt 11 ] || die "identity line does not fit on one line at ${W}px: $TEXT"
	SIZE=$((SIZE - 1))
done

PAD=$(( (SIZE * 2 + 4) / 5 ))
TX=$MARGIN
TY=$((H - BOTTOM - MARGIN - TH))
[ "$TY" -gt "$PAD" ] || die "image too short for the identity line"
BX=$((TX - PAD)) BY=$((TY - PAD)) BW=$((TW + 2 * PAD)) BH=$((TH + 2 * PAD))
[ "$BX" -ge 0 ] || BX=0
BBOX="${BW}x${BH}+${BX}+${BY}"

# ------------------------------------------------------------- contrast
lum() {
	# lum HEX : WCAG relative luminance of an sRGB hex colour (ImageMagick's
	# linear-light grey uses the same Rec. 709 weights; no awk maths needed)
	"$IM" xc:"#$1" -colorspace LinearGray -format '%[fx:mean]' info:
}
ratio() {
	# ratio L1 L2 : WCAG contrast ratio
	awk -v a="$1" -v b="$2" 'BEGIN { if (a < b) { t = a; a = b; b = t }; printf "%.2f\n", (a + 0.05) / (b + 0.05) }'
}
# Lightest and darkest background luminance under the box (linear-light
# grey with Rec. 709 weights, which are the WCAG weights).
set -- $("$IM" "$IN" -crop "$BBOX" +repage -alpha off -colorspace LinearGray -format '%[fx:minima] %[fx:maxima]' info:)
BG_MIN=$1 BG_MAX=$2

worst() {
	# worst FG_LUM : worst contrast of FG against the background range
	awk -v f="$1" -v lo="$BG_MIN" -v hi="$BG_MAX" 'BEGIN {
		if (f >= lo && f <= hi) { print "1.00"; exit }
		b = (f > hi) ? hi : lo
		a = f; if (a < b) { t = a; a = b; b = t }
		printf "%.2f\n", (a + 0.05) / (b + 0.05) }'
}
ge45() { awk -v c="$1" 'BEGIN { exit !(c >= 4.5) }'; }

USE_PLATE=0
CONTRAST=$(worst "$(lum "$FG")")
if ! ge45 "$CONTRAST"; then
	[ "$ALLOW_PLATE" -eq 1 ] || die "contrast $CONTRAST is below 4.5:1 and --no-plate was given"
	USE_PLATE=1
	CONTRAST=$(ratio "$(lum "$FG")" "$(lum "$PLATE_HEX")")
	if ! ge45 "$CONTRAST" && [ -n "$LIGHT_HEX" ]; then
		FG=$LIGHT_HEX
		CONTRAST=$(ratio "$(lum "$FG")" "$(lum "$PLATE_HEX")")
	fi
	ge45 "$CONTRAST" || die "no palette colour reaches 4.5:1 on the plate (best $CONTRAST)"
fi

# ----------------------------------------------------------------- draw
if [ "$USE_PLATE" -eq 1 ]; then
	"$IM" "$IN" -fill "#$PLATE_HEX" -draw "rectangle $BX,$BY $((BX + BW - 1)),$((BY + BH - 1))" \
		-density 72 -font "$FONT_ARG" -pointsize "$SIZE" -fill "#$FG" -gravity NorthWest \
		-annotate "+$TX+$TY" "$TEXT" "$OUT"
else
	"$IM" "$IN" -density 72 -font "$FONT_ARG" -pointsize "$SIZE" -fill "#$FG" -gravity NorthWest \
		-annotate "+$TX+$TY" "$TEXT" "$OUT"
fi

printf 'bbox=%s fg=%s plate=%s size=%s contrast=%s\n' "$BBOX" "$FG" "$USE_PLATE" "$SIZE" "$CONTRAST"
