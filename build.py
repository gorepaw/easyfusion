"""Builds the patched ROM and an IPS patch from the clean Metroid Fusion (USA) ROM.

Usage: python build.py
"""
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent
CLEAN_ROM = ROOT / "Metroid Fusion (USA).gba"
CLEAN_SHA1 = "ca33f4348c2c05dd330d37b97e2c5a69531dfe87"
OUT_DIR = ROOT / "build"
OUT_ROM = OUT_DIR / "EasyFusion.gba"
OUT_IPS = OUT_DIR / "EasyFusion.ips"
OUT_SYM = OUT_DIR / "EasyFusion.sym"
ARMIPS = ROOT / "tools" / "armips.exe"
MAIN_ASM = ROOT / "src" / "main.asm"


def make_ips(clean: bytes, patched: bytes) -> bytes:
    assert len(clean) == len(patched), "ROM size changed; IPS writer assumes same size"
    out = bytearray(b"PATCH")
    i = 0
    n = len(clean)
    while i < n:
        if clean[i] == patched[i]:
            i += 1
            continue
        start = i
        # Extend the record while bytes differ (allow short equal gaps to merge records)
        while i < n and i - start < 0xFFFF:
            if clean[i] != patched[i]:
                i += 1
            elif clean[i:i + 6] != patched[i:i + 6]:
                i += 1
            else:
                break
        if start == 0x454F46:  # "EOF" offset would end the patch early
            start -= 1
        out += start.to_bytes(3, "big") + (i - start).to_bytes(2, "big") + patched[start:i]
    out += b"EOF"
    return bytes(out)


def main() -> int:
    clean = CLEAN_ROM.read_bytes()
    if hashlib.sha1(clean).hexdigest() != CLEAN_SHA1:
        print(f"error: {CLEAN_ROM.name} is not a clean Metroid Fusion (USA) ROM")
        return 1

    OUT_DIR.mkdir(exist_ok=True)
    shutil.copyfile(CLEAN_ROM, OUT_ROM)
    result = subprocess.run(
        [str(ARMIPS), MAIN_ASM.name, "-strequ", "ROM", str(OUT_ROM), "-sym", str(OUT_SYM)],
        cwd=MAIN_ASM.parent,
    )
    if result.returncode != 0:
        OUT_ROM.unlink(missing_ok=True)
        return result.returncode

    patched = OUT_ROM.read_bytes()
    OUT_IPS.write_bytes(make_ips(clean, patched))

    changed = sum(a != b for a, b in zip(clean, patched))
    print(f"built {OUT_ROM.name} ({changed} bytes changed)")
    print(f"built {OUT_IPS.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
