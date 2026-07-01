    STRUCT chunk_riff_header_t
id            DWORD ; "RIFF"
len           DWORD
id2           DWORD ; "RMID"
id3           DWORD ; "data"
len2          DWORD
    ENDS

    STRUCT chunk_header_t
id            DWORD ; "MThd" or "MTrk"
len           DWORD
    ENDS

    STRUCT chunk_mthd_t
header        chunk_header_t
format        WORD
num_tracks    WORD
division      WORD
    ENDS

    STRUCT chunk_mtrk_t
header        chunk_header_t
data          BLOCK 0
    ENDS

    STRUCT smf_file_t
num_tracks             BYTE
num_tracks_play        BYTE
ppqn                   WORD
tempo                  DWORD
ticks_per_int          WORD
ticks_per_int_fraction WORD
ticks                  DWORD
ticks_fraction         WORD
bytes_left             WORD
bytes_left_hi          BYTE     ; bits 16..23 of bytes_left (>64KB countdown support)
tracks                 BLOCK SMF_MAX_TRACKS*smf_track_t
_zerobyte              BYTE 0   ; this is read by smf_get_next_track and written by smf_parse (flags=0)
    ENDS

    STRUCT smf_track_t
flags             BYTE
last_status       BYTE
end               WORD
end_hi            BYTE     ; bits 16..19 of end position (>64KB support)
position          WORD
position_hi       BYTE     ; bits 16..19 of read position (>64KB support)
next_tick         DWORD
    ENDS

SMF_TRACK_FLAGS_VALID  equ 0
SMF_TRACK_FLAGS_PLAY   equ 1
SMF_TRACK_FLAGS_DELAY  equ 2

SMF_DEFAULT_TEMPO equ 500000     ; defined by MIDI standard


; IN  - HL - position of beginning of file
; OUT - HL - position of next byte after end of chunk
; OUT - AF - garbage
; OUT - BC - garbage
smf_parse_file_header_rmi:
    push hl                                    ;
    call .sub                                  ;
    pop hl                                     ;
    jr z, .is_riff                             ;
    ret                                        ;
.is_riff:
    ld bc, chunk_riff_header_t                 ; skip riff header
    add hl, bc                                 ; ...
    ret                                        ;
.sub:
    call file_get_next_byte : cp 'R' : ret nz  ;
    call file_get_next_byte : cp 'I' : ret nz  ;
    call file_get_next_byte : cp 'F' : ret nz  ;
    call file_get_next_byte : cp 'F' : ret nz  ;
    xor a                                      ; set Z flag
    ret                                        ;

; IN  - HL - position of beginning of file
; OUT -  F - Z = 1 on success, 0 on error
; OUT - HL - position of next byte after end of chunk
; OUT - AF - garbage
; OUT - BC - garbage
smf_parse_file_header:
    call file_get_next_byte : cp 'M' : ret nz                  ; chunk_header_t.id[0]
    call file_get_next_byte : cp 'T' : ret nz                  ; chunk_header_t.id[1]
    call file_get_next_byte : cp 'h' : ret nz                  ; chunk_header_t.id[2]
    call file_get_next_byte : cp 'd' : ret nz                  ; chunk_header_t.id[3]
    call file_get_next_byte : cp 0   : ret nz                  ; chunk_header_t.len[0]
    call file_get_next_byte : cp 0   : ret nz                  ; chunk_header_t.len[1]
    call file_get_next_byte : cp 0   : ret nz                  ; chunk_header_t.len[2]
    call file_get_next_byte : cp 6   : ret nz                  ; chunk_header_t.len[3]
    call file_get_next_byte : cp 0   : ret nz                  ; chunk_mthd_t.format[0]
    call file_get_next_byte :                                  ; chunk_mthd_t.format[1]
    or 1 : cp 1 : ret nz                                       ; if (format != 0 && format != 1) - return error
    call file_get_next_byte : cp 0   : ret nz                  ; chunk_mthd_t.num_tracks[0]
    call file_get_next_byte                                    ; chunk_mthd_t.num_tracks[1]
    ld (var_smf_file.num_tracks), a                            ; ...
    ld (var_smf_file.num_tracks_play), a                       ; ...
    cp SMF_MAX_TRACKS                                          ; if (num_tracks>SMF_MAX_TRACKS) - return error
    jp c, 1f : jp z, 1f                                        ; ...
    or 1                                                       ; reset Z flag
    ret                                                        ; ...
