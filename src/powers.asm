; Metroid Fusion (USA) - new powers for Samus
;
;   Select          Phase Shift + Time Stop. Samus drifts through walls (D-pad,
;                   hold R for speed) while enemies, beams and animated tiles
;                   freeze. Press Select again to drop back in; refused with a
;                   buzz if Samus would end up inside a wall.
;   Select + A      Warp to the last save room (the last room where Samus stood
;                   on a save pad, or loaded a file). Works from Phase Shift too.
;   Always on       Regeneration of energy, missiles and power bombs.
;
; Addresses come from the metroidret/mf decompilation and the MARS symbol file.

.gba
.thumb

; ---------------------------------------------------------------- tuning ----

; Regeneration ticks once every (mask + 1) frames; masks must be 2^n - 1.
REGEN_ENERGY_MASK       equ 3       ; +1 energy every 4 frames (15/s)
REGEN_MISSILE_MASK      equ 15      ; +1 missile every 16 frames
REGEN_POWER_BOMB_MASK   equ 63      ; +1 power bomb every 64 frames

SND_PHASE_IN            equ 146h    ; SOUND_FREEZE_SPRITE
SND_PHASE_OUT           equ 0EAh    ; SOUND_ICE_BEAM_CHARGED
SND_DENIED              equ 2C7h    ; SOUND_VOICE_UNAUTHORIZED_ENTRY
SND_WARP                equ 1F6h    ; SOUND_CHARACTER_APPEARING_SAMUS

; ------------------------------------------------------------- constants ----

KEY_A                   equ 1 << 0
KEY_SELECT              equ 1 << 2

SUB_GAME_MODE_PLAYING       equ 2
SUB_GAME_MODE_LOADING_ROOM  equ 3
SUB_GAME_MODE_NO_CLIP       equ 6

SPOSE_USING_ELEVATOR    equ 17h
SPOSE_ON_SAVE_PAD       equ 20h
SPOSE_DELAY_BEFORE_SHINESPARKING equ 23h
SPOSE_UNLOCKING_SECURITY equ 34h
SPOSE_SAVING            equ 35h

DOOR_TYPE_NO_FLAGS      equ 0Fh
DOOR_TYPE_NO_HATCH      equ 2
DOOR_SIZE               equ 0Ch

CLIPDATA_SOLID_BIT      equ 24

; ------------------------------------------------------------------- RAM ----

gDisablePauseFlag       equ 0300002Bh
gCurrentArea            equ 0300002Ch   ; gCurrentRoom is the next byte
gLastDoorUsed           equ 0300002Eh
gCurrentPowerBomb       equ 03000110h
gIsLoadingFile          equ 03000B8Bh
gSubGameMode1           equ 03000BE0h
gButtonInput            equ 030011E8h
gChangedInput           equ 030011ECh
gDemoState              equ 03001242h
gSamusData              equ 03001244h
gEquipment              equ 03001310h
gPreventMovementTimer   equ 03001348h
gDoorPositionStart      equ 03004E0Ch
gSamusDoorPositionOffset equ 03004E38h

SamusData_Pose          equ 01h
SamusData_XPosition     equ 16h
SamusData_YPosition     equ 18h
SamusData_HitboxLeft    equ 24h
SamusData_HitboxTop     equ 26h
SamusData_HitboxRight   equ 28h

Equipment_CurrentEnergy     equ 0
Equipment_MaxEnergy         equ 2
Equipment_CurrentMissiles   equ 4
Equipment_MaxMissiles       equ 6
Equipment_CurrentPowerBombs equ 8
Equipment_MaxPowerBombs     equ 9

; Unused IWRAM after the sound track data (also used as free RAM by MARS).
PowersRam               equ 03005630h
WarpValid               equ PowersRam + 0   ; WARP_VALID_MAGIC when set
WarpArea                equ PowersRam + 1
WarpRoom                equ PowersRam + 2
RegenTimer              equ PowersRam + 4   ; u16
WARP_VALID_MAGIC        equ 0A5h

; ------------------------------------------------------------- functions ----

SoundPlay                       equ 0800270Ch
InitAndLoadGenerics             equ 0800E420h
UpdateFreeMovement_Debug        equ 0800E684h
SpriteUpdate                    equ 0800E7E8h
RoomEffectSetCurrentNavigationRoom equ 080631D0h
RoomUpdateAnimatedGraphicsAndPalette equ 08065B0Ch
InGameTimerUpdate               equ 08068660h
ClipdataProcess                 equ 08068BC0h
ColorEffectCopyPalramToEwramPal2And1 equ 0806CF0Ch
ColorFadingStart                equ 0806E108h
PlayRoomMusicTrack              equ 080715ACh
InitStartingMap                 equ 08074FFCh
UpdateArmCannonAndWeapons       equ 080812F0h

