#!/bin/sh
# tests/test-branding.sh -- variants, display-manager assets, the branding
# spots list, rebranding of every DM asset, and the identity line.
#
# Usage: sh tests/test-branding.sh
#
# Renders both variants into a temporary directory and checks:
#   - every asset renders for each variant, and the variants really differ;
#   - a variant only overrides files that exist in the base, and only when
#     they differ from the base;
#   - every display-manager asset exists and carries the variant's palette
#     and the product's logo (never an OS default such as OpenBSD's pixmaps);
#   - branding/spots.tsv is well formed, every source path exists, every
#     rendered path is produced, and BRANDING-SPOTS.md lists every spot;
#   - rebrand.sh changes the name in every display-manager asset;
#   - identity-stamp.sh fits one line at 1024 px, keeps contrast >= 4.5:1
#     (measured here, independently of the script), and refuses to stamp
#     when it cannot reach that contrast.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$(dirname -- "$HERE")" && pwd)

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/branding-test.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 1' INT TERM

FAILURES=0
PASSES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { printf 'ok: %s\n' "$1"; PASSES=$((PASSES + 1)); }
check() {
	# check DESCRIPTION COMMAND... : ok if the command succeeds
	_d=$1
	shift
	if "$@" >/dev/null 2>&1; then ok "$_d"; else fail "$_d"; fi
}

IM=""
command -v magick >/dev/null 2>&1 && IM=magick
[ -n "$IM" ] || { command -v convert >/dev/null 2>&1 && IM=convert; } || true
[ -n "$IM" ] || { printf 'test-branding.sh: ImageMagick is required\n' >&2; exit 1; }

