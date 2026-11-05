#!/bin/sh
# tests/test-crop.sh -- the identity line survives a screen of another shape.
#
# xfdesktop (image-style 5, zoomed) and the greeters scale a background to
# fill the screen and crop what overflows, centred. A 16:9 background on a
# 4:3 or 5:4 screen loses its left and right edges; a 4:3 background on a
# 16:9 screen loses its top and the bottom. For every background
# render.sh stamps, and for some other screen sizes, the stamp (found by
# diffing the image with and without it, not from the script's own report)
# must lie inside the central 5:4, 4:3 and 16:9 crops.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$(dirname -- "$HERE")" && pwd)

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/crop-test.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 1' INT TERM

FAILURES=0
PASSES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { printf 'ok: %s\n' "$1"; PASSES=$((PASSES + 1)); }

IM=""
command -v magick >/dev/null 2>&1 && IM=magick
[ -n "$IM" ] || { command -v convert >/dev/null 2>&1 && IM=convert; } || true
[ -n "$IM" ] || { printf 'test-crop.sh: ImageMagick is required\n' >&2; exit 1; }

LOWER=$(sed -nE 's/^[[:space:]]*NAME_LOWER="?([^"]*)"?[[:space:]]*$/\1/p' "$ROOT/palette.env")

# stamp_box PLAIN STAMPED : WxH+X+Y of the pixels that differ
stamp_box() {
	"$IM" "$1" "$2" -alpha off -compose difference -composite -colorspace Gray \
		-threshold 0 -format '%@' info:
}

# box_h BOX : the height of a WxH+X+Y box
box_h() { printf '%s\n' "$1" | sed -E 's/^[0-9]+x([0-9]+).*/\1/'; }

# The screen shapes the line must survive: every screen from 5:4 to 16:9.
CROP_RATIOS='5:4 4:3 16:9'

# inside_crops W H BOX : true if BOX lies inside the central crop of a W x H
# image to every shape in CROP_RATIOS (scaled to fill, centred). Prints the
# failing crop.
inside_crops() {
	awk -v W="$1" -v H="$2" -v box="$3" -v ratios="$CROP_RATIOS" 'BEGIN {
		if (split(box, a, /[x+]/) != 4) { print "no box"; exit 1 }
		bw = a[1]; bh = a[2]; bx = a[3]; by = a[4]
		if (bw <= 1 || bh <= 1) { print "no stamp found"; exit 1 }
		n = split(ratios, r, " ")
		for (i = 1; i <= n; i++) {
			split(r[i], q, ":")
			if (W * q[2] > H * q[1]) {
				cw = int(H * q[1] / q[2]); ch = H
				x0 = int((W - cw + 1) / 2); y0 = 0
				right = W - x0; bottom = H
			} else {
				cw = W; ch = int(W * q[2] / q[1])
				x0 = 0; y0 = int((H - ch + 1) / 2)
				right = W; bottom = H - y0
			}
			if (bx < x0 || by < y0 || bx + bw > right || by + bh > bottom) {
				printf "%s crop %dx%d+%d+%d\n", r[i], cw, ch, x0, y0; exit 1
			}
		}
	}'
}