sAreaDoorPointers               equ 0879B894h

; Unused audio sample, reclaimed as free space (same region MARS uses). It is
; within Thumb BL range of all game code, unlike the padding at end of ROM.
FreeSpace                       equ 080F9A28h
FreeSpaceLen                    equ 20318h

; ----------------------------------------------------------------- hooks ----

.org 0800DD84h  ; InGameHandler: InitAndLoadGenerics()
    bl      LoadGenericsHook

.org 0800DE54h  ; InGameHandler, playing: InGameTimerUpdate()
    bl      PlayingHook

.org 0800DEB0h  ; InGameHandler, no-clip: UpdateFreeMovement_Debug()
    bl      NoClipHook

.org 0800DEE6h  ; InGameHandler: RoomUpdateAnimatedGraphicsAndPalette()
    bl      AnimatedGraphicsHook

.org 0800DEEAh  ; InGameHandler: SpriteUpdate()
    bl      SpriteUpdateHook

.org 0800DF10h  ; InGameHandler: UpdateArmCannonAndWeapons()
    bl      WeaponUpdateHook

.org 0800E6A4h  ; UpdateFreeMovement_Debug: skip its own Select/Start handling
    b       0800E6C4h

.org 080804B6h  ; NewGameInit: InitStartingMap()
    bl      NewGameHook

; ------------------------------------------------------------------ code ----

.org FreeSpace
.area FreeSpaceLen

; Runs every frame of normal gameplay, in place of InGameTimerUpdate.
.align 2
.func PlayingHook
    push    { r4, lr }
    bl      InGameTimerUpdate
    ldr     r0, =gSubGameMode1
    ldrh    r0, [r0]
    cmp     r0, SUB_GAME_MODE_PLAYING   ; pause may have been pressed this frame
    bne     @@return
    ldr     r0, =gDemoState
    ldrb    r0, [r0]
    cmp     r0, #0
    bne     @@return
    bl      RecordWarpTarget
    bl      Regenerate
    ldr     r0, =gChangedInput
    ldrh    r0, [r0]
    mov     r1, KEY_SELECT
    tst     r0, r1
    beq     @@return
    bl      PowersAllowed
    cmp     r0, #0
    beq     @@denied
    ldr     r0, =gButtonInput
    ldrh    r0, [r0]
    mov     r1, KEY_A
    tst     r0, r1
    beq     @@phase_in
    bl      TryWarp
    cmp     r0, #0
    bne     @@return
    b       @@denied
@@phase_in:
    ldr     r0, =gSubGameMode1
    mov     r1, SUB_GAME_MODE_NO_CLIP
    strh    r1, [r0]
    ldr     r0, =SND_PHASE_IN
    bl      SoundPlay
    b       @@return
@@denied:
    ldr     r0, =SND_DENIED
    bl      SoundPlay
@@return:
    pop     { r4 }
    pop     { r0 }
    bx      r0
    .pool
.endfunc

; Runs every frame of Phase Shift, in place of UpdateFreeMovement_Debug.
.align 2
.func NoClipHook
    push    { r4, lr }
    ldr     r0, =gChangedInput
    ldrh    r0, [r0]
    mov     r1, KEY_SELECT
    tst     r0, r1
    beq     @@move
    ldr     r0, =gButtonInput
    ldrh    r0, [r0]
    mov     r1, KEY_A
    tst     r0, r1
    beq     @@phase_out
    bl      TryWarp
    cmp     r0, #0
    bne     @@return
    b       @@denied
@@phase_out:
    bl      SamusPositionIsClear
    cmp     r0, #0
    beq     @@denied
    ldr     r0, =gSubGameMode1
    mov     r1, SUB_GAME_MODE_PLAYING
    strh    r1, [r0]
    ldr     r0, =SND_PHASE_OUT
    bl      SoundPlay
    b       @@return
@@denied:
    ldr     r0, =SND_DENIED
    bl      SoundPlay
@@move:
    bl      UpdateFreeMovement_Debug
@@return:
    pop     { r4 }
    pop     { r0 }
    bx      r0
    .pool
.endfunc

; Time Stop: these updates are skipped while in Phase Shift.
.align 2
.func SpriteUpdateHook
    ldr     r0, =gSubGameMode1
    ldrh    r0, [r0]
    cmp     r0, SUB_GAME_MODE_NO_CLIP
    beq     @@skip
    ldr     r0, =SpriteUpdate + 1
    bx      r0
@@skip:
    bx      lr
    .pool
.endfunc

.align 2
.func WeaponUpdateHook
    ldr     r0, =gSubGameMode1
    ldrh    r0, [r0]
    cmp     r0, SUB_GAME_MODE_NO_CLIP
    beq     @@skip
    ldr     r0, =UpdateArmCannonAndWeapons + 1
    bx      r0
