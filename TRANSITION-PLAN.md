# Bazzite → Fedora Silverblue Transition Plan
Target: fully cut over by **December 2026**. GPU: **AMD** (mesa + ROCm, no proprietary driver needed — this simplifies almost everything below).

---

## Why this plan is structured this way

Your last attempt (Kinoite) died on DaVinci Resolve. That failure mode is now well understood in the Fedora/atomic community: Resolve's installer expects an old enterprise-Linux dependency set, and it collides badly with rpm-ostree's immutable `/usr`. The fix isn't "layer more packages" — it's **never let Resolve touch the host at all**. It runs in a disposable Podman/Distrobox container (via the `davincibox` project) that has the exact dependency set it wants, isolated from your base OS. If it breaks, you delete the container and rebuild it in five minutes — the host is untouched. That's the core design principle for this whole migration: **host stays minimal and hardened; everything volatile (games, Resolve, dev tooling) lives in Flatpaks or containers.**

---

## Phase 0 — Prep (this week)

- [ ] Confirm your final `progam-list.txt` is complete; anything not on it goes in `extras.conf` (template provided) as you think of it.
- [ ] Check your exact GPU model. `davincibox`'s ROCm path is reliable on **RX 6000-series and newer**. If you're on something older (RX 5000 or earlier), Resolve's OpenCL performance may be weaker — not a blocker, just set expectations.
- [ ] Back up before touching anything:
  - Steam: note which games use cloud saves vs. local-only saves (local saves in `~/.local/share/Steam/userdata` won't survive unless copied off).
  - DaVinci Resolve project files/media (wherever they live now).
  - OBS scenes/profiles: `~/.config/obs-studio`.
  - Browser profiles/bookmarks (Firefox sync handles this if you're signed in).
  - Standard Notes: use its built-in encrypted export.
  - Element (Matrix): back up your cross-signing/recovery key — without it you lose access to encrypted room history on a new device.
  - Thunderbird profile + note your Proton Mail Bridge account so you can re-pair it.
  - YubiKey: note which services you'll need to re-register/re-pair the key with (Bridge, any FIDO2 logins).
  - Any custom `ujust` commands or Bazzite-specific tweaks you rely on — write them down (see note below, this tool won't exist on stock Silverblue).

**`ujust`:** this is a Universal Blue (Bazzite/Bluefin/Aurora) tool, not a stock Fedora Silverblue one — vanilla Silverblue doesn't have it, and it was never added to the install list in `setup-silverblue.sh` (it only appeared in your original `progam-list.txt`, flagged early as a decision point, and is now dropped). If you ever want ublue's curated `just` recipes back, that means targeting Fedora Bluefin instead of vanilla Silverblue — not something this plan does.

---

## Phase 1 — Test in a VM (Weeks 1–2)

`vm-test/provision-test-vm.sh` builds a throwaway Fedora Silverblue 44 VM that
actually shows up in GNOME Boxes (still on Bazzite) — not just click-through
GUI instructions, a real script, verified against a live libvirt/virt-install
install (confirmed valid domain XML: UEFI firmware, both disks, SPICE
graphics — see the script's own header for exactly what was and wasn't
possible to verify in my environment). Full walkthrough, including a real
snapshot-before-risky-steps workflow and an honest breakdown of what a VM can
and can't tell you (USBGuard and AMD GPU-specific behavior need real
hardware, everything else genuinely doesn't) is in `vm-test/VM-TESTING.md`.

Quick start:
```bash
cd vm-test
./provision-test-vm.sh iso
./provision-test-vm.sh create --dry-run   # sanity-check before creating anything
./provision-test-vm.sh create
```
Anything that breaks, breaks here — not on your daily driver.

## Phase 2 — Install (Weeks 3–4)

- Download the latest **Fedora Linux 44 Silverblue** ISO (the July respin has three months of patches baked in, saving you a slow first update).
- Verify the checksum, write it to USB.
- **Enable disk encryption during the install — do not skip this.** In Anaconda's installation destination screen, check **"Encrypt my data"** (LUKS2) and set a strong passphrase you can actually remember; there's no recovery if you lose it. This has to happen at install time — it cannot be added afterward without wiping and reinstalling. Given the stated goal here is maximizing security, this is arguably the single highest-value control in this entire plan: it's what actually protects your data if the laptop is ever lost, stolen, or seized. Note it separately from your login password somewhere safe (not in Proton Pass alone — if the drive isn't decrypted yet at boot, you can't reach your password manager to look it up).
- **Recommendation:** don't wipe Bazzite immediately. If you have the disk space, install Silverblue alongside it (separate partition/drive) so you have an instant fallback for the first few weeks. If you only have one drive, a full backup image of the Bazzite install before wiping is the next best thing.

## Phase 3 — Base layer (Week 4)

Run:
```bash
./setup-silverblue.sh base
```
This layers RPM Fusion, swaps in freeworld codecs/VA-API drivers, enables OpenH264, and layers the small CLI/host-integration tools that can't be Flatpaks or don't fit a container: `git`/`lshw` (need real host access), `restic` (backup tool — kept host-side deliberately, see "Compartmentalization audit" below), GSConnect + AppIndicator (GNOME Shell extensions, can only run on the host), and the distrobox installer (needed for `davincibox`/`protonpass` specifically — `dev` uses toolbox instead, already pre-installed). **Requires one reboot** — rpm-ostree layered changes apply on next boot, not immediately.

## Phase 4 — Apps, hardening, extras (Week 5)

```bash
./setup-silverblue.sh apps      # all your Flatpaks + Steam/Lutris overrides + GSConnect
./setup-silverblue.sh webapps   # GNOME Web install steps for Discord/Element
./setup-silverblue.sh resolve   # clones davincibox, walks you through the Resolve container
./setup-silverblue.sh harden    # runs nixbys/fedora-hardening, then firewall/DNS/Firefox extras
./setup-silverblue.sh protonvpn # official Proton VPN app (two reboot-separated runs)
./setup-silverblue.sh protonpass # official Proton Pass desktop app (distrobox)
./setup-silverblue.sh dev       # dev/scripting toolbox (compilers, runtimes)
./setup-silverblue.sh backup-setup # restic + encrypted drive + systemd timer
./setup-silverblue.sh extras    # reads extras.conf for anything you add later
./setup-silverblue.sh status    # verify DNS/firewall/SELinux/USBGuard/GSConnect/etc landed correctly
```
Verify each piece as you go: launch Steam, install a Lutris game, open Resolve inside its container, confirm OBS can capture a game window, pair GSConnect with your phone (Android app is still called "KDE Connect" — that's expected). Run `status` after `harden` specifically — it's the fastest way to catch a declined prompt or failed step before you forget about it. After connecting Proton VPN for the first time, run `protonvpn-check` to confirm DNS is actually routing through it.

**One manual step `harden` prints as an action item but doesn't set for you: a GRUB password.** Section 6 only verifies Secure Boot is on; setting a bootloader password (so someone with physical access can't edit boot parameters to bypass your login) is a manual `grub2-setpassword` step. Worth doing once, early, since you won't remember to circle back to it later.

## Phase 5 — Burn-in (Weeks 5–8, through ~September)

Daily-drive Silverblue for editing, gaming, and browsing while Bazzite stays available as a fallback. Keep a running note of anything that misbehaves — most of it will trace back to a Flatpak sandbox permission (fixable in Flatseal) or a hardening section that's too strict for a specific peripheral (see the conflict table below).

## Phase 6 — Full cutover (~October)

Once you've gone 2–3 weeks without needing the Bazzite fallback, decommission it and reclaim the drive. This lands comfortably before Fedora 45 ships (~late October 2026), so your first in-place `rpm-ostree rebase` upgrade happens on a system you already trust.

## Phase 7 — Ongoing (through December and beyond)

- New game or app you want? Add one line to `extras.conf`, run `./setup-silverblue.sh extras`.
- Something a hardening section broke? `sudo ./fedora-harden.sh --rollback` undoes the last run; re-run with an adjusted `--skip` list.
- Fedora 45 lands in October — plan a routine `rpm-ostree rebase` a few weeks after release, once initial bug reports settle.

---

## Where hardening and gaming/creator work interact

I pulled the actual `fedora-harden.sh` source (not just the README) to check this properly. Good news: it's better-behaved than a typical hardening script — almost every risky action is gated behind a `confirm()` prompt, asked per-service or per-item, not applied as a blanket sweep. That means **you generally don't need to skip whole sections** — you just need to know which specific prompts to answer differently than the default-minded reader would, and where the auto-detection misses your setup because it's tuned for Bazzite/KDE.

| Section | What it actually does (from source) | What to watch for |
|---|---|---|
| 5 — firewalld | Sets zone default to `drop`, then *asks* about mDNS, KDE Connect (only if it detects a KDE session), and Steam Remote Play ports (only if it detects a Bazzite-style gaming spin) | Answer yes to the base drop-zone. On vanilla Silverblue+GNOME, the KDE Connect and Steam prompts **will not appear** — that detection is Bazzite/KDE-specific, not a "you said no" situation. `harden` in the script runs `firewall-extras` right after to add both automatically, so you don't lose them. |
| 8 — USBGuard | Explicitly warns you first, then generates an allowlist from *whatever's plugged in right now*, and only proceeds if you confirm | Plug in every controller, capture card, mic/interface, and your YubiKey **before** answering yes. Anything added later needs one command: `sudo usbguard allow-device <ID> --permanent` (find the ID with `sudo usbguard list-devices`). Not a reason to skip — just a reason to plug things in first. |
| 13 — Flatpak/Firejail | Firejail is offered as a fully optional install (its own yes/no prompt), and `firecfg` only wraps *native, non-Flatpak* binaries — it doesn't touch Flatpak apps at all | Since Steam, Lutris, and OBS are all Flatpaks in this setup, Firejail doesn't touch them either way. Answer the prompt however you like re: hardening non-Flatpak CLI tools. |
| 19 — Service cleanup | Asks individually about avahi, cups, cups-browsed, **bluetooth**, ModemManager, iSCSI, NFS, rpcbind, telnet/rsh/rlogin sockets | Say **no** specifically to the bluetooth prompt if you use any Bluetooth controller or headset. Everything else in that list is safe to disable for a gaming/editing desktop. |

Everything else (SELinux checks, SSH hardening, kernel sysctl, auditd, rkhunter/AIDE, container/Podman hardening, Firefox hardening, DNS-over-TLS, fail2ban) doesn't touch anything gaming- or Resolve-related and is safe to run as-is.

---

## Open trade-offs — not fixed, deliberately left for you to decide

- **Steam and Lutris have broad filesystem access** (`--filesystem=host`) per the note in Phase 4 above — narrow it once you know your actual game library paths. This is the one item here still genuinely open; everything else that used to be listed in this section got resolved in later turns and now has its own dedicated section instead of a summary here:
  - Proton VPN coverage (browser extension vs. full app) → see the Proton VPN bullet under "Notes on specific items," below
  - Proton Pass extension-only risk → see "Password manager," below
  - No backup strategy → see "Backup strategy," below

---

## Rating this setup, and what I changed as a result

Asked to rate the current state and improve where warranted. Rather than re-summarize what's already documented elsewhere in this file, here's specifically what a fresh critical pass found and fixed:

- **Real gap: `harden` and `resolve` git-pull scripts from GitHub and then run them with `sudo`, with zero review step in between.** For a setup built around "maximize security," blindly trusting whatever's on `main` at pull time is a genuine supply-chain gap — not fully closed here (no signature verification, no commit pinning, which would fight the goal of staying current), but `git_clone_or_update` now shows you the commit log of anything new since your last run *before* it gets executed with elevated privileges, so you're not flying blind.
- **Inconsistency: `resolve` was the only container-touching command not using the `container_exists` check** the redundancy pass added everywhere else, so it always re-printed the full first-time walkthrough even on a container you'd already set up. Fixed — it now gives you a one-line upgrade pointer instead on repeat runs.
- **Completeness gap: `status` checked a lot of things, but not disk encryption or Secure Boot** — the two controls this plan itself calls out as the highest-value ones in Phase 2. Added both, plus a heuristic GRUB password check. None of these can be *fixed* by the script (LUKS is install-time only; Secure Boot and GRUB password are BIOS/bootloader-level manual steps) — but they can at least be verified rather than just trusted.

---

## Stateless work system — yes, achievable, and committed to

This maps onto a real, established pattern: **bootc**. Instead of `base` and `protonvpn` running imperative `rpm-ostree install` commands against your live machine, the OS becomes a `Containerfile` — built in CI, from source you can read and diff, pushed to a registry, applied with one `bootc switch`. Confirmed this is a legitimate path for a *personal* single-machine setup, not just enterprise fleets — found real prior art doing exactly this (`htgar/bootc-personal-desktop`, a template repo built specifically for this use case; Fedora's own Discussion forum walking through the identical pattern in late 2025).

### What actually becomes stateless, and what genuinely can't

Be precise about this rather than oversell it — "stateless" applies to the **OS layer**, not to you:

| Becomes stateless (in the image, rebuilt by CI) | Stays state, by necessity |
|---|---|
| RPM Fusion, codecs, VA-API/VDPAU drivers | Your actual data — Resolve projects, game saves, notes (→ `backup-setup` already handles this) |
| GSConnect, AppIndicator, git, lshw, restic, distrobox | LUKS passphrase, Proton account, GRUB password — secrets have to live *somewhere* |
| Proton VPN (repo + app) | `fedora-hardening`'s interactive prompts — USBGuard's allowlist is built from whatever's plugged in *right now*; there's no correct answer to bake into an image built on a CI runner with no USB devices attached |
| | Flatpak app data, Firefox profile, GNOME extension enablement state — `/var`, never part of the ostree/bootc image by design regardless of this change |

That last row is worth being explicit about: **`apps`, `webapps`, `harden`, `firewall-extras`, `firefox-extensions`, `dns-mullvad`, `resolve`, `protonpass`, `dev`, and `backup-setup` all stay exactly as they are.** This isn't a partial implementation — it's the correct, permanent boundary. Anything writing to `/var` (Flatpak data, your home directory) or requiring live interaction with actual hardware can't be made stateless without becoming wrong.

### What I built and actually verified

- **`image/Containerfile`** — the declarative replacement for what `base` and `protonvpn` used to layer imperatively. Installed `podman` and `hadolint` in my own environment and actually linted it for real — not just eyeballed the syntax. Two fixes came out of that (missing `dnf clean all` per layer), and two warnings I deliberately didn't act on with reasons written directly in the file (version-pinning would freeze codec packages the moment they're written, defeating the point of a weekly rebuild; the multi-`RUN` structure is intentional for build-cache granularity, not an oversight).
- **Tried an actual `podman build`** against the real Fedora bootc base image to verify it builds, not just lints clean. Hit a sandbox restriction specific to container registries (`quay.io`/`docker.io` both blocked — a narrower allowlist than general HTTPS, evidently a deliberate guard against pulling arbitrary container images in this environment). Couldn't get past that here — **you should treat the first real build as the actual test**, via the checklist at the bottom of `build-image.yml`.
- **`image/build-image.yml`** — GitHub Actions workflow to build and push to GHCR on every Containerfile change, plus a weekly rebuild so RPM Fusion/codec/Proton VPN updates land even if you don't touch the repo. Valid YAML, and the action pattern matches the real templates found — but same honesty as above, I can't execute a GitHub Actions run myself.

### Migration path

1. Push `image/Containerfile` and `.github/workflows/build-image.yml` to a git repo (the same one holding `setup-silverblue.sh` is a reasonable choice — one source of truth for the whole system, declarative and imperative parts together).
2. Follow `build-image.yml`'s first-run checklist (Actions write permissions, GHCR package visibility) and watch the Actions tab.
3. On the Silverblue machine, **after** Phase 2's install + LUKS, **before** running `base`/`protonvpn`: `sudo bootc switch ghcr.io/<you>/silverblue-custom:latest`, reboot once. This replaces the old base→reboot→protonvpn→reboot→protonvpn→reboot dance with a single switch+reboot.
4. Run the rest of `setup-silverblue.sh` as documented in Phase 4 — `apps` onward is completely unaffected by this change.
5. `base` and `protonvpn` are still safe to run afterward if you want — every check in them is already idempotent (`rpm -q` guards throughout), so on a machine that already has these baked in, they just report "already present" and no-op. No script changes were needed for this to work correctly; it's a property the existing idempotency design already had.

### One real option not implemented: image signing

The custom-image examples I found (`guix-silverblue` in particular) sign their builds with cosign and enforce that signature on the client (`bootc switch --enforce-container-sigpolicy`), so a compromised registry can't silently serve a malicious image. This is a genuine additional security step matching this whole plan's stated goal — not implemented here because it requires generating and safeguarding a private signing key, which is a decision only you should make deliberately, not one I should make for you by default. If you want it: `cosign generate-key-pair`, commit `cosign.pub` to the repo, sign the image as a step in `build-image.yml`, then switch with `--enforce-container-sigpolicy`.

---

## Compartmentalization audit

You asked me to make sure everything is properly sorted by use case/category, and to genuinely evaluate — not reflexively assume — whether anything currently host-side would be better off in a container, and which container tool fits which job. Here's the full inventory and the reasoning per category, not just the new additions. (This section was dropped from an earlier revision due to a sync issue on my end — see the note in the toolbox-vs-distrobox section below for what happened and how I caught it.)

### Where things live and why

| Category | Lives in | Why not elsewhere |
|---|---|---|
| Codecs, VA-API/mesa drivers, RPM Fusion | Host (`rpm-ostree`) | System-wide media stack — every app that decodes video needs these to be at the OS level, not sandboxed to one container |
| GSConnect, AppIndicator | Host (`rpm-ostree`) | GNOME Shell extensions run *inside* the `gnome-shell` process itself — there's no container boundary that could contain them even in principle |
| Proton VPN | Host (`rpm-ostree`) | Needs kernel WireGuard, NetworkManager D-Bus, killswitch routing — host network stack access a container namespace can't provide |
| `git`, `lshw` | Host (`rpm-ostree`) | Used to `git clone` repos that then run `sudo` commands modifying host SELinux/sysctl/firewalld directly (fedora-hardening, davincibox setup) — these operate ON the host, so they have to run FROM the host |
| `restic` | Host (`rpm-ostree`) — **deliberately, see below** | |
| Firefox, Epiphany, Tor Browser, Boxes, Tweaks, Extension Manager, Thunderbird, Proton Mail Bridge, Steam, Lutris, Podman Desktop, GIMP, VLC, OBS, LibreOffice, Standard Notes, Flatseal, Gearlever, Audacity, RPi Imager, Yubico Authenticator | Flatpak | Official Flatpak builds exist for all of these with proper portal integration — distrobox/toolbox would mean rebuilding permission handling these already get for free |
| DaVinci Resolve | Distrobox (`davincibox`) | Custom OCI image, not plain Fedora — needs its own heavy ROCm/AV stack. Upstream project's own primary/recommended path (it does support toolbox as a documented alternative, but distrobox is what its README and maintainer recommend) |
| Proton Pass desktop | Distrobox (`protonpass`) | Needs `distrobox-export --app`'s automated `.desktop` integration — toolbox can run GUI apps, but has no equivalent automated host-grid export |
| Compilers, language runtimes, ShellCheck/shfmt | **Toolbox** (`dev`) | See the dedicated section below — this is the one place the tool choice itself was worth analyzing |

### Toolbox vs distrobox — the direct answer

Neither is universally better — they solve overlapping problems with different trade-offs, and which one's "right" depends on what the container needs to do:

| | Toolbox | Distrobox |
|---|---|---|
| Base images | Fedora only (matches host version by default) | Any OCI image — Ubuntu, Arch, Debian, Kali, custom images, anything |
| Pre-installed on Silverblue | **Yes** | No — this script installs it itself |
| GUI app → host desktop integration | Manual `.desktop` authoring only | `distrobox-export --app` — automated, one command |
| Maintainer | Red Hat / Fedora (official) | Community (89luca89) |
| Best fit | A clean Fedora CLI sandbox for dev packages, without touching the host | Anything needing a non-Fedora base, or GUI apps that need to show up in your app grid properly |

Checked this against real usage rather than reasoning in the abstract: davincibox's own README documents *both* as supported (`distrobox enter davincibox` or `toolbox run --container davincibox`), but its author's own write-up and the community consensus is explicit that distrobox is the primary, recommended path for it — more maturity for this exact use case, and better handling of GPU passthrough flags. That's staying as-is.

**What changed: `dev` is now a toolbox, not a distrobox.** It's pure Fedora, pure CLI, nothing that needs desktop integration — exactly toolbox's textbook case, and using it means zero new dependencies (it's already there) instead of relying on the distrobox installer this script runs. `protonpass` stays on distrobox specifically because its install flow depends on `distrobox-export --app`'s automated `.desktop` detection — toolbox has no equivalent, only manual authoring, which would've meant hand-writing that file instead of the current one-command export.

**One real trade-off worth knowing:** toolbox has no equivalent to `distrobox-export --bin` for putting a container binary on your host PATH — for CLI tools inside `dev`, you'll always need `toolbox run --container dev -- <tool>` or `toolbox enter dev` rather than running the tool bare. That's a minor, permanent inconvenience versus what distrobox would've offered, accepted in exchange for using the pre-installed, officially-supported tool for a job that doesn't need distrobox's extra capabilities.

**A note on how I caught the missing section above:** this is the second time in this conversation I've found my own working copy silently out of sync with what was actually delivered to you — the first was `cmd_dev` disappearing entirely, this time it was this whole audit section. Both times I caught it by diffing my working copy against the file in your outputs folder before trusting my own edits, which is now something I check any time a "that doesn't look right" moment comes up rather than only when directly prompted. Worth you knowing this happened, not just that it's fixed.

---

### The one thing I actually reconsidered: `restic`

This is the honest edge case. A single static Go binary with zero host integration requirements is *exactly* the profile that could go either way, and I want to be upfront that I didn't just default to "container it" — I weighed both:

- **For containerizing it:** consistent with keeping the host minimal; groups it with other CLI tooling.
- **For keeping it on the host (what I did):** it's invoked unattended by a `systemd --user` timer with no one watching. Routing that through a container adds a moving part — the container has to actually be up and reachable when the timer fires — to the one thing in this entire setup where reliability matters more than architectural tidiness. And the "host bloat" argument that justifies containerizing compilers doesn't really apply to a single static binary with no dependency tree; there's essentially nothing to bloat. Given backups are the thing you really don't want failing silently because a container didn't start in time, I kept it host-layered.

---

## Password manager: KeePassXC analysis, and why it's not being added

You asked me to analyze whether KeePassXC should be added given the earlier flagged risk (Proton Pass as a browser-extension-only vault means a Firefox compromise is a vault compromise), and to check whether Proton Pass has a native desktop app that would change that calculus.

**It does.** Proton Pass ships an official Linux desktop app (confirmed against Proton's own current site) — a standalone `.rpm`/`.deb` download, not a browser dependency. That directly resolves the original concern: the vault is now reachable from a separate process with its own local encrypted offline storage, independent of whether Firefox itself is compromised. Per your instruction, that closes the case for KeePassXC — it's not being added. Installed via `protonpass` (distrobox, not host-layered — a password manager doesn't need host network access, so it fits the container-first approach the rest of this plan uses).

**One honest residual gap, not acted on, just noted:** even with the desktop app, everything still lives inside one ecosystem tied to one account. If you're ever locked out of Proton itself (forgotten password with no recovery method set up, account dispute, Proton having an outage), there's no independent vault to fall back to. The practical mitigation — which doesn't require a second password manager — is Proton's own emergency recovery kit (a PDF with your account recovery phrase), which `protonpass` reminds you to store on the encrypted backup drive rather than inside Pass itself. If that residual gap ever bothers you enough to want a truly independent offline vault, KeePassXC remains a one-line addition to `extras.conf` — but that's your call to revisit later, not something I'm adding now.

### Using the desktop app and browser extension together

They're not two separate vaults — same account, same data, synced. The split is about *where* you reach for which:

| Task | Use |
|---|---|
| Logging into a website in Firefox | Browser extension — autofill works inline, no app-switching |
| Looking up a Wi-Fi password, API key, or database credential while working in a terminal | Desktop app — this is exactly the gap it was built to fill |
| Copying a credential into GIMP/OBS/a native app that isn't a browser | Desktop app |
| Everything else (Discord/Element webapps via GNOME Web, Steam) | Desktop app, since the browser extension only exists in Firefox |
| Generating/checking a new password | Either — same generator, same Pass Monitor breach checks |
| No internet connection | Both work — offline mode is supported on desktop, mobile, and browser extension |

Nothing to configure to make this work — installing the desktop app via `protonpass` doesn't change or duplicate anything about the extension `firefox-extensions` already installed. Sign into both with the same account and they share one vault automatically.

---

## Backup strategy

You already practice 3-2-1 and use Proton Drive as part of it — the gap is the *local* leg, since Proton Drive has no native Linux sync client (confirmed: Proton doesn't ship one, web app is genuinely the only supported access method on Linux right now). Here's how the pieces map:

| 3-2-1 requirement | This plan |
|---|---|
| 3 copies | Working files (SSD) + local encrypted backup (separate drive) + Proton Drive (cloud) |
| 2 different media | Internal SSD + external/second-drive encrypted backup |
| 1 offsite | Proton Drive |

### Local leg: `backup-setup` — restic to a LUKS-encrypted drive

I didn't script the drive partitioning/encryption itself — wiping the wrong block device is unrecoverable and I have no reliable way to confirm which device is safe to touch on your actual hardware. That's a guided manual step (GNOME Disks, LUKS2, ext4). Everything after that is scripted and safe to re-run:

- Layers `restic` (small static Go binary, minimal footprint — consistent with how `git`/`lshw` are handled)
- Initializes a restic repository on the encrypted drive, with its own repository password **separate from the LUKS passphrase** — deliberate defense in depth. If the drive is ever decrypted by someone else (lost while unlocked, cloned, whatever), the backup contents are still opaque without the second password.
- Generates `backup-home.sh` with a starting file list (Documents, Pictures, Videos, OBS config, Steam userdata/saves — not the games themselves, those are redownloadable) and a sane retention policy (7 daily / 4 weekly / 6 monthly snapshots, older ones pruned automatically)
- Generates real `systemd --user` service + timer units with your actual mount path baked in, so the timer safely no-ops if the drive isn't plugged in rather than erroring

Run `systemctl --user enable --now backup-home.timer` once and it runs daily on its own. Edit `~/silverblue-setup/backup-home.sh` any time to add paths specific to your setup — Resolve project directories, davincibox container exports, etc.

### Offsite leg: Proton Drive

Since you're already resigned to the web app being the only real option — that's correct, there's no gap to close there with a better native tool. I did check whether something better exists: `rclone` has a Proton Drive backend, which would let the offsite copy run on a timer the same way the local one does. **I'm not recommending it as your primary offsite mechanism, and here's why:** it's unofficial (Proton doesn't publish an API, so it's reverse-engineered), it's still marked Beta, and there was an active GitHub issue in late 2025 proposing to mark it *unsupported* entirely due to lack of a maintainer — it's since picked back up (a Proton engineer has been engaging with the project and there's been recent development activity as of a few months ago), but that history is enough that I wouldn't want it to be the only thing standing between you and your offsite copy. The web app upload, done manually or on whatever cadence you're comfortable with, is the boring and reliable choice here. If you want to experiment with `rclone`'s protondrive backend as a *supplementary* automation layer on top of (not instead of) manual web uploads, it's a one-line `extras.conf` addition (`rclone` under `[rpm-ostree]`) plus its own `rclone config` walkthrough — just don't make it load-bearing.

### `dev` toolchain, expanded: analyzed against fedora-hardening's own author's other repos

You asked me to look at nixbys's full GitHub profile and pull in whatever language/tool support their other repos actually need. GitHub's API rate-limited my automated lookup (shared IP pool in this environment), so rather than guess at the two repos I couldn't fully inspect, I went deep on the ones I *could* actually fetch and read — which is a more honest basis than a repo list with no detail:

- **`linavelt`** — Laravel 12 + PHP 8.2+, Composer, Node.js 22+, MariaDB, Podman Compose/quadlet deployment. Its own preflight script explicitly checks for GitHub CLI authentication.
- **`kaiden-engine`** — Python (46%) + ActionScript (42%) + PHP (5%) + Java (4%), with a `.sql` database dump and PHP login/registration scripts. This is an AS3-era game server emulator — structurally similar to what an AQW-style private server project would look like, which is a notable parallel to your own content niche even if it's not something you're building.
- **`kali-pdm-mcp-server`** — Go, an MCP server for Podman/Docker.
- Bio confirms OWASP Foundation affiliation, consistent with the security focus already evident in `fedora-hardening` itself.

Added to `dev`: `php`/`php-cli`/`composer`/`php-mysqlnd` (Laravel + MariaDB stack), `mariadb` (client, for that `.sql` dump and any MariaDB work), `golang`, `java-latest-openjdk` (the JVM piece of kaiden-engine), and `gh` (GitHub CLI, since linavelt's own tooling expects it). **Deliberately not added:** ActionScript/Flex SDK tooling (niche, not a standard Fedora package, not worth bundling unless you actually pursue an AS3 project) and any pentesting frameworks despite the clear security/Kali thread across the profile — that's a different risk category than build tooling, you didn't ask for it, and it doesn't match the defensive posture the rest of this plan is built around.

---

## Notes on specific items from your list

- **DNS**: switched from the hardening script's Quad9+Cloudflare default to **Mullvad's no-log DNS-over-TLS resolver** (`dns-mullvad` command), per your request after reviewing the privacyguides.org DNS page. Deliberately using Mullvad's *unfiltered* tier rather than its ad/malware-blocking tiers — those are known to break some streaming sites, and between uBlock Origin already handling ad/tracker blocking in-browser and your MAL-Sync/Animouto anime-tracking workflow depending on those streaming sites working, the filtered tiers would trade real breakage for marginal gain. Quad9 stays as the fallback resolver for provider diversity if Mullvad is ever unreachable.
- **Firefox extensions**: fedora-harden.sh's section 16 already force-installs uBlock Origin, LocalCDN, and Multi-Account Containers via a Firefox enterprise policy. Rather than risk that overwriting anything I add, `firefox-extensions` writes the full superset — those three plus **Proton Pass**, **Proton VPN**, **MAL-Sync**, and **Animouto** — and runs automatically right after `harden`, making it the authoritative version regardless of order. Slugs verified directly against addons.mozilla.org (`proton-pass`, `proton-vpn-firefox-extension`, `mal-sync`, `animouto`).
- **Discord & Element as web apps**: installed via **GNOME Web (Epiphany)**'s "Install as Web App" feature rather than a DIY Firefox-profile trick. Epiphany's web apps get a genuinely separate window identity/icon in the dock; a hacked-together Firefox profile launcher would just get grouped under Firefox. The install step itself is a GUI action (2 clicks) — not something worth faking through a shell script when the real thing is one menu click away and guaranteed to keep working across GNOME updates. `webapps` installs Epiphany and prints the exact steps.
- Everything else on your list stays as a native Flatpak — either it needs hardware/file access a webapp sandbox can't get (Yubico Authenticator, KDE Connect, OBS, Raspberry Pi Imager), or there's no meaningful web equivalent (GIMP, VLC, Audacity, LibreOffice, Lutris, Steam, Podman Desktop, Boxes, Tweaks/Extension Manager). Thunderbird, Proton Mail Bridge, and Standard Notes stay native per your explicit instruction, even though Standard Notes does have a web app.
- **KDE Connect → GSConnect**: switched, not just added alongside. GSConnect's own documentation states it flatly won't work if the KDE Connect desktop app is installed — they fight over the same port range. Beyond the incompatibility, GSConnect is also the more native choice for GNOME specifically: it's a GNOME Shell extension (not a separate Qt/Kirigami app), so you get a device icon and battery indicator directly in the top bar/quick-settings, plus Nautilus "send to phone" integration — rather than a foreign-feeling KDE app window. Layered via `rpm-ostree` in `base` (`gnome-shell-extension-gsconnect`, since Shell extensions can't be Flatpaks — they run inside gnome-shell itself), enabled automatically in `apps` post-reboot. Same firewall ports as before (`firewall-extras` already opens 1714-1764 tcp/udp — that was always for the KDE Connect *protocol*, not the app specifically, so nothing needed to change there). On your phone, the Android app is still called "KDE Connect" — that's fine, GSConnect only conflicts with the *desktop* app of that name.
- **Proton VPN (full app)**: added via `protonvpn` command. Proton doesn't officially distribute this as a Flatpak — official method is their own DNF repo, which on an atomic system means `rpm-ostree` layering in two reboot-separated steps (repo, then the app). This is the one deliberate exception to this whole plan's "keep the host minimal, put volatile stuff in containers/Flatpaks" philosophy — a VPN client needs host-level network stack access (kernel WireGuard, NetworkManager, killswitch routing) that no container can provide, so layering it is actually correct here, not a compromise. AppIndicator support (for the tray icon) is layered alongside GSConnect in `base` for the same reason — Shell extensions aren't Flatpak-able.
  - **On the Mullvad DNS question you asked earlier**: I looked at how Proton's own uninstall docs describe their app (it manages state through NetworkManager connection profiles like `pvpn-killswitch`), which means it should participate in systemd-resolved's normal per-link DNS priority — i.e., when connected, Proton's interface should automatically take over DNS ahead of the global Mullvad default, no revert needed. I didn't want to just assert that, so `protonvpn-check` actually verifies it post-connection by inspecting `resolvectl status` for which resolver is live. `dns-revert` still exists but is now a fallback for if that check shows a genuine leak, not a required pre-step.
- **Proton Mail Bridge**: no official Flatpak from Proton; there's a well-maintained *community* Flatpak (`ch.protonmail.protonmail-bridge`) used by this plan. Flagged as community-maintained, not Proton-official, in case that matters to you.
- **Artix Game Launcher**: ships only as an AppImage (`Artix_Games_Launcher-x86_64.AppImage`) — perfect fit for Gearlever, which is already on your list. The script downloads it; you integrate it with one click in Gearlever.
- **ujust**: removed — see Phase 0. Never present on vanilla Silverblue, never added to the install list.
- **Podman / Podman CLI**: already included in the Silverblue base image, nothing to install. Only Podman Desktop needs a Flatpak.
- **OBS + game capture**: added the Vulkan capture layer Flatpak (`org.freedesktop.Platform.VulkanLayer.OBSVkCapture`) since you'll be capturing gameplay for the channel — not on your original list but needed for Flatpak OBS to capture Flatpak/native games cleanly.
