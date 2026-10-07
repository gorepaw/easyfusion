; Entry point. The ROM path is passed in by build.py (-strequ ROM <path>).
.gba
.open ROM, 08000000h

.include "powers.asm"

.close