@@skip:
    bx      lr
    .pool
.endfunc

.align 2
.func AnimatedGraphicsHook
    ldr     r0, =gSubGameMode1
    ldrh    r0, [r0]
    cmp     r0, SUB_GAME_MODE_NO_CLIP
    beq     @@skip
    ldr     r0, =RoomUpdateAnimatedGraphicsAndPalette + 1
    bx      r0
@@skip:
    bx      lr
    .pool
.endfunc

; Loading a file forgets the warp target; the room the file loads into (the
; save room) is recorded on the first frame of gameplay.
.align 2
.func LoadGenericsHook
    ldr     r0, =gIsLoadingFile
    ldrb    r0, [r0]
    cmp     r0, #0
    beq     @@continue
    ldr     r0, =WarpValid
    mov     r1, #0
    strb    r1, [r0]
@@continue:
    ldr     r0, =InitAndLoadGenerics + 1
    bx      r0
    .pool
.endfunc

; A new game forgets the warp target too, so the starting room is recorded.
.align 2
.func NewGameHook
    ldr     r1, =WarpValid
    mov     r2, #0
    strb    r2, [r1]
    ldr     r1, =InitStartingMap + 1
    bx      r1
    .pool
.endfunc

; Records the current room as the warp target if there is none yet, or if
; Samus is standing on a save pad (including the gunship).
.align 2
.func RecordWarpTarget
    ldr     r2, =WarpValid
    ldrb    r0, [r2]
    cmp     r0, WARP_VALID_MAGIC
    bne     @@record
    ldr     r0, =gSamusData
    ldrb    r0, [r0, SamusData_Pose]
    cmp     r0, SPOSE_ON_SAVE_PAD
    beq     @@record
    cmp     r0, SPOSE_SAVING
    beq     @@record
    bx      lr
