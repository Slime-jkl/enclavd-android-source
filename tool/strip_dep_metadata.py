#!/usr/bin/env python3
"""Remove AGP's 'Dependency metadata' pair (block ID 0x504b4453, 'PKDS') from
an APK's signing block.

Why this is safe:
- v2/v3 APK signatures cover the ZIP ENTRIES, not the signing block itself,
  so removing a pair does NOT invalidate the signature.
- ZIP entries and the central directory are byte-identical afterwards (the
  CD merely shifts earlier; the EOCD cd_offset is updated), so F-Droid's
  content comparison is unaffected.

Must run on BOTH sides (Actions fdroid job + the pipe's fdroid_build.sh) so
the two APKs stay byte-identical.

Usage: strip_dep_metadata.py <apk> [<out.apk>]   (in-place when no out given)
"""
import struct
import sys

BLOCK_ID = 0x504B4453  # 'PKDS' — Dependency metadata
MAGIC = b"\x41\x50\x4b\x20\x53\x69\x67\x20\x42\x6c\x6f\x63\x6b\x20\x34\x32"
EOCD_SIG = b"\x50\x4b\x05\x06"


def strip(path: str, out: str | None = None) -> int:
    data = bytearray(open(path, "rb").read())
    eocd = data.rfind(EOCD_SIG)
    if eocd == -1:
        raise SystemExit(f"{path}: no EOCD — not an APK/zip?")
    cd_offset = struct.unpack_from("<I", data, eocd + 16)[0]
    magic_pos = data.rfind(MAGIC, 0, cd_offset)
    if magic_pos == -1:
        print(f"{path}: no APK signing block, nothing to strip")
        if out and out != path:
            open(out, "wb").write(bytes(data))
        return 0
    size_pos = magic_pos - 8
    block_size = struct.unpack_from("<Q", data, size_pos)[0]
    # block_size counts pairs + second size field + magic (16). The first size
    # field sits block_size - 24 bytes of pairs/etc before the second size
    # field, i.e. size_pos - block_size + 16 (verified against real APKs).
    block_start = size_pos - block_size + 16
    if struct.unpack_from("<Q", data, block_start)[0] != block_size:
        # fallback probe: some signers omit the 16-byte entry tail
        for delta in (-8, 8, 16):
            if struct.unpack_from("<Q", data, block_start + delta)[0] == block_size:
                block_start += delta
                break
        else:
            raise SystemExit(f"{path}: could not locate APK signing block start")

    removed_total = 0
    pairs = bytearray()
    pos = block_start + 8
    while pos < size_pos:
        if pos + 12 > size_pos:
            # trailing junk (cannot be a standard pair) — drop it
            removed_total += size_pos - pos
            print(f"{path}: removed {size_pos - pos} trailing bytes")
            break
        length, pair_id = struct.unpack_from("<QI", data, pos)
        nxt = pos + 12 + length
        if nxt > size_pos:
            # non-standard framing (AGP's dependency-metadata entry: 4 zero
            # bytes then the id) — the entry spans to the second size field
            eid = struct.unpack_from("<I", data, pos + 4)[0] if pos + 4 < size_pos else 0
            removed_total += size_pos - pos
            print(f"{path}: removed non-standard block entry 0x{eid:08x} ({size_pos - pos} bytes)")
            break
        if pair_id == BLOCK_ID:
            removed_total += 12 + length
            print(f"{path}: removed pair 0x{pair_id:08x} ({length} bytes)")
        else:
            pairs += data[pos : pos + 12 + length]
        pos = nxt

    if removed_total == 0:
        print(f"{path}: no Dependency metadata pair found, nothing to strip")
        if out and out != path:
            open(out, "wb").write(bytes(data))
        return 0

    new_size = block_size - removed_total
    new_block = (
        struct.pack("<Q", new_size)
        + bytes(pairs)
        + struct.pack("<Q", new_size)
        + MAGIC
    )
    new_file = bytearray(data[:block_start]) + new_block + data[cd_offset:]

    # patch the EOCD cd_offset (EOCD now sits at the tail; its offset field
    # must point at the shifted central directory)
    new_eocd = new_file.rfind(EOCD_SIG)
    new_cd_offset = cd_offset - removed_total
    struct.pack_into("<I", new_file, new_eocd + 16, new_cd_offset)

    target = out if out else path
    open(target, "wb").write(bytes(new_file))
    print(f"{path}: stripped {removed_total} bytes -> {target}")
    return removed_total


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        raise SystemExit("usage: strip_dep_metadata.py <apk> [<out.apk>]")
    strip(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else None)
