#!/usr/bin/env bash
#
# setup-silverblue.sh — post-install automation for Fedora Silverblue
# Usage: ./setup-silverblue.sh <command> [--dry-run]
#
# Commands:
#   base      Layer RPM Fusion, freeworld codecs/VA-API, and the handful of
#             small CLI tools the rest of this script needs. REQUIRES REBOOT
#             after it finishes (rpm-ostree layered changes aren't live until
#             next boot).
#   apps      Install all Flatpaks from your program list + sandbox overrides
#             for Steam/Lutris/OBS, and enable GSConnect/AppIndicator (layered
#             in 'base') now that the reboot has made them available.
#   webapps   Install GNOME Web (Epiphany) and print the 2-click steps to
#             install Discord and Element as real, isolated web apps instead
#             of native Flatpaks.
#   resolve   Clone davincibox and walk you through the DaVinci Resolve
#             container setup (the manual .run download can't be scripted —
#             Blackmagic requires a login).
#   harden    Clone nixbys/fedora-hardening and run it interactively (no
#             sections pre-skipped — they already prompt per-item). Prints
#             guidance for the three prompts worth answering deliberately,
#             then auto-runs firewall-extras, firefox-extensions, and
#             dns-mullvad after.
#   firewall-extras  Add Steam Remote Play + KDE Connect firewalld exceptions
#             that section 5 only auto-offers on Bazzite/KDE (not vanilla
#             Silverblue+GNOME). Safe/idempotent; no-op if firewalld is off.
#   firefox-extensions  Force-install uBlock Origin, LocalCDN, Multi-Account
#             Containers, Proton Pass, Proton VPN, MAL-Sync, and Animouto via
#             Firefox enterprise policy. Supersedes harden's shorter list.
#   dns-mullvad  Switch system DNS from harden's Quad9+Cloudflare default to
#             Mullvad's no-log resolver over DoT (unfiltered tier — the
#             content-filtered tiers are known to break anime streaming
#             sites). Quad9 stays as fallback.
#   dns-revert  Remove the forced-DNS override entirely (back to DHCP
#             defaults). Manual fallback only — see protonvpn-check first;
#             this usually isn't needed.
#   protonvpn  Install the official Proton VPN Linux app (rpm-ostree layered,
#             two reboot-separated phases — re-run to continue). GSConnect
#             (not KDE Connect — see apps) and AppIndicator support are
#             layered in 'base' for the tray icon this app wants.
#   protonvpn-check  Verify DNS actually routes through Proton when connected,
#             instead of just assuming it does.
#   protonpass  Install the official Proton Pass Linux desktop app via
#             distrobox (it doesn't need host network access like the VPN
#             app, so it stays containerized). Download is a manual step
#             (JS-rendered link, can't be scripted) — drop the RPM in
#             ~/Downloads and re-run; install/export is automated from there.
#   dev       Dedicated TOOLBOX (not distrobox — see below) for compilers/
#             language runtimes: gcc/make, python3, nodejs, git, ShellCheck/
#             shfmt, plus PHP+Composer+MariaDB client, Go, Java, gh CLI, and
#             podman-compose (based on what fedora-hardening's own author's
#             other public repos use). Pure Fedora, pure CLI, no GUI export
#             needed — toolbox's textbook case, and it's pre-installed on
#             Silverblue already. davincibox and protonpass stay on
#             distrobox (upstream's recommended path / needs --export --app).
#   backup-setup  Layer restic, guide you through the one-time encrypted
#             backup drive setup (not scripted — partitioning is
#             destructive), then generate a customized backup script + point
#             you at the systemd timer for automation.
#   extras    Read extras.conf (see extras.conf.example) and install anything
#             listed there — your ongoing "add more stuff" mechanism.
#   status    Check the actual current state of disk encryption, Secure Boot,
#             GRUB password, DNS, firewalld, SELinux, USBGuard, Firefox
#             extension policy, davincibox, bluetooth, GSConnect, Proton VPN,
#             Proton Pass, and the dev toolbox in one shot — doesn't fix
#             anything, just reports.
#   all       Run base, then print instructions to reboot and continue.
#
# Any command accepts --dry-run to print what would happen without doing it.

set -uo pipefail

DRY_RUN=0
CMD="${1:-}"
[[ "${2:-}" == "--dry-run" || "${1:-}" == "--dry-run" ]] && DRY_RUN=1

REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
WORKDIR="$HOME/silverblue-setup"
LOGFILE="$WORKDIR/setup.log"
FAILED=()

mkdir -p "$WORKDIR"

log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOGFILE"; }
say()  { echo -e "$*"; }

run() {
  # run <description> -- <command...>
  local desc="$1"; shift
  [[ "$1" == "--" ]] && shift
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: $desc :: $*"
    return 0
  fi
  log "-> $desc"
  if ! "$@" >>"$LOGFILE" 2>&1; then
    log "   FAILED: $desc (see $LOGFILE)"
    FAILED+=("$desc")
    return 1
  fi
  log "   OK: $desc"
  return 0
}

flatpak_install() {
  local app="$1"
  run "flatpak install $app" -- flatpak install -y --noninteractive flathub "$app"
}

ensure_layered() {
  # Layer an rpm-ostree package only if not already present in the base/layer.
  local pkg="$1"
  if rpm -q "$pkg" &>/dev/null; then
    log "   already layered: $pkg"
    return 0
  fi
  run "layer $pkg" -- sudo rpm-ostree install -y "$pkg"
}

require_silverblue() {
  if [[ ! -f /run/ostree-booted ]]; then
    say "This doesn't look like an rpm-ostree/atomic system. Aborting."
    exit 1
  fi
}

container_exists() {
  # container_exists <distrobox|toolbox> <name>
  # Consolidates a check that was previously duplicated six times across
  # cmd_protonpass, cmd_dev, and cmd_status.
  local runtime="$1" name="$2"
  command -v "$runtime" &>/dev/null || return 1
  case "$runtime" in
    distrobox) distrobox list 2>/dev/null | grep -qw "$name" ;;
    toolbox)   toolbox list --containers 2>/dev/null | grep -qw "$name" ;;
    *) return 1 ;;
  esac
}

