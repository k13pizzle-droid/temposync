#!/usr/bin/env bash
# Setup script for the Claude Code on the web environment for this repo.
# Paste the body into claude.ai/code -> environment -> Setup script. It is not
# run from the repo automatically. Installs the Swift toolchain on Ubuntu via
# swiftly (https://www.swift.org/install/linux/). Untested in the cloud image as
# of 2026-09-30; if it fails, the session still works for reading and editing.
set -euo pipefail
if command -v swift >/dev/null 2>&1; then
  echo "swift already present: $(swift --version 2>&1 | head -1)"
  exit 0
fi
sudo apt-get update -qq
sudo apt-get install -y -qq binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev
cd /tmp
curl -fsSLO "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
tar zxf "swiftly-$(uname -m).tar.gz"
./swiftly init --assume-yes --quiet-shell-followup
# shellcheck disable=SC1091
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
swiftly install latest --use
echo "PATH=$HOME/.local/share/swiftly/bin:$PATH" >> "$HOME/.bashrc"
swift --version
