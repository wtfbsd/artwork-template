#!/bin/sh
# tests/test-session.sh -- the wallpaper reaches every display output.
#
# xfdesktop keys the wallpaper by output name
# (/backdrop/screen0/monitor<OUTPUT>/workspace<N>/last-image). The shipped
# xfce4-desktop.xml must name "default" (the scfb and vesa drivers), and the
# session-start helper must set the wallpaper for whatever outputs are
# connected (eDP-1, HDMI-A-1, ...). The helper runs against stub
# xfconf-query, xrandr and id commands that record every call.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$(dirname -- "$HERE")" && pwd)

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/session-test.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 1' INT TERM

FAILURES=0
PASSES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { printf 'ok: %s\n' "$1"; PASSES=$((PASSES + 1)); }

XML="$ROOT/xfce/xfconf/xfce4-desktop.xml"
HELPER="$ROOT/xfce/session/@NAME_LOWER@-wallpaper.sh"
DESKTOP="$ROOT/xfce/autostart/@NAME_LOWER@-wallpaper.desktop"

# ------------------------------------------------- 1. xfce4-desktop.xml
# monitor_props NAME : the property names under monitor NAME, workspace0
monitor_props() {
	awk -v m="monitor$1" '
		/<property name="/ { n = $0; sub(/.*<property name="/, "", n); sub(/".*/, "", n) }
		/<property name="/ && /type="empty"/ && !/\/>/ { depth++; path[depth] = n; next }
		/<\/property>/ { depth--; next }
		/<property name="/ && depth == 4 && path[3] == m && path[4] == "workspace0" { print n }' "$XML"
}
for m in default 0; do
	_p=$(monitor_props "$m" | tr '\n' ' ')
	case $_p in
	*last-image*image-style*|*image-style*last-image*) ok "xfce4-desktop.xml sets monitor$m/workspace0" ;;
	*) fail "xfce4-desktop.xml lacks monitor$m/workspace0 last-image and image-style (got: $_p)" ;;
	esac
done
XML_IMAGE=$(sed -n 's/.*name="last-image" type="string" value="\([^"]*\)".*/\1/p' "$XML" | sort -u)
XML_STYLE=$(sed -n 's/.*name="image-style" type="[a-z]*" value="\([0-9]*\)".*/\1/p' "$XML" | sort -u)
[ "$(printf '%s\n' "$XML_IMAGE" | wc -l)" -eq 1 ] && ok "one wallpaper for every monitor in the XML" ||
	fail "the XML names more than one wallpaper: $XML_IMAGE"

# ------------------------------------------------------- 2. the helper
if [ ! -f "$HELPER" ]; then
	fail "missing $HELPER"
	printf 'test-session.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
	exit 1
fi
grep -q "^IMAGE_DEFAULT=$XML_IMAGE\$" "$HELPER" && ok 'helper default image is the XML wallpaper' ||
	fail "helper default image is not $XML_IMAGE"
grep -q "^STYLE_DEFAULT=$XML_STYLE\$" "$HELPER" && ok 'helper default image-style is the XML one' ||
	fail "helper default image-style is not $XML_STYLE"

STUB="$TMPD/stub"
mkdir -p "$STUB"
cat > "$STUB/xfconf-query" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DATA/calls"
case "$*" in
*'-c xfce4-desktop -l'*) [ -f "$STUB_DATA/listing" ] && cat "$STUB_DATA/listing" ;;
*'-c xfwm4 -p /general/workspace_count'*) [ -f "$STUB_DATA/wscount" ] && cat "$STUB_DATA/wscount" || exit 1 ;;
esac
exit 0
EOF
cat > "$STUB/xrandr" <<'EOF'
#!/bin/sh
[ "$*" = --listmonitors ] || exit 2
[ -f "$STUB_DATA/monitors" ] || exit 1
cat "$STUB_DATA/monitors"
EOF
cat > "$STUB/id" <<'EOF'
#!/bin/sh
[ "$*" = -u ] && { cat "$STUB_DATA/uid"; exit 0; }
exit 1
EOF
chmod 755 "$STUB/xfconf-query" "$STUB/xrandr" "$STUB/id"
IMG="$TMPD/wall.png"
: > "$IMG"

# run_case NAME [helper args...] : run the helper with $TMPD/NAME as STUB_DATA
run_case() {
	_d="$TMPD/$1"
	shift
	mkdir -p "$_d"
	[ -f "$_d/uid" ] || printf '1001\n' > "$_d/uid"
	: > "$_d/calls"
	STUB_DATA=$_d PATH="$STUB:$PATH" sh "$HELPER" "$@" > "$_d/out" 2> "$_d/err"
}
# sets CASE : the property paths the helper set, sorted, one per line
sets() { sed -n 's/.*-c xfce4-desktop -p \([^ ]*\) .*-s.*/\1/p' "$TMPD/$1/calls" | sort; }
expect_sets() {
	# expect_sets CASE DESCRIPTION PATH... : exactly these paths were set
	_c=$1 _desc=$2
	shift 2
	printf '%s\n' "$@" | sort > "$TMPD/$_c/want"
	sets "$_c" > "$TMPD/$_c/got"
	if cmp -s "$TMPD/$_c/want" "$TMPD/$_c/got"; then ok "$_desc"; else
		fail "$_desc: got $(tr '\n' ' ' < "$TMPD/$_c/got")"; fi
}
B=/backdrop/screen0

