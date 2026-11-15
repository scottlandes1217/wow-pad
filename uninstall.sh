#!/bin/zsh
# Remove the LaunchAgent and stop wow-pad. The PadBar addon and the repo folder are left alone.
launchctl bootout gui/$(id -u)/com.scottlandes.wow-pad 2>/dev/null
rm -f ~/Library/LaunchAgents/com.scottlandes.wow-pad.plist
pkill -x wow-pad
echo "Uninstalled. Delete Interface/AddOns/PadBar in WoW to remove the addon too."
