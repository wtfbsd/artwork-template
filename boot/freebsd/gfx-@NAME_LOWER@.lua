-- @NAME@ boot menu graphics for the FreeBSD Lua loader.
--
-- Install as /boot/lua/gfx-@NAME_LOWER@.lua, with
--   /boot/images/@NAME_LOWER@-brand.png   (out/loader/@NAME_LOWER@-brand.png)
--   /boot/images/@NAME_LOWER@-logo.png    (out/loader/@NAME_LOWER@-logo.png)
-- and select it in /boot/loader.conf (see loader.conf.fragment):
--   loader_brand="@NAME_LOWER@"
--   loader_logo="@NAME_LOWER@"
-- On a framebuffer console the PNGs are drawn (brand 7 text rows high,
-- logo 15 rows); on a text console the ASCII versions below are used.
-- Replace the ASCII brand with your own lettering if you like.
return {
	brand = {
		ascii = {
			image = {
				"",
				"  @NAME@",
				"  ------------------------",
			},
		},
		fb = {
			image = "/boot/images/@NAME_LOWER@-brand.png",
		},
	},
	logo = {
		ascii = {
			image = {
				"  .------------------.",
				"  |                  |",
				"  |   ============   |",
				"  |                  |",
				"  |   ========       |",
				"  |                  |",
				"  |   ============   |",
				"  |                  |",
				"  '------------------'",
			},
			requires_color = false,
			shift = {x = 3, y = 2},
		},
		fb = {
			image = "/boot/images/@NAME_LOWER@-logo.png",
			width = 15,
			shift = {x = 2, y = -2},
		},
	},
}
