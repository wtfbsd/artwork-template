#!/bin/sh
# tests/test-panel.sh -- xfce4-panel.xml declares its panels the way
# xfce4-panel reads them.
#
# xfce4-panel takes the panel list from the xfconf property /panels, an array
# of ints naming the panel ids; each id N has its settings under
# /panels/panel-N. Each panel lists its plugins in /panels/panel-N/plugin-ids,
# an array of ints; each id M is defined at /plugins/plugin-M, a string naming
# the plugin. /panels/panel-N/position must parse as p=N;x=N;y=N, or
# xfce4-panel ignores it. If /panels is not such an array, xfce4-panel ignores the file
# and falls back to its stock layout (a second, bottom dock panel). xfconf
# arrays hold <value> children; a nested <property> is not an array item.
#
# Each panel must also span the screen and stay put, with the types
# xfce4-panel's stock layout uses (xfconf properties are type-tagged):
# exactly one /panels/panel-N/length, type uint value 100, and
# /panels/panel-N/length-adjust, when present, type bool value false --
# or xfce4-panel draws a short box in the corner that grows as windows
# open instead of a full-width bar. Each panel must also have exactly one
# /panels/panel-N/position-locked, type bool value true, so it cannot be
# dragged off its edge. A clock plugin (a /plugins/plugin-M whose value is
# "clock") that sets a mode must set it as type uint value 2 (digital):
# 0 is analog, 1 the binary dot-grid, 3 fuzzy and 4 LCD; no mode means
# the plugin's default, which is digital.
#
# Checks the source file and the rendered one (out/xfce/xfconf/), and first
# proves the checker rejects each broken layout it is meant to catch.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$(dirname -- "$HERE")" && pwd)

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/panel-test.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 1' INT TERM

FAILURES=0
PASSES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { printf 'ok: %s\n' "$1"; PASSES=$((PASSES + 1)); }

SRC="$ROOT/xfce/xfconf/xfce4-panel.xml"

