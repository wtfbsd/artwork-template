# ExampleBSD — BSD Artwork & Branding Template

A generic, rebrandable **artwork and branding pack** for the
[wtfbsd](https://github.com/wtfbsd) family of BSD desktop templates
(FreeBSD, NetBSD, OpenBSD, DragonFly, illumos). It produces a coherent set
of logos, splash screens, installers themes, a LightDM greeter, wallpapers,
icon set, and X11/Xfce/LightDM configuration that can be rebranded and
installed on any of those systems.

The desktop target is **X11 + Xfce + LightDM**.

This pack ships with the placeholder distributor name **ExampleBSD**. The
mark, name, and colors are everything you need to change: nothing is baked
into the SVG sources.

## Quick start

```sh
# 1. Render the assets into out/
sh scripts/render.sh

# 2. Rebrand
sh scripts/rebrand.sh "My OS"
sh scripts/rebrand.sh "My OS" 4488CC 26B67C

# 3. Validate (renders into a temp dir, checks every PNG + rebrand behavior)
sh tests/test-render.sh
```

## What's included

```
.
├── LICENSE                       BSD-2-Clause
├── palette.env                   the single source of branding (see below)
├── README.md
├── .gitignore                    ignores out/
├── scripts/
│   ├── render.sh                 substitute tokens, render the whole asset tree
│   └── rebrand.sh                rewrite palette.env, then run render.sh
├── src/                          hand-written SVG "templates"
│   ├── logo.svg                  512x512 mark only (E built from 3 bars)
│   ├── wordmark.svg              1200x300 mark + name (light bg)
│   ├── wordmark-light.svg        1200x300 mark + name (dark bg)
│   ├── splash-640x480.svg        boot splash, small
│   ├── splash-1024x768.svg       boot splash, common
│   ├── splash-1920x1080.svg      boot splash, full-HD
│   ├── loader-logo.svg           FreeBSD-style loader mark+name, 480x200
│   ├── installer-header.svg      800x96 installer banner
│   ├── installer-sidebar.svg     200x600 installer side panel
│   ├── greeter.svg               1920x1080 LightDM background
│   ├── wallpaper-1.svg           gradient + large soft mark
│   ├── wallpaper-2.svg           geometric diagonal bands
│   ├── wallpaper-3.svg           minimal dark + small wordmark (BR)
│   ├── favicon.svg               64x64 simplified mark
│   └── icons/
│       ├── distributor-logo.svg
│       ├── system-installer.svg
│       └── panel-menu.svg
├── xfce/                         config templates (tokens)
│   ├── gtk-colors.css
│   ├── xfwm4-themerc
│   └── xfconf/
│       ├── xfce4-desktop.xml      wallpaper seed
│       ├── xfce4-panel.xml        single bottom panel
│       └── xsettings.xml          icon theme + font
├── lightdm/
│   └── lightdm-gtk-greeter.conf  greeter background + defaults
├── xinit/
│   └── xinitrc.example           exec startxfce4 (X11 only)
└── tests/
    └── test-render.sh            unit-style checks on a fresh render
```

### `palette.env`

A POSIX shell `KEY=VALUE` file — the one place branding lives. **No `#`
characters are allowed in values** (so the file can be `.`-sourced safely).
Hex colors are stored **without the leading `#`**.

```sh
NAME=ExampleBSD
NAME_LOWER=examplebsd
TAGLINE=Your BSD, your way
PRIMARY=2F6FDE
ACCENT=21B8A6
DARK=14182B
DARK2=1E2440
LIGHT=F4F6FB
MUTED=8A93B2
```

Changing `NAME`, `PRIMARY`, and `ACCENT` is enough to turn this into a new
distribution's visual identity — then re-run `render.sh`.

### `src/` templates

Every source file uses **token substitution** rather than hardcoded values.
The tokens are replaced by `render.sh` before rendering. Nothing in `src/`
may reference the distributor name or its colors directly — always go
through a token.

| Token        | Meaning                                  |
|--------------|------------------------------------------|
| `@NAME@`     | Distributor/mark name (verbatim)         |
| `@NAME_LOWER@` | Lowercase name, e.g. for icon filenames|
| `@TAGLINE@`  | Slogan                                   |
| `@PRIMARY@`  | Primary color, written as `fill="#@PRIMARY@"` |
| `@ACCENT@`   | Accent color                             |
| `@DARK@`     | Darkest background                      |
| `@DARK2@`    | Secondary background                    |
| `@LIGHT@`    | Light text/fill on dark                 |
| `@MUTED@`    | Muted text                              |

## Rebranding

Two equivalent ways, or both in sequence:

1. **Edit `palette.env`** by hand (name, tagline, colors), then
   `sh scripts/render.sh`.
2. **Run `sh scripts/rebrand.sh NewName [PRIMARY ACCENT]`**. This rewrites
   `palette.env` (validating the name and any colors), lowercases it into
   `NAME_LOWER`, and immediately re-renders. It never touches `src/`.

After rebranding, inspect `out/`; everything reflects the new branding.

## Output layout & per-OS install paths

`render.sh` writes everything under `out/`. All shared assets live under a
single distributor prefix. Install paths differ per BSD family — see the
per-OS notes below.

```
out/
├── logo/        logo-{64,128,256,512}.png, wordmark.png, wordmark-light.png
├── splash/      splash-640x480.png, splash-1024x768.png, splash-1920x1080.png
├── loader/      loader-logo.png (480x200), splash.png (1024x768)
├── installer/   header.png, sidebar.png
├── lightdm/     greeter-1920x1080.png
├── wallpapers/  wallpaper-N-1920x1080.png, wallpaper-N-3840x2160.png (N=1..3)
├── icons/       hicolor/{sizes}/apps/{name}-logo|installer|menu.png
│                + scalable/apps/*.svg
└── favicon/     favicon-{16,32,48,180,192,512}.png, favicon.svg, favicon.ico
```

The `xfce/`, `lightdm/`, and `xinit/` **config templates** are rendered into
the matching `out/` subdirectories with tokens substituted.

### Distribution prefixes

- **FreeBSD, NetBSD, OpenBSD, DragonFly, illumos** — install artwork under
  `/usr/local/share/@NAME_LOWER@/` by default.
- **NetBSD**: the system-wide prefix is `/usr/pkg`; use
  `/usr/pkg/share/@NAME_LOWER@/` instead.
- **illumos**: the system-wide prefix is `/usr`; use
  `/usr/share/@NAME_LOWER@/` instead.

### Boot splash / loader

- **FreeBSD**: `out/loader/loader-logo.png` (480×200) and
  `out/loader/splash.png` (1024×768, flattened to 8-bit RGB without an
  alpha channel when ImageMagick is available) belong under `/boot/images/`
  together with `loader.conf` wiring — see `loader.conf(5)` for the
  `loader_logo` / splash variables and `splash(4)` for the splash support
  your loader has (PNG support depends on the loader in use; older boot
  setups want 8-bit-friendly images, hence the flattening step).
- **NetBSD / OpenBSD / DragonFly / illumos**: these use a plain PNG splash
  in the installer or greeter rather than a boot-loader logo; no
  loader-specific plumbing is provided.

### LightDM / Xfce / Xinit

- Install `lightdm/greeter-*.png` and
  `/usr/local/share/@NAME_LOWER@/lightdm/lightdm-gtk-greeter.conf`
  (BSD prefixes may differ — see README).
- Seed `xfce/xfconf/*.xml` into
  `~/.config/xfce4/xfconf/xfce4-perchannel-xml/`; copy `gtk-colors.css` and
  `xfwm4-themerc` into the GTK theme, and use `xfce/gtk-colors.css` via
  `@import` in `~/.config/gtk-3.0/gtk.css`.
- `xinit/xinitrc.example` is just `exec startxfce4` — place it at `~/.xinitrc`
  and run `startx`.

## Requirements

- **rsvg-convert** (librsvg2 / `graphics/librsvg2`) — required. It is the
  default SVG→PNG renderer. If absent, **inkscape** is used as a fallback.
- **ImageMagick** (`convert`/`magick`) — optional. Used to flatten the
  loader splash to 8-bit RGB (no alpha) and to build `favicon.ico`. Without
  it the loader splash keeps its alpha channel and `favicon.ico` is skipped.
- **icotools / `icotool`** — optional. Preferred for building
  `favicon.ico`; falls back to ImageMagick.
- **python3** — required by `tests/test-render.sh` to read PNG dimensions
  from the IHDR chunk.
- **DejaVu Sans** — the only font referenced inside the SVGs, via
  `font-family="DejaVu Sans, sans-serif"`.

## Style & compliance rules

- **Fonts:** SVGs use only `DejaVu Sans, sans-serif`.
- **No raster embedding / no external hrefs:** all art is hand-written
  vector; nothing is imported.
- **No official marks:** this mark is an abstract geometric "E" (three
  horizontal bars inside a rounded square). It **must not** resemble any
  official BSD logo or mascot — no daemon, horns, pitchfork, red sphere with
  horns, flag, pufferfish, dragonfly/insect, or illumos sun/flame. Keep it
  abstract and neutral.
- **X11 only:** the panel/greeter/wallpaper configs target X11 (Xfce +
  LightDM); there is no Wayland session here.

## Tests

```sh
sh tests/test-render.sh
```

`tests/test-render.sh` renders into a temporary directory and asserts:

- every listed PNG exists **and** has the exact pixel dimensions declared in
  the spec (read back from the PNG IHDR via `python3`);
- no `@TOKEN@` markers remain in any `out/` text config or scalable SVG;
- `scripts/rebrand.sh` applied to a **copy** of the repo correctly renames
  everything under `out/` (name in configs, icon filenames, lowercased
  `NAME_LOWER`) — without touching the original.

## License

BSD-2-Clause. See [LICENSE](LICENSE).