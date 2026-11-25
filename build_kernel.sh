#!/usr/bin/env bash
set -euo pipefail

phase="${1:-all}"
case "$phase" in all|prepare|build) ;; *) exit 2 ;; esac
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
if [[ "$phase" != "build" ]]; then
    python3 "$inputs/configure.py" "$common" "$out"
fi

export KBUILD_BUILD_USER=milinux
export KBUILD_BUILD_HOST=sheng-kernel-prep
export KBUILD_BUILD_TIMESTAMP="Wed Jul 2 02:41:59 UTC 2025"
make_args=(
    -C "$common" "O=$out" ARCH=arm64 LLVM=1 LLVM_IAS=1
    HOSTCC=clang HOSTCXX=clang++ HOSTLDFLAGS=-fuse-ld=lld
    KCFLAGS=-D__ANDROID_COMMON_KERNEL__
    "LD=ld.lld --thinlto-jobs=${KERNEL_LINK_JOBS:-2}"
)
if [[ "$phase" != "build" ]]; then
    make "${make_args[@]}" olddefconfig
fi
cp "$out/.config" "$dist/kernel.config"
cp "$inputs/sources.json" "$dist/sources.json"
python3 "$inputs/verify_config.py" "$out/.config" "$dist/config-review.json"
if [[ "$phase" == "prepare" ]]; then
    exit 0
fi

(
    while true; do
        {
            printf '\n[build resources %s]\n' "$(date -u +%FT%TZ)"
            free -m
            ps -eo pid,ppid,comm,etime,pcpu,rss --sort=-rss | sed -n '1,9p'
            for entry in memory.current memory.max memory.swap.max memory.events; do
                if [[ -r "/sys/fs/cgroup/$entry" ]]; then
                    printf '%s: ' "$entry"
                    cat "/sys/fs/cgroup/$entry"
                fi
            done
        } | tee -a "$dist/resources.log"
        sleep 60
    done
) &
monitor=$!
stop_monitor() {
    kill "$monitor" 2>/dev/null || true
    wait "$monitor" 2>/dev/null || true
}
trap stop_monitor EXIT
/usr/bin/time -v make "${make_args[@]}" "-j${KERNEL_JOBS:-4}" \
    Image Image.gz modules 2>&1 | tee "$dist/build.log"
stop_monitor
trap - EXIT

cp "$out/arch/arm64/boot/Image" "$dist/Image"
cp "$out/arch/arm64/boot/Image.gz" "$dist/Image.gz"
cp "$out/Module.symvers" "$dist/Module.symvers"
cp "$out/.config" "$dist/kernel.config"
cp "$out/include/config/kernel.release" "$dist/kernel.release"
cp "$inputs/sources.json" "$dist/sources.json"
cp "$inputs/inputs/stock-public-cert.pem" "$dist/stock-public-cert.pem"
pahole -C task_struct "$out/vmlinux" > "$dist/task_struct.txt"
openssl x509 -in "$out/certs/signing_key.x509" -inform DER -out "$dist/build-public-cert.pem"
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