png_size() {
	python3 -c 'import struct, sys
with open(sys.argv[1], "rb") as fh:
    head = fh.read(24)
if head[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit(1)
w, h = struct.unpack(">II", head[16:24])
print(str(w) + " " + str(h))' "$1"
}
expect_png() {
	if [ ! -f "$1" ]; then fail "missing: $1"; return; fi
	_got=$(png_size "$1" 2>/dev/null) || { fail "unreadable png: $1"; return; }
	if [ "$_got" = "$2 $3" ]; then ok "${1#"$TMPD/"}"; else fail "size of $1: got $_got want $2 $3"; fi
}
palette_get() {
	# palette_get FILE KEY : value of KEY in a palette file ("" if absent)
	sed -nE "s/^[[:space:]]*$2=\"?([^\"]*)\"?[[:space:]]*\$/\\1/p" "$1" | tail -n 1
}
variant_get() {
	# variant_get VARIANT KEY : effective palette value (variant overrides root)
	_v=$(palette_get "$ROOT/variants/$1/palette.env" "$2" 2>/dev/null || true)
	[ -n "$_v" ] || _v=$(palette_get "$ROOT/palette.env" "$2")
	printf '%s' "$_v"
}

LOWER=$(palette_get "$ROOT/palette.env" NAME_LOWER)
VARIANTS="default cyberpunk"

# ------------------------------------------------------------ 1. variants
for v in $VARIANTS; do
	if [ ! -f "$ROOT/variants/$v/palette.env" ]; then
		fail "variants/$v/palette.env missing"
		continue
	fi
	ok "variants/$v/palette.env present"
done

for v in $VARIANTS; do
	O="$TMPD/out-$v"
	if sh "$ROOT/scripts/render.sh" --variant "$v" "$ROOT/palette.env" "$O" > "$TMPD/render-$v.log" 2>&1; then
		ok "render.sh --variant $v"
	else
		fail "render.sh --variant $v exited non-zero"
		sed 's/^/    /' "$TMPD/render-$v.log" >&2
		continue
	fi
	for s in 64 128 256 512; do expect_png "$O/logo/logo-$s.png" "$s" "$s"; done
	expect_png "$O/logo/wordmark.png" 1200 300
	expect_png "$O/logo/wordmark-light.png" 1200 300
	for s in 640x480 1024x768 1920x1080; do expect_png "$O/splash/splash-$s.png" "${s%%x*}" "${s##*x}"; done
	expect_png "$O/loader/loader-logo.png" 480 200
	expect_png "$O/loader/splash.png" 1024 768
	expect_png "$O/loader/$LOWER-brand.png" 400 100
	expect_png "$O/loader/$LOWER-logo.png" 240 200
	# vt(4) draws the splash only from an 8-bit RGBA PNG (splash(4)); the
	# loader's pnglite rejects indexed colour and interlacing.
	for f in loader/splash.png loader/$LOWER-brand.png loader/$LOWER-logo.png; do
		[ -f "$O/$f" ] || continue
		_ct=$(python3 -c 'import sys; d = open(sys.argv[1], "rb").read(29); print(d[24], d[25], d[28])' "$O/$f")
		if [ "$_ct" = "8 6 0" ]; then ok "$v $f is 8-bit RGBA, not interlaced"; else fail "$v $f is not 8-bit RGBA (depth/type/interlace: $_ct)"; fi
	done
	for f in boot/freebsd/gfx-$LOWER.lua boot/freebsd/loader.conf.fragment boot/illumos/brand-$LOWER.4th boot/illumos/logo-$LOWER.4th boot/illumos/loader.conf.fragment boot/netbsd/boot.cfg boot/dragonfly/dloader.menu console/motd.template console/gettytab.fragment; do
		if [ -s "$O/$f" ]; then ok "$v $f"; else fail "$v missing $f"; fi
	done
	grep -q "image = \"/boot/images/$LOWER-brand.png\"" "$O/boot/freebsd/gfx-$LOWER.lua" 2>/dev/null &&
		ok "$v gfx lua points at the brand PNG" || fail "$v gfx lua does not point at /boot/images/$LOWER-brand.png"
	expect_png "$O/installer/header.png" 800 96
	expect_png "$O/installer/sidebar.png" 200 600
	expect_png "$O/lightdm/greeter-1920x1080.png" 1920 1080
	for n in 1 2 3; do
		expect_png "$O/wallpapers/wallpaper-$n-1920x1080.png" 1920 1080
		expect_png "$O/wallpapers/wallpaper-$n-3840x2160.png" 3840 2160
	done
	for s in 16 32 48 128 256; do
		for name in logo installer menu; do
			expect_png "$O/icons/hicolor/${s}x$s/apps/$LOWER-$name.png" "$s" "$s"
		done
	done
	expect_png "$O/favicon/favicon-32.png" 32 32
	expect_png "$O/dm/slim/$LOWER/background.png" 1920 1080
	expect_png "$O/dm/slim/$LOWER/panel.png" 600 280
	# XPM pixel codes may contain any printable run, so XPMs are skipped.
	if find "$O" -type f ! -name '*.xpm' ! -name '*.png' ! -name '*.ico' -exec grep -lE '@[A-Z0-9_]+@' {} + > "$TMPD/tok-$v" 2>/dev/null; then
		fail "unsubstituted @TOKEN@ in $v: $(tr '\n' ' ' < "$TMPD/tok-$v")"
	else
		ok "no @TOKEN@ markers left ($v)"
	fi
	if [ "$(cat "$O/variant" 2>/dev/null)" = "$v" ]; then ok "out/variant says $v"; else fail "out/variant does not say $v"; fi
done

for f in lightdm/greeter-1920x1080.png logo/wordmark-light.png splash/splash-1920x1080.png wallpapers/wallpaper-1-1920x1080.png; do
	if [ -f "$TMPD/out-default/$f" ] && [ -f "$TMPD/out-cyberpunk/$f" ] &&
		! cmp -s "$TMPD/out-default/$f" "$TMPD/out-cyberpunk/$f"; then
		ok "cyberpunk differs from default: $f"
	else
		fail "cyberpunk does not differ from default: $f"
	fi
done

# A variant only overrides what differs: every override has a base file and
# is not a byte-identical copy of it; its palette only sets known keys.
for v in $VARIANTS; do
	[ -d "$ROOT/variants/$v" ] || continue
	_bad=0
	for f in $(cd "$ROOT/variants/$v" && find . -type f ! -name palette.env ! -name README.md | sed 's|^\./||'); do
		if [ ! -f "$ROOT/$f" ]; then fail "variants/$v/$f overrides nothing (no $f in base)"; _bad=1
		elif cmp -s "$ROOT/$f" "$ROOT/variants/$v/$f"; then fail "variants/$v/$f is identical to the base"; _bad=1
		fi
	done
	[ "$_bad" -eq 0 ] && ok "variants/$v overrides only files that exist and differ"
	for k in $(sed -nE 's/^([A-Z][A-Z0-9_]*)=.*/\1/p' "$ROOT/variants/$v/palette.env"); do
		[ "$k" = VARIANT_LABEL ] && continue
		grep -q "^$k=" "$ROOT/palette.env" || fail "variants/$v/palette.env sets unknown key $k"
		[ "$(palette_get "$ROOT/variants/$v/palette.env" "$k")" = "$(palette_get "$ROOT/palette.env" "$k")" ] &&
			fail "variants/$v/palette.env repeats the base value of $k"
	done
done
ok 'variant palettes checked'

# ---------------------------------------------------- 2. display managers
DM_TEXT="dm/xenodm/Xresources dm/xenodm/Xsetup_0 dm/xdm/Xresources dm/xdm/Xsetup_0 dm/slim/$LOWER/slim.theme dm/slim/slim.conf.fragment lightdm/lightdm-gtk-greeter.conf lightdm/greeter-gtk.css"
DM_XPM="dm/pixmaps/$LOWER-color.xpm dm/pixmaps/$LOWER-8bpp.xpm dm/pixmaps/$LOWER-1bpp.xpm"
for v in $VARIANTS; do
	O="$TMPD/out-$v"
	[ -d "$O" ] || continue
	for f in $DM_TEXT $DM_XPM; do
		if [ -s "$O/$f" ]; then ok "$v DM asset $f"; else fail "$v DM asset missing: $f"; fi
	done
	for f in $DM_XPM; do
		[ -f "$O/$f" ] || continue
		if head -n 1 "$O/$f" | grep -q '/\* XPM \*/' &&
			grep -qE '^"[0-9]+ [0-9]+ [0-9]+ [0-9]+' "$O/$f"; then
			ok "$v $f is an XPM"
		else
			fail "$v $f is not an XPM"
		fi
	done
	_ncol=$(sed -nE 's/^"[0-9]+ [0-9]+ ([0-9]+) [0-9]+.*/\1/p' "$O/dm/pixmaps/$LOWER-1bpp.xpm" 2>/dev/null | head -n 1)
	if [ -n "$_ncol" ] && [ "$_ncol" -le 3 ]; then ok "$v 1bpp XPM has <= 3 colours"; else fail "$v 1bpp XPM has ${_ncol:-?} colours"; fi
	# The 2-colour logo must still show all three bars of the mark: down the
	# middle column there must be three separate light runs.
	if [ -f "$O/dm/pixmaps/$LOWER-1bpp.xpm" ]; then
		_runs=$("$IM" "$O/dm/pixmaps/$LOWER-1bpp.xpm" -colorspace Gray -crop 1x84+56+14 +repage -depth 8 txt:- |
			awk '/^[0-9]/ { w = ($0 ~ /#FFFFFF|white|gray\(255\)/) ? 1 : 0; if (w && !p) n++; p = w } END { print n + 0 }')
		if [ "$_runs" -ge 3 ]; then ok "$v 1bpp logo shows the three bars ($_runs runs)"; else fail "$v 1bpp logo shows $_runs bar(s), want 3"; fi
	fi
	_ncol=$(sed -nE 's/^"[0-9]+ [0-9]+ ([0-9]+) [0-9]+.*/\1/p' "$O/dm/pixmaps/$LOWER-8bpp.xpm" 2>/dev/null | head -n 1)
	if [ -n "$_ncol" ] && [ "$_ncol" -le 16 ]; then ok "$v 8bpp XPM has <= 16 colours"; else fail "$v 8bpp XPM has ${_ncol:-?} colours"; fi

	P=$(variant_get "$v" PRIMARY)
	D=$(variant_get "$v" DARK)
	for f in dm/xenodm/Xresources dm/xdm/Xresources dm/slim/$LOWER/slim.theme lightdm/greeter-gtk.css; do
		[ -f "$O/$f" ] || continue
		if grep -qi "$P" "$O/$f" || grep -qi "$D" "$O/$f"; then ok "$v $f uses the $v palette"; else fail "$v $f does not use the $v palette"; fi
	done
	for f in dm/xenodm/Xresources dm/xdm/Xresources; do
		[ -f "$O/$f" ] || continue
		if grep -E '^[^!]*logoFileName' "$O/$f" | grep -vq "$LOWER-"; then
			fail "$v $f has a logoFileName that is not the product pixmap"
		elif grep -qE '^[^!]*logoFileName' "$O/$f"; then
			ok "$v $f logo is the product pixmap"
		else
			fail "$v $f sets no logoFileName"
		fi
		if grep -E '^[^!]' "$O/$f" | grep -qiE 'OpenBSD_|puffy|NetBSD\.xpm'; then fail "$v $f still refers to an OS default logo"; else ok "$v $f has no OS default logo"; fi
	done
	if grep -q '^current_theme[[:space:]]*'"$LOWER"'$' "$O/dm/slim/slim.conf.fragment" 2>/dev/null; then
		ok "$v slim.conf selects the $LOWER theme"
	else
		fail "$v slim.conf does not select the $LOWER theme"
	fi
done

# ------------------------------------------------------- 3. spots list
TSV="$ROOT/branding/spots.tsv"
HEADER='spot	what	shows	freebsd	netbsd	openbsd	dragonfly	illumos	size_format	source	rendered	notes'
if [ ! -f "$TSV" ]; then
	fail 'branding/spots.tsv missing'
else
	if [ "$(head -n 1 "$TSV")" = "$HEADER" ]; then ok 'spots.tsv header'; else fail 'spots.tsv header is wrong'; fi
	_bad=$(awk -F '\t' 'NR > 1 && NF != 12 { print NR }' "$TSV" | tr '\n' ' ')
	if [ -z "$_bad" ]; then ok 'spots.tsv: every row has 12 columns'; else fail "spots.tsv rows with wrong column count: $_bad"; fi
	_dup=$(awk -F '\t' 'NR > 1 { print $1 }' "$TSV" | sort | uniq -d | tr '\n' ' ')
	if [ -z "$_dup" ]; then ok 'spots.tsv: ids unique'; else fail "spots.tsv duplicate ids: $_dup"; fi
	_empty=$(awk -F '\t' 'NR > 1 { for (i = 1; i <= 12; i++) if ($i == "") print $1 ":" i }' "$TSV" | tr '\n' ' ')
	if [ -z "$_empty" ]; then ok 'spots.tsv: no empty cells'; else fail "spots.tsv empty cells: $_empty"; fi
	for id in loader-brand loader-logo boot-splash netbsd-boot-banner motd login-issue lightdm-background lightdm-theme xenodm-logo xenodm-colours xenodm-background slim-theme xdm-logo xdm-colours installer-header installer-sidebar installer-palette installer-slides wallpapers icon-distributor icon-menu icon-installer xfce-theme favicon identity-line; do
		if awk -F '\t' -v id="$id" 'NR > 1 && $1 == id { f = 1 } END { exit !f }' "$TSV"; then ok "spot $id listed"; else fail "spot $id not in spots.tsv"; fi
	done
	# OS cells: an absolute path, "n/a: <reason>", or "check: <what>".
	_bad=$(awk -F '\t' 'NR > 1 { for (i = 4; i <= 8; i++) if ($i !~ /^(\/|n\/a: .+|check: .+|same as |via )/) print $1 ":" i }' "$TSV" | tr '\n' ' ')
	if [ -z "$_bad" ]; then ok 'spots.tsv: OS cells are a path, n/a: or check:'; else fail "spots.tsv bad OS cells: $_bad"; fi
	# Source column: comma-separated repo paths, each must exist.
	_missing=""
	awk -F '\t' 'NR > 1 { print $10 }' "$TSV" | tr ',' '\n' | sed 's/^ *//; s/ *$//' > "$TMPD/sources"
	while IFS= read -r src; do
		case $src in n/a:*) continue ;; esac
		[ -e "$ROOT/$src" ] || _missing="$_missing $src"
	done < "$TMPD/sources"
	if [ -z "$_missing" ]; then ok 'spots.tsv: every source file exists'; else fail "spots.tsv sources missing:$_missing"; fi
	# Rendered column: paths under out/ (<slug> = NAME_LOWER), each produced.
	for v in $VARIANTS; do
		[ -d "$TMPD/out-$v" ] || continue
		_missing=""
		for r in $(awk -F '\t' 'NR > 1 { print $11 }' "$TSV" | tr ',' '\n' | sed 's/^ *//; s/ *$//'); do
			case $r in n/a*|-) continue ;; esac
			r=$(printf '%s' "$r" | sed "s/<slug>/$LOWER/g")
			[ -e "$TMPD/out-$v/$r" ] || _missing="$_missing $r"
		done
		if [ -z "$_missing" ]; then ok "spots.tsv: every rendered path exists ($v)"; else fail "spots.tsv rendered paths missing ($v):$_missing"; fi
	done
	if [ -f "$ROOT/BRANDING-SPOTS.md" ]; then
		_missing=""
		for id in $(awk -F '\t' 'NR > 1 { print $1 }' "$TSV"); do
			grep -q "\`$id\`" "$ROOT/BRANDING-SPOTS.md" || _missing="$_missing $id"
		done
		if [ -z "$_missing" ]; then ok 'BRANDING-SPOTS.md lists every spot'; else fail "BRANDING-SPOTS.md is missing:$_missing"; fi
	else
		fail 'BRANDING-SPOTS.md missing'
	fi
