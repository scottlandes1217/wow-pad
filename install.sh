#!/bin/zsh
# Build wow-pad, put the PadBar addon into every WoW install found, and install a LaunchAgent that runs
# wow-pad whenever World of Warcraft is running.
set -e
dir=${0:A:h}
"$dir/build.sh"
for addons in /Applications/World\ of\ Warcraft/_*_/Interface/AddOns(N); do
  rm -rf "$addons/PadBar"; cp -R "$dir/addon/PadBar" "$addons/PadBar"
done
plist=~/Library/LaunchAgents/com.scottlandes.wow-pad.plist
cat > $plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.scottlandes.wow-pad</string>
  <key>ProgramArguments</key><array><string>/bin/zsh</string><string>$dir/wow-pad-watch.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u)/com.scottlandes.wow-pad 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $plist
echo "Installed. wow-pad starts with WoW; allow it under Accessibility when asked."
echo "First time: log in, then run: $dir/wow-pad --calibrate"
