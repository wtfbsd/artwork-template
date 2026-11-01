\ @NAME@ brand for the illumos Forth loader.
\ Install as /boot/forth/brand-@NAME_LOWER@.4th and the PNG as
\ /boot/@NAME_LOWER@-brand.png; select with loader_brand="@NAME_LOWER@".
\ On a framebuffer the PNG is drawn 7 rows high, otherwise the text below.

2 brandX ! 1 brandY !

: brand+ ( x y c-addr/u -- x y' )
	2swap 2dup at-xy 2swap
	type
	1+
;

: brand ( x y -- )
	framebuffer? if
		s" term-putimage" sfind if
			>r 0 0 0 0 7
			s" /boot/@NAME_LOWER@-brand.png"
			r> execute if 2drop exit then
		else
			drop
		then
	then
	s" " brand+
	s"   @NAME@" brand+
	s"   ------------------------" brand+
	2drop
;