firewalld_add_service() {
  # firewalld_add_service <name> <<< "$xml"
  # Consolidates the create-XML-then-allow pattern that was duplicated for
  # steam-remote-play and kde-connect in cmd_firewall_extras.
  local svc="$1"
  local svc_dir="/etc/firewalld/services"
  if ! sudo firewall-cmd --get-services 2>/dev/null | grep -qw "$svc"; then
    local tmp; tmp="$(mktemp)"
    cat > "$tmp"
    run "create $svc service definition" -- sudo install -m 644 "$tmp" "$svc_dir/$svc.xml"
    rm -f "$tmp"
  fi
  run "allow $svc" -- sudo firewall-cmd --zone=drop --add-service="$svc" --permanent
}

git_clone_or_update() {
  # git_clone_or_update <url> <dir>
  # Both fedora-hardening and davincibox get pulled here and then executed
  # with sudo. A fresh 'git pull' with zero review before that is a real
  # supply-chain gap for a security-focused setup — this doesn't fully close
  # it (no signature verification, no pinning), but it does mean you see
  # what changed before trusting it, instead of running it blind.
  local url="$1" dir="$2"
  if [[ ! -d "$dir" ]]; then
    run "clone $(basename "$dir")" -- git clone "$url" "$dir"
    return 0
  fi
  local before after
  before="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
  run "update $(basename "$dir")" -- git -C "$dir" pull
  after="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
  if [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
    say "\nNew commits since your last run of $(basename "$dir") — review before trusting"
    say "this with sudo:"
    git -C "$dir" log --oneline "$before..$after" | sed 's/^/  /'
    say ""
  fi
}

# ---------------------------------------------------------------------------
cmd_base() {
  # If you've adopted the declarative bootc image (image/Containerfile — see
  # "Stateless work system" in TRANSITION-PLAN.md), everything below is
  # already baked in. Every check here is idempotent (rpm -q guards
  # throughout), so this just confirms that and no-ops — safe to run either
  # way, no need to skip it manually.
  require_silverblue
  log "=== BASE: RPM Fusion, codecs, VA-API, core CLI tools ==="

  local fver
  fver=$(rpm -E %fedora)

  run "enable RPM Fusion free + nonfree" -- sudo rpm-ostree install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fver}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fver}.noarch.rpm"

  if rpm -q ffmpeg-free &>/dev/null; then
    run "swap ffmpeg-free for full ffmpeg" -- sudo rpm-ostree override remove ffmpeg-free \
      --install ffmpeg --install ffmpeg-libs
  else
    log "   already swapped: ffmpeg (ffmpeg-free not present)"
  fi

  if rpm -q mesa-va-drivers &>/dev/null; then
    run "AMD hardware video accel (mesa freeworld)" -- sudo rpm-ostree override remove \
      mesa-va-drivers --install mesa-va-drivers-freeworld
  else
    log "   already swapped: mesa-va-drivers-freeworld"
  fi

  if rpm -q mesa-vdpau-drivers &>/dev/null; then
    run "AMD VDPAU freeworld" -- sudo rpm-ostree override remove \
      mesa-vdpau-drivers --install mesa-vdpau-drivers-freeworld
  else
    log "   already swapped: mesa-vdpau-drivers-freeworld"
  fi

  run "GStreamer good/bad/ugly plugins + openh264" -- sudo rpm-ostree install -y \
    gstreamer1-plugins-bad-free gstreamer1-plugins-good gstreamer1-plugins-ugly \
    gstreamer1-plugin-openh264 gstreamer1-libav lame

  if [[ -f /etc/yum.repos.d/fedora-cisco-openh264.repo ]]; then
    run "enable Cisco openh264 repo" -- sudo sed -i 's/enabled=0/enabled=1/' \
      /etc/yum.repos.d/fedora-cisco-openh264.repo
    run "install openh264 + mozilla-openh264" -- sudo rpm-ostree install -y \
      openh264 mozilla-openh264
  fi

  # small CLI tools other phases need on the *host* (not containerized)
  ensure_layered git
  ensure_layered lshw   # davincibox uses this to detect your GPU
  ensure_layered restic # local backup tool — see backup-setup command
  ensure_layered gnome-shell-extension-gsconnect   # replaces KDE Connect flatpak — see cmd_apps
  ensure_layered libappindicator-gtk3              # tray icon support, needed for Proton VPN app
  ensure_layered gnome-shell-extension-appindicator

  if [[ $DRY_RUN -eq 0 ]] && ! command -v distrobox &>/dev/null; then
    run "install distrobox (user-local, no layering needed)" -- \
      bash -c 'curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix "$HOME/.local"'
  fi
  # Still needed for davincibox and protonpass specifically (non-Fedora base /
  # GUI export). The 'dev' command uses toolbox instead — already
  # pre-installed on Silverblue, nothing to layer or install for it.

  run "refresh firmware metadata" -- sudo fwupdmgr refresh --force
  run "apply firmware updates" -- sudo fwupdmgr update -y

  log "=== BASE complete. REBOOT NOW, then run: ./setup-silverblue.sh apps ==="
}