# scfb: one output, called "default", nothing in xfconf yet.
mkdir -p "$TMPD/scfb"
printf 'Monitors: 1\n 0: +*default 1024/271x768/203+0+0  default\n' > "$TMPD/scfb/monitors"
if run_case scfb --image "$IMG"; then ok 'helper runs (scfb)'; else fail "helper failed (scfb): $(cat "$TMPD/scfb/err")"; fi
expect_sets scfb 'scfb output "default" gets the wallpaper and style' \
	"$B/monitordefault/workspace0/last-image" "$B/monitordefault/workspace0/image-style"
grep -q -- "-p $B/monitordefault/workspace0/last-image -n -t string -s $IMG\$" "$TMPD/scfb/calls" &&
	ok 'last-image is set to the image, created if missing' || fail "last-image call wrong: $(cat "$TMPD/scfb/calls")"
grep -q -- "-p $B/monitordefault/workspace0/image-style -n -t int -s $XML_STYLE\$" "$TMPD/scfb/calls" &&
	ok 'image-style is set to the XML style' || fail "image-style call wrong: $(cat "$TMPD/scfb/calls")"

# A laptop panel and an HDMI monitor, two workspaces.
mkdir -p "$TMPD/two"
printf 'Monitors: 2\n 0: +*eDP-1 1920/344x1080/193+0+0  eDP-1\n 1: +HDMI-A-1 2560/597x1440/336+1920+0  HDMI-A-1\n' > "$TMPD/two/monitors"
printf '2\n' > "$TMPD/two/wscount"
run_case two --image "$IMG" || fail "helper failed (two): $(cat "$TMPD/two/err")"
expect_sets two 'eDP-1 and HDMI-A-1, both workspaces' \
	"$B/monitoreDP-1/workspace0/last-image" "$B/monitoreDP-1/workspace0/image-style" \
	"$B/monitoreDP-1/workspace1/last-image" "$B/monitoreDP-1/workspace1/image-style" \
	"$B/monitorHDMI-A-1/workspace0/last-image" "$B/monitorHDMI-A-1/workspace0/image-style" \
	"$B/monitorHDMI-A-1/workspace1/last-image" "$B/monitorHDMI-A-1/workspace1/image-style"

# No xrandr answer: the outputs xfdesktop already wrote to xfconf.
mkdir -p "$TMPD/listing"
printf '%s\n' "$B/monitorHDMI-A-1/workspace0/last-image" "$B/monitorHDMI-A-1/workspace0/image-style" \
	"$B/monitordefault/workspace0/last-image" /last-settings-migrated > "$TMPD/listing/listing"
run_case listing --image "$IMG" --style none || fail "helper failed (listing): $(cat "$TMPD/listing/err")"
expect_sets listing 'outputs from the xfconf listing; --style none sets no style' \
	"$B/monitorHDMI-A-1/workspace0/last-image" "$B/monitordefault/workspace0/last-image"

# Nothing known at all: fall back to "default".
mkdir -p "$TMPD/none"
run_case none --image "$IMG" || fail "helper failed (none): $(cat "$TMPD/none/err")"
expect_sets none 'no outputs known: "default"' \
	"$B/monitordefault/workspace0/last-image" "$B/monitordefault/workspace0/image-style"

# An output name that is not a plain name is skipped.
mkdir -p "$TMPD/bad"
printf 'Monitors: 2\n 0: +*x;id 1/1x1/1+0+0  x;id\n 1: +DP-1 1/1x1/1+0+0  DP-1\n' > "$TMPD/bad/monitors"
run_case bad --image "$IMG" --style none || fail "helper failed (bad): $(cat "$TMPD/bad/err")"
expect_sets bad 'odd output names are skipped' "$B/monitorDP-1/workspace0/last-image"

# Never as root; never with a missing image; bad style refused.
mkdir -p "$TMPD/root"
printf '0\n' > "$TMPD/root/uid"
if run_case root --image "$IMG"; then fail 'helper ran as root'; else
	[ -z "$(sets root)" ] && ok 'helper refuses to run as root' || fail 'helper set properties as root'; fi
if run_case noimg --image "$TMPD/missing.png"; then fail 'helper accepted a missing image'; else
	[ -z "$(sets noimg)" ] && ok 'helper refuses a missing image' || fail 'helper set properties for a missing image'; fi
if run_case badstyle --image "$IMG" --style 'x'; then fail 'helper accepted a bad style'; else ok 'helper refuses a bad style'; fi
for c in root noimg badstyle; do
	_n=$(wc -l < "$TMPD/$c/err")
	[ "$_n" -le 2 ] && ok "terse error ($c)" || fail "error for $c is $_n lines"
done

# ----------------------------------------------------- 3. autostart entry
if [ -f "$DESKTOP" ]; then
	grep -qx 'Type=Application' "$DESKTOP" && ok 'autostart: Type=Application' || fail 'autostart: no Type=Application'
	grep -qx 'Exec=/bin/sh @SHARE_DIR@/xfce/session/@NAME_LOWER@-wallpaper.sh' "$DESKTOP" &&
		ok 'autostart runs the installed helper' || fail 'autostart Exec is not the installed helper'
	grep -qx 'OnlyShowIn=XFCE;' "$DESKTOP" && ok 'autostart: Xfce only' || fail 'autostart: not OnlyShowIn=XFCE;'
else
	fail "missing $DESKTOP"
fi

printf 'test-session.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
