#!/bin/sh
# boot-void.sh — the boot chain in the Void (quickshell/CLAUDE.md, "Design language"):
#   firmware → Limine (a black menu: SELECT SYSTEM) → Plymouth (SYSTEM BOOT, the hairline
#   growing with the boot) → SDDM (sddm-void.sh: SYSTEM LOGIN) → the shell; and back down
#   through the shell's power exit and Plymouth (SYSTEM SHUTDOWN / REBOOTING), laid out alike.
#
#   sudo sh boot-void.sh           install (shows the plan and asks once)
#   sudo sh boot-void.sh --update  bring an install up to date with this folder: the pictures,
#                                  the Plymouth theme (into every initramfs), Limine's look
#   sudo sh boot-void.sh --art     redraw the pictures only (after changing [void] or fonts)
#   sudo sh boot-void.sh --label NAME  what the firmware's boot menu calls Limine (default
#                                  "Limine"; the entry is recreated under the new name)
#   sudo sh boot-void.sh --drop-grub   take GRUB out of the firmware's boot menu (its kernels
#                                  go stale with the first update after the switch)
#   sudo sh boot-void.sh --undo    GRUB first again, the initramfs as it was, no splash
#
# In order:
#   1. a snapper snapshot, and copies of what it changes in /var/backups/boot-void-<time>/
#      (mkinitcpio.conf, /boot/EFI, /boot/limine.conf, `efibootmgr -v`)
#   2. /etc/default/limine: this kernel command line + splash; a fallback initramfs for
#      linux-cachyos; Limine also as the firmware's fallback loader (\EFI\BOOT\BOOTX64.EFI on
#      this ESP — what a firmware that lost its boot entries starts)
#   3. pacman: limine, limine-mkinitcpio-hook (Limine's entries on every kernel update; it
#      registers Limine first in the UEFI boot order), limine-snapper-sync (snapshots in the
#      menu), plymouth
#   4. mkinitcpio: i915 first (the laptop panel hangs off the iGPU: Plymouth draws there),
#      plymouth after systemd, sd-btrfs-overlayfs (a read-only snapshot boots with an overlay)
#   5. the pictures (boot-void/gen-art.py), the Plymouth theme, /boot/limine.conf's look,
#      then every initramfs and entry rebuilt, and Windows (on its own ESP) added.
#      limine-entry-tool rewrites the config's global section from its own template on
#      every write, so the look is a block that /etc/boot/hooks/post.d/80-boot-void-look
#      (boot-void/limine-look) puts back after each one, and at boot
#   6. the boot-order guard: Limine back in front at each boot (Windows updates move theirs)
#   7. repairs without a USB: Limine's Recovery folder (kept by the same hook) has
#      · Rescue console — the real system, single user, no desktop, opening void-rescue
#        (roll back / rebuild boot / last boot's errors / network / disk check / shell)
#      · Emergency shell — the initramfs's root shell for a root that won't mount, with
#        btrfs, lsblk and a note (the boot-void-rescue mkinitcpio hook)
#      and the snapshots (CachyOS > Snapshots, limine-snapper-sync) to go back to
#
# GRUB stays installed, behind Limine and Windows in the boot order; its copies of the
# kernels in /boot stop being refreshed at the first kernel update (Limine's hook replaces
# mkinitcpio's), so the rescue paths are Limine's: the fallback initramfs, linux-zen, the
# snapshots — and `E` at the menu edits an entry's command line (remove `splash` there if
# Plymouth ever misbehaves).
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/boot-void"
ESP=/boot
CONF=/etc/mkinitcpio.conf
say() { printf '\033[1m◆ %s\033[0m\n' "$*"; }

