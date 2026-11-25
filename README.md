# sheng DroidSpaces kernel preparation

This branch builds a reviewable kernel only. It does not flash a device.

The base is the exact public common-kernel commit used by the tablet's current
5.15.178 kernel: `android13-5.15-2025-03_r8`. The compiler is the matching
Android Clang r450784e (14.0.7). See `sources.json` for pinned commits and hashes.

The build starts from the running GKI configuration and enables SYSVIPC,
POSIX message queues, PID/IPC/user namespaces and devtmpfs. One pinned
DroidSpaces ABI-padding patch keeps the SYSVIPC fields within reserved
`task_struct` space. CPU bandwidth and process-count controllers remain disabled.

The existing Magisk installation lives in init_boot and is not replaced.
No KernelSU, SukiSU, ReSukiSU, overclock or scheduler patches are included.

Module version checks, CFI, LTO and GKI module signature protection remain
enabled. ThinLTO replaces the stock full LTO to reduce build memory pressure;
the two option changes are included in the configuration review. ThinLTO link
workers are limited to two. The stock kernel's public module-verification certificate is retained
as an additional trusted certificate. No private signing keys are uploaded or
included in the build artifact.

The public certificate does not validate every captured stock module signature.
In particular, the original system zram/zsmalloc modules are already loaded with
the unsigned/unverified taint on the unchanged running kernel. Retaining the
original certificate preserves the original trust anchor; it does not claim to
repair those existing signatures or prove runtime compatibility.

The workflow saves its configuration review before compilation. The build logs
memory usage and linker process statistics every minute and includes those logs
with the final artifact. A stopped build is not treated as a usable kernel.

Before using any output:

1. Compare all required live vendor/system-module CRCs with the new Module.symvers.
2. Inspect the final configuration diff and task_struct layout.
3. Package the kernel inside a copy of the captured boot image.
4. Preserve the unchanged init_boot, vendor_boot, DTBO and original boot backup.
5. Obtain authorization for the specific boot test or flash operation.

Device images, module binaries and private configuration backups stay on the
local computer. They are not part of this branch or the cloud build inputs.
