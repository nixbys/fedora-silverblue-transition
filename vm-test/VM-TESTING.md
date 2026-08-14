# Testing the migration in a VM before touching real hardware

Covers Phase 1 of TRANSITION-PLAN.md. Uses `provision-test-vm.sh` to build a
throwaway Fedora Silverblue 44 VM visible in GNOME Boxes, then walks through
what to actually test in it — and, just as importantly, what a VM genuinely
can't tell you, so you don't mistake a clean VM run for full confidence.

## Setup

```bash
cd vm-test
./provision-test-vm.sh iso              # download + GPG/checksum-verify the ISO
./provision-test-vm.sh create --dry-run # print the VM definition, create nothing
# read the XML output — sanity check disk sizes, UEFI firmware, network type
./provision-test-vm.sh create           # actually create it
```

Open GNOME Boxes — the VM should be in the list. Boot it, run through Anaconda
exactly like Phase 2 of the plan (**enable LUKS encryption here too** — the
whole point is testing the real flow, and `status`'s disk-encryption check is
worth confirming actually works before you rely on it for real). Use a simple
test passphrase; this VM gets thrown away.

Once installed and booted, get the toolkit onto the VM the same way you'd
maintain it for real — clone whatever repo holds `setup-silverblue.sh` and
`image/Containerfile`:

```bash
git clone <your-repo-url> ~/silverblue-toolkit
cd ~/silverblue-toolkit
```

## Snapshot before anything risky

This is the actual value of testing in a VM over testing on real hardware —
cheap, instant rollback. Snapshot before any step you might want to retry:

```bash
./provision-test-vm.sh snapshot before-base
# ... run ./setup-silverblue.sh base inside the VM, reboot, see what happens ...
# didn't like it? from the host:
./provision-test-vm.sh restore before-base
```

Reasonable checkpoints: before `base`, before `harden`, before `bootc switch`
(if testing the declarative image path), before `backup-setup`'s LUKS step.

## What's fully testable here

- **`base`** — RPM Fusion, codec swaps, GSConnect/AppIndicator layering,
  restic/git/lshw/distrobox install. All of it works identically in a VM.
- **`apps`** — every Flatpak installs and runs normally. Steam/Lutris will
  install fine; obviously don't expect real gaming performance from a VM.
- **`webapps`** — GNOME Web installs, and the "Install as Web App" flow for
  Discord/Element works the same as on real hardware.
- **`harden`** — almost all of it. SELinux checks, kernel sysctl, SSH
  hardening, DNS-over-TLS, Firefox hardening, auditd, fail2ban, container
  hardening all behave identically. Firewalld's base drop-zone setup works
  too. (See the exception below for USBGuard specifically.)
- **`firewall-extras`, `firefox-extensions`, `dns-mullvad`** — all pure
  config-file/policy writes, identical in a VM. `dns-mullvad` is a genuinely
  good thing to test here — you can confirm DNS actually resolves through
  Mullvad (`resolvectl status`) without risking your real network setup.
- **`protonvpn`, `protonpass`** — the app installs and sign-in flow work
  fine. VPN *connection* will work too (it's just network traffic), though
  there's no meaningful killswitch test without a second network path to
  compare against.
- **`dev`** — toolbox creation and the whole toolchain install (gcc, PHP,
  Go, Java, etc.) work identically.
- **`backup-setup`** — genuinely well-suited to VM testing. The second
  virtio disk `provision-test-vm.sh` attaches is exactly for this: format
  and LUKS-encrypt it with GNOME Disks inside the VM, then run
  `backup-setup` against it for real. You can verify the whole restic
  init → backup → systemd timer flow without touching a real drive.
- **The `bootc switch` path** — if you're testing `image/Containerfile`,
  this VM is actually the *right* place to do it, not just an acceptable
  one. Build the image (on the host or in CI), push it somewhere reachable,
  and `bootc switch` the VM to it. Confirms the whole declarative path
  before you point real hardware at it.
- **`status`** — run it at every stage; this is your primary signal for
  whether a given step actually landed.

## What a VM genuinely can't tell you

Be honest with yourself about these rather than treating a clean VM run as
full confidence:

- **USBGuard (`harden` section 8)** — its policy is built from whatever's
  plugged in *right now*. A VM has no real USB devices to allowlist. You can
  confirm the section runs without erroring, but not that your actual
  controllers/YubiKey/capture gear get handled correctly — that only proves
  out on real hardware with everything actually plugged in first.
- **AMD-specific GPU behavior** — `davincibox`'s ROCm detection, the
  mesa-va/vdpau-freeworld hardware video acceleration, and any real
  DaVinci Resolve performance. Boxes' virtual GPU (virtio-gpu/virgl) isn't
  your RDNA card; this whole path needs real hardware.
- **GSConnect pairing** — needs an actual phone on the same network. You can
  confirm the extension enables and shows up in Quick Settings, not that
  pairing itself works.
- **Secure Boot / GRUB password** — the VM's UEFI firmware (OVMF) isn't your
  real motherboard's. `status`'s Secure Boot check will report *something*,
  but it's testing OVMF's Secure Boot state, not your actual hardware's.
- **Proton VPN's killswitch under real network conditions**, Steam Remote
  Play across your actual LAN, YubiKey-anything, and OBS capturing a real
  game window at real framerates.

None of these are reasons to skip the VM pass — everything above the line
*is* worth catching here rather than on real hardware. Just don't let a
clean VM run stand in for the hardware-dependent pieces; Phase 5's burn-in
period on real hardware alongside Bazzite still matters for exactly these.
