#!/bin/sh
# tests/test-session.sh -- the wallpaper reaches every display output.
#
# xfdesktop keys the wallpaper by output name
# (/backdrop/screen0/monitor<OUTPUT>/workspace<N>/last-image). The shipped
# xfce4-desktop.xml must name "default" (the scfb and vesa drivers), and the
# session-start helper must set the wallpaper for whatever outputs are
# connected (eDP-1, HDMI-A-1, ...). The helper runs against stub
# xfconf-query, xrandr and id commands that record every call.
#
# The stub keeps two sets of properties: the listing (-l) and the ones that
# really exist (a read of a property succeeds only for those). The helper
# must fill in the outputs that have no wallpaper yet and leave the ones a
# person chose alone.
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

# xml_types NAME : the types xfce4-desktop.xml declares for property NAME
xml_types() {
	sed -n "s/.*name=\"$1\" type=\"\([a-z]*\)\".*/\1/p" "$XML" | sort -u
}
XML_IMAGE_TYPE=$(xml_types last-image)
XML_STYLE_TYPE=$(xml_types image-style)
one_type() {
	# one_type DESCRIPTION LIST : LIST holds exactly one type
	if [ "$(printf '%s\n' "$2" | wc -l)" -eq 1 ] && [ -n "$2" ]; then
		ok "$1 ($2)"
	else
		fail "$1: $2"
	fi
}
one_type 'the XML declares one type for last-image' "$XML_IMAGE_TYPE"
one_type 'the XML declares one type for image-style' "$XML_STYLE_TYPE"

# ------------------------------------------------------- 2. the helper
if [ ! -f "$HELPER" ]; then
	fail "missing $HELPER"
	printf 'test-session.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
	exit 1
fi
grep -q "^IMAGE_DEFAULT=$XML_IMAGE\$" "$HELPER" && ok 'helper default image is the packaged wallpaper' ||
	fail "helper default image is not $XML_IMAGE"
grep -q "^STYLE_DEFAULT=$XML_STYLE\$" "$HELPER" && ok 'helper default image-style is 5' ||
	fail "helper default image-style is not $XML_STYLE"

# --help prints the helper's own comment block: the styles it takes (and
# the "none" that leaves the style alone), without the shebang.
if sh "$HELPER" --help > "$TMPD/help" 2>&1; then
	if grep -qw 'none' "$TMPD/help"; then ok '--help mentions "none"'; else fail '--help does not mention "none"'; fi
	if grep -q 'xrandr' "$TMPD/help"; then
		ok '--help prints the whole comment block'
	else
		fail '--help prints only part of the comment block'
	fi
	if grep -q '#!/bin/sh' "$TMPD/help"; then fail '--help prints the shebang'; else ok '--help skips the shebang'; fi
	# The defaults are the packaged wallpaper and style 5 (zoomed): the
	# help must not claim they are read from the XML.
	if grep -qi 'the xml' "$TMPD/help"; then
		fail '--help claims the defaults come from the XML'
	else
		ok '--help does not claim the defaults come from the XML'
	fi
	if grep -q 'packaged' "$TMPD/help" && grep -q 'zoomed' "$TMPD/help"; then
		ok '--help names the packaged wallpaper and the zoomed style'
	else
		fail '--help does not name the packaged wallpaper and the zoomed style'
	fi
else
	fail '--help exited non-zero'
fi

STUB="$TMPD/stub"
mkdir -p "$STUB"
cat > "$STUB/xfconf-query" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DATA/calls"
# Record the type of every write: a test compares it with the type
# xfce4-desktop.xml declares for the same property.
_prop=''
_type=''
_prev=''
for _arg in "$@"; do
	case $_prev in
	-p) _prop=$_arg ;;
	-t) _type=$_arg ;;
	esac
	_prev=$_arg
done
if [ -n "$_type" ]; then
	printf '%s %s\n' "$_prop" "$_type" >> "$STUB_DATA/types"
fi
case "$*" in
*'-c xfce4-desktop -l'*) [ -f "$STUB_DATA/listing" ] && cat "$STUB_DATA/listing"; exit 0 ;;
*'-c xfwm4 -p /general/workspace_count'*) [ -f "$STUB_DATA/wscount" ] && cat "$STUB_DATA/wscount"; exit 1 ;;
esac
# A read of one property: it exists only when the test says so. The
# helper must find the properties that exist and leave them alone.
if [ -z "$_type" ] && [ -n "$_prop" ]; then
	if [ -f "$STUB_DATA/known" ] && grep -qxF "$_prop" "$STUB_DATA/known"; then
		printf '/home/person/pictures/chosen.png\n'
		exit 0
	fi
	printf 'Property %s not found\n' "$_prop" >&2
	exit 1
fi
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
	: > "$_d/types"
	# The properties xfconf really holds; a case writes the ones that
	# exist. Empty means: nothing is set yet.
	[ -f "$_d/known" ] || : > "$_d/known"
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
grep -q -- "-p $B/monitordefault/workspace0/image-style -n -t $XML_STYLE_TYPE -s $XML_STYLE\$" "$TMPD/scfb/calls" &&
	ok 'image-style is set to the XML style' || fail "image-style call wrong: $(cat "$TMPD/scfb/calls")"
