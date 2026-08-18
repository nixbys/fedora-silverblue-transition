#!/usr/bin/env bash
# Run this from wherever you've saved the project files (the ones downloaded
# from this conversation), with the same directory structure they came in:
#   setup-silverblue.sh, TRANSITION-PLAN.md, DIGITAL-COMPARTMENTALIZATION.md,
#   extras.conf.example, backup-home.service, backup-home.timer,
#   silverblue-migration-hub.html, image/Containerfile,
#   .github/workflows/build-image.yml, vm-test/provision-test-vm.sh,
#   vm-test/VM-TESTING.md

git init
git remote add origin https://github.com/nixbys/fedora-silverblue-transition.git
git add .
git commit -m "Initial commit: Silverblue migration toolkit"
git branch -M main
git push -u origin main

# GitHub Actions needs one manual setting before build-image.yml can push to
# GHCR (this is off by default on new repos, not something git push sets):
#   Settings -> Actions -> General -> Workflow permissions -> "Read and write permissions"
# Full first-run checklist (this setting plus package visibility, verifying
# the first run, etc.) is at the bottom of .github/workflows/build-image.yml.