fi

# --------------------------------------------------------- 4. rebranding
CPY="$TMPD/copy"
mkdir -p "$CPY"
for d in palette.env src scripts variants xfce lightdm xinit dm console boot branding; do
	[ -e "$ROOT/$d" ] && cp -R "$ROOT/$d" "$CPY/"
done
if (cd "$CPY" && sh scripts/rebrand.sh --variant cyberpunk 'Neon Test' FF1E56) > "$TMPD/rebrand.log" 2>&1; then
	ok 'rebrand.sh --variant cyberpunk'
	for f in dm/xenodm/Xresources dm/xdm/Xresources dm/slim/neon-test/slim.theme lightdm/lightdm-gtk-greeter.conf dm/slim/slim.conf.fragment dm/xenodm/Xsetup_0 dm/xdm/Xsetup_0; do
		if [ ! -f "$CPY/out/$f" ]; then fail "rebrand: missing $f"; continue; fi
		if grep -qiE 'Neon Test|neon-test' "$CPY/out/$f" && ! grep -q 'ExampleBSD\|examplebsd' "$CPY/out/$f"; then
			ok "rebrand renamed $f"
		else
			fail "rebrand did not rename $f"
		fi
	done
	for f in dm/pixmaps/neon-test-color.xpm dm/pixmaps/neon-test-8bpp.xpm dm/pixmaps/neon-test-1bpp.xpm loader/neon-test-brand.png boot/freebsd/gfx-neon-test.lua boot/illumos/brand-neon-test.4th; do
		if [ -f "$CPY/out/$f" ]; then ok "rebrand produced $f"; else fail "rebrand did not produce $f"; fi
	done
	if grep -q '^PRIMARY=FF1E56$' "$CPY/variants/cyberpunk/palette.env" && [ "$(palette_get "$CPY/palette.env" PRIMARY)" = "$(palette_get "$ROOT/palette.env" PRIMARY)" ]; then
		ok 'rebrand put the colour into the variant that overrides it'
	else
		fail 'rebrand did not put the colour into the cyberpunk palette'
	fi
	grep -qi FF1E56 "$CPY/out/dm/xenodm/Xresources" && ok 'rebrand colour reaches xenodm' || fail 'rebrand colour does not reach xenodm'
	[ "$(palette_get "$CPY/palette.env" NAME)" = 'Neon Test' ] && ok 'rebrand NAME in root palette' || fail 'rebrand NAME not in root palette'
