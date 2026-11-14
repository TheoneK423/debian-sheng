#!/usr/bin/env bash
set -euo pipefail
test -n "${ROOTFS_MOUNT:-}"
sudo install -D -m 0755 scripts/first-login-setup "$ROOTFS_MOUNT/usr/local/sbin/milinux-initial-setup"
sudo mkdir -p "$ROOTFS_MOUNT/etc/sudoers.d" "$ROOTFS_MOUNT/var/lib/milinux" "$ROOTFS_MOUNT/etc/xdg/autostart"
printf '%s\n' 'debian ALL=(root) NOPASSWD: /usr/local/sbin/milinux-initial-setup' | \
  sudo tee "$ROOTFS_MOUNT/etc/sudoers.d/milinux-initial-setup" >/dev/null
sudo chmod 0440 "$ROOTFS_MOUNT/etc/sudoers.d/milinux-initial-setup"
sudo touch "$ROOTFS_MOUNT/var/lib/milinux/needs-password"
sudo tee "$ROOTFS_MOUNT/etc/xdg/autostart/milinux-initial-setup.desktop" >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Set your Debian password
Name[zh_CN]=设置 Debian 登录密码
Exec=konsole -e sudo -n /usr/local/sbin/milinux-initial-setup
TryExec=konsole
Terminal=false
X-KDE-autostart-after=panel
EOF
sudo chroot "$ROOTFS_MOUNT" visudo -cf /etc/sudoers.d/milinux-initial-setup
sudo chroot "$ROOTFS_MOUNT" systemctl disable ssh.service
if [[ -e "$ROOTFS_MOUNT/usr/lib/systemd/system/ssh.socket" || -e "$ROOTFS_MOUNT/lib/systemd/system/ssh.socket" ]]; then
  sudo chroot "$ROOTFS_MOUNT" systemctl disable ssh.socket
fi
test "$(sudo chroot "$ROOTFS_MOUNT" passwd -S root | awk '{print $2}')" = L
test "$(sudo chroot "$ROOTFS_MOUNT" passwd -S debian | awk '{print $2}')" = L