# The helper must write the type xfce4-desktop.xml declares for the same
# property: xfconf-query refuses a write whose type differs from the one
# the channel already holds.
if grep -qxF "$B/monitordefault/workspace0/image-style $XML_STYLE_TYPE" "$TMPD/scfb/types"; then
	ok "image-style is written with the XML's type ($XML_STYLE_TYPE)"
else
	fail "image-style is not written with the XML's type ($XML_STYLE_TYPE): $(cat "$TMPD/scfb/types")"
fi
if grep -qxF "$B/monitordefault/workspace0/last-image $XML_IMAGE_TYPE" "$TMPD/scfb/types"; then
	ok "last-image is written with the XML's type ($XML_IMAGE_TYPE)"
else
	fail "last-image is not written with the XML's type ($XML_IMAGE_TYPE): $(cat "$TMPD/scfb/types")"
fi

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

# No xrandr answer: the outputs xfconf already knows. Only the style
# exists for them, so the helper fills in the wallpaper and leaves the
# style it found alone.
mkdir -p "$TMPD/listing"
printf '%s\n' "$B/monitorHDMI-A-1/workspace0/image-style" \
	"$B/monitordefault/workspace0/image-style" /last-settings-migrated > "$TMPD/listing/listing"
cp "$TMPD/listing/listing" "$TMPD/listing/known"
run_case listing --image "$IMG" || fail "helper failed (listing): $(cat "$TMPD/listing/err")"
expect_sets listing 'outputs from the xfconf listing; the style that exists is left alone' \
	"$B/monitorHDMI-A-1/workspace0/last-image" "$B/monitordefault/workspace0/last-image"

# A wallpaper the person chose must survive: the helper fills in the
# outputs that have none yet and leaves the chosen one alone.
mkdir -p "$TMPD/chosen"
printf 'Monitors: 2\n 0: +*eDP-1 1920/344x1080/193+0+0  eDP-1\n 1: +HDMI-A-1 2560/597x1440/336+1920+0  HDMI-A-1\n' > "$TMPD/chosen/monitors"
printf '%s\n' "$B/monitorHDMI-A-1/workspace0/last-image" > "$TMPD/chosen/known"
run_case chosen --image "$IMG" || fail "helper failed (chosen): $(cat "$TMPD/chosen/err")"
expect_sets chosen 'the output with a wallpaper of its own is left alone' \
	"$B/monitoreDP-1/workspace0/last-image" "$B/monitoreDP-1/workspace0/image-style"
if grep -q -- "-p $B/monitorHDMI-A-1/workspace0/last-image -n -t" "$TMPD/chosen/calls"; then
	fail 'helper overwrote the wallpaper the person chose'
else
	ok 'helper did not write over the wallpaper the person chose'
fi
if grep -q -- "-p $B/monitorHDMI-A-1/workspace0/image-style -n -t" "$TMPD/chosen/calls"; then
	fail 'helper changed the style of the output the person chose'
else
	ok 'helper left the chosen output alone'
fi

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

# --style takes 0-5, or "none"; anything else is refused and named.
for s in 6 7 12 x -1 ''; do
	_n="badstyle-$(printf '%s' "$s" | tr -c 'a-zA-Z0-9' '_')"
	mkdir -p "$TMPD/$_n"
	if run_case "$_n" --image "$IMG" --style "$s"; then
		fail "helper accepted the style $s"
	elif grep -q "bad style: $s (0-5 or none)" "$TMPD/$_n/err"; then
		ok "helper refuses the style $s by name"
	else
		fail "helper refuses the style $s but says: $(cat "$TMPD/$_n/err")"
	fi
done
# A style in range is used.
run_case style3 --image "$IMG" --style 3 || fail "helper failed (style3): $(cat "$TMPD/style3/err")"
grep -q -- "-p $B/monitordefault/workspace0/image-style -n -t $XML_STYLE_TYPE -s 3\$" "$TMPD/style3/calls" &&
	ok 'a style in 0-5 is set' || fail "style 3 not set: $(cat "$TMPD/style3/calls")"
# "none" leaves the style alone.
run_case stylenone --image "$IMG" --style none || fail "helper failed (stylenone): $(cat "$TMPD/stylenone/err")"
if [ -z "$(sets stylenone | grep image-style)" ]; then
	ok '--style none sets no style'
else
	fail "--style none set a style: $(sets stylenone)"
fi

# ----------------------------------------------------- 3. autostart entry
if [ -f "$DESKTOP" ]; then
	grep -qx 'Type=Application' "$DESKTOP" && ok 'autostart: Type=Application' || fail 'autostart: no Type=Application'
	grep -qxF 'Exec=/bin/sh "@SHARE_DIR@/xfce/session/@NAME_LOWER@-wallpaper.sh"' "$DESKTOP" &&
		ok 'autostart runs the installed helper' || fail 'autostart Exec is not the installed helper'
	grep -qx 'OnlyShowIn=XFCE;' "$DESKTOP" && ok 'autostart: Xfce only' || fail 'autostart: not OnlyShowIn=XFCE;'
else
	fail "missing $DESKTOP"
fi

printf 'test-session.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