else
	fail 'rebrand.sh --variant cyberpunk exited non-zero'
	sed 's/^/    /' "$TMPD/rebrand.log" >&2
fi

# ------------------------------------------------------ 5. identity line
STAMP="$ROOT/scripts/identity-stamp.sh"
IDFILE="$ROOT/scripts/identity-file.sh"
worst_contrast() {
	# worst_contrast PNG GEOMETRY FG : lowest WCAG ratio of FG against any
	# pixel of PNG inside GEOMETRY (WxH+X+Y). Computed here in Python from
	# ImageMagick's pixel dump, independently of identity-stamp.sh.
	"$IM" "$1" -crop "$2" +repage -alpha off -depth 8 txt:- | python3 -c '
import re, sys
def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
fg = lum(sys.argv[1])
worst = None
for line in sys.stdin:
    m = re.search(r"#([0-9A-Fa-f]{6})", line)
    if not m or line.startswith("#"):
        continue
    bg = lum(m.group(1))
    hi, lo = max(fg, bg), min(fg, bg)
    r = (hi + 0.05) / (lo + 0.05)
    worst = r if worst is None or r < worst else worst
print("%.2f" % (worst or 0))' "$3"
}
kv() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
box_inside() {
	# box_inside BOX RECT : true when BOX (WxH+X+Y) lies inside RECT
	# (WxH+X+Y). Both are parsed here, not taken from the script's report.
	awk -v b="$1" -v r="$2" 'BEGIN {
		if (split(b, p, /[x+]/) != 4 || split(r, q, /[x+]/) != 4) exit 1
		exit !(p[3] >= q[3] && p[4] >= q[4] && p[3] + p[1] <= q[3] + q[1] && p[4] + p[2] <= q[4] + q[2])
	}'
}
box_x() { printf '%s\n' "$1" | sed -E 's/^[0-9]+x[0-9]+\+([0-9]+)\+.*/\1/'; }
box_y() { printf '%s\n' "$1" | sed -E 's/^[0-9]+x[0-9]+\+[0-9]+\+([0-9]+)$/\1/'; }
box_w() { printf '%s\n' "$1" | sed -E 's/^([0-9]+)x.*/\1/'; }
box_h() { printf '%s\n' "$1" | sed -E 's/^[0-9]+x([0-9]+).*/\1/'; }
safe_rect() {
	# safe_rect W H : the safe area of a W x H image, computed here from
	# the crop geometry alone: the part of the image every screen of 5:4,
	# 4:3 or 16:9 shows, that is the intersection of the centred crops.
	# The origin rounds up, as scripts/identity-stamp.sh does it.
	awk -v W="$1" -v H="$2" 'BEGIN {
		sx = 0; sy = 0; sr = W; sb = H
		n = split("5:4 4:3 16:9", r, " ")
		for (i = 1; i <= n; i++) {
			split(r[i], q, ":")
			a = q[1]; b = q[2]
			if (W * b > H * a) {
				cw = int(H * a / b)
				x0 = int((W - cw + 1) / 2)
				if (x0 > sx) sx = x0
				if (W - x0 < sr) sr = W - x0
			} else {
				ch = int(W * b / a)
				y0 = int((H - ch + 1) / 2)
				if (y0 > sy) sy = y0
				if (H - y0 < sb) sb = H - y0
			}
		}
		printf "%dx%d+%d+%d", sr - sx, sb - sy, sx, sy
	}'
}

