# Branding spots

Every place a product built from this pack shows its own branding instead of
the operating system's: what the spot is, where it appears, the path in the
installed system on each OS, the size and format, and the file in this
repository it comes from.

**Machine-readable list:** [`branding/spots.tsv`](branding/spots.tsv), tab
separated, one header line. OS templates read it **by column name**:

| Column | Meaning |
|---|---|
| `spot` | unique id of the spot |
| `what` | what it is |
| `shows` | where a person sees it |
| `freebsd` `netbsd` `openbsd` `dragonfly` `illumos` | install path on that OS, or `n/a: <reason>`, `check: <what>`, `same as <os>`, `via <spot>` |
| `size_format` | pixel size and file format |
| `source` | comma-separated files in this repository |
| `rendered` | comma-separated paths under `out/` after `render.sh` (`-` if none) |
| `notes` | anything else (`-` if none) |

In paths, `<slug>` is `NAME_LOWER` from `palette.env` (`examplebsd`) and
`<Name>` is `NAME`; templates substitute them.

How to read the OS columns:

- a path: the OS supports the spot and the template installs it there;
- `n/a: <reason>`: the OS has no such spot;
- `check: <what>`: not yet confirmed for that OS;
- `same as freebsd`, `via <spot>`: see the named cell or spot.

Artwork is installed under `/usr/local/share/<slug>/` on every OS
(`render.sh --share-dir` changes it).

