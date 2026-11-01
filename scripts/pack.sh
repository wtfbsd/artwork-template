#!/bin/sh
# scripts/pack.sh -- render every variant and write one pre-rendered pack per
# variant, so an OS template can install the artwork without rendering on
# its build host.
#
# Usage: sh scripts/pack.sh [--commit HASH] [--variant NAME]... [outdir]
#
#   outdir          where to write the packs (default: dist/)
#   --commit HASH   the commit the pack is named after (default: the current
#                   git commit, with "-dirty" if the work tree has changes)
#   --variant NAME  pack only this variant (repeatable; default: all)
#
# Writes, per variant:
#   <slug>-<commit>-<variant>.tar.xz          the pack
#   <slug>-<commit>-<variant>.tar.xz.sha256   "<sha256>  <file name>"
# The pack holds one directory, <slug>-<commit>-<variant>/, containing out/
# (the render), branding/spots.tsv, BRANDING-SPOTS.md, the palettes, the
# identity scripts (stamping needs ImageMagick only) and a PACK manifest.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_DIR")" && pwd)
. "$SCRIPT_DIR/lib-identity.sh"

die() { printf 'pack.sh: error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '3,19s/^# \{0,1\}//p' "$0"; }

COMMIT=''
VARIANTS=''
while [ $# -gt 0 ]; do
	case $1 in
	--commit) [ $# -ge 2 ] || die "--commit needs a value"; COMMIT=$2; shift 2 ;;
	--variant) [ $# -ge 2 ] || die "--variant needs a name"; VARIANTS="$VARIANTS $2"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	-*) usage >&2; die "unknown option: $1" ;;
	*) break ;;
	esac
done
DEST=${1:-$ROOT_DIR/dist}

if [ -z "$COMMIT" ]; then
	command -v git >/dev/null 2>&1 || die "git not found; pass --commit"
	COMMIT=$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD 2>/dev/null) || die "not a git checkout; pass --commit"
	[ -z "$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null)" ] || COMMIT="$COMMIT-dirty"
fi
printf '%s' "$COMMIT" | grep -Eq '^[0-9a-f]{7,40}(-dirty)?$' || die "commit must be a hex hash (got: $COMMIT)"

if [ -z "$VARIANTS" ]; then
	VARIANTS=$(cd "$ROOT_DIR/variants" && for d in */; do printf '%s ' "${d%/}"; done)
fi
SLUG=$(palette_value NAME_LOWER "$ROOT_DIR/palette.env")
printf '%s' "$SLUG" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || die "bad NAME_LOWER in palette.env: $SLUG"

command -v xz >/dev/null 2>&1 || die "xz not found"
sha256_line() {
	# sha256_line FILE : "<hex>  <basename>"
	if command -v sha256sum >/dev/null 2>&1; then
		_h=$(sha256sum "$1" | cut -d ' ' -f 1)
	elif command -v sha256 >/dev/null 2>&1; then
		_h=$(sha256 -q "$1")
	else
		die "no sha256sum or sha256"
	fi
	printf '%s  %s\n' "$_h" "$(basename "$1")"
}

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/pack.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 1' INT TERM
mkdir -p "$DEST"

for v in $VARIANTS; do
	[ -d "$ROOT_DIR/variants/$v" ] || die "no such variant: $v"
	NAME="$SLUG-$COMMIT-$v"
	P="$TMPD/$NAME"
	mkdir -p "$P/branding" "$P/scripts" "$P/variants/$v"
	sh "$SCRIPT_DIR/render.sh" --variant "$v" "$ROOT_DIR/palette.env" "$P/out" > "$TMPD/render-$v.log" 2>&1 ||
		{ cat "$TMPD/render-$v.log" >&2; die "render failed for $v"; }
	cp "$ROOT_DIR/branding/spots.tsv" "$P/branding/"
	cp "$ROOT_DIR/BRANDING-SPOTS.md" "$ROOT_DIR/LICENSE" "$ROOT_DIR/palette.env" "$P/"
	cp "$ROOT_DIR/variants/$v/palette.env" "$P/variants/$v/"
	cp "$SCRIPT_DIR/identity-stamp.sh" "$SCRIPT_DIR/identity-file.sh" "$SCRIPT_DIR/lib-identity.sh" "$P/scripts/"
	{
		printf 'name=%s\n' "$SLUG"
		printf 'commit=%s\n' "$COMMIT"
		printf 'variant=%s\n' "$v"
		printf 'created=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	} > "$P/PACK"
	(cd "$TMPD" && tar -cf - "$NAME") | xz -9 > "$DEST/$NAME.tar.xz"
	sha256_line "$DEST/$NAME.tar.xz" > "$DEST/$NAME.tar.xz.sha256"
	printf 'pack.sh: wrote %s\n' "$DEST/$NAME.tar.xz"
	rm -rf "$P"
done
