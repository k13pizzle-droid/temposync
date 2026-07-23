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

# Turn OFF Xcode's automatic scheme creation. project.yml declares shared schemes for the three
# runnable apps; left on, Xcode also invents one per target (including the widget extension) and
# regenerating resets which scheme is selected — landing a device run on the widget, which cannot
# be launched like an app ("Failed to show Widget ... Failed to get descriptors").
settings_dir="TempoSync.xcodeproj/project.xcworkspace/xcshareddata"
mkdir -p "$settings_dir"
cat > "$settings_dir/WorkspaceSettings.xcsettings" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded</key>
	<false/>
</dict>
</plist>
PLIST

team=$(sed -n 's/^ *DEVELOPMENT_TEAM *= *//p' Signing.xcconfig | tr -d '[:space:]')
if [ -n "$team" ]; then
  echo "Project generated. Signing team: $team"
else
  echo "Project generated. No team set — simulator builds only."
fi
