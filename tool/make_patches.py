"""Makes the small update patches that let the app download only what changed.

  python3 tool/make_patches.py NEW_APK BUILD_NUMBER OUT_DIR

For the last few releases it creates  OUT_DIR/DROM-patch-from-<old>.bin  (old
APK -> new APK) and OUT_DIR/DROM.sha256 (hash of the new APK). Every patch is
checked by rebuilding the APK from it before it is kept; with the same Dart
code the app uses for the newest one (tool/verify_patch.dart).

Needs: pip install bsdiff4, the gh CLI (GH_TOKEN) and dart.
The app falls back to the full APK whenever a patch is missing or fails, so
this script must never be able to publish a bad patch."""
import bz2
import hashlib
import os
import re
import struct
import subprocess
import sys
import zlib

KEEP = 3  # patches for the last N releases
MAX_RATIO = 0.7  # a patch bigger than this share of the APK is not worth it


def offtin(b):
    """bsdiff's sign + magnitude little endian integer."""
    y = b[7] & 0x7F
    for i in range(6, -1, -1):
        y = y * 256 + b[i]
    return -y if b[7] & 0x80 else y


def to_drom(patch: bytes) -> bytes:
    """BSDIFF40 (bzip2) -> DROMPAT1 (zlib, plain int64): fast to read in Dart."""
    if patch[:8] != b"BSDIFF40":
        raise ValueError("not a BSDIFF40 patch")
    clen, dlen, newsize = (offtin(patch[8:16]), offtin(patch[16:24]),
                           offtin(patch[24:32]))
    ctrl = bz2.decompress(patch[32:32 + clen])
    diff = bz2.decompress(patch[32 + clen:32 + clen + dlen])
    extra = bz2.decompress(patch[32 + clen + dlen:])
    out_ctrl = bytearray()
    for i in range(0, len(ctrl), 24):
        out_ctrl += struct.pack("<qqq", offtin(ctrl[i:i + 8]),
                                offtin(ctrl[i + 8:i + 16]),
                                offtin(ctrl[i + 16:i + 24]))
    zc, zd, ze = (zlib.compress(bytes(x), 9) for x in (out_ctrl, diff, extra))
    return (b"DROMPAT1" + struct.pack("<qqqq", newsize, len(zc), len(zd), len(ze))
            + zc + zd + ze)


def apply_drom(old: bytes, patch: bytes) -> bytes:
    """Reference implementation (same steps as lib/patcher.dart)."""
    newsize, zc, zd, ze = struct.unpack("<qqqq", patch[8:40])
    assert 40 + zc + zd + ze == len(patch)
    ctrl = zlib.decompress(patch[40:40 + zc])
    diff = zlib.decompress(patch[40 + zc:40 + zc + zd])
    extra = zlib.decompress(patch[40 + zc + zd:])
    out = bytearray()
    oldpos = diffpos = extrapos = 0
    for i in range(0, len(ctrl), 24):
        add, copy, seek = struct.unpack("<qqq", ctrl[i:i + 24])
        for k in range(add):
            o = oldpos + k
            ob = old[o] if 0 <= o < len(old) else 0
            out.append((diff[diffpos + k] + ob) & 0xFF)
        diffpos += add
        oldpos += add
        out += extra[extrapos:extrapos + copy]
        extrapos += copy
        oldpos += seek
    assert len(out) == newsize
    return bytes(out)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sh(*cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, **kw)


def previous_builds(build):
    repo = os.environ["GITHUB_REPOSITORY"]
    res = sh("gh", "api", f"repos/{repo}/releases", "--paginate", "-q",
             ".[].tag_name", capture_output=True)
    nums = sorted({int(m.group(1)) for t in res.stdout.split()
                   if (m := re.fullmatch(r"build-(\d+)", t))
                   and int(m.group(1)) < build}, reverse=True)
    return nums[:KEEP]


def main():
    import bsdiff4

    new_apk, build, out_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    os.makedirs(out_dir, exist_ok=True)
    new_sha = sha256_file(new_apk)
    new_size = os.path.getsize(new_apk)
    made = 0
    for n, old in enumerate(previous_builds(build)):
        old_apk = f"/tmp/DROM-old-{old}.apk"
        try:
            sh("gh", "release", "download", f"build-{old}", "-p", "*.apk",  # DROM.apk on old releases, SDM.apk on new ones
               "-O", old_apk, "--clobber")
            raw = bsdiff4.diff(open(old_apk, "rb").read(),
                               open(new_apk, "rb").read())
            patch = to_drom(raw)
            if len(patch) > MAX_RATIO * new_size:
                print(f"build {old}: patch {len(patch)} B is too big, skipped")
                continue
            # 1) reference check in Python
            if hashlib.sha256(apply_drom(open(old_apk, "rb").read(),
                                         patch)).hexdigest() != new_sha:
                raise RuntimeError("python check failed")
            path = os.path.join(out_dir, f"DROM-patch-from-{old}.bin")
            with open(path, "wb") as f:
                f.write(patch)
            # 2) the newest one is also rebuilt with the real Dart code
            if n == 0:
                sh("dart", "run", "tool/verify_patch.dart", old_apk, path, new_sha)
            print(f"build {old}: patch {len(patch) / 1e6:.1f} MB "
                  f"(full APK {new_size / 1e6:.1f} MB)")
            made += 1
        except Exception as e:  # never publish a patch that was not verified
            print(f"build {old}: no patch ({e})")
            p = os.path.join(out_dir, f"DROM-patch-from-{old}.bin")
            if os.path.exists(p):
                os.remove(p)
        finally:
            if os.path.exists(old_apk):
                os.remove(old_apk)
    if made:
        with open(os.path.join(out_dir, "DROM.sha256"), "w") as f:
            f.write(new_sha + "\n")
    print(f"{made} patch(es) ready")


if __name__ == "__main__":
    main()