# ---------------------------------------------------------------------------
cmd_apps() {
  log "=== APPS: Flatpaks from your program list ==="

  local apps=(
    org.mozilla.firefox
    org.gnome.Epiphany
    com.github.micahflee.torbrowser-launcher
    org.gnome.Boxes
    com.mattjakeman.ExtensionManager
    org.gnome.tweaks
    org.mozilla.Thunderbird
    ch.protonmail.protonmail-bridge
    com.valvesoftware.Steam
    net.lutris.Lutris
    io.podman_desktop.PodmanDesktop
    org.gimp.GIMP
    org.videolan.VLC
    com.obsproject.Studio
    org.freedesktop.Platform.VulkanLayer.OBSVkCapture
    org.libreoffice.LibreOffice
    org.standardnotes.standardnotes
    com.github.tchx84.Flatseal
    it.mijorus.gearlever
    org.audacityteam.Audacity
    org.raspberrypi.rpi-imager
    com.yubico.yubioath
  )

  for app in "${apps[@]}"; do
    flatpak_install "$app"
  done

  say "\nDiscord and Element are intentionally not in this list — see the 'webapps'"
  say "command. Run './setup-silverblue.sh webapps' to install them as GNOME Web apps."

  # GSConnect / AppIndicator were layered in 'base' — enable them now that the
  # reboot has made them available. Detecting the UUID rather than hardcoding
  # it, in case the packaged version differs.
  if command -v gnome-extensions &>/dev/null; then
    local gsc_uuid ai_uuid
    gsc_uuid="$(gnome-extensions list 2>/dev/null | grep -i gsconnect | head -1)"
    if [[ -n "$gsc_uuid" ]]; then
      run "enable GSConnect" -- gnome-extensions enable "$gsc_uuid"
      say "GSConnect enabled — pair your phone via the GNOME Shell top bar icon."
      say "(Install 'KDE Connect' from the Play Store/F-Droid on the phone side — same"
      say "protocol, different name; that app is fine, it's the *desktop* KDE Connect"
      say "app GSConnect conflicts with, not the Android one.)"
    else
      say "GSConnect package installed but not found by 'gnome-extensions list' — enable"
      say "it manually via Extension Manager (already installed) instead."
    fi

    ai_uuid="$(gnome-extensions list 2>/dev/null | grep -i appindicator | head -1)"
    if [[ -n "$ai_uuid" ]]; then
      run "enable AppIndicator support" -- gnome-extensions enable "$ai_uuid"
    fi
  fi

  say "\nMinecraft: install via the Minecraft Launcher's own .tar.gz from minecraft.net,"
  say "or via Prism Launcher (org.prismlauncher.PrismLauncher) which is generally the"
  say "more reliable Flatpak-friendly path on atomic distros. Add whichever you prefer"
  say "to extras.conf if you want it scripted."

  run "kvm group membership for Boxes" -- sudo usermod -aG kvm "$REAL_USER"

  run "Lutris: allow host filesystem access (install scripts need this)" -- \
    flatpak override --user net.lutris.Lutris --filesystem=host --talk-name=org.freedesktop.Flatpak

  run "Steam: allow host filesystem access (for external game libraries)" -- \
    flatpak override --user com.valvesoftware.Steam --filesystem=host

  say "\nSecurity trade-off worth knowing: Steam and Lutris both got --filesystem=host,"
  say "meaning full home directory + mounted drive access — this undercuts Flatpak's"
  say "sandboxing for the two apps most exposed to third-party content (installers, mod"
  say "managers). It's broad because game libraries can live anywhere and I don't know"
  say "your disk layout. Once you know your actual game library path(s), narrow it:"
  say "  flatpak override --user com.valvesoftware.Steam --nofilesystem=host \\"
  say "    --filesystem=/run/media/$REAL_USER/GameDrive:rw --filesystem=~/.local/share/Steam:rw"
  say "(same pattern for net.lutris.Lutris). Check current grants any time with:"
  say "  flatpak info --show-permissions com.valvesoftware.Steam"

  log "=== APPS complete. Log out/in once so the kvm group membership takes effect. ==="
}

# ---------------------------------------------------------------------------
cmd_firefox_extensions() {
  # Writes the full extension policy (superset of what fedora-harden.sh's
  # section 16 installs). Safe to run standalone or after harden — this is
  # the authoritative version and will overwrite harden's shorter list.
  log "=== FIREFOX-EXTENSIONS: policy-installing your extension set ==="

  local ff_root="$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
  local profiles_ini="$ff_root/profiles.ini"

  if [[ ! -f "$profiles_ini" ]] && [[ $DRY_RUN -eq 0 ]]; then
    log "No Firefox profile found yet — launching Firefox once to create one."
    run "create default Firefox profile" -- flatpak run --command=firefox org.mozilla.firefox -CreateProfile default-release
  fi

  local policy_dir="$ff_root/distribution"
  local policy_file="$policy_dir/policies.json"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: would write extension policy to $policy_file"
    return 0
  fi

  mkdir -p "$policy_dir"
  if [[ -f "$policy_file" ]]; then
    cp "$policy_file" "${policy_file}.bak-$(date +%Y%m%d%H%M%S)"
  fi
  cat > "$policy_file" <<'EOF'
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "Extensions": {
      "Install": [
        "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi",
        "https://addons.mozilla.org/firefox/downloads/latest/localcdn-fork-of-decentraleyes/latest.xpi",
        "https://addons.mozilla.org/firefox/downloads/latest/multi-account-containers/latest.xpi",
        "https://addons.mozilla.org/firefox/downloads/latest/proton-pass/latest.xpi",
        "https://addons.mozilla.org/firefox/downloads/latest/proton-vpn-firefox-extension/latest.xpi",
        "https://addons.mozilla.org/firefox/downloads/latest/mal-sync/latest.xpi",
        "https://addons.mozilla.org/firefox/downloads/latest/animouto/latest.xpi"
      ]
    },
    "ExtensionSettings": {
      "*": {
        "installation_mode": "allowed"
      }
    }
  }
}
EOF
  log "   OK: wrote $policy_file (7 extensions: uBlock Origin, LocalCDN, Multi-Account"
  log "   Containers, Proton Pass, Proton VPN, MAL-Sync, Animouto)"
  say "Restart Firefox to apply. This overwrites/supersedes any policy fedora-harden.sh"
  say "section 16 wrote earlier — that's intentional, this file is the full list."
}

# ---------------------------------------------------------------------------
cmd_webapps() {
  log "=== WEBAPPS: GNOME Web for site-installed apps ==="
  flatpak_install org.gnome.Epiphany

  say "\nGNOME Web (Epiphany) is installed. It creates real, isolated web apps with"
  say "their own icon/window identity — genuinely equivalent to a native app, unlike a"
  say "DIY Firefox-profile trick (which would just get grouped under Firefox in the"
  say "dock). That install step is a GUI action, not something worth faking via a"
  say "shell script — two clicks, done properly, once per site:"
  say ""
  say "  1. Open GNOME Web, navigate to the site"
  say "  2. Menu (⋮) -> Install as Web App -> Install"
  say ""
  say "Sites to install this way:"
  say "  Discord  -> https://discord.com/app"
  say "  Element  -> https://app.element.io"
  say ""
  say "Everything else on your list (Steam, Lutris, GIMP, VLC, OBS, LibreOffice,"
  say "Audacity, Raspberry Pi Imager, Yubico Authenticator, Flatseal, Gearlever, KDE"
  say "Connect, Podman Desktop, Boxes, Tweaks/Extension Manager) either needs native"
  say "hardware/file access a webapp can't get, or has no web equivalent at all — left"
  say "as native Flatpaks. Thunderbird, Proton Mail Bridge, and Standard Notes stay"
  say "native per your instructions even though the latter two have web apps too."
}
# ---------------------------------------------------------------------------
cmd_resolve() {
  log "=== RESOLVE: davincibox container setup ==="

  local repo_dir="$WORKDIR/davincibox"
  git_clone_or_update https://github.com/zelikos/davincibox.git "$repo_dir"

  if container_exists distrobox davincibox; then
    say "\ndavincibox container already exists. To upgrade to the latest image:"
    say "  cd $repo_dir && ./setup.sh upgrade"
    return 0
  fi

  say "\nManual step (can't be scripted — Blackmagic requires a login):"
  say "  1. Go to https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion"
  say "  2. Download the Linux .zip, extract it, and place the .run installer in ~/Downloads"
  say "  3. Then run:"
  say "       cd $repo_dir"
  say "       ./setup.sh"
  say "     and follow its prompts. It auto-detects your AMD GPU via lshw and configures"
  say "     the ROCm OpenCL path inside the container — nothing to configure manually for AMD."
  say "  4. A DaVinci Resolve launcher will be added to your app grid when it's done."
}