# check_panel FILE : prints one line per problem; exit 0 only when none.
check_panel() {
	python3 -I - "$1" <<'EOF'
import re, sys
import xml.etree.ElementTree as ET

# The panels stay on the top edge so none covers the identity line in the
# lower-left corner. SnapPosition in panel-window.c runs NONE 0, E 1, NE 2,
# EC 3, SE 4, W 5, NW 6, WC 7, SW 8, NC 9, SC 10, N 11, S 12; the stock
# layout puts its top panel at p=6 and its bottom dock at p=10. The
# top-edge snaps are NE, NW, NC and N.
TOP_SNAPS = {2, 6, 9, 11}

problems = []
def bad(msg):
    problems.append(msg)

def int_values(prop, where):
    """The int items of xfconf array PROP, or None when it is not one."""
    if prop.get("type") != "array":
        bad("%s is type=%r, not an array" % (where, prop.get("type")))
        return None
    if where.endswith("plugin-ids"):
        for child in prop.findall("property"):
            bad("%s holds <property name=%r>, not a <value>" % (where, child.get("name")))
    ids = []
    for v in prop.findall("value"):
        if v.get("type") != "int" or not re.fullmatch(r"\d{1,9}", v.get("value", "")):
            bad("%s has a non-int item: type=%r value=%r" % (where, v.get("type"), v.get("value")))
            continue
        ids.append(int(v.get("value")))
    if not ids:
        bad("%s has no <value type=\"int\"> items" % where)
    if len(ids) != len(set(ids)):
        bad("%s repeats an id: %s" % (where, ids))
    return ids

try:
    root = ET.parse(sys.argv[1]).getroot()
except ET.ParseError as e:
    print("not well-formed XML: %s" % e)
    sys.exit(1)

if root.tag != "channel" or root.get("name") != "xfce4-panel":
    bad("root is <%s name=%r>, not <channel name=\"xfce4-panel\">" % (root.tag, root.get("name")))

# Every property needs a name: xfconf paths are made of them.
for p in root.iter("property"):
    if not p.get("name"):
        bad("a <property> has no name (type=%r)" % p.get("type"))

top = {}
for p in root.findall("property"):
    if not p.get("name"):
        continue
    if p.get("name") in top:
        bad("/%s is declared twice" % p.get("name"))
    top[p.get("name")] = p

# configver is the panel config version; below 2 xfce4-panel runs its
# migration over the channel, so it is required and at least 2.
if "configver" not in top:
    bad("no /configver: xfce4-panel would migrate the channel")
else:
    cv = top["configver"]
    if cv.get("type") != "int" or not re.fullmatch(r"\d{1,9}", cv.get("value", "")):
        bad("/configver is type=%r value=%r, not an int" % (cv.get("type"), cv.get("value")))
    elif int(cv.get("value")) < 2:
        bad("/configver is %s; below 2 xfce4-panel migrates the channel" % cv.get("value"))

plugins = {}
plugin_els = {}
if "plugins" not in top:
    bad("no /plugins property")
else:
    if top["plugins"].get("type") != "empty":
        bad("/plugins is type=%r, not empty" % top["plugins"].get("type"))
    for p in top["plugins"].findall("property"):
        m = re.fullmatch(r"plugin-([1-9]\d{0,8})", p.get("name") or "")
        if not m:
            if re.fullmatch(r"plugin-.*", p.get("name") or ""):
                bad("/plugins/%s is not plugin-<id> with a plain decimal id" % p.get("name"))
            continue
        if int(m.group(1)) in plugins:
            bad("/plugins/%s is defined twice" % p.get("name"))
        if p.get("type") != "string" or not p.get("value"):
            bad("/plugins/%s does not name a plugin (type=%r value=%r)"
                % (p.get("name"), p.get("type"), p.get("value")))
        plugins[int(m.group(1))] = p.get("value")
        plugin_els[int(m.group(1))] = p

# The clock plugin's mode is 0 analog, 1 binary, 2 digital, 3 fuzzy, 4 LCD.
# Mode 1 renders as a grid of dots that reads as broken; the pack ships the
# digital clock. No mode property means the plugin default, which is digital.
for _m in sorted(plugin_els):
    _el = plugin_els[_m]
    if _el.get("value") != "clock":
        continue
    for q in _el.findall("property"):
        if q.get("name") != "mode":
            continue
        if q.get("type") != "uint" or q.get("value") != "2":
            bad("/plugins/plugin-%d is a clock with mode type=%r value=%r, not uint 2 (digital)"
                % (_m, q.get("type"), q.get("value")))

if "panels" not in top:
    bad("no /panels property (found top-level: %s)" % ", ".join(sorted(top)))
else:
    panels = top["panels"]
    ids = int_values(panels, "/panels") or []
    children = {}
    for p in panels.findall("property"):
        m = re.fullmatch(r"panel-([1-9]\d{0,8})", p.get("name") or "")
        if not m and re.fullmatch(r"panel-.*", p.get("name") or ""):
            bad("/panels/%s is not panel-<id> with a plain decimal id" % p.get("name"))
        if m:
            if p.get("type") != "empty":
                bad("/panels/%s is type=%r, not empty" % (p.get("name"), p.get("type")))
            if int(m.group(1)) in children:
                bad("/panels/%s is defined twice" % p.get("name"))
            children[int(m.group(1))] = p
    # the pack ships one panel, along the top: a second one would cover the
    # identity line in the lower-left corner again
    if len(ids) != 1:
        bad("/panels lists %d panels, not the one top panel" % len(ids))
    for n in ids:
        if n not in children:
            bad("/panels lists %d but has no panel-%d" % (n, n))
    for n in sorted(set(children) - set(ids)):
        bad("stray panel-%d: not listed in /panels" % n)
    used = set()
    for n in sorted(set(children) & set(ids)):
        # panel-window.c reads the position with sscanf "p=%d;x=%d;y=%d"
        # and ignores the whole string unless all three parse; p is a
        # SnapPosition, 0 (none) to 12 (bottom).
        pos = [p for p in children[n].findall("property") if p.get("name") == "position"]
        if len(pos) != 1:
            bad("panel-%d has %d position properties, not 1" % (n, len(pos)))
        for p in pos:
            # Non-negative coordinates only: xfce4-panel clamps x and y to 0.
            m = re.fullmatch(r"p=(\d{1,2});x=(\d{1,5});y=(\d{1,5})", p.get("value", ""))
            if p.get("type") != "string" or not m or int(m.group(1)) > 12:
                bad("/panels/panel-%d/position %r is not p=N;x=N;y=N with N <= 12 for p"
                    % (n, p.get("value")))
            elif int(m.group(1)) not in TOP_SNAPS:
                bad("/panels/panel-%d/position %r is not on the top edge (p must be one of %s);"
                    " the identity line sits in the lower-left corner"
                    % (n, p.get("value"), sorted(TOP_SNAPS)))
        # A panel spans the screen only when it has exactly one
        # /panels/panel-N/length of type uint value 100 (a percentage of the
        # screen edge, the type xfce4-panel's stock layout uses) and
        # length-adjust, when present, is type bool value false; with
        # length-adjust true, or with no length at all, xfce4-panel draws a
        # short box in the corner that grows as windows open.
        lens = [p for p in children[n].findall("property") if p.get("name") == "length"]
        if not lens:
            bad("/panels/panel-%d has no length property (need exactly one: type uint, value 100)" % n)
        elif len(lens) != 1:
            bad("/panels/panel-%d has %d length properties, not exactly one" % (n, len(lens)))
        for p in lens:
            if p.get("type") != "uint" or p.get("value") != "100":
                bad("/panels/panel-%d/length is type=%r value=%r, not type uint value 100"
                    % (n, p.get("type"), p.get("value")))
        for p in children[n].findall("property"):
            if p.get("name") != "length-adjust":
                continue
            if p.get("type") != "bool" or p.get("value") != "false":
                bad("/panels/panel-%d/length-adjust is type=%r value=%r, not type bool value"
                    " false: the panel shrinks to fit its plugins instead of spanning the"
                    " screen" % (n, p.get("type"), p.get("value")))
        # position-locked keeps the panel on its edge; the stock layout sets
        # it as type bool value true, and each panel needs exactly one.
        locks = [p for p in children[n].findall("property") if p.get("name") == "position-locked"]
        if not locks:
            bad("/panels/panel-%d has no position-locked property (need exactly one:"
                " type bool, value true)" % n)
        elif len(locks) != 1:
            bad("/panels/panel-%d has %d position-locked properties, not exactly one"
                % (n, len(locks)))
        for p in locks:
            if p.get("type") != "bool" or p.get("value") != "true":
                bad("/panels/panel-%d/position-locked is type=%r value=%r, not type bool value"
                    " true: the panel can be dragged off its edge"
                    % (n, p.get("type"), p.get("value")))
        where = "/panels/panel-%d/plugin-ids" % n
        pids = [p for p in children[n].findall("property") if p.get("name") == "plugin-ids"]
        if len(pids) != 1:
            bad("panel-%d has %d plugin-ids properties" % (n, len(pids)))
            continue
        for m in int_values(pids[0], where) or []:
            used.add(m)
            if m not in plugins:
                bad("%s names plugin %d, but /plugins/plugin-%d is not defined" % (where, m, m))

    for m in sorted(set(plugins) - used):
        bad("/plugins/plugin-%d is defined but no panel lists it" % m)

for msg in problems:
    print(msg)
sys.exit(1 if problems else 0)
EOF
}

# expect_reject NAME WANT XML : the checker must refuse this layout, for the
# reason WANT (a substring of its report), and not by crashing.
expect_reject() {
	printf '%s\n' "$3" > "$TMPD/$1.xml"
	if _out=$(check_panel "$TMPD/$1.xml" 2>&1); then
		fail "checker accepted a broken layout: $1"
	else
		case $_out in
		*Traceback*) fail "checker crashed on $1: $(printf '%s' "$_out" | tail -n 1)" ;;
		*"$2"*) ok "checker rejects $1 ($(printf '%s' "$_out" | grep -F -- "$2" | head -n 1))" ;;
		*) fail "checker rejected $1, but not for \"$2\": $_out" ;;
		esac
	fi
}

# chan BODY : a channel holding BODY. panels IDS PANELS : /panels with the
# int values IDS and the panel properties PANELS. panel N BODY : panel-N.
chan() { printf '<channel name="xfce4-panel" version="1.0">%s</channel>' "$1"; }
panels() {
	printf '<property name="panels" type="array">'
	for _i in $1; do printf '<value type="int" value="%s"/>' "$_i"; done
	printf '%s</property>' "$2"
}
panel() { printf '<property name="panel-%s" type="empty">%s</property>' "$1" "$2"; }

# ------------------------------------------------ 1. the checker can fail
POS='<property name="position" type="string" value="p=6;x=0;y=0"/>'
LOCKED='<property name="position-locked" type="bool" value="true"/>'
LENGTH='<property name="length" type="uint" value="100"/>'
IDS1='<property name="plugin-ids" type="array"><value type="int" value="1"/></property>'
PLUGINS='<property name="plugins" type="empty"><property name="plugin-1" type="string" value="clock"/></property>'
PANEL1=$(panel 1 "$POS$LOCKED$LENGTH$IDS1")
CV='<property name="configver" type="int" value="2"/>'
GOOD=$(chan "$CV$(panels 1 "$PANEL1")$PLUGINS")
printf '%s\n' "$GOOD" > "$TMPD/good.xml"
if _out=$(check_panel "$TMPD/good.xml" 2>&1); then
	ok 'checker accepts a well-formed one-panel layout'