1:  call file_get_next_byte : ld (var_smf_file.ppqn+1), a      ; chunk_mthd_t.division[0]
    call file_get_next_byte : ld (var_smf_file.ppqn+0), a      ; chunk_mthd_t.division[1]
    xor a                                                      ; set Z flag
    ret

; IN  - HL - position in file
; IN  - IY - pointer to smf_track_t
; OUT -  F - Z = 1 on success, 0 on error
; OUT - HL - position of next byte after end of chunk
; OUT - AF - garbage
; OUT - BC - garbage
; OUT -  D - garbage
smf_parse_track_header:
    call file_get_next_byte : cp 'M' : ret nz                  ; chunk_header_t.id+0
    call file_get_next_byte : cp 'T' : ret nz                  ; chunk_header_t.id+1
    call file_get_next_byte : cp 'r' : ret nz                  ; chunk_header_t.id+2
    call file_get_next_byte : cp 'k' : ret nz                  ; chunk_header_t.id+3
    call file_get_next_byte : cp 0 : ret nz                    ; chunk_header_t.len+0 (must be 0; >16MB unsupported)
    call file_get_next_byte : ld e, a                          ; chunk_header_t.len+1 -> E = len bits 16..23 (DE survives file_get_next_byte)
    call file_get_next_byte : ld d, a                          ; chunk_header_t.len+2 -> D = len bits 8..15 (file_get_next_byte clobbers BC, NOT DE)
    call file_get_next_byte : ld c, a                          ; chunk_header_t.len+3 -> C = len bits 0..7
    ld b, d                                                    ; BC = len low 16 (bits 8..0)
    ld (iy+smf_track_t.position+0), l                          ; save 20-bit position to begin of track data
    ld (iy+smf_track_t.position+1), h                          ; ...
    ld a, (var_file_pos_hi)                                    ; ...
    ld (iy+smf_track_t.position+2), a                          ; ...
    add hl, bc                                                 ; end = position + len (24-bit)
    ld (iy+smf_track_t.end+0), l                               ; ...
    ld (iy+smf_track_t.end+1), h                               ; ...
    ld a, (var_file_pos_hi)                                    ; end_hi = pos_hi + len_hi + carry
    adc a, e                                                   ; ...
    ld (iy+smf_track_t.end+2), a                               ; ...
    ld (var_file_pos_hi), a                                    ; advance parse position (HL already = end low16) to next track
    push hl                                                    ; bytes_left += len (24-bit)
    ld hl, (var_smf_file.bytes_left)                           ; ... low 16
    add hl, bc                                                 ; ...
    ld (var_smf_file.bytes_left), hl                           ; ...
    ld a, (var_smf_file.bytes_left_hi)                         ; ... hi += len bits 16..23 + carry
    adc a, e                                                   ; ... (E = len bits 16..23, still valid here)
    ld (var_smf_file.bytes_left_hi), a                         ; ...
    pop hl                                                     ; ...
    ld a, (1<<SMF_TRACK_FLAGS_VALID)|(1<<SMF_TRACK_FLAGS_PLAY) ; set track flags
    ld (iy+smf_track_t.flags), a                               ; ...
    xor a                                                      ; set Z flag
    ld (iy+smf_track_t.last_status), a                         ;
    ld (iy+smf_track_t.next_tick+0), a                         ;
    ld (iy+smf_track_t.next_tick+1), a                         ;
    ld (iy+smf_track_t.next_tick+2), a                         ;
    ld (iy+smf_track_t.next_tick+3), a                         ;
    ret                                                        ;

; OUT -  F - Z = 1 on success, 0 on error
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - HL - garbage
; OUT - IX - garbage
; OUT - IY - garbage
smf_parse:
    ld bc, (SMF_DEFAULT_TEMPO>> 0)&0xFFFF : ld (var_smf_file.tempo+0), bc ; set default tempo
    ld bc, (SMF_DEFAULT_TEMPO>>16)&0xFFFF : ld (var_smf_file.tempo+2), bc ; ...
    ld hl, 0                              ; parse file header
    xor a : ld (var_file_pos_hi), a       ; ... start at position 0 (20-bit)
    call smf_parse_file_header_rmi        ; ... skip rmi header if present
    call smf_parse_file_header            ; ...
    ret nz                                ; ... return on error
    xor a                                 ;
    ld (var_smf_file.ticks+0), a          ;
    ld (var_smf_file.ticks+1), a          ;
    ld (var_smf_file.ticks+2), a          ;
    ld (var_smf_file.ticks+3), a          ;
    ld (var_smf_file.ticks_fraction+0), a ;
    ld (var_smf_file.ticks_fraction+1), a ;
    ld (var_smf_file.bytes_left+0), a     ;
    ld (var_smf_file.bytes_left+1), a     ;
    ld (var_smf_file.bytes_left_hi), a    ; bits 16..23 (>64KB countdown)
    ld a, (var_smf_file.num_tracks)       ; parse each track header
    ld ixl, a                             ; ...
    ld iy, var_smf_file.tracks            ; ...