| Spot | What | FreeBSD | NetBSD | OpenBSD | DragonFly | illumos | Size / format | Source |
|---|---|---|---|---|---|---|---|---|
| `loader-brand` | Boot menu brand (the name above the menu). *FreeBSD 14+ gfx-&lt;name&gt;.lua format; brand-&lt;name&gt;.lua is a legacy fallback.* | /boot/lua/gfx-&lt;slug&gt;.lua + /boot/images/&lt;slug&gt;-brand.png; loader_brand="&lt;slug&gt;" | n/a: boot.cfg has no image keyword; see netbsd-boot-banner | n/a: boot(8) has no logo, banner or splash facility | n/a: dloader has no brand file; see loader-menu-title | /boot/forth/brand-&lt;slug&gt;.4th + /boot/&lt;slug&gt;-brand.png; loader_brand="&lt;slug&gt;" | PNG 400x100, 8-bit RGBA, drawn 7 text rows high; ASCII rows on a text console | `src/loader-brand.svg`<br>`boot/freebsd/gfx-@NAME_LOWER@.lua`<br>`boot/illumos/brand-@NAME_LOWER@.4th`<br>`boot/freebsd/loader.conf.fragment`<br>`boot/illumos/loader.conf.fragment` |
| `loader-logo` | Boot menu logo (beside the menu). *The illumos stock logo PNG is 236x126; check the aspect on an illumos framebuffer.* | /boot/lua/gfx-&lt;slug&gt;.lua + /boot/images/&lt;slug&gt;-logo.png; loader_logo="&lt;slug&gt;" | n/a: boot.cfg has no image keyword | n/a: boot(8) has no logo facility | n/a: the ASCII mascot is compiled into dloader; fred_disable="YES" hides it | /boot/forth/logo-&lt;slug&gt;.4th + /boot/&lt;slug&gt;-logo.png; loader_logo="&lt;slug&gt;" | PNG 240x200, 8-bit RGBA, drawn 15 text rows high; ASCII rows on a text console | `src/loader-mark.svg`<br>`boot/freebsd/gfx-@NAME_LOWER@.lua`<br>`boot/illumos/logo-@NAME_LOWER@.4th` |
| `loader-menu-title` | Boot menu title and entries. *DragonFly: copy /boot/defaults/dloader.menu and change only the titles.* | /boot/loader.conf: loader_menu_title="Welcome to &lt;Name&gt;" | same as netbsd-boot-banner | n/a: no boot menu | /boot/dloader.menu: menuitem titles | check: whether the Forth menu reads a title variable | text | `boot/freebsd/loader.conf.fragment`<br>`boot/dragonfly/dloader.menu` |
| `netbsd-boot-banner` | Boot banner lines and menu entries. *Replaces the stock welcome text.* | n/a: see loader-menu-title | /boot.cfg: banner= (up to 12 lines) and menu= | n/a: no boot menu | n/a: see loader-menu-title | n/a: see loader-menu-title | plain text, no escape sequences | `boot/netbsd/boot.cfg` |
| `boot-splash` | Splash while the kernel boots. *`boot_mute` hides kernel messages; splash/ sizes are for live media and installers.* | /boot/images/&lt;slug&gt;-splash.png; splash= and boot_mute="YES" in /boot/loader.conf | n/a: needs a kernel with options SPLASHSCREEN (not in GENERIC); boot(8) has a splash command for such kernels | n/a: no splash support | n/a: no loader splash | check: no splash variable found in loader.conf(5) | PNG 1024x768, 8-bit RGBA, not interlaced (vt(4) draws only RGBA) | `src/splash-1024x768.svg`<br>`src/splash-640x480.svg`<br>`src/splash-1920x1080.svg`<br>`boot/freebsd/loader.conf.fragment` |
| `motd` | Message of the day. *Starts with a blank line so the system line stays separate.* | /etc/motd.template (rc.d/motd adds the kernel line) | /etc/motd (rc.d/motd rewrites line 1 only) | /etc/motd (rc rewrites line 1; text after the first blank line is kept) | /etc/motd (line 1 is updated only if it starts with DragonFly) | /etc/motd | text | `console/motd.template` |
| `login-issue` | Console login banner | /etc/gettytab: im= of the default entry (also /etc/issue via if=) | /etc/gettytab: im= of the default entry | /etc/gettytab: im= of the default entry (no /etc/issue support) | /etc/gettytab: im= of the default entry (also /etc/issue via if=) | /etc/issue (printed by login before the prompt) | text; gettytab escapes %h host, %t terminal | `console/gettytab.fragment`<br>`console/issue` |
| `lightdm-background` | LightDM greeter background, identity line lower left. *The greeter cannot place free text, so the identity line is stamped on.* | /usr/local/share/&lt;slug&gt;/lightdm/greeter-1920x1080.png | n/a: this OS template uses another display manager (slim) | n/a: this OS template uses another display manager (xenodm) | same as freebsd | check: display manager not chosen for the illumos template yet (OpenIndiana ships LightDM) | PNG 1920x1080 | `src/greeter.svg` |
| `lightdm-theme` | LightDM greeter settings, colours, font, user image. *Check: the #login_window and #panel_window selectors against the installed greeter version.* | /usr/local/etc/lightdm/lightdm-gtk-greeter.conf + /usr/local/share/themes/&lt;slug&gt;-greeter/gtk-3.0/gtk.css | n/a: this OS template uses another display manager (slim) | n/a: this OS template uses another display manager (xenodm) | same as freebsd | check: display manager not chosen for the illumos template yet | INI + GTK 3 CSS | `lightdm/lightdm-gtk-greeter.conf`<br>`lightdm/greeter-gtk.css` |
| `xenodm-logo` | Logo in the xenodm login box (replaces Puffy). *Named by xlogin*logoFileName in xenodm-colours.* | n/a: xenodm is OpenBSD only | n/a: xenodm is OpenBSD only | /etc/X11/xenodm/pixmaps/&lt;slug&gt;-color.xpm, &lt;slug&gt;-8bpp.xpm, &lt;slug&gt;-1bpp.xpm | n/a: xenodm is OpenBSD only | n/a: xenodm is OpenBSD only | XPM 112x112: 64, 16 and 2 colours by display depth (stock logos are 240x175) | `src/logo.svg` |
| `xenodm-colours` | xenodm login box colours, fonts, greeting (identity line). *Render.sh adds #undef lines so no word of the greeting is taken for a cpp macro.* | n/a: xenodm is OpenBSD only | n/a: xenodm is OpenBSD only | /etc/X11/xenodm/Xresources | n/a: xenodm is OpenBSD only | n/a: xenodm is OpenBSD only | X resources, run through cpp by xrdb | `dm/xenodm/Xresources` |
| `xenodm-background` | Root window behind the xenodm login box. *Paints the PNG with xwallpaper or feh when installed, else a flat palette colour (stock paints a grey weave).* | n/a: xenodm is OpenBSD only | n/a: xenodm is OpenBSD only | /etc/X11/xenodm/Xsetup_0 (+ the greeter PNG under /usr/local/share/&lt;slug&gt;/lightdm/) | n/a: xenodm is OpenBSD only | n/a: xenodm is OpenBSD only | sh script; PNG 1920x1080 | `dm/xenodm/Xsetup_0`<br>`src/greeter.svg` |
| `slim-theme` | SLiM theme: background, panel, colours, identity line. *Welcome text is placed relative to the panel; the lower-left copy is on the background.* | n/a: this OS template uses another display manager (LightDM) | /usr/pkg/share/slim/themes/&lt;slug&gt;/ + current_theme in /usr/pkg/etc/slim.conf | n/a: this OS template uses another display manager (xenodm) | n/a: this OS template uses another display manager (LightDM) | check: display manager not chosen for the illumos template yet | slim.theme; background PNG 1920x1080 (stretched); panel PNG 600x280 | `dm/slim/@NAME_LOWER@/slim.theme`<br>`dm/slim/slim.conf.fragment`<br>`src/greeter.svg`<br>`src/slim-panel.svg` |
| `xdm-logo` | Logo in the plain xdm login box. *Shown only when xdm is built with XPM support; NetBSD stock is NetBSD.xpm.* | /usr/local/share/&lt;slug&gt;/dm/pixmaps/&lt;slug&gt;-color.xpm (and -8bpp, -1bpp) | /usr/local/share/&lt;slug&gt;/dm/pixmaps/&lt;slug&gt;-color.xpm (and -8bpp, -1bpp) | n/a: OpenBSD ships xenodm; see xenodm-logo | /usr/local/share/&lt;slug&gt;/dm/pixmaps/&lt;slug&gt;-color.xpm (and -8bpp, -1bpp) | check: whether the illumos template ships xdm | XPM 112x112: 64, 16 and 2 colours | `src/logo.svg` |
| `xdm-colours` | Plain xdm colours, fonts, greeting (identity line), root window | /usr/local/etc/X11/xdm/Xresources + Xsetup_0 (x11/xdm) | /etc/X11/xdm/Xresources + Xsetup_0 (base X) | n/a: OpenBSD ships xenodm; see xenodm-colours | /usr/local/etc/X11/xdm/Xresources + Xsetup_0 (x11/xdm) | check: whether the illumos template ships xdm | X resources, run through cpp by xrdb; sh script | `dm/xdm/Xresources`<br>`dm/xdm/Xsetup_0` |
| `installer-header` | Installer header banner. *Read by the product's graphical installer.* | /usr/local/share/&lt;slug&gt;/installer/header.png | same as freebsd | same as freebsd | same as freebsd | same as freebsd | PNG 800x96 | `src/installer-header.svg` |
| `installer-sidebar` | Installer side panel. *Read by the product's graphical installer.* | /usr/local/share/&lt;slug&gt;/installer/sidebar.png | same as freebsd | same as freebsd | same as freebsd | same as freebsd | PNG 200x600 | `src/installer-sidebar.svg` |
| `installer-palette` | Installer colours and font. *The installer imports the same colours as the desktop.* | /usr/local/share/&lt;slug&gt;/xfce/gtk-colors.css | same as freebsd | same as freebsd | same as freebsd | same as freebsd | GTK 3 CSS colours | `palette.env`<br>`xfce/gtk-colors.css` |
| `installer-slides` | Slides shown while files are copied. *Add src/installer-slide-N.svg once the installer defines the slide size.* | check: depends on the installer template | check: depends on the installer template | check: depends on the installer template | check: depends on the installer template | check: depends on the installer template | not defined yet | n/a: no slides in this pack yet |
| `installer-name` | Installer title text | /usr/sbin/bsdinstall run with OSNAME=&lt;Name&gt; in the environment (sets the backtitle and boot label) | check: sysinst title | check: install.sh title | check: installer title | check: installer title | text | `palette.env` |
| `wallpapers` | Desktop wallpapers, identity line lower left above the panel. *The stamp keeps the 30 px bottom panel clear.* | /usr/local/share/&lt;slug&gt;/wallpapers/ | same as freebsd | same as freebsd | same as freebsd | same as freebsd | PNG 1920x1080 and 3840x2160 | `src/wallpaper-1.svg`<br>`src/wallpaper-2.svg`<br>`src/wallpaper-3.svg`<br>`xfce/xfconf/xfce4-desktop.xml` |
| `icon-distributor` | Distributor logo icon (About dialogs, user image fallback). *Xfce4-about shows LOGO= from /etc/os-release, else &lt;ID&gt;-logo: set LOGO=&lt;slug&gt;-logo.* | /usr/local/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-logo.png | /usr/pkg/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-logo.png | /usr/local/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-logo.png | /usr/local/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-logo.png | check: icon theme prefix of the illumos desktop | PNG 16 to 256 px + scalable SVG | `src/icons/distributor-logo.svg` |
| `icon-menu` | Panel menu button icon | /usr/local/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-menu.png | /usr/pkg/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-menu.png | /usr/local/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-menu.png | /usr/local/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-menu.png | check: icon theme prefix of the illumos desktop | PNG 16 to 256 px + scalable SVG | `src/icons/panel-menu.svg` |
| `icon-installer` | Installer launcher icon | /usr/local/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-installer.png | /usr/pkg/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-installer.png | /usr/local/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-installer.png | /usr/local/share/icons/hicolor/&lt;size&gt;/apps/&lt;slug&gt;-installer.png | check: icon theme prefix of the illumos desktop | PNG 16 to 256 px + scalable SVG | `src/icons/system-installer.svg` |
| `xfce-theme` | Xfce window titles, colours, panel, font. *Check: system-wide xfconf defaults path against the installed Xfce.* | /usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/ + /usr/local/share/themes/&lt;Name&gt;/xfwm4/themerc | /usr/pkg/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/ + /usr/pkg/share/themes/&lt;Name&gt;/xfwm4/themerc | /usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/ + /usr/local/share/themes/&lt;Name&gt;/xfwm4/themerc | /usr/local/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/ + /usr/local/share/themes/&lt;Name&gt;/xfwm4/themerc | check: Xfce prefix of the illumos desktop | xfconf XML, xfwm4 themerc, GTK 3 CSS | `xfce/xfconf/xfce4-panel.xml`<br>`xfce/xfconf/xfce4-desktop.xml`<br>`xfce/xfconf/xsettings.xml`<br>`xfce/xfwm4-themerc`<br>`xfce/gtk-colors.css` |
| `favicon` | Web site icon | n/a: web asset, not installed in the OS | n/a: web asset, not installed in the OS | n/a: web asset, not installed in the OS | n/a: web asset, not installed in the OS | n/a: web asset, not installed in the OS | PNG 16 to 512 px, SVG, ICO | `src/favicon.svg` |
| `identity-file` | Generated identity of the image (product, version, base, variant, arch, build). *Written by the product build; never hand-edited.* | /usr/local/share/&lt;slug&gt;/identity | same as freebsd | same as freebsd | same as freebsd | same as freebsd | KEY=value: PRODUCT VERSION BASE VARIANT ARCH BUILD | `scripts/identity-file.sh`<br>`scripts/lib-identity.sh` |
| `identity-line` | Identity line, lower left: &lt;Product&gt; &lt;version&gt; · &lt;base&gt; · &lt;variant&gt; · &lt;arch&gt;. *Render.sh --identity stamps every background and writes the line into xdm, xenodm and slim.* | via lightdm-background and wallpapers (stamped) | via slim-theme (stamped background + welcome text) and wallpapers | via xenodm-colours (greeting), xenodm-background (stamped) and wallpapers | via lightdm-background and wallpapers (stamped) | check: follows the illumos display manager | one line of text, 1/60 of the screen height, contrast 4.5:1 or better | `scripts/identity-stamp.sh`<br>`scripts/lib-identity.sh`<br>`scripts/render.sh` |