else
	fail "checker refused a good layout: $_out"
fi
expect_reject panels-empty "/panels is type='empty'" \
	"$(chan "<property name=\"panels\" type=\"empty\">$PANEL1</property>$PLUGINS")"
expect_reject panels-nested 'no /panels property' \
	"$(chan "<property name=\"config\" type=\"empty\">$(panels 1 "$PANEL1")$PLUGINS</property>")"
expect_reject stray-panel 'stray panel-2' \
	"$(chan "$(panels 1 "$PANEL1$(panel 2 "$POS$IDS1")")$PLUGINS")"
expect_reject panel-missing 'lists 2 but has no panel-2' \
	"$(chan "$(panels '1 2' "$PANEL1")$PLUGINS")"
expect_reject panel-id-string "non-int item: type='string'" \
	"$(chan "<property name=\"panels\" type=\"array\"><value type=\"string\" value=\"1\"/>$PANEL1</property>$PLUGINS")"
expect_reject panel-twice '/panels/panel-1 is defined twice' \
	"$(chan "$(panels 1 "$PANEL1$PANEL1")$PLUGINS")"
expect_reject plugin-undefined '/plugins/plugin-7 is not defined' \
	"$(chan "$(panels 1 "$(panel 1 "$POS<property name=\"plugin-ids\" type=\"array\"><value type=\"int\" value=\"1\"/><value type=\"int\" value=\"7\"/></property>")")$PLUGINS")"
expect_reject plugin-ids-properties "holds <property name='plugin-1'>" \
	"$(chan "$(panels 1 "$(panel 1 "$POS<property name=\"plugin-ids\" type=\"array\"><property name=\"plugin-1\" type=\"int\" value=\"1\"/></property>")")$PLUGINS")"
expect_reject plugin-twice '/plugins/plugin-1 is defined twice' \
	"$(chan "$(panels 1 "$PANEL1")<property name=\"plugins\" type=\"empty\"><property name=\"plugin-1\" type=\"string\" value=\"clock\"/><property name=\"plugin-1\" type=\"string\" value=\"systray\"/></property>")"