1:  call smf_parse_track_header           ; ...
    ret nz                                ; ... return on error
    ld de, smf_track_t                    ; ...
    add iy, de                            ; ...
    dec ixl                               ; ...
    jp nz, 1b                             ; ...
    xor a                                 ; set next track flags = 0
    ld (iy+smf_track_t.flags), a          ; ...
    call smf_update_ticks_per_int         ;
    xor a                                 ; set Z flag
    ret                                   ;


; OUT - CIX - tempo
smf_get_tempo:
    ld a, (var_smf_file.tempo+0)    ;
    ld ixl, a                       ;
    ld a, (var_smf_file.tempo+1)    ;
    ld ixh, a                       ;
    ld a, (var_smf_file.tempo+2)    ;
    ld c, a                         ;
    ret                             ;


; see smf_get_next_track
; if this function returns F/Z=1 then there is nothing to play anymore
smf_get_first_track:
    ld iy, var_smf_file.tracks-smf_track_t ;
    jp smf_get_next_track.entry            ;

; IN  - HL - current track position
; IN  - IY - pointer to current track
; OUT -  F - Z = 0 on success, 1 if there is no more tracks
; OUT - HL - current position of next track
; OUT - IY - pointer to next track
; OUT - AF - garbage
; OUT - DE - garbage
smf_get_next_track:
    ld e, (iy+smf_track_t.position+0) ; DE = old_position low 16
    ld d, (iy+smf_track_t.position+1) ; ...
    ld c, (iy+smf_track_t.position+2) ; C  = old_position hi (bits 16..19)
    ld (iy+smf_track_t.position+0), l ; IY->track_position = HL+hi (current 20-bit position)
    ld (iy+smf_track_t.position+1), h ; ...
    ld a, (var_file_pos_hi)           ; A = current hi
    ld (iy+smf_track_t.position+2), a ; ...
    and a                             ; delta = current - old (24-bit; bytes consumed this step)
    sbc hl, de                        ; HL = current_low16 - old_low16 ; CY = borrow
    sbc a, c                          ; A  = current_hi - old_hi - borrow = delta_hi
    ex de, hl                         ; DE = delta low 16 (A still = delta_hi)
    ld c, a                           ; C  = delta_hi
    ld hl, (var_smf_file.bytes_left)  ; bytes_left -= delta (24-bit countdown, display only)
    and a                             ; ...
    sbc hl, de                        ; ... low 16
    ld (var_smf_file.bytes_left), hl  ; ...
    ld a, (var_smf_file.bytes_left_hi); ...
    sbc a, c                          ; ... hi - delta_hi - borrow
    ld (var_smf_file.bytes_left_hi), a; ...
.entry:
    ld de, smf_track_t                ;
.next_track:
    add iy, de                        ; IY += sizeof(smf_track_t)
    ld a, (iy+smf_track_t.flags)      ; if (!track_valid) return Z=1
    bit SMF_TRACK_FLAGS_VALID, a      ; ...
    ret z                             ; ...
    bit SMF_TRACK_FLAGS_PLAY, a       ; if (!track_play) check next track
    jr z, .next_track                 ; ...
    ld l, (iy+smf_track_t.position+0) ; HL+hi = IY->track_position (20-bit)
    ld h, (iy+smf_track_t.position+1) ; ...
    ld a, (iy+smf_track_t.position+2) ; ...
    ld (var_file_pos_hi), a           ; ...
    ret                               ;


; IN  - HL   - track position
; OUT - DEBC - int value (max 0x0FFFFFFF - 4 bytes)
; OUT - HL   - next track position
; OUT - AF   - garbage
smf_parse_varint:
    call file_get_next_byte   ; A = byte - fvvvvvvV - f - flag, v - value
    ld de, 0                  ;
    ld b, d                   ;
    ld c, a                   ;
    rlca                      ; if (flag == 0) - no more bytes, exit
    ret nc                    ; ...
    res 7, c                  ;
