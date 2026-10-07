# EasyFusion

An assembly hack for **Metroid Fusion (USA)** that gives Samus new powers that
make the game easy, a bit like a debug mode that still plays like the real game.

> **Status: untested.** The patch assembles and the hooks have been checked in
> a disassembler, but it has not been play-tested yet. Expect bugs.

## Powers

| Input | Power |
|---|---|
| **Select** | **Phase Shift + Time Stop.** Samus floats through walls (D-pad, hold R to go faster) while enemies, beams and animated tiles freeze. Press Select again to drop back into normal play. If Samus would end up inside a wall, you hear a "denied" sound and stay in Phase Shift. |
| **Select + A** | **Warp** to the last save room, meaning the last room where Samus stood on a save pad (including the gunship) or loaded a file. Works from Phase Shift too. |
| always on | **Regeneration** of energy (+1 every 4 frames), missiles (+1 every 16 frames) and power bombs (+1 every 64 frames). |

Powers are blocked whenever the game wouldn't let you pause: cutscenes,
elevators, saving, downloading abilities, while a power bomb is going off,
and so on.

Phase Shift reuses Nintendo's leftover debug no-clip mode, which is still in
the retail ROM but can't be reached in normal play.

## Building

You need:

- A clean **Metroid Fusion (USA)** ROM (SHA-1 `ca33f4348c2c05dd330d37b97e2c5a69531dfe87`),
  named `Metroid Fusion (USA).gba`, in the repo root
- [armips v0.11.0](https://github.com/Kingcom/armips/releases/tag/v0.11.0), with `armips.exe` placed in `tools/`
- Python 3

```
python build.py
```

This writes `build/EasyFusion.gba` and `build/EasyFusion.ips`. You can apply
the IPS patch to a clean ROM with any patcher, or load it in mGBA with `-p`.

## Tuning

The regeneration rates and the sound effect for each power are constants at
the top of [`src/powers.asm`](src/powers.asm).

## How it works

- New code goes in an unused 129 KiB audio sample at `0x080F9A28`. The
  [MARS](https://github.com/MetroidAdvRandomizerSystem/mars-fusion-asm)
  randomizer reclaims the same space. It's within Thumb `bl` range of all game
  code, which the padding at the end of the ROM isn't.
- `InGameHandler` gets per-frame hooks: input and regeneration run during
  normal play; the sprite, weapon and animated-tile updates are skipped while
  in no-clip mode.
- The warp copies how the game handles an area connection (elevator): it
  sets the area and an entry door into the target room, then starts the room
  transition.

## Credits

Function and RAM addresses come from the
[metroidret/mf](https://github.com/metroidret/mf) decompilation and the MARS
symbol file.
