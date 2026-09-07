# Fedora Silverblue Transition Toolkit

A personal toolkit for migrating one machine from Bazzite to Fedora
Silverblue: a written phase-by-phase plan, a post-install automation
script, a declarative `bootc` container image, a VM test harness, and a
local browser-based control panel to drive it all without a terminal
window.

## What this is

This is a real, working migration project for a specific machine and a
specific person's setup — not a generic "how to install Silverblue" guide
or a reusable distro tool. The scripts assume an AMD GPU, a particular set
of apps (Steam, DaVinci Resolve, OBS, Proton VPN/Pass, Element, etc.), and
design choices (host stays minimal, everything volatile lives in Flatpaks
or containers) documented in `TRANSITION-PLAN.md`. It's shared here as a
working reference, not a product — expect to read and adapt it rather than
run it unmodified on a different machine.

The core idea, if you're adapting this rather than just reading it: keep
the immutable host tiny and hardened, and push anything that needs a
heavier or fragile dependency set (games, video editing, dev tooling) into
Flatpaks, toolboxes, or distroboxes that can be blown away and rebuilt
without touching the base system.

## Quick start

1. **Read the plan.** `TRANSITION-PLAN.md` is the actual migration plan,
   phase by phase (prep, VM test, install, base layer, apps, hardening,
   backups). Start there — the rest of this repo is the tooling it
   references.
2. **Test in a VM first.**
   ```bash
   cd vm-test
   ./provision-test-vm.sh iso
   ./provision-test-vm.sh create --dry-run   # sanity-check before creating anything
   ./provision-test-vm.sh create
   ```
   See `vm-test/VM-TESTING.md` for the full walkthrough and what a VM can't
   tell you (USBGuard and AMD-specific behavior need real hardware).
3. **After a real install**, run the post-install automation from the repo
   checkout on the new machine:
   ```bash
   ./setup-silverblue.sh status              # see what's already true, changes nothing
   ./setup-silverblue.sh base                # RPM Fusion, codecs, core CLI tools -- then reboot
   ./setup-silverblue.sh apps                # Flatpaks + sandbox overrides
   ./setup-silverblue.sh harden              # runs nixbys/fedora-hardening interactively
   ./setup-silverblue.sh all                 # just runs base, then tells you to reboot
   ```
   Every command accepts `--dry-run` to print what it would do without
   doing it. Run `./setup-silverblue.sh` with no arguments (or open the
   script header) for the full command list — `webapps`, `resolve`,
   `protonvpn`, `protonpass`, `dev`, `backup-setup`, `extras`, and more.
4. **Or drive it from a browser instead of a terminal:**
   ```bash
   ./setup-silverblue.sh control-panel start
   ```
   Opens a local-only (`127.0.0.1:8642`) web terminal with real `sudo`
   prompts. See `control-panel/README.md` for how it works and its trust
   model before using it.

## Architecture

| Path | Purpose |
|------|---------|
| `TRANSITION-PLAN.md` | The actual migration plan: phases, reasoning, and decision points |
| `DIGITAL-COMPARTMENTALIZATION.md` | A companion plan for separating identities/accounts by purpose, alongside the container/Flatpak compartmentalization |
| `setup-silverblue.sh` | The main post-install automation script (imperative, idempotent, `--dry-run`-able); see its own header for the full command list |
| `image/Containerfile` | A declarative `bootc` image that bakes in what used to be `setup-silverblue.sh base`/`protonvpn` (RPM Fusion, codecs, core CLI tools, Proton VPN) so it's built once in CI, not run ad hoc on the live machine |
| `.github/workflows/build-image.yml` | Builds and pushes the `bootc` image to GHCR |
| `control-panel/` | A local-only web terminal (Python stdlib server + hand-rolled JS terminal renderer) that runs `setup-silverblue.sh` from a browser tab — see its own README for the full trust model |
| `vm-test/` | Scripts and notes for validating the install in a throwaway libvirt VM before touching real hardware |
| `extras.conf.example` | Template for the ongoing "install more stuff" config `setup-silverblue.sh extras` reads |
| `backup-home.service` / `backup-home.timer` | systemd user units (templates) for a daily `restic` backup, generated with real paths by `setup-silverblue.sh backup-setup` |
| `index.html`, `silverblue-migration-hub*.html` | A browsable, styled version of the plan/toolkit for reading outside a terminal |
| `push-instructions.sh` | One-time bootstrap notes for pushing this project to its GitHub remote |

## Configuration

- **`extras.conf`** (copy from `extras.conf.example` into
  `~/silverblue-setup/extras.conf`) drives `./setup-silverblue.sh extras`:
  Flatpak app IDs, small `rpm-ostree` CLI packages, distrobox containers,
  and AppImages to install on top of the base setup. Safe to re-run.
- **`image/Containerfile`** takes a `FEDORA_VERSION` build arg (defaults to
  `44`); everything else is fixed at build time and reviewed as code rather
  than run interactively.
- **`backup-home.service`** is a template — `ConditionPathIsMountPoint`
  needs a real mount path, which `setup-silverblue.sh backup-setup`
  fills in when it generates your copy under
  `~/.config/systemd/user/`.
- The control panel has essentially no configuration surface by design —
  see the next section.

## Security

- **`control-panel/`** runs a real PTY with real `sudo` access, so it's
  deliberately constrained: binds to `127.0.0.1` only (no flag to change
  that), requires a random per-run `X-Auth-Token` on every state-changing
  request, allowlists the `Host` header against DNS rebinding, and sends
  `X-Frame-Options`/CSP headers against clickjacking. Full detail is in
  `control-panel/README.md`'s "Trust model" section and the module
  docstring at the top of `control-panel/server.py`. It is explicitly not
  designed for multi-device/LAN access.
- **CI** runs CodeQL (Actions, JavaScript/TypeScript, Python) on every PR
  and weekly, a `gitleaks` workflow for secret patterns GitHub's own
  scanning doesn't cover, and a dependency-review gate on PRs
  (`.github/workflows/`).
- **Dependabot** tracks the `image/Containerfile` base image and the
  GitHub Actions pinned in `.github/workflows/`.
- Disk encryption (LUKS2, enabled at install time) is called out in
  `TRANSITION-PLAN.md` as the single highest-value control in the whole
  migration — see Phase 2 there.

See `SECURITY.md` for the full policy and how to report an issue.