# safe_rect W H : the safe area of a W x H image, computed here from the
# crop geometry alone: the part of the image every screen of 5:4, 4:3 or
# 16:9 shows, that is the intersection of the centred crops. The origin
# rounds up, exactly as scripts/identity-stamp.sh does it.
safe_rect() {
	awk -v W="$1" -v H="$2" -v ratios="$CROP_RATIOS" 'BEGIN {
		sx = 0; sy = 0; sr = W; sb = H
		n = split(ratios, r, " ")
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

ID="$TMPD/identity"
sh "$ROOT/scripts/identity-file.sh" --product ExampleBSD --version 2026.11 --base 'FreeBSD 16.0' \
	--variant Default --arch amd64 > "$ID"
IDLONG="$TMPD/identity-long"
sh "$ROOT/scripts/identity-file.sh" --product ExampleBSD --version 2026.11 --base 'FreeBSD 16.0-CURRENT' \
	--variant Cyberpunk --arch aarch64 --build 2026-11-01 > "$IDLONG"

# ------------------------------------------- 1. every background render.sh stamps
STAMPED="lightdm/greeter-1920x1080.png dm/slim/$LOWER/background.png"
for n in 1 2 3; do
	STAMPED="$STAMPED wallpapers/wallpaper-$n-1920x1080.png wallpapers/wallpaper-$n-3840x2160.png"
done
for v in default cyberpunk; do
	P="$TMPD/plain-$v" S="$TMPD/stamped-$v"
	if ! sh "$ROOT/scripts/render.sh" --variant "$v" "$ROOT/palette.env" "$P" > "$TMPD/r.log" 2>&1 ||
		! sh "$ROOT/scripts/render.sh" --variant "$v" --identity "$IDLONG" "$ROOT/palette.env" "$S" > "$TMPD/r.log" 2>&1; then
		fail "render.sh failed for $v"
		sed 's/^/    /' "$TMPD/r.log" >&2
		continue
	fi
	for f in $STAMPED; do
		set -- $("$IM" "$P/$f" -format '%w %h' info:)
		B=$(stamp_box "$P/$f" "$S/$f")
		if why=$(inside_crops "$1" "$2" "$B"); then
			ok "$v $f: stamp $B inside the 5:4, 4:3 and 16:9 crops"
		else
			fail "$v $f: stamp $B outside the $why"
		fi
	done
done

# ------------------------------------------------ 2. other background shapes
# 1601x900 and 1601x901 leave an odd pixel over when the 16:9 crop is
# centred: the origin rounds up, as scripts/identity-stamp.sh does it.
for sz in 1920x1080 1366x768 1920x1200 2560x1080 1280x1024 1024x768 800x600 1601x900 1601x901; do
	"$IM" -size "$sz" xc:'#14182B' "$TMPD/bg.png"
	for id in "$ID" "$IDLONG"; do
		if ! sh "$ROOT/scripts/identity-stamp.sh" --bottom 30 "$id" "$TMPD/bg.png" "$TMPD/bg-s.png" > "$TMPD/s.out" 2> "$TMPD/s.err"; then
			fail "stamp failed at $sz: $(cat "$TMPD/s.err")"
			continue
		fi
		B=$(stamp_box "$TMPD/bg.png" "$TMPD/bg-s.png")
		if why=$(inside_crops "${sz%%x*}" "${sz##*x}" "$B"); then
			ok "$sz $(basename "$id"): stamp $B inside the 5:4, 4:3 and 16:9 crops"
		else
			fail "$sz $(basename "$id"): stamp $B outside the $why"
		fi
		# The box the script reports covers what it drew.
		R=$(sed -n 's/.*bbox=\([^ ]*\).*/\1/p' "$TMPD/s.out")
		if awk -v r="$R" -v b="$B" 'BEGIN { split(r, p, /[x+]/); split(b, q, /[x+]/)
			exit !(q[3] >= p[3] && q[4] >= p[4] && q[3] + q[1] <= p[3] + p[1] && q[4] + q[2] <= p[4] + p[2]) }'; then
			ok "$sz $(basename "$id"): reported bbox $R covers the stamp"
		else
			fail "$sz $(basename "$id"): reported bbox $R does not cover the stamp $B"
		fi
		# The safe area the script reports is the rectangle this test
		# computes from the crop geometry, not a number to trust.
		SAFE=$(sed -n 's/.*safe=\([^ ]*\).*/\1/p' "$TMPD/s.out")
		WANT=$(safe_rect "${sz%%x*}" "${sz##*x}")
		if [ -n "$SAFE" ] && [ "$SAFE" = "$WANT" ]; then
			ok "$sz $(basename "$id"): reported safe area $SAFE is the crop rectangle"
		else
			fail "$sz $(basename "$id"): reported safe area ${SAFE:-none}, want $WANT"
		fi
	done
done

# ------------------------------------------- 3. a 4:3 source, named as one
# A 4:3 background shown on a 16:9 screen loses its top and its bottom.
# The line must stay in the band the 16:9 screen shows, so it is worth
# naming that case on its own and not only inside the loop above.
FOURTHREE=1024x768
"$IM" -size "$FOURTHREE" xc:'#14182B' "$TMPD/fourthree.png"
if sh "$ROOT/scripts/identity-stamp.sh" --bottom 30 "$ID" "$TMPD/fourthree.png" \
	"$TMPD/fourthree-s.png" > "$TMPD/s.out" 2> "$TMPD/s.err"; then
	B=$(stamp_box "$TMPD/fourthree.png" "$TMPD/fourthree-s.png")
	if why=$(inside_crops 1024 768 "$B"); then
		ok "$FOURTHREE source: stamp $B inside the 5:4, 4:3 and 16:9 crops"
	else
		fail "$FOURTHREE source: stamp $B outside the $why"
	fi
	SAFE=$(sed -n 's/.*safe=\([^ ]*\).*/\1/p' "$TMPD/s.out")
	WANT=$(safe_rect 1024 768)
	if [ -n "$SAFE" ] && [ "$SAFE" = "$WANT" ]; then
		ok "$FOURTHREE source: safe area $SAFE is the crop rectangle"
	else
		fail "$FOURTHREE source: safe area ${SAFE:-none}, want $WANT"
	fi
	# The safe area of a 4:3 source is the band a 16:9 screen shows: it
	# must be shorter than the image, or a 16:9 screen would crop the line.
	if [ "$(box_h "$SAFE")" -lt 768 ]; then
		ok "$FOURTHREE source: the safe area is the band a 16:9 screen shows"
	else
		fail "$FOURTHREE source: the safe area is the whole image ($SAFE)"
	fi
else
	fail "stamp failed at $FOURTHREE: $(cat "$TMPD/s.err")"
fi

printf 'test-crop.sh: %s passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
