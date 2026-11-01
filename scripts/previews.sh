#!/bin/sh
# scripts/previews.sh -- regenerate the README previews in docs/screenshots/.
#
# Usage: sh scripts/previews.sh [outdir]   (default docs/screenshots)
#
# Renders both variants, stamps the identity line with a different base OS on
# each preview, and writes 1280x720 PNGs with metadata stripped. Requires
# what render.sh requires.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_DIR")" && pwd)
DEST=${1:-$ROOT_DIR/docs/screenshots}

IM=magick
command -v magick >/dev/null 2>&1 || IM=convert

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/previews.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 1' INT TERM
mkdir -p "$DEST"

for v in default cyberpunk; do
	sh "$SCRIPT_DIR/render.sh" --variant "$v" "$ROOT_DIR/palette.env" "$TMPD/$v" > /dev/null
done

# preview VARIANT LABEL BASE SOURCE_PNG NAME [BOTTOM]
preview() {
	sh "$SCRIPT_DIR/identity-file.sh" --product ExampleBSD --version 1.0 \
		--base "$3" --variant "$2" --arch amd64 > "$TMPD/id"
	"$IM" "$4" -resize 1280x720! "$TMPD/in.png"
	sh "$SCRIPT_DIR/identity-stamp.sh" --variant "$1" --bottom "${6:-0}" \
		"$TMPD/id" "$TMPD/in.png" "$TMPD/stamped.png" > /dev/null
	"$IM" "$TMPD/stamped.png" -strip -colors 255 PNG8:"$DEST/$5.png"
}

# SLiM as it looks: the panel centred on the background, the identity line
# as the welcome text on the panel.
slim_mock() {
	# slim_mock VARIANT OUT
	_font=$(sh -c ". '$SCRIPT_DIR/lib-identity.sh'; palette_value FONT '$ROOT_DIR/palette.env' '$ROOT_DIR/variants/$1/palette.env'")
	_fg=$(sh -c ". '$SCRIPT_DIR/lib-identity.sh'; palette_value IDENTITY_FG '$ROOT_DIR/palette.env' '$ROOT_DIR/variants/$1/palette.env'")
	_ff=$(fc-match -f '%{file}' "$_font" 2>/dev/null || printf '%s' "$_font")
	"$IM" "$TMPD/$1/dm/slim/examplebsd/background.png" -resize 1280x720! \
		"$TMPD/$1/dm/slim/examplebsd/panel.png" -gravity center -composite \
		-gravity NorthWest -font "$_ff" -pointsize 13 -fill "#$_fg" \
		-annotate +380+322 'ExampleBSD 1.0 | NetBSD 11.0 | Cyberpunk | amd64' "$2"
}

preview default Default 'FreeBSD 16.0-CURRENT' "$TMPD/default/lightdm/greeter-1920x1080.png" default-freebsd-greeter
preview default Default 'DragonFly 6.4.2' "$TMPD/default/wallpapers/wallpaper-2-1920x1080.png" default-dragonfly-wallpaper 20
slim_mock cyberpunk "$TMPD/slim.png"
preview cyberpunk Cyberpunk 'NetBSD 11.0' "$TMPD/slim.png" cyberpunk-netbsd-slim
preview cyberpunk Cyberpunk 'OpenBSD 8.0' "$TMPD/cyberpunk/wallpapers/wallpaper-1-1920x1080.png" cyberpunk-openbsd-wallpaper 20
preview cyberpunk Cyberpunk 'illumos r151054' "$TMPD/cyberpunk/splash/splash-1920x1080.png" cyberpunk-illumos-splash

ls -l "$DEST"