# ---------------------------------------------------------------------------
cmd_harden() {
  log "=== HARDEN: nixbys/fedora-hardening (interactive — no sections pre-skipped) ==="

  local repo_dir="$WORKDIR/fedora-hardening"
  git_clone_or_update https://github.com/nixbys/fedora-hardening.git "$repo_dir"
  chmod +x "$repo_dir/fedora-harden.sh" 2>/dev/null || true

  say "\nThe script itself asks per-item before changing anything risky, so nothing is"
  say "pre-skipped here. Three prompts to answer deliberately when they come up:"
  say ""
  say "  Section 5 (firewalld):  say YES to the base drop-zone. It will NOT auto-offer"
  say "    Steam Remote Play or KDE Connect ports on vanilla Silverblue+GNOME (that"
  say "    detection is Bazzite/KDE-specific) — this script adds both automatically"
  say "    afterward via 'firewall-extras', regardless of what you answer here."
  say "    Section 14 (DNS-over-TLS) sets Quad9+Cloudflare by default — this script"
  say "    overrides that to Mullvad afterward via 'dns-mullvad', so answer normally."
  say "  Section 8 (USBGuard):   BEFORE answering yes, physically plug in every"
  say "    controller, capture card, mic/interface, and your YubiKey. Anything not"
  say "    plugged in when the policy is generated gets blocked until you run:"
  say "      sudo usbguard list-devices"
  say "      sudo usbguard allow-device <ID> --permanent"
  say "  Section 19 (service cleanup): say NO to disabling bluetooth if you use any"
  say "    Bluetooth controller/headset. Everything else in that list is safe to disable."
  say ""

  if [[ $DRY_RUN -eq 0 ]]; then
    ( cd "$repo_dir" && sudo ./fedora-harden.sh --user "$REAL_USER" --dry-run )
    read -r -p $'\nPreview looked right? Proceed with the real (interactive) run? [y/N] ' confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      ( cd "$repo_dir" && sudo ./fedora-harden.sh --user "$REAL_USER" )
      cmd_firewall_extras
      cmd_firefox_extensions
      cmd_dns_mullvad
    else
      say "Skipped. Re-run './setup-silverblue.sh harden' any time, or run"
      say "$repo_dir/fedora-harden.sh directly with your own --only/--skip list."
    fi
  else
    log "DRY-RUN: would preview then prompt to run fedora-harden.sh interactively"
  fi
}

# ---------------------------------------------------------------------------
cmd_firewall_extras() {
  # Backfills the two firewalld exceptions section 5 would only offer on
  # Bazzite (Steam Remote Play) or KDE (KDE Connect). Safe to re-run — the
  # underlying firewall-cmd calls are idempotent, and this is a no-op if
  # firewalld isn't active (i.e. you declined section 5 entirely).
  if ! command -v firewall-cmd &>/dev/null || ! sudo firewall-cmd --state &>/dev/null 2>&1; then
    log "firewalld not active — skipping firewall-extras (you likely declined section 5)."
    return 0
  fi
  log "=== FIREWALL-EXTRAS: Steam Remote Play + KDE Connect ports ==="

  firewalld_add_service steam-remote-play <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>Steam Remote Play</short>
  <port port="27031" protocol="tcp"/>
  <port port="27036" protocol="tcp"/>
  <port port="27031" protocol="udp"/>
  <port port="27032" protocol="udp"/>
  <port port="27033" protocol="udp"/>
  <port port="27034" protocol="udp"/>
  <port port="27035" protocol="udp"/>
  <port port="27036" protocol="udp"/>
</service>
EOF

  firewalld_add_service kde-connect <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>KDE Connect</short>
  <port port="1714-1764" protocol="tcp"/>
  <port port="1714-1764" protocol="udp"/>
</service>
EOF

  run "reload firewalld" -- sudo firewall-cmd --reload
}

# ---------------------------------------------------------------------------
cmd_dns_mullvad() {
  # Overwrites the same drop-in fedora-harden.sh section 14 writes
  # (/etc/systemd/resolved.conf.d/99-hardening.conf), switching primary DNS
  # from Quad9+Cloudflare to Mullvad's no-log resolver over DoT. Quad9 stays
  # as FallbackDNS for provider diversity if Mullvad is ever unreachable.
  #
  # Deliberately using the UNFILTERED endpoint (dns.mullvad.net), not the
  # "base"/"adblock" content-filtering tiers Mullvad also offers. Those add
  # malware/tracker blocklists at the DNS level, but real-world reports show
  # the blocklists catch anime streaming sites — and between MAL-Sync,
  # Animouto, and uBlock Origin already doing ad/tracker blocking in-browser,
  # the filtered tiers would cost more (breakage) than they'd add here. If
  # you want the filtering later anyway, swap the hostnames below for
  # adblock.dns.mullvad.net (194.242.2.3) or base.dns.mullvad.net (194.242.2.4).
  log "=== DNS-MULLVAD: switching systemd-resolved to Mullvad (unfiltered, no-log) ==="

  local dropin_dir="/etc/systemd/resolved.conf.d"
  local dropin="$dropin_dir/99-hardening.conf"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: would write Mullvad DNS-over-TLS config to $dropin"
    return 0
  fi

  run "create resolved.conf.d directory" -- sudo install -d -m 755 "$dropin_dir"

  if [[ -f "$dropin" ]]; then
    run "back up existing resolved drop-in" -- sudo cp "$dropin" "${dropin}.bak-$(date +%Y%m%d%H%M%S)"
  fi

  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<'EOF'
[Resolve]
DNS=194.242.2.2#dns.mullvad.net 2a07:e340::2#dns.mullvad.net
FallbackDNS=9.9.9.9#dns.quad9.net
DNSOverTLS=yes
DNSSEC=yes
EOF
  run "write Mullvad DNS drop-in" -- sudo install -m 644 "$tmp" "$dropin"
  rm -f "$tmp"

  run "restart systemd-resolved" -- sudo systemctl restart systemd-resolved
  say "\nPrimary DNS is now Mullvad (dns.mullvad.net), TLS-encrypted, Quad9 as fallback."
  say "Verify with: resolvectl status | grep -A2 'Current DNS'"
}

