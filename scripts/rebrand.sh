#!/bin/sh
# scripts/rebrand.sh -- retarget the branding: rewrite the name (and
# optionally PRIMARY/ACCENT) and re-render. Never touches src/.
#
# Usage: sh scripts/rebrand.sh [--variant NAME] NewName [PRIMARY [ACCENT]]
#
# NewName: human-readable name; NAME_LOWER is derived by lowercasing it and
# mapping every character outside [a-z0-9-] to '-'. Both go to palette.env.
# PRIMARY/ACCENT: optional 6-digit hex colors; a leading '#' is tolerated.
# A colour goes to variants/NAME/palette.env when that variant sets the key
# itself (cyberpunk sets its own neon PRIMARY and ACCENT), else palette.env.
# --variant NAME: the variant to rebrand and render (default:
# $ARTWORK_VARIANT, else "default").
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_DIR")" && pwd)
PALETTE="$ROOT_DIR/palette.env"

usage() {
	printf 'usage: sh scripts/rebrand.sh [--variant NAME] NewName [PRIMARY [ACCENT]]\n'
}

die() {
	printf 'rebrand.sh: error: %s\n' "$*" >&2
	exit 1
}

# ------------------------------- arguments
VARIANT=${ARTWORK_VARIANT:-default}
case "${1:-}" in
--variant)
	[ $# -ge 2 ] || { usage; die "--variant needs a name"; }
	VARIANT=$2
	shift 2
	;;
-h|--help) usage; exit 0 ;;
esac
case $# in
0) usage; exit 1 ;;
1|2|3) ;;
*) usage; die "too many arguments" ;;
esac
printf '%s' "$VARIANT" | grep -Eq '^[a-z0-9][a-z0-9-]{0,31}$' || die "bad variant name: $VARIANT"
VPALETTE="$ROOT_DIR/variants/$VARIANT/palette.env"
[ -d "$ROOT_DIR/variants/$VARIANT" ] || die "no such variant: $VARIANT"

HEX_RE='^[0-9A-Fa-f]{6}$'
NAME_RE='^[A-Za-z][A-Za-z0-9 ._%:,!?+-]{0,63}$'

NAME_IN=$1
[ -f "$PALETTE" ] || die "palette file not found: $PALETTE"
printf '%s' "$NAME_IN" | grep -Eq -- "$NAME_RE" ||
	die "NAME must match $NAME_RE (got: \"$NAME_IN\")"

# NAME_LOWER: lowercase, map awkward characters to '-', collapse and trim.
NEW_LOWER=$(printf '%s' "$NAME_IN" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')
[ -n "$NEW_LOWER" ] || die "cannot derive NAME_LOWER from \"$NAME_IN\""
printf '%s' "$NEW_LOWER" | grep -Eq '^[a-z0-9][a-z0-9-]{0,63}$' ||
	die "derived NAME_LOWER is not a valid identifier: \"$NEW_LOWER\""

hex_arg() {
	# hex_arg LABEL VALUE : print VALUE as upper-case hex or die
	_h=$(printf '%s' "$2" | sed -e 's/^#//')
	printf '%s' "$_h" | grep -Eq -- "$HEX_RE" || die "$1 must be 6-digit hex (got: \"$2\")"
	printf '%s' "$_h" | tr '[:lower:]' '[:upper:]'
}
NEW_PRIMARY=""
NEW_ACCENT=""
[ $# -ge 2 ] && NEW_PRIMARY=$(hex_arg PRIMARY "$2")
[ $# -ge 3 ] && NEW_ACCENT=$(hex_arg ACCENT "$3")

# ------------------------------- rewrite palettes, keeping every other line
_tmp=$(mktemp)
trap 'rm -f "$_tmp" "$_tmp".*' EXIT INT TERM

has_key() {
	# has_key FILE KEY : true if FILE assigns KEY
	[ -f "$1" ] && grep -Eq "^[[:space:]]*$2=" "$1"
}

set_key() {
	# set_key FILE KEY LINE : replace KEY's assignment in FILE with LINE
	# (appending it if absent); comments and other keys are kept as they are.
	tr -d '\r' < "$1" | awk -v key="$2" -v line="$3" '
		$0 ~ "^[[:space:]]*" key "=" { if (!done) print line; done = 1; next }
		{ print }
		END { if (!done) print line }' > "$_tmp.new" || die "cannot rewrite $1"
	mv "$_tmp.new" "$1"
}

set_key "$PALETTE" NAME "NAME=\"$NAME_IN\""
set_key "$PALETTE" NAME_LOWER "NAME_LOWER=\"$NEW_LOWER\""
for _k in PRIMARY ACCENT; do
	eval "_v=\$NEW_$_k"
	[ -n "$_v" ] || continue
	if has_key "$VPALETTE" "$_k"; then
		set_key "$VPALETTE" "$_k" "$_k=$_v"
		printf 'rebrand.sh: %s set in variants/%s/palette.env\n' "$_k" "$VARIANT"
	else
		set_key "$PALETTE" "$_k" "$_k=$_v"
	fi
done

printf 'rebrand.sh: palette updated (%s), rendering variant %s...\n' "$PALETTE" "$VARIANT"
sh "$SCRIPT_DIR/render.sh" --variant "$VARIANT" "$PALETTE" "$ROOT_DIR/out"