# The header states the range of screens the safe area covers, and --help
# prints the whole comment block, not a fixed line range.
if [ ! -f "$STAMP" ]; then
	fail 'scripts/identity-stamp.sh missing'
elif sh "$STAMP" --help > "$TMPD/stamp-help" 2>&1; then
	if grep -q '4:3 to 16:9' "$TMPD/stamp-help"; then
		ok 'the stamp header states the safe area covers 4:3 to 16:9'
	else
		fail 'the stamp header does not state the 4:3 to 16:9 range'
	fi
	if grep -q '5:4, 4:3 or 16:9' "$TMPD/stamp-help"; then
		ok 'the stamp header names the three crops of the safe area'
	else
		fail 'the stamp header does not name the three crops of the safe area'
	fi
	# The line that says what is printed lists every field, safe= too.
	_print=$(grep -m1 'Prints one line:' "$TMPD/stamp-help")
	if printf '%s' "$_print" | grep -q 'safe='; then
		ok 'the stamp header lists safe= on the "Prints one line:" line'
	else
		fail "the stamp header does not list safe= on that line: $_print"
	fi
	if grep -q 'safe is the safe area' "$TMPD/stamp-help"; then
		ok 'the stamp header says "safe is the safe area"'
	else
		fail 'the stamp header does not say "safe is the safe area"'
	fi
	if grep -q 'draw the identity line' "$TMPD/stamp-help"; then
		ok 'identity-stamp.sh --help prints the whole comment block'
	else
		fail 'identity-stamp.sh --help prints only part of the comment block'
	fi
	if grep -q '#!/bin/sh' "$TMPD/stamp-help"; then
		fail 'identity-stamp.sh --help prints the shebang'
	else
		ok 'identity-stamp.sh --help skips the shebang'
	fi
else
	fail 'identity-stamp.sh --help exited non-zero'
fi

