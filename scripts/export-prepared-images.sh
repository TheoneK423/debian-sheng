#!/usr/bin/env bash
set -euo pipefail

test -s rootfs.img
test -n "${ROOTFS_MOUNT:-}"
if mountpoint -q "$ROOTFS_MOUNT"; then
  echo 'Root filesystem is still mounted; refusing to export.' >&2
  exit 1
fi

check_ext4() {
  local status=0
  sudo e2fsck -pf rootfs.img || status=$?
  if (( status > 1 )); then
    echo "e2fsck failed: $status" >&2
    exit "$status"
  fi
}

mkdir -p prepared-images
sha256sum ./*.deb > prepared-images/PACKAGE_SHA256SUMS
check_ext4
sudo mount -o loop rootfs.img "$ROOTFS_MOUNT"
grep -q '^PARTLABEL=linux / ' "$ROOTFS_MOUNT/etc/fstab"
sudo chroot "$ROOTFS_MOUNT" dpkg-query -W > prepared-images/packages.txt
sudo cp "$ROOTFS_MOUNT/etc/os-release" prepared-images/os-release
sudo cp "$ROOTFS_MOUNT/etc/fstab" prepared-images/fstab-dual.txt
sudo umount "$ROOTFS_MOUNT"

export_mode() {
  local mode=$1
  check_ext4
  sha256sum rootfs.img | sed "s|rootfs.img|rootfs-${mode}.raw.img|" >> prepared-images/RAW_SHA256SUMS
  img2simg rootfs.img "rootfs-${mode}.sparse.img"
  local available logical
  available=$(df -PB1 . | awk 'NR==2 {print $4}')
  logical=$(stat -c %s rootfs.img)
  if (( available < logical + 536870912 )); then
    echo 'Insufficient runner disk space for the verified sparse roundtrip.' >&2
    exit 1
  fi
  simg2img "rootfs-${mode}.sparse.img" roundtrip.img
  cmp rootfs.img roundtrip.img
  rm roundtrip.img
  sha256sum "rootfs-${mode}.sparse.img" >> prepared-images/SPARSE_SHA256SUMS
  zstd -T0 -5 --rm "rootfs-${mode}.sparse.img" -o "prepared-images/rootfs-${mode}.sparse.img.zst"
}

export_mode dual
sudo mount -o loop rootfs.img "$ROOTFS_MOUNT"
sudo sed -i 's/^PARTLABEL=linux \/ /PARTLABEL=userdata \/ /' "$ROOTFS_MOUNT/etc/fstab"
grep -q '^PARTLABEL=userdata / ' "$ROOTFS_MOUNT/etc/fstab"
sudo cp "$ROOTFS_MOUNT/etc/fstab" prepared-images/fstab-single.txt
sudo umount "$ROOTFS_MOUNT"
export_mode single

gh release download 7.3.4 --repo ianchb/sm8550-mainline \
  --pattern boot_sheng_singleboot.img --pattern boot_sheng_dualboot.img \
  --dir prepared-images
(
  cd prepared-images
  echo '13d45dc0c31aab989df8a7c551c1801241e244539f0ae65378811496e7e32d12  boot_sheng_singleboot.img' | sha256sum -c -
  echo 'a1a308ae09b8a3134cde7fec1fd83775757bb64c34cd47c6b6ecb2c6260b973d  boot_sheng_dualboot.img' | sha256sum -c -
  sha256sum *.zst *.img > SHA256SUMS
)
python3 - <<'PY'
import json, os, pathlib, subprocess
record = {
    'upstream_repository': 'ianchb/debian-sheng',
    'upstream_commit': 'a93aaa1eff77a2bf0552b8dafaa35c1e0880317f',
    'build_commit': subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(),
    'run_url': f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
    'kernel_release': '7.3.4',
    'suite': 'trixie', 'desktop': 'KDE Plasma', 'language': 'zh_CN.UTF-8',
    'image_logical_bytes': pathlib.Path('rootfs.img').stat().st_size,
    'modes': {'single': 'userdata', 'dual': 'linux'},
    'notes': [
        'xiaomi-pen-status prebuilt omitted because Qt_6.10 is unavailable on Trixie',
        'Touchscreen/stylus input daemon remains installed',
        'Chinese fonts, Fcitx5 Chinese addons and Maliit keyboard added',
        'Sparse roundtrip compared byte-for-byte with each raw ext4 image',
        'Password logins locked; user sets a password locally on the first desktop login; SSH disabled',
        'Not tested on the physical tablet'
    ],
}
pathlib.Path('prepared-images/build-info.json').write_text(json.dumps(record, indent=2)+'\n')
PY