# ── the pictures ──
art() {
    tmp=$(mktemp -d)
    SUDO_USER="${SUDO_USER:-$USER}" python3 "$SRC/gen-art.py" "$tmp" >/dev/null
    install -d "$ESP/void" /usr/share/plymouth/themes/void
    install -m 644 "$tmp/limine/void.png" "$tmp/limine/void.f16" "$ESP/void/"
    install -m 644 "$tmp"/plymouth/*.png "$SRC/void.script" "$SRC/void.plymouth" /usr/share/plymouth/themes/void/
    rm -rf "$tmp"
}

# ── Limine's look: the block, the hook that keeps it, the guard that runs it at boot ──
look() {
    install -Dm 644 "$SRC/limine-head.conf" /usr/local/lib/boot-void/limine-head.conf
    install -Dm 755 "$SRC/limine-look" /usr/local/lib/boot-void/limine-look
    install -d /etc/boot/hooks/post.d
    ln -sf /usr/local/lib/boot-void/limine-look /etc/boot/hooks/post.d/80-boot-void-look
    install -Dm 755 "$SRC/bootorder-guard" /usr/local/lib/boot-void/bootorder-guard
    install -Dm 644 "$SRC/boot-void-bootorder.service" /etc/systemd/system/boot-void-bootorder.service
    systemctl daemon-reload
    /usr/local/lib/boot-void/limine-look
}

# ── repairs without a USB (step 7) ──
rescue() {
    install -Dm 755 "$SRC/void-rescue" /usr/local/lib/boot-void/void-rescue
    ln -sf /usr/local/lib/boot-void/void-rescue /usr/local/bin/void-rescue
    install -Dm 644 "$SRC/rescue-profile.sh" /etc/profile.d/boot-void-rescue.sh
    install -Dm 644 "$SRC/initcpio/install/boot-void-rescue" /etc/initcpio/install/boot-void-rescue
    install -d /etc/mkinitcpio.conf.d
    printf '# boot-void: repair tools and a note in the initramfs emergency shell\nHOOKS+=(boot-void-rescue)\n' \
        > /etc/mkinitcpio.conf.d/boot-void-rescue.conf
    # the menu's cards: voidbox, from the user running this (root has no ~/.local/bin)
    local home vb
    home=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    vb="$home/.local/bin/voidbox"
    [ -x "$vb" ] && install -Dm 755 "$vb" /usr/local/lib/boot-void/voidbox
    return 0
}

if [ "$1" = "--update" ]; then
    art
    plymouth-set-default-theme void
    look
    rescue
    limine-mkinitcpio          # the Plymouth theme and the rescue hook ride in the initramfs
    limine-snapper-sync || true    # the snapshots into the menu now, not at the next one
    /usr/local/lib/boot-void/limine-look
    say "boot chain up to date"
    grep -q '^# ── boot-void: the look' "$ESP/limine.conf" && say "Limine's look is in $ESP/limine.conf"
    grep -q '^/Recovery' "$ESP/limine.conf" && say "Recovery folder: Rescue console · Emergency shell"
    exit 0
fi

if [ "$1" = "--label" ]; then
    name=$2
    [ -n "$name" ] || { echo "usage: sudo sh $0 --label NAME"; exit 1; }
    # the guard finds the entry by its loader, not its name: install that one first
    install -Dm 755 "$SRC/bootorder-guard" /usr/local/lib/boot-void/bootorder-guard
    loader='\EFI\limine\limine_x64.efi'
    ids() { efibootmgr | grep -iF "$loader" | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p'; }
    old=$(ids)
    src=$(findmnt -n -o SOURCE "$ESP")
    disk=/dev/$(lsblk -no PKNAME "$src")
    part=$(cat "/sys/class/block/${src#/dev/}/partition")
    # the new entry first, the old one only once it's there (never without one)
    efibootmgr --create --disk "$disk" --part "$part" --label "$name" --loader "$loader" >/dev/null
    new=$(ids | grep -vxF "$old" | head -1)
    [ -n "$new" ] || { echo "couldn't create the entry; nothing removed"; exit 1; }
    for n in $old; do efibootmgr -b "$n" -B >/dev/null; done
    /usr/local/lib/boot-void/bootorder-guard >/dev/null || true
    say "the firmware's boot menu calls Limine \"$name\" now (Boot$new)"
    efibootmgr | sed -n '/^BootOrder/p; /^Boot[0-9A-Fa-f]\{4\}/p' | cut -c1-60
    exit 0
fi

if [ "$1" = "--drop-grub" ]; then
    for n in $(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Arch Linux[[:space:]].*grubx64\.efi.*/\1/p'); do
        efibootmgr -b "$n" -B >/dev/null && say "removed Boot$n (GRUB) from the firmware's boot menu"
    done
    systemctl disable --now grub-btrfsd.service 2>/dev/null && say "grub-btrfsd off (it rewrote grub.cfg on every snapshot)" || true
    echo "  GRUB's files stay in $ESP (EFI/ARCH, grub/). To remove GRUB altogether:"
    echo "  pacman -Rns grub grub-btrfs os-prober"
    echo "  (--undo can't go back to GRUB after this.)"
    exit 0
fi

if [ "$1" = "--art" ]; then
    art
    say "pictures redrawn (Limine: $ESP/void · Plymouth: /usr/share/plymouth/themes/void)"
    echo "  Plymouth's pictures live in the initramfs: run limine-mkinitcpio to carry them there."
    exit 0
fi

if [ "$1" = "--undo" ]; then
    last=$(ls -d /var/backups/boot-void-* 2>/dev/null | tail -1)
    grub=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Arch Linux[[:space:]].*/\1/p' | head -1)
    order=$(efibootmgr | sed -n 's/^BootOrder: *//p')
    if [ -n "$grub" ]; then
        rest=$(printf '%s\n' "$order" | tr ',' '\n' | grep -vix "$grub" | paste -sd, -)
        efibootmgr -o "$grub${rest:+,$rest}" >/dev/null && say "GRUB first in the boot order"
    fi
    systemctl disable --now boot-void-bootorder.service 2>/dev/null || true
    if [ -n "$last" ] && [ -f "$last/mkinitcpio.conf" ]; then
        cp "$last/mkinitcpio.conf" "$CONF"
        say "mkinitcpio.conf back from $last"
    fi
    /usr/bin/mkinitcpio -P
    say "done. Limine is still installed (its entry stays behind GRUB); to remove it:"
    echo "  pacman -R limine-snapper-sync limine-mkinitcpio-hook limine plymouth"
    exit 0
fi

# ── preflight ──
[ -d /sys/firmware/efi ] || { echo "not booted in UEFI mode"; exit 1; }
[ "$(findmnt -n -o FSTYPE "$ESP")" = vfat ] || { echo "$ESP is not the EFI system partition"; exit 1; }
if bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
    echo "Secure Boot is on: Limine isn't signed here. Turn it off, or sign with sbctl first."; exit 1
fi
free=$(df -m --output=avail "$ESP" | tail -1 | tr -d ' ')
[ "$free" -ge 500 ] || { echo "only ${free} MB free on $ESP (Limine's copies need ~500 MB)"; exit 1; }
cmdline=$(sed -e 's/BOOT_IMAGE=[^ ]* *//' -e 's/initrd=[^ ]* *//g' -e 's/ *splash//g' /proc/cmdline)
case "$cmdline" in *.snapshots*) echo "booted from a snapshot: boot the normal system first"; exit 1 ;; esac
win=$(efibootmgr -v | sed -n 's/^Boot[0-9A-Fa-f]\{4\}\*\{0,1\} Windows Boot Manager.*HD([0-9]*,GPT,\([0-9a-fA-F-]*\),.*/\1/p' | head -1)

