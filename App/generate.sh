#!/usr/bin/env bash
# Regenerate TempoSync.xcodeproj from project.yml (the source of truth).
# Use this instead of a bare `xcodegen generate`: it creates the local, gitignored
# Signing.xcconfig on first run, so your Apple team survives every regeneration.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f Signing.xcconfig ]; then
  cp Signing.example.xcconfig Signing.xcconfig
  echo "Created App/Signing.xcconfig."
  echo "   Add your Apple team ID to it for device builds (Xcode > Settings > Accounts > Team ID)."
fi

xcodegen generate
team=$(sed -n 's/^ *DEVELOPMENT_TEAM *= *//p' Signing.xcconfig | tr -d '[:space:]')
if [ -n "$team" ]; then
  echo "Project generated. Signing team: $team"
else
  echo "Project generated. No team set — simulator builds only."
fi