if [ -f "$IDFILE" ]; then
	sh "$IDFILE" --product ExampleBSD --version 1.0 --base 'FreeBSD 16.0-CURRENT' --variant Cyberpunk --arch aarch64 --build 2026-11-01 > "$TMPD/identity" 2>"$TMPD/idfile.err" &&
		ok 'identity-file.sh writes an identity file' || fail 'identity-file.sh failed'
	for k in PRODUCT VERSION BASE VARIANT ARCH BUILD; do
		grep -q "^$k=" "$TMPD/identity" && ok "identity has $k" || fail "identity lacks $k"
	done
	# A release build has no build date: the file must still be accepted.
	if sh "$IDFILE" --product ExampleBSD --version 1.0 --base 'OpenBSD 8.0' --variant Default --arch amd64 > "$TMPD/id-release" 2>/dev/null &&
		sh "$STAMP" "$TMPD/id-release" "$TMPD/out-default/lightdm/greeter-1920x1080.png" "$TMPD/rel.png" > /dev/null 2>&1; then
		ok 'identity without a build date (release) is accepted'
	else
		fail 'identity without a build date (release) is refused'
	fi
	if sh "$IDFILE" --product 'Bad$(id)' --version 1 --base x --variant y --arch z > /dev/null 2>&1; then
		fail 'identity-file.sh accepted a shell metacharacter'
	else
		ok 'identity-file.sh rejects shell metacharacters'
	fi
else
	fail 'scripts/identity-file.sh missing'
fi