cat <<EOF
The boot chain in the Void. This will:
  · snapshot root, back up to /var/backups/boot-void-<time>/
  · install limine, limine-mkinitcpio-hook, limine-snapper-sync, plymouth
  · make Limine the first boot entry and this ESP's fallback loader (GRUB stays, behind it)
  · kernel command line:  $cmdline splash
  · initramfs: i915 first, plymouth, sd-btrfs-overlayfs
  · Windows entry: ${win:-not found}
EOF
printf 'Go ahead? [y/N] '
read -r ok
case "$ok" in y|Y|yes) ;; *) echo "nothing changed"; exit 0 ;; esac

# 1 ── safety ──
bak=/var/backups/boot-void-$(date +%Y%m%d-%H%M)
mkdir -p "$bak"
cp "$CONF" "$bak/"
cp -r "$ESP/EFI" "$bak/EFI"
[ -f "$ESP/limine.conf" ] && cp "$ESP/limine.conf" "$bak/"
efibootmgr -v > "$bak/efibootmgr.txt"
if snapper -c root list >/dev/null 2>&1; then
    snapper -c root create -d "before boot-void" && say "snapshot: before boot-void"
fi
say "backups in $bak"

# 2 ── Limine's settings, before its hook first runs ──
cat > /etc/default/limine <<EOF
# Limine's entries (limine-entry-tool) — written by dotfiles/system/boot-void.sh.
# The command line is copied as it was under GRUB, plus splash (Plymouth).
ESP_PATH="$ESP"
KERNEL_CMDLINE[default]=$cmdline splash
MKINITCPIO_FALLBACK=linux-cachyos
ENABLE_LIMINE_FALLBACK=yes
FIND_BOOTLOADERS=no
BOOT_ORDER="*, *fallback, Snapshots"
ENABLE_VERIFICATION=yes
EOF
say "/etc/default/limine"

