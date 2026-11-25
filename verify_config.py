"""Reject unexpected configuration changes before compiling the kernel."""

import json
from pathlib import Path
import sys


def parse(path):
    values = {}
    for line in Path(path).read_text().splitlines():
        if line.startswith("CONFIG_"):
            key, value = line.split("=", 1)
            values[key] = value
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            values[line[2:-11]] = "n"
    return values


base = Path(__file__).resolve().parent
before = parse(base / "inputs/stock.config")
after = parse(sys.argv[1])
required = [
    "SYSVIPC", "POSIX_MQUEUE", "IPC_NS", "PID_NS", "DEVTMPFS", "USER_NS",
    "MODVERSIONS", "MODULE_SIG", "MODULE_SIG_PROTECT", "CFI_CLANG",
    "LTO_CLANG_FULL", "CGROUP_FREEZER", "MEMCG",
]
for name in required:
    if after.get(f"CONFIG_{name}") != "y":
        raise RuntimeError(f"Required configuration is missing: {name}")
for name in ["CGROUP_PIDS", "CFS_BANDWIDTH", "CFI_PERMISSIVE", "KSU", "KERNELSU"]:
    if after.get(f"CONFIG_{name}", "n") != "n":
        raise RuntimeError(f"Unexpected option: {name}")
allowed = {
    "CONFIG_SYSVIPC", "CONFIG_POSIX_MQUEUE", "CONFIG_POSIX_MQUEUE_SYSCTL",
    "CONFIG_SYSVIPC_SYSCTL", "CONFIG_IPC_NS", "CONFIG_PID_NS", "CONFIG_DEVTMPFS",
    "CONFIG_USER_NS", "CONFIG_DEVTMPFS_MOUNT", "CONFIG_DEVTMPFS_SAFE",
    "CONFIG_SYSTEM_TRUSTED_KEYS", "CONFIG_UNUSED_KSYMS_WHITELIST",
    "CONFIG_PAHOLE_VERSION",
}
differences = {
    key: {"before": before.get(key, "n"), "after": after.get(key, "n")}
    for key in sorted(before.keys() | after.keys())
    if before.get(key, "n") != after.get(key, "n")
}
unexpected = sorted(set(differences) - allowed)
if unexpected:
    raise RuntimeError(f"Unexpected kernel options changed: {unexpected}")
report = {
    "status": "configuration_matches_reviewed_scope",
    "changed": differences,
    "module_signature_protection_retained": True,
    "root_framework_added": False,
    "runtime_compatibility_verified": False,
}
Path(sys.argv[2]).write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