if [ -f "$STAMP" ] && [ -f "$TMPD/identity" ]; then
	for v in $VARIANTS; do
		IN="$TMPD/out-$v/lightdm/greeter-1920x1080.png"
		[ -f "$IN" ] || continue
		OUTP="$TMPD/stamped-$v.png"
		if R=$(sh "$STAMP" --variant "$v" "$TMPD/identity" "$IN" "$OUTP" 2>"$TMPD/stamp-$v.err"); then
			ok "identity-stamp.sh on the $v greeter"
		else
			fail "identity-stamp.sh failed on $v: $(cat "$TMPD/stamp-$v.err")"
			continue
		fi
		expect_png "$OUTP" 1920 1080
		cmp -s "$IN" "$OUTP" && fail "stamp did not change the $v greeter" || ok "stamp changed the $v greeter"
		G=$(kv "$R" bbox); FG=$(kv "$R" fg); PLATE=$(kv "$R" plate); SAFE=$(kv "$R" safe)
		case $G in *x*+*+*) ;; *) fail "stamp reported no bbox: $R"; continue ;; esac
		case $SAFE in *x*+*+*) ;; *) fail "stamp reported no safe area: $R"; continue ;; esac
		_x=$(box_x "$G")
		_y=$(box_y "$G")
		_h=$(box_h "$G")
		# The safe area the test computes itself, from the crop
		# geometry: the stamp must sit inside that rectangle, and not
		# only inside the one the script reports. No magic numbers.
		_iw=$("$IM" "$IN" -format '%w' info:)
		_ih=$("$IM" "$IN" -format '%h' info:)
		WSAFE=$(safe_rect "$_iw" "$_ih")
		if [ "$SAFE" = "$WSAFE" ]; then
			ok "$v the reported safe area $SAFE is the crop rectangle"
		else
			fail "$v the reported safe area is $SAFE, want $WSAFE"
		fi
		_sx=$(box_x "$WSAFE")
		_sy=$(box_y "$WSAFE")
		_sh=$(box_h "$WSAFE")
		# The stamp must sit inside the safe area: its left edge at or
		# right of the safe area's left edge, and the box inside the
		# safe rectangle the test computed.
		if [ "$_x" -ge "$_sx" ] && box_inside "$G" "$WSAFE"; then
			ok "$v stamp is inside the safe area ($G in $WSAFE)"
		else
			fail "$v stamp is not inside the safe area ($G in $WSAFE)"
		fi
		# And in the lower left of it: the box starts in the left quarter of
		# the safe area and ends within 80 px of its bottom edge.
		if [ $((_x - _sx)) -le $(( $(box_w "$SAFE") / 4 )) ] &&
			[ $((_y + _h)) -ge $((_sy + _sh - 80)) ]; then
			ok "$v stamp is in the lower left of the safe area ($G in $SAFE)"
		else
			fail "$v stamp is not in the lower left of the safe area ($G in $SAFE)"
		fi
		if [ "$PLATE" = 0 ]; then
			C=$(worst_contrast "$IN" "$G" "$FG")
		else
			C=$(worst_contrast "$OUTP" 4x4+$((_x + 1))+$((_y + 1)) "$FG")
		fi
		awk -v c="$C" 'BEGIN { exit !(c >= 4.5) }' && ok "$v identity contrast $C >= 4.5 (measured)" || fail "$v identity contrast $C < 4.5"
	done
	# Fit: the longest line on a 1024x768 background stays on one line.
	"$IM" -size 1024x768 "xc:#$(variant_get default DARK)" "$TMPD/small.png"
	for base in 'FreeBSD 16.0-CURRENT' 'NetBSD 11.0' 'OpenBSD 8.0' 'DragonFly 6.4.2' 'illumos r151054'; do
		sh "$IDFILE" --product ExampleBSD --version 1.0 --base "$base" --variant Cyberpunk --arch aarch64 --build 2026-11-01 > "$TMPD/id-fit"
		if R=$(sh "$STAMP" "$TMPD/id-fit" "$TMPD/small.png" "$TMPD/small-out.png" 2>"$TMPD/fit.err"); then
			G=$(kv "$R" bbox); _w=${G%%x*}; _h=$(printf '%s' "$G" | sed -E 's/^[0-9]+x([0-9]+).*/\1/'); _x=$(printf '%s' "$G" | sed -E 's/.*x[0-9]+\+([0-9]+)\+.*/\1/')
			_pt=$(kv "$R" size)
			# Ink height of what was drawn, from a pixel diff (independent of
			# the script's own measurement): one line stays under 1.6 x size.
			_ink=$("$IM" "$TMPD/small.png" "$TMPD/small-out.png" -compose difference -composite -threshold 1% -trim -format '%h' info:)
			if [ $((_x + _w)) -le 1000 ] && [ $((_ink * 10)) -lt $((_pt * 16)) ] && [ "$_pt" -ge 11 ]; then
				ok "one line at 1024 px: $base ($G, ${_pt}px, ink ${_ink}px)"
			else
				fail "does not fit one line at 1024 px: $base ($G, ${_pt}px, ink ${_ink}px)"
			fi
		else
			fail "stamp failed at 1024 px for $base: $(cat "$TMPD/fit.err")"
		fi
	done
	grep -q 'FreeBSD 16.0-CURRENT' "$TMPD/id-fit" && fail 'identity file not rewritten per base' || true
	# The padded box must stay inside the safe area: it starts no further
	# left than the safe area and ends inside it. With the real margin
	# and padding that always holds, so a copy of the script is patched
	# here to break it. Without the guard the copy would draw outside the
	# safe area; with it, the copy refuses and says so in one line.
	GREETER="$TMPD/out-default/lightdm/greeter-1920x1080.png"
	if [ -f "$GREETER" ]; then
		cp -R "$ROOT/scripts" "$TMPD/scripts-fit"
		cp "$ROOT/palette.env" "$TMPD/palette.env"
		for v in $VARIANTS; do
			mkdir -p "$TMPD/variants/$v"
			cp "$ROOT/variants/$v/palette.env" "$TMPD/variants/$v/palette.env"
		done
		# No margin and a padding of one pixel: the box would start one
		# pixel left of the safe area, and must be clamped to it.
		sed -e 's|^MARGIN=\$(( (H + 22) / 45 ))$|MARGIN=0|' \
			-e 's|^\[ "\$MARGIN" -ge 8 \] \|\| MARGIN=8$|MARGIN=0|' \
			-e 's|^PAD=\$(( (SIZE \* 2 + 4) / 5 ))$|PAD=1|' \
			"$ROOT/scripts/identity-stamp.sh" > "$TMPD/scripts-fit/identity-stamp.sh"
		if grep -q '^PAD=1$' "$TMPD/scripts-fit/identity-stamp.sh" &&
			grep -q '^MARGIN=0$' "$TMPD/scripts-fit/identity-stamp.sh"; then
			if R=$(sh "$TMPD/scripts-fit/identity-stamp.sh" "$TMPD/identity" \
				"$GREETER" "$TMPD/fit-clamp.png" 2> "$TMPD/fit-clamp.err"); then
				G=$(kv "$R" bbox)
				WANT=$(box_x "$(safe_rect 1920 1080)")
				if [ "$(box_x "$G")" = "$WANT" ]; then
					ok "the padded box starts at the safe area's left edge ($G)"
				else
					fail "the padded box starts at $(box_x "$G"), want $WANT"
				fi
			else
				fail "the patched stamp failed: $(cat "$TMPD/fit-clamp.err")"
			fi
		else
			fail 'could not patch the copy of identity-stamp.sh'
		fi
		# No margin and a huge padding: the box cannot fit the safe area.
		sed -e 's|^MARGIN=\$(( (H + 22) / 45 ))$|MARGIN=0|' \
			-e 's|^\[ "\$MARGIN" -ge 8 \] \|\| MARGIN=8$|MARGIN=0|' \
			-e 's|^PAD=\$(( (SIZE \* 2 + 4) / 5 ))$|PAD=800|' \
			"$ROOT/scripts/identity-stamp.sh" > "$TMPD/scripts-fit/identity-stamp.sh"
		if sh "$TMPD/scripts-fit/identity-stamp.sh" "$TMPD/identity" "$GREETER" \
			"$TMPD/fit-guard.png" > "$TMPD/fit-guard.out" 2> "$TMPD/fit-guard.err"; then
			fail 'a padded box that does not fit the safe area was drawn'
		elif grep -q 'identity line does not fit in the 1350px safe area of 1920x1080' "$TMPD/fit-guard.err"; then
			ok 'a padded box that does not fit the safe area is refused'
		else
			fail "the padded box does not fit the safe area but the script says: $(cat "$TMPD/fit-guard.err")"
		fi
		_n=$(wc -l < "$TMPD/fit-guard.err")
		[ "$_n" -eq 1 ] && ok 'the refusal is one line' || fail "the refusal is $_n lines"
	else
		fail 'no greeter to stamp'
	fi
	# Hostile background: the text colour itself. Must back with a plate
	# and still pass, and must refuse outright with --no-plate.
	FGC=$(variant_get default IDENTITY_FG)
	"$IM" -size 1024x768 "xc:#$FGC" "$TMPD/hostile.png"
	if R=$(sh "$STAMP" "$TMPD/identity" "$TMPD/hostile.png" "$TMPD/hostile-out.png" 2>/dev/null) && [ "$(kv "$R" plate)" = 1 ]; then
		G=$(kv "$R" bbox); _x=$(printf '%s' "$G" | sed -E 's/.*x[0-9]+\+([0-9]+)\+.*/\1/'); _y=$(printf '%s' "$G" | sed -E 's/.*\+([0-9]+)$/\1/')
		C=$(worst_contrast "$TMPD/hostile-out.png" 4x4+$((_x + 1))+$((_y + 1)) "$(kv "$R" fg)")
		awk -v c="$C" 'BEGIN { exit !(c >= 4.5) }' && ok "hostile background gets a plate, contrast $C" || fail "hostile plate contrast $C < 4.5"
	else
		fail 'stamp on a hostile background did not use a plate'
	fi
	if sh "$STAMP" --no-plate "$TMPD/identity" "$TMPD/hostile.png" "$TMPD/hostile-np.png" >/dev/null 2>&1; then
		fail 'stamp --no-plate accepted contrast below 4.5'
	else
		ok 'stamp --no-plate refuses contrast below 4.5'
	fi
	# render.sh --identity stamps the greeter and writes the line into DM text.
	if sh "$ROOT/scripts/render.sh" --variant cyberpunk --identity "$TMPD/identity" "$ROOT/palette.env" "$TMPD/out-id" > "$TMPD/render-id.log" 2>&1; then
		ok 'render.sh --identity'
		cmp -s "$TMPD/out-id/lightdm/greeter-1920x1080.png" "$TMPD/out-cyberpunk/lightdm/greeter-1920x1080.png" &&
			fail 'render.sh --identity did not stamp the greeter' || ok 'render.sh --identity stamped the greeter'
		cmp -s "$TMPD/out-id/dm/slim/$LOWER/background.png" "$TMPD/out-cyberpunk/dm/slim/$LOWER/background.png" &&
			fail 'render.sh --identity did not stamp the slim background' || ok 'render.sh --identity stamped the slim background'
		for f in dm/xenodm/Xresources dm/xdm/Xresources dm/slim/$LOWER/slim.theme; do
			grep -q 'FreeBSD 16.0-CURRENT' "$TMPD/out-id/$f" && ok "identity line in $f" || fail "identity line not in $f"
		done
		[ -f "$TMPD/out-id/identity" ] && ok 'render.sh --identity installs out/identity' || fail 'render.sh --identity did not copy out/identity'
	else
		fail 'render.sh --identity exited non-zero'
		sed 's/^/    /' "$TMPD/render-id.log" >&2
	fi