.loop:
    srl d                     ; before DEBC = 44444444 33333333 22222222 11111111; after DEBC = 43333333 32222222 21111111 10000000
    ld d, e                   ; ...
    rr d                      ; ... Cflag = 3
    ld e, b                   ; ...
    rr e                      ; ... Cflag = 2
    ld b, c                   ; ...
    rr b                      ; ... Cflag = 1
    ld c, 0                   ; ...
    rr c                      ; ...
    push bc                   ;
    call file_get_next_byte   ; A = byte - fvvvvvvv
    pop bc                    ;
    bit 7, a                  ;
    jr nz, .have_more_bytes   ;
.last_byte:
    or c                      ;
    ld c, a                   ;
    ret                       ;
.have_more_bytes:
    res 7, a                  ;
    or c                      ;
    ld c, a                   ;
    jp .loop                  ;


; TODO: SMPTE; negative 'division' field value

; OUT - AF  - garbage
; OUT - BC  - garbage
; OUT - DE  - garbage
; OUT - HL  - garbage
; OUT - IX  - garbage
smf_update_ticks_per_int:                                ; ticks_per_int = int_len_ms*1000 / tempo / ppqn
    ld a, (var_smf_file.tempo+2)                         ;
    ld ix, (var_smf_file.tempo)                          ;
    call player_set_tempo                                ;
    ld de, (var_smf_file.ppqn)                           ; DE = ppqn
    ld a, (var_smf_file.tempo+2)                         ; ACIX = tempo
    ld c, a                                              ; ...
    xor a                                                ; tempo is 24 bit value
    call div_acix_de                                     ; ACIX = tempo / ppqn
    or c                                                 ; if (ACIX > 0xffff) { DE = ACIX/256; AC = us_per_int/256 }; else { DE = IX; AC = us_per_int }
    ld hl, (var_device.us_per_int)                       ; ...
    jp z, .not_overflow                                  ; ...
.overflow:
    ld d, c : ld e, ixh                                  ; ...
    xor a : ld c, h                                      ; ...
    jp 1f                                                ; ...
.not_overflow:
    ld d, ixh : ld e, ixl                                ; ...
    ld a, h : ld c, l                                    ; ...
1:  call div_ac_de                                       ; AC = int_len_ms*1000 / (tempo/ppqn), HL = remainder
    ld (var_smf_file.ticks_per_int+1), a                 ; save
    ld a, c                                              ; ...
    ld (var_smf_file.ticks_per_int+0), a                 ; ...
    ld a, h : ld c, l : ld ix, 0                         ; ACIX = remainder * 65535 / (tempo/ppqn)
    call div_acix_de                                     ; ...
    ld (var_smf_file.ticks_per_int_fraction), ix         ; save
    ret                                                  ;


; OUT - F  - garbage
; OUT - BC - garbage
; OUT - HL - garbage
smf_next_int:
    ld hl, (var_smf_file.ticks_fraction)              ;
    ld bc, (var_smf_file.ticks_per_int_fraction)      ;
    add hl, bc                                        ;
    ld (var_smf_file.ticks_fraction), hl              ;
    ld hl, (var_smf_file.ticks+0)                     ;
    ld bc, (var_smf_file.ticks_per_int)               ;
    adc hl, bc                                        ;
    ld (var_smf_file.ticks+0), hl                     ;
    ret nc                                            ;
    ld hl, var_smf_file.ticks+2                       ;
    inc (hl)                                          ;
    ret nz                                            ;
    inc hl                                            ;
    inc (hl)                                          ;
    ret                                               ;


; IN  - HL - track position
; IN  - IY - pointer to smf_track_t
; OUT -  A - status byte
; OUT - BC - data len
; OUT - HL - next track position
; OUT -  F - garbage
; OUT - DE - garbage
smf_get_next_status:
.parse_status_byte:
    call file_get_next_byte                   ; A = byte
    bit 7, a                                  ; if this isn't status byte - reuse last one ("Running Status")
    jr nz, .is_meta_event                     ; ...
    ld a, h : or l                            ; rewind position by 1 (20-bit): borrow into hi if HL wraps
    jr nz, 1f                                 ; ...
    ld a, (var_file_pos_hi) : dec a : ld (var_file_pos_hi), a ; ...