# ---------------------------------------------------------------------------
cmd_dns_revert() {
  # Manual fallback ONLY — see 'protonvpn-check' first. Proton's Linux app
  # manages its VPN state through NetworkManager connection profiles (visible
  # as pvpn-killswitch etc. in `nmcli connection show`), which means it should
  # participate in systemd-resolved's normal per-link DNS priority: when
  # connected, its interface should take over DNS resolution ahead of our
  # global Mullvad default automatically, with no conflict and no revert
  # needed. Only use this if 'protonvpn-check' shows a genuine leak.
  log "=== DNS-REVERT: removing forced DNS override, back to DHCP defaults ==="
  local dropin="/etc/systemd/resolved.conf.d/99-hardening.conf"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: would remove $dropin and restart systemd-resolved"
    return 0
  fi
  if [[ ! -f "$dropin" ]]; then
    log "No override present at $dropin — nothing to revert."
    return 0
  fi
  run "remove forced DNS drop-in" -- sudo rm -f "$dropin"
  run "restart systemd-resolved" -- sudo systemctl restart systemd-resolved
  say "\nDNS is back to whatever your network/DHCP provides."
}

# ---------------------------------------------------------------------------
cmd_protonvpn() {
  # If you've adopted the declarative bootc image, this is also already
  # baked in — the app_installed check below will find it and no-op
  # immediately. See "Stateless work system" in TRANSITION-PLAN.md.
  #
  # Official app only — Proton explicitly doesn't support Flatpak distribution
  # of their own tools. A VPN client needs host-level network stack access
  # (kernel WireGuard, NetworkManager D-Bus, killswitch routing) that no
  # container can provide, so rpm-ostree layering is the only correct
  # approach here — unlike almost everything else in this script.
  #
  # Two reboot-separated phases, same pattern as 'base':
  #   1. Layer the repo package (adds /etc/yum.repos.d entry + GPG key)
  #   2. Layer proton-vpn-gnome-desktop from that repo
  # Re-running this command picks up wherever you left off.
  require_silverblue
  log "=== PROTONVPN: official Linux app (rpm-ostree layered) ==="

  local fver; fver=$(rpm -E %fedora)
  local repo_installed=0 app_installed=0
  rpm -q protonvpn-stable-release &>/dev/null && repo_installed=1
  rpm -q proton-vpn-gnome-desktop &>/dev/null && app_installed=1

  if [[ $app_installed -eq 1 ]]; then
    log "Already fully installed (proton-vpn-gnome-desktop present)."
    say "Launch it from your app grid, or run './setup-silverblue.sh protonvpn-check'"
    say "after connecting to verify DNS is routing through Proton, not Mullvad."
    return 0
  fi

  if [[ $repo_installed -eq 0 ]]; then
    local repo_rpm="protonvpn-stable-release-1.0.4-1.noarch.rpm"
    local repo_url="https://repo.protonvpn.com/fedora-${fver}-stable/protonvpn-stable-release/${repo_rpm}"
    run "layer Proton VPN repo package" -- sudo rpm-ostree install -y "$repo_url"
    log "=== Repo layered. REBOOT NOW, then run './setup-silverblue.sh protonvpn' again ==="
    return 0
  fi

  run "layer proton-vpn-gnome-desktop" -- sudo rpm-ostree install -y proton-vpn-gnome-desktop
  log "=== App layered. REBOOT NOW. After reboot: launch Proton VPN, sign in, connect, ==="
  log "=== then run './setup-silverblue.sh protonvpn-check' to verify DNS is clean.    ==="
}

# ---------------------------------------------------------------------------
cmd_protonvpn_check() {
  # Verifies the theory in cmd_dns_revert's comment instead of just trusting
  # it: is a pvpn-* NetworkManager connection active, and if so, is
  # systemd-resolved actually using it (not still showing Mullvad)?
  say "=== PROTONVPN-CHECK: verifying DNS routes through Proton when connected ===\n"

  local pvpn_conn
  pvpn_conn="$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep '^pvpn-' | head -1)"

  if [[ -z "$pvpn_conn" ]]; then
    say "No active pvpn-* NetworkManager connection found — Proton VPN doesn't look"
    say "connected right now. Connect it, then re-run this check."
    return 0
  fi
  say "Active Proton connection: $pvpn_conn\n"

  if ! command -v resolvectl &>/dev/null; then
    say "resolvectl not found — can't verify DNS routing on this system."
    return 0
  fi

  say "Current DNS servers by interface (resolvectl status):"
  resolvectl status 2>/dev/null | grep -A3 -E "Link [0-9]+ \(" | grep -B3 -E "DNS Servers"

  echo
  if resolvectl status 2>/dev/null | grep -q "194.242.2.2"; then
    say "⚠  Mullvad's address (194.242.2.2) still shows as an active resolver somewhere"
    say "   above. Check which link it's attached to — if it's on the Proton VPN"
    say "   interface itself rather than your regular ethernet/wifi link, that's likely"
    say "   fine (Mullvad as configured fallback). If it's the ONLY resolver shown while"
    say "   connected, DNS isn't being routed through Proton — run 'dns-revert', then"
    say "   reconnect Proton VPN and re-check."
  else
    say "✓  Mullvad's address isn't showing as active — DNS looks like it's routing"
    say "   through Proton's own resolvers while connected, as expected. No action needed."
  fi
}

