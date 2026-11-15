#!/bin/zsh
# Run by the LaunchAgent (see install.sh): keeps wow-pad running exactly while WoW is running.
dir=${0:A:h}
wow() { pgrep -qx 'World of Warcraft' }
while true; do
  if wow; then
    "$dir/wow-pad" >> "$dir/run.log" 2>&1 &
    pp=$!
    while kill -0 $pp 2>/dev/null && wow; do sleep 0.5; done
    kill $pp 2>/dev/null; wait $pp 2>/dev/null
    wow && sleep 30   # (it died while WoW runs, e.g. no permission yet: don't thrash)
  fi
  sleep 0.5
done