expect_reject position-unparsed "'p=6;o=76' is not p=N;x=N;y=N" \
	"$(chan "$(panels 1 "$(panel 1 "<property name=\"position\" type=\"string\" value=\"p=6;o=76\"/>$IDS1")")$PLUGINS")"
expect_reject position-missing 'panel-1 has 0 position properties' \
	"$(chan "$(panels 1 "$(panel 1 "$IDS1")")$PLUGINS")"
expect_reject position-twice 'panel-1 has 2 position properties' \
	"$(chan "$(panels 1 "$(panel 1 "$POS$POS$IDS1")")$PLUGINS")"
expect_reject position-bottom 'is not on the top edge' \
	"$(chan "$(panels 1 "$(panel 1 "<property name=\"position\" type=\"string\" value=\"p=10;x=0;y=0\"/>$IDS1")")$PLUGINS")"
expect_reject panel-not-empty "/panels/panel-1 is type='string'" \
	"$(chan "$(panels 1 "<property name=\"panel-1\" type=\"string\" value=\"x\">$POS$IDS1</property>")$PLUGINS")"
expect_reject plugins-not-empty "/plugins is type='array'" \
	"$(chan "$(panels 1 "$PANEL1")<property name=\"plugins\" type=\"array\"><property name=\"plugin-1\" type=\"string\" value=\"clock\"/></property>")"
expect_reject panel-id-huge "non-int item" \
	"$(chan "<property name=\"panels\" type=\"array\"><value type=\"int\" value=\"$(printf '%05000d' 1)\"/>$PANEL1</property>$PLUGINS")"
expect_reject panel-zero-padded "/panels/panel-01 is not panel-<id>" \
	"$(chan "$(panels 1 "$(panel 01 "$POS$IDS1")")$PLUGINS")"
expect_reject plugin-zero-padded "/plugins/plugin-01 is not plugin-<id>" \
	"$(chan "$(panels 1 "$PANEL1")<property name=\"plugins\" type=\"empty\"><property name=\"plugin-01\" type=\"string\" value=\"clock\"/></property>")"
expect_reject plugin-orphan "/plugins/plugin-2 is defined but no panel lists it" \
	"$(chan "$(panels 1 "$PANEL1")<property name=\"plugins\" type=\"empty\"><property name=\"plugin-1\" type=\"string\" value=\"clock\"/><property name=\"plugin-2\" type=\"string\" value=\"systray\"/></property>")"
expect_reject position-trailing "is not p=N;x=N;y=N" \
	"$(chan "$(panels 1 "$(panel 1 "<property name=\"position\" type=\"string\" value=\"p=6;x=0;y=0;junk\"/>$IDS1")")$PLUGINS")"
expect_reject nameless-property "a <property> has no name" \
	"$(chan "<property type=\"int\" value=\"1\"/>$(panels 1 "$PANEL1")$PLUGINS")"
expect_reject configver-string '/configver is type=' \
	"$(chan "<property name=\"configver\" type=\"string\" value=\"2\"/>$(panels 1 "$PANEL1")$PLUGINS")"
expect_reject configver-old '/configver is 1' \
	"$(chan "<property name=\"configver\" type=\"int\" value=\"1\"/>$(panels 1 "$PANEL1")$PLUGINS")"
expect_reject panel-length-missing 'has no length property' \
	"$(chan "$CV$(panels 1 "$(panel 1 "$POS$LOCKED$IDS1")")$PLUGINS")"
expect_reject panel-length-double "length is type='double' value='100', not type uint value 100" \
	"$(chan "$CV$(panels 1 "$(panel 1 "$POS$LOCKED<property name=\"length\" type=\"double\" value=\"100\"/>$IDS1")")$PLUGINS")"
