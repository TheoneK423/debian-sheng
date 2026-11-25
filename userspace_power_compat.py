"""Keep Android power management unchanged when Droidspaces starts or stops."""

import hashlib
import json
from pathlib import Path
import sys

COMMIT = "cdadb9eb5d0f86aacffff60776333e6f6b73a30a"
ORIGINAL = "313b2b92150a6e8f09225bcc746fa737a793ab4a282d3e367f31e178982a3370"
PATCHED = "2f26c3b9a0a7feafd6ed3dc9ea175e2a068851f6518ea6a10b5bc539089cc988"
REPLACEMENT = """void android_optimizations(int enable) {
  /* Root-owned containers leave app cgroups; keep Android's idle policy intact. */
  (void)enable;
}

"""


def main():
    source = Path(sys.argv[1]) / "src/android/android.c"
    original = source.read_bytes()
    if hashlib.sha256(original).hexdigest() != ORIGINAL:
        raise RuntimeError("Upstream source differs from the pinned release")
    text = original.decode("utf-8")
    start = text.index("void android_optimizations(int enable) {")
    end = text.index("/* Data partition remount", start)
    patched = (text[:start] + REPLACEMENT + text[end:]).encode("utf-8")
    if hashlib.sha256(patched).hexdigest() != PATCHED:
        raise RuntimeError("Patch differs from the reviewed function replacement")
    source.write_bytes(patched)
    destination = Path("dist/userspace-power")
    destination.mkdir(parents=True, exist_ok=True)
    receipt = {
        "upstream_repository": "ravindu644/Droidspaces-OSS",
        "upstream_commit": COMMIT,
        "upstream_version": "7.2.0",
        "source_file": "src/android/android.c",
        "original_sha256": ORIGINAL,
        "patched_sha256": PATCHED,
        "change": "Make android_optimizations a no-op on both start and stop",
        "preserved": [
            "Android Doze policy", "DeviceConfig synchronization",
            "host phantom process limit",
        ],
        "compiler_archive_sha256":
            "03ae51af722af0dcffea0fc9eefb872a2a4e0a59300b612b1bff8b716404a8a1",
    }
    (destination / "build-info.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8"
    )
    print("Pinned source verified; only android_optimizations replaced.")


if __name__ == "__main__":
    main()