# 3 ── packages ──
pacman -S --needed --noconfirm limine limine-mkinitcpio-hook limine-snapper-sync plymouth

# 4 ── the initramfs ──
if ! grep -q '^MODULES=([^)]*\bi915\b' "$CONF"; then
    sed -i 's/^MODULES=(/MODULES=(i915 /' "$CONF"
fi
if ! grep -q '^HOOKS=([^)]*\bplymouth\b' "$CONF"; then
    sed -i 's/^\(HOOKS=([^)]*\bsystemd\b\)/\1 plymouth/' "$CONF"
fi
sed -i 's/\bgrub-btrfs-overlayfs\b/sd-btrfs-overlayfs/' "$CONF"
grep -q '^HOOKS=([^)]*\bsd-btrfs-overlayfs\b' "$CONF" || sed -i 's/^\(HOOKS=([^)]*\))/\1 sd-btrfs-overlayfs)/' "$CONF"
sed -i '/^HOOKS=/s/  */ /g' "$CONF"
say "$(grep '^MODULES=' "$CONF")"
say "$(grep '^HOOKS=' "$CONF")"

# 5 ── the look, the entries, Windows ──
art
plymouth-set-default-theme void
touch "$ESP/limine.conf"
look                       # the block now, and the hook that puts it back after every write
rescue
limine-mkinitcpio
limine-snapper-sync || true
if [ -n "$win" ] && ! grep -q '^/Windows' "$ESP/limine.conf"; then
    printf '\n/Windows\n    comment: Windows Boot Manager, on its own EFI partition\n    protocol: efi\n    path: guid(%s):/EFI/Microsoft/Boot/bootmgfw.efi\n' "$win" >> "$ESP/limine.conf"
fi

/usr/local/lib/boot-void/limine-look

# 6 ── the boot order, now and at every boot ──
systemctl enable boot-void-bootorder.service
/usr/local/lib/boot-void/bootorder-guard || true

say "done"
echo
efibootmgr | sed -n '/^BootOrder/p; /^Boot[0-9A-Fa-f]\{4\}/p' | cut -c1-60
echo
echo "Menu entries ($ESP/limine.conf):"
grep -E '^ *//?[^/ ]|^/' "$ESP/limine.conf" | sed 's/^/  /'
echo
df -h "$ESP" | tail -1 | awk '{print "ESP: " $3 " used of " $2}'
echo
echo "Reboot to see it. If the menu or the splash misbehaves: pick GRUB in the firmware's"
echo "boot menu (F12 on Acer), or press E at Limine's menu and remove 'splash'."
echo "Back to GRUB: sudo sh $0 --undo"