## Display managers

| Display manager | Used by | Logo | Colours and font | Background | Identity line, live |
|---|---|---|---|---|---|
| LightDM GTK greeter | FreeBSD, DragonFly | user image falls back to the `<slug>-logo` icon | `<slug>-greeter` GTK theme + `font-name` | `background=` PNG | none: the greeter cannot place free text, so it is stamped on the background |
| xenodm | OpenBSD | `xlogin*logoFileName`, XPM by display depth | `xlogin*` colours and Xft faces | `Xsetup_0` paints the stamped PNG (xwallpaper or feh), else a palette colour | `xlogin*greeting` |
| SLiM | NetBSD | drawn on `panel.png` | `slim.theme` colours and fonts | `background.png`, stamped | `welcome_msg`, on the panel |
| plain xdm | where a template uses it | `xlogin*logoFileName` (needs xdm built with XPM) | `xlogin*` colours and Xft faces | `Xsetup_0`, as for xenodm | `xlogin*greeting` |

No display manager configuration in this pack names an OS logo: the xdm and
xenodm files point at the product's XPMs, never at `OpenBSD_*.xpm` or
`NetBSD.xpm`. `tests/test-branding.sh` checks this.

## Identity line

A small line in the lower-left corner of the installer, the greeter and the
desktop, so every screenshot says what it shows:

