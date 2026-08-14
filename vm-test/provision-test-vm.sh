#!/usr/bin/env bash
#
# provision-test-vm.sh — sets up a Fedora Silverblue 44 VM for testing the
# whole Bazzite->Silverblue migration toolkit, visible in GNOME Boxes (not
# just virt-manager), before touching real hardware.
#
# Why this can appear in Boxes at all: Boxes uses libvirt's qemu:///session
# connection (per-user, not qemu:///system) — confirmed by checking how
# Boxes itself reports failures ("Make sure virsh -c qemu:///session ...").
# A VM created with virt-install against that same connection shows up in
# Boxes' own machine list.
#
# VERIFICATION NOTE: installed the real libvirt/virt-install stack in my own
# environment and actually ran this — not just eyeballed against docs.
# `create --dry-run` produced real, valid libvirt domain XML (confirmed UEFI
# firmware, both disks correctly attached — the 40GB primary and the 20GB
# virtio backup-testing disk, SPICE graphics, user-mode networking, even a
# TPM device auto-added). The snapshot/restore commands' argument parsing
# was also confirmed against a real virsh binary. What I could NOT verify:
# an actual full VM boot (would need a real ISO and significant runtime —
# out of scope for this environment) and whether it shows up in Boxes' GUI
# specifically (would need a live Boxes instance) — the qemu:///session
# connection detail is the documented mechanism for that, not something I
# could click-and-confirm myself. Run `create --dry-run` yourself first
# anyway, same as this note recommends — cheap, and confirms it matches
# your actual hardware/libvirt version before the real thing.
#
# Usage:
#   ./provision-test-vm.sh iso          Download + GPG/checksum-verify the
#                                        current Fedora Silverblue 44 ISO
#   ./provision-test-vm.sh create --dry-run   Print the VM definition only
#   ./provision-test-vm.sh create             Actually create the VM
#   ./provision-test-vm.sh snapshot <name>    Snapshot current VM state
#   ./provision-test-vm.sh restore <name>     Roll back to a snapshot
#   ./provision-test-vm.sh list-snapshots

set -uo pipefail

VMNAME="silverblue-test"
WORKDIR="$HOME/vm-test"
FEDORA_VERSION=44
ISO_DIR="$WORKDIR/iso"
DISK_DIR="$HOME/.local/share/gnome-boxes/images"  # Boxes' conventional location
BACKUP_DISK="$WORKDIR/test-backup-drive.qcow2"

mkdir -p "$WORKDIR" "$ISO_DIR" "$DISK_DIR"

say() { echo -e "$*"; }

cmd_iso() {
  local base_url="https://download.fedoraproject.org/pub/fedora/linux/releases/${FEDORA_VERSION}/Silverblue/x86_64/iso"

  say "Looking up the current Silverblue ${FEDORA_VERSION} respin..."
  local listing
  listing="$(curl -sL "${base_url}/")"

  local iso_name checksum_name
  iso_name="$(echo "$listing" | grep -oE "Fedora-Silverblue-ostree-x86_64-${FEDORA_VERSION}[0-9.-]*\.iso" | head -1)"
  checksum_name="$(echo "$listing" | grep -oE "Fedora-Silverblue-${FEDORA_VERSION}[0-9.-]*-x86_64-CHECKSUM" | head -1)"

  if [[ -z "$iso_name" || -z "$checksum_name" ]]; then
    say "Couldn't auto-detect the current filename from the directory listing."
    say "Browse it yourself: ${base_url}/"
    say "and download + verify manually — the commands below show the pattern."
    return 1
  fi

  say "Found: $iso_name"
  cd "$ISO_DIR" || exit 1

  if [[ ! -f "$iso_name" ]]; then
    curl -Lo "$iso_name" "${base_url}/${iso_name}"
  else
    say "Already downloaded: $ISO_DIR/$iso_name"
  fi

  curl -Lo "$checksum_name" "${base_url}/${checksum_name}"
  curl -Lo fedora.gpg https://fedoraproject.org/fedora.gpg

  gpg --import fedora.gpg 2>/dev/null
  say "\n--- GPG signature check ---"
  gpg --verify-files "$checksum_name" 2>&1 || say "(gpg verify failed or gpg not installed — sha256 check below still matters)"

  say "\n--- Checksum check ---"
  sha256sum -c "$checksum_name" --ignore-missing 2>&1 | grep -i "$iso_name"

  say "\nIf that printed 'OK', the ISO is verified: $ISO_DIR/$iso_name"
}

cmd_create() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" ]] && dry_run=1

  local iso_path
  iso_path="$(find "$ISO_DIR" -name '*.iso' 2>/dev/null | head -1)"
  if [[ -z "$iso_path" ]]; then
    say "No ISO found in $ISO_DIR — run './provision-test-vm.sh iso' first."
    exit 1
  fi

  # Second disk specifically for testing backup-setup's LUKS+restic flow
  # without touching anything that matters — attach, format, encrypt this
  # exactly like you'd test the real external backup drive.
  if [[ ! -f "$BACKUP_DISK" ]]; then
    qemu-img create -f qcow2 "$BACKUP_DISK" 20G
  fi

  local args=(
    --connect qemu:///session
    --name "$VMNAME"
    --memory 8192
    --vcpus 4
    --cpu host-passthrough
    --disk "path=${DISK_DIR}/${VMNAME}.qcow2,size=40,format=qcow2"
    --disk "path=${BACKUP_DISK},format=qcow2,bus=virtio"
    --cdrom "$iso_path"
    --os-variant detect=on,require=off
    --boot uefi
    --graphics spice
    --video virtio
    --network user
    --sound default
  )

  if [[ $dry_run -eq 1 ]]; then
    say "DRY RUN — printing the VM definition, creating nothing:\n"
    virt-install "${args[@]}" --dry-run --print-xml
    say "\nLooks right? Re-run without --dry-run to actually create it."
    return 0
  fi

  virt-install "${args[@]}"
  say "\nCreated. It should now show up in GNOME Boxes' machine list — open Boxes to"
  say "confirm before doing anything else. If it doesn't appear, run:"
  say "  virsh --connect qemu:///session list --all"
  say "to confirm libvirt itself sees it even if Boxes' UI hasn't refreshed."
}

cmd_snapshot() {
  local name="${1:?snapshot name required}"
  virsh --connect qemu:///session snapshot-create-as "$VMNAME" "$name" \
    "Snapshot before: $name" --atomic
  say "Snapshotted as '$name'. Test the risky step now — restore if it goes wrong:"
  say "  ./provision-test-vm.sh restore $name"
}

cmd_restore() {
  local name="${1:?snapshot name required}"
  virsh --connect qemu:///session snapshot-revert "$VMNAME" "$name"
  say "Reverted to '$name'."
}

cmd_list_snapshots() {
  virsh --connect qemu:///session snapshot-list "$VMNAME"
}

case "${1:-}" in
  iso)             cmd_iso ;;
  create)          shift; cmd_create "${1:-}" ;;
  snapshot)        shift; cmd_snapshot "${1:-}" ;;
  restore)         shift; cmd_restore "${1:-}" ;;
  list-snapshots)  cmd_list_snapshots ;;
  *)
    sed -n '2,20p' "$0"
    exit 1
    ;;
esac