1:  dec hl                                    ; ...
    ld a, (iy+smf_track_t.last_status)        ; reuse last status
.is_meta_event:
    cp #ff                                    ; A == 0xFF?
    jr nz, .is_sysex                          ; ... no
    ld a, (var_file_pos_hi)                   ; save position hi (restored with HL below)
    push af                                   ; ...
    push hl                                   ; save HL (position at cc)
    inc hl                                    ; "FF cc ll... dd..." - cc - command, ll - length, dd - data
    call smf_parse_varint                     ; DEBC = ll - length of dd, HL = position pointing to dd
    pop de                                    ; DE = position at cc ;XXX assume cc+ll length <= 0xffff
    or a                                      ; reset C flag
    sbc hl, de                                ; get length of cc and ll (HL = HL - DE - C flag)
    add hl, bc                                ; sum length of cc/ll and dd
    ld b, h : ld c, l                         ; BC = total data len
    ex hl, de                                 ; restore HL (position at cc)
    pop af                                    ; restore position hi to match HL
    ld (var_file_pos_hi), a                   ; ...
    ld a, #ff                                 ; restore status byte = 0xFF
    ret                                       ;
.is_sysex:
    cp #f0                                    ; check 0xF0 <= byte < 0xF8
    jr c, .is_note                            ; ...
    jr z, .is_sysex_yes                       ; ...
    cp #f8                                    ; ...
    jr nc, .eof                               ; ...
.is_sysex_yes:
    push af                                   ;
    call smf_parse_varint                     ;
    pop af                                    ;
    ret                                       ;
.is_note:
    ld (iy+smf_track_t.last_status), a        ;
    ld d, a                                   ;
    and #f0                                   ; "sssscccc" - s - status byte, c - channel number
    ld bc, 2                                  ;
    cp #90 : jr nz, 1f         : or d : ret   ; note on
1:  cp #80 : jr nz, 1f         : or d : ret   ; note off
1:  cp #a0 : jr nz, 1f         : or d : ret   ; key after-touch
1:  cp #b0 : jr nz, 1f         : or d : ret   ; control change
1:  cp #c0 : jr nz, 1f : dec c : or d : ret   ; program (patch) change
1:  cp #d0 : jr nz, 1f : dec c : or d : ret   ; channel after-touch (aka "channel pressure")
1:  cp #e0 : jr nz, 1f         : or d : ret   ; pitch wheel change
.eof:
1:  xor a                                     ; not valid command, set to zero
    ret                                       ;


; IN  - HL - track position
; IN  - IY - pointer to smf_track_t
; OUT -  F - C=1 when delay is going on; C=0 when delay is expired
; OUT -  F - Z=1 when no more data on this track; Z=0 when ok
; OUT -  A - status byte (only when F/C=0 and F/Z=0)
; OUT - BC - data len (only when F/C=0 and F/Z=0)
; OUT - HL - next track position
; OUT - DE - garbage
; OUT - IX - garbage
smf_process_track:
.check_delay:
    bit SMF_TRACK_FLAGS_DELAY, (iy+smf_track_t.flags) ;
    jr z, .check_end_of_track                         ;
    ld a, (var_smf_file.ticks+3)                      ;
    cp (iy+smf_track_t.next_tick+3)                   ;
    ret c                                             ;
    jr nz, .delay_expired                             ;
    ld a, (var_smf_file.ticks+2)                      ;
    cp (iy+smf_track_t.next_tick+2)                   ;
    ret c                                             ;
    jr nz, .delay_expired                             ;
    ld a, (var_smf_file.ticks+1)                      ;
    cp (iy+smf_track_t.next_tick+1)                   ;
    ret c                                             ;
    jp nz, .delay_expired                             ;
    ld a, (var_smf_file.ticks+0)                      ;
    cp (iy+smf_track_t.next_tick+0)                   ;
    ret c                                             ;
.delay_expired:
    res SMF_TRACK_FLAGS_DELAY, (iy+smf_track_t.flags) ;
.get_status:
    call smf_get_next_status                          ;
    or a                                              ; set Z flag if command is 0 (aka not valid)
    ret                                               ;