```
<Product> <version> · <base OS and version> · <variant> · <arch>[ · build <date>]
ExampleBSD 1.0 · FreeBSD 16.0-CURRENT · Cyberpunk · amd64
ExampleBSD 1.0 · OpenBSD 8.0 · Default · amd64 · build 2026-11-01
```

The build date appears on test builds only.

**Source of truth.** The product build writes `/usr/local/share/<slug>/identity`
from the built system; nothing is typed by hand:

```sh
sh scripts/identity-file.sh --product ExampleBSD --version 1.0 \
    --base "FreeBSD 16.0-CURRENT" --variant Cyberpunk --arch amd64 \
    --build today > identity
```

```
PRODUCT=ExampleBSD
VERSION=1.0
BASE=FreeBSD 16.0-CURRENT
VARIANT=Cyberpunk
ARCH=amd64
BUILD=2026-11-01
```

`BASE` is the base system's name and release (`FreeBSD 16.0-CURRENT`,
`NetBSD 11.0`, `OpenBSD 8.0`, `DragonFly 6.4.2`, `illumos r151054`);
`--base auto` takes `uname -sr` when run inside the built system. Values may
use letters, digits, space and `. _ : + ( ) / -` only; anything else is
refused. The file is read, never sourced.

**Layout.** Lower left. Text height is 1/60 of the image height (18 px at
1080p, 13 px at 768, at least 11 px); the margin is 1/45 of the height. If
the line is wider than the image it shrinks, down to 11 px; the longest
line (`FreeBSD 16.0-CURRENT`, a build date and a long arch) fits on one line
at 1024 px wide. On wallpapers it sits above the 30 px bottom panel.
Colour is the palette's `IDENTITY_FG` in the palette's `FONT`.

