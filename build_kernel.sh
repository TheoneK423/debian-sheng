#!/usr/bin/env bash
set -euo pipefail

inputs="$(cd "$(dirname "$0")" && pwd)"
work="${KERNEL_WORK_DIR:-$PWD/kernel-work}"
mkdir -p "$work"
work="$(cd "$work" && pwd)"
common="$work/common"
toolchain="$work/clang"
out="$work/out"
dist="$work/dist"
mkdir -p "$dist"

readarray -t pins < <(python3 - "$inputs/sources.json" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
for key in ["kernel_repository", "kernel_commit", "clang_repository",
            "clang_commit", "clang_directory"]:
    print(lock[key])
PY
)

if [[ ! -d "$common/.git" ]]; then
    git init "$common"
    git -C "$common" remote add origin "${pins[0]}"
    git -C "$common" fetch --depth=1 origin "${pins[1]}"
    git -C "$common" checkout --detach FETCH_HEAD
fi
test "$(git -C "$common" rev-parse HEAD)" = "${pins[1]}"
if [[ ! -d "$toolchain/.git" ]]; then
    git init "$toolchain"
    git -C "$toolchain" remote add origin "${pins[2]}"
    git -C "$toolchain" sparse-checkout init --cone
    git -C "$toolchain" sparse-checkout set "${pins[4]}"
    git -C "$toolchain" fetch --depth=1 --filter=blob:none origin "${pins[3]}"
    git -C "$toolchain" checkout --detach FETCH_HEAD
fi
test "$(git -C "$toolchain" rev-parse HEAD)" = "${pins[3]}"
export PATH="$toolchain/${pins[4]}/bin:$PATH"
clang --version
python3 "$inputs/configure.py" "$common" "$out"

export KBUILD_BUILD_USER=milinux
export KBUILD_BUILD_HOST=sheng-kernel-prep
export KBUILD_BUILD_TIMESTAMP="Wed Jul 2 02:41:59 UTC 2025"
make_args=(
    -C "$common" "O=$out" ARCH=arm64 LLVM=1 LLVM_IAS=1
    HOSTCC=clang HOSTCXX=clang++ HOSTLDFLAGS=-fuse-ld=lld
)
make "${make_args[@]}" olddefconfig
cp "$out/.config" "$dist/kernel.config"
python3 "$inputs/verify_config.py" "$out/.config" "$dist/config-review.json"
make "${make_args[@]}" "-j${KERNEL_JOBS:-4}" Image Image.gz modules

cp "$out/arch/arm64/boot/Image" "$dist/Image"
cp "$out/arch/arm64/boot/Image.gz" "$dist/Image.gz"
cp "$out/Module.symvers" "$dist/Module.symvers"
cp "$out/.config" "$dist/kernel.config"
cp "$out/include/config/kernel.release" "$dist/kernel.release"
cp "$inputs/sources.json" "$dist/sources.json"
cp "$inputs/inputs/stock-public-cert.pem" "$dist/stock-public-cert.pem"
pahole -C task_struct "$out/vmlinux" > "$dist/task_struct.txt"
openssl x509 -in "$common/certs/signing_key.x509" -inform DER -out "$dist/build-public-cert.pem"
python3 - "$dist" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = {}
for path in sorted(root.iterdir()):
    if path.is_file() and path.name != "sha256.json":
        files[path.name] = {"bytes": path.stat().st_size,
                            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
(root / "sha256.json").write_text(json.dumps(files, indent=2) + "\n")
PY
echo "Kernel build complete. Device compatibility audit and boot packaging remain."