# ---------------------------------------------------------------------------
cmd_protonpass() {
  # Proton Pass DOES have an official Linux desktop app (confirmed — standalone
  # .rpm download, no repo, so no auto-updates; re-download to update, per
  # Proton's own docs).
  #
  # The download link on proton.me/pass/download/linux is JavaScript-rendered
  # (confirmed by fetching the page directly — the button points to a #download
  # anchor and the actual per-OS link loads client-side), so this can't
  # reliably scrape the current URL the way 'base' does for RPM Fusion. Rather
  # than ship something that looks automated but silently breaks, the download
  # itself is a manual step; everything after that (install into the
  # container, export to the app grid) is scripted.
  #
  # Unlike Proton VPN, a password manager doesn't need host-level network
  # stack access — it's a normal GUI app with local encrypted storage plus
  # outbound API calls to sync. That means it fits the container-first
  # philosophy the rest of this plan uses: it goes in a distrobox, exported
  # to the host app grid, rather than layered onto the host like the VPN app
  # had to be.
  log "=== PROTONPASS: official desktop app (distrobox, not host-layered) ==="

  local box="protonpass"
  if ! container_exists distrobox "$box"; then
    run "create $box distrobox" -- distrobox create -n "$box" -i registry.fedoraproject.org/fedora:latest --yes
  fi

  local rpm_path
  rpm_path="$(ls -t "$HOME"/Downloads/ProtonPass*.rpm 2>/dev/null | head -1)"

  if [[ -z "$rpm_path" ]]; then
    say "\nManual step first (the download link is JS-rendered, can't be scripted):"
    say "  1. https://proton.me/pass/download/linux -> Download Proton Pass -> RPM"
    say "  2. Save it to ~/Downloads (default location)"
    say "  3. Re-run: ./setup-silverblue.sh protonpass"
    return 0
  fi

  say "Found $rpm_path\n"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: would install $rpm_path in $box and export it to the app grid"
    return 0
  fi

  run "copy rpm into $box" -- distrobox enter "$box" -- \
    bash -c "cp '$rpm_path' /tmp/protonpass.rpm"
  run "install Proton Pass in $box" -- distrobox enter "$box" -- \
    sudo rpm -i /tmp/protonpass.rpm

  local desktop_file
  desktop_file="$(distrobox enter "$box" -- bash -c \
    "find /usr/share/applications -iname '*proton*pass*.desktop' 2>/dev/null" | head -1)"

  if [[ -n "$desktop_file" ]]; then
    local app_name; app_name="$(basename "$desktop_file" .desktop)"
    run "export to host app grid" -- distrobox-export --app "$app_name" --container "$box"
    say "\nProton Pass installed and exported — it'll show up in your app grid."
  else
    say "\nInstalled, but couldn't find the .desktop file to export automatically."
    say "Run: distrobox enter $box -- ls /usr/share/applications | grep -i pass"
    say "Then: distrobox-export --app <name-from-above> --container $box"
  fi

  say "\nUpdating later: this is a static download, not a repo — download a fresh RPM"
  say "from the link above and re-run this command any time."
  say "\nOne thing worth keeping outside Proton entirely: their emergency recovery kit"
  say "(the PDF Proton generates with your recovery phrase/keys). Store that on the"
  say "encrypted backup drive from 'backup-setup', not inside Pass itself — if you're"
  say "ever locked out of your Proton account, that's the only way back in."
}

# ---------------------------------------------------------------------------
cmd_dev() {
  # Toolbox, not distrobox — reconsidered on request. This is genuinely the
  # one place in this system where the choice was worth revisiting:
  #   - dev is pure Fedora, pure CLI, no GUI apps to export to the host grid.
  #     That's toolbox's textbook case (a "clean Fedora sandbox for dev
  #     packages," per its own docs), not a marginal fit.
  #   - Toolbox is PRE-INSTALLED on Silverblue — using it here adds zero new
  #     dependencies, unlike distrobox which this script installs itself.
  #   - Toolbox containers default to matching the host Fedora version
  #     automatically; no image URL to specify or keep in sync.
  # distrobox stays for davincibox (its own upstream project's primary,
  # recommended path — it supports toolbox too, but distrobox is what its
  # own README and maintainer recommend) and protonpass (needs
  # distrobox-export's automated .desktop integration — toolbox can run GUI
  # apps fine, but has no equivalent automated host-grid export, only manual
  # .desktop authoring, which is exactly the polish protonpass's install flow
  # depends on).
  log "=== DEV: general-purpose dev/scripting toolbox ==="

  local box="dev"
  if ! container_exists toolbox "$box"; then
    run "create dev toolbox" -- toolbox create --container "$box" --yes
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: would install toolchain in $box"
    return 0
  fi

  run "install dev toolchain in $box" -- toolbox run --container "$box" -- \
    sudo dnf install -y gcc make python3 python3-pip nodejs npm ShellCheck shfmt git \
      php php-cli php-common php-mbstring php-xml php-mysqlnd composer \
      mariadb golang java-latest-openjdk gh podman-compose

  say "\nStarter toolchain, expanded from the base build/scripting set:"
  say "  gcc/make, python3+pip, nodejs+npm, git, ShellCheck+shfmt (bash tooling for"
  say "  maintaining this project itself), plus PHP+Composer+MariaDB client, Go, Java,"
  say "  gh (GitHub CLI), and podman-compose."
  say ""
  say "The second set isn't generic — it's what fedora-hardening's own author's other"
  say "public repos actually use: a Laravel+MariaDB+Podman-Compose app (PHP/Composer/"
  say "MariaDB/podman-compose), a Go-based container MCP server (golang), and a game"
  say "server project mixing Python/ActionScript/PHP/Java (java-latest-openjdk covers"
  say "the JVM piece; ActionScript/Flex SDK itself isn't a standard package — add it"
  say "manually if you actually pursue that project, it's too niche to bundle by default)."
  say "gh specifically because that project's own preflight script checks for it."
  say ""
  say "Lint/format this project's own bash scripts from inside the container:"
  say "  toolbox run --container dev -- shellcheck ~/silverblue-setup/fedora-hardening/fedora-harden.sh"
  say ""
  say "Enter it any time with: toolbox enter dev"
  say "Run a single command without entering a shell first: toolbox run --container dev -- <tool>"
  say "(toolbox has no equivalent to distrobox's --export --bin — there's no automated"
  say "way to put a container binary on your host PATH. For CLI tools that's rarely"
  say "worth missing; 'toolbox run -c dev -- <tool>' is one extra word.)"
  say ""
  say "Need something not in this starter list? Add it directly:"
  say "  toolbox run --container dev -- sudo dnf install -y <package>"
  say "(extras.conf's [distrobox] section is distrobox-specific syntax — it won't drive"
  say "toolbox installs. For dev, just run the command above directly.)"
}

