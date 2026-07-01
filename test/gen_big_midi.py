#!/usr/bin/env python3
# Generate a valid, large multi-track (SMF format 1) MIDI file to exercise the
# >64KB file support of zx-midiplayer (20-bit file position, bank crossing,
# multi-track merge past the 64KB boundary).
#
# Usage: python3 gen_big_midi.py out.mid [target_kb] [num_tracks]
# Default: ~192 KB, 8 channel tracks + 1 conductor track.
import sys, struct

def vlq(n):
    b = [n & 0x7f]
    n >>= 7
    while n:
        b.append((n & 0x7f) | 0x80)
        n >>= 7
    return bytes(reversed(b))

def chunk(cid, data):
    return cid + struct.pack(">I", len(data)) + data

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "big.mid"
    target = int(sys.argv[2]) * 1024 if len(sys.argv) > 2 else 192 * 1024
    ntr = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    ppqn = 96

    # conductor track: tempo + time signature
    cond = bytearray()
    cond += vlq(0) + bytes([0xff, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])      # 4/4
    cond += vlq(0) + bytes([0xff, 0x51, 0x03, 0x07, 0xa1, 0x20])            # 500000 us/qn
    cond += vlq(0) + bytes([0xff, 0x2f, 0x00])
    tracks = [chunk(b"MTrk", bytes(cond))]

    per = max(1, (target // ntr))
    for t in range(ntr):
        ch = t & 0x0f
        ev = bytearray()
        ev += vlq(0) + bytes([0xff, 0x21, 0x01, 0x00])                      # port 0
        ev += vlq(0) + bytes([0xc0 | ch, (t * 5) & 0x7f])                   # program change
        note = 48 + (t % 12)
        while len(ev) < per:
            ev += vlq(0)   + bytes([0x90 | ch, note, 0x64])                # note on
            ev += vlq(48)  + bytes([0x80 | ch, note, 0x40])                # note off
            note += 1
            if note > 84:
                note = 48 + (t % 12)
        ev += vlq(0) + bytes([0xff, 0x2f, 0x00])
        tracks.append(chunk(b"MTrk", bytes(ev)))

    hdr = chunk(b"MThd", struct.pack(">HHH", 1, len(tracks), ppqn))
    blob = hdr + b"".join(tracks)
    with open(out, "wb") as f:
        f.write(blob)
    print(f"wrote {out}: {len(blob)} bytes ({len(blob)/1024:.1f} KB), "
          f"format 1, {len(tracks)} tracks, ppqn {ppqn}")

if __name__ == "__main__":
    main()