expect_reject panel-length-not-100 "length is type='uint' value='50', not type uint value 100" \
	"$(chan "$CV$(panels 1 "$(panel 1 "$POS$LOCKED<property name=\"length\" type=\"uint\" value=\"50\"/>$IDS1")")$PLUGINS")"
expect_reject panel-length-string "length is type='string' value='100', not type uint value 100" \
	"$(chan "$CV$(panels 1 "$(panel 1 "$POS$LOCKED<property name=\"length\" type=\"string\" value=\"100\"/>$IDS1")")$PLUGINS")"
expect_reject length-adjust-true "length-adjust is type='bool' value='true', not type bool value false" \
	"$(chan "$CV$(panels 1 "$(panel 1 "$POS$LOCKED$LENGTH$IDS1<property name=\"length-adjust\" type=\"bool\" value=\"true\"/>")")$PLUGINS")"
expect_reject length-adjust-one "length-adjust is type='bool' value='1', not type bool value false" \
	"$(chan "$CV$(panels 1 "$(panel 1 "$POS$LOCKED$LENGTH$IDS1<property name=\"length-adjust\" type=\"bool\" value=\"1\"/>")")$PLUGINS")"
expect_reject position-locked-missing 'has no position-locked property' \
	"$(chan "$CV$(panels 1 "$(panel 1 "$POS$LENGTH$IDS1")")$PLUGINS")"
expect_reject position-locked-false "position-locked is type='bool' value='false', not type bool value true" \
	"$(chan "$CV$(panels 1 "$(panel 1 "$POS<property name=\"position-locked\" type=\"bool\" value=\"false\"/>$LENGTH$IDS1")")$PLUGINS")"
expect_reject clock-mode-binary "clock with mode type='uint' value='1', not uint 2" \
	"$(chan "$CV$(panels 1 "$PANEL1")<property name=\"plugins\" type=\"empty\"><property name=\"plugin-1\" type=\"string\" value=\"clock\"><property name=\"mode\" type=\"uint\" value=\"1\"/></property></property>")"
expect_reject clock-mode-int "clock with mode type='int' value='2', not uint 2" \
	"$(chan "$CV$(panels 1 "$PANEL1")<property name=\"plugins\" type=\"empty\"><property name=\"plugin-1\" type=\"string\" value=\"clock\"><property name=\"mode\" type=\"int\" value=\"2\"/></property></property>")"
expect_reject clock-mode-string "clock with mode type='string' value='2', not uint 2" \
	"$(chan "$CV$(panels 1 "$PANEL1")<property name=\"plugins\" type=\"empty\"><property name=\"plugin-1\" type=\"string\" value=\"clock\"><property name=\"mode\" type=\"string\" value=\"2\"/></property></property>")"

# ------------------------------------------------ 2. the source file
if _out=$(check_panel "$SRC" 2>&1); then
	ok 'xfce/xfconf/xfce4-panel.xml: /panels and plugin-ids are int arrays that match'
else
	fail "xfce/xfconf/xfce4-panel.xml:"
	printf '%s\n' "$_out" | sed 's/^/    /' >&2
fi

# ------------------------------------------------ 3. the rendered file
for _v in default cyberpunk; do
	if sh "$ROOT/scripts/render.sh" --variant "$_v" "$ROOT/palette.env" "$TMPD/out-$_v" > "$TMPD/render-$_v.log" 2>&1; then
		if _out=$(check_panel "$TMPD/out-$_v/xfce/xfconf/xfce4-panel.xml" 2>&1); then
			ok "rendered $_v xfce/xfconf/xfce4-panel.xml: /panels and plugin-ids match"
		else
			fail "rendered $_v xfce/xfconf/xfce4-panel.xml:"
			printf '%s\n' "$_out" | sed 's/^/    /' >&2
		fi
	else
		fail "render.sh failed for $_v:"
		tail -n 5 "$TMPD/render-$_v.log" | sed 's/^/    /' >&2
	fi
done

printf 'test-panel.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