# ---------------------------------------------------------------------------
cmd_backup_setup() {
  # Deliberately NOT scripting partition/LUKS creation — wiping the wrong
  # block device is unrecoverable, and I have no reliable way to confirm
  # which device is safe to touch on your specific hardware. That one-time
  # step gets guided manual instructions (GNOME Disks, not raw cryptsetup).
  # Everything repeatable after that — restic repo init, the actual backup,
  # scheduling — is scripted and safe to re-run.
  require_silverblue
  log "=== BACKUP-SETUP: local encrypted backup target + restic ==="

  ensure_layered restic

  say "\n--- One-time manual step: prepare the encrypted backup drive ---"
  say "This needs to be a SEPARATE physical drive from your OS disk — an internal"
  say "second drive or an external USB/SSD — to actually satisfy 3-2-1's \"2 different"
  say "media\" requirement. A second partition on the same drive as your OS doesn't"
  say "protect you if that drive fails or the laptop is stolen.\n"
  say "  1. Open GNOME Disks (already covers this — no separate app needed)"
  say "  2. Select the backup drive -> the gear/menu icon -> Format Partition"
  say "  3. Type: 'Encrypt underlying device (LUKS2)', filesystem: ext4"
  say "  4. Set a strong passphrase — DIFFERENT from your OS disk's LUKS passphrase"
  say "     and store it in Proton Pass now, before you forget"
  say "  5. Note the mount path once it's set up (GNOME auto-mounts LUKS drives under"
  say "     /run/media/\$USER/<volume-name> after you unlock them once in Files/Disks)\n"

  read -r -p "Mount path of your encrypted backup drive (e.g. /run/media/$REAL_USER/Backup): " backup_path

  if [[ -z "$backup_path" || ! -d "$backup_path" ]]; then
    say "That path doesn't exist yet — run this again once the drive is formatted and mounted."
    return 0
  fi

  local repo="$backup_path/restic-repo"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: would init restic repo at $repo (if not already present)"
    log "DRY-RUN: would write $WORKDIR/backup-home.sh"
    log "DRY-RUN: would write $HOME/.config/systemd/user/backup-home.{service,timer}"
    return 0
  fi

  if [[ ! -f "$repo/config" ]]; then
    say "\nInitializing restic repository at $repo"
    say "You'll be asked to set a repository password — this is IN ADDITION to the LUKS"
    say "passphrase (defense in depth: the drive being decrypted doesn't automatically"
    say "expose the backup contents). Store this one in Proton Pass too."
    restic init --repo "$repo"
  else
    log "restic repository already exists at $repo"
  fi

  # Write a customized backup script + systemd user units
  mkdir -p "$WORKDIR"
  cat > "$WORKDIR/backup-home.sh" <<EOF
#!/usr/bin/env bash
# Generated by setup-silverblue.sh backup-setup on $(date '+%Y-%m-%d')
set -euo pipefail
export RESTIC_REPOSITORY="$repo"
# RESTIC_PASSWORD_COMMAND avoids a plaintext password file — pulls it from
# Proton Pass CLI if you set one up, otherwise switch this to
# RESTIC_PASSWORD_FILE pointing at a root-only-readable file.
export RESTIC_PASSWORD_COMMAND="\${RESTIC_PASSWORD_COMMAND:-cat \$HOME/.restic-pw}"

restic backup \\
  "\$HOME/Documents" \\
  "\$HOME/Pictures" \\
  "\$HOME/Videos" \\
  "\$HOME/.config/obs-studio" \\
  "\$HOME/.local/share/Steam/userdata" \\
  --exclude-caches \\
  --exclude="*.tmp" \\
  --tag auto

# Keep 7 daily, 4 weekly, 6 monthly snapshots; discard the rest.
restic forget --prune \\
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6
EOF
  chmod +x "$WORKDIR/backup-home.sh"

  say "\nWritten: $WORKDIR/backup-home.sh — edit the path list for anything specific to"
  say "your setup (Resolve project directory, davincibox container data, etc.)."

  # Generate the real unit files (not the static template's placeholder) with
  # the actual mount path baked in via ConditionPathIsMountPoint, so the
  # timer safely no-ops instead of erroring if the drive isn't plugged in.
  local unit_dir="$HOME/.config/systemd/user"
  mkdir -p "$unit_dir"
  cat > "$unit_dir/backup-home.service" <<EOF
[Unit]
Description=restic backup of home directory to encrypted drive
ConditionPathIsMountPoint=$backup_path

[Service]
Type=oneshot
ExecStart=$WORKDIR/backup-home.sh
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF
  cat > "$unit_dir/backup-home.timer" <<'EOF'
[Unit]
Description=Daily backup timer for backup-home.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF

  run "reload systemd user units" -- systemctl --user daemon-reload
  say "\nGenerated $unit_dir/backup-home.{service,timer} with your actual mount path."
  say "Enable the schedule with:"
  say "  systemctl --user enable --now backup-home.timer"
  say "Check it worked with:"
  say "  systemctl --user list-timers backup-home.timer"
}

# ---------------------------------------------------------------------------
cmd_extras() {
  log "=== EXTRAS: reading extras.conf ==="
  local conf="$WORKDIR/extras.conf"
  if [[ ! -f "$conf" ]]; then
    say "No $conf found. Copy extras.conf.example there and edit it, then re-run."
    return 0
  fi

  local section=""
  while IFS= read -r line; do
    line="${line%%#*}"                 # strip comments
    line="$(echo -n "$line" | xargs)"  # trim whitespace
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
      section="${BASH_REMATCH[1]}"
      continue
    fi

    case "$section" in
      flatpak)
        flatpak_install "$line"
        ;;
      rpm-ostree)
        ensure_layered "$line"
        ;;
      distrobox)
        # format: name:image:pkg1,pkg2,pkg3
        IFS=':' read -r dbname dbimage dbpkgs <<< "$line"
        run "distrobox create $dbname" -- distrobox create -n "$dbname" -i "$dbimage" --yes
        if [[ -n "${dbpkgs:-}" ]]; then
          IFS=',' read -ra pkgarr <<< "$dbpkgs"
          run "install packages in $dbname" -- distrobox enter "$dbname" -- \
            sudo dnf install -y "${pkgarr[@]}"
        fi
        ;;
      appimage)
        # format: Name|https://example.com/App.AppImage
        IFS='|' read -r apname apurl <<< "$line"
        mkdir -p "$HOME/Applications"
        local dest="$HOME/Applications/${apname// /_}.AppImage"
        run "download $apname" -- curl -Lo "$dest" "$apurl"
        run "make $apname executable" -- chmod +x "$dest"
        say "   -> Open Gearlever and integrate: $dest"
        ;;
      *)
        log "   unknown section [$section], skipping line: $line"
        ;;
    esac
  done < "$conf"
}