else
	fail 'scripts/identity-stamp.sh missing (or no identity file)'
fi

# ---------------------------------------------------------- 6. README
for word in 'variant' 'BRANDING-SPOTS.md' 'identity' 'docs/screenshots/'; do
	grep -q "$word" "$ROOT/README.md" && ok "README mentions $word" || fail "README does not mention $word"
done
# The README says where the xfce/ tree installs.
for word in '/etc/xdg/autostart/' 'xfce/session/'; do
	grep -q "$word" "$ROOT/README.md" && ok "README mentions $word" || fail "README does not mention $word"
done
# It says what the tokens expand to, how the session helper is installed,
# and that the helper only fills in the outputs that have no wallpaper.
if grep -q '/usr/local/share/<slug>' "$ROOT/README.md" &&
	grep -q '@SHARE_DIR@' "$ROOT/README.md"; then
	ok 'README says @SHARE_DIR@ expands to /usr/local/share/<slug>'
else
	fail 'README does not say @SHARE_DIR@ expands to /usr/local/share/<slug>'
fi
if grep -q '@NAME_LOWER@' "$ROOT/README.md" && grep -q '<slug>' "$ROOT/README.md"; then
	ok 'README says @NAME_LOWER@ expands to the slug'
else
	fail 'README does not say @NAME_LOWER@ expands to the slug'
fi
if grep -q 'root-owned' "$ROOT/README.md" && grep -q '0755' "$ROOT/README.md"; then
	ok 'README says the session helper is installed root-owned, mode 0755'
else
	fail 'README does not say the session helper is installed root-owned, mode 0755'
fi
if grep -qi 'no wallpaper yet\|none yet' "$ROOT/README.md"; then
	ok 'README says the helper fills in the outputs that have no wallpaper yet'
else
	fail 'README does not say the helper fills in the outputs that have no wallpaper yet'
fi
_n=0
for p in "$ROOT"/docs/screenshots/*.png; do
	[ -f "$p" ] || continue
	_n=$((_n + 1))
	_sz=$(wc -c < "$p")
	[ "$_sz" -le 307200 ] && ok "preview $(basename "$p") <= 300 KB" || fail "preview $(basename "$p") is $_sz bytes"
done
for v in default cyberpunk; do
	ls "$ROOT"/docs/screenshots/"$v"-*.png >/dev/null 2>&1 && ok "previews for $v" || fail "no previews for $v"
done
for b in FreeBSD NetBSD OpenBSD DragonFly illumos; do
	ls "$ROOT"/docs/screenshots/*-"$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]')"*.png >/dev/null 2>&1 && ok "a preview shows $b" || fail "no preview shows $b"
done

printf 'test-branding.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