**Contrast.** `scripts/identity-stamp.sh` measures the lightest and darkest
background pixel under the text box and needs 4.5:1 or better against the
nearer one. If the background cannot give that, it draws an opaque plate in
`DARK` behind the text (or uses `LIGHT` text if that is what reaches 4.5:1);
with `--no-plate` it refuses instead. It prints what it did:

```
bbox=644x39+16+1025 fg=00E5F2 plate=0 size=18 contrast=6.91
```

**Where it is drawn.**

- *Stamped* (`render.sh --identity FILE`): the LightDM background, the SLiM
  background and every wallpaper.
- *Live text* (`render.sh --identity FILE` writes it into the config): the
  xenodm and xdm `xlogin*greeting` and the SLiM `welcome_msg`. These use
  ` | ` between fields instead of ` · ` because UTF-8 in those fields is not
  confirmed. `render.sh` puts an `#undef` before the greeting for each of its
  words, because xrdb runs the file through cpp and a word such as `unix` or
  `i386` would otherwise be replaced.
- *Installer*: stamp the installer's backdrop with `identity-stamp.sh`; the
  installer template decides where its backdrop lives.

Without `--identity`, `render.sh` writes `<Name> · <variant>` into the text
configs and stamps nothing; the product build renders again once version,
base and arch are known.

