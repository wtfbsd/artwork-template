\ @NAME@ logo for the illumos Forth loader.
\ Install as /boot/forth/logo-@NAME_LOWER@.4th and the PNG as
\ /boot/@NAME_LOWER@-logo.png; select with loader_logo="@NAME_LOWER@".

46 logoX ! 4 logoY !

: logo+ ( x y c-addr/u -- x y' )
	2swap 2dup at-xy 2swap
	type
	1+
;

: logo ( x y -- )
	framebuffer? if
		s" term-putimage" sfind if
			>r over 0 swap 12 0 22
			s" /boot/@NAME_LOWER@-logo.png"
			r> execute if 2drop exit then
		else
			drop
		then
	then
	s"   .------------------." logo+
	s"   |                  |" logo+
	s"   |   ============   |" logo+
	s"   |                  |" logo+
	s"   |   ========       |" logo+
	s"   |                  |" logo+
	s"   |   ============   |" logo+
	s"   |                  |" logo+
	s"   '------------------'" logo+
	2drop
;
