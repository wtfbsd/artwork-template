#!/bin/sh
# @NAME_LOWER@-wallpaper.sh -- set the @NAME@ wallpaper on every display
# output at Xfce login.
#
# Usage: sh @NAME_LOWER@-wallpaper.sh [--image PATH] [--style N|none]
#
#   --image PATH  wallpaper (default: the packaged wallpaper,
#                 @SHARE_DIR@/wallpapers/wallpaper-1-1920x1080.png)
#   --style N     xfdesktop image-style, 0-5 (default: 5, zoomed);
#                 "none" leaves the style alone
#
# xfdesktop keys the wallpaper by output name, so the shipped
# xfce4-desktop.xml covers only the outputs it lists. This sets
# /backdrop/screen0/monitor<OUTPUT>/workspace<N>/last-image (and
# image-style) for every output that xrandr --listmonitors reports or that
# xfconf already lists, and every workspace; "default" if none is known.
# It only fills in outputs that have no wallpaper yet: a property xfconf
# already holds is left alone, so a wallpaper the person chose is never
# overwritten.
# Run as the logged-in user, from an XDG autostart entry; never as root.
set -eu

IMAGE_DEFAULT=@SHARE_DIR@/wallpapers/wallpaper-1-1920x1080.png
STYLE_DEFAULT=5

die() { printf '@NAME_LOWER@-wallpaper: %s\n' "$*" >&2; exit 1; }
usage() {
	# the leading comment block, up to the first line that is not a comment
	awk 'NR == 1 { next } /^#/ { sub(/^#[[:space:]]?/, ""); print; next } { exit }' "$0"
}

IMAGE=$IMAGE_DEFAULT
STYLE=$STYLE_DEFAULT
while [ $# -gt 0 ]; do
	case $1 in
	--image) [ $# -ge 2 ] || die "--image needs a path"; IMAGE=$2; shift 2 ;;
	--style) [ $# -ge 2 ] || die "--style needs a value"; STYLE=$2; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) die "unknown argument: $1" ;;
	esac
done
case $STYLE in
none) STYLE='' ;;
0|1|2|3|4|5) ;;
*) die "bad style: $STYLE (0-5 or none)" ;;
esac

[ "$(id -u)" != 0 ] || die "refusing to run as root"
[ -f "$IMAGE" ] || die "no such image: $IMAGE"
command -v xfconf-query >/dev/null 2>&1 || die "xfconf-query not found"

CH=xfce4-desktop
BASE=/backdrop/screen0

# Output names: the last field of each xrandr --listmonitors line, then the
# monitor<NAME> nodes xfdesktop has already written.
outputs() {
	if command -v xrandr >/dev/null 2>&1; then
		xrandr --listmonitors 2>/dev/null | awk 'NR > 1 && NF >= 2 { print $NF }' || true
	fi
	xfconf-query -c "$CH" -l 2>/dev/null |
		sed -n "s|^$BASE/monitor\([^/]*\)/.*|\1|p" || true
}
NAMES=$(outputs | grep -E '^[A-Za-z0-9._-]+$' | sort -u || true)
[ -n "$NAMES" ] || NAMES=default

WS=$(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || true)
case $WS in ''|*[!0-9]*) WS=1 ;; esac
[ "$WS" -ge 1 ] || WS=1
[ "$WS" -le 64 ] || WS=64

# exists PROP : true when xfconf already holds PROP.
exists() {
	xfconf-query -c "$CH" -p "$1" >/dev/null 2>&1
}

for _o in $NAMES; do
	_w=0
	while [ "$_w" -lt "$WS" ]; do
		_p="$BASE/monitor$_o/workspace$_w"
		# A wallpaper the person chose is never overwritten: fill in
		# only the outputs that have none yet.
		if exists "$_p/last-image"; then
			_w=$((_w + 1))
			continue
		fi
		xfconf-query -c "$CH" -p "$_p/last-image" -n -t string -s "$IMAGE" ||
			die "cannot set $_p/last-image"
		if [ -n "$STYLE" ] && ! exists "$_p/image-style"; then
			xfconf-query -c "$CH" -p "$_p/image-style" -n -t uint -s "$STYLE" ||
				die "cannot set $_p/image-style"
		fi
		_w=$((_w + 1))
	done
done
