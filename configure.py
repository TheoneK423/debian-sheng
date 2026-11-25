"""Apply minimal container options to the captured GKI configuration."""

import configparser
import hashlib
import json
from pathlib import Path
import subprocess
import sys


base = Path(__file__).resolve().parent
source = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
lock = json.loads((base / "sources.json").read_text())
stock = (base / "inputs/stock.config").read_bytes()
if hashlib.sha256(stock).hexdigest() != lock["stock_config_sha256"]:
    raise RuntimeError("Stock configuration does not match the pinned input")
patch = base / "patches" / lock["patch_filename"]
if hashlib.sha256(patch.read_bytes()).hexdigest() != lock["patch_sha256"]:
    raise RuntimeError("ABI patch hash mismatch")
subprocess.run(["git", "-C", str(source), "apply", "--check", str(patch)], check=True)
subprocess.run(["git", "-C", str(source), "apply", str(patch)], check=True)
output.mkdir(parents=True, exist_ok=True)
(output / ".config").write_bytes(stock)
(source / "stock-public-cert.pem").write_bytes(
    (base / "inputs/stock-public-cert.pem").read_bytes()
)

symbols = set()
for symbol_file in sorted((source / "android").glob("abi_gki_aarch64*")):
    if symbol_file.suffix or not symbol_file.is_file():
        continue
    parser = configparser.ConfigParser(
        allow_no_value=True, strict=False, interpolation=None
    )
    parser.optionxform = str
    parser.read_string(symbol_file.read_text())
    for section in parser.sections():
        symbols.update(parser.options(section))
if len(symbols) < 1000:
    raise RuntimeError("Incomplete public GKI symbol allowlist")
allowlist = output / "abi_symbols.raw"
allowlist.write_text("\n".join(sorted(symbols)) + "\n")
(source / ".scmversion").write_text(
    "-android13-8-00021-g6f2f96be86b9-ab13729987-droidspaces1\n"
)
config = [str(source / "scripts/config"), "--file", str(output / ".config")]
for option in [
    "SYSVIPC", "POSIX_MQUEUE", "IPC_NS", "PID_NS",
    "DEVTMPFS", "USER_NS",
]:
    subprocess.run(config + ["--enable", option], check=True)
subprocess.run(config + ["--disable", "LTO_CLANG_FULL"], check=True)
subprocess.run(config + ["--enable", "LTO_CLANG_THIN"], check=True)
subprocess.run(
    config + ["--set-str", "SYSTEM_TRUSTED_KEYS", "stock-public-cert.pem"],
    check=True,
)
subprocess.run(
    config + ["--set-str", "UNUSED_KSYMS_WHITELIST", str(allowlist)],
    check=True,
)
print(f"Applied one IPC ABI patch; generated {len(symbols)} public GKI symbols")
