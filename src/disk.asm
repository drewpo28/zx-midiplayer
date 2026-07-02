; Page         128  +3
; 0 000
; 1 001        slow
; 2 010 0x8000
; 3 011        slow
; 4 100             slow
; 5 101 0x4000 slow slow
; 6 110             slow
; 7 111 altscr slow slow

file_base_addr equ #c000
file_page_size equ #4000

; --- Bank paging: Pentagon (#7FFD), Profi (#7FFD + #DFFD), TS-Conf (#13AF) or ---
; --- Scorpion (#7FFD + #1FFD bit4), chosen at runtime ---
; var_file_pages[index] holds the physical bank NUMBER (0..63) for each 16 KB file page.

; IN  -  A - physical bank number N (0..63)
; OUT - maps bank N into the 16 KB window at file_base_addr
; OUT - preserves DE, HL ; clobbers AF, BC
file_set_bank:
    push de                          ;
    ld e, a                          ; E = N (physical bank / page number)
    ld a, (var_profi_mode)           ; 0=Pentagon, 1=Profi, 2=TS-Conf, 3=Scorpion
    dec a : jr z, .profi             ; mode 1 -> Profi
    dec a : jr z, .tsconf            ; mode 2 -> TS-Conf
    dec a : jr z, .scorpion          ; mode 3 -> Scorpion
.pentagon:                           ; Pentagon 128/256/512/1024: one #7FFD write
    ld a, e                          ;
    call file_bankval                ; A = #7FFD value (D6/D7/D5 encode high bank bits)
    ld bc, #7ffd : out (c), a        ;
    pop de                           ;
    ret                              ;
.tsconf:                             ; TS-Conf: Page3 register maps any 16K page into #C000
    ld a, e                          ; A = 8-bit physical page number (0..255 -> up to 4 MB)
    ld bc, #13af : out (c), a        ; write Page3 (#nnAF reg space, reg #13)
    pop de                           ;
    ret                              ;
.scorpion:                           ; Scorpion ZS-256: #7FFD low 3 bits + #1FFD bit4 (RAM ext)
    ld a, e                          ; #7FFD = ROM(#10) | (N & 7)
    and 7 : or #10                   ;
    ld bc, #7ffd : out (c), a        ;
    ld a, e                          ; #1FFD bit4 = N bit3 (banks 8..15); other bits 0
    and 8 : add a, a                 ;
    ld bc, #1ffd : out (c), a        ;
    pop de                           ;
    ret                              ;
.profi:                              ; Profi 1024: #7FFD low 3 bits + #DFFD page group
    ld a, e                          ; #7FFD = ROM(#10) | (N & 7)
    and 7 : or #10                   ;
    ld bc, #7ffd : out (c), a        ;
    ld a, e                          ; #DFFD = (N >> 3) & 7 (upper page group; other bits 0)
    rrca : rrca : rrca               ;
    and 7                            ;
    ld bc, #dffd : out (c), a        ;
    pop de                           ;
    ret                              ;

; Reset the Profi extended page group (#DFFD) / Scorpion RAM-extension bit (#1FFD)
; to 0, so the player's own #7FFD bank writes (e.g. screen_load) address the base
; banks; also invalidate the file page cache because the #C000 mapping is about to
; change. Harmless on Pentagon/128K.
; OUT - AF, BC garbage ; HL, DE preserved
file_page_reset:
    ld a, #ff                        ; invalidate file_get_next_byte page cache
    ld (file_get_next_byte.pg+1), a  ;
    ld a, (var_profi_mode)           ;
    cp 1 : jr z, .profi              ; Profi: #DFFD page group -> 0
    cp 3                             ; Scorpion: #1FFD ext bit -> 0
    ret nz                           ; ... Pentagon/128K/TS-Conf: cache invalidate is enough
    xor a                            ;
    ld bc, #1ffd                     ;
    out (c), a                       ;
    ret                              ;
.profi:
    xor a                            ;
    ld bc, #dffd                     ;
    out (c), a                       ;
    ret                              ;

; IN  - HL - file position (low 16), var_file_pos_hi - bits 16..19
; OUT - selects the bank mapping this position; primes the page cache; HL,DE preserved
; OUT - AF, BC - garbage
file_switch_page:
    ld a, (var_file_pos_hi)          ; bank index = (var_file_pos_hi << 2) | H[7:6]
    add a, a : add a, a              ;
    ld c, a                          ;
    ld a, h : and #c0 : rlca : rlca  ;
    or c                             ; A = bank index (0..63)
    ld (file_get_next_byte.pg+1), a  ; cache (already-current -> no re-switch)
    add a, low var_file_pages        ;
    ld c, a : ld b, high var_file_pages ;
    ld a, (bc)                       ; A = physical bank number
    jp file_set_bank                 ; map it (preserves HL, DE)

; IN  - HL - file position low 16, var_file_pos_hi - bits 16..19
; OUT -  A - data byte ; HL - next position ; DE preserved ; F, BC - garbage
file_get_next_byte:
    ld a, (var_file_pos_hi)          ; bank index = (var_file_pos_hi << 2) | H[7:6]
    add a, a : add a, a              ; ... (full index, so a change in bits 16..19
    ld c, a                          ; ...  alone still forces a page switch)
    ld a, h : and #c0 : rlca : rlca  ;
    or c                             ;
.pg:cp #ff                           ; page changed? self modifying code! see file_switch_page
    jp z, .get                       ;
.switch_page:
    ld (.pg+1), a                    ; cache new bank index
    add a, low var_file_pages        ;
    ld c, a : ld b, high var_file_pages ;
    ld a, (bc)                       ; A = physical bank number
    call file_set_bank               ; map it (preserves HL, DE)
.get:
    ld a, h                          ; window offset = position[13:0]
    and #3f                          ;
    add a, high file_base_addr       ;
    ld b, a                          ;
    ld c, l                          ;
    inc hl                           ; position++ (low 16)
    ld a, h                          ; did HL wrap 0xFFFF -> 0x0000 (crossed 64 KB)?
    or l                             ; ... (the LD below does not touch flags)
    ld a, (bc)                       ; A = data byte
    ret nz                           ; no wrap -> done
    push af                          ; wrap: carry into bits 16..19
    ld a, (var_file_pos_hi) : inc a : ld (var_file_pos_hi), a ;
    pop af                           ;
    ret                              ;

; A = physical bank number (0..63) -> A = #7FFD value (Pentagon encoding).
; D6=bit3, D7=bit4, D5=bit5; D4=ROM kept set.  OUT - DE garbage
file_bankval:
    ld e, a                          ;
    and 7 : or #10                   ;
    ld d, a                          ;
    ld a, e : and #08 : jr z, 1f     ; N bit3 -> D6
    set 6, d                         ;
1:  ld a, e : and #10 : jr z, 1f     ; N bit4 -> D7
    set 7, d                         ;
1:  ld a, e : and #20 : jr z, 1f     ; N bit5 -> D5
    set 5, d                         ;
1:  ld a, d                          ;
    ret                              ;

; IN  -  A - bank number to probe ; uses file_set_bank (current var_profi_mode)
; OUT -  F - Z if bank is real and distinct from bank 0
; OUT - AF, BC garbage ; DE, HL preserved
probe_bank:
    ld (var_probe_val), a            ;
    call file_set_bank               ; map candidate, write marker
    ld a, #a5 : ld (#c000), a        ;
    ld a, #5a : ld (#c001), a        ;
    xor a : call file_set_bank       ; map reference bank 0, write different data
    xor a : ld (#c000), a            ;
    ld a, #ff : ld (#c001), a        ;
    ld a, (var_probe_val)            ; re-map candidate, verify markers survived
    call file_set_bank               ;
    ld a, (#c000) : cp #a5 : ret nz  ;
    ld a, (#c001) : cp #5a           ; Z iff both markers survived
    ret                              ;

; Test for a Pentagon 1024SL by probing port #EFF7: bit3=1 overlays page0 with RAM
; (bank 0). We then write to 0x0000 and read it back - it sticks only if the overlay
; exists. A plain Pentagon 512 has no #EFF7, so the write hits ROM and is ignored ->
; not detected. This lets us confirm a 1024SL (where #7FFD bit5 is a SAFE bank bit)
; WITHOUT ever blindly setting bit5, which would permanently lock a Pentagon 512.
; Leaves #EFF7 = 0 (page0 back to ROM; bit2=0 -> bit5 enabled as bank bit on 1024SL).
; OUT - F - Z if Pentagon 1024SL detected ; AF, BC, DE, HL garbage
detect_eff7_1024:
    di                               ;
    push bc                          ; preserve caller's bank counter (we clobber BC via #EFF7 OUTs)
    ld hl, 0                         ; HL = 0x0000 (page0)
    ld d, (hl)                       ; D = byte currently there (ROM)
    ld a, #08                        ; #EFF7: bit3=1 (overlay page0 with RAM bank0), bit2=0
    ld bc, #eff7 : out (c), a        ;
    ld a, d : cpl                    ; A = a value guaranteed different from the ROM byte
    ld (hl), a                       ; write to 0x0000 (sticks only if RAM is overlaid)
    ld e, a                          ; E = expected
    ld a, (hl)                       ; read back
    cp e                             ; Z iff the write took -> RAM overlay -> 1024SL
    push af                          ;
    xor a                            ; #EFF7 = 0: page0 back to ROM, bit5 left unlocked
    ld bc, #eff7 : out (c), a        ;
    pop af                           ;
    pop bc                           ; restore bank counter (Z from `cp e` survives pop)
    ei                               ;
    ret                              ;

; Test for a TS-Configuration. Its MMU exposes the #C000 window page (Page3) as a
; READ/WRITE register at port #13AF (#nnAF config-reg space, reg #13). On a plain
; Pentagon/Profi that port is undecoded, so a written value won't read back (floating
; bus). We confirm with two distinct values to reject a floating-bus false match.
; Non-destructive: touches only Page3 (no RAM writes); leaves Page3 = page 0 (#C000)
; on a real TS-Conf. OUT - F - Z if TS-Conf ; AF, BC garbage ; DE, HL preserved
detect_tsconf:
    ld bc, #13af                     ; B=#13 (reg number), C=#AF (reg-space low byte)
    ld a, #2a : out (c), a           ; Page3 = #2A
    in a, (c) : cp #2a : ret nz      ; ... no read-back -> not a register -> not TS-Conf
    ld a, #15 : out (c), a           ; Page3 = #15 (second, distinct value)
    in a, (c) : cp #15 : ret nz      ; ... confirm a real R/W register (NZ -> not TS-Conf)
    xor a : out (c), a               ; restore Page3 = page 0 at #C000
    cp a                             ; force Z (TS-Conf confirmed)
    ret                              ;

; Detect extended RAM + paging scheme at runtime, build var_file_pages (bank numbers).
; 0) TS-Conf first: its Page3 (#13AF) is a clean 8-bit linear pager (up to 4 MB),
;    so probe pages 8.. via #13AF. (Probed before #7FFD so we never hit the TS-Conf
;    512K-mode where #7FFD bit5 = LOCK rather than a bank bit.)
; 1) Pentagon banks 8..31 via #7FFD D6/D7 (safe everywhere). A Pentagon 256 (D6
;    only) stops by itself at bank 15 - bank 16 (D7) aliases bank 0 and fails.
; 2) If those exist, test for a 1024SL via #EFF7 (above) and, only if confirmed,
;    probe banks 32..63 via #7FFD D5 -> full 1 MB. (Never touches D5 on a 512.)
; 3) If no Pentagon banks, probe Profi banks 8..63 via #DFFD page groups (no lock bit).
; 4) If no Profi banks, probe Scorpion 256 banks 8..15 via #1FFD bit4.
; On plain 128K nothing extra is found and the 4 base banks (64 KB) remain.
; Must run once at init. Clobbers the #C000 window.  OUT - everything garbage
file_detect_memory:
    ld hl, var_file_pages            ; base banks 0,4,6,3 (bank NUMBERS), present on every 128K
    ld (hl), 0 : inc hl              ;
    ld (hl), 4 : inc hl              ;
    ld (hl), 6 : inc hl              ;
    ld (hl), 3                       ;
    ld a, 4 : ld (var_file_pages_count), a ;
    xor a : ld (var_profi_mode), a   ; default Pentagon mode (also correct for forced Pent128/256/512/1024)
    ld a, (var_settings.memory)      ; forced paging mode? (Settings->Memory; 0 = Auto)
    or a : jr z, .auto               ; ... Auto: probe/detect below
    dec a : jp z, .done              ; 1 = Pent 128: base 4 banks (64 KB) only
    dec a : jr z, .force256          ; 2 = Pent 256: mode 0 already; D6 banks 8..15
    dec a : jr z, .force512          ; 3 = Pent 512: D6/D7 banks 8..31
    dec a : jr z, .force_ext         ; 4 = Pent 1024: mode 0 already; D5 banks 8..63
    dec a : jr z, .force_profi       ; 5 = Profi 1024 (#DFFD page groups)
    dec a : jr z, .force_ts          ; 6 = TS-Conf (Page3 #13AF)
    ld a, 3 : ld (var_profi_mode), a ; 7 = Scorp 256 (#7FFD + #1FFD bit4)
    jr .force256                     ;
.force_profi:
    ld a, 1 : ld (var_profi_mode), a ;
    jr .force_ext                    ;
.force_ts:
    ld a, 2 : ld (var_profi_mode), a ;
.force_ext:                          ; forced: probe extended banks/pages 8..63 in the chosen mode
    ld c, 8                          ;
.fe_loop:
    ld a, (var_file_pages_count) : cp FILE_PAGES_MAX : jp nc, .done ;
    ld a, c : push bc : call probe_bank : pop bc : jp nz, .done     ;
    call .append : inc c : jr .fe_loop                             ;
.force256:                           ; forced Pent 256 / Scorp 256: banks 8..15 only
    ld b, 16                         ; B = bank cap (survives probe_bank via push/pop)
    jr .fc_start                     ;
.force512:                           ; forced Pentagon 512: D6/D7 only (banks 8..31)
    ld b, 32                         ; stop before the D5 range
.fc_start:
    ld c, 8                          ;
.fc_loop:
    ld a, (var_file_pages_count) : cp FILE_PAGES_MAX : jp nc, .done ;
    ld a, c : cp b : jp nc, .done    ; stop at the mode's bank cap
    ld a, c : push bc : call probe_bank : pop bc : jp nz, .done     ;
    call .append : inc c : jr .fc_loop                             ;
.auto:
    call detect_tsconf               ; TS-Conf? (Page3 #13AF is a R/W register)
    jr nz, .try_pentagon             ; ... no -> fall through to Pentagon/Profi probing
    ld a, 2 : ld (var_profi_mode), a ; TS-Conf paging mode (Page3 via #13AF)
    ld c, 8                          ; probe physical pages 8.. (0,4,6,3 are the base banks)
.ts_loop:
    ld a, (var_file_pages_count)     ;
    cp FILE_PAGES_MAX : jp nc, .done ;
    ld a, c                          ;
    push bc : call probe_bank : pop bc ;
    jp nz, .done                     ; first page that isn't real/distinct -> stop
    call .append                     ;
    inc c : jr .ts_loop              ;
.try_pentagon:
    xor a : ld (var_profi_mode), a   ; Pentagon scheme for the first probe
    ld c, 8                          ; C = physical bank number to probe
.pent_loop:
    ld a, (var_file_pages_count)     ;
    cp FILE_PAGES_MAX : jp nc, .done ;
    ld a, c : cp 32 : jr nc, .check_1024 ; finished D6/D7 range (8..31) -> test for 1024SL
    ld a, c                          ;
    push bc : call probe_bank : pop bc ;
    jr nz, .pent_done                ;
    call .append                     ;
    inc c : jr .pent_loop            ;
.pent_done:
    ld a, (var_file_pages_count)     ; probe failed: found some Pentagon banks?
    cp 4                             ;
    jr nz, .done                     ; ... yes (partial) -> stop, Pentagon mode
    jr .try_profi                    ; ... no (bank 8 failed) -> not Pentagon -> try Profi
.check_1024:
    call detect_eff7_1024            ; banks 8..31 exist; is it a 1024SL? (Z = yes, D5 unlocked)
    jr nz, .done                     ; ... 512 -> stop at ~448 KB (never touch D5)
    ld c, 32                         ; resume bank numbering at 32 (D5 range); guard against C clobber
.d5_loop:                            ; 1024SL: probe banks 32..63 via #7FFD D5
    ld a, (var_file_pages_count)     ;
    cp FILE_PAGES_MAX : jr nc, .done ;
    ld a, c                          ;
    push bc : call probe_bank : pop bc ;
    jr nz, .done                     ;
    call .append                     ;
    inc c : jr .d5_loop              ;
.try_profi:
    ld a, 1 : ld (var_profi_mode), a ; try Profi scheme (#DFFD page groups)
    ld c, 8                          ;
.profi_loop:
    ld a, (var_file_pages_count)     ;
    cp FILE_PAGES_MAX : jr nc, .done ;
    ld a, c                          ;
    push bc : call probe_bank : pop bc ;
    jr nz, .profi_end                ;
    call .append                     ;
    inc c : jr .profi_loop           ;
.profi_end:
    ld a, (var_file_pages_count)     ;
    cp 4                             ;
    jr nz, .done                     ; found Profi RAM
.try_scorpion:
    ld a, 3 : ld (var_profi_mode), a ; try Scorpion scheme (#1FFD bit4)
    ld c, 8                          ;
.scorp_loop:
    ld a, (var_file_pages_count)     ;
    cp FILE_PAGES_MAX : jr nc, .done ;
    ld a, c : cp 16 : jr nc, .done   ; Scorpion 256: banks 8..15 only
    ld a, c                          ;
    push bc : call probe_bank : pop bc ;
    jr nz, .scorp_end                ;
    call .append                     ;
    inc c : jr .scorp_loop           ;
.scorp_end:
    ld a, (var_file_pages_count)     ;
    cp 4                             ;
    jr nz, .done                     ; found Scorpion RAM
    xor a : ld (var_profi_mode), a   ; none of them -> plain 128K (64 KB), Pentagon mode
    ld bc, #1ffd : out (c), a        ; clear #1FFD probe residue (ignored on non-Scorpion)
.done:
    xor a                            ; restore bank 0 at #C000
    jp file_set_bank                 ;
.append:                             ; append bank number C to var_file_pages; count++
    ld a, (var_file_pages_count)     ;
    ld l, a : ld h, 0                ;
    ld de, var_file_pages            ;
    add hl, de                       ;
    ld (hl), c                       ;
    ld hl, var_file_pages_count      ;
    inc (hl)                         ;
    ret                              ;


disk_sector_size equ 512

DISK_DRIVER_DIVMMC      equ #10
DISK_DRIVER_ZXMMC       equ #20
DISK_DRIVER_ZCONTROLLER equ #30
DISK_DRIVER_NEOGS       equ #40
DISK_DRIVER_DIVIDE      equ #50 | #80
DISK_DRIVER_NEMOIDE     equ #60 | #80
DISK_DRIVER_SMUC        equ #70 | #80
    STRUCT disk_t
driver         DB
offset         DD
disk_param     DB
fatfs          fatfs_disk_t
    ENDS
    STRUCT disks_t
boot_n         DB
current_n      DB
current_ptr    DW
count          DB
all            BLOCK disk_t*DISKS_MAX_COUNT
    ENDS



; OUT - IXH - IXH+1 on success
; OUT -  AF - garbage
; OUT -  BC - garbage
; OUT -  DE - garbage
; OUT -  HL - garbage
disks_save_new:
    ld a, (var_disks.count)            ;
    cp DISKS_MAX_COUNT                 ;
    ret z                              ;
    ld hl, var_disks.count             ; count_next++
    inc (hl)                           ; ...
    assert disk_t == 16
    ld h, 0 : ld l, a                  ; de = &disks.all[count]
    .4 add hl, hl                      ; ...
    ld de, var_disks.all               ; ...
    add hl, de                         ; ...
    ex de, hl                          ; ...
    ld hl, var_disk                    ; memcpy(&disks.all[count],var_disk,sizeof(disk_t))
    ld bc, disk_t                      ; ...
    ldir                               ; ...
    inc ixh                            ;
    ret                                ;


; OUT - IXH - number of disks added
; OUT -   F - garbage
; OUT -  BC - garbage
; OUT -  DE - garbage
; OUT -  HL - garbage
; OUT - IXL - garbage
disks_scan_filesystems:
    ld ixh, 0                          ;
    ld bc, 0                           ;
    ld de, 0                           ;
    ld (var_disk.offset+0), bc         ;
    ld (var_disk.offset+2), de         ;
    ld hl, disk_buffer                 ;
    ld ixl, 1                          ;
    call disk_read_sectors             ;
    ret nz                             ;
.fatfs_without_mbr:
    call fatfs_init.check              ; disk may be formatted to fat without mbr
    jp z, disks_save_new               ;
.mbr:
    ld hl, disk_buffer+#1fe            ; check mbr signature
    ld a, #55 : cp (hl) : ret nz       ; ...
    inc hl                             ; ...
    ld a, #aa:  cp (hl):  ret nz       ; ...
    ld b, 0                            ; entries = 0
    ld hl, disk_buffer+#1ee            ;
    call .check_partition_entry        ;
    ld hl, disk_buffer+#1de            ;
    call .check_partition_entry        ;
    ld hl, disk_buffer+#1ce            ;
    call .check_partition_entry        ;
    ld hl, disk_buffer+#1be            ;
    call .check_partition_entry        ;
    ld ixh, 0                          ;
    ld a, b                            ;
    or a                               ;
    ret z                              ;
.check_partition_filesystem:
    pop hl                             ;
    ld (var_disk.offset+2), hl         ;
    pop hl                             ;
    ld (var_disk.offset+0), hl         ;
    push bc                            ;
    call fatfs_init                    ;
    call z, disks_save_new             ;
    pop bc                             ;
    djnz .check_partition_filesystem   ;
    ret                                ;
.check_partition_entry:
    ld a, (hl)                         ; valid PT_BootID is 0x00 or 0x80
    and #7f                            ; ...
    ret nz                             ; ...
    .4 inc hl                          ; check PT_System is not Blank
    ld a, (hl)                         ; ...
    or a                               ; ...
    ret z                              ; ...
    .4 inc hl                          ; check PT_LbaOfs != 0
    ld d, h : ld e, l                  ;
    xor a                              ; ...
    or (hl) : inc hl                   ; ...
    or (hl) : inc hl                   ; ...
    or (hl) : inc hl                   ; ...
    or (hl)                            ; ...
    ret z                              ; ...
    pop ix                             ; return address
1:  ex de, hl                          ; save PT_LbaOfs
    ld e, (hl) : inc hl                ; ...
    ld d, (hl) : inc hl                ; ...
    push de                            ; ...
    ld e, (hl) : inc hl                ; ...
    ld d, (hl) : inc hl                ; ...
    push de                            ; ...
    inc b                              ; entries++
    jp (ix)                            ; ret


; IN  -  A - driver | disk_number
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
; OUT - IX - garbage
disks_scan_mmc:
    ld (var_disk.driver), a            ;
    call mmc_driver_select             ;
    call mmc_init                      ;
    ret nz                             ;
    ld a, e                            ;
    ld (var_disk.disk_param), a        ;
    call disks_scan_filesystems        ;
    xor a : or ixh                     ; if there is no filesystems on disk - add it anyway, but deny any access to it
    ret nz                             ;
    ld a, #01                          ; ...
    ld (var_disk.driver), a            ; ...
    jp disks_save_new                  ; ...


; IN  -  A - driver | disk_number
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
; OUT - IX - garbage
disks_scan_ide:
    ld (var_disk.driver), a            ;
    call ide_driver_select             ;
    call ide_init                      ;
    ld a, 0                            ; nemoide may affect #fe port
    out (#fe), a                       ; ...
    ret nz                             ;
    call disks_scan_filesystems        ;
    xor a : or ixh                     ; if there is no filesystems on disk - add it anyway, but deny any access to it
    ret nz                             ;
    ld a, #81                          ; ...
    ld (var_disk.driver), a            ; ...
    jp disks_save_new                  ; ...


; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
; OUT - IX - garbage
disks_init:
    xor a                              ;
    ld (var_disks.count), a            ;
    ld (var_disks.current_ptr+0), a    ;
    ld (var_disks.current_ptr+1), a    ;
.scan_trdos:
    ld a, (var_trdos_present)          ;
    or a                               ;
    jr z, .scan_divide                 ;
    ld a, trdos_disks                  ;
    ld (var_disks.count), a            ;
.scan_divide:
    ld a, (var_settings.divide)        ;
    or a                               ;
    jr z, .scan_nemoide                ;
    ld a, DISK_DRIVER_DIVIDE | #00     ;
    call disks_scan_ide                ;
    ld a, DISK_DRIVER_DIVIDE | #01     ;
    call disks_scan_ide                ;
.scan_nemoide:
    ld a, (var_settings.nemoide)       ;
    or a                               ;
    jr z, .scan_smuc                   ;
    ld a, DISK_DRIVER_NEMOIDE | #00    ;
    call disks_scan_ide                ;
    ld a, DISK_DRIVER_NEMOIDE | #01    ;
    call disks_scan_ide                ;
.scan_smuc:
    ld a, (var_settings.smuc)          ;
    or a                               ;
    jr z, .scan_divmmc                 ;
    ld a, DISK_DRIVER_SMUC | #00       ;
    call disks_scan_ide                ;
    ld a, DISK_DRIVER_SMUC | #01       ;
    call disks_scan_ide                ;
.scan_divmmc:
    ld a, (var_settings.divmmc)        ;
    or a                               ;
    jr z, .scan_zxmmc                  ;
    ld a, DISK_DRIVER_DIVMMC | #00     ;
    call disks_scan_mmc                ;
    ld a, DISK_DRIVER_DIVMMC | #01     ;
    call disks_scan_mmc                ;
.scan_zxmmc:
    ld a, (var_settings.zxmmc)         ;
    or a                               ;
    jr z, .scan_zcontroller            ;
    ld a, DISK_DRIVER_ZXMMC | #00      ;
    call disks_scan_mmc                ;
    ld a, DISK_DRIVER_ZXMMC | #01      ;
    call disks_scan_mmc                ;
.scan_zcontroller:
    ld a, (var_settings.zcontroller)   ;
    or a                               ;
    jr z, .scan_neogs                  ;
    ld a, DISK_DRIVER_ZCONTROLLER      ;
    call disks_scan_mmc                ;
.scan_neogs:
    ld a, (var_settings.neogsmmc)      ;
    or a                               ;
    ret z                              ;
    ld a, DISK_DRIVER_NEOGS            ;
    jp disks_scan_mmc                  ;


; IN  - DEBC - src lba
; IN  - HL   - dst address of IXL*512-byte buffer
; IN  - IXL  - sectors count
; OUT - F    - Z on success, NZ on fail
; OUT - HL   - next untouched dst address
; OUT - A    - garbage
; OUT - BC   - garbage
; OUT - DE   - garbage
; OUT - IXL  - garbage
disk_read_sectors:
    push hl                          ;
    ld hl, (var_disk.offset+0)       ; lba = lba + partition offset
    add hl, bc                       ; ...
    ld b, h : ld c, l                ; ...
    ld hl, (var_disk.offset+2)       ; ...
    adc hl, de                       ; ...
    ex de, hl                        ; ...
    pop hl                           ;
.loop:
    push de                          ;
    push bc                          ;
    push ix                          ;
    call .driver_read_block          ;
    pop ix                           ;
    pop bc                           ;
    pop de                           ;
    ret nz                           ;
    inc c : jr nz, 1f                ;
    inc b : jr nz, 1f                ;
    inc e : jr nz, 1f                ;
    inc d                            ;
1:  dec ixl                          ;
    jr nz, .loop                     ;
    ret                              ;
.driver_read_block:
    ld a, (var_disk.driver)          ; if 7th bit is set - ide driver, else mmc
    bit 7, a                         ; ...
    ld a, (var_disk.disk_param)      ;
    jp nz, ide_read_block            ;
    jp mmc_read_block                ;


; IN  - DE - entry number
; OUT -  F - NZ when yes, Z when no
; OUT -  A - garbage
; OUT - BC - garbage
; OUT - HL - garbage
disk_entry_is_directory:
    jp 0

; IN  - DE - entry number
; OUT -  F - Z on success, NZ on fail
; OUT -  A - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
disk_file_load:
    jp 0

; IN  - DE - entry number or 0xffff for root directory
; OUT -  F - Z on success, NZ on fail
; OUT -  A - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
disk_directory_load:
    jp 0

; IN  - DE - entry number
; OUT -  F - Z on success, NZ on fail
; OUT - IX - pointer to 0-terminated string
; OUT -  A - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
disk_directory_menu_generator:
    jp 0


; IN  -  E - disk number
; OUT -  F - Z on success, NZ on fail
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
disk_change:
    push de                                  ;
.save_old_cur_disk:
    ld de, (var_disks.current_ptr)           ;
    ld a, d                                  ;
    or e                                     ;
    jr z, .change_to_new_disk                ;
    ld hl, var_disk                          ; memcpy(&disks.all[count],var_disk,sizeof(disk_t))
    ld bc, disk_t                            ;
    ldir                                     ;
.change_to_new_disk:
    pop de                                   ;
    ld a, e                                  ;
    ld (var_disks.current_n), a              ;
    ld h, 0 : ld l, e                        ; hl = &disks.all[count]
    assert disk_t == 16
    .4 add hl, hl                            ; ...
    ld de, var_disks.all                     ; ...
    add hl, de                               ; ...
    ld (var_disks.current_ptr), hl           ;
    ld de, var_disk                          ; memcpy(var_disk,&disks.all[count],sizeof(disk_t))
    ld bc, disk_t                            ; ...
    ldir                                     ; ...
    ld a, (var_disk.driver)                  ; determine driver type
    or a                                     ; ...
    jr z, .trd                               ; ...
.fat:
    ld hl, fatfs_entry_is_directory          ;
    ld (disk_entry_is_directory+1), hl       ;
    ld hl, fatfs_file_load                   ;
    ld (disk_file_load+1), hl                ;
    ld hl, fatfs_directory_load              ;
    ld (disk_directory_load+1), hl           ;
    ld hl, fatfs_file_menu_generator         ;
    ld (disk_directory_menu_generator+1), hl ;
.ide:
    jp m, ide_driver_select                  ; ... check bit 7
.mmc:
    jp mmc_driver_select                     ; ...
.trd:
    ld hl, trdos_entry_is_directory          ;
    ld (disk_entry_is_directory+1), hl       ;
    ld hl, trdos_file_load                   ;
    ld (disk_file_load+1), hl                ;
    ld hl, trdos_directory_load              ;
    ld (disk_directory_load+1), hl           ;
    ld hl, trdos_file_menu_generator         ;
    ld (disk_directory_menu_generator+1), hl ;
    ld hl, 0                                 ;
    ld (var_disks.current_ptr), hl           ;
    xor a                                    ; set Z flag
    ret                                      ;



; IN  - HL - pointer to file extension
; OUT -  A - icon
; OUT -  F - garbage
; OUT - DE - garbage
disks_get_icon_by_extension:
    ld d, h : ld e, l                    ;
.check_mid_extension:
    ld a, (de) : inc de                  ; if extension is "mid" - set appropriate icon
    cp 'm' : jr z, 1f                    ;
    cp 'M' : jr nz, .check_rmi_extension ;
1:  ld a, (de) : inc de                  ;
    cp 'i' : jr z, 1f                    ;
    cp 'I' : jr nz, .check_rmi_extension ;
1:  ld a, (de) : inc de                  ;
    cp 'd' : jr z, .melody_icon          ;
    cp 'D' : jr z, .melody_icon          ;
.check_rmi_extension:
    ld d, h : ld e, l                    ;
    ld a, (de) : inc de                  ; if extension is "rmi" - set appropriate icon
    cp 'r' : jr z, 1f                    ;
    cp 'R' : jr nz, .no_icon             ;
1:  ld a, (de) : inc de                  ;
    cp 'm' : jr z, 1f                    ;
    cp 'M' : jr nz, .no_icon             ;
1:  ld a, (de) : inc de                  ;
    cp 'i' : jr z, .melody_icon          ;
    cp 'I' : jr z, .melody_icon          ;
.no_icon:
    ld a, ' '                            ; if extension isn't recognized - set empty icon (space)
    ret                                  ;
.melody_icon:
    ld a, udg_melody                     ;
    ret                                  ;


; IN  -  E - entry number
; OUT -  F - Z on success, NZ on fail
; OUT - IX - pointer to 0-terminated string
; OUT -  A - garbage
; OUT - DE - garbage
; OUT - HL - garbage
disks_menu_generator:
    ld ix, tmp_menu_string              ;
    ld a, 'A'                           ;
    add a, e                            ;
    ld (ix+1), a                        ;
    ld (ix+2), ':'                      ;
    ld (ix+3), 0                        ;
.icon:
    assert disk_t == 16
    ld h, 0 : ld l, e                   ; de = &disks.all[count]
    .4 add hl, hl                       ; ...
    ld de, var_disks.all                ; ...
    add hl, de                          ; ...
    ld a, (hl)                          ; determine driver type
    or a                                ; ...
    jr z, .trd                          ; ...
    jp m, .ide                          ; ...
.mmc:
    ld (ix+0), udg_mmc                  ;
    xor a                               ; set Z flag
    ret                                 ;
.ide:
    ld (ix+0), udg_ide                  ;
    xor a                               ; set Z flag
    ret                                 ;
.trd:
    ld (ix+0), udg_floppy               ;
    xor a                               ; set Z flag
    ret                                 ;