@@record:
    ldr     r0, =gCurrentArea
    ldrb    r1, [r0]
    strb    r1, [r2, WarpArea - WarpValid]
    ldrb    r1, [r0, #1]
    strb    r1, [r2, WarpRoom - WarpValid]
    mov     r0, WARP_VALID_MAGIC
    strb    r0, [r2]
    bx      lr
    .pool
.endfunc

.align 2
.func Regenerate
    ldr     r2, =RegenTimer
    ldrh    r3, [r2]
    add     r3, #1
    strh    r3, [r2]
    ldr     r2, =gEquipment
@@energy:
    mov     r0, REGEN_ENERGY_MASK
    tst     r0, r3
    bne     @@missiles
    ldrh    r0, [r2, Equipment_CurrentEnergy]
    ldrh    r1, [r2, Equipment_MaxEnergy]
    cmp     r0, r1
    bhs     @@missiles
    add     r0, #1
    strh    r0, [r2, Equipment_CurrentEnergy]
@@missiles:
    mov     r0, REGEN_MISSILE_MASK
    tst     r0, r3
    bne     @@power_bombs
    ldrh    r0, [r2, Equipment_CurrentMissiles]
    ldrh    r1, [r2, Equipment_MaxMissiles]
    cmp     r0, r1
    bhs     @@power_bombs
    add     r0, #1
    strh    r0, [r2, Equipment_CurrentMissiles]
@@power_bombs:
    mov     r0, REGEN_POWER_BOMB_MASK
    tst     r0, r3
    bne     @@return
    ldrb    r0, [r2, Equipment_CurrentPowerBombs]
    ldrb    r1, [r2, Equipment_MaxPowerBombs]
    cmp     r0, r1
    bhs     @@return
    add     r0, #1
    strb    r0, [r2, Equipment_CurrentPowerBombs]
@@return:
    bx      lr
    .pool
.endfunc

; Same conditions as pausing (ProcessPauseButtonPress), so powers are blocked
; during cutscenes, elevators, saving, downloads, being grabbed, dying etc.
; Returns r0 = 1 if allowed.
.align 2
.func PowersAllowed
    ldr     r0, =gPreventMovementTimer
    ldrh    r0, [r0]
    cmp     r0, #0
    bne     @@no
    ldr     r0, =gCurrentPowerBomb
    ldrb    r1, [r0]
    ldrb    r0, [r0, #10h]
    orr     r0, r1
    bne     @@no
    ldr     r0, =gDisablePauseFlag
    ldrb    r0, [r0]
    cmp     r0, #0
    bne     @@no
    ldr     r0, =gSamusData
    ldrb    r0, [r0, SamusData_Pose]
    cmp     r0, SPOSE_USING_ELEVATOR
    beq     @@no
    cmp     r0, SPOSE_ON_SAVE_PAD
    blo     @@yes
    cmp     r0, SPOSE_DELAY_BEFORE_SHINESPARKING
    blo     @@no
    cmp     r0, SPOSE_UNLOCKING_SECURITY
    blo     @@yes
@@no:
    mov     r0, #0
    bx      lr
@@yes:
    mov     r0, #1
    bx      lr
    .pool
.endfunc

; Returns r0 = 1 if none of the points on the edge of Samus's hitbox are in
; solid clipdata.
.align 2
.func SamusPositionIsClear
    push    { r4-r7, lr }
    ldr     r0, =gSamusData
    ldrh    r4, [r0, SamusData_XPosition]
    ldrh    r5, [r0, SamusData_YPosition]
    mov     r1, SamusData_HitboxLeft
    ldsh    r6, [r0, r1]            ; left offset (negative)
    mov     r1, SamusData_HitboxRight
    ldsh    r7, [r0, r1]            ; right offset
    mov     r1, SamusData_HitboxTop
    ldsh    r3, [r0, r1]            ; top offset (negative)
    add     r6, #2                  ; inset slightly from the edges
    sub     r7, #2
    add     r3, #2
    sub     r5, #1                  ; bottom: just above the feet
    mov     r0, r5
    add     r0, r3                  ; r0 = top y
    asr     r3, #1
    add     r3, r5                  ; r3 = middle y
    sub     sp, #0Ch
    str     r0, [sp]                ; top
    str     r3, [sp, #4]            ; middle
    str     r5, [sp, #8]            ; bottom
    mov     r5, #0                  ; point index 0-5
@@loop:
    lsr     r1, r5, #1
    lsl     r1, #2
    mov     r0, sp
    ldr     r0, [r0, r1]            ; y for this row
    mov     r1, #1
    tst     r1, r5
    beq     @@left
    add     r1, r4, r7
    b       @@check
@@left:
    add     r1, r4, r6
@@check:
    lsl     r0, #10h
    lsr     r0, #10h
    lsl     r1, #10h
    lsr     r1, #10h
    bl      ClipdataProcess
    lsr     r0, CLIPDATA_SOLID_BIT
    lsl     r0, #1Fh
    bne     @@blocked
    add     r5, #1
    cmp     r5, #6
    blo     @@loop
    mov     r0, #1
    b       @@return
@@blocked:
    mov     r0, #0
@@return:
    add     sp, #0Ch
    pop     { r4-r7 }
    pop     { r1 }
    bx      r1
    .pool
.endfunc

; Starts a room transition into the recorded save room, the same way an area
; connection (elevator) does. Returns r0 = 1 if the warp started.
.align 2
.func TryWarp
    push    { r4-r7, lr }
    ldr     r0, =WarpValid
    ldrb    r1, [r0]
    cmp     r1, WARP_VALID_MAGIC
    bne     @@fail
    ldrb    r4, [r0, WarpArea - WarpValid]
    ldrb    r5, [r0, WarpRoom - WarpValid]
    ; Find a door that leads out of the target room, to arrive through
    ldr     r0, =sAreaDoorPointers
    lsl     r1, r4, #2
    ldr     r6, [r0, r1]
    mov     r7, #0                  ; door index
@@find_door:
    ldrb    r0, [r6]                ; type
    cmp     r0, #0
    beq     @@fail                  ; end of door list
    ldrb    r1, [r6, #1]            ; source room
    cmp     r1, r5
    bne     @@next_door
    mov     r1, DOOR_TYPE_NO_FLAGS
    and     r0, r1
    cmp     r0, DOOR_TYPE_NO_HATCH  ; skip area connections
    bhs     @@found_door
@@next_door:
    add     r6, DOOR_SIZE
    add     r7, #1
    cmp     r7, #0FFh
    blo     @@find_door
    b       @@fail
@@found_door:
    ldr     r0, =gCurrentArea
    strb    r4, [r0]
    ldr     r0, =gLastDoorUsed
    strb    r7, [r0]
    mov     r1, #0
    ldr     r0, =gDoorPositionStart
    str     r1, [r0]
    ldr     r0, =gSamusDoorPositionOffset
    strh    r1, [r0]
    ldr     r0, =gSubGameMode1
    mov     r1, SUB_GAME_MODE_LOADING_ROOM
    strh    r1, [r0]
    mov     r0, #6
    bl      ColorFadingStart
    bl      ColorEffectCopyPalramToEwramPal2And1
    mov     r0, r5
    bl      RoomEffectSetCurrentNavigationRoom
    mov     r0, r4
    mov     r1, r5
    bl      PlayRoomMusicTrack
    ldr     r0, =SND_WARP
    bl      SoundPlay
    mov     r0, #1
    b       @@return
@@fail:
    mov     r0, #0
@@return:
    pop     { r4-r7 }
    pop     { r1 }
    bx      r1
    .pool
.endfunc

.endarea