.check_end_of_track:                                  ; reached end of track? (20-bit position >= end), HL preserved
    ld a, (var_file_pos_hi)                           ; ...
    cp (iy+smf_track_t.end+2)                          ; pos_hi vs end_hi
    jr c, .set_delay                                  ; ... pos_hi < end_hi -> not yet
    jr nz, .end_of_track                              ; ... pos_hi > end_hi -> past end
    ld a, l                                           ; equal hi: compare low 16 (pos - end)
    sub (iy+smf_track_t.end+0)                          ; ...
    ld a, h                                           ; ...
    sbc (iy+smf_track_t.end+1)                          ; ... C set iff pos < end
    jr nc, .end_of_track                              ; ... pos >= end -> end of track
.set_delay:
    call smf_parse_varint                             ; DEBC = time delta (ticks count)
    ld a, b : or c : or d : or e                      ; check if delay == 0
    jp z, .get_status                                 ; ... if yes - process status command
    push hl                                           ; else - calculate and save delay
    ld l, (iy+smf_track_t.next_tick+0)                ; .. next_tick += ticks_count
    ld h, (iy+smf_track_t.next_tick+1)                ; ...
    add hl, bc                                        ; ...
    ld (iy+smf_track_t.next_tick+0), l                ; ...
    ld (iy+smf_track_t.next_tick+1), h                ; ...
    ld l, (iy+smf_track_t.next_tick+2)                ; ...
    ld h, (iy+smf_track_t.next_tick+3)                ; ...
    adc hl, de                                        ; ...
    ld (iy+smf_track_t.next_tick+2), l                ; ...
    ld (iy+smf_track_t.next_tick+3), h                ; ...
    set SMF_TRACK_FLAGS_DELAY, (iy+smf_track_t.flags) ; ... set delay flag
    pop hl                                            ; ...
    jp .check_delay                                   ; delay may be already expired
.end_of_track:
    res SMF_TRACK_FLAGS_PLAY, (iy+smf_track_t.flags)  ; clear play flag
    ld a, (var_smf_file.num_tracks_play)              ; num_tracks_play--
    dec a                                             ; ...
    ld (var_smf_file.num_tracks_play), a              ; ...
    call player_set_tracks                            ; ...
    xor a                                             ; set Z flag
    ret                                               ;


; IN  - BC - data len
; IN  - HL - track position
; OUT - HL - next track position
; OUT - AF - garbage
; OUT - BC - garbage
; OUT - DE - garbage
; OUT - IX - garbage
smf_handle_meta:
    ld a, b                      ; if (len == 0) - exit
    or c                         ; ...
    ret z                        ; ...
    ld d, b : ld e, c            ; DE = data len
    call file_get_next_byte      ; A = cmd
    dec de                       ; ...
.tempo:
    cp #51                       ; tempo
    jr nz, .title                ; ...
    ld a, d                      ; len should == 4
    or a                         ; ...
    jr nz, .exit                 ; ...
    ld a, e                      ; ...
    cp 4                         ; ...
    jr nz, .exit                 ; ...
    call file_get_next_byte      ; skip ll (advances 20-bit position safely)
    dec de                       ; ...
    call file_get_next_byte      ; tempo = tt tt tt
    dec de                       ; ...
    ld (var_smf_file.tempo+2), a ; ... MIDI is big endian, Z80 is little endian
    call file_get_next_byte      ; ...
    dec de                       ; ...
    ld (var_smf_file.tempo+1), a ; ...
    call file_get_next_byte      ; ...
    dec de                       ; ...
    ld (var_smf_file.tempo+0), a ; ...
    push de                      ;
    push hl                      ;
    call smf_update_ticks_per_int;
    pop hl                       ;
    pop de                       ;
    jp .exit                     ;
.title:
    cp #03                       ; track title
    jr nz, .exit                 ; ...
    call file_get_next_byte      ; skip ll (advances 20-bit position safely)
    dec de                       ; ...
    ld a, (var_file_pos_hi)      ; save title-start hi (HL is restored by push/pop below)
    push af                      ; ...
    push de                      ;
    push hl                      ;
    call player_set_title        ; advances HL+hi (discarded)
    pop hl                       ;
    pop de                       ;
    pop af                       ; restore hi to match the restored HL
    ld (var_file_pos_hi), a      ; ...
    ; jp .exit                     ;
.exit:
    add hl, de                   ; next position += remaining data len (20-bit)
    ret nc                       ; ...
    ld a, (var_file_pos_hi)      ; ... carry into bits 16..19 on 64 KB crossing
    inc a                        ; ...
    ld (var_file_pos_hi), a      ; ...
    ret                          ;
