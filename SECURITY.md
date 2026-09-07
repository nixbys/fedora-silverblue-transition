# Security Policy

This is a personal Fedora Silverblue migration toolkit: shell scripts run
on the host during the transition, a `bootc` container image build, and a
local-only browser control panel (`control-panel/`) that drives those
scripts from a web page.

## Supported Versions

Security fixes are handled on the `main` branch; there are no tagged
releases.

## Where the threat model already lives

The one component here with a real remote-facing surface --
`control-panel/server.py` -- documents its own threat model in detail:

- The module docstring at the top of `control-panel/server.py`.
- The "Trust model" section of `control-panel/README.md`.

Read those before changing anything in `control-panel/`. In short: the
server binds to `127.0.0.1` only, requires a random per-run `X-Auth-Token`
on every state-changing request, allowlists the `Host` header against DNS
rebinding, and sends `X-Frame-Options`/CSP headers against clickjacking.
None of that replaces `sudo`'s own password prompt as the real
authorization boundary -- it exists so that prompt is the only thing
standing between a stray browser tab and a root shell.

## Automated checks

- **CodeQL** (GitHub default setup) scans `actions`, `javascript`,
  `javascript-typescript`, and `python` weekly and on every PR.
- **Secret scanning + push protection** (GitHub native) are enabled on
  this repo, supplemented by a `gitleaks` workflow for generic/non-provider
  secret patterns.
- **Dependabot** tracks the `image/Containerfile` base image and the
  GitHub Actions used in `.github/workflows/`.
- **Dependency review** runs on pull requests as a supply-chain gate.

## Reporting

Please report vulnerabilities privately via
[GitHub security advisories](https://github.com/nixbys/fedora-silverblue-transition/security/advisories/new)
for this repo, or by opening a minimal issue that does not disclose exploit
details.