## Variants

`variants/<name>/` holds what a look changes, and nothing else:

- `palette.env`: only the keys that differ from `palette.env`, plus
  `VARIANT_LABEL` (the name shown in the identity line);
- any file at the same path as a base file replaces it (for example
  `variants/cyberpunk/src/greeter.svg`); a file with no base counterpart is
  an error.

Shipped: `default` (the base look) and `cyberpunk` (near-black, neon magenta,
cyan and acid, monospace type, scanlines, a perspective grid, a city skyline
and a glitched wordmark). A product picks one with `ARTWORK_VARIANT` in
product.conf, which `render.sh` and `rebrand.sh` also read from the
environment.

## Not confirmed yet

- illumos: which display manager the illumos template uses; whether the Forth
  menu reads a title variable; the aspect of the logo PNG on a framebuffer;
  the icon and Xfce prefixes.
- LightDM: the `#login_window` / `#panel_window` selectors against the
  installed greeter version.
- xenodm and xdm: whether the greeting renders UTF-8 (hence ` | `).
- Installer title on NetBSD, OpenBSD, DragonFly and illumos; installer slides.

## Sources checked

- FreeBSD: drawer.lua(8), gfx.lua(8), loader.conf(5), splash(4), vt(4),
  motd(5), gettytab(5); `stand/lua/drawer.lua`, `stand/lua/gfx-orb.lua`,
  `stand/images/`, `stand/common/gfx_fb.c`, `libexec/rc/rc.d/motd`,
  `libexec/rc/rc.d/os-release`, `usr.sbin/bsdinstall/scripts/auto`,
  `usr.sbin/bsdconfig/share/common.subr`; ports `x11/xdm`,
  `x11/lightdm-gtk-greeter` pkg-plist.
- NetBSD: boot.cfg(5), x86 boot(8); `sys/lib/libsa/bootcfg.c`,
  `etc/rc.d/motd`, `etc/gettytab`, `external/mit/xorg/bin/xdm/config`;
  pkgsrc `x11/slim` (PLIST, Makefile) and slim 1.4.0 `cfg.cpp`, `panel.cpp`.
- OpenBSD: boot(8), boot.conf(8), xenodm(1), gettytab(5); `etc/rc`,
  xenocara `app/xenodm/config/Xresources.in`, `Xsetup_0.in`,
  `Makefile.bsd-wrapper`.
- DragonFly: loader(8), loader.conf(5); `stand/boot/dloader/cmds.c`,
  `dloader.menu`, `etc/rc.d/motd`, `etc/gettytab`; DPorts `x11/xdm`.
- illumos: loader(7), loader.conf(5), login(1), issue(5), ttymon(8);
  illumos-gate `usr/src/boot/forth/` (`brand.4th`, `brand-illumos.4th`,
  `logo-illumos.4th`, `loader.conf`), `usr/src/cmd/login/login.c`;
  oi-userland `components/desktop/lightdm-gtk-greeter`.
- X.Org xdm(1); lightdm-gtk-greeter `src/greeterconfiguration.h`;
  libxfce4ui `xfce4-about`; freedesktop Icon Naming Specification.
