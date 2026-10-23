#!/bin/sh
# scripts/rebrand.sh -- retarget the branding: rewrite palette.env (new name,
# optionally new PRIMARY/ACCENT colors) and re-render. Never touches src/.
#
# Usage: sh scripts/rebrand.sh NewName [PRIMARY [ACCENT]]
#
# NewName: human-readable name; NAME_LOWER is derived by lowercasing it and
# mapping every character outside [a-z0-9-] to '-'.
# PRIMARY/ACCENT: optional 6-digit hex colors; a leading '#' is tolerated.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_DIR")" && pwd)
PALETTE="$ROOT_DIR/palette.env"

usage() {
	printf 'usage: sh scripts/rebrand.sh NewName [PRIMARY [ACCENT]]\n'
}

die() {
	printf 'rebrand.sh: error: %s\n' "$*" >&2
	exit 1
}

quotes_ok() {
	# quotes_ok STRING : false if STRING contains a double quote
	[ "${1#*\"}" = "$1" ]
}

# ------------------------------- arguments
case $# in
0) usage; exit 1 ;;
1|2|3) ;;
*) usage; die "too many arguments" ;;
esac

HEX_RE='^[0-9A-Fa-f]{6}$'
NAME_RE='^[A-Za-z][A-Za-z0-9 ._%:,!?+-]{0,63}$'

NAME_IN=$1
[ -f "$PALETTE" ] || die "palette file not found: $PALETTE"
printf '%s' "$NAME_IN" | grep -Eq -- "$NAME_RE" ||
	die "NAME must match $NAME_RE (got: \"$NAME_IN\")"

# NAME_LOWER: lowercase, map awkward characters to '-', collapse and trim.
NEW_LOWER=$(printf '%s' "$NAME_IN" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')
[ -n "$NEW_LOWER" ] || die "cannot derive NAME_LOWER from \"$NAME_IN\""
printf '%s' "$NEW_LOWER" | grep -EqE '^[a-z0-9][a-z0-9-]{0,63}$' ||
	die "derived NAME_LOWER is not a valid identifier: \"$NEW_LOWER\""

NEW_PRIMARY=""
NEW_ACCENT=""
if [ $# -ge 2 ]; then
	_p=$(printf '%s' "$2" | sed -e 's/^#//')
	quotes_ok "$_p" || die "PRIMARY must be 6-digit hex (got: \"$2\")"
	printf '%s' "$_p" | grep -Eq -- "$HEX_RE" ||
		die "PRIMARY must be 6-digit hex (got: \"$2\")"
	NEW_PRIMARY=$(printf '%s' "$_p" | tr '[:lower:]' '[:upper:]')
fi
if [ $# -ge 3 ]; then
	_a=$(printf '%s' "$3" | sed -e 's/^#//')
	quotes_ok "$_a" || die "ACCENT must be 6-digit hex (got: \"$3\")"
	printf '%s' "$_a" | grep -Eq -- "$HEX_RE" ||
		die "ACCENT must be 6-digit hex (got: \"$3\")"
	NEW_ACCENT=$(printf '%s' "$_a" | tr '[:lower:]' '[:upper:]')
fi

# ------------------------------- carry over unchanged palette values
_tmp=$(mktemp)
trap 'rm -f "$_tmp"' EXIT INT TERM
tr -d '\r' < "$PALETTE" > "$_tmp"

get_key() {
	# get_key KEY : print the value, tolerating the quoted form
	_val=$(sed -nE "s/^[[:space:]]*$1=\"?([^\"]*)\"?[[:space:]]*\$/\1/p" "$_tmp") ||
		die "palette is missing key: $1"
	[ -n "$_val" ] || die "palette value is empty for key: $1"
	printf '%s' "$_val"
}

OLD_TAGLINE=$(get_key TAGLINE)
OLD_PRIMARY=$(get_key PRIMARY)
OLD_ACCENT=$(get_key ACCENT)
for _k in DARK DARK2 LIGHT MUTED; do
	_v=$(get_key "$_k")
	printf '%s' "$_v" | grep -Eq -- "$HEX_RE" || die "current $_k is not 6-digit hex: \"$_v\""
	eval "$_k=\$_v"
done
if [ -z "$NEW_PRIMARY" ]; then NEW_PRIMARY=$OLD_PRIMARY; fi
if [ -z "$NEW_ACCENT" ]; then NEW_ACCENT=$OLD_ACCENT; fi

# ------------------------------- write the new palette (string keys quoted)
{
	printf 'NAME="%s"\n' "$NAME_IN"
	printf 'NAME_LOWER="%s"\n' "$NEW_LOWER"
	printf 'TAGLINE="%s"\n' "$OLD_TAGLINE"
	printf 'PRIMARY=%s\n' "$NEW_PRIMARY"
	printf 'ACCENT=%s\n' "$NEW_ACCENT"
	printf 'DARK=%s\n' "$DARK"
	printf 'DARK2=%s\n' "$DARK2"
	printf 'LIGHT=%s\n' "$LIGHT"
	printf 'MUTED=%s\n' "$MUTED"
} > "$_tmp.palette" || die "cannot write palette"
mv "$_tmp.palette" "$PALETTE"

printf 'rebrand.sh: palette updated (%s), rendering...\n' "$PALETTE"
sh "$SCRIPT_DIR/render.sh" "$PALETTE" "$ROOT_DIR/out"
