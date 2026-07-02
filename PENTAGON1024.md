# Large MIDI files (>64 KB) on Pentagon 128 / 512 / 1024

This fork lifts the original 64 KB MIDI-file limit by widening the internal file
pointer to 20 bits (up to 1 MB) and laying the file out across the extended RAM
banks of Pentagon 512/1024 machines.

## What changed

The original player kept the whole MIDI file in 4×16 KB banks at `#C000` and
addressed it with a 16-bit pointer (`HL`), so the hard ceiling was 4×16 = 64 KB.
Multi-track (SMF format 1) playback was already supported — only the size was
capped.

This version:

- **20-bit file position** — `HL` (low 16) + `var_file_pos_hi` (bits 16..19).
  `smf_track_t.position`/`.end` and `var_current_file_size` were widened
  accordingly; the SMF parser, both loaders (FAT and TR-DOS) and the visualiser
  were updated to carry the high byte.
- **Runtime RAM detection** (`file_detect_memory`, `disk.asm`) builds the
  `var_file_pages` bank table by probing physical banks 8.. upward. One binary
  adapts itself:
  - **Pentagon 128** — no extra banks found → 64 KB cap (unchanged behaviour).
  - **Pentagon 256** — banks 8..15 (via `#7FFD` bit 6) → ~192 KB.
  - **Pentagon 512** — banks 8..31 (via `#7FFD` bits 6,7) → ~448 KB.
  - **Pentagon 1024** — banks 32..63 (via `#7FFD` bit 5, unlocked through
    `#EFF7`) → ~960 KB. Requires the `MEM=1024` build (see below).
  - **Scorpion ZS-256** — banks 8..15 (via `#1FFD` bit 4 + `#7FFD` low bits)
    → ~192 KB. Probed only if no Pentagon/Profi extended banks were found.
- The paging scheme can also be forced in **Settings → Memory**
  (`Auto` / `Pent 128` / `Pent 512` / `Pent 1024` / `Profi 1024` / `TS Conf` /
  `Pent 256` / `Scorp 256`) — useful when auto-detection misfires on a clone.
- Files that do not fit the detected RAM are rejected at load time instead of
  corrupting memory.

The bank mapping follows the standard Pentagon 1024SL scheme: `#7FFD` bank bits
`{D5,D7,D6,D2,D1,D0}` with `D4` (ROM) kept set, and `#EFF7` bit2=0 to turn `D5`
from the paging-lock latch into the top bank bit.

## Building

```
make                # auto-detects 128K/512K at runtime (safe on any machine)
make MEM=1024       # adds the last 512KB via #7FFD bit5 (Pentagon 1024SL only)
```

Outputs in `build/`: `main.trd` (canonical, used by `make run`), plus
`main.sna`/`main.tap`.

> Note: the code now exceeds 16 KB, so the `.sna`/`.tap` packer (which assumed a
> single 16 KB code page) reports a "cannot fit" error for those two formats.
> `main.trd` builds fully and is the file to use.

## ⚠️ Pentagon 1024 caveat — read before flashing `MEM=1024`

`MEM=1024` writes `#EFF7` and then sets `#7FFD` bit5. On a **real Pentagon
1024SL** this unlocks bit5 as a RAM bank bit. On a **128K/512K** machine bit5 is
the paging-**lock** latch — setting it freezes paging until reset. Therefore:

- Run the `MEM=1024` build **only** on genuine Pentagon 1024SL hardware.
- On 128K/512K use the plain `make` build (it never touches bit5/`#EFF7` and
  caps at the safely-detected size).
- If your 1024 clone needs other system bits in `#EFF7`, adjust
  `EFF7_UNLOCK_1024` in `src/disk.asm` (default `#00`).

## Testing

> **First check the machine architecture.** A plain "Pentagon" / "128K" profile
> has only 128 KB and genuinely cannot hold >64 KB — the player correctly refuses
> such files (and the browser shows a real size, see below). You must select a
> **Pentagon 512** or **Pentagon 1024** profile (e.g. in pico-spec: arch `P512`
> or `P1024`) for big files to load. Detection runs at boot and unlocks extended
> banking via `#EFF7` (bit2=0) before probing, so 512/1024 RAM is found whether or
> not the firmware left paging locked.

TR-DOS files top out at ~64 KB (1-byte sector count), so a **>64 KB file must be
loaded from a FAT volume** (DivMMC / ZXMMC / Z-Controller / NemoIDE / SMUC).

1. Generate test files (valid SMF format 1):
   ```
   python3 test/gen_big_midi.py big192.mid 192 8     # 192 KB, 9 tracks
   python3 test/gen_big_midi.py big384.mid 384 12     # 384 KB, 13 tracks
   python3 test/gen_big_midi.py big_track.mid 200 2   # 2 tracks, each >64 KB
   ```
2. Copy them to a FAT-formatted SD/CF/IDE image (or card).
3. Boot the player, enable your storage interface in Settings, browse to the
   file and play.

What each file checks:
- `big192`/`big384` — track **positions** cross 64 KB boundaries (per-track
  `position_hi`/`end_hi`, bank switching, multi-track merge past 64 KB).
- `big_track` — a single **track length >64 KB** (24-bit chunk length parsing
  and the 20-bit end-of-track comparison).

## Known limitations

- The on-screen size/progress counter (`bytes_left`) is still 16-bit, so for
  files >64 KB the displayed size wraps. Cosmetic only — playback is unaffected.
- `.sna`/`.tap` build outputs are broken by the larger code (see above); use the
  TRD.
