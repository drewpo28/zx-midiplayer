INPUT_REPEAT            equ 2
INPUT_REPEAT_FIRST      equ 11
INPUT_BEEP_DELAY        equ 20

PIANO_KEYS_FIRST        equ 12

PLAYLIST_DELAY          equ 10

SMF_MAX_TRACKS          equ 60

MMC_INIT_TIMEOUT        equ 4000/20
MMC_READ_TIMEOUT        equ 4000/20

IDE_INIT_TIMEOUT        equ 500/20
IDE_READ_TIMEOUT        equ 4000/20

DISKS_MAX_COUNT         equ 10

; --- Large MIDI support (>64KB) ---------------------------------------------
; File position is a 20-bit value (up to 1 MB):
;   - low 16 bits  -> HL
;   - high 4 bits  -> var_file_pos_hi  (file position bits 16..19)
; The 16 KB bank window lives at #C000. The bank index (which 16 KB page of the
; file is mapped) is  page = (var_file_pos_hi << 2) | (H >> 6)  -> 0..63.
; var_file_pages[page] holds the value to write to #7FFD to map that bank.
; On a plain 128K machine only the 4 base banks exist (64 KB cap); on
; Pentagon 512/1024 the table is extended at runtime by file_detect_memory.
FILE_PAGES_MAX          equ 64           ; hard ceiling on table size (1 MB)

; Load HL+var_file_pos_hi from a 3-byte little-endian field at (iy+field)
    MACRO FPOS_LD field
        ld l, (iy+field+0)
        ld h, (iy+field+1)
        ld a, (iy+field+2)
        ld (var_file_pos_hi), a
    ENDM

; Store HL+var_file_pos_hi to a 3-byte little-endian field at (iy+field)
    MACRO FPOS_ST field
        ld (iy+field+0), l
        ld (iy+field+1), h
        ld a, (var_file_pos_hi)
        ld (iy+field+2), a
    ENDM