# ---------------------------------------------------------------------------
cmd_status() {
  say "=== STATUS: current state of everything this script touches ===\n"

  # Disk encryption — this script can't set it up (install-time only), but
  # it can at least tell you whether it's actually there, since the plan
  # calls this the single highest-value control and nothing else checks it.
  printf '%-28s' "Disk encryption (LUKS):"
  if lsblk -o FSTYPE 2>/dev/null | grep -qw crypto_LUKS; then
    echo "present on at least one block device"
  else
    echo "NOT DETECTED — see Phase 2 of the plan if this is unexpected"
  fi

  # Secure Boot
  printf '%-28s' "Secure Boot:"
  if command -v mokutil &>/dev/null; then
    mokutil --sb-state 2>/dev/null | grep -qi "enabled" && echo "enabled" || echo "disabled or unknown"
  else
    echo "mokutil not installed — can't check (harden's section 6 covers this)"
  fi

  # GRUB password — heuristic only (checks for a password hash in the grub
  # config), not authoritative, but better than no signal at all.
  printf '%-28s' "GRUB password:"
  if sudo grep -rq "password_pbkdf2" /boot/grub2/ /etc/grub.d/ 2>/dev/null; then
    echo "appears set"
  else
    echo "not detected — see Phase 4's grub2-setpassword note"
  fi

  # DNS
  printf '%-28s' "DNS:"
  if [[ -f /etc/systemd/resolved.conf.d/99-hardening.conf ]]; then
    if grep -q "mullvad" /etc/systemd/resolved.conf.d/99-hardening.conf 2>/dev/null; then
      echo "Mullvad (forced, DoT)"
    else
      echo "forced override present (not Mullvad — check 99-hardening.conf)"
    fi
  else
    echo "no override — DHCP/network default"
  fi

  # Firewalld
  printf '%-28s' "Firewalld:"
  if command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state &>/dev/null 2>&1; then
    local zone; zone="$(sudo firewall-cmd --get-default-zone 2>/dev/null)"
    local svcs; svcs="$(sudo firewall-cmd --zone="$zone" --list-services 2>/dev/null)"
    echo "active, default zone '$zone', services: ${svcs:-none}"
  else
    echo "inactive / not installed (section 5 declined?)"
  fi

  # SELinux
  printf '%-28s' "SELinux:"
  command -v getenforce &>/dev/null && getenforce || echo "getenforce not found"

  # USBGuard
  printf '%-28s' "USBGuard:"
  if systemctl is-active --quiet usbguard 2>/dev/null; then
    echo "active ($(sudo usbguard list-devices 2>/dev/null | wc -l) devices known)"
  else
    echo "inactive / not installed (section 8 declined?)"
  fi

  # Firefox extension policy
  printf '%-28s' "Firefox policy:"
  local policy_file="$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/distribution/policies.json"
  if [[ -f "$policy_file" ]]; then
    echo "present ($(grep -o 'addons.mozilla.org[^"]*' "$policy_file" | wc -l) extensions listed)"
  else
    echo "not written yet — run 'firefox-extensions'"
  fi

  # Distrobox / davincibox
  printf '%-28s' "davincibox container:"
  if container_exists distrobox davincibox; then
    echo "exists"
  else
    echo "not created yet — run 'resolve'"
  fi

  # Bluetooth (flagged since harden's section 19 can disable it)
  printf '%-28s' "Bluetooth service:"
  systemctl is-enabled bluetooth &>/dev/null && echo "enabled" || echo "disabled/not present"

  # GSConnect
  printf '%-28s' "GSConnect:"
  if command -v gnome-extensions &>/dev/null && gnome-extensions list --enabled 2>/dev/null | grep -qi gsconnect; then
    echo "enabled"
  else
    echo "not enabled — run 'base' then 'apps' if not yet done"
  fi

  # Proton VPN
  printf '%-28s' "Proton VPN app:"
  if rpm -q proton-vpn-gnome-desktop &>/dev/null; then
    if nmcli -t -f NAME connection show --active 2>/dev/null | grep -q '^pvpn-'; then
      echo "installed, connected"
    else
      echo "installed, not connected"
    fi
  else
    echo "not installed — run 'protonvpn'"
  fi

  # Proton Pass (distrobox)
  printf '%-28s' "Proton Pass desktop:"
  if container_exists distrobox protonpass; then
    echo "container exists"
  else
    echo "not installed — run 'protonpass'"
  fi

  # Dev toolbox
  printf '%-28s' "Dev toolbox:"
  if container_exists toolbox dev; then
    echo "exists"
  else
    echo "not created — run 'dev'"
  fi

  # Backup
  printf '%-28s' "Backup (restic):"
  if rpm -q restic &>/dev/null; then
    if [[ -f "$WORKDIR/backup-home.sh" ]]; then
      echo "configured ($WORKDIR/backup-home.sh)"
    else
      echo "restic installed, not configured — run 'backup-setup'"
    fi
  else
    echo "not installed — run 'backup-setup'"
  fi

  echo
  say "Note: this reads current state, it doesn't fix anything. Re-run the relevant"
  say "command (dns-mullvad, firewall-extras, firefox-extensions, harden) to fix a gap."
}

# ---------------------------------------------------------------------------
usage() {
  awk '/^#!/{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
}

case "$CMD" in
  base)             cmd_base ;;
  apps)             cmd_apps ;;
  webapps)          cmd_webapps ;;
  resolve)          cmd_resolve ;;
  harden)           cmd_harden ;;
  firewall-extras)  cmd_firewall_extras ;;
  firefox-extensions) cmd_firefox_extensions ;;
  dns-mullvad)      cmd_dns_mullvad ;;
  dns-revert)       cmd_dns_revert ;;
  protonvpn)        cmd_protonvpn ;;
  protonvpn-check)  cmd_protonvpn_check ;;
  protonpass)       cmd_protonpass ;;
  dev)              cmd_dev ;;
  backup-setup)     cmd_backup_setup ;;
  extras)           cmd_extras ;;
  status)           cmd_status ;;
  all)              cmd_base; say "\nReboot now, then run: ./setup-silverblue.sh apps" ;;
  *)                usage; exit 1 ;;
esac

if [[ ${#FAILED[@]} -gt 0 ]]; then
  say "\n${#FAILED[@]} step(s) failed — see $LOGFILE:"
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi
